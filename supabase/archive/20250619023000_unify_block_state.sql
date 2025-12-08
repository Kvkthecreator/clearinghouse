-- Rename if it exists, else add fresh
ALTER TABLE blocks
  RENAME COLUMN status TO state;
-- Ensure ENUM & default
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'block_state') THEN
    CREATE TYPE block_state AS ENUM ('PROPOSED','ACCEPTED','LOCKED',
                                     'CONSTANT','SUPERSEDED','REJECTED');
  END IF;
END$$;
ALTER TABLE blocks
  ALTER COLUMN state TYPE block_state USING state::text::block_state,
  ALTER COLUMN state SET DEFAULT 'PROPOSED',
  ALTER COLUMN state SET NOT NULL;

