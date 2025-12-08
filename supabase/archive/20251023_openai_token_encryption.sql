-- Add encrypted token storage for OpenAI app installs

alter table public.openai_app_tokens
  alter column access_token drop not null,
  alter column access_token type text,
  alter column refresh_token type text;

alter table public.openai_app_tokens
  add column if not exists access_token_enc jsonb,
  add column if not exists refresh_token_enc jsonb,
  add column if not exists encryption_version smallint,
  add column if not exists encryption_updated_at timestamptz,
  add column if not exists rotated_at timestamptz;

comment on column public.openai_app_tokens.access_token_enc is 'AES-GCM encrypted access token payload';
comment on column public.openai_app_tokens.refresh_token_enc is 'AES-GCM encrypted refresh token payload';
comment on column public.openai_app_tokens.encryption_version is 'Encryption scheme version for stored tokens';
comment on column public.openai_app_tokens.encryption_updated_at is 'Timestamp when encrypted tokens were last updated';
comment on column public.openai_app_tokens.rotated_at is 'Timestamp when refresh rotation last occurred';
