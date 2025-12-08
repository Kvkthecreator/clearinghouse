-- Migration: Phase 1 - Reference Assets & Substrate Tables
-- Date: 2025-11-13
-- Purpose: Create reference_assets infrastructure for non-text substrate
--
-- Changes:
-- 1. Create asset_type_catalog (dynamic, admin-managed)
-- 2. Create reference_assets table (file metadata + embeddings)
-- 3. Update blocks table with provenance column
-- 4. Add comprehensive RLS policies and GRANTS
--
-- Database: Shared DB (substrate-API tables colocated with work-platform)

-- ============================================================================
-- STEP 1: Create asset_type_catalog (dynamic type management)
-- ============================================================================

CREATE TABLE IF NOT EXISTS asset_type_catalog (
  asset_type text PRIMARY KEY,
  display_name text NOT NULL,
  description text,
  category text,

  -- MIME type validation
  allowed_mime_types text[],

  -- Lifecycle
  is_active boolean DEFAULT true NOT NULL,
  deprecated_at timestamptz,

  -- Audit
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  created_by_user_id uuid REFERENCES auth.users(id),
  notes text
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_asset_type_catalog_active
  ON asset_type_catalog(is_active)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_asset_type_catalog_category
  ON asset_type_catalog(category)
  WHERE category IS NOT NULL;

-- Seed initial asset types (expandable via admin UI without migration)
INSERT INTO asset_type_catalog (asset_type, display_name, description, category, allowed_mime_types) VALUES
  (
    'brand_voice_sample',
    'Brand Voice Sample',
    'Example content demonstrating desired brand voice and tone',
    'brand_identity',
    ARRAY['image/*', 'application/pdf', 'text/*']
  ),
  (
    'competitor_screenshot',
    'Competitor Screenshot',
    'Screenshots of competitor products, marketing, or content',
    'competitive_intel',
    ARRAY['image/*']
  ),
  (
    'tone_reference_doc',
    'Tone Reference Document',
    'Document defining brand tone, style guide, or voice guidelines',
    'brand_identity',
    ARRAY['application/pdf', 'text/*', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
  ),
  (
    'watchlist_json',
    'Watchlist Configuration',
    'JSON file containing watchlist domains, keywords, or monitoring targets',
    'configuration',
    ARRAY['application/json']
  ),
  (
    'template_file',
    'Template File',
    'Report template, content template, or output format specification',
    'template',
    ARRAY['application/*', 'text/*']
  ),
  (
    'data_source',
    'Data Source',
    'External data file for analysis or reference',
    'integration',
    ARRAY['*/*']
  ),
  (
    'other',
    'Other',
    'Uncategorized reference asset',
    'uncategorized',
    ARRAY['*/*']
  )
ON CONFLICT (asset_type) DO NOTHING;

COMMENT ON TABLE asset_type_catalog IS 'Dynamic catalog of asset types. Extensible via admin UI without schema migration.';
COMMENT ON COLUMN asset_type_catalog.asset_type IS 'Unique identifier for asset type (lowercase, underscore-separated)';
COMMENT ON COLUMN asset_type_catalog.allowed_mime_types IS 'Array of allowed MIME types (supports wildcards like image/*)';
COMMENT ON COLUMN asset_type_catalog.category IS 'Grouping category for UI organization';

-- ============================================================================
-- STEP 2: Create reference_assets table
-- ============================================================================

CREATE TABLE IF NOT EXISTS reference_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  basket_id uuid NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,

  -- Storage (Supabase Storage integration)
  storage_path text NOT NULL, -- Format: baskets/{basket_id}/assets/{asset_id}/{filename}
  file_name text NOT NULL,
  file_size_bytes bigint,
  mime_type text,

  -- Classification (validated via FK to catalog, NOT hardcoded enum)
  asset_type text NOT NULL REFERENCES asset_type_catalog(asset_type),
  asset_category text NOT NULL,

  -- Lifecycle management
  permanence text NOT NULL DEFAULT 'permanent' CHECK (permanence IN ('permanent', 'temporary')),
  expires_at timestamptz,
  work_session_id uuid, -- Note: Cross-table reference (not FK) - work_sessions in same DB

  -- Agent scoping
  agent_scope text[], -- Array of agent_types that can access this asset

  -- Semantic metadata
  metadata jsonb DEFAULT '{}' NOT NULL,
  tags text[],
  description text,
  description_embedding vector(1536), -- pgvector for semantic search

  -- Audit trail
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  created_by_user_id uuid REFERENCES auth.users(id),
  last_accessed_at timestamptz,
  access_count integer DEFAULT 0 NOT NULL,

  -- Constraints
  CONSTRAINT temporary_must_expire CHECK (
    (permanence = 'temporary' AND expires_at IS NOT NULL) OR
    (permanence = 'permanent')
  ),
  CONSTRAINT expires_at_future CHECK (
    expires_at IS NULL OR expires_at > created_at
  ),
  CONSTRAINT access_count_non_negative CHECK (access_count >= 0),
  CONSTRAINT file_size_positive CHECK (file_size_bytes IS NULL OR file_size_bytes > 0)
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_ref_assets_basket
  ON reference_assets(basket_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ref_assets_type
  ON reference_assets(asset_type, permanence);

CREATE INDEX IF NOT EXISTS idx_ref_assets_category
  ON reference_assets(asset_category, basket_id);

CREATE INDEX IF NOT EXISTS idx_ref_assets_scope
  ON reference_assets USING gin(agent_scope);

CREATE INDEX IF NOT EXISTS idx_ref_assets_tags
  ON reference_assets USING gin(tags);

CREATE INDEX IF NOT EXISTS idx_ref_assets_metadata
  ON reference_assets USING gin(metadata);

-- Index for embedding-based semantic search
CREATE INDEX IF NOT EXISTS idx_ref_assets_embedding
  ON reference_assets
  USING ivfflat (description_embedding vector_cosine_ops)
  WITH (lists = 100) -- Tune based on dataset size (sqrt of expected rows)
  WHERE description_embedding IS NOT NULL;

-- Index for lifecycle management (cleanup expired temporary assets)
CREATE INDEX IF NOT EXISTS idx_ref_assets_expired
  ON reference_assets(expires_at)
  WHERE permanence = 'temporary' AND expires_at IS NOT NULL;

-- Index for work session linkage
CREATE INDEX IF NOT EXISTS idx_ref_assets_work_session
  ON reference_assets(work_session_id)
  WHERE work_session_id IS NOT NULL;

COMMENT ON TABLE reference_assets IS 'Non-text substrate: files, images, documents that agents reference during work execution';
COMMENT ON COLUMN reference_assets.storage_path IS 'Supabase Storage path (bucket: yarnnn-assets)';
COMMENT ON COLUMN reference_assets.permanence IS 'Permanent assets persist indefinitely, temporary assets expire after work session';
COMMENT ON COLUMN reference_assets.work_session_id IS 'Links to work_sessions for temporary assets (not enforced FK - same DB but different domain)';
COMMENT ON COLUMN reference_assets.agent_scope IS 'Array of agent_types that can access this asset (null = all agents)';
COMMENT ON COLUMN reference_assets.description_embedding IS 'Vector embedding of description for semantic search';

-- ============================================================================
-- STEP 3: Update blocks table (add provenance column)
-- ============================================================================

-- Add column for blocks derived from reference assets
ALTER TABLE blocks
  ADD COLUMN IF NOT EXISTS derived_from_asset_id uuid;

-- Add FK constraint (same DB, can use FK)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'blocks_derived_from_asset_id_fkey'
  ) THEN
    ALTER TABLE blocks
      ADD CONSTRAINT blocks_derived_from_asset_id_fkey
      FOREIGN KEY (derived_from_asset_id)
      REFERENCES reference_assets(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Create index for provenance queries
CREATE INDEX IF NOT EXISTS idx_blocks_derived_asset
  ON blocks(derived_from_asset_id, created_at DESC)
  WHERE derived_from_asset_id IS NOT NULL;

-- Create index for reverse lookup (asset → blocks)
CREATE INDEX IF NOT EXISTS idx_blocks_asset_basket
  ON blocks(derived_from_asset_id, basket_id)
  WHERE derived_from_asset_id IS NOT NULL;

COMMENT ON COLUMN blocks.derived_from_asset_id IS 'Provenance: links block to reference_asset it was extracted/derived from';

-- ============================================================================
-- STEP 4: RLS Policies for reference_assets
-- ============================================================================

ALTER TABLE reference_assets ENABLE ROW LEVEL SECURITY;

-- Users can view assets in their workspace baskets
CREATE POLICY "Users can view assets in their workspace"
  ON reference_assets FOR SELECT
  TO authenticated
  USING (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Users can upload assets to their workspace baskets
CREATE POLICY "Users can upload assets to their workspace"
  ON reference_assets FOR INSERT
  TO authenticated
  WITH CHECK (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Users can update assets in their workspace baskets
CREATE POLICY "Users can update assets in their workspace"
  ON reference_assets FOR UPDATE
  TO authenticated
  USING (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Users can delete assets from their workspace baskets
CREATE POLICY "Users can delete assets from their workspace"
  ON reference_assets FOR DELETE
  TO authenticated
  USING (
    basket_id IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Service role has full access
CREATE POLICY "Service role has full access to reference_assets"
  ON reference_assets
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- STEP 5: RLS Policies for asset_type_catalog
-- ============================================================================

ALTER TABLE asset_type_catalog ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read active asset types
CREATE POLICY "Users can read active asset types"
  ON asset_type_catalog FOR SELECT
  TO authenticated
  USING (is_active = true AND deprecated_at IS NULL);

-- Service role has full access
CREATE POLICY "Service role has full access to asset_type_catalog"
  ON asset_type_catalog
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Admin users can manage asset types (implement in Phase 2)
-- For now, service role only

-- ============================================================================
-- STEP 6: GRANTS (critical for service-to-service access)
-- ============================================================================

-- Grant service role access to all new tables
GRANT ALL ON asset_type_catalog TO service_role;
GRANT ALL ON reference_assets TO service_role;
GRANT ALL ON blocks TO service_role;

-- Grant authenticated users appropriate access
GRANT SELECT ON asset_type_catalog TO authenticated;
GRANT ALL ON reference_assets TO authenticated;
GRANT ALL ON blocks TO authenticated;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================================================
-- STEP 7: Trigger for tracking asset access
-- ============================================================================

CREATE OR REPLACE FUNCTION track_asset_access()
RETURNS TRIGGER AS $$
BEGIN
  -- Update access stats when asset is retrieved
  UPDATE reference_assets
  SET
    access_count = access_count + 1,
    last_accessed_at = now()
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: Trigger not automatically created - would fire on every SELECT
-- Instead, increment access_count explicitly in application code when downloading file
COMMENT ON FUNCTION track_asset_access IS 'Updates access_count and last_accessed_at for reference_assets (call explicitly in app code)';

-- ============================================================================
-- STEP 8: Function for cleaning up expired temporary assets
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_expired_assets()
RETURNS TABLE(deleted_count bigint) AS $$
DECLARE
  deleted_ids uuid[];
BEGIN
  -- Find expired temporary assets
  SELECT array_agg(id) INTO deleted_ids
  FROM reference_assets
  WHERE permanence = 'temporary'
    AND expires_at IS NOT NULL
    AND expires_at < now();

  -- Delete from storage (application code should call Supabase Storage API)
  -- This function only deletes DB records - storage cleanup happens in application

  -- Delete expired assets
  DELETE FROM reference_assets
  WHERE id = ANY(deleted_ids);

  deleted_count := array_length(deleted_ids, 1);
  RETURN QUERY SELECT COALESCE(deleted_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_expired_assets IS 'Deletes expired temporary assets from DB. Call from cron job. Storage cleanup handled in application code.';

-- ============================================================================
-- STEP 9: Trigger for auto-updating updated_at timestamp
-- ============================================================================

-- Create or replace function (may already exist from other migrations)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to reference_assets
DROP TRIGGER IF EXISTS trg_update_reference_assets_updated_at ON reference_assets;
CREATE TRIGGER trg_update_reference_assets_updated_at
  BEFORE UPDATE ON reference_assets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Apply to asset_type_catalog
DROP TRIGGER IF EXISTS trg_update_asset_type_catalog_updated_at ON asset_type_catalog;
CREATE TRIGGER trg_update_asset_type_catalog_updated_at
  BEFORE UPDATE ON asset_type_catalog
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  catalog_count INTEGER;
  assets_table_exists BOOLEAN;
  blocks_has_derived BOOLEAN;
  asset_policies INTEGER;
  catalog_policies INTEGER;
BEGIN
  -- Check asset_type_catalog
  SELECT COUNT(*) INTO catalog_count FROM asset_type_catalog;

  -- Check reference_assets table
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'reference_assets'
  ) INTO assets_table_exists;

  -- Check blocks.derived_from_asset_id
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'blocks'
    AND column_name = 'derived_from_asset_id'
  ) INTO blocks_has_derived;

  -- Count RLS policies
  SELECT COUNT(*) INTO asset_policies
  FROM pg_policies
  WHERE tablename = 'reference_assets';

  SELECT COUNT(*) INTO catalog_policies
  FROM pg_policies
  WHERE tablename = 'asset_type_catalog';

  RAISE NOTICE '✅ Migration 2 (Phase 1 - Reference Assets) Complete:';
  RAISE NOTICE '  - asset_type_catalog: % types seeded', catalog_count;
  RAISE NOTICE '  - reference_assets table: % (created)', assets_table_exists;
  RAISE NOTICE '  - blocks.derived_from_asset_id: % (added)', blocks_has_derived;
  RAISE NOTICE '  - reference_assets RLS policies: %', asset_policies;
  RAISE NOTICE '  - asset_type_catalog RLS policies: %', catalog_policies;

  -- Validation checks
  IF catalog_count < 7 THEN
    RAISE WARNING 'asset_type_catalog incomplete (expected 7+ types, got %)', catalog_count;
  END IF;

  IF NOT assets_table_exists THEN
    RAISE WARNING 'reference_assets table not created';
  END IF;

  IF NOT blocks_has_derived THEN
    RAISE WARNING 'blocks.derived_from_asset_id column not added';
  END IF;

  IF asset_policies < 5 THEN
    RAISE WARNING 'reference_assets RLS policies incomplete (expected 5+, got %)', asset_policies;
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '📋 Next Steps:';
  RAISE NOTICE '  1. Setup Supabase Storage bucket (yarnnn-assets)';
  RAISE NOTICE '  2. Configure Storage RLS policies';
  RAISE NOTICE '  3. Deploy substrate-API file upload endpoints';
  RAISE NOTICE '  4. Deploy work-platform BFF proxy routes';
END $$;
