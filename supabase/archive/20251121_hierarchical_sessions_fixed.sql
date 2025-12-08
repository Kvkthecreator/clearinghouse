-- Migration: Hierarchical Session Architecture (Fixed for existing data)
-- Date: 2025-11-21
-- Purpose: Enable TP to coordinate persistent specialist sessions

-- ============================================================================
-- Add parent_session_id for hierarchical session management
-- ============================================================================

-- Add parent_session_id column (nullable for backward compatibility)
ALTER TABLE agent_sessions
ADD COLUMN IF NOT EXISTS parent_session_id UUID REFERENCES agent_sessions(id) ON DELETE CASCADE;

COMMENT ON COLUMN agent_sessions.parent_session_id IS
'FK to parent agent_session. NULL for TP sessions (root). Non-null for specialist sessions (children of TP).';

-- ============================================================================
-- Add created_by_session_id for audit trail
-- ============================================================================

-- Track which session created this session
ALTER TABLE agent_sessions
ADD COLUMN IF NOT EXISTS created_by_session_id UUID REFERENCES agent_sessions(id);

COMMENT ON COLUMN agent_sessions.created_by_session_id IS
'FK to agent_session that created this session. Used for audit trail of session spawning.';

-- ============================================================================
-- Indexes for session hierarchy queries
-- ============================================================================

-- Index for parent-child lookups (e.g., "get all specialist sessions for this TP session")
CREATE INDEX IF NOT EXISTS idx_agent_sessions_parent
ON agent_sessions(parent_session_id)
WHERE parent_session_id IS NOT NULL;

-- Index for basket + agent_type (supports get_or_create pattern)
CREATE INDEX IF NOT EXISTS idx_agent_sessions_basket_type
ON agent_sessions(basket_id, agent_type);

-- ============================================================================
-- Link work_requests to TP sessions
-- ============================================================================

-- Add agent_session_id to work_requests (tracks which TP session created the request)
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS agent_session_id UUID REFERENCES agent_sessions(id);

COMMENT ON COLUMN work_requests.agent_session_id IS
'FK to TP agent_session. Tracks which TP session created this work request.';

-- Index for querying work_requests by session
CREATE INDEX IF NOT EXISTS idx_work_requests_session
ON work_requests(agent_session_id);

-- ============================================================================
-- Link work_tickets to specialist sessions
-- ============================================================================

-- Add agent_session_id to work_tickets (tracks which specialist session executed the work)
ALTER TABLE work_tickets
ADD COLUMN IF NOT EXISTS agent_session_id UUID REFERENCES agent_sessions(id);

COMMENT ON COLUMN work_tickets.agent_session_id IS
'FK to specialist agent_session. Tracks which specialist session executed this work ticket.';

-- Index for querying work_tickets by session
CREATE INDEX IF NOT EXISTS idx_work_tickets_session
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
-- Migration Complete
-- ============================================================================

-- Note: Constraint NOT added because existing data violates it
-- We'll let the application enforce the hierarchy going forward
-- Existing sessions (parent_session_id = NULL for all) are grandfathered in
-- New sessions created by TP will follow the hierarchy rules

-- Summary of changes:
-- 1. parent_session_id: Links specialist sessions to TP parent (nullable)
-- 2. created_by_session_id: Audit trail of session creation (nullable)
-- 3. Indexes: Optimize parent-child and basket+type queries
-- 4. work_requests.agent_session_id: Link to TP session (if not exists)
-- 5. work_tickets.agent_session_id: Link to specialist session (if not exists)
-- 6. Helper functions: get_child_sessions(), get_session_hierarchy()
