-- Migration: Jobs Queue
-- Infrastructure-agnostic job queue for scheduling, email, LLM batch, etc.
-- See docs/features/scheduling.md for architecture details.

-- ============================================================================
-- 1. JOBS TABLE
-- Central queue for all async work. Domain logic in handlers, not here.
-- ============================================================================

CREATE TABLE IF NOT EXISTS jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Job definition (DOMAIN)
  job_type TEXT NOT NULL,  -- 'scheduled_work', 'stale_refresh', 'email_notification', 'llm_batch'
  payload JSONB NOT NULL DEFAULT '{}',  -- Job-specific data

  -- Scheduling (DOMAIN)
  scheduled_for TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  priority INTEGER DEFAULT 5 CHECK (priority >= 1 AND priority <= 10),

  -- Execution state (INFRASTRUCTURE)
  status TEXT DEFAULT 'pending' CHECK (status IN (
    'pending',    -- Waiting to be claimed
    'claimed',    -- Worker has claimed, not yet started
    'running',    -- Currently executing
    'completed',  -- Successfully finished
    'failed',     -- Failed after max retries
    'cancelled'   -- Manually cancelled
  )),
  claimed_by TEXT,  -- Worker ID that claimed this job
  claimed_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,

  -- Retry logic (INFRASTRUCTURE)
  attempts INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 3,
  last_error TEXT,
  retry_after TIMESTAMPTZ,  -- For exponential backoff

  -- Result storage
  result JSONB,

  -- Recurrence (links back to schedule)
  parent_schedule_id UUID REFERENCES project_schedules(id) ON DELETE SET NULL,

  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. INDEXES
-- Optimized for the job claiming pattern
-- ============================================================================

-- Primary query: find pending jobs ready to run
-- Note: We can't use NOW() in partial index (not immutable), so we just filter on status
CREATE INDEX idx_jobs_pending_ready ON jobs(scheduled_for, priority DESC)
WHERE status = 'pending';

-- Find jobs by type (for monitoring)
CREATE INDEX idx_jobs_type_status ON jobs(job_type, status);

-- Find jobs by schedule (for schedule management)
CREATE INDEX idx_jobs_parent_schedule ON jobs(parent_schedule_id)
WHERE parent_schedule_id IS NOT NULL;

-- Cleanup old completed jobs
CREATE INDEX idx_jobs_completed_at ON jobs(completed_at)
WHERE status IN ('completed', 'failed', 'cancelled');

-- ============================================================================
-- 3. CLAIM JOBS FUNCTION
-- Atomic job claiming to prevent double-processing
-- This is the INFRASTRUCTURE layer - can be replaced with Redis, SQS, etc.
-- ============================================================================

CREATE OR REPLACE FUNCTION claim_jobs(
  p_worker_id TEXT,
  p_job_types TEXT[],
  p_limit INTEGER DEFAULT 5
) RETURNS TABLE (
  id UUID,
  job_type TEXT,
  payload JSONB,
  priority INTEGER,
  attempts INTEGER,
  max_attempts INTEGER,
  parent_schedule_id UUID
) AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    UPDATE jobs j
    SET
      status = 'claimed',
      claimed_by = p_worker_id,
      claimed_at = NOW(),
      updated_at = NOW()
    WHERE j.id IN (
      SELECT j2.id
      FROM jobs j2
      WHERE j2.status = 'pending'
      AND j2.job_type = ANY(p_job_types)
      AND j2.scheduled_for <= NOW()
      AND (j2.retry_after IS NULL OR j2.retry_after <= NOW())
      ORDER BY j2.priority DESC, j2.scheduled_for ASC
      LIMIT p_limit
      FOR UPDATE SKIP LOCKED
    )
    RETURNING j.*
  )
  SELECT
    claimed.id,
    claimed.job_type,
    claimed.payload,
    claimed.priority,
    claimed.attempts,
    claimed.max_attempts,
    claimed.parent_schedule_id
  FROM claimed;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. COMPLETE JOB FUNCTION
-- Mark job as completed with result
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_job(
  p_job_id UUID,
  p_result JSONB DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
  v_updated BOOLEAN;
BEGIN
  UPDATE jobs
  SET
    status = 'completed',
    completed_at = NOW(),
    result = p_result,
    updated_at = NOW()
  WHERE id = p_job_id
  AND status IN ('claimed', 'running');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. FAIL JOB FUNCTION
-- Mark job as failed, potentially schedule retry
-- ============================================================================

CREATE OR REPLACE FUNCTION fail_job(
  p_job_id UUID,
  p_error TEXT
) RETURNS BOOLEAN AS $$
DECLARE
  v_job RECORD;
  v_retry_delay INTERVAL;
BEGIN
  -- Get current job state
  SELECT * INTO v_job FROM jobs WHERE id = p_job_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Check if we should retry
  IF v_job.attempts < v_job.max_attempts THEN
    -- Exponential backoff: 1min, 5min, 25min, etc.
    v_retry_delay := (POWER(5, v_job.attempts) * INTERVAL '1 minute');

    UPDATE jobs
    SET
      status = 'pending',
      attempts = attempts + 1,
      last_error = p_error,
      retry_after = NOW() + v_retry_delay,
      claimed_by = NULL,
      claimed_at = NULL,
      updated_at = NOW()
    WHERE id = p_job_id;
  ELSE
    -- Max retries exceeded, mark as failed
    UPDATE jobs
    SET
      status = 'failed',
      completed_at = NOW(),
      last_error = p_error,
      updated_at = NOW()
    WHERE id = p_job_id;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. CHECK AND QUEUE DUE SCHEDULES
-- Called periodically by worker to find schedules that need to run
-- This is DOMAIN logic - what schedules are due
-- ============================================================================

CREATE OR REPLACE FUNCTION check_and_queue_due_schedules()
RETURNS TABLE (
  schedule_id UUID,
  job_id UUID
) AS $$
DECLARE
  v_schedule RECORD;
  v_job_id UUID;
BEGIN
  -- Find all enabled schedules that are due
  FOR v_schedule IN
    SELECT
      ps.id,
      ps.project_id,
      ps.recipe_id,
      ps.basket_id,
      ps.recipe_parameters,
      ps.frequency,
      ps.day_of_week,
      ps.time_of_day,
      wr.slug as recipe_slug,
      wr.context_outputs
    FROM project_schedules ps
    JOIN work_recipes wr ON wr.id = ps.recipe_id
    WHERE ps.enabled = true
    AND ps.next_run_at <= NOW()
    AND wr.status = 'active'
    -- Don't create duplicate jobs for same schedule
    AND NOT EXISTS (
      SELECT 1 FROM jobs j
      WHERE j.parent_schedule_id = ps.id
      AND j.status IN ('pending', 'claimed', 'running')
    )
    FOR UPDATE OF ps SKIP LOCKED
  LOOP
    -- Create job for this schedule
    INSERT INTO jobs (
      job_type,
      payload,
      priority,
      parent_schedule_id
    ) VALUES (
      'scheduled_work',
      jsonb_build_object(
        'schedule_id', v_schedule.id,
        'project_id', v_schedule.project_id,
        'recipe_id', v_schedule.recipe_id,
        'recipe_slug', v_schedule.recipe_slug,
        'basket_id', v_schedule.basket_id,
        'recipe_parameters', v_schedule.recipe_parameters,
        'context_outputs', v_schedule.context_outputs,
        'triggered_at', NOW()
      ),
      5,  -- Default priority
      v_schedule.id
    )
    RETURNING id INTO v_job_id;

    -- Update schedule's next run time
    UPDATE project_schedules
    SET
      next_run_at = calculate_next_run_at(
        v_schedule.frequency,
        v_schedule.day_of_week,
        v_schedule.time_of_day,
        NULL
      ),
      updated_at = NOW()
    WHERE id = v_schedule.id;

    schedule_id := v_schedule.id;
    job_id := v_job_id;
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. CHECK AND QUEUE STALE ANCHORS
-- Find stale context blocks and create refresh jobs
-- This is DOMAIN logic - what anchors are stale
-- ============================================================================

CREATE OR REPLACE FUNCTION check_and_queue_stale_anchors()
RETURNS TABLE (
  block_id UUID,
  job_id UUID
) AS $$
DECLARE
  v_stale RECORD;
  v_job_id UUID;
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
    -- Don't queue if there's already a pending job
    AND NOT EXISTS (
      SELECT 1 FROM jobs j
      WHERE j.job_type = 'stale_refresh'
      AND j.payload->>'basket_id' = b.basket_id::TEXT
      AND j.payload->>'anchor_role' = b.anchor_role
      AND j.status IN ('pending', 'claimed', 'running')
    )
    FOR UPDATE OF b SKIP LOCKED
  LOOP
    -- Create refresh job
    INSERT INTO jobs (
      job_type,
      payload,
      priority
    ) VALUES (
      'stale_refresh',
      jsonb_build_object(
        'block_id', v_stale.block_id,
        'basket_id', v_stale.basket_id,
        'anchor_role', v_stale.anchor_role,
        'recipe_id', v_stale.recipe_id,
        'recipe_slug', v_stale.recipe_slug,
        'context_outputs', v_stale.context_outputs,
        'triggered_at', NOW()
      ),
      3  -- Lower priority than user-initiated
    )
    RETURNING id INTO v_job_id;

    block_id := v_stale.block_id;
    job_id := v_job_id;
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 8. CLEANUP OLD JOBS
-- Remove completed/failed jobs older than retention period
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_old_jobs(
  p_retention_days INTEGER DEFAULT 30
) RETURNS INTEGER AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM jobs
  WHERE status IN ('completed', 'failed', 'cancelled')
  AND completed_at < NOW() - (p_retention_days * INTERVAL '1 day');

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 9. TRIGGER: Update timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_jobs_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_jobs_updated_at
BEFORE UPDATE ON jobs
FOR EACH ROW
EXECUTE FUNCTION update_jobs_updated_at();

-- ============================================================================
-- 10. RLS POLICIES
-- Jobs are internal system state, not user-accessible
-- Only service_role can manage jobs
-- ============================================================================

ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;

-- Service role has full access
CREATE POLICY "Service role can manage jobs"
ON jobs
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Authenticated users can view their project's jobs (read-only)
CREATE POLICY "Users can view their project jobs"
ON jobs FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM project_schedules ps
    JOIN projects p ON p.id = ps.project_id
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE ps.id = jobs.parent_schedule_id
    AND wm.user_id = auth.uid()
  )
);

-- ============================================================================
-- 11. GRANTS
-- ============================================================================

GRANT SELECT ON jobs TO authenticated;
GRANT ALL ON jobs TO service_role;
GRANT EXECUTE ON FUNCTION claim_jobs TO service_role;
GRANT EXECUTE ON FUNCTION complete_job TO service_role;
GRANT EXECUTE ON FUNCTION fail_job TO service_role;
GRANT EXECUTE ON FUNCTION check_and_queue_due_schedules TO service_role;
GRANT EXECUTE ON FUNCTION check_and_queue_stale_anchors TO service_role;
GRANT EXECUTE ON FUNCTION cleanup_old_jobs TO service_role;

-- ============================================================================
-- 12. COMMENTS
-- ============================================================================

COMMENT ON TABLE jobs IS
'Infrastructure-agnostic job queue. See docs/features/scheduling.md';

COMMENT ON FUNCTION claim_jobs IS
'Atomic job claiming for workers. Infrastructure layer - swappable.';

COMMENT ON FUNCTION check_and_queue_due_schedules IS
'Domain logic: Find due schedules and create jobs. Called by worker.';

COMMENT ON FUNCTION check_and_queue_stale_anchors IS
'Domain logic: Find stale anchors and create refresh jobs. Called by worker.';
