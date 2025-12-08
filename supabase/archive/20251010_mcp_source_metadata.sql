-- 20251010_mcp_source_metadata.sql
-- Track origin host/session for ambient events.

ALTER TABLE public.mcp_unassigned_captures
  ADD COLUMN IF NOT EXISTS source_host text,
  ADD COLUMN IF NOT EXISTS source_session text;

ALTER TABLE public.proposals
  ADD COLUMN IF NOT EXISTS source_host text,
  ADD COLUMN IF NOT EXISTS source_session text;

ALTER TABLE public.timeline_events
  ADD COLUMN IF NOT EXISTS source_host text,
  ADD COLUMN IF NOT EXISTS source_session text;

COMMENT ON COLUMN public.mcp_unassigned_captures.source_host IS 'Origin host of the capture (e.g., claude, chatgpt, web, agent:name)';
COMMENT ON COLUMN public.proposals.source_host IS 'Origin host of the proposal (ambient agent vs human)';
COMMENT ON COLUMN public.timeline_events.source_host IS 'Origin host generating this event';
