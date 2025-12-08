-- Migration: Research Deep Dive Recipe
-- Purpose: Add first research agent recipe for testing TodoWrite streaming
-- Date: 2025-11-26

-- ============================================================================
-- Research Deep Dive Recipe
-- ============================================================================

INSERT INTO work_recipes (
  slug,
  name,
  description,
  category,
  agent_type,
  deliverable_intent,
  configurable_parameters,
  output_specification,
  context_requirements,
  execution_template,
  estimated_duration_seconds_range,
  estimated_cost_cents_range,
  status,
  version
) VALUES (
  'research-deep-dive',
  'Research Deep Dive',
  'Conduct comprehensive research on a topic with structured findings, insights, and recommendations. Perfect for market analysis, competitor research, or trend exploration.',
  'research',
  'research',
  '{
    "purpose": "Comprehensive research and analysis on a specific topic",
    "audience": "Product teams, strategists, decision-makers",
    "outcome": "Structured findings with actionable insights and recommendations"
  }'::jsonb,
  '{
    "research_scope": {
      "type": "select",
      "default": "general",
      "options": ["general", "competitor", "market", "technical"],
      "description": "Focus area for the research"
    },
    "depth": {
      "type": "select",
      "default": "standard",
      "options": ["quick", "standard", "deep"],
      "description": "Research depth (affects time and detail)"
    },
    "focus_area": {
      "type": "text",
      "optional": true,
      "max_length": 500,
      "description": "Specific topic or question to research"
    }
  }'::jsonb,
  '{
    "format": "markdown",
    "required_sections": ["Overview", "Key Findings", "Recommendations"],
    "output_types": ["finding", "insight", "recommendation"],
    "validation_rules": {
      "min_findings": 1,
      "structured_outputs_required": true
    }
  }'::jsonb,
  '{
    "substrate_blocks": {
      "semantic_types": ["finding", "insight", "analysis", "competitor_data"],
      "min_blocks": 0,
      "recency_preference": "last_90_days"
    },
    "reference_assets": {
      "required": false,
      "types": ["documents", "reports", "urls"],
      "min_count": 0,
      "purpose": "Optional: Provide existing research or reference materials"
    }
  }'::jsonb,
  '{
    "system_prompt_additions": "You are conducting a Research Deep Dive. Your goal is to produce comprehensive, structured findings. Use the TodoWrite tool to show progress. Each significant finding, insight, or recommendation MUST be emitted via emit_work_output tool.",
    "task_breakdown": [
      "Query substrate for existing knowledge on the topic",
      "Identify knowledge gaps requiring new research",
      "Conduct web research using WebSearch tool",
      "Emit findings via emit_work_output (type: finding)",
      "Synthesize patterns into insights (type: insight)",
      "Generate actionable recommendations (type: recommendation)",
      "Provide summary with confidence scores"
    ],
    "validation_instructions": "Verify: (1) At least one structured output emitted, (2) Outputs include source_block_ids for provenance, (3) Confidence scores provided"
  }'::jsonb,
  ARRAY[120, 300],  -- 2-5 minutes estimated
  ARRAY[200, 500],  -- $2-5 estimated
  'active',
  1
) ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  deliverable_intent = EXCLUDED.deliverable_intent,
  configurable_parameters = EXCLUDED.configurable_parameters,
  output_specification = EXCLUDED.output_specification,
  context_requirements = EXCLUDED.context_requirements,
  execution_template = EXCLUDED.execution_template,
  estimated_duration_seconds_range = EXCLUDED.estimated_duration_seconds_range,
  estimated_cost_cents_range = EXCLUDED.estimated_cost_cents_range,
  updated_at = now();

-- ============================================================================
-- Verification
-- ============================================================================

DO $$
DECLARE
  research_recipe_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM work_recipes
    WHERE slug = 'research-deep-dive' AND status = 'active'
  ) INTO research_recipe_exists;

  RAISE NOTICE '✅ Research Deep Dive Recipe: %',
    CASE WHEN research_recipe_exists THEN 'Created/Updated' ELSE 'FAILED' END;
END $$;
