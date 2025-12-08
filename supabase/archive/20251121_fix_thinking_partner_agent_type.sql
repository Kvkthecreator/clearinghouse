-- Migration: Fix agent_type constraint to include 'thinking_partner'
-- Purpose: Fix CRITICAL blocking error preventing TP chat from working
-- Date: 2025-11-21
-- Issue: Phase 2e migration only allowed ('research', 'content', 'reporting')
--        but TP code creates sessions with agent_type='thinking_partner'
--
-- Production Error:
--   AgentSession.get_or_create failed:
--   'new row violates check constraint "agent_sessions_agent_type_check"'
--   code: '23514'
--
-- This migration supersedes:
--   - 20251120_add_thinking_partner_agent_type.sql (delete after applying this)
--   - 20251121_add_thinking_partner_to_agent_type.sql (delete after applying this)

BEGIN;

-- Drop existing constraint (from Phase 2e migration)
ALTER TABLE agent_sessions
  DROP CONSTRAINT IF EXISTS agent_sessions_agent_type_check;

-- Recreate constraint with 'thinking_partner' included
ALTER TABLE agent_sessions
  ADD CONSTRAINT agent_sessions_agent_type_check
  CHECK (agent_type IN ('research', 'content', 'reporting', 'thinking_partner'));

-- Update comment
COMMENT ON CONSTRAINT agent_sessions_agent_type_check ON agent_sessions IS
  'Valid agent types: research (intelligence), content (creative), reporting (analytical), thinking_partner (orchestrator)';

COMMIT;

-- Verification query (run after commit)
-- Expected result: constraint should include all 4 agent types
SELECT
  conname as constraint_name,
  pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conname = 'agent_sessions_agent_type_check'
  AND conrelid = 'agent_sessions'::regclass;
