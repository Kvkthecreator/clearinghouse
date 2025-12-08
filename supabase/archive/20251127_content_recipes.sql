-- Migration: Content Agent Recipes
-- Purpose: Add work recipes for ContentAgent (social media content generation)
-- Date: 2025-11-27

-- ============================================================================
-- Social Media Post Recipe (LinkedIn, Twitter)
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
  'social-media-post',
  'Social Media Post',
  'Generate engaging social media content for LinkedIn, Twitter/X, or Instagram. Includes variants for A/B testing and suggested hashtags.',
  'content',
  'content',
  '{
    "purpose": "Create platform-optimized social media content",
    "audience": "Professional networks, followers, target demographics",
    "outcome": "Ready-to-publish posts with variants and engagement elements"
  }'::jsonb,
  '{
    "platform": {
      "type": "select",
      "default": "linkedin",
      "options": ["linkedin", "twitter", "instagram"],
      "description": "Target social media platform"
    },
    "tone": {
      "type": "select",
      "default": "professional",
      "options": ["professional", "casual", "authoritative", "friendly", "inspiring"],
      "description": "Content tone and voice"
    },
    "create_variants": {
      "type": "boolean",
      "default": true,
      "description": "Create A/B testing variants"
    },
    "variant_count": {
      "type": "range",
      "default": 2,
      "min": 1,
      "max": 4,
      "description": "Number of variants to create"
    },
    "topic_focus": {
      "type": "text",
      "optional": false,
      "max_length": 500,
      "description": "Topic or key message for the post"
    },
    "target_audience": {
      "type": "text",
      "optional": true,
      "max_length": 200,
      "description": "Specific target audience description"
    }
  }'::jsonb,
  '{
    "format": "text",
    "output_types": ["content_draft", "content_variant", "content_asset", "recommendation"],
    "validation_rules": {
      "content_draft_required": true,
      "platform_constraints_met": true
    }
  }'::jsonb,
  '{
    "substrate_blocks": {
      "semantic_types": ["brand", "insight", "finding"],
      "min_blocks": 0,
      "recency_preference": "last_90_days"
    },
    "reference_assets": {
      "required": false,
      "types": ["documents", "images", "prior_posts"],
      "min_count": 0,
      "purpose": "Optional: Brand guidelines, prior successful posts"
    }
  }'::jsonb,
  '{
    "system_prompt_additions": "You are creating social media content. Focus on engagement, platform best practices, and the specified tone. Create compelling hooks that stop scrollers. Each output MUST be emitted via emit_work_output tool.",
    "task_breakdown": [
      "Query substrate for brand voice and prior content",
      "Understand platform constraints ({{platform}})",
      "Create main content draft with strong hook",
      "If create_variants=true, create {{variant_count}} distinct variants",
      "Generate hashtag suggestions as content_asset",
      "Emit posting strategy recommendation",
      "Include confidence scores"
    ],
    "validation_instructions": "Verify: (1) Content meets platform character limits, (2) Variants have distinct hooks, (3) All outputs emitted with correct output_type"
  }'::jsonb,
  ARRAY[60, 180],  -- 1-3 minutes estimated
  ARRAY[100, 300], -- $1-3 estimated
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
-- Twitter Thread Recipe
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
  'twitter-thread',
  'Twitter Thread',
  'Create an engaging Twitter/X thread breaking down complex topics. Includes numbered tweets with a compelling hook and clear call-to-action.',
  'content',
  'content',
  '{
    "purpose": "Break down complex topics into engaging thread format",
    "audience": "Twitter/X followers, professional audience",
    "outcome": "Ready-to-publish thread with hook, content, and CTA"
  }'::jsonb,
  '{
    "thread_length": {
      "type": "range",
      "default": 7,
      "min": 5,
      "max": 15,
      "description": "Number of tweets in the thread"
    },
    "tone": {
      "type": "select",
      "default": "authoritative",
      "options": ["professional", "casual", "authoritative", "educational", "provocative"],
      "description": "Thread tone and style"
    },
    "topic": {
      "type": "text",
      "optional": false,
      "max_length": 500,
      "description": "Topic to break down in the thread"
    },
    "include_stats": {
      "type": "boolean",
      "default": true,
      "description": "Include statistics and data points"
    }
  }'::jsonb,
  '{
    "format": "text",
    "output_types": ["content_draft", "content_asset"],
    "validation_rules": {
      "thread_count_matches": true,
      "character_limits_met": true,
      "hook_present": true
    }
  }'::jsonb,
  '{
    "substrate_blocks": {
      "semantic_types": ["finding", "insight", "statistic", "analysis"],
      "min_blocks": 0,
      "recency_preference": "last_90_days"
    },
    "reference_assets": {
      "required": false,
      "types": ["documents", "research"],
      "min_count": 0,
      "purpose": "Optional: Research or data to reference"
    }
  }'::jsonb,
  '{
    "system_prompt_additions": "You are creating a Twitter thread. Focus on: (1) Compelling hook tweet, (2) Clear progression, (3) Actionable takeaways, (4) Strong CTA. Each tweet must be under 280 characters. Number tweets (1/, 2/, etc.).",
    "task_breakdown": [
      "Research topic using substrate context",
      "Create hook tweet (Tweet 1/) - must grab attention",
      "Develop {{thread_length}} tweets with clear progression",
      "Include data points if include_stats=true",
      "End with call-to-action (retweet, follow, comment)",
      "Emit thread as single content_draft with all tweets",
      "Emit hashtag suggestions as content_asset"
    ],
    "validation_instructions": "Verify: (1) Thread has {{thread_length}} tweets, (2) Each tweet under 280 chars, (3) Hook is compelling, (4) CTA present"
  }'::jsonb,
  ARRAY[90, 240],  -- 1.5-4 minutes estimated
  ARRAY[150, 400], -- $1.50-4 estimated
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
-- Blog Article Recipe
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
  'blog-article',
  'Blog Article',
  'Generate SEO-optimized blog articles with proper structure, headings, and meta descriptions. Perfect for content marketing.',
  'content',
  'content',
  '{
    "purpose": "Create SEO-optimized blog content for thought leadership",
    "audience": "Website visitors, potential customers, industry professionals",
    "outcome": "Publish-ready article with SEO elements and CTAs"
  }'::jsonb,
  '{
    "article_length": {
      "type": "select",
      "default": "standard",
      "options": ["short", "standard", "long"],
      "description": "Article length (short: 500-800 words, standard: 800-1200 words, long: 1200-2000 words)"
    },
    "tone": {
      "type": "select",
      "default": "professional",
      "options": ["professional", "conversational", "educational", "thought-leadership"],
      "description": "Article tone and voice"
    },
    "topic": {
      "type": "text",
      "optional": false,
      "max_length": 500,
      "description": "Article topic or title idea"
    },
    "target_keywords": {
      "type": "text",
      "optional": true,
      "max_length": 200,
      "description": "SEO target keywords (comma-separated)"
    },
    "include_cta": {
      "type": "boolean",
      "default": true,
      "description": "Include call-to-action section"
    }
  }'::jsonb,
  '{
    "format": "markdown",
    "output_types": ["content_draft", "content_asset", "recommendation"],
    "validation_rules": {
      "word_count_in_range": true,
      "headings_present": true,
      "meta_description_present": true
    }
  }'::jsonb,
  '{
    "substrate_blocks": {
      "semantic_types": ["insight", "finding", "analysis", "statistic"],
      "min_blocks": 0,
      "recency_preference": "last_90_days"
    },
    "reference_assets": {
      "required": false,
      "types": ["documents", "research", "competitor_articles"],
      "min_count": 0,
      "purpose": "Optional: Research, data, or competitor examples"
    }
  }'::jsonb,
  '{
    "system_prompt_additions": "You are creating an SEO-optimized blog article. Focus on: (1) Compelling title, (2) Clear H2/H3 structure, (3) Natural keyword integration, (4) Actionable content, (5) Strong introduction and conclusion.",
    "task_breakdown": [
      "Research topic using substrate and web search",
      "Create compelling title and meta description",
      "Outline article with H2/H3 headings",
      "Write article matching {{article_length}} length",
      "Integrate keywords: {{target_keywords}} naturally",
      "Add CTA section if include_cta=true",
      "Emit article as content_draft",
      "Emit meta description and internal linking suggestions as content_asset"
    ],
    "validation_instructions": "Verify: (1) Word count matches length parameter, (2) Proper heading hierarchy, (3) Meta description under 155 chars, (4) Keywords integrated naturally"
  }'::jsonb,
  ARRAY[180, 420],  -- 3-7 minutes estimated
  ARRAY[300, 700],  -- $3-7 estimated
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
  content_recipe_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO content_recipe_count
  FROM work_recipes
  WHERE agent_type = 'content' AND status = 'active';

  RAISE NOTICE '✅ Content Recipes Migration Complete:';
  RAISE NOTICE '  - Active content recipes: %', content_recipe_count;
  RAISE NOTICE '';
  RAISE NOTICE '📋 Available Content Recipes:';
  RAISE NOTICE '  - social-media-post: LinkedIn/Twitter/Instagram posts';
  RAISE NOTICE '  - twitter-thread: Engaging Twitter threads';
  RAISE NOTICE '  - blog-article: SEO-optimized blog articles';
END $$;
