-- =============================================================================
-- CLEARINGHOUSE: Governance Schema
-- Migration: 00003_governance.sql
-- Purpose: Proposal pipeline for controlled rights changes
-- =============================================================================

-- =============================================================================
-- PROPOSALS (Rights Change Requests)
-- =============================================================================

CREATE TABLE proposals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_id UUID NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,

    -- Proposal classification
    proposal_type TEXT NOT NULL CHECK (proposal_type IN (
        'CREATE',           -- New rights entity
        'UPDATE',           -- Modify existing entity
        'TRANSFER',         -- Change ownership
        'VERIFY',           -- Verify claimed rights
        'DISPUTE',          -- Challenge existing claim
        'ARCHIVE',          -- Archive/deactivate entity
        'RESTORE'           -- Restore archived entity
    )),

    -- Target entity (null for CREATE)
    target_entity_id UUID REFERENCES rights_entities(id) ON DELETE CASCADE,

    -- Proposed changes
    payload JSONB NOT NULL,  -- Full entity data for CREATE, or delta for UPDATE
    reasoning TEXT,          -- Why this change is being proposed

    -- Status
    status TEXT DEFAULT 'pending' CHECK (status IN (
        'pending',
        'under_review',
        'approved',
        'rejected',
        'cancelled',
        'expired'
    )),

    -- Priority/urgency
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),

    -- Review information
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,

    -- Auto-approval rules
    auto_approved BOOLEAN DEFAULT false,
    auto_approval_reason TEXT,

    -- Expiration (optional)
    expires_at TIMESTAMPTZ,

    -- Audit
    created_by TEXT NOT NULL,  -- 'user:{uuid}' or 'system' or 'api:{client}'
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE proposals IS 'Governance pipeline for rights changes - all mutations go through proposals';
COMMENT ON COLUMN proposals.payload IS 'Full entity data for CREATE, or partial update for UPDATE';
COMMENT ON COLUMN proposals.auto_approved IS 'True if proposal was auto-approved by rules (e.g., restricting AI permissions)';

-- Indexes
CREATE INDEX idx_proposals_catalog ON proposals(catalog_id);
CREATE INDEX idx_proposals_status ON proposals(status) WHERE status = 'pending';
CREATE INDEX idx_proposals_target ON proposals(target_entity_id) WHERE target_entity_id IS NOT NULL;
CREATE INDEX idx_proposals_created_by ON proposals(created_by);
CREATE INDEX idx_proposals_created_at ON proposals(created_at DESC);

-- =============================================================================
-- PROPOSAL COMMENTS (Discussion Thread)
-- =============================================================================

CREATE TABLE proposal_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id UUID NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,

    -- Comment content
    content TEXT NOT NULL,
    comment_type TEXT DEFAULT 'comment' CHECK (comment_type IN ('comment', 'question', 'concern', 'approval', 'rejection')),

    -- Audit
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE proposal_comments IS 'Discussion thread for proposal review';

CREATE INDEX idx_proposal_comments_proposal ON proposal_comments(proposal_id);

-- =============================================================================
-- GOVERNANCE RULES (Auto-Approval Configuration)
-- =============================================================================

CREATE TABLE governance_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Rule definition
    rule_name TEXT NOT NULL,
    description TEXT,

    -- Conditions (JSONB for flexibility)
    conditions JSONB NOT NULL,
    -- Example:
    -- {
    --   "proposal_type": "UPDATE",
    --   "field_path": "ai_permissions.training",
    --   "change_direction": "restrict"  -- allow auto-approve when restricting
    -- }

    -- Action
    action TEXT NOT NULL CHECK (action IN ('auto_approve', 'require_review', 'auto_reject')),

    -- Priority (higher = evaluated first)
    priority INTEGER DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT true,

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE governance_rules IS 'Configurable rules for auto-approval of proposals';

CREATE INDEX idx_governance_rules_workspace ON governance_rules(workspace_id);

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE proposal_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance_rules ENABLE ROW LEVEL SECURITY;

-- Proposals: workspace members can view
CREATE POLICY "proposals_select_members"
ON proposals FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = proposals.catalog_id
        AND wm.user_id = auth.uid()
    )
);

-- Proposals: workspace members can create
CREATE POLICY "proposals_insert_members"
ON proposals FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = proposals.catalog_id
        AND wm.user_id = auth.uid()
    )
);

-- Proposals: admins can update (approve/reject)
CREATE POLICY "proposals_update_admins"
ON proposals FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = proposals.catalog_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

-- Proposals: creator can cancel their own pending proposals
CREATE POLICY "proposals_cancel_creator"
ON proposals FOR UPDATE TO authenticated
USING (
    proposals.created_by = 'user:' || auth.uid()::text
    AND proposals.status = 'pending'
);

CREATE POLICY "proposals_service_role"
ON proposals FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- Proposal comments: workspace members can view/create
CREATE POLICY "proposal_comments_select_members"
ON proposal_comments FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM proposals p
        JOIN catalogs c ON c.id = p.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE p.id = proposal_comments.proposal_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "proposal_comments_insert_members"
ON proposal_comments FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM proposals p
        JOIN catalogs c ON c.id = p.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE p.id = proposal_comments.proposal_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "proposal_comments_service_role"
ON proposal_comments FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- Governance rules: workspace admins only
CREATE POLICY "governance_rules_select_admins"
ON governance_rules FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = governance_rules.workspace_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

CREATE POLICY "governance_rules_manage_admins"
ON governance_rules FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = governance_rules.workspace_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

CREATE POLICY "governance_rules_service_role"
ON governance_rules FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

CREATE TRIGGER trg_proposals_updated_at
    BEFORE UPDATE ON proposals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_governance_rules_updated_at
    BEFORE UPDATE ON governance_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT ALL ON proposals TO authenticated;
GRANT ALL ON proposals TO service_role;
GRANT ALL ON proposal_comments TO authenticated;
GRANT ALL ON proposal_comments TO service_role;
GRANT ALL ON governance_rules TO authenticated;
GRANT ALL ON governance_rules TO service_role;
