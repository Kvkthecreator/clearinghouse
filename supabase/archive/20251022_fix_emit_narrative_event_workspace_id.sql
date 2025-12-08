-- Fix emit_narrative_event to include workspace_id when creating timeline events
-- Issue: timeline_events.workspace_id is NOT NULL but function wasn't setting it

CREATE OR REPLACE FUNCTION public.emit_narrative_event(
  p_basket_id uuid,
  p_doc_id uuid,
  p_kind text,
  p_preview text
)
RETURNS void
LANGUAGE plpgsql
AS $function$
declare
  v_workspace_id uuid;
begin
  -- Get workspace_id from basket
  select workspace_id into v_workspace_id
  from public.baskets
  where id = p_basket_id;

  if v_workspace_id is null then
    raise exception 'Basket % not found or has no workspace', p_basket_id;
  end if;

  -- Insert timeline event with workspace_id
  insert into public.timeline_events (basket_id, workspace_id, kind, ref_id, preview, payload)
  values (
    p_basket_id,
    v_workspace_id,
    'narrative',
    p_doc_id,
    p_preview,
    jsonb_build_object('event', p_kind, 'doc_id', p_doc_id::text)
  );
end;
$function$;

COMMENT ON FUNCTION public.emit_narrative_event IS 'Emits narrative timeline events for document operations. Auto-fetches workspace_id from basket.';
