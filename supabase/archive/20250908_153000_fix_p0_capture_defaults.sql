-- Migration: Fix P0 Capture defaults to be canon-compliant (onboarding_dump = 'direct')
-- Context: P0 (Capture) must be immediate and non-interpretive to persist raw_dumps and
--          trigger P1 governance processing. Routing P0 through proposal blocks P1.
-- Changes:
--  1) Set ep_onboarding_dump default to 'direct' for new workspaces
--  2) Update existing workspace_governance_settings rows from 'proposal' → 'direct'
--  3) Update get_workspace_governance_flags() fallback defaults to return 'direct' for onboarding_dump

-- 1) Column default → 'direct'
ALTER TABLE public.workspace_governance_settings
  ALTER COLUMN ep_onboarding_dump SET DEFAULT 'direct';

-- 2) One-time normalization of existing rows (only flip explicit 'proposal')
UPDATE public.workspace_governance_settings
SET ep_onboarding_dump = 'direct'
WHERE ep_onboarding_dump = 'proposal';

-- 3) Update fallback defaults in governance flags function
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
      'ep_graph_action', settings_row.ep_graph_action,
      'ep_timeline_restore', settings_row.ep_timeline_restore,
      'default_blast_radius', settings_row.default_blast_radius,
      'source', 'workspace_database'
    );
  ELSE
    -- Canon-compliant defaults when no row exists:
    -- P0 capture must be direct; all other entry points conservative (proposal)
    result := jsonb_build_object(
      'governance_enabled', true,
      'validator_required', false,
      'direct_substrate_writes', false,
      'governance_ui_enabled', true,
      'ep_onboarding_dump', 'direct',
      'ep_manual_edit', 'proposal',
      'ep_document_edit', 'proposal',            -- legacy field retained for compatibility
      'ep_reflection_suggestion', 'proposal',    -- legacy field retained for compatibility
      'ep_graph_action', 'proposal',
      'ep_timeline_restore', 'proposal',
      'default_blast_radius', 'Scoped',
      'source', 'canon_compliant_defaults'
    );
  END IF;

  RETURN result;
END;
$$;

-- End of migration

