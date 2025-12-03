from fastapi import APIRouter
from fastapi.responses import JSONResponse
from ..utils.supabase import supabase_admin
from services.job_worker import get_job_worker_status

router = APIRouter(tags=["health"])

@router.get("/health/sb-admin")
def health_sb_admin():
    """Verify service role access to Supabase."""
    try:
        sb = supabase_admin()
        # cheap call: list 1 workspace id (no data leak)
        res = sb.table("workspaces").select("id").limit(1).execute()
        return JSONResponse({"ok": True, "count": len(res.data)})
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"ok": False, "error": str(e)}
        )


@router.get("/health/jobs")
def health_jobs():
    """Get job worker status for monitoring."""
    try:
        status = get_job_worker_status()
        return JSONResponse({
            "ok": status.get("running", False),
            **status
        })
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"ok": False, "error": str(e)}
        )