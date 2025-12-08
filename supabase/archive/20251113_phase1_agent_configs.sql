-- Migration: Phase 1 - Agent Configurations & Work-Platform Table Updates
-- Date: 2025-11-13
-- Purpose: Add agent config support, evolve agent_catalog, cleanup work_sessions
--
-- Changes:
-- 1. Evolve agent_catalog: Add config schema columns while keeping billing columns
-- 2. Update project_agents: Add config columns
-- 3. Create agent_config_history: Audit trail for config changes
-- 4. Cleanup work_sessions: Remove redundant executed_by_agent_id column
-- 5. Add comprehensive RLS policies and GRANTS

-- ============================================================================
-- STEP 1: Evolve agent_catalog (add config schema support)
-- ============================================================================

-- Add new columns to existing agent_catalog table
ALTER TABLE agent_catalog
  ADD COLUMN IF NOT EXISTS icon text,
  ADD COLUMN IF NOT EXISTS config_schema jsonb DEFAULT '{}' NOT NULL,
  ADD COLUMN IF NOT EXISTS is_beta boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS deprecated_at timestamptz,
  ADD COLUMN IF NOT EXISTS schema_version integer DEFAULT 1 NOT NULL,
  ADD COLUMN IF NOT EXISTS created_by_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS notes text;

-- Update existing records with default config schemas
UPDATE agent_catalog SET config_schema = '{
  "type": "object",
  "properties": {
    "watchlist": {
      "type": "object",
      "properties": {
        "competitors": {"type": "array", "items": {"type": "string"}},
        "topics": {"type": "array", "items": {"type": "string"}},
        "data_sources": {"type": "array"}
      }
    },
    "alert_rules": {"type": "object"},
    "output_preferences": {"type": "object"}
  }
}'::jsonb, icon = 'Brain' WHERE agent_type = 'research';

UPDATE agent_catalog SET config_schema = '{
  "type": "object",
  "properties": {
    "brand_voice": {"type": "object"},
    "platforms": {"type": "object"},
    "content_rules": {"type": "object"}
  }
}'::jsonb, icon = 'PenSquare' WHERE agent_type = 'content';

UPDATE agent_catalog SET config_schema = '{
  "type": "object",
  "properties": {
    "report_preferences": {"type": "object"},
    "data_sources": {"type": "object"},
    "formatting": {"type": "object"}
  }
}'::jsonb, icon = 'BarChart3' WHERE agent_type = 'reporting';

-- Update index to include new columns
CREATE INDEX IF NOT EXISTS idx_agent_catalog_lifecycle
  ON agent_catalog(is_active, is_beta, deprecated_at)
  WHERE is_active = true;

COMMENT ON COLUMN agent_catalog.config_schema IS 'JSON Schema for runtime config validation';
COMMENT ON COLUMN agent_catalog.icon IS 'Lucide icon name for UI display';
COMMENT ON COLUMN agent_catalog.is_beta IS 'Agent is in beta testing phase';
COMMENT ON COLUMN agent_catalog.deprecated_at IS 'Timestamp when agent type was deprecated';
COMMENT ON COLUMN agent_catalog.schema_version IS 'Config schema version for migration support';

-- ============================================================================
-- STEP 2: Update project_agents table (add config columns)
-- ============================================================================

ALTER TABLE project_agents
  ADD COLUMN IF NOT EXISTS config jsonb DEFAULT '{}' NOT NULL,
  ADD COLUMN IF NOT EXISTS config_version integer DEFAULT 1 NOT NULL,
  ADD COLUMN IF NOT EXISTS config_updated_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS config_updated_by uuid REFERENCES auth.users(id);

-- Create index for config queries (GIN for jsonb)
CREATE INDEX IF NOT EXISTS idx_project_agents_config
  ON project_agents USING gin(config);

-- Create index for active configs
CREATE INDEX IF NOT EXISTS idx_project_agents_active_config
  ON project_agents(project_id, is_active, config_updated_at DESC)
  WHERE is_active = true;

COMMENT ON COLUMN project_agents.config IS 'Agent-specific configuration (validated against agent_catalog.config_schema)';
COMMENT ON COLUMN project_agents.config_version IS 'Config version for tracking changes';
COMMENT ON COLUMN project_agents.config_updated_at IS 'Last config update timestamp';
COMMENT ON COLUMN project_agents.config_updated_by IS 'User who last updated config';

-- ============================================================================
-- STEP 3: Create agent_config_history table (audit trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS agent_config_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_agent_id uuid NOT NULL REFERENCES project_agents(id) ON DELETE CASCADE,

  -- Snapshot
  config_snapshot jsonb NOT NULL,
  config_version integer NOT NULL,

  -- Audit
  changed_by_user_id uuid REFERENCES auth.users(id),
  changed_at timestamptz DEFAULT now() NOT NULL,
  change_reason text,

  -- Metadata
  metadata jsonb DEFAULT '{}'
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_agent_config_history_agent
  ON agent_config_history(project_agent_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_config_history_version
  ON agent_config_history(project_agent_id, config_version DESC);

CREATE INDEX IF NOT EXISTS idx_agent_config_history_user
  ON agent_config_history(changed_by_user_id, changed_at DESC);

COMMENT ON TABLE agent_config_history IS 'Audit trail for agent configuration changes';
COMMENT ON COLUMN agent_config_history.config_snapshot IS 'Full config snapshot at time of change';
COMMENT ON COLUMN agent_config_history.change_reason IS 'User-provided reason for config change';

-- ============================================================================
-- STEP 4: Cleanup work_sessions (remove redundant column)
-- ============================================================================

-- Remove legacy executed_by_agent_id column (replaced by project_agent_id)
ALTER TABLE work_sessions
  DROP COLUMN IF EXISTS executed_by_agent_id;

COMMENT ON COLUMN work_sessions.project_agent_id IS 'Links to project_agents for proper agent identification (executed_by_agent_id deprecated)';

-- ============================================================================
-- STEP 5: RLS Policies for new tables
-- ============================================================================

-- Enable RLS on agent_config_history
ALTER TABLE agent_config_history ENABLE ROW LEVEL SECURITY;

-- Users can view config history for agents in their workspace
CREATE POLICY "Users can view agent_config_history in their workspace"
  ON agent_config_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM project_agents pa
      JOIN projects p ON p.id = pa.project_id
      JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
      WHERE pa.id = agent_config_history.project_agent_id
      AND wm.user_id = auth.uid()
    )
  );

-- Users can insert config history when they update agent configs
CREATE POLICY "Users can insert agent_config_history in their workspace"
  ON agent_config_history FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM project_agents pa
      JOIN projects p ON p.id = pa.project_id
      JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
      WHERE pa.id = agent_config_history.project_agent_id
      AND wm.user_id = auth.uid()
    )
  );

-- Service role has full access
CREATE POLICY "Service role has full access to agent_config_history"
  ON agent_config_history
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Update agent_catalog RLS (currently only has read policy for is_active)
-- Add service role policy
CREATE POLICY "Service role has full access to agent_catalog"
  ON agent_catalog
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Add authenticated user policy for reading all agent types
DROP POLICY IF EXISTS "agent_catalog_read" ON agent_catalog;
CREATE POLICY "Users can read active agent types"
  ON agent_catalog FOR SELECT
  TO authenticated
  USING (is_active = true AND deprecated_at IS NULL);

-- Admin users can manage agent catalog (implement in Phase 2)
-- For now, service role only

-- ============================================================================
-- STEP 6: GRANTS (critical for service-to-service access)
-- ============================================================================

-- Grant service role access to all new columns/tables
GRANT ALL ON agent_catalog TO service_role;
GRANT ALL ON project_agents TO service_role;
GRANT ALL ON agent_config_history TO service_role;
GRANT ALL ON work_sessions TO service_role;

-- Grant authenticated users appropriate access
GRANT SELECT ON agent_catalog TO authenticated;
GRANT ALL ON project_agents TO authenticated;
GRANT SELECT, INSERT ON agent_config_history TO authenticated;
GRANT ALL ON work_sessions TO authenticated;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================================================
-- STEP 7: Trigger for auto-capturing config changes
-- ============================================================================

CREATE OR REPLACE FUNCTION capture_agent_config_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only capture if config actually changed
  IF OLD.config IS DISTINCT FROM NEW.config THEN
    INSERT INTO agent_config_history (
      project_agent_id,
      config_snapshot,
      config_version,
      changed_by_user_id,
      changed_at,
      change_reason,
      metadata
    ) VALUES (
      NEW.id,
      NEW.config,
      NEW.config_version,
      NEW.config_updated_by,
      NEW.config_updated_at,
      'Auto-captured via trigger',
      jsonb_build_object(
        'previous_version', OLD.config_version,
        'trigger_source', 'project_agents_update'
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
DROP TRIGGER IF EXISTS trg_capture_config_change ON project_agents;
CREATE TRIGGER trg_capture_config_change
  AFTER UPDATE ON project_agents
  FOR EACH ROW
  WHEN (OLD.config IS DISTINCT FROM NEW.config)
  EXECUTE FUNCTION capture_agent_config_change();

COMMENT ON FUNCTION capture_agent_config_change IS 'Auto-captures agent config changes to history table';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  catalog_cols INTEGER;
  project_agents_cols INTEGER;
  history_count INTEGER;
  work_session_has_executed_by BOOLEAN;
BEGIN
  -- Check agent_catalog columns
  SELECT COUNT(*) INTO catalog_cols
  FROM information_schema.columns
  WHERE table_name = 'agent_catalog'
  AND column_name IN ('icon', 'config_schema', 'is_beta', 'schema_version');

  -- Check project_agents columns
  SELECT COUNT(*) INTO project_agents_cols
  FROM information_schema.columns
  WHERE table_name = 'project_agents'
  AND column_name IN ('config', 'config_version', 'config_updated_at', 'config_updated_by');

  -- Check agent_config_history exists
  SELECT COUNT(*) INTO history_count
  FROM information_schema.tables
  WHERE table_name = 'agent_config_history';

  -- Check executed_by_agent_id was removed
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_sessions'
    AND column_name = 'executed_by_agent_id'
  ) INTO work_session_has_executed_by;

  RAISE NOTICE '✅ Migration 1 (Phase 1 - Agent Configs) Complete:';
  RAISE NOTICE '  - agent_catalog: % new columns added', catalog_cols;
  RAISE NOTICE '  - project_agents: % config columns added', project_agents_cols;
  RAISE NOTICE '  - agent_config_history: % (1 = created)', history_count;
  RAISE NOTICE '  - work_sessions.executed_by_agent_id removed: %', NOT work_session_has_executed_by;

  -- Validation checks
  IF catalog_cols < 4 THEN
    RAISE WARNING 'agent_catalog columns incomplete (expected 4, got %)', catalog_cols;
  END IF;

  IF project_agents_cols < 4 THEN
    RAISE WARNING 'project_agents columns incomplete (expected 4, got %)', project_agents_cols;
  END IF;

  IF history_count = 0 THEN
    RAISE WARNING 'agent_config_history table not created';
  END IF;

  IF work_session_has_executed_by THEN
    RAISE WARNING 'work_sessions.executed_by_agent_id still exists (should be removed)';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Next Steps:';
  RAISE NOTICE '  1. Run Migration 2: reference_assets + blocks enhancement';
  RAISE NOTICE '  2. Setup Supabase Storage bucket';
  RAISE NOTICE '  3. Deploy substrate-API file upload endpoints';
END $$;
