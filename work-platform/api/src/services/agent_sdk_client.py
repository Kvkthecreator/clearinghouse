"""
Agent SDK Client: Legacy wrapper - SDK removed.

NOTE: Post-SDK removal, this module is deprecated.
Use the new executor pattern instead:
- agents/research_executor.py (ResearchExecutor)
- agents/base_executor.py (BaseAgentExecutor)
- clients/anthropic_client.py (AnthropicDirectClient)

This file is kept for backward compatibility but all functionality
has been migrated to the direct Anthropic API pattern.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional
from uuid import UUID

logger = logging.getLogger(__name__)


class AgentSDKClient:
    """
    [DEPRECATED] Client for executing work sessions via Claude Agent SDK.

    NOTE: Claude Agent SDK has been removed. This class now raises
    NotImplementedError for all operations.

    Use the new executor pattern instead:
    - ResearchExecutor for research tasks
    - Direct workflow endpoints for agent execution
    """

    def __init__(self, substrate_client=None):
        """
        Initialize Agent SDK client (deprecated).

        Args:
            substrate_client: Optional substrate client (ignored)
        """
        logger.warning(
            "[AGENT SDK CLIENT] DEPRECATED: Claude Agent SDK removed. "
            "Use ResearchExecutor or workflow endpoints instead."
        )

    async def create_agent(
        self,
        agent_type: str,
        basket_id: str | UUID,
        workspace_id: str,
        work_ticket_id: str,
        user_id: str,
        agent_session=None,
    ):
        """
        [DEPRECATED] Create agent instance for work session execution.

        Raises:
            NotImplementedError: Always - SDK removed
        """
        raise NotImplementedError(
            "Claude Agent SDK has been removed. Use the workflow endpoints instead:\n"
            "- POST /api/work/research/execute for research tasks\n"
            "- POST /api/work/reporting/execute for reporting tasks"
        )

    async def provision_context_envelope(
        self,
        agent,
        task_document_id: UUID,
        basket_id: UUID
    ) -> Dict[str, Any]:
        """
        [DEPRECATED] Fetch and provision context envelope to agent.

        Raises:
            NotImplementedError: Always - SDK removed
        """
        raise NotImplementedError(
            "Claude Agent SDK has been removed. Context is now assembled "
            "directly by BaseAgentExecutor using SubstrateQueryAdapter."
        )


# Export deprecated class for backward compatibility
__all__ = ["AgentSDKClient"]
