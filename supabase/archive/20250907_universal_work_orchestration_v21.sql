-- YARNNN Canon v2.1: Universal Work Orchestration Extension
-- Extends agent_processing_queue to support all async work types per Canon v2.1

-- Add universal work orchestration columns to existing table
ALTER TABLE agent_processing_queue 
ADD COLUMN IF NOT EXISTS processing_stage text,
ADD COLUMN IF NOT EXISTS work_payload jsonb DEFAULT '{}',
ADD COLUMN IF NOT EXISTS work_result jsonb DEFAULT '{}',
ADD COLUMN IF NOT EXISTS cascade_metadata jsonb DEFAULT '{}',
ADD COLUMN IF NOT EXISTS parent_work_id uuid,
ADD COLUMN IF NOT EXISTS user_id uuid,
ADD COLUMN IF NOT EXISTS work_id text;

-- Add work_type column to support universal work orchestration
ALTER TABLE agent_processing_queue
ADD COLUMN IF NOT EXISTS work_type text DEFAULT 'P1_SUBSTRATE';

-- Update the processing_state enum to align with Canon v2.1
ALTER TYPE processing_state ADD VALUE IF NOT EXISTS 'cascading';

-- Update constraints to support all work types per Canon v2.1
ALTER TABLE agent_processing_queue 
DROP CONSTRAINT IF EXISTS valid_work_type;

ALTER TABLE agent_processing_queue 
ADD CONSTRAINT valid_work_type_v21 CHECK (work_type IN (
    'P0_CAPTURE', 'P1_SUBSTRATE', 'P2_GRAPH', 'P3_REFLECTION', 'P4_COMPOSE',
    'MANUAL_EDIT', 'PROPOSAL_REVIEW', 'TIMELINE_RESTORE'
));

-- Performance indexes for universal work orchestration
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_agent_queue_work_id ON agent_processing_queue (work_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_agent_queue_user_workspace ON agent_processing_queue (user_id, workspace_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_agent_queue_cascade ON agent_processing_queue USING gin (cascade_metadata);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_agent_queue_work_type ON agent_processing_queue (work_type, processing_state);

-- Update existing rows to have work_type = 'P1_SUBSTRATE' (current default)
UPDATE agent_processing_queue 
SET work_type = 'P1_SUBSTRATE' 
WHERE work_type IS NULL;

-- Add canon compliance comments
COMMENT ON COLUMN agent_processing_queue.work_type IS 'Canon v2.1: Type of work being processed (P0-P4, manual operations)';
COMMENT ON COLUMN agent_processing_queue.processing_stage IS 'Canon v2.1: Stage-specific status within work type';
COMMENT ON COLUMN agent_processing_queue.work_payload IS 'Canon v2.1: Input data for work execution';
COMMENT ON COLUMN agent_processing_queue.work_result IS 'Canon v2.1: Output data from completed work';
COMMENT ON COLUMN agent_processing_queue.cascade_metadata IS 'Canon v2.1: Metadata for P1→P2→P3 cascade flows';
COMMENT ON COLUMN agent_processing_queue.parent_work_id IS 'Canon v2.1: Parent work entry for cascade flows';
COMMENT ON COLUMN agent_processing_queue.user_id IS 'Canon v2.1: User who initiated this work';
COMMENT ON COLUMN agent_processing_queue.work_id IS 'Canon v2.1: Optional external work identifier';

-- Note: This migration extends the existing agent_processing_queue to serve as the
-- canonical_queue referenced in Canon v2.1 documentation, maintaining backward compatibility
-- while enabling universal work orchestration across all async operations.