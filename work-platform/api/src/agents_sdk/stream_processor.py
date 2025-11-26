"""
SDK Stream Processor - Shared utility for processing Claude Agent SDK message streams.

Handles extraction of:
- TodoWrite tool calls (progress tracking) → streams to frontend
- emit_work_output tool calls (structured outputs) → captures for return
- Text responses → captures for logging

This is the single canonical approach for processing SDK responses across all agents.
Replaces inline processing in individual agent files.

Architecture (2025-11):
- All agents use this shared processor
- TodoWrite events are streamed in real-time to frontend via task_streaming
- Work outputs are captured and returned to caller
"""

import json
import logging
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class StreamProcessorResult:
    """Result from processing an SDK message stream."""
    work_outputs: List[Dict[str, Any]] = field(default_factory=list)
    response_text: str = ""
    tool_calls: List[Dict[str, Any]] = field(default_factory=list)
    todo_updates: List[Dict[str, Any]] = field(default_factory=list)
    final_todos: List[Dict[str, Any]] = field(default_factory=list)
    message_count: int = 0


def process_tool_block(
    block: Any,
    work_ticket_id: Optional[str] = None,
    agent_type: str = "unknown"
) -> Tuple[Optional[Dict], Optional[List[Dict]], str]:
    """
    Process a single tool use block from SDK stream.

    Args:
        block: Tool use block from SDK message
        work_ticket_id: Work ticket ID for streaming TodoWrite updates
        agent_type: Agent type for logging context

    Returns:
        Tuple of (work_output, todos, tool_name)
    """
    tool_name = getattr(block, 'name', None)
    if not tool_name:
        return None, None, ""

    tool_input = getattr(block, 'input', {})
    work_output = None
    todos = None

    # Handle emit_work_output
    if tool_name == 'mcp__shared_tools__emit_work_output':
        try:
            # Tool input is already the structured output
            if isinstance(tool_input, dict):
                work_output = tool_input
                logger.info(f"[{agent_type}] Captured work output: {tool_input.get('title', 'untitled')}")
        except Exception as e:
            logger.error(f"[{agent_type}] Failed to parse work output: {e}")

    # Handle TodoWrite - stream to frontend
    elif tool_name == 'TodoWrite':
        try:
            todos_data = tool_input.get('todos', []) if isinstance(tool_input, dict) else []

            if todos_data and work_ticket_id:
                # Stream to frontend via task_streaming
                from app.work.task_streaming import emit_task_update
                emit_task_update(work_ticket_id, {
                    "type": "todo_update",
                    "todos": todos_data,
                    "source": agent_type
                })
                logger.info(f"[{agent_type}] TodoWrite streamed: {len(todos_data)} items")

            todos = todos_data
        except Exception as e:
            logger.error(f"[{agent_type}] Failed to process TodoWrite: {e}")

    return work_output, todos, tool_name


async def process_sdk_stream(
    client: Any,
    work_ticket_id: Optional[str] = None,
    agent_type: str = "unknown"
) -> StreamProcessorResult:
    """
    Process SDK message stream and extract all relevant data.

    This is the canonical method for processing Claude Agent SDK responses.
    All agents should use this instead of inline processing.

    Args:
        client: ClaudeSDKClient instance (connected and query sent)
        work_ticket_id: Work ticket ID for streaming TodoWrite updates
        agent_type: Agent type for logging context

    Returns:
        StreamProcessorResult with work_outputs, response_text, tool_calls, etc.

    Usage:
        async with ClaudeSDKClient(options=self._options) as client:
            await client.connect()
            await client.query(prompt)
            result = await process_sdk_stream(client, work_ticket_id, "research")
    """
    result = StreamProcessorResult()

    async for message in client.receive_response():
        result.message_count += 1

        if not hasattr(message, 'content') or not isinstance(message.content, list):
            continue

        for block in message.content:
            # Extract text responses
            if hasattr(block, 'text'):
                result.response_text += block.text

            # Process tool use blocks
            if hasattr(block, 'name'):
                work_output, todos, tool_name = process_tool_block(
                    block, work_ticket_id, agent_type
                )

                # Track tool call
                tool_input = getattr(block, 'input', {})
                result.tool_calls.append({
                    "tool": tool_name,
                    "input": str(tool_input)[:300]  # Truncate for logging
                })

                # Capture work output
                if work_output:
                    result.work_outputs.append(work_output)

                # Track todo updates
                if todos:
                    result.todo_updates.append({"todos": todos})
                    result.final_todos = todos  # Keep latest

    logger.info(
        f"[{agent_type}] Stream processed: {result.message_count} messages, "
        f"{len(result.work_outputs)} outputs, {len(result.tool_calls)} tool calls, "
        f"{len(result.final_todos)} final todos"
    )

    return result


def emit_completion_status(work_ticket_id: str, status: str = "completed"):
    """
    Emit completion status to frontend stream.

    Args:
        work_ticket_id: Work ticket ID
        status: "completed" or "failed"
    """
    try:
        from app.work.task_streaming import emit_task_update
        emit_task_update(work_ticket_id, {
            "type": "completed",
            "status": status
        })
        logger.info(f"Emitted completion status: {status} for ticket {work_ticket_id}")
    except Exception as e:
        logger.error(f"Failed to emit completion status: {e}")
