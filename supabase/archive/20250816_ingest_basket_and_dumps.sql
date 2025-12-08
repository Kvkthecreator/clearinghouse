-- Unique indexes for idempotency
CREATE UNIQUE INDEX IF NOT EXISTS ux_baskets_ws_idempo
ON public.baskets (workspace_id, idempotency_key)
WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_raw_dumps_ws_dumpreq
ON public.raw_dumps (workspace_id, dump_request_id)
WHERE dump_request_id IS NOT NULL;

-- Function to atomically ingest basket and dumps
CREATE OR REPLACE FUNCTION public.ingest_basket_and_dumps(
  p_workspace_id uuid,
  p_idempotency_key text,
  p_basket_name text,
  p_dumps jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_basket_id uuid;
  v_basket_created boolean := false;
  v_dump jsonb;
  v_dump_id uuid;
  v_dump_created boolean;
  v_out jsonb := jsonb_build_object();
  v_dump_results jsonb := '[]'::jsonb;
BEGIN
  -- basket (create or replay)
  INSERT INTO public.baskets (workspace_id, idempotency_key, name)
  VALUES (p_workspace_id, p_idempotency_key, p_basket_name)
  ON CONFLICT (workspace_id, idempotency_key) DO UPDATE
    SET name = COALESCE(EXCLUDED.name, public.baskets.name)
  RETURNING id, (xmax = 0) INTO v_basket_id, v_basket_created;

  -- dumps
  FOR v_dump IN SELECT * FROM jsonb_array_elements(p_dumps)
  LOOP
    INSERT INTO public.raw_dumps (workspace_id, dump_request_id, text_dump, file_urls)
    VALUES (
      p_workspace_id,
      (v_dump->>'dump_request_id'),
      (v_dump->>'text_dump'),
      COALESCE((v_dump->'file_urls')::text[], '{}')
    )
    ON CONFLICT (workspace_id, dump_request_id) DO UPDATE
      SET text_dump = COALESCE(EXCLUDED.text_dump, public.raw_dumps.text_dump)
    RETURNING id, (xmax = 0) INTO v_dump_id, v_dump_created;

    v_dump_results := v_dump_results || jsonb_build_object(
      'dump_id', v_dump_id
    );
  END LOOP;

  v_out := jsonb_build_object(
    'basket_id', v_basket_id,
    'dumps', v_dump_results
  );
  RETURN v_out;
END $$;

-- Allow authenticated users to invoke
GRANT EXECUTE ON FUNCTION public.ingest_basket_and_dumps(uuid, text, text, jsonb) TO authenticated;
