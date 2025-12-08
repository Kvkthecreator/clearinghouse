-- Migration: Unified Work Orchestration
-- Date: 2025-12-05
-- Description: Extends work_requests for unified work entry point
--
-- This enables:
-- 1. All work (manual, TP, scheduled, API) flows through work_requests
-- 2. Recipe reference on work_requests for audit trail
-- 3. Scheduling intent stored on requests (not just project_schedules)
-- 4. Consistent metadata structure

-- ============================================================================
-- 1. Extend work_requests table
-- ============================================================================

-- Add recipe reference (denormalized slug for quick access)
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS recipe_id UUID REFERENCES work_recipes(id) ON DELETE SET NULL;

ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS recipe_slug TEXT;

-- Add source tracking (who/what created this request)
-- Note: work_tickets already has source column from continuous_work_model migration
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manual';

-- Add constraint for source values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'work_requests_source_check'
  ) THEN
    ALTER TABLE work_requests
    ADD CONSTRAINT work_requests_source_check
    CHECK (source IN ('manual', 'thinking_partner', 'schedule', 'api'));
  END IF;
END $$;

-- Add scheduling intent (for requests that want recurring execution)
-- This captures the "intent" at request time; project_schedules stores the "config"
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS scheduling_intent JSONB DEFAULT NULL;
-- Example: { "mode": "recurring", "frequency": "weekly", "day_of_week": 1, "time_of_day": "09:00:00" }

-- Add TP session reference for thinking_partner requests
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS tp_session_id UUID;

-- ============================================================================
-- 2. Extend work_recipes table for scheduling metadata
-- ============================================================================

-- Whether this recipe can be scheduled (some recipes may be one-shot only)
ALTER TABLE work_recipes
ADD COLUMN IF NOT EXISTS schedulable BOOLEAN DEFAULT true;

-- Suggested default frequency when scheduling this recipe
ALTER TABLE work_recipes
ADD COLUMN IF NOT EXISTS default_frequency TEXT;

-- Minimum interval between runs (prevents spamming)
ALTER TABLE work_recipes
ADD COLUMN IF NOT EXISTS min_interval_hours INTEGER DEFAULT 24;

-- ============================================================================
-- 3. Make work_tickets.work_request_id nullable for migration period
-- ============================================================================

-- During migration, some tickets may be created before work_request normalization
-- We'll backfill these later, but allow null temporarily
-- Note: The original schema has work_request_id as NOT NULL
-- We need to be careful here - let's just add a comment for now

COMMENT ON COLUMN work_tickets.work_request_id IS
'FK to work_requests. Required for new tickets. Legacy tickets may have this via metadata.';

-- ============================================================================
-- 4. Indexes for efficient querying
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_work_requests_recipe
ON work_requests(recipe_id)
WHERE recipe_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_requests_source
ON work_requests(source);

CREATE INDEX IF NOT EXISTS idx_work_requests_scheduling
ON work_requests((scheduling_intent->>'mode'))
WHERE scheduling_intent IS NOT NULL;

-- Queue processor index: find pending tickets efficiently
CREATE INDEX IF NOT EXISTS idx_work_tickets_queue
ON work_tickets(priority DESC, created_at ASC)
WHERE status = 'pending';

-- ============================================================================
-- 5. Function to create unified work entry
-- ============================================================================

CREATE OR REPLACE FUNCTION create_work_entry(
  p_basket_id UUID,
  p_workspace_id UUID,
  p_user_id UUID,
  p_recipe_id UUID,
  p_recipe_slug TEXT,
  p_source TEXT,
  p_parameters JSONB DEFAULT '{}'::jsonb,
  p_scheduling_intent JSONB DEFAULT NULL,
  p_priority INTEGER DEFAULT 5,
  p_tp_session_id UUID DEFAULT NULL,
  p_schedule_id UUID DEFAULT NULL
) RETURNS TABLE(
  work_request_id UUID,
  work_ticket_id UUID
) AS $$
DECLARE
  v_request_id UUID;
  v_ticket_id UUID;
  v_agent_type TEXT;
  v_mode TEXT;
BEGIN
  -- Get agent_type from recipe
  SELECT wr.agent_type INTO v_agent_type
  FROM work_recipes wr
  WHERE wr.id = p_recipe_id;

  IF v_agent_type IS NULL THEN
    RAISE EXCEPTION 'Recipe not found: %', p_recipe_id;
  END IF;

  -- Determine mode
  v_mode := CASE
    WHEN p_schedule_id IS NOT NULL THEN 'continuous'
    WHEN p_scheduling_intent IS NOT NULL AND p_scheduling_intent->>'mode' = 'recurring' THEN 'continuous'
    ELSE 'one_shot'
  END;

  -- Create work_request
  INSERT INTO work_requests (
    workspace_id,
    basket_id,
    requested_by_user_id,
    request_type,
    task_intent,
    parameters,
    recipe_id,
    recipe_slug,
    source,
    scheduling_intent,
    tp_session_id,
    priority
  ) VALUES (
    p_workspace_id,
    p_basket_id,
    p_user_id,
    p_recipe_slug,  -- Use recipe_slug as request_type
    COALESCE(p_parameters->>'task_description', 'Work request via ' || p_source),
    p_parameters,
    p_recipe_id,
    p_recipe_slug,
    p_source,
    p_scheduling_intent,
    p_tp_session_id,
    COALESCE(p_parameters->>'priority', 'normal')
  )
  RETURNING id INTO v_request_id;

  -- Create work_ticket
  INSERT INTO work_tickets (
    work_request_id,
    workspace_id,
    basket_id,
    agent_type,
    status,
    priority,
    source,
    mode,
    schedule_id,
    metadata
  ) VALUES (
    v_request_id,
    p_workspace_id,
    p_basket_id,
    v_agent_type,
    'pending',
    p_priority,
    p_source,
    v_mode,
    p_schedule_id,
    jsonb_build_object(
      'recipe_slug', p_recipe_slug,
      'recipe_id', p_recipe_id,
      'parameters', p_parameters,
      'tp_session_id', p_tp_session_id,
      'created_at', NOW()
    )
  )
  RETURNING id INTO v_ticket_id;

  -- Return both IDs
  work_request_id := v_request_id;
  work_ticket_id := v_ticket_id;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. Function to process work queue (called by queue processor)
-- ============================================================================

CREATE OR REPLACE FUNCTION claim_pending_ticket(
  p_limit INTEGER DEFAULT 1
) RETURNS TABLE(
  ticket_id UUID,
  work_request_id UUID,
  basket_id UUID,
  workspace_id UUID,
  agent_type TEXT,
  recipe_slug TEXT,
  metadata JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    SELECT wt.id
    FROM work_tickets wt
    WHERE wt.status = 'pending'
    ORDER BY wt.priority DESC, wt.created_at ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE work_tickets wt
  SET
    status = 'running',
    started_at = NOW()
  FROM claimed
  WHERE wt.id = claimed.id
  RETURNING
    wt.id,
    wt.work_request_id,
    wt.basket_id,
    wt.workspace_id,
    wt.agent_type,
    wt.metadata->>'recipe_slug',
    wt.metadata;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. Grants
-- ============================================================================

GRANT EXECUTE ON FUNCTION create_work_entry TO authenticated;
GRANT EXECUTE ON FUNCTION create_work_entry TO service_role;
GRANT EXECUTE ON FUNCTION claim_pending_ticket TO service_role;

-- ============================================================================
-- 8. Comments
-- ============================================================================

COMMENT ON COLUMN work_requests.recipe_id IS 'FK to work_recipes - which recipe template was used';
COMMENT ON COLUMN work_requests.recipe_slug IS 'Denormalized recipe slug for quick access';
COMMENT ON COLUMN work_requests.source IS 'Origin: manual, thinking_partner, schedule, api';
COMMENT ON COLUMN work_requests.scheduling_intent IS 'If user wants recurring execution, this captures their intent';
COMMENT ON COLUMN work_requests.tp_session_id IS 'For TP-originated requests, link to tp_sessions';

COMMENT ON COLUMN work_recipes.schedulable IS 'Whether this recipe can be scheduled for recurring execution';
COMMENT ON COLUMN work_recipes.default_frequency IS 'Suggested frequency when scheduling (weekly, biweekly, monthly)';
COMMENT ON COLUMN work_recipes.min_interval_hours IS 'Minimum hours between runs to prevent spam';

COMMENT ON FUNCTION create_work_entry IS 'Unified function to create work_request + work_ticket atomically';
COMMENT ON FUNCTION claim_pending_ticket IS 'Queue processor: claim pending tickets with row locking';
