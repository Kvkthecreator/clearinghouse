-- Add text_dump column to raw_dumps table for backend compatibility
-- Backend agent service expects text_dump column but frontend uses body_md

-- Only add if column doesn't exist to avoid conflicts
DO $$
BEGIN
  -- Add text_dump column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'raw_dumps' 
    AND column_name = 'text_dump'
  ) THEN
    ALTER TABLE public.raw_dumps ADD COLUMN text_dump text;
    
    -- Copy existing body_md values to text_dump for backwards compatibility
    UPDATE public.raw_dumps 
    SET text_dump = body_md 
    WHERE text_dump IS NULL AND body_md IS NOT NULL;
    
    RAISE NOTICE 'Added text_dump column to raw_dumps table and synced existing data';
  ELSE
    RAISE NOTICE 'text_dump column already exists in raw_dumps table';
  END IF;
END $$;

-- Create sync function if it doesn't exist
CREATE OR REPLACE FUNCTION sync_raw_dump_text_columns()
RETURNS TRIGGER AS $$
BEGIN
  -- When body_md is updated, sync to text_dump
  IF NEW.body_md IS DISTINCT FROM OLD.body_md THEN
    NEW.text_dump = NEW.body_md;
  END IF;
  
  -- When text_dump is updated, sync to body_md  
  IF NEW.text_dump IS DISTINCT FROM OLD.text_dump THEN
    NEW.body_md = NEW.text_dump;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers only if they don't exist
DO $$
BEGIN
  -- Update trigger
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers 
    WHERE trigger_name = 'sync_text_dump_columns'
  ) THEN
    CREATE TRIGGER sync_text_dump_columns
      BEFORE UPDATE ON public.raw_dumps
      FOR EACH ROW
      EXECUTE FUNCTION sync_raw_dump_text_columns();
    RAISE NOTICE 'Created sync_text_dump_columns trigger';
  END IF;
  
  -- Insert trigger function
  CREATE OR REPLACE FUNCTION ensure_raw_dump_text_columns()
  RETURNS TRIGGER AS $inner$
  BEGIN
    -- Ensure both columns have the same value on insert
    IF NEW.body_md IS NOT NULL AND NEW.text_dump IS NULL THEN
      NEW.text_dump = NEW.body_md;
    ELSIF NEW.text_dump IS NOT NULL AND NEW.body_md IS NULL THEN
      NEW.body_md = NEW.text_dump;
    END IF;
    
    RETURN NEW;
  END;
  $inner$ LANGUAGE plpgsql;
  
  -- Insert trigger
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers 
    WHERE trigger_name = 'ensure_text_dump_columns'
  ) THEN
    CREATE TRIGGER ensure_text_dump_columns
      BEFORE INSERT ON public.raw_dumps
      FOR EACH ROW
      EXECUTE FUNCTION ensure_raw_dump_text_columns();
    RAISE NOTICE 'Created ensure_text_dump_columns trigger';
  END IF;
END $$;

-- Add comments
COMMENT ON COLUMN public.raw_dumps.text_dump IS 'Backend compatibility column - synced with body_md';
COMMENT ON COLUMN public.raw_dumps.body_md IS 'Frontend primary column - synced with text_dump';