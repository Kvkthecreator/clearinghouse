-- Rename old column if present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'blocks'
      AND column_name = 'type'
  ) THEN
    ALTER TABLE blocks RENAME COLUMN type TO semantic_type;
  END IF;
END $$;
