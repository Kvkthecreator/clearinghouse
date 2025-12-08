-- 20251009_basket_signatures.sql
-- Create canonical basket signature storage backing MCP basket inference.

CREATE TABLE IF NOT EXISTS public.basket_signatures (
  basket_id uuid PRIMARY KEY REFERENCES public.baskets(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  summary text,
  anchors jsonb DEFAULT '[]'::jsonb,
  entities text[] DEFAULT ARRAY[]::text[],
  keywords text[] DEFAULT ARRAY[]::text[],
  embedding double precision[] DEFAULT ARRAY[]::double precision[],
  last_refreshed timestamptz NOT NULL DEFAULT now(),
  ttl_hours integer NOT NULL DEFAULT 336,
  source_reflection_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_basket_signatures_workspace
  ON public.basket_signatures(workspace_id);

CREATE INDEX IF NOT EXISTS idx_basket_signatures_updated
  ON public.basket_signatures(last_refreshed DESC);

ALTER TABLE public.basket_signatures ENABLE ROW LEVEL SECURITY;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'basket_signatures'
      AND policyname = 'basket_signatures_select'
  ) THEN
    EXECUTE $$CREATE POLICY "basket_signatures_select"
      ON public.basket_signatures
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM workspace_memberships wm
          WHERE wm.workspace_id = basket_signatures.workspace_id
          AND wm.user_id = auth.uid()
        )
      );$$;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'basket_signatures'
      AND policyname = 'basket_signatures_service_insert'
  ) THEN
    EXECUTE $$CREATE POLICY "basket_signatures_service_insert"
      ON public.basket_signatures
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');$$;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'basket_signatures'
      AND policyname = 'basket_signatures_service_update'
  ) THEN
    EXECUTE $$CREATE POLICY "basket_signatures_service_update"
      ON public.basket_signatures
      FOR UPDATE
      USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');$$;
  END IF;
END;
$do$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.basket_signatures TO service_role;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc
    WHERE proname = 'set_updated_at'
  ) THEN
    CREATE FUNCTION public.set_updated_at()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $func$
    BEGIN
      NEW.updated_at := NOW();
      RETURN NEW;
    END;
    $func$;
  END IF;
END;
$do$;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'basket_signatures_set_updated_at'
  ) THEN
    CREATE TRIGGER basket_signatures_set_updated_at
      BEFORE UPDATE ON public.basket_signatures
      FOR EACH ROW
      EXECUTE FUNCTION public.set_updated_at();
  END IF;
END;
$do$;
