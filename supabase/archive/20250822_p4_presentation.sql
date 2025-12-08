-- 20250822_p4_presentation.sql

-- 1) Join table: documents ↔ context_items (do not mutate context_items)
create table if not exists public.document_context_items (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  context_item_id uuid not null references public.context_items(id) on delete cascade,
  role text,                       -- optional: 'supporting','mentioned','about'
  weight numeric,                  -- optional scoring
  created_at timestamptz not null default now()
);

-- Uniqueness: same CI should not be attached twice to the same doc
do $$
begin
  if not exists (
    select 1 from pg_indexes where schemaname='public' and indexname='uq_doc_ctx_item'
  ) then
    execute 'create unique index uq_doc_ctx_item on public.document_context_items (document_id, context_item_id)';
  end if;
end$$;

-- Helpful index for block_links if high cardinality (you already have the table)
do $$
begin
  if not exists (
    select 1 from pg_indexes where schemaname='public' and indexname='ix_block_links_doc_block'
  ) then
    execute 'create index ix_block_links_doc_block on public.block_links (document_id, block_id)';
  end if;
end$$;

-- 2) (Soft) discourage direct narrative table writes:
-- Create a convenience view that surfaces documents of type 'narrative'
create or replace view public.v_narrative_documents as
select d.*
from public.documents d
where d.document_type = 'narrative';

comment on view public.v_narrative_documents is
  'Preferred read path for narrative content (documents.document_type=''narrative''). Avoid writing to legacy public.narrative table in new flows.';

-- 3) Timeline convenience function for narrative events
create or replace function public.emit_narrative_event(
  p_basket_id uuid,
  p_doc_id uuid,
  p_kind text,          -- 'doc.created' | 'doc.updated'
  p_preview text
) returns void language plpgsql as $$
begin
  -- Constrained kinds allow 'narrative' (use as channel); encode p_kind in payload
  insert into public.timeline_events (basket_id, kind, ref_id, preview, payload)
  values (
    p_basket_id, 'narrative', p_doc_id, p_preview,
    jsonb_build_object('event', p_kind, 'doc_id', p_doc_id::text)
  );
end$$;