"""
Token Budget Tracker

Phase 5 Optimization: Track token usage and enforce budgets.

Features:
- Real-time token tracking across conversation turns
- Budget enforcement with warnings
- Cost estimation
- Cache efficiency metrics

Usage:
    tracker = TokenTracker(budget=get_token_budget("tp_conversation"))
    tracker.add_turn(input_tokens=1000, output_tokens=500, cache_read=800)

    if tracker.is_over_budget():
        logger.warning(f"Token budget exceeded: {tracker.summary()}")
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Optional

from .model_config import TokenBudget, ModelConfig, MODEL_REGISTRY, ModelTier

logger = logging.getLogger(__name__)


@dataclass
class TurnMetrics:
    """Metrics for a single conversation turn."""
    turn_number: int
    input_tokens: int
    output_tokens: int
    cache_read_tokens: int = 0
    cache_creation_tokens: int = 0
    timestamp: datetime = field(default_factory=datetime.now)

    @property
    def total_tokens(self) -> int:
        """Total tokens for this turn."""
        return self.input_tokens + self.output_tokens

    @property
    def effective_input_tokens(self) -> int:
        """Input tokens after cache discount (cache read is ~90% cheaper)."""
        # Cache read tokens are charged at 10% of normal rate
        non_cached = self.input_tokens - self.cache_read_tokens
        cached_cost = self.cache_read_tokens * 0.1
        return int(non_cached + cached_cost)

    @property
    def cache_hit_ratio(self) -> float:
        """Ratio of tokens served from cache."""
        if self.input_tokens == 0:
            return 0.0
        return self.cache_read_tokens / self.input_tokens


@dataclass
class TokenTracker:
    """
    Track token usage across a conversation or execution.

    Provides:
    - Running totals
    - Budget enforcement
    - Cost estimation
    - Cache efficiency metrics
    """
    budget: TokenBudget
    model_config: ModelConfig = field(default_factory=lambda: MODEL_REGISTRY[ModelTier.SONNET])
    turns: List[TurnMetrics] = field(default_factory=list)

    @property
    def total_input_tokens(self) -> int:
        """Total input tokens across all turns."""
        return sum(t.input_tokens for t in self.turns)

    @property
    def total_output_tokens(self) -> int:
        """Total output tokens across all turns."""
        return sum(t.output_tokens for t in self.turns)

    @property
    def total_cache_read(self) -> int:
        """Total cache read tokens."""
        return sum(t.cache_read_tokens for t in self.turns)

    @property
    def total_cache_creation(self) -> int:
        """Total cache creation tokens."""
        return sum(t.cache_creation_tokens for t in self.turns)

    @property
    def effective_input_tokens(self) -> int:
        """Effective input tokens after cache discount."""
        return sum(t.effective_input_tokens for t in self.turns)

    @property
    def cache_hit_ratio(self) -> float:
        """Overall cache hit ratio."""
        if self.total_input_tokens == 0:
            return 0.0
        return self.total_cache_read / self.total_input_tokens

    @property
    def estimated_cost_usd(self) -> float:
        """Estimated cost in USD."""
        # Cache reads are 10% of normal input cost
        # Cache creation is 25% more than normal input cost
        normal_input = self.total_input_tokens - self.total_cache_read - self.total_cache_creation
        cache_read_cost = self.total_cache_read * 0.1 * self.model_config.cost_per_1k_input / 1000
        cache_creation_cost = self.total_cache_creation * 1.25 * self.model_config.cost_per_1k_input / 1000
        normal_input_cost = normal_input * self.model_config.cost_per_1k_input / 1000
        output_cost = self.total_output_tokens * self.model_config.cost_per_1k_output / 1000

        return cache_read_cost + cache_creation_cost + normal_input_cost + output_cost

    @property
    def savings_from_cache(self) -> float:
        """Estimated savings from caching in USD."""
        # If all cache reads were normal input
        full_cost_input = self.total_input_tokens * self.model_config.cost_per_1k_input / 1000
        output_cost = self.total_output_tokens * self.model_config.cost_per_1k_output / 1000

        return (full_cost_input + output_cost) - self.estimated_cost_usd

    def add_turn(
        self,
        input_tokens: int,
        output_tokens: int,
        cache_read_tokens: int = 0,
        cache_creation_tokens: int = 0,
    ) -> TurnMetrics:
        """
        Add a new turn's metrics.

        Args:
            input_tokens: Input tokens for this turn
            output_tokens: Output tokens for this turn
            cache_read_tokens: Tokens served from cache
            cache_creation_tokens: Tokens used to create cache

        Returns:
            The created TurnMetrics
        """
        turn = TurnMetrics(
            turn_number=len(self.turns) + 1,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cache_read_tokens=cache_read_tokens,
            cache_creation_tokens=cache_creation_tokens,
        )
        self.turns.append(turn)

        # Log if approaching budget limits
        if self.is_approaching_budget():
            logger.warning(
                f"[TOKEN_TRACKER] Approaching budget: "
                f"input={self.total_input_tokens}/{self.budget.max_input}, "
                f"output={self.total_output_tokens}/{self.budget.max_output}"
            )

        return turn

    def is_over_budget(self) -> bool:
        """Check if we've exceeded the token budget."""
        return (
            self.total_input_tokens > self.budget.max_input or
            self.total_output_tokens > self.budget.max_output
        )

    def is_approaching_budget(self, threshold: float = 0.8) -> bool:
        """Check if we're approaching the budget limit."""
        return (
            self.total_input_tokens > self.budget.max_input * threshold or
            self.total_output_tokens > self.budget.max_output * threshold
        )

    def remaining_input_tokens(self) -> int:
        """Remaining input tokens in budget."""
        return max(0, self.budget.max_input - self.total_input_tokens)

    def remaining_output_tokens(self) -> int:
        """Remaining output tokens in budget."""
        return max(0, self.budget.max_output - self.total_output_tokens)

    def summary(self) -> Dict:
        """Get a summary of token usage."""
        return {
            "turns": len(self.turns),
            "total_input_tokens": self.total_input_tokens,
            "total_output_tokens": self.total_output_tokens,
            "cache_read_tokens": self.total_cache_read,
            "cache_creation_tokens": self.total_cache_creation,
            "cache_hit_ratio": round(self.cache_hit_ratio, 3),
            "effective_input_tokens": self.effective_input_tokens,
            "estimated_cost_usd": round(self.estimated_cost_usd, 4),
            "savings_from_cache_usd": round(self.savings_from_cache, 4),
            "budget": {
                "max_input": self.budget.max_input,
                "max_output": self.budget.max_output,
                "remaining_input": self.remaining_input_tokens(),
                "remaining_output": self.remaining_output_tokens(),
            },
            "is_over_budget": self.is_over_budget(),
        }


def create_tracker(
    operation: str = "tp_conversation",
    model_tier: ModelTier = ModelTier.SONNET,
) -> TokenTracker:
    """
    Create a token tracker for an operation.

    Args:
        operation: Operation type (for budget selection)
        model_tier: Model tier (for cost estimation)

    Returns:
        Configured TokenTracker
    """
    from .model_config import get_token_budget

    return TokenTracker(
        budget=get_token_budget(operation),
        model_config=MODEL_REGISTRY[model_tier],
    )
