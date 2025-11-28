"""API routes for block lifecycle management and agent proposals."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Body
from pydantic import BaseModel

from ..memory.blocks import (
    BlockLifecycleService,
    BlockProposalService,
    StateTransitionError,
    StateTransitionRequest,
    BlockProposalRequest,
    ProposalActionRequest
)
from ..utils.jwt import verify_jwt
from ..utils.workspace import get_or_create_workspace
from services.events import EventService

router = APIRouter(prefix="/blocks", tags=["block-lifecycle"])
logger = logging.getLogger("uvicorn.error")


@router.post("/{block_id}/transition")
async def transition_block_state(
    block_id: str,
    request: StateTransitionRequest,
    user: dict = Depends(verify_jwt)
):
    """Transition a block to a new state with validation."""
    try:
        result = await BlockLifecycleService.transition_block_state(
            block_id=UUID(block_id),
            new_state=request.new_state,
            actor_id=user["user_id"],
            actor_type="user",
            reason=request.reason
        )
        return result
    except StateTransitionError as e:
        raise HTTPException(400, str(e))
    except ValueError as e:
        raise HTTPException(400, f"Invalid block ID: {block_id}")
    except Exception as e:
        logger.exception("State transition failed")
        raise HTTPException(500, "Internal error")


@router.post("/baskets/{basket_id}/propose")
async def propose_block(
    basket_id: str,
    request: BlockProposalRequest,
    user: dict = Depends(verify_jwt)
):
    """Create a new block proposal (typically called by agents)."""
    try:
        # For now, treat all proposals as coming from the authenticated user
        # In future iterations, this will be called by agent services
        result = await BlockProposalService.propose_block(
            basket_id=UUID(basket_id),
            semantic_type=request.semantic_type,
            content=request.content,
            agent_id=user["user_id"],  # Will be agent_id in production
            origin_ref=request.origin_ref,
            scope=request.scope
        )
        return result
    except ValueError as e:
        raise HTTPException(400, f"Invalid basket ID: {basket_id}")
    except Exception as e:
        logger.exception("Block proposal failed")
        raise HTTPException(500, "Internal error")


@router.post("/{block_id}/approve")
async def approve_block_proposal(
    block_id: str,
    request: ProposalActionRequest,
    user: dict = Depends(verify_jwt)
):
    """User approves a proposed block."""
    try:
        result = await BlockProposalService.approve_proposal(
            block_id=UUID(block_id),
            user_id=user["user_id"],
            feedback=request.feedback
        )
        
        # Emit notification for approval
        try:
            workspace = await get_or_create_workspace(user["user_id"])
            EventService.emit_app_event(
                workspace_id=workspace["id"],
                type="action_result",
                name="block.approve",
                message=f"Block proposal approved",
                severity="success",
                entity_id=block_id,
                payload={
                    "block_id": block_id,
                    "approved_by": user["user_id"],
                    "feedback": request.feedback
                }
            )
        except Exception as e:
            logger.warning(f"Failed to emit block approval notification: {e}")
        
        return result
    except StateTransitionError as e:
        raise HTTPException(400, str(e))
    except ValueError as e:
        raise HTTPException(400, f"Invalid block ID: {block_id}")
    except Exception as e:
        logger.exception("Block approval failed")
        raise HTTPException(500, "Internal error")


@router.post("/{block_id}/reject") 
async def reject_block_proposal(
    block_id: str,
    request: ProposalActionRequest,
    user: dict = Depends(verify_jwt)
):
    """User rejects a proposed block."""
    try:
        result = await BlockProposalService.reject_proposal(
            block_id=UUID(block_id),
            user_id=user["user_id"],
            reason=request.feedback
        )
        
        # Emit notification for rejection
        try:
            workspace = await get_or_create_workspace(user["user_id"])
            EventService.emit_app_event(
                workspace_id=workspace["id"],
                type="action_result",
                name="block.reject",
                message=f"Block proposal rejected",
                severity="warning",
                entity_id=block_id,
                payload={
                    "block_id": block_id,
                    "rejected_by": user["user_id"],
                    "reason": request.feedback
                }
            )
        except Exception as e:
            logger.warning(f"Failed to emit block rejection notification: {e}")
        
        return result
    except StateTransitionError as e:
        raise HTTPException(400, str(e))
    except ValueError as e:
        raise HTTPException(400, f"Invalid block ID: {block_id}")
    except Exception as e:
        logger.exception("Block rejection failed")
        raise HTTPException(500, "Internal error")


@router.get("/baskets/{basket_id}/proposed")
def list_proposed_blocks(
    basket_id: str,
    user: dict = Depends(verify_jwt)
):
    """List all blocks in PROPOSED state for a basket."""
    try:
        workspace_id = get_or_create_workspace(user["user_id"])
        
        from ..utils.supabase_client import supabase_client as supabase
        # Canon: use canonical fields for blocks
        resp = (
            supabase.table("blocks")
            .select("id,title,content,semantic_type,confidence_score,state,created_at,updated_at")
            .eq("basket_id", basket_id)
            .eq("workspace_id", workspace_id)
            .eq("state", "PROPOSED")
            .order("created_at", desc=True)
            .execute()
        )
        
        return resp.data or []
    except Exception as e:
        logger.exception("Failed to list proposed blocks")
        raise HTTPException(500, "Internal error")


@router.get("/{block_id}/lifecycle")
def get_block_lifecycle_history(
    block_id: str,
    user: dict = Depends(verify_jwt)
):
    """Get the complete lifecycle history for a block."""
    try:
        workspace_id = get_or_create_workspace(user["user_id"])
        
        from ..utils.supabase_client import supabase_client as supabase
        
        # Get block info
        block_resp = (
            supabase.table("blocks")
            .select("id,state,version,created_at")
            .eq("id", block_id)
            .eq("workspace_id", workspace_id)
            .maybe_single()
            .execute()
        )
        
        if not block_resp.data:
            raise HTTPException(404, "Block not found")
        
        # Get revision history
        revisions_resp = (
            supabase.table("block_revisions")
            .select("*")
            .eq("block_id", block_id)
            .order("created_at", desc=True)
            .execute()
        )
        
        # Get related events
        events_resp = (
            supabase.table("events")
            .select("*")
            .eq("block_id", block_id)
            .order("ts", desc=True)
            .execute()
        )
        
        return {
            "block": block_resp.data,
            "revisions": revisions_resp.data or [],
            "events": events_resp.data or []
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to get block lifecycle")
        raise HTTPException(500, "Internal error")