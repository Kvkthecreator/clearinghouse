-- Fix governance defaults to be Canon-compliant
-- Ensures workspaces without governance settings default to governance enabled

-- Update the governance evaluation function to use Canon-compliant defaults
CREATE OR REPLACE FUNCTION public.get_workspace_governance_flags(p_workspace_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
  settings_row public.workspace_governance_settings%ROWTYPE;
BEGIN
  -- Try to get workspace-specific settings
  SELECT * INTO settings_row 
  FROM public.workspace_governance_settings 
  WHERE workspace_id = p_workspace_id;
  
  IF FOUND THEN
    -- Return workspace-specific flags
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
      'source', 'workspace_database'
    );
  ELSE
    -- Return Canon-compliant defaults (governance enabled by default)
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
      'source', 'canon_compliant_defaults'
    );
  END IF;
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.get_workspace_governance_flags(uuid) IS 'Returns Canon-compliant governance flags with governance enabled by default';