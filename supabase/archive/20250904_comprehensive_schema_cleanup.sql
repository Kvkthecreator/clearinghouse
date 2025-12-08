-- Comprehensive Schema Cleanup: Substrate/Artifact Separation + Legacy Removal
-- This migration implements Canon v2.0 with clean substrate/artifact model

BEGIN;

-- =============================================================================
-- STEP 1: BACKUP LEGACY DATA (before deletion)
-- =============================================================================

-- Backup block_links before deletion
CREATE TABLE block_links_legacy_backup AS SELECT * FROM block_links;

-- Backup document_context_items before deletion  
CREATE TABLE document_context_items_legacy_backup AS SELECT * FROM document_context_items;

-- Backup reflection substrate_references before deletion
CREATE TABLE substrate_references_reflection_backup AS 
  SELECT * FROM substrate_references WHERE substrate_type = 'reflection';

-- =============================================================================
-- STEP 2: CREATE NEW SUBSTRATE_TYPE ENUM (Pure Substrates Only)
-- =============================================================================

-- Create new enum without 'reflection' 
CREATE TYPE substrate_type_v2 AS ENUM (
  'block',           -- context_blocks (knowledge ingredients)
  'dump',            -- raw_dumps (sacred capture)
  'context_item',    -- context_items (connective tissue)
  'timeline_event'   -- timeline_events (system memory)
);

-- =============================================================================
-- STEP 3: DOCUMENT VERSIONING SYSTEM (Git-inspired)
-- =============================================================================

-- Document versions table (git-like)
CREATE TABLE document_versions (
  version_hash varchar(64) PRIMARY KEY,              -- SHA-256 of content
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  content text NOT NULL,                              -- Full content at version
  content_delta text,                                 -- Delta from previous (performance)
  metadata_snapshot jsonb DEFAULT '{}',               -- Metadata at time of version
  substrate_refs_snapshot jsonb DEFAULT '[]',         -- Substrate refs at time of version
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  version_message text,                               -- Optional commit message
  parent_version_hash varchar(64) REFERENCES document_versions(version_hash),
  
  -- Constraints
  CONSTRAINT valid_version_hash_format CHECK (version_hash ~ '^doc_v[a-f0-9]{58}$'),
  CONSTRAINT non_empty_content CHECK (length(content) > 0)
);

-- Add current version tracking to documents
ALTER TABLE documents 
  ADD COLUMN IF NOT EXISTS current_version_hash varchar(64),
  ADD CONSTRAINT documents_current_version_fk 
    FOREIGN KEY (current_version_hash) REFERENCES document_versions(version_hash);

-- =============================================================================
-- STEP 4: UPDATE REFLECTIONS FOR ARTIFACT TARGETING  
-- =============================================================================

-- Rename reflection_cache to reflections_artifact (clarity)
ALTER TABLE reflection_cache RENAME TO reflections_artifact;

-- Add columns for flexible targeting (substrate OR document versions)
ALTER TABLE reflections_artifact
  ADD COLUMN IF NOT EXISTS reflection_target_type varchar(20) DEFAULT 'legacy',
  ADD COLUMN IF NOT EXISTS reflection_target_id uuid,
  ADD COLUMN IF NOT EXISTS reflection_target_version varchar(64),
  ADD COLUMN IF NOT EXISTS substrate_analysis_ids uuid[],
  ADD COLUMN IF NOT EXISTS computation_method varchar(50) DEFAULT 'pattern_analysis';

-- Add constraint for valid target types
ALTER TABLE reflections_artifact
  ADD CONSTRAINT valid_reflection_target_type 
  CHECK (reflection_target_type IN ('substrate', 'document', 'legacy'));

-- =============================================================================
-- STEP 5: CLEAN UP SUBSTRATE_REFERENCES (Remove reflection references)
-- =============================================================================

-- Remove reflection references (they're now artifacts, not substrates)
DELETE FROM substrate_references WHERE substrate_type = 'reflection';

-- Update substrate_references to use new enum  
ALTER TABLE substrate_references 
  ALTER COLUMN substrate_type TYPE substrate_type_v2 
  USING substrate_type::text::substrate_type_v2;

-- =============================================================================
-- STEP 6: DROP LEGACY TABLES (Clean Slate)
-- =============================================================================

-- Drop legacy document reference systems
DROP TABLE IF EXISTS block_links CASCADE;           -- Replaced by substrate_references
DROP TABLE IF EXISTS document_context_items CASCADE; -- Replaced by substrate_references

-- Drop deprecated basket events (use events table)
DROP TABLE IF EXISTS basket_events CASCADE;

-- Drop generic revisions (document versioning handles this)
DROP TABLE IF EXISTS revisions CASCADE;

-- Drop old substrate_type enum
DROP TYPE substrate_type;
ALTER TYPE substrate_type_v2 RENAME TO substrate_type;

-- =============================================================================
-- STEP 7: UPDATE VIEWS FOR NEW MODEL
-- =============================================================================

-- Update composition stats view (remove reflections_count)
DROP VIEW IF EXISTS document_composition_stats CASCADE;

CREATE VIEW document_composition_stats AS
 SELECT substrate_references.document_id,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'block') AS blocks_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'dump') AS dumps_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'context_item') AS context_items_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'timeline_event') AS timeline_events_count,
    count(*) AS total_substrate_references
   FROM substrate_references
  GROUP BY substrate_references.document_id;

-- Create artifact composition view (separate from substrate)
CREATE VIEW document_artifact_stats AS
 SELECT d.id as document_id,
    d.title,
    d.current_version_hash,
    dcs.total_substrate_references,
    COALESCE(ref_stats.reflections_count, 0) as reflections_count,
    COALESCE(ver_stats.versions_count, 0) as versions_count
   FROM documents d
   LEFT JOIN document_composition_stats dcs ON d.id = dcs.document_id
   LEFT JOIN (
     SELECT reflection_target_id as document_id, count(*) as reflections_count
     FROM reflections_artifact 
     WHERE reflection_target_type = 'document'
     GROUP BY reflection_target_id
   ) ref_stats ON d.id = ref_stats.document_id
   LEFT JOIN (
     SELECT document_id, count(*) as versions_count
     FROM document_versions
     GROUP BY document_id  
   ) ver_stats ON d.id = ver_stats.document_id;

-- =============================================================================
-- STEP 8: CREATE OPTIMIZED FUNCTIONS
-- =============================================================================

-- Function: Create document version (git-inspired)
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
  v_previous_version varchar(64);
  v_metadata_snapshot jsonb;
  v_refs_snapshot jsonb;
  v_workspace_id uuid;
BEGIN
  -- Generate version hash
  v_version_hash := 'doc_v' || substr(encode(sha256(p_content::bytea), 'hex'), 1, 58);
  
  -- Get document context
  SELECT current_version_hash, metadata, workspace_id, basket_id
    INTO v_previous_version, v_metadata_snapshot, v_workspace_id
    FROM documents WHERE id = p_document_id;
    
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % not found', p_document_id;
  END IF;
  
  -- Get substrate references snapshot
  SELECT COALESCE(jsonb_agg(to_jsonb(sr.*)), '[]'::jsonb)
    INTO v_refs_snapshot
    FROM substrate_references sr WHERE document_id = p_document_id;
  
  -- Insert version (idempotent)
  INSERT INTO document_versions (
    version_hash,
    document_id,
    content,
    metadata_snapshot,
    substrate_refs_snapshot,
    created_by,
    version_message,
    parent_version_hash
  ) VALUES (
    v_version_hash,
    p_document_id,
    p_content,
    v_metadata_snapshot,
    v_refs_snapshot,
    auth.uid(),
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
    'Version ' || left(v_version_hash, 12),
    jsonb_build_object(
      'version_hash', v_version_hash,
      'message', p_version_message,
      'substrate_refs_count', jsonb_array_length(v_refs_snapshot)
    )
  );
  
  RETURN v_version_hash;
END $$;

-- Function: Create substrate reflection
CREATE OR REPLACE FUNCTION fn_reflection_create_from_substrate(
  p_basket_id uuid,
  p_substrate_ids uuid[],
  p_reflection_text text,
  p_computation_method varchar(50) DEFAULT 'ai_analysis'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
BEGIN
  -- Get workspace
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  
  -- Create substrate-focused reflection
  INSERT INTO reflections_artifact (
    basket_id,
    workspace_id,
    reflection_text,
    reflection_target_type,
    substrate_analysis_ids,
    computation_method,
    computation_timestamp,
    substrate_hash
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    'substrate',
    p_substrate_ids,
    p_computation_method,
    now(),
    'substrate_' || encode(sha256(array_to_string(p_substrate_ids, ',')::bytea), 'hex')
  ) RETURNING id INTO v_reflection_id;
  
  RETURN v_reflection_id;
END $$;

-- Function: Create document reflection
CREATE OR REPLACE FUNCTION fn_reflection_create_from_document(
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
  -- Get workspace
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  
  -- Create document-focused reflection
  INSERT INTO reflections_artifact (
    basket_id,
    workspace_id,
    reflection_text,
    reflection_target_type,
    reflection_target_id,
    reflection_target_version,
    computation_timestamp,
    substrate_hash
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    'document',
    p_document_id,
    p_document_version,
    now(),
    'document_' || p_document_version
  ) RETURNING id INTO v_reflection_id;
  
  RETURN v_reflection_id;
END $$;

-- =============================================================================
-- STEP 9: PERFORMANCE INDEXES (Git-inspired)
-- =============================================================================

-- Document versioning indexes
CREATE INDEX idx_document_versions_document ON document_versions(document_id);
CREATE INDEX idx_document_versions_created ON document_versions(created_at DESC);
CREATE INDEX idx_document_versions_parent ON document_versions(parent_version_hash);
CREATE INDEX idx_document_versions_hash ON document_versions(version_hash);

-- Documents current version
CREATE INDEX idx_documents_current_version ON documents(current_version_hash);

-- Artifact reflections
CREATE INDEX idx_reflections_target ON reflections_artifact(reflection_target_type, reflection_target_id);
CREATE INDEX idx_reflections_basket ON reflections_artifact(basket_id);
CREATE INDEX idx_reflections_computation ON reflections_artifact(computation_timestamp DESC);

-- Substrate references (optimized)
CREATE INDEX idx_substrate_refs_compound ON substrate_references(document_id, substrate_type);

-- =============================================================================
-- STEP 10: RLS POLICIES FOR NEW TABLES
-- =============================================================================

-- Document versions RLS
ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "document_versions_select" ON document_versions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id  
      JOIN workspace_memberships wm ON b.workspace_id = wm.workspace_id
      WHERE d.id = document_versions.document_id
      AND wm.user_id = auth.uid()
    )
  );

CREATE POLICY "document_versions_insert" ON document_versions
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      JOIN workspace_memberships wm ON b.workspace_id = wm.workspace_id
      WHERE d.id = document_versions.document_id
      AND wm.user_id = auth.uid()
    )
  );

-- Reflections artifact RLS (renamed from reflection_cache)
ALTER TABLE reflections_artifact ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reflections_artifact_select" ON reflections_artifact
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM workspace_memberships wm
      WHERE wm.workspace_id = reflections_artifact.workspace_id
      AND wm.user_id = auth.uid()
    )
  );

-- Service role can insert reflections (system operations)
CREATE POLICY "reflections_artifact_service_insert" ON reflections_artifact
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- =============================================================================
-- STEP 11: GRANT PERMISSIONS
-- =============================================================================

-- Document versioning functions
GRANT EXECUTE ON FUNCTION fn_document_create_version(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_document_create_version(uuid, text, text) TO service_role;

-- Reflection functions (service role only - system operations)
GRANT EXECUTE ON FUNCTION fn_reflection_create_from_substrate(uuid, uuid[], text, varchar) TO service_role;
GRANT EXECUTE ON FUNCTION fn_reflection_create_from_document(uuid, uuid, varchar, text) TO service_role;

-- =============================================================================
-- STEP 12: MIGRATE EXISTING DATA
-- =============================================================================

-- Migrate block_links to substrate_references if not already done
INSERT INTO substrate_references (document_id, substrate_type, substrate_id, snippets, metadata, created_at)
  SELECT 
    bl.document_id,
    'block'::substrate_type_v2,
    bl.block_id,
    bl.snippets,
    jsonb_build_object('migrated_from', 'block_links', 'occurrences', bl.occurrences),
    now()
  FROM block_links bl
  WHERE NOT EXISTS (
    SELECT 1 FROM substrate_references sr 
    WHERE sr.document_id = bl.document_id 
    AND sr.substrate_type = 'block' 
    AND sr.substrate_id = bl.block_id
  );

-- Migrate document_context_items to substrate_references if not already done  
INSERT INTO substrate_references (document_id, substrate_type, substrate_id, role, weight, metadata, created_at)
  SELECT
    dci.document_id,
    'context_item'::substrate_type_v2,
    dci.context_item_id,
    dci.role,
    dci.weight,
    jsonb_build_object('migrated_from', 'document_context_items'),
    dci.created_at
  FROM document_context_items dci
  WHERE NOT EXISTS (
    SELECT 1 FROM substrate_references sr
    WHERE sr.document_id = dci.document_id
    AND sr.substrate_type = 'context_item'  
    AND sr.substrate_id = dci.context_item_id
  );

-- Update substrate_references to use new enum
ALTER TABLE substrate_references 
  ALTER COLUMN substrate_type TYPE substrate_type_v2
  USING substrate_type::text::substrate_type_v2;

-- =============================================================================
-- STEP 13: DROP LEGACY TABLES (Clean Slate)  
-- =============================================================================

-- Remove legacy reference systems
DROP TABLE block_links CASCADE;
DROP TABLE document_context_items CASCADE;

-- Remove deprecated event system
DROP TABLE basket_events CASCADE;  
DROP SEQUENCE basket_events_id_seq CASCADE;

-- Remove generic revision system  
DROP TABLE revisions CASCADE;
DROP TABLE block_revisions CASCADE;

-- Rename enum for clarity
DROP TYPE substrate_type;
ALTER TYPE substrate_type_v2 RENAME TO substrate_type;

-- =============================================================================
-- STEP 14: UPDATE FUNCTIONS FOR NEW MODEL
-- =============================================================================

-- Update fn_persist_reflection to be legacy-compatible while new system develops
CREATE OR REPLACE FUNCTION fn_persist_reflection(
  p_basket_id uuid,
  p_pattern text,
  p_tension text, 
  p_question text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
  v_reflection_text text;
  v_substrate_hash text;
BEGIN
  -- Get workspace
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  
  -- Compose reflection text from legacy parameters
  v_reflection_text := COALESCE(
    CASE 
      WHEN p_pattern IS NOT NULL AND p_tension IS NOT NULL AND p_question IS NOT NULL 
      THEN 'Pattern: ' || p_pattern || E'\n\nTension: ' || p_tension || E'\n\nQuestion: ' || p_question
      WHEN p_pattern IS NOT NULL AND p_tension IS NOT NULL
      THEN 'Pattern: ' || p_pattern || E'\n\nTension: ' || p_tension  
      WHEN p_pattern IS NOT NULL THEN p_pattern
      WHEN p_tension IS NOT NULL THEN p_tension
      WHEN p_question IS NOT NULL THEN p_question
      ELSE 'Empty reflection'
    END,
    'Empty reflection'
  );
  
  v_substrate_hash := 'legacy_' || encode(sha256((COALESCE(p_pattern, '') || COALESCE(p_tension, '') || COALESCE(p_question, ''))::bytea), 'hex');
  
  -- Insert into new artifact table
  INSERT INTO reflections_artifact (
    basket_id,
    workspace_id,
    reflection_text,
    substrate_hash,
    reflection_target_type,
    computation_timestamp,
    computation_method,
    meta
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    v_reflection_text,
    v_substrate_hash,
    'legacy',
    now(),
    'legacy_pattern_analysis',
    jsonb_build_object('pattern', p_pattern, 'tension', p_tension, 'question', p_question)
  ) ON CONFLICT (basket_id, substrate_hash) DO UPDATE SET
    reflection_text = EXCLUDED.reflection_text,
    computation_timestamp = EXCLUDED.computation_timestamp,
    meta = EXCLUDED.meta
  RETURNING id INTO v_reflection_id;
  
  -- Emit timeline event
  PERFORM fn_timeline_emit(
    p_basket_id,
    'reflection.computed',
    v_reflection_id,
    left(v_reflection_text, 140),
    jsonb_build_object('method', 'legacy', 'target_type', 'legacy')
  );
  
  RETURN v_reflection_id;
END $$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION fn_persist_reflection(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_persist_reflection(uuid, text, text, text) TO service_role;

COMMIT;

-- =============================================================================
-- POST-MIGRATION VALIDATION
-- =============================================================================

-- Verify substrate_type enum is clean
-- SELECT 'Substrate types' as check, unnest(enum_range(NULL::substrate_type));

-- Verify no reflection substrate references exist
-- SELECT 'Reflection substrate refs (should be 0)' as check, count(*) FROM substrate_references WHERE substrate_type = 'reflection';

-- Check document versioning
-- SELECT 'Document versions' as check, count(*) FROM document_versions;

-- Verify artifact reflections
-- SELECT 'Artifact reflections' as check, reflection_target_type, count(*) FROM reflections_artifact GROUP BY reflection_target_type;