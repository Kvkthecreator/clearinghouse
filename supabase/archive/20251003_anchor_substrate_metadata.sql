-- Phase A: Anchor Refactor - Move anchors to substrate metadata
--
-- Canon principle: Substrate equality (anchors are promoted substrate, not separate registry)
--
-- Changes:
-- 1. Add anchor_role, anchor_status, anchor_confidence to blocks and context_items
-- 2. Migrate existing basket_anchors data to substrate metadata
-- 3. Create indexes for efficient anchor queries
-- 4. Keep basket_anchors table for rollback (will drop in later migration after validation)

BEGIN;

-- =====================================================
-- 1. Add anchor metadata columns to blocks
-- =====================================================

ALTER TABLE blocks
  ADD COLUMN anchor_role TEXT CHECK (
    anchor_role IN ('problem', 'customer', 'solution', 'feature', 'constraint', 'metric', 'insight', 'vision')
  ),
  ADD COLUMN anchor_status TEXT CHECK (
    anchor_status IN ('proposed', 'accepted', 'rejected', 'n/a')
  ) DEFAULT 'proposed',
  ADD COLUMN anchor_confidence REAL CHECK (
    anchor_confidence >= 0.0 AND anchor_confidence <= 1.0
  );

COMMENT ON COLUMN blocks.anchor_role IS 'Anchor role this block fulfills (if promoted to anchor)';
COMMENT ON COLUMN blocks.anchor_status IS 'Anchor promotion status: proposed (suggested), accepted (user confirmed), rejected (user declined), n/a (not applicable)';
COMMENT ON COLUMN blocks.anchor_confidence IS 'Confidence score for anchor role (0.0 to 1.0), derived from evidence quality and recency';

-- =====================================================
-- 2. Add anchor metadata columns to context_items
-- =====================================================

ALTER TABLE context_items
  ADD COLUMN anchor_role TEXT CHECK (
    anchor_role IN ('problem', 'customer', 'solution', 'feature', 'constraint', 'metric', 'insight', 'vision')
  ),
  ADD COLUMN anchor_status TEXT CHECK (
    anchor_status IN ('proposed', 'accepted', 'rejected', 'n/a')
  ) DEFAULT 'proposed',
  ADD COLUMN anchor_confidence REAL CHECK (
    anchor_confidence >= 0.0 AND anchor_confidence <= 1.0
  );

COMMENT ON COLUMN context_items.anchor_role IS 'Anchor role this context item fulfills (if promoted to anchor)';
COMMENT ON COLUMN context_items.anchor_status IS 'Anchor promotion status: proposed, accepted, rejected, n/a';
COMMENT ON COLUMN context_items.anchor_confidence IS 'Confidence score for anchor role (0.0 to 1.0)';

-- =====================================================
-- 3. Create indexes for efficient anchor queries
-- =====================================================

-- Index for fetching anchored blocks by basket and role
CREATE INDEX idx_blocks_anchor_role
  ON blocks(basket_id, anchor_role, anchor_status)
  WHERE anchor_role IS NOT NULL;

-- Index for fetching anchored context_items by basket and role
CREATE INDEX idx_context_items_anchor_role
  ON context_items(basket_id, anchor_role, anchor_status)
  WHERE anchor_role IS NOT NULL;

-- Index for anchor confidence queries (find high-confidence anchors)
CREATE INDEX idx_blocks_anchor_confidence
  ON blocks(basket_id, anchor_confidence DESC)
  WHERE anchor_role IS NOT NULL AND anchor_confidence IS NOT NULL;

CREATE INDEX idx_context_items_anchor_confidence
  ON context_items(basket_id, anchor_confidence DESC)
  WHERE anchor_role IS NOT NULL AND anchor_confidence IS NOT NULL;

-- =====================================================
-- 4. Migrate existing basket_anchors to substrate metadata
-- =====================================================

-- Helper function to map anchor_key to anchor_role
CREATE OR REPLACE FUNCTION map_anchor_key_to_role(anchor_key TEXT)
RETURNS TEXT AS $$
BEGIN
  -- Extract role from anchor_key patterns
  -- Examples: "core_problem" -> "problem", "feature_block_1" -> "feature"

  IF anchor_key LIKE '%problem%' THEN RETURN 'problem';
  ELSIF anchor_key LIKE '%customer%' THEN RETURN 'customer';
  ELSIF anchor_key LIKE '%solution%' THEN RETURN 'solution';
  ELSIF anchor_key LIKE '%feature%' THEN RETURN 'feature';
  ELSIF anchor_key LIKE '%constraint%' THEN RETURN 'constraint';
  ELSIF anchor_key LIKE '%metric%' THEN RETURN 'metric';
  ELSIF anchor_key LIKE '%insight%' THEN RETURN 'insight';
  ELSIF anchor_key LIKE '%vision%' THEN RETURN 'vision';
  ELSE RETURN NULL; -- Unknown anchor key pattern
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Migrate basket_anchors where linked_substrate_id points to blocks
UPDATE blocks b
SET
  anchor_role = map_anchor_key_to_role(ba.anchor_key),
  anchor_status = 'accepted', -- Existing anchors are assumed accepted
  anchor_confidence = 1.0 -- Existing anchors assumed high confidence
FROM basket_anchors ba
WHERE
  ba.linked_substrate_id = b.id
  AND ba.expected_type = 'block'
  AND ba.status = 'active'
  AND map_anchor_key_to_role(ba.anchor_key) IS NOT NULL;

-- Migrate basket_anchors where linked_substrate_id points to context_items
UPDATE context_items ci
SET
  anchor_role = map_anchor_key_to_role(ba.anchor_key),
  anchor_status = 'accepted',
  anchor_confidence = 1.0
FROM basket_anchors ba
WHERE
  ba.linked_substrate_id = ci.id
  AND ba.expected_type = 'context_item'
  AND ba.status = 'active'
  AND map_anchor_key_to_role(ba.anchor_key) IS NOT NULL;

-- Log migration stats
DO $$
DECLARE
  blocks_migrated INT;
  context_items_migrated INT;
BEGIN
  SELECT COUNT(*) INTO blocks_migrated
  FROM blocks WHERE anchor_role IS NOT NULL;

  SELECT COUNT(*) INTO context_items_migrated
  FROM context_items WHERE anchor_role IS NOT NULL;

  RAISE NOTICE 'Anchor migration complete: % blocks, % context_items now have anchor metadata',
    blocks_migrated, context_items_migrated;
END $$;

-- =====================================================
-- 5. Create helper view for anchored substrate
-- =====================================================

CREATE OR REPLACE VIEW anchored_substrate AS
SELECT
  'block' AS substrate_type,
  id AS substrate_id,
  basket_id,
  anchor_role,
  anchor_status,
  anchor_confidence,
  title,
  content,
  semantic_type,
  state::text AS state,
  status,
  created_at,
  updated_at,
  last_validated_at,
  metadata
FROM blocks
WHERE anchor_role IS NOT NULL

UNION ALL

SELECT
  'context_item' AS substrate_type,
  id AS substrate_id,
  basket_id,
  anchor_role,
  anchor_status,
  anchor_confidence,
  title,
  semantic_meaning AS content,
  semantic_category AS semantic_type,
  state::text AS state,
  status,
  created_at,
  updated_at,
  NULL AS last_validated_at,
  metadata
FROM context_items
WHERE anchor_role IS NOT NULL;

COMMENT ON VIEW anchored_substrate IS 'Unified view of all anchored substrate (blocks + context_items) for P4 composition';

-- =====================================================
-- 6. Grant permissions
-- =====================================================

-- Service role has full access
GRANT SELECT, INSERT, UPDATE, DELETE ON anchored_substrate TO service_role;

-- Authenticated users can view anchored substrate if they're workspace members
-- (RLS policies on blocks/context_items already handle this)

COMMIT;

-- =====================================================
-- Notes for rollback
-- =====================================================
-- basket_anchors table is NOT dropped in this migration
-- Keep it for validation and rollback safety
-- Will drop in a future migration after Phase A is validated in production
