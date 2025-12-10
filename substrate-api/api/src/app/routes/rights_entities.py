"""Rights entity management endpoints."""
from typing import Optional, Dict, Any, List
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Query
from pydantic import BaseModel, Field

from app.deps import get_db

router = APIRouter()


# =============================================================================
# Pydantic Models
# =============================================================================

class SemanticMetadata(BaseModel):
    """Hybrid semantic metadata schema."""
    primary_tags: List[str] = Field(default_factory=list)
    mood: List[str] = Field(default_factory=list)
    energy: Optional[float] = Field(None, ge=0.0, le=1.0)
    language: Optional[str] = None
    explicit_content: bool = False
    type_fields: Dict[str, Any] = Field(default_factory=dict)
    custom_tags: List[Dict[str, str]] = Field(default_factory=list)
    ai_analysis: Optional[Dict[str, Any]] = None


class AIPermissions(BaseModel):
    """AI permissions model - Phase 1 simplified."""
    training: Dict[str, Any] = Field(default_factory=lambda: {
        "allowed": False,
        "commercial_ok": False,
        "requires_attribution": True
    })
    generation: Dict[str, Any] = Field(default_factory=lambda: {
        "allowed": False,
        "derivative_works": False,
        "style_imitation": False,
        "direct_sampling": False,
        "watermark_required": True
    })
    voice: Optional[Dict[str, Any]] = None
    commercial: Dict[str, Any] = Field(default_factory=lambda: {
        "commercial_use_allowed": False,
        "territories": ["WORLDWIDE"],
        "revenue_share_required": False
    })
    extensions: Optional[Dict[str, Any]] = None


class RightsEntityCreate(BaseModel):
    rights_type: str  # e.g., 'musical_work', 'sound_recording', 'voice_likeness'
    title: str
    entity_key: Optional[str] = None
    content: Optional[Dict[str, Any]] = None
    ai_permissions: Optional[Dict[str, Any]] = None
    ownership_chain: Optional[List[Dict[str, Any]]] = None
    semantic_metadata: Optional[Dict[str, Any]] = None


class RightsEntityUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[Dict[str, Any]] = None
    ai_permissions: Optional[Dict[str, Any]] = None
    ownership_chain: Optional[List[Dict[str, Any]]] = None
    semantic_metadata: Optional[Dict[str, Any]] = None


@router.get("/rights-schemas")
async def list_rights_schemas(request: Request):
    """List available IP type schemas."""
    db = await get_db()

    schemas = await db.fetch_all("""
        SELECT id, display_name, description, category,
               field_schema, ai_permission_fields, identifier_fields, display_field
        FROM rights_schemas
        ORDER BY category, display_name
    """)

    return {"schemas": [dict(s) for s in schemas]}


@router.get("/rights-schemas/{schema_id}")
async def get_rights_schema(schema_id: str):
    """Get a specific IP type schema."""
    db = await get_db()

    schema = await db.fetch_one("""
        SELECT id, display_name, description, category,
               field_schema, ai_permission_fields, identifier_fields, display_field
        FROM rights_schemas
        WHERE id = :schema_id
    """, {"schema_id": schema_id})

    if not schema:
        raise HTTPException(status_code=404, detail="Schema not found")

    return {"schema": dict(schema)}


@router.get("/catalogs/{catalog_id}/entities")
async def list_rights_entities(
    request: Request,
    catalog_id: UUID,
    rights_type: Optional[str] = None,
    status: str = Query("active", enum=["active", "draft", "archived", "all"]),
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List rights entities in a catalog."""
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

    if rights_type:
        where_clauses.append("rights_type = :rights_type")
        params["rights_type"] = rights_type

    entities = await db.fetch_all(f"""
        SELECT id, rights_type, title, entity_key, status, version,
               embedding_status, verification_status,
               created_at, updated_at
        FROM rights_entities
        WHERE {' AND '.join(where_clauses)}
        ORDER BY updated_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    # Get total count
    count_result = await db.fetch_one(f"""
        SELECT COUNT(*) as total
        FROM rights_entities
        WHERE {' AND '.join(where_clauses[:-1] if status == "all" else where_clauses)}
    """, {k: v for k, v in params.items() if k not in ("limit", "offset")})

    return {
        "entities": [dict(e) for e in entities],
        "total": count_result["total"],
        "limit": limit,
        "offset": offset
    }


@router.post("/catalogs/{catalog_id}/entities")
async def create_rights_entity(request: Request, catalog_id: UUID, payload: RightsEntityCreate):
    """Create a new rights entity (creates pending proposal if governance requires it)."""
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

    # Validate rights_type exists
    schema = await db.fetch_one("""
        SELECT id FROM rights_schemas WHERE id = :rights_type
    """, {"rights_type": payload.rights_type})

    if not schema:
        raise HTTPException(status_code=400, detail=f"Invalid rights_type: {payload.rights_type}")

    # Check governance rules for auto-approval
    # governance_rules uses workspace_id and conditions JSONB with action TEXT
    governance = await db.fetch_one("""
        SELECT gr.conditions, gr.action
        FROM governance_rules gr
        WHERE gr.workspace_id = :workspace_id
        AND gr.is_active = true
        AND gr.conditions->>'proposal_type' = 'CREATE'
        ORDER BY gr.priority DESC
        LIMIT 1
    """, {"workspace_id": str(catalog["workspace_id"])})

    auto_approve = False
    if governance and governance["action"] == "auto_approve":
        auto_approve = True

    async with db.transaction():
        # Create entity (as draft if requires approval)
        entity = await db.fetch_one("""
            INSERT INTO rights_entities (
                catalog_id, rights_type, title, entity_key,
                content, ai_permissions, ownership_chain,
                status, created_by
            )
            VALUES (
                :catalog_id, :rights_type, :title, :entity_key,
                :content, :ai_permissions, :ownership_chain,
                :status, :created_by
            )
            RETURNING id, rights_type, title, entity_key, status, version, created_at
        """, {
            "catalog_id": str(catalog_id),
            "rights_type": payload.rights_type,
            "title": payload.title,
            "entity_key": payload.entity_key,
            "content": payload.content or {},
            "ai_permissions": payload.ai_permissions or {},
            "ownership_chain": payload.ownership_chain or [],
            "status": "active" if auto_approve else "pending",
            "created_by": f"user:{user_id}"
        })

        # Create proposal if not auto-approved
        if not auto_approve:
            await db.execute("""
                INSERT INTO proposals (
                    catalog_id, proposal_type, target_entity_id,
                    payload, reasoning, priority, status, created_by
                )
                VALUES (
                    :catalog_id, 'CREATE', :entity_id,
                    :payload, :reasoning, 'normal', 'pending', :created_by
                )
            """, {
                "catalog_id": str(catalog_id),
                "entity_id": str(entity["id"]),
                "payload": {
                    "title": payload.title,
                    "rights_type": payload.rights_type,
                    "content": payload.content,
                    "ai_permissions": payload.ai_permissions
                },
                "reasoning": f"Create new {payload.rights_type} entity: {payload.title}",
                "created_by": f"user:{user_id}"
            })

    return {
        "entity": dict(entity),
        "requires_approval": not auto_approve
    }


@router.get("/entities/{entity_id}")
async def get_rights_entity(request: Request, entity_id: UUID):
    """Get full details of a rights entity."""
    user_id = request.state.user_id
    db = await get_db()

    entity = await db.fetch_one("""
        SELECT re.*, rs.display_name as type_display_name, rs.category
        FROM rights_entities re
        JOIN rights_schemas rs ON rs.id = re.rights_type
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    return {"entity": dict(entity)}


@router.patch("/entities/{entity_id}")
async def update_rights_entity(request: Request, entity_id: UUID, payload: RightsEntityUpdate):
    """Update a rights entity (creates proposal if governance requires it)."""
    user_id = request.state.user_id
    db = await get_db()

    # Get entity and check access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id, re.title, re.content, re.ai_permissions, re.ownership_chain
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Check governance for auto-approval
    # Need to get workspace_id from catalog first
    catalog = await db.fetch_one("""
        SELECT workspace_id FROM catalogs WHERE id = :catalog_id
    """, {"catalog_id": str(entity["catalog_id"])})

    governance = await db.fetch_one("""
        SELECT gr.conditions, gr.action
        FROM governance_rules gr
        WHERE gr.workspace_id = :workspace_id
        AND gr.is_active = true
        AND gr.conditions->>'proposal_type' = 'UPDATE'
        ORDER BY gr.priority DESC
        LIMIT 1
    """, {"workspace_id": str(catalog["workspace_id"])}) if catalog else None

    auto_approve = False
    if governance and governance["action"] == "auto_approve":
        auto_approve = True

    # Build proposed changes
    proposed_changes = {}
    if payload.title is not None:
        proposed_changes["title"] = payload.title
    if payload.content is not None:
        proposed_changes["content"] = payload.content
    if payload.ai_permissions is not None:
        proposed_changes["ai_permissions"] = payload.ai_permissions
    if payload.ownership_chain is not None:
        proposed_changes["ownership_chain"] = payload.ownership_chain
    if payload.semantic_metadata is not None:
        proposed_changes["semantic_metadata"] = payload.semantic_metadata

    if not proposed_changes:
        raise HTTPException(status_code=400, detail="No changes provided")

    if auto_approve:
        # Apply directly
        updates = []
        params = {"entity_id": str(entity_id), "user_id": user_id}

        for key, value in proposed_changes.items():
            updates.append(f"{key} = :{key}")
            params[key] = value

        updates.append("version = version + 1")
        updates.append("updated_by = :user_id")

        await db.execute(f"""
            UPDATE rights_entities
            SET {', '.join(updates)}, updated_at = now()
            WHERE id = :entity_id
        """, params)

        return {"updated": True, "requires_approval": False}
    else:
        # Create proposal
        await db.execute("""
            INSERT INTO proposals (
                catalog_id, proposal_type, target_entity_id,
                payload, reasoning, priority, status, created_by
            )
            VALUES (
                :catalog_id, 'UPDATE', :entity_id,
                :payload, :reasoning, 'normal', 'pending', :created_by
            )
        """, {
            "catalog_id": str(entity["catalog_id"]),
            "entity_id": str(entity_id),
            "payload": proposed_changes,
            "reasoning": f"Update entity fields: {', '.join(proposed_changes.keys())}",
            "created_by": f"user:{user_id}"
        })

        return {"updated": False, "requires_approval": True}


@router.get("/entities/{entity_id}/processing-status")
async def get_entity_processing_status(request: Request, entity_id: UUID):
    """Get processing/embedding status for a rights entity."""
    user_id = request.state.user_id
    db = await get_db()

    entity = await db.fetch_one("""
        SELECT re.id, re.title, re.status
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Note: processing_jobs and entity_embeddings tables may not exist yet
    # Return basic status for now
    return {
        "entity_id": entity["id"],
        "title": entity["title"],
        "status": entity["status"],
        "embedding_status": "not_implemented",
        "processing_error": None,
        "embedding_count": 0,
        "recent_jobs": []
    }


@router.post("/entities/{entity_id}/process")
async def trigger_entity_processing(
    request: Request,
    entity_id: UUID,
    force: bool = False
):
    """Trigger embedding generation for a rights entity.

    Note: Processing/embedding functionality is not yet implemented.
    This endpoint is a placeholder for future AI processing features.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify entity access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id, re.title, re.status
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Processing not yet implemented
    raise HTTPException(
        status_code=501,
        detail="Processing/embedding functionality is not yet implemented"
    )
