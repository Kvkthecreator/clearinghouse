-- 20251011_mcp_activity_logs.sql
-- Capture ambient MCP tool executions for observability and analytics.

create table if not exists public.mcp_activity_logs (
  id uuid primary key default uuid_generate_v4(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  tool text not null,
  host text not null,
  result text not null,
  latency_ms integer,
  basket_id uuid references public.baskets(id) on delete set null,
  selection_decision text,
  selection_score numeric,
  error_code text,
  session_id text,
  fingerprint_summary text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

comment on table public.mcp_activity_logs is 'Raw log of MCP tool executions per workspace.';
comment on column public.mcp_activity_logs.host is 'Origin host (claude, chatgpt, agent:<name>, etc.)';
comment on column public.mcp_activity_logs.result is 'success | queued | error';
comment on column public.mcp_activity_logs.metadata is 'Optional structured payload for debugging (input sizes, confidence breakdown).';

create index if not exists idx_mcp_activity_workspace
  on public.mcp_activity_logs(workspace_id, created_at desc);

create index if not exists idx_mcp_activity_host
  on public.mcp_activity_logs(host, created_at desc);

create index if not exists idx_mcp_activity_result
  on public.mcp_activity_logs(result);

alter table public.mcp_activity_logs enable row level security;

create policy "mcp_activity_select"
  on public.mcp_activity_logs
  for select
  using (
    exists (
      select 1 from workspace_memberships wm
      where wm.workspace_id = mcp_activity_logs.workspace_id
        and wm.user_id = auth.uid()
    )
  );

create policy "mcp_activity_service_insert"
  on public.mcp_activity_logs
  for insert
  with check (auth.role() = 'service_role');

create policy "mcp_activity_service_delete"
  on public.mcp_activity_logs
  for delete
  using (auth.role() = 'service_role');

grant select, insert, delete on public.mcp_activity_logs to service_role;

-- View summarising recent host activity for dashboards.
create or replace view public.mcp_activity_host_recent as
  select
    workspace_id,
    host,
    max(created_at) as last_seen_at,
    count(*) filter (where created_at >= now() - interval '1 hour') as calls_last_hour,
    count(*) filter (where result = 'error' and created_at >= now() - interval '1 hour') as errors_last_hour,
    percentile_cont(0.95) within group (order by coalesce(latency_ms, 0)) as p95_latency_ms
  from public.mcp_activity_logs
  where created_at >= now() - interval '7 days'
  group by workspace_id, host;

comment on view public.mcp_activity_host_recent is 'Aggregated view of recent MCP activity per host used by dashboard widgets.';

