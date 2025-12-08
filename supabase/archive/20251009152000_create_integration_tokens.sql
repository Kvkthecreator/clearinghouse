create table if not exists public.integration_tokens (
    id uuid primary key default uuid_generate_v4(),
    token_hash text not null unique,
    user_id uuid not null references auth.users (id) on delete cascade,
    workspace_id uuid not null references public.workspaces (id) on delete cascade,
    description text,
    created_at timestamptz not null default now(),
    revoked_at timestamptz,
    last_used_at timestamptz
);

create index if not exists integration_tokens_user_id_idx on public.integration_tokens (user_id);
create index if not exists integration_tokens_workspace_id_idx on public.integration_tokens (workspace_id);
