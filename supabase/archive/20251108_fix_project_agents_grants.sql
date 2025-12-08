-- Migration: Fix missing GRANT statements for project_agents table
-- Date: 2025-11-08
-- Purpose: Add table-level permissions for authenticated role
--
-- Root Cause: The 20251108_project_agents_architecture.sql migration
-- created the project_agents table with RLS policies but forgot to
-- GRANT permissions to the authenticated role. Without GRANTs, users
-- get "permission denied" even though RLS policies are correct.
--
-- Symptoms:
-- - Project overview page shows "Project not found"
-- - Frontend queries to project_agents fail silently
-- - Production 404 errors for valid projects
--
-- Fix: Add missing GRANT statements

-- Grant table-level permissions to authenticated role
GRANT SELECT, INSERT, UPDATE, DELETE ON project_agents TO authenticated;

-- Verify grants are applied
DO $$
DECLARE
  grant_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO grant_count
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'project_agents'
    AND grantee = 'authenticated';

  RAISE NOTICE '✅ Fix applied: project_agents now has % authenticated role grants', grant_count;

  IF grant_count < 4 THEN
    RAISE WARNING 'Expected 4 grants (SELECT, INSERT, UPDATE, DELETE) but found %', grant_count;
  END IF;
END $$;
