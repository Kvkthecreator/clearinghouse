-- Add canonical file_url column to raw_dumps and backfill from legacy file_refs
ALTER TABLE public.raw_dumps
  ADD COLUMN IF NOT EXISTS file_url text;

-- Backfill single-element file_refs into file_url
UPDATE public.raw_dumps
SET file_url = file_refs[1]
WHERE file_url IS NULL AND cardinality(file_refs) = 1;

-- Retain existing unique index on (basket_id, dump_request_id)
