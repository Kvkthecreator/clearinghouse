-- 1) Ensure EXECUTE grants on existing RPCs (idempotent)
GRANT EXECUTE ON FUNCTION public.fn_persist_reflection(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_document_create(uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_block_create(uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_context_item_create(uuid, text, text, text, text) TO authenticated;

-- 2) New RPC: block revision + timeline emission
CREATE OR REPLACE FUNCTION public.fn_block_revision_create(
  p_basket_id uuid,
  p_block_id uuid,
  p_workspace_id uuid,
  p_summary text,
  p_diff_json jsonb
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE v_rev_id uuid;
BEGIN
  INSERT INTO public.block_revisions (block_id, workspace_id, summary, diff_json)
  VALUES (p_block_id, p_workspace_id, p_summary, p_diff_json)
  RETURNING id INTO v_rev_id;

  PERFORM public.fn_timeline_emit(
    p_basket_id,
    'block_revision',
    v_rev_id,
    LEFT(COALESCE(p_summary,''), 140),
    jsonb_build_object('source','block_revision','actor_id', auth.uid(), 'block_id', p_block_id)
  );

  RETURN v_rev_id;
END; $$;

GRANT EXECUTE ON FUNCTION public.fn_block_revision_create(uuid, uuid, uuid, text, jsonb) TO authenticated;

-- 3) Optional but recommended index for hot path reads
CREATE INDEX IF NOT EXISTS idx_block_revisions_basket_ts
  ON public.block_revisions (workspace_id, created_at DESC);

-- 4) RPC: substrate_relationships upsert (+ timeline)
-- If you ALREADY have a unique key for relationships, keep it; else create one to support UPSERT.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_relationship_identity'
  ) THEN
    CREATE UNIQUE INDEX uq_relationship_identity
      ON public.substrate_relationships (basket_id, from_type, from_id, to_type, to_id, relationship_type);
  END IF;
END$$;

CREATE OR REPLACE FUNCTION public.fn_relationship_upsert(
  p_basket_id uuid,
  p_from_type text,
  p_from_id uuid,
  p_to_type text,
  p_to_id uuid,
  p_relationship_type text,
  p_description text DEFAULT NULL,
  p_strength double precision DEFAULT 0.5
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.substrate_relationships (basket_id, from_type, from_id, to_type, to_id, relationship_type, description, strength)
  VALUES (p_basket_id, p_from_type, p_from_id, p_to_type, p_to_id, p_relationship_type, p_description, p_strength)
  ON CONFLICT (basket_id, from_type, from_id, to_type, to_id, relationship_type)
  DO UPDATE SET description = EXCLUDED.description, strength = EXCLUDED.strength
  RETURNING id INTO v_id;

  PERFORM public.fn_timeline_emit(
    p_basket_id,
    'relationship',
    v_id,
    LEFT(p_relationship_type || ' ' || COALESCE(p_from_type,'') || '→' || COALESCE(p_to_type,''), 140),
    jsonb_build_object('source','relationship_upsert','from_id', p_from_id, 'to_id', p_to_id, 'relationship_type', p_relationship_type, 'actor_id', auth.uid())
  );

  RETURN v_id;
END; $$;

GRANT EXECUTE ON FUNCTION public.fn_relationship_upsert(uuid, text, uuid, text, uuid, text, text, double precision) TO authenticated;
