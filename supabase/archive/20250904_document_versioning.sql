-- Step 3: Add Document Versioning System (Git-inspired)

BEGIN;

-- =============================================================================
-- DOCUMENT VERSIONING TABLES  
-- =============================================================================

-- Document versions (git-like snapshots)
CREATE TABLE document_versions (
  version_hash varchar(64) PRIMARY KEY,
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  content text NOT NULL,
  metadata_snapshot jsonb DEFAULT '{}',
  substrate_refs_snapshot jsonb DEFAULT '[]',
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  version_message text,
  parent_version_hash varchar(64),
  
  CONSTRAINT valid_version_hash CHECK (version_hash ~ '^doc_v[a-f0-9]{58}$'),
  CONSTRAINT non_empty_content CHECK (length(content) > 0)
);

-- Add current version tracking to documents
ALTER TABLE documents ADD COLUMN IF NOT EXISTS current_version_hash varchar(64);

-- =============================================================================
-- ARTIFACT REFLECTIONS SYSTEM
-- =============================================================================

-- Rename reflection_cache to reflections_artifact for clarity
ALTER TABLE reflection_cache RENAME TO reflections_artifact;

-- Add flexible targeting columns
ALTER TABLE reflections_artifact
  ADD COLUMN IF NOT EXISTS reflection_target_type varchar(20) DEFAULT 'legacy',
  ADD COLUMN IF NOT EXISTS reflection_target_id uuid,
  ADD COLUMN IF NOT EXISTS reflection_target_version varchar(64);

-- Add constraint for valid targets  
ALTER TABLE reflections_artifact
  ADD CONSTRAINT valid_reflection_target
  CHECK (reflection_target_type IN ('substrate', 'document', 'legacy'));

-- =============================================================================
-- FUNCTIONS FOR NEW MODEL
-- =============================================================================

-- Function: Create document version
CREATE OR REPLACE FUNCTION fn_document_create_version(
  p_document_id uuid,
  p_content text,
  p_version_message text DEFAULT NULL
) RETURNS varchar(64)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_version_hash varchar(64);
  v_workspace_id uuid;
BEGIN
  -- Generate version hash (git-like)
  v_version_hash := 'doc_v' || substr(encode(sha256(p_content::bytea), 'hex'), 1, 58);
  
  -- Get document workspace for validation
  SELECT workspace_id INTO v_workspace_id 
  FROM documents WHERE id = p_document_id;
  
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Document % not found', p_document_id;
  END IF;
  
  -- Insert version (idempotent by hash)
  INSERT INTO document_versions (
    version_hash,
    document_id,
    content,
    metadata_snapshot,
    substrate_refs_snapshot,
    created_by,
    version_message,
    parent_version_hash
  ) 
  SELECT 
    v_version_hash,
    p_document_id,
    p_content,
    d.metadata,
    COALESCE(
      (SELECT jsonb_agg(to_jsonb(sr.*)) 
       FROM substrate_references sr 
       WHERE sr.document_id = p_document_id), 
      '[]'::jsonb
    ),
    auth.uid(),
    p_version_message,
    d.current_version_hash
  FROM documents d 
  WHERE d.id = p_document_id
  ON CONFLICT (version_hash) DO NOTHING;
  
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
    'Document version created: ' || left(v_version_hash, 12),
    jsonb_build_object('version_hash', v_version_hash, 'message', p_version_message)
  );
  
  RETURN v_version_hash;
END $$;

-- Function: Create substrate reflection
CREATE OR REPLACE FUNCTION fn_reflection_create_from_substrate(
  p_basket_id uuid,
  p_reflection_text text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
  v_substrate_hash varchar(64);
BEGIN
  -- Get workspace
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  
  -- Generate substrate hash for this basket's current state
  v_substrate_hash := 'substrate_' || encode(sha256((p_basket_id || now())::text::bytea), 'hex');
  
  -- Insert substrate-focused reflection
  INSERT INTO reflections_artifact (
    basket_id,
    workspace_id,
    reflection_text,
    substrate_hash,
    reflection_target_type,
    computation_timestamp
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    v_substrate_hash,
    'substrate',
    now()
  ) RETURNING id INTO v_reflection_id;
  
  -- Emit timeline event
  PERFORM fn_timeline_emit(
    p_basket_id,
    'reflection.computed',
    v_reflection_id,
    left(p_reflection_text, 140),
    jsonb_build_object('target_type', 'substrate')
  );
  
  RETURN v_reflection_id;
END $$;

-- Function: Create document reflection
CREATE OR REPLACE FUNCTION fn_reflection_create_from_document(
  p_basket_id uuid,
  p_document_id uuid,
  p_reflection_text text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
  v_version_hash varchar(64);
BEGIN
  -- Get workspace and current document version
  SELECT d.workspace_id, d.current_version_hash
  INTO v_workspace_id, v_version_hash
  FROM documents d WHERE d.id = p_document_id;
  
  -- Create document-focused reflection
  INSERT INTO reflections_artifact (
    basket_id,
    workspace_id,
    reflection_text,
    substrate_hash,
    reflection_target_type,
    reflection_target_id,
    reflection_target_version,
    computation_timestamp
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    'document_' || COALESCE(v_version_hash, 'current'),
    'document',
    p_document_id,
    v_version_hash,
    now()
  ) RETURNING id INTO v_reflection_id;
  
  RETURN v_reflection_id;
END $$;

-- =============================================================================
-- INDEXES FOR PERFORMANCE
-- =============================================================================

-- Document versioning indexes
CREATE INDEX idx_document_versions_document ON document_versions(document_id);
CREATE INDEX idx_document_versions_hash ON document_versions(version_hash);
CREATE INDEX idx_document_versions_created ON document_versions(created_at DESC);

-- Documents current version
CREATE INDEX idx_documents_current_version ON documents(current_version_hash) WHERE current_version_hash IS NOT NULL;

-- Reflections artifact indexes
CREATE INDEX idx_reflections_target ON reflections_artifact(reflection_target_type, reflection_target_id);
CREATE INDEX idx_reflections_basket ON reflections_artifact(basket_id);

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

-- Document versions RLS
ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "document_versions_workspace_select" ON document_versions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      JOIN workspace_memberships wm ON b.workspace_id = wm.workspace_id  
      WHERE d.id = document_versions.document_id
      AND wm.user_id = auth.uid()
    )
  );

CREATE POLICY "document_versions_workspace_insert" ON document_versions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      JOIN workspace_memberships wm ON b.workspace_id = wm.workspace_id
      WHERE d.id = document_versions.document_id
      AND wm.user_id = auth.uid()
    )
  );

-- Reflections artifact RLS (updated table name)
CREATE POLICY "reflections_artifact_workspace_select" ON reflections_artifact
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM workspace_memberships wm
      WHERE wm.workspace_id = reflections_artifact.workspace_id
      AND wm.user_id = auth.uid()
    )
  );

CREATE POLICY "reflections_artifact_service_insert" ON reflections_artifact
  FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

GRANT EXECUTE ON FUNCTION fn_document_create_version(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_document_create_version(uuid, text, text) TO service_role;

GRANT EXECUTE ON FUNCTION fn_reflection_create_from_substrate(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION fn_reflection_create_from_document(uuid, uuid, text) TO service_role;

-- Recreate attach/detach functions with new enum
GRANT EXECUTE ON FUNCTION fn_document_attach_substrate(uuid, substrate_type, uuid, text, numeric, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_document_detach_substrate(uuid, substrate_type, uuid) TO authenticated;

COMMIT;