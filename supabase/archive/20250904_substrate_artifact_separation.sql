-- Migration: Substrate/Artifact Separation (Canon v2.0)
-- Removes reflection from substrate_type, adds document versioning, updates reflection targeting

BEGIN;

-- Step 1: Create new substrate_type enum without 'reflection'
CREATE TYPE substrate_type_v2 AS ENUM (
  'block',           -- context_blocks (knowledge ingredients)
  'dump',            -- raw_dumps (sacred capture)
  'context_item',    -- context_items (connective tissue)
  'timeline_event'   -- timeline_events (system memory)
);

-- Step 2: Create document versioning system (git-inspired)
CREATE TABLE document_versions (
  version_hash varchar(64) PRIMARY KEY,              -- SHA-256 of content (git-like)
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  content text NOT NULL,                              -- Full content at this version
  content_delta text,                                 -- Delta from previous version (performance)
  metadata_snapshot jsonb DEFAULT '{}',               -- Metadata at time of version
  substrate_refs_snapshot jsonb DEFAULT '[]',         -- Substrate references at time of version
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  version_message text,                               -- Optional commit-like message
  parent_version_hash varchar(64) REFERENCES document_versions(version_hash),
  
  -- Performance indexes
  CONSTRAINT valid_hash_format CHECK (version_hash ~ '^[a-f0-9]{64}$'),
  CONSTRAINT non_empty_content CHECK (length(content) > 0)
);

-- Step 3: Add current version tracking to documents
ALTER TABLE documents ADD COLUMN IF NOT EXISTS current_version_hash varchar(64);

-- Step 4: Update reflections to handle substrate + document version targets
ALTER TABLE reflections 
  ADD COLUMN IF NOT EXISTS reflection_target_type varchar(20) DEFAULT 'legacy',
  ADD COLUMN IF NOT EXISTS reflection_target_id uuid,
  ADD COLUMN IF NOT EXISTS reflection_target_version varchar(64),
  ADD COLUMN IF NOT EXISTS substrate_analysis_window jsonb DEFAULT '{}';

-- Add constraint to ensure target type is valid
ALTER TABLE reflections 
  ADD CONSTRAINT valid_reflection_target_type 
  CHECK (reflection_target_type IN ('substrate', 'document', 'legacy'));

-- Step 5: Migrate existing substrate_references away from 'reflection' type
-- First, backup existing reflection references
CREATE TABLE substrate_references_reflection_backup AS 
  SELECT * FROM substrate_references WHERE substrate_type = 'reflection';

-- Remove reflection references from substrate_references (they're now invalid)
DELETE FROM substrate_references WHERE substrate_type = 'reflection';

-- Step 6: Update substrate_references to use new enum
-- This is a breaking change - requires careful deployment
ALTER TABLE substrate_references 
  ALTER COLUMN substrate_type TYPE substrate_type_v2 
  USING substrate_type::text::substrate_type_v2;

-- Step 7: Drop old enum type
DROP TYPE substrate_type;
ALTER TYPE substrate_type_v2 RENAME TO substrate_type;

-- Step 8: Create performance indexes
CREATE INDEX idx_document_versions_document ON document_versions(document_id);
CREATE INDEX idx_document_versions_created ON document_versions(created_at DESC);
CREATE INDEX idx_document_versions_parent ON document_versions(parent_version_hash);
CREATE INDEX idx_documents_current_version ON documents(current_version_hash);
CREATE INDEX idx_reflections_target ON reflections(reflection_target_type, reflection_target_id);

-- Step 9: Create functions for document versioning

-- Function to create document version (git-inspired)
CREATE OR REPLACE FUNCTION fn_document_create_version(
  p_document_id uuid,
  p_content text,
  p_version_message text DEFAULT NULL,
  p_created_by uuid DEFAULT NULL
) RETURNS varchar(64)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_version_hash varchar(64);
  v_previous_version varchar(64);
  v_content_delta text;
  v_metadata_snapshot jsonb;
  v_refs_snapshot jsonb;
BEGIN
  -- Generate content hash (SHA-256-like)
  v_version_hash := 'doc_v' || encode(sha256(p_content::bytea), 'hex');
  
  -- Get current document state
  SELECT current_version_hash INTO v_previous_version 
    FROM documents WHERE id = p_document_id;
  
  -- Get metadata and references snapshot
  SELECT to_jsonb(d.*) - 'id' - 'current_version_hash'
    INTO v_metadata_snapshot
    FROM documents d WHERE id = p_document_id;
    
  SELECT COALESCE(jsonb_agg(to_jsonb(sr.*)), '[]'::jsonb)
    INTO v_refs_snapshot  
    FROM substrate_references sr WHERE document_id = p_document_id;
  
  -- Compute delta if previous version exists
  IF v_previous_version IS NOT NULL THEN
    SELECT content INTO v_content_delta 
      FROM document_versions 
      WHERE version_hash = v_previous_version;
    -- Simple delta: store previous content for reconstruction
  END IF;
  
  -- Insert version
  INSERT INTO document_versions (
    version_hash,
    document_id,
    content,
    content_delta,
    metadata_snapshot,
    substrate_refs_snapshot,
    created_by,
    version_message,
    parent_version_hash
  ) VALUES (
    v_version_hash,
    p_document_id,
    p_content,
    v_content_delta,
    v_metadata_snapshot,
    v_refs_snapshot,
    COALESCE(p_created_by, auth.uid()),
    p_version_message,
    v_previous_version
  ) ON CONFLICT (version_hash) DO NOTHING;
  
  -- Update document current version
  UPDATE documents 
    SET current_version_hash = v_version_hash,
        updated_at = now()
    WHERE id = p_document_id;
  
  -- Emit timeline event
  PERFORM fn_timeline_emit(
    (SELECT basket_id FROM documents WHERE id = p_document_id),
    'document.versioned',
    p_document_id,
    'Document version ' || left(v_version_hash, 8) || ' created',
    jsonb_build_object(
      'version_hash', v_version_hash,
      'version_message', p_version_message
    )
  );
  
  RETURN v_version_hash;
END $$;

-- Function to create substrate-focused reflection  
CREATE OR REPLACE FUNCTION fn_reflection_create_substrate(
  p_basket_id uuid,
  p_substrate_ids uuid[],
  p_reflection_text text,
  p_analysis_window jsonb DEFAULT '{}'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
BEGIN
  -- Get workspace from basket
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  
  -- Insert reflection targeting substrate
  INSERT INTO reflections (
    basket_id,
    workspace_id,
    reflection_text,
    reflection_target_type,
    substrate_analysis_window,
    created_at
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    'substrate',
    p_analysis_window,
    now()
  ) RETURNING id INTO v_reflection_id;
  
  -- Emit timeline event
  PERFORM fn_timeline_emit(
    p_basket_id,
    'reflection.computed',
    v_reflection_id,
    left(p_reflection_text, 140),
    jsonb_build_object(
      'target_type', 'substrate',
      'substrate_count', array_length(p_substrate_ids, 1)
    )
  );
  
  RETURN v_reflection_id;
END $$;

-- Function to create document-focused reflection
CREATE OR REPLACE FUNCTION fn_reflection_create_document(
  p_basket_id uuid,
  p_document_id uuid,
  p_document_version varchar(64),
  p_reflection_text text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
BEGIN
  -- Get workspace from basket
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  
  -- Insert reflection targeting document version
  INSERT INTO reflections (
    basket_id,
    workspace_id,
    reflection_text,
    reflection_target_type,
    reflection_target_id,
    reflection_target_version,
    created_at
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    'document',
    p_document_id,
    p_document_version,
    now()
  ) RETURNING id INTO v_reflection_id;
  
  -- Emit timeline event
  PERFORM fn_timeline_emit(
    p_basket_id,
    'reflection.computed',
    v_reflection_id,
    left(p_reflection_text, 140),
    jsonb_build_object(
      'target_type', 'document',
      'document_id', p_document_id,
      'version_hash', p_document_version
    )
  );
  
  RETURN v_reflection_id;
END $$;

-- Step 10: Grant permissions
GRANT EXECUTE ON FUNCTION fn_document_create_version(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_document_create_version(uuid, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION fn_reflection_create_substrate(uuid, uuid[], text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION fn_reflection_create_document(uuid, uuid, varchar(64), text) TO service_role;

-- Step 11: Add RLS policies for new tables
ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "document_versions_select_policy" ON document_versions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      WHERE d.id = document_versions.document_id
      AND (b.visibility = 'public' OR b.user_id = auth.uid())
    )
  );

CREATE POLICY "document_versions_insert_policy" ON document_versions
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      WHERE d.id = document_versions.document_id
      AND b.user_id = auth.uid()
    )
  );

-- Step 12: Update existing functions to handle new schema
-- Note: fn_persist_reflection will need to be updated to use new reflection structure

COMMIT;

-- Post-migration validation queries
-- SELECT 'substrate_type enum' as check, unnest(enum_range(NULL::substrate_type));
-- SELECT 'reflection targeting' as check, reflection_target_type, count(*) FROM reflections GROUP BY reflection_target_type;