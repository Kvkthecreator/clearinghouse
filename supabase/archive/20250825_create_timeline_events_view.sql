-- Create timeline_events as a view over events table for schema consistency
-- This aligns with Canon v1.3.1 where timeline_events is the canonical interface

-- The events table should already have workspace_id from 20250817_add_events_table.sql
-- But let's ensure it's backfilled and properly constrained

-- Backfill any missing workspace_id in events table from baskets
UPDATE public.events e
SET workspace_id = b.workspace_id
FROM public.baskets b
WHERE e.workspace_id IS NULL
  AND e.basket_id = b.id;

-- Create timeline_events as a proper table for Canon v1.3.1
-- This provides the canonical timeline interface expected by Canon applications
CREATE TABLE IF NOT EXISTS public.timeline_events (
  id bigserial PRIMARY KEY,
  basket_id uuid NOT NULL REFERENCES public.baskets(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  ts timestamptz DEFAULT now() NOT NULL,
  kind text NOT NULL,
  ref_id uuid,
  preview text,
  payload jsonb DEFAULT '{}'::jsonb
);

-- Migrate existing events data to timeline_events if the table was just created
INSERT INTO public.timeline_events (basket_id, workspace_id, ts, kind, ref_id, preview, payload)
SELECT 
  e.basket_id,
  e.workspace_id,
  e.ts,
  e.kind,
  e.id AS ref_id,
  CASE 
    WHEN e.payload ? 'preview' THEN e.payload->>'preview'
    WHEN e.kind = 'dump' AND e.payload ? 'char_count' THEN 'Added ' || (e.payload->>'char_count') || ' characters'
    WHEN e.kind = 'reflection.computed' THEN 'Computed reflection'
    ELSE e.kind
  END AS preview,
  e.payload
FROM public.events e
LEFT JOIN public.timeline_events te ON te.ref_id = e.id AND te.kind = e.kind
WHERE te.id IS NULL; -- Only insert if not already migrated

-- Create indexes on timeline_events for efficient queries
CREATE INDEX IF NOT EXISTS idx_timeline_events_basket_ts_id
  ON public.timeline_events (basket_id, ts DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_timeline_events_workspace_ts_id
  ON public.timeline_events (workspace_id, ts DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_timeline_events_kind_ref_id
  ON public.timeline_events (kind, ref_id);

-- Add RLS policies for timeline_events
ALTER TABLE public.timeline_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY timeline_events_workspace_members ON public.timeline_events
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM workspace_memberships wm
    WHERE wm.workspace_id = timeline_events.workspace_id
    AND wm.user_id = auth.uid()
  )
);

-- Update emit functions to work with timeline_events interface
CREATE OR REPLACE FUNCTION public.fn_timeline_emit(
  p_basket_id uuid,
  p_kind       text,
  p_ref_id     uuid,
  p_preview    text,
  p_payload    jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  v_id         bigint;
  v_workspace  uuid;
BEGIN
  SELECT workspace_id INTO v_workspace FROM public.baskets WHERE id = p_basket_id;
  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'basket % not found (workspace missing)', p_basket_id;
  END IF;

  -- 1:1 rule for dumps (no dupes per ref_id)
  IF p_kind = 'dump' AND EXISTS (
    SELECT 1 FROM public.timeline_events WHERE kind='dump' AND ref_id=p_ref_id
  ) THEN
    SELECT id INTO v_id FROM public.timeline_events
     WHERE kind='dump' AND ref_id=p_ref_id
     ORDER BY id DESC LIMIT 1;
    RETURN v_id;
  END IF;

  INSERT INTO public.timeline_events (basket_id, workspace_id, ts, kind, ref_id, preview, payload)
  VALUES (p_basket_id, v_workspace, now(), p_kind, p_ref_id, p_preview, p_payload)
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

-- Same function but when you already have a timestamp
CREATE OR REPLACE FUNCTION public.fn_timeline_emit_with_ts(
  p_basket_id uuid,
  p_kind       text,
  p_ref_id     uuid,
  p_preview    text,
  p_ts         timestamptz,
  p_payload    jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  v_id         bigint;
  v_workspace  uuid;
BEGIN
  SELECT workspace_id INTO v_workspace FROM public.baskets WHERE id = p_basket_id;
  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'basket % not found (workspace missing)', p_basket_id;
  END IF;

  IF p_kind = 'dump' AND EXISTS (
    SELECT 1 FROM public.timeline_events WHERE kind='dump' AND ref_id=p_ref_id
  ) THEN
    RETURN (SELECT id FROM public.timeline_events WHERE kind='dump' AND ref_id=p_ref_id ORDER BY id DESC LIMIT 1);
  END IF;

  INSERT INTO public.timeline_events (basket_id, workspace_id, ts, kind, ref_id, preview, payload)
  VALUES (p_basket_id, v_workspace, p_ts, p_kind, p_ref_id, p_preview, p_payload)
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;