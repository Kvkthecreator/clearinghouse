-- Migration: Project-Agent Architecture Refactor
-- Date: 2025-11-08
-- Purpose: Implement first-principles agent-centric architecture
--
-- Changes:
-- 1. Create project_agents table (many-to-many projects ↔ agents)
-- 2. Update work_sessions with proper agent linkage
-- 3. Remove project_type from projects (pure container model)

-- ============================================================================
-- STEP 1: Create project_agents table
-- ============================================================================

CREATE TABLE IF NOT EXISTS project_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  agent_type text NOT NULL,

  -- User customization
  display_name text NOT NULL,
  is_active boolean DEFAULT true NOT NULL,

  -- Audit trail
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by_user_id uuid,

  -- Constraints
  CONSTRAINT fk_agent_type FOREIGN KEY (agent_type)
    REFERENCES agent_catalog(agent_type) ON UPDATE CASCADE,
  CONSTRAINT unique_agent_per_project
    UNIQUE(project_id, agent_type)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_project_agents_project ON project_agents(project_id);
CREATE INDEX IF NOT EXISTS idx_project_agents_type ON project_agents(agent_type);
CREATE INDEX IF NOT EXISTS idx_project_agents_active ON project_agents(project_id, is_active);

COMMENT ON TABLE project_agents IS 'Agent instances within projects. Many-to-many relationship allowing projects to have multiple agents.';
COMMENT ON COLUMN project_agents.display_name IS 'User-customizable agent name (e.g., "My Market Research Agent")';
COMMENT ON COLUMN project_agents.agent_type IS 'References agent_catalog.agent_type for billing/permissions';

-- ============================================================================
-- STEP 2: Update work_sessions with agent linkage
-- ============================================================================

-- Add project_agent_id column (nullable for backward compatibility)
ALTER TABLE work_sessions
  ADD COLUMN IF NOT EXISTS project_agent_id uuid REFERENCES project_agents(id) ON DELETE SET NULL;

-- Add billing linkage
ALTER TABLE work_sessions
  ADD COLUMN IF NOT EXISTS agent_work_request_id uuid REFERENCES agent_work_requests(id) ON DELETE SET NULL;

-- Create index for common query patterns
CREATE INDEX IF NOT EXISTS idx_work_sessions_agent ON work_sessions(project_agent_id);
CREATE INDEX IF NOT EXISTS idx_work_sessions_billing ON work_sessions(agent_work_request_id);

COMMENT ON COLUMN work_sessions.project_agent_id IS 'Links to project_agents for data integrity. NULL for legacy sessions.';
COMMENT ON COLUMN work_sessions.agent_work_request_id IS 'Links to agent_work_requests for trial/billing tracking.';

-- ============================================================================
-- STEP 3: Remove project_type from projects (pure container model)
-- ============================================================================

-- Drop CHECK constraint first
ALTER TABLE projects DROP CONSTRAINT IF EXISTS projects_project_type_check;

-- Drop the column
ALTER TABLE projects DROP COLUMN IF EXISTS project_type;

COMMENT ON TABLE projects IS 'Pure container model: projects hold context (baskets) and agents work within them. No structural typing.';

-- ============================================================================
-- STEP 4: RLS Policies for project_agents
-- ============================================================================

-- Enable RLS
ALTER TABLE project_agents ENABLE ROW LEVEL SECURITY;

-- Users can view agents in their workspace projects
CREATE POLICY "Users can view project_agents in their workspace"
  ON project_agents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects p
      JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
      WHERE p.id = project_agents.project_id
      AND wm.user_id = auth.uid()
    )
  );

-- Users can create agents in their workspace projects
CREATE POLICY "Users can create project_agents in their workspace"
  ON project_agents FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects p
      JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
      WHERE p.id = project_agents.project_id
      AND wm.user_id = auth.uid()
    )
  );

-- Users can update agents in their workspace projects
CREATE POLICY "Users can update project_agents in their workspace"
  ON project_agents FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM projects p
      JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
      WHERE p.id = project_agents.project_id
      AND wm.user_id = auth.uid()
    )
  );

-- Users can delete agents in their workspace projects
CREATE POLICY "Users can delete project_agents in their workspace"
  ON project_agents FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM projects p
      JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
      WHERE p.id = project_agents.project_id
      AND wm.user_id = auth.uid()
    )
  );

-- Service role has full access
CREATE POLICY "Service role has full access to project_agents"
  ON project_agents
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- STEP 5: Backfill existing projects with default research agent
-- ============================================================================

-- Auto-create research agent for all existing projects
-- (Safe to run multiple times due to UNIQUE constraint)
INSERT INTO project_agents (project_id, agent_type, display_name, created_by_user_id)
SELECT
  p.id as project_id,
  'research' as agent_type,
  'Research Agent' as display_name,
  p.user_id as created_by_user_id
FROM projects p
ON CONFLICT (project_id, agent_type) DO NOTHING;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  project_count INTEGER;
  agent_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO project_count FROM projects;
  SELECT COUNT(*) INTO agent_count FROM project_agents;

  RAISE NOTICE '✅ Migration complete:';
  RAISE NOTICE '  - % projects in database', project_count;
  RAISE NOTICE '  - % project agents created (1 per project)', agent_count;
  RAISE NOTICE '  - project_type column removed from projects';
  RAISE NOTICE '  - work_sessions updated with agent linkage columns';
END $$;
