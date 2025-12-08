-- Fix emit_timeline_event function to use timeline_events table exclusively
-- This migration aligns event emission with Canon v1.3.1

-- Drop and recreate emit_timeline_event to use timeline_events table
DROP FUNCTION IF EXISTS emit_timeline_event(UUID, TEXT, JSONB, UUID, UUID, TEXT);

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
  INSERT INTO timeline_events (
    basket_id,
    event_kind,
    event_data,
    workspace_id,
    actor_id,
    agent_type,
    origin,
    timestamp
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

-- Add check constraint for valid event types on timeline_events
ALTER TABLE timeline_events DROP CONSTRAINT IF EXISTS timeline_events_kind_check;
ALTER TABLE timeline_events ADD CONSTRAINT timeline_events_kind_check CHECK (
  event_kind IN (
    'dump.created',
    'reflection.computed',
    'delta.applied',
    'delta.rejected',
    'document.created',
    'document.updated',
    'document.block.attached',
    'document.block.detached',
    'document.dump.attached',
    'document.dump.detached',
    'document.context_item.attached',
    'document.context_item.detached',
    'document.reflection.attached',
    'document.reflection.detached',
    'document.timeline_event.attached',
    'document.timeline_event.detached',
    'block.created',
    'block.updated',
    'basket.created',
    'workspace.member_added'
  )
);

-- Add composite index for efficient timeline queries with cursor pagination
CREATE INDEX IF NOT EXISTS idx_timeline_events_basket_timestamp_id ON timeline_events(basket_id, timestamp DESC, id DESC);