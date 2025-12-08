"""Catalog management endpoints."""
from typing import Optional
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


class CatalogCreate(BaseModel):
    name: str
    description: Optional[str] = None


class CatalogUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


@router.get("/workspaces/{workspace_id}/catalogs")
async def list_catalogs(request: Request, workspace_id: UUID):
    """List catalogs in a workspace."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    catalogs = await db.fetch_all("""
        SELECT c.id, c.name, c.description, c.created_at, c.updated_at,
               COUNT(re.id) as entity_count
        FROM catalogs c
        LEFT JOIN rights_entities re ON re.catalog_id = c.id AND re.status = 'active'
        WHERE c.workspace_id = :workspace_id
        GROUP BY c.id
        ORDER BY c.created_at DESC
    """, {"workspace_id": str(workspace_id)})

    return {"catalogs": [dict(c) for c in catalogs]}


@router.post("/workspaces/{workspace_id}/catalogs")
async def create_catalog(request: Request, workspace_id: UUID, payload: CatalogCreate):
    """Create a new catalog in a workspace."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    catalog = await db.fetch_one("""
        INSERT INTO catalogs (workspace_id, name, description, created_by)
        VALUES (:workspace_id, :name, :description, :user_id)
        RETURNING id, name, description, created_at
    """, {
        "workspace_id": str(workspace_id),
        "name": payload.name,
        "description": payload.description,
        "user_id": user_id
    })

    return {"catalog": dict(catalog)}


@router.get("/catalogs/{catalog_id}")
async def get_catalog(request: Request, catalog_id: UUID):
    """Get catalog details."""
    user_id = request.state.user_id
    db = await get_db()

    catalog = await db.fetch_one("""
        SELECT c.id, c.workspace_id, c.name, c.description, c.created_at, c.updated_at
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    # Get entity counts by type
    type_counts = await db.fetch_all("""
        SELECT rights_type, COUNT(*) as count
        FROM rights_entities
        WHERE catalog_id = :catalog_id AND status = 'active'
        GROUP BY rights_type
    """, {"catalog_id": str(catalog_id)})

    return {
        "catalog": dict(catalog),
        "entity_counts": {r["rights_type"]: r["count"] for r in type_counts}
    }


@router.patch("/catalogs/{catalog_id}")
async def update_catalog(request: Request, catalog_id: UUID, payload: CatalogUpdate):
    """Update catalog details."""
    user_id = request.state.user_id
    db = await get_db()

    # Check admin access via workspace
    catalog = await db.fetch_one("""
        SELECT c.id, wm.role
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    if catalog["role"] not in ("owner", "admin"):
        raise HTTPException(status_code=403, detail="Admin access required")

    updates = []
    params = {"catalog_id": str(catalog_id)}

    if payload.name is not None:
        updates.append("name = :name")
        params["name"] = payload.name
    if payload.description is not None:
        updates.append("description = :description")
        params["description"] = payload.description

    if updates:
        await db.execute(f"""
            UPDATE catalogs SET {', '.join(updates)}, updated_at = now()
            WHERE id = :catalog_id
        """, params)

    return await get_catalog(request, catalog_id)
