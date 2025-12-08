-- Simple Substrate Fix: Remove reflection from substrate_type enum
-- Breaking this into minimal steps to avoid dependency issues

BEGIN;

-- Step 1: Drop the problematic view
DROP VIEW IF EXISTS document_composition_stats CASCADE;

-- Step 2: Remove reflection references from substrate_references
DELETE FROM substrate_references WHERE substrate_type = 'reflection';

-- Step 3: Create new substrate type enum (without reflection)
CREATE TYPE substrate_type_new AS ENUM (
  'block',           -- context_blocks
  'dump',            -- raw_dumps
  'context_item',    -- context_items  
  'timeline_event'   -- timeline_events
);

-- Step 4: Update substrate_references table
ALTER TABLE substrate_references 
  ALTER COLUMN substrate_type TYPE substrate_type_new
  USING substrate_type::text::substrate_type_new;

-- Step 5: Drop old enum and rename new one
DROP TYPE substrate_type;
ALTER TYPE substrate_type_new RENAME TO substrate_type;

-- Step 6: Recreate the view (without reflections)
CREATE VIEW document_composition_stats AS
 SELECT substrate_references.document_id,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'block') AS blocks_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'dump') AS dumps_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'context_item') AS context_items_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'timeline_event') AS timeline_events_count,
    count(*) AS total_substrate_references
   FROM substrate_references
  GROUP BY substrate_references.document_id;

COMMIT;