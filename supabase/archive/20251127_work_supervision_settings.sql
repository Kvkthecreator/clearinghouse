-- Migration: Work Supervision Settings
-- Purpose: Add promotion mode settings to projects and link work_outputs to proposals
-- Date: 2025-11-27
-- Context: Work output promotion to substrate via P1 proposals

-- ============================================================================
-- PROJECT SETTINGS: Add work_supervision_settings to metadata
-- ============================================================================

-- Add settings column directly to projects table for explicit schema
-- (metadata.work_supervision already works, but explicit is better)
COMMENT ON COLUMN projects.metadata IS 'Project metadata including work_supervision settings:
{
  "work_supervision": {
    "promotion_mode": "auto" | "manual",  -- default: auto
    "auto_promote_types": ["finding", "recommendation"],  -- types to auto-promote
    "require_review_before_promotion": false,  -- if true, waits for explicit approval
    "notify_on_promotion": true  -- send notifications
  }
}';

-- ============================================================================
-- WORK_OUTPUTS: Add promotion tracking columns (if not exists)
-- ============================================================================

-- These columns may already exist from 20251117, but ensure they're present
DO $$
BEGIN
  -- Add promoted_to_block_id if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'promoted_to_block_id'
  ) THEN
    ALTER TABLE work_outputs ADD COLUMN promoted_to_block_id uuid REFERENCES blocks(id);
  END IF;

  -- Add promotion_method if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'promotion_method'
  ) THEN
    ALTER TABLE work_outputs ADD COLUMN promotion_method text CHECK (
      promotion_method IN ('auto', 'manual', 'skipped', 'rejected')
    );
  END IF;

  -- Add promoted_at if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'promoted_at'
  ) THEN
    ALTER TABLE work_outputs ADD COLUMN promoted_at timestamptz;
  END IF;

  -- Add promoted_by if missing (user who triggered promotion)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_outputs' AND column_name = 'promoted_by'
  ) THEN
    ALTER TABLE work_outputs ADD COLUMN promoted_by uuid REFERENCES auth.users(id);
  END IF;
END $$;

-- Index for finding outputs pending promotion
CREATE INDEX IF NOT EXISTS idx_work_outputs_pending_promotion
  ON work_outputs(basket_id, supervision_status)
  WHERE supervision_status = 'approved' AND substrate_proposal_id IS NULL;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get project work supervision settings
CREATE OR REPLACE FUNCTION get_project_supervision_settings(p_project_id uuid)
RETURNS jsonb AS $$
DECLARE
  settings jsonb;
BEGIN
  SELECT
    COALESCE(
      metadata->'work_supervision',
      '{"promotion_mode": "auto", "auto_promote_types": ["finding", "recommendation"], "require_review_before_promotion": false}'::jsonb
    )
  INTO settings
  FROM projects
  WHERE id = p_project_id;

  RETURN settings;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get project supervision settings by basket_id
CREATE OR REPLACE FUNCTION get_basket_supervision_settings(p_basket_id uuid)
RETURNS jsonb AS $$
DECLARE
  settings jsonb;
BEGIN
  SELECT
    COALESCE(
      p.metadata->'work_supervision',
      '{"promotion_mode": "auto", "auto_promote_types": ["finding", "recommendation"], "require_review_before_promotion": false}'::jsonb
    )
  INTO settings
  FROM projects p
  WHERE p.basket_id = p_basket_id
  LIMIT 1;

  -- Default if no project found
  IF settings IS NULL THEN
    settings := '{"promotion_mode": "auto", "auto_promote_types": ["finding", "recommendation"], "require_review_before_promotion": false}'::jsonb;
  END IF;

  RETURN settings;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update project supervision settings
CREATE OR REPLACE FUNCTION update_project_supervision_settings(
  p_project_id uuid,
  p_settings jsonb
)
RETURNS void AS $$
BEGIN
  UPDATE projects
  SET metadata = jsonb_set(
    COALESCE(metadata, '{}'::jsonb),
    '{work_supervision}',
    p_settings
  ),
  updated_at = now()
  WHERE id = p_project_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mark work output as promoted
CREATE OR REPLACE FUNCTION mark_work_output_promoted(
  p_output_id uuid,
  p_proposal_id uuid,
  p_block_id uuid,
  p_method text,
  p_user_id uuid
)
RETURNS void AS $$
BEGIN
  UPDATE work_outputs
  SET
    substrate_proposal_id = p_proposal_id,
    promoted_to_block_id = p_block_id,
    promotion_method = p_method,
    promoted_at = now(),
    promoted_by = p_user_id,
    merged_to_substrate_at = now()
  WHERE id = p_output_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get outputs pending promotion for a basket
CREATE OR REPLACE FUNCTION get_outputs_pending_promotion(p_basket_id uuid)
RETURNS TABLE (
  id uuid,
  output_type text,
  title text,
  body jsonb,
  confidence float,
  source_context_ids uuid[],
  agent_type text,
  work_ticket_id uuid
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    wo.id,
    wo.output_type,
    wo.title,
    wo.body,
    wo.confidence,
    wo.source_context_ids,
    wo.agent_type,
    wo.work_ticket_id
  FROM work_outputs wo
  WHERE wo.basket_id = p_basket_id
    AND wo.supervision_status = 'approved'
    AND wo.substrate_proposal_id IS NULL
    AND wo.promotion_method IS NULL
  ORDER BY wo.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT EXECUTE ON FUNCTION get_project_supervision_settings(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_basket_supervision_settings(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION update_project_supervision_settings(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION mark_work_output_promoted(uuid, uuid, uuid, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION get_outputs_pending_promotion(uuid) TO authenticated, service_role;

-- ============================================================================
-- MIGRATION NOTES
-- ============================================================================

-- Work Supervision Settings Schema:
-- {
--   "promotion_mode": "auto" | "manual",
--   "auto_promote_types": ["finding", "recommendation", "insight"],
--   "require_review_before_promotion": false,
--   "notify_on_promotion": true
-- }
--
-- Promotion Flow:
-- 1. User approves work_output (supervision_status = 'approved')
-- 2. System checks project.metadata.work_supervision.promotion_mode
-- 3. If "auto": immediately create P1 proposal
-- 4. If "manual": wait for explicit promotion action
-- 5. P1 proposal created via substrate-api
-- 6. On proposal approval: block created, work_output.promoted_to_block_id set
