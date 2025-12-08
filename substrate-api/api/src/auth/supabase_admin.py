"""Supabase admin client for service-role operations."""

import os
from functools import lru_cache

from supabase import create_client, Client


@lru_cache(maxsize=1)
def supabase_admin() -> Client:
    """
    Returns a Supabase client using service role key.
    Cached to reuse the same client instance.
    """
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

    if not url or not key:
        raise ValueError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables are required"
        )

    return create_client(url, key)


__all__ = ["supabase_admin"]
