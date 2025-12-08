-- Migration: Initial Agent Config Schemas v1
-- Date: 2025-01-14
-- Purpose: Define JSON Schema configs for research, content, and reporting agents
--
-- These schemas power dynamic config forms in the UI and provide structured
-- configuration for agent execution.

-- Research Agent Config Schema
UPDATE agent_catalog
SET config_schema = '{
  "type": "object",
  "properties": {
    "watchlist": {
      "type": "object",
      "title": "Watchlist Configuration",
      "description": "Topics and competitors to monitor",
      "properties": {
        "competitors": {
          "type": "array",
          "title": "Competitors",
          "description": "Company names to track (e.g., Anthropic, OpenAI)",
          "items": {"type": "string"},
          "default": []
        },
        "topics": {
          "type": "array",
          "title": "Topics",
          "description": "Keywords and topics to monitor",
          "items": {"type": "string"},
          "default": []
        },
        "data_sources": {
          "type": "array",
          "title": "Data Sources",
          "description": "Sources to monitor (web, social, news)",
          "items": {"type": "string", "enum": ["web", "social_media", "news", "research_papers"]},
          "default": ["web", "news"]
        }
      }
    },
    "alert_rules": {
      "type": "object",
      "title": "Alert Rules",
      "description": "When to surface findings",
      "properties": {
        "confidence_threshold": {
          "type": "number",
          "title": "Confidence Threshold",
          "description": "Minimum confidence to surface findings (0.0 - 1.0)",
          "minimum": 0,
          "maximum": 1,
          "default": 0.7
        },
        "priority_keywords": {
          "type": "array",
          "title": "Priority Keywords",
          "description": "Keywords that trigger immediate alerts",
          "items": {"type": "string"},
          "default": []
        }
      }
    },
    "output_preferences": {
      "type": "object",
      "title": "Output Preferences",
      "description": "How to format research findings",
      "properties": {
        "synthesis_mode": {
          "type": "string",
          "title": "Synthesis Mode",
          "description": "How to synthesize findings",
          "enum": ["detailed", "summary", "bullet_points"],
          "default": "summary"
        },
        "include_sources": {
          "type": "boolean",
          "title": "Include Sources",
          "description": "Include source links in findings",
          "default": true
        }
      }
    }
  }
}'::jsonb
WHERE agent_type = 'research';

-- Content Agent Config Schema
UPDATE agent_catalog
SET config_schema = '{
  "type": "object",
  "properties": {
    "brand_voice": {
      "type": "object",
      "title": "Brand Voice",
      "description": "Brand voice and tone settings",
      "properties": {
        "tone": {
          "type": "string",
          "title": "Tone",
          "description": "Default tone for content",
          "enum": ["professional", "casual", "enthusiastic", "educational", "witty"],
          "default": "professional"
        },
        "voice_guidelines": {
          "type": "string",
          "title": "Voice Guidelines",
          "description": "Additional voice guidance (reference uploaded brand assets for more detail)",
          "default": ""
        },
        "avoid_keywords": {
          "type": "array",
          "title": "Avoid Keywords",
          "description": "Words/phrases to avoid in content",
          "items": {"type": "string"},
          "default": []
        }
      }
    },
    "platforms": {
      "type": "object",
      "title": "Platform Settings",
      "description": "Platform-specific preferences",
      "properties": {
        "linkedin": {
          "type": "object",
          "title": "LinkedIn",
          "properties": {
            "enabled": {"type": "boolean", "default": true},
            "max_length": {"type": "number", "default": 3000},
            "include_hashtags": {"type": "boolean", "default": true},
            "hashtag_count": {"type": "number", "default": 3}
          }
        },
        "twitter": {
          "type": "object",
          "title": "Twitter/X",
          "properties": {
            "enabled": {"type": "boolean", "default": true},
            "thread_mode": {"type": "boolean", "default": false}
          }
        }
      }
    },
    "content_rules": {
      "type": "object",
      "title": "Content Rules",
      "description": "Content quality rules",
      "properties": {
        "require_call_to_action": {
          "type": "boolean",
          "title": "Require CTA",
          "description": "Always include call-to-action",
          "default": false
        },
        "emoji_usage": {
          "type": "string",
          "title": "Emoji Usage",
          "enum": ["none", "minimal", "moderate", "frequent"],
          "default": "minimal"
        }
      }
    }
  }
}'::jsonb
WHERE agent_type = 'content';

-- Reporting Agent Config Schema
UPDATE agent_catalog
SET config_schema = '{
  "type": "object",
  "properties": {
    "report_preferences": {
      "type": "object",
      "title": "Report Preferences",
      "description": "Default report settings",
      "properties": {
        "default_format": {
          "type": "string",
          "title": "Default Format",
          "description": "Default output format",
          "enum": ["pdf", "markdown", "html", "docx"],
          "default": "pdf"
        },
        "include_toc": {
          "type": "boolean",
          "title": "Include Table of Contents",
          "default": true
        },
        "include_executive_summary": {
          "type": "boolean",
          "title": "Include Executive Summary",
          "default": true
        }
      }
    },
    "data_sources": {
      "type": "object",
      "title": "Data Sources",
      "description": "Default data sources for reports",
      "properties": {
        "substrate_blocks": {
          "type": "boolean",
          "title": "Use Substrate Blocks",
          "description": "Pull data from substrate knowledge blocks",
          "default": true
        },
        "external_apis": {
          "type": "array",
          "title": "External APIs",
          "description": "External data sources to integrate",
          "items": {"type": "string"},
          "default": []
        }
      }
    },
    "formatting": {
      "type": "object",
      "title": "Formatting",
      "description": "Visual formatting preferences",
      "properties": {
        "chart_style": {
          "type": "string",
          "title": "Chart Style",
          "enum": ["minimal", "corporate", "modern", "colorful"],
          "default": "corporate"
        },
        "font_family": {
          "type": "string",
          "title": "Font Family",
          "enum": ["arial", "calibri", "times_new_roman", "helvetica"],
          "default": "calibri"
        }
      }
    }
  }
}'::jsonb
WHERE agent_type = 'reporting';

-- Verify updates
SELECT
  agent_type,
  name,
  jsonb_pretty(config_schema) as schema
FROM agent_catalog
ORDER BY agent_type;
