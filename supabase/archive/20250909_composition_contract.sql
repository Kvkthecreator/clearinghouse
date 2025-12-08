-- Composition contract & signature on versions; index for doc metadata signature

ALTER TABLE IF EXISTS public.document_versions
  ADD COLUMN IF NOT EXISTS composition_contract jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS composition_signature varchar(64);

-- Partial unique per document to prevent duplicate signatures per doc
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_doc_version_signature'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX uq_doc_version_signature ON public.document_versions (document_id, composition_signature) WHERE composition_signature IS NOT NULL';
  END IF;
END $$;

-- Speed up signature lookups on versions
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_doc_versions_signature'
  ) THEN
    EXECUTE 'CREATE INDEX idx_doc_versions_signature ON public.document_versions (composition_signature) WHERE composition_signature IS NOT NULL';
  END IF;
END $$;

-- Index the documents metadata signature for dedup checks
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_documents_meta_comp_sig'
  ) THEN
    EXECUTE 'CREATE INDEX idx_documents_meta_comp_sig ON public.documents ((metadata->>''composition_signature''))';
  END IF;
END $$;

