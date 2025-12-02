-- Seed Recipe Context Declarations
-- Date: 2025-12-02
-- Purpose: Add context role requirements and outputs to existing recipes
-- Canon ref: /docs/canon/CONTEXT_ROLES_ARCHITECTURE.md

BEGIN;

-- =====================================================
-- Content Recipes: Consume foundation + insight roles
-- =====================================================

-- Blog Article: Needs customer context, optionally trend insights
UPDATE work_recipes
SET context_requirements = jsonb_set(
  context_requirements,
  '{roles}',
  '["customer", "problem"]'::jsonb
) || jsonb_build_object('roles_optional', '["brand_voice", "trend_digest"]'::jsonb)
WHERE slug = 'blog-article';

-- Social Media Post: Needs brand voice and customer
UPDATE work_recipes
SET context_requirements = jsonb_set(
  context_requirements,
  '{roles}',
  '["customer"]'::jsonb
) || jsonb_build_object('roles_optional', '["brand_voice", "trend_digest"]'::jsonb)
WHERE slug = 'social-media-post';

-- Twitter Thread: Needs customer, optionally insights
UPDATE work_recipes
SET context_requirements = jsonb_set(
  context_requirements,
  '{roles}',
  '["customer"]'::jsonb
) || jsonb_build_object('roles_optional', '["brand_voice", "trend_digest"]'::jsonb)
WHERE slug = 'twitter-thread';

-- =====================================================
-- Reporting Recipes: Consume foundation roles
-- =====================================================

-- Executive Summary: Needs problem, customer, vision
UPDATE work_recipes
SET context_requirements = jsonb_set(
  context_requirements,
  '{roles}',
  '["problem", "customer", "vision"]'::jsonb
)
WHERE slug = 'executive-summary-deck';

-- =====================================================
-- Research Recipes: Consume foundation, produce insights
-- =====================================================

-- Research Deep Dive: Consumes customer/problem, produces insights
-- This is a context-producing recipe
UPDATE work_recipes
SET
  context_requirements = jsonb_set(
    context_requirements,
    '{roles}',
    '["customer", "problem"]'::jsonb
  ),
  context_outputs = '{
    "role": "market_signal",
    "refresh_policy": {
      "ttl_hours": 336,
      "auto_promote": false
    }
  }'::jsonb
WHERE slug = 'research-deep-dive';

-- =====================================================
-- Add new context-producing recipes
-- =====================================================

-- Weekly Trend Scan: Produces trend_digest
INSERT INTO work_recipes (
  slug, name, description, agent_type, status,
  context_requirements, context_outputs,
  configurable_parameters, output_specification,
  execution_template, deliverable_intent, metadata, version
) VALUES (
  'weekly-trend-scan',
  'Weekly Trend Scan',
  'Scans industry trends and produces a trend digest for content planning. Run weekly for fresh insights.',
  'research',
  'active',
  '{
    "roles": ["customer", "problem"],
    "roles_optional": ["vision"],
    "substrate_blocks": {
      "min_blocks": 0,
      "semantic_types": ["insight", "finding"],
      "recency_preference": "last_90_days"
    }
  }'::jsonb,
  '{
    "role": "trend_digest",
    "refresh_policy": {
      "ttl_hours": 168,
      "auto_promote": false
    }
  }'::jsonb,
  '{
    "industry_focus": {"type": "text", "label": "Industry Focus", "placeholder": "e.g., SaaS, E-commerce, FinTech"},
    "trend_sources": {"type": "multiselect", "label": "Trend Sources", "options": ["Industry publications", "Social media", "Competitor activity", "Market reports"]}
  }'::jsonb,
  '{
    "format": "structured_analysis",
    "sections": ["Executive Summary", "Top Trends", "Opportunities", "Threats", "Recommendations"]
  }'::jsonb,
  '{
    "task_breakdown": [
      "Load customer and problem context from substrate",
      "Research current industry trends using provided sources",
      "Analyze trends for relevance to customer segment",
      "Identify opportunities and threats",
      "Synthesize into digestible trend report",
      "Emit work_output targeting trend_digest role"
    ],
    "system_prompt_additions": "You are producing a Trend Digest that will inform content strategy. Focus on actionable trends with clear implications. Be specific about why each trend matters for this audience."
  }'::jsonb,
  '{
    "outcome": "Fresh understanding of industry trends relevant to target audience",
    "purpose": "Keep content strategy informed by current market movements",
    "audience": "Content strategists, marketing team"
  }'::jsonb,
  '{}'::jsonb,
  1
) ON CONFLICT (slug) DO UPDATE SET
  context_requirements = EXCLUDED.context_requirements,
  context_outputs = EXCLUDED.context_outputs;

-- Competitor Intelligence: Produces competitor_snapshot
INSERT INTO work_recipes (
  slug, name, description, agent_type, status,
  context_requirements, context_outputs,
  configurable_parameters, output_specification,
  execution_template, deliverable_intent, metadata, version
) VALUES (
  'competitor-intelligence',
  'Competitor Intelligence',
  'Analyzes competitor positioning, messaging, and strategy. Run monthly or when competitors make moves.',
  'research',
  'active',
  '{
    "roles": ["customer", "problem", "solution"],
    "roles_optional": ["vision"],
    "substrate_blocks": {
      "min_blocks": 0,
      "semantic_types": ["competitor_data", "finding"],
      "recency_preference": "last_90_days"
    }
  }'::jsonb,
  '{
    "role": "competitor_snapshot",
    "refresh_policy": {
      "ttl_hours": 720,
      "auto_promote": false
    }
  }'::jsonb,
  '{
    "competitors": {"type": "text", "label": "Competitors to Analyze", "placeholder": "Comma-separated list of competitor names"},
    "focus_areas": {"type": "multiselect", "label": "Focus Areas", "options": ["Pricing", "Features", "Messaging", "Market position", "Recent launches"]}
  }'::jsonb,
  '{
    "format": "competitive_analysis",
    "sections": ["Competitor Overview", "Positioning Analysis", "Feature Comparison", "Strategic Implications"]
  }'::jsonb,
  '{
    "task_breakdown": [
      "Load customer, problem, and solution context",
      "Research each competitor across focus areas",
      "Analyze positioning and messaging strategies",
      "Compare features and market position",
      "Identify competitive advantages and gaps",
      "Synthesize strategic implications",
      "Emit work_output targeting competitor_snapshot role"
    ],
    "system_prompt_additions": "You are producing a Competitor Snapshot for strategic planning. Be objective, cite sources where possible, and focus on actionable intelligence."
  }'::jsonb,
  '{
    "outcome": "Clear picture of competitive landscape and positioning opportunities",
    "purpose": "Inform product and marketing strategy with competitive intelligence",
    "audience": "Product team, marketing strategy, leadership"
  }'::jsonb,
  '{}'::jsonb,
  1
) ON CONFLICT (slug) DO UPDATE SET
  context_requirements = EXCLUDED.context_requirements,
  context_outputs = EXCLUDED.context_outputs;

-- Brand Voice Extraction: Produces brand_voice
INSERT INTO work_recipes (
  slug, name, description, agent_type, status,
  context_requirements, context_outputs,
  configurable_parameters, output_specification,
  execution_template, deliverable_intent, metadata, version
) VALUES (
  'brand-voice-extraction',
  'Brand Voice Extraction',
  'Analyzes existing content to extract and codify brand voice guidelines. Run once, update when brand evolves.',
  'research',
  'active',
  '{
    "roles": ["customer", "vision"],
    "roles_optional": ["problem"],
    "reference_assets": {
      "types": ["documents", "prior_content"],
      "purpose": "Existing brand content, marketing materials, or style guides",
      "required": true,
      "min_count": 3
    }
  }'::jsonb,
  '{
    "role": "brand_voice",
    "refresh_policy": {
      "ttl_hours": 2160,
      "auto_promote": false
    }
  }'::jsonb,
  '{
    "content_samples": {"type": "text", "label": "Content Samples", "placeholder": "Paste 3-5 examples of your best content"},
    "brand_values": {"type": "text", "label": "Brand Values", "placeholder": "What does your brand stand for?"}
  }'::jsonb,
  '{
    "format": "brand_guidelines",
    "sections": ["Voice Characteristics", "Tone Guidelines", "Do/Don''t Examples", "Vocabulary", "Style Rules"]
  }'::jsonb,
  '{
    "task_breakdown": [
      "Analyze provided content samples for voice patterns",
      "Identify consistent tone, vocabulary, and style elements",
      "Map voice characteristics to audience and vision",
      "Create actionable guidelines with examples",
      "Document do/don''t rules for content creation",
      "Emit work_output targeting brand_voice role"
    ],
    "system_prompt_additions": "You are extracting and codifying brand voice. Be precise and provide concrete examples. The output should be immediately usable by content creators."
  }'::jsonb,
  '{
    "outcome": "Codified brand voice guidelines that ensure consistent content",
    "purpose": "Enable anyone to write on-brand content",
    "audience": "Content creators, marketing team, external writers"
  }'::jsonb,
  '{}'::jsonb,
  1
) ON CONFLICT (slug) DO UPDATE SET
  context_requirements = EXCLUDED.context_requirements,
  context_outputs = EXCLUDED.context_outputs;

COMMIT;
