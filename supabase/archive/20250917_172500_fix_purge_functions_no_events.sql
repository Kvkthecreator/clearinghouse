-- Override archive/redact functions to avoid timeline kind constraint mismatch
-- Removes event emission to satisfy timeline_events_kind_check in this environment

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_archive_block(
  p_basket_id uuid,
  p_block_id uuid,
  p_actor_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_workspace_id uuid;
  v_preview jsonb;
  v_tomb_id uuid;
BEGIN
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;

  -- Detach references
  DELETE FROM substrate_references
  USING documents d
  WHERE substrate_references.document_id = d.id
    AND d.basket_id = p_basket_id
    AND substrate_references.substrate_type = 'block'
    AND substrate_references.substrate_id = p_block_id;

  -- Prune relationships
  DELETE FROM substrate_relationships
  WHERE basket_id = p_basket_id
    AND ((from_id = p_block_id AND from_type = 'block') OR (to_id = p_block_id AND to_type = 'block'));

  -- Mark block archived via status
  UPDATE blocks SET status = 'archived', updated_at = now()
  WHERE id = p_block_id AND basket_id = p_basket_id;

  -- Preview snapshot for tombstone counts
  SELECT fn_cascade_preview(p_basket_id, 'block', p_block_id) INTO v_preview;

  INSERT INTO substrate_tombstones (
    workspace_id, basket_id, substrate_type, substrate_id,
    deletion_mode, redaction_scope, redaction_reason,
    refs_detached_count, relationships_pruned_count, affected_documents_count,
    created_by
  ) VALUES (
    v_workspace_id, p_basket_id, 'block', p_block_id,
    'archived', NULL, NULL,
    COALESCE((v_preview->>'refs_detached_count')::int, 0),
    COALESCE((v_preview->>'relationships_pruned_count')::int, 0),
    COALESCE((v_preview->>'affected_documents_count')::int, 0),
    p_actor_id
  ) RETURNING id INTO v_tomb_id;

  -- No timeline event emission to avoid kind constraint mismatch

  RETURN v_tomb_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_redact_dump(
  p_basket_id uuid,
  p_dump_id uuid,
  p_scope text DEFAULT 'full',
  p_reason text DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_workspace_id uuid;
  v_preview jsonb;
  v_tomb_id uuid;
BEGIN
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;

  -- Redact content
  UPDATE raw_dumps
    SET body_md = NULL, text_dump = NULL, file_url = NULL, processing_status = 'redacted'
  WHERE id = p_dump_id AND basket_id = p_basket_id;

  -- Preview snapshot for tombstone counts
  SELECT fn_cascade_preview(p_basket_id, 'dump', p_dump_id) INTO v_preview;

  INSERT INTO substrate_tombstones (
    workspace_id, basket_id, substrate_type, substrate_id,
    deletion_mode, redaction_scope, redaction_reason,
    refs_detached_count, relationships_pruned_count, affected_documents_count,
    created_by
  ) VALUES (
    v_workspace_id, p_basket_id, 'dump', p_dump_id,
    'redacted', p_scope, p_reason,
    COALESCE((v_preview->>'refs_detached_count')::int, 0),
    COALESCE((v_preview->>'relationships_pruned_count')::int, 0),
    COALESCE((v_preview->>'affected_documents_count')::int, 0),
    p_actor_id
  ) RETURNING id INTO v_tomb_id;

  -- No timeline event emission to avoid kind constraint mismatch

  RETURN v_tomb_id;
END;
$$;

COMMIT;

