-- Canon purity: Disable direct substrate writes by default at the schema level
-- This aligns the database default with governance policy and documentation.

-- Set default to FALSE for new workspaces
ALTER TABLE public.workspace_governance_settings
  ALTER COLUMN direct_substrate_writes SET DEFAULT false;

-- Backfill existing rows to FALSE to remove ambiguity
UPDATE public.workspace_governance_settings
SET direct_substrate_writes = false
WHERE direct_substrate_writes IS DISTINCT FROM false;

COMMENT ON COLUMN public.workspace_governance_settings.direct_substrate_writes
  IS 'Canon: direct substrate writes are disabled by default; P0 capture is exempt (raw_dumps only).';

