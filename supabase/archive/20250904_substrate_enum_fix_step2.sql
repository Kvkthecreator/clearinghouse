-- Step 2: Update substrate_type enum to pure substrates only

BEGIN;

-- Create new enum without reflection  
CREATE TYPE substrate_type_v2 AS ENUM (
  'block',           -- context_blocks
  'dump',            -- raw_dumps
  'context_item',    -- context_items
  'timeline_event'   -- timeline_events
);

-- Update substrate_references table to use new enum
ALTER TABLE substrate_references 
  ALTER COLUMN substrate_type TYPE substrate_type_v2
  USING substrate_type::text::substrate_type_v2;

-- Drop old enum and rename new one
DROP TYPE substrate_type;
ALTER TYPE substrate_type_v2 RENAME TO substrate_type;

-- Recreate the composition stats view (without reflections)
CREATE VIEW document_composition_stats AS
 SELECT substrate_references.document_id,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'block') AS blocks_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'dump') AS dumps_count, 
    count(*) FILTER (WHERE substrate_references.substrate_type = 'context_item') AS context_items_count,
    count(*) FILTER (WHERE substrate_references.substrate_type = 'timeline_event') AS timeline_events_count,
    count(*) AS total_substrate_references
   FROM substrate_references
  GROUP BY substrate_references.document_id;

-- Recreate the functions with clean substrate enum
CREATE OR REPLACE FUNCTION fn_document_attach_substrate(
  p_document_id uuid,
  p_substrate_type substrate_type,
  p_substrate_id uuid,
  p_role text DEFAULT NULL,
  p_weight numeric DEFAULT NULL,
  p_snippets jsonb DEFAULT '[]',
  p_metadata jsonb DEFAULT '{}'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reference_id uuid;
  v_workspace_id uuid;
BEGIN
  -- Get document workspace
  SELECT d.workspace_id INTO v_workspace_id
  FROM documents d WHERE d.id = p_document_id;
  
  -- Insert or update reference
  INSERT INTO substrate_references (
    document_id,
    substrate_type, 
    substrate_id,
    role,
    weight,
    snippets,
    metadata,
    created_by
  ) VALUES (
    p_document_id,
    p_substrate_type,
    p_substrate_id,
    p_role,
    p_weight,
    p_snippets,
    p_metadata,
    auth.uid()
  ) ON CONFLICT (document_id, substrate_type, substrate_id) 
  DO UPDATE SET
    role = EXCLUDED.role,
    weight = EXCLUDED.weight,
    snippets = EXCLUDED.snippets,
    metadata = EXCLUDED.metadata
  RETURNING id INTO v_reference_id;
  
  -- Emit timeline event
  PERFORM fn_timeline_emit(
    (SELECT basket_id FROM documents WHERE id = p_document_id),
    'document.' || p_substrate_type || '.attached',
    v_reference_id,
    'Attached ' || p_substrate_type || ' to document',
    jsonb_build_object('substrate_id', p_substrate_id, 'substrate_type', p_substrate_type)
  );
  
  RETURN v_reference_id;
END $$;

CREATE OR REPLACE FUNCTION fn_document_detach_substrate(
  p_document_id uuid,
  p_substrate_type substrate_type,
  p_substrate_id uuid
) RETURNS boolean
LANGUAGE plpgsql  
SECURITY DEFINER
AS $$
DECLARE
  v_deleted_count int;
BEGIN
  -- Delete the reference
  DELETE FROM substrate_references
  WHERE document_id = p_document_id
    AND substrate_type = p_substrate_type
    AND substrate_id = p_substrate_id;
    
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  IF v_deleted_count > 0 THEN
    -- Emit timeline event
    PERFORM fn_timeline_emit(
      (SELECT basket_id FROM documents WHERE id = p_document_id),
      'document.' || p_substrate_type || '.detached',
      p_substrate_id,
      'Detached ' || p_substrate_type || ' from document',
      jsonb_build_object('substrate_id', p_substrate_id, 'substrate_type', p_substrate_type)
    );
    
    RETURN true;
  END IF;
  
  RETURN false;
END $$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION fn_document_attach_substrate(uuid, substrate_type, uuid, text, numeric, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_document_detach_substrate(uuid, substrate_type, uuid) TO authenticated;

COMMIT;