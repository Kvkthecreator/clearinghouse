-- Set default Smart Review (Hybrid) across workspaces and adjust function defaults

-- 1) Update existing workspace settings to Hybrid and enable governance
UPDATE public.workspace_governance_settings
SET 
  governance_enabled = TRUE,
  validator_required = FALSE,
  ep_manual_edit = 'hybrid',
  ep_graph_action = 'hybrid'
WHERE TRUE;

-- 2) Replace get_workspace_governance_flags to default to Hybrid when no row exists
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
      'direct_substrate_writes', FALSE,
      'governance_ui_enabled', settings_row.governance_ui_enabled,
      'ep_onboarding_dump', 'direct',
      'ep_manual_edit', settings_row.ep_manual_edit,
      'ep_graph_action', settings_row.ep_graph_action,
      'ep_timeline_restore', 'proposal',
      'default_blast_radius', CASE WHEN settings_row.default_blast_radius = 'Global' THEN 'Scoped' ELSE settings_row.default_blast_radius END,
      'source', 'workspace_database'
    );
  ELSE
    -- Fallback defaults: Governance on, Smart Review (Hybrid), Validator off
    result := jsonb_build_object(
      'governance_enabled', TRUE,
      'validator_required', FALSE,
      'direct_substrate_writes', FALSE,
      'governance_ui_enabled', TRUE,
      'ep_onboarding_dump', 'direct',
      'ep_manual_edit', 'hybrid',
      'ep_graph_action', 'hybrid',
      'ep_timeline_restore', 'proposal',
      'default_blast_radius', 'Scoped',
      'source', 'canon_compliant_defaults'
    );
  END IF;
  
  RETURN result;
END;
$$;

