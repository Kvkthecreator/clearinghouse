-- Fix Memory Workflow for Canon v2.2 Compliance
-- Ensures memory addition follows canonical governance flow:
-- P0: Direct raw dump creation (canonical)  
-- P1: Mandatory governance proposals for substrate evolution (canonical)

-- 1. Update all workspaces to use canonical governance settings
UPDATE public.workspace_governance_settings
SET 
  governance_enabled = TRUE,
  validator_required = FALSE,
  direct_substrate_writes = FALSE,  -- Canon: P1 substrate evolution requires proposals
  governance_ui_enabled = TRUE,
  ep_onboarding_dump = 'direct',    -- Canon: P0 capture is always direct
  ep_manual_edit = 'hybrid',
  ep_graph_action = 'hybrid',
  ep_timeline_restore = 'proposal',
  default_blast_radius = 'Scoped'
WHERE TRUE;

-- 2. Insert canonical settings for workspaces without governance configuration
INSERT INTO public.workspace_governance_settings (
  workspace_id,
  governance_enabled,
  validator_required, 
  direct_substrate_writes,
  governance_ui_enabled,
  ep_onboarding_dump,
  ep_manual_edit,
  ep_graph_action,
  ep_timeline_restore,
  default_blast_radius,
  created_at,
  updated_at
)
SELECT 
  w.id as workspace_id,
  TRUE as governance_enabled,
  FALSE as validator_required,
  FALSE as direct_substrate_writes,  -- Canon: force proposals for P1
  TRUE as governance_ui_enabled,
  'direct' as ep_onboarding_dump,    -- Canon: P0 always direct
  'hybrid' as ep_manual_edit,
  'hybrid' as ep_graph_action, 
  'proposal' as ep_timeline_restore,
  'Scoped' as default_blast_radius,
  NOW() as created_at,
  NOW() as updated_at
FROM public.workspaces w
WHERE w.id NOT IN (
  SELECT workspace_id 
  FROM public.workspace_governance_settings
);

-- 3. Verify queue trigger exists and is active
-- (This ensures dumps get automatically queued for P1 processing)
DO $$
BEGIN
  -- Check if trigger exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers 
    WHERE trigger_name = 'after_dump_insert' 
    AND event_object_table = 'raw_dumps'
  ) THEN
    -- Recreate the trigger if missing
    CREATE OR REPLACE FUNCTION queue_agent_processing() 
    RETURNS trigger AS $trigger$
    BEGIN
      -- Insert into processing queue with workspace context
      INSERT INTO agent_processing_queue (
        dump_id, 
        basket_id, 
        workspace_id
      )
      SELECT 
        NEW.id,
        NEW.basket_id,
        b.workspace_id
      FROM baskets b
      WHERE b.id = NEW.basket_id;
      
      RETURN NEW;
    END;
    $trigger$ LANGUAGE plpgsql;

    CREATE TRIGGER after_dump_insert
    AFTER INSERT ON raw_dumps
    FOR EACH ROW 
    EXECUTE FUNCTION queue_agent_processing();
    
    RAISE NOTICE 'Queue trigger recreated for canon compliance';
  ELSE
    RAISE NOTICE 'Queue trigger already exists';
  END IF;
END $$;

-- 4. Update governance flags function to ensure canon compliance
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
      'direct_substrate_writes', FALSE, -- Canon: Always FALSE for P1 proposals
      'governance_ui_enabled', settings_row.governance_ui_enabled,
      'ep_onboarding_dump', 'direct',   -- Canon: P0 always direct
      'ep_manual_edit', settings_row.ep_manual_edit,
      'ep_graph_action', settings_row.ep_graph_action,
      'ep_timeline_restore', 'proposal', -- Canon: timeline restore requires review
      'default_blast_radius', COALESCE(settings_row.default_blast_radius, 'Scoped'),
      'source', 'workspace_database'
    );
  ELSE
    -- Canonical fallback: Governance enabled, proposals for P1, direct for P0
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

-- 5. Add comments for canon compliance documentation
COMMENT ON FUNCTION public.get_workspace_governance_flags(uuid) IS 
'Returns Canon v2.2 compliant governance flags: P0 direct, P1 proposals, governance enabled';

COMMENT ON TRIGGER after_dump_insert ON raw_dumps IS 
'Canon v2.2: Ensures every raw dump is queued for mandatory P1 governance processing';

-- 6. Grant necessary permissions for service operations
GRANT EXECUTE ON FUNCTION queue_agent_processing() TO authenticated;
GRANT EXECUTE ON FUNCTION queue_agent_processing() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_governance_flags(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_workspace_governance_flags(uuid) TO service_role;