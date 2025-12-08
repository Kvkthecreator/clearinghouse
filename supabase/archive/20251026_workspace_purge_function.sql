-- Migration: Workspace Purge Function
-- Purpose: Safely delete all data for a specific workspace
-- Safety: Transaction-wrapped, workspace-scoped only, no CASCADE

CREATE OR REPLACE FUNCTION purge_workspace_data(target_workspace_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- All operations in this function run in a single transaction
  -- If any DELETE fails, the entire operation rolls back

  -- Delete substrate_references for documents in this workspace
  DELETE FROM substrate_references
  WHERE document_id IN (
    SELECT id FROM documents WHERE workspace_id = target_workspace_id
  );

  -- Delete document_versions for documents in this workspace
  DELETE FROM document_versions
  WHERE document_id IN (
    SELECT id FROM documents WHERE workspace_id = target_workspace_id
  );

  -- Delete document_context_items for documents in this workspace
  DELETE FROM document_context_items
  WHERE document_id IN (
    SELECT id FROM documents WHERE workspace_id = target_workspace_id
  );

  -- Delete documents in this workspace
  DELETE FROM documents WHERE workspace_id = target_workspace_id;

  -- Delete block_links for blocks in this workspace's baskets
  DELETE FROM block_links
  WHERE from_block_id IN (
    SELECT id FROM blocks WHERE basket_id IN (
      SELECT id FROM baskets WHERE workspace_id = target_workspace_id
    )
  );

  -- Delete substrate_relationships for blocks in this workspace's baskets
  DELETE FROM substrate_relationships
  WHERE from_block_id IN (
    SELECT id FROM blocks WHERE basket_id IN (
      SELECT id FROM baskets WHERE workspace_id = target_workspace_id
    )
  );

  -- Delete blocks in this workspace's baskets
  DELETE FROM blocks
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete raw_dumps in this workspace's baskets
  DELETE FROM raw_dumps
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete reflections_artifact in this workspace's baskets
  DELETE FROM reflections_artifact
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete timeline_events in this workspace's baskets
  DELETE FROM timeline_events
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete proposals in this workspace's baskets
  DELETE FROM proposals
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete basket_anchors in this workspace's baskets
  DELETE FROM basket_anchors
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete agent_processing_queue items for this workspace's baskets
  DELETE FROM agent_processing_queue
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete baskets in this workspace
  DELETE FROM baskets WHERE workspace_id = target_workspace_id;

  -- Note: We do NOT delete:
  -- - workspaces table (the workspace itself remains, just empty)
  -- - workspace_memberships (user still has access)
  -- - users table
  -- - integration tokens/connections (preserved for future use)

END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION purge_workspace_data(UUID) TO authenticated;

-- Add helpful comment
COMMENT ON FUNCTION purge_workspace_data IS 'Purges all data (baskets, blocks, documents, etc.) for a specific workspace. Workspace itself and user memberships are preserved. Transaction-wrapped for safety.';
