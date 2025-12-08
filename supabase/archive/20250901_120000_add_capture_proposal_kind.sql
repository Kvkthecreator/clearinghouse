-- Add 'Capture' proposal kind for governance-routed dump creation
-- Critical for capture workflow hardening per Sacred Principle #1

ALTER TYPE public.proposal_kind ADD VALUE IF NOT EXISTS 'Capture';

-- Update comments for clarity
COMMENT ON TYPE public.proposal_kind IS 'Types of governance proposals: Capture (raw dumps), Extraction (P1 substrate), Edit, Merge, Attachment, ScopePromotion, Deprecation, Revision, Detach, Rename, ContextAlias';