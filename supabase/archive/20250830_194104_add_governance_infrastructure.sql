-- YARNNN Governance Infrastructure Migration
-- Implements YARNNN_GOVERNANCE_CANON.md requirements
-- Creates proposal system and context_items governance states

-- Step 1: Create governance enums
CREATE TYPE public.proposal_state AS ENUM (
    'DRAFT',
    'PROPOSED', 
    'UNDER_REVIEW',
    'APPROVED',
    'REJECTED',
    'SUPERSEDED',
    'MERGED'
);

CREATE TYPE public.proposal_kind AS ENUM (
    'Extraction',
    'Edit', 
    'Merge',
    'Attachment',
    'ScopePromotion',
    'Deprecation'
);

CREATE TYPE public.context_item_state AS ENUM (
    'PROVISIONAL',
    'PROPOSED',
    'UNDER_REVIEW',
    'ACTIVE',
    'DEPRECATED', 
    'MERGED',
    'REJECTED'
);

-- Step 2: Create proposals table
CREATE TABLE public.proposals (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    basket_id uuid NOT NULL REFERENCES public.baskets(id),
    workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
    proposal_kind public.proposal_kind NOT NULL,
    basis_snapshot_id uuid, -- NULL means HEAD
    origin text NOT NULL CHECK (origin IN ('agent', 'human')),
    provenance jsonb DEFAULT '[]'::jsonb, -- array of dump_ids or artifact refs
    ops jsonb NOT NULL, -- array of atomic operations
    validator_report jsonb DEFAULT '{}'::jsonb,
    status public.proposal_state DEFAULT 'PROPOSED'::public.proposal_state NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid,
    reviewed_by uuid,
    reviewed_at timestamptz,
    review_notes text,
    metadata jsonb DEFAULT '{}'::jsonb
);

-- Step 3: Add governance column to context_items (preserving existing data)
ALTER TABLE public.context_items 
    ADD COLUMN state public.context_item_state DEFAULT 'ACTIVE'::public.context_item_state;

-- Migrate existing context_items status to governance states
UPDATE public.context_items 
SET state = CASE 
    WHEN status = 'active' THEN 'ACTIVE'::public.context_item_state
    WHEN status = 'archived' THEN 'DEPRECATED'::public.context_item_state
    ELSE 'ACTIVE'::public.context_item_state -- fallback
END;

-- Step 4: Add governance timeline events
-- Update timeline_events kind constraint to include governance events
ALTER TABLE public.timeline_events 
DROP CONSTRAINT timeline_events_kind_check;

ALTER TABLE public.timeline_events 
ADD CONSTRAINT timeline_events_kind_check 
CHECK ((kind = ANY (ARRAY[
    'dump'::text, 'reflection'::text, 'narrative'::text, 'system_note'::text, 'block'::text, 
    'dump.created'::text, 'reflection.computed'::text, 'delta.applied'::text, 'delta.rejected'::text, 
    'document.created'::text, 'document.updated'::text, 'document.block.attached'::text, 
    'document.block.detached'::text, 'document.dump.attached'::text, 'document.dump.detached'::text, 
    'document.context_item.attached'::text, 'document.context_item.detached'::text, 
    'document.reflection.attached'::text, 'document.reflection.detached'::text, 
    'document.timeline_event.attached'::text, 'document.timeline_event.detached'::text, 
    'block.created'::text, 'block.updated'::text, 'basket.created'::text, 'workspace.member_added'::text,
    -- New governance events
    'proposal.submitted'::text, 'proposal.approved'::text, 'proposal.rejected'::text,
    'substrate.committed'::text, 'cascade.completed'::text
])));

-- Step 5: Add indexes for governance performance
CREATE INDEX idx_proposals_basket_status ON public.proposals(basket_id, status);
CREATE INDEX idx_proposals_workspace_created ON public.proposals(workspace_id, created_at DESC);
CREATE INDEX idx_context_items_state ON public.context_items(state);

-- Step 6: Enable RLS on proposals table
ALTER TABLE public.proposals ENABLE ROW LEVEL SECURITY;

-- Step 7: Create RLS policies for proposals (workspace isolation)
CREATE POLICY "Users can view proposals in their workspace" ON public.proposals
    FOR SELECT USING (
        workspace_id IN (
            SELECT workspace_id FROM public.workspace_memberships 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create proposals in their workspace" ON public.proposals
    FOR INSERT WITH CHECK (
        workspace_id IN (
            SELECT workspace_id FROM public.workspace_memberships 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update proposals in their workspace" ON public.proposals
    FOR UPDATE USING (
        workspace_id IN (
            SELECT workspace_id FROM public.workspace_memberships 
            WHERE user_id = auth.uid()
        )
    );

-- Step 8: Grant permissions to authenticated users
GRANT ALL ON public.proposals TO authenticated;
GRANT USAGE ON TYPE public.proposal_state TO authenticated;
GRANT USAGE ON TYPE public.proposal_kind TO authenticated;
GRANT USAGE ON TYPE public.context_item_state TO authenticated;

-- Step 9: Add governance tracking fields to existing tables
ALTER TABLE public.context_items 
    ADD COLUMN proposal_id uuid REFERENCES public.proposals(id),
    ADD COLUMN approved_at timestamptz,
    ADD COLUMN approved_by uuid;

ALTER TABLE public.blocks 
    ADD COLUMN proposal_id uuid REFERENCES public.proposals(id),
    ADD COLUMN approved_at timestamptz,
    ADD COLUMN approved_by uuid;

COMMENT ON TABLE public.proposals IS 'Governance proposals for substrate mutations - implements YARNNN_GOVERNANCE_CANON.md';
COMMENT ON COLUMN public.context_items.state IS 'Governance state for context_items - replaces simple status field';
COMMENT ON COLUMN public.context_items.proposal_id IS 'Links to the proposal that created/modified this context_item';