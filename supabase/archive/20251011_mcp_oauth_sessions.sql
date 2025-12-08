-- Migration: Add MCP OAuth Sessions table
-- Purpose: Store OAuth token mappings for Claude.ai remote MCP connector
-- Canon compliance: Workspace-scoped with RLS, service-role writes only

-- Create mcp_oauth_sessions table
CREATE TABLE IF NOT EXISTS public.mcp_oauth_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mcp_token TEXT NOT NULL UNIQUE,
    supabase_token TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add indexes for fast lookups
CREATE INDEX idx_mcp_oauth_sessions_mcp_token ON public.mcp_oauth_sessions(mcp_token);
CREATE INDEX idx_mcp_oauth_sessions_user_id ON public.mcp_oauth_sessions(user_id);
CREATE INDEX idx_mcp_oauth_sessions_workspace_id ON public.mcp_oauth_sessions(workspace_id);
CREATE INDEX idx_mcp_oauth_sessions_expires_at ON public.mcp_oauth_sessions(expires_at);

-- Add comment
COMMENT ON TABLE public.mcp_oauth_sessions IS 'OAuth session mappings for Claude.ai remote MCP connector. Maps MCP access tokens to Supabase user sessions.';

-- Enable RLS
ALTER TABLE public.mcp_oauth_sessions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own sessions
CREATE POLICY "Users can view own MCP sessions"
    ON public.mcp_oauth_sessions
    FOR SELECT
    USING (
        user_id = auth.uid()
    );

-- Policy: Users can delete their own sessions (revoke)
CREATE POLICY "Users can revoke own MCP sessions"
    ON public.mcp_oauth_sessions
    FOR DELETE
    USING (
        user_id = auth.uid()
    );

-- Policy: Service role can insert/update sessions (MCP server operations)
-- Note: Service role bypasses RLS, but we document the intent here

-- Grant permissions
GRANT SELECT, DELETE ON public.mcp_oauth_sessions TO authenticated;
GRANT ALL ON public.mcp_oauth_sessions TO service_role;

-- Function to clean up expired sessions (run periodically)
CREATE OR REPLACE FUNCTION public.cleanup_expired_mcp_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.mcp_oauth_sessions
    WHERE expires_at < NOW();

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_mcp_sessions() IS 'Delete expired MCP OAuth sessions. Should be called periodically via cron or manually.';

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION public.cleanup_expired_mcp_sessions() TO service_role;
