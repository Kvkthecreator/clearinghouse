-- Add trigger to automatically queue dumps for agent processing
-- This enforces the YARNNN canon: every raw dump MUST be processed by agents

-- Function to create queue entry when dump is inserted
CREATE OR REPLACE FUNCTION queue_agent_processing() 
RETURNS trigger AS $$
BEGIN
  -- Insert into processing queue with workspace context
  INSERT INTO agent_processing_queue (
    dump_id, 
    basket_id, 
    workspace_id
  )
  SELECT 
    NEW.id,
    NEW.basket_id,
    b.workspace_id
  FROM baskets b
  WHERE b.id = NEW.basket_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger that fires after dump insertion
CREATE TRIGGER after_dump_insert
AFTER INSERT ON raw_dumps
FOR EACH ROW 
EXECUTE FUNCTION queue_agent_processing();

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION queue_agent_processing() TO authenticated;
GRANT EXECUTE ON FUNCTION queue_agent_processing() TO service_role;

-- Add comment for documentation
COMMENT ON FUNCTION queue_agent_processing() IS 'Automatically queues raw dumps for agent processing per YARNNN canon';
COMMENT ON TRIGGER after_dump_insert ON raw_dumps IS 'Ensures every raw dump is queued for mandatory agent processing';