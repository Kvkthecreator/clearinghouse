-- Allow authenticated clients to read the workspace mapping view
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.v_user_workspaces TO authenticated;

-- Ensure underlying tables are selectable (RLS still restricts rows)
GRANT SELECT ON public.workspaces             TO authenticated;
GRANT SELECT ON public.workspace_memberships  TO authenticated;
GRANT SELECT ON public.baskets                TO authenticated;

-- (From earlier steps; include here if not already applied)
GRANT SELECT          ON public.timeline_events     TO authenticated;
GRANT SELECT, INSERT  ON public.basket_reflections  TO authenticated;

-- Make sure RLS is enabled (no-op if already)
ALTER TABLE public.workspaces            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.baskets               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timeline_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.basket_reflections    ENABLE ROW LEVEL SECURITY;

-- Workspace-scoped SELECT policy for timeline (idempotent if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='timeline_events' AND policyname='te_select_workspace_member'
  ) THEN
    CREATE POLICY te_select_workspace_member
    ON public.timeline_events
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.baskets b
        JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
        WHERE b.id = timeline_events.basket_id
          AND wm.user_id = auth.uid()
      )
    );
  END IF;
END$$;

-- Workspace-scoped SELECT policy for reflections (idempotent if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='basket_reflections' AND policyname='br_select_workspace_member'
  ) THEN
    CREATE POLICY br_select_workspace_member
    ON public.basket_reflections
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.baskets b
        JOIN public.workspace_memberships wm ON wm.workspace_id = b.workspace_id
        WHERE b.id = basket_reflections.basket_id
          AND wm.user_id = auth.uid()
      )
    );
  END IF;
END$$;
