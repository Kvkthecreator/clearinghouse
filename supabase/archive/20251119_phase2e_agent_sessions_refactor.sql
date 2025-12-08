-- Migration: Phase 2e - Agent Sessions & Work Orchestration Refactor
-- Purpose: Clean separation of agent sessions vs work execution
-- Date: 2025-11-19
-- Strategy: Aggressive drop & recreate (pre-launch, no user data)

-- ============================================================================
-- STEP 1: Drop existing work orchestration tables
-- ============================================================================

-- Drop in reverse dependency order
DROP TABLE IF EXISTS work_context_mutations CASCADE;
DROP TABLE IF EXISTS work_iterations CASCADE;
DROP TABLE IF EXISTS work_checkpoints CASCADE;
DROP TABLE IF EXISTS work_artifacts CASCADE;  -- Now work_outputs in substrate-API
DROP TABLE IF EXISTS work_sessions CASCADE;

-- ============================================================================
-- STEP 2: Create agent_sessions (persistent Claude SDK sessions)
-- ============================================================================

CREATE TABLE agent_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identity & Scope
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,
  agent_type TEXT NOT NULL CHECK (agent_type IN ('research', 'content', 'reporting')),

  -- Claude SDK Integration
  sdk_session_id TEXT,  -- Claude SDK session identifier for resume
  conversation_history JSONB DEFAULT '[]'::jsonb,

  -- Session State
  state JSONB DEFAULT '{}'::jsonb,  -- Agent-specific state
  last_active_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  created_by_user_id UUID REFERENCES auth.users(id),
  metadata JSONB DEFAULT '{}'::jsonb NOT NULL,

  -- Constraints
  UNIQUE(basket_id, agent_type)  -- ONE session per agent type per basket
);

-- Indexes
CREATE INDEX idx_agent_sessions_basket ON agent_sessions(basket_id);
CREATE INDEX idx_agent_sessions_workspace ON agent_sessions(workspace_id);
CREATE INDEX idx_agent_sessions_type ON agent_sessions(agent_type);
CREATE INDEX idx_agent_sessions_active ON agent_sessions(last_active_at DESC);
CREATE INDEX idx_agent_sessions_sdk ON agent_sessions(sdk_session_id) WHERE sdk_session_id IS NOT NULL;

-- ============================================================================
-- STEP 3: Create work_requests (user asks)
-- ============================================================================

CREATE TABLE work_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identity & Scope
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,
  agent_session_id UUID REFERENCES agent_sessions(id) ON DELETE SET NULL,

  -- Request Details
  requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
  request_type TEXT NOT NULL,  -- deep_dive, monitor, create_content, generate_report
  task_intent TEXT NOT NULL,   -- User's description of what they want
  parameters JSONB DEFAULT '{}'::jsonb,

  -- Priority & Scheduling
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  requested_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb NOT NULL
);

-- Indexes
CREATE INDEX idx_work_requests_workspace ON work_requests(workspace_id);
CREATE INDEX idx_work_requests_basket ON work_requests(basket_id);
CREATE INDEX idx_work_requests_session ON work_requests(agent_session_id) WHERE agent_session_id IS NOT NULL;
CREATE INDEX idx_work_requests_user ON work_requests(requested_by_user_id);
CREATE INDEX idx_work_requests_requested_at ON work_requests(requested_at DESC);

-- ============================================================================
-- STEP 4: Create work_tickets (execution tracking)
-- ============================================================================

CREATE TABLE work_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Relationships
  work_request_id UUID NOT NULL REFERENCES work_requests(id) ON DELETE CASCADE,
  agent_session_id UUID REFERENCES agent_sessions(id) ON DELETE SET NULL,

  -- Denormalized for queries
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,
  agent_type TEXT NOT NULL,

  -- Execution State
  status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN (
    'pending',           -- Waiting to start
    'running',           -- Currently executing
    'completed',         -- Successfully finished
    'failed',            -- Execution failed
    'cancelled'          -- User cancelled
  )),

  -- Execution Details
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,

  -- Work Trail
  reasoning_trail JSONB[] DEFAULT '{}',
  context_snapshot JSONB,

  -- Outcomes
  outputs_count INTEGER DEFAULT 0,
  checkpoints_count INTEGER DEFAULT 0,
  iterations_count INTEGER DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb NOT NULL
);

-- Indexes
CREATE INDEX idx_work_tickets_request ON work_tickets(work_request_id);
CREATE INDEX idx_work_tickets_session ON work_tickets(agent_session_id) WHERE agent_session_id IS NOT NULL;
CREATE INDEX idx_work_tickets_workspace ON work_tickets(workspace_id);
CREATE INDEX idx_work_tickets_basket ON work_tickets(basket_id, created_at DESC);
CREATE INDEX idx_work_tickets_status ON work_tickets(status) WHERE status IN ('pending', 'running');
CREATE INDEX idx_work_tickets_agent_type ON work_tickets(agent_type);

-- ============================================================================
-- STEP 5: Create work_checkpoints (multi-stage approval)
-- ============================================================================

CREATE TABLE work_checkpoints (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Relationship
  work_ticket_id UUID NOT NULL REFERENCES work_tickets(id) ON DELETE CASCADE,

  -- Checkpoint Identity
  checkpoint_sequence INTEGER NOT NULL,
  checkpoint_type TEXT NOT NULL CHECK (checkpoint_type IN (
    'plan_approval',
    'mid_work_review',
    'artifact_review',
    'final_approval'
  )),

  -- Review Scope
  review_scope TEXT NOT NULL,
  outputs_at_checkpoint UUID[],

  -- Agent Submission
  agent_confidence NUMERIC CHECK (agent_confidence BETWEEN 0 AND 1),
  agent_reasoning TEXT,
  agent_summary TEXT,

  -- Status
  status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN (
    'pending',
    'approved',
    'rejected',
    'skipped'
  )),

  -- User Review
  reviewed_by_user_id UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,
  user_decision TEXT CHECK (user_decision IN ('approve', 'reject', 'request_changes')),
  user_feedback TEXT,
  changes_requested JSONB,

  -- Risk
  risk_level TEXT CHECK (risk_level IN ('low', 'medium', 'high')),
  risk_factors JSONB,

  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  UNIQUE(work_ticket_id, checkpoint_sequence)
);

-- Indexes
CREATE INDEX idx_work_checkpoints_ticket ON work_checkpoints(work_ticket_id);
CREATE INDEX idx_work_checkpoints_status ON work_checkpoints(status) WHERE status = 'pending';

-- ============================================================================
-- STEP 6: Create work_iterations (revision loops)
-- ============================================================================

CREATE TABLE work_iterations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Relationship
  work_ticket_id UUID NOT NULL REFERENCES work_tickets(id) ON DELETE CASCADE,

  -- Iteration Identity
  iteration_number INTEGER NOT NULL,

  -- Trigger
  triggered_by TEXT NOT NULL CHECK (triggered_by IN (
    'checkpoint_rejection',
    'user_feedback',
    'agent_self_correction',
    'context_staleness'
  )),

  user_feedback_text TEXT,
  changes_requested JSONB,

  -- Agent Response
  agent_interpretation TEXT,
  revised_approach TEXT,
  outputs_revised UUID[],

  -- Resolution
  resolved BOOLEAN DEFAULT false NOT NULL,
  resolved_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  UNIQUE(work_ticket_id, iteration_number)
);

-- Indexes
CREATE INDEX idx_work_iterations_ticket ON work_iterations(work_ticket_id);
CREATE INDEX idx_work_iterations_resolved ON work_iterations(resolved) WHERE NOT resolved;

-- ============================================================================
-- STEP 7: Grants
-- ============================================================================

GRANT ALL ON TABLE agent_sessions TO service_role;
GRANT ALL ON TABLE work_requests TO service_role;
GRANT ALL ON TABLE work_tickets TO service_role;
GRANT ALL ON TABLE work_checkpoints TO service_role;
GRANT ALL ON TABLE work_iterations TO service_role;

GRANT SELECT, INSERT, UPDATE ON TABLE agent_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE work_requests TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE work_tickets TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE work_checkpoints TO authenticated;
GRANT SELECT, INSERT ON TABLE work_iterations TO authenticated;

-- ============================================================================
-- STEP 8: RLS Policies
-- ============================================================================

ALTER TABLE agent_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_iterations ENABLE ROW LEVEL SECURITY;

-- Agent Sessions
CREATE POLICY "Users can view agent sessions in their workspaces"
  ON agent_sessions FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can create agent sessions in their workspaces"
  ON agent_sessions FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ) AND created_by_user_id = auth.uid());

CREATE POLICY "Users can update agent sessions in their workspaces"
  ON agent_sessions FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

-- Work Requests
CREATE POLICY "Users can view work requests in their workspaces"
  ON work_requests FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can create work requests in their workspaces"
  ON work_requests FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ) AND requested_by_user_id = auth.uid());

-- Work Tickets
CREATE POLICY "Users can view work tickets in their workspaces"
  ON work_tickets FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can create work tickets in their workspaces"
  ON work_tickets FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can update work tickets in their workspaces"
  ON work_tickets FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
  ));

-- Work Checkpoints
CREATE POLICY "Users can view checkpoints in their workspace tickets"
  ON work_checkpoints FOR SELECT
  USING (work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  ));

CREATE POLICY "Users can create checkpoints in their workspace tickets"
  ON work_checkpoints FOR INSERT
  WITH CHECK (work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  ));

CREATE POLICY "Users can update checkpoints in their workspace tickets"
  ON work_checkpoints FOR UPDATE
  USING (work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  ));

-- Work Iterations
CREATE POLICY "Users can view iterations in their workspace tickets"
  ON work_iterations FOR SELECT
  USING (work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  ));

CREATE POLICY "Users can create iterations in their workspace tickets"
  ON work_iterations FOR INSERT
  WITH CHECK (work_ticket_id IN (
    SELECT id FROM work_tickets WHERE workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  ));

-- ============================================================================
-- STEP 9: Triggers & Functions
-- ============================================================================

-- Update work_tickets updated_at timestamp
CREATE TRIGGER trigger_update_work_tickets_timestamp
  BEFORE UPDATE ON work_tickets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Update agent_sessions last_active_at on work_ticket creation
CREATE OR REPLACE FUNCTION update_agent_session_activity()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.agent_session_id IS NOT NULL THEN
    UPDATE agent_sessions
    SET last_active_at = now()
    WHERE id = NEW.agent_session_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_agent_session_activity
  AFTER INSERT ON work_tickets
  FOR EACH ROW
  EXECUTE FUNCTION update_agent_session_activity();

-- Increment outputs_count on work_tickets when work_outputs created
-- (work_outputs table is in substrate-API, so this trigger will be added there)

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  sessions_count INTEGER;
  requests_count INTEGER;
  tickets_count INTEGER;
  checkpoints_count INTEGER;
  iterations_count INTEGER;
BEGIN
  -- Count tables
  SELECT COUNT(*) INTO sessions_count FROM information_schema.tables WHERE table_name = 'agent_sessions';
  SELECT COUNT(*) INTO requests_count FROM information_schema.tables WHERE table_name = 'work_requests';
  SELECT COUNT(*) INTO tickets_count FROM information_schema.tables WHERE table_name = 'work_tickets';
  SELECT COUNT(*) INTO checkpoints_count FROM information_schema.tables WHERE table_name = 'work_checkpoints';
  SELECT COUNT(*) INTO iterations_count FROM information_schema.tables WHERE table_name = 'work_iterations';

  RAISE NOTICE '✅ Phase 2e Migration Complete:';
  RAISE NOTICE '  - agent_sessions: %', sessions_count;
  RAISE NOTICE '  - work_requests: %', requests_count;
  RAISE NOTICE '  - work_tickets: %', tickets_count;
  RAISE NOTICE '  - work_checkpoints: %', checkpoints_count;
  RAISE NOTICE '  - work_iterations: %', iterations_count;

  IF sessions_count = 0 OR requests_count = 0 OR tickets_count = 0 THEN
    RAISE WARNING 'Some tables were not created!';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Clean schema ready for Phase 2e agent session architecture.';
  RAISE NOTICE '   Next: Update code to use new tables.';
END $$;
