# Implementation Plan: Context Items Migration

**Date**: 2025-12-04
**Status**: Ready for Implementation
**ADR Reference**: [ADR_CONTEXT_ITEMS_UNIFIED.md](../architecture/ADR_CONTEXT_ITEMS_UNIFIED.md)

---

## Overview

This plan migrates from `context_entries` to `context_items` - a unified table supporting tiered context management with equal human/agent authorship.

**Key Changes**:
- Single `context_items` table replaces `context_entries`
- Tier column (foundation/working/ephemeral) replaces category-based separation
- Versioning/provenance columns added (nullable, Phase 2 implementation)
- Tags and embeddings for flexible retrieval
- Asset references updated

---

## Pre-Implementation Verification

### Current State Check

```sql
-- Check existing context_entries data
SELECT
    anchor_role,
    COUNT(*) as count
FROM context_entries
GROUP BY anchor_role;

-- Check asset references
SELECT COUNT(*)
FROM reference_assets
WHERE context_entry_id IS NOT NULL;
```

**Note**: Since we're pre-launch, existing data can be purged if migration is complex.

---

## Phase 1: Database Migration

### Step 1.1: Create context_items Table

```sql
-- Migration: 20251204_context_items_unified.sql

BEGIN;

-- ============================================================================
-- PART 1: Create Unified context_items Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS context_items (
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

    -- Authorship
    created_by TEXT NOT NULL,
    updated_by TEXT,

    -- Lifecycle
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'superseded')),
    expires_at TIMESTAMPTZ,

    -- PHASE 2: Versioning (present, not enforced)
    version INTEGER DEFAULT 1,
    previous_version_id UUID REFERENCES context_items(id),

    -- PHASE 2: Provenance (present, not enforced)
    source_type TEXT,
    source_ref JSONB,

    -- Completeness
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
CREATE INDEX idx_context_items_basket_tier ON context_items(basket_id, tier);
CREATE INDEX idx_context_items_type ON context_items(basket_id, item_type);
CREATE INDEX idx_context_items_tags ON context_items USING GIN(tags);
CREATE INDEX idx_context_items_active ON context_items(basket_id) WHERE status = 'active';
CREATE INDEX idx_context_items_schema ON context_items(schema_id) WHERE schema_id IS NOT NULL;
CREATE INDEX idx_context_items_expires ON context_items(expires_at) WHERE expires_at IS NOT NULL;

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
        WHEN 'insight' THEN 'working'  -- insights are working tier with TTL
        ELSE 'working'
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Migrate existing entries
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

-- Migrate existing references
UPDATE reference_assets
SET context_item_id = context_entry_id
WHERE context_entry_id IS NOT NULL;

-- Index for new column
CREATE INDEX IF NOT EXISTS idx_ref_assets_context_item
    ON reference_assets(context_item_id, context_field_key)
    WHERE context_item_id IS NOT NULL;

COMMENT ON COLUMN reference_assets.context_item_id IS
'Links asset to context item. If set, asset is permanent.
Replaces context_entry_id.';

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
-- PART 6: Deprecate context_entries
-- ============================================================================

COMMENT ON TABLE context_entries IS
'DEPRECATED (2025-12-04): Replaced by context_items table.
This table will be dropped after verification period.
See: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md';

COMMENT ON COLUMN reference_assets.context_entry_id IS
'DEPRECATED (2025-12-04): Use context_item_id instead.
This column will be dropped after verification period.';

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
    migrated_count INTEGER;
    ref_assets_updated INTEGER;
BEGIN
    SELECT COUNT(*) INTO items_count FROM context_items;
    SELECT COUNT(*) INTO migrated_count FROM context_items WHERE schema_id IS NOT NULL;
    SELECT COUNT(*) INTO ref_assets_updated FROM reference_assets WHERE context_item_id IS NOT NULL;

    RAISE NOTICE '';
    RAISE NOTICE '============================================================';
    RAISE NOTICE '✅ Migration: Context Items Unified (20251204) Complete';
    RAISE NOTICE '============================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Results:';
    RAISE NOTICE '  - context_items table created';
    RAISE NOTICE '  - % items total', items_count;
    RAISE NOTICE '  - % items migrated from context_entries', migrated_count;
    RAISE NOTICE '  - % asset references updated', ref_assets_updated;
    RAISE NOTICE '';
    RAISE NOTICE 'Deprecated:';
    RAISE NOTICE '  - context_entries table (marked for removal)';
    RAISE NOTICE '  - reference_assets.context_entry_id (use context_item_id)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next Steps:';
    RAISE NOTICE '  1. Update substrate-API routes';
    RAISE NOTICE '  2. Update ContextProvisioner service';
    RAISE NOTICE '  3. Update frontend components';
    RAISE NOTICE '  4. After verification, drop context_entries';
    RAISE NOTICE '============================================================';
END $$;

COMMIT;
```

### Step 1.2: Cleanup Migration (After Verification)

```sql
-- Migration: 20251205_context_entries_cleanup.sql
-- RUN ONLY AFTER VERIFYING context_items works correctly

BEGIN;

-- Drop deprecated column from reference_assets
ALTER TABLE reference_assets DROP COLUMN IF EXISTS context_entry_id;

-- Drop deprecated table
DROP TABLE IF EXISTS context_entries;

-- Update FK constraint comment
COMMENT ON COLUMN reference_assets.context_item_id IS
'Links asset to context item. If set, asset is permanent.';

RAISE NOTICE 'context_entries table and context_entry_id column removed';

COMMIT;
```

---

## Phase 2: Application Code Updates

### Step 2.1: Substrate-API Routes

**Files to Update**:
- `substrate-api/api/src/app/context/` - New directory

**New Routes**:

```
GET  /baskets/{id}/context-items                 # List all items
GET  /baskets/{id}/context-items?tier=foundation # Filter by tier
GET  /baskets/{id}/context-items/{type}          # Get by type
GET  /baskets/{id}/context-items/{type}/{key}    # Get specific item
POST /baskets/{id}/context-items                 # Create item
PUT  /baskets/{id}/context-items/{id}            # Update item
DELETE /baskets/{id}/context-items/{id}          # Archive item
```

### Step 2.2: ContextProvisioner Service

**File**: `work-platform/api/src/app/work/services/context_provisioner.py`

**Changes**:
- Query from `context_items` instead of `context_entries`
- Support tier-based filtering
- Update field projection logic

```python
# Key changes
async def provision_context(
    basket_id: str,
    roles: list[str] | None = None,
    tiers: list[str] | None = None,  # NEW
    tags: list[str] | None = None,   # NEW
) -> ContextProvisionResult:
    query = supabase.table("context_items") \
        .select("*") \
        .eq("basket_id", basket_id) \
        .eq("status", "active")

    if roles:
        query = query.in_("item_type", roles)
    if tiers:
        query = query.in_("tier", tiers)
    # ... rest of implementation
```

### Step 2.3: Frontend Components

**Files to Update**:
- `substrate-api/web/app/api/baskets/[id]/context/` - API routes
- `work-platform/web/app/projects/[id]/context/` - Context page

**Changes**:
- Update API calls to use new endpoints
- Update types/interfaces
- Minimal UI changes (tier badge instead of category)

---

## Phase 3: Thinking Partner Tools (Optional MVP)

### Tool Definitions

```python
# thinking_partner_tools.py

TOOLS = [
    {
        "name": "read_context",
        "description": "Read context items from the project substrate",
        "parameters": {
            "basket_id": {"type": "string", "required": True},
            "tier": {"type": "string", "enum": ["foundation", "working", "ephemeral"]},
            "item_type": {"type": "string"},
            "tags": {"type": "array", "items": {"type": "string"}}
        }
    },
    {
        "name": "write_context",
        "description": "Create or update a context item",
        "parameters": {
            "basket_id": {"type": "string", "required": True},
            "tier": {"type": "string", "required": True},
            "item_type": {"type": "string", "required": True},
            "content": {"type": "object", "required": True},
            "title": {"type": "string"},
            "tags": {"type": "array", "items": {"type": "string"}},
            "schema_id": {"type": "string"}
        }
    },
    {
        "name": "list_recipes",
        "description": "List available work recipes for the project",
        "parameters": {
            "basket_id": {"type": "string", "required": True}
        }
    },
    {
        "name": "trigger_work",
        "description": "Create a work ticket from a recipe",
        "parameters": {
            "basket_id": {"type": "string", "required": True},
            "recipe_slug": {"type": "string", "required": True},
            "params": {"type": "object"}
        }
    }
]
```

---

## Verification Checklist

### After Phase 1 (Database)

- [ ] `context_items` table exists with correct schema
- [ ] All `context_entries` data migrated
- [ ] `reference_assets.context_item_id` populated
- [ ] RLS policies working
- [ ] Indexes created

### After Phase 2 (Application)

- [ ] Substrate-API routes responding
- [ ] ContextProvisioner using new table
- [ ] Frontend context page working
- [ ] Work recipes executing with context

### Before Cleanup

- [ ] No queries to `context_entries` in application code
- [ ] No references to `context_entry_id` in application code
- [ ] All tests passing
- [ ] Production verified for 24+ hours

---

## Rollback Plan

If issues arise:

1. **Database**: `context_entries` remains intact until cleanup migration
2. **Application**: Feature flag to switch between old/new table
3. **Full rollback**: Revert application code, data still in `context_entries`

---

## Timeline

| Day | Phase | Tasks |
|-----|-------|-------|
| 1 | Database | Run migration, verify data |
| 1-2 | API | Update substrate-API routes |
| 2 | Backend | Update ContextProvisioner |
| 2-3 | Frontend | Update context page |
| 3 | Testing | End-to-end verification |
| 4+ | Cleanup | Drop deprecated table/column |

---

## Open Items

1. **Thinking Partner MVP**: Build after core migration or in parallel?
2. **Embedding generation**: When/how to populate embeddings for semantic search?
3. **Ephemeral TTL**: Default expiration for ephemeral tier items?

---

**Document Status**: Ready for Implementation
**Last Updated**: 2025-12-04
