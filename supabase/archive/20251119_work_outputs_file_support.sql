-- Migration: Add file output support to work_outputs table
-- Date: 2025-11-19
-- Purpose: Enable work_outputs to store file-based deliverables (PDF, XLSX, DOCX, PPTX)
--          generated via Claude Agent SDK Skills

-- PART 1: Update work_outputs to use work_ticket_id (Phase 2e alignment)
-- ========================================================================

-- Rename work_session_id → work_ticket_id
ALTER TABLE public.work_outputs
  RENAME COLUMN work_session_id TO work_ticket_id;

-- Update foreign key constraint
ALTER TABLE public.work_outputs
  DROP CONSTRAINT IF EXISTS work_outputs_work_session_id_fkey,
  ADD CONSTRAINT work_outputs_work_ticket_id_fkey
    FOREIGN KEY (work_ticket_id)
    REFERENCES public.work_tickets(id)
    ON DELETE CASCADE;

COMMENT ON COLUMN public.work_outputs.work_ticket_id IS
  'References work_tickets table (Phase 2e architecture)';


-- PART 2: Add file output support fields
-- ========================================================================

-- Change body from JSONB to TEXT (for text outputs) and make nullable
ALTER TABLE public.work_outputs
  ALTER COLUMN body TYPE TEXT USING body::TEXT,
  ALTER COLUMN body DROP NOT NULL;

COMMENT ON COLUMN public.work_outputs.body IS
  'Text content for text-based outputs. NULL if file_id is set. Mutually exclusive with file_id.';

-- Add file-related columns
ALTER TABLE public.work_outputs
  ADD COLUMN file_id TEXT,
  ADD COLUMN file_format TEXT,
  ADD COLUMN file_size_bytes INTEGER,
  ADD COLUMN mime_type TEXT,
  ADD COLUMN storage_path TEXT;

COMMENT ON COLUMN public.work_outputs.file_id IS
  'Claude Files API identifier (e.g., file_011CNha...). Retrieved via client.beta.files.download(file_id).';

COMMENT ON COLUMN public.work_outputs.file_format IS
  'File extension: pdf, xlsx, docx, pptx, png, csv, etc. Corresponds to skill_id used.';

COMMENT ON COLUMN public.work_outputs.file_size_bytes IS
  'File size in bytes. Retrieved from client.beta.files.retrieve_metadata(file_id).size_bytes';

COMMENT ON COLUMN public.work_outputs.mime_type IS
  'MIME type: application/pdf, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, etc.';

COMMENT ON COLUMN public.work_outputs.storage_path IS
  'Supabase Storage path if file is persisted locally. Format: baskets/{basket_id}/work_outputs/{work_ticket_id}/{filename}';

-- Add provenance tracking columns
ALTER TABLE public.work_outputs
  ADD COLUMN generation_method TEXT DEFAULT 'text',
  ADD COLUMN skill_metadata JSONB;

COMMENT ON COLUMN public.work_outputs.generation_method IS
  'How the output was created: text (standard text), code_execution (via code tool), skill (via Agent Skill), manual (user upload)';

COMMENT ON COLUMN public.work_outputs.skill_metadata IS
  'Skill-specific provenance: {skill_id, skill_name, container_id, execution_time_ms, skill_version, code_executed}';

-- Add constraint: body XOR file_id (mutually exclusive)
ALTER TABLE public.work_outputs
  ADD CONSTRAINT work_outputs_content_type CHECK (
    (body IS NOT NULL AND file_id IS NULL) OR
    (body IS NULL AND file_id IS NOT NULL)
  );

COMMENT ON CONSTRAINT work_outputs_content_type ON public.work_outputs IS
  'Ensures work_outputs contain EITHER text (body) OR file (file_id), never both or neither';


-- PART 3: Add indexes for performance
-- ========================================================================

-- Index for file lookups
CREATE INDEX idx_work_outputs_file_id
  ON public.work_outputs(file_id)
  WHERE file_id IS NOT NULL;

-- Index for generation method analytics
CREATE INDEX idx_work_outputs_generation_method
  ON public.work_outputs(generation_method);

-- Index for file format filtering
CREATE INDEX idx_work_outputs_file_format
  ON public.work_outputs(file_format)
  WHERE file_format IS NOT NULL;


-- PART 4: Update check constraints for generation_method enum
-- ========================================================================

ALTER TABLE public.work_outputs
  ADD CONSTRAINT work_outputs_generation_method_check CHECK (
    generation_method IN ('text', 'code_execution', 'skill', 'manual')
  );

COMMENT ON CONSTRAINT work_outputs_generation_method_check ON public.work_outputs IS
  'Valid generation methods: text (standard), code_execution (code tool), skill (Agent Skill), manual (user upload)';


-- PART 5: Add storage path validation (follows reference_assets pattern)
-- ========================================================================

-- Storage path format: baskets/{basket_id}/work_outputs/{work_ticket_id}/{filename}
ALTER TABLE public.work_outputs
  ADD CONSTRAINT work_outputs_storage_path_format CHECK (
    storage_path IS NULL OR
    storage_path LIKE 'baskets/' || basket_id::TEXT || '/work_outputs/%'
  );

COMMENT ON CONSTRAINT work_outputs_storage_path_format ON public.work_outputs IS
  'Validates storage_path follows format: baskets/{basket_id}/work_outputs/{work_ticket_id}/{filename}';


-- PART 6: Backfill existing records
-- ========================================================================

-- Set generation_method='text' for existing text-only records
UPDATE public.work_outputs
SET generation_method = 'text'
WHERE generation_method IS NULL AND body IS NOT NULL;

COMMENT ON TABLE public.work_outputs IS
  'Agent-generated deliverables (text and files). Text outputs use body field. File outputs use file_id + metadata. Mutually exclusive via CHECK constraint.';


-- PART 7: Migration rollback script (commented for safety)
-- ========================================================================

/*
-- ROLLBACK SCRIPT (execute only if needed):

-- Drop new constraints
ALTER TABLE public.work_outputs
  DROP CONSTRAINT IF EXISTS work_outputs_content_type,
  DROP CONSTRAINT IF EXISTS work_outputs_generation_method_check,
  DROP CONSTRAINT IF EXISTS work_outputs_storage_path_format;

-- Drop new indexes
DROP INDEX IF EXISTS idx_work_outputs_file_id;
DROP INDEX IF EXISTS idx_work_outputs_generation_method;
DROP INDEX IF EXISTS idx_work_outputs_file_format;

-- Drop new columns
ALTER TABLE public.work_outputs
  DROP COLUMN IF EXISTS file_id,
  DROP COLUMN IF EXISTS file_format,
  DROP COLUMN IF EXISTS file_size_bytes,
  DROP COLUMN IF EXISTS mime_type,
  DROP COLUMN IF EXISTS storage_path,
  DROP COLUMN IF EXISTS generation_method,
  DROP COLUMN IF EXISTS skill_metadata;

-- Revert body to JSONB and NOT NULL
ALTER TABLE public.work_outputs
  ALTER COLUMN body TYPE JSONB USING body::JSONB,
  ALTER COLUMN body SET NOT NULL;

-- Revert work_ticket_id → work_session_id
ALTER TABLE public.work_outputs
  DROP CONSTRAINT IF EXISTS work_outputs_work_ticket_id_fkey,
  RENAME COLUMN work_ticket_id TO work_session_id;

ALTER TABLE public.work_outputs
  ADD CONSTRAINT work_outputs_work_session_id_fkey
    FOREIGN KEY (work_session_id)
    REFERENCES public.work_sessions(id)
    ON DELETE CASCADE;
*/
