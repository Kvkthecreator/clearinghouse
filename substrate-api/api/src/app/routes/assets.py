"""Reference assets management endpoints."""
from typing import Optional, List
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, Query, UploadFile, File, Form
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


# =============================================================================
# Pydantic Models
# =============================================================================

class AssetCreate(BaseModel):
    """Create asset metadata (for URL-based assets)."""
    asset_type: str
    filename: str
    storage_path: str
    mime_type: Optional[str] = None
    file_size_bytes: Optional[int] = None
    is_public: bool = False
    duration_seconds: Optional[float] = None
    sample_rate: Optional[int] = None
    channels: Optional[int] = None


class AssetUpdate(BaseModel):
    """Update asset metadata."""
    is_public: Optional[bool] = None
    processing_status: Optional[str] = None


VALID_ASSET_TYPES = [
    'audio_master', 'audio_preview', 'audio_stem',
    'lyrics', 'sheet_music', 'artwork', 'photo',
    'contract', 'certificate', 'other'
]


# =============================================================================
# Asset Routes
# =============================================================================

@router.get("/entities/{entity_id}/assets")
async def list_entity_assets(
    request: Request,
    entity_id: UUID,
    asset_type: Optional[str] = None
):
    """List all assets for a rights entity."""
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
    where_clause = "rights_entity_id = :entity_id"
    params = {"entity_id": str(entity_id)}

    if asset_type:
        where_clause += " AND asset_type = :asset_type"
        params["asset_type"] = asset_type

    assets = await db.fetch_all(f"""
        SELECT id, asset_type, filename, mime_type, file_size_bytes,
               storage_bucket, storage_path, is_public,
               duration_seconds, sample_rate, channels,
               processing_status, created_at, updated_at
        FROM reference_assets
        WHERE {where_clause}
        ORDER BY created_at DESC
    """, params)

    return {"assets": [dict(a) for a in assets]}


@router.post("/entities/{entity_id}/assets")
async def create_asset(
    request: Request,
    entity_id: UUID,
    asset_type: str = Form(...),
    filename: str = Form(...),
    storage_path: str = Form(...),
    mime_type: Optional[str] = Form(None),
    file_size_bytes: Optional[int] = Form(None),
    is_public: bool = Form(False),
    duration_seconds: Optional[float] = Form(None),
    sample_rate: Optional[int] = Form(None),
    channels: Optional[int] = Form(None)
):
    """
    Create asset metadata record.

    Note: Actual file upload should be done directly to Supabase Storage.
    This endpoint creates the metadata record linking the asset to the entity.
    """
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

    # Validate asset type
    if asset_type not in VALID_ASSET_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid asset_type. Must be one of: {VALID_ASSET_TYPES}"
        )

    asset = await db.fetch_one("""
        INSERT INTO reference_assets (
            rights_entity_id, asset_type, filename, mime_type,
            file_size_bytes, storage_path, is_public,
            duration_seconds, sample_rate, channels,
            processing_status, created_by
        )
        VALUES (
            :entity_id, :asset_type, :filename, :mime_type,
            :file_size_bytes, :storage_path, :is_public,
            :duration_seconds, :sample_rate, :channels,
            'uploaded', :user_id
        )
        RETURNING id, asset_type, filename, storage_path, processing_status, created_at
    """, {
        "entity_id": str(entity_id),
        "asset_type": asset_type,
        "filename": filename,
        "mime_type": mime_type,
        "file_size_bytes": file_size_bytes,
        "storage_path": storage_path,
        "is_public": is_public,
        "duration_seconds": duration_seconds,
        "sample_rate": sample_rate,
        "channels": channels,
        "user_id": user_id
    })

    return {"asset": dict(asset)}


@router.get("/assets/{asset_id}")
async def get_asset(request: Request, asset_id: UUID):
    """Get asset details."""
    user_id = request.state.user_id
    db = await get_db()

    asset = await db.fetch_one("""
        SELECT ra.*
        FROM reference_assets ra
        JOIN rights_entities re ON re.id = ra.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE ra.id = :asset_id AND wm.user_id = :user_id
    """, {"asset_id": str(asset_id), "user_id": user_id})

    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    return {"asset": dict(asset)}


@router.patch("/assets/{asset_id}")
async def update_asset(request: Request, asset_id: UUID, payload: AssetUpdate):
    """Update asset metadata."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify access (admin/owner only)
    asset = await db.fetch_one("""
        SELECT ra.id, wm.role
        FROM reference_assets ra
        JOIN rights_entities re ON re.id = ra.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE ra.id = :asset_id AND wm.user_id = :user_id
    """, {"asset_id": str(asset_id), "user_id": user_id})

    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    if asset["role"] not in ("owner", "admin"):
        raise HTTPException(status_code=403, detail="Admin access required")

    # Build update
    updates = []
    params = {"asset_id": str(asset_id)}

    if payload.is_public is not None:
        updates.append("is_public = :is_public")
        params["is_public"] = payload.is_public

    if payload.processing_status is not None:
        valid_statuses = ['uploaded', 'processing', 'ready', 'failed']
        if payload.processing_status not in valid_statuses:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid processing_status. Must be one of: {valid_statuses}"
            )
        updates.append("processing_status = :processing_status")
        params["processing_status"] = payload.processing_status

    if not updates:
        raise HTTPException(status_code=400, detail="No changes provided")

    await db.execute(f"""
        UPDATE reference_assets
        SET {', '.join(updates)}, updated_at = now()
        WHERE id = :asset_id
    """, params)

    return await get_asset(request, asset_id)


@router.delete("/assets/{asset_id}")
async def delete_asset(request: Request, asset_id: UUID):
    """Delete an asset (admin/owner only)."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify access
    asset = await db.fetch_one("""
        SELECT ra.id, ra.storage_path, wm.role
        FROM reference_assets ra
        JOIN rights_entities re ON re.id = ra.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE ra.id = :asset_id AND wm.user_id = :user_id
    """, {"asset_id": str(asset_id), "user_id": user_id})

    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    if asset["role"] not in ("owner", "admin"):
        raise HTTPException(status_code=403, detail="Admin access required")

    # Delete the record (actual file deletion from storage should be handled separately)
    await db.execute("""
        DELETE FROM reference_assets WHERE id = :asset_id
    """, {"asset_id": str(asset_id)})

    return {"deleted": True, "asset_id": asset_id}
