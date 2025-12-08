-- Create roles
do $$ begin
  if not exists (select 1 from pg_roles where rolname='substrate_writer') then create role substrate_writer; end if;
  if not exists (select 1 from pg_roles where rolname='graph_writer') then create role graph_writer; end if;
  if not exists (select 1 from pg_roles where rolname='derived_writer') then create role derived_writer; end if;
  if not exists (select 1 from pg_roles where rolname='presentation_writer') then create role presentation_writer; end if;
end $$;

-- Revoke blanket execute on functions from PUBLIC
revoke execute on all functions in schema public from public;

-- Grant per-pipeline RPCs
grant execute on function public.fn_ingest_dumps() to substrate_writer;

grant execute on function public.fn_context_item_upsert_bulk(uuid,uuid,jsonb,text) to substrate_writer;
grant execute on function public.fn_block_create(uuid,text,jsonb,jsonb) to substrate_writer;
grant execute on function public.fn_block_revision_create(uuid,jsonb) to substrate_writer;

grant execute on function public.fn_relationship_upsert_bulk(uuid,jsonb,text) to graph_writer;

grant execute on function public.fn_reflection_cache_upsert(uuid,text,text,text,text) to derived_writer;

grant execute on function public.fn_document_create(uuid,text,text,text,jsonb) to presentation_writer;
grant execute on function public.fn_document_update(uuid,text,text,jsonb) to presentation_writer;
grant execute on function public.fn_document_attach_block(uuid,uuid,int,jsonb) to presentation_writer;
grant execute on function public.fn_document_attach_context_item(uuid,uuid,text,numeric) to presentation_writer;