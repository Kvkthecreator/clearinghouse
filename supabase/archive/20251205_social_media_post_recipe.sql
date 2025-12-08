-- Migration: Add social-media-post recipe for Gemini Content Agent
-- Created: 2025-12-05
-- Purpose: Enable text + image content generation via Gemini

-- Insert social-media-post recipe
INSERT INTO work_recipes (
  slug,
  name,
  description,
  category,
  agent_type,
  deliverable_intent,
  configurable_parameters,
  output_specification,
  execution_template,
  status,
  schedulable,
  default_frequency,
  min_interval_hours
) VALUES (
  'social-media-post',
  'Social Media Post Generator',
  'Generate engaging social media posts with optional AI-generated images. Supports LinkedIn, Twitter/X, Instagram, and more.',
  'content',
  'content',
  '{
    "purpose": "Create engaging, platform-optimized social media content with optional AI-generated images",
    "audience": "Social media managers, marketers, content creators",
    "outcome": "Ready-to-publish social media posts with accompanying visuals"
  }'::jsonb,
  '{
    "topic": {
      "type": "string",
      "title": "Topic",
      "description": "What should the post be about?",
      "placeholder": "e.g., AI trends in 2025, product launch announcement",
      "required": true
    },
    "platform": {
      "type": "string",
      "title": "Platform",
      "description": "Which platform is this content for?",
      "options": ["linkedin_post", "twitter_post", "twitter_thread", "instagram_caption", "blog_article"],
      "default": "linkedin_post",
      "required": true
    },
    "tone": {
      "type": "string",
      "title": "Tone",
      "description": "What tone should the content have?",
      "options": ["professional", "casual", "inspiring", "authoritative", "friendly"],
      "default": "professional"
    },
    "target_audience": {
      "type": "string",
      "title": "Target Audience",
      "description": "Who is this content for?",
      "placeholder": "e.g., Tech professionals, startup founders"
    },
    "include_image": {
      "type": "boolean",
      "title": "Generate Image",
      "description": "Should an AI image be generated for this post?",
      "default": true
    },
    "image_style": {
      "type": "string",
      "title": "Image Style",
      "description": "What visual style for the generated image?",
      "options": ["modern professional", "minimalist tech", "vibrant creative", "corporate elegant", "startup casual"],
      "default": "modern professional"
    },
    "create_variants": {
      "type": "boolean",
      "title": "Create Variants",
      "description": "Generate alternative versions for A/B testing?",
      "default": false
    }
  }'::jsonb,
  '{
    "outputs": [
      {"type": "content_draft", "description": "Main social media post content"},
      {"type": "content_asset", "description": "Generated image (if enabled)"},
      {"type": "content_variant", "description": "Alternative versions (if variants enabled)"}
    ]
  }'::jsonb,
  '{
    "task_breakdown": [
      "Analyze topic and platform requirements",
      "Generate platform-optimized content",
      "Create AI image (if enabled)",
      "Generate variants (if enabled)"
    ],
    "provider": "gemini"
  }'::jsonb,
  'active',
  true,
  'custom',
  1
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  configurable_parameters = EXCLUDED.configurable_parameters,
  deliverable_intent = EXCLUDED.deliverable_intent,
  output_specification = EXCLUDED.output_specification,
  execution_template = EXCLUDED.execution_template,
  schedulable = EXCLUDED.schedulable,
  default_frequency = EXCLUDED.default_frequency,
  min_interval_hours = EXCLUDED.min_interval_hours,
  updated_at = NOW();

-- Add blog-article recipe (longer-form content with image)
INSERT INTO work_recipes (
  slug,
  name,
  description,
  category,
  agent_type,
  deliverable_intent,
  configurable_parameters,
  output_specification,
  execution_template,
  status,
  schedulable,
  default_frequency,
  min_interval_hours
) VALUES (
  'blog-article',
  'Blog Article Generator',
  'Generate SEO-optimized blog articles with header images. Supports various content lengths and styles.',
  'content',
  'content',
  '{
    "purpose": "Create SEO-optimized blog articles with professional header images",
    "audience": "Content marketers, bloggers, marketing teams",
    "outcome": "Ready-to-publish blog articles with header images"
  }'::jsonb,
  '{
    "topic": {
      "type": "string",
      "title": "Topic",
      "description": "What should the article be about?",
      "placeholder": "e.g., The Future of AI in Healthcare",
      "required": true
    },
    "word_count": {
      "type": "string",
      "title": "Article Length",
      "description": "How long should the article be?",
      "options": ["short (500-800 words)", "medium (800-1200 words)", "long (1200-1800 words)"],
      "default": "medium (800-1200 words)"
    },
    "tone": {
      "type": "string",
      "title": "Tone",
      "description": "What tone should the article have?",
      "options": ["professional", "conversational", "technical", "thought leadership"],
      "default": "professional"
    },
    "target_audience": {
      "type": "string",
      "title": "Target Audience",
      "description": "Who is this article for?",
      "placeholder": "e.g., Business decision makers"
    },
    "include_image": {
      "type": "boolean",
      "title": "Generate Header Image",
      "description": "Should an AI header image be generated?",
      "default": true
    },
    "seo_keywords": {
      "type": "string",
      "title": "SEO Keywords",
      "description": "Target keywords for SEO (comma-separated)",
      "placeholder": "e.g., AI healthcare, medical AI, health tech"
    }
  }'::jsonb,
  '{
    "outputs": [
      {"type": "content_draft", "description": "Blog article content"},
      {"type": "content_asset", "description": "Header image (if enabled)"}
    ]
  }'::jsonb,
  '{
    "task_breakdown": [
      "Research topic and SEO keywords",
      "Generate article structure",
      "Write full article content",
      "Create header image (if enabled)"
    ],
    "provider": "gemini"
  }'::jsonb,
  'active',
  true,
  'custom',
  24
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  configurable_parameters = EXCLUDED.configurable_parameters,
  deliverable_intent = EXCLUDED.deliverable_intent,
  output_specification = EXCLUDED.output_specification,
  execution_template = EXCLUDED.execution_template,
  schedulable = EXCLUDED.schedulable,
  default_frequency = EXCLUDED.default_frequency,
  min_interval_hours = EXCLUDED.min_interval_hours,
  updated_at = NOW();

-- Add marketing-content recipe (general marketing content)
INSERT INTO work_recipes (
  slug,
  name,
  description,
  category,
  agent_type,
  deliverable_intent,
  configurable_parameters,
  output_specification,
  execution_template,
  status,
  schedulable
) VALUES (
  'marketing-content',
  'Marketing Content Generator',
  'Generate marketing copy for various purposes: ads, landing pages, email campaigns. Includes optional image generation.',
  'content',
  'content',
  '{
    "purpose": "Create compelling marketing copy with optional visuals",
    "audience": "Marketing teams, product marketers, growth teams",
    "outcome": "Ready-to-use marketing content with images"
  }'::jsonb,
  '{
    "content_purpose": {
      "type": "string",
      "title": "Content Purpose",
      "description": "What type of marketing content?",
      "options": ["product launch", "feature announcement", "promotional campaign", "email newsletter", "landing page copy"],
      "default": "product launch",
      "required": true
    },
    "key_message": {
      "type": "string",
      "title": "Key Message",
      "description": "What is the main message to convey?",
      "placeholder": "e.g., Introducing our new AI-powered feature",
      "required": true
    },
    "call_to_action": {
      "type": "string",
      "title": "Call to Action",
      "description": "What action should readers take?",
      "placeholder": "e.g., Sign up for early access"
    },
    "tone": {
      "type": "string",
      "title": "Tone",
      "description": "What tone should the content have?",
      "options": ["professional", "exciting", "urgent", "friendly", "exclusive"],
      "default": "exciting"
    },
    "include_image": {
      "type": "boolean",
      "title": "Generate Image",
      "description": "Should an AI image be generated?",
      "default": true
    }
  }'::jsonb,
  '{
    "outputs": [
      {"type": "content_draft", "description": "Marketing content"},
      {"type": "content_asset", "description": "Marketing image (if enabled)"}
    ]
  }'::jsonb,
  '{
    "task_breakdown": [
      "Understand marketing goal and audience",
      "Generate persuasive copy",
      "Create supporting image (if enabled)"
    ],
    "provider": "gemini"
  }'::jsonb,
  'active',
  false
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  configurable_parameters = EXCLUDED.configurable_parameters,
  deliverable_intent = EXCLUDED.deliverable_intent,
  output_specification = EXCLUDED.output_specification,
  execution_template = EXCLUDED.execution_template,
  schedulable = EXCLUDED.schedulable,
  updated_at = NOW();

-- Verify insertions
SELECT slug, name, agent_type, status, schedulable FROM work_recipes
WHERE agent_type = 'content'
ORDER BY slug;
