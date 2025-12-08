-- Remove deprecated content_rendered field from documents table
-- This field was marked for removal in Canon v1.3.1

-- Remove the deprecated column
ALTER TABLE documents DROP COLUMN IF EXISTS content_rendered;