-- Schema Cleanup: Remove Legacy Fields
-- Hardening P3/P4 Canon by removing deprecated/legacy columns

BEGIN;

-- =============================================================================
-- REFLECTIONS_ARTIFACT: Remove legacy reflection_target fields
-- =============================================================================
-- These fields predate the P3 taxonomy (insight_type) and are no longer needed
-- P3 insights now use insight_type + derived_from for all targeting

ALTER TABLE public.reflections_artifact
  DROP COLUMN IF EXISTS reflection_target_type,
  DROP COLUMN IF EXISTS reflection_target_id,
  DROP COLUMN IF EXISTS reflection_target_version;

-- Drop the now-unused constraint
ALTER TABLE public.reflections_artifact
  DROP CONSTRAINT IF EXISTS valid_reflection_target;

-- =============================================================================
-- BLOCKS: Remove legacy extraction_method field
-- =============================================================================
-- Extraction method was for old substrate extraction patterns
-- Now superseded by governance pipeline (proposals + provenance in metadata)

-- First drop dependent views with CASCADE
DROP VIEW IF EXISTS public.knowledge_ingredients_view CASCADE;
DROP VIEW IF EXISTS public.structured_ingredient_blocks CASCADE;

-- Drop indexes on extraction_method
DROP INDEX IF EXISTS public.idx_blocks_extraction_method;
DROP INDEX IF EXISTS public.idx_blocks_provenance_validated;

-- Remove the columns (CASCADE will handle remaining dependencies)
ALTER TABLE public.blocks
  DROP COLUMN IF EXISTS extraction_method CASCADE,
  DROP COLUMN IF EXISTS provenance_validated CASCADE,
  DROP COLUMN IF EXISTS ingredient_version CASCADE;

-- =============================================================================
-- EXTRACTION_QUALITY_METRICS: Remove extraction_method column
-- =============================================================================
-- Metrics table references old extraction_method enum
-- Keep table for other metrics, just remove this field

ALTER TABLE public.extraction_quality_metrics
  DROP COLUMN IF EXISTS extraction_method;

-- Update the logging function signature
CREATE OR REPLACE FUNCTION public.log_extraction_metrics(
  p_dump_id uuid,
  p_basket_id uuid,
  p_workspace_id uuid,
  p_agent_version text,
  p_blocks_created integer,
  p_context_items_created integer,
  p_avg_confidence real,
  p_processing_time_ms integer
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_metric_id uuid;
BEGIN
  INSERT INTO extraction_quality_metrics (
    dump_id, basket_id, workspace_id, agent_version,
    blocks_created, context_items_created, avg_confidence, processing_time_ms
  ) VALUES (
    p_dump_id, p_basket_id, p_workspace_id, p_agent_version,
    p_blocks_created, p_context_items_created, p_avg_confidence, p_processing_time_ms
  )
  RETURNING id INTO v_metric_id;
  RETURN v_metric_id;
END;
$$;

-- =============================================================================
-- CONTEXT_ITEMS: Remove extraction_method + legacy provenance fields
-- =============================================================================

ALTER TABLE public.context_items
  DROP COLUMN IF EXISTS extraction_method CASCADE,
  DROP COLUMN IF EXISTS provenance_validated CASCADE,
  DROP COLUMN IF EXISTS ingredient_version CASCADE;

-- =============================================================================
-- DOCUMENTS: document_type is legacy, now replaced by doc_type
-- =============================================================================
-- Keep document_type for backward compat if needed, but ensure doc_type is primary

-- Add comment to clarify deprecation
COMMENT ON COLUMN public.documents.document_type IS 'DEPRECATED: Use doc_type instead. Kept for backward compatibility only.';
COMMENT ON COLUMN public.documents.doc_type IS 'P4 taxonomy: document_canon, starter_prompt, artifact_other';

COMMIT;
