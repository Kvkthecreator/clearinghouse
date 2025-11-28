"""Create raw dumps via RPC with idempotency."""
from __future__ import annotations

import json
import logging
import time
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, model_validator

from ..utils.jwt import verify_jwt
from ..utils.supabase import supabase_admin
from services.events import EventService

router = APIRouter(prefix="/dumps", tags=["dumps"])
log = logging.getLogger("uvicorn.error")


class CreateDumpReq(BaseModel):
    basket_id: str
    dump_request_id: str
    text_dump: str | None = None
    file_url: str | None = None
    meta: dict[str, Any] | None = None

    @model_validator(mode="after")
    def require_content(cls, model):  # type: ignore[override]
        if not model.text_dump and not model.file_url:
            raise ValueError("Either text_dump or file_url must be provided")
        return model


@router.post("/new", status_code=201)
async def create_dump(
    payload: CreateDumpReq, req: Request
):
    """
    Create raw dump (Phase 6: Service-to-service endpoint, no JWT required).

    This endpoint is called by work-platform during project scaffolding.
    Authentication is handled via SUBSTRATE_SERVICE_SECRET at middleware level.
    """
    start = time.time()

    # For service-to-service calls, we don't have a user context
    # The user_id should be passed in the metadata if needed
    user = None

    sb = supabase_admin()
    basket = (
        sb.table("baskets")
        .select("id, workspace_id")
        .eq("id", payload.basket_id)
        .single()
        .execute()
    )
    if not basket.data:
        raise HTTPException(status_code=404, detail="Basket not found")
    workspace_id = basket.data["workspace_id"]

    # Skip workspace membership check for service-to-service calls
    if user is not None:
        membership = (
            sb.table("workspace_memberships")
            .select("workspace_id")
            .eq("workspace_id", workspace_id)
            .eq("user_id", user["user_id"])
            .execute()
        )
        if not membership.data:
            log.info(
                json.dumps(
                    {
                        "route": "/api/dumps/new",
                        "user_id": user["user_id"],
                        "basket_id": payload.basket_id,
                        "dump_request_id": payload.dump_request_id,
                        "action": "forbidden",
                    }
                )
            )
            raise HTTPException(status_code=403, detail="Workspace access denied")

    dumps = [
        {
            "dump_request_id": payload.dump_request_id,
            "text_dump": payload.text_dump,
            "file_url": payload.file_url,
            "source_meta": payload.meta or {},
            "ingest_trace_id": (payload.meta or {}).get("ingest_trace_id"),
        }
    ]
    resp = sb.rpc(
        "fn_ingest_dumps",
        {
            "p_workspace_id": workspace_id,
            "p_basket_id": payload.basket_id,
            "p_dumps": dumps,
        },
    ).execute()
    if getattr(resp, "error", None):
        err = resp.error
        if getattr(err, "code", "") == "23505":
            raise HTTPException(status_code=409, detail="IDEMPOTENCY_CONFLICT")
        raise HTTPException(status_code=500, detail="INTERNAL_ERROR")

    if not resp.data:
        raise HTTPException(status_code=500, detail="INGEST_FAILED")

    dump_id = resp.data[0]["dump_id"]
    log.info(
        json.dumps(
            {
                "route": "/api/dumps/new",
                "user_id": user["user_id"] if user else "service_to_service",
                "basket_id": payload.basket_id,
                "dump_request_id": payload.dump_request_id,
                "action": "created",
                "dump_id": dump_id,
                "duration_ms": int((time.time() - start) * 1000),
            }
        )
    )
    
    # Emit notification for dump creation
    try:
        EventService.emit_app_event(
            workspace_id=workspace_id,
            type="action_result",
            name="dump.create",
            message=f"Memory dump created successfully",
            severity="success",
            basket_id=payload.basket_id,
            entity_id=dump_id,
            correlation_id=req.headers.get("X-Correlation-Id"),
            payload={
                "dump_id": dump_id,
                "content_type": "text" if payload.text_dump else "file",
                "duration_ms": int((time.time() - start) * 1000)
            }
        )
    except Exception as e:
        log.warning(f"Failed to emit dump creation notification: {e}")
    
    return JSONResponse({"dump_id": dump_id}, status_code=201)
