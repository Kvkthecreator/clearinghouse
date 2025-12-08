-- Substrate Quality Improvements: Usage Tracking & Staleness Detection
-- Phase 1: Core infrastructure for context-aware extraction and quality feedback
--
-- NOTE: Phase A anchor refactor (20251003_anchor_substrate_metadata.sql) supersedes
-- the basket_substrate_context view created in this migration. The view was used by
-- P1 context-aware extraction, which was removed to restore phase boundaries.
-- See 20251003_cleanup_legacy_anchor_code.sql for cleanup.

BEGIN;

-- =====================================================
-- 1. USAGE TRACKING: Track which blocks get used
-- =====================================================

CREATE TABLE IF NOT EXISTS block_usage (
  block_id uuid PRIMARY KEY REFERENCES blocks(id) ON DELETE CASCADE,
  times_referenced int DEFAULT 0 NOT NULL,
  last_used_at timestamptz,
  -- Simple usefulness scoring: 0.0 (unused) to 1.0 (proven useful)
  usefulness_score real GENERATED ALWAYS AS (
    CASE
      WHEN times_referenced = 0 THEN 0.0
      WHEN times_referenced < 3 THEN 0.5
      ELSE 0.9
    END
  ) STORED,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX idx_block_usage_score ON block_usage(usefulness_score DESC);
CREATE INDEX idx_block_usage_last_used ON block_usage(last_used_at DESC NULLS LAST);

COMMENT ON TABLE block_usage IS 'Tracks block usage patterns to identify which substrate is actually useful';
COMMENT ON COLUMN block_usage.usefulness_score IS 'Auto-calculated: 0.0 (unused), 0.5 (1-2 uses), 0.9 (3+ uses)';

-- Function to increment block usage
CREATE OR REPLACE FUNCTION increment_block_usage(p_block_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO block_usage (block_id, times_referenced, last_used_at)
  VALUES (p_block_id, 1, now())
  ON CONFLICT (block_id)
  DO UPDATE SET
    times_referenced = block_usage.times_referenced + 1,
    last_used_at = now();
END;
$$;

COMMENT ON FUNCTION increment_block_usage IS 'Increment usage count when block is referenced (document attachment, query result, etc.)';

-- =====================================================
-- 2. STALENESS DETECTION: Simple timestamp-based
-- =====================================================

ALTER TABLE blocks
  ADD COLUMN IF NOT EXISTS last_validated_at timestamptz DEFAULT now();

CREATE INDEX idx_blocks_staleness ON blocks(last_validated_at DESC NULLS LAST);

COMMENT ON COLUMN blocks.last_validated_at IS 'Timestamp of last validation - updates when related content changes. Query: EXTRACT(DAY FROM (now() - last_validated_at)) for staleness in days';

-- Trigger: Mark related blocks as stale when new dump arrives in same basket
CREATE OR REPLACE FUNCTION mark_related_blocks_stale()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Mark blocks from previous dumps in same basket as potentially stale
  -- Force staleness by setting last_validated_at to 30 days ago
  UPDATE blocks
  SET last_validated_at = now() - interval '30 days'
  WHERE basket_id = NEW.basket_id
    AND raw_dump_id IN (
      SELECT id FROM raw_dumps
      WHERE basket_id = NEW.basket_id
      AND id != NEW.id
      AND created_at < NEW.created_at  -- Only older dumps
    )
    AND status NOT IN ('archived', 'rejected');  -- Don't mark archived blocks

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_mark_blocks_stale_on_new_dump
  AFTER INSERT ON raw_dumps
  FOR EACH ROW
  EXECUTE FUNCTION mark_related_blocks_stale();

COMMENT ON FUNCTION mark_related_blocks_stale IS 'Auto-marks blocks stale when new related dump arrives (signals context may have evolved)';

-- =====================================================
-- 3. CONTEXT-AWARE EXTRACTION: Helper views
-- =====================================================

-- View: Basket substrate summary for context-aware extraction
CREATE OR REPLACE VIEW basket_substrate_context AS
WITH ranked_blocks AS (
  SELECT
    b.id,
    b.basket_id,
    b.workspace_id,
    b.title,
    b.semantic_type,
    b.content,
    b.confidence_score,
    b.status,
    b.last_validated_at,
    COALESCE(bu.usefulness_score, 0.0) AS usefulness,
    ROW_NUMBER() OVER (
      PARTITION BY b.basket_id
      ORDER BY COALESCE(bu.usefulness_score, 0.0) DESC, b.created_at DESC
    ) AS rank
  FROM blocks b
  LEFT JOIN block_usage bu ON bu.block_id = b.id
  WHERE b.status NOT IN ('archived', 'rejected')
),
ranked_context_items AS (
  SELECT
    ci.id,
    ci.basket_id,
    ci.title,
    ci.semantic_meaning,
    ci.metadata,
    ci.state,
    ROW_NUMBER() OVER (
      PARTITION BY ci.basket_id
      ORDER BY ci.created_at DESC
    ) AS rank
  FROM context_items ci
  WHERE ci.state = 'ACTIVE'
)
SELECT
  bsk.id AS basket_id,
  bsk.workspace_id,

  -- Aggregate blocks (top 20 by usefulness)
  (
    SELECT jsonb_agg(jsonb_build_object(
      'id', rb.id,
      'title', rb.title,
      'semantic_type', rb.semantic_type,
      'content', LEFT(rb.content, 200),
      'confidence', rb.confidence_score,
      'usefulness', rb.usefulness,
      'staleness_days', EXTRACT(DAY FROM (now() - rb.last_validated_at))::int
    ))
    FROM ranked_blocks rb
    WHERE rb.basket_id = bsk.id AND rb.rank <= 20
  ) AS blocks_summary,

  -- Aggregate context items (top 20)
  (
    SELECT jsonb_agg(jsonb_build_object(
      'id', rci.id,
      'label', rci.title,
      'semantic_meaning', rci.semantic_meaning,
      'kind', rci.metadata->>'kind'
    ))
    FROM ranked_context_items rci
    WHERE rci.basket_id = bsk.id AND rci.rank <= 20
  ) AS context_items_summary,

  -- Stats
  (SELECT COUNT(*) FROM ranked_blocks rb WHERE rb.basket_id = bsk.id) AS active_blocks_count,
  (SELECT COUNT(*) FROM ranked_context_items rci WHERE rci.basket_id = bsk.id) AS active_context_items_count,

  -- Goals/constraints from blocks
  (
    SELECT string_agg(b.content, ' | ')
    FROM blocks b
    WHERE b.basket_id = bsk.id
      AND b.semantic_type IN ('goal', 'constraint')
      AND b.status NOT IN ('archived', 'rejected')
  ) AS goals_and_constraints

FROM baskets bsk;

COMMENT ON VIEW basket_substrate_context IS 'Aggregated basket substrate for context-aware P1 extraction';

-- =====================================================
-- 4. QUALITY METRICS: Track extraction effectiveness
-- =====================================================

CREATE TABLE IF NOT EXISTS extraction_quality_metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dump_id uuid REFERENCES raw_dumps(id) ON DELETE CASCADE,
  basket_id uuid REFERENCES baskets(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL,

  -- Extraction metadata
  agent_version text NOT NULL,
  extraction_method text NOT NULL,

  -- Quality metrics
  blocks_created int DEFAULT 0,
  context_items_created int DEFAULT 0,
  duplicates_detected int DEFAULT 0,
  orphans_created int DEFAULT 0,
  avg_confidence real DEFAULT 0.0,

  -- Performance
  processing_time_ms int,

  -- Outcomes (filled in over time)
  blocks_accepted int DEFAULT 0,
  blocks_rejected int DEFAULT 0,
  blocks_used int DEFAULT 0,  -- How many got referenced elsewhere

  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX idx_extraction_quality_basket ON extraction_quality_metrics(basket_id, created_at DESC);
CREATE INDEX idx_extraction_quality_workspace ON extraction_quality_metrics(workspace_id, created_at DESC);

COMMENT ON TABLE extraction_quality_metrics IS 'Tracks P1 extraction quality over time for continuous improvement';

-- Function to log extraction metrics
CREATE OR REPLACE FUNCTION log_extraction_metrics(
  p_dump_id uuid,
  p_basket_id uuid,
  p_workspace_id uuid,
  p_agent_version text,
  p_extraction_method text,
  p_blocks_created int,
  p_context_items_created int,
  p_avg_confidence real,
  p_processing_time_ms int
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_metric_id uuid;
BEGIN
  INSERT INTO extraction_quality_metrics (
    dump_id, basket_id, workspace_id, agent_version, extraction_method,
    blocks_created, context_items_created, avg_confidence, processing_time_ms
  ) VALUES (
    p_dump_id, p_basket_id, p_workspace_id, p_agent_version, p_extraction_method,
    p_blocks_created, p_context_items_created, p_avg_confidence, p_processing_time_ms
  )
  RETURNING id INTO v_metric_id;

  RETURN v_metric_id;
END;
$$;

COMMENT ON FUNCTION log_extraction_metrics IS 'Log extraction quality metrics for monitoring and improvement';

-- =====================================================
-- 5. AUTO-INCREMENT USAGE: Hook into substrate_references
-- =====================================================

-- When a block is attached to a document, increment usage
CREATE OR REPLACE FUNCTION auto_increment_block_usage_on_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only increment for block substrate types
  IF NEW.substrate_type = 'block' THEN
    PERFORM increment_block_usage(NEW.substrate_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_auto_increment_usage_on_substrate_reference
  AFTER INSERT ON substrate_references
  FOR EACH ROW
  EXECUTE FUNCTION auto_increment_block_usage_on_reference();

COMMENT ON FUNCTION auto_increment_block_usage_on_reference IS 'Auto-increment block usage when referenced in documents';

COMMIT;
