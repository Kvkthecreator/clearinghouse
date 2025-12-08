-- Fix reflection_cache schema inconsistencies
-- Issue: Production has legacy schema with computed_at, ReflectionEngine expects computation_timestamp
-- Solution: Migrate data from legacy schema to canonical schema

-- Drop the compatibility view first
DROP VIEW IF EXISTS public.basket_reflections;

-- Check current schema and migrate if needed
DO $$
DECLARE
    has_computed_at boolean;
    has_computation_timestamp boolean;
    has_pattern boolean;
    has_reflection_text boolean;
BEGIN
    -- Check what columns exist in current table
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema='public' AND table_name='reflection_cache' AND column_name='computed_at'
    ) INTO has_computed_at;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema='public' AND table_name='reflection_cache' AND column_name='computation_timestamp'
    ) INTO has_computation_timestamp;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema='public' AND table_name='reflection_cache' AND column_name='pattern'
    ) INTO has_pattern;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema='public' AND table_name='reflection_cache' AND column_name='reflection_text'
    ) INTO has_reflection_text;
    
    RAISE NOTICE 'Schema detection: computed_at=%, computation_timestamp=%, pattern=%, reflection_text=%', 
                 has_computed_at, has_computation_timestamp, has_pattern, has_reflection_text;
    
    -- If we have the legacy schema, migrate to canonical
    IF has_computed_at AND NOT has_computation_timestamp THEN
        RAISE NOTICE 'Migrating from legacy schema to canonical ReflectionEngine schema';
        
        -- Add new columns required by ReflectionEngine
        ALTER TABLE reflection_cache 
        ADD COLUMN IF NOT EXISTS substrate_hash TEXT,
        ADD COLUMN IF NOT EXISTS reflection_text TEXT,
        ADD COLUMN IF NOT EXISTS substrate_window_start TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS substrate_window_end TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS computation_timestamp TIMESTAMP WITH TIME ZONE,
        ADD COLUMN IF NOT EXISTS last_accessed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        ADD COLUMN IF NOT EXISTS meta JSONB DEFAULT '{}',
        ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
        
        -- Migrate existing data to new schema
        UPDATE reflection_cache SET 
            computation_timestamp = computed_at,
            reflection_text = COALESCE(
                CASE 
                    WHEN pattern IS NOT NULL AND tension IS NOT NULL AND question IS NOT NULL 
                    THEN 'Pattern: ' || pattern || E'\n\nTension: ' || tension || E'\n\nQuestion: ' || question
                    WHEN pattern IS NOT NULL AND tension IS NOT NULL
                    THEN 'Pattern: ' || pattern || E'\n\nTension: ' || tension
                    WHEN pattern IS NOT NULL
                    THEN pattern
                    WHEN tension IS NOT NULL  
                    THEN tension
                    WHEN question IS NOT NULL
                    THEN question
                    ELSE 'Legacy reflection content'
                END, 
                'Legacy reflection content'
            ),
            substrate_hash = COALESCE(meta_derived_from, 'legacy-' || id::text),
            substrate_window_start = computed_at,
            substrate_window_end = computed_at,
            created_at = computed_at,
            updated_at = computed_at,
            last_accessed_at = COALESCE(computed_at, NOW())
        WHERE computation_timestamp IS NULL;
        
        -- Set NOT NULL constraints on required new columns after data migration
        UPDATE reflection_cache SET 
            substrate_hash = 'legacy-' || id::text 
        WHERE substrate_hash IS NULL;
        
        UPDATE reflection_cache SET 
            reflection_text = 'Migrated legacy reflection' 
        WHERE reflection_text IS NULL;
        
        ALTER TABLE reflection_cache 
        ALTER COLUMN substrate_hash SET NOT NULL,
        ALTER COLUMN reflection_text SET NOT NULL,
        ALTER COLUMN computation_timestamp SET NOT NULL;
        
        -- Drop legacy columns after successful migration
        ALTER TABLE reflection_cache 
        DROP COLUMN IF EXISTS computed_at,
        DROP COLUMN IF EXISTS meta_derived_from,
        DROP COLUMN IF EXISTS meta_refreshable,
        DROP COLUMN IF EXISTS pattern,
        DROP COLUMN IF EXISTS tension,
        DROP COLUMN IF EXISTS question;
        
        RAISE NOTICE 'Legacy schema migration completed successfully';
        
    ELSIF NOT has_computed_at AND has_computation_timestamp THEN
        RAISE NOTICE 'Already using canonical schema - no migration needed';
        
    ELSIF has_computed_at AND has_computation_timestamp THEN
        RAISE NOTICE 'Both schemas detected - manual intervention may be required';
        
    ELSE
        RAISE NOTICE 'No reflection_cache table found or unrecognized schema';
    END IF;
END $$;

-- Ensure proper indexes exist for canonical schema
DROP INDEX IF EXISTS idx_reflection_cache_computation_timestamp;
CREATE INDEX IF NOT EXISTS idx_reflection_cache_computation_timestamp 
ON reflection_cache(computation_timestamp DESC);

DROP INDEX IF EXISTS idx_reflection_cache_basket_computation;
CREATE INDEX IF NOT EXISTS idx_reflection_cache_basket_computation 
ON reflection_cache(basket_id, computation_timestamp DESC);

-- Ensure unique constraint for deduplication exists
DROP INDEX IF EXISTS reflection_cache_uq;
CREATE UNIQUE INDEX IF NOT EXISTS reflection_cache_uq 
ON reflection_cache (basket_id, substrate_hash);

-- Update RLS policies to match canonical schema
DROP POLICY IF EXISTS reflection_cache_read ON reflection_cache;
CREATE POLICY reflection_cache_read ON reflection_cache
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM workspace_memberships m
    WHERE m.user_id = auth.uid()
      AND m.workspace_id = reflection_cache.workspace_id
  )
);

-- Ensure server-only write policies
DROP POLICY IF EXISTS reflection_cache_no_user_insert ON reflection_cache;
DROP POLICY IF EXISTS reflection_cache_no_user_update ON reflection_cache;  
DROP POLICY IF EXISTS reflection_cache_no_user_delete ON reflection_cache;

CREATE POLICY reflection_cache_no_user_insert ON reflection_cache
FOR INSERT WITH CHECK (false);

CREATE POLICY reflection_cache_no_user_update ON reflection_cache
FOR UPDATE USING (false) WITH CHECK (false);

CREATE POLICY reflection_cache_no_user_delete ON reflection_cache
FOR DELETE USING (false);

-- Add updated_at trigger if it doesn't exist
DROP TRIGGER IF EXISTS reflection_cache_updated_at_trigger ON reflection_cache;
CREATE OR REPLACE FUNCTION update_reflection_cache_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER reflection_cache_updated_at_trigger
  BEFORE UPDATE ON reflection_cache
  FOR EACH ROW
  EXECUTE FUNCTION update_reflection_cache_updated_at();

-- Log completion
SELECT 'reflection_cache schema migration completed' as migration_status;