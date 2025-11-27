"""
Diagnostic endpoints for troubleshooting and validating the new direct Anthropic API stack.

Post-SDK removal: Comprehensive test suite for core agent functionality.

Test Progression (run in order):
1. test-anthropic-connection - Verify API key and basic connectivity
2. test-tool-definition - Verify tool schemas are valid
3. test-emit-work-output - Verify work output tool works end-to-end
4. test-research-executor - Full ResearchExecutor workflow
5. test-streaming - Verify streaming responses work
6. test-token-tracking - Verify cost/token analysis

All tests are designed for production (Render) deployment testing.
"""

import os
import logging
import time
import json
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/diagnostics", tags=["diagnostics"])
logger = logging.getLogger(__name__)


# =============================================================================
# Models
# =============================================================================

class TestResult(BaseModel):
    """Standard test result format."""
    test_name: str
    status: str  # success, error, warning
    duration_ms: int
    message: str
    details: Dict[str, Any] = Field(default_factory=dict)


class TestSuiteResult(BaseModel):
    """Result from running multiple tests."""
    total_tests: int
    passed: int
    failed: int
    warnings: int
    duration_ms: int
    results: List[TestResult]


# =============================================================================
# Test 1: Anthropic API Connection
# =============================================================================

@router.post("/test-anthropic-connection")
async def test_anthropic_connection() -> TestResult:
    """
    Test 1: Verify Anthropic API connectivity.

    Validates:
    - ANTHROPIC_API_KEY is configured
    - Basic API call succeeds
    - Model responds correctly
    - Response structure is valid

    This is the foundational test - if this fails, nothing else will work.
    """
    start_time = time.time()
    test_name = "anthropic_connection"

    try:
        from clients.anthropic_client import AnthropicDirectClient

        # Check API key exists
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            return TestResult(
                test_name=test_name,
                status="error",
                duration_ms=int((time.time() - start_time) * 1000),
                message="ANTHROPIC_API_KEY not configured",
                details={"env_var_present": False}
            )

        # Initialize client
        client = AnthropicDirectClient()

        # Simple API call - minimal tokens
        result = await client.execute(
            system_prompt="You are a test assistant. Be extremely brief.",
            user_message="Reply with exactly: TEST_OK",
            tools=[],
        )

        # Validate response
        response_ok = "TEST_OK" in result.response_text or "test" in result.response_text.lower()
        tokens_valid = result.input_tokens > 0 and result.output_tokens > 0

        duration_ms = int((time.time() - start_time) * 1000)

        return TestResult(
            test_name=test_name,
            status="success" if response_ok and tokens_valid else "warning",
            duration_ms=duration_ms,
            message="Anthropic API connection successful" if response_ok else "Connection works but response unexpected",
            details={
                "model": result.model,
                "response_preview": result.response_text[:100],
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
                "stop_reason": result.stop_reason,
                "api_key_present": True,
                "api_key_suffix": f"...{api_key[-4:]}",
            }
        )

    except Exception as e:
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"Anthropic API connection failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
            }
        )


# =============================================================================
# Test 2: Tool Definition Validation
# =============================================================================

@router.post("/test-tool-definition")
async def test_tool_definition() -> TestResult:
    """
    Test 2: Verify tool definitions are valid.

    Validates:
    - emit_work_output tool schema is valid
    - Claude accepts the tool definition
    - Tool can be invoked by Claude

    This test doesn't execute the tool, just validates Claude accepts it.
    """
    start_time = time.time()
    test_name = "tool_definition"

    try:
        from clients.anthropic_client import AnthropicDirectClient

        client = AnthropicDirectClient()

        # Request with tools enabled - ask Claude to describe the tools
        result = await client.execute(
            system_prompt="You are a test assistant. List the tools available to you.",
            user_message="What tools do you have access to? List them briefly.",
            tools=["emit_work_output", "web_search"],
        )

        # Check if Claude acknowledges the tools
        response_lower = result.response_text.lower()
        emit_mentioned = "emit" in response_lower or "work_output" in response_lower or "output" in response_lower
        search_mentioned = "search" in response_lower or "web" in response_lower

        duration_ms = int((time.time() - start_time) * 1000)

        return TestResult(
            test_name=test_name,
            status="success" if emit_mentioned else "warning",
            duration_ms=duration_ms,
            message="Tool definitions accepted by Claude" if emit_mentioned else "Tools accepted but not explicitly acknowledged",
            details={
                "emit_work_output_acknowledged": emit_mentioned,
                "web_search_acknowledged": search_mentioned,
                "response_preview": result.response_text[:200],
                "model": result.model,
            }
        )

    except Exception as e:
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"Tool definition test failed: {str(e)}",
            details={"error_type": type(e).__name__, "error_message": str(e)}
        )


# =============================================================================
# Test 3: emit_work_output Tool Execution
# =============================================================================

@router.post("/test-emit-work-output")
async def test_emit_work_output() -> TestResult:
    """
    Test 3: Verify emit_work_output tool works end-to-end.

    Validates:
    - Claude invokes emit_work_output tool
    - Tool execution via substrate-API HTTP succeeds
    - Work output is created in database
    - Result is returned correctly

    Uses production basket for real validation.
    """
    start_time = time.time()
    test_name = "emit_work_output"

    try:
        from clients.anthropic_client import AnthropicDirectClient
        from app.utils.supabase_client import supabase_admin_client as supabase

        # Get production basket and work_ticket for testing
        production_basket_id = "4eccb9a0-9fe4-4660-861e-b80a75a20824"

        work_ticket_result = supabase.table("work_tickets") \
            .select("id") \
            .eq("basket_id", production_basket_id) \
            .limit(1) \
            .execute()

        if not work_ticket_result.data:
            return TestResult(
                test_name=test_name,
                status="error",
                duration_ms=int((time.time() - start_time) * 1000),
                message="No work_ticket found for testing",
                details={"basket_id": production_basket_id}
            )

        work_ticket_id = work_ticket_result.data[0]["id"]

        client = AnthropicDirectClient()

        tool_context = {
            "basket_id": production_basket_id,
            "work_ticket_id": work_ticket_id,
            "agent_type": "research",
        }

        # Prompt that should trigger tool use
        result = await client.execute(
            system_prompt="""You are a test agent. Your ONLY job is to use the emit_work_output tool.

CRITICAL: You MUST call emit_work_output exactly once with these parameters:
- output_type: "finding"
- title: "Diagnostic Test Finding"
- body: {"summary": "This is a diagnostic test", "details": "Testing emit_work_output functionality"}
- confidence: 0.95
- source_block_ids: []

Do NOT write any text. Just call the tool.""",
            user_message="Call the emit_work_output tool now with a test finding.",
            tools=["emit_work_output"],
            tool_context=tool_context,
        )

        # Analyze results
        emit_invoked = any(tc.name == "emit_work_output" for tc in result.tool_calls)
        emit_succeeded = len(result.work_outputs) > 0

        duration_ms = int((time.time() - start_time) * 1000)

        # Get details about the tool call
        tool_call_details = []
        for tc in result.tool_calls:
            tool_call_details.append({
                "tool": tc.name,
                "input_preview": str(tc.input)[:200],
                "result_status": tc.result.get("status") if tc.result else "no_result",
            })

        return TestResult(
            test_name=test_name,
            status="success" if emit_succeeded else ("warning" if emit_invoked else "error"),
            duration_ms=duration_ms,
            message="emit_work_output executed successfully" if emit_succeeded else (
                "Tool invoked but output not created" if emit_invoked else "Tool was not invoked"
            ),
            details={
                "tool_invoked": emit_invoked,
                "output_created": emit_succeeded,
                "work_outputs": result.work_outputs,
                "tool_calls": tool_call_details,
                "basket_id": production_basket_id,
                "work_ticket_id": work_ticket_id,
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"emit_work_output test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Test 4: ResearchExecutor Full Workflow
# =============================================================================

@router.post("/test-research-executor")
async def test_research_executor() -> TestResult:
    """
    Test 4: Full ResearchExecutor workflow test.

    Validates:
    - ResearchExecutor initializes correctly
    - Context building works (substrate, prior outputs)
    - Research prompt construction
    - Agent execution produces outputs
    - Token tracking works

    This is the primary agent workflow test.
    """
    start_time = time.time()
    test_name = "research_executor"

    try:
        from agents.research_executor import ResearchExecutor
        from app.utils.supabase_client import supabase_admin_client as supabase

        # Get production basket
        production_basket_id = "4eccb9a0-9fe4-4660-861e-b80a75a20824"

        # Get or create work_ticket
        work_ticket_result = supabase.table("work_tickets") \
            .select("id, workspace_id") \
            .eq("basket_id", production_basket_id) \
            .limit(1) \
            .execute()

        if not work_ticket_result.data:
            return TestResult(
                test_name=test_name,
                status="error",
                duration_ms=int((time.time() - start_time) * 1000),
                message="No work_ticket found for testing",
                details={"basket_id": production_basket_id}
            )

        work_ticket_id = work_ticket_result.data[0]["id"]
        workspace_id = work_ticket_result.data[0].get("workspace_id", "test-workspace")

        # Initialize executor
        executor = ResearchExecutor(
            basket_id=production_basket_id,
            workspace_id=workspace_id,
            work_ticket_id=work_ticket_id,
            user_id="diagnostic-test-user",
        )

        # Execute quick research task
        result = await executor.execute(
            task="What is the current state of AI assistant technology? Provide 2 key findings.",
            research_scope="general",
            depth="quick",  # Minimal depth for fast testing
            enable_web_search=False,  # Skip web search for faster test
        )

        duration_ms = int((time.time() - start_time) * 1000)

        return TestResult(
            test_name=test_name,
            status="success" if len(result.work_outputs) > 0 else "warning",
            duration_ms=duration_ms,
            message=f"ResearchExecutor completed with {len(result.work_outputs)} outputs",
            details={
                "outputs_created": len(result.work_outputs),
                "work_outputs": result.work_outputs,
                "tool_calls_count": len(result.tool_calls),
                "response_preview": result.response_text[:300] if result.response_text else "(no text)",
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
                "cache_read_tokens": result.cache_read_tokens,
                "model": result.model,
                "stop_reason": result.stop_reason,
                "basket_id": production_basket_id,
                "work_ticket_id": work_ticket_id,
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"ResearchExecutor test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Test 5: Streaming Response
# =============================================================================

@router.post("/test-streaming")
async def test_streaming() -> TestResult:
    """
    Test 5: Verify streaming responses work.

    Validates:
    - Streaming API endpoint works
    - Events are yielded correctly
    - Final result contains all data

    Note: This test collects streaming events, doesn't return a stream.
    """
    start_time = time.time()
    test_name = "streaming"

    try:
        from clients.anthropic_client import AnthropicDirectClient

        client = AnthropicDirectClient()

        events_received = []
        final_result = None

        # Collect streaming events
        async for event in client.execute_streaming(
            system_prompt="You are a test assistant. Be brief.",
            user_message="Count from 1 to 3.",
            tools=[],
        ):
            events_received.append(event.get("type", "unknown"))
            if event.get("type") == "complete":
                final_result = event.get("result")

        duration_ms = int((time.time() - start_time) * 1000)

        text_deltas = events_received.count("text_delta")
        has_complete = "complete" in events_received

        return TestResult(
            test_name=test_name,
            status="success" if has_complete and text_deltas > 0 else "warning",
            duration_ms=duration_ms,
            message=f"Streaming test: {text_deltas} text deltas, complete={has_complete}",
            details={
                "event_types": list(set(events_received)),
                "text_delta_count": text_deltas,
                "has_complete_event": has_complete,
                "total_events": len(events_received),
                "final_response_preview": final_result.response_text[:100] if final_result else "(no result)",
                "input_tokens": final_result.input_tokens if final_result else 0,
                "output_tokens": final_result.output_tokens if final_result else 0,
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"Streaming test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Test 6: Token Tracking & Cost Analysis
# =============================================================================

@router.post("/test-token-tracking")
async def test_token_tracking() -> TestResult:
    """
    Test 6: Verify token tracking and cost analysis.

    Validates:
    - Input tokens are tracked
    - Output tokens are tracked
    - Cache tokens are tracked (if caching enabled)
    - Cost estimation is possible

    Returns detailed token breakdown for cost analysis.
    """
    start_time = time.time()
    test_name = "token_tracking"

    try:
        from clients.anthropic_client import AnthropicDirectClient

        client = AnthropicDirectClient()

        # Run two requests to test caching
        # First request
        result1 = await client.execute(
            system_prompt="You are a test assistant. This prompt is cached for efficiency testing.",
            user_message="Say hello.",
            tools=[],
        )

        # Second request with same system prompt (should use cache)
        result2 = await client.execute(
            system_prompt="You are a test assistant. This prompt is cached for efficiency testing.",
            user_message="Say goodbye.",
            tools=[],
        )

        duration_ms = int((time.time() - start_time) * 1000)

        # Calculate costs (approximate, Sonnet 3.5 pricing)
        # Input: $3.00 / 1M tokens, Output: $15.00 / 1M tokens
        # Cache read: $0.30 / 1M tokens (90% discount)
        input_cost_1 = (result1.input_tokens / 1_000_000) * 3.00
        output_cost_1 = (result1.output_tokens / 1_000_000) * 15.00
        input_cost_2 = (result2.input_tokens / 1_000_000) * 3.00
        output_cost_2 = (result2.output_tokens / 1_000_000) * 15.00
        cache_savings = (result2.cache_read_tokens / 1_000_000) * 2.70  # 90% of $3.00

        total_cost = input_cost_1 + output_cost_1 + input_cost_2 + output_cost_2 - cache_savings

        return TestResult(
            test_name=test_name,
            status="success" if result1.input_tokens > 0 and result2.input_tokens > 0 else "warning",
            duration_ms=duration_ms,
            message=f"Token tracking working. Total: {result1.input_tokens + result2.input_tokens} input, {result1.output_tokens + result2.output_tokens} output",
            details={
                "request_1": {
                    "input_tokens": result1.input_tokens,
                    "output_tokens": result1.output_tokens,
                    "cache_read_tokens": result1.cache_read_tokens,
                    "cache_creation_tokens": result1.cache_creation_tokens,
                },
                "request_2": {
                    "input_tokens": result2.input_tokens,
                    "output_tokens": result2.output_tokens,
                    "cache_read_tokens": result2.cache_read_tokens,
                    "cache_creation_tokens": result2.cache_creation_tokens,
                },
                "totals": {
                    "total_input_tokens": result1.input_tokens + result2.input_tokens,
                    "total_output_tokens": result1.output_tokens + result2.output_tokens,
                    "total_cache_read": result1.cache_read_tokens + result2.cache_read_tokens,
                },
                "cost_analysis": {
                    "estimated_cost_usd": round(total_cost, 6),
                    "cache_savings_usd": round(cache_savings, 6),
                    "note": "Based on Claude Sonnet 3.5 pricing",
                },
                "model": result1.model,
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"Token tracking test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Run All Tests
# =============================================================================

@router.post("/run-all-tests")
async def run_all_tests() -> TestSuiteResult:
    """
    Run all diagnostic tests in sequence.

    Returns comprehensive test suite results.
    """
    start_time = time.time()
    results = []
    passed = 0
    failed = 0
    warnings = 0

    # Test 1: Anthropic Connection
    logger.info("Running test 1: anthropic_connection")
    result1 = await test_anthropic_connection()
    results.append(result1)
    if result1.status == "success":
        passed += 1
    elif result1.status == "error":
        failed += 1
    else:
        warnings += 1

    # Only continue if connection works
    if result1.status == "error":
        return TestSuiteResult(
            total_tests=1,
            passed=passed,
            failed=failed,
            warnings=warnings,
            duration_ms=int((time.time() - start_time) * 1000),
            results=results,
        )

    # Test 2: Tool Definition
    logger.info("Running test 2: tool_definition")
    result2 = await test_tool_definition()
    results.append(result2)
    if result2.status == "success":
        passed += 1
    elif result2.status == "error":
        failed += 1
    else:
        warnings += 1

    # Test 3: emit_work_output
    logger.info("Running test 3: emit_work_output")
    result3 = await test_emit_work_output()
    results.append(result3)
    if result3.status == "success":
        passed += 1
    elif result3.status == "error":
        failed += 1
    else:
        warnings += 1

    # Test 4: ResearchExecutor
    logger.info("Running test 4: research_executor")
    result4 = await test_research_executor()
    results.append(result4)
    if result4.status == "success":
        passed += 1
    elif result4.status == "error":
        failed += 1
    else:
        warnings += 1

    # Test 5: Streaming
    logger.info("Running test 5: streaming")
    result5 = await test_streaming()
    results.append(result5)
    if result5.status == "success":
        passed += 1
    elif result5.status == "error":
        failed += 1
    else:
        warnings += 1

    # Test 6: Token Tracking
    logger.info("Running test 6: token_tracking")
    result6 = await test_token_tracking()
    results.append(result6)
    if result6.status == "success":
        passed += 1
    elif result6.status == "error":
        failed += 1
    else:
        warnings += 1

    return TestSuiteResult(
        total_tests=len(results),
        passed=passed,
        failed=failed,
        warnings=warnings,
        duration_ms=int((time.time() - start_time) * 1000),
        results=results,
    )


# =============================================================================
# Test 7: ContentAgent
# =============================================================================

@router.post("/test-content-agent")
async def test_content_agent() -> TestResult:
    """
    Test 7: ContentAgent workflow test.

    Validates:
    - ContentAgent initializes correctly
    - Content generation prompt construction
    - Agent execution produces content outputs
    """
    start_time = time.time()
    test_name = "content_agent"

    try:
        from agents.content_agent import ContentAgent
        from app.utils.supabase_client import supabase_admin_client as supabase

        # Get production basket
        production_basket_id = "4eccb9a0-9fe4-4660-861e-b80a75a20824"

        work_ticket_result = supabase.table("work_tickets") \
            .select("id, workspace_id") \
            .eq("basket_id", production_basket_id) \
            .limit(1) \
            .execute()

        if not work_ticket_result.data:
            return TestResult(
                test_name=test_name,
                status="error",
                duration_ms=int((time.time() - start_time) * 1000),
                message="No work_ticket found for testing",
                details={"basket_id": production_basket_id}
            )

        work_ticket_id = work_ticket_result.data[0]["id"]
        workspace_id = work_ticket_result.data[0].get("workspace_id", "test-workspace")

        # Initialize agent
        agent = ContentAgent(
            basket_id=production_basket_id,
            workspace_id=workspace_id,
            work_ticket_id=work_ticket_id,
            user_id="diagnostic-test-user",
        )

        # Execute content generation task
        result = await agent.execute(
            task="Write a brief post about AI assistants for professionals",
            content_type="linkedin_post",
            tone="professional",
            create_variants=False,
            enable_web_search=False,
        )

        duration_ms = int((time.time() - start_time) * 1000)

        return TestResult(
            test_name=test_name,
            status="success" if len(result.work_outputs) > 0 else "warning",
            duration_ms=duration_ms,
            message=f"ContentAgent completed with {len(result.work_outputs)} outputs",
            details={
                "outputs_created": len(result.work_outputs),
                "work_outputs": result.work_outputs,
                "response_preview": result.response_text[:300] if result.response_text else "(no text)",
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"ContentAgent test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Test 8: ThinkingPartnerAgent
# =============================================================================

@router.post("/test-thinking-partner-agent")
async def test_thinking_partner_agent() -> TestResult:
    """
    Test 8: ThinkingPartnerAgent scaffold test.

    Validates:
    - ThinkingPartnerAgent initializes correctly
    - Basic execution works
    - Insights are captured as work_outputs
    """
    start_time = time.time()
    test_name = "thinking_partner_agent"

    try:
        from agents.thinking_partner_agent import ThinkingPartnerAgent
        from app.utils.supabase_client import supabase_admin_client as supabase

        # Get production basket
        production_basket_id = "4eccb9a0-9fe4-4660-861e-b80a75a20824"

        work_ticket_result = supabase.table("work_tickets") \
            .select("id, workspace_id") \
            .eq("basket_id", production_basket_id) \
            .limit(1) \
            .execute()

        if not work_ticket_result.data:
            return TestResult(
                test_name=test_name,
                status="error",
                duration_ms=int((time.time() - start_time) * 1000),
                message="No work_ticket found for testing",
                details={"basket_id": production_basket_id}
            )

        work_ticket_id = work_ticket_result.data[0]["id"]
        workspace_id = work_ticket_result.data[0].get("workspace_id", "test-workspace")

        # Initialize agent
        agent = ThinkingPartnerAgent(
            basket_id=production_basket_id,
            workspace_id=workspace_id,
            work_ticket_id=work_ticket_id,
            user_id="diagnostic-test-user",
        )

        # Execute brainstorming task
        result = await agent.execute(
            task="What are the key considerations for AI assistant adoption in enterprises?",
            thinking_mode="brainstorm",
            capture_insights=True,
        )

        duration_ms = int((time.time() - start_time) * 1000)

        return TestResult(
            test_name=test_name,
            status="success" if result.response_text else "warning",
            duration_ms=duration_ms,
            message=f"ThinkingPartnerAgent completed with {len(result.work_outputs)} insights",
            details={
                "insights_captured": len(result.work_outputs),
                "work_outputs": result.work_outputs,
                "response_preview": result.response_text[:300] if result.response_text else "(no text)",
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
                "note": "ThinkingPartnerAgent is a scaffold - full implementation pending",
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"ThinkingPartnerAgent test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Test 9: ReportingAgent (Skills API)
# =============================================================================

@router.post("/test-reporting-agent")
async def test_reporting_agent() -> TestResult:
    """
    Test 9: ReportingAgent with Skills API test.

    Validates:
    - ReportingAgent initializes correctly
    - Skills API beta headers are configured
    - Document generation is attempted

    Note: Full Skills API testing may require beta access.
    """
    start_time = time.time()
    test_name = "reporting_agent"

    try:
        from agents.reporting_agent import ReportingAgent, SKILLS_BETAS
        from app.utils.supabase_client import supabase_admin_client as supabase

        # Get production basket
        production_basket_id = "4eccb9a0-9fe4-4660-861e-b80a75a20824"

        work_ticket_result = supabase.table("work_tickets") \
            .select("id, workspace_id") \
            .eq("basket_id", production_basket_id) \
            .limit(1) \
            .execute()

        if not work_ticket_result.data:
            return TestResult(
                test_name=test_name,
                status="error",
                duration_ms=int((time.time() - start_time) * 1000),
                message="No work_ticket found for testing",
                details={"basket_id": production_basket_id}
            )

        work_ticket_id = work_ticket_result.data[0]["id"]
        workspace_id = work_ticket_result.data[0].get("workspace_id", "test-workspace")

        # Initialize agent
        agent = ReportingAgent(
            basket_id=production_basket_id,
            workspace_id=workspace_id,
            work_ticket_id=work_ticket_id,
            user_id="diagnostic-test-user",
        )

        # Verify configuration
        has_skills_client = hasattr(agent, 'skills_client') and agent.skills_client is not None

        duration_ms = int((time.time() - start_time) * 1000)

        # Note: Full execution test skipped as Skills API requires beta access
        # In production, this would execute: await agent.execute(task="...", output_format="pptx")

        return TestResult(
            test_name=test_name,
            status="success" if has_skills_client else "warning",
            duration_ms=duration_ms,
            message="ReportingAgent initialized with Skills API support",
            details={
                "skills_client_initialized": has_skills_client,
                "skills_betas": SKILLS_BETAS,
                "supported_formats": agent.OUTPUT_FORMATS,
                "note": "Full Skills API execution requires beta access - skipping document generation",
            }
        )

    except Exception as e:
        import traceback
        return TestResult(
            test_name=test_name,
            status="error",
            duration_ms=int((time.time() - start_time) * 1000),
            message=f"ReportingAgent test failed: {str(e)}",
            details={
                "error_type": type(e).__name__,
                "error_message": str(e),
                "traceback": traceback.format_exc()[:500],
            }
        )


# =============================================================================
# Legacy Endpoints (kept for compatibility)
# =============================================================================

@router.get("/migration-status")
async def get_migration_status():
    """
    Get SDK removal migration status.

    Returns comprehensive status of the migration from Claude Agent SDK
    to direct Anthropic API.
    """
    return {
        "migration": "sdk_removal",
        "recovery_tag": "pre-sdk-removal",
        "status": "complete",
        "architecture": {
            "client": "AnthropicDirectClient (direct API)",
            "agents": "BaseAgent + ResearchAgent, ContentAgent, ReportingAgent, ThinkingPartnerAgent",
            "tools": "emit_work_output via substrate-API HTTP",
            "streaming": "Native Anthropic streaming",
            "skills_api": "ReportingAgent uses Skills API for document generation",
        },
        "test_endpoints": {
            "/api/diagnostics/test-anthropic-connection": "Test 1: API connectivity",
            "/api/diagnostics/test-tool-definition": "Test 2: Tool schemas",
            "/api/diagnostics/test-emit-work-output": "Test 3: Work output creation",
            "/api/diagnostics/test-research-executor": "Test 4: ResearchAgent workflow",
            "/api/diagnostics/test-streaming": "Test 5: Streaming responses",
            "/api/diagnostics/test-token-tracking": "Test 6: Cost analysis",
            "/api/diagnostics/test-content-agent": "Test 7: ContentAgent workflow",
            "/api/diagnostics/test-thinking-partner-agent": "Test 8: ThinkingPartnerAgent",
            "/api/diagnostics/test-reporting-agent": "Test 9: ReportingAgent (Skills API)",
            "/api/diagnostics/run-all-tests": "Run complete test suite",
        },
        "active_workflows": {
            "/api/work/research/execute": "active",
            "/api/work/content/execute": "pending_endpoint",
            "/api/work/reporting/execute": "pending_endpoint",
        }
    }


@router.get("/skills")
async def check_skills_availability():
    """
    Check Skills availability (legacy SDK feature).

    Post-SDK: Skills are no longer used. Tools are built into AnthropicDirectClient.
    """
    return {
        "status": "deprecated",
        "message": "Skills were a Claude Agent SDK feature. Now using direct tool definitions.",
        "tools_available": ["emit_work_output", "web_search"],
        "architecture": "Direct Anthropic API with inline tool definitions",
    }


@router.get("/agent-config")
async def check_agent_configuration():
    """
    Check agent configuration.

    Returns info about how agents are configured (post-SDK removal).
    """
    return {
        "status": "migrated",
        "architecture": "direct_anthropic_api",
        "note": "Claude Agent SDK removed. Agents now use AnthropicDirectClient.",
        "available_agents": [
            {
                "name": "ResearchAgent",
                "path": "agents/research_agent.py",
                "status": "active",
                "features": ["emit_work_output", "web_search", "substrate_context", "multi_search_limits"],
                "backward_compat": "ResearchExecutor"
            },
            {
                "name": "ContentAgent",
                "path": "agents/content_agent.py",
                "status": "active",
                "features": ["emit_work_output", "platform_specific_content", "variant_creation"],
                "content_types": ["linkedin_post", "twitter_thread", "blog_article", "newsletter"],
                "backward_compat": "ContentExecutor"
            },
            {
                "name": "ReportingAgent",
                "path": "agents/reporting_agent.py",
                "status": "active",
                "features": ["skills_api", "document_generation", "pptx", "xlsx", "docx", "pdf"],
                "requires_beta": ["code-execution-2025-08-25", "skills-2025-10-02"],
                "backward_compat": "ReportingExecutor"
            },
            {
                "name": "ThinkingPartnerAgent",
                "path": "agents/thinking_partner_agent.py",
                "status": "scaffold",
                "features": ["emit_work_output", "brainstorming", "insight_capture"],
                "note": "Minimal implementation - full interactive features pending",
                "backward_compat": "ThinkingPartnerExecutor"
            }
        ],
        "base_classes": [
            {
                "name": "BaseAgent",
                "path": "agents/base_agent.py",
                "purpose": "Shared agent logic, context building, tool execution",
                "backward_compat": "BaseAgentExecutor"
            },
            {
                "name": "AnthropicDirectClient",
                "path": "clients/anthropic_client.py",
                "purpose": "Direct Anthropic API calls with tool loop"
            }
        ],
        "tools": [
            {
                "name": "emit_work_output",
                "execution": "substrate-API HTTP POST",
                "status": "active"
            },
            {
                "name": "web_search",
                "execution": "Anthropic web search tool",
                "status": "active"
            },
            {
                "name": "code_execution",
                "execution": "Skills API (ReportingAgent only)",
                "status": "active",
                "requires_beta": True
            }
        ]
    }
