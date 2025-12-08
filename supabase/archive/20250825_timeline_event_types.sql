-- Add timeline event type constraints for Canon v1.3.1
-- This migration updates the events table to support standardized event types

-- First, update existing event kinds to match Canon v1.3.1 naming
UPDATE events SET kind = 'dump.created' WHERE kind = 'dump';
UPDATE events SET kind = 'reflection.computed' WHERE kind = 'reflection';
UPDATE events SET kind = 'document.created' WHERE kind = 'doc_created';
UPDATE events SET kind = 'document.updated' WHERE kind = 'doc_updated';
UPDATE events SET kind = 'block.created' WHERE kind = 'block_created';
UPDATE events SET kind = 'block.updated' WHERE kind = 'block_updated';

-- Add check constraint for valid event types
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_kind_check;
ALTER TABLE events ADD CONSTRAINT events_kind_check CHECK (
  kind IN (
    'dump.created',
    'reflection.computed',
    'delta.applied',
    'delta.rejected',
    'document.created',
    'document.updated',
    'block.created',
    'block.updated',
    'basket.created',
    'workspace.member_added'
  )
);

-- Add composite index for efficient timeline queries with cursor pagination
CREATE INDEX IF NOT EXISTS idx_events_basket_ts_id ON events(basket_id, ts DESC, id DESC);

-- Add function to emit timeline events (for use by other operations)
CREATE OR REPLACE FUNCTION emit_timeline_event(
  p_basket_id UUID,
  p_event_type TEXT,
  p_event_data JSONB,
  p_workspace_id UUID,
  p_actor_id UUID DEFAULT NULL,
  p_agent_type TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  v_event_id UUID;
BEGIN
  INSERT INTO events (
    basket_id,
    kind,
    payload,
    workspace_id,
    actor_id,
    agent_type,
    origin,
    ts
  ) VALUES (
    p_basket_id,
    p_event_type,
    p_event_data,
    p_workspace_id,
    p_actor_id,
    p_agent_type,
    CASE 
      WHEN p_actor_id IS NOT NULL THEN 'user'
      WHEN p_agent_type IS NOT NULL THEN 'agent'
      ELSE 'system'
    END,
    NOW()
  ) RETURNING id INTO v_event_id;
  
  RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update fn_ingest_dumps to emit dump.created events
CREATE OR REPLACE FUNCTION fn_ingest_dumps(
  p_workspace_id uuid,
  p_basket_id uuid,
  p_dumps jsonb[]
) RETURNS jsonb AS $$
DECLARE
  dump jsonb;
  inserted_id uuid;
  result_array jsonb[] := '{}';
  is_replay boolean;
  v_text_dump text;
  v_file_url text;
BEGIN
  FOREACH dump IN ARRAY p_dumps LOOP
    v_text_dump := dump->>'text_dump';
    v_file_url := dump->>'file_url';
    
    -- Validate that at least one content field is provided
    IF v_text_dump IS NULL AND v_file_url IS NULL THEN
      RAISE EXCEPTION 'Either text_dump or file_url must be provided';
    END IF;
    
    BEGIN
      INSERT INTO raw_dumps (
        workspace_id,
        basket_id,
        dump_request_id,
        text_dump,
        file_url,
        source_meta,
        ingest_trace_id
      ) VALUES (
        p_workspace_id,
        p_basket_id,
        (dump->>'dump_request_id')::uuid,
        v_text_dump,
        v_file_url,
        dump->'source_meta',
        (dump->>'ingest_trace_id')::uuid
      ) RETURNING id INTO inserted_id;
      
      is_replay := false;
      
      -- Emit dump.created event
      PERFORM emit_timeline_event(
        p_basket_id,
        'dump.created',
        jsonb_build_object(
          'dump_id', inserted_id,
          'source_type', CASE 
            WHEN v_text_dump IS NOT NULL THEN 'text'
            WHEN v_file_url IS NOT NULL THEN 'file'
          END,
          'char_count', COALESCE(length(v_text_dump), 0)
        ),
        p_workspace_id
      );
      
    EXCEPTION WHEN unique_violation THEN
      -- For idempotency, return the existing dump_id
      SELECT id INTO inserted_id 
      FROM raw_dumps 
      WHERE basket_id = p_basket_id 
        AND dump_request_id = (dump->>'dump_request_id')::uuid
      LIMIT 1;
      
      is_replay := true;
    END;
    
    result_array := array_append(
      result_array, 
      jsonb_build_object(
        'dump_id', inserted_id,
        'was_replay', is_replay
      )
    );
  END LOOP;
  
  RETURN to_jsonb(result_array);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;