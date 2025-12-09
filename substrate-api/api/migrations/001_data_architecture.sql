-- ============================================================================
-- CLEARINGHOUSE DATA ARCHITECTURE MIGRATION
-- Version: 1.0
-- Date: 2025-12-09
--
-- Run this migration in Supabase SQL Editor to enable:
-- - Vector embeddings storage (pgvector)
-- - Reference assets management
-- - Processing jobs for async embedding generation
-- - Enhanced semantic metadata on rights entities
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For text search optimization

-- ============================================================================
-- 1. ENHANCE RIGHTS_ENTITIES TABLE
-- ============================================================================

-- Add embedding and processing status
ALTER TABLE rights_entities
ADD COLUMN IF NOT EXISTS embedding_status TEXT DEFAULT 'pending'
    CHECK (embedding_status IN ('pending', 'processing', 'ready', 'failed', 'skipped'));

ALTER TABLE rights_entities
ADD COLUMN IF NOT EXISTS processing_error TEXT;

-- Add semantic metadata (hybrid schema)
ALTER TABLE rights_entities
ADD COLUMN IF NOT EXISTS semantic_metadata JSONB DEFAULT '{
    "primary_tags": [],
    "mood": [],
    "energy": null,
    "language": null,
    "explicit_content": false,
    "type_fields": {},
    "custom_tags": [],
    "ai_analysis": null
}'::jsonb;

-- Add extensions field for future flexibility
ALTER TABLE rights_entities
ADD COLUMN IF NOT EXISTS extensions JSONB DEFAULT '{}';

-- Index for semantic queries
CREATE INDEX IF NOT EXISTS idx_entities_semantic_tags
ON rights_entities USING gin ((semantic_metadata->'primary_tags'));

CREATE INDEX IF NOT EXISTS idx_entities_mood
ON rights_entities USING gin ((semantic_metadata->'mood'));

CREATE INDEX IF NOT EXISTS idx_entities_embedding_status
ON rights_entities (embedding_status);

-- ============================================================================
-- 2. REFERENCE ASSETS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS reference_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rights_entity_id UUID NOT NULL REFERENCES rights_entities(id) ON DELETE CASCADE,

    -- Asset identification
    asset_type TEXT NOT NULL CHECK (asset_type IN (
        'audio_master', 'audio_preview', 'audio_stem',
        'lyrics', 'sheet_music', 'artwork', 'photo',
        'contract', 'certificate', 'other'
    )),
    filename TEXT NOT NULL,
    mime_type TEXT,
    file_size_bytes BIGINT,

    -- Storage location
    storage_bucket TEXT NOT NULL DEFAULT 'reference-assets',
    storage_path TEXT NOT NULL,
    is_public BOOLEAN DEFAULT false,

    -- Audio-specific metadata
    duration_seconds NUMERIC,
    sample_rate INTEGER,
    channels INTEGER,
    bit_depth INTEGER,

    -- Processing
    processing_status TEXT DEFAULT 'uploaded'
        CHECK (processing_status IN ('uploaded', 'processing', 'ready', 'failed')),
    processing_error TEXT,
    extracted_metadata JSONB DEFAULT '{}',

    -- Audit
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assets_entity ON reference_assets(rights_entity_id);
CREATE INDEX IF NOT EXISTS idx_assets_type ON reference_assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_assets_status ON reference_assets(processing_status);

-- ============================================================================
-- 3. ENTITY EMBEDDINGS TABLE (pgvector)
-- ============================================================================

CREATE TABLE IF NOT EXISTS entity_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rights_entity_id UUID NOT NULL REFERENCES rights_entities(id) ON DELETE CASCADE,

    -- Embedding identification
    embedding_type TEXT NOT NULL CHECK (embedding_type IN (
        'text_description', 'text_lyrics', 'audio_full', 'audio_segment',
        'visual', 'combined'
    )),
    source_asset_id UUID REFERENCES reference_assets(id) ON DELETE SET NULL,

    -- Model information
    model_id TEXT NOT NULL,
    model_version TEXT,

    -- The embedding vector (1536 dims for OpenAI text-embedding-3-small)
    embedding vector(1536),

    -- Segment info (for chunked embeddings)
    segment_index INTEGER DEFAULT 0,
    segment_start_ms INTEGER,
    segment_end_ms INTEGER,

    -- Metadata
    metadata JSONB DEFAULT '{}',

    -- Audit
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_embeddings_entity ON entity_embeddings(rights_entity_id);
CREATE INDEX IF NOT EXISTS idx_embeddings_type ON entity_embeddings(embedding_type);

-- Vector similarity index (HNSW for small/medium datasets)
CREATE INDEX IF NOT EXISTS idx_embeddings_vector_hnsw ON entity_embeddings
    USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- 4. PROCESSING JOBS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS processing_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Job scope
    job_type TEXT NOT NULL CHECK (job_type IN (
        'embedding_generation', 'asset_analysis', 'metadata_extraction',
        'fingerprint_generation', 'batch_import'
    )),
    rights_entity_id UUID REFERENCES rights_entities(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES reference_assets(id) ON DELETE CASCADE,

    -- Status
    status TEXT DEFAULT 'queued'
        CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'cancelled')),
    priority INTEGER DEFAULT 0,

    -- Execution tracking
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,

    -- Job data
    config JSONB DEFAULT '{}',
    result JSONB,

    -- Audit
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_jobs_status ON processing_jobs(status, priority DESC, created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_entity ON processing_jobs(rights_entity_id);
CREATE INDEX IF NOT EXISTS idx_jobs_type ON processing_jobs(job_type);

-- ============================================================================
-- 5. HELPER FUNCTIONS
-- ============================================================================

-- Function to find similar entities by embedding
CREATE OR REPLACE FUNCTION find_similar_entities(
    query_embedding vector(1536),
    match_threshold FLOAT DEFAULT 0.7,
    match_count INT DEFAULT 10,
    filter_catalog_ids UUID[] DEFAULT NULL,
    filter_rights_types TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    entity_id UUID,
    title TEXT,
    rights_type TEXT,
    catalog_id UUID,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        re.id as entity_id,
        re.title,
        re.rights_type,
        re.catalog_id,
        1 - (ee.embedding <=> query_embedding) as similarity
    FROM entity_embeddings ee
    JOIN rights_entities re ON re.id = ee.rights_entity_id
    WHERE
        re.status = 'active'
        AND re.embedding_status = 'ready'
        AND (filter_catalog_ids IS NULL OR re.catalog_id = ANY(filter_catalog_ids))
        AND (filter_rights_types IS NULL OR re.rights_type = ANY(filter_rights_types))
        AND 1 - (ee.embedding <=> query_embedding) > match_threshold
    ORDER BY ee.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Function to update entity embedding status based on job completion
CREATE OR REPLACE FUNCTION update_entity_embedding_status()
RETURNS TRIGGER AS $$
BEGIN
    -- When all processing jobs for an entity are complete, update status
    IF NEW.status = 'completed' AND NEW.rights_entity_id IS NOT NULL THEN
        -- Check if any jobs are still pending/processing
        IF NOT EXISTS (
            SELECT 1 FROM processing_jobs
            WHERE rights_entity_id = NEW.rights_entity_id
            AND status IN ('queued', 'processing')
            AND id != NEW.id
        ) THEN
            -- Check if any embeddings exist
            IF EXISTS (
                SELECT 1 FROM entity_embeddings
                WHERE rights_entity_id = NEW.rights_entity_id
            ) THEN
                UPDATE rights_entities
                SET embedding_status = 'ready', updated_at = now()
                WHERE id = NEW.rights_entity_id;
            END IF;
        END IF;
    ELSIF NEW.status = 'failed' AND NEW.rights_entity_id IS NOT NULL THEN
        -- If job failed and no retries left
        IF NEW.retry_count >= NEW.max_retries THEN
            UPDATE rights_entities
            SET embedding_status = 'failed',
                processing_error = NEW.error_message,
                updated_at = now()
            WHERE id = NEW.rights_entity_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for auto-updating embedding status
DROP TRIGGER IF EXISTS trigger_update_embedding_status ON processing_jobs;
CREATE TRIGGER trigger_update_embedding_status
    AFTER UPDATE OF status ON processing_jobs
    FOR EACH ROW
    EXECUTE FUNCTION update_entity_embedding_status();

-- ============================================================================
-- 6. ROW LEVEL SECURITY
-- ============================================================================

-- Assets: same access as parent entity
ALTER TABLE reference_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "assets_select" ON reference_assets;
CREATE POLICY "assets_select" ON reference_assets FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = reference_assets.rights_entity_id
        AND wm.user_id = auth.uid()::text
    )
);

DROP POLICY IF EXISTS "assets_insert" ON reference_assets;
CREATE POLICY "assets_insert" ON reference_assets FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = reference_assets.rights_entity_id
        AND wm.user_id = auth.uid()::text
    )
);

DROP POLICY IF EXISTS "assets_delete" ON reference_assets;
CREATE POLICY "assets_delete" ON reference_assets FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = reference_assets.rights_entity_id
        AND wm.user_id = auth.uid()::text
        AND wm.role IN ('owner', 'admin')
    )
);

-- Embeddings: read access same as entity
ALTER TABLE entity_embeddings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "embeddings_select" ON entity_embeddings;
CREATE POLICY "embeddings_select" ON entity_embeddings FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = entity_embeddings.rights_entity_id
        AND wm.user_id = auth.uid()::text
    )
);

-- Service role can insert embeddings (from background jobs)
DROP POLICY IF EXISTS "embeddings_service_insert" ON entity_embeddings;
CREATE POLICY "embeddings_service_insert" ON entity_embeddings FOR INSERT TO service_role
WITH CHECK (true);

-- Jobs: users can see their own entity jobs
ALTER TABLE processing_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "jobs_select" ON processing_jobs;
CREATE POLICY "jobs_select" ON processing_jobs FOR SELECT TO authenticated
USING (
    rights_entity_id IS NULL
    OR EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = processing_jobs.rights_entity_id
        AND wm.user_id = auth.uid()::text
    )
);

DROP POLICY IF EXISTS "jobs_insert" ON processing_jobs;
CREATE POLICY "jobs_insert" ON processing_jobs FOR INSERT TO authenticated
WITH CHECK (
    rights_entity_id IS NULL
    OR EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = processing_jobs.rights_entity_id
        AND wm.user_id = auth.uid()::text
    )
);

-- ============================================================================
-- 7. UPDATE RIGHTS SCHEMAS WITH AI PERMISSION TEMPLATES
-- ============================================================================

-- Update existing schemas with permission template hints
UPDATE rights_schemas SET ai_permission_fields = '{
    "training": {
        "type": "object",
        "properties": {
            "allowed": {"type": "boolean", "default": false},
            "permitted_uses": {"type": "array", "items": {"type": "string"}},
            "commercial_ok": {"type": "boolean", "default": false},
            "requires_attribution": {"type": "boolean", "default": true},
            "attribution_text": {"type": "string"}
        }
    },
    "generation": {
        "type": "object",
        "properties": {
            "allowed": {"type": "boolean", "default": false},
            "derivative_works": {"type": "boolean", "default": false},
            "style_imitation": {"type": "boolean", "default": false},
            "direct_sampling": {"type": "boolean", "default": false},
            "watermark_required": {"type": "boolean", "default": true}
        }
    },
    "commercial": {
        "type": "object",
        "properties": {
            "commercial_use_allowed": {"type": "boolean", "default": false},
            "territories": {"type": "array", "items": {"type": "string"}, "default": ["WORLDWIDE"]},
            "revenue_share_required": {"type": "boolean", "default": false}
        }
    }
}'::jsonb
WHERE ai_permission_fields IS NULL OR ai_permission_fields = '{}'::jsonb;

-- Add voice-specific permissions to voice_likeness schema
UPDATE rights_schemas SET ai_permission_fields = ai_permission_fields || '{
    "voice": {
        "type": "object",
        "properties": {
            "cloning_allowed": {"type": "boolean", "default": false},
            "synthesis_allowed": {"type": "boolean", "default": false},
            "requires_disclosure": {"type": "boolean", "default": true}
        }
    }
}'::jsonb
WHERE id = 'voice_likeness';

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
--
-- Next steps:
-- 1. Create Supabase Storage bucket 'reference-assets'
-- 2. Set up storage policies for the bucket
-- 3. Configure Supabase webhook for entity changes (optional, for auto-processing)
-- ============================================================================
