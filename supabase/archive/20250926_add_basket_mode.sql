-- Canon: introduce basket modes for productized experiences without touching substrate pipelines
BEGIN;

-- Create enum if absent (idempotent for local refresh)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'basket_mode') THEN
    CREATE TYPE public.basket_mode AS ENUM ('default', 'product_brain', 'campaign_brain');
  END IF;
END
$$;

-- Add column with default; tolerate reruns
ALTER TABLE public.baskets
  ADD COLUMN IF NOT EXISTS mode public.basket_mode NOT NULL DEFAULT 'default';

-- Backfill legacy rows that may have NULL (pre-IF NOT EXISTS runs)
UPDATE public.baskets
   SET mode = 'default'
 WHERE mode IS NULL;

-- Helpful index for dashboards & analytics
CREATE INDEX IF NOT EXISTS baskets_mode_idx ON public.baskets (mode);

COMMIT;
