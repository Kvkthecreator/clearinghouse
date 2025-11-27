"""
Test Workflows Endpoint - For E2E Testing Without JWT Complexity

Uses service-to-service authentication (X-Test-User-ID header) instead of JWT.
Bypasses Supabase JWT complexity for programmatic testing.

NOTE: Post-SDK removal, test workflows use the new ResearchExecutor.

Usage:
    curl -X POST http://localhost:10000/api/test/workflows/research \
      -H "X-Test-User-ID: uuid" \
      -H "Content-Type: application/json" \
      -d '{"basket_id": "uuid", "task_description": "test"}'
"""

import logging
import time
from typing import Optional
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel

from app.utils.supabase_client import supabase_admin_client as supabase

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/test/workflows", tags=["testing"])


class TestResearchRequest(BaseModel):
    """Test research workflow parameters."""
    basket_id: str
    task_description: str
    research_scope: Optional[str] = "general"
    depth: Optional[str] = "quick"


class TestResearchResponse(BaseModel):
    """Test research workflow response."""
    success: bool
    work_request_id: str
    work_ticket_id: str
    status: str
    outputs: list[dict]
    execution_time_ms: Optional[int]
    message: str
    test_mode: bool = True


@router.post("/research", response_model=TestResearchResponse)
async def test_research_workflow(
    request: TestResearchRequest,
    x_test_user_id: str = Header(..., description="Test user ID for auth bypass")
):
    """
    Test endpoint for research workflow (bypasses JWT auth).

    Uses X-Test-User-ID header for user identification instead of JWT.
    This allows E2E testing without Supabase authentication complexity.

    Post-SDK: Uses ResearchExecutor with direct Anthropic API.

    Args:
        request: Research workflow parameters
        x_test_user_id: User ID from X-Test-User-ID header

    Returns:
        Research workflow execution result

    Raises:
        400: Invalid request or basket not found
        500: Execution error
    """

    logger.info(
        f"[TEST RESEARCH WORKFLOW] Starting: user={x_test_user_id}, "
        f"basket={request.basket_id}"
    )

    try:
        # Step 1: Validate basket access and get workspace
        basket_response = supabase.table("baskets").select(
            "id, workspace_id, name"
        ).eq("id", request.basket_id).single().execute()

        if not basket_response.data:
            raise HTTPException(status_code=404, detail="Basket not found")

        basket = basket_response.data
        workspace_id = basket["workspace_id"]

        logger.info(f"[TEST] Basket found: {basket['name']} in workspace {workspace_id}")

        # Step 2: Create work_request
        work_request_data = {
            "workspace_id": workspace_id,
            "basket_id": request.basket_id,
            "requested_by_user_id": x_test_user_id,
            "request_type": "test_research_workflow",
            "task_intent": request.task_description,
            "parameters": {
                "research_scope": request.research_scope,
                "depth": request.depth,
                "test_mode": True,
            },
            "priority": "normal",
        }
        work_request_response = supabase.table("work_requests").insert(
            work_request_data
        ).execute()
        work_request_id = work_request_response.data[0]["id"]

        # Step 3: Create work_ticket
        work_ticket_data = {
            "work_request_id": work_request_id,
            "workspace_id": workspace_id,
            "basket_id": request.basket_id,
            "agent_type": "research",
            "status": "pending",
            "metadata": {
                "workflow": "test_research",
                "test_mode": True,
            },
        }
        work_ticket_response = supabase.table("work_tickets").insert(
            work_ticket_data
        ).execute()
        work_ticket_id = work_ticket_response.data[0]["id"]

        logger.info(
            f"[TEST] Created: work_request={work_request_id}, "
            f"work_ticket={work_ticket_id}"
        )

        # Step 4: Update work_ticket to running
        supabase.table("work_tickets").update({
            "status": "running",
        }).eq("id", work_ticket_id).execute()

        # Step 5: Execute ResearchExecutor (new pattern, no SDK)
        logger.info("[TEST] Executing ResearchExecutor (direct Anthropic API)...")

        from agents.research_executor import ResearchExecutor

        executor = ResearchExecutor(
            basket_id=request.basket_id,
            workspace_id=workspace_id,
            work_ticket_id=work_ticket_id,
            user_id=x_test_user_id,
        )

        start_time = time.time()

        result = await executor.execute(
            task=request.task_description,
            research_scope=request.research_scope,
            depth=request.depth,
        )

        execution_time_ms = int((time.time() - start_time) * 1000)

        # Step 6: Update work_ticket to completed
        supabase.table("work_tickets").update({
            "status": "completed",
            "metadata": {
                "execution_time_ms": execution_time_ms,
                "output_count": len(result.work_outputs),
                "test_mode": True,
            },
        }).eq("id", work_ticket_id).execute()

        logger.info(
            f"[TEST] Execution complete: {len(result.work_outputs)} outputs "
            f"in {execution_time_ms}ms"
        )

        return TestResearchResponse(
            success=True,
            work_request_id=work_request_id,
            work_ticket_id=work_ticket_id,
            status="completed",
            outputs=result.work_outputs,
            execution_time_ms=execution_time_ms,
            message=f"Test successful: {len(result.work_outputs)} outputs generated",
            test_mode=True,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"[TEST RESEARCH WORKFLOW] Failed: {e}")

        # Update work_ticket to failed if it exists
        if 'work_ticket_id' in locals():
            try:
                supabase.table("work_tickets").update({
                    "status": "failed",
                    "metadata": {
                        "error": str(e),
                        "error_type": type(e).__name__,
                        "test_mode": True,
                    },
                }).eq("id", work_ticket_id).execute()
            except Exception as update_error:
                logger.error(f"Failed to update work_ticket: {update_error}")

        raise HTTPException(
            status_code=500,
            detail=f"Test research workflow failed: {str(e)}"
        )


@router.get("/health")
async def test_health():
    """
    Health check for test endpoints.

    Returns endpoint status for availability testing.
    """
    return {
        "status": "ok",
        "message": "Test endpoints available",
        "sdk_status": "removed",
        "executor": "ResearchExecutor (direct Anthropic API)",
    }
