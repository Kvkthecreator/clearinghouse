-- Context Roles Phase 5: Create scheduling infrastructure
-- Date: 2025-12-02
-- Canon Reference: /docs/canon/CONTEXT_ROLES_ARCHITECTURE.md
--
-- This migration creates:
-- 1. project_recipe_schedules table for scheduling recipe execution
-- 2. RLS policies for workspace access control
-- 3. Indexes for efficient scheduling queries

BEGIN;

-- =====================================================
-- 1. Create project_recipe_schedules table
-- =====================================================

CREATE TABLE IF NOT EXISTS project_recipe_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  recipe_slug TEXT NOT NULL,

  -- Schedule definition (use one of these)
  cron_expression TEXT,           -- e.g., '0 9 * * 1' (Monday 9am UTC)
  interval_hours INTEGER,         -- Alternative: run every N hours

  -- State
  enabled BOOLEAN DEFAULT true,
  last_run_at TIMESTAMPTZ,
  next_run_at TIMESTAMPTZ,
  last_run_status TEXT CHECK (last_run_status IN ('success', 'failed', 'skipped')),
  last_run_error TEXT,

  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id),

  -- Constraints
  UNIQUE(project_id, recipe_slug),
  CHECK (cron_expression IS NOT NULL OR interval_hours IS NOT NULL)
);

COMMENT ON TABLE project_recipe_schedules IS
'Schedules for automated recipe execution per project.
Used for context-producing recipes that refresh insight roles (trend_digest, etc.).
Canon ref: /docs/canon/CONTEXT_ROLES_ARCHITECTURE.md';

COMMENT ON COLUMN project_recipe_schedules.cron_expression IS
'Cron expression for scheduled runs. Examples: "0 9 * * 1" (Monday 9am), "0 0 * * *" (daily midnight).';

COMMENT ON COLUMN project_recipe_schedules.interval_hours IS
'Alternative to cron: run every N hours. E.g., 168 for weekly.';

-- =====================================================
-- 2. Create indexes
-- =====================================================

-- Index for finding due schedules
CREATE INDEX idx_schedules_next_run
ON project_recipe_schedules (next_run_at, enabled)
WHERE enabled = true;

-- Index for finding schedules by project
CREATE INDEX idx_schedules_project
ON project_recipe_schedules (project_id);

-- =====================================================
-- 3. Create updated_at trigger
-- =====================================================

CREATE OR REPLACE FUNCTION fn_set_schedule_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER project_recipe_schedules_updated_at
  BEFORE UPDATE ON project_recipe_schedules
  FOR EACH ROW EXECUTE FUNCTION fn_set_schedule_updated_at();

-- =====================================================
-- 4. Enable RLS
-- =====================================================

ALTER TABLE project_recipe_schedules ENABLE ROW LEVEL SECURITY;

-- Service role has full access
CREATE POLICY schedule_service_full
ON project_recipe_schedules
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Workspace members can view schedules
CREATE POLICY schedule_workspace_members_select
ON project_recipe_schedules FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_recipe_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- Workspace members can create schedules
CREATE POLICY schedule_workspace_members_insert
ON project_recipe_schedules FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_recipe_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- Workspace members can update schedules
CREATE POLICY schedule_workspace_members_update
ON project_recipe_schedules FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_recipe_schedules.project_id
    AND wm.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_recipe_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- Workspace members can delete schedules
CREATE POLICY schedule_workspace_members_delete
ON project_recipe_schedules FOR DELETE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM projects p
    JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
    WHERE p.id = project_recipe_schedules.project_id
    AND wm.user_id = auth.uid()
  )
);

-- =====================================================
-- 5. Update purge function to include schedules
-- =====================================================

CREATE OR REPLACE FUNCTION public.purge_workspace_data(target_workspace_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  -- All operations in this function run in a single transaction
  -- If any DELETE fails, the entire operation rolls back

  -- ========================================
  -- WORK-PLATFORM TABLES (Phase 2e Schema)
  -- ========================================

  -- Delete project_recipe_schedules (new)
  DELETE FROM project_recipe_schedules
  WHERE project_id IN (
    SELECT id FROM projects WHERE workspace_id = target_workspace_id
  );

  -- Delete work_iterations (references work_tickets)
  DELETE FROM work_iterations
  WHERE work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id = target_workspace_id
  );

  -- Delete work_checkpoints (references work_tickets)
  DELETE FROM work_checkpoints
  WHERE work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id = target_workspace_id
  );

  -- Delete work_tickets (references work_requests)
  DELETE FROM work_tickets
  WHERE workspace_id = target_workspace_id;

  -- Delete work_requests
  DELETE FROM work_requests
  WHERE workspace_id = target_workspace_id;

  -- Delete agent_sessions
  DELETE FROM agent_sessions
  WHERE workspace_id = target_workspace_id;

  -- Delete project_agents (before projects)
  DELETE FROM project_agents
  WHERE project_id IN (
    SELECT id FROM projects WHERE workspace_id = target_workspace_id
  );

  -- Delete projects (before baskets, as projects reference baskets)
  DELETE FROM projects
  WHERE workspace_id = target_workspace_id;

  -- ========================================
  -- SUBSTRATE TABLES
  -- ========================================

  -- Delete work_outputs (before blocks)
  DELETE FROM work_outputs
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete substrate_relationships (before blocks/context_items)
  DELETE FROM substrate_relationships
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete blocks (core substrate)
  DELETE FROM blocks
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete context_items (if still exists)
  DELETE FROM context_items
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete reference_assets
  DELETE FROM reference_assets
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete reflections_artifact
  DELETE FROM reflections_artifact
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete proposals (governance)
  DELETE FROM proposals
  WHERE basket_id IN (
    SELECT id FROM baskets WHERE workspace_id = target_workspace_id
  );

  -- Delete baskets
  DELETE FROM baskets
  WHERE workspace_id = target_workspace_id;

  -- ========================================
  -- NOTE: The following are intentionally NOT deleted:
  -- - workspaces (the container itself)
  -- - workspace_memberships (user access)
  -- - users (shared across workspaces)
  -- - workspace_governance_settings (settings preserved)
  -- - Integration tokens/connections (preserved for future use)
  -- ========================================

END;
$function$;

COMMENT ON FUNCTION public.purge_workspace_data(uuid) IS
'Purges ALL data (work-platform + substrate) for a workspace. Preserves workspace, memberships, users, and settings. Updated 2025-12-02 to include project_recipe_schedules.';

COMMIT;
