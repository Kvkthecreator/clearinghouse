-- Migration: Hierarchical Session Architecture
-- Date: 2025-11-21
-- Purpose: Enable TP to coordinate persistent specialist sessions

-- ============================================================================
-- Add parent_session_id for hierarchical session management
-- ============================================================================

-- Add parent_session_id column (nullable for backward compatibility)
ALTER TABLE agent_sessions
ADD COLUMN parent_session_id UUID REFERENCES agent_sessions(id) ON DELETE CASCADE;

COMMENT ON COLUMN agent_sessions.parent_session_id IS
'FK to parent agent_session. NULL for TP sessions (root). Non-null for specialist sessions (children of TP).';

-- ============================================================================
-- Add created_by_session_id for audit trail
-- ============================================================================

-- Track which session created this session
ALTER TABLE agent_sessions
ADD COLUMN created_by_session_id UUID REFERENCES agent_sessions(id);

COMMENT ON COLUMN agent_sessions.created_by_session_id IS
'FK to agent_session that created this session. Used for audit trail of session spawning.';

-- ============================================================================
-- Indexes for session hierarchy queries
-- ============================================================================

-- Index for parent-child lookups (e.g., "get all specialist sessions for this TP session")
CREATE INDEX idx_agent_sessions_parent
ON agent_sessions(parent_session_id)
WHERE parent_session_id IS NOT NULL;

-- Index for basket + agent_type (supports get_or_create pattern)
CREATE INDEX idx_agent_sessions_basket_type
ON agent_sessions(basket_id, agent_type);

-- ============================================================================
-- Constraints for session hierarchy integrity
-- ============================================================================

-- Constraint: Only TP sessions can be root (parent_session_id = NULL)
-- Specialist sessions MUST have a parent
ALTER TABLE agent_sessions
ADD CONSTRAINT chk_tp_is_root
CHECK (
  (agent_type = 'thinking_partner' AND parent_session_id IS NULL)
  OR
  (agent_type != 'thinking_partner' AND parent_session_id IS NOT NULL)
);

-- ============================================================================
-- Link work_requests to TP sessions
-- ============================================================================

-- Add agent_session_id to work_requests (tracks which TP session created the request)
ALTER TABLE work_requests
ADD COLUMN agent_session_id UUID REFERENCES agent_sessions(id);

COMMENT ON COLUMN work_requests.agent_session_id IS
'FK to TP agent_session. Tracks which TP session created this work request.';

-- Index for querying work_requests by session
CREATE INDEX idx_work_requests_session
ON work_requests(agent_session_id);

-- ============================================================================
-- Link work_tickets to specialist sessions
-- ============================================================================

-- Add agent_session_id to work_tickets (tracks which specialist session executed the work)
ALTER TABLE work_tickets
ADD COLUMN agent_session_id UUID REFERENCES agent_sessions(id);

COMMENT ON COLUMN work_tickets.agent_session_id IS
'FK to specialist agent_session. Tracks which specialist session executed this work ticket.';

-- Index for querying work_tickets by session
CREATE INDEX idx_work_tickets_session
ON work_tickets(agent_session_id);

-- ============================================================================
-- Query Helpers: Functions for common session hierarchy queries
-- ============================================================================

-- Function: Get all child sessions of a parent session
CREATE OR REPLACE FUNCTION get_child_sessions(parent_id UUID)
RETURNS TABLE (
    id UUID,
    agent_type TEXT,
    sdk_session_id TEXT,
    last_active_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        s.agent_type,
        s.sdk_session_id,
        s.last_active_at,
        s.created_at
    FROM agent_sessions s
    WHERE s.parent_session_id = parent_id
    ORDER BY s.created_at ASC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_child_sessions(UUID) IS
'Get all specialist sessions that are children of a TP session.';

-- Function: Get session hierarchy (TP + all children)
CREATE OR REPLACE FUNCTION get_session_hierarchy(basket_id_param UUID)
RETURNS TABLE (
    session_id UUID,
    agent_type TEXT,
    parent_session_id UUID,
    sdk_session_id TEXT,
    is_root BOOLEAN,
    depth INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE session_tree AS (
        -- Base case: TP session (root)
        SELECT
            s.id AS session_id,
            s.agent_type,
            s.parent_session_id,
            s.sdk_session_id,
            (s.parent_session_id IS NULL) AS is_root,
            0 AS depth
        FROM agent_sessions s
        WHERE s.basket_id = basket_id_param
          AND s.parent_session_id IS NULL
          AND s.agent_type = 'thinking_partner'

        UNION ALL

        -- Recursive case: Child sessions
        SELECT
            s.id AS session_id,
            s.agent_type,
            s.parent_session_id,
            s.sdk_session_id,
            FALSE AS is_root,
            st.depth + 1 AS depth
        FROM agent_sessions s
        INNER JOIN session_tree st ON s.parent_session_id = st.session_id
    )
    SELECT * FROM session_tree
    ORDER BY depth, agent_type;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_session_hierarchy(UUID) IS
'Get complete session hierarchy for a basket (TP + all specialist sessions).';

-- ============================================================================
-- RLS Policies (if RLS is enabled on agent_sessions)
-- ============================================================================

-- Allow users to query their own session hierarchies
-- Note: This assumes RLS is enabled. If not, these policies have no effect.

-- Policy: Users can select sessions in their workspace
DROP POLICY IF EXISTS select_workspace_sessions ON agent_sessions;
CREATE POLICY select_workspace_sessions ON agent_sessions
    FOR SELECT
    USING (
        workspace_id IN (
            SELECT id FROM workspaces
            WHERE owner_id = auth.uid()
               OR id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
        )
    );

-- Policy: Users can insert sessions in their workspace
DROP POLICY IF EXISTS insert_workspace_sessions ON agent_sessions;
CREATE POLICY insert_workspace_sessions ON agent_sessions
    FOR INSERT
    WITH CHECK (
        workspace_id IN (
            SELECT id FROM workspaces
            WHERE owner_id = auth.uid()
               OR id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
        )
    );

-- Policy: Users can update sessions in their workspace
DROP POLICY IF EXISTS update_workspace_sessions ON agent_sessions;
CREATE POLICY update_workspace_sessions ON agent_sessions
    FOR UPDATE
    USING (
        workspace_id IN (
            SELECT id FROM workspaces
            WHERE owner_id = auth.uid()
               OR id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
        )
    );

-- ============================================================================
-- Validation Queries
-- ============================================================================

-- Example: Get TP session and its children for a basket
-- SELECT * FROM get_session_hierarchy('basket_abc');

-- Example: Get all research work done in a project
-- SELECT wt.*, s.agent_type, s.sdk_session_id
-- FROM work_tickets wt
-- JOIN agent_sessions s ON wt.agent_session_id = s.id
-- WHERE s.basket_id = 'basket_abc'
--   AND s.agent_type = 'research'
-- ORDER BY wt.created_at DESC;

-- ============================================================================
-- Migration Complete
-- ============================================================================

-- This migration adds hierarchical session support to agent_sessions table.
--
-- Key Changes:
-- 1. parent_session_id: Links specialist sessions to TP parent
-- 2. created_by_session_id: Audit trail of session creation
-- 3. Constraints: TP sessions must be root, specialists must have parent
-- 4. Indexes: Optimize parent-child and basket+type queries
-- 5. work_requests.agent_session_id: Link to TP session
-- 6. work_tickets.agent_session_id: Link to specialist session
-- 7. Helper functions: get_child_sessions(), get_session_hierarchy()
--
-- Next Steps:
-- 1. Apply this migration via Supabase dashboard or CLI
-- 2. Update Python code (ThinkingPartnerAgentSDK, specialist agents)
-- 3. Test session hierarchy creation and persistence
-- 4. Deploy to production
