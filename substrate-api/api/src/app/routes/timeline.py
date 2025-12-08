"""Timeline/audit trail endpoints."""
from typing import Optional, List
from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, HTTPException, Request, Query
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


@router.get("/workspaces/{workspace_id}/timeline")
async def list_workspace_timeline(
    request: Request,
    workspace_id: UUID,
    event_type: Optional[str] = None,
    entity_type: Optional[str] = None,
    actor_type: Optional[str] = None,
    since: Optional[datetime] = None,
    until: Optional[datetime] = None,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List timeline events for a workspace."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    # Build query
    where_clauses = ["workspace_id = :workspace_id"]
    params = {
        "workspace_id": str(workspace_id),
        "limit": limit,
        "offset": offset
    }

    if event_type:
        where_clauses.append("event_type = :event_type")
        params["event_type"] = event_type

    if entity_type:
        where_clauses.append("entity_type = :entity_type")
        params["entity_type"] = entity_type

    if actor_type:
        where_clauses.append("actor_type = :actor_type")
        params["actor_type"] = actor_type

    if since:
        where_clauses.append("created_at >= :since")
        params["since"] = since

    if until:
        where_clauses.append("created_at <= :until")
        params["until"] = until

    events = await db.fetch_all(f"""
        SELECT id, event_type, entity_type, entity_id, summary,
               actor_type, actor_id, created_at
        FROM timeline_events
        WHERE {' AND '.join(where_clauses)}
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    return {
        "events": [dict(e) for e in events],
        "limit": limit,
        "offset": offset
    }


@router.get("/catalogs/{catalog_id}/timeline")
async def list_catalog_timeline(
    request: Request,
    catalog_id: UUID,
    event_type: Optional[str] = None,
    entity_type: Optional[str] = None,
    since: Optional[datetime] = None,
    until: Optional[datetime] = None,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List timeline events for a catalog."""
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
    params = {
        "catalog_id": str(catalog_id),
        "limit": limit,
        "offset": offset
    }

    if event_type:
        where_clauses.append("event_type = :event_type")
        params["event_type"] = event_type

    if entity_type:
        where_clauses.append("entity_type = :entity_type")
        params["entity_type"] = entity_type

    if since:
        where_clauses.append("created_at >= :since")
        params["since"] = since

    if until:
        where_clauses.append("created_at <= :until")
        params["until"] = until

    events = await db.fetch_all(f"""
        SELECT id, event_type, entity_type, entity_id, summary,
               actor_type, actor_id, created_at
        FROM timeline_events
        WHERE {' AND '.join(where_clauses)}
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    return {
        "events": [dict(e) for e in events],
        "limit": limit,
        "offset": offset
    }


@router.get("/entities/{entity_id}/timeline")
async def list_entity_timeline(
    request: Request,
    entity_id: UUID,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List timeline events for a specific rights entity."""
    user_id = request.state.user_id
    db = await get_db()

    # Check entity access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    events = await db.fetch_all("""
        SELECT id, event_type, entity_type, entity_id, summary,
               payload, actor_type, actor_id, created_at
        FROM timeline_events
        WHERE entity_id = :entity_id AND entity_type = 'rights_entity'
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    """, {"entity_id": str(entity_id), "limit": limit, "offset": offset})

    return {
        "events": [dict(e) for e in events],
        "limit": limit,
        "offset": offset
    }


@router.get("/timeline/{event_id}")
async def get_timeline_event(request: Request, event_id: int):
    """Get full details of a timeline event."""
    user_id = request.state.user_id
    db = await get_db()

    event = await db.fetch_one("""
        SELECT te.*
        FROM timeline_events te
        JOIN workspace_memberships wm ON wm.workspace_id = te.workspace_id
        WHERE te.id = :event_id AND wm.user_id = :user_id
    """, {"event_id": event_id, "user_id": user_id})

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    return {"event": dict(event)}


@router.get("/timeline/stats")
async def get_timeline_stats(
    request: Request,
    workspace_id: UUID,
    days: int = Query(30, le=90)
):
    """Get timeline statistics for a workspace."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    # Get event counts by type
    event_counts = await db.fetch_all("""
        SELECT event_type, COUNT(*) as count
        FROM timeline_events
        WHERE workspace_id = :workspace_id
        AND created_at >= now() - make_interval(days => :days)
        GROUP BY event_type
        ORDER BY count DESC
    """, {"workspace_id": str(workspace_id), "days": days})

    # Get daily activity
    daily_activity = await db.fetch_all("""
        SELECT DATE(created_at) as date, COUNT(*) as count
        FROM timeline_events
        WHERE workspace_id = :workspace_id
        AND created_at >= now() - make_interval(days => :days)
        GROUP BY DATE(created_at)
        ORDER BY date DESC
    """, {"workspace_id": str(workspace_id), "days": days})

    # Get top actors
    top_actors = await db.fetch_all("""
        SELECT actor_id, actor_type, COUNT(*) as count
        FROM timeline_events
        WHERE workspace_id = :workspace_id
        AND created_at >= now() - make_interval(days => :days)
        AND actor_id IS NOT NULL
        GROUP BY actor_id, actor_type
        ORDER BY count DESC
        LIMIT 10
    """, {"workspace_id": str(workspace_id), "days": days})

    return {
        "period_days": days,
        "event_counts": [dict(e) for e in event_counts],
        "daily_activity": [dict(d) for d in daily_activity],
        "top_actors": [dict(a) for a in top_actors]
    }


# =============================================================================
# EVENT TYPE CONSTANTS (for reference)
# =============================================================================
# Rights: 'rights_entity_created', 'rights_entity_updated', 'rights_entity_archived'
# Governance: 'proposal_created', 'proposal_approved', 'proposal_rejected'
# Licensing: 'license_granted', 'license_terminated', 'usage_reported'
# System: 'catalog_created', 'workspace_created', 'user_joined'
