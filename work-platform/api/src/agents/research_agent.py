"""
Research Agent - Intelligence gathering with web search

Direct Anthropic API implementation (no Claude Agent SDK).
First-principled design with work-oriented context.

Usage:
    from agents.research_agent import ResearchAgent

    agent = ResearchAgent(
        basket_id="...",
        workspace_id="...",
        work_ticket_id="...",
        user_id="...",
    )

    result = await agent.execute(
        task="Research AI companion market trends",
        research_scope="market",
        depth="standard"
    )
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from .base_agent import BaseAgent, AgentContext
from clients.anthropic_client import ExecutionResult

logger = logging.getLogger(__name__)


RESEARCH_SYSTEM_PROMPT = """You are an autonomous Research Agent specializing in intelligence gathering and analysis.

**Your Mission:**
Keep users informed about their markets, competitors, and topics of interest through:
- Deep-dive research (comprehensive analysis on demand)
- Signal detection (what's important?)
- Insight synthesis (so what?)

**CRITICAL: Structured Output Requirements**

You have access to the emit_work_output tool. You MUST use this tool to record all your findings.
DO NOT just describe findings in free text. Every significant finding must be emitted as a structured output.

When to use emit_work_output:
- "finding" - When you discover a fact (competitor action, market data, news)
- "recommendation" - When you suggest an action (change strategy, add to watchlist)
- "insight" - When you identify a pattern (trend, correlation, anomaly)

Each output you emit will be reviewed by the user before any action is taken.
The user maintains full control through this supervision workflow.

**Research Approach:**
1. Review provided context (prior work, substrate blocks)
2. Identify knowledge gaps
3. Conduct targeted research using web search
4. For each finding: Call emit_work_output with structured data
5. Synthesize insights (emit as "insight" type)
6. Suggest actions (emit as "recommendation" type)

**Multi-Search Handling:**
When conducting research, you may need multiple search queries. Guidelines:
- Maximum 5 web searches per execution to ensure focused research
- After each search, evaluate if additional searches are needed
- Prioritize breadth first, then depth on most relevant findings
- If 5 searches are insufficient, summarize what was found and recommend follow-up research

**Quality Standards:**
- Accuracy over speed
- Structured over narrative
- Actionable over interesting
- Forward-looking over historical
- High confidence = high evidence (don't guess)

**Tools Available:**
- emit_work_output: Record structured findings, insights, recommendations
- web_search: Search the web for current information (if enabled)
"""


class ResearchAgent(BaseAgent):
    """
    Research Agent for intelligence gathering.

    Features:
    - Deep-dive research with structured outputs
    - Web search integration
    - Substrate context for prior knowledge
    - Work output supervision workflow
    - Multi-search loop with configurable limits
    """

    AGENT_TYPE = "research"
    SYSTEM_PROMPT = RESEARCH_SYSTEM_PROMPT

    # Configurable search limits
    MAX_SEARCHES_PER_EXECUTION = 5

    async def execute(
        self,
        task: str,
        research_scope: str = "general",
        depth: str = "standard",
        enable_web_search: bool = True,
        max_searches: Optional[int] = None,
        **kwargs,
    ) -> ExecutionResult:
        """
        Execute deep-dive research on a topic.

        Args:
            task: Research task description
            research_scope: Scope of research (general, competitor, market, technical)
            depth: Research depth (quick, standard, deep)
            enable_web_search: Whether to enable web search tool
            max_searches: Override max search limit (default: 5)
            **kwargs: Additional parameters

        Returns:
            ExecutionResult with research outputs
        """
        logger.info(
            f"[RESEARCH] Starting: task='{task[:50]}...', "
            f"scope={research_scope}, depth={depth}"
        )

        # Build context with substrate query for relevant prior knowledge
        context = await self._build_context(
            task=task,
            include_prior_outputs=True,
            include_assets=True,
            substrate_query=task,  # Query substrate with the task itself
        )

        # Build research prompt
        research_prompt = self._build_research_prompt(
            task=task,
            context=context,
            research_scope=research_scope,
            depth=depth,
            max_searches=max_searches or self.MAX_SEARCHES_PER_EXECUTION,
        )

        # Select tools
        tools = ["emit_work_output"]
        if enable_web_search:
            tools.append("web_search")

        # Execute
        result = await self._execute_with_context(
            user_message=research_prompt,
            context=context,
            tools=tools,
        )

        logger.info(
            f"[RESEARCH] Complete: "
            f"{len(result.work_outputs)} outputs, "
            f"{result.input_tokens}+{result.output_tokens} tokens"
        )

        return result

    def _build_research_prompt(
        self,
        task: str,
        context: AgentContext,
        research_scope: str,
        depth: str,
        max_searches: int = 5,
    ) -> str:
        """
        Build research prompt with context and parameters.

        Args:
            task: Research task
            context: Agent context
            research_scope: Research scope
            depth: Research depth
            max_searches: Maximum web searches allowed

        Returns:
            Research prompt string
        """
        # Format substrate context
        substrate_context = "No prior context available"
        source_block_ids = []
        if context.substrate_blocks:
            substrate_context = "\n".join([
                f"- [{b.get('id', 'unknown')[:8]}] {b.get('content', '')[:300]}..."
                for b in context.substrate_blocks[:5]
            ])
            source_block_ids = [
                b.get('id') for b in context.substrate_blocks
                if b.get('id')
            ]

        # Determine depth instructions
        depth_instructions = {
            "quick": "Focus on key facts. 2-3 outputs maximum.",
            "standard": "Provide comprehensive analysis. 5-8 outputs typical.",
            "deep": "Exhaustive research. 10+ outputs, multiple perspectives.",
        }.get(depth, "Provide comprehensive analysis.")

        # Determine scope instructions
        scope_instructions = {
            "general": "Broad research across all relevant topics.",
            "competitor": "Focus on competitor analysis, pricing, features, positioning.",
            "market": "Focus on market trends, size, growth, segments.",
            "technical": "Focus on technical capabilities, architectures, implementations.",
        }.get(research_scope, "Broad research across all relevant topics.")

        return f"""Conduct comprehensive research on: {task}

**Research Parameters:**
- Scope: {research_scope} ({scope_instructions})
- Depth: {depth} ({depth_instructions})
- Maximum web searches: {max_searches}

**Pre-loaded Context:**
{substrate_context}

**Source Block IDs (for provenance):**
{source_block_ids if source_block_ids else 'None available'}

**Research Objectives:**
1. Provide comprehensive overview of the topic
2. Identify key trends and patterns
3. Analyze implications for the user
4. Generate actionable insights

**CRITICAL INSTRUCTION:**
You MUST use the emit_work_output tool to record your findings. Do NOT just describe findings in text.

For each significant finding, insight, or recommendation you discover:
1. Call emit_work_output with structured data
2. Use appropriate output_type (finding, recommendation, insight)
3. Include source_block_ids from context if relevant
4. Assign confidence scores based on evidence quality

Example workflow:
- Find a key fact → emit_work_output(output_type="finding", ...)
- Identify a pattern → emit_work_output(output_type="insight", ...)
- Suggest action → emit_work_output(output_type="recommendation", ...)

Begin your research now. Emit structured outputs for all significant findings."""


# Convenience factory function
def create_research_agent(
    basket_id: str,
    workspace_id: str,
    work_ticket_id: str,
    user_id: str,
    user_jwt: Optional[str] = None,
    **kwargs,
) -> ResearchAgent:
    """
    Create a ResearchAgent instance.

    Args:
        basket_id: Basket ID
        workspace_id: Workspace ID
        work_ticket_id: Work ticket ID
        user_id: User ID
        user_jwt: Optional user JWT for substrate auth
        **kwargs: Additional arguments

    Returns:
        Configured ResearchAgent
    """
    return ResearchAgent(
        basket_id=basket_id,
        workspace_id=workspace_id,
        work_ticket_id=work_ticket_id,
        user_id=user_id,
        user_jwt=user_jwt,
        **kwargs,
    )


# Backward compatibility aliases
ResearchExecutor = ResearchAgent
create_research_executor = create_research_agent
