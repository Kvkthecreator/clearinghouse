-- Phase 1: Archive/Redact + Cascade Preview (Canon Deletion)

BEGIN;

-- 1) Tombstones for archived/redacted substrates (no content)
CREATE TABLE IF NOT EXISTS public.substrate_tombstones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  basket_id uuid NOT NULL,
  substrate_type text NOT NULL CHECK (substrate_type IN ('block','context_item','dump','timeline_event')),
  substrate_id uuid NOT NULL,
  deletion_mode text NOT NULL CHECK (deletion_mode IN ('archived','redacted','deleted')),
  redaction_scope text NULL CHECK (redaction_scope IN ('full','partial')),
  redaction_reason text NULL,
  legal_hold boolean DEFAULT false,
  refs_detached_count integer DEFAULT 0,
  relationships_pruned_count integer DEFAULT 0,
  affected_documents_count integer DEFAULT 0,
  retention_policy_id uuid NULL,
  earliest_physical_delete_at timestamptz NULL,
  event_ids uuid[] DEFAULT '{}',
  content_fingerprint text NULL,
  created_at timestamptz DEFAULT now(),
  created_by uuid NULL
);

CREATE INDEX IF NOT EXISTS idx_tombstones_lookup
  ON public.substrate_tombstones (workspace_id, basket_id, substrate_type, substrate_id);

-- 2) Cascade preview function (counts only)
CREATE OR REPLACE FUNCTION public.fn_cascade_preview(
  p_basket_id uuid,
  p_substrate_type text,
  p_substrate_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_refs int := 0;
  v_rels int := 0;
  v_docs int := 0;
BEGIN
  -- References in documents
  SELECT count(*) INTO v_refs
  FROM substrate_references
  WHERE document_id IN (SELECT id FROM documents WHERE basket_id = p_basket_id)
    AND substrate_type = p_substrate_type::substrate_type
    AND substrate_id = p_substrate_id;

  -- Relationships touching the node
  SELECT count(*) INTO v_rels
  FROM substrate_relationships
  WHERE basket_id = p_basket_id
    AND ((from_id = p_substrate_id AND from_type = p_substrate_type)
      OR (to_id = p_substrate_id AND to_type = p_substrate_type));

  -- Distinct documents affected
  SELECT count(DISTINCT document_id) INTO v_docs
  FROM substrate_references
  WHERE document_id IN (SELECT id FROM documents WHERE basket_id = p_basket_id)
    AND substrate_type = p_substrate_type::substrate_type
    AND substrate_id = p_substrate_id;

  RETURN jsonb_build_object(
    'refs_detached_count', v_refs,
    'relationships_pruned_count', v_rels,
    'affected_documents_count', v_docs
  );
END;
$$;

-- 3) Archive block operation (with detach + prune)
CREATE OR REPLACE FUNCTION public.fn_archive_block(
  p_basket_id uuid,
  p_block_id uuid,
  p_actor_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_workspace_id uuid;
  v_preview jsonb;
  v_event_ids uuid[] := '{}';
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

  -- Mark block archived via status (non-breaking minimal change)
  UPDATE blocks SET status = 'archived', updated_at = now()
  WHERE id = p_block_id AND basket_id = p_basket_id;

  -- Preview snapshot for tombstone counts
  SELECT fn_cascade_preview(p_basket_id, 'block', p_block_id) INTO v_preview;

  -- Tombstone (with earliest_physical_delete_at if retention policy enabled)
  DECLARE v_flags jsonb := public.get_workspace_governance_flags(v_workspace_id); BEGIN END; -- dummy
  -- Fetch flags properly
  SELECT public.get_workspace_governance_flags(v_workspace_id) INTO v_preview; -- reuse v_preview var
  -- v_preview holds flags now; avoid extra local var creation for brevity

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

  -- Set earliest_physical_delete_at from retention policy if enabled and policy provides days
  BEGIN
    IF COALESCE((v_preview->>'retention_enabled')::boolean, false) THEN
      -- Expect policy like { block: { days: N|null } }
      IF ((v_preview->'retention_policy'->'block'->>'days') IS NOT NULL) THEN
        UPDATE substrate_tombstones
          SET earliest_physical_delete_at = now() + ((v_preview->'retention_policy'->'block'->>'days')::int || ' days')::interval
          WHERE id = v_tomb_id;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- ignore policy parsing errors
  END;

  -- Emit event
  PERFORM emit_timeline_event(p_basket_id, 'substrate.archived', jsonb_build_object(
    'substrate_type','block','substrate_id',p_block_id,'tombstone_id',v_tomb_id
  ), v_workspace_id, p_actor_id, 'p1_maintenance');

  RETURN v_tomb_id;
END;
$$;

-- 4) Redact dump operation (privacy fast-path)
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

  -- Redact content (do not drop row)
  UPDATE raw_dumps
    SET body_md = NULL, text_dump = NULL, file_url = NULL, processing_status = 'redacted'
  WHERE id = p_dump_id AND basket_id = p_basket_id;

  -- Preview snapshot for tombstone counts (post‑detach not required for dumps by default)
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

  -- Set earliest_physical_delete_at from retention policy if enabled and policy provides days
  BEGIN
    IF COALESCE((public.get_workspace_governance_flags(v_workspace_id)->>'retention_enabled')::boolean, false) THEN
      IF ((public.get_workspace_governance_flags(v_workspace_id)->'retention_policy'->'dump'->>'days') IS NOT NULL) THEN
        UPDATE substrate_tombstones
          SET earliest_physical_delete_at = now() + ((public.get_workspace_governance_flags(v_workspace_id)->'retention_policy'->'dump'->>'days')::int || ' days')::interval
          WHERE id = v_tomb_id;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
  END;

  PERFORM emit_timeline_event(p_basket_id, 'substrate.redacted', jsonb_build_object(
    'substrate_type','dump','substrate_id',p_dump_id,'scope',p_scope,'tombstone_id',v_tomb_id
  ), v_workspace_id, p_actor_id, 'p1_maintenance');

  RETURN v_tomb_id;
END;
$$;

COMMIT;
