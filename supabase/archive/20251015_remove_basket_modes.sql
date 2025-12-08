-- Remove basket mode enum, configs table, and column
BEGIN;

-- Drop index and column on baskets
DROP INDEX IF EXISTS public.baskets_mode_idx;
ALTER TABLE public.baskets
  DROP COLUMN IF EXISTS mode;

-- Drop mode configuration table
DROP TABLE IF EXISTS public.basket_mode_configs;

-- Drop enum type
DROP TYPE IF EXISTS public.basket_mode;

COMMIT;
