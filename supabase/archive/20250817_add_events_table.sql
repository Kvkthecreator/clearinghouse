-- Create events table
CREATE TABLE IF NOT EXISTS public.events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    basket_id uuid,
    block_id uuid,
    kind text,
    payload jsonb,
    ts timestamptz DEFAULT now() NOT NULL,
    workspace_id uuid NOT NULL,
    origin text DEFAULT 'user',
    actor_id uuid,
    agent_type text,
    CONSTRAINT events_origin_check CHECK (origin = ANY (ARRAY['user','agent','daemon','system']))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_events_agent_type ON public.events USING btree (agent_type);
CREATE INDEX IF NOT EXISTS idx_events_basket_kind_ts ON public.events USING btree (basket_id, kind, ts);
CREATE INDEX IF NOT EXISTS idx_events_origin_kind ON public.events USING btree (origin, kind);
CREATE INDEX IF NOT EXISTS idx_events_workspace_ts ON public.events USING btree (workspace_id, ts DESC);

-- Foreign keys
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'events_basket_id_fkey'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_basket_id_fkey
      FOREIGN KEY (basket_id) REFERENCES public.baskets(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'events_block_id_fkey'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_block_id_fkey
      FOREIGN KEY (block_id) REFERENCES public.blocks(id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'events_actor_id_fkey'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_actor_id_fkey
      FOREIGN KEY (actor_id) REFERENCES auth.users(id);
  END IF;
END$$;

-- Row level security
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'Allow anon read events'
  ) THEN
    CREATE POLICY "Allow anon read events" ON public.events FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'Users can insert events for their workspaces'
  ) THEN
    CREATE POLICY "Users can insert events for their workspaces" ON public.events
      FOR INSERT TO authenticated
      WITH CHECK (workspace_id IN (
        SELECT workspace_memberships.workspace_id
        FROM public.workspace_memberships
        WHERE workspace_memberships.user_id = auth.uid()
      ));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'Workspace members can read events'
  ) THEN
    CREATE POLICY "Workspace members can read events" ON public.events
      FOR SELECT USING ((workspace_id IN (
        SELECT workspace_memberships.workspace_id
        FROM public.workspace_memberships
        WHERE workspace_memberships.user_id = auth.uid()
      )));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'Workspace members can update events'
  ) THEN
    CREATE POLICY "Workspace members can update events" ON public.events
      FOR UPDATE TO authenticated USING ((EXISTS (
        SELECT 1
        FROM public.workspace_memberships
        WHERE workspace_memberships.workspace_id = events.workspace_id
          AND workspace_memberships.user_id = auth.uid()
      )));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'Workspace members can view events'
  ) THEN
    CREATE POLICY "Workspace members can view events" ON public.events
      FOR SELECT TO authenticated USING ((EXISTS (
        SELECT 1
        FROM public.workspace_memberships
        WHERE workspace_memberships.workspace_id = events.workspace_id
          AND workspace_memberships.user_id = auth.uid()
      )));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'event_member_delete'
  ) THEN
    CREATE POLICY event_member_delete ON public.events
      FOR DELETE USING ((EXISTS (
        SELECT 1
        FROM public.workspace_memberships
        WHERE workspace_memberships.workspace_id = events.workspace_id
          AND workspace_memberships.user_id = auth.uid()
      )));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'event_member_insert'
  ) THEN
    CREATE POLICY event_member_insert ON public.events
      FOR INSERT WITH CHECK ((EXISTS (
        SELECT 1
        FROM public.workspace_memberships
        WHERE workspace_memberships.workspace_id = events.workspace_id
          AND workspace_memberships.user_id = auth.uid()
      )));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'event_member_update'
  ) THEN
    CREATE POLICY event_member_update ON public.events
      FOR UPDATE USING ((EXISTS (
        SELECT 1
        FROM public.workspace_memberships
        WHERE workspace_memberships.workspace_id = events.workspace_id
          AND workspace_memberships.user_id = auth.uid()
      )));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'events' AND policyname = 'select_own_events'
  ) THEN
    CREATE POLICY select_own_events ON public.events
      FOR SELECT TO authenticated USING ((EXISTS (
        SELECT 1
        FROM public.baskets b
        WHERE b.id = events.basket_id AND b.user_id = auth.uid()
      )));
  END IF;
END$$;
