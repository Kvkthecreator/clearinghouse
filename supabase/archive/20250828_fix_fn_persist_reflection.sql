-- Fix fn_persist_reflection function to insert into actual table not view
-- The function was trying to INSERT into basket_reflections (view) which caused
-- permission denied errors. Views don't support INSERT unless they have INSTEAD OF triggers.

CREATE OR REPLACE FUNCTION public.fn_persist_reflection(
  p_basket_id uuid,
  p_pattern text,
  p_tension text,
  p_question text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE 
  v_id uuid;
  v_workspace_id uuid;
BEGIN
  -- Get workspace_id from basket
  SELECT workspace_id INTO v_workspace_id FROM public.baskets WHERE id = p_basket_id;
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Basket % not found', p_basket_id;
  END IF;

  -- Insert into actual table, not the view
  INSERT INTO public.reflection_cache (basket_id, pattern, tension, question, workspace_id)
  VALUES (p_basket_id, p_pattern, p_tension, p_question, v_workspace_id)
  RETURNING id INTO v_id;

  PERFORM public.fn_timeline_emit(
    p_basket_id,
    'reflection',
    v_id,
    LEFT(COALESCE(p_pattern, p_question, ''), 140),
    jsonb_build_object('source','reflection_job','actor_id', auth.uid())
  );

  RETURN v_id;
END $$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.fn_persist_reflection(uuid, text, text, text) TO authenticated;