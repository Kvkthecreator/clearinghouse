-- Migration: Alter work_outputs table to match new schema
-- Date: 2025-11-17
-- Purpose: Update existing work_outputs table with new columns for Phase 1 implementation
--
-- Context: work_outputs table was previously created (from work_artifacts rename)
-- with a simpler schema. This migration adds the new columns for work supervision lifecycle.

-- ============================================================================
-- STEP 1: Add missing columns to work_outputs
-- ============================================================================

-- Add basket_id (required for BFF pattern - basket-scoped access)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS basket_id uuid;

-- Add FK constraint for basket_id (only if column was just added and baskets exist)
DO $$
BEGIN
  -- Only add FK if basket_id column exists and constraint doesn't
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'basket_id'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'work_outputs_basket_id_fkey'
  ) THEN
    -- For existing rows, we need to populate basket_id from work_sessions
    UPDATE work_outputs wo
    SET basket_id = (
      SELECT pa.basket_id
      FROM work_sessions ws
      JOIN project_agents pa ON ws.project_agent_id = pa.id
      WHERE ws.id = wo.work_session_id
      LIMIT 1
    )
    WHERE basket_id IS NULL;

    -- Now we can add the constraint (if baskets table exists)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'baskets') THEN
      ALTER TABLE work_outputs
        ADD CONSTRAINT work_outputs_basket_id_fkey
        FOREIGN KEY (basket_id) REFERENCES baskets(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- Add agent_type column
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS agent_type text DEFAULT 'research';

-- Add title column (extract from content if possible)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS title text;

-- Populate title from content JSONB if not set
UPDATE work_outputs
SET title = COALESCE(
  content->>'title',
  content->>'summary',
  'Output #' || EXTRACT(EPOCH FROM created_at)::text
)
WHERE title IS NULL;

-- Add body column (rename content to body conceptually, but keep content for backward compat)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS body jsonb;

-- Copy content to body for new column
UPDATE work_outputs
SET body = content
WHERE body IS NULL;

-- Add confidence column (convert agent_confidence)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS confidence float;

-- Copy agent_confidence to confidence
UPDATE work_outputs
SET confidence = COALESCE(agent_confidence::float, 0.7)
WHERE confidence IS NULL;

-- Add source_context_ids for provenance
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS source_context_ids uuid[];

-- Add tool_call_id for Claude traceability
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS tool_call_id text;

-- Add supervision_status (map from status)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS supervision_status text DEFAULT 'pending_review';

-- Map old status to new supervision_status
UPDATE work_outputs
SET supervision_status = CASE
  WHEN status = 'pending' THEN 'pending_review'
  WHEN status = 'approved' THEN 'approved'
  WHEN status = 'rejected' THEN 'rejected'
  ELSE 'pending_review'
END
WHERE supervision_status IS NULL OR supervision_status = 'pending_review';

-- Add reviewer_notes (rename review_feedback)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS reviewer_notes text;

UPDATE work_outputs
SET reviewer_notes = review_feedback
WHERE reviewer_notes IS NULL AND review_feedback IS NOT NULL;

-- Add reviewed_by (rename reviewed_by_user_id)
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS reviewed_by uuid;

UPDATE work_outputs
SET reviewed_by = reviewed_by_user_id
WHERE reviewed_by IS NULL AND reviewed_by_user_id IS NOT NULL;

-- Add updated_at column
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Add metadata column
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}';

-- Add substrate integration columns
ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS substrate_proposal_id uuid;

ALTER TABLE work_outputs
  ADD COLUMN IF NOT EXISTS merged_to_substrate_at timestamptz;

-- ============================================================================
-- STEP 2: Add constraints
-- ============================================================================

-- Add check constraint for supervision_status
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'work_outputs_supervision_status_check'
  ) THEN
    ALTER TABLE work_outputs
      ADD CONSTRAINT work_outputs_supervision_status_check
      CHECK (supervision_status IN (
        'pending_review', 'approved', 'rejected', 'revision_requested', 'archived'
      ));
  END IF;
EXCEPTION
  WHEN others THEN
    RAISE NOTICE 'Could not add supervision_status constraint: %', SQLERRM;
END $$;

-- Add check constraint for confidence
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'work_outputs_confidence_check'
  ) THEN
    ALTER TABLE work_outputs
      ADD CONSTRAINT work_outputs_confidence_check
      CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1));
  END IF;
EXCEPTION
  WHEN others THEN
    RAISE NOTICE 'Could not add confidence constraint: %', SQLERRM;
END $$;

-- ============================================================================
-- STEP 3: Create new indexes
-- ============================================================================

-- Index for basket_id queries
CREATE INDEX IF NOT EXISTS idx_work_outputs_basket
  ON work_outputs(basket_id, created_at DESC);

-- Index for supervision_status filtering
CREATE INDEX IF NOT EXISTS idx_work_outputs_supervision_status
  ON work_outputs(supervision_status, created_at DESC)
  WHERE supervision_status = 'pending_review';

-- Index for agent_type filtering
CREATE INDEX IF NOT EXISTS idx_work_outputs_agent_type
  ON work_outputs(agent_type, basket_id);

-- Index for provenance queries
CREATE INDEX IF NOT EXISTS idx_work_outputs_provenance
  ON work_outputs USING gin(source_context_ids)
  WHERE source_context_ids IS NOT NULL;

-- Index for metadata queries
CREATE INDEX IF NOT EXISTS idx_work_outputs_metadata
  ON work_outputs USING gin(metadata)
  WHERE metadata IS NOT NULL AND metadata != '{}';

-- Index for tool call tracing
CREATE INDEX IF NOT EXISTS idx_work_outputs_tool_call
  ON work_outputs(tool_call_id)
  WHERE tool_call_id IS NOT NULL;

-- ============================================================================
-- STEP 4: Update RLS policies for basket-scoped access
-- ============================================================================

-- Drop old workspace-scoped policies
DROP POLICY IF EXISTS "Users can view work_artifacts in their workspace" ON work_outputs;
DROP POLICY IF EXISTS "Users can create work_artifacts in their workspace" ON work_outputs;
DROP POLICY IF EXISTS "Users can update work_artifacts in their workspace" ON work_outputs;
DROP POLICY IF EXISTS "Users can delete work_artifacts in their workspace" ON work_outputs;

-- Create new basket-scoped policies (only if basket_id exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'basket_id'
  ) THEN
    -- Users can view outputs in their workspace baskets
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view outputs in their workspace' AND tablename = 'work_outputs') THEN
      EXECUTE '
        CREATE POLICY "Users can view outputs in their workspace"
          ON work_outputs FOR SELECT
          TO authenticated
          USING (
            basket_id IN (
              SELECT b.id FROM baskets b
              JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
              WHERE wm.user_id = auth.uid()
            )
          )
      ';
    END IF;

    -- Users can create outputs
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can create outputs in their workspace' AND tablename = 'work_outputs') THEN
      EXECUTE '
        CREATE POLICY "Users can create outputs in their workspace"
          ON work_outputs FOR INSERT
          TO authenticated
          WITH CHECK (
            basket_id IN (
              SELECT b.id FROM baskets b
              JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
              WHERE wm.user_id = auth.uid()
            )
          )
      ';
    END IF;

    -- Users can update outputs
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can supervise outputs in their workspace' AND tablename = 'work_outputs') THEN
      EXECUTE '
        CREATE POLICY "Users can supervise outputs in their workspace"
          ON work_outputs FOR UPDATE
          TO authenticated
          USING (
            basket_id IN (
              SELECT b.id FROM baskets b
              JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
              WHERE wm.user_id = auth.uid()
            )
          )
          WITH CHECK (
            basket_id IN (
              SELECT b.id FROM baskets b
              JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
              WHERE wm.user_id = auth.uid()
            )
          )
      ';
    END IF;

    -- Users can delete outputs
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can delete outputs from their workspace' AND tablename = 'work_outputs') THEN
      EXECUTE '
        CREATE POLICY "Users can delete outputs from their workspace"
          ON work_outputs FOR DELETE
          TO authenticated
          USING (
            basket_id IN (
              SELECT b.id FROM baskets b
              JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
              WHERE wm.user_id = auth.uid()
            )
          )
      ';
    END IF;
  END IF;
END $$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  new_columns_count INTEGER;
  has_basket_id BOOLEAN;
  has_supervision_status BOOLEAN;
  policy_count INTEGER;
BEGIN
  -- Count new columns
  SELECT COUNT(*) INTO new_columns_count
  FROM information_schema.columns
  WHERE table_name = 'work_outputs'
    AND column_name IN ('basket_id', 'agent_type', 'title', 'body', 'confidence',
                        'source_context_ids', 'tool_call_id', 'supervision_status',
                        'reviewer_notes', 'reviewed_by', 'metadata', 'updated_at');

  -- Check specific columns
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'basket_id'
  ) INTO has_basket_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'supervision_status'
  ) INTO has_supervision_status;

  -- Count policies
  SELECT COUNT(*) INTO policy_count
  FROM pg_policies
  WHERE tablename = 'work_outputs';

  RAISE NOTICE '✅ Work Outputs ALTER Migration Complete:';
  RAISE NOTICE '  - New columns added: %', new_columns_count;
  RAISE NOTICE '  - Has basket_id: %', has_basket_id;
  RAISE NOTICE '  - Has supervision_status: %', has_supervision_status;
  RAISE NOTICE '  - RLS policies: %', policy_count;

  IF new_columns_count < 10 THEN
    RAISE WARNING 'Some columns may not have been added (expected 12, got %)', new_columns_count;
  END IF;

  IF NOT has_basket_id THEN
    RAISE WARNING 'basket_id column not added - basket-scoped access will not work';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Schema updated. Old columns (content, status, etc.) preserved for backward compatibility.';
END $$;
