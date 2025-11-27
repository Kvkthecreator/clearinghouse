"""
YARNNN Agents - Direct Anthropic API Integration

This package contains agents that use direct Anthropic API calls
instead of the Claude Agent SDK. First-principled design with work-oriented
context assembly.

Agents:
- BaseAgent: Shared execution logic
- ResearchAgent: Intelligence gathering with web search
- ContentAgent: Content generation with tools pattern
- ReportingAgent: Document generation with Skills API
- ThinkingPartnerAgent: Interactive ideation (scaffold)

Architecture:
- No session persistence (context assembled per-call)
- Direct API calls via AnthropicDirectClient
- Tool execution via substrate-API HTTP
- Streaming support for frontend updates
"""

# New *Agent pattern (primary exports)
from .base_agent import BaseAgent, AgentContext
from .research_agent import ResearchAgent, create_research_agent
from .content_agent import ContentAgent, create_content_agent
from .reporting_agent import ReportingAgent, create_reporting_agent
from .thinking_partner_agent import ThinkingPartnerAgent, create_thinking_partner_agent

# Backward compatibility exports (deprecated, use *Agent pattern)
from .base_agent import BaseAgentExecutor  # Alias for BaseAgent
from .research_agent import ResearchExecutor, create_research_executor  # Aliases
from .content_agent import ContentExecutor, create_content_executor  # Aliases
from .reporting_agent import ReportingExecutor, create_reporting_executor  # Aliases
from .thinking_partner_agent import ThinkingPartnerExecutor, create_thinking_partner_executor  # Aliases

__all__ = [
    # New pattern (preferred)
    "BaseAgent",
    "AgentContext",
    "ResearchAgent",
    "create_research_agent",
    "ContentAgent",
    "create_content_agent",
    "ReportingAgent",
    "create_reporting_agent",
    "ThinkingPartnerAgent",
    "create_thinking_partner_agent",
    # Backward compatibility (deprecated)
    "BaseAgentExecutor",
    "ResearchExecutor",
    "create_research_executor",
    "ContentExecutor",
    "create_content_executor",
    "ReportingExecutor",
    "create_reporting_executor",
    "ThinkingPartnerExecutor",
    "create_thinking_partner_executor",
]
