"""Processing jobs management endpoints."""
from typing import Optional
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
    status: Optional[str] = None,
    job_type: Optional[str] = None,
    entity_id: Optional[UUID] = None,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List processing jobs accessible to the user."""
    user_id = request.state.user_id
    db = await get_db()

    # Build query - only show jobs for entities/assets user has access to
    where_clauses = ["""
        EXISTS (
            SELECT 1 FROM rights_entities re
            JOIN catalogs c ON c.id = re.catalog_id
            JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
            WHERE re.id = pj.rights_entity_id AND wm.user_id = :user_id
        )
    """]
    params = {"user_id": user_id, "limit": limit, "offset": offset}

    if status:
        if status not in VALID_JOB_STATUSES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status. Must be one of: {VALID_JOB_STATUSES}"
            )
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

    if entity_id:
        where_clauses.append("pj.rights_entity_id = :entity_id")
        params["entity_id"] = str(entity_id)

    jobs = await db.fetch_all(f"""
        SELECT pj.id, pj.job_type, pj.rights_entity_id, pj.asset_id,
               pj.status, pj.priority, pj.started_at, pj.completed_at,
               pj.error_message, pj.retry_count, pj.max_retries,
               pj.config, pj.result, pj.created_at, pj.updated_at,
               re.title as entity_title, re.rights_type
        FROM processing_jobs pj
        LEFT JOIN rights_entities re ON re.id = pj.rights_entity_id
        WHERE {' AND '.join(where_clauses)}
        ORDER BY
            CASE pj.status
                WHEN 'processing' THEN 1
                WHEN 'queued' THEN 2
                WHEN 'failed' THEN 3
                ELSE 4
            END,
            pj.priority DESC,
            pj.created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    # Get total count
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


@router.get("/entities/{entity_id}/jobs")
async def list_entity_jobs(
    request: Request,
    entity_id: UUID,
    status: Optional[str] = None,
    limit: int = Query(20, le=100),
    offset: int = 0
):
    """List all processing jobs for a specific entity."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify entity access
    entity = await db.fetch_one("""
        SELECT re.id
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Build query
    where_clauses = ["rights_entity_id = :entity_id"]
    params = {"entity_id": str(entity_id), "limit": limit, "offset": offset}

    if status:
        where_clauses.append("status = :status")
        params["status"] = status

    jobs = await db.fetch_all(f"""
        SELECT id, job_type, asset_id, status, priority,
               started_at, completed_at, error_message,
               retry_count, max_retries, config, result,
               created_at, updated_at
        FROM processing_jobs
        WHERE {' AND '.join(where_clauses)}
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    return {"jobs": [dict(j) for j in jobs]}


@router.get("/jobs/{job_id}")
async def get_job(request: Request, job_id: UUID):
    """Get job details."""
    user_id = request.state.user_id
    db = await get_db()

    job = await db.fetch_one("""
        SELECT pj.*, re.title as entity_title, re.rights_type,
               ra.filename as asset_filename, ra.asset_type
        FROM processing_jobs pj
        LEFT JOIN rights_entities re ON re.id = pj.rights_entity_id
        LEFT JOIN reference_assets ra ON ra.id = pj.asset_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE pj.id = :job_id AND wm.user_id = :user_id
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

    # Must have either entity_id or asset_id
    if not payload.rights_entity_id and not payload.asset_id:
        raise HTTPException(
            status_code=400,
            detail="Either rights_entity_id or asset_id is required"
        )

    # Verify access
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

    if payload.asset_id:
        asset = await db.fetch_one("""
            SELECT ra.id, ra.rights_entity_id
            FROM reference_assets ra
            JOIN rights_entities re ON re.id = ra.rights_entity_id
            JOIN catalogs c ON c.id = re.catalog_id
            JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
            WHERE ra.id = :asset_id AND wm.user_id = :user_id
        """, {"asset_id": str(payload.asset_id), "user_id": user_id})

        if not asset:
            raise HTTPException(status_code=404, detail="Asset not found")

        # Use asset's entity_id if not provided
        if not payload.rights_entity_id:
            payload.rights_entity_id = UUID(asset["rights_entity_id"])

    # Create job
    job = await db.fetch_one("""
        INSERT INTO processing_jobs (
            job_type, rights_entity_id, asset_id, status,
            priority, config, created_by
        )
        VALUES (
            :job_type, :entity_id, :asset_id, 'queued',
            :priority, :config, :created_by
        )
        RETURNING id, job_type, rights_entity_id, asset_id, status,
                  priority, retry_count, max_retries, created_at
    """, {
        "job_type": payload.job_type,
        "entity_id": str(payload.rights_entity_id) if payload.rights_entity_id else None,
        "asset_id": str(payload.asset_id) if payload.asset_id else None,
        "priority": payload.priority,
        "config": payload.config,
        "created_by": f"user:{user_id}"
    })

    # If embedding job, update entity status
    if payload.job_type == 'embedding_generation' and payload.rights_entity_id:
        await db.execute("""
            UPDATE rights_entities
            SET embedding_status = 'processing', updated_at = now()
            WHERE id = :entity_id
        """, {"entity_id": str(payload.rights_entity_id)})

    return {
        "job": dict(job),
        "message": "Job queued successfully"
    }


@router.post("/entities/{entity_id}/process")
async def trigger_entity_processing(
    request: Request,
    entity_id: UUID,
    force: bool = False
):
    """
    Trigger embedding generation for a rights entity.

    Creates a processing job to generate embeddings from entity content and assets.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify access
    entity = await db.fetch_one("""
        SELECT re.id, re.embedding_status, re.title
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Check if already processing (unless force)
    if entity["embedding_status"] == "processing" and not force:
        raise HTTPException(
            status_code=409,
            detail="Entity is already being processed. Use force=true to queue anyway."
        )

    # Check for existing queued/processing jobs
    existing = await db.fetch_one("""
        SELECT id, status FROM processing_jobs
        WHERE rights_entity_id = :entity_id
        AND job_type = 'embedding_generation'
        AND status IN ('queued', 'processing')
    """, {"entity_id": str(entity_id)})

    if existing and not force:
        raise HTTPException(
            status_code=409,
            detail=f"Job already {existing['status']}. Use force=true to queue new job."
        )

    # Create embedding job
    job = await db.fetch_one("""
        INSERT INTO processing_jobs (
            job_type, rights_entity_id, status, priority, created_by
        )
        VALUES (
            'embedding_generation', :entity_id, 'queued', 0, :created_by
        )
        RETURNING id, job_type, status, created_at
    """, {
        "entity_id": str(entity_id),
        "created_by": f"user:{user_id}"
    })

    # Update entity status
    await db.execute("""
        UPDATE rights_entities
        SET embedding_status = 'processing', processing_error = NULL, updated_at = now()
        WHERE id = :entity_id
    """, {"entity_id": str(entity_id)})

    return {
        "job": dict(job),
        "entity_id": str(entity_id),
        "message": f"Embedding generation queued for '{entity['title']}'"
    }


@router.post("/jobs/{job_id}/cancel")
async def cancel_job(request: Request, job_id: UUID):
    """Cancel a queued job."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify access
    job = await db.fetch_one("""
        SELECT pj.id, pj.status, pj.rights_entity_id
        FROM processing_jobs pj
        JOIN rights_entities re ON re.id = pj.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE pj.id = :job_id AND wm.user_id = :user_id
    """, {"job_id": str(job_id), "user_id": user_id})

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job["status"] not in ("queued", "processing"):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel job with status '{job['status']}'"
        )

    # Cancel the job
    await db.execute("""
        UPDATE processing_jobs
        SET status = 'cancelled', updated_at = now()
        WHERE id = :job_id
    """, {"job_id": str(job_id)})

    # Reset entity status if no other pending jobs
    other_jobs = await db.fetch_one("""
        SELECT COUNT(*) as count FROM processing_jobs
        WHERE rights_entity_id = :entity_id
        AND status IN ('queued', 'processing')
        AND id != :job_id
    """, {"entity_id": str(job["rights_entity_id"]), "job_id": str(job_id)})

    if other_jobs["count"] == 0:
        await db.execute("""
            UPDATE rights_entities
            SET embedding_status = 'pending', updated_at = now()
            WHERE id = :entity_id
        """, {"entity_id": str(job["rights_entity_id"])})

    return {"status": "cancelled", "job_id": str(job_id)}


@router.post("/jobs/{job_id}/retry")
async def retry_job(request: Request, job_id: UUID):
    """Retry a failed job."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify access
    job = await db.fetch_one("""
        SELECT pj.id, pj.status, pj.job_type, pj.rights_entity_id,
               pj.asset_id, pj.config, pj.retry_count, pj.max_retries
        FROM processing_jobs pj
        JOIN rights_entities re ON re.id = pj.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE pj.id = :job_id AND wm.user_id = :user_id
    """, {"job_id": str(job_id), "user_id": user_id})

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job["status"] != "failed":
        raise HTTPException(
            status_code=400,
            detail=f"Can only retry failed jobs. Current status: '{job['status']}'"
        )

    # Create new job with same config
    new_job = await db.fetch_one("""
        INSERT INTO processing_jobs (
            job_type, rights_entity_id, asset_id, status,
            priority, config, created_by
        )
        VALUES (
            :job_type, :entity_id, :asset_id, 'queued',
            1, :config, :created_by
        )
        RETURNING id, job_type, status, created_at
    """, {
        "job_type": job["job_type"],
        "entity_id": str(job["rights_entity_id"]) if job["rights_entity_id"] else None,
        "asset_id": str(job["asset_id"]) if job["asset_id"] else None,
        "config": job["config"],
        "created_by": f"user:{user_id}"
    })

    # Update entity status if embedding job
    if job["job_type"] == "embedding_generation" and job["rights_entity_id"]:
        await db.execute("""
            UPDATE rights_entities
            SET embedding_status = 'processing', processing_error = NULL, updated_at = now()
            WHERE id = :entity_id
        """, {"entity_id": str(job["rights_entity_id"])})

    return {
        "job": dict(new_job),
        "original_job_id": str(job_id),
        "message": "Job retry queued"
    }
