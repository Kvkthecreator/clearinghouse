-- Migration: Project Schedules
-- Enables user-configurable recurring work ticket execution
-- Uses pg_cron for system scheduling + user preferences table

-- ============================================================================
-- 1. PROJECT SCHEDULES TABLE
-- Stores user-defined recurring schedule preferences per project/recipe
-- ============================================================================

CREATE TABLE IF NOT EXISTS project_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Relationships
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  recipe_id UUID NOT NULL REFERENCES work_recipes(id) ON DELETE CASCADE,
  basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,

  -- Schedule configuration
  frequency TEXT NOT NULL CHECK (frequency IN ('weekly', 'biweekly', 'monthly', 'custom')),
  cron_expression TEXT, -- For custom: e.g., "0 9 * * 1" (Monday 9am)
  day_of_week INTEGER CHECK (day_of_week >= 0 AND day_of_week <= 6), -- 0=Sunday, 1=Monday, etc.
  time_of_day TIME DEFAULT '09:00:00', -- When to run (in UTC)

  -- Recipe parameters to use when executing
  recipe_parameters JSONB DEFAULT '{}',

  -- State
  enabled BOOLEAN DEFAULT true,
  next_run_at TIMESTAMPTZ,
  last_run_at TIMESTAMPTZ,
  last_run_status TEXT CHECK (last_run_status IN ('success', 'failed', 'skipped')),
  last_run_ticket_id UUID REFERENCES work_tickets(id),
  run_count INTEGER DEFAULT 0,

  -- Audit
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique constraint: one schedule per project/recipe combo
  UNIQUE(project_id, recipe_id)
);

-- Indexes for efficient querying
CREATE INDEX idx_project_schedules_next_run
ON project_schedules(next_run_at)
WHERE enabled = true;

CREATE INDEX idx_project_schedules_project
ON project_schedules(project_id);

CREATE INDEX idx_project_schedules_recipe
ON project_schedules(recipe_id);

-- ============================================================================
-- 2. HELPER FUNCTION: Calculate next run time from frequency
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_next_run_at(
  p_frequency TEXT,
  p_day_of_week INTEGER,
  p_time_of_day TIME,
  p_cron_expression TEXT DEFAULT NULL
) RETURNS TIMESTAMPTZ AS $$
DECLARE
  v_next_run TIMESTAMPTZ;
  v_today DATE := CURRENT_DATE;
  v_now TIMESTAMPTZ := NOW();
  v_target_dow INTEGER;
  v_days_until INTEGER;
BEGIN
  -- Default time if not specified
  IF p_time_of_day IS NULL THEN
    p_time_of_day := '09:00:00'::TIME;
  END IF;

  CASE p_frequency
    WHEN 'weekly' THEN
      -- Find next occurrence of day_of_week at time_of_day
      v_target_dow := COALESCE(p_day_of_week, 1); -- Default to Monday
      v_days_until := (v_target_dow - EXTRACT(DOW FROM v_today)::INTEGER + 7) % 7;

      -- If today is the target day but time has passed, schedule for next week
      IF v_days_until = 0 AND (v_today + p_time_of_day) <= v_now THEN
        v_days_until := 7;
      END IF;

      v_next_run := (v_today + v_days_until) + p_time_of_day;

    WHEN 'biweekly' THEN
      v_target_dow := COALESCE(p_day_of_week, 1);
      v_days_until := (v_target_dow - EXTRACT(DOW FROM v_today)::INTEGER + 7) % 7;

      IF v_days_until = 0 AND (v_today + p_time_of_day) <= v_now THEN
        v_days_until := 14;
      ELSIF v_days_until > 0 THEN
        -- Add extra week for biweekly
        v_days_until := v_days_until + 7;
      END IF;

      v_next_run := (v_today + v_days_until) + p_time_of_day;

    WHEN 'monthly' THEN
      -- First occurrence of day_of_week in next month
      v_target_dow := COALESCE(p_day_of_week, 1);
      v_next_run := date_trunc('month', v_today + INTERVAL '1 month');

      -- Find first target day of week in that month
      v_days_until := (v_target_dow - EXTRACT(DOW FROM v_next_run)::INTEGER + 7) % 7;
      v_next_run := v_next_run + (v_days_until * INTERVAL '1 day') + p_time_of_day;

    WHEN 'custom' THEN
      -- For custom cron, we'd need a cron parser - for now, default to weekly
      v_target_dow := COALESCE(p_day_of_week, 1);
      v_days_until := (v_target_dow - EXTRACT(DOW FROM v_today)::INTEGER + 7) % 7;
      IF v_days_until = 0 AND (v_today + p_time_of_day) <= v_now THEN
        v_days_until := 7;
      END IF;
      v_next_run := (v_today + v_days_until) + p_time_of_day;

    ELSE
      RAISE EXCEPTION 'Unknown frequency: %', p_frequency;
  END CASE;

  RETURN v_next_run;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. TRIGGER: Auto-update next_run_at on schedule changes
-- ============================================================================

CREATE OR REPLACE FUNCTION update_schedule_next_run()
RETURNS TRIGGER AS $$
BEGIN
  -- Only calculate if enabled
  IF NEW.enabled THEN
    NEW.next_run_at := calculate_next_run_at(
      NEW.frequency,
      NEW.day_of_week,
      NEW.time_of_day,
      NEW.cron_expression
    );
  ELSE
    NEW.next_run_at := NULL;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_schedule_next_run
BEFORE INSERT OR UPDATE OF frequency, day_of_week, time_of_day, cron_expression, enabled
ON project_schedules
FOR EACH ROW
EXECUTE FUNCTION update_schedule_next_run();

-- ============================================================================
-- 4. FUNCTION: Queue due scheduled work tickets
-- Called by pg_cron or external scheduler
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_scheduled_work_tickets()
RETURNS TABLE(
  schedule_id UUID,
  project_id UUID,
  recipe_id UUID,
  ticket_id UUID
) AS $$
DECLARE
  v_schedule RECORD;
  v_ticket_id UUID;
  v_recipe RECORD;
BEGIN
  -- Find all due schedules
  FOR v_schedule IN
    SELECT
      ps.id,
      ps.project_id,
      ps.recipe_id,
      ps.basket_id,
      ps.recipe_parameters,
      ps.frequency,
      ps.day_of_week,
      ps.time_of_day
    FROM project_schedules ps
    WHERE ps.enabled = true
    AND ps.next_run_at <= NOW()
    ORDER BY ps.next_run_at ASC
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Get recipe details
    SELECT wr.slug, wr.name, wr.agent_type, wr.context_outputs
    INTO v_recipe
    FROM work_recipes wr
    WHERE wr.id = v_schedule.recipe_id
    AND wr.status = 'active';

    IF NOT FOUND THEN
      -- Recipe no longer active, skip
      UPDATE project_schedules
      SET last_run_status = 'skipped',
          last_run_at = NOW(),
          next_run_at = calculate_next_run_at(
            v_schedule.frequency,
            v_schedule.day_of_week,
            v_schedule.time_of_day,
            NULL
          )
      WHERE id = v_schedule.id;
      CONTINUE;
    END IF;

    -- Create work ticket
    INSERT INTO work_tickets (
      basket_id,
      status,
      priority,
      source,
      metadata
    ) VALUES (
      v_schedule.basket_id,
      'pending',
      5, -- Default priority
      'scheduled',
      jsonb_build_object(
        'schedule_id', v_schedule.id,
        'recipe_slug', v_recipe.slug,
        'recipe_id', v_schedule.recipe_id,
        'recipe_parameters', v_schedule.recipe_parameters,
        'context_outputs', v_recipe.context_outputs,
        'scheduled_at', NOW()
      )
    )
    RETURNING id INTO v_ticket_id;

    -- Update schedule state
    UPDATE project_schedules
    SET last_run_at = NOW(),
        last_run_status = 'success',
        last_run_ticket_id = v_ticket_id,
        run_count = run_count + 1,
        next_run_at = calculate_next_run_at(
          v_schedule.frequency,
          v_schedule.day_of_week,
          v_schedule.time_of_day,
          NULL
        )
    WHERE id = v_schedule.id;

    -- Return result
    schedule_id := v_schedule.id;
    project_id := v_schedule.project_id;
    recipe_id := v_schedule.recipe_id;
    ticket_id := v_ticket_id;
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. FUNCTION: Queue stale anchor refreshes (based on recipe TTL)
-- Uses refresh_policy from work_recipes.context_outputs
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_stale_anchor_refreshes()
RETURNS TABLE(
  block_id UUID,
  basket_id UUID,
  anchor_role TEXT,
  recipe_id UUID,
  ticket_id UUID
) AS $$
DECLARE
  v_stale RECORD;
  v_ticket_id UUID;
BEGIN
  -- Find stale anchor blocks that have a producing recipe
  FOR v_stale IN
    SELECT
      b.id as block_id,
      b.basket_id,
      b.anchor_role,
      wr.id as recipe_id,
      wr.slug as recipe_slug,
      wr.context_outputs
    FROM blocks b
    JOIN work_recipes wr ON wr.context_outputs->>'role' = b.anchor_role
    WHERE b.anchor_role IS NOT NULL
    AND b.state = 'ACCEPTED'
    AND wr.status = 'active'
    AND b.updated_at < NOW() - (
      (wr.context_outputs->'refresh_policy'->>'ttl_hours')::INTEGER * INTERVAL '1 hour'
    )
    -- Don't queue if there's already a pending ticket for this basket/recipe
    AND NOT EXISTS (
      SELECT 1 FROM work_tickets wt
      WHERE wt.basket_id = b.basket_id
      AND wt.source = 'stale_refresh'
      AND wt.metadata->>'recipe_id' = wr.id::TEXT
      AND wt.status IN ('pending', 'running')
    )
    FOR UPDATE OF b SKIP LOCKED
  LOOP
    -- Create work ticket for refresh
    INSERT INTO work_tickets (
      basket_id,
      status,
      priority,
      source,
      metadata
    ) VALUES (
      v_stale.basket_id,
      'pending',
      3, -- Lower priority than user-initiated
      'stale_refresh',
      jsonb_build_object(
        'recipe_slug', v_stale.recipe_slug,
        'recipe_id', v_stale.recipe_id,
        'anchor_role', v_stale.anchor_role,
        'stale_block_id', v_stale.block_id,
        'context_outputs', v_stale.context_outputs,
        'triggered_at', NOW()
      )
    )
    RETURNING id INTO v_ticket_id;

    -- Return result
    block_id := v_stale.block_id;
    basket_id := v_stale.basket_id;
    anchor_role := v_stale.anchor_role;
    recipe_id := v_stale.recipe_id;
    ticket_id := v_ticket_id;
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. RLS POLICIES
-- ============================================================================

ALTER TABLE project_schedules ENABLE ROW LEVEL SECURITY;

-- Users can view schedules for projects they have access to
CREATE POLICY "Users can view project schedules"
ON project_schedules FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- Users can create schedules for projects they have access to
CREATE POLICY "Users can create project schedules"
ON project_schedules FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- Users can update their own schedules or schedules they have access to
CREATE POLICY "Users can update project schedules"
ON project_schedules FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- Users can delete schedules for projects they have access to
CREATE POLICY "Users can delete project schedules"
ON project_schedules FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- ============================================================================
-- 7. GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON project_schedules TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_next_run_at TO authenticated;
GRANT EXECUTE ON FUNCTION queue_scheduled_work_tickets TO service_role;
GRANT EXECUTE ON FUNCTION queue_stale_anchor_refreshes TO service_role;

-- ============================================================================
-- 8. COMMENTS
-- ============================================================================

COMMENT ON TABLE project_schedules IS
'User-configurable recurring schedules for work recipe execution';

COMMENT ON FUNCTION queue_scheduled_work_tickets IS
'Finds due schedules and creates work_tickets. Call from pg_cron or external scheduler.';

COMMENT ON FUNCTION queue_stale_anchor_refreshes IS
'Finds stale anchor blocks based on recipe TTL and queues refresh tickets. Call daily.';

-- ============================================================================
-- NOTE: pg_cron setup (requires Supabase Pro plan)
-- Run these manually in Supabase Dashboard SQL Editor after enabling pg_cron:
--
-- -- Enable extension
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
--
-- -- Schedule: Check for due user schedules every 15 minutes
-- SELECT cron.schedule(
--   'process-scheduled-work',
--   '*/15 * * * *',
--   'SELECT * FROM queue_scheduled_work_tickets()'
-- );
--
-- -- Schedule: Check for stale anchors daily at 6 AM UTC
-- SELECT cron.schedule(
--   'check-stale-anchors',
--   '0 6 * * *',
--   'SELECT * FROM queue_stale_anchor_refreshes()'
-- );
-- ============================================================================
