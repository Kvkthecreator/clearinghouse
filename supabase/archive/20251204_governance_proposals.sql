-- ============================================================================
-- Governance Proposals Table
-- ============================================================================
-- Stores proposed changes to foundation-tier context items.
-- TP creates proposals when it wants to modify problem, customer, vision, brand.
-- User approves/rejects via Governance UI.
--
-- See: /docs/implementation/THINKING_PARTNER_IMPLEMENTATION_PLAN.md
-- ============================================================================

-- Create governance_proposals table
CREATE TABLE IF NOT EXISTS public.governance_proposals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    basket_id UUID NOT NULL REFERENCES public.baskets(id) ON DELETE CASCADE,

    -- Proposal metadata
    proposal_type TEXT NOT NULL DEFAULT 'context_item',  -- 'context_item', 'recipe_config', etc.
    status TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'approved', 'rejected', 'expired'

    -- Who/what created the proposal
    proposed_by TEXT NOT NULL,  -- 'agent:thinking_partner', 'user:uuid', etc.

    -- The proposed changes (JSONB for flexibility)
    proposed_changes JSONB NOT NULL DEFAULT '{}',
    -- For context_item type:
    -- {
    --   "item_type": "problem",
    --   "item_key": null,
    --   "title": "Problem Statement",
    --   "content": {...new content...},
    --   "previous_content": {...old content or null...},
    --   "operation": "create" | "update" | "delete"
    -- }

    -- Additional metadata
    metadata JSONB DEFAULT '{}',
    -- {
    --   "source": "thinking_partner",
    --   "session_id": "...",
    --   "completeness_score": 0.8
    -- }

    -- Review information
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,

    -- Auto-expiry for stale proposals
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days'),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient queries
CREATE INDEX IF NOT EXISTS idx_governance_proposals_basket_status
    ON public.governance_proposals(basket_id, status);

CREATE INDEX IF NOT EXISTS idx_governance_proposals_created
    ON public.governance_proposals(created_at DESC);

-- Enable RLS
ALTER TABLE public.governance_proposals ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view proposals for baskets they own
CREATE POLICY "Users can view own basket proposals"
    ON public.governance_proposals
    FOR SELECT
    USING (
        basket_id IN (
            SELECT id FROM public.baskets WHERE user_id = auth.uid()
        )
    );

-- Users can update (approve/reject) proposals for baskets they own
CREATE POLICY "Users can update own basket proposals"
    ON public.governance_proposals
    FOR UPDATE
    USING (
        basket_id IN (
            SELECT id FROM public.baskets WHERE user_id = auth.uid()
        )
    );

-- Service role can insert proposals (for TP agent)
CREATE POLICY "Service role can insert proposals"
    ON public.governance_proposals
    FOR INSERT
    WITH CHECK (true);

-- Updated_at trigger
CREATE TRIGGER governance_proposals_updated_at
    BEFORE UPDATE ON public.governance_proposals
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at();

-- ============================================================================
-- Function to apply approved proposal
-- ============================================================================
CREATE OR REPLACE FUNCTION public.apply_governance_proposal(proposal_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_proposal RECORD;
    v_changes JSONB;
    v_item_data JSONB;
    v_result JSONB;
BEGIN
    -- Get the proposal
    SELECT * INTO v_proposal
    FROM public.governance_proposals
    WHERE id = proposal_id AND status = 'approved';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Proposal not found or not approved');
    END IF;

    v_changes := v_proposal.proposed_changes;

    -- Handle context_item proposals
    IF v_proposal.proposal_type = 'context_item' THEN
        IF v_changes->>'operation' = 'delete' THEN
            -- Archive the item
            UPDATE public.context_items
            SET status = 'archived', updated_at = NOW()
            WHERE basket_id = v_proposal.basket_id
              AND item_type = v_changes->>'item_type'
              AND (item_key = v_changes->>'item_key' OR (item_key IS NULL AND v_changes->>'item_key' IS NULL));

            v_result := jsonb_build_object('action', 'deleted', 'item_type', v_changes->>'item_type');
        ELSE
            -- Upsert the item
            INSERT INTO public.context_items (
                basket_id,
                tier,
                item_type,
                item_key,
                title,
                content,
                schema_id,
                completeness_score,
                status,
                created_by,
                updated_by
            ) VALUES (
                v_proposal.basket_id,
                'foundation',
                v_changes->>'item_type',
                v_changes->>'item_key',
                v_changes->>'title',
                v_changes->'content',
                v_changes->>'item_type',
                COALESCE((v_proposal.metadata->>'completeness_score')::numeric, 0),
                'active',
                v_proposal.proposed_by,
                'user:' || auth.uid()::text
            )
            ON CONFLICT (basket_id, item_type, item_key)
            DO UPDATE SET
                title = EXCLUDED.title,
                content = EXCLUDED.content,
                completeness_score = EXCLUDED.completeness_score,
                updated_by = EXCLUDED.updated_by,
                updated_at = NOW();

            v_result := jsonb_build_object(
                'action', v_changes->>'operation',
                'item_type', v_changes->>'item_type'
            );
        END IF;

        -- Mark proposal as applied
        UPDATE public.governance_proposals
        SET metadata = metadata || jsonb_build_object('applied_at', NOW()::text)
        WHERE id = proposal_id;
    END IF;

    RETURN v_result;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.apply_governance_proposal(UUID) TO authenticated;

COMMENT ON TABLE public.governance_proposals IS 'Stores proposed changes to foundation-tier context requiring user approval';
COMMENT ON FUNCTION public.apply_governance_proposal IS 'Applies an approved governance proposal to context_items';
