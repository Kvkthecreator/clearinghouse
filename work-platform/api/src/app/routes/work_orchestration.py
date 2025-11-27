"""
Work Orchestration API - Phase 4 + Phase 5

Core work execution infrastructure for YARNNN platform.
Creates work_requests, work_tickets, and orchestrates specialist agents.

NOTE: Post-SDK removal, agent orchestration is pending migration.
Use workflow-specific endpoints (/work/research, /work/reporting) instead.

Phase 5: Work-request-based trials (10 free requests total, then subscription).
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional
from uuid import UUID

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field

# Import Phase 1-3 utilities
from app.utils.jwt import verify_jwt
from app.utils.supabase_client import supabase_admin_client

# Import Phase 5 permissions
from utils.permissions import (
    get_trial_status,
    create_agent_subscription,
)

router = APIRouter(prefix="/agents", tags=["work-orchestration"])
logger = logging.getLogger(__name__)

logger.info("Work orchestration initialized (SDK removed - use workflow endpoints)")


async def _get_workspace_id_for_user(user_id: str) -> str:
    """
    Get workspace_id for user using existing authorization pattern.

    Args:
        user_id: User ID from JWT

    Returns:
        workspace_id for the user

    Raises:
        HTTPException: If user has no workspace or workspace not found
    """
    response = supabase_admin_client.table("workspace_memberships").select(
        "workspace_id"
    ).eq("user_id", user_id).limit(1).execute()

    if not response.data or len(response.data) == 0:
        logger.error(f"No workspace found for user {user_id}")
        raise HTTPException(
            status_code=403,
            detail="User does not belong to any workspace"
        )

    return response.data[0]['workspace_id']


# =====================================================================
# Models
# =====================================================================


class AgentTaskRequest(BaseModel):
    """Request to run agent task."""
    agent_type: str = Field(..., description="Agent type: research, content, reporting")
    task_type: str = Field(..., description="Task type specific to agent")
    basket_id: str = Field(..., description="Basket ID for agent context")
    parameters: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Task parameters")


class AgentTaskResponse(BaseModel):
    """Response from agent task execution."""
    status: str
    agent_type: str
    task_type: str
    message: str
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    work_request_id: Optional[str] = None
    is_trial_request: Optional[bool] = None
    remaining_trials: Optional[int] = None
    recommended_endpoint: Optional[str] = None


# =====================================================================
# Agent Task Endpoint (Migration Stub)
# =====================================================================


@router.post("/run", response_model=AgentTaskResponse, deprecated=True)
async def run_agent_task(
    request: AgentTaskRequest,
    user: dict = Depends(verify_jwt)
):
    """
    [DEPRECATED] Direct agent invocation endpoint.

    NOTE: Post-SDK removal, this endpoint returns a migration notice.
    Use workflow-specific endpoints instead:
    - POST /api/work/research/execute - For research tasks
    - POST /api/work/reporting/execute - For reporting tasks

    Args:
        request: Agent task request
        user: Authenticated user from JWT

    Returns:
        Migration notice with recommended endpoint
    """
    user_id = user.get("sub") or user.get("user_id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid user token")

    logger.warning(
        f"[WORK ORCHESTRATION] SDK removed - returning migration notice: "
        f"agent={request.agent_type}, task={request.task_type}, user={user_id}"
    )

    # Determine recommended endpoint based on agent type
    recommended = None
    if request.agent_type == "research":
        recommended = "/api/work/research/execute"
    elif request.agent_type in ("content", "reporting"):
        recommended = "/api/work/reporting/execute"

    return AgentTaskResponse(
        status="migration_pending",
        agent_type=request.agent_type,
        task_type=request.task_type,
        message=(
            f"Direct agent invocation is pending migration from Claude Agent SDK. "
            f"Use the workflow endpoint instead: {recommended or 'workflow endpoints'}"
        ),
        recommended_endpoint=recommended,
    )


# =====================================================================
# Capabilities Endpoint (Still Active)
# =====================================================================


@router.get("/capabilities")
async def get_agent_capabilities():
    """
    Get capabilities of all agents.

    Returns:
        Dictionary of agent capabilities
    """
    return {
        "status": "migration_in_progress",
        "note": "Claude Agent SDK removed. Use workflow endpoints.",
        "active_workflows": {
            "research": {
                "endpoint": "/api/work/research/execute",
                "status": "active",
                "description": "Deep-dive research with structured outputs"
            },
            "reporting": {
                "endpoint": "/api/work/reporting/execute",
                "status": "pending_migration",
                "description": "Document generation"
            }
        },
        "legacy_capabilities": {
            "research": {
                "tasks": ["monitor", "deep_dive"],
                "status": "migrated_to_workflow"
            },
            "content": {
                "tasks": ["create", "repurpose"],
                "status": "pending_migration"
            },
            "reporting": {
                "tasks": ["generate"],
                "status": "pending_migration"
            }
        },
        "architecture": {
            "pattern": "Direct Anthropic API + Executors",
            "adapters": ["SubstrateQueryAdapter"],
            "backend": "substrate-api (via HTTP)"
        }
    }


# =====================================================================
# Phase 5: Trial & Subscription Endpoints (Still Active)
# =====================================================================


@router.get("/trial-status")
async def get_user_trial_status(user: dict = Depends(verify_jwt)):
    """
    Get user's trial status (remaining free work requests).

    Phase 5: Users get 10 FREE work requests total across all agents.

    Args:
        user: Authenticated user from JWT

    Returns:
        Trial status with remaining requests and active subscriptions
    """
    user_id = user.get("sub") or user.get("user_id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid user token")

    workspace_id = await _get_workspace_id_for_user(user_id)
    trial_status = await get_trial_status(user_id=user_id, workspace_id=workspace_id)

    return trial_status


class AgentInfo(BaseModel):
    """Agent information from catalog."""
    agent_type: str
    name: str
    description: str
    monthly_price_usd: float
    trial_limit: int
    is_subscribed: bool


@router.get("/marketplace")
async def get_agent_marketplace(user: dict = Depends(verify_jwt)):
    """
    Get available agents with pricing and subscription status.

    Phase 5: Lists all agents users can "hire" with monthly pricing.

    Args:
        user: Authenticated user from JWT

    Returns:
        List of available agents with pricing and subscription status
    """
    user_id = user.get("sub") or user.get("user_id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid user token")

    workspace_id = await _get_workspace_id_for_user(user_id)

    try:
        # Get all active agents from catalog
        catalog_response = supabase_admin_client.table("agent_catalog").select(
            "agent_type, name, description, monthly_price_cents, trial_work_requests"
        ).eq("is_active", True).order("agent_type").execute()

        if not catalog_response.data:
            return {"agents": [], "trial_status": {"remaining_trial_requests": 10}}

        # Get user's subscriptions
        subs_response = supabase_admin_client.table("user_agent_subscriptions").select(
            "agent_type"
        ).eq("user_id", user_id).eq(
            "workspace_id", workspace_id
        ).eq("status", "active").execute()

        subscribed_types = {sub["agent_type"] for sub in subs_response.data} if subs_response.data else set()

        # Build agent list
        agents = []
        for agent in catalog_response.data:
            agents.append({
                "agent_type": agent["agent_type"],
                "name": agent["name"],
                "description": agent["description"],
                "monthly_price_usd": agent["monthly_price_cents"] / 100.0,
                "trial_limit": agent["trial_work_requests"],
                "is_subscribed": agent["agent_type"] in subscribed_types
            })

        # Get trial status
        trial_status = await get_trial_status(user_id=user_id, workspace_id=workspace_id)

        return {
            "agents": agents,
            "trial_status": {
                "remaining_trial_requests": trial_status["remaining_trial_requests"],
                "used_trial_requests": trial_status["used_trial_requests"]
            }
        }

    except Exception as e:
        logger.error(f"Error fetching marketplace: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to fetch marketplace: {str(e)}"
        )


class SubscribeRequest(BaseModel):
    """Request to subscribe to an agent."""
    stripe_subscription_id: Optional[str] = Field(None, description="Stripe subscription ID (optional for now)")
    stripe_customer_id: Optional[str] = Field(None, description="Stripe customer ID (optional for now)")


class SubscribeResponse(BaseModel):
    """Response from subscription creation."""
    subscription_id: str
    agent_type: str
    monthly_price_usd: float
    status: str
    message: str


@router.post("/subscribe/{agent_type}", response_model=SubscribeResponse)
async def subscribe_to_agent(
    agent_type: str,
    request: SubscribeRequest,
    user: dict = Depends(verify_jwt)
):
    """
    Subscribe to an agent (unlock unlimited work requests).

    Phase 5: Users "hire" agents individually with monthly subscriptions.
    Each subscription unlocks unlimited work requests for that specific agent.

    Args:
        agent_type: Agent type to subscribe to ('research', 'content', 'reporting')
        request: Subscription request with optional Stripe IDs
        user: Authenticated user from JWT

    Returns:
        Subscription details
    """
    user_id = user.get("sub") or user.get("user_id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid user token")

    workspace_id = await _get_workspace_id_for_user(user_id)

    # Create subscription
    subscription_id = await create_agent_subscription(
        user_id=user_id,
        workspace_id=workspace_id,
        agent_type=agent_type,
        stripe_subscription_id=request.stripe_subscription_id,
        stripe_customer_id=request.stripe_customer_id
    )

    # Get pricing from catalog
    catalog = supabase_admin_client.table("agent_catalog").select("monthly_price_cents").eq(
        "agent_type", agent_type
    ).single().execute()

    monthly_price = catalog.data["monthly_price_cents"] / 100.0

    logger.info(f"User {user_id} subscribed to {agent_type} agent (${monthly_price}/mo)")

    return SubscribeResponse(
        subscription_id=subscription_id,
        agent_type=agent_type,
        monthly_price_usd=monthly_price,
        status="active",
        message=f"Successfully subscribed to {agent_type} agent"
    )


@router.get("/migration-status")
async def get_migration_status():
    """
    Get SDK removal migration status for work orchestration.

    Returns:
        Migration status information
    """
    return {
        "status": "migration_in_progress",
        "message": "Claude Agent SDK has been removed. Agent orchestration is being migrated.",
        "active_endpoints": {
            "/api/work/research/execute": "active",
            "/api/work/reporting/execute": "pending_migration",
            "/api/agents/trial-status": "active",
            "/api/agents/marketplace": "active",
            "/api/agents/subscribe/{agent_type}": "active",
        },
        "deprecated_endpoints": {
            "/api/agents/run": "returns_migration_notice"
        },
        "migration_eta": "Phase 2 of SDK removal"
    }
