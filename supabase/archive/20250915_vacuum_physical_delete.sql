-- Phase 2: Vacuum routine for physical delete under retention policy

BEGIN;

-- Optional: track physical deletion timestamp
ALTER TABLE public.substrate_tombstones
  ADD COLUMN IF NOT EXISTS physically_deleted_at timestamptz NULL;

CREATE OR REPLACE FUNCTION public.fn_vacuum_substrates(
  p_workspace_id uuid,
  p_limit int DEFAULT 50
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_deleted_blocks int := 0;
  v_deleted_dumps int := 0;
  v_deleted_items int := 0;
  v_row record;
  v_settings jsonb;
  v_retention_enabled boolean := false;
BEGIN
  -- Check retention policy flag
  SELECT public.get_workspace_governance_flags(p_workspace_id) INTO v_settings;
  v_retention_enabled := COALESCE((v_settings->>'retention_enabled')::boolean, false);

  IF NOT v_retention_enabled THEN
    RETURN jsonb_build_object('deleted_blocks',0,'deleted_dumps',0,'deleted_context_items',0,'note','retention disabled');
  END IF;

  FOR v_row IN
    SELECT * FROM public.substrate_tombstones
    WHERE workspace_id = p_workspace_id
      AND deletion_mode IN ('archived','redacted','deleted')
      AND earliest_physical_delete_at IS NOT NULL
      AND now() >= earliest_physical_delete_at
      AND physically_deleted_at IS NULL
    LIMIT p_limit
  LOOP
    -- Ensure no remaining hard references
    IF EXISTS (
      SELECT 1 FROM public.substrate_references sr
      JOIN public.documents d ON d.id = sr.document_id
      WHERE d.workspace_id = p_workspace_id
        AND sr.substrate_type = v_row.substrate_type::substrate_type
        AND sr.substrate_id = v_row.substrate_id
    ) THEN
      CONTINUE;
    END IF;

    -- Ensure no remaining relationships (for block/context_item)
    IF v_row.substrate_type IN ('block','context_item') THEN
      IF EXISTS (
        SELECT 1 FROM public.substrate_relationships
        WHERE basket_id = v_row.basket_id
          AND ((from_id = v_row.substrate_id AND from_type = v_row.substrate_type)
            OR (to_id = v_row.substrate_id AND to_type = v_row.substrate_type))
      ) THEN
        CONTINUE;
      END IF;
    END IF;

    -- Perform physical deletion per substrate type
    IF v_row.substrate_type = 'block' THEN
      DELETE FROM public.blocks WHERE id = v_row.substrate_id AND workspace_id = p_workspace_id;
      v_deleted_blocks := v_deleted_blocks + 1;
    ELSIF v_row.substrate_type = 'dump' THEN
      DELETE FROM public.raw_dumps WHERE id = v_row.substrate_id AND workspace_id = p_workspace_id;
      v_deleted_dumps := v_deleted_dumps + 1;
    ELSIF v_row.substrate_type = 'context_item' THEN
      DELETE FROM public.context_items WHERE id = v_row.substrate_id AND basket_id = v_row.basket_id;
      v_deleted_items := v_deleted_items + 1;
    ELSE
      CONTINUE;
    END IF;

    -- Mark tombstone as physically deleted and emit event
    UPDATE public.substrate_tombstones
      SET deletion_mode = 'deleted', physically_deleted_at = now()
      WHERE id = v_row.id;

    PERFORM emit_timeline_event(v_row.basket_id, 'substrate.physically_deleted', jsonb_build_object(
      'substrate_type', v_row.substrate_type,
      'substrate_id', v_row.substrate_id,
      'tombstone_id', v_row.id
    ), p_workspace_id, NULL, 'vacuum');
  END LOOP;

  RETURN jsonb_build_object(
    'deleted_blocks', v_deleted_blocks,
    'deleted_dumps', v_deleted_dumps,
    'deleted_context_items', v_deleted_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_vacuum_substrates(uuid, int) TO service_role;

COMMIT;

