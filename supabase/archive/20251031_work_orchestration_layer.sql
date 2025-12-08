-- Migration: Work Orchestration Layer (Layer 2)
-- Purpose: Add work session management, artifacts, checkpoints, and unified governance
-- Date: 2025-10-31
-- Applied: Yes (2025-10-31)

-- ============================================================================
-- WORK SESSIONS: Track agent work execution
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identity & Scope
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  basket_id uuid NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,
  initiated_by_user_id uuid NOT NULL REFERENCES auth.users(id),
  executed_by_agent_id text,
  agent_session_id text,

  -- Task Context
  task_intent text NOT NULL,
  task_type text CHECK (task_type IN ('research', 'synthesis', 'analysis', 'composition', 'update')) NOT NULL,
  task_document_id uuid REFERENCES documents(id),

  -- Execution State
  status text CHECK (status IN (
    'initialized',
    'in_progress',
    'awaiting_checkpoint',
    'awaiting_final_approval',
    'approved',
    'rejected',
    'failed'
  )) DEFAULT 'initialized' NOT NULL,

  -- Configuration
  approval_strategy text CHECK (approval_strategy IN (
    'checkpoint_required',
    'final_only',
    'auto_approve_low_risk'
  )) DEFAULT 'final_only' NOT NULL,
  confidence_threshold numeric DEFAULT 0.85 CHECK (confidence_threshold BETWEEN 0 AND 1),

  -- Work Trail
  reasoning_trail jsonb[] DEFAULT '{}',
  context_snapshot jsonb,

  -- Outcomes
  artifacts_count integer DEFAULT 0,
  substrate_mutations_count integer DEFAULT 0,

  -- Timestamps
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  started_at timestamptz,
  ended_at timestamptz,

  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_work_sessions_workspace ON work_sessions(workspace_id);
CREATE INDEX IF NOT EXISTS idx_work_sessions_basket ON work_sessions(basket_id);
CREATE INDEX IF NOT EXISTS idx_work_sessions_status ON work_sessions(status);
CREATE INDEX IF NOT EXISTS idx_work_sessions_user ON work_sessions(initiated_by_user_id);
CREATE INDEX IF NOT EXISTS idx_work_sessions_agent ON work_sessions(executed_by_agent_id) WHERE executed_by_agent_id IS NOT NULL;

-- ============================================================================
-- WORK ARTIFACTS: Outputs of agent work
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_artifacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_session_id uuid NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
  checkpoint_id uuid,

  -- Artifact Type & Content
  artifact_type text CHECK (artifact_type IN (
    'block_proposal',
    'block_update',
    'document_creation',
    'insight',
    'external_deliverable'
  )) NOT NULL,

  content jsonb NOT NULL,

  -- Substrate Linkage
  becomes_block_id uuid REFERENCES blocks(id),
  supersedes_block_id uuid REFERENCES blocks(id),
  creates_document_id uuid REFERENCES documents(id),

  -- External Deliverable
  external_url text,
  external_type text,

  -- Agent Context
  agent_confidence numeric CHECK (agent_confidence BETWEEN 0 AND 1),
  agent_reasoning text,
  source_context_ids uuid[],

  -- Status
  status text CHECK (status IN (
    'draft',
    'pending_review',
    'approved',
    'rejected',
    'applied_to_substrate'
  )) DEFAULT 'draft' NOT NULL,

  -- Risk Assessment
  risk_level text CHECK (risk_level IN ('low', 'medium', 'high')),
  risk_factors jsonb,

  -- Review
  reviewed_by_user_id uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  review_decision text,
  review_feedback text,

  -- Timestamps
  created_at timestamptz DEFAULT now() NOT NULL,
  applied_at timestamptz,

  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_work_artifacts_session ON work_artifacts(work_session_id);
CREATE INDEX IF NOT EXISTS idx_work_artifacts_status ON work_artifacts(status);
CREATE INDEX IF NOT EXISTS idx_work_artifacts_type ON work_artifacts(artifact_type);
CREATE INDEX IF NOT EXISTS idx_work_artifacts_block ON work_artifacts(becomes_block_id) WHERE becomes_block_id IS NOT NULL;

-- ============================================================================
-- WORK CHECKPOINTS: Multi-stage approval workflow
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_checkpoints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_session_id uuid NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,

  -- Checkpoint Identity
  checkpoint_sequence integer NOT NULL,
  checkpoint_type text CHECK (checkpoint_type IN (
    'plan_approval',
    'mid_work_review',
    'artifact_review',
    'final_approval'
  )) NOT NULL,

  -- Review Scope
  review_scope text NOT NULL,
  artifacts_at_checkpoint uuid[],

  -- Agent Submission
  agent_confidence numeric CHECK (agent_confidence BETWEEN 0 AND 1),
  agent_reasoning text,
  agent_summary text,

  -- Status
  status text CHECK (status IN (
    'pending',
    'approved',
    'rejected',
    'skipped'
  )) DEFAULT 'pending' NOT NULL,

  -- User Review
  reviewed_by_user_id uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  user_decision text CHECK (user_decision IN ('approve', 'reject', 'request_changes')),
  user_feedback text,
  changes_requested jsonb,

  -- Risk
  risk_level text CHECK (risk_level IN ('low', 'medium', 'high')),
  risk_factors jsonb,

  created_at timestamptz DEFAULT now() NOT NULL,

  UNIQUE(work_session_id, checkpoint_sequence)
);

CREATE INDEX IF NOT EXISTS idx_work_checkpoints_session ON work_checkpoints(work_session_id);
CREATE INDEX IF NOT EXISTS idx_work_checkpoints_status ON work_checkpoints(status);

-- ============================================================================
-- WORK ITERATIONS: Feedback loops and revisions
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_iterations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_session_id uuid NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,

  iteration_number integer NOT NULL,

  -- Trigger
  triggered_by text CHECK (triggered_by IN (
    'checkpoint_rejection',
    'user_feedback',
    'agent_self_correction',
    'context_staleness'
  )) NOT NULL,

  user_feedback_text text,
  changes_requested jsonb,

  -- Agent Response
  agent_interpretation text,
  revised_approach text,
  artifacts_revised uuid[],

  -- Resolution
  resolved boolean DEFAULT false NOT NULL,
  resolved_at timestamptz,

  created_at timestamptz DEFAULT now() NOT NULL,

  UNIQUE(work_session_id, iteration_number)
);

CREATE INDEX IF NOT EXISTS idx_work_iterations_session ON work_iterations(work_session_id);
CREATE INDEX IF NOT EXISTS idx_work_iterations_resolved ON work_iterations(resolved);

-- ============================================================================
-- WORK CONTEXT MUTATIONS: Track substrate changes from work
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_context_mutations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_session_id uuid NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
  artifact_id uuid REFERENCES work_artifacts(id),

  mutation_type text CHECK (mutation_type IN (
    'block_created',
    'block_updated',
    'block_superseded',
    'block_locked',
    'document_created',
    'document_updated'
  )) NOT NULL,

  -- Target
  substrate_id uuid NOT NULL,
  substrate_type text CHECK (substrate_type IN ('block', 'document')) NOT NULL,

  -- Change Details
  before_state jsonb,
  after_state jsonb NOT NULL,

  -- Risk & Validation
  mutation_risk text CHECK (mutation_risk IN ('low', 'medium', 'high')),
  validation_checks jsonb,

  applied_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_work_mutations_session ON work_context_mutations(work_session_id);
CREATE INDEX IF NOT EXISTS idx_work_mutations_substrate ON work_context_mutations(substrate_id, substrate_type);
CREATE INDEX IF NOT EXISTS idx_work_mutations_artifact ON work_context_mutations(artifact_id) WHERE artifact_id IS NOT NULL;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON TABLE work_sessions TO service_role;
GRANT ALL ON TABLE work_artifacts TO service_role;
GRANT ALL ON TABLE work_checkpoints TO service_role;
GRANT ALL ON TABLE work_iterations TO service_role;
GRANT ALL ON TABLE work_context_mutations TO service_role;

GRANT SELECT, INSERT, UPDATE ON TABLE work_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE work_artifacts TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE work_checkpoints TO authenticated;
GRANT SELECT, INSERT ON TABLE work_iterations TO authenticated;
GRANT SELECT, INSERT ON TABLE work_context_mutations TO authenticated;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE work_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_iterations ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_context_mutations ENABLE ROW LEVEL SECURITY;

-- Work Sessions
CREATE POLICY "Users can view work sessions in their workspaces"
  ON work_sessions FOR SELECT
  USING (workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()));

CREATE POLICY "Users can create work sessions in their workspaces"
  ON work_sessions FOR INSERT
  WITH CHECK (workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()) AND initiated_by_user_id = auth.uid());

CREATE POLICY "Users can update their work sessions"
  ON work_sessions FOR UPDATE
  USING (workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()));

-- Work Artifacts
CREATE POLICY "Users can view artifacts in their workspace sessions"
  ON work_artifacts FOR SELECT
  USING (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

CREATE POLICY "Users can create artifacts in their workspace sessions"
  ON work_artifacts FOR INSERT
  WITH CHECK (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

CREATE POLICY "Users can update artifacts in their workspace sessions"
  ON work_artifacts FOR UPDATE
  USING (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

-- Work Checkpoints
CREATE POLICY "Users can view checkpoints in their workspace sessions"
  ON work_checkpoints FOR SELECT
  USING (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

CREATE POLICY "Users can create checkpoints in their workspace sessions"
  ON work_checkpoints FOR INSERT
  WITH CHECK (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

CREATE POLICY "Users can update checkpoints in their workspace sessions"
  ON work_checkpoints FOR UPDATE
  USING (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

-- Work Iterations
CREATE POLICY "Users can view iterations in their workspace sessions"
  ON work_iterations FOR SELECT
  USING (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

CREATE POLICY "Users can create iterations in their workspace sessions"
  ON work_iterations FOR INSERT
  WITH CHECK (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

-- Work Context Mutations
CREATE POLICY "Users can view mutations in their workspace sessions"
  ON work_context_mutations FOR SELECT
  USING (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

CREATE POLICY "Users can create mutations in their workspace sessions"
  ON work_context_mutations FOR INSERT
  WITH CHECK (work_session_id IN (SELECT id FROM work_sessions WHERE workspace_id IN (SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid())));

-- ============================================================================
-- TRIGGERS & FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION update_work_session_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_work_session_timestamp
  BEFORE UPDATE ON work_sessions
  FOR EACH ROW
  EXECUTE FUNCTION update_work_session_timestamp();

CREATE OR REPLACE FUNCTION increment_work_session_artifacts_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE work_sessions SET artifacts_count = artifacts_count + 1 WHERE id = NEW.work_session_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_artifacts_count
  AFTER INSERT ON work_artifacts
  FOR EACH ROW
  EXECUTE FUNCTION increment_work_session_artifacts_count();

CREATE OR REPLACE FUNCTION increment_work_session_mutations_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE work_sessions SET substrate_mutations_count = substrate_mutations_count + 1 WHERE id = NEW.work_session_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_mutations_count
  AFTER INSERT ON work_context_mutations
  FOR EACH ROW
  EXECUTE FUNCTION increment_work_session_mutations_count();

-- FK constraint for work_artifacts.checkpoint_id (circular dependency handled)
ALTER TABLE work_artifacts
  ADD CONSTRAINT work_artifacts_checkpoint_id_fkey
  FOREIGN KEY (checkpoint_id) REFERENCES work_checkpoints(id) ON DELETE SET NULL;
