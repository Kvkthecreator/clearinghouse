-- 20251010_mcp_unassigned_captures.sql
-- Track low-confidence MCP captures awaiting user review.

create table if not exists public.mcp_unassigned_captures (
  id uuid primary key default uuid_generate_v4(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  requested_by uuid references auth.users(id) on delete set null,
  tool text not null,
  summary text,
  payload jsonb,
  fingerprint jsonb,
  candidates jsonb,
  status text not null default 'pending',
  assigned_basket_id uuid references public.baskets(id),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_mcp_unassigned_workspace
  on public.mcp_unassigned_captures(workspace_id);

create index if not exists idx_mcp_unassigned_status
  on public.mcp_unassigned_captures(status);

alter table public.mcp_unassigned_captures enable row level security;

create policy "mcp_unassigned_select"
  on public.mcp_unassigned_captures
  for select
  using (
    exists (
      select 1 from workspace_memberships wm
      where wm.workspace_id = mcp_unassigned_captures.workspace_id
        and wm.user_id = auth.uid()
    )
  );

create policy "mcp_unassigned_update"
  on public.mcp_unassigned_captures
  for update
  using (
    exists (
      select 1 from workspace_memberships wm
      where wm.workspace_id = mcp_unassigned_captures.workspace_id
        and wm.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from workspace_memberships wm
      where wm.workspace_id = mcp_unassigned_captures.workspace_id
        and wm.user_id = auth.uid()
    )
  );

create policy "mcp_unassigned_service_insert"
  on public.mcp_unassigned_captures
  for insert
  with check (auth.role() = 'service_role');

create policy "mcp_unassigned_service_delete"
  on public.mcp_unassigned_captures
  for delete
  using (auth.role() = 'service_role');

grant select, insert, update, delete on public.mcp_unassigned_captures to service_role;

create trigger mcp_unassigned_set_updated_at
  before update on public.mcp_unassigned_captures
  for each row execute function public.set_updated_at();
