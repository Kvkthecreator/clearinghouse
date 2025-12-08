-- Migration: Add helper functions for work_outputs supervision
-- Date: 2025-11-17
-- Purpose: Database functions for supervision statistics (used by substrate-API)

-- ============================================================================
-- SUPERVISION STATISTICS FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION get_supervision_stats(p_basket_id uuid)
RETURNS TABLE (
    total_outputs bigint,
    pending_review bigint,
    approved bigint,
    rejected bigint,
    revision_requested bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::bigint AS total_outputs,
        COUNT(*) FILTER (WHERE supervision_status = 'pending_review')::bigint AS pending_review,
        COUNT(*) FILTER (WHERE supervision_status = 'approved')::bigint AS approved,
        COUNT(*) FILTER (WHERE supervision_status = 'rejected')::bigint AS rejected,
        COUNT(*) FILTER (WHERE supervision_status = 'revision_requested')::bigint AS revision_requested
    FROM work_outputs
    WHERE basket_id = p_basket_id;
END;
$$;

COMMENT ON FUNCTION get_supervision_stats IS 'Get counts of outputs by supervision status for dashboard';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
    func_count INTEGER;
BEGIN
    -- Count helper functions
    SELECT COUNT(*) INTO func_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.proname = 'get_supervision_stats';

    RAISE NOTICE '✅ Work Outputs Helper Functions Created:';
    RAISE NOTICE '  - get_supervision_stats: %', CASE WHEN func_count > 0 THEN 'OK' ELSE 'MISSING' END;
END $$;
