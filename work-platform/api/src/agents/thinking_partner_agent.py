"""
Thinking Partner Agent - Interactive ideation and brainstorming (SCAFFOLD)

This is a minimal scaffold for tech stack alignment. Full implementation
will follow the same patterns as other agents once requirements are finalized.

The ThinkingPartnerAgent differs from other agents:
- Interactive, conversational flow (not task-based)
- May require conversation history (different from work-oriented pattern)
- Real-time collaboration focus

Usage (when implemented):
    from agents.thinking_partner_agent import ThinkingPartnerAgent

    agent = ThinkingPartnerAgent(
        basket_id="...",
        workspace_id="...",
        work_ticket_id="...",
        user_id="...",
    )

    result = await agent.execute(
        task="Brainstorm product positioning strategies",
    )
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from .base_agent import BaseAgent, AgentContext
from clients.anthropic_client import ExecutionResult

logger = logging.getLogger(__name__)


THINKING_PARTNER_SYSTEM_PROMPT = """You are a Thinking Partner Agent - an interactive collaborator for brainstorming and ideation.

**Your Role:**
Help users think through problems, explore ideas, and develop strategies through:
- Socratic questioning
- Perspective-taking
- Pattern recognition
- Creative exploration

**Interaction Style:**
- Conversational and collaborative
- Ask probing questions
- Offer multiple perspectives
- Build on user ideas
- Challenge assumptions constructively

**Output Approach:**
Unlike task-oriented agents, you engage in dialogue. However, when valuable insights emerge:
- Capture key insights as work_outputs
- Document decision points
- Record action items identified

**Tools Available:**
- emit_work_output: Capture valuable insights, decisions, and action items

NOTE: This is a scaffold implementation. Full interactive capabilities
will be added in a future iteration.
"""


class ThinkingPartnerAgent(BaseAgent):
    """
    Thinking Partner Agent for interactive ideation and brainstorming.

    SCAFFOLD STATUS: This is a minimal implementation for tech stack alignment.
    Full implementation requires:
    - Conversation history management
    - Real-time streaming collaboration
    - Interactive questioning flows

    Features (planned):
    - Socratic questioning
    - Multi-perspective exploration
    - Insight capture and synthesis
    - Decision framework support
    """

    AGENT_TYPE = "thinking_partner"
    SYSTEM_PROMPT = THINKING_PARTNER_SYSTEM_PROMPT

    async def execute(
        self,
        task: str,
        thinking_mode: str = "brainstorm",
        capture_insights: bool = True,
        **kwargs,
    ) -> ExecutionResult:
        """
        Execute thinking partner session.

        SCAFFOLD: Basic implementation that follows task-oriented pattern.
        Full implementation will support interactive conversation flow.

        Args:
            task: Topic or problem to explore
            thinking_mode: Mode of thinking (brainstorm, analyze, challenge, explore)
            capture_insights: Whether to emit insights as work_outputs
            **kwargs: Additional parameters

        Returns:
            ExecutionResult with insights and recommendations
        """
        logger.info(
            f"[THINKING_PARTNER] Starting: task='{task[:50]}...', "
            f"mode={thinking_mode}"
        )

        # Build context (minimal for thinking partner)
        context = await self._build_context(
            task=task,
            include_prior_outputs=True,
            include_assets=False,
            substrate_query=task,
        )

        # Build thinking prompt
        thinking_prompt = self._build_thinking_prompt(
            task=task,
            context=context,
            thinking_mode=thinking_mode,
            capture_insights=capture_insights,
        )

        # Select tools
        tools = ["emit_work_output"] if capture_insights else []

        # Execute
        result = await self._execute_with_context(
            user_message=thinking_prompt,
            context=context,
            tools=tools,
        )

        logger.info(
            f"[THINKING_PARTNER] Complete: "
            f"{len(result.work_outputs)} insights captured, "
            f"{result.input_tokens}+{result.output_tokens} tokens"
        )

        return result

    def _build_thinking_prompt(
        self,
        task: str,
        context: AgentContext,
        thinking_mode: str,
        capture_insights: bool,
    ) -> str:
        """
        Build thinking partner prompt.

        Args:
            task: Topic/problem to explore
            context: Agent context
            thinking_mode: Mode of thinking
            capture_insights: Whether to capture insights

        Returns:
            Thinking prompt string
        """
        # Mode-specific instructions
        mode_instructions = {
            "brainstorm": "Generate diverse ideas without judgment. Quantity over quality initially.",
            "analyze": "Break down the problem systematically. Identify root causes and implications.",
            "challenge": "Play devil's advocate. Question assumptions and explore edge cases.",
            "explore": "Map the problem space. Identify adjacent areas and connections.",
        }.get(thinking_mode, "Explore the topic from multiple angles.")

        # Prior context
        prior_context = "No prior exploration available"
        if context.substrate_blocks:
            prior_context = "\n".join([
                f"- {b.get('content', '')[:200]}..."
                for b in context.substrate_blocks[:3]
            ])

        capture_instruction = ""
        if capture_insights:
            capture_instruction = """
**Insight Capture:**
When you identify a valuable insight, decision point, or action item:
- Use emit_work_output with type "insight" for key realizations
- Use emit_work_output with type "recommendation" for action items
- Use emit_work_output with type "finding" for important facts discovered
"""

        return f"""Let's think through: {task}

**Thinking Mode:** {thinking_mode}
{mode_instructions}

**Prior Context:**
{prior_context}
{capture_instruction}

**Approach:**
1. Understand the core question/problem
2. Explore multiple perspectives
3. Identify patterns and connections
4. Surface actionable insights
5. Suggest next steps

Begin exploration now. Think step-by-step and capture key insights."""


# Convenience factory function
def create_thinking_partner_agent(
    basket_id: str,
    workspace_id: str,
    work_ticket_id: str,
    user_id: str,
    user_jwt: Optional[str] = None,
    **kwargs,
) -> ThinkingPartnerAgent:
    """
    Create a ThinkingPartnerAgent instance.

    Args:
        basket_id: Basket ID
        workspace_id: Workspace ID
        work_ticket_id: Work ticket ID
        user_id: User ID
        user_jwt: Optional user JWT for substrate auth
        **kwargs: Additional arguments

    Returns:
        Configured ThinkingPartnerAgent
    """
    return ThinkingPartnerAgent(
        basket_id=basket_id,
        workspace_id=workspace_id,
        work_ticket_id=work_ticket_id,
        user_id=user_id,
        user_jwt=user_jwt,
        **kwargs,
    )


# Backward compatibility alias
ThinkingPartnerExecutor = ThinkingPartnerAgent
create_thinking_partner_executor = create_thinking_partner_agent
