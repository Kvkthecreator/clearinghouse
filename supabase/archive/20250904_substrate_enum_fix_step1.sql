-- Step 1: Handle dependencies before enum change
-- Drop functions that depend on substrate_type enum

BEGIN;

-- Remove the view that depends on substrate_type
DROP VIEW IF EXISTS document_composition_stats CASCADE;

-- Remove any reflection references from substrate_references  
DELETE FROM substrate_references WHERE substrate_type = 'reflection';

-- Drop functions that depend on substrate_type enum
DROP FUNCTION IF EXISTS fn_document_attach_substrate(uuid, substrate_type, uuid, text, numeric, jsonb, jsonb);
DROP FUNCTION IF EXISTS fn_document_detach_substrate(uuid, substrate_type, uuid);

COMMIT;