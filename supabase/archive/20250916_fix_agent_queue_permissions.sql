-- Fix missing INSERT permission on agent_processing_queue
-- This was causing BreakdownDocument operations to fail with "permission denied"
-- when the after_dump_insert trigger attempts to queue agent processing

-- Add INSERT policy for authenticated users in their workspace
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

-- Also ensure users can update their own queued items (for status tracking)
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

COMMENT ON POLICY "Users can queue processing in their workspace" ON public.agent_processing_queue IS 
'Allows authenticated users to insert into agent_processing_queue when creating raw_dumps via triggers. Critical for P0->P1 canon flow.';

COMMENT ON POLICY "Users can update their queued items" ON public.agent_processing_queue IS 
'Allows users to update queue items in their workspace for status tracking and error handling.';