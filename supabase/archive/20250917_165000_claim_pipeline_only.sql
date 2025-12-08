-- Claim only pipeline-executable work types to avoid governance items (e.g., MANUAL_EDIT)
CREATE OR REPLACE FUNCTION public.fn_claim_pipeline_work(
  p_worker_id text,
  p_limit integer DEFAULT 10,
  p_stale_after_minutes integer DEFAULT 5
) RETURNS SETOF public.agent_processing_queue
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  UPDATE agent_processing_queue
  SET 
    processing_state = 'claimed',
    claimed_at = now(),
    claimed_by = p_worker_id
  WHERE id IN (
    SELECT id 
    FROM agent_processing_queue
    WHERE (
      processing_state = 'pending' AND work_type IN ('P0_CAPTURE','P1_SUBSTRATE','P2_GRAPH','P4_COMPOSE')
    ) OR (
      processing_state = 'claimed' 
      AND claimed_at < now() - interval '1 minute' * p_stale_after_minutes
      AND work_type IN ('P0_CAPTURE','P1_SUBSTRATE','P2_GRAPH','P4_COMPOSE')
    )
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;

