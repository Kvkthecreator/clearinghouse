"""Reference assets management endpoints with file upload support."""
import os
from typing import Optional
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, UploadFile, File, Form
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()

# Supabase Storage configuration
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
STORAGE_BUCKET = "reference-assets"

# Valid asset types per DB constraint
VALID_ASSET_TYPES = [
    'audio_master', 'audio_preview', 'audio_stem', 'lyrics',
    'sheet_music', 'artwork', 'photo', 'contract', 'certificate', 'other'
]


class AssetCreateRequest(BaseModel):
    """Request body for creating asset metadata (without file upload)."""
    asset_type: str
    filename: str
    storage_path: str
    mime_type: Optional[str] = None
    file_size_bytes: Optional[int] = None
    is_public: bool = False


class SignedUrlResponse(BaseModel):
    """Response with signed upload/download URL."""
    url: str
    path: str
    expires_in: int


# =============================================================================
# Helper Functions
# =============================================================================

async def get_supabase_storage_client():
    """Get Supabase storage client for file operations."""
    try:
        from supabase import create_client
        if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
            raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required")
        client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        return client.storage
    except ImportError:
        raise HTTPException(
            status_code=501,
            detail="Supabase client not installed. Run: pip install supabase"
        )


def generate_storage_path(entity_id: str, asset_type: str, filename: str) -> str:
    """Generate storage path: {entity_id}/{asset_type}/{filename}"""
    import re
    # Sanitize filename
    safe_filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
    return f"{entity_id}/{asset_type}/{safe_filename}"


# =============================================================================
# Asset List/Get Endpoints
# =============================================================================

@router.get("/entities/{entity_id}/assets")
async def list_entity_assets(
    request: Request,
    entity_id: UUID,
    asset_type: Optional[str] = None,
    processing_status: Optional[str] = None
):
    """List all assets for a rights entity."""
    user_id = request.state.user_id
    db = await get_db()

    # Verify entity access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Build query
    where_clauses = ["rights_entity_id = :entity_id"]
    params = {"entity_id": str(entity_id)}

    if asset_type:
        where_clauses.append("asset_type = :asset_type")
        params["asset_type"] = asset_type

    if processing_status:
        where_clauses.append("processing_status = :processing_status")
        params["processing_status"] = processing_status

    assets = await db.fetch_all(f"""
        SELECT id, asset_type, filename, mime_type, file_size_bytes,
               storage_bucket, storage_path, is_public,
               duration_seconds, sample_rate, channels, bit_depth,
               processing_status, processing_error, extracted_metadata,
               created_at, updated_at
        FROM reference_assets
        WHERE {' AND '.join(where_clauses)}
        ORDER BY created_at DESC
    """, params)

    return {"assets": [dict(a) for a in assets]}


@router.get("/assets/{asset_id}")
async def get_asset(request: Request, asset_id: UUID):
    """Get asset details."""
    user_id = request.state.user_id
    db = await get_db()

    asset = await db.fetch_one("""
        SELECT ra.*, re.title as entity_title, re.rights_type
        FROM reference_assets ra
        JOIN rights_entities re ON re.id = ra.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE ra.id = :asset_id AND wm.user_id = :user_id
    """, {"asset_id": str(asset_id), "user_id": user_id})

    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    return {"asset": dict(asset)}


# =============================================================================
# File Upload Endpoints
# =============================================================================

@router.post("/entities/{entity_id}/assets/upload")
async def upload_asset(
    request: Request,
    entity_id: UUID,
    file: UploadFile = File(...),
    asset_type: str = Form(...),
    is_public: bool = Form(False)
):
    """
    Upload a file and create asset metadata record.

    Uploads file to Supabase Storage and creates reference_assets record.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify entity access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id
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

    # Generate storage path
    storage_path = generate_storage_path(str(entity_id), asset_type, file.filename or "file")

    # Read file content
    file_content = await file.read()
    file_size = len(file_content)

    # Upload to Supabase Storage
    try:
        storage = await get_supabase_storage_client()
        result = storage.from_(STORAGE_BUCKET).upload(
            path=storage_path,
            file=file_content,
            file_options={"content-type": file.content_type or "application/octet-stream"}
        )

        if hasattr(result, 'error') and result.error:
            raise HTTPException(status_code=500, detail=f"Storage upload failed: {result.error}")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Storage upload failed: {str(e)}")

    # Create asset record
    asset = await db.fetch_one("""
        INSERT INTO reference_assets (
            rights_entity_id, asset_type, filename, mime_type,
            file_size_bytes, storage_bucket, storage_path, is_public,
            processing_status, created_by
        )
        VALUES (
            :entity_id, :asset_type, :filename, :mime_type,
            :file_size, :bucket, :path, :is_public,
            'uploaded', :created_by
        )
        RETURNING id, asset_type, filename, mime_type, file_size_bytes,
                  storage_bucket, storage_path, is_public, processing_status, created_at
    """, {
        "entity_id": str(entity_id),
        "asset_type": asset_type,
        "filename": file.filename,
        "mime_type": file.content_type,
        "file_size": file_size,
        "bucket": STORAGE_BUCKET,
        "path": storage_path,
        "is_public": is_public,
        "created_by": f"user:{user_id}"
    })

    return {
        "asset": dict(asset),
        "message": "File uploaded successfully"
    }


@router.post("/entities/{entity_id}/assets/request-upload")
async def request_upload_url(
    request: Request,
    entity_id: UUID,
    asset_type: str = Form(...),
    filename: str = Form(...),
    content_type: str = Form(...)
):
    """
    Request a signed URL for direct client-side upload.

    Use this for large files to upload directly to storage from the browser.
    After upload completes, call POST /entities/{entity_id}/assets to register the metadata.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify entity access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id
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

    # Generate storage path
    storage_path = generate_storage_path(str(entity_id), asset_type, filename)

    # Get signed upload URL
    try:
        storage = await get_supabase_storage_client()
        result = storage.from_(STORAGE_BUCKET).create_signed_upload_url(storage_path)

        if hasattr(result, 'error') and result.error:
            raise HTTPException(status_code=500, detail=f"Failed to create upload URL: {result.error}")

        signed_url = result.get('signedURL') or result.get('signed_url') or (result.data.get('signedUrl') if hasattr(result, 'data') else None)

        if not signed_url:
            # Fallback: construct URL if signed URL generation not available
            raise HTTPException(
                status_code=501,
                detail="Signed upload URLs not available. Use direct upload endpoint instead."
            )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create upload URL: {str(e)}")

    return {
        "upload_url": signed_url,
        "storage_path": storage_path,
        "storage_bucket": STORAGE_BUCKET,
        "expires_in": 3600  # 1 hour
    }


@router.post("/entities/{entity_id}/assets")
async def create_asset_metadata(
    request: Request,
    entity_id: UUID,
    payload: AssetCreateRequest
):
    """
    Create asset metadata record for an already-uploaded file.

    Use this after uploading via signed URL from request-upload endpoint.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify entity access
    entity = await db.fetch_one("""
        SELECT re.id, re.catalog_id
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Validate asset type
    if payload.asset_type not in VALID_ASSET_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid asset_type. Must be one of: {VALID_ASSET_TYPES}"
        )

    # Create asset record
    asset = await db.fetch_one("""
        INSERT INTO reference_assets (
            rights_entity_id, asset_type, filename, mime_type,
            file_size_bytes, storage_bucket, storage_path, is_public,
            processing_status, created_by
        )
        VALUES (
            :entity_id, :asset_type, :filename, :mime_type,
            :file_size, :bucket, :path, :is_public,
            'uploaded', :created_by
        )
        RETURNING id, asset_type, filename, mime_type, file_size_bytes,
                  storage_bucket, storage_path, is_public, processing_status, created_at
    """, {
        "entity_id": str(entity_id),
        "asset_type": payload.asset_type,
        "filename": payload.filename,
        "mime_type": payload.mime_type,
        "file_size": payload.file_size_bytes,
        "bucket": STORAGE_BUCKET,
        "path": payload.storage_path,
        "is_public": payload.is_public,
        "created_by": f"user:{user_id}"
    })

    return {"asset": dict(asset)}


# =============================================================================
# Download URL Endpoint
# =============================================================================

@router.get("/assets/{asset_id}/url")
async def get_asset_download_url(
    request: Request,
    asset_id: UUID,
    expires_in: int = 3600  # Default 1 hour
):
    """
    Get a signed download URL for an asset.

    Returns a temporary URL valid for the specified duration (default 1 hour).
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify access and get storage info
    asset = await db.fetch_one("""
        SELECT ra.id, ra.storage_bucket, ra.storage_path, ra.is_public, ra.filename
        FROM reference_assets ra
        JOIN rights_entities re ON re.id = ra.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE ra.id = :asset_id AND wm.user_id = :user_id
    """, {"asset_id": str(asset_id), "user_id": user_id})

    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    # If public, return direct URL
    if asset["is_public"]:
        public_url = f"{SUPABASE_URL}/storage/v1/object/public/{asset['storage_bucket']}/{asset['storage_path']}"
        return {
            "url": public_url,
            "filename": asset["filename"],
            "expires_in": None,
            "is_public": True
        }

    # Get signed URL for private assets
    try:
        storage = await get_supabase_storage_client()
        result = storage.from_(asset["storage_bucket"]).create_signed_url(
            asset["storage_path"],
            expires_in
        )

        signed_url = None
        if isinstance(result, dict):
            signed_url = result.get('signedURL') or result.get('signed_url')
        elif hasattr(result, 'data') and result.data:
            signed_url = result.data.get('signedUrl') or result.data.get('signedURL')

        if not signed_url:
            raise HTTPException(status_code=500, detail="Failed to generate download URL")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate download URL: {str(e)}")

    return {
        "url": signed_url,
        "filename": asset["filename"],
        "expires_in": expires_in,
        "is_public": False
    }


# =============================================================================
# Delete Endpoint
# =============================================================================

@router.delete("/assets/{asset_id}")
async def delete_asset(request: Request, asset_id: UUID):
    """
    Delete an asset and its file from storage.

    Requires admin/owner role in the workspace.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify access and get storage info
    asset = await db.fetch_one("""
        SELECT ra.id, ra.storage_bucket, ra.storage_path, wm.role
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

    # Delete from storage
    try:
        storage = await get_supabase_storage_client()
        storage.from_(asset["storage_bucket"]).remove([asset["storage_path"]])
    except Exception as e:
        # Log but don't fail - file might already be deleted
        print(f"Warning: Could not delete file from storage: {e}")

    # Delete the record
    await db.execute("""
        DELETE FROM reference_assets WHERE id = :asset_id
    """, {"asset_id": str(asset_id)})

    return {"deleted": True, "asset_id": str(asset_id)}


# =============================================================================
# Trigger Processing Endpoint
# =============================================================================

@router.post("/assets/{asset_id}/process")
async def trigger_asset_processing(
    request: Request,
    asset_id: UUID,
    job_type: str = Form("asset_analysis")
):
    """
    Trigger processing job for an asset (e.g., metadata extraction, fingerprinting).

    Creates a processing_job record for the background worker to pick up.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify access
    asset = await db.fetch_one("""
        SELECT ra.id, ra.rights_entity_id, ra.processing_status
        FROM reference_assets ra
        JOIN rights_entities re ON re.id = ra.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE ra.id = :asset_id AND wm.user_id = :user_id
    """, {"asset_id": str(asset_id), "user_id": user_id})

    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    # Validate job type
    valid_job_types = ['asset_analysis', 'metadata_extraction', 'fingerprint_generation']
    if job_type not in valid_job_types:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid job_type. Must be one of: {valid_job_types}"
        )

    # Create processing job
    job = await db.fetch_one("""
        INSERT INTO processing_jobs (
            job_type, rights_entity_id, asset_id, status, created_by
        )
        VALUES (
            :job_type, :entity_id, :asset_id, 'queued', :created_by
        )
        RETURNING id, job_type, status, created_at
    """, {
        "job_type": job_type,
        "entity_id": str(asset["rights_entity_id"]),
        "asset_id": str(asset_id),
        "created_by": f"user:{user_id}"
    })

    # Update asset status
    await db.execute("""
        UPDATE reference_assets
        SET processing_status = 'processing', updated_at = now()
        WHERE id = :asset_id
    """, {"asset_id": str(asset_id)})

    return {
        "job": dict(job),
        "message": "Processing job queued"
    }
