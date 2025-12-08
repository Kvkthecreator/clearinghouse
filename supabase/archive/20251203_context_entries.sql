-- Migration: Context Entries Architecture
-- Date: 2025-12-03
-- Purpose: Implement structured context entries for work recipe context
--
-- This migration:
-- 1. Creates context_entry_schemas table (defines field structure per role)
-- 2. Creates context_entries table (stores structured context data)
-- 3. Seeds initial schemas (foundation, market, insight roles)
-- 4. Links reference_assets to context entries (ephemeral/permanent model)
-- 5. Adds deprecation notices to legacy systems
--
-- ADR Reference: /docs/architecture/ADR_CONTEXT_ENTRIES.md
-- Implementation Plan: /docs/implementation/CONTEXT_ENTRIES_IMPLEMENTATION_PLAN.md

BEGIN;

-- ============================================================================
-- PART 1: Context Entry Schemas Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS context_entry_schemas (
    anchor_role TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    description TEXT,
    icon TEXT,                           -- Lucide icon name
    category TEXT CHECK (category IN ('foundation', 'market', 'insight')),
    is_singleton BOOLEAN DEFAULT true,   -- true = one per basket, false = multiple allowed
    field_schema JSONB NOT NULL,         -- Defines available fields
    sort_order INTEGER DEFAULT 0,        -- Display order in UI
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE context_entry_schemas IS
'Defines the structure and available fields for each context anchor role.
Foundation roles (problem, customer, vision, brand) are universal.
Market roles (competitor) support multiple entries per basket.
Insight roles (trend_digest, competitor_snapshot) are agent-produced.
See: /docs/architecture/ADR_CONTEXT_ENTRIES.md';

COMMENT ON COLUMN context_entry_schemas.anchor_role IS 'Unique identifier for this context type';
COMMENT ON COLUMN context_entry_schemas.is_singleton IS 'If true, only one entry per basket allowed. If false, multiple entries (e.g., competitors)';
COMMENT ON COLUMN context_entry_schemas.field_schema IS 'JSON schema defining available fields, types, and validation rules';

-- Enable RLS
ALTER TABLE context_entry_schemas ENABLE ROW LEVEL SECURITY;

-- Schemas are readable by all authenticated users
CREATE POLICY "context_entry_schemas_select_authenticated"
ON context_entry_schemas FOR SELECT TO authenticated
USING (true);

-- Service role has full access
CREATE POLICY "context_entry_schemas_service_role"
ON context_entry_schemas FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- ============================================================================
-- PART 2: Seed Initial Schemas
-- ============================================================================

-- Foundation Roles (universal, human-established)
INSERT INTO context_entry_schemas (anchor_role, display_name, description, icon, category, is_singleton, sort_order, field_schema)
VALUES
(
    'problem',
    'Problem',
    'The core pain point or challenge being addressed',
    'AlertTriangle',
    'foundation',
    true,
    1,
    '{
        "fields": [
            {"key": "statement", "type": "longtext", "label": "Problem Statement", "required": true, "placeholder": "Describe the core problem you are solving..."},
            {"key": "impact", "type": "longtext", "label": "Impact", "placeholder": "What happens if this problem is not solved?"},
            {"key": "evidence", "type": "array", "label": "Evidence", "item_type": "text", "placeholder": "Add supporting evidence..."}
        ]
    }'::jsonb
),
(
    'customer',
    'Customer',
    'Who you are building for - the target persona',
    'Users',
    'foundation',
    true,
    2,
    '{
        "fields": [
            {"key": "description", "type": "longtext", "label": "Customer Description", "required": true, "placeholder": "Describe your ideal customer..."},
            {"key": "demographics", "type": "text", "label": "Demographics", "placeholder": "Age, location, industry, company size..."},
            {"key": "pain_points", "type": "array", "label": "Pain Points", "item_type": "text", "placeholder": "Add a pain point..."},
            {"key": "goals", "type": "array", "label": "Goals", "item_type": "text", "placeholder": "Add a goal..."},
            {"key": "jobs_to_be_done", "type": "array", "label": "Jobs to Be Done", "item_type": "text", "placeholder": "Add a job..."}
        ]
    }'::jsonb
),
(
    'vision',
    'Vision',
    'Where this is going - the future state you are working toward',
    'Eye',
    'foundation',
    true,
    3,
    '{
        "fields": [
            {"key": "statement", "type": "longtext", "label": "Vision Statement", "required": true, "placeholder": "Describe your vision for the future..."},
            {"key": "milestones", "type": "array", "label": "Key Milestones", "item_type": "text", "placeholder": "Add a milestone..."},
            {"key": "success_metrics", "type": "array", "label": "Success Metrics", "item_type": "text", "placeholder": "Add a metric..."}
        ]
    }'::jsonb
),
(
    'brand',
    'Brand Identity',
    'Your brand voice, visual identity, and guidelines',
    'Palette',
    'foundation',
    true,
    4,
    '{
        "fields": [
            {"key": "name", "type": "text", "label": "Brand Name", "required": true, "placeholder": "Your company or product name"},
            {"key": "tagline", "type": "text", "label": "Tagline", "placeholder": "Your memorable catchphrase"},
            {"key": "voice", "type": "longtext", "label": "Brand Voice", "placeholder": "Describe how your brand communicates...", "help": "Include tone, vocabulary preferences, things to avoid"},
            {"key": "logo", "type": "asset", "label": "Logo", "accept": "image/*"},
            {"key": "colors", "type": "array", "label": "Brand Colors", "item_type": "text", "placeholder": "#FF5733"},
            {"key": "guidelines_doc", "type": "asset", "label": "Brand Guidelines", "accept": "application/pdf,.docx"}
        ]
    }'::jsonb
)
ON CONFLICT (anchor_role) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    category = EXCLUDED.category,
    field_schema = EXCLUDED.field_schema,
    sort_order = EXCLUDED.sort_order,
    updated_at = now();

-- Market Roles (non-singleton, multiple entries allowed)
INSERT INTO context_entry_schemas (anchor_role, display_name, description, icon, category, is_singleton, sort_order, field_schema)
VALUES
(
    'competitor',
    'Competitor',
    'Competitive intelligence for a specific competitor',
    'Target',
    'market',
    false,  -- Multiple competitors allowed
    10,
    '{
        "fields": [
            {"key": "name", "type": "text", "label": "Competitor Name", "required": true, "placeholder": "Competitor company name"},
            {"key": "website", "type": "text", "label": "Website", "placeholder": "https://..."},
            {"key": "description", "type": "longtext", "label": "Description", "placeholder": "What do they do?"},
            {"key": "strengths", "type": "array", "label": "Strengths", "item_type": "text"},
            {"key": "weaknesses", "type": "array", "label": "Weaknesses", "item_type": "text"},
            {"key": "differentiators", "type": "longtext", "label": "How You Differ", "placeholder": "What makes you different from this competitor?"},
            {"key": "screenshot", "type": "asset", "label": "Screenshot", "accept": "image/*"}
        ]
    }'::jsonb
)
ON CONFLICT (anchor_role) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    category = EXCLUDED.category,
    is_singleton = EXCLUDED.is_singleton,
    field_schema = EXCLUDED.field_schema,
    sort_order = EXCLUDED.sort_order,
    updated_at = now();

-- Insight Roles (agent-produced, refreshable)
INSERT INTO context_entry_schemas (anchor_role, display_name, description, icon, category, is_singleton, sort_order, field_schema)
VALUES
(
    'trend_digest',
    'Trend Digest',
    'Synthesized market and industry trends',
    'TrendingUp',
    'insight',
    true,
    20,
    '{
        "fields": [
            {"key": "summary", "type": "longtext", "label": "Summary", "required": true},
            {"key": "key_themes", "type": "array", "label": "Key Themes", "item_type": "text"},
            {"key": "opportunities", "type": "array", "label": "Opportunities", "item_type": "text"},
            {"key": "threats", "type": "array", "label": "Threats", "item_type": "text"},
            {"key": "sources", "type": "array", "label": "Sources", "item_type": "text"}
        ],
        "agent_produced": true,
        "refresh_ttl_hours": 168
    }'::jsonb
),
(
    'competitor_snapshot',
    'Competitor Snapshot',
    'Synthesized competitive landscape analysis',
    'BarChart3',
    'insight',
    true,
    21,
    '{
        "fields": [
            {"key": "summary", "type": "longtext", "label": "Summary", "required": true},
            {"key": "landscape", "type": "longtext", "label": "Competitive Landscape"},
            {"key": "positioning", "type": "longtext", "label": "Your Positioning"},
            {"key": "gaps", "type": "array", "label": "Market Gaps", "item_type": "text"}
        ],
        "agent_produced": true,
        "refresh_ttl_hours": 336
    }'::jsonb
)
ON CONFLICT (anchor_role) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    category = EXCLUDED.category,
    field_schema = EXCLUDED.field_schema,
    sort_order = EXCLUDED.sort_order,
    updated_at = now();

-- ============================================================================
-- PART 3: Context Entries Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS context_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,
    anchor_role TEXT NOT NULL REFERENCES context_entry_schemas(anchor_role),
    entry_key TEXT,                      -- For non-singleton (e.g., competitor name)
    display_name TEXT,                   -- Optional display override
    data JSONB NOT NULL DEFAULT '{}',    -- Structured data per field_schema
    completeness_score FLOAT,            -- 0.0-1.0 based on required fields
    state TEXT DEFAULT 'active' CHECK (state IN ('active', 'archived')),
    refresh_policy JSONB,                -- For insight roles: {"ttl_hours": 168, "last_refreshed": "..."}
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    created_by UUID REFERENCES auth.users(id),

    UNIQUE(basket_id, anchor_role, entry_key)
);

COMMENT ON TABLE context_entries IS
'Stores structured context data per basket, organized by anchor role.
Each entry contains typed fields defined by context_entry_schemas.
Asset references use asset://uuid pattern resolved at query time.
See: /docs/architecture/ADR_CONTEXT_ENTRIES.md';

COMMENT ON COLUMN context_entries.entry_key IS 'For non-singleton roles (e.g., competitors), identifies the specific entry';
COMMENT ON COLUMN context_entries.data IS 'Structured JSONB data. Asset fields contain "asset://uuid" references';
COMMENT ON COLUMN context_entries.completeness_score IS 'Calculated score 0.0-1.0 based on required fields filled';
COMMENT ON COLUMN context_entries.refresh_policy IS 'For agent-produced entries: TTL and refresh metadata';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_context_entries_basket_role
ON context_entries(basket_id, anchor_role);

CREATE INDEX IF NOT EXISTS idx_context_entries_updated
ON context_entries(basket_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_context_entries_state
ON context_entries(basket_id, state)
WHERE state = 'active';

-- GIN index for JSONB data queries
CREATE INDEX IF NOT EXISTS idx_context_entries_data
ON context_entries USING gin(data);

-- Enable RLS
ALTER TABLE context_entries ENABLE ROW LEVEL SECURITY;

-- Users can read entries for baskets they have access to
CREATE POLICY "context_entries_select_workspace_members"
ON context_entries FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_entries.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Users can insert entries for baskets they have access to
CREATE POLICY "context_entries_insert_workspace_members"
ON context_entries FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_entries.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Users can update entries for baskets they have access to
CREATE POLICY "context_entries_update_workspace_members"
ON context_entries FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_entries.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Users can delete (archive) entries for baskets they have access to
CREATE POLICY "context_entries_delete_workspace_members"
ON context_entries FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        JOIN workspace_memberships wm ON wm.workspace_id = p.workspace_id
        WHERE b.id = context_entries.basket_id
        AND wm.user_id = auth.uid()
    )
);

-- Service role has full access
CREATE POLICY "context_entries_service_role"
ON context_entries FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- ============================================================================
-- PART 4: Link Reference Assets to Context Entries
-- ============================================================================

-- Add columns for context entry association (ephemeral/permanent model)
ALTER TABLE reference_assets
  ADD COLUMN IF NOT EXISTS context_entry_id UUID,
  ADD COLUMN IF NOT EXISTS context_field_key TEXT;

-- Add FK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'ref_assets_context_entry_fk'
  ) THEN
    ALTER TABLE reference_assets
      ADD CONSTRAINT ref_assets_context_entry_fk
      FOREIGN KEY (context_entry_id)
      REFERENCES context_entries(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Index for context entry lookups
CREATE INDEX IF NOT EXISTS idx_ref_assets_context_entry
  ON reference_assets(context_entry_id, context_field_key)
  WHERE context_entry_id IS NOT NULL;

COMMENT ON COLUMN reference_assets.context_entry_id IS
'Links asset to context entry. If set, asset is permanent. If NULL, asset is ephemeral.
See: /docs/architecture/ADR_CONTEXT_ENTRIES.md#ephemeral-vs-permanent-asset-model';

COMMENT ON COLUMN reference_assets.context_field_key IS
'Which field in the context entry this asset fills (e.g., "logo", "guidelines_doc")';

-- ============================================================================
-- PART 5: Deprecation Notices for Legacy Systems
-- ============================================================================

-- Mark asset_type_catalog as deprecated for user uploads
COMMENT ON TABLE asset_type_catalog IS
'Dynamic catalog of asset types.

DEPRECATION NOTICE (2025-12-03):
For USER uploads, asset classification is now determined by attachment to context_entries.
LLM classification remains active ONLY for work output files (agent-produced).
This table is kept for backward compatibility and existing assets.
See: /docs/architecture/ADR_CONTEXT_ENTRIES.md#de-wiring-legacy-classification-system

New user uploads should use context_entry_id instead of asset_type for categorization.';

-- Mark basket_anchors as deprecated (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'basket_anchors') THEN
    EXECUTE $comment$
      COMMENT ON TABLE basket_anchors IS
'DEPRECATED (2025-12-03): This table is empty and unused.
Context roles are now stored on context_entries.
Block anchor_role column remains for RAG/knowledge extraction only.
Table will be dropped after 30-day observation period.
See: /docs/architecture/ADR_CONTEXT_ENTRIES.md'
    $comment$;
  END IF;
END $$;

-- Add deprecation notice to blocks.anchor_role (if column exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'blocks' AND column_name = 'anchor_role'
  ) THEN
    EXECUTE $comment$
      COMMENT ON COLUMN blocks.anchor_role IS
'LEGACY (2025-12-03): For work recipe context, use context_entries instead.
This column remains active for:
- RAG/semantic search
- Knowledge extraction pipelines
- Existing block categorization
See: /docs/architecture/ADR_CONTEXT_ENTRIES.md#legacy-systems-reference'
    $comment$;
  END IF;
END $$;

-- ============================================================================
-- PART 6: Helper Functions
-- ============================================================================

-- Function to update updated_at on context entries
CREATE OR REPLACE FUNCTION update_context_entry_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for context_entries updated_at
DROP TRIGGER IF EXISTS trg_context_entries_updated_at ON context_entries;
CREATE TRIGGER trg_context_entries_updated_at
BEFORE UPDATE ON context_entries
FOR EACH ROW EXECUTE FUNCTION update_context_entry_timestamp();

-- Trigger for context_entry_schemas updated_at
DROP TRIGGER IF EXISTS trg_context_entry_schemas_updated_at ON context_entry_schemas;
CREATE TRIGGER trg_context_entry_schemas_updated_at
BEFORE UPDATE ON context_entry_schemas
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to calculate completeness score
CREATE OR REPLACE FUNCTION calculate_context_completeness(
    p_data JSONB,
    p_field_schema JSONB
) RETURNS FLOAT AS $$
DECLARE
    v_required_count INTEGER := 0;
    v_filled_count INTEGER := 0;
    v_field JSONB;
    v_key TEXT;
    v_value JSONB;
BEGIN
    FOR v_field IN SELECT * FROM jsonb_array_elements(p_field_schema->'fields')
    LOOP
        IF (v_field->>'required')::boolean = true THEN
            v_required_count := v_required_count + 1;
            v_key := v_field->>'key';

            IF p_data ? v_key THEN
                v_value := p_data->v_key;
                -- Check if value is non-null and non-empty
                IF v_value IS NOT NULL
                   AND v_value::text != 'null'
                   AND v_value::text != '""'
                   AND v_value::text != '[]' THEN
                    v_filled_count := v_filled_count + 1;
                END IF;
            END IF;
        END IF;
    END LOOP;

    IF v_required_count = 0 THEN
        RETURN 1.0;
    END IF;

    RETURN v_filled_count::FLOAT / v_required_count::FLOAT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_context_completeness IS
'Calculates completeness score (0.0-1.0) for a context entry based on required fields filled';

-- ============================================================================
-- PART 7: Grants
-- ============================================================================

-- Grant service role full access to new tables
GRANT ALL ON context_entry_schemas TO service_role;
GRANT ALL ON context_entries TO service_role;

-- Grant authenticated users appropriate access
GRANT SELECT ON context_entry_schemas TO authenticated;
GRANT ALL ON context_entries TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
    schemas_count INTEGER;
    entries_table_exists BOOLEAN;
    ref_assets_has_entry_id BOOLEAN;
    schemas_policies INTEGER;
    entries_policies INTEGER;
BEGIN
    -- Check context_entry_schemas
    SELECT COUNT(*) INTO schemas_count FROM context_entry_schemas;

    -- Check context_entries table
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'context_entries'
    ) INTO entries_table_exists;

    -- Check reference_assets.context_entry_id
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'reference_assets'
        AND column_name = 'context_entry_id'
    ) INTO ref_assets_has_entry_id;

    -- Count RLS policies
    SELECT COUNT(*) INTO schemas_policies
    FROM pg_policies
    WHERE tablename = 'context_entry_schemas';

    SELECT COUNT(*) INTO entries_policies
    FROM pg_policies
    WHERE tablename = 'context_entries';

    RAISE NOTICE '';
    RAISE NOTICE '============================================================';
    RAISE NOTICE '✅ Migration: Context Entries (20251203) Complete';
    RAISE NOTICE '============================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Tables Created:';
    RAISE NOTICE '  - context_entry_schemas: % schema types seeded', schemas_count;
    RAISE NOTICE '  - context_entries: % (created)', entries_table_exists;
    RAISE NOTICE '';
    RAISE NOTICE 'Reference Assets Updated:';
    RAISE NOTICE '  - context_entry_id column: % (added)', ref_assets_has_entry_id;
    RAISE NOTICE '  - context_field_key column: added';
    RAISE NOTICE '';
    RAISE NOTICE 'RLS Policies:';
    RAISE NOTICE '  - context_entry_schemas: % policies', schemas_policies;
    RAISE NOTICE '  - context_entries: % policies', entries_policies;
    RAISE NOTICE '';
    RAISE NOTICE 'Deprecation Notices Added:';
    RAISE NOTICE '  - asset_type_catalog: deprecated for user uploads';
    RAISE NOTICE '  - basket_anchors: deprecated (if exists)';
    RAISE NOTICE '  - blocks.anchor_role: marked as legacy';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Next Steps:';
    RAISE NOTICE '  1. Deploy substrate-API context entry routes';
    RAISE NOTICE '  2. Update classification_service.py with source parameter';
    RAISE NOTICE '  3. Build frontend Context page with entry editors';
    RAISE NOTICE '  4. Update work orchestration to use context entries';
    RAISE NOTICE '';
    RAISE NOTICE 'ADR: /docs/architecture/ADR_CONTEXT_ENTRIES.md';
    RAISE NOTICE 'Plan: /docs/implementation/CONTEXT_ENTRIES_IMPLEMENTATION_PLAN.md';
    RAISE NOTICE '============================================================';

    -- Validation warnings
    IF schemas_count < 7 THEN
        RAISE WARNING 'Expected 7+ schemas, got %', schemas_count;
    END IF;

    IF NOT entries_table_exists THEN
        RAISE WARNING 'context_entries table not created';
    END IF;

    IF NOT ref_assets_has_entry_id THEN
        RAISE WARNING 'reference_assets.context_entry_id not added';
    END IF;
END $$;

COMMIT;
