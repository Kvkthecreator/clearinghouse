-- Fix fn_persist_reflection to work with canonical reflection_cache schema
-- The function currently expects pattern, tension, question columns that were removed
-- Update to use reflection_text and canonical schema

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
  v_reflection_text text;
  v_substrate_hash text;
BEGIN
  -- Get workspace_id from basket
  SELECT workspace_id INTO v_workspace_id FROM public.baskets WHERE id = p_basket_id;
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Basket % not found', p_basket_id;
  END IF;

  -- Compose reflection_text from pattern, tension, question
  v_reflection_text := COALESCE(
    CASE 
      WHEN p_pattern IS NOT NULL AND p_tension IS NOT NULL AND p_question IS NOT NULL 
      THEN 'Pattern: ' || p_pattern || E'\n\nTension: ' || p_tension || E'\n\nQuestion: ' || p_question
      WHEN p_pattern IS NOT NULL AND p_tension IS NOT NULL
      THEN 'Pattern: ' || p_pattern || E'\n\nTension: ' || p_tension
      WHEN p_pattern IS NOT NULL
      THEN p_pattern
      WHEN p_tension IS NOT NULL  
      THEN p_tension
      WHEN p_question IS NOT NULL
      THEN p_question
      ELSE 'Empty reflection'
    END, 
    'Empty reflection'
  );

  -- Generate substrate hash from inputs
  v_substrate_hash := 'reflection-' || encode(sha256((COALESCE(p_pattern, '') || COALESCE(p_tension, '') || COALESCE(p_question, ''))::bytea), 'hex');

  -- Insert into canonical schema
  INSERT INTO public.reflection_cache (
    basket_id, 
    workspace_id,
    substrate_hash,
    reflection_text,
    substrate_window_start,
    substrate_window_end,
    computation_timestamp,
    last_accessed_at,
    meta,
    created_at,
    updated_at
  )
  VALUES (
    p_basket_id, 
    v_workspace_id,
    v_substrate_hash,
    v_reflection_text,
    NOW(),
    NOW(),
    NOW(),
    NOW(),
    jsonb_build_object('legacy_migration', true, 'pattern', p_pattern, 'tension', p_tension, 'question', p_question),
    NOW(),
    NOW()
  )
  ON CONFLICT (basket_id, substrate_hash) DO UPDATE SET
    reflection_text = EXCLUDED.reflection_text,
    computation_timestamp = EXCLUDED.computation_timestamp,
    last_accessed_at = NOW(),
    updated_at = NOW(),
    meta = EXCLUDED.meta
  RETURNING id INTO v_id;

  -- Emit timeline event
  PERFORM public.fn_timeline_emit(
    p_basket_id,
    'reflection',
    v_id,
    LEFT(v_reflection_text, 140),
    jsonb_build_object('source','reflection_job','actor_id', auth.uid())
  );

  RETURN v_id;
END $$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.fn_persist_reflection(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_persist_reflection(uuid, text, text, text) TO service_role;