-- YARNNN Governance Hardening: Workspace-Level Governance Settings
-- Moves from environment flags to workspace-scoped governance policies
-- Enables per-workspace governance configuration with entry-point policies

-- Step 1: Create workspace governance settings table
CREATE TABLE IF NOT EXISTS public.workspace_governance_settings (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,
  
  -- Global governance switches
  governance_enabled boolean NOT NULL DEFAULT false,
  validator_required boolean NOT NULL DEFAULT false,
  direct_substrate_writes boolean NOT NULL DEFAULT true,
  governance_ui_enabled boolean NOT NULL DEFAULT false,

  -- Per-entry-point policies (proposal/direct/hybrid)
  ep_onboarding_dump text NOT NULL DEFAULT 'proposal' CHECK (ep_onboarding_dump IN ('proposal', 'direct', 'hybrid')),
  ep_manual_edit text NOT NULL DEFAULT 'proposal' CHECK (ep_manual_edit IN ('proposal', 'direct', 'hybrid')),
  ep_document_edit text NOT NULL DEFAULT 'proposal' CHECK (ep_document_edit IN ('proposal', 'direct', 'hybrid')),
  ep_reflection_suggestion text NOT NULL DEFAULT 'proposal' CHECK (ep_reflection_suggestion IN ('proposal', 'direct', 'hybrid')),
  ep_graph_action text NOT NULL DEFAULT 'proposal' CHECK (ep_graph_action IN ('proposal', 'direct', 'hybrid')),
  ep_timeline_restore text NOT NULL DEFAULT 'proposal' CHECK (ep_timeline_restore IN ('proposal', 'direct', 'hybrid')),

  -- Default risk settings
  default_blast_radius public.blast_radius NOT NULL DEFAULT 'Scoped'::public.blast_radius,

  -- Audit tracking
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Step 2: Add updated_at trigger
CREATE TRIGGER trg_workspace_governance_settings_updated_at
  BEFORE UPDATE ON public.workspace_governance_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Step 3: RLS policies for workspace governance settings
ALTER TABLE public.workspace_governance_settings ENABLE ROW LEVEL SECURITY;

-- Members can read their workspace governance settings
CREATE POLICY "workspace_governance_settings_select" ON public.workspace_governance_settings
  FOR SELECT USING (
    workspace_id IN (
      SELECT workspace_id FROM public.workspace_memberships 
      WHERE user_id = auth.uid()
    )
  );

-- Only workspace admins can update governance settings
CREATE POLICY "workspace_governance_settings_update" ON public.workspace_governance_settings
  FOR UPDATE USING (
    workspace_id IN (
      SELECT workspace_id FROM public.workspace_memberships 
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  );

-- Workspace admins can insert governance settings
CREATE POLICY "workspace_governance_settings_insert" ON public.workspace_governance_settings
  FOR INSERT WITH CHECK (
    workspace_id IN (
      SELECT workspace_id FROM public.workspace_memberships 
      WHERE user_id = auth.uid() AND role = 'admin'
    )
  );

-- Step 4: Extend proposal kinds to match canon requirements
DO $$
BEGIN
  -- Add missing proposal kinds if not present
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'proposal_kind') THEN
    CREATE TYPE public.proposal_kind AS ENUM (
      'Extraction', 'Edit', 'Merge', 'Attachment', 'Detach', 
      'Revision', 'Rename', 'ContextAlias', 'ScopePromotion', 'Deprecation'
    );
  ELSE
    -- Extend existing enum with new values
    ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'Detach';
    ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'Revision';
    ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'Rename';
    ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'ContextAlias';
    ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'ScopePromotion';
    ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'Deprecation';
  END IF;
END
$$;

-- Step 5: Create proposal execution log table (if not exists)
CREATE TABLE IF NOT EXISTS public.proposal_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proposal_id uuid NOT NULL REFERENCES public.proposals(id) ON DELETE CASCADE,
  executed_by uuid NOT NULL REFERENCES auth.users(id),
  executed_at timestamptz NOT NULL DEFAULT now(),
  ops_executed jsonb NOT NULL,
  status text NOT NULL CHECK (status IN ('success', 'partial', 'failed')),
  error jsonb DEFAULT '{}'::jsonb,
  execution_time_ms integer DEFAULT 0,
  
  -- Audit fields
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_proposal_executions_proposal_id ON public.proposal_executions(proposal_id);
CREATE INDEX IF NOT EXISTS idx_proposal_executions_executed_at ON public.proposal_executions(executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_workspace_governance_settings_workspace_id ON public.workspace_governance_settings(workspace_id);

-- Step 6: Update proposals table if needed (ensure workspace_id index exists)
CREATE INDEX IF NOT EXISTS idx_proposals_workspace_status ON public.proposals(workspace_id, status, created_at DESC);

-- Step 7: Create governance evaluation helper function
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

-- Step 8: RLS for proposal executions
ALTER TABLE public.proposal_executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "proposal_executions_select" ON public.proposal_executions
  FOR SELECT USING (
    proposal_id IN (
      SELECT id FROM public.proposals 
      WHERE workspace_id IN (
        SELECT workspace_id FROM public.workspace_memberships 
        WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "proposal_executions_insert" ON public.proposal_executions
  FOR INSERT WITH CHECK (
    proposal_id IN (
      SELECT id FROM public.proposals 
      WHERE workspace_id IN (
        SELECT workspace_id FROM public.workspace_memberships 
        WHERE user_id = auth.uid()
      )
    )
  );

-- Step 9: Grant necessary permissions
GRANT SELECT ON public.workspace_governance_settings TO authenticated;
GRANT INSERT, UPDATE ON public.workspace_governance_settings TO authenticated;
GRANT SELECT, INSERT ON public.proposal_executions TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_workspace_governance_flags(uuid) TO authenticated;

-- Completion
COMMENT ON TABLE public.workspace_governance_settings IS 'Per-workspace governance configuration with entry-point policies';
COMMENT ON FUNCTION public.get_workspace_governance_flags(uuid) IS 'Evaluates governance flags for workspace with environment fallback';