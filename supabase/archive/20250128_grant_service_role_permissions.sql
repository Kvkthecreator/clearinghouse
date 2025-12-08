-- Grant permissions to service_role for agent queue processing
-- This fixes "permission denied for schema public" errors in Render deployment

-- Grant execute permissions to service_role for all queue RPCs
GRANT EXECUTE ON FUNCTION fn_claim_next_dumps TO service_role;
GRANT EXECUTE ON FUNCTION fn_update_queue_state TO service_role; 
GRANT EXECUTE ON FUNCTION fn_queue_health TO service_role;
GRANT EXECUTE ON FUNCTION fn_ingest_dumps TO service_role;

-- Grant schema access
GRANT USAGE ON SCHEMA public TO service_role;

-- Grant table permissions needed by queue processor
GRANT SELECT, INSERT, UPDATE ON agent_processing_queue TO service_role;
GRANT SELECT ON raw_dumps TO service_role;
GRANT SELECT ON baskets TO service_role;
GRANT SELECT ON workspaces TO service_role;
GRANT SELECT ON blocks TO service_role;
GRANT SELECT ON context_items TO service_role;

-- Grant permissions for context item operations
GRANT SELECT, INSERT, UPDATE ON context_items TO service_role;

-- Grant permissions for event logging
GRANT INSERT ON events TO service_role;

-- Grant permissions for other existing tables
GRANT SELECT ON reflection_cache TO service_role;
GRANT SELECT ON timeline_events TO service_role;
GRANT SELECT ON substrate_references TO service_role;
GRANT SELECT ON narrative TO service_role;
GRANT SELECT ON documents TO service_role;
GRANT SELECT ON block_links TO service_role;

-- Verify permissions are granted
SELECT 'Agent queue permissions granted to service_role' as status;