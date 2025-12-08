-- Fix RLS permissions for block_usage table and anchored_substrate view
--
-- Issue: block_usage and anchored_substrate created without RLS policies
-- causing "permission denied" errors in building-blocks and anchors APIs

BEGIN;

-- =====================================================
-- 1. Enable RLS on block_usage table
-- =====================================================

ALTER TABLE block_usage ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view block_usage for blocks in their workspace
CREATE POLICY "Users can view block_usage in their workspace"
  ON block_usage
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM blocks b
      JOIN baskets bsk ON bsk.id = b.basket_id
      JOIN workspace_memberships wm ON wm.workspace_id = bsk.workspace_id
      WHERE b.id = block_usage.block_id
        AND wm.user_id = auth.uid()
    )
  );

-- Policy: Service role has full access
CREATE POLICY "Service role has full access to block_usage"
  ON block_usage
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- =====================================================
-- 2. Grant permissions on anchored_substrate view
-- =====================================================

-- Note: Views in Postgres inherit RLS from underlying tables
-- but we need to grant SELECT permission to authenticated users

GRANT SELECT ON anchored_substrate TO authenticated;
GRANT SELECT ON anchored_substrate TO service_role;

-- =====================================================
-- 3. Ensure extraction_quality_metrics has RLS
-- =====================================================

ALTER TABLE extraction_quality_metrics ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view metrics for their workspace
CREATE POLICY "Users can view extraction metrics in their workspace"
  ON extraction_quality_metrics
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM workspace_memberships wm
      WHERE wm.workspace_id = extraction_quality_metrics.workspace_id
        AND wm.user_id = auth.uid()
    )
  );

-- Policy: Service role has full access
CREATE POLICY "Service role has full access to extraction_quality_metrics"
  ON extraction_quality_metrics
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMIT;

-- =====================================================
-- Summary
-- =====================================================
-- Added RLS policies to:
-- 1. block_usage - view if workspace member
-- 2. anchored_substrate - SELECT granted to authenticated
-- 3. extraction_quality_metrics - view if workspace member
