-- Unify P3 reflection creation RPC to canon signature and keep legacy shim
-- Canon signature:
--   fn_reflection_create_from_substrate(p_basket_id uuid,
--                                      p_substrate_ids uuid[],
--                                      p_reflection_text text,
--                                      p_computation_method varchar(50) DEFAULT 'ai_analysis')

BEGIN;

-- Ensure required columns exist on reflections_artifact
ALTER TABLE IF EXISTS public.reflections_artifact
  ADD COLUMN IF NOT EXISTS computation_method varchar(50),
  ADD COLUMN IF NOT EXISTS substrate_analysis_ids uuid[];

-- Create or replace the canon function
CREATE OR REPLACE FUNCTION public.fn_reflection_create_from_substrate(
  p_basket_id uuid,
  p_substrate_ids uuid[],
  p_reflection_text text,
  p_computation_method varchar(50) DEFAULT 'ai_analysis'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reflection_id uuid;
  v_workspace_id uuid;
  v_substrate_hash text;
BEGIN
  -- Resolve workspace
  SELECT workspace_id INTO v_workspace_id FROM baskets WHERE id = p_basket_id;
  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Basket % not found', p_basket_id;
  END IF;

  -- Stable hash for idempotency (empty array falls back to basket hash)
  v_substrate_hash := CASE WHEN coalesce(array_length(p_substrate_ids, 1), 0) > 0 THEN
      'substrate_' || encode(sha256(array_to_string(p_substrate_ids, ',')::bytea), 'hex')
    ELSE
      'substrate_' || encode(sha256(p_basket_id::text::bytea), 'hex')
  END;

  -- Insert or reuse existing artifact
  INSERT INTO reflections_artifact (
    basket_id,
    workspace_id,
    reflection_text,
    reflection_target_type,
    substrate_analysis_ids,
    computation_method,
    computation_timestamp,
    substrate_hash
  ) VALUES (
    p_basket_id,
    v_workspace_id,
    p_reflection_text,
    'substrate',
    coalesce(p_substrate_ids, ARRAY[]::uuid[]),
    p_computation_method,
    now(),
    v_substrate_hash
  ) ON CONFLICT (basket_id, substrate_hash)
  DO UPDATE SET
    reflection_text = EXCLUDED.reflection_text,
    computation_timestamp = EXCLUDED.computation_timestamp,
    computation_method = EXCLUDED.computation_method
  RETURNING id INTO v_reflection_id;

  RETURN v_reflection_id;
END;
$$;

-- Legacy shim (two-arg) for compatibility
CREATE OR REPLACE FUNCTION public.fn_reflection_create_from_substrate(
  p_basket_id uuid,
  p_reflection_text text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT public.fn_reflection_create_from_substrate(
    p_basket_id,
    ARRAY[]::uuid[],
    p_reflection_text,
    'legacy'
  ) INTO v_id;
  RETURN v_id;
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.fn_reflection_create_from_substrate(uuid, uuid[], text, varchar) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_reflection_create_from_substrate(uuid, text) TO service_role;

COMMIT;

