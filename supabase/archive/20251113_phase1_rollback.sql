-- Rollback Script: Phase 1 - All Migrations
-- Date: 2025-11-13
-- Purpose: Surgical rollback for Phase 1 changes
--
-- IMPORTANT: This script is idempotent - safe to run multiple times
-- Execute in REVERSE order of original migrations:
--   1. Rollback Migration 3 (Storage)
--   2. Rollback Migration 2 (Reference Assets)
--   3. Rollback Migration 1 (Agent Configs)

-- ============================================================================
-- ROLLBACK 3: Storage Setup
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '🔄 Rolling back Migration 3 (Storage Setup)...';
END $$;

-- Drop storage RLS policies
DROP POLICY IF EXISTS "Users can upload assets to their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Users can read assets from their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Users can update assets in their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete assets from their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Service role has full access to yarnnn-assets" ON storage.objects;

-- Drop helper function
DROP FUNCTION IF EXISTS validate_asset_storage_path(uuid, text);

-- Note: Bucket deletion must be done via Supabase Dashboard
-- Cannot drop bucket if it contains files
-- Manual step: Dashboard → Storage → yarnnn-assets → Delete Bucket

DO $$
BEGIN
  RAISE NOTICE '  ✅ Storage RLS policies dropped';
  RAISE NOTICE '  ⚠️  Bucket yarnnn-assets must be deleted manually via Dashboard';
END $$;

-- ============================================================================
-- ROLLBACK 2: Reference Assets & Substrate Tables
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '🔄 Rolling back Migration 2 (Reference Assets)...';
END $$;

-- Drop triggers
DROP TRIGGER IF EXISTS trg_update_reference_assets_updated_at ON reference_assets;
DROP TRIGGER IF EXISTS trg_update_asset_type_catalog_updated_at ON asset_type_catalog;

-- Drop functions
DROP FUNCTION IF EXISTS track_asset_access();
DROP FUNCTION IF EXISTS cleanup_expired_assets();

-- Drop RLS policies (must drop before table)
DROP POLICY IF EXISTS "Users can view assets in their workspace" ON reference_assets;
DROP POLICY IF EXISTS "Users can upload assets to their workspace" ON reference_assets;
DROP POLICY IF EXISTS "Users can update assets in their workspace" ON reference_assets;
DROP POLICY IF EXISTS "Users can delete assets from their workspace" ON reference_assets;
DROP POLICY IF EXISTS "Service role has full access to reference_assets" ON reference_assets;

DROP POLICY IF EXISTS "Users can read active asset types" ON asset_type_catalog;
DROP POLICY IF EXISTS "Service role has full access to asset_type_catalog" ON asset_type_catalog;

-- Drop FK constraint from blocks (must drop before dropping reference_assets)
ALTER TABLE blocks
  DROP CONSTRAINT IF EXISTS blocks_derived_from_asset_id_fkey;

-- Drop column from blocks
ALTER TABLE blocks
  DROP COLUMN IF EXISTS derived_from_asset_id;

-- Drop indexes on blocks
DROP INDEX IF EXISTS idx_blocks_derived_asset;
DROP INDEX IF EXISTS idx_blocks_asset_basket;

-- Drop reference_assets table (CASCADE will drop dependent objects)
DROP TABLE IF EXISTS reference_assets CASCADE;

-- Drop asset_type_catalog table
DROP TABLE IF EXISTS asset_type_catalog CASCADE;

DO $$
BEGIN
  RAISE NOTICE '  ✅ reference_assets table dropped';
  RAISE NOTICE '  ✅ asset_type_catalog table dropped';
  RAISE NOTICE '  ✅ blocks.derived_from_asset_id column dropped';
END $$;

-- ============================================================================
-- ROLLBACK 1: Agent Configs & Work-Platform Tables
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '🔄 Rolling back Migration 1 (Agent Configs)...';
END $$;

-- Drop trigger
DROP TRIGGER IF EXISTS trg_capture_config_change ON project_agents;
DROP FUNCTION IF EXISTS capture_agent_config_change();

-- Drop RLS policies
DROP POLICY IF EXISTS "Users can view agent_config_history in their workspace" ON agent_config_history;
DROP POLICY IF EXISTS "Users can insert agent_config_history in their workspace" ON agent_config_history;
DROP POLICY IF EXISTS "Service role has full access to agent_config_history" ON agent_config_history;

DROP POLICY IF EXISTS "Service role has full access to agent_catalog" ON agent_catalog;
DROP POLICY IF EXISTS "Users can read active agent types" ON agent_catalog;

-- Drop agent_config_history table
DROP TABLE IF EXISTS agent_config_history CASCADE;

-- Drop indexes from project_agents
DROP INDEX IF EXISTS idx_project_agents_config;
DROP INDEX IF EXISTS idx_project_agents_active_config;

-- Drop config columns from project_agents
ALTER TABLE project_agents
  DROP COLUMN IF EXISTS config,
  DROP COLUMN IF EXISTS config_version,
  DROP COLUMN IF EXISTS config_updated_at,
  DROP COLUMN IF EXISTS config_updated_by;

-- Drop indexes from agent_catalog
DROP INDEX IF EXISTS idx_agent_catalog_lifecycle;

-- Remove new columns from agent_catalog (keep original billing columns)
ALTER TABLE agent_catalog
  DROP COLUMN IF EXISTS icon,
  DROP COLUMN IF EXISTS config_schema,
  DROP COLUMN IF EXISTS is_beta,
  DROP COLUMN IF EXISTS deprecated_at,
  DROP COLUMN IF EXISTS schema_version,
  DROP COLUMN IF EXISTS created_by_user_id,
  DROP COLUMN IF EXISTS notes;

-- Note: We do NOT restore executed_by_agent_id to work_sessions
-- That column was legacy and should remain removed

DO $$
BEGIN
  RAISE NOTICE '  ✅ agent_config_history table dropped';
  RAISE NOTICE '  ✅ project_agents config columns dropped';
  RAISE NOTICE '  ✅ agent_catalog reverted to original schema';
  RAISE NOTICE '  ⚠️  work_sessions.executed_by_agent_id NOT restored (was legacy)';
END $$;

-- ============================================================================
-- RESTORE GRANTS (revert to pre-migration state)
-- ============================================================================

-- Note: GRANTS are additive, no need to revoke
-- PostgreSQL will not have issue with extra grants

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  ref_assets_exists BOOLEAN;
  asset_catalog_exists BOOLEAN;
  config_history_exists BOOLEAN;
  project_agents_has_config BOOLEAN;
  agent_catalog_has_schema BOOLEAN;
  blocks_has_derived BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🔍 Verifying rollback...';
  RAISE NOTICE '';

  -- Check tables dropped
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'reference_assets'
  ) INTO ref_assets_exists;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'asset_type_catalog'
  ) INTO asset_catalog_exists;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'agent_config_history'
  ) INTO config_history_exists;

  -- Check columns dropped
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'project_agents'
    AND column_name = 'config'
  ) INTO project_agents_has_config;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'agent_catalog'
    AND column_name = 'config_schema'
  ) INTO agent_catalog_has_schema;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'blocks'
    AND column_name = 'derived_from_asset_id'
  ) INTO blocks_has_derived;

  -- Report results
  RAISE NOTICE '✅ Rollback Verification Results:';
  RAISE NOTICE '';
  RAISE NOTICE '  Tables Dropped:';
  RAISE NOTICE '    - reference_assets: % (should be false)', NOT ref_assets_exists;
  RAISE NOTICE '    - asset_type_catalog: % (should be false)', NOT asset_catalog_exists;
  RAISE NOTICE '    - agent_config_history: % (should be false)', NOT config_history_exists;
  RAISE NOTICE '';
  RAISE NOTICE '  Columns Dropped:';
  RAISE NOTICE '    - project_agents.config: % (should be false)', NOT project_agents_has_config;
  RAISE NOTICE '    - agent_catalog.config_schema: % (should be false)', NOT agent_catalog_has_schema;
  RAISE NOTICE '    - blocks.derived_from_asset_id: % (should be false)', NOT blocks_has_derived;
  RAISE NOTICE '';

  -- Overall status
  IF NOT (ref_assets_exists OR asset_catalog_exists OR config_history_exists OR
          project_agents_has_config OR agent_catalog_has_schema OR blocks_has_derived) THEN
    RAISE NOTICE '✅ ROLLBACK SUCCESSFUL - Database reverted to pre-Phase 1 state';
  ELSE
    RAISE WARNING '⚠️  ROLLBACK INCOMPLETE - Some objects still exist';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Manual Cleanup Required:';

    IF ref_assets_exists THEN
      RAISE NOTICE '  - DROP TABLE reference_assets CASCADE;';
    END IF;

    IF asset_catalog_exists THEN
      RAISE NOTICE '  - DROP TABLE asset_type_catalog CASCADE;';
    END IF;

    IF config_history_exists THEN
      RAISE NOTICE '  - DROP TABLE agent_config_history CASCADE;';
    END IF;

    IF project_agents_has_config THEN
      RAISE NOTICE '  - ALTER TABLE project_agents DROP COLUMN config;';
    END IF;

    IF agent_catalog_has_schema THEN
      RAISE NOTICE '  - ALTER TABLE agent_catalog DROP COLUMN config_schema;';
    END IF;

    IF blocks_has_derived THEN
      RAISE NOTICE '  - ALTER TABLE blocks DROP COLUMN derived_from_asset_id;';
    END IF;
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Post-Rollback Steps:';
  RAISE NOTICE '  1. Delete yarnnn-assets bucket via Supabase Dashboard (if exists)';
  RAISE NOTICE '  2. Verify application still works with original schema';
  RAISE NOTICE '  3. Review rollback reason and fix issues before re-applying';
END $$;
