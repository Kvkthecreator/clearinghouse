-- Allow anonymous users to read work tickets for tracking page
-- This enables the public tracking page to display ticket status without authentication

-- Grant schema access to anon role
GRANT USAGE ON SCHEMA public TO anon;

-- Grant SELECT permission on work_tickets table to anon role
GRANT SELECT ON public.work_tickets TO anon;

-- Grant SELECT permission on work_outputs table to anon role (for output preview)
GRANT SELECT ON public.work_outputs TO anon;

-- Create RLS policy to allow anonymous read access to work_tickets
CREATE POLICY "Allow anonymous read access to work_tickets"
ON public.work_tickets
FOR SELECT
TO anon
USING (true);

-- Create RLS policy to allow anonymous read access to work_outputs
CREATE POLICY "Allow anonymous read access to work_outputs"
ON public.work_outputs
FOR SELECT
TO anon
USING (true);

-- Note: This is safe because:
-- 1. Only SELECT (read) is allowed, no INSERT/UPDATE/DELETE
-- 2. Sensitive data should not be stored in these tables
-- 3. Work tickets are meant to be shareable tracking links
-- 4. No user-specific filtering needed for public tracking pages
