-- Migration: Align projects table with Phase 6 schema
-- Date: 2025-11-07
-- Context: Production has created_by_user_id, but code expects user_id
-- This migration adds missing columns from 20251104_projects_table.sql

-- ============================================================================
-- STEP 1: Rename created_by_user_id to user_id
-- ============================================================================

-- First, check if user_id already exists (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'projects' AND column_name = 'user_id'
    ) THEN
        -- Rename created_by_user_id to user_id
        ALTER TABLE projects RENAME COLUMN created_by_user_id TO user_id;

        RAISE NOTICE 'Renamed created_by_user_id to user_id';
    ELSE
        RAISE NOTICE 'user_id column already exists, skipping rename';
    END IF;
END $$;

-- ============================================================================
-- STEP 2: Add missing columns
-- ============================================================================

-- Add project_type with enum constraint
ALTER TABLE projects ADD COLUMN IF NOT EXISTS project_type text
    CHECK (project_type IN ('research', 'content_creation', 'reporting', 'analysis', 'general'))
    DEFAULT 'general' NOT NULL;

-- Add origin tracking columns
ALTER TABLE projects ADD COLUMN IF NOT EXISTS origin_template text;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS onboarded_at timestamptz;

-- Add archived_at for soft deletes
ALTER TABLE projects ADD COLUMN IF NOT EXISTS archived_at timestamptz;

-- Add metadata JSONB column
ALTER TABLE projects ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb NOT NULL;

-- ============================================================================
-- STEP 3: Create missing indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_projects_user ON projects(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_type ON projects(project_type);

-- Note: These indexes should already exist from earlier migrations:
-- - idx_projects_workspace ON projects(workspace_id)
-- - idx_projects_basket ON projects(basket_id)
-- - idx_projects_status ON projects(status)
-- - idx_projects_created ON projects(created_at DESC)

-- ============================================================================
-- STEP 4: Update RLS policies (if needed)
-- ============================================================================

-- Drop old policies that reference created_by_user_id (if they exist)
DROP POLICY IF EXISTS "Users can view their projects" ON projects;
DROP POLICY IF EXISTS "Users can create their projects" ON projects;
DROP POLICY IF EXISTS "Users can update their projects" ON projects;

-- Recreate policies using user_id
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
-- VERIFICATION
-- ============================================================================

-- Show final schema
DO $$
DECLARE
    col_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO col_count
    FROM information_schema.columns
    WHERE table_name = 'projects';

    RAISE NOTICE 'Projects table now has % columns', col_count;

    -- Verify key columns exist
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'projects' AND column_name = 'user_id') THEN
        RAISE NOTICE '✓ user_id column exists';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'projects' AND column_name = 'project_type') THEN
        RAISE NOTICE '✓ project_type column exists';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'projects' AND column_name = 'metadata') THEN
        RAISE NOTICE '✓ metadata column exists';
    END IF;
END $$;
