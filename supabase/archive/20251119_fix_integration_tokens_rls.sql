-- Fix: Add RLS policies for integration_tokens table
-- Problem: Service role getting 406 Not Acceptable when querying integration_tokens
-- Solution: Enable RLS with service role bypass policy

-- Enable RLS on integration_tokens (if not already enabled)
ALTER TABLE public.integration_tokens ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (idempotent)
DROP POLICY IF EXISTS "Service role can manage integration tokens" ON public.integration_tokens;
DROP POLICY IF EXISTS "Users can view their workspace integration tokens" ON public.integration_tokens;
DROP POLICY IF EXISTS "Users can create integration tokens for their workspaces" ON public.integration_tokens;
DROP POLICY IF EXISTS "Users can revoke their workspace integration tokens" ON public.integration_tokens;

-- Policy 1: Service role bypass (for auth middleware verification)
CREATE POLICY "Service role can manage integration tokens"
ON public.integration_tokens
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Policy 2: Users can view integration tokens for their workspaces
CREATE POLICY "Users can view their workspace integration tokens"
ON public.integration_tokens
FOR SELECT
TO authenticated
USING (
  workspace_id IN (
    SELECT workspace_id
    FROM public.workspace_memberships
    WHERE user_id = auth.uid()
  )
);

-- Policy 3: Users can create integration tokens for their workspaces
CREATE POLICY "Users can create integration tokens for their workspaces"
ON public.integration_tokens
FOR INSERT
TO authenticated
WITH CHECK (
  workspace_id IN (
    SELECT workspace_id
    FROM public.workspace_memberships
    WHERE user_id = auth.uid()
      AND role IN ('owner', 'admin')  -- Only owners/admins can create tokens
  )
);

-- Policy 4: Users can revoke integration tokens for their workspaces
CREATE POLICY "Users can revoke their workspace integration tokens"
ON public.integration_tokens
FOR UPDATE
TO authenticated
USING (
  workspace_id IN (
    SELECT workspace_id
    FROM public.workspace_memberships
    WHERE user_id = auth.uid()
      AND role IN ('owner', 'admin')  -- Only owners/admins can revoke
  )
)
WITH CHECK (
  workspace_id IN (
    SELECT workspace_id
    FROM public.workspace_memberships
    WHERE user_id = auth.uid()
      AND role IN ('owner', 'admin')
  )
);

-- Grant table permissions (GRANTS + RLS both required)
-- Service role needs SELECT/INSERT/UPDATE for auth middleware
GRANT SELECT, INSERT, UPDATE ON public.integration_tokens TO service_role;

-- Authenticated users need SELECT/INSERT/UPDATE (RLS policies control access)
GRANT SELECT, INSERT, UPDATE ON public.integration_tokens TO authenticated;

-- Anon role should NOT have access (authenticated only)
REVOKE ALL ON public.integration_tokens FROM anon;

-- Comment explaining the policy structure
COMMENT ON TABLE public.integration_tokens IS 'API integration tokens for external access. Service role has full access for auth middleware verification. Users can manage tokens for their workspaces based on role. Both GRANTS and RLS policies are required for access control.';
