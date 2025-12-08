-- 20250823_p6_metrics.sql

create table if not exists public.pipeline_metrics (
  id bigserial primary key,
  ts timestamptz not null default now(),
  pipeline text not null,                 -- 'p1' | 'p2' | 'p3' | 'p4'
  basket_id uuid,
  dump_id uuid,
  doc_id uuid,
  dims jsonb not null default '{}'::jsonb, -- arbitrary detail
  counts jsonb not null default '{}'::jsonb -- { created, attached, revised, ignored, edges_created, ... }
);

do $$ begin
  if not exists (select 1 from pg_indexes where indexname='ix_pipeline_metrics_recent') then
    create index ix_pipeline_metrics_recent on public.pipeline_metrics (pipeline, ts desc);
  end if;
  if not exists (select 1 from pg_indexes where indexname='ix_pipeline_metrics_basket') then
    create index ix_pipeline_metrics_basket on public.pipeline_metrics (basket_id, ts desc);
  end if;
end $$;

-- 24h rollup for ops
create or replace view public.v_kpi_24h as
select
  pipeline,
  count(*) as runs,
  jsonb_object_agg(key, sum(value)) as totals
from (
  select pipeline,
         (each(counts)).key,
         ((each(counts)).value)::numeric as value
  from public.pipeline_metrics
  where ts > now() - interval '24 hours'
) s
group by pipeline;

-- per-basket recent summary
create or replace view public.v_kpi_basket_recent as
select basket_id, pipeline, ts, counts, dims
from public.pipeline_metrics
where ts > now() - interval '7 days'
order by ts desc;