-- Add pipeline cascade timeline events to allowed kinds
-- Fixes: pipeline.cascade_triggered violates timeline_events_kind_check constraint

BEGIN;

-- Drop existing constraint
ALTER TABLE timeline_events DROP CONSTRAINT IF EXISTS timeline_events_kind_check;

-- Add new constraint with pipeline events included
ALTER TABLE timeline_events ADD CONSTRAINT timeline_events_kind_check 
CHECK ((kind = ANY (ARRAY[
    -- Legacy events (preserved for compatibility)
    'dump'::text, 'reflection'::text, 'narrative'::text, 'system_note'::text, 'block'::text,
    
    -- P0 Capture events
    'dump.created'::text, 'dump.queued'::text,
    
    -- P1 Substrate events
    'block.created'::text, 'block.updated'::text, 'block.state_changed'::text,
    'context_item.created'::text, 'context_item.updated'::text, 'context_item.archived'::text,
    
    -- P2 Graph events
    'relationship.created'::text, 'relationship.deleted'::text,
    
    -- P3 Reflection events
    'reflection.computed'::text, 'reflection.cached'::text,
    
    -- P4 Presentation events
    'document.created'::text, 'document.updated'::text, 'document.composed'::text,
    'narrative.authored'::text,
    
    -- Document attachment events (legacy)
    'document.block.attached'::text, 'document.block.detached'::text,
    'document.dump.attached'::text, 'document.dump.detached'::text,
    'document.context_item.attached'::text, 'document.context_item.detached'::text,
    'document.reflection.attached'::text, 'document.reflection.detached'::text,
    'document.timeline_event.attached'::text, 'document.timeline_event.detached'::text,
    
    -- Governance events
    'proposal.submitted'::text, 'proposal.approved'::text, 'proposal.rejected'::text,
    'substrate.committed'::text,
    
    -- System events
    'basket.created'::text, 'workspace.member_added'::text,
    'delta.applied'::text, 'delta.rejected'::text,
    'cascade.completed'::text,
    
    -- Universal Work Orchestration events (Canon v2.1)
    'work.initiated'::text, 'work.routed'::text,
    
    -- Pipeline orchestration events
    'pipeline.cascade_triggered'::text, 'pipeline.cascade_completed'::text,
    'pipeline.cascade_failed'::text,
    
    -- Queue processing events
    'queue.entry_created'::text, 'queue.processing_started'::text,
    'queue.processing_completed'::text, 'queue.processing_failed'::text
])));

-- Refresh the schema cache to ensure PostgREST picks up the constraint changes
NOTIFY pgrst, 'reload schema';

COMMIT;
