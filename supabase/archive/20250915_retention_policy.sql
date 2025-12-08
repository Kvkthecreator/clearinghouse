-- Phase 2: Workspace retention policy toggles and exposure via flags

BEGIN;

-- Add retention fields to workspace governance settings
ALTER TABLE public.workspace_governance_settings
  ADD COLUMN IF NOT EXISTS retention_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS retention_policy jsonb NOT NULL DEFAULT '{}'::jsonb; -- flexible, no hardcoded durations

-- Update flags function to include retention fields
CREATE OR REPLACE FUNCTION public.get_workspace_governance_flags(p_workspace_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
  settings_row public.workspace_governance_settings%ROWTYPE;
BEGIN
  SELECT * INTO settings_row 
  FROM public.workspace_governance_settings 
  WHERE workspace_id = p_workspace_id;
  
  IF FOUND THEN
    result := jsonb_build_object(
      'governance_enabled', settings_row.governance_enabled,
      'validator_required', settings_row.validator_required,
      'direct_substrate_writes', settings_row.direct_substrate_writes,
      'governance_ui_enabled', settings_row.governance_ui_enabled,
      'ep_onboarding_dump', settings_row.ep_onboarding_dump,
      'ep_manual_edit', settings_row.ep_manual_edit,
      'ep_document_edit', settings_row.ep_document_edit,
      'ep_reflection_suggestion', settings_row.ep_reflection_suggestion,
      'ep_graph_action', settings_row.ep_graph_action,
      'ep_timeline_restore', settings_row.ep_timeline_restore,
      'default_blast_radius', settings_row.default_blast_radius,
      'retention_enabled', settings_row.retention_enabled,
      'retention_policy', COALESCE(settings_row.retention_policy, '{}'::jsonb),
      'source', 'workspace_database'
    );
  ELSE
    result := jsonb_build_object(
      'governance_enabled', true,
      'validator_required', false,
      'direct_substrate_writes', false,
      'governance_ui_enabled', true,
      'ep_onboarding_dump', 'proposal',
      'ep_manual_edit', 'proposal',
      'ep_document_edit', 'proposal',
      'ep_reflection_suggestion', 'proposal',
      'ep_graph_action', 'proposal',
      'ep_timeline_restore', 'proposal',
      'default_blast_radius', 'Scoped',
      'retention_enabled', false,
      'retention_policy', '{}'::jsonb,
      'source', 'canon_compliant_defaults'
    );
  END IF;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_workspace_governance_flags(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_workspace_governance_flags(uuid) TO service_role;

COMMIT;

