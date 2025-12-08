-- Promote Work Output to Context Block
-- Date: 2025-12-02
-- Canon Reference: /docs/canon/CONTEXT_ROLES_ARCHITECTURE.md
--
-- This function promotes a work_output to a block with an anchor_role,
-- creating the block and linking it back to the output.

BEGIN;

-- =====================================================
-- Function: promote_output_to_context_block
-- =====================================================

CREATE OR REPLACE FUNCTION promote_output_to_context_block(
  p_output_id UUID,
  p_promoted_by UUID DEFAULT NULL,
  p_override_role TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_output RECORD;
  v_recipe RECORD;
  v_new_block_id UUID;
  v_target_role TEXT;
  v_refresh_policy JSONB;
BEGIN
  -- 1. Fetch the work output
  SELECT wo.*, wt.recipe_slug
  INTO v_output
  FROM work_outputs wo
  LEFT JOIN work_tickets wt ON wo.work_ticket_id = wt.id
  WHERE wo.id = p_output_id;

  IF v_output IS NULL THEN
    RAISE EXCEPTION 'Work output not found: %', p_output_id;
  END IF;

  IF v_output.promotion_status = 'promoted' THEN
    RAISE EXCEPTION 'Output already promoted: %', p_output_id;
  END IF;

  -- 2. Determine target role (override > output > recipe)
  v_target_role := COALESCE(
    p_override_role,
    v_output.target_context_role
  );

  -- If no role specified, try to get from recipe
  IF v_target_role IS NULL AND v_output.recipe_slug IS NOT NULL THEN
    SELECT context_outputs->>'role'
    INTO v_target_role
    FROM work_recipes
    WHERE slug = v_output.recipe_slug;
  END IF;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'No target context role specified for output: %', p_output_id;
  END IF;

  -- 3. Get refresh policy from recipe if available
  IF v_output.recipe_slug IS NOT NULL THEN
    SELECT context_outputs->'refresh_policy'
    INTO v_refresh_policy
    FROM work_recipes
    WHERE slug = v_output.recipe_slug;
  END IF;

  -- 4. Create the block
  INSERT INTO blocks (
    id,
    basket_id,
    workspace_id,
    title,
    body_md,
    content,
    semantic_type,
    anchor_role,
    anchor_status,
    anchor_confidence,
    refresh_policy,
    state,
    scope,
    status,
    confidence_score,
    metadata,
    processing_agent,
    approved_at,
    approved_by,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    v_output.basket_id,
    b.workspace_id,
    v_output.title,
    v_output.body,
    v_output.body,  -- content = body for context blocks
    'context_' || v_target_role,  -- semantic_type derived from role
    v_target_role,
    'approved',  -- anchor_status - promoted outputs are approved
    COALESCE(v_output.confidence, 0.8),  -- anchor_confidence
    v_refresh_policy,
    'active',  -- state
    'primary',  -- scope
    'approved',  -- status
    v_output.confidence,
    jsonb_build_object(
      'promoted_from_output_id', v_output.id,
      'promoted_at', now(),
      'source_agent', v_output.agent_type
    ) || COALESCE(v_output.metadata, '{}'::jsonb),
    v_output.agent_type,
    now(),
    p_promoted_by
  FROM baskets b
  WHERE b.id = v_output.basket_id
  RETURNING id INTO v_new_block_id;

  -- 5. Update the work output to mark as promoted
  UPDATE work_outputs
  SET
    promotion_status = 'promoted',
    promoted_to_block_id = v_new_block_id,
    promoted_at = now(),
    promoted_by = p_promoted_by,
    promotion_method = CASE
      WHEN p_promoted_by IS NOT NULL THEN 'manual'
      ELSE 'auto'
    END,
    updated_at = now()
  WHERE id = p_output_id;

  -- 6. Archive any existing block with the same anchor_role in this basket
  -- (only one active block per role per basket)
  UPDATE blocks
  SET
    state = 'archived',
    anchor_status = 'superseded',
    updated_at = now()
  WHERE basket_id = v_output.basket_id
    AND anchor_role = v_target_role
    AND id != v_new_block_id
    AND state = 'active';

  RETURN v_new_block_id;
END;
$$;

COMMENT ON FUNCTION promote_output_to_context_block IS
'Promotes a work_output to a block with anchor_role for context roles system.
Archives any existing block with the same role in the basket.
Returns the new block ID.';

-- =====================================================
-- Function: check_output_promotable
-- =====================================================

CREATE OR REPLACE FUNCTION check_output_promotable(p_output_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_output RECORD;
  v_target_role TEXT;
  v_result JSONB;
BEGIN
  SELECT wo.*, wt.recipe_slug
  INTO v_output
  FROM work_outputs wo
  LEFT JOIN work_tickets wt ON wo.work_ticket_id = wt.id
  WHERE wo.id = p_output_id;

  IF v_output IS NULL THEN
    RETURN jsonb_build_object(
      'promotable', false,
      'reason', 'Output not found'
    );
  END IF;

  IF v_output.promotion_status = 'promoted' THEN
    RETURN jsonb_build_object(
      'promotable', false,
      'reason', 'Already promoted',
      'promoted_to_block_id', v_output.promoted_to_block_id
    );
  END IF;

  -- Check for target role
  v_target_role := v_output.target_context_role;
  IF v_target_role IS NULL AND v_output.recipe_slug IS NOT NULL THEN
    SELECT context_outputs->>'role'
    INTO v_target_role
    FROM work_recipes
    WHERE slug = v_output.recipe_slug;
  END IF;

  IF v_target_role IS NULL THEN
    RETURN jsonb_build_object(
      'promotable', false,
      'reason', 'No target context role defined'
    );
  END IF;

  -- Check supervision status
  IF v_output.supervision_status NOT IN ('approved', 'auto_approved') THEN
    RETURN jsonb_build_object(
      'promotable', true,
      'requires_approval', true,
      'target_role', v_target_role,
      'supervision_status', v_output.supervision_status
    );
  END IF;

  RETURN jsonb_build_object(
    'promotable', true,
    'requires_approval', false,
    'target_role', v_target_role,
    'auto_promote', COALESCE(v_output.auto_promote, false)
  );
END;
$$;

COMMENT ON FUNCTION check_output_promotable IS
'Checks if a work_output can be promoted to a context block.
Returns promotability status and any requirements.';

COMMIT;
