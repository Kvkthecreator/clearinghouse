-- Migration: Recreate work_outputs table with complete schema
-- Date: 2025-11-17
-- Purpose: Drop old work_outputs schema and recreate with full Phase 1 implementation
--
-- AGGRESSIVE APPROACH: Pre-launch, so we drop and recreate to ensure clean schema

-- ============================================================================
-- STEP 1: Drop existing work_outputs and recreate
-- ============================================================================

-- Drop old table (cascades policies, indexes, triggers)
DROP TABLE IF EXISTS work_outputs CASCADE;

-- Create new table with complete schema
CREATE TABLE work_outputs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  basket_id uuid NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,

  -- Cross-DB reference (not FK, work_sessions in same Supabase but different domain)
  work_session_id uuid NOT NULL,

  -- Output classification
  output_type text NOT NULL,  -- finding, recommendation, insight, draft_content, etc.
  agent_type text NOT NULL,   -- research, content, reporting

  -- Content (structured via tool_use pattern)
  title text NOT NULL,
  body jsonb NOT NULL,  -- Structured output from agent's emit_work_output tool
  confidence float CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),

  -- Provenance tracking
  source_context_ids uuid[],  -- Block IDs used to generate this output
  tool_call_id text,          -- Claude's tool_use id for traceability

  -- Work Supervision lifecycle (independent from substrate governance)
  supervision_status text NOT NULL DEFAULT 'pending_review'
    CHECK (supervision_status IN (
      'pending_review',      -- Awaiting user review
      'approved',            -- User approved
      'rejected',            -- User rejected
      'revision_requested',  -- User wants changes
      'archived'             -- No longer relevant
    )),
  reviewer_notes text,
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),

  -- Metadata and timestamps
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  metadata jsonb DEFAULT '{}' NOT NULL,

  -- Future substrate integration (Phase N)
  substrate_proposal_id uuid,  -- If output becomes substrate proposal
  merged_to_substrate_at timestamptz,  -- When approved output merged to blocks

  -- Constraints
  CONSTRAINT body_not_empty CHECK (body != '{}'::jsonb),
  CONSTRAINT title_not_empty CHECK (length(trim(title)) > 0)
);

-- ============================================================================
-- STEP 2: Create comprehensive indexes
-- ============================================================================

-- Primary query: List outputs by basket (dashboard view)
CREATE INDEX idx_work_outputs_basket
  ON work_outputs(basket_id, created_at DESC);

-- Filter by work session (agent execution view)
CREATE INDEX idx_work_outputs_session
  ON work_outputs(work_session_id, created_at DESC);

-- Filter by supervision status (review queue) - partial for efficiency
CREATE INDEX idx_work_outputs_pending
  ON work_outputs(supervision_status, created_at DESC)
  WHERE supervision_status = 'pending_review';

-- Filter by agent type (agent-specific views)
CREATE INDEX idx_work_outputs_agent_type
  ON work_outputs(agent_type, basket_id);

-- Filter by output type (type-specific analysis)
CREATE INDEX idx_work_outputs_type
  ON work_outputs(output_type, basket_id);

-- Provenance queries (which outputs used which blocks)
CREATE INDEX idx_work_outputs_provenance
  ON work_outputs USING gin(source_context_ids);

-- Metadata queries (arbitrary metadata filtering)
CREATE INDEX idx_work_outputs_metadata
  ON work_outputs USING gin(metadata);

-- Tool call tracing (Claude API debugging)
CREATE INDEX idx_work_outputs_tool_call
  ON work_outputs(tool_call_id)
  WHERE tool_call_id IS NOT NULL;

-- ============================================================================
-- STEP 3: Enable RLS and create policies
-- ============================================================================

ALTER TABLE work_outputs ENABLE ROW LEVEL SECURITY;

-- Users can view outputs in their workspace baskets
CREATE POLICY "Users can view outputs in their workspace"
  ON work_outputs FOR SELECT
  TO authenticated
  USING (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Users can create outputs (agent execution inserts via service role)
CREATE POLICY "Users can create outputs in their workspace"
  ON work_outputs FOR INSERT
  TO authenticated
  WITH CHECK (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Users can update outputs (for supervision actions)
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
  );

-- Users can delete outputs (cleanup, archive)
CREATE POLICY "Users can delete outputs from their workspace"
  ON work_outputs FOR DELETE
  TO authenticated
  USING (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Service role has full access (for agent execution)
CREATE POLICY "Service role has full access to work_outputs"
  ON work_outputs
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- STEP 4: GRANTS (critical for service-to-service and user access)
-- ============================================================================

-- Service role needs full access for agent execution
GRANT ALL ON work_outputs TO service_role;

-- Authenticated users need CRUD on outputs (supervision flow)
GRANT SELECT, INSERT, UPDATE, DELETE ON work_outputs TO authenticated;

-- Grant sequence permissions (for gen_random_uuid)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================================================
-- STEP 5: Trigger for auto-updating updated_at timestamp
-- ============================================================================

-- Apply to work_outputs (uses existing update_updated_at_column function)
DROP TRIGGER IF EXISTS trg_update_work_outputs_updated_at ON work_outputs;
CREATE TRIGGER trg_update_work_outputs_updated_at
  BEFORE UPDATE ON work_outputs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  column_count INTEGER;
  index_count INTEGER;
  policy_count INTEGER;
  has_rls BOOLEAN;
BEGIN
  -- Count columns
  SELECT COUNT(*) INTO column_count
  FROM information_schema.columns
  WHERE table_name = 'work_outputs' AND table_schema = 'public';

  -- Count indexes
  SELECT COUNT(*) INTO index_count
  FROM pg_indexes
  WHERE tablename = 'work_outputs' AND schemaname = 'public';

  -- Count policies
  SELECT COUNT(*) INTO policy_count
  FROM pg_policies
  WHERE tablename = 'work_outputs';

  -- Check RLS enabled
  SELECT relrowsecurity INTO has_rls
  FROM pg_class
  WHERE relname = 'work_outputs' AND relnamespace = 'public'::regnamespace;

  RAISE NOTICE '✅ Work Outputs RECREATE Migration Complete:';
  RAISE NOTICE '  - Columns: % (expected 18)', column_count;
  RAISE NOTICE '  - Indexes: % (expected 9 including PK)', index_count;
  RAISE NOTICE '  - RLS Policies: % (expected 5)', policy_count;
  RAISE NOTICE '  - RLS Enabled: %', has_rls;

  IF column_count < 18 THEN
    RAISE WARNING 'Column count mismatch (expected 18, got %)', column_count;
  END IF;

  IF policy_count < 5 THEN
    RAISE WARNING 'Policy count mismatch (expected 5, got %)', policy_count;
  END IF;

  IF NOT has_rls THEN
    RAISE WARNING 'RLS is not enabled!';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Clean schema ready for Phase 1 work output lifecycle.';
END $$;
