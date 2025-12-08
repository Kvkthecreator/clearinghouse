-- Fix orphaned workspace memberships
-- Date: 2025-09-06
-- 
-- Issue: Some workspaces were created without corresponding workspace_memberships entries
-- This caused RLS policies to deny access, resulting in 404 errors for existing baskets
-- 
-- Root cause: ensureWorkspaceServer.ts uses regular client instead of service role
-- for bootstrap operations, causing silent membership creation failures

-- Fix orphaned workspaces by creating missing memberships
INSERT INTO workspace_memberships (workspace_id, user_id, role) 
SELECT w.id, w.owner_id, 'owner'
FROM workspaces w 
LEFT JOIN workspace_memberships wm ON w.id = wm.workspace_id 
WHERE wm.workspace_id IS NULL 
  AND w.owner_id IS NOT NULL
ON CONFLICT (workspace_id, user_id) DO NOTHING;

-- Add comment for documentation
COMMENT ON TABLE workspace_memberships IS 'User memberships in workspaces. Required for RLS access control. All workspaces must have at least one owner membership.';