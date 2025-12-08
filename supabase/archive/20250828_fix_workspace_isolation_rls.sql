-- Fix Workspace Isolation RLS Policies
-- Addresses canon compliance gaps: ensure complete workspace isolation

-- =============================================================================
-- 1. BLOCKS TABLE - Add workspace isolation RLS
-- =============================================================================

-- Enable RLS on blocks table
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;

-- Policy: Members can read blocks in their workspace
CREATE POLICY "blocks_select_workspace_member" ON blocks 
FOR SELECT TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can insert blocks in their workspace  
CREATE POLICY "blocks_insert_workspace_member" ON blocks
FOR INSERT TO authenticated 
WITH CHECK (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can update blocks in their workspace
CREATE POLICY "blocks_update_workspace_member" ON blocks
FOR UPDATE TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can delete blocks in their workspace
CREATE POLICY "blocks_delete_workspace_member" ON blocks
FOR DELETE TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Service role full access for backend operations
CREATE POLICY "blocks_service_role_all" ON blocks
TO service_role USING (true) WITH CHECK (true);

-- =============================================================================
-- 2. CONTEXT_ITEMS TABLE - Add workspace isolation RLS
-- =============================================================================

-- Enable RLS on context_items table
ALTER TABLE context_items ENABLE ROW LEVEL SECURITY;

-- Policy: Members can read context_items via basket workspace
CREATE POLICY "context_items_select_workspace_member" ON context_items
FOR SELECT TO authenticated 
USING (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = context_items.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Members can insert context_items in their workspace
CREATE POLICY "context_items_insert_workspace_member" ON context_items
FOR INSERT TO authenticated 
WITH CHECK (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = context_items.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Members can update context_items in their workspace
CREATE POLICY "context_items_update_workspace_member" ON context_items
FOR UPDATE TO authenticated 
USING (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = context_items.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Members can delete context_items in their workspace
CREATE POLICY "context_items_delete_workspace_member" ON context_items
FOR DELETE TO authenticated 
USING (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = context_items.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Service role full access for backend operations
CREATE POLICY "context_items_service_role_all" ON context_items
TO service_role USING (true) WITH CHECK (true);

-- =============================================================================
-- 3. DOCUMENTS TABLE - Add workspace isolation RLS  
-- =============================================================================

-- Enable RLS on documents table
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- Policy: Members can read documents in their workspace
CREATE POLICY "documents_select_workspace_member" ON documents
FOR SELECT TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can insert documents in their workspace
CREATE POLICY "documents_insert_workspace_member" ON documents
FOR INSERT TO authenticated 
WITH CHECK (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can update documents in their workspace
CREATE POLICY "documents_update_workspace_member" ON documents
FOR UPDATE TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can delete documents in their workspace
CREATE POLICY "documents_delete_workspace_member" ON documents
FOR DELETE TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Service role full access for backend operations
CREATE POLICY "documents_service_role_all" ON documents
TO service_role USING (true) WITH CHECK (true);

-- =============================================================================
-- 4. RAW_DUMPS TABLE - Add proper workspace isolation RLS
-- =============================================================================

-- Enable RLS on raw_dumps table (if not already enabled)
ALTER TABLE raw_dumps ENABLE ROW LEVEL SECURITY;

-- Policy: Members can read raw_dumps in their workspace
CREATE POLICY "raw_dumps_select_workspace_member" ON raw_dumps
FOR SELECT TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can insert raw_dumps in their workspace
CREATE POLICY "raw_dumps_insert_workspace_member" ON raw_dumps
FOR INSERT TO authenticated 
WITH CHECK (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Note: raw_dumps are immutable per canon, so no UPDATE policy needed

-- Policy: Members can delete raw_dumps in their workspace (if allowed by business logic)
CREATE POLICY "raw_dumps_delete_workspace_member" ON raw_dumps
FOR DELETE TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Keep existing service role policies (they already exist)

-- =============================================================================
-- 5. NARRATIVE TABLE - Add workspace isolation RLS
-- =============================================================================

-- Enable RLS on narrative table
ALTER TABLE narrative ENABLE ROW LEVEL SECURITY;

-- Policy: Members can read narrative via basket workspace
CREATE POLICY "narrative_select_workspace_member" ON narrative
FOR SELECT TO authenticated 
USING (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = narrative.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Members can insert narrative in their workspace
CREATE POLICY "narrative_insert_workspace_member" ON narrative
FOR INSERT TO authenticated 
WITH CHECK (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = narrative.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Members can update narrative in their workspace
CREATE POLICY "narrative_update_workspace_member" ON narrative
FOR UPDATE TO authenticated 
USING (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = narrative.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Members can delete narrative in their workspace
CREATE POLICY "narrative_delete_workspace_member" ON narrative
FOR DELETE TO authenticated 
USING (EXISTS (
  SELECT 1 FROM baskets b 
  JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
  WHERE b.id = narrative.basket_id AND wm.user_id = auth.uid()
));

-- Policy: Service role full access for backend operations
CREATE POLICY "narrative_service_role_all" ON narrative
TO service_role USING (true) WITH CHECK (true);

-- =============================================================================
-- 6. EVENTS TABLE - Fix workspace scoping (currently user-scoped)
-- =============================================================================

-- Drop existing user-scoped policies
DROP POLICY IF EXISTS "select_own_events" ON events;
DROP POLICY IF EXISTS "Workspace members can view events" ON events;

-- Policy: Members can read events in their workspace
CREATE POLICY "events_select_workspace_member" ON events
FOR SELECT TO authenticated 
USING (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Members can insert events in their workspace
CREATE POLICY "events_insert_workspace_member" ON events
FOR INSERT TO authenticated 
WITH CHECK (workspace_id IN (
  SELECT workspace_memberships.workspace_id 
  FROM workspace_memberships 
  WHERE workspace_memberships.user_id = auth.uid()
));

-- Policy: Service role full access for backend operations
CREATE POLICY "events_service_role_all" ON events
TO service_role USING (true) WITH CHECK (true);

-- =============================================================================
-- VERIFICATION QUERIES (for testing)
-- =============================================================================

-- Verify all workspace-scoped tables now have RLS enabled
-- Run these in SQL editor after migration:

/*
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN ('baskets', 'blocks', 'context_items', 'documents', 'raw_dumps', 'events', 'narrative', 'timeline_events')
ORDER BY tablename;

-- Should show rowsecurity = true for all tables

SELECT schemaname, tablename, policyname, roles, cmd, qual
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename IN ('blocks', 'context_items', 'documents', 'raw_dumps', 'narrative', 'events')
ORDER BY tablename, policyname;

-- Should show workspace isolation policies for each table
*/

-- =============================================================================
-- COMMENTS FOR DOCUMENTATION
-- =============================================================================

COMMENT ON TABLE blocks IS 'Workspace isolated via RLS - blocks table enforces complete workspace boundaries';
COMMENT ON TABLE context_items IS 'Workspace isolated via RLS - context_items access controlled by basket workspace membership';
COMMENT ON TABLE documents IS 'Workspace isolated via RLS - documents table enforces complete workspace boundaries';
COMMENT ON TABLE raw_dumps IS 'Workspace isolated via RLS - raw_dumps table enforces complete workspace boundaries';
COMMENT ON TABLE narrative IS 'Workspace isolated via RLS - narrative access controlled by basket workspace membership';
COMMENT ON TABLE events IS 'Workspace isolated via RLS - events table now workspace-scoped instead of user-scoped';