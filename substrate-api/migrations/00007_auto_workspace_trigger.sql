-- Migration: Auto-create workspace on user signup
-- Description: Creates a default workspace when a new user signs up via Supabase Auth
-- Applied: 2024-12-10

-- =============================================================================
-- Function: Create default workspace for new users
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_default_workspace()
RETURNS TRIGGER AS $$
DECLARE
    new_workspace_id uuid;
BEGIN
    -- Create default workspace for the new user
    INSERT INTO public.workspaces (name, slug, description, created_by)
    VALUES (
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email, 'My Workspace'),
        'ws-' || SUBSTRING(NEW.id::text FROM 1 FOR 8),
        'Default workspace',
        NEW.id::text
    )
    RETURNING id INTO new_workspace_id;

    -- Add user as owner of the workspace
    INSERT INTO public.workspace_memberships (workspace_id, user_id, role)
    VALUES (new_workspace_id, NEW.id::text, 'owner');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- Trigger: Execute on auth.users insert
-- =============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.create_default_workspace();

-- =============================================================================
-- Note: This migration must be run with sufficient privileges to create
-- triggers on auth.users. In Supabase, this requires using the SQL editor
-- in the dashboard or running as the postgres/service_role user.
-- =============================================================================
