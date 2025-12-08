-- 20251010_openai_app_tokens.sql
-- Store OAuth tokens issued by OpenAI Apps installations (ChatGPT).

create table if not exists public.openai_app_tokens (
  id uuid primary key default uuid_generate_v4(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  install_id text,
  access_token text not null,
  refresh_token text,
  expires_at timestamptz,
  scope text,
  provider_metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_openai_app_tokens_workspace
  on public.openai_app_tokens(workspace_id);

create index if not exists idx_openai_app_tokens_expires
  on public.openai_app_tokens(expires_at);

alter table public.openai_app_tokens enable row level security;

create policy "openai_app_tokens_service_access"
  on public.openai_app_tokens
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

grant select, insert, update, delete
  on public.openai_app_tokens
  to service_role;

create trigger openai_app_tokens_set_updated_at
  before update on public.openai_app_tokens
  for each row execute function public.set_updated_at();
