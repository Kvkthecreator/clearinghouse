-- Migration: Phase 1 - Supabase Storage Setup
-- Date: 2025-11-13
-- Purpose: Create storage bucket and RLS policies for reference assets
--
-- NOTE: Bucket creation via SQL is supported in newer Supabase versions
-- If this migration fails, create bucket manually via Dashboard:
--   1. Navigate to Storage → Buckets
--   2. Create new bucket: yarnnn-assets
--   3. Settings: Private (public: false), File size limit: 50MB
--   4. Then run this migration for RLS policies only

-- ============================================================================
-- STEP 1: Create storage bucket (if supported)
-- ============================================================================

-- Insert bucket configuration
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'yarnnn-assets',
  'yarnnn-assets',
  false, -- Private bucket
  52428800, -- 50MB in bytes
  ARRAY[
    'image/*',
    'application/pdf',
    'application/json',
    'text/*',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

COMMENT ON TABLE storage.buckets IS 'Supabase Storage buckets configuration';

-- ============================================================================
-- STEP 2: RLS Policies for storage.objects
-- ============================================================================

-- Enable RLS on storage.objects (should already be enabled)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (idempotent migration)
DROP POLICY IF EXISTS "Users can upload assets to their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Users can read assets from their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Users can update assets in their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete assets from their workspace baskets" ON storage.objects;
DROP POLICY IF EXISTS "Service role has full access to yarnnn-assets" ON storage.objects;

-- Policy 1: Users can upload (INSERT) to their workspace baskets
CREATE POLICY "Users can upload assets to their workspace baskets"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'yarnnn-assets'
    AND (storage.foldername(name))[1] = 'baskets'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Policy 2: Users can read (SELECT) from their workspace baskets
CREATE POLICY "Users can read assets from their workspace baskets"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'yarnnn-assets'
    AND (storage.foldername(name))[1] = 'baskets'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Policy 3: Users can update (UPDATE) assets in their workspace baskets
CREATE POLICY "Users can update assets in their workspace baskets"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'yarnnn-assets'
    AND (storage.foldername(name))[1] = 'baskets'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    bucket_id = 'yarnnn-assets'
    AND (storage.foldername(name))[1] = 'baskets'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Policy 4: Users can delete (DELETE) assets from their workspace baskets
CREATE POLICY "Users can delete assets from their workspace baskets"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'yarnnn-assets'
    AND (storage.foldername(name))[1] = 'baskets'
    AND (storage.foldername(name))[2]::uuid IN (
      SELECT b.id FROM baskets b
      JOIN workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );

-- Policy 5: Service role has full access
CREATE POLICY "Service role has full access to yarnnn-assets"
  ON storage.objects
  TO service_role
  USING (bucket_id = 'yarnnn-assets')
  WITH CHECK (bucket_id = 'yarnnn-assets');

-- ============================================================================
-- STEP 3: GRANTS for storage tables
-- ============================================================================

-- Grant necessary permissions
GRANT ALL ON storage.buckets TO service_role;
GRANT ALL ON storage.objects TO service_role;

GRANT SELECT ON storage.buckets TO authenticated;
GRANT ALL ON storage.objects TO authenticated;

-- ============================================================================
-- STEP 4: Helper function for validating storage paths
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_asset_storage_path(
  basket_id_param uuid,
  storage_path_param text
)
RETURNS boolean AS $$
DECLARE
  expected_prefix text;
BEGIN
  -- Expected format: baskets/{basket_id}/assets/{asset_id}/{filename}
  expected_prefix := 'baskets/' || basket_id_param::text || '/assets/';

  RETURN storage_path_param LIKE expected_prefix || '%';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION validate_asset_storage_path IS 'Validates that storage_path follows expected format for reference_assets';

-- Add CHECK constraint to reference_assets (if table exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'reference_assets'
  ) THEN
    -- Add constraint to validate storage path format
    ALTER TABLE reference_assets
      ADD CONSTRAINT IF NOT EXISTS valid_storage_path
      CHECK (validate_asset_storage_path(basket_id, storage_path));

    RAISE NOTICE 'Added storage path validation constraint to reference_assets';
  ELSE
    RAISE WARNING 'reference_assets table does not exist yet - run migration 2 first';
  END IF;
END $$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
  bucket_exists BOOLEAN;
  bucket_public BOOLEAN;
  bucket_size_limit BIGINT;
  storage_policies INTEGER;
BEGIN
  -- Check bucket exists
  SELECT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'yarnnn-assets'
  ) INTO bucket_exists;

  -- Get bucket settings
  SELECT public, file_size_limit
  INTO bucket_public, bucket_size_limit
  FROM storage.buckets
  WHERE id = 'yarnnn-assets';

  -- Count storage.objects policies
  SELECT COUNT(*) INTO storage_policies
  FROM pg_policies
  WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE '%yarnnn-assets%' OR policyname LIKE '%workspace baskets%';

  RAISE NOTICE '✅ Migration 3 (Phase 1 - Storage Setup) Complete:';
  RAISE NOTICE '  - Bucket yarnnn-assets exists: %', bucket_exists;

  IF bucket_exists THEN
    RAISE NOTICE '  - Bucket public setting: % (should be false)', bucket_public;
    RAISE NOTICE '  - File size limit: % MB', bucket_size_limit / 1048576;
    RAISE NOTICE '  - Storage RLS policies: % (expected 5+)', storage_policies;

    -- Validation warnings
    IF bucket_public THEN
      RAISE WARNING 'Bucket is PUBLIC - should be PRIVATE for security';
    END IF;

    IF bucket_size_limit > 52428800 THEN
      RAISE WARNING 'File size limit too high: % MB (recommended: 50 MB)', bucket_size_limit / 1048576;
    END IF;

    IF storage_policies < 5 THEN
      RAISE WARNING 'Storage policies incomplete (expected 5+, got %)', storage_policies;
    END IF;
  ELSE
    RAISE WARNING 'Bucket yarnnn-assets does not exist - create manually via Supabase Dashboard';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Manual Setup Steps:';
    RAISE NOTICE '  1. Navigate to Supabase Dashboard → Storage → Buckets';
    RAISE NOTICE '  2. Click "New Bucket"';
    RAISE NOTICE '  3. Name: yarnnn-assets';
    RAISE NOTICE '  4. Public: OFF (private bucket)';
    RAISE NOTICE '  5. File size limit: 50 MB';
    RAISE NOTICE '  6. Allowed MIME types: image/*, application/pdf, application/json, text/*';
    RAISE NOTICE '  7. Click "Create Bucket"';
    RAISE NOTICE '  8. Re-run this migration to apply RLS policies';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '✅ All Phase 1 Migrations Complete!';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Next Steps:';
  RAISE NOTICE '  1. Verify all migrations with: psql $PG_DUMP_URL -f scripts/phase1_verify.sh';
  RAISE NOTICE '  2. Deploy substrate-API file upload endpoints';
  RAISE NOTICE '  3. Deploy work-platform BFF proxy routes';
  RAISE NOTICE '  4. Build UI components (Assets tab, Config forms)';
  RAISE NOTICE '  5. Test end-to-end asset upload/download flow';
END $$;
