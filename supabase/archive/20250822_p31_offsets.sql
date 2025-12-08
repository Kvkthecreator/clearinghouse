-- 20250822_p31_offsets.sql

-- 1) Generic pipeline offsets (reusable for any consumer)
create table if not exists public.pipeline_offsets (
  pipeline_name text primary key,
  last_event_id uuid,                -- matches public.events.id
  last_event_ts timestamptz,
  updated_at timestamptz not null default now()
);

-- 2) Helpful view for P2→P3 events
create or replace view public.v_events_rel_bulk as
select id, basket_id, kind, payload, ts
from public.events
where kind = 'rel.bulk_upserted'
order by ts asc;

-- 3) Index for fast scans by time
do $$
begin
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='ix_events_kind_ts') then
    execute 'create index ix_events_kind_ts on public.events (kind, ts)';
  end if;
end$$;