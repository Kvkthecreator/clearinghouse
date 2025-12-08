-- Queue management RPCs for agent processing
-- These functions enable agents to claim and manage processing work

-- Function for agents to atomically claim pending dumps
CREATE OR REPLACE FUNCTION fn_claim_next_dumps(
  p_worker_id text,
  p_limit int DEFAULT 10,
  p_stale_after_minutes int DEFAULT 5
) RETURNS SETOF agent_processing_queue AS $$
BEGIN
  -- Atomically claim pending or stale dumps
  RETURN QUERY
  UPDATE agent_processing_queue
  SET 
    processing_state = 'claimed',
    claimed_at = now(),
    claimed_by = p_worker_id
  WHERE id IN (
    SELECT id 
    FROM agent_processing_queue
    WHERE processing_state = 'pending'
       -- Include stale claimed jobs that haven't been updated
       OR (processing_state = 'claimed' 
           AND claimed_at < now() - interval '1 minute' * p_stale_after_minutes)
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED  -- Prevents race conditions between agents
  )
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update processing state
CREATE OR REPLACE FUNCTION fn_update_queue_state(
  p_id uuid,
  p_state processing_state,
  p_error text DEFAULT NULL
) RETURNS void AS $$
BEGIN
  UPDATE agent_processing_queue 
  SET 
    processing_state = p_state,
    completed_at = CASE WHEN p_state = 'completed' THEN now() ELSE completed_at END,
    error_message = p_error,
    attempts = CASE WHEN p_state = 'failed' THEN attempts + 1 ELSE attempts END
  WHERE id = p_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get queue health metrics
CREATE OR REPLACE FUNCTION fn_queue_health()
RETURNS TABLE (
  processing_state processing_state,
  count bigint,
  avg_age_seconds numeric,
  max_age_seconds numeric
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    q.processing_state,
    COUNT(*) as count,
    AVG(EXTRACT(epoch FROM (now() - q.created_at)))::numeric as avg_age_seconds,
    MAX(EXTRACT(epoch FROM (now() - q.created_at)))::numeric as max_age_seconds
  FROM agent_processing_queue q
  GROUP BY q.processing_state
  ORDER BY q.processing_state;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reset failed jobs for retry
CREATE OR REPLACE FUNCTION fn_reset_failed_jobs(
  p_max_attempts int DEFAULT 3
) RETURNS int AS $$
DECLARE
  reset_count int;
BEGIN
  UPDATE agent_processing_queue
  SET 
    processing_state = 'pending',
    claimed_at = NULL,
    claimed_by = NULL,
    error_message = NULL
  WHERE processing_state = 'failed' 
    AND attempts < p_max_attempts;
    
  GET DIAGNOSTICS reset_count = ROW_COUNT;
  RETURN reset_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
-- Service role (agents) can claim and update
GRANT EXECUTE ON FUNCTION fn_claim_next_dumps(text, int, int) TO service_role;
GRANT EXECUTE ON FUNCTION fn_update_queue_state(uuid, processing_state, text) TO service_role;

-- Authenticated users can view health metrics
GRANT EXECUTE ON FUNCTION fn_queue_health() TO authenticated;

-- Service role can reset failed jobs
GRANT EXECUTE ON FUNCTION fn_reset_failed_jobs(int) TO service_role;

-- Add comments for documentation
COMMENT ON FUNCTION fn_claim_next_dumps(text, int, int) IS 'Atomically claim pending dumps for agent processing';
COMMENT ON FUNCTION fn_update_queue_state(uuid, processing_state, text) IS 'Update processing state of queued dumps';
COMMENT ON FUNCTION fn_queue_health() IS 'Get queue health metrics for monitoring';
COMMENT ON FUNCTION fn_reset_failed_jobs(int) IS 'Reset failed jobs for retry (admin function)';