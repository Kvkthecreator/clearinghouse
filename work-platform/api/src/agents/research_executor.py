"""
DEPRECATED: Use research_agent.py instead.

This file is kept for backward compatibility.
All functionality has been moved to research_agent.py with the *Agent naming pattern.

Migration:
    # Old (deprecated)
    from agents.research_executor import ResearchExecutor

    # New (preferred)
    from agents.research_agent import ResearchAgent
"""

# Re-export from new location for backward compatibility
from .research_agent import ResearchAgent as ResearchExecutor
from .research_agent import create_research_agent as create_research_executor

__all__ = ["ResearchExecutor", "create_research_executor"]
