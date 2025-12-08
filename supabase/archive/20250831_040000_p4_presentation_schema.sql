-- P4 Presentation Pipeline Schema
-- Implements Sacred Principle #3: "Narrative is Deliberate"
-- Documents = substrate references + authored prose

-- Step 1: Create document composition types
DO $$
BEGIN
  -- Document composition type for P4 operations
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'composition_element') THEN
    CREATE TYPE public.composition_element AS (
      substrate_id uuid,
      substrate_type text,
      order_index integer,
      excerpt text
    );
  END IF;

  -- Narrative section for authored prose
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'narrative_section') THEN
    CREATE TYPE public.narrative_section AS (
      section_id text,
      title text,
      content text,
      order_index integer
    );
  END IF;
END
$$;

-- Step 2: Extend documents table for P4 composition
ALTER TABLE public.documents 
ADD COLUMN IF NOT EXISTS substrate_references jsonb DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS narrative_sections jsonb DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS composition_type text DEFAULT 'substrate_plus_narrative' CHECK (composition_type IN ('substrate_plus_narrative', 'pure_narrative', 'substrate_only')),
ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS pipeline_source text DEFAULT 'P4_PRESENTATION' CHECK (pipeline_source IN ('P4_PRESENTATION', 'LEGACY'));

-- Step 3: Create P4 document composition function
CREATE OR REPLACE FUNCTION public.fn_p4_compose_document(
  p_workspace_id uuid,
  p_basket_id uuid,
  p_title text,
  p_substrate_references jsonb DEFAULT '[]'::jsonb,
  p_narrative_sections jsonb DEFAULT '[]'::jsonb,
  p_author_id uuid DEFAULT auth.uid()
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  document_id uuid;
  ref_element jsonb;
  substrate_exists boolean;
BEGIN
  -- Validate author has workspace access
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships 
    WHERE workspace_id = p_workspace_id AND user_id = p_author_id
  ) THEN
    RAISE EXCEPTION 'User not authorized for workspace';
  END IF;

  -- P4 Constraint: Validate all substrate references exist (consume, never create)
  FOR ref_element IN SELECT jsonb_array_elements(p_substrate_references)
  LOOP
    substrate_exists := false;
    
    -- Check substrate existence based on type (substrate equality)
    CASE ref_element->>'type'
      WHEN 'raw_dump' THEN
        SELECT EXISTS(
          SELECT 1 FROM public.raw_dumps 
          WHERE id = (ref_element->>'id')::uuid 
            AND workspace_id = p_workspace_id
        ) INTO substrate_exists;
        
      WHEN 'context_block' THEN
        SELECT EXISTS(
          SELECT 1 FROM public.context_blocks 
          WHERE id = (ref_element->>'id')::uuid 
            AND workspace_id = p_workspace_id
        ) INTO substrate_exists;
        
      WHEN 'context_item' THEN
        SELECT EXISTS(
          SELECT 1 FROM public.context_items 
          WHERE id = (ref_element->>'id')::uuid 
            AND workspace_id = p_workspace_id
        ) INTO substrate_exists;
        
      WHEN 'timeline_event' THEN
        SELECT EXISTS(
          SELECT 1 FROM public.timeline_events 
          WHERE id = (ref_element->>'id')::uuid 
            AND workspace_id = p_workspace_id
        ) INTO substrate_exists;
        
      WHEN 'reflection' THEN
        SELECT EXISTS(
          SELECT 1 FROM public.reflection_cache 
          WHERE id = (ref_element->>'id')::uuid 
            AND workspace_id = p_workspace_id
        ) INTO substrate_exists;
        
      ELSE
        RAISE EXCEPTION 'Invalid substrate type: %', ref_element->>'type';
    END CASE;
    
    IF NOT substrate_exists THEN
      RAISE EXCEPTION 'Substrate reference not found: % (id: %)', 
        ref_element->>'type', ref_element->>'id';
    END IF;
  END LOOP;

  -- Create composed document
  INSERT INTO public.documents (
    id,
    workspace_id,
    basket_id,
    title,
    content_md,
    document_type,
    substrate_references,
    narrative_sections,
    composition_type,
    created_by,
    pipeline_source,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    p_workspace_id,
    p_basket_id,
    p_title,
    '', -- Will be computed from narrative sections
    'composition',
    p_substrate_references,
    p_narrative_sections,
    CASE 
      WHEN jsonb_array_length(p_substrate_references) = 0 THEN 'pure_narrative'
      WHEN jsonb_array_length(p_narrative_sections) = 0 THEN 'substrate_only'
      ELSE 'substrate_plus_narrative'
    END,
    p_author_id,
    'P4_PRESENTATION',
    now(),
    now()
  ) RETURNING id INTO document_id;

  -- Emit P4 timeline event
  PERFORM public.fn_timeline_emit(
    p_workspace_id,
    p_basket_id,
    'document.composed'::text,
    jsonb_build_object(
      'document_id', document_id,
      'composition_type', CASE 
        WHEN jsonb_array_length(p_substrate_references) = 0 THEN 'pure_narrative'
        WHEN jsonb_array_length(p_narrative_sections) = 0 THEN 'substrate_only'
        ELSE 'substrate_plus_narrative'
      END,
      'pipeline', 'P4_PRESENTATION',
      'substrate_ref_count', jsonb_array_length(p_substrate_references),
      'narrative_section_count', jsonb_array_length(p_narrative_sections)
    ),
    p_author_id
  );

  RETURN document_id;
END;
$$;

-- Step 4: Create P4 document reference addition function
CREATE OR REPLACE FUNCTION public.fn_p4_add_substrate_reference(
  p_document_id uuid,
  p_substrate_id uuid,
  p_substrate_type text,
  p_order_index integer DEFAULT 999,
  p_excerpt text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  doc_workspace_id uuid;
  substrate_exists boolean;
  current_refs jsonb;
  new_ref jsonb;
BEGIN
  -- Get document workspace for validation
  SELECT workspace_id INTO doc_workspace_id
  FROM public.documents
  WHERE id = p_document_id;
  
  IF doc_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Document not found: %', p_document_id;
  END IF;

  -- Validate user has access to document's workspace
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships 
    WHERE workspace_id = doc_workspace_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'User not authorized for document workspace';
  END IF;

  -- P4 Constraint: Validate substrate reference exists (consume, never create)
  substrate_exists := false;
  
  CASE p_substrate_type
    WHEN 'raw_dump' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.raw_dumps 
        WHERE id = p_substrate_id AND workspace_id = doc_workspace_id
      ) INTO substrate_exists;
      
    WHEN 'context_block' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.context_blocks 
        WHERE id = p_substrate_id AND workspace_id = doc_workspace_id
      ) INTO substrate_exists;
      
    WHEN 'context_item' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.context_items 
        WHERE id = p_substrate_id AND workspace_id = doc_workspace_id
      ) INTO substrate_exists;
      
    WHEN 'timeline_event' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.timeline_events 
        WHERE id = p_substrate_id AND workspace_id = doc_workspace_id
      ) INTO substrate_exists;
      
    WHEN 'reflection' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.reflection_cache 
        WHERE id = p_substrate_id AND workspace_id = doc_workspace_id
      ) INTO substrate_exists;
      
    ELSE
      RAISE EXCEPTION 'Invalid substrate type: %', p_substrate_type;
  END CASE;
  
  IF NOT substrate_exists THEN
    RAISE EXCEPTION 'Substrate reference not found: % (id: %)', p_substrate_type, p_substrate_id;
  END IF;

  -- Get current substrate references
  SELECT substrate_references INTO current_refs
  FROM public.documents
  WHERE id = p_document_id;

  -- Create new reference
  new_ref := jsonb_build_object(
    'id', p_substrate_id,
    'type', p_substrate_type,
    'order', p_order_index,
    'excerpt', p_excerpt,
    'added_at', extract(epoch from now())
  );

  -- Add reference to document
  UPDATE public.documents
  SET 
    substrate_references = current_refs || jsonb_build_array(new_ref),
    updated_at = now()
  WHERE id = p_document_id;

  -- Emit P4 timeline event
  PERFORM public.fn_timeline_emit(
    doc_workspace_id,
    (SELECT basket_id FROM public.documents WHERE id = p_document_id),
    'document.reference_added'::text,
    jsonb_build_object(
      'document_id', p_document_id,
      'substrate_reference', new_ref,
      'pipeline', 'P4_PRESENTATION'
    ),
    auth.uid()
  );

  RETURN true;
END;
$$;

-- Step 5: Grant permissions for P4 operations
GRANT EXECUTE ON FUNCTION public.fn_p4_compose_document(uuid, uuid, text, jsonb, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_p4_add_substrate_reference(uuid, uuid, text, integer, text) TO authenticated;

-- Step 6: Create view for document composition analysis
CREATE OR REPLACE VIEW public.document_composition_analysis AS
SELECT 
  d.id,
  d.title,
  d.composition_type,
  d.pipeline_source,
  d.workspace_id,
  d.basket_id,
  d.created_by,
  d.created_at,
  jsonb_array_length(COALESCE(d.substrate_references, '[]'::jsonb)) as substrate_ref_count,
  jsonb_array_length(COALESCE(d.narrative_sections, '[]'::jsonb)) as narrative_section_count,
  CASE 
    WHEN jsonb_array_length(COALESCE(d.substrate_references, '[]'::jsonb)) > 0 
     AND jsonb_array_length(COALESCE(d.narrative_sections, '[]'::jsonb)) > 0 
    THEN true
    ELSE false
  END as implements_sacred_principle_3,
  -- Extract substrate types referenced (substrate equality validation)
  (
    SELECT jsonb_agg(DISTINCT ref->>'type')
    FROM jsonb_array_elements(COALESCE(d.substrate_references, '[]'::jsonb)) as ref
  ) as referenced_substrate_types
FROM public.documents d
WHERE d.pipeline_source = 'P4_PRESENTATION';

-- Step 7: RLS for composition operations
CREATE POLICY "p4_documents_compose" ON public.documents
  FOR ALL USING (
    workspace_id IN (
      SELECT workspace_id FROM public.workspace_memberships 
      WHERE user_id = auth.uid()
    )
  );

-- Completion notification
RAISE NOTICE 'P4 Presentation Pipeline schema complete - Sacred Principle #3 implementation ready';