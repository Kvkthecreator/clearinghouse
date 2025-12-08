-- Canon fix: ensure context item archival updates state field and backfill existing records
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_archive_context_item(
  p_basket_id uuid,
  p_context_item_id uuid,
  p_actor_id uuid DEFAULT NULL::uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_workspace_id uuid;
  v_preview jsonb;
  v_event_ids uuid[] := '{}';
  v_tomb_id uuid;
  v_refs_count int := 0;
  v_rels_count int := 0;
  v_docs_count int := 0;
BEGIN
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Basket % not found', p_basket_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM context_items
    WHERE id = p_context_item_id AND basket_id = p_basket_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Context item % not found in basket % or already archived', p_context_item_id, p_basket_id;
  END IF;

  SELECT fn_cascade_preview(p_basket_id, 'context_item', p_context_item_id) INTO v_preview;
  v_refs_count := COALESCE((v_preview->'substrate_references_detached')::int, 0);
  v_rels_count := COALESCE((v_preview->'relationships_pruned')::int, 0);
  v_docs_count := COALESCE((v_preview->'affected_documents')::int, 0);

  UPDATE context_items
    SET status = 'archived',
        state = 'DEPRECATED'::context_item_state,
        updated_at = now()
    WHERE id = p_context_item_id AND basket_id = p_basket_id;

  DELETE FROM substrate_references
    WHERE substrate_id = p_context_item_id AND substrate_type = 'context_item';

  DELETE FROM substrate_relationships
    WHERE (from_id = p_context_item_id AND from_type = 'context_item')
       OR (to_id = p_context_item_id AND to_type = 'context_item');

  INSERT INTO substrate_tombstones (
    workspace_id, basket_id, substrate_type, substrate_id,
    deletion_mode, redaction_scope, redaction_reason,
    refs_detached_count, relationships_pruned_count, affected_documents_count,
    created_by
  ) VALUES (
    v_workspace_id, p_basket_id, 'context_item', p_context_item_id,
    'archived', NULL, 'user_archive',
    v_refs_count, v_rels_count, v_docs_count,
    p_actor_id
  ) RETURNING id INTO v_tomb_id;

  BEGIN
    DECLARE
      v_flags jsonb;
      v_retention_days text;
    BEGIN
      SELECT public.get_workspace_governance_flags(v_workspace_id) INTO v_flags;
      IF COALESCE((v_flags->>'retention_enabled')::boolean, false) THEN
        v_retention_days := v_flags->'retention_policy'->'context_item'->>'days';
        IF v_retention_days IS NOT NULL THEN
          UPDATE substrate_tombstones
            SET earliest_physical_delete_at = now() + (v_retention_days::int || ' days')::interval
            WHERE id = v_tomb_id;
        END IF;
      END IF;
    END;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  PERFORM emit_timeline_event(
    p_basket_id,
    'context_item.archived',
    jsonb_build_object(
      'context_item_id', p_context_item_id,
      'tomb_id', v_tomb_id,
      'refs_detached', v_refs_count,
      'relationships_pruned', v_rels_count,
      'affected_documents', v_docs_count
    ),
    v_workspace_id,
    p_actor_id
  );
  RETURN v_tomb_id;
END;
$$;

UPDATE context_items
SET state = 'DEPRECATED'::context_item_state
WHERE status = 'archived' AND state <> 'DEPRECATED'::context_item_state;

COMMIT;
