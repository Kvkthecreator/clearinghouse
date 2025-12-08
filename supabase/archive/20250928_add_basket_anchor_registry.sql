BEGIN;

CREATE TABLE IF NOT EXISTS public.basket_anchors (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  basket_id uuid NOT NULL REFERENCES public.baskets(id) ON DELETE CASCADE,
  anchor_key text NOT NULL,
  label text NOT NULL,
  scope text NOT NULL CHECK (scope IN ('core','brain','custom')),
  expected_type text NOT NULL CHECK (expected_type IN ('block','context_item')),
  required boolean NOT NULL DEFAULT false,
  description text,
  ordering integer,
  linked_substrate_id uuid,
  status text NOT NULL DEFAULT 'active',
  metadata jsonb NOT NULL DEFAULT '{}',
  last_refreshed_at timestamptz,
  last_relationship_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_basket_anchors_key ON public.basket_anchors (basket_id, anchor_key);
CREATE INDEX IF NOT EXISTS idx_basket_anchors_substrate ON public.basket_anchors (linked_substrate_id);
CREATE INDEX IF NOT EXISTS idx_basket_anchors_scope ON public.basket_anchors (basket_id, scope);

ALTER TABLE public.basket_anchors ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.fn_set_basket_anchor_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER basket_anchors_set_updated_at
  BEFORE UPDATE ON public.basket_anchors
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_basket_anchor_updated_at();

CREATE POLICY basket_anchors_service_full
  ON public.basket_anchors
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY basket_anchors_workspace_members_select
  ON public.basket_anchors
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.baskets b
      JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE b.id = basket_anchors.basket_id AND wm.user_id = auth.uid()
    )
  );

CREATE POLICY basket_anchors_workspace_members_modify
  ON public.basket_anchors
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.baskets b
      JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE b.id = basket_anchors.basket_id AND wm.user_id = auth.uid()
    )
  );

CREATE POLICY basket_anchors_workspace_members_update
  ON public.basket_anchors
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.baskets b
      JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE b.id = basket_anchors.basket_id AND wm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.baskets b
      JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE b.id = basket_anchors.basket_id AND wm.user_id = auth.uid()
    )
  );

CREATE POLICY basket_anchors_workspace_members_delete
  ON public.basket_anchors
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.baskets b
      JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
      WHERE b.id = basket_anchors.basket_id AND wm.user_id = auth.uid()
    )
  );

COMMIT;
