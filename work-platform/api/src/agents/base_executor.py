"""
DEPRECATED: Use base_agent.py instead.

This file is kept for backward compatibility.
All functionality has been moved to base_agent.py with the *Agent naming pattern.

Migration:
    # Old (deprecated)
    from agents.base_executor import BaseAgentExecutor

    # New (preferred)
    from agents.base_agent import BaseAgent
"""

# Re-export from new location for backward compatibility
from .base_agent import BaseAgent as BaseAgentExecutor
from .base_agent import AgentContext

__all__ = ["BaseAgentExecutor", "AgentContext"]
