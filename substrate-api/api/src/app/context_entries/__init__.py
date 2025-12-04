"""Context Items module for structured multi-modal context management.

This module implements the unified Context Items architecture as defined in:
- ADR: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md

Context Items provide:
- Tiered context (foundation, working, ephemeral)
- Schema-driven structured fields per item type
- Multi-modal content (text + embedded asset references)
- Token-efficient context injection for work recipes
- Completeness tracking and validation
- Equal human + agent authorship
"""

from .routes import router

__all__ = ["router"]
