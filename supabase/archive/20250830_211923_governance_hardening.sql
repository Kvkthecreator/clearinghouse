-- YARNNN Governance Hardening Migration
-- Fixes critical gaps identified in governance implementation audit
-- Adds blast_radius, aligns proposal kinds, and prepares operation execution

-- Step 1: Add blast_radius enum and column
CREATE TYPE public.blast_radius AS ENUM (
    'Local',
    'Scoped', 
    'Global'
);

ALTER TABLE public.proposals 
    ADD COLUMN blast_radius public.blast_radius DEFAULT 'Local'::public.blast_radius;

-- Step 2: Align proposal kinds with governance canon
-- Add missing kinds
ALTER TYPE public.proposal_kind ADD VALUE 'Revision';
ALTER TYPE public.proposal_kind ADD VALUE 'Detach';
ALTER TYPE public.proposal_kind ADD VALUE 'Rename';
ALTER TYPE public.proposal_kind ADD VALUE 'ContextAlias';

-- Step 3: Add operation execution tracking
ALTER TABLE public.proposals 
    ADD COLUMN executed_at timestamptz,
    ADD COLUMN execution_log jsonb DEFAULT '[]'::jsonb,
    ADD COLUMN commit_id uuid,
    ADD COLUMN is_executed boolean DEFAULT false;

-- Step 4: Add validation enforcement tracking
ALTER TABLE public.proposals 
    ADD COLUMN validator_version text DEFAULT 'v1.0',
    ADD COLUMN validation_required boolean DEFAULT true,
    ADD COLUMN validation_bypassed boolean DEFAULT false,
    ADD COLUMN bypass_reason text;

-- Step 5: Create proposal operation execution log table
CREATE TABLE public.proposal_executions (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    proposal_id uuid NOT NULL REFERENCES public.proposals(id),
    operation_index integer NOT NULL,
    operation_type text NOT NULL,
    executed_at timestamptz DEFAULT now() NOT NULL,
    success boolean NOT NULL,
    result_data jsonb DEFAULT '{}'::jsonb,
    error_message text,
    substrate_id uuid, -- Reference to created/modified substrate
    rpc_called text,
    execution_time_ms integer
);

-- Step 6: Update indexes for governance performance
CREATE INDEX idx_proposals_blast_radius ON public.proposals(blast_radius);
CREATE INDEX idx_proposals_executed ON public.proposals(is_executed, executed_at);
CREATE INDEX idx_proposal_executions_proposal ON public.proposal_executions(proposal_id, operation_index);

-- Step 7: Add validation gates RLS policies
-- Ensure only validated proposals can be approved
CREATE OR REPLACE FUNCTION public.proposal_validation_check()
RETURNS trigger AS $$
BEGIN
    -- Prevent approval of unvalidated proposals
    IF NEW.status = 'APPROVED' AND OLD.status != 'APPROVED' THEN
        IF NEW.validation_required = true AND NEW.validation_bypassed = false THEN
            -- Check if validator report is complete
            IF NEW.validator_report IS NULL OR 
               NOT (NEW.validator_report ? 'confidence') OR
               NOT (NEW.validator_report ? 'impact_summary') THEN
                RAISE EXCEPTION 'Cannot approve proposal without complete validator report. Use validation_bypassed=true to override.';
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER proposals_validation_gate
    BEFORE UPDATE ON public.proposals
    FOR EACH ROW
    EXECUTE FUNCTION public.proposal_validation_check();

-- Step 8: Enable RLS on new tables
ALTER TABLE public.proposal_executions ENABLE ROW LEVEL SECURITY;

-- Step 9: Create RLS policies for execution tracking
CREATE POLICY "Users can view executions in their workspace" ON public.proposal_executions
    FOR SELECT USING (
        proposal_id IN (
            SELECT id FROM public.proposals 
            WHERE workspace_id IN (
                SELECT workspace_id FROM public.workspace_memberships 
                WHERE user_id = auth.uid()
            )
        )
    );

-- Step 10: Grant permissions
GRANT ALL ON public.proposal_executions TO authenticated;
GRANT USAGE ON TYPE public.blast_radius TO authenticated;

COMMENT ON TABLE public.proposal_executions IS 'Tracks execution of individual operations within proposals';
COMMENT ON COLUMN public.proposals.blast_radius IS 'Impact scope: Local (basket), Scoped (workspace), Global (cross-workspace)';
COMMENT ON COLUMN public.proposals.is_executed IS 'Whether proposal operations have been committed to substrate';