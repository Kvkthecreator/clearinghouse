"""
Model Configuration for Chat-First Architecture

Phase 5 Optimization: Model tiering and prompt caching configuration.

Tiering Strategy:
- Haiku: Fast, cheap operations (context reads, simple queries, classification)
- Sonnet: Orchestration, complex reasoning, tool use
- Opus: (Reserved) Deep analysis, strategic planning

Caching Strategy:
- System prompts: cache_control: ephemeral (auto-refreshes)
- Static context (brand, problem): Cached with long TTL
- Dynamic context (conversation): Not cached

See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class ModelTier(Enum):
    """Model tiers for cost/performance optimization."""
    HAIKU = "haiku"      # Fast, cheap: context reads, classification
    SONNET = "sonnet"    # Balanced: orchestration, tool use
    OPUS = "opus"        # Deep: analysis, strategic planning


@dataclass
class ModelConfig:
    """Configuration for a specific model."""
    model_id: str
    tier: ModelTier
    max_tokens: int = 4096
    supports_caching: bool = True
    cost_per_1k_input: float = 0.0  # USD
    cost_per_1k_output: float = 0.0


# Model registry - updated for Dec 2025
MODEL_REGISTRY: Dict[ModelTier, ModelConfig] = {
    ModelTier.HAIKU: ModelConfig(
        model_id="claude-3-5-haiku-20241022",
        tier=ModelTier.HAIKU,
        max_tokens=4096,
        supports_caching=True,
        cost_per_1k_input=0.00025,  # $0.25/M tokens
        cost_per_1k_output=0.00125,  # $1.25/M tokens
    ),
    ModelTier.SONNET: ModelConfig(
        model_id="claude-sonnet-4-20250514",
        tier=ModelTier.SONNET,
        max_tokens=8192,
        supports_caching=True,
        cost_per_1k_input=0.003,    # $3/M tokens
        cost_per_1k_output=0.015,   # $15/M tokens
    ),
    ModelTier.OPUS: ModelConfig(
        model_id="claude-opus-4-20250514",
        tier=ModelTier.OPUS,
        max_tokens=8192,
        supports_caching=True,
        cost_per_1k_input=0.015,    # $15/M tokens
        cost_per_1k_output=0.075,   # $75/M tokens
    ),
}


def get_model_for_tier(tier: ModelTier) -> ModelConfig:
    """Get model config for a tier."""
    return MODEL_REGISTRY[tier]


def get_model_id(tier: ModelTier) -> str:
    """Get model ID string for a tier."""
    return MODEL_REGISTRY[tier].model_id


# Operation to model tier mapping
@dataclass
class OperationConfig:
    """Configuration for an operation type."""
    default_tier: ModelTier
    max_tokens: int
    timeout_seconds: int = 60
    use_caching: bool = True


OPERATION_TIERS: Dict[str, OperationConfig] = {
    # Context operations - use Haiku for speed
    "read_context": OperationConfig(
        default_tier=ModelTier.HAIKU,
        max_tokens=1024,
        timeout_seconds=15,
        use_caching=False,  # Context is already fetched
    ),
    "list_context": OperationConfig(
        default_tier=ModelTier.HAIKU,
        max_tokens=512,
        timeout_seconds=10,
        use_caching=False,
    ),
    "classify_message": OperationConfig(
        default_tier=ModelTier.HAIKU,
        max_tokens=256,
        timeout_seconds=10,
        use_caching=True,
    ),

    # Conversation - use Sonnet for quality
    "tp_conversation": OperationConfig(
        default_tier=ModelTier.SONNET,
        max_tokens=4096,
        timeout_seconds=90,
        use_caching=True,
    ),
    "tp_with_tools": OperationConfig(
        default_tier=ModelTier.SONNET,
        max_tokens=4096,
        timeout_seconds=120,
        use_caching=True,
    ),

    # Work execution - Sonnet for reliability
    "research_execution": OperationConfig(
        default_tier=ModelTier.SONNET,
        max_tokens=8192,
        timeout_seconds=180,
        use_caching=True,
    ),
    "content_generation": OperationConfig(
        default_tier=ModelTier.SONNET,
        max_tokens=8192,
        timeout_seconds=180,
        use_caching=True,
    ),

    # Deep analysis - Opus for quality
    "strategic_analysis": OperationConfig(
        default_tier=ModelTier.OPUS,
        max_tokens=8192,
        timeout_seconds=300,
        use_caching=True,
    ),
}


def get_operation_config(operation: str) -> OperationConfig:
    """Get config for an operation type."""
    return OPERATION_TIERS.get(
        operation,
        OperationConfig(
            default_tier=ModelTier.SONNET,
            max_tokens=4096,
            timeout_seconds=90,
        )
    )


# Token budget management
@dataclass
class TokenBudget:
    """Token budget for a request."""
    max_input: int
    max_output: int
    reserved_for_context: int
    reserved_for_tools: int

    @property
    def available_for_prompt(self) -> int:
        """Tokens available for system prompt after reservations."""
        return self.max_input - self.reserved_for_context - self.reserved_for_tools


# Default budgets by operation
TOKEN_BUDGETS: Dict[str, TokenBudget] = {
    "tp_conversation": TokenBudget(
        max_input=16000,       # Plenty for conversation + context
        max_output=4096,
        reserved_for_context=6000,   # Room for context items
        reserved_for_tools=500,       # Tool definitions
    ),
    "research_execution": TokenBudget(
        max_input=32000,       # More room for research context
        max_output=8192,
        reserved_for_context=12000,
        reserved_for_tools=1000,
    ),
    "content_generation": TokenBudget(
        max_input=24000,
        max_output=8192,
        reserved_for_context=8000,
        reserved_for_tools=500,
    ),
}


def get_token_budget(operation: str) -> TokenBudget:
    """Get token budget for an operation."""
    return TOKEN_BUDGETS.get(
        operation,
        TokenBudget(
            max_input=16000,
            max_output=4096,
            reserved_for_context=6000,
            reserved_for_tools=500,
        )
    )


# Caching configuration
@dataclass
class CacheConfig:
    """Prompt caching configuration."""
    # Minimum tokens for caching to be worthwhile (Anthropic minimum is ~1024)
    min_cacheable_tokens: int = 1024

    # Cache control type
    cache_control_type: str = "ephemeral"

    # Which prompt sections to cache
    cache_system_prompt: bool = True
    cache_static_context: bool = True  # Foundation context items
    cache_tools: bool = True
    cache_conversation: bool = False    # Dynamic, don't cache


DEFAULT_CACHE_CONFIG = CacheConfig()


def build_cached_system_prompt(
    base_prompt: str,
    static_context: Optional[str] = None,
    config: CacheConfig = DEFAULT_CACHE_CONFIG,
) -> List[Dict[str, Any]]:
    """
    Build system prompt with cache control blocks.

    Anthropic caching works best when:
    1. Cached content is at the start of the prompt
    2. Cached blocks are sufficiently large (>1024 tokens)
    3. Static content is separated from dynamic content

    Args:
        base_prompt: Base system prompt (static)
        static_context: Static context like brand/problem (optional)
        config: Cache configuration

    Returns:
        List of content blocks with cache_control
    """
    blocks = []

    # Block 1: Base system prompt (always cached)
    if config.cache_system_prompt:
        blocks.append({
            "type": "text",
            "text": base_prompt,
            "cache_control": {"type": config.cache_control_type}
        })
    else:
        blocks.append({
            "type": "text",
            "text": base_prompt
        })

    # Block 2: Static context (cached if present)
    if static_context and config.cache_static_context:
        blocks.append({
            "type": "text",
            "text": f"\n\n# Foundation Context\n\n{static_context}",
            "cache_control": {"type": config.cache_control_type}
        })
    elif static_context:
        blocks.append({
            "type": "text",
            "text": f"\n\n# Foundation Context\n\n{static_context}"
        })

    return blocks


def estimate_prompt_tokens(text: str) -> int:
    """
    Rough token estimate for text.

    Anthropic models use ~4 chars per token on average.
    This is a rough estimate for budget planning.
    """
    return len(text) // 4


def should_use_caching(prompt_text: str, config: CacheConfig = DEFAULT_CACHE_CONFIG) -> bool:
    """
    Determine if caching should be used for a prompt.

    Args:
        prompt_text: The prompt text to potentially cache
        config: Cache configuration

    Returns:
        True if caching is worthwhile
    """
    estimated_tokens = estimate_prompt_tokens(prompt_text)
    return estimated_tokens >= config.min_cacheable_tokens
