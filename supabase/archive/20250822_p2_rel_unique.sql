-- 20250822_p2_rel_unique.sql
-- Enforce uniqueness per directed, typed edge.

do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='uq_substrate_rel_directed'
  ) then
    execute '
      create unique index uq_substrate_rel_directed
      on public.substrate_relationships (basket_id, from_type, from_id, relationship_type, to_type, to_id)
    ';
  end if;
end$$;