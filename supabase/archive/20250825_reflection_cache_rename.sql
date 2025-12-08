DO $$
BEGIN
  IF to_regclass('public.basket_reflections') IS NOT NULL
     AND to_regclass('public.reflection_cache') IS NULL THEN
    ALTER TABLE public.basket_reflections RENAME TO reflection_cache;
    CREATE OR REPLACE VIEW public.basket_reflections AS
      SELECT * FROM public.reflection_cache;
    COMMENT ON VIEW public.basket_reflections IS 'DEPRECATED compat view; use reflection_cache.';
  END IF;
END$$;

COMMENT ON COLUMN public.raw_dumps.file_refs IS 'DEPRECATED: drop on 2025-09-23.';
