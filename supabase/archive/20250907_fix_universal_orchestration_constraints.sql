-- Fix Universal Work Orchestration Constraints
-- Make dump_id nullable to support all work types (not just P1_SUBSTRATE)
-- Add priority column for work ordering

-- Make dump_id nullable since not all work types require a dump
ALTER TABLE agent_processing_queue 
ALTER COLUMN dump_id DROP NOT NULL;

-- Make basket_id nullable since not all work types require a basket
ALTER TABLE agent_processing_queue 
ALTER COLUMN basket_id DROP NOT NULL;

-- Add priority column for work ordering
ALTER TABLE agent_processing_queue 
ADD COLUMN IF NOT EXISTS priority integer DEFAULT 5;

-- Update the unique constraint on dump_id to only apply when dump_id is not null
-- First drop the existing constraint
ALTER TABLE agent_processing_queue 
DROP CONSTRAINT IF EXISTS agent_processing_queue_dump_id_key;

-- Create partial unique constraint for dump_id (only when not null)
CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_queue_dump_id_unique 
ON agent_processing_queue (dump_id) 
WHERE dump_id IS NOT NULL;

-- Update foreign key constraints to handle nullable values
ALTER TABLE agent_processing_queue 
DROP CONSTRAINT IF EXISTS agent_processing_queue_dump_id_fkey;

ALTER TABLE agent_processing_queue 
ADD CONSTRAINT agent_processing_queue_dump_id_fkey 
FOREIGN KEY (dump_id) REFERENCES raw_dumps(id)
DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE agent_processing_queue 
DROP CONSTRAINT IF EXISTS agent_processing_queue_basket_id_fkey;

ALTER TABLE agent_processing_queue 
ADD CONSTRAINT agent_processing_queue_basket_id_fkey 
FOREIGN KEY (basket_id) REFERENCES baskets(id)
DEFERRABLE INITIALLY DEFERRED;

-- Add index for priority-based work ordering
CREATE INDEX IF NOT EXISTS idx_agent_queue_priority 
ON agent_processing_queue (priority DESC, created_at);

-- Comments for the new flexibility
COMMENT ON COLUMN agent_processing_queue.dump_id IS 'Canon v2.1: Associated dump ID (nullable for non-dump work types)';
COMMENT ON COLUMN agent_processing_queue.basket_id IS 'Canon v2.1: Associated basket ID (nullable for workspace-level work)';
COMMENT ON COLUMN agent_processing_queue.priority IS 'Canon v2.1: Work priority for ordering (1=highest, 10=lowest)';

-- Update work type constraint description
COMMENT ON CONSTRAINT valid_work_type_v21 ON agent_processing_queue IS 'Canon v2.1: Ensures work_type is one of the supported universal work types';