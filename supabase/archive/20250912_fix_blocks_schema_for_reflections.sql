-- Fix missing columns in blocks table that break reflection analysis
-- Backend requires blocks.updated_at and blocks.normalized_label for substrate analysis

-- Add updated_at column (backend expects this for recency analysis)
ALTER TABLE public.blocks 
    ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

-- Add normalized_label column (backend uses this for content deduplication)
ALTER TABLE public.blocks 
    ADD COLUMN IF NOT EXISTS normalized_label text;

-- Set updated_at to created_at for existing records
UPDATE public.blocks 
SET updated_at = created_at;

-- Create index on updated_at for efficient time window queries
CREATE INDEX IF NOT EXISTS idx_blocks_updated_at ON public.blocks(updated_at);

-- Update normalized_label for existing records (use title or content as fallback)
UPDATE public.blocks 
SET normalized_label = COALESCE(title, LEFT(content, 100));

COMMENT ON COLUMN public.blocks.updated_at IS 'Timestamp for reflection analysis time windows';
COMMENT ON COLUMN public.blocks.normalized_label IS 'Normalized content label for substrate deduplication';