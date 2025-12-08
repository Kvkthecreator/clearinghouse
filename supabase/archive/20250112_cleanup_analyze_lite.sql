-- Cleanup: Remove legacy analyze-lite views
-- These views are no longer used after document system consolidation

-- Drop the views in reverse dependency order
DROP VIEW IF EXISTS public.vw_document_analyze_lite;
DROP VIEW IF EXISTS public.document_staleness;

-- Note: We keep the underlying substrate_references table as it's still used
-- by the composition system for tracking document-substrate relationships