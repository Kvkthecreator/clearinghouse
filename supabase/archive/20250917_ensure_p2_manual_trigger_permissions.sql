-- Ensure RLS policies for agent_processing_queue support manual P2_GRAPH trigger
-- Fixes "permission denied for table agent_processing_queue" error when users
-- click the manual P2 connection mapping button on the graph page

-- This migration is idempotent - it only creates policies if they don't exist

DO $$ 
BEGIN
    -- Check if the INSERT policy already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'agent_processing_queue' 
        AND policyname = 'Users can queue processing in their workspace'
    ) THEN
        -- Create the INSERT policy for user-initiated work entries
        CREATE POLICY "Users can queue processing in their workspace" 
        ON public.agent_processing_queue 
        FOR INSERT 
        TO authenticated 
        WITH CHECK (
            workspace_id IN (
                SELECT workspace_memberships.workspace_id
                FROM public.workspace_memberships
                WHERE workspace_memberships.user_id = auth.uid()
            )
        );
        
        RAISE NOTICE 'Created INSERT policy for agent_processing_queue';
    ELSE
        RAISE NOTICE 'INSERT policy for agent_processing_queue already exists';
    END IF;

    -- Check if the UPDATE policy already exists  
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'agent_processing_queue' 
        AND policyname = 'Users can update their queued items'
    ) THEN
        -- Create the UPDATE policy for work status tracking
        CREATE POLICY "Users can update their queued items"
        ON public.agent_processing_queue
        FOR UPDATE
        TO authenticated
        USING (
            workspace_id IN (
                SELECT workspace_memberships.workspace_id
                FROM public.workspace_memberships
                WHERE workspace_memberships.user_id = auth.uid()
            )
        )
        WITH CHECK (
            workspace_id IN (
                SELECT workspace_memberships.workspace_id
                FROM public.workspace_memberships
                WHERE workspace_memberships.user_id = auth.uid()
            )
        );
        
        RAISE NOTICE 'Created UPDATE policy for agent_processing_queue';
    ELSE
        RAISE NOTICE 'UPDATE policy for agent_processing_queue already exists';
    END IF;
END $$;

-- Add explanatory comments
COMMENT ON POLICY "Users can queue processing in their workspace" ON public.agent_processing_queue IS 
'Canon v2.2 compliant: allows authenticated users to create P2_GRAPH and other work entries in their workspace via /api/work endpoint. Essential for manual P2 Graph trigger on graph page.';

COMMENT ON POLICY "Users can update their queued items" ON public.agent_processing_queue IS 
'Canon v2.2 compliant: allows users to update work entry status in their workspace for progress tracking and error handling.';

-- Verify RLS is enabled on the table
DO $$
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE relname = 'agent_processing_queue') THEN
        ALTER TABLE public.agent_processing_queue ENABLE ROW LEVEL SECURITY;
        RAISE NOTICE 'Enabled RLS on agent_processing_queue table';
    ELSE
        RAISE NOTICE 'RLS already enabled on agent_processing_queue table';
    END IF;
END $$;