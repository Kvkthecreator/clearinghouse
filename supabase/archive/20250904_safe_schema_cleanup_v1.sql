-- Safe Schema Cleanup: Step 1 - Remove dependencies before enum change
-- This migration handles view dependencies and prepares for enum update

BEGIN;

-- =============================================================================
-- STEP 1: DROP VIEWS THAT DEPEND ON substrate_type ENUM
-- =============================================================================

-- Drop the view that's blocking our enum change
DROP VIEW IF EXISTS document_composition_stats CASCADE;

-- =============================================================================  
-- STEP 2: BACKUP LEGACY DATA
-- =============================================================================

-- Backup block_links before deletion
CREATE TABLE IF NOT EXISTS block_links_legacy_backup AS 
  SELECT * FROM block_links WHERE NOT EXISTS (SELECT 1 FROM block_links_legacy_backup LIMIT 1);

-- Backup document_context_items
CREATE TABLE IF NOT EXISTS document_context_items_legacy_backup AS
  SELECT * FROM document_context_items WHERE NOT EXISTS (SELECT 1 FROM document_context_items_legacy_backup LIMIT 1);

-- Backup reflection substrate_references 
CREATE TABLE IF NOT EXISTS substrate_references_reflection_backup AS
  SELECT * FROM substrate_references 
  WHERE substrate_type = 'reflection'
  AND NOT EXISTS (SELECT 1 FROM substrate_references_reflection_backup LIMIT 1);

-- =============================================================================
-- STEP 3: REMOVE REFLECTION REFERENCES FROM SUBSTRATE_REFERENCES
-- =============================================================================

-- Remove reflection references (they're artifacts, not substrates)
DELETE FROM substrate_references WHERE substrate_type = 'reflection';

-- =============================================================================
-- STEP 4: CREATE NEW SUBSTRATE_TYPE ENUM (Clean)
-- =============================================================================

-- Create new enum without 'reflection'
CREATE TYPE substrate_type_v2 AS ENUM (
  'block',           -- context_blocks
  'dump',            -- raw_dumps  
  'context_item',    -- context_items
  'timeline_event'   -- timeline_events
);

-- =============================================================================
-- STEP 5: UPDATE SUBSTRATE_REFERENCES TABLE
-- =============================================================================

-- Update column to use new enum type
ALTER TABLE substrate_references 
  ALTER COLUMN substrate_type TYPE substrate_type_v2
  USING substrate_type::text::substrate_type_v2;

-- =============================================================================
-- STEP 6: RECREATE VIEWS WITH CLEAN MODEL
-- =============================================================================

-- Recreate composition stats view (without reflections)
CREATE VIEW document_composition_stats AS
 SELECT substrate_references.document_id,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'block') AS blocks_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'dump') AS dumps_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'context_item') AS context_items_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'timeline_event') AS timeline_events_count,
    count(*) AS total_substrate_references
   FROM substrate_references
  GROUP BY substrate_references.document_id;

-- =============================================================================
-- STEP 7: DROP OLD ENUM AND RENAME
-- =============================================================================

-- Drop old enum type
DROP TYPE substrate_type;

-- Rename new enum 
ALTER TYPE substrate_type_v2 RENAME TO substrate_type;

COMMIT;