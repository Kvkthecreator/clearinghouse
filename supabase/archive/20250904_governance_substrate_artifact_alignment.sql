-- Governance Schema v2.0: Align with Pure Substrate Model
-- Update governance to handle only substrate operations, separate artifact generation

BEGIN;

-- =============================================================================
-- UPDATE GOVERNANCE SETTINGS FOR SUBSTRATE/ARTIFACT MODEL
-- =============================================================================

-- Remove reflection suggestion endpoint (reflections are artifacts, not governed substrates)
ALTER TABLE workspace_governance_settings 
  DROP COLUMN IF EXISTS ep_reflection_suggestion;

-- Add artifact generation policies (separate from substrate governance)
ALTER TABLE workspace_governance_settings
  ADD COLUMN IF NOT EXISTS artifact_generation_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS auto_reflection_compute boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS document_versioning_enabled boolean DEFAULT true;

-- =============================================================================
-- UPDATE TIMELINE EVENT TYPES FOR SUBSTRATE/ARTIFACT MODEL
-- =============================================================================

-- Remove reflection from substrate timeline events (now artifact events)
-- Note: timeline_events.kind is text, no enum to update

-- =============================================================================
-- ADD ARTIFACT-SPECIFIC GOVERNANCE (OPTIONAL)
-- =============================================================================

-- Table for artifact generation policies (if needed for future governance)
CREATE TABLE IF NOT EXISTS artifact_generation_settings (
  workspace_id uuid PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
  
  -- Reflection generation policies
  auto_substrate_reflection boolean DEFAULT true,
  auto_document_reflection boolean DEFAULT false,
  reflection_frequency interval DEFAULT '1 hour',
  
  -- Document versioning policies  
  auto_version_on_edit boolean DEFAULT true,
  version_retention_days integer DEFAULT 90,
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- RLS for artifact settings
ALTER TABLE artifact_generation_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "artifact_settings_workspace" ON artifact_generation_settings
  FOR ALL USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_memberships 
      WHERE user_id = auth.uid()
    )
  );

-- =============================================================================
-- CLEAN UP LEGACY GOVERNANCE REFERENCES
-- =============================================================================

-- Update any timeline events that reference governance of reflections
-- (This is data cleanup - timeline events are append-only)

COMMIT;