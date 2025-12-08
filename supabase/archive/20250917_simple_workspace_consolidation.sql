-- Simple workspace consolidation to fix canon violation
-- Keep workspace 99e6bf7d-513c-45ff-9b96-9362bd914d12 (has most data)
-- Move data from 9eae3fd3-62c8-4dd1-850a-9509669c2ae9 to primary

BEGIN;

-- Set the primary workspace
DO $$
DECLARE
  primary_workspace uuid := '99e6bf7d-513c-45ff-9b96-9362bd914d12';
  secondary_workspace uuid := '9eae3fd3-62c8-4dd1-850a-9509669c2ae9'; 
  empty_workspace uuid := 'f31ba16d-cde7-4246-89c4-8b46eefb7150';
  moved_count integer;
BEGIN
  RAISE NOTICE 'Starting workspace consolidation...';
  
  -- Move baskets from secondary to primary
  UPDATE baskets SET workspace_id = primary_workspace WHERE workspace_id = secondary_workspace;
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Moved % baskets', moved_count;
  
  -- Move raw_dumps from secondary to primary  
  UPDATE raw_dumps SET workspace_id = primary_workspace WHERE workspace_id = secondary_workspace;
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Moved % raw_dumps', moved_count;
  
  -- Move agent_processing_queue entries
  UPDATE agent_processing_queue SET workspace_id = primary_workspace WHERE workspace_id = secondary_workspace;
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Moved % queue entries', moved_count;
  
  -- Move timeline_events
  UPDATE timeline_events SET workspace_id = primary_workspace WHERE workspace_id = secondary_workspace;
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Moved % timeline events', moved_count;
  
  -- Move documents if any
  UPDATE documents SET workspace_id = primary_workspace WHERE workspace_id = secondary_workspace;
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Moved % documents', moved_count;
  
  -- Move proposals if any
  UPDATE proposals SET workspace_id = primary_workspace WHERE workspace_id = secondary_workspace;
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Moved % proposals', moved_count;
  
  -- Delete workspace governance settings for non-primary workspaces
  DELETE FROM workspace_governance_settings WHERE workspace_id IN (secondary_workspace, empty_workspace);
  
  -- Delete workspace memberships for non-primary workspaces
  DELETE FROM workspace_memberships WHERE workspace_id IN (secondary_workspace, empty_workspace);
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Deleted % workspace memberships', moved_count;
  
  -- Delete the non-primary workspaces
  DELETE FROM workspaces WHERE id IN (secondary_workspace, empty_workspace);
  GET DIAGNOSTICS moved_count = ROW_COUNT;
  RAISE NOTICE 'Deleted % workspaces', moved_count;
  
  RAISE NOTICE 'Consolidation complete!';
END $$;

-- Verify the fix
SELECT 
  u.id as user_id,
  COUNT(DISTINCT wm.workspace_id) as workspace_count,
  array_agg(w.name) as workspace_names
FROM users u
JOIN workspace_memberships wm ON wm.user_id = u.id
JOIN workspaces w ON w.id = wm.workspace_id
WHERE u.id = 'aa94fbd9-13cc-4dbc-a9fb-2114ad0928f2'
GROUP BY u.id;

COMMIT;