-- Migration: Context Items Unified Architecture
-- Date: 2025-12-04
-- Purpose: Replace context_entries with unified context_items table
--
-- This migration:
-- 1. Creates context_items table with tiered governance
-- 2. Migrates data from context_entries
-- 3. Updates reference_assets to use context_item_id
-- 4. DROPS context_entries table (no legacy approach)
--
-- ADR Reference: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md

BEGIN;

-- ============================================================================
-- PART 0: Drop Legacy context_items Table (Different Schema)
-- ============================================================================

-- There's an old context_items table with incompatible schema
-- Pre-launch, no data, safe to drop and recreate
DROP TABLE IF EXISTS context_items CASCADE;

-- ============================================================================
-- PART 1: Create Unified context_items Table
-- ============================================================================

CREATE TABLE context_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,

    -- Classification
    tier TEXT NOT NULL CHECK (tier IN ('foundation', 'working', 'ephemeral')),
    item_type TEXT NOT NULL,
    item_key TEXT,

    -- Content
    title TEXT,
    content JSONB NOT NULL DEFAULT '{}',

    -- Schema reference (for structured types)
    schema_id TEXT REFERENCES context_entry_schemas(anchor_role),

    -- Multi-modal support
    asset_ids UUID[] DEFAULT '{}',

    -- Retrieval support
    tags TEXT[] DEFAULT '{}',
    embedding VECTOR(1536),

    -- Authorship (human OR agent, equal access)
    created_by TEXT NOT NULL,
    updated_by TEXT,

    -- Lifecycle
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'superseded')),
    expires_at TIMESTAMPTZ,

    -- PHASE 2: Versioning (columns present, not enforced yet)
    version INTEGER DEFAULT 1,
    previous_version_id UUID REFERENCES context_items(id),

    -- PHASE 2: Provenance (columns present, not enforced yet)
    source_type TEXT,
    source_ref JSONB,

    -- Completeness (for structured types)
    completeness_score FLOAT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    -- Constraints
    UNIQUE(basket_id, item_type, item_key)
);

-- Comments
COMMENT ON TABLE context_items IS
'Unified context storage with tiered governance.
Tiers: foundation (stable), working (accumulating), ephemeral (temporary).
Replaces context_entries table.
See: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md';

COMMENT ON COLUMN context_items.tier IS 'Governance tier: foundation (high), working (medium), ephemeral (low)';
COMMENT ON COLUMN context_items.item_type IS 'Context type: problem, customer, vision, brand, competitor, note, insight, etc.';
COMMENT ON COLUMN context_items.item_key IS 'For non-singleton types, identifies specific entry';
COMMENT ON COLUMN context_items.schema_id IS 'Optional reference to context_entry_schemas for structured types';
COMMENT ON COLUMN context_items.created_by IS 'Author: "user:{id}" or "agent:{type}"';
COMMENT ON COLUMN context_items.version IS 'PHASE 2: Version number for this item';
COMMENT ON COLUMN context_items.previous_version_id IS 'PHASE 2: Link to previous version';
COMMENT ON COLUMN context_items.source_type IS 'PHASE 2: Origin of content (manual, extracted, generated, imported)';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_context_items_basket_tier ON context_items(basket_id, tier);
CREATE INDEX IF NOT EXISTS idx_context_items_type ON context_items(basket_id, item_type);
CREATE INDEX IF NOT EXISTS idx_context_items_tags ON context_items USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_context_items_active ON context_items(basket_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_context_items_schema ON context_items(schema_id) WHERE schema_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_context_items_expires ON context_items(expires_at) WHERE expires_at IS NOT NULL;

-- ============================================================================
-- PART 2: RLS Policies
-- ============================================================================

ALTER TABLE context_items ENABLE ROW LEVEL SECURITY;

-- Select: workspace members
CREATE POLICY "context_items_select_workspace_members"
ON context_items FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_items.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Insert: workspace members
CREATE POLICY "context_items_insert_workspace_members"
ON context_items FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_items.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Update: workspace members
CREATE POLICY "context_items_update_workspace_members"
ON context_items FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_items.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Delete: workspace members
CREATE POLICY "context_items_delete_workspace_members"
ON context_items FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_items.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Service role: full access
CREATE POLICY "context_items_service_role"
ON context_items FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- ============================================================================
-- PART 3: Migrate Data from context_entries
-- ============================================================================

-- Tier mapping function
CREATE OR REPLACE FUNCTION map_category_to_tier(category TEXT) RETURNS TEXT AS $$
BEGIN
    RETURN CASE category
        WHEN 'foundation' THEN 'foundation'
        WHEN 'market' THEN 'working'
        WHEN 'insight' THEN 'working'
        ELSE 'working'
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Migrate existing entries (if any exist)
INSERT INTO context_items (
    id,
    basket_id,
    tier,
    item_type,
    item_key,
    title,
    content,
    schema_id,
    status,
    completeness_score,
    created_by,
    created_at,
    updated_at
)
SELECT
    ce.id,
    ce.basket_id,
    map_category_to_tier(ces.category) AS tier,
    ce.anchor_role AS item_type,
    ce.entry_key AS item_key,
    ce.display_name AS title,
    ce.data AS content,
    ce.anchor_role AS schema_id,
    ce.state AS status,
    ce.completeness_score,
    COALESCE('user:' || ce.created_by::text, 'user:system') AS created_by,
    ce.created_at,
    ce.updated_at
FROM context_entries ce
JOIN context_entry_schemas ces ON ces.anchor_role = ce.anchor_role
ON CONFLICT (basket_id, item_type, item_key) DO NOTHING;

-- Drop migration function
DROP FUNCTION IF EXISTS map_category_to_tier;

-- ============================================================================
-- PART 4: Update reference_assets
-- ============================================================================

-- Add new column
ALTER TABLE reference_assets
    ADD COLUMN IF NOT EXISTS context_item_id UUID;

-- Migrate existing references
UPDATE reference_assets
SET context_item_id = context_entry_id
WHERE context_entry_id IS NOT NULL;

-- Add FK constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'ref_assets_context_item_fk'
    ) THEN
        ALTER TABLE reference_assets
            ADD CONSTRAINT ref_assets_context_item_fk
            FOREIGN KEY (context_item_id)
            REFERENCES context_items(id)
            ON DELETE SET NULL;
    END IF;
END $$;

-- Index for new column
CREATE INDEX IF NOT EXISTS idx_ref_assets_context_item
    ON reference_assets(context_item_id, context_field_key)
    WHERE context_item_id IS NOT NULL;

COMMENT ON COLUMN reference_assets.context_item_id IS
'Links asset to context item. If set, asset is permanent.';

-- ============================================================================
-- PART 5: Helper Functions
-- ============================================================================

-- Updated timestamp trigger
CREATE OR REPLACE FUNCTION update_context_item_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_context_items_updated_at ON context_items;
CREATE TRIGGER trg_context_items_updated_at
BEFORE UPDATE ON context_items
FOR EACH ROW EXECUTE FUNCTION update_context_item_timestamp();

-- Ephemeral cleanup function
CREATE OR REPLACE FUNCTION cleanup_expired_context_items()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM context_items
    WHERE tier = 'ephemeral'
      AND expires_at IS NOT NULL
      AND expires_at < now();

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 6: DROP Legacy Tables and Columns (NO DUAL APPROACH)
-- ============================================================================

-- Drop FK constraint from reference_assets to context_entries
ALTER TABLE reference_assets
    DROP CONSTRAINT IF EXISTS ref_assets_context_entry_fk;

-- Drop the deprecated column
ALTER TABLE reference_assets
    DROP COLUMN IF EXISTS context_entry_id;

-- Drop the context_entries table entirely
DROP TABLE IF EXISTS context_entries CASCADE;

-- ============================================================================
-- PART 7: Grants
-- ============================================================================

GRANT ALL ON context_items TO service_role;
GRANT ALL ON context_items TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
    items_count INTEGER;
    schemas_count INTEGER;
    context_entries_exists BOOLEAN;
    context_entry_id_exists BOOLEAN;
BEGIN
    SELECT COUNT(*) INTO items_count FROM context_items;
    SELECT COUNT(*) INTO schemas_count FROM context_entry_schemas;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'context_entries'
    ) INTO context_entries_exists;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'reference_assets'
        AND column_name = 'context_entry_id'
    ) INTO context_entry_id_exists;

    RAISE NOTICE '';
    RAISE NOTICE '============================================================';
    RAISE NOTICE '✅ Migration: Context Items Unified (20251204) Complete';
    RAISE NOTICE '============================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Created:';
    RAISE NOTICE '  - context_items table with % items', items_count;
    RAISE NOTICE '  - % context entry schemas available', schemas_count;
    RAISE NOTICE '';
    RAISE NOTICE 'Removed (NO LEGACY):';
    RAISE NOTICE '  - context_entries table: %', CASE WHEN context_entries_exists THEN 'STILL EXISTS (ERROR)' ELSE 'DROPPED ✓' END;
    RAISE NOTICE '  - reference_assets.context_entry_id: %', CASE WHEN context_entry_id_exists THEN 'STILL EXISTS (ERROR)' ELSE 'DROPPED ✓' END;
    RAISE NOTICE '';
    RAISE NOTICE 'New columns:';
    RAISE NOTICE '  - reference_assets.context_item_id: added';
    RAISE NOTICE '';
    RAISE NOTICE 'ADR: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md';
    RAISE NOTICE '============================================================';

    -- Fail if legacy still exists
    IF context_entries_exists THEN
        RAISE EXCEPTION 'context_entries table was not dropped!';
    END IF;

    IF context_entry_id_exists THEN
        RAISE EXCEPTION 'reference_assets.context_entry_id was not dropped!';
    END IF;
END $$;

COMMIT;
