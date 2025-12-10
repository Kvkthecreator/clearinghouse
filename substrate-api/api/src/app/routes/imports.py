"""Bulk import endpoints for rights entities."""
import csv
import io
from typing import Optional, List, Dict, Any
from uuid import UUID
from fastapi import APIRouter, HTTPException, Request, UploadFile, File, Form
from pydantic import BaseModel, Field

from app.deps import get_db

router = APIRouter()


# =============================================================================
# Pydantic Models
# =============================================================================

class EntityImportItem(BaseModel):
    """Single entity for bulk import."""
    rights_type: str
    title: str
    entity_key: Optional[str] = None
    content: Optional[Dict[str, Any]] = None
    ai_permissions: Optional[Dict[str, Any]] = None
    ownership_chain: Optional[List[Dict[str, Any]]] = None
    semantic_metadata: Optional[Dict[str, Any]] = None


class BulkImportRequest(BaseModel):
    """Bulk import request body."""
    entities: List[EntityImportItem]
    auto_process: bool = False  # Whether to queue embedding generation


class ImportResult(BaseModel):
    """Result for a single imported entity."""
    index: int
    success: bool
    entity_id: Optional[str] = None
    title: str
    error: Optional[str] = None


class BulkImportResponse(BaseModel):
    """Response from bulk import."""
    total: int
    successful: int
    failed: int
    results: List[ImportResult]
    job_id: Optional[str] = None  # If auto_process was enabled


# =============================================================================
# Bulk Import Endpoints
# =============================================================================

@router.post("/catalogs/{catalog_id}/import")
async def bulk_import_entities(
    request: Request,
    catalog_id: UUID,
    payload: BulkImportRequest
):
    """
    Bulk import multiple rights entities at once.

    Accepts a JSON array of entities and creates them in the catalog.
    Optionally queues embedding generation for all imported entities.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify catalog access
    catalog = await db.fetch_one("""
        SELECT c.id, c.workspace_id
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    # Get valid rights types
    schemas = await db.fetch_all("SELECT id FROM rights_schemas")
    valid_types = {s["id"] for s in schemas}

    results: List[ImportResult] = []
    successful_ids: List[str] = []

    # Process each entity
    for idx, item in enumerate(payload.entities):
        try:
            # Validate rights_type
            if item.rights_type not in valid_types:
                results.append(ImportResult(
                    index=idx,
                    success=False,
                    title=item.title,
                    error=f"Invalid rights_type: {item.rights_type}"
                ))
                continue

            # Create entity
            entity = await db.fetch_one("""
                INSERT INTO rights_entities (
                    catalog_id, rights_type, title, entity_key,
                    content, ai_permissions, ownership_chain, semantic_metadata,
                    status, embedding_status, created_by
                )
                VALUES (
                    :catalog_id, :rights_type, :title, :entity_key,
                    :content, :ai_permissions, :ownership_chain, :semantic_metadata,
                    'active', 'pending', :created_by
                )
                RETURNING id, title
            """, {
                "catalog_id": str(catalog_id),
                "rights_type": item.rights_type,
                "title": item.title,
                "entity_key": item.entity_key,
                "content": item.content or {},
                "ai_permissions": item.ai_permissions or {},
                "ownership_chain": item.ownership_chain or [],
                "semantic_metadata": item.semantic_metadata or {},
                "created_by": f"user:{user_id}"
            })

            results.append(ImportResult(
                index=idx,
                success=True,
                entity_id=str(entity["id"]),
                title=entity["title"]
            ))
            successful_ids.append(str(entity["id"]))

        except Exception as e:
            error_msg = str(e)
            # Handle unique constraint violations
            if "unique" in error_msg.lower() or "duplicate" in error_msg.lower():
                error_msg = f"Duplicate entity_key for this rights_type"
            results.append(ImportResult(
                index=idx,
                success=False,
                title=item.title,
                error=error_msg
            ))

    # Create batch processing job if requested and we have successful imports
    job_id = None
    if payload.auto_process and successful_ids:
        job = await db.fetch_one("""
            INSERT INTO processing_jobs (
                job_type, status, priority, config, created_by
            )
            VALUES (
                'batch_import', 'queued', 0, :config, :created_by
            )
            RETURNING id
        """, {
            "config": {"entity_ids": successful_ids, "catalog_id": str(catalog_id)},
            "created_by": f"user:{user_id}"
        })
        job_id = str(job["id"])

        # Update all imported entities to processing status
        for entity_id in successful_ids:
            await db.execute("""
                UPDATE rights_entities
                SET embedding_status = 'processing'
                WHERE id = :entity_id
            """, {"entity_id": entity_id})

    successful = sum(1 for r in results if r.success)
    return {
        "total": len(payload.entities),
        "successful": successful,
        "failed": len(payload.entities) - successful,
        "results": [r.dict() for r in results],
        "job_id": job_id
    }


@router.post("/catalogs/{catalog_id}/import/csv")
async def bulk_import_csv(
    request: Request,
    catalog_id: UUID,
    file: UploadFile = File(...),
    rights_type: str = Form(...),
    auto_process: bool = Form(False)
):
    """
    Bulk import entities from a CSV file.

    CSV must have headers. Required column: title
    Optional columns: entity_key, content (JSON string), ai_permissions (JSON string)

    All imported entities will use the specified rights_type.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify catalog access
    catalog = await db.fetch_one("""
        SELECT c.id, c.workspace_id
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    # Validate rights_type
    schema = await db.fetch_one("""
        SELECT id FROM rights_schemas WHERE id = :rights_type
    """, {"rights_type": rights_type})

    if not schema:
        raise HTTPException(status_code=400, detail=f"Invalid rights_type: {rights_type}")

    # Read and parse CSV
    try:
        content = await file.read()
        text = content.decode('utf-8-sig')  # Handle BOM
        reader = csv.DictReader(io.StringIO(text))
        rows = list(reader)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse CSV: {str(e)}")

    if not rows:
        raise HTTPException(status_code=400, detail="CSV file is empty")

    # Verify required column
    if 'title' not in reader.fieldnames:
        raise HTTPException(status_code=400, detail="CSV must have 'title' column")

    results: List[ImportResult] = []
    successful_ids: List[str] = []

    for idx, row in enumerate(rows):
        try:
            title = row.get('title', '').strip()
            if not title:
                results.append(ImportResult(
                    index=idx,
                    success=False,
                    title='(empty)',
                    error="Title is required"
                ))
                continue

            # Parse optional JSON fields
            content = {}
            ai_permissions = {}

            if row.get('content'):
                try:
                    import json
                    content = json.loads(row['content'])
                except:
                    pass

            if row.get('ai_permissions'):
                try:
                    import json
                    ai_permissions = json.loads(row['ai_permissions'])
                except:
                    pass

            # Create entity
            entity = await db.fetch_one("""
                INSERT INTO rights_entities (
                    catalog_id, rights_type, title, entity_key,
                    content, ai_permissions,
                    status, embedding_status, created_by
                )
                VALUES (
                    :catalog_id, :rights_type, :title, :entity_key,
                    :content, :ai_permissions,
                    'active', 'pending', :created_by
                )
                RETURNING id, title
            """, {
                "catalog_id": str(catalog_id),
                "rights_type": rights_type,
                "title": title,
                "entity_key": row.get('entity_key', '').strip() or None,
                "content": content,
                "ai_permissions": ai_permissions,
                "created_by": f"user:{user_id}"
            })

            results.append(ImportResult(
                index=idx,
                success=True,
                entity_id=str(entity["id"]),
                title=entity["title"]
            ))
            successful_ids.append(str(entity["id"]))

        except Exception as e:
            error_msg = str(e)
            if "unique" in error_msg.lower() or "duplicate" in error_msg.lower():
                error_msg = "Duplicate entity_key"
            results.append(ImportResult(
                index=idx,
                success=False,
                title=row.get('title', '(unknown)'),
                error=error_msg
            ))

    # Create batch job if requested
    job_id = None
    if auto_process and successful_ids:
        job = await db.fetch_one("""
            INSERT INTO processing_jobs (
                job_type, status, priority, config, created_by
            )
            VALUES (
                'batch_import', 'queued', 0, :config, :created_by
            )
            RETURNING id
        """, {
            "config": {"entity_ids": successful_ids, "catalog_id": str(catalog_id)},
            "created_by": f"user:{user_id}"
        })
        job_id = str(job["id"])

        for entity_id in successful_ids:
            await db.execute("""
                UPDATE rights_entities
                SET embedding_status = 'processing'
                WHERE id = :entity_id
            """, {"entity_id": entity_id})

    successful = sum(1 for r in results if r.success)
    return {
        "total": len(rows),
        "successful": successful,
        "failed": len(rows) - successful,
        "results": [r.dict() for r in results],
        "job_id": job_id
    }


@router.get("/catalogs/{catalog_id}/import/template")
async def get_import_template(
    request: Request,
    catalog_id: UUID,
    rights_type: str
):
    """
    Get a CSV template for bulk import.

    Returns CSV content with headers based on the rights schema.
    """
    user_id = request.state.user_id
    db = await get_db()

    # Verify catalog access
    catalog = await db.fetch_one("""
        SELECT c.id
        FROM catalogs c
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE c.id = :catalog_id AND wm.user_id = :user_id
    """, {"catalog_id": str(catalog_id), "user_id": user_id})

    if not catalog:
        raise HTTPException(status_code=404, detail="Catalog not found")

    # Get schema
    schema = await db.fetch_one("""
        SELECT id, display_name, field_schema, identifier_fields
        FROM rights_schemas
        WHERE id = :rights_type
    """, {"rights_type": rights_type})

    if not schema:
        raise HTTPException(status_code=400, detail=f"Invalid rights_type: {rights_type}")

    # Build headers
    headers = ["title", "entity_key"]

    # Add schema-specific fields as columns
    field_schema = schema["field_schema"] or {}
    for field_name in field_schema.keys():
        if field_name not in headers:
            headers.append(field_name)

    # Add content and ai_permissions as JSON columns
    headers.extend(["content", "ai_permissions"])

    # Generate CSV
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(headers)

    # Add example row
    example_row = ["Example Title", "EXAMPLE-KEY-001"]
    example_row.extend([""] * (len(headers) - 4))  # Empty schema fields
    example_row.append('{}')  # content
    example_row.append('{"training": {"allowed": true}}')  # ai_permissions
    writer.writerow(example_row)

    from fastapi.responses import Response
    return Response(
        content=output.getvalue(),
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename={rights_type}_import_template.csv"
        }
    )
