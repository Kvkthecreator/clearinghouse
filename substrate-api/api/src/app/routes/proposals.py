"""Governance proposal endpoints."""
from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Query
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


class ProposalCreate(BaseModel):
    proposal_type: str  # CREATE, UPDATE, TRANSFER, VERIFY, DISPUTE, ARCHIVE, RESTORE
    target_entity_id: Optional[UUID] = None
    payload: dict
    reasoning: Optional[str] = None
    priority: str = "normal"


class ProposalReview(BaseModel):
    status: str  # approved, rejected
    review_notes: Optional[str] = None


class ProposalComment(BaseModel):
    content: str
    comment_type: str = "comment"  # comment, question, concern, approval, rejection


@router.get("/catalogs/{catalog_id}/proposals")
async def list_proposals(
    request: Request,
    catalog_id: UUID,
    status: str = Query("pending", enum=["pending", "under_review", "approved", "rejected", "all"]),
    proposal_type: Optional[str] = None,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List proposals for a catalog."""
    user_id = request.state.user_id
    db = await get_db()

    # Check catalog access
    catalog = await db.fetch_one("""
        SELECT c.id
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    # Build query
    where_clauses = ["catalog_id = :catalog_id"]
    params = {"catalog_id": str(catalog_id), "limit": limit, "offset": offset}

    if status != "all":
        where_clauses.append("status = :status")
        params["status"] = status

    if proposal_type:
        where_clauses.append("proposal_type = :proposal_type")
        params["proposal_type"] = proposal_type

    proposals = await db.fetch_all(f"""
        SELECT p.id, p.proposal_type, p.target_entity_id, p.status, p.priority,
               p.auto_approved, p.created_by, p.created_at, p.reviewed_at,
               re.title as entity_title, re.rights_type
        FROM proposals p
        LEFT JOIN rights_entities re ON re.id = p.target_entity_id
        WHERE {' AND '.join(where_clauses)}
        ORDER BY
            CASE p.priority
                WHEN 'urgent' THEN 1
                WHEN 'high' THEN 2
                WHEN 'normal' THEN 3
                ELSE 4
            END,
            p.created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    # Get count
    count_params = {k: v for k, v in params.items() if k not in ("limit", "offset")}
    count_result = await db.fetch_one(f"""
        SELECT COUNT(*) as total
        FROM proposals
        WHERE {' AND '.join(where_clauses)}
    """, count_params)

    return {
        "proposals": [dict(p) for p in proposals],
        "total": count_result["total"],
        "limit": limit,
        "offset": offset
    }


@router.post("/catalogs/{catalog_id}/proposals")
async def create_proposal(request: Request, catalog_id: UUID, payload: ProposalCreate):
    """Create a new proposal."""
    user_id = request.state.user_id
    db = await get_db()

    # Check catalog access
    catalog = await db.fetch_one("""
        SELECT c.id, c.workspace_id
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    # Validate proposal type
    valid_types = ["CREATE", "UPDATE", "TRANSFER", "VERIFY", "DISPUTE", "ARCHIVE", "RESTORE"]
    if payload.proposal_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid proposal_type. Must be one of: {valid_types}")

    # For non-CREATE proposals, validate target entity
    if payload.proposal_type != "CREATE" and not payload.target_entity_id:
        raise HTTPException(status_code=400, detail="target_entity_id required for non-CREATE proposals")

    if payload.target_entity_id:
        entity = await db.fetch_one("""
            SELECT id FROM rights_entities
            WHERE id = :entity_id AND catalog_id = :catalog_id
        """, {"entity_id": str(payload.target_entity_id), "catalog_id": str(catalog_id)})

        if not entity:
            raise HTTPException(status_code=404, detail="Target entity not found in this catalog")

    # Check governance rules for auto-approval
    governance = await db.fetch_one("""
        SELECT auto_approve_types
        FROM governance_rules
        WHERE catalog_id = :catalog_id AND is_active = true
    """, {"catalog_id": str(catalog_id)})

    auto_approve = False
    auto_reason = None
    if governance and governance["auto_approve_types"]:
        if payload.proposal_type in governance["auto_approve_types"]:
            auto_approve = True
            auto_reason = f"Auto-approved: {payload.proposal_type} in auto_approve_types"

    proposal = await db.fetch_one("""
        INSERT INTO proposals (
            catalog_id, proposal_type, target_entity_id,
            payload, reasoning, priority, status,
            auto_approved, auto_approval_reason, created_by
        )
        VALUES (
            :catalog_id, :proposal_type, :target_entity_id,
            :payload, :reasoning, :priority, :status,
            :auto_approved, :auto_approval_reason, :created_by
        )
        RETURNING id, proposal_type, status, priority, auto_approved, created_at
    """, {
        "catalog_id": str(catalog_id),
        "proposal_type": payload.proposal_type,
        "target_entity_id": str(payload.target_entity_id) if payload.target_entity_id else None,
        "payload": payload.payload,
        "reasoning": payload.reasoning,
        "priority": payload.priority,
        "status": "approved" if auto_approve else "pending",
        "auto_approved": auto_approve,
        "auto_approval_reason": auto_reason,
        "created_by": user_id
    })

    # If auto-approved and it's a CREATE, create the entity
    if auto_approve and payload.proposal_type == "CREATE":
        await _apply_create_proposal(db, catalog_id, payload.payload, user_id)

    return {
        "proposal": dict(proposal),
        "auto_approved": auto_approve
    }


async def _apply_create_proposal(db, catalog_id: UUID, payload: dict, user_id: str):
    """Apply a CREATE proposal by creating the entity."""
    await db.execute("""
        INSERT INTO rights_entities (
            catalog_id, rights_type, title, entity_key,
            content, ai_permissions, ownership_chain,
            status, created_by
        )
        VALUES (
            :catalog_id, :rights_type, :title, :entity_key,
            :content, :ai_permissions, :ownership_chain,
            'active', :user_id
        )
    """, {
        "catalog_id": str(catalog_id),
        "rights_type": payload.get("rights_type"),
        "title": payload.get("title"),
        "entity_key": payload.get("entity_key"),
        "content": payload.get("content", {}),
        "ai_permissions": payload.get("ai_permissions", {}),
        "ownership_chain": payload.get("ownership_chain", []),
        "user_id": user_id
    })


@router.get("/proposals/{proposal_id}")
async def get_proposal(request: Request, proposal_id: UUID):
    """Get full details of a proposal."""
    user_id = request.state.user_id
    db = await get_db()

    proposal = await db.fetch_one("""
        SELECT p.*, re.title as entity_title, re.rights_type,
               c.name as catalog_name
        FROM proposals p
        JOIN catalogs c ON c.id = p.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        LEFT JOIN rights_entities re ON re.id = p.target_entity_id
        WHERE p.id = :proposal_id AND wm.user_id = :user_id
    """, {"proposal_id": str(proposal_id), "user_id": user_id})

    if not proposal:
        raise HTTPException(status_code=404, detail="Proposal not found")

    # Get comments
    comments = await db.fetch_all("""
        SELECT id, content, comment_type, created_by, created_at
        FROM proposal_comments
        WHERE proposal_id = :proposal_id
        ORDER BY created_at ASC
    """, {"proposal_id": str(proposal_id)})

    return {
        "proposal": dict(proposal),
        "comments": [dict(c) for c in comments]
    }


@router.post("/proposals/{proposal_id}/review")
async def review_proposal(request: Request, proposal_id: UUID, payload: ProposalReview):
    """Approve or reject a proposal (admin only)."""
    user_id = request.state.user_id
    db = await get_db()

    # Get proposal and check admin access
    proposal = await db.fetch_one("""
        SELECT p.id, p.catalog_id, p.proposal_type, p.target_entity_id, p.payload, p.status
        FROM proposals p
        JOIN catalogs c ON c.id = p.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE p.id = :proposal_id AND wm.user_id = :user_id
        AND wm.role IN ('owner', 'admin')
    """, {"proposal_id": str(proposal_id), "user_id": user_id})

    if not proposal:
        raise HTTPException(status_code=404, detail="Proposal not found or insufficient permissions")

    if proposal["status"] != "pending":
        raise HTTPException(status_code=400, detail=f"Proposal is already {proposal['status']}")

    if payload.status not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail="Status must be 'approved' or 'rejected'")

    async with db.transaction():
        # Update proposal
        await db.execute("""
            UPDATE proposals
            SET status = :status,
                reviewed_by = :user_id,
                reviewed_at = now(),
                review_notes = :review_notes,
                updated_at = now()
            WHERE id = :proposal_id
        """, {
            "proposal_id": str(proposal_id),
            "status": payload.status,
            "user_id": user_id,
            "review_notes": payload.review_notes
        })

        # If approved, apply the changes
        if payload.status == "approved":
            await _apply_proposal(db, proposal, user_id)

    return {"status": payload.status, "proposal_id": proposal_id}


async def _apply_proposal(db, proposal: dict, user_id: str):
    """Apply an approved proposal."""
    p_type = proposal["proposal_type"]
    payload = proposal["payload"]
    target_id = proposal["target_entity_id"]
    catalog_id = proposal["catalog_id"]

    if p_type == "CREATE":
        await db.execute("""
            INSERT INTO rights_entities (
                catalog_id, rights_type, title, entity_key,
                content, ai_permissions, ownership_chain,
                status, created_by
            )
            VALUES (
                :catalog_id, :rights_type, :title, :entity_key,
                :content, :ai_permissions, :ownership_chain,
                'active', :user_id
            )
        """, {
            "catalog_id": str(catalog_id),
            "rights_type": payload.get("rights_type"),
            "title": payload.get("title"),
            "entity_key": payload.get("entity_key"),
            "content": payload.get("content", {}),
            "ai_permissions": payload.get("ai_permissions", {}),
            "ownership_chain": payload.get("ownership_chain", []),
            "user_id": user_id
        })

    elif p_type == "UPDATE":
        updates = []
        params = {"entity_id": str(target_id), "user_id": user_id}

        for key in ["title", "content", "ai_permissions", "ownership_chain"]:
            if key in payload:
                updates.append(f"{key} = :{key}")
                params[key] = payload[key]

        if updates:
            updates.append("version = version + 1")
            updates.append("updated_by = :user_id")
            await db.execute(f"""
                UPDATE rights_entities
                SET {', '.join(updates)}, updated_at = now()
                WHERE id = :entity_id
            """, params)

    elif p_type == "ARCHIVE":
        await db.execute("""
            UPDATE rights_entities
            SET status = 'archived', updated_by = :user_id, updated_at = now()
            WHERE id = :entity_id
        """, {"entity_id": str(target_id), "user_id": user_id})

    elif p_type == "RESTORE":
        await db.execute("""
            UPDATE rights_entities
            SET status = 'active', updated_by = :user_id, updated_at = now()
            WHERE id = :entity_id
        """, {"entity_id": str(target_id), "user_id": user_id})


@router.post("/proposals/{proposal_id}/comments")
async def add_comment(request: Request, proposal_id: UUID, payload: ProposalComment):
    """Add a comment to a proposal."""
    user_id = request.state.user_id
    db = await get_db()

    # Check access
    proposal = await db.fetch_one("""
        SELECT p.id
        FROM proposals p
        JOIN catalogs c ON c.id = p.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE p.id = :proposal_id AND wm.user_id = :user_id
    """, {"proposal_id": str(proposal_id), "user_id": user_id})

    if not proposal:
        raise HTTPException(status_code=404, detail="Proposal not found")

    comment = await db.fetch_one("""
        INSERT INTO proposal_comments (proposal_id, content, comment_type, created_by)
        VALUES (:proposal_id, :content, :comment_type, :user_id)
        RETURNING id, content, comment_type, created_at
    """, {
        "proposal_id": str(proposal_id),
        "content": payload.content,
        "comment_type": payload.comment_type,
        "user_id": user_id
    })

    return {"comment": dict(comment)}


@router.post("/proposals/{proposal_id}/cancel")
async def cancel_proposal(request: Request, proposal_id: UUID):
    """Cancel a pending proposal (creator only)."""
    user_id = request.state.user_id
    db = await get_db()

    result = await db.execute("""
        UPDATE proposals
        SET status = 'cancelled', updated_at = now()
        WHERE id = :proposal_id
        AND created_by = :user_id
        AND status = 'pending'
    """, {"proposal_id": str(proposal_id), "user_id": user_id})

    if result == 0:
        raise HTTPException(
            status_code=404,
            detail="Proposal not found, not owned by you, or not in pending status"
        )

    return {"status": "cancelled", "proposal_id": proposal_id}
