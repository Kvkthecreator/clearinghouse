"""Health check endpoints."""
from fastapi import APIRouter, Depends
from app.deps import get_db

router = APIRouter()


@router.get("/health")
async def health():
    """Basic health check."""
    return {"status": "healthy", "service": "clearinghouse-api"}


@router.get("/health/db")
async def health_db():
    """Database connectivity check."""
    try:
        db = await get_db()
        result = await db.fetch_one("SELECT 1 as ok")
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": "disconnected", "error": str(e)}


@router.get("/health/tables")
async def health_tables():
    """Check that core tables exist."""
    try:
        db = await get_db()
        tables = await db.fetch_all("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_type = 'BASE TABLE'
            ORDER BY table_name
        """)
        table_names = [t["table_name"] for t in tables]

        required_tables = [
            "workspaces", "workspace_memberships", "catalogs",
            "rights_schemas", "rights_entities", "reference_assets",
            "proposals", "proposal_comments", "governance_rules",
            "license_templates", "licensees", "license_grants", "usage_records",
            "timeline_events"
        ]

        missing = [t for t in required_tables if t not in table_names]

        return {
            "status": "healthy" if not missing else "degraded",
            "tables": table_names,
            "required_tables": required_tables,
            "missing_tables": missing,
        }
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}
