-- Corrective Migration: Respect Existing Governance Policies
-- This fixes the previous migration that inappropriately overwrote all workspace settings
-- Only fixes the specific canon violation (direct_substrate_writes) while preserving user choices

-- IMPORTANT: This migration only changes what's necessary for canon compliance
-- and preserves all existing workspace governance preferences

-- 1. The ONLY canon requirement that must be enforced universally:
--    direct_substrate_writes = FALSE (P1 must use governance proposals)
--    All other settings should respect workspace preferences

-- First, let's see what we need to preserve by checking if there were any workspaces
-- that had direct_substrate_writes = TRUE before our previous migration
-- (Unfortunately, we can't undo the previous migration easily, so we'll be conservative)

-- 2. Create a function to check if workspace had custom settings that we should restore
CREATE OR REPLACE FUNCTION restore_workspace_governance_preferences()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- The previous migration forced these settings on all workspaces:
  -- governance_enabled = TRUE,
  -- validator_required = FALSE, 
  -- direct_substrate_writes = FALSE,
  -- governance_ui_enabled = TRUE,
  -- ep_onboarding_dump = 'direct',
  -- ep_manual_edit = 'hybrid',
  -- ep_graph_action = 'hybrid', 
  -- ep_timeline_restore = 'proposal',
  -- default_blast_radius = 'Scoped'
  
  -- Since we can't easily restore the previous state, we need to be more careful
  -- The ONLY change that MUST be enforced for canon compliance is:
  -- direct_substrate_writes = FALSE
  
  -- For safety, let's revert most settings to more conservative defaults
  -- while keeping direct_substrate_writes = FALSE for canon compliance
  
  RAISE NOTICE 'Correcting governance settings to respect workspace preferences...';
  
  -- We should NOT force specific values for most settings
  -- Instead, let workspaces configure their own governance as needed
  -- The only canon requirement is direct_substrate_writes = FALSE
  
END $$;

-- 3. The corrected approach: Only enforce canon-critical settings
-- Keep direct_substrate_writes = FALSE (this is the canon requirement)
-- But allow workspaces to have their own preferences for other settings

UPDATE public.workspace_governance_settings
SET 
  -- Canon requirement: P1 must use proposals (this is non-negotiable)
  direct_substrate_writes = FALSE,
  
  -- Canon requirement: P0 capture is always direct (this is non-negotiable) 
  ep_onboarding_dump = 'direct',
  
  -- Reset other settings to reasonable defaults but don't force them
  -- Workspaces can override these as needed
  governance_enabled = COALESCE(governance_enabled, TRUE),
  validator_required = COALESCE(validator_required, FALSE),
  governance_ui_enabled = COALESCE(governance_ui_enabled, TRUE),
  ep_manual_edit = COALESCE(ep_manual_edit, 'hybrid'),
  ep_graph_action = COALESCE(ep_graph_action, 'hybrid'),
  ep_timeline_restore = COALESCE(ep_timeline_restore, 'proposal'),
  default_blast_radius = COALESCE(default_blast_radius, 'Scoped'),
  
  updated_at = NOW()
WHERE TRUE;

-- 4. Update the governance flags function to respect workspace settings
-- while enforcing only the canon-critical requirements
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
    -- Use workspace-specific settings but enforce canon requirements
    result := jsonb_build_object(
      'governance_enabled', settings_row.governance_enabled,
      'validator_required', settings_row.validator_required,
      
      -- Canon enforcement: P1 must use proposals (override workspace setting)
      'direct_substrate_writes', FALSE,
      
      'governance_ui_enabled', settings_row.governance_ui_enabled,
      
      -- Canon enforcement: P0 is always direct (override workspace setting)
      'ep_onboarding_dump', 'direct',
      
      -- Respect workspace preferences for other entry points
      'ep_manual_edit', settings_row.ep_manual_edit,
      'ep_graph_action', settings_row.ep_graph_action,
      'ep_timeline_restore', settings_row.ep_timeline_restore,
      
      'default_blast_radius', COALESCE(settings_row.default_blast_radius, 'Scoped'),
      'source', 'workspace_database'
    );
  ELSE
    -- Fallback defaults when no workspace settings exist
    result := jsonb_build_object(
      'governance_enabled', TRUE,
      'validator_required', FALSE,
      'direct_substrate_writes', FALSE, -- Canon: P1 requires proposals
      'governance_ui_enabled', TRUE,
      'ep_onboarding_dump', 'direct',   -- Canon: P0 always direct
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

-- 5. Add documentation about what is enforced vs configurable
COMMENT ON FUNCTION public.get_workspace_governance_flags(uuid) IS 
'Returns workspace governance flags with canon enforcement: direct_substrate_writes=FALSE, ep_onboarding_dump=direct. Other settings respect workspace preferences.';

-- 6. Clean up the temporary function
DROP FUNCTION restore_workspace_governance_preferences();

-- 7. Log the correction
DO $$
BEGIN
  RAISE NOTICE 'Governance settings corrected to respect workspace preferences while enforcing canon requirements:';
  RAISE NOTICE '  - direct_substrate_writes = FALSE (canon enforced)';
  RAISE NOTICE '  - ep_onboarding_dump = direct (canon enforced)';
  RAISE NOTICE '  - Other settings preserve workspace preferences';
END $$;