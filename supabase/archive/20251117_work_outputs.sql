-- Migration: Work Outputs Table for Agent Supervision
-- Date: 2025-11-17
-- Purpose: Create work_outputs table to store agent-generated deliverables pending user review
--
-- Architecture: Work outputs live in substrate-API DB (NOT work-platform)
-- Rationale: Outputs are basket-scoped context that can feed back into substrate
-- Pattern: Follows reference_assets migration structure
--
-- Key Design Decisions:
-- 1. Cross-DB work_session_id reference (NOT FK) - enforced in app code
-- 2. Supervision lifecycle independent from substrate governance
-- 3. Structured output content via JSONB (parsed from Claude tool_use)
-- 4. Full provenance tracking (source_context_ids → which blocks were used)

-- ============================================================================
-- STEP 1: Create work_outputs table
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_outputs (
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
  -- These columns support "Request for Merge" pattern when ready
  substrate_proposal_id uuid,  -- If output becomes substrate proposal
  merged_to_substrate_at timestamptz,  -- When approved output merged to blocks

  -- Constraints
  CONSTRAINT body_not_empty CHECK (body != '{}'::jsonb),
  CONSTRAINT title_not_empty CHECK (length(trim(title)) > 0)
);

-- ============================================================================
-- STEP 2: Create indexes for common query patterns
-- ============================================================================

-- Primary query: List outputs by basket (dashboard view)
CREATE INDEX IF NOT EXISTS idx_work_outputs_basket
  ON work_outputs(basket_id, created_at DESC);

-- Filter by work session (agent execution view)
CREATE INDEX IF NOT EXISTS idx_work_outputs_session
  ON work_outputs(work_session_id, created_at DESC);

-- Filter by supervision status (review queue)
CREATE INDEX IF NOT EXISTS idx_work_outputs_status
  ON work_outputs(supervision_status, created_at DESC)
  WHERE supervision_status = 'pending_review';

-- Filter by agent type (agent-specific views)
CREATE INDEX IF NOT EXISTS idx_work_outputs_agent_type
  ON work_outputs(agent_type, basket_id);

-- Filter by output type (type-specific analysis)
CREATE INDEX IF NOT EXISTS idx_work_outputs_type
  ON work_outputs(output_type, basket_id);

-- Provenance queries (which outputs used which blocks)
CREATE INDEX IF NOT EXISTS idx_work_outputs_provenance
  ON work_outputs USING gin(source_context_ids);

-- Metadata queries (arbitrary metadata filtering)
CREATE INDEX IF NOT EXISTS idx_work_outputs_metadata
  ON work_outputs USING gin(metadata);

-- Tool call tracing (Claude API debugging)
CREATE INDEX IF NOT EXISTS idx_work_outputs_tool_call
  ON work_outputs(tool_call_id)
  WHERE tool_call_id IS NOT NULL;

-- ============================================================================
-- STEP 3: Create output_type_catalog (dynamic, admin-managed)
-- ============================================================================

CREATE TABLE IF NOT EXISTS output_type_catalog (
  output_type text PRIMARY KEY,
  display_name text NOT NULL,
  description text,

  -- Which agent types can produce this output type
  allowed_agent_types text[],

  -- Substrate integration policy
  can_merge_to_substrate boolean DEFAULT false NOT NULL,
  merge_target text CHECK (merge_target IN ('block', 'document', 'none')),

  -- Lifecycle
  is_active boolean DEFAULT true NOT NULL,
  deprecated_at timestamptz,

  -- Audit
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  notes text
);

-- Seed initial output types
INSERT INTO output_type_catalog (output_type, display_name, description, allowed_agent_types, can_merge_to_substrate, merge_target) VALUES
  (
    'finding',
    'Research Finding',
    'Factual discovery from research (competitor move, market signal)',
    ARRAY['research'],
    true,
    'block'
  ),
  (
    'recommendation',
    'Strategic Recommendation',
    'Actionable recommendation based on analysis',
    ARRAY['research', 'content', 'reporting'],
    true,
    'block'
  ),
  (
    'insight',
    'Pattern Insight',
    'Non-actionable insight or observation',
    ARRAY['research', 'reporting'],
    false,
    'none'
  ),
  (
    'draft_content',
    'Content Draft',
    'Social media post, blog draft, or marketing copy',
    ARRAY['content'],
    false,
    'none'
  ),
  (
    'report_section',
    'Report Section',
    'Section of generated report or analysis',
    ARRAY['reporting'],
    true,
    'document'
  ),
  (
    'data_analysis',
    'Data Analysis',
    'Structured analysis of data with visualizations',
    ARRAY['reporting', 'research'],
    false,
    'none'
  )
ON CONFLICT (output_type) DO NOTHING;

-- Indexes for catalog
CREATE INDEX IF NOT EXISTS idx_output_type_catalog_active
  ON output_type_catalog(is_active)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_output_type_catalog_mergeable
  ON output_type_catalog(can_merge_to_substrate)
  WHERE can_merge_to_substrate = true;

COMMENT ON TABLE output_type_catalog IS 'Dynamic catalog of work output types. Defines supervision policies.';
COMMENT ON COLUMN output_type_catalog.can_merge_to_substrate IS 'Whether approved outputs of this type can become substrate entities';
COMMENT ON COLUMN output_type_catalog.merge_target IS 'Target substrate primitive (block or document) when merged';

-- ============================================================================
-- STEP 4: RLS Policies for work_outputs
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
-- Note: Most inserts happen via service role, but allow authenticated for direct submission
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
-- STEP 5: RLS Policies for output_type_catalog
-- ============================================================================

ALTER TABLE output_type_catalog ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read active output types
CREATE POLICY "Users can read active output types"
  ON output_type_catalog FOR SELECT
  TO authenticated
  USING (is_active = true AND deprecated_at IS NULL);

-- Service role has full access
CREATE POLICY "Service role has full access to output_type_catalog"
  ON output_type_catalog
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- STEP 6: GRANTS (critical for service-to-service and user access)
-- ============================================================================

-- Service role needs full access for agent execution
GRANT ALL ON work_outputs TO service_role;
GRANT ALL ON output_type_catalog TO service_role;

-- Authenticated users need CRUD on outputs (supervision flow)
GRANT SELECT, INSERT, UPDATE, DELETE ON work_outputs TO authenticated;
GRANT SELECT ON output_type_catalog TO authenticated;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================================================
-- STEP 7: Trigger for auto-updating updated_at timestamp
-- ============================================================================

-- Apply to work_outputs (uses existing update_updated_at_column function)
DROP TRIGGER IF EXISTS trg_update_work_outputs_updated_at ON work_outputs;
CREATE TRIGGER trg_update_work_outputs_updated_at
  BEFORE UPDATE ON work_outputs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Apply to output_type_catalog
DROP TRIGGER IF EXISTS trg_update_output_type_catalog_updated_at ON output_type_catalog;
CREATE TRIGGER trg_update_output_type_catalog_updated_at
  BEFORE UPDATE ON output_type_catalog
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- STEP 8: Helper functions for work output operations
-- ============================================================================

-- Function to approve output and track reviewer
CREATE OR REPLACE FUNCTION approve_work_output(
  p_output_id uuid,
  p_reviewer_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  UPDATE work_outputs
  SET
    supervision_status = 'approved',
    reviewed_by = p_reviewer_id,
    reviewed_at = now(),
    reviewer_notes = p_notes
  WHERE id = p_output_id
    AND supervision_status = 'pending_review';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Output not found or not pending review';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reject output
CREATE OR REPLACE FUNCTION reject_work_output(
  p_output_id uuid,
  p_reviewer_id uuid,
  p_notes text
)
RETURNS void AS $$
BEGIN
  IF p_notes IS NULL OR length(trim(p_notes)) = 0 THEN
    RAISE EXCEPTION 'Rejection notes are required';
  END IF;

  UPDATE work_outputs
  SET
    supervision_status = 'rejected',
    reviewed_by = p_reviewer_id,
    reviewed_at = now(),
    reviewer_notes = p_notes
  WHERE id = p_output_id
    AND supervision_status IN ('pending_review', 'revision_requested');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Output not found or not reviewable';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to request revision
CREATE OR REPLACE FUNCTION request_output_revision(
  p_output_id uuid,
  p_reviewer_id uuid,
  p_feedback text
)
RETURNS void AS $$
BEGIN
  IF p_feedback IS NULL OR length(trim(p_feedback)) = 0 THEN
    RAISE EXCEPTION 'Revision feedback is required';
  END IF;

  UPDATE work_outputs
  SET
    supervision_status = 'revision_requested',
    reviewed_by = p_reviewer_id,
    reviewed_at = now(),
    reviewer_notes = p_feedback
  WHERE id = p_output_id
    AND supervision_status = 'pending_review';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Output not found or not pending review';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get supervision statistics for a basket
CREATE OR REPLACE FUNCTION get_supervision_stats(p_basket_id uuid)
RETURNS TABLE(
  total_outputs bigint,
  pending_review bigint,
  approved bigint,
  rejected bigint,
  revision_requested bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(*)::bigint as total_outputs,
    COUNT(*) FILTER (WHERE supervision_status = 'pending_review')::bigint as pending_review,
    COUNT(*) FILTER (WHERE supervision_status = 'approved')::bigint as approved,
    COUNT(*) FILTER (WHERE supervision_status = 'rejected')::bigint as rejected,
    COUNT(*) FILTER (WHERE supervision_status = 'revision_requested')::bigint as revision_requested
  FROM work_outputs
  WHERE basket_id = p_basket_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION approve_work_output IS 'Approve a work output - marks as approved with reviewer info';
COMMENT ON FUNCTION reject_work_output IS 'Reject a work output - requires notes explaining rejection';
COMMENT ON FUNCTION request_output_revision IS 'Request revision - requires feedback for agent to act on';
COMMENT ON FUNCTION get_supervision_stats IS 'Get counts of outputs by supervision status for dashboard';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  outputs_table_exists BOOLEAN;
  catalog_count INTEGER;
  output_policies INTEGER;
  catalog_policies INTEGER;
  functions_count INTEGER;
BEGIN
  -- Check work_outputs table
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'work_outputs'
  ) INTO outputs_table_exists;

  -- Check output_type_catalog
  SELECT COUNT(*) INTO catalog_count FROM output_type_catalog;

  -- Count RLS policies
  SELECT COUNT(*) INTO output_policies
  FROM pg_policies
  WHERE tablename = 'work_outputs';

  SELECT COUNT(*) INTO catalog_policies
  FROM pg_policies
  WHERE tablename = 'output_type_catalog';

  -- Count helper functions
  SELECT COUNT(*) INTO functions_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname IN ('approve_work_output', 'reject_work_output', 'request_output_revision', 'get_supervision_stats');

  RAISE NOTICE '✅ Work Outputs Migration Complete:';
  RAISE NOTICE '  - work_outputs table: % (created)', outputs_table_exists;
  RAISE NOTICE '  - output_type_catalog: % types seeded', catalog_count;
  RAISE NOTICE '  - work_outputs RLS policies: %', output_policies;
  RAISE NOTICE '  - output_type_catalog RLS policies: %', catalog_policies;
  RAISE NOTICE '  - Helper functions: %', functions_count;

  -- Validation checks
  IF NOT outputs_table_exists THEN
    RAISE WARNING 'work_outputs table not created';
  END IF;

  IF catalog_count < 6 THEN
    RAISE WARNING 'output_type_catalog incomplete (expected 6+ types, got %)', catalog_count;
  END IF;

  IF output_policies < 5 THEN
    RAISE WARNING 'work_outputs RLS policies incomplete (expected 5+, got %)', output_policies;
  END IF;

  IF functions_count < 4 THEN
    RAISE WARNING 'Helper functions incomplete (expected 4, got %)', functions_count;
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Next Steps:';
  RAISE NOTICE '  1. Run migration: psql "$PG_DUMP_URL" -f supabase/migrations/20251117_work_outputs.sql';
  RAISE NOTICE '  2. Implement tool-use schema in yarnnn_agents';
  RAISE NOTICE '  3. Wire BFF integration (substrate_client + routes)';
  RAISE NOTICE '  4. Build supervision API endpoints';
END $$;
