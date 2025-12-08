-- Create agent processing queue for async intelligence
-- This enables the core async intelligence framework per YARNNN canon

-- Processing states enum
CREATE TYPE processing_state AS ENUM (
  'pending',      -- Waiting for agent
  'claimed',      -- Agent has claimed
  'processing',   -- Actively processing  
  'completed',    -- Successfully processed
  'failed'        -- Failed (will retry)
);

-- Agent processing queue table
CREATE TABLE agent_processing_queue (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  dump_id uuid REFERENCES raw_dumps(id) NOT NULL,
  basket_id uuid REFERENCES baskets(id) NOT NULL,
  workspace_id uuid REFERENCES workspaces(id) NOT NULL,
  processing_state processing_state DEFAULT 'pending',
  claimed_at timestamp,
  claimed_by text,
  completed_at timestamp,
  attempts int DEFAULT 0,
  error_message text,
  created_at timestamp DEFAULT now(),
  
  -- Ensure no duplicate queue entries for same dump
  UNIQUE(dump_id)
);

-- Indexes for efficient polling and monitoring
CREATE INDEX idx_queue_state_created ON agent_processing_queue(processing_state, created_at);
CREATE INDEX idx_queue_workspace ON agent_processing_queue(workspace_id, processing_state);
CREATE INDEX idx_queue_claimed ON agent_processing_queue(claimed_by, processing_state) WHERE claimed_by IS NOT NULL;

-- RLS policies to maintain workspace isolation
ALTER TABLE agent_processing_queue ENABLE ROW LEVEL SECURITY;

-- Authenticated users can view queue entries for their workspace
CREATE POLICY "Users can view queue in their workspace"
ON agent_processing_queue FOR SELECT TO authenticated
USING (
  workspace_id IN (
    SELECT workspace_id FROM workspace_memberships 
    WHERE user_id = auth.uid()
  )
);

-- Service role can manage all queue entries (for agents)
CREATE POLICY "Service role can manage queue"
ON agent_processing_queue FOR ALL TO service_role
USING (true);

-- Grant permissions
GRANT SELECT ON agent_processing_queue TO authenticated;
GRANT ALL ON agent_processing_queue TO service_role;

COMMENT ON TABLE agent_processing_queue IS 'Queue for async agent processing of raw dumps per YARNNN canon';
COMMENT ON COLUMN agent_processing_queue.processing_state IS 'Current state in processing pipeline';
COMMENT ON COLUMN agent_processing_queue.claimed_by IS 'Worker ID that claimed this job';
COMMENT ON COLUMN agent_processing_queue.attempts IS 'Number of processing attempts (for retry logic)';