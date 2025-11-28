import json
import os
import sys
from uuid import uuid4, UUID
from typing import Optional

# CRITICAL: Add src to path BEFORE any other imports that depend on it
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../.."))

from contracts.basket import BasketChangeRequest, BasketDelta
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, ValidationError
from ..baskets.schemas import BasketWorkRequest
from typing import Union
from infra.substrate.services.deltas import list_deltas, persist_delta, try_apply_delta
from infra.substrate.services.idempotency import (
    already_processed,
    fetch_delta_by_request_id,
    mark_processed,
)
# Legacy manager removed - use canonical queue processor
from src.services.canonical_queue_processor import CanonicalQueueProcessor, get_canonical_queue_health

# Import deps AFTER path setup
from ..deps import get_db
from ..utils.jwt import verify_jwt
from ..utils.workspace import get_or_create_workspace

router = APIRouter(prefix="/api/baskets", tags=["baskets"])


# ========================================================================
# Phase 6: Basket Creation Models
# ========================================================================


class CreateBasketRequest(BaseModel):
    """Request model for creating a new basket."""

    workspace_id: str = Field(..., description="Workspace ID for basket")
    name: str = Field(..., min_length=1, max_length=200, description="Basket name")
    metadata: Optional[dict] = Field(default_factory=dict, description="Metadata (stored in tags as JSON)")
    user_id: Optional[str] = Field(None, description="User ID (for audit trail)")


class CreateBasketResponse(BaseModel):
    """Response model for basket creation."""

    basket_id: str
    name: str
    workspace_id: str
    status: str
    user_id: Optional[str]
    created_at: str


# ========================================================================
# Phase 4: Service-to-Service Blocks Endpoint (BFF Pattern)
# IMPORTANT: Must be defined BEFORE /{basket_id} to ensure proper route matching
# ========================================================================


@router.get("/{basket_id}/blocks")
async def list_basket_blocks(
    basket_id: str,
    states: Optional[str] = None,
    limit: int = 20,
    prioritize_anchors: bool = True,
    db=Depends(get_db),  # noqa: B008
):
    """
    List blocks for a basket (service-to-service endpoint).

    Phase 4: Called by work-platform's SubstrateMemoryAdapter via substrate_client.
    This endpoint is part of the Phase 3 BFF architecture - work-platform never
    touches substrate tables directly.

    No JWT auth required - uses service-to-service auth via exempt_prefixes.

    Args:
        basket_id: Basket UUID
        states: Optional comma-separated list of block states (e.g., "ACCEPTED,LOCKED")
        limit: Maximum number of blocks to return (default: 20)
        prioritize_anchors: If True, anchor blocks appear first (default: True)
        db: Database connection

    Returns:
        List of block dictionaries with id, title, content, semantic_type,
        confidence_score, state, anchor_role, created_at, updated_at

    Raises:
        HTTPException 400: Invalid basket_id format
        HTTPException 500: Database error
    """
    import logging

    logger = logging.getLogger(__name__)

    try:
        # Validate basket_id is valid UUID
        try:
            basket_uuid = UUID(basket_id)
        except (ValueError, AttributeError) as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid basket_id format: {basket_id}",
            ) from e

        # Build query with optional state filtering
        # Include anchor_role for context assembly prioritization
        query = """
            SELECT id, title, content, semantic_type, confidence_score, state,
                   anchor_role, anchor_status, anchor_confidence,
                   created_at, updated_at
            FROM blocks
            WHERE basket_id = :basket_id
        """

        query_values = {"basket_id": str(basket_uuid)}

        # Add state filtering if provided
        if states:
            state_list = [s.strip().upper() for s in states.split(",")]
            # Use ANY for array comparison
            query += " AND state = ANY(:states)"
            query_values["states"] = state_list

        # Sort anchor blocks first (advisory pattern - anchors are quality signals)
        # anchor_role IS NOT NULL = 1 (true), IS NULL = 0 (false)
        # DESC puts 1s (anchors) first
        if prioritize_anchors:
            query += " ORDER BY (anchor_role IS NOT NULL) DESC, created_at DESC LIMIT :limit"
        else:
            query += " ORDER BY created_at DESC LIMIT :limit"
        query_values["limit"] = limit

        results = await db.fetch_all(query, values=query_values)

        # Convert to dict format
        blocks = [dict(row) for row in results]

        anchor_count = sum(1 for b in blocks if b.get("anchor_role"))
        logger.debug(
            f"[SERVICE] Fetched {len(blocks)} blocks ({anchor_count} anchors) for basket {basket_id} "
            f"(states={states}, limit={limit}, prioritize_anchors={prioritize_anchors})"
        )

        return blocks

    except HTTPException:
        raise

    except Exception as e:
        logger.exception(f"Failed to fetch blocks for basket {basket_id}: {e}")
        raise HTTPException(
            status_code=500, detail=f"Failed to fetch blocks: {str(e)}"
        ) from e


# ========================================================================
# Phase 6: Basket Creation Endpoint
# ========================================================================


@router.post("", response_model=CreateBasketResponse, status_code=201)
async def create_basket(
    request: CreateBasketRequest,
    db=Depends(get_db),  # noqa: B008
):
    """
    Create a new basket.

    Phase 6: Called by work-platform's onboarding_scaffolder via substrate_client.
    This endpoint is part of the Phase 3 BFF architecture - work-platform never
    touches substrate tables directly.

    Args:
        request: Basket creation parameters
        db: Database connection

    Returns:
        Created basket information

    Raises:
        HTTPException 400: Invalid workspace_id or validation error
        HTTPException 500: Database error
    """
    import logging

    logger = logging.getLogger(__name__)

    try:
        # Validate workspace_id is valid UUID
        try:
            workspace_uuid = UUID(request.workspace_id)
        except (ValueError, AttributeError) as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid workspace_id format: {request.workspace_id}",
            ) from e

        # Validate user_id if provided
        user_uuid = None
        if request.user_id:
            try:
                user_uuid = UUID(request.user_id)
            except (ValueError, AttributeError) as e:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid user_id format: {request.user_id}",
                ) from e

        # Generate basket ID
        basket_id = uuid4()

        # Prepare tags array with metadata
        tags = []
        if request.metadata:
            # Store metadata keys as tags for searchability
            for key, value in request.metadata.items():
                tags.append(f"{key}:{str(value)}")

        # Insert basket using actual production schema
        query = """
            INSERT INTO baskets (id, name, workspace_id, user_id, status, tags, origin_template)
            VALUES (:id, :name, :workspace_id, :user_id, :status, :tags, :origin_template)
            RETURNING id, name, workspace_id, user_id, status, created_at
        """

        result = await db.fetch_one(
            query,
            values={
                "id": str(basket_id),
                "name": request.name,
                "workspace_id": str(workspace_uuid),
                "user_id": str(user_uuid) if user_uuid else None,
                "status": "INIT",  # basket_state enum default
                "tags": tags,
                "origin_template": "work_platform_onboarding",  # origin_template for tracking
            },
        )

        if not result:
            raise HTTPException(status_code=500, detail="Failed to create basket")

        logger.info(
            f"[BASKET CREATE] Created basket {result['id']} "
            f"for workspace {result['workspace_id']} via Phase 6 onboarding"
        )

        return CreateBasketResponse(
            basket_id=str(result["id"]),
            name=result["name"],
            workspace_id=str(result["workspace_id"]),
            user_id=str(result["user_id"]) if result["user_id"] else None,
            status=str(result["status"]),
            created_at=result["created_at"].isoformat(),
        )

    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise

    except Exception as e:
        logger.exception(f"Failed to create basket: {e}")
        raise HTTPException(
            status_code=500, detail=f"Failed to create basket: {str(e)}"
        ) from e


@router.get("/{basket_id}", status_code=200)
async def get_basket(
    basket_id: str,
    user: dict = Depends(verify_jwt),  # noqa: B008
    db=Depends(get_db),  # noqa: B008
):
    """
    Get basket details with stats.

    Service-to-service endpoint for BFF pattern. Returns basket metadata
    and aggregate counts (blocks, documents).

    Args:
        basket_id: Basket UUID
        db: Database connection

    Returns:
        {
            "id": "...",
            "name": "...",
            "status": "...",
            "workspace_id": "...",
            "user_id": "...",
            "created_at": "...",
            "updated_at": "...",
            "stats": {
                "blocks_count": 0,
                "documents_count": 0
            }
        }

    Raises:
        HTTPException 404: Basket not found
        HTTPException 500: Database error
    """
    import logging

    logger = logging.getLogger(__name__)

    try:
        # Validate basket_id is valid UUID
        try:
            basket_uuid = UUID(basket_id)
        except (ValueError, AttributeError) as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid basket_id format: {basket_id}",
            ) from e

        # Fetch basket with stats
        basket_query = """
            SELECT
                id,
                name,
                status,
                workspace_id,
                user_id,
                created_at
            FROM baskets
            WHERE id = :basket_id
        """

        basket = await db.fetch_one(basket_query, values={"basket_id": str(basket_uuid)})

        if not basket:
            raise HTTPException(status_code=404, detail="Basket not found")

        # Get blocks count
        blocks_count_query = """
            SELECT COUNT(*) as count
            FROM blocks
            WHERE basket_id = :basket_id
            AND state IN ('CONSTANT', 'LOCKED', 'ACCEPTED', 'PROPOSED')
        """
        blocks_result = await db.fetch_one(blocks_count_query, values={"basket_id": str(basket_uuid)})
        blocks_count = blocks_result["count"] if blocks_result else 0

        # Get documents count
        documents_count_query = """
            SELECT COUNT(*) as count
            FROM documents
            WHERE basket_id = :basket_id
        """
        documents_result = await db.fetch_one(documents_count_query, values={"basket_id": str(basket_uuid)})
        documents_count = documents_result["count"] if documents_result else 0

        logger.info(f"[BASKET GET] Fetched basket {basket_id}: {blocks_count} blocks, {documents_count} documents")

        return {
            "id": str(basket["id"]),
            "name": basket["name"],
            "status": basket["status"],
            "workspace_id": str(basket["workspace_id"]),
            "user_id": str(basket["user_id"]) if basket["user_id"] else None,
            "created_at": basket["created_at"].isoformat(),
            "stats": {
                "blocks_count": blocks_count,
                "documents_count": documents_count,
            },
        }

    except HTTPException:
        raise

    except Exception as e:
        logger.exception(f"Failed to fetch basket {basket_id}: {e}")
        raise HTTPException(
            status_code=500, detail=f"Failed to fetch basket: {str(e)}"
        ) from e


@router.post("/{basket_id}/work", response_model=BasketDelta)
async def post_basket_work(
    basket_id: str,
    request: Request,
    user: dict = Depends(verify_jwt),  # noqa: B008
    db=Depends(get_db),  # noqa: B008
):
    """Process basket work request with mode support"""
    
    # Parse request body to determine format
    try:
        body = await request.json()
    except Exception as err:
        raise HTTPException(400, "Invalid JSON") from err

    workspace_id = get_or_create_workspace(user["user_id"])
    trace_req_id = request.headers.get("X-Req-Id")

    if "mode" in body:
        # New BasketWorkRequest format
        from ..baskets.schemas import BasketWorkRequest
        try:
            work_req = BasketWorkRequest.model_validate(body)
        except ValidationError as err:
            raise HTTPException(422, err.errors())

        # Attach trace ID (don't lose it)
        work_req.options.trace_req_id = trace_req_id

        # Idempotency for new mode - prioritize trace_req_id for deduplication
        request_id = (work_req.options.trace_req_id
                      or request.headers.get("X-Req-Id")
                      or f"work_{uuid4().hex[:8]}")
        if await already_processed(db, request_id):
            cached_delta = await fetch_delta_by_request_id(db, request_id)
            if not cached_delta:
                raise HTTPException(409, "Duplicate request but missing delta")
            return BasketDelta(**json.loads(cached_delta["payload"]))

        # ✅ Call canonical queue processor for basket work
        processor = CanonicalQueueProcessor()
        delta = await processor.process_basket_work(basket_id, work_req, workspace_id)

        await persist_delta(db, delta, request_id)
        await mark_processed(db, request_id, delta.delta_id)
        return delta

    else:
        # Legacy BasketChangeRequest format
        try:
            req = BasketChangeRequest.model_validate(body)
        except ValidationError as err:
            raise HTTPException(422, err.errors())
        if req.basket_id != basket_id:
            raise HTTPException(400, "basket_id mismatch")

        if await already_processed(db, req.request_id):
            cached_delta = await fetch_delta_by_request_id(db, req.request_id)
            if not cached_delta:
                raise HTTPException(409, "Duplicate request but missing delta")
            return BasketDelta(**json.loads(cached_delta["payload"]))

        # Legacy path with basket_id - use canonical queue processor
        processor = CanonicalQueueProcessor()
        delta = await processor.process_basket_change(basket_id, req, workspace_id)

        await persist_delta(db, delta, req.request_id)
        await mark_processed(db, req.request_id, delta.delta_id)
        return delta


@router.get("/{basket_id}/deltas")
async def get_basket_deltas(basket_id: str, db=Depends(get_db)):  # noqa: B008
    """Get all deltas for a basket"""
    return await list_deltas(db, basket_id)


@router.post("/{basket_id}/apply/{delta_id}")
async def apply_basket_delta(
    basket_id: str,
    delta_id: str,
    db=Depends(get_db),  # noqa: B008
):
    """Apply a specific delta"""
    success = await try_apply_delta(db, basket_id, delta_id)
    if not success:
        raise HTTPException(409, "Version conflict or delta not found")

    return {"status": "applied", "basket_id": basket_id, "delta_id": delta_id}


