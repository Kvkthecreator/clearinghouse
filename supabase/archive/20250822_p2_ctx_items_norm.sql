-- 20250822_p2_ctx_items_norm.sql
-- Align context_items with graph canon while respecting existing schema.

-- 1) Add normalized_label + origin_ref + equivalence_class (nullable, non-breaking)
alter table if exists public.context_items
  add column if not exists normalized_label text,
  add column if not exists origin_ref jsonb,
  add column if not exists equivalence_class uuid;

-- 2) Optional partial unique to reduce drift within a basket per type+label
do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='uq_ctx_items_norm_label_by_type'
  ) then
    execute '
      create unique index uq_ctx_items_norm_label_by_type
      on public.context_items (basket_id, type, normalized_label)
      where normalized_label is not null
    ';
  end if;
end$$;

-- 3) Normalizer helper (safe to re-create)
create or replace function public.normalize_label(p_label text)
returns text language sql immutable as $$
  select case
           when p_label is null then null
           else lower(regexp_replace(p_label, '\s+', ' ', 'g'))
         end
$$;