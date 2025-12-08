-- Migration: Document Impact Tracking for Artifact Management
-- Canon v2.0: Pure substrate governance + separate artifact impact management
-- Date: 2025-09-05

-- Create enums for document impact system
CREATE TYPE document_impact_type AS ENUM (
  'content_drift',      -- Referenced substrate content changed
  'new_references',     -- New substrates available for inclusion  
  'reference_removed',  -- Referenced substrate was deleted
  'structural_change'   -- Major substrate reorganization
);

CREATE TYPE document_impact_status AS ENUM (
  'pending',           -- Awaiting user decision
  'auto_applied',      -- Automatically updated (high confidence)
  'user_approved',     -- User chose to update
  'user_deferred',     -- User chose to handle later
  'user_skipped',      -- User chose to skip permanently
  'resolved'           -- Action completed
);

CREATE TYPE proposed_action_type AS ENUM (
  'recompose',         -- Full document recomposition
  'add_references',    -- Add new substrate references
  'update_references', -- Update existing references
  'version_snapshot'   -- Create version lock before changes
);

-- Document impacts table: tracks artifact impacts from substrate changes
CREATE TABLE document_impacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Links to the substrate change that caused this impact
  substrate_commit_id uuid NOT NULL,
  
  -- Affected document
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  
  -- Impact analysis
  impact_type document_impact_type NOT NULL,
  affected_references jsonb NOT NULL DEFAULT '[]', -- Array of SubstrateReference objects
  confidence_score decimal(3,2) NOT NULL DEFAULT 0.70,
  impact_summary text NOT NULL,
  
  -- Proposed action
  proposed_action_type proposed_action_type NOT NULL,
  proposed_action_details jsonb NOT NULL DEFAULT '{}', -- ProposedDocumentAction object
  
  -- User decision tracking
  status document_impact_status NOT NULL DEFAULT 'pending',
  user_choice jsonb, -- Stores user's decision details
  user_notes text,
  
  -- Resolution tracking
  resolved_by uuid REFERENCES auth.users(id),
  resolved_at timestamptz,
  
  -- Audit trail
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for efficient querying
CREATE INDEX idx_document_impacts_workspace ON document_impacts(workspace_id);
CREATE INDEX idx_document_impacts_document ON document_impacts(document_id);
CREATE INDEX idx_document_impacts_status ON document_impacts(status);
CREATE INDEX idx_document_impacts_commit ON document_impacts(substrate_commit_id);
CREATE INDEX idx_document_impacts_created_at ON document_impacts(created_at DESC);

-- RLS policies for workspace isolation
ALTER TABLE document_impacts ENABLE ROW LEVEL SECURITY;

-- Users can only see impacts in workspaces they belong to
CREATE POLICY "document_impacts_workspace_isolation" ON document_impacts
  FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id 
      FROM workspace_memberships 
      WHERE user_id = auth.uid()
    )
  );

-- Document impact batches: group related impacts for batch processing
CREATE TABLE document_impact_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  
  -- Batch metadata
  batch_name text NOT NULL, -- e.g., "Substrate changes from proposal #123"
  substrate_commit_id uuid NOT NULL,
  total_impacts integer NOT NULL DEFAULT 0,
  
  -- Batch status
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
  
  -- Batch processing stats
  auto_applied_count integer NOT NULL DEFAULT 0,
  user_approved_count integer NOT NULL DEFAULT 0,
  user_skipped_count integer NOT NULL DEFAULT 0,
  
  -- Audit trail
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

-- Indexes for batch management
CREATE INDEX idx_document_impact_batches_workspace ON document_impact_batches(workspace_id);
CREATE INDEX idx_document_impact_batches_status ON document_impact_batches(status);
CREATE INDEX idx_document_impact_batches_commit ON document_impact_batches(substrate_commit_id);

-- RLS for batch isolation
ALTER TABLE document_impact_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "document_impact_batches_workspace_isolation" ON document_impact_batches
  FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id 
      FROM workspace_memberships 
      WHERE user_id = auth.uid()
    )
  );

-- Link impacts to batches
ALTER TABLE document_impacts ADD COLUMN batch_id uuid REFERENCES document_impact_batches(id) ON DELETE SET NULL;
CREATE INDEX idx_document_impacts_batch ON document_impacts(batch_id);

-- Function: Create document impact batch from substrate commit
CREATE OR REPLACE FUNCTION create_document_impact_batch(
  p_workspace_id uuid,
  p_substrate_commit_id uuid,
  p_batch_name text,
  p_created_by uuid
) RETURNS uuid AS $$
DECLARE
  batch_id uuid;
BEGIN
  -- Create the batch
  INSERT INTO document_impact_batches (
    workspace_id,
    substrate_commit_id, 
    batch_name,
    created_by
  ) VALUES (
    p_workspace_id,
    p_substrate_commit_id,
    p_batch_name,
    p_created_by
  ) RETURNING id INTO batch_id;
  
  RETURN batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Update batch statistics
CREATE OR REPLACE FUNCTION update_batch_stats(p_batch_id uuid) RETURNS void AS $$
BEGIN
  UPDATE document_impact_batches 
  SET 
    total_impacts = (
      SELECT COUNT(*) 
      FROM document_impacts 
      WHERE batch_id = p_batch_id
    ),
    auto_applied_count = (
      SELECT COUNT(*) 
      FROM document_impacts 
      WHERE batch_id = p_batch_id AND status = 'auto_applied'
    ),
    user_approved_count = (
      SELECT COUNT(*) 
      FROM document_impacts 
      WHERE batch_id = p_batch_id AND status = 'user_approved'  
    ),
    user_skipped_count = (
      SELECT COUNT(*) 
      FROM document_impacts 
      WHERE batch_id = p_batch_id AND status = 'user_skipped'
    ),
    updated_at = now()
  WHERE id = p_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Update batch stats when impact status changes
CREATE OR REPLACE FUNCTION trigger_update_batch_stats() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.batch_id IS NOT NULL THEN
    PERFORM update_batch_stats(NEW.batch_id);
  END IF;
  
  IF OLD.batch_id IS NOT NULL AND OLD.batch_id != COALESCE(NEW.batch_id, '00000000-0000-0000-0000-000000000000'::uuid) THEN
    PERFORM update_batch_stats(OLD.batch_id);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER document_impacts_update_batch_stats
  AFTER INSERT OR UPDATE OR DELETE ON document_impacts
  FOR EACH ROW EXECUTE FUNCTION trigger_update_batch_stats();

-- View: Document impact summary for UI
CREATE VIEW document_impact_summary AS
SELECT 
  di.id,
  di.document_id,
  d.title as document_title,
  di.workspace_id,
  di.impact_type,
  di.confidence_score,
  di.impact_summary,
  di.proposed_action_type,
  di.status,
  di.created_at,
  di.batch_id,
  dib.batch_name,
  jsonb_array_length(di.affected_references) as affected_references_count,
  CASE 
    WHEN di.confidence_score > 0.8 THEN 'high'
    WHEN di.confidence_score > 0.6 THEN 'medium'
    ELSE 'low'
  END as confidence_level
FROM document_impacts di
JOIN documents d ON di.document_id = d.id
LEFT JOIN document_impact_batches dib ON di.batch_id = dib.id;

-- Grant access to service role for background processing
GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Comments for documentation
COMMENT ON TABLE document_impacts IS 'Tracks document impacts from substrate changes - Canon v2.0 artifact management';
COMMENT ON TABLE document_impact_batches IS 'Groups related document impacts for batch processing';
COMMENT ON VIEW document_impact_summary IS 'Denormalized view for efficient UI queries';

-- Migration complete
-- This enables the two-tier system: pure substrate governance + separate artifact impact management