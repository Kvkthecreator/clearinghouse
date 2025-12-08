-- Canon v3.0: Document Composition Model - Phase 1 Schema Migration
--
-- Revolutionary Change: Documents become read-only composed views of substrate.
-- Users manage substrate and direct composition; they never edit prose directly.
--
-- Key Changes:
-- 1. Remove content_raw, content_rendered from documents (content lives in versions)
-- 2. Add composition_instructions, substrate_filter to documents
-- 3. Add source_raw_dump_id to link uploaded documents
-- 4. Add version_trigger to document_versions
-- 5. Add document_id to raw_dumps for upload wizard linking

BEGIN;

-- =====================================================
-- 1. Backup existing document content to versions
-- =====================================================

-- For any document with content_raw but no version, create initial version
INSERT INTO document_versions (
  version_hash,
  document_id,
  content,
  metadata_snapshot,
  substrate_refs_snapshot,
  created_at,
  created_by,
  version_message,
  composition_contract
)
SELECT
  'doc_v' || substring(encode(sha256(COALESCE(d.content_raw, d.title)::bytea || d.id::text::bytea), 'hex'), 1, 58),
  d.id,
  CASE
    WHEN d.content_raw IS NOT NULL AND length(d.content_raw) > 0 THEN d.content_raw
    ELSE d.title || E'\n\n(Document created but content not yet added)'
  END,
  d.metadata,
  COALESCE(
    (SELECT jsonb_agg(
      jsonb_build_object(
        'substrate_type', sr.substrate_type,
        'substrate_id', sr.substrate_id,
        'role', sr.role,
        'weight', sr.weight
      )
    )
    FROM substrate_references sr
    WHERE sr.document_id = d.id),
    '[]'::jsonb
  ),
  d.created_at,
  d.created_by,
  'Initial version (migrated from content_raw)',
  jsonb_build_object('migrated', true, 'original_status', d.status)
FROM documents d
WHERE NOT EXISTS (
    SELECT 1 FROM document_versions dv WHERE dv.document_id = d.id
  )
ON CONFLICT (version_hash) DO NOTHING;

-- Update documents.current_version_hash to point to migrated versions
UPDATE documents d
SET current_version_hash = (
  SELECT dv.version_hash
  FROM document_versions dv
  WHERE dv.document_id = d.id
  ORDER BY dv.created_at DESC
  LIMIT 1
)
WHERE d.current_version_hash IS NULL
  AND EXISTS (SELECT 1 FROM document_versions dv WHERE dv.document_id = d.id);

-- =====================================================
-- 2. Add new composition fields to documents
-- =====================================================

-- Add composition_instructions (defines how to compose from substrate)
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS composition_instructions jsonb DEFAULT '{}'::jsonb;

COMMENT ON COLUMN documents.composition_instructions IS
  'Instructions for P4 composition agent: tone, style, section-specific guidance';

-- Add substrate_filter (defines which substrate to include)
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS substrate_filter jsonb DEFAULT '{}'::jsonb;

COMMENT ON COLUMN documents.substrate_filter IS
  'Filter criteria for substrate selection: anchor_roles, semantic_types, etc.';

-- Add source_raw_dump_id (link to uploaded document)
ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS source_raw_dump_id uuid REFERENCES raw_dumps(id) ON DELETE SET NULL;

COMMENT ON COLUMN documents.source_raw_dump_id IS
  'If document was composed from uploaded file, links to original raw_dump for reference';

-- =====================================================
-- 3. Remove editing fields from documents
-- =====================================================

-- Drop dependent views first (legacy code - delete and streamline)
DROP VIEW IF EXISTS v_narrative_documents CASCADE;

-- Remove content fields (content now lives in versions only)
ALTER TABLE documents
  DROP COLUMN IF EXISTS content_raw,
  DROP COLUMN IF EXISTS content_rendered;

-- Remove status (documents are always "composed", not "draft")
ALTER TABLE documents
  DROP COLUMN IF EXISTS status;

-- Keep document_type for backward compatibility (will use for templates)
-- Keep metadata for extensibility

-- =====================================================
-- 4. Add version_trigger to document_versions
-- =====================================================

ALTER TABLE document_versions
  ADD COLUMN IF NOT EXISTS version_trigger text;

-- Add check constraint for valid triggers
ALTER TABLE document_versions
  DROP CONSTRAINT IF EXISTS valid_version_trigger;

ALTER TABLE document_versions
  ADD CONSTRAINT valid_version_trigger CHECK (
    version_trigger IS NULL OR
    version_trigger IN (
      'initial',
      'substrate_update',
      'user_requested',
      'instruction_change',
      'upload_composition',
      'migrated'
    )
  );

COMMENT ON COLUMN document_versions.version_trigger IS
  'What caused this version: initial, substrate_update, user_requested, instruction_change, upload_composition, migrated';

-- Set version_trigger for existing versions
UPDATE document_versions
SET version_trigger = 'migrated'
WHERE version_trigger IS NULL;

-- =====================================================
-- 5. Add document_id to raw_dumps (upload wizard linking)
-- =====================================================

-- Link from raw_dump to composed document (if upload wizard used)
-- Already exists in schema, just add comment
COMMENT ON COLUMN raw_dumps.document_id IS
  'If raw_dump was uploaded as document import, links to composed YARNNN document';

-- =====================================================
-- 6. Update table comments to reflect new model
-- =====================================================

COMMENT ON TABLE documents IS
  'Canon v3.0: Composition definitions that generate versioned artifacts from substrate. Content lives in versions only. Documents are read-only composed views - users manage substrate, not prose.';

COMMENT ON TABLE document_versions IS
  'Immutable snapshots of composed documents. Content is frozen and read-only. Each version captures substrate state at composition time.';

-- =====================================================
-- 7. Create helper view for document HEAD state
-- =====================================================

CREATE OR REPLACE VIEW document_heads AS
SELECT
  d.id AS document_id,
  d.basket_id,
  d.workspace_id,
  d.title,
  d.document_type,
  d.composition_instructions,
  d.substrate_filter,
  d.source_raw_dump_id,
  d.current_version_hash,
  d.created_at AS document_created_at,
  d.created_by AS document_created_by,
  d.updated_at AS document_updated_at,
  d.metadata AS document_metadata,

  -- Current version content
  dv.content,
  dv.metadata_snapshot AS version_metadata,
  dv.substrate_refs_snapshot,
  dv.created_at AS version_created_at,
  dv.created_by AS version_created_by,
  dv.version_trigger,
  dv.version_message

FROM documents d
LEFT JOIN document_versions dv ON dv.version_hash = d.current_version_hash;

COMMENT ON VIEW document_heads IS
  'Current HEAD state of documents with their latest version content. Use this for reading document content.';

-- =====================================================
-- 8. Update RLS policies (documents now composition-only)
-- =====================================================

-- RLS policies remain unchanged - workspace-scoped access
-- Users can still create/read/update documents, but content is managed via versions

COMMIT;

-- =====================================================
-- Migration Summary
-- =====================================================
-- ✅ Existing document content preserved in document_versions
-- ✅ Documents table now stores composition definitions only
-- ✅ Added composition_instructions and substrate_filter
-- ✅ Added source_raw_dump_id for upload wizard
-- ✅ Added version_trigger to document_versions
-- ✅ Created document_heads view for easy HEAD access
-- ✅ Updated table comments to reflect Canon v3.0
--
-- Next: Phase 2 - Upload Wizard implementation
