"""License management endpoints."""
from typing import Optional, List
from uuid import UUID
from datetime import date
from fastapi import APIRouter, HTTPException, Request, Query
from pydantic import BaseModel

from app.deps import get_db

router = APIRouter()


# =============================================================================
# LICENSE TEMPLATES
# =============================================================================

class LicenseTemplateCreate(BaseModel):
    name: str
    description: Optional[str] = None
    license_type: str  # exclusive, non_exclusive, sync, mechanical, ai_training, etc.
    terms: dict = {}
    ai_terms: dict = {}
    pricing: dict = {}
    is_public: bool = False


class LicenseTemplateUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    terms: Optional[dict] = None
    ai_terms: Optional[dict] = None
    pricing: Optional[dict] = None
    is_public: Optional[bool] = None
    is_active: Optional[bool] = None


@router.get("/workspaces/{workspace_id}/license-templates")
async def list_license_templates(
    request: Request,
    workspace_id: UUID,
    include_public: bool = True,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List license templates for a workspace."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    if include_public:
        templates = await db.fetch_all("""
            SELECT id, name, description, license_type, is_public, is_active,
                   workspace_id, created_at
            FROM license_templates
            WHERE (workspace_id = :workspace_id OR is_public = true)
            AND is_active = true
            ORDER BY name
            LIMIT :limit OFFSET :offset
        """, {"workspace_id": str(workspace_id), "limit": limit, "offset": offset})
    else:
        templates = await db.fetch_all("""
            SELECT id, name, description, license_type, is_public, is_active,
                   workspace_id, created_at
            FROM license_templates
            WHERE workspace_id = :workspace_id AND is_active = true
            ORDER BY name
            LIMIT :limit OFFSET :offset
        """, {"workspace_id": str(workspace_id), "limit": limit, "offset": offset})

    return {"templates": [dict(t) for t in templates]}


@router.post("/workspaces/{workspace_id}/license-templates")
async def create_license_template(
    request: Request,
    workspace_id: UUID,
    payload: LicenseTemplateCreate
):
    """Create a new license template."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    template = await db.fetch_one("""
        INSERT INTO license_templates (
            workspace_id, name, description, license_type,
            terms, ai_terms, pricing, is_public, created_by
        )
        VALUES (
            :workspace_id, :name, :description, :license_type,
            :terms, :ai_terms, :pricing, :is_public, :user_id
        )
        RETURNING id, name, license_type, is_public, created_at
    """, {
        "workspace_id": str(workspace_id),
        "name": payload.name,
        "description": payload.description,
        "license_type": payload.license_type,
        "terms": payload.terms,
        "ai_terms": payload.ai_terms,
        "pricing": payload.pricing,
        "is_public": payload.is_public,
        "user_id": user_id
    })

    return {"template": dict(template)}


@router.get("/license-templates/{template_id}")
async def get_license_template(request: Request, template_id: UUID):
    """Get a license template by ID."""
    user_id = request.state.user_id
    db = await get_db()

    template = await db.fetch_one("""
        SELECT lt.*
        FROM license_templates lt
        LEFT JOIN workspace_memberships wm ON wm.workspace_id = lt.workspace_id
        WHERE lt.id = :template_id
        AND (lt.is_public = true OR wm.user_id = :user_id)
    """, {"template_id": str(template_id), "user_id": user_id})

    if not template:
        raise HTTPException(status_code=404, detail="Template not found")

    return {"template": dict(template)}


@router.patch("/license-templates/{template_id}")
async def update_license_template(
    request: Request,
    template_id: UUID,
    payload: LicenseTemplateUpdate
):
    """Update a license template (admin only)."""
    user_id = request.state.user_id
    db = await get_db()

    # Check ownership and admin access
    template = await db.fetch_one("""
        SELECT lt.id, lt.workspace_id
        FROM license_templates lt
        JOIN workspace_memberships wm ON wm.workspace_id = lt.workspace_id
        WHERE lt.id = :template_id AND wm.user_id = :user_id
        AND wm.role IN ('owner', 'admin')
    """, {"template_id": str(template_id), "user_id": user_id})

    if not template:
        raise HTTPException(status_code=404, detail="Template not found or insufficient permissions")

    updates = []
    params = {"template_id": str(template_id)}

    for field in ["name", "description", "terms", "ai_terms", "pricing", "is_public", "is_active"]:
        value = getattr(payload, field, None)
        if value is not None:
            updates.append(f"{field} = :{field}")
            params[field] = value

    if not updates:
        raise HTTPException(status_code=400, detail="No updates provided")

    await db.execute(f"""
        UPDATE license_templates
        SET {', '.join(updates)}, updated_at = now()
        WHERE id = :template_id
    """, params)

    return {"updated": True}


# =============================================================================
# LICENSEES
# =============================================================================

class LicenseeCreate(BaseModel):
    name: str
    entity_type: str = "organization"  # organization, individual, platform
    contact_email: Optional[str] = None
    contact_name: Optional[str] = None
    platform_info: dict = {}
    metadata: dict = {}


@router.get("/workspaces/{workspace_id}/licensees")
async def list_licensees(
    request: Request,
    workspace_id: UUID,
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List licensees for a workspace."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    licensees = await db.fetch_all("""
        SELECT id, name, entity_type, contact_email, contact_name,
               verification_status, created_at
        FROM licensees
        WHERE workspace_id = :workspace_id
        ORDER BY name
        LIMIT :limit OFFSET :offset
    """, {"workspace_id": str(workspace_id), "limit": limit, "offset": offset})

    return {"licensees": [dict(l) for l in licensees]}


@router.post("/workspaces/{workspace_id}/licensees")
async def create_licensee(request: Request, workspace_id: UUID, payload: LicenseeCreate):
    """Create a new licensee."""
    user_id = request.state.user_id
    db = await get_db()

    # Check workspace access
    membership = await db.fetch_one("""
        SELECT role FROM workspace_memberships
        WHERE workspace_id = :workspace_id AND user_id = :user_id
    """, {"workspace_id": str(workspace_id), "user_id": user_id})

    if not membership:
        raise HTTPException(status_code=404, detail="Workspace not found")

    licensee = await db.fetch_one("""
        INSERT INTO licensees (
            workspace_id, name, entity_type,
            contact_email, contact_name, platform_info, metadata
        )
        VALUES (
            :workspace_id, :name, :entity_type,
            :contact_email, :contact_name, :platform_info, :metadata
        )
        RETURNING id, name, entity_type, created_at
    """, {
        "workspace_id": str(workspace_id),
        "name": payload.name,
        "entity_type": payload.entity_type,
        "contact_email": payload.contact_email,
        "contact_name": payload.contact_name,
        "platform_info": payload.platform_info,
        "metadata": payload.metadata
    })

    return {"licensee": dict(licensee)}


# =============================================================================
# LICENSE GRANTS
# =============================================================================

class LicenseGrantCreate(BaseModel):
    rights_entity_id: UUID
    licensee_id: Optional[UUID] = None
    template_id: Optional[UUID] = None
    terms: dict = {}
    ai_terms: dict = {}
    territory: List[str] = ["worldwide"]
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    usage_tracking_enabled: bool = False
    usage_reporting_frequency: Optional[str] = None
    pricing: dict = {}
    requires_approval: bool = False


@router.get("/entities/{entity_id}/licenses")
async def list_entity_licenses(
    request: Request,
    entity_id: UUID,
    status: str = Query("active", enum=["active", "all"]),
    limit: int = Query(50, le=200),
    offset: int = 0
):
    """List licenses for a rights entity."""
    user_id = request.state.user_id
    db = await get_db()

    # Check entity access
    entity = await db.fetch_one("""
        SELECT re.id
        FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = :entity_id AND wm.user_id = :user_id
    """, {"entity_id": str(entity_id), "user_id": user_id})

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    where_clause = "lg.rights_entity_id = :entity_id"
    params = {"entity_id": str(entity_id), "limit": limit, "offset": offset}

    if status == "active":
        where_clause += " AND lg.status = 'active'"

    licenses = await db.fetch_all(f"""
        SELECT lg.id, lg.status, lg.territory, lg.start_date, lg.end_date,
               lg.usage_tracking_enabled, lg.created_at,
               l.name as licensee_name, lt.name as template_name
        FROM license_grants lg
        LEFT JOIN licensees l ON l.id = lg.licensee_id
        LEFT JOIN license_templates lt ON lt.id = lg.template_id
        WHERE {where_clause}
        ORDER BY lg.created_at DESC
        LIMIT :limit OFFSET :offset
    """, params)

    return {"licenses": [dict(l) for l in licenses]}


@router.post("/entities/{entity_id}/licenses")
async def create_license_grant(request: Request, entity_id: UUID, payload: LicenseGrantCreate):
    """Create a new license grant."""
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

    # Get template terms if provided
    terms = payload.terms
    ai_terms = payload.ai_terms

    if payload.template_id:
        template = await db.fetch_one("""
            SELECT terms, ai_terms FROM license_templates WHERE id = :template_id
        """, {"template_id": str(payload.template_id)})

        if template:
            # Merge template with overrides
            terms = {**template["terms"], **payload.terms}
            ai_terms = {**template["ai_terms"], **payload.ai_terms}

    license_grant = await db.fetch_one("""
        INSERT INTO license_grants (
            rights_entity_id, licensee_id, template_id,
            terms, ai_terms, territory,
            start_date, end_date, status,
            usage_tracking_enabled, usage_reporting_frequency,
            pricing, requires_approval, created_by
        )
        VALUES (
            :entity_id, :licensee_id, :template_id,
            :terms, :ai_terms, :territory,
            :start_date, :end_date, :status,
            :usage_tracking_enabled, :usage_reporting_frequency,
            :pricing, :requires_approval, :user_id
        )
        RETURNING id, status, territory, start_date, end_date, created_at
    """, {
        "entity_id": str(entity_id),
        "licensee_id": str(payload.licensee_id) if payload.licensee_id else None,
        "template_id": str(payload.template_id) if payload.template_id else None,
        "terms": terms,
        "ai_terms": ai_terms,
        "territory": payload.territory,
        "start_date": payload.start_date or date.today(),
        "end_date": payload.end_date,
        "status": "pending_approval" if payload.requires_approval else "active",
        "usage_tracking_enabled": payload.usage_tracking_enabled,
        "usage_reporting_frequency": payload.usage_reporting_frequency,
        "pricing": payload.pricing,
        "requires_approval": payload.requires_approval,
        "user_id": user_id
    })

    return {"license": dict(license_grant)}


@router.get("/licenses/{license_id}")
async def get_license_grant(request: Request, license_id: UUID):
    """Get full details of a license grant."""
    user_id = request.state.user_id
    db = await get_db()

    license_grant = await db.fetch_one("""
        SELECT lg.*,
               re.title as entity_title, re.rights_type,
               l.name as licensee_name,
               lt.name as template_name
        FROM license_grants lg
        JOIN rights_entities re ON re.id = lg.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        LEFT JOIN licensees l ON l.id = lg.licensee_id
        LEFT JOIN license_templates lt ON lt.id = lg.template_id
        WHERE lg.id = :license_id AND wm.user_id = :user_id
    """, {"license_id": str(license_id), "user_id": user_id})

    if not license_grant:
        raise HTTPException(status_code=404, detail="License not found")

    return {"license": dict(license_grant)}


@router.post("/licenses/{license_id}/terminate")
async def terminate_license(request: Request, license_id: UUID, reason: Optional[str] = None):
    """Terminate an active license."""
    user_id = request.state.user_id
    db = await get_db()

    # Check access (admin only)
    license_grant = await db.fetch_one("""
        SELECT lg.id, lg.status
        FROM license_grants lg
        JOIN rights_entities re ON re.id = lg.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE lg.id = :license_id AND wm.user_id = :user_id
        AND wm.role IN ('owner', 'admin')
    """, {"license_id": str(license_id), "user_id": user_id})

    if not license_grant:
        raise HTTPException(status_code=404, detail="License not found or insufficient permissions")

    if license_grant["status"] != "active":
        raise HTTPException(status_code=400, detail="License is not active")

    await db.execute("""
        UPDATE license_grants
        SET status = 'terminated', updated_at = now()
        WHERE id = :license_id
    """, {"license_id": str(license_id)})

    return {"status": "terminated", "license_id": license_id}


# =============================================================================
# USAGE RECORDS
# =============================================================================

class UsageRecordCreate(BaseModel):
    usage_type: str  # training_sample, generation, api_call, etc.
    usage_count: int = 1
    usage_context: dict = {}
    reported_by: Optional[str] = None


@router.get("/licenses/{license_id}/usage")
async def list_usage_records(
    request: Request,
    license_id: UUID,
    limit: int = Query(100, le=500),
    offset: int = 0
):
    """List usage records for a license."""
    user_id = request.state.user_id
    db = await get_db()

    # Check access
    license_grant = await db.fetch_one("""
        SELECT lg.id
        FROM license_grants lg
        JOIN rights_entities re ON re.id = lg.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE lg.id = :license_id AND wm.user_id = :user_id
    """, {"license_id": str(license_id), "user_id": user_id})

    if not license_grant:
        raise HTTPException(status_code=404, detail="License not found")

    records = await db.fetch_all("""
        SELECT id, usage_type, usage_count, usage_context,
               reported_by, reported_at, billable, amount_due
        FROM usage_records
        WHERE license_grant_id = :license_id
        ORDER BY reported_at DESC
        LIMIT :limit OFFSET :offset
    """, {"license_id": str(license_id), "limit": limit, "offset": offset})

    # Get totals
    totals = await db.fetch_one("""
        SELECT
            COUNT(*) as record_count,
            SUM(usage_count) as total_usage,
            SUM(CASE WHEN billable THEN amount_due ELSE 0 END) as total_billable
        FROM usage_records
        WHERE license_grant_id = :license_id
    """, {"license_id": str(license_id)})

    return {
        "records": [dict(r) for r in records],
        "totals": dict(totals)
    }


@router.post("/licenses/{license_id}/usage")
async def report_usage(request: Request, license_id: UUID, payload: UsageRecordCreate):
    """Report usage for a license (typically from API/webhook)."""
    db = await get_db()

    # Verify license exists and is active
    license_grant = await db.fetch_one("""
        SELECT id, status, usage_tracking_enabled, pricing
        FROM license_grants
        WHERE id = :license_id AND status = 'active'
    """, {"license_id": str(license_id)})

    if not license_grant:
        raise HTTPException(status_code=404, detail="Active license not found")

    if not license_grant["usage_tracking_enabled"]:
        raise HTTPException(status_code=400, detail="Usage tracking not enabled for this license")

    # Calculate billable amount if pricing is configured
    amount_due = None
    pricing = license_grant["pricing"]
    if pricing and pricing.get("model") == "per_use":
        base_rate = pricing.get("base_rate", 0)
        amount_due = base_rate * payload.usage_count

    record = await db.fetch_one("""
        INSERT INTO usage_records (
            license_grant_id, usage_type, usage_count,
            usage_context, reported_by, billable, amount_due
        )
        VALUES (
            :license_id, :usage_type, :usage_count,
            :usage_context, :reported_by, true, :amount_due
        )
        RETURNING id, usage_type, usage_count, reported_at, amount_due
    """, {
        "license_id": str(license_id),
        "usage_type": payload.usage_type,
        "usage_count": payload.usage_count,
        "usage_context": payload.usage_context,
        "reported_by": payload.reported_by or "api",
        "amount_due": amount_due
    })

    return {"usage_record": dict(record)}
