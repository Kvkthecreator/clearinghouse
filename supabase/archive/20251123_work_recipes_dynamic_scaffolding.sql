-- Migration: Dynamic Work Recipes - Parameterized Deliverable Scaffolding
-- Purpose: Enable recipe-driven work execution with bounded flexibility
-- Date: 2025-11-23
-- Strategy: Additive (extends existing work_requests table)

-- ============================================================================
-- STEP 1: Create work_recipes table
-- ============================================================================

CREATE TABLE work_recipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identity
  slug VARCHAR(100) UNIQUE NOT NULL,  -- URL-safe identifier: "executive-summary-deck"
  name VARCHAR(255) NOT NULL,          -- Display name: "Executive Summary Deck"
  description TEXT,                     -- User-facing description

  -- Categorization
  category VARCHAR(50),                 -- "reporting", "research", "content"
  agent_type VARCHAR(50) NOT NULL CHECK (agent_type IN ('research', 'content', 'reporting')),

  -- Deliverable Intent (what this achieves)
  deliverable_intent JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Example:
  -- {
  --   "purpose": "High-level overview for leadership",
  --   "audience": "Leadership, stakeholders",
  --   "outcome": "Clear understanding of key insights and next steps"
  -- }

  -- Configurable Parameters (user can customize)
  configurable_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Example:
  -- {
  --   "slide_count": {
  --     "type": "range",
  --     "default": 5,
  --     "min": 3,
  --     "max": 7,
  --     "description": "Number of slides"
  --   },
  --   "focus_area": {
  --     "type": "text",
  --     "optional": true,
  --     "max_length": 200,
  --     "description": "Specific focus or theme"
  --   }
  -- }

  -- Output Specification (validation rules)
  output_specification JSONB NOT NULL,
  -- Example:
  -- {
  --   "format": "pptx",
  --   "required_sections": ["Title", "Key Insights", "Next Steps"],
  --   "validation_rules": {
  --     "min_slides": 3,
  --     "max_slides": 7,
  --     "sections_present": true
  --   }
  -- }

  -- Context Requirements (what substrate/assets are needed)
  context_requirements JSONB DEFAULT '{}'::jsonb,
  -- Example:
  -- {
  --   "substrate_blocks": {
  --     "semantic_types": ["insight", "finding", "recommendation"],
  --     "min_blocks": 5,
  --     "recency": "last_90_days"
  --   },
  --   "reference_assets": {
  --     "required": false,
  --     "types": ["presentations", "reports"],
  --     "min_count": 0,
  --     "purpose": "Style and structure guidance"
  --   }
  -- }

  -- Execution Template (agent instructions)
  execution_template JSONB NOT NULL,
  -- Example:
  -- {
  --   "system_prompt_additions": "Focus on executive-level communication...",
  --   "task_breakdown": [
  --     "Load substrate blocks (insights, findings)",
  --     "Parse reference assets if provided",
  --     "Generate {{slide_count}} slide deck",
  --     "Include required sections: {{required_sections}}",
  --     "Emit work_output with validation metadata"
  --   ],
  --   "validation_instructions": "Verify slide count matches parameter..."
  -- }

  -- Estimates (for UI display)
  estimated_duration_seconds_range INT[2],  -- [180, 360] = 3-6 minutes
  estimated_cost_cents_range INT[2],        -- [300, 500] = $3-5

  -- Lifecycle
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'beta', 'deprecated')),
  version INT DEFAULT 1 NOT NULL,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb NOT NULL
);

-- Indexes
CREATE INDEX idx_work_recipes_slug ON work_recipes(slug);
CREATE INDEX idx_work_recipes_category ON work_recipes(category);
CREATE INDEX idx_work_recipes_agent_type ON work_recipes(agent_type);
CREATE INDEX idx_work_recipes_status ON work_recipes(status) WHERE status = 'active';

-- Grants
GRANT ALL ON TABLE work_recipes TO service_role;
GRANT SELECT ON TABLE work_recipes TO authenticated;  -- Read-only for users

-- RLS
ALTER TABLE work_recipes ENABLE ROW LEVEL SECURITY;

-- Public read (all active recipes visible to authenticated users)
CREATE POLICY "Users can view active recipes"
  ON work_recipes FOR SELECT
  USING (status = 'active');

-- ============================================================================
-- STEP 2: Extend work_requests table for recipe linkage
-- ============================================================================

-- Add recipe columns to work_requests
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS recipe_id UUID REFERENCES work_recipes(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS recipe_parameters JSONB DEFAULT '{}'::jsonb;

-- Add reference_asset_ids column (user-uploaded assets for context)
ALTER TABLE work_requests
ADD COLUMN IF NOT EXISTS reference_asset_ids UUID[] DEFAULT '{}';

-- Indexes
CREATE INDEX idx_work_requests_recipe ON work_requests(recipe_id) WHERE recipe_id IS NOT NULL;

-- Comments
COMMENT ON COLUMN work_requests.recipe_id IS 'Optional: Recipe used for this work request (dynamic scaffolding)';
COMMENT ON COLUMN work_requests.recipe_parameters IS 'User-customized parameters for recipe execution (e.g., slide_count, focus_area)';
COMMENT ON COLUMN work_requests.reference_asset_ids IS 'User-uploaded reference assets for context front-loading (e.g., existing decks, benchmarks)';

-- ============================================================================
-- STEP 3: Seed Data - First Recipe: Executive Summary Deck
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
  'executive-summary-deck',
  'Executive Summary Deck',
  'Generate a concise 3-7 slide presentation summarizing key insights and next steps. Perfect for leadership updates and stakeholder communication.',
  'reporting',
  'reporting',
  '{
    "purpose": "High-level overview for leadership and stakeholders",
    "audience": "Executives, leadership team, stakeholders",
    "outcome": "Clear understanding of key insights, findings, and recommended next steps"
  }'::jsonb,
  '{
    "slide_count": {
      "type": "range",
      "default": 5,
      "min": 3,
      "max": 7,
      "description": "Number of slides in the deck"
    },
    "focus_area": {
      "type": "text",
      "optional": true,
      "max_length": 200,
      "description": "Specific focus or theme for the summary (e.g., Q4 performance, market trends)"
    }
  }'::jsonb,
  '{
    "format": "pptx",
    "required_sections": ["Title", "Key Insights", "Next Steps"],
    "validation_rules": {
      "slide_count_in_range": true,
      "required_sections_present": true,
      "format_is_pptx": true
    }
  }'::jsonb,
  '{
    "substrate_blocks": {
      "semantic_types": ["insight", "finding", "recommendation", "analysis"],
      "min_blocks": 3,
      "recency_preference": "last_90_days"
    },
    "reference_assets": {
      "required": false,
      "types": ["presentations", "reports", "documents"],
      "min_count": 0,
      "purpose": "Optional: Provide existing decks or reports for style and structure guidance"
    }
  }'::jsonb,
  '{
    "system_prompt_additions": "You are creating an Executive Summary Deck. Focus on high-level insights suitable for leadership. Be concise, actionable, and visually clear. Use executive language (avoid jargon unless necessary).",
    "task_breakdown": [
      "Load substrate blocks (insights, findings, recommendations, analysis)",
      "Parse reference assets if provided (extract style, structure, tone)",
      "Identify {{slide_count}} key insights from substrate context",
      "Generate {{slide_count}}-slide PPTX deck using Claude pptx Skill",
      "Required sections: Title, Key Insights ({{slide_count - 2}} slides), Next Steps (1 slide)",
      "If focus_area provided, emphasize related insights",
      "Emit work_output with format=pptx, validation metadata"
    ],
    "validation_instructions": "After generation, verify: (1) Slide count matches user parameter, (2) All required sections present, (3) Format is PPTX. Include validation results in work_output metadata."
  }'::jsonb,
  ARRAY[180, 360],  -- 3-6 minutes estimated
  ARRAY[300, 500],  -- $3-5 estimated
  'active',
  1
);

-- ============================================================================
-- STEP 4: Verification
-- ============================================================================

DO $$
DECLARE
  recipes_count INTEGER;
  work_requests_recipe_column BOOLEAN;
BEGIN
  -- Count recipes
  SELECT COUNT(*) INTO recipes_count FROM work_recipes WHERE status = 'active';

  -- Check work_requests columns
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'work_requests' AND column_name = 'recipe_id'
  ) INTO work_requests_recipe_column;

  RAISE NOTICE '✅ Work Recipes Migration Complete:';
  RAISE NOTICE '  - Active recipes: %', recipes_count;
  RAISE NOTICE '  - work_requests.recipe_id column: %', work_requests_recipe_column;
  RAISE NOTICE '';
  RAISE NOTICE '📋 Dynamic work recipes ready for Phase 1 implementation.';
  RAISE NOTICE '   Next: Implement RecipeLoader and RecipeValidator classes.';
END $$;
