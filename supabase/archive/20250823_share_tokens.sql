-- Share tokens for secure document exports
create table if not exists public.share_tokens (
  token text primary key,
  basket_id uuid not null references public.baskets(id) on delete cascade,
  doc_id uuid not null references public.documents(id) on delete cascade,
  format text not null check (format in ('markdown', 'html')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  accessed_count int not null default 0,
  last_accessed_at timestamptz
);

-- Index for cleanup and lookups
create index if not exists idx_share_tokens_expires_at on public.share_tokens(expires_at);
create index if not exists idx_share_tokens_basket_doc on public.share_tokens(basket_id, doc_id);

-- RLS policies
alter table public.share_tokens enable row level security;

-- Only allow reading unexpired tokens
create policy "Share tokens can be read if not expired" on public.share_tokens
  for select using (expires_at > now());

-- Only allow inserting tokens for own baskets (assuming user context)
create policy "Share tokens can be created for own baskets" on public.share_tokens
  for insert with check (true); -- Will be refined based on auth context

-- Function to validate and consume share token
create or replace function public.fn_share_token_validate(token_input text)
returns table(
  valid boolean,
  basket_id uuid,
  doc_id uuid,
  format text
) as $$
begin
  -- Update access count and last accessed
  update public.share_tokens 
  set accessed_count = accessed_count + 1,
      last_accessed_at = now()
  where token = token_input 
    and expires_at > now();

  -- Return token info if valid
  return query
  select 
    true as valid,
    st.basket_id,
    st.doc_id,
    st.format
  from public.share_tokens st
  where st.token = token_input 
    and st.expires_at > now();

  -- If no rows, return invalid
  if not found then
    return query select false as valid, null::uuid as basket_id, null::uuid as doc_id, null::text as format;
  end if;
end;
$$ language plpgsql security definer;

-- Function to cleanup expired tokens (run via cron)
create or replace function public.fn_share_tokens_cleanup()
returns int as $$
declare
  deleted_count int;
begin
  delete from public.share_tokens where expires_at < now() - interval '7 days';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$ language plpgsql security definer;