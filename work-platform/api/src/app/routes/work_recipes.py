"""
Work Recipes API - Recipe Discovery and Recipe-Driven Execution

Provides endpoints for:
1. Listing available work recipes (for frontend recipe selection)
2. Executing recipe-driven work requests (reporting, content, research)

Design Philosophy:
- Recipes are discoverable (GET /api/work/recipes)
- Execution is recipe-driven (POST /api/work/recipes/{slug}/execute)
- Parameters are validated against recipe schema
- Reference assets can be attached for context front-loading
"""

import logging
from typing import Optional, List, Dict, Any
from uuid import UUID
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from app.utils.jwt import verify_jwt
from app.utils.supabase_client import supabase_admin_client as supabase
from services.recipe_loader import RecipeLoader, RecipeValidationError
from agents_sdk.reporting_agent_sdk import ReportingAgentSDK
from agents_sdk.work_bundle import WorkBundle
from yarnnn_agents.session import AgentSession

router = APIRouter(prefix="/work/recipes", tags=["work_recipes"])
logger = logging.getLogger(__name__)


# ============================================================================
# Request/Response Models
# ============================================================================

class RecipeSummary(BaseModel):
    """Recipe summary for frontend display."""
    id: str
    slug: str
    name: str
    description: str
    category: str
    agent_type: str
    deliverable_intent: Dict[str, Any]
    configurable_parameters: Dict[str, Any]
    estimated_duration_seconds: List[int]  # [min, max]
    estimated_cost_cents: List[int]  # [min, max]


class RecipeExecutionRequest(BaseModel):
    """Request to execute a recipe-driven work request."""
    basket_id: str
    recipe_parameters: Dict[str, Any]  # User-customized parameters
    reference_asset_ids: Optional[List[str]] = []  # User-uploaded assets for context
    priority: Optional[str] = "normal"


class RecipeExecutionResponse(BaseModel):
    """Response from recipe execution."""
    work_request_id: str
    work_ticket_id: str
    agent_session_id: str
    recipe_id: str
    recipe_slug: str
    recipe_name: str
    status: str
    outputs: List[Dict[str, Any]]
    execution_time_ms: Optional[int]
    message: str


# ============================================================================
# Recipe Discovery Endpoints
# ============================================================================

@router.get("", response_model=List[RecipeSummary])
async def list_recipes(
    agent_type: Optional[str] = None,
    category: Optional[str] = None,
    user: dict = Depends(verify_jwt)
):
    """
    List all active work recipes.

    Query parameters:
    - agent_type: Filter by agent type (research, content, reporting)
    - category: Filter by category

    Returns:
        List of recipe summaries with configurable parameters and estimates
    """
    logger.info(f"[LIST RECIPES] agent_type={agent_type}, category={category}")

    try:
        loader = RecipeLoader()
        recipes = await loader.list_active_recipes(
            agent_type=agent_type,
            category=category
        )

        # Transform to response model
        return [
            RecipeSummary(
                id=r["id"],
                slug=r["slug"],
                name=r["name"],
                description=r.get("description", ""),
                category=r.get("category", ""),
                agent_type=r["agent_type"],
                deliverable_intent=r.get("deliverable_intent", {}),
                configurable_parameters=r.get("configurable_parameters", {}),
                estimated_duration_seconds=r.get("estimated_duration_seconds_range", [180, 360]),
                estimated_cost_cents=r.get("estimated_cost_cents_range", [300, 500]),
            )
            for r in recipes
        ]

    except Exception as e:
        logger.exception(f"[LIST RECIPES] Failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{slug}", response_model=RecipeSummary)
async def get_recipe(
    slug: str,
    user: dict = Depends(verify_jwt)
):
    """
    Get details of a specific recipe by slug.

    Args:
        slug: Recipe slug (e.g., "executive-summary-deck")

    Returns:
        Recipe details with configurable parameters
    """
    logger.info(f"[GET RECIPE] slug={slug}")

    try:
        loader = RecipeLoader()
        recipe = await loader.load_recipe(slug=slug)

        return RecipeSummary(
            id=recipe.id,
            slug=recipe.slug,
            name=recipe.name,
            description=recipe.description,
            category=recipe.category,
            agent_type=recipe.agent_type,
            deliverable_intent=recipe.deliverable_intent,
            configurable_parameters=recipe.configurable_parameters,
            estimated_duration_seconds=recipe.estimated_duration_seconds_range,
            estimated_cost_cents=recipe.estimated_cost_cents_range,
        )

    except RecipeValidationError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception(f"[GET RECIPE] Failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Recipe Execution Endpoint (Reporting Agent)
# ============================================================================

@router.post("/{slug}/execute", response_model=RecipeExecutionResponse)
async def execute_recipe(
    slug: str,
    request: RecipeExecutionRequest,
    user: dict = Depends(verify_jwt)
):
    """
    Execute a recipe-driven work request.

    Flow:
    1. Load recipe by slug
    2. Validate user parameters against recipe schema
    3. Create work_request with recipe linkage
    4. Load context (WorkBundle: blocks + reference_assets)
    5. Generate execution context from recipe template
    6. Execute agent (ReportingAgentSDK for reporting recipes)
    7. Return structured outputs

    Args:
        slug: Recipe slug (e.g., "executive-summary-deck")
        request: Recipe execution parameters

    Returns:
        Recipe execution result with outputs
    """
    user_id = user.get("sub") or user.get("user_id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid user token")

    logger.info(
        f"[EXECUTE RECIPE] slug={slug}, user={user_id}, basket={request.basket_id}"
    )

    try:
        # Step 1: Load recipe
        loader = RecipeLoader()
        recipe = await loader.load_recipe(slug=slug)

        logger.info(f"[EXECUTE RECIPE] Loaded recipe: {recipe.name} (v{recipe.version})")

        # Step 2: Validate parameters
        try:
            validated_params = loader.validate_parameters(
                recipe=recipe,
                user_parameters=request.recipe_parameters
            )
            logger.info(f"[EXECUTE RECIPE] Validated parameters: {validated_params}")
        except RecipeValidationError as e:
            raise HTTPException(status_code=400, detail=f"Parameter validation failed: {str(e)}")

        # Step 3: Generate execution context
        execution_context = loader.generate_execution_context(
            recipe=recipe,
            validated_parameters=validated_params
        )

        # Step 4: Validate basket access and get workspace
        basket_response = supabase.table("baskets").select(
            "id, workspace_id, name"
        ).eq("id", request.basket_id).single().execute()

        if not basket_response.data:
            raise HTTPException(status_code=404, detail="Basket not found")

        basket = basket_response.data
        workspace_id = basket["workspace_id"]

        # Step 5: Get or create agent session
        agent_session = await AgentSession.get_or_create(
            basket_id=request.basket_id,
            workspace_id=workspace_id,
            agent_type=recipe.agent_type,
            user_id=user_id,
        )

        logger.info(f"[EXECUTE RECIPE] Agent session: {agent_session.id}")

        # Step 6: Create work_request with recipe linkage
        work_request_data = {
            "workspace_id": workspace_id,
            "basket_id": request.basket_id,
            "agent_session_id": agent_session.id,
            "requested_by_user_id": user_id,
            "request_type": f"recipe_{recipe.slug}",
            "task_intent": f"{recipe.name}: {execution_context['deliverable_intent'].get('purpose', '')}",
            "parameters": {
                "recipe_id": recipe.id,
                "recipe_slug": recipe.slug,
                "recipe_parameters": validated_params,
                "execution_context": execution_context,
            },
            "priority": request.priority,
            "recipe_id": recipe.id,  # NEW: Recipe linkage
            "recipe_parameters": validated_params,  # NEW: Validated parameters
            "reference_asset_ids": request.reference_asset_ids or [],  # NEW: Reference assets
        }

        work_request_response = supabase.table("work_requests").insert(
            work_request_data
        ).execute()
        work_request_id = work_request_response.data[0]["id"]

        # Step 7: Create work_ticket
        work_ticket_data = {
            "work_request_id": work_request_id,
            "agent_session_id": agent_session.id,
            "workspace_id": workspace_id,
            "basket_id": request.basket_id,
            "agent_type": recipe.agent_type,
            "status": "pending",
            "metadata": {
                "recipe_id": recipe.id,
                "recipe_slug": recipe.slug,
                "recipe_name": recipe.name,
            },
        }

        work_ticket_response = supabase.table("work_tickets").insert(
            work_ticket_data
        ).execute()
        work_ticket_id = work_ticket_response.data[0]["id"]

        logger.info(
            f"[EXECUTE RECIPE] Created: work_request={work_request_id}, "
            f"work_ticket={work_ticket_id}"
        )

        # Step 8: Load context (WorkBundle pattern)
        blocks_response = supabase.table("blocks").select(
            "id, content, semantic_type, state, created_at, metadata"
        ).eq("basket_id", request.basket_id).in_(
            "state", ["ACCEPTED", "LOCKED", "CONSTANT"]
        ).order("created_at", desc=True).limit(50).execute()

        substrate_blocks = blocks_response.data or []

        # Load reference assets (user-uploaded)
        reference_assets = []
        if request.reference_asset_ids:
            assets_response = supabase.table("documents").select(
                "id, title, document_type, metadata, file_url"
            ).in_("id", request.reference_asset_ids).execute()
            reference_assets = assets_response.data or []

        # Create WorkBundle
        context_bundle = WorkBundle(
            work_request_id=work_request_id,
            work_ticket_id=work_ticket_id,
            basket_id=request.basket_id,
            workspace_id=workspace_id,
            user_id=user_id,
            task=execution_context["deliverable_intent"].get("purpose", recipe.name),
            agent_type=recipe.agent_type,
            priority=request.priority,
            substrate_blocks=substrate_blocks,
            reference_assets=reference_assets,
            agent_config=execution_context,  # Pass execution context as config
        )

        logger.info(
            f"[EXECUTE RECIPE] WorkBundle: {len(substrate_blocks)} blocks, "
            f"{len(reference_assets)} assets"
        )

        # Step 9: Update work_ticket to running
        supabase.table("work_tickets").update({
            "status": "running",
            "started_at": "now()",
        }).eq("id", work_ticket_id).execute()

        # Step 10: Execute agent (currently only ReportingAgentSDK)
        if recipe.agent_type == "reporting":
            logger.info(f"[EXECUTE RECIPE] Executing ReportingAgentSDK...")

            reporting_sdk = ReportingAgentSDK(
                basket_id=request.basket_id,
                workspace_id=workspace_id,
                work_ticket_id=work_ticket_id,
                session=agent_session,
                bundle=context_bundle,
            )

            import time
            start_time = time.time()

            # Execute recipe-driven generation
            result = await reporting_sdk.execute_recipe(
                recipe_context=execution_context,
                claude_session_id=agent_session.claude_session_id,
            )

            execution_time_ms = int((time.time() - start_time) * 1000)

            # Step 11: Update work_ticket to completed
            supabase.table("work_tickets").update({
                "status": "completed",
                "completed_at": "now()",
                "metadata": {
                    "recipe_id": recipe.id,
                    "recipe_slug": recipe.slug,
                    "execution_time_ms": execution_time_ms,
                    "output_count": result.get("output_count", 0),
                },
            }).eq("id", work_ticket_id).execute()

            logger.info(
                f"[EXECUTE RECIPE] Execution complete: {result.get('output_count', 0)} outputs "
                f"in {execution_time_ms}ms"
            )

            return RecipeExecutionResponse(
                work_request_id=work_request_id,
                work_ticket_id=work_ticket_id,
                agent_session_id=agent_session.id,
                recipe_id=recipe.id,
                recipe_slug=recipe.slug,
                recipe_name=recipe.name,
                status="completed",
                outputs=result.get("work_outputs", []),
                execution_time_ms=execution_time_ms,
                message=f"Recipe '{recipe.name}' executed successfully: {result.get('output_count', 0)} outputs generated",
            )

        else:
            # Future: Support other agent types (research, content)
            raise HTTPException(
                status_code=501,
                detail=f"Recipe execution for agent_type '{recipe.agent_type}' not yet implemented"
            )

    except HTTPException:
        raise
    except RecipeValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception(f"[EXECUTE RECIPE] Failed: {e}")

        # Update work_ticket to failed if it exists
        if 'work_ticket_id' in locals():
            try:
                supabase.table("work_tickets").update({
                    "status": "failed",
                    "completed_at": "now()",
                    "error_message": str(e),
                    "metadata": {
                        "error_type": type(e).__name__,
                        "recipe_id": recipe.id if 'recipe' in locals() else None,
                    },
                }).eq("id", work_ticket_id).execute()
            except Exception as update_error:
                logger.error(f"Failed to update work_ticket: {update_error}")

        raise HTTPException(
            status_code=500,
            detail=f"Recipe execution failed: {str(e)}"
        )
