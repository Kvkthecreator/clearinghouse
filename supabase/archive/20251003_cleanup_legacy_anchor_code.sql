-- Phase A Cleanup: Remove legacy anchor code
--
-- This migration removes code that's no longer needed after Phase A anchor refactor:
-- 1. basket_substrate_context view (used by removed P1 context-aware extraction)
-- 2. Any functions/triggers specific to old anchor system
--
-- Note: basket_anchors table is kept for rollback safety (will drop in later migration)

BEGIN;

-- =====================================================
-- 1. Drop basket_substrate_context view
-- =====================================================
-- This view was used by P1 context-aware extraction to fetch existing substrate
-- Phase A made P1 anchor-blind, so this view is no longer needed

DROP VIEW IF EXISTS basket_substrate_context CASCADE;

-- =====================================================
-- 2. Check for any other legacy anchor-related code
-- =====================================================
-- increment_block_usage() and related functions are still used (usage tracking is separate from anchors)
-- log_extraction_metrics() is still used (quality tracking is separate from anchors)
-- These stay in place

COMMIT;

-- =====================================================
-- Validation
-- =====================================================
-- After this migration:
-- ✅ basket_substrate_context view should be gone
-- ✅ anchored_substrate view should exist (new Phase A view)
-- ✅ blocks and context_items should have anchor_role, anchor_status, anchor_confidence columns
-- ✅ basket_anchors table should still exist (for rollback safety)
