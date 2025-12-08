-- Add origin_template column to baskets if not exists
ALTER TABLE IF EXISTS baskets
  ADD COLUMN IF NOT EXISTS origin_template text;

-- Add is_required column to blocks if not exists
ALTER TABLE IF EXISTS blocks
  ADD COLUMN IF NOT EXISTS is_required boolean DEFAULT false;

-- Create documents table if not exists
CREATE TABLE IF NOT EXISTS documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    basket_id uuid,
    title text NOT NULL,
    content_raw text NOT NULL,
    content_rendered text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    created_by uuid,
    updated_by uuid
);

-- Unique index on basket_id and title
CREATE UNIQUE INDEX IF NOT EXISTS docs_basket_title_idx
  ON documents (basket_id, title);

-- Foreign key for documents.basket_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'documents_basket_id_fkey'
  ) THEN
    ALTER TABLE documents
      ADD CONSTRAINT documents_basket_id_fkey
      FOREIGN KEY (basket_id) REFERENCES baskets(id) ON DELETE CASCADE;
  END IF;
END$$;

-- Create block_links table if not exists
CREATE TABLE IF NOT EXISTS block_links (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    block_id uuid,
    document_id uuid,
    occurrences integer DEFAULT 0,
    snippets jsonb
);

-- Index for block_id + document_id
CREATE INDEX IF NOT EXISTS blk_doc_idx
  ON block_links (block_id, document_id);

-- Foreign keys for block_links
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'block_links_block_id_fkey'
  ) THEN
    ALTER TABLE block_links
      ADD CONSTRAINT block_links_block_id_fkey
      FOREIGN KEY (block_id) REFERENCES blocks(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'block_links_document_id_fkey'
  ) THEN
    ALTER TABLE block_links
      ADD CONSTRAINT block_links_document_id_fkey
      FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
  END IF;
END$$;
