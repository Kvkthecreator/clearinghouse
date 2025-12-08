-- Migration: Projects Table (Work-Platform Domain)
-- Purpose: User-facing project containers that wrap substrate baskets
-- Date: 2025-11-04
-- Context: Phase 6 refactor - Projects vs Baskets domain separation

-- ============================================================================
-- PROJECTS: User-facing work containers (work-platform domain)
-- ============================================================================

CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identity & Ownership
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Project Metadata
  name text NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 200),
  description text,

  -- Substrate Linkage (1:1 mapping for now, but flexible for future)
  basket_id uuid NOT NULL REFERENCES baskets(id) ON DELETE RESTRICT,

  -- Project Configuration
  project_type text CHECK (project_type IN (
    'research',
    'content_creation',
    'reporting',
    'analysis',
    'general'
  )) DEFAULT 'general' NOT NULL,

  -- Status
  status text CHECK (status IN (
    'active',
    'archived',
    'completed',
    'on_hold'
  )) DEFAULT 'active' NOT NULL,

  -- Origin Tracking
  origin_template text,  -- e.g., 'onboarding_v1', 'manual_creation', 'imported'
  onboarded_at timestamptz,  -- When user completed onboarding for this project

  -- Timestamps
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  archived_at timestamptz,

  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_projects_workspace ON projects(workspace_id);
CREATE INDEX IF NOT EXISTS idx_projects_user ON projects(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_basket ON projects(basket_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_type ON projects(project_type);
CREATE INDEX IF NOT EXISTS idx_projects_created ON projects(created_at DESC);

-- Unique constraint: One basket per project (enforce 1:1 for now)
CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_basket_unique ON projects(basket_id);

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON TABLE projects TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE projects TO authenticated;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view projects in their workspaces"
  ON projects FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can create projects in their workspaces"
  ON projects FOR INSERT
  WITH CHECK (
    workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
    AND user_id = auth.uid()
  );

CREATE POLICY "Users can update their projects"
  ON projects FOR UPDATE
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION update_project_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_project_timestamp
  BEFORE UPDATE ON projects
  FOR EACH ROW
  EXECUTE FUNCTION update_project_timestamp();

-- ============================================================================
-- MIGRATION NOTES
-- ============================================================================

-- This table creates a work-platform domain abstraction over substrate baskets.
--
-- DOMAIN SEPARATION:
-- - Projects = User-facing concept (work-platform)
-- - Baskets = Storage concept (substrate)
-- - Currently 1:1 mapping, but schema allows future flexibility
--
-- FUTURE EXTENSIONS:
-- - project_baskets junction table (1:many)
-- - project_permissions (fine-grained access control)
-- - project_collaborators (multi-user projects)
-- - project_templates (reusable project scaffolding)
