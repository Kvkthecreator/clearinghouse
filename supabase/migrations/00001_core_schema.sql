-- =============================================================================
-- CLEARINGHOUSE: Core Schema
-- Migration: 00001_core_schema.sql
-- Purpose: Foundation tables for multi-tenancy and basic infrastructure
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- =============================================================================
-- WORKSPACES (Multi-Tenancy)
-- =============================================================================

CREATE TABLE workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    description TEXT,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE workspaces IS 'Multi-tenant workspace containers (organizations)';

-- Workspace memberships
CREATE TABLE workspace_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(workspace_id, user_id)
);

COMMENT ON TABLE workspace_memberships IS 'Maps users to workspaces with roles';

-- Indexes
CREATE INDEX idx_workspace_memberships_user ON workspace_memberships(user_id);
CREATE INDEX idx_workspace_memberships_workspace ON workspace_memberships(workspace_id);

-- =============================================================================
-- CATALOGS (IP Portfolios)
-- =============================================================================

CREATE TABLE catalogs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    -- Catalog-level defaults for AI permissions
    default_ai_permissions JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE catalogs IS 'IP portfolios/collections within a workspace';

CREATE INDEX idx_catalogs_workspace ON catalogs(workspace_id);

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalogs ENABLE ROW LEVEL SECURITY;

-- Workspaces: members can view their workspaces
CREATE POLICY "workspaces_select_members"
ON workspaces FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = workspaces.id
        AND wm.user_id = auth.uid()
    )
);

-- Workspaces: owners/admins can update
CREATE POLICY "workspaces_update_admins"
ON workspaces FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = workspaces.id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

-- Workspace memberships: members can view memberships in their workspaces
CREATE POLICY "memberships_select_members"
ON workspace_memberships FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = workspace_memberships.workspace_id
        AND wm.user_id = auth.uid()
    )
);

-- Workspace memberships: owners/admins can manage
CREATE POLICY "memberships_manage_admins"
ON workspace_memberships FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = workspace_memberships.workspace_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

-- Catalogs: workspace members can view
CREATE POLICY "catalogs_select_members"
ON catalogs FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = catalogs.workspace_id
        AND wm.user_id = auth.uid()
    )
);

-- Catalogs: workspace members can insert
CREATE POLICY "catalogs_insert_members"
ON catalogs FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = catalogs.workspace_id
        AND wm.user_id = auth.uid()
    )
);

-- Catalogs: workspace admins can update/delete
CREATE POLICY "catalogs_update_admins"
ON catalogs FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = catalogs.workspace_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin', 'member')
    )
);

CREATE POLICY "catalogs_delete_admins"
ON catalogs FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = catalogs.workspace_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

-- Service role: full access
CREATE POLICY "workspaces_service_role" ON workspaces FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "memberships_service_role" ON workspace_memberships FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "catalogs_service_role" ON catalogs FOR ALL TO service_role USING (true) WITH CHECK (true);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers
CREATE TRIGGER trg_workspaces_updated_at
    BEFORE UPDATE ON workspaces
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_catalogs_updated_at
    BEFORE UPDATE ON catalogs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT ALL ON workspaces TO authenticated;
GRANT ALL ON workspace_memberships TO authenticated;
GRANT ALL ON catalogs TO authenticated;
GRANT ALL ON workspaces TO service_role;
GRANT ALL ON workspace_memberships TO service_role;
GRANT ALL ON catalogs TO service_role;
