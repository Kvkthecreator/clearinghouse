-- Migration: Create generic substrate_references table for Canon v1.3.1 compliance
-- This replaces the block-only composition model with generic substrate composition

BEGIN;

-- Create enum for substrate types
CREATE TYPE substrate_type AS ENUM (
  'block',           -- context_blocks
  'dump',            -- raw_dumps
  'context_item',    -- context_items
  'reflection',      -- reflections (from cache)
  'timeline_event'   -- timeline_events
);

-- Create generic substrate_references table
CREATE TABLE substrate_references (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  substrate_type substrate_type NOT NULL,
  substrate_id uuid NOT NULL,
  role text,                    -- e.g., "primary", "supporting", "citation"
  weight numeric(3,2) CHECK (weight >= 0 AND weight <= 1),
  snippets jsonb DEFAULT '[]'::jsonb,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now() NOT NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- Ensure unique substrate per document
  UNIQUE(document_id, substrate_type, substrate_id)
);

-- Create indexes for efficient querying
CREATE INDEX idx_substrate_references_document ON substrate_references(document_id);
CREATE INDEX idx_substrate_references_type ON substrate_references(substrate_type);
CREATE INDEX idx_substrate_references_substrate ON substrate_references(substrate_id);
CREATE INDEX idx_substrate_references_role ON substrate_references(role) WHERE role IS NOT NULL;
CREATE INDEX idx_substrate_references_created ON substrate_references(created_at);

-- Enable RLS
ALTER TABLE substrate_references ENABLE ROW LEVEL SECURITY;

-- RLS policies (workspace-scoped via document's basket)
CREATE POLICY "substrate_references_select_policy" ON substrate_references
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      WHERE d.id = substrate_references.document_id
      AND (b.visibility = 'public' OR b.user_id = auth.uid())
    )
  );

CREATE POLICY "substrate_references_insert_policy" ON substrate_references
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      WHERE d.id = substrate_references.document_id
      AND b.user_id = auth.uid()
    )
  );

CREATE POLICY "substrate_references_update_policy" ON substrate_references
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      WHERE d.id = substrate_references.document_id
      AND b.user_id = auth.uid()
    )
  );

CREATE POLICY "substrate_references_delete_policy" ON substrate_references
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM documents d
      JOIN baskets b ON d.basket_id = b.id
      WHERE d.id = substrate_references.document_id
      AND b.user_id = auth.uid()
    )
  );

-- Migrate existing block_links data to substrate_references
INSERT INTO substrate_references (
  id,
  document_id,
  substrate_type,
  substrate_id,
  role,
  weight,
  snippets,
  metadata,
  created_at
)
SELECT 
  id,
  document_id,
  'block'::substrate_type,
  block_id,
  'primary',  -- Default role for migrated blocks
  NULL,       -- No weight in old schema
  COALESCE(snippets, '[]'::jsonb),
  '{"migrated_from": "block_links"}'::jsonb,
  created_at
FROM block_links;

-- Generic attachment function for any substrate type
CREATE OR REPLACE FUNCTION fn_document_attach_substrate(
  p_document_id uuid,
  p_substrate_type substrate_type,
  p_substrate_id uuid,
  p_role text DEFAULT NULL,
  p_weight numeric DEFAULT NULL,
  p_snippets jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_basket uuid;
  v_event_kind text;
BEGIN
  -- Validate substrate exists based on type (using actual table names)
  CASE p_substrate_type
    WHEN 'block' THEN
      IF NOT EXISTS (SELECT 1 FROM blocks WHERE id = p_substrate_id) THEN
        RAISE EXCEPTION 'Block % not found', p_substrate_id;
      END IF;
    WHEN 'dump' THEN
      IF NOT EXISTS (SELECT 1 FROM raw_dumps WHERE id = p_substrate_id) THEN
        RAISE EXCEPTION 'Dump % not found', p_substrate_id;
      END IF;
    WHEN 'context_item' THEN
      IF NOT EXISTS (SELECT 1 FROM context_items WHERE id = p_substrate_id) THEN
        RAISE EXCEPTION 'Context item % not found', p_substrate_id;
      END IF;
    WHEN 'reflection' THEN
      IF NOT EXISTS (SELECT 1 FROM reflection_cache WHERE id = p_substrate_id) THEN
        RAISE EXCEPTION 'Reflection % not found', p_substrate_id;
      END IF;
    WHEN 'timeline_event' THEN
      IF NOT EXISTS (SELECT 1 FROM timeline_events WHERE id = p_substrate_id) THEN
        RAISE EXCEPTION 'Timeline event % not found', p_substrate_id;
      END IF;
  END CASE;

  -- Check if reference already exists
  SELECT id INTO v_id FROM substrate_references
  WHERE document_id = p_document_id 
    AND substrate_type = p_substrate_type 
    AND substrate_id = p_substrate_id;

  IF v_id IS NULL THEN
    -- Insert new reference
    INSERT INTO substrate_references (
      document_id, substrate_type, substrate_id, role, weight, snippets, metadata, created_by
    )
    VALUES (
      p_document_id, p_substrate_type, p_substrate_id, p_role, p_weight, p_snippets, p_metadata, auth.uid()
    )
    RETURNING id INTO v_id;
  ELSE
    -- Update existing reference
    UPDATE substrate_references
    SET 
      role = COALESCE(p_role, role),
      weight = COALESCE(p_weight, weight),
      snippets = p_snippets,
      metadata = p_metadata || metadata  -- Merge metadata
    WHERE id = v_id;
  END IF;

  -- Emit timeline event
  SELECT basket_id INTO v_basket FROM documents WHERE id = p_document_id;
  v_event_kind := 'document.' || p_substrate_type || '.attached';
  
  PERFORM fn_timeline_emit(
    v_basket,
    v_event_kind,
    p_document_id,
    'Substrate ' || p_substrate_type || ' attached to document',
    jsonb_build_object(
      'document_id', p_document_id,
      'substrate_type', p_substrate_type,
      'substrate_id', p_substrate_id,
      'reference_id', v_id
    )
  );

  RETURN v_id;
END;
$$;

-- Detachment function
CREATE OR REPLACE FUNCTION fn_document_detach_substrate(
  p_document_id uuid,
  p_substrate_type substrate_type,
  p_substrate_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_basket uuid;
  v_event_kind text;
BEGIN
  -- Delete the reference
  DELETE FROM substrate_references
  WHERE document_id = p_document_id 
    AND substrate_type = p_substrate_type 
    AND substrate_id = p_substrate_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Emit timeline event
  SELECT basket_id INTO v_basket FROM documents WHERE id = p_document_id;
  v_event_kind := 'document.' || p_substrate_type || '.detached';
  
  PERFORM fn_timeline_emit(
    v_basket,
    v_event_kind,
    p_document_id,
    'Substrate ' || p_substrate_type || ' detached from document',
    jsonb_build_object(
      'document_id', p_document_id,
      'substrate_type', p_substrate_type,
      'substrate_id', p_substrate_id
    )
  );

  RETURN true;
END;
$$;

-- Helper view for document composition stats
CREATE VIEW document_composition_stats AS
SELECT 
  document_id,
  COUNT(*) FILTER (WHERE substrate_type = 'block') AS blocks_count,
  COUNT(*) FILTER (WHERE substrate_type = 'dump') AS dumps_count,
  COUNT(*) FILTER (WHERE substrate_type = 'context_item') AS context_items_count,
  COUNT(*) FILTER (WHERE substrate_type = 'reflection') AS reflections_count,
  COUNT(*) FILTER (WHERE substrate_type = 'timeline_event') AS timeline_events_count,
  COUNT(*) AS total_references
FROM substrate_references
GROUP BY document_id;

-- Grant permissions
GRANT SELECT ON substrate_references TO authenticated;
GRANT INSERT, UPDATE, DELETE ON substrate_references TO authenticated;
GRANT SELECT ON document_composition_stats TO authenticated;

-- Add comment for documentation
COMMENT ON TABLE substrate_references IS 'Generic substrate reference system for Canon v1.3.1 - documents compose all substrate types as peers';

COMMIT;