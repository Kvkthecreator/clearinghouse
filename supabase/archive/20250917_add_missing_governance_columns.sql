-- Add missing ep_reflection_suggestion column to workspace_governance_settings
-- Fixes: record "settings_row" has no field "ep_reflection_suggestion" error

-- Add the missing column if it doesn't exist
DO $$ 
BEGIN
    -- Check if ep_reflection_suggestion column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'workspace_governance_settings' 
        AND column_name = 'ep_reflection_suggestion'
    ) THEN
        -- Add the column with appropriate default and constraint
        ALTER TABLE public.workspace_governance_settings 
        ADD COLUMN ep_reflection_suggestion text NOT NULL DEFAULT 'proposal';
        
        -- Add check constraint for valid values
        ALTER TABLE public.workspace_governance_settings 
        ADD CONSTRAINT workspace_governance_settings_ep_reflection_suggestion_check 
        CHECK (ep_reflection_suggestion = ANY (ARRAY['proposal'::text, 'direct'::text, 'hybrid'::text]));
        
        RAISE NOTICE 'Added ep_reflection_suggestion column to workspace_governance_settings';
    ELSE
        RAISE NOTICE 'ep_reflection_suggestion column already exists in workspace_governance_settings';
    END IF;
END $$;

COMMENT ON COLUMN public.workspace_governance_settings.ep_reflection_suggestion IS 
'Canon v2.2: Execution policy for reflection suggestion operations - proposal (review required), direct (auto-execute), or hybrid (confidence-based routing)';