BEGIN;

CREATE TABLE IF NOT EXISTS public.basket_mode_configs (
  mode_id text PRIMARY KEY,
  config jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text
);

ALTER TABLE public.basket_mode_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY basket_mode_configs_service_role_full
  ON public.basket_mode_configs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMIT;
