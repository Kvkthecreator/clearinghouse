"""
Direct Anthropic API Client

Replaces ClaudeSDKClient with direct anthropic.AsyncAnthropic() calls.
First-principled design: no session persistence, no conversation history.

Architecture:
- Work-oriented context (project, request, ticket) assembled per-call
- Streaming support for frontend progress updates
- Tool execution via substrate-API HTTP calls
- Token tracking for cost analysis

Usage:
    from clients.anthropic_client import AnthropicDirectClient

    client = AnthropicDirectClient()
    result = await client.execute(
        system_prompt="You are a research agent...",
        user_message="Research AI trends",
        tools=["web_search", "emit_work_output"],
        tool_context={"basket_id": "...", "work_ticket_id": "..."},
    )
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass, field
from typing import Any, AsyncGenerator, Callable, Dict, List, Optional

import anthropic
import httpx

logger = logging.getLogger(__name__)

# Substrate API configuration
SUBSTRATE_API_URL = os.getenv("SUBSTRATE_API_URL", "https://yarnnn-substrate-api.onrender.com")
SUBSTRATE_SERVICE_SECRET = os.getenv("SUBSTRATE_SERVICE_SECRET", "")


@dataclass
class ToolCall:
    """Represents a tool call from Claude."""
    id: str
    name: str
    input: Dict[str, Any]
    result: Optional[Dict[str, Any]] = None


@dataclass
class ExecutionResult:
    """Result of an agent execution."""
    response_text: str
    tool_calls: List[ToolCall] = field(default_factory=list)
    work_outputs: List[Dict[str, Any]] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_creation_tokens: int = 0
    stop_reason: str = ""
    model: str = ""


class AnthropicDirectClient:
    """
    Direct Anthropic API client for agent execution.

    Key Design Principles:
    - No session persistence (first-principled context)
    - Direct API calls (no SDK wrapper overhead)
    - Built-in tool execution (emit_work_output, web_search)
    - Streaming support for real-time updates
    - Token tracking for cost analysis
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = "claude-sonnet-4-20250514",
        max_tokens: int = 8192,
    ):
        """
        Initialize direct Anthropic client.

        Args:
            api_key: Anthropic API key (from env if None)
            model: Claude model to use
            max_tokens: Maximum tokens for response
        """
        self.api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
        if not self.api_key:
            raise ValueError("ANTHROPIC_API_KEY required")

        self.model = model
        self.max_tokens = max_tokens

        # Initialize async client
        self.client = anthropic.AsyncAnthropic(api_key=self.api_key)

        logger.info(f"AnthropicDirectClient initialized: model={model}")

    def _build_tools(self, enabled_tools: List[str]) -> List[Dict[str, Any]]:
        """
        Build tool definitions for Claude API.

        Args:
            enabled_tools: List of tool names to enable

        Returns:
            List of tool definitions in Anthropic format
        """
        tool_definitions = {
            "emit_work_output": {
                "name": "emit_work_output",
                "description": """Emit a structured work output for user review.

Use this tool to record your findings, recommendations, insights, or draft content.
Each output you emit will be reviewed by the user before any action is taken.

IMPORTANT: You MUST use this tool for EVERY significant finding or output you generate.
Do not just describe your findings in text - emit them as structured outputs.

When to use:
- You discover a new fact or finding (output_type: "finding")
- You want to suggest an action (output_type: "recommendation")
- You identify a pattern or insight (output_type: "insight")
- You draft content for review (output_type: "draft_content")
- You analyze data (output_type: "data_analysis")
- You create a report section (output_type: "report_section")""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "output_type": {
                            "type": "string",
                            "description": "Type of output: finding, recommendation, insight, draft_content, data_analysis, report_section",
                            "enum": ["finding", "recommendation", "insight", "draft_content", "data_analysis", "report_section"]
                        },
                        "title": {
                            "type": "string",
                            "description": "Brief title summarizing the output"
                        },
                        "body": {
                            "type": "object",
                            "description": "Structured content of the output",
                            "properties": {
                                "summary": {"type": "string"},
                                "details": {"type": "string"},
                                "evidence": {"type": "array", "items": {"type": "string"}},
                                "implications": {"type": "array", "items": {"type": "string"}}
                            }
                        },
                        "confidence": {
                            "type": "number",
                            "description": "Confidence score from 0.0 to 1.0",
                            "minimum": 0.0,
                            "maximum": 1.0
                        },
                        "source_block_ids": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "IDs of substrate blocks used as sources (for provenance)"
                        }
                    },
                    "required": ["output_type", "title", "body", "confidence"]
                }
            },
            "web_search": {
                "name": "web_search",
                "description": """Search the web for current information.

Use this tool to find recent news, market data, competitor information, or any other
real-time information that may not be in the substrate context.

The search will return relevant results that you should analyze and synthesize.""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Search query"
                        },
                        "num_results": {
                            "type": "integer",
                            "description": "Number of results to return (default: 5)",
                            "default": 5
                        }
                    },
                    "required": ["query"]
                }
            },
            "emit_context_item": {
                "name": "emit_context_item",
                "description": """Emit a context item directly to the project's context store.

Use this tool for continuous research recipes (trend-digest, market-research, competitor-monitor)
where the output is a periodic digest that should be stored as context, not reviewed as work output.

Context items are immediately available to other agents and the user's context view.
Each context item is time-stamped and accumulates (non-singleton schemas).

When to use:
- Trend digests (schema_id: "trend_digest")
- Market intelligence (schema_id: "market_intel")
- Competitor snapshots (schema_id: "competitor_snapshot")

Do NOT use for findings that need user review - use emit_work_output instead.""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "schema_id": {
                            "type": "string",
                            "description": "Context schema type: trend_digest, market_intel, competitor_snapshot",
                            "enum": ["trend_digest", "market_intel", "competitor_snapshot"]
                        },
                        "title": {
                            "type": "string",
                            "description": "Title for the context item (e.g., 'Week of Dec 2-8, 2024')"
                        },
                        "content": {
                            "type": "object",
                            "description": "Structured content matching the schema",
                            "properties": {
                                "summary": {"type": "string"},
                                "sections": {"type": "array"},
                                "highlights": {"type": "array"},
                                "implications": {"type": "array"},
                                "period": {"type": "string"}
                            }
                        }
                    },
                    "required": ["schema_id", "title", "content"]
                }
            }
        }

        return [
            tool_definitions[name]
            for name in enabled_tools
            if name in tool_definitions
        ]

    async def _execute_tool(
        self,
        tool_name: str,
        tool_input: Dict[str, Any],
        tool_context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Execute a tool call and return result.

        Args:
            tool_name: Name of the tool to execute
            tool_input: Tool input parameters
            tool_context: Context for tool execution (basket_id, work_ticket_id, etc.)

        Returns:
            Tool execution result
        """
        if tool_name == "emit_work_output":
            return await self._emit_work_output(tool_input, tool_context)
        elif tool_name == "emit_context_item":
            return await self._emit_context_item(tool_input, tool_context)
        elif tool_name == "web_search":
            return await self._web_search(tool_input, tool_context)
        else:
            return {"error": f"Unknown tool: {tool_name}"}

    async def _emit_work_output(
        self,
        tool_input: Dict[str, Any],
        tool_context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Emit work output to substrate-API.

        Args:
            tool_input: Tool input with output_type, title, body, confidence
            tool_context: Context with basket_id, work_ticket_id, agent_type

        Returns:
            Result with work_output_id or error
        """
        basket_id = tool_context.get("basket_id")
        work_ticket_id = tool_context.get("work_ticket_id")
        agent_type = tool_context.get("agent_type", "research")
        user_jwt = tool_context.get("user_jwt")

        if not basket_id or not work_ticket_id:
            return {"error": "Missing basket_id or work_ticket_id in tool_context"}

        logger.info(
            f"emit_work_output: type={tool_input.get('output_type')}, "
            f"basket={basket_id}, ticket={work_ticket_id}"
        )

        try:
            url = f"{SUBSTRATE_API_URL}/api/baskets/{basket_id}/work-outputs"

            # Convert body dict to JSON string (work_outputs.body is TEXT column)
            body = tool_input.get("body", {})
            body_text = json.dumps(body) if isinstance(body, dict) else str(body)

            # Ensure source_block_ids is a list
            source_block_ids = tool_input.get("source_block_ids", [])
            if isinstance(source_block_ids, str):
                try:
                    source_block_ids = json.loads(source_block_ids)
                except Exception:
                    source_block_ids = []
            elif not isinstance(source_block_ids, list):
                source_block_ids = []

            payload = {
                "basket_id": basket_id,
                "work_ticket_id": work_ticket_id,
                "output_type": tool_input.get("output_type"),
                "agent_type": agent_type,
                "title": tool_input.get("title"),
                "body": body_text,
                "confidence": tool_input.get("confidence", 0.7),
                "source_context_ids": source_block_ids,
                "metadata": {}
            }

            headers = {
                "X-Service-Name": "work-platform-api",
                "X-Service-Secret": SUBSTRATE_SERVICE_SECRET,
                "Content-Type": "application/json",
            }
            if user_jwt:
                headers["Authorization"] = f"Bearer {user_jwt}"

            async with httpx.AsyncClient(timeout=30.0) as http_client:
                response = await http_client.post(url, json=payload, headers=headers)
                response.raise_for_status()
                work_output = response.json()

            logger.info(
                f"emit_work_output SUCCESS: id={work_output.get('id')}"
            )

            return {
                "status": "success",
                "work_output_id": work_output.get("id"),
                "output_type": tool_input.get("output_type"),
                "title": tool_input.get("title"),
                "message": f"Work output '{tool_input.get('title')}' created successfully"
            }

        except httpx.HTTPStatusError as e:
            logger.error(f"emit_work_output HTTP error: {e.response.status_code}")
            return {
                "status": "error",
                "error": f"HTTP {e.response.status_code}: {e.response.text}",
                "message": "Failed to create work output"
            }
        except Exception as e:
            logger.error(f"emit_work_output failed: {e}", exc_info=True)
            return {
                "status": "error",
                "error": str(e),
                "message": "Unexpected error creating work output"
            }

    async def _emit_context_item(
        self,
        tool_input: Dict[str, Any],
        tool_context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Emit context item directly to context_items table.

        Used by continuous research recipes (trend-digest, market-research, competitor-monitor)
        to store periodic digests as project context.

        Args:
            tool_input: Tool input with schema_id, title, content
            tool_context: Context with basket_id, work_ticket_id, agent_type

        Returns:
            Result with context_item_id or error
        """
        basket_id = tool_context.get("basket_id")
        work_ticket_id = tool_context.get("work_ticket_id")
        agent_type = tool_context.get("agent_type", "research")

        if not basket_id:
            return {"error": "Missing basket_id in tool_context"}

        schema_id = tool_input.get("schema_id")
        title = tool_input.get("title")
        content = tool_input.get("content", {})

        logger.info(
            f"emit_context_item: schema={schema_id}, title={title}, "
            f"basket={basket_id}"
        )

        try:
            # Insert directly into context_items table via Supabase
            from app.utils.supabase_client import supabase_admin_client as supabase

            # Ensure content is properly formatted
            if isinstance(content, str):
                try:
                    content = json.loads(content)
                except Exception:
                    content = {"raw": content}

            # Add metadata
            content["_generated_by"] = agent_type
            content["_work_ticket_id"] = work_ticket_id
            content["_generated_at"] = __import__("datetime").datetime.now(
                __import__("datetime").timezone.utc
            ).isoformat()

            # Map schema_id to item_type for database constraint
            # trend_digest, market_intel, competitor_snapshot all map to their schema_id as item_type
            item_type = schema_id  # Use schema_id as item_type (e.g., "trend_digest")

            insert_data = {
                "basket_id": basket_id,
                "tier": "working",  # Agent-generated insights are working tier
                "item_type": item_type,
                "schema_id": schema_id,
                "title": title,
                "content": content,
                "created_by": "agent",  # Mark as agent-generated
                "source_type": "agent",  # Track origin
                "source_ref": {"work_ticket_id": work_ticket_id, "agent_type": agent_type},
            }

            response = supabase.table("context_items").insert(insert_data).execute()

            if response.data and len(response.data) > 0:
                context_item_id = response.data[0].get("id")
                logger.info(f"emit_context_item SUCCESS: id={context_item_id}")

                return {
                    "status": "success",
                    "context_item_id": context_item_id,
                    "schema_id": schema_id,
                    "title": title,
                    "message": f"Context item '{title}' created successfully"
                }
            else:
                return {
                    "status": "error",
                    "error": "No data returned from insert",
                    "message": "Failed to create context item"
                }

        except Exception as e:
            logger.error(f"emit_context_item failed: {e}", exc_info=True)
            return {
                "status": "error",
                "error": str(e),
                "message": "Unexpected error creating context item"
            }

    async def _web_search(
        self,
        tool_input: Dict[str, Any],
        tool_context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Execute web search (placeholder - use Claude's built-in WebSearch).

        Note: Claude 3.5 Sonnet has built-in web search via server tools.
        This method is a fallback if using models without built-in search.

        Args:
            tool_input: Tool input with query
            tool_context: Context for search

        Returns:
            Search results or error
        """
        query = tool_input.get("query", "")
        logger.info(f"web_search: query={query}")

        # For now, return a placeholder indicating Claude should use built-in search
        # In production, you might integrate with Tavily, Brave Search API, etc.
        return {
            "status": "info",
            "message": "Web search executed. Please use Claude's built-in WebSearch tool for actual results.",
            "query": query,
            "note": "This is a placeholder. Configure external search API for production."
        }

    async def execute(
        self,
        system_prompt: str,
        user_message: str,
        tools: Optional[List[str]] = None,
        tool_context: Optional[Dict[str, Any]] = None,
        on_stream: Optional[Callable[[str, Any], None]] = None,
        max_tool_rounds: int = 10,
    ) -> ExecutionResult:
        """
        Execute an agent request with optional tool use.

        Args:
            system_prompt: System prompt for Claude
            user_message: User message (research task, etc.)
            tools: List of tool names to enable
            tool_context: Context for tool execution
            on_stream: Optional callback for streaming events
            max_tool_rounds: Maximum tool use rounds before stopping

        Returns:
            ExecutionResult with response, tool calls, and token usage
        """
        tools = tools or []
        tool_context = tool_context or {}

        # Build tool definitions
        tool_defs = self._build_tools(tools) if tools else []

        # Add Claude's built-in web search if requested
        enable_web_search = "web_search" in tools

        # Track execution
        all_tool_calls: List[ToolCall] = []
        work_outputs: List[Dict[str, Any]] = []
        total_input_tokens = 0
        total_output_tokens = 0
        total_cache_read = 0
        total_cache_creation = 0
        final_response = ""
        stop_reason = ""

        # Build messages
        messages = [{"role": "user", "content": user_message}]

        logger.info(
            f"[EXECUTE] Starting: model={self.model}, tools={len(tool_defs)}, "
            f"system_prompt={len(system_prompt)} chars"
        )

        # Execute with tool loop
        round_count = 0
        while round_count < max_tool_rounds:
            round_count += 1
            logger.debug(f"[EXECUTE] Round {round_count}")

            try:
                # Call Claude API
                # Use beta.prompt_caching for cache control
                response = await self.client.messages.create(
                    model=self.model,
                    max_tokens=self.max_tokens,
                    system=[{
                        "type": "text",
                        "text": system_prompt,
                        "cache_control": {"type": "ephemeral"}  # Enable caching
                    }],
                    messages=messages,
                    tools=tool_defs if tool_defs else anthropic.NOT_GIVEN,
                )

                # Track tokens
                usage = response.usage
                total_input_tokens += usage.input_tokens
                total_output_tokens += usage.output_tokens

                # Check for cache usage (if available)
                if hasattr(usage, 'cache_read_input_tokens'):
                    total_cache_read += usage.cache_read_input_tokens or 0
                if hasattr(usage, 'cache_creation_input_tokens'):
                    total_cache_creation += usage.cache_creation_input_tokens or 0

                logger.info(
                    f"[TOKEN] Round {round_count}: "
                    f"input={usage.input_tokens}, output={usage.output_tokens}, "
                    f"cache_read={getattr(usage, 'cache_read_input_tokens', 0)}"
                )

                stop_reason = response.stop_reason

                # Process response content
                tool_use_blocks = []
                text_blocks = []

                for block in response.content:
                    if block.type == "text":
                        text_blocks.append(block.text)
                        if on_stream:
                            on_stream("text", block.text)
                    elif block.type == "tool_use":
                        tool_use_blocks.append(block)
                        if on_stream:
                            on_stream("tool_use", {"name": block.name, "input": block.input})

                final_response = "\n".join(text_blocks)

                # If no tool use, we're done
                if stop_reason != "tool_use" or not tool_use_blocks:
                    logger.info(f"[EXECUTE] Complete: stop_reason={stop_reason}")
                    break

                # Execute tools and build tool results
                assistant_content = []
                tool_results = []

                for block in response.content:
                    if block.type == "text":
                        assistant_content.append({"type": "text", "text": block.text})
                    elif block.type == "tool_use":
                        assistant_content.append({
                            "type": "tool_use",
                            "id": block.id,
                            "name": block.name,
                            "input": block.input
                        })

                        # Execute tool
                        tool_result = await self._execute_tool(
                            block.name,
                            block.input,
                            tool_context
                        )

                        # Track tool call
                        tool_call = ToolCall(
                            id=block.id,
                            name=block.name,
                            input=block.input,
                            result=tool_result
                        )
                        all_tool_calls.append(tool_call)

                        # Track work outputs
                        if block.name == "emit_work_output" and tool_result.get("status") == "success":
                            work_outputs.append({
                                "id": tool_result.get("work_output_id"),
                                "output_type": block.input.get("output_type"),
                                "title": block.input.get("title"),
                                "confidence": block.input.get("confidence"),
                            })

                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": block.id,
                            "content": json.dumps(tool_result)
                        })

                # Add assistant response and tool results to messages
                messages.append({"role": "assistant", "content": assistant_content})
                messages.append({"role": "user", "content": tool_results})

            except anthropic.APIError as e:
                logger.error(f"[EXECUTE] API error: {e}")
                raise

        if round_count >= max_tool_rounds:
            logger.warning(f"[EXECUTE] Hit max tool rounds ({max_tool_rounds})")

        return ExecutionResult(
            response_text=final_response,
            tool_calls=all_tool_calls,
            work_outputs=work_outputs,
            input_tokens=total_input_tokens,
            output_tokens=total_output_tokens,
            cache_read_tokens=total_cache_read,
            cache_creation_tokens=total_cache_creation,
            stop_reason=stop_reason,
            model=self.model,
        )

    async def execute_streaming(
        self,
        system_prompt: str,
        user_message: str,
        tools: Optional[List[str]] = None,
        tool_context: Optional[Dict[str, Any]] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Execute with streaming response.

        Yields events as they occur:
        - {"type": "text_delta", "text": "..."}
        - {"type": "tool_use_start", "name": "...", "id": "..."}
        - {"type": "tool_result", "id": "...", "result": {...}}
        - {"type": "complete", "result": ExecutionResult}

        Args:
            system_prompt: System prompt for Claude
            user_message: User message
            tools: List of tool names to enable
            tool_context: Context for tool execution

        Yields:
            Streaming events
        """
        tools = tools or []
        tool_context = tool_context or {}

        tool_defs = self._build_tools(tools) if tools else []

        all_tool_calls: List[ToolCall] = []
        work_outputs: List[Dict[str, Any]] = []
        total_input_tokens = 0
        total_output_tokens = 0
        total_cache_read = 0
        final_response = ""
        stop_reason = ""

        messages = [{"role": "user", "content": user_message}]

        max_rounds = 10
        round_count = 0

        while round_count < max_rounds:
            round_count += 1

            current_text = ""
            current_tool_calls = []

            async with self.client.messages.stream(
                model=self.model,
                max_tokens=self.max_tokens,
                system=[{
                    "type": "text",
                    "text": system_prompt,
                    "cache_control": {"type": "ephemeral"}
                }],
                messages=messages,
                tools=tool_defs if tool_defs else anthropic.NOT_GIVEN,
            ) as stream:
                async for event in stream:
                    if event.type == "content_block_start":
                        if event.content_block.type == "tool_use":
                            yield {
                                "type": "tool_use_start",
                                "name": event.content_block.name,
                                "id": event.content_block.id
                            }

                    elif event.type == "content_block_delta":
                        if hasattr(event.delta, "text"):
                            current_text += event.delta.text
                            yield {"type": "text_delta", "text": event.delta.text}

                    elif event.type == "message_delta":
                        stop_reason = event.delta.stop_reason or ""
                        if hasattr(event, "usage"):
                            total_output_tokens += event.usage.output_tokens

                # Get final message
                final_message = await stream.get_final_message()
                usage = final_message.usage
                total_input_tokens += usage.input_tokens

                if hasattr(usage, 'cache_read_input_tokens'):
                    total_cache_read += usage.cache_read_input_tokens or 0

            final_response = current_text

            # Check for tool use
            tool_use_blocks = [
                b for b in final_message.content
                if b.type == "tool_use"
            ]

            if not tool_use_blocks or stop_reason != "tool_use":
                break

            # Execute tools
            assistant_content = []
            tool_results = []

            for block in final_message.content:
                if block.type == "text":
                    assistant_content.append({"type": "text", "text": block.text})
                elif block.type == "tool_use":
                    assistant_content.append({
                        "type": "tool_use",
                        "id": block.id,
                        "name": block.name,
                        "input": block.input
                    })

                    tool_result = await self._execute_tool(
                        block.name,
                        block.input,
                        tool_context
                    )

                    tool_call = ToolCall(
                        id=block.id,
                        name=block.name,
                        input=block.input,
                        result=tool_result
                    )
                    all_tool_calls.append(tool_call)

                    yield {
                        "type": "tool_result",
                        "id": block.id,
                        "name": block.name,
                        "result": tool_result
                    }

                    if block.name == "emit_work_output" and tool_result.get("status") == "success":
                        work_outputs.append({
                            "id": tool_result.get("work_output_id"),
                            "output_type": block.input.get("output_type"),
                            "title": block.input.get("title"),
                        })

                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(tool_result)
                    })

            messages.append({"role": "assistant", "content": assistant_content})
            messages.append({"role": "user", "content": tool_results})

        # Yield final result
        result = ExecutionResult(
            response_text=final_response,
            tool_calls=all_tool_calls,
            work_outputs=work_outputs,
            input_tokens=total_input_tokens,
            output_tokens=total_output_tokens,
            cache_read_tokens=total_cache_read,
            cache_creation_tokens=0,
            stop_reason=stop_reason,
            model=self.model,
        )

        yield {"type": "complete", "result": result}


# Convenience function
def get_anthropic_client(**kwargs) -> AnthropicDirectClient:
    """Get an AnthropicDirectClient instance."""
    return AnthropicDirectClient(**kwargs)
