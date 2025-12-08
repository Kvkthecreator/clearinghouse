-- P3/P4 Taxonomy and Immutability Hardening
-- Implements: Insights (P3) and Documents (P4) canonical taxonomy
-- Ref: YARNNN P3/P4 Implementation Spec

BEGIN;

-- =============================================================================
-- P3: INSIGHTS TAXONOMY (reflections_artifact)
-- =============================================================================

-- Add insight type taxonomy
ALTER TABLE public.reflections_artifact
  ADD COLUMN insight_type text CHECK (insight_type IN (
    'insight_canon',      -- Basket-level insight (one current per basket)
    'doc_insight',        -- Document-scoped insight
    'timeboxed_insight',  -- Temporal window insight
    'review_insight'      -- Proposal evaluation (internal, computed)
  )),

  -- Add current pointer (for insight_canon only)
  ADD COLUMN is_current boolean DEFAULT false,

  -- Add lineage tracking
  ADD COLUMN previous_id uuid REFERENCES public.reflections_artifact(id) ON DELETE SET NULL,

  -- Add provenance (derived from blocks, reflections, docs, proposals)
  ADD COLUMN derived_from jsonb DEFAULT '[]'::jsonb,

  -- Context-driven freshness (not time-driven)
  ADD COLUMN graph_signature text,  -- Relationship topology at generation time

  -- Scope level (basket, workspace, org, global)
  ADD COLUMN scope_level text CHECK (scope_level IN (
    'basket',
    'workspace',
    'org',
    'global'
  )) DEFAULT 'basket';

-- Make basket_id nullable for workspace/org/global insights
ALTER TABLE public.reflections_artifact
  ALTER COLUMN basket_id DROP NOT NULL;

-- Constraint: basket insights must have basket_id, workspace insights must not
ALTER TABLE public.reflections_artifact
  ADD CONSTRAINT insight_scope_consistency CHECK (
    (scope_level = 'basket' AND basket_id IS NOT NULL) OR
    (scope_level != 'basket' AND basket_id IS NULL)
  );

-- Constraint: Only one current insight_canon per basket
CREATE UNIQUE INDEX uq_current_insight_canon_per_basket
  ON public.reflections_artifact(basket_id)
  WHERE insight_type = 'insight_canon' AND is_current = true AND basket_id IS NOT NULL;

-- Constraint: Only one current workspace insight_canon per workspace
CREATE UNIQUE INDEX uq_current_insight_canon_per_workspace
  ON public.reflections_artifact(workspace_id)
  WHERE insight_type = 'insight_canon' AND is_current = true AND scope_level = 'workspace';

-- Index for workspace-level queries
CREATE INDEX idx_reflections_workspace_scope
  ON public.reflections_artifact(workspace_id, scope_level, is_current)
  WHERE scope_level = 'workspace';

-- Index for lineage traversal
CREATE INDEX idx_reflections_lineage
  ON public.reflections_artifact(previous_id)
  WHERE previous_id IS NOT NULL;

-- =============================================================================
-- P4: DOCUMENTS TAXONOMY
-- =============================================================================

-- Add document type taxonomy
ALTER TABLE public.documents
  ADD COLUMN doc_type text CHECK (doc_type IN (
    'document_canon',   -- Basket Context Canon (one active per basket)
    'starter_prompt',   -- Reasoning capsule
    'artifact_other'    -- Future extensibility
  )) DEFAULT 'artifact_other',

  -- Add lineage tracking for regeneration
  ADD COLUMN previous_id uuid REFERENCES public.documents(id) ON DELETE SET NULL,

  -- Add provenance (derived from insights, reflections, substrate)
  ADD COLUMN derived_from jsonb DEFAULT '{}'::jsonb;

-- Enforce immutability: Remove body_md (content lives in document_versions only)
-- NOTE: This is a breaking change - migrate existing body_md to document_versions first
-- Commented out for now, implement in follow-up migration after data migration
-- ALTER TABLE public.documents DROP COLUMN IF EXISTS body_md;

-- Constraint: Only one document_canon per basket
CREATE UNIQUE INDEX uq_document_canon_per_basket
  ON public.documents(basket_id)
  WHERE doc_type = 'document_canon' AND basket_id IS NOT NULL;

-- Index for document lineage
CREATE INDEX idx_documents_lineage
  ON public.documents(previous_id)
  WHERE previous_id IS NOT NULL;

-- =============================================================================
-- P3/P4 REGENERATION POLICY
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.p3_p4_regeneration_policy (
  workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id) ON DELETE CASCADE,

  -- Basket-level policies
  insight_canon_auto_regenerate boolean DEFAULT true,
  document_canon_auto_regenerate boolean DEFAULT true,

  -- Workspace-level policies (cross-basket synthesis)
  workspace_insight_enabled boolean DEFAULT false,  -- Feature flag
  workspace_insight_min_baskets int DEFAULT 3,      -- Min baskets for synthesis
  workspace_insight_throttle_hours int DEFAULT 24,  -- Max once per day

  -- Metadata
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- RLS for regeneration policy
ALTER TABLE public.p3_p4_regeneration_policy ENABLE ROW LEVEL SECURITY;

CREATE POLICY p3_p4_policy_workspace_access
  ON public.p3_p4_regeneration_policy
  FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id
      FROM public.workspace_memberships
      WHERE user_id = auth.uid()
    )
  );

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function: Get current basket insight canon
CREATE OR REPLACE FUNCTION public.get_current_insight_canon(p_basket_id uuid)
RETURNS TABLE (
  id uuid,
  reflection_text text,
  substrate_hash text,
  graph_signature text,
  derived_from jsonb,
  created_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ra.id,
    ra.reflection_text,
    ra.substrate_hash,
    ra.graph_signature,
    ra.derived_from,
    ra.created_at
  FROM public.reflections_artifact ra
  WHERE ra.basket_id = p_basket_id
    AND ra.insight_type = 'insight_canon'
    AND ra.is_current = true
  LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Function: Get document canon for basket
CREATE OR REPLACE FUNCTION public.get_document_canon(p_basket_id uuid)
RETURNS TABLE (
  id uuid,
  title text,
  current_version_hash text,
  composition_instructions jsonb,
  derived_from jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.title,
    d.current_version_hash,
    d.composition_instructions,
    d.derived_from
  FROM public.documents d
  WHERE d.basket_id = p_basket_id
    AND d.doc_type = 'document_canon'
  LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================================================
-- MIGRATION NOTES
-- =============================================================================

-- TODO (Follow-up migrations):
-- 1. Migrate existing reflections_artifact rows to set insight_type (default to legacy)
-- 2. Migrate existing documents.body_md to document_versions before dropping column
-- 3. Seed document_canon for all existing baskets (via backend health endpoint)
-- 4. Seed insight_canon for all existing baskets (via backend health endpoint)

COMMIT;
