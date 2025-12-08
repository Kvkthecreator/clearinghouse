-- =============================================================================
-- CLEARINGHOUSE: Rights Entities Schema
-- Migration: 00002_rights_entities.sql
-- Purpose: IP type schemas and rights entity storage
-- =============================================================================

-- =============================================================================
-- RIGHTS SCHEMAS (IP Type Definitions)
-- =============================================================================

CREATE TABLE rights_schemas (
    id TEXT PRIMARY KEY,  -- e.g., 'musical_work', 'sound_recording'
    display_name TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,  -- 'music', 'voice', 'character', 'visual', 'literary', 'video'

    -- JSON Schema for content validation
    field_schema JSONB NOT NULL,

    -- JSON Schema for AI permission fields specific to this type
    ai_permission_fields JSONB,

    -- Which fields serve as identifiers (e.g., ['iswc'], ['isrc'])
    identifier_fields TEXT[] DEFAULT '{}',

    -- Which field to use as display title
    display_field TEXT DEFAULT 'title',

    -- Whether this schema is active
    is_active BOOLEAN DEFAULT true,

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE rights_schemas IS 'Defines structure for each IP type (schema-driven design)';
COMMENT ON COLUMN rights_schemas.id IS 'Unique identifier like musical_work, sound_recording, voice_likeness';
COMMENT ON COLUMN rights_schemas.field_schema IS 'JSON Schema defining required/optional fields for this IP type';
COMMENT ON COLUMN rights_schemas.ai_permission_fields IS 'JSON Schema defining AI-specific permission fields';

-- =============================================================================
-- RIGHTS ENTITIES (Actual IP Records)
-- =============================================================================

CREATE TABLE rights_entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_id UUID NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,

    -- Classification
    rights_type TEXT NOT NULL REFERENCES rights_schemas(id),
    entity_key TEXT,  -- External identifier (ISRC, ISWC, etc.)

    -- Content
    title TEXT NOT NULL,
    content JSONB NOT NULL DEFAULT '{}',  -- Type-specific metadata

    -- AI Permissions (first-class citizen)
    ai_permissions JSONB DEFAULT '{}',

    -- Ownership information
    rights_holder_info JSONB,  -- Primary rights holder details
    ownership_chain JSONB DEFAULT '[]',  -- Provenance/chain of custody

    -- Status & Verification
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'pending', 'disputed')),
    verification_status TEXT DEFAULT 'unverified' CHECK (verification_status IN ('unverified', 'pending_verification', 'verified', 'disputed', 'expired')),

    -- Versioning
    version INTEGER DEFAULT 1,
    previous_version_id UUID REFERENCES rights_entities(id),

    -- Audit
    created_by TEXT NOT NULL,  -- 'user:{uuid}' or 'system' or 'import:{source}'
    updated_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    -- Uniqueness constraint per catalog/type/key
    UNIQUE(catalog_id, rights_type, entity_key)
);

COMMENT ON TABLE rights_entities IS 'Individual IP items with associated rights and AI permissions';
COMMENT ON COLUMN rights_entities.content IS 'Type-specific metadata validated against rights_schemas.field_schema';
COMMENT ON COLUMN rights_entities.ai_permissions IS 'AI usage permissions (training, generation, style_reference, etc.)';
COMMENT ON COLUMN rights_entities.ownership_chain IS 'Array of ownership events tracking provenance';

-- Indexes
CREATE INDEX idx_rights_entities_catalog ON rights_entities(catalog_id);
CREATE INDEX idx_rights_entities_type ON rights_entities(rights_type);
CREATE INDEX idx_rights_entities_status ON rights_entities(status) WHERE status = 'active';
CREATE INDEX idx_rights_entities_entity_key ON rights_entities(entity_key) WHERE entity_key IS NOT NULL;
CREATE INDEX idx_rights_entities_content ON rights_entities USING GIN(content);
CREATE INDEX idx_rights_entities_ai_permissions ON rights_entities USING GIN(ai_permissions);

-- =============================================================================
-- REFERENCE ASSETS (Files, Documents, Contracts)
-- =============================================================================

CREATE TABLE reference_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_id UUID NOT NULL REFERENCES catalogs(id) ON DELETE CASCADE,
    rights_entity_id UUID REFERENCES rights_entities(id) ON DELETE SET NULL,

    -- Asset info
    asset_type TEXT NOT NULL,  -- 'contract', 'master_file', 'sample', 'image', 'document'
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,  -- Supabase Storage path
    content_type TEXT,  -- MIME type
    file_size_bytes BIGINT,

    -- Metadata
    description TEXT,
    metadata JSONB DEFAULT '{}',

    -- Audit
    uploaded_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE reference_assets IS 'File storage for contracts, master files, and supporting documents';

CREATE INDEX idx_reference_assets_catalog ON reference_assets(catalog_id);
CREATE INDEX idx_reference_assets_entity ON reference_assets(rights_entity_id) WHERE rights_entity_id IS NOT NULL;

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE rights_schemas ENABLE ROW LEVEL SECURITY;
ALTER TABLE rights_entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE reference_assets ENABLE ROW LEVEL SECURITY;

-- Rights schemas: anyone authenticated can read (they're global)
CREATE POLICY "rights_schemas_select_authenticated"
ON rights_schemas FOR SELECT TO authenticated
USING (true);

-- Rights schemas: only service role can modify
CREATE POLICY "rights_schemas_service_role"
ON rights_schemas FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- Rights entities: workspace members can view
CREATE POLICY "rights_entities_select_members"
ON rights_entities FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = rights_entities.catalog_id
        AND wm.user_id = auth.uid()
    )
);

-- Rights entities: workspace members can insert
CREATE POLICY "rights_entities_insert_members"
ON rights_entities FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = rights_entities.catalog_id
        AND wm.user_id = auth.uid()
    )
);

-- Rights entities: workspace members can update
CREATE POLICY "rights_entities_update_members"
ON rights_entities FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = rights_entities.catalog_id
        AND wm.user_id = auth.uid()
    )
);

-- Rights entities: workspace admins can delete
CREATE POLICY "rights_entities_delete_admins"
ON rights_entities FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = rights_entities.catalog_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

-- Rights entities: service role full access
CREATE POLICY "rights_entities_service_role"
ON rights_entities FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- Reference assets: similar pattern
CREATE POLICY "reference_assets_select_members"
ON reference_assets FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = reference_assets.catalog_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "reference_assets_insert_members"
ON reference_assets FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = reference_assets.catalog_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "reference_assets_delete_admins"
ON reference_assets FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = reference_assets.catalog_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

CREATE POLICY "reference_assets_service_role"
ON reference_assets FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

CREATE TRIGGER trg_rights_schemas_updated_at
    BEFORE UPDATE ON rights_schemas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_rights_entities_updated_at
    BEFORE UPDATE ON rights_entities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON rights_schemas TO authenticated;
GRANT ALL ON rights_schemas TO service_role;
GRANT ALL ON rights_entities TO authenticated;
GRANT ALL ON rights_entities TO service_role;
GRANT ALL ON reference_assets TO authenticated;
GRANT ALL ON reference_assets TO service_role;
