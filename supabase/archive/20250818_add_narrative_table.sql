-- Create narrative table
CREATE TABLE IF NOT EXISTS public.narrative (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    basket_id uuid,
    raw_dump_id uuid,
    type text NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    confidence_score double precision DEFAULT 0.5,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Replica identity full
ALTER TABLE IF EXISTS public.narrative REPLICA IDENTITY FULL;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_narrative_basket ON public.narrative USING btree (basket_id);

-- Foreign keys
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'narrative_basket_id_fkey'
  ) THEN
    ALTER TABLE public.narrative
      ADD CONSTRAINT narrative_basket_id_fkey
      FOREIGN KEY (basket_id) REFERENCES public.baskets(id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'narrative_raw_dump_id_fkey'
  ) THEN
    ALTER TABLE public.narrative
      ADD CONSTRAINT narrative_raw_dump_id_fkey
      FOREIGN KEY (raw_dump_id) REFERENCES public.raw_dumps(id);
  END IF;
END$$;

-- Row level security
ALTER TABLE public.narrative ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'narrative' AND policyname = 'Users can view narrative in their workspace'
  ) THEN
    CREATE POLICY "Users can view narrative in their workspace" ON public.narrative
      FOR SELECT USING ((EXISTS (
        SELECT 1
        FROM public.baskets
        WHERE baskets.id = narrative.basket_id
          AND baskets.workspace_id IN (
            SELECT workspace_memberships.workspace_id
            FROM public.workspace_memberships
            WHERE workspace_memberships.user_id = auth.uid()
          )
      )));
  END IF;
END$$;
