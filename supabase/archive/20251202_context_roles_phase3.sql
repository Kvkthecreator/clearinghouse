-- Context Roles Phase 3: Add context role targeting to work_outputs
-- Date: 2025-12-02
-- Canon Reference: /docs/canon/CONTEXT_ROLES_ARCHITECTURE.md
--
-- This migration adds:
-- 1. target_context_role column for declaring what role an output will fill
-- 2. auto_promote flag for trusted scheduled recipes
-- 3. promotion_status for tracking promotion workflow

BEGIN;

-- =====================================================
-- 1. Add target_context_role to work_outputs
-- =====================================================

ALTER TABLE work_outputs
ADD COLUMN IF NOT EXISTS target_context_role TEXT;

COMMENT ON COLUMN work_outputs.target_context_role IS
'The context role this output is intended to fill when promoted to a block.
Examples: trend_digest, competitor_snapshot, brand_voice.
Set by recipes that produce context via context_outputs declaration.';

-- =====================================================
-- 2. Add auto_promote flag
-- =====================================================

ALTER TABLE work_outputs
ADD COLUMN IF NOT EXISTS auto_promote BOOLEAN DEFAULT false;

COMMENT ON COLUMN work_outputs.auto_promote IS
'If true, output is automatically promoted to block on completion.
Used for trusted scheduled recipes. Still requires work supervision approval if enabled.';

-- =====================================================
-- 3. Add promotion_status for tracking
-- =====================================================

ALTER TABLE work_outputs
ADD COLUMN IF NOT EXISTS promotion_status TEXT DEFAULT 'pending'
CHECK (promotion_status IN ('pending', 'promoted', 'rejected', 'skipped'));

COMMENT ON COLUMN work_outputs.promotion_status IS
'Status of promotion workflow: pending (awaiting review), promoted (became block),
rejected (declined by reviewer), skipped (not applicable for promotion).';

-- =====================================================
-- 4. Add index for finding promotable outputs by role
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_work_outputs_target_role
ON work_outputs (target_context_role, promotion_status)
WHERE target_context_role IS NOT NULL;

-- =====================================================
-- 5. Extend work_recipes with context_outputs
-- =====================================================

ALTER TABLE work_recipes
ADD COLUMN IF NOT EXISTS context_outputs JSONB DEFAULT NULL;

COMMENT ON COLUMN work_recipes.context_outputs IS
'Declares what context role this recipe produces.
Schema: {"role": "trend_digest", "refresh_policy": {"ttl_hours": 168, "auto_promote": true}}
Only set for context-producing recipes (not execution recipes).';

COMMIT;
