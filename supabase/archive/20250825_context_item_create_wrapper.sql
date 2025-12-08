CREATE OR REPLACE FUNCTION public.fn_context_item_create(
  p_basket_id uuid,
  p_type text,
  p_content text,
  p_title text,
  p_description text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_ids uuid[];
BEGIN
  RAISE NOTICE 'deprecated';
  SELECT array_agg(id) INTO v_ids FROM public.fn_context_item_upsert_bulk(
    jsonb_build_array(
      jsonb_build_object(
        'basket_id', p_basket_id,
        'type', p_type,
        'content', p_content,
        'title', p_title,
        'description', p_description
      )
    ),
    NULL
  );
  RETURN v_ids[1];
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_context_item_create(uuid, text, text, text, text) TO authenticated;
