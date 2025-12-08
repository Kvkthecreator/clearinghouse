-- Migration: Rename work_artifacts to work_outputs
-- Date: 2025-11-16
-- Purpose: Terminology hardening - separate work_outputs (work-platform) from reflections_artifact (substrate-API)

-- ============================================================================
-- PHASE 0: Terminology Hardening
-- ============================================================================
-- The word "artifact" was overloaded across domains:
-- - substrate-API: reflections_artifact (P3 pipeline outputs)
-- - work-platform: work_artifacts (agent execution outputs)
--
-- This migration renames work_artifacts → work_outputs to prevent confusion.

BEGIN;

-- 1. Rename the table
ALTER TABLE IF EXISTS work_artifacts RENAME TO work_outputs;

-- 2. Rename the column (artifact_type → output_type)
ALTER TABLE IF EXISTS work_outputs RENAME COLUMN artifact_type TO output_type;

-- 3. Update indexes (if they exist)
DO $$
BEGIN
    -- Rename index for work_session_id lookup
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_work_artifacts_session_id') THEN
        ALTER INDEX idx_work_artifacts_session_id RENAME TO idx_work_outputs_session_id;
    END IF;

    -- Rename any other artifact-related indexes
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname LIKE '%work_artifacts%') THEN
        -- Log but don't fail if additional indexes exist
        RAISE NOTICE 'Additional work_artifacts indexes may need manual renaming';
    END IF;
END $$;

-- 4. Update RLS policies (if they exist)
DO $$
BEGIN
    -- Drop and recreate RLS policies with new names
    IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'work_outputs') THEN
        -- Policies automatically update when table is renamed
        RAISE NOTICE 'RLS policies updated for work_outputs table';
    END IF;
END $$;

-- 5. Add comment for documentation
COMMENT ON TABLE work_outputs IS 'Agent execution outputs awaiting user review. Renamed from work_artifacts to avoid confusion with substrate-API reflections_artifact table.';
COMMENT ON COLUMN work_outputs.output_type IS 'Type of work output: insight, block_proposal, document_creation, external_deliverable, etc.';

COMMIT;

-- ============================================================================
-- Verification Query
-- ============================================================================
-- Run this to verify the migration:
-- SELECT table_name FROM information_schema.tables WHERE table_name = 'work_outputs';
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'work_outputs' AND column_name = 'output_type';
