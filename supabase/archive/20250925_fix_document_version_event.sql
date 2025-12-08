-- Fix timeline event kind for document versioning to align with canon timeline enum
-- and avoid timeline_events_kind_check violations.
-- Also fetch basket/workspace once to reuse values.

CREATE OR REPLACE FUNCTION public.fn_document_create_version(
  p_document_id uuid,
  p_content text,
  p_version_message text DEFAULT NULL::text
) RETURNS character varying
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_version_hash varchar(64);
  v_workspace_id uuid;
  v_basket_id uuid;
BEGIN
  -- Generate version hash (git-inspired deterministic key)
  v_version_hash := 'doc_v' || substr(encode(sha256(p_content::bytea), 'hex'), 1, 58);

  -- Load document context
  SELECT workspace_id, basket_id
    INTO v_workspace_id, v_basket_id
  FROM documents
  WHERE id = p_document_id;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Document % not found', p_document_id;
  END IF;

  -- Insert version snapshot (idempotent by hash)
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
      (
        SELECT jsonb_agg(to_jsonb(sr.*))
        FROM substrate_references sr
        WHERE sr.document_id = p_document_id
      ),
      '[]'::jsonb
    ),
    auth.uid(),
    p_version_message,
    d.current_version_hash
  FROM documents d
  WHERE d.id = p_document_id
  ON CONFLICT (version_hash) DO NOTHING;

  -- Update document pointer
  UPDATE documents
  SET current_version_hash = v_version_hash,
      updated_at = now()
  WHERE id = p_document_id;

  -- Emit timeline event using allowed kind
  PERFORM fn_timeline_emit(
    v_basket_id,
    'document.updated',
    p_document_id,
    'Document version created: ' || left(v_version_hash, 12),
    jsonb_build_object('version_hash', v_version_hash, 'message', p_version_message)
  );

  RETURN v_version_hash;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_document_create_version(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_document_create_version(uuid, text, text) TO service_role;
