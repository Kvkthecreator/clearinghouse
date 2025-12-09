"""Processing jobs management endpoints."""
from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Query
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


# =============================================================================
# Pydantic Models
# =============================================================================

class JobCreate(BaseModel):
    """Create a processing job."""
    job_type: str
    rights_entity_id: Optional[UUID] = None
    asset_id: Optional[UUID] = None
    priority: int = 0
    config: dict = {}


class JobUpdate(BaseModel):
    """Update job (for internal/worker use)."""
    status: Optional[str] = None
    error_message: Optional[str] = None
    result: Optional[dict] = None


VALID_JOB_TYPES = [
    'embedding_generation', 'asset_analysis', 'metadata_extraction',
    'fingerprint_generation', 'batch_import'
]

VALID_JOB_STATUSES = ['queued', 'processing', 'completed', 'failed', 'cancelled']


# =============================================================================
# Job Routes
# =============================================================================

@router.get("/jobs")
async def list_jobs(
    request: Request,
    status: Optional[str] = Query(None, enum=VALID_JOB_STATUSES),
    job_type: Optional[str] = None,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List processing jobs (filtered by accessible entities)."""
    user_id = request.state.user_id
    db = await get_db()

    # Build query - only show jobs for entities the user can access
    where_clauses = ["""
        (pj.rights_entity_id IS NULL OR EXISTS (
            SELECT 1 FROM rights_entities re
            JOIN catalogs c ON c.id = re.catalog_id
            JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
            WHERE re.id = pj.rights_entity_id AND wm.user_id = :user_id
        ))
    """]
    params = {"user_id": user_id, "limit": limit, "offset": offset}

    if status:
        where_clauses.append("pj.status = :status")
        params["status"] = status

    if job_type:
        if job_type not in VALID_JOB_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid job_type. Must be one of: {VALID_JOB_TYPES}"
            )
        where_clauses.append("pj.job_type = :job_type")
        params["job_type"] = job_type

    jobs = await db.fetch_all(f"""
        SELECT pj.id, pj.job_type, pj.rights_entity_id, pj.asset_id,
               pj.status, pj.priority, pj.started_at, pj.completed_at,
               pj.error_message, pj.retry_count, pj.created_at,
               re.title as entity_title
        FROM processing_jobs pj
        LEFT JOIN rights_entities re ON re.id = pj.rights_entity_id
        WHERE {' AND '.join(where_clauses)}
        ORDER BY pj.priority DESC, pj.created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    # Get count
    count_params = {k: v for k, v in params.items() if k not in ("limit", "offset")}
    count_result = await db.fetch_one(f"""
        SELECT COUNT(*) as total
        FROM processing_jobs pj
        WHERE {' AND '.join(where_clauses)}
    """, count_params)

    return {
        "jobs": [dict(j) for j in jobs],
        "total": count_result["total"],
        "limit": limit,
        "offset": offset
    }


@router.get("/jobs/{job_id}")
async def get_job(request: Request, job_id: UUID):
    """Get job details."""
    user_id = request.state.user_id
    db = await get_db()

    job = await db.fetch_one("""
        SELECT pj.*, re.title as entity_title
        FROM processing_jobs pj
        LEFT JOIN rights_entities re ON re.id = pj.rights_entity_id
        LEFT JOIN catalogs c ON c.id = re.catalog_id
        LEFT JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE pj.id = :job_id
        AND (pj.rights_entity_id IS NULL OR wm.user_id = :user_id)
    """, {"job_id": str(job_id), "user_id": user_id})

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    return {"job": dict(job)}


@router.post("/jobs")
async def create_job(request: Request, payload: JobCreate):
    """Create a new processing job."""
    user_id = request.state.user_id
    db = await get_db()

    # Validate job type
    if payload.job_type not in VALID_JOB_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid job_type. Must be one of: {VALID_JOB_TYPES}"
        )

    # If entity_id provided, verify access
    if payload.rights_entity_id:
        entity = await db.fetch_one("""
            SELECT re.id
            FROM rights_entities re
            JOIN catalogs c ON c.id = re.catalog_id
            JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
            WHERE re.id = :entity_id AND wm.user_id = :user_id
        """, {"entity_id": str(payload.rights_entity_id), "user_id": user_id})

        if not entity:
            raise HTTPException(status_code=404, detail="Entity not found")

    # If asset_id provided, verify access
    if payload.asset_id:
        asset = await db.fetch_one("""
            SELECT ra.id
            FROM reference_assets ra
            JOIN rights_entities re ON re.id = ra.rights_entity_id
            JOIN catalogs c ON c.id = re.catalog_id
            JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
            WHERE ra.id = :asset_id AND wm.user_id = :user_id
        """, {"asset_id": str(payload.asset_id), "user_id": user_id})

        if not asset:
            raise HTTPException(status_code=404, detail="Asset not found")

    job = await db.fetch_one("""
        INSERT INTO processing_jobs (
            job_type, rights_entity_id, asset_id,
            status, priority, config, created_by
        )
        VALUES (
            :job_type, :entity_id, :asset_id,
            'queued', :priority, :config, :user_id
        )
        RETURNING id, job_type, status, priority, created_at
    """, {
        "job_type": payload.job_type,
        "entity_id": str(payload.rights_entity_id) if payload.rights_entity_id else None,
        "asset_id": str(payload.asset_id) if payload.asset_id else None,
        "priority": payload.priority,
        "config": payload.config,
        "user_id": user_id
    })

    return {"job": dict(job)}


@router.post("/jobs/{job_id}/cancel")
async def cancel_job(request: Request, job_id: UUID):
    """Cancel a queued or processing job."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify job exists and user has access
    job = await db.fetch_one("""
        SELECT pj.id, pj.status
        FROM processing_jobs pj
        LEFT JOIN rights_entities re ON re.id = pj.rights_entity_id
        LEFT JOIN catalogs c ON c.id = re.catalog_id
        LEFT JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE pj.id = :job_id
        AND (pj.rights_entity_id IS NULL OR wm.user_id = :user_id)
    """, {"job_id": str(job_id), "user_id": user_id})

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job["status"] not in ("queued", "processing"):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel job with status '{job['status']}'"
        )

    await db.execute("""
        UPDATE processing_jobs
        SET status = 'cancelled', updated_at = now()
        WHERE id = :job_id
    """, {"job_id": str(job_id)})

    return {"cancelled": True, "job_id": job_id}


@router.post("/jobs/{job_id}/retry")
async def retry_job(request: Request, job_id: UUID):
    """Retry a failed job."""
    user_id = request.state.user_id
    db = await get_db()

    job = await db.fetch_one("""
        SELECT pj.id, pj.status, pj.retry_count, pj.max_retries
        FROM processing_jobs pj
        LEFT JOIN rights_entities re ON re.id = pj.rights_entity_id
        LEFT JOIN catalogs c ON c.id = re.catalog_id
        LEFT JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE pj.id = :job_id
        AND (pj.rights_entity_id IS NULL OR wm.user_id = :user_id)
    """, {"job_id": str(job_id), "user_id": user_id})

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job["status"] != "failed":
        raise HTTPException(
            status_code=400,
            detail=f"Can only retry failed jobs. Current status: '{job['status']}'"
        )

    await db.execute("""
        UPDATE processing_jobs
        SET status = 'queued',
            error_message = NULL,
            retry_count = retry_count + 1,
            updated_at = now()
        WHERE id = :job_id
    """, {"job_id": str(job_id)})

    return {"retried": True, "job_id": job_id}


# =============================================================================
# Internal/Worker Routes (for background processing)
# =============================================================================

@router.get("/internal/jobs/next")
async def get_next_job(
    request: Request,
    job_types: Optional[List[str]] = Query(None)
):
    """
    Get the next queued job for processing.
    Used by background workers. Returns the highest priority queued job.
    """
    db = await get_db()

    where_clauses = ["status = 'queued'"]
    params = {}

    if job_types:
        for jt in job_types:
            if jt not in VALID_JOB_TYPES:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid job_type: {jt}"
                )
        where_clauses.append("job_type = ANY(:job_types)")
        params["job_types"] = job_types

    # Atomic claim: update and return in one query
    job = await db.fetch_one(f"""
        UPDATE processing_jobs
        SET status = 'processing',
            started_at = now(),
            updated_at = now()
        WHERE id = (
            SELECT id FROM processing_jobs
            WHERE {' AND '.join(where_clauses)}
            ORDER BY priority DESC, created_at ASC
            LIMIT 1
            FOR UPDATE SKIP LOCKED
        )
        RETURNING id, job_type, rights_entity_id, asset_id, config
    """, params)

    if not job:
        return {"job": None, "message": "No jobs available"}

    return {"job": dict(job)}


@router.patch("/internal/jobs/{job_id}")
async def update_job_internal(request: Request, job_id: UUID, payload: JobUpdate):
    """
    Update job status (for background workers).
    """
    db = await get_db()

    updates = ["updated_at = now()"]
    params = {"job_id": str(job_id)}

    if payload.status:
        if payload.status not in VALID_JOB_STATUSES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status. Must be one of: {VALID_JOB_STATUSES}"
            )
        updates.append("status = :status")
        params["status"] = payload.status

        if payload.status == "completed":
            updates.append("completed_at = now()")
        elif payload.status == "failed":
            updates.append("completed_at = now()")

    if payload.error_message is not None:
        updates.append("error_message = :error_message")
        params["error_message"] = payload.error_message

    if payload.result is not None:
        updates.append("result = :result")
        params["result"] = payload.result

    result = await db.execute(f"""
        UPDATE processing_jobs
        SET {', '.join(updates)}
        WHERE id = :job_id
    """, params)

    if result == 0:
        raise HTTPException(status_code=404, detail="Job not found")

    return {"updated": True, "job_id": job_id}
