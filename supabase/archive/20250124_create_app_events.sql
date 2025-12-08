-- Governed by: /docs/YARNNN_ALERTS_NOTIFICATIONS_CANON.md (v1.0)

-- Create app_events table for unified notification system
create table if not exists app_events (
  id uuid primary key default gen_random_uuid(),
  v int not null default 1,
  type text not null check (type in ('job_update', 'system_alert', 'action_result', 'collab_activity', 'validation')),
  name text not null,
  phase text check (phase in ('started', 'progress', 'succeeded', 'failed')),
  severity text not null default 'info' check (severity in ('info', 'success', 'warning', 'error')),
  message text not null,
  workspace_id uuid not null references workspaces(id),
  basket_id uuid references baskets(id),
  entity_id uuid,
  correlation_id text,
  dedupe_key text,
  ttl_ms int,
  payload jsonb,
  created_at timestamptz not null default now()
);

-- Create indexes for performance
create index if not exists idx_app_events_workspace on app_events(workspace_id, created_at desc);
create index if not exists idx_app_events_dedupe on app_events(dedupe_key) where dedupe_key is not null;
create index if not exists idx_app_events_correlation on app_events(correlation_id) where correlation_id is not null;
create index if not exists idx_app_events_basket on app_events(basket_id, created_at desc) where basket_id is not null;

-- Enable RLS
alter table app_events enable row level security;

-- Policy: Users can read events for their workspaces
create policy "workspace_members_can_read_events" on app_events
  for select
  using (
    exists (
      select 1 from workspace_memberships
      where workspace_memberships.workspace_id = app_events.workspace_id
        and workspace_memberships.user_id = auth.uid()
    )
  );

-- Policy: Service role can insert events
create policy "service_role_can_insert_events" on app_events
  for insert
  with check (auth.role() = 'service_role');

-- Enable realtime for app_events
alter publication supabase_realtime add table app_events;

-- Comment for documentation
comment on table app_events is 'Unified event table for notifications following YARNNN_ALERTS_NOTIFICATIONS_CANON.md';
comment on column app_events.type is 'Event domain: job_update, system_alert, action_result, collab_activity, validation';
comment on column app_events.phase is 'Optional phase for job_update events';
comment on column app_events.severity is 'Event severity level';
comment on column app_events.dedupe_key is 'Optional key for client-side deduplication';
comment on column app_events.ttl_ms is 'Optional time-to-live in milliseconds for UI display';
comment on column app_events.correlation_id is 'Request correlation ID for tracking async operations';