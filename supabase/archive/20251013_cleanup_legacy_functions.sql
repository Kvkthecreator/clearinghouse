-- Cleanup Legacy Functions
-- Remove or update functions that reference removed columns

BEGIN;

-- =============================================================================
-- DROP LEGACY REFLECTION FUNCTIONS
-- =============================================================================
-- These functions predate P3 taxonomy and use old reflection_target fields
-- They should be replaced with P3-aware functions in upcoming implementation

DROP FUNCTION IF EXISTS public.fn_reflection_create_from_document(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.fn_reflection_create_from_substrate(uuid, text);

-- fn_persist_reflection and fn_reflection_cache_upsert also use legacy fields
-- Check if they're still in use before dropping
DROP FUNCTION IF EXISTS public.fn_persist_reflection(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.fn_reflection_cache_upsert(uuid, text, text, text, text);

-- =============================================================================
-- DROP OLD log_extraction_metrics SIGNATURE
-- =============================================================================
-- We updated this function in the previous migration but old signature still exists
-- Drop the old one with extraction_method parameter

DROP FUNCTION IF EXISTS public.log_extraction_metrics(
  uuid, uuid, uuid, text, text, integer, integer, real, integer
);

COMMIT;
