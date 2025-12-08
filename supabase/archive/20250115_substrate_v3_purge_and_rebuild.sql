-- =====================================================================
-- YARNNN Substrate Canon v3.0: Purge & Rebuild
-- =====================================================================
-- WARNING: This is a DESTRUCTIVE migration for pre-launch cleanup
-- Drops context_items table entirely
-- Rebuilds blocks table with emergent anchor architecture
-- Removes all legacy constraints and types
-- =====================================================================

BEGIN;

-- =====================================================================
-- PHASE 1: PURGE LEGACY
-- =====================================================================

-- Drop dependent views first (CASCADE will catch all dependencies)
DROP VIEW IF EXISTS anchored_substrate CASCADE;
DROP VIEW IF EXISTS document_composition_stats CASCADE;
DROP VIEW IF EXISTS document_staleness CASCADE;
DROP VIEW IF EXISTS vw_document_analyze_lite CASCADE;

-- Drop context_items table (no migration, pre-launch purge)
DROP TABLE IF EXISTS context_items CASCADE;

-- Drop legacy context_item_state enum
DROP TYPE IF EXISTS context_item_state CASCADE;

-- Drop legacy basket_anchor_definitions if exists
DROP TABLE IF EXISTS basket_anchor_definitions CASCADE;

-- =====================================================================
-- PHASE 2: CLEAN BLOCKS TABLE
-- =====================================================================

-- Drop old anchor constraints (fixed enums)
ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_anchor_role_check;
ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_anchor_status_check;

-- Drop old blocks_check constraint (CONSTANT scope requirement)
ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_check;

-- =====================================================================
-- PHASE 3: REBUILD BLOCKS TABLE FOR V3.0
-- =====================================================================

-- Ensure all required columns exist with correct types
-- (Most should already exist, this is defensive)

-- Add scope column if missing (should exist)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'blocks' AND column_name = 'scope'
    ) THEN
        ALTER TABLE blocks ADD COLUMN scope scope_level;
    END IF;
END $$;

-- Ensure workspace_id exists (should exist)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'blocks' AND column_name = 'workspace_id'
    ) THEN
        ALTER TABLE blocks ADD COLUMN workspace_id uuid NOT NULL;
    END IF;
END $$;

-- Ensure parent_block_id exists for versioning (should exist)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'blocks' AND column_name = 'parent_block_id'
    ) THEN
        ALTER TABLE blocks ADD COLUMN parent_block_id uuid REFERENCES blocks(id);
    END IF;
END $$;

-- Ensure version exists (should exist)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'blocks' AND column_name = 'version'
    ) THEN
        ALTER TABLE blocks ADD COLUMN version integer DEFAULT 1 NOT NULL;
    END IF;
END $$;

-- Ensure last_validated_at exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'blocks' AND column_name = 'last_validated_at'
    ) THEN
        ALTER TABLE blocks ADD COLUMN last_validated_at timestamp with time zone DEFAULT now();
    END IF;
END $$;

-- =====================================================================
-- PHASE 4: V3.0 CONSTRAINTS (Emergent Architecture)
-- =====================================================================

-- Emergent anchors: No CHECK constraint on anchor_role (free text)
-- Only validate status values
ALTER TABLE blocks ADD CONSTRAINT blocks_anchor_status_v3_check
    CHECK (anchor_status IS NULL OR anchor_status IN ('proposed', 'accepted', 'rejected'));

-- CONSTANT blocks must have scope (cross-basket memory)
ALTER TABLE blocks ADD CONSTRAINT blocks_constant_requires_scope
    CHECK (
        (state = 'CONSTANT' AND scope IS NOT NULL) OR
        (state != 'CONSTANT')
    );

-- Anchor confidence must be 0-1 if present
ALTER TABLE blocks ADD CONSTRAINT blocks_anchor_confidence_v3_check
    CHECK (
        anchor_confidence IS NULL OR
        (anchor_confidence >= 0.0 AND anchor_confidence <= 1.0)
    );

-- Content and title must not be empty
ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_content_not_empty;
ALTER TABLE blocks ADD CONSTRAINT blocks_content_not_empty
    CHECK (content IS NOT NULL AND content != '');

ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_title_not_empty;
ALTER TABLE blocks ADD CONSTRAINT blocks_title_not_empty
    CHECK (title IS NOT NULL AND title != '');

-- =====================================================================
-- PHASE 5: INDEXES FOR V3.0 QUERIES
-- =====================================================================

-- Drop old indexes (aggressive cleanup)
DROP INDEX IF EXISTS idx_blocks_basket;
DROP INDEX IF EXISTS idx_blocks_basket_state_time;
DROP INDEX IF EXISTS idx_blocks_workspace_scope;
DROP INDEX IF EXISTS idx_blocks_anchor;
DROP INDEX IF EXISTS idx_blocks_anchor_vocabulary;
DROP INDEX IF EXISTS idx_blocks_semantic_type;
DROP INDEX IF EXISTS idx_blocks_version_chain;
DROP INDEX IF EXISTS idx_blocks_anchor_confidence;
DROP INDEX IF EXISTS idx_blocks_recent_validated;
DROP INDEX IF EXISTS idx_blocks_constants;

-- V3.0 optimized indexes

-- Primary basket queries (state + temporal)
CREATE INDEX idx_blocks_basket_state_time ON blocks(basket_id, state, last_validated_at DESC)
    WHERE state = 'ACCEPTED';

-- Workspace-scoped memory (cross-basket)
CREATE INDEX idx_blocks_workspace_scope ON blocks(workspace_id, scope, state)
    WHERE scope IS NOT NULL;

-- Emergent anchor vocabulary discovery
CREATE INDEX idx_blocks_anchor_vocabulary ON blocks(basket_id, anchor_role, anchor_status)
    WHERE anchor_role IS NOT NULL;

-- Semantic type filtering (knowledge vs meaning vs structural)
CREATE INDEX idx_blocks_semantic_type ON blocks(basket_id, semantic_type, state);

-- Version chain traversal
CREATE INDEX idx_blocks_version_chain ON blocks(parent_block_id, version)
    WHERE parent_block_id IS NOT NULL;

-- Anchor confidence sorting
CREATE INDEX idx_blocks_anchor_confidence ON blocks(basket_id, anchor_confidence DESC)
    WHERE anchor_role IS NOT NULL AND anchor_status = 'accepted';

-- Recently validated (LLM short-term memory)
CREATE INDEX idx_blocks_recent_validated ON blocks(basket_id, last_validated_at DESC)
    WHERE state = 'ACCEPTED';

-- CONSTANT blocks (long-term memory)
CREATE INDEX idx_blocks_constants ON blocks(workspace_id, state, scope)
    WHERE state = 'CONSTANT';

-- =====================================================================
-- PHASE 6: UPDATE SUBSTRATE_RELATIONSHIPS
-- =====================================================================

-- First, update existing relationships pointing to context_items
UPDATE substrate_relationships
SET from_type = 'block'
WHERE from_type = 'context_item';

UPDATE substrate_relationships
SET to_type = 'block'
WHERE to_type = 'context_item';

-- Now remove context_item from substrate_type enum
DO $$
BEGIN
    -- Check if context_item exists in enum
    IF EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'context_item'
        AND enumtypid = 'substrate_type'::regtype
    ) THEN
        -- Cannot directly remove enum value in PostgreSQL
        -- Workaround: Recreate enum
        ALTER TYPE substrate_type RENAME TO substrate_type_old;

        CREATE TYPE substrate_type AS ENUM (
            'block',
            'dump',
            'event',
            'document'
        );

        -- Update substrate_relationships columns
        ALTER TABLE substrate_relationships
            ALTER COLUMN from_type TYPE substrate_type
            USING from_type::text::substrate_type;

        ALTER TABLE substrate_relationships
            ALTER COLUMN to_type TYPE substrate_type
            USING to_type::text::substrate_type;

        -- Update substrate_references table
        ALTER TABLE substrate_references
            ALTER COLUMN substrate_type TYPE substrate_type
            USING substrate_type::text::substrate_type;

        -- Drop old enum with CASCADE to update dependent views/functions
        DROP TYPE substrate_type_old CASCADE;

        -- Recreate functions that were dropped
        -- (These will be recreated with correct type automatically)
    END IF;
END $$;

-- =====================================================================
-- PHASE 7: V3.0 HELPER FUNCTIONS
-- =====================================================================

-- Function: Get basket's emergent anchor vocabulary
CREATE OR REPLACE FUNCTION get_basket_anchor_vocabulary(p_basket_id uuid)
RETURNS TABLE (
    anchor_role text,
    usage_count bigint,
    accepted_count bigint,
    avg_confidence numeric,
    semantic_types text[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.anchor_role,
        COUNT(*) as usage_count,
        COUNT(*) FILTER (WHERE b.anchor_status = 'accepted') as accepted_count,
        ROUND(AVG(b.anchor_confidence)::numeric, 2) as avg_confidence,
        ARRAY_AGG(DISTINCT b.semantic_type ORDER BY b.semantic_type) as semantic_types
    FROM blocks b
    WHERE b.basket_id = p_basket_id
        AND b.anchor_role IS NOT NULL
    GROUP BY b.anchor_role
    ORDER BY accepted_count DESC, usage_count DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get workspace constants (cross-basket memory)
CREATE OR REPLACE FUNCTION get_workspace_constants(p_workspace_id uuid)
RETURNS TABLE (
    id uuid,
    semantic_type text,
    title text,
    content text,
    anchor_role text,
    scope scope_level,
    created_at timestamp with time zone
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.semantic_type,
        b.title,
        b.content,
        b.anchor_role,
        b.scope,
        b.created_at
    FROM blocks b
    WHERE b.workspace_id = p_workspace_id
        AND b.state = 'CONSTANT'
        AND b.scope IN ('WORKSPACE', 'ORG', 'GLOBAL')
    ORDER BY b.scope DESC, b.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get block version history
CREATE OR REPLACE FUNCTION get_block_version_history(p_block_id uuid)
RETURNS TABLE (
    id uuid,
    version integer,
    title text,
    content text,
    state block_state,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE version_chain AS (
        -- Start with the given block
        SELECT
            b.id,
            b.parent_block_id,
            b.version,
            b.title,
            b.content,
            b.state,
            b.created_at,
            b.updated_at
        FROM blocks b
        WHERE b.id = p_block_id

        UNION ALL

        -- Recursively get parent versions
        SELECT
            b.id,
            b.parent_block_id,
            b.version,
            b.title,
            b.content,
            b.state,
            b.created_at,
            b.updated_at
        FROM blocks b
        INNER JOIN version_chain vc ON b.id = vc.parent_block_id
    )
    SELECT
        vc.id,
        vc.version,
        vc.title,
        vc.content,
        vc.state,
        vc.created_at,
        vc.updated_at
    FROM version_chain vc
    ORDER BY vc.version DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get basket substrate categorized by type
CREATE OR REPLACE FUNCTION get_basket_substrate_categorized(p_basket_id uuid)
RETURNS TABLE (
    category text,
    block_count bigint,
    semantic_types jsonb
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        CASE
            WHEN semantic_type IN ('fact', 'metric', 'event', 'insight', 'action', 'finding', 'quote', 'summary')
                THEN 'knowledge'
            WHEN semantic_type IN ('intent', 'objective', 'rationale', 'principle', 'assumption', 'context', 'constraint')
                THEN 'meaning'
            WHEN semantic_type IN ('entity', 'classification', 'reference')
                THEN 'structural'
            ELSE 'other'
        END as category,
        COUNT(*) as block_count,
        jsonb_object_agg(
            semantic_type,
            COUNT(*)
        ) as semantic_types
    FROM blocks
    WHERE basket_id = p_basket_id
        AND state = 'ACCEPTED'
    GROUP BY category;
END;
$$ LANGUAGE plpgsql STABLE;

-- =====================================================================
-- PHASE 8: RECREATE ANCHORED_SUBSTRATE VIEW
-- =====================================================================

CREATE OR REPLACE VIEW anchored_substrate AS
SELECT
    'block'::text AS substrate_type,
    b.id AS substrate_id,
    b.basket_id,
    b.workspace_id,
    b.anchor_role,
    b.anchor_status,
    b.anchor_confidence,
    b.title,
    b.content,
    b.semantic_type,
    b.state::text AS state,
    b.scope,
    b.created_at,
    b.updated_at,
    b.last_validated_at,
    b.metadata
FROM blocks b
WHERE b.anchor_role IS NOT NULL;

-- =====================================================================
-- PHASE 9: GRANT PERMISSIONS
-- =====================================================================

-- Grant access to service role
GRANT SELECT, INSERT, UPDATE, DELETE ON blocks TO service_role;
GRANT EXECUTE ON FUNCTION get_basket_anchor_vocabulary TO service_role;
GRANT EXECUTE ON FUNCTION get_workspace_constants TO service_role;
GRANT EXECUTE ON FUNCTION get_block_version_history TO service_role;
GRANT EXECUTE ON FUNCTION get_basket_substrate_categorized TO service_role;
GRANT SELECT ON anchored_substrate TO service_role;

-- Grant read access to authenticated users (via RLS)
GRANT SELECT ON blocks TO authenticated;
GRANT EXECUTE ON FUNCTION get_basket_anchor_vocabulary TO authenticated;
GRANT EXECUTE ON FUNCTION get_workspace_constants TO authenticated;
GRANT EXECUTE ON FUNCTION get_block_version_history TO authenticated;
GRANT EXECUTE ON FUNCTION get_basket_substrate_categorized TO authenticated;
GRANT SELECT ON anchored_substrate TO authenticated;

-- =====================================================================
-- PHASE 10: VALIDATION
-- =====================================================================

-- Verify blocks table structure
DO $$
DECLARE
    v_column_count integer;
BEGIN
    SELECT COUNT(*) INTO v_column_count
    FROM information_schema.columns
    WHERE table_name = 'blocks'
        AND column_name IN (
            'id', 'basket_id', 'workspace_id', 'semantic_type',
            'title', 'content', 'anchor_role', 'anchor_status',
            'anchor_confidence', 'state', 'scope', 'parent_block_id',
            'version', 'last_validated_at'
        );

    IF v_column_count < 14 THEN
        RAISE EXCEPTION 'Blocks table missing required columns for v3.0';
    END IF;

    RAISE NOTICE '✅ Blocks table structure validated (% columns)', v_column_count;
END $$;

-- Verify context_items is dropped
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'context_items'
    ) THEN
        RAISE EXCEPTION 'context_items table still exists';
    END IF;

    RAISE NOTICE '✅ context_items table successfully dropped';
END $$;

-- Verify substrate_type enum updated
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'context_item'
        AND enumtypid = 'substrate_type'::regtype
    ) THEN
        RAISE EXCEPTION 'context_item still in substrate_type enum';
    END IF;

    RAISE NOTICE '✅ substrate_type enum cleaned';
END $$;

COMMIT;

-- =====================================================================
-- MIGRATION COMPLETE
-- =====================================================================
-- Summary:
-- ✅ context_items table dropped
-- ✅ blocks table cleaned and v3.0 ready
-- ✅ Emergent anchor architecture enabled (no role constraints)
-- ✅ Universal versioning support
-- ✅ Scope elevation for cross-basket memory
-- ✅ Helper functions for v3.0 queries
-- ✅ Optimized indexes for LLM memory patterns
-- =====================================================================
