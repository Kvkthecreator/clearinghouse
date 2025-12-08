"""Workspace management endpoints."""
from typing import Optional
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


class WorkspaceCreate(BaseModel):
    name: str
    description: Optional[str] = None


class WorkspaceUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


@router.get("/workspaces")
async def list_workspaces(request: Request):
    """List workspaces the current user has access to."""
    user_id = request.state.user_id
    db = await get_db()

    workspaces = await db.fetch_all("""
        SELECT w.id, w.name, w.description, w.created_at, wm.role
        FROM workspaces w
        JOIN workspace_memberships wm ON wm.workspace_id = w.id
        WHERE wm.user_id = :user_id
        ORDER BY w.created_at DESC
    """, {"user_id": user_id})

    return {"workspaces": [dict(w) for w in workspaces]}


@router.post("/workspaces")
async def create_workspace(request: Request, payload: WorkspaceCreate):
    """Create a new workspace."""
    user_id = request.state.user_id
    db = await get_db()

    async with db.transaction():
        # Create workspace
        workspace = await db.fetch_one("""
            INSERT INTO workspaces (name, description, created_by)
            VALUES (:name, :description, :user_id)
            RETURNING id, name, description, created_at
        """, {"name": payload.name, "description": payload.description, "user_id": user_id})

        # Add creator as owner
        await db.execute("""
            INSERT INTO workspace_memberships (workspace_id, user_id, role)
            VALUES (:workspace_id, :user_id, 'owner')
        """, {"workspace_id": workspace["id"], "user_id": user_id})

    return {"workspace": dict(workspace)}


@router.get("/workspaces/{workspace_id}")
async def get_workspace(request: Request, workspace_id: UUID):
    """Get workspace details."""
    user_id = request.state.user_id
    db = await get_db()

    workspace = await db.fetch_one("""
        SELECT w.id, w.name, w.description, w.created_at, wm.role
        FROM workspaces w
        JOIN workspace_memberships wm ON wm.workspace_id = w.id
        WHERE w.id = :workspace_id AND wm.user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not workspace:
        raise HTTPException(status_code=404, detail="Workspace not found")

    return {"workspace": dict(workspace)}


@router.patch("/workspaces/{workspace_id}")
async def update_workspace(request: Request, workspace_id: UUID, payload: WorkspaceUpdate):
    """Update workspace details."""
    user_id = request.state.user_id
    db = await get_db()

    # Check admin access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership or membership["role"] not in ("owner", "admin"):
        raise HTTPException(status_code=403, detail="Admin access required")

    updates = []
    params = {"workspace_id": str(workspace_id)}

    if payload.name is not None:
        updates.append("name = :name")
        params["name"] = payload.name
    if payload.description is not None:
        updates.append("description = :description")
        params["description"] = payload.description

    if updates:
        await db.execute(f"""
            UPDATE workspaces SET {', '.join(updates)}, updated_at = now()
            WHERE id = :workspace_id
        """, params)

    return await get_workspace(request, workspace_id)


@router.get("/workspaces/{workspace_id}/members")
async def list_workspace_members(request: Request, workspace_id: UUID):
    """List workspace members."""
    user_id = request.state.user_id
    db = await get_db()

    # Check access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    members = await db.fetch_all("""
        SELECT user_id, role, created_at
        FROM workspace_memberships
        WHERE workspace_id = :workspace_id
        ORDER BY created_at
    """, {"workspace_id": str(workspace_id)})

    return {"members": [dict(m) for m in members]}
