-- 20250822_p3_reflection_cache.sql
-- Add cache metadata to basket_reflections; keep existing rows valid.

alter table if exists public.basket_reflections
  add column if not exists meta_derived_from text,
  add column if not exists meta_refreshable boolean default true;

-- Helpful index for fast cache lookups per basket
do $$
begin
  if not exists (
    select 1 from pg_indexes where schemaname='public' and indexname='ix_basket_reflections_basket_ts'
  ) then
    execute 'create index ix_basket_reflections_basket_ts on public.basket_reflections (basket_id, computed_at desc)';
  end if;
end$$;