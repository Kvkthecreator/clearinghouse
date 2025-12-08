from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timezone

from fastapi import HTTPException

from auth.supabase_admin import supabase_admin

log = logging.getLogger("uvicorn.error")


def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def verify_integration_token(token: str) -> dict:
    """Validate an integration token against the database."""

    sb = supabase_admin()
    token_hash = _hash_token(token)
    resp = (
        sb.table("integration_tokens")
        .select("id, user_id, workspace_id, revoked_at")
        .eq("token_hash", token_hash)
        .maybe_single()
        .execute()
    )

    # Handle None response (can happen if Supabase client errors)
    if resp is None or not hasattr(resp, 'data'):
        log.warning("Integration token query returned invalid response")
        raise HTTPException(status_code=401, detail="Invalid integration token")

    record = resp.data
    if not record or record.get("revoked_at"):
        log.debug("Integration token invalid or revoked")
        raise HTTPException(status_code=401, detail="Invalid integration token")

    # Update last_used_at
    try:
        sb.table("integration_tokens").update({
            "last_used_at": datetime.now(timezone.utc).isoformat()
        }).eq("id", record["id"]).execute()
    except Exception as exc:  # pragma: no cover - best effort
        log.warning("Failed to update integration token usage: %s", exc)

    return {
        "id": record["id"],
        "user_id": record["user_id"],
        "workspace_id": record["workspace_id"],
        "token_type": "integration",
    }


__all__ = ["verify_integration_token"]
