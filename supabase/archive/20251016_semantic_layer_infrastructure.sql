-- ============================================================================
-- V3.1 Semantic Layer Infrastructure - Clean Replacement
-- ============================================================================
-- Purpose: Add vector embeddings and causal relationships to substrate
-- Scope: blocks table (ACCEPTED+ state only), causal block relationships
-- Strategy: Clean replacement (drop legacy generic relationships)
-- Reference: docs/V3.1_IMPLEMENTATION_SEQUENCING.md
-- Canon: YARNNN_CANON.md v3.1, SEMANTIC_LAYER_INTEGRATION_DESIGN.md

-- ============================================================================
-- 1. Enable pgvector extension
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS vector;

COMMENT ON EXTENSION vector IS
'V3.1: pgvector for semantic similarity search on substrate blocks';

-- ============================================================================
-- 2. Add embedding column to blocks table
-- ============================================================================

-- Add embedding column (1536 dimensions for text-embedding-3-small)
ALTER TABLE public.blocks
ADD COLUMN IF NOT EXISTS embedding vector(1536);

-- Create comment explaining embedding strategy
COMMENT ON COLUMN public.blocks.embedding IS
'V3.1: Vector embedding (text-embedding-3-small, 1536d) for semantic search. Generated async after ACCEPTED state. Used by P1 (duplicate detection), P2 (relationship inference), P3/P4 (semantic retrieval). Only ACCEPTED+ blocks embedded (refined context, not raw dumps).';

-- ============================================================================
-- 3. Create pgvector indexes for similarity search
-- ============================================================================

-- IVFFlat index for cosine similarity (all blocks)
-- lists=100 is appropriate for 10K-100K vectors per basket
CREATE INDEX IF NOT EXISTS blocks_embedding_idx ON public.blocks
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100)
WHERE embedding IS NOT NULL;

-- Partial index: only ACCEPTED+ blocks (optimization for P1-P4 queries)
CREATE INDEX IF NOT EXISTS blocks_embedding_accepted_idx ON public.blocks
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100)
WHERE state IN ('ACCEPTED', 'LOCKED', 'CONSTANT')
AND embedding IS NOT NULL;

-- Composite index for hybrid search (basket + semantic_type + embedding)
CREATE INDEX IF NOT EXISTS blocks_basket_embedding_idx ON public.blocks (basket_id, semantic_type)
WHERE embedding IS NOT NULL;

COMMENT ON INDEX blocks_embedding_accepted_idx IS
'V3.1: Optimized index for semantic search on accepted substrate only';

-- ============================================================================
-- 4. DROP legacy substrate_relationships table (clean replacement)
-- ============================================================================

-- Drop legacy table (generic graph, not causal semantics)
-- This table supported block/dump/event/document relationships
-- V3.1 uses causal block-only relationships for semantic reasoning

DROP TABLE IF EXISTS public.substrate_relationships CASCADE;

-- ============================================================================
-- 5. CREATE v3.1 substrate_relationships table (causal semantics)
-- ============================================================================

CREATE TABLE public.substrate_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Core causal relationship (blocks only)
    from_block_id UUID NOT NULL REFERENCES public.blocks(id) ON DELETE CASCADE,
    to_block_id UUID NOT NULL REFERENCES public.blocks(id) ON DELETE CASCADE,
    relationship_type TEXT NOT NULL,

    -- Confidence and provenance (semantic intelligence)
    confidence_score DECIMAL(3,2),
    inference_method TEXT,

    -- Governance lifecycle (substrate is governed)
    state public.block_state NOT NULL DEFAULT 'PROPOSED',

    -- Metadata (LLM reasoning, semantic scores)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    metadata JSONB DEFAULT '{}'::jsonb,

    -- Constraints (causal semantics)
    CONSTRAINT no_self_reference CHECK (from_block_id != to_block_id),
    CONSTRAINT unique_relationship UNIQUE (from_block_id, to_block_id, relationship_type),
    CONSTRAINT valid_relationship_type CHECK (relationship_type IN ('addresses', 'supports', 'contradicts', 'depends_on')),
    CONSTRAINT valid_confidence_score CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    CONSTRAINT valid_inference_method CHECK (inference_method IS NULL OR inference_method IN ('semantic_search', 'llm_verification', 'user_created', 'agent_inferred'))
);

-- Add table and column comments (canon documentation)
COMMENT ON TABLE public.substrate_relationships IS
'V3.1: Causal relationships between substrate blocks. Inferred by P2 agent using semantic search + LLM verification. Four types: addresses (solution→problem), supports (evidence→claim), contradicts (conflicts), depends_on (prerequisite). Governed like substrate (PROPOSED→ACCEPTED).';

COMMENT ON COLUMN public.substrate_relationships.relationship_type IS
'Causal relationship types:
- addresses: Solution/action addresses problem/constraint
- supports: Evidence/finding supports claim/objective
- contradicts: Conflicts with existing statement
- depends_on: Prerequisite dependency (X requires Y first)';

COMMENT ON COLUMN public.substrate_relationships.confidence_score IS
'LLM-generated confidence (0.0-1.0). High confidence (>0.90) auto-accepted, medium (0.70-0.90) proposed for review, low (<0.70) rejected.';

COMMENT ON COLUMN public.substrate_relationships.inference_method IS
'Provenance tracking:
- semantic_search: Found via vector similarity
- llm_verification: LLM confirmed causal relationship
- user_created: Manual override by user
- agent_inferred: P2 agent proposed automatically';

COMMENT ON COLUMN public.substrate_relationships.state IS
'Governance lifecycle: PROPOSED (pending review), ACCEPTED (validated), REJECTED (invalid). Aligns with block governance model.';

-- ============================================================================
-- 6. Indexes for relationship traversal (graph queries)
-- ============================================================================

-- Forward traversal (from_block → related blocks)
CREATE INDEX relationships_from_block_idx
ON public.substrate_relationships(from_block_id)
WHERE state = 'ACCEPTED';

-- Backward traversal (to_block ← related blocks)
CREATE INDEX relationships_to_block_idx
ON public.substrate_relationships(to_block_id)
WHERE state = 'ACCEPTED';

-- Relationship type filter (for type-specific queries)
CREATE INDEX relationships_type_idx
ON public.substrate_relationships(relationship_type)
WHERE state = 'ACCEPTED';

-- Composite index for graph queries (optimized for traverse_relationships)
CREATE INDEX relationships_graph_query_idx
ON public.substrate_relationships(relationship_type, from_block_id, state);

-- Confidence-based queries (high confidence auto-accept)
CREATE INDEX relationships_confidence_idx
ON public.substrate_relationships(confidence_score DESC)
WHERE state = 'PROPOSED' AND confidence_score IS NOT NULL;

COMMENT ON INDEX relationships_graph_query_idx IS
'V3.1: Optimized for recursive graph traversal queries by relationship type';

-- ============================================================================
-- 7. RLS Policies for substrate_relationships
-- ============================================================================

ALTER TABLE public.substrate_relationships ENABLE ROW LEVEL SECURITY;

-- Users can view relationships in their workspace baskets
CREATE POLICY "Users can view relationships in their workspace baskets"
ON public.substrate_relationships FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.blocks b
        JOIN public.baskets bsk ON b.basket_id = bsk.id
        JOIN public.workspace_memberships wm ON bsk.workspace_id = wm.workspace_id
        WHERE b.id = substrate_relationships.from_block_id
        AND wm.user_id = auth.uid()
    )
);

-- Users can create relationships in their workspace baskets
CREATE POLICY "Users can create relationships in their workspace baskets"
ON public.substrate_relationships FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.blocks b
        JOIN public.baskets bsk ON b.basket_id = bsk.id
        JOIN public.workspace_memberships wm ON bsk.workspace_id = wm.workspace_id
        WHERE b.id = substrate_relationships.from_block_id
        AND wm.user_id = auth.uid()
    )
);

-- Users can update relationships they created or in their workspace
CREATE POLICY "Users can update relationships in their workspace"
ON public.substrate_relationships FOR UPDATE
USING (
    created_by = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.blocks b
        JOIN public.baskets bsk ON b.basket_id = bsk.id
        JOIN public.workspace_memberships wm ON bsk.workspace_id = wm.workspace_id
        WHERE b.id = substrate_relationships.from_block_id
        AND wm.user_id = auth.uid()
    )
);

-- Service role can manage all relationships (for agent operations)
CREATE POLICY "Service role can manage all relationships"
ON public.substrate_relationships FOR ALL
USING (auth.jwt() ->> 'role' = 'service_role')
WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================================
-- 8. Triggers for substrate_relationships
-- ============================================================================

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.update_substrate_relationships_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_substrate_relationships_updated_at
BEFORE UPDATE ON public.substrate_relationships
FOR EACH ROW
EXECUTE FUNCTION public.update_substrate_relationships_updated_at();

-- ============================================================================
-- 9. Helper function: semantic_search_blocks (database-level optimization)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.semantic_search_blocks(
    p_basket_id UUID,
    p_query_embedding vector(1536),
    p_semantic_types TEXT[] DEFAULT NULL,
    p_anchor_roles TEXT[] DEFAULT NULL,
    p_states TEXT[] DEFAULT ARRAY['ACCEPTED', 'LOCKED', 'CONSTANT'],
    p_min_similarity DECIMAL DEFAULT 0.70,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    basket_id UUID,
    content TEXT,
    semantic_type TEXT,
    anchor_role TEXT,
    state TEXT,
    metadata JSONB,
    similarity_score DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.basket_id,
        b.content,
        b.semantic_type,
        b.anchor_role,
        b.state::TEXT,
        b.metadata,
        (1 - (b.embedding <=> p_query_embedding))::DECIMAL AS similarity_score
    FROM public.blocks b
    WHERE b.basket_id = p_basket_id
        AND b.embedding IS NOT NULL
        AND (p_semantic_types IS NULL OR b.semantic_type = ANY(p_semantic_types))
        AND (p_anchor_roles IS NULL OR b.anchor_role = ANY(p_anchor_roles))
        AND b.state::TEXT = ANY(p_states)
        AND (1 - (b.embedding <=> p_query_embedding)) >= p_min_similarity
    ORDER BY b.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.semantic_search_blocks IS
'V3.1: Hybrid semantic search within basket. Combines vector similarity with structured filters (type, role, state). Returns blocks with similarity >= min_similarity, ordered by relevance. Used by P1 (duplicate detection), P3/P4 (context retrieval).';

-- ============================================================================
-- 10. Helper function: semantic_search_cross_basket (workspace scope)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.semantic_search_cross_basket(
    p_workspace_id UUID,
    p_query_embedding vector(1536),
    p_scopes TEXT[] DEFAULT ARRAY['WORKSPACE', 'GLOBAL'],
    p_semantic_types TEXT[] DEFAULT NULL,
    p_min_similarity DECIMAL DEFAULT 0.70,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    basket_id UUID,
    content TEXT,
    semantic_type TEXT,
    anchor_role TEXT,
    scope TEXT,
    similarity_score DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.basket_id,
        b.content,
        b.semantic_type,
        b.anchor_role,
        b.scope::TEXT,
        (1 - (b.embedding <=> p_query_embedding))::DECIMAL AS similarity_score
    FROM public.blocks b
    JOIN public.baskets bsk ON b.basket_id = bsk.id
    WHERE bsk.workspace_id = p_workspace_id
        AND b.embedding IS NOT NULL
        AND b.scope::TEXT = ANY(p_scopes)
        AND b.state IN ('ACCEPTED', 'LOCKED', 'CONSTANT')
        AND (p_semantic_types IS NULL OR b.semantic_type = ANY(p_semantic_types))
        AND (1 - (b.embedding <=> p_query_embedding)) >= p_min_similarity
    ORDER BY b.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.semantic_search_cross_basket IS
'V3.1: Cross-basket semantic search for scope elevation detection. Searches workspace/global scoped blocks across all baskets. Used for pattern discovery and knowledge reuse.';

-- ============================================================================
-- 11. Helper function: traverse_relationships (graph traversal)
-- ============================================================================

-- Drop existing function if signature changed
DROP FUNCTION IF EXISTS public.traverse_relationships(UUID, TEXT, TEXT, INT);

CREATE OR REPLACE FUNCTION public.traverse_relationships(
    p_start_block_id UUID,
    p_relationship_type TEXT,
    p_direction TEXT DEFAULT 'forward', -- 'forward' or 'backward'
    p_max_depth INT DEFAULT 2
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    semantic_type TEXT,
    anchor_role TEXT,
    depth INT,
    relationship_type TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE relationship_chain AS (
        -- Base case: start block
        SELECT
            b.id,
            b.content,
            b.semantic_type,
            b.anchor_role,
            0 AS depth,
            ''::TEXT AS relationship_type
        FROM public.blocks b
        WHERE b.id = p_start_block_id

        UNION ALL

        -- Recursive case: follow relationships
        SELECT
            b.id,
            b.content,
            b.semantic_type,
            b.anchor_role,
            rc.depth + 1,
            r.relationship_type
        FROM relationship_chain rc
        JOIN public.substrate_relationships r ON
            CASE
                WHEN p_direction = 'forward' THEN rc.id = r.from_block_id
                ELSE rc.id = r.to_block_id
            END
        JOIN public.blocks b ON
            CASE
                WHEN p_direction = 'forward' THEN r.to_block_id = b.id
                ELSE r.from_block_id = b.id
            END
        WHERE rc.depth < p_max_depth
            AND r.relationship_type = p_relationship_type
            AND r.state = 'ACCEPTED'
    )
    SELECT DISTINCT ON (relationship_chain.id)
        relationship_chain.id,
        relationship_chain.content,
        relationship_chain.semantic_type,
        relationship_chain.anchor_role,
        relationship_chain.depth,
        relationship_chain.relationship_type
    FROM relationship_chain
    WHERE relationship_chain.depth > 0  -- Exclude start block
    ORDER BY relationship_chain.id, relationship_chain.depth;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.traverse_relationships IS
'V3.1: Recursive graph traversal following specific causal relationship type. Direction: forward (from→to) or backward (to→from). Returns blocks up to max_depth. Used by P3 (causal reasoning for "why" questions) and P4 (narrative flow).';

-- ============================================================================
-- 12. Grant permissions
-- ============================================================================

-- Grant execute on helper functions to authenticated users
GRANT EXECUTE ON FUNCTION public.semantic_search_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION public.semantic_search_cross_basket TO authenticated;
GRANT EXECUTE ON FUNCTION public.traverse_relationships TO authenticated;

-- Service role needs full access for agent operations
GRANT ALL ON public.substrate_relationships TO service_role;

-- ============================================================================
-- 13. Migration validation
-- ============================================================================

DO $$
DECLARE
    embedding_col_exists BOOLEAN;
    relationships_table_exists BOOLEAN;
    pgvector_installed BOOLEAN;
BEGIN
    -- Verify pgvector extension
    SELECT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'vector'
    ) INTO pgvector_installed;

    IF NOT pgvector_installed THEN
        RAISE EXCEPTION 'pgvector extension not installed';
    END IF;

    -- Verify blocks.embedding column exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'blocks'
        AND column_name = 'embedding'
    ) INTO embedding_col_exists;

    IF NOT embedding_col_exists THEN
        RAISE EXCEPTION 'blocks.embedding column not created';
    END IF;

    -- Verify substrate_relationships table exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'substrate_relationships'
    ) INTO relationships_table_exists;

    IF NOT relationships_table_exists THEN
        RAISE EXCEPTION 'substrate_relationships table not created';
    END IF;

    RAISE NOTICE '✅ V3.1 Semantic Layer Infrastructure migration completed successfully';
    RAISE NOTICE '📊 Embeddings: blocks.embedding column added';
    RAISE NOTICE '🔗 Relationships: Causal block relationships table created (addresses, supports, contradicts, depends_on)';
    RAISE NOTICE '🔍 Indexes: pgvector IVFFlat indexes created';
    RAISE NOTICE '⚠️  BREAKING: Legacy substrate_relationships table dropped (clean replacement)';
    RAISE NOTICE '📝 Next: Implement semantic_primitives.py API layer';
END $$;
