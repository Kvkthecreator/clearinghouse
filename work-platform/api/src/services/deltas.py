"""
Delta persistence service.

Note: Legacy event publishing to 'events' table has been removed.
Delta events (delta.created, delta.applied) were never consumed.
If notification is needed, use EventService.emit_app_event() instead.
"""

import sys
import os
import logging

# Add src to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from contracts.basket import BasketDelta
from repositories.delta_repository import DeltaRepository

logger = logging.getLogger(__name__)


async def persist_delta(db, delta: BasketDelta, request_id: str) -> None:
    """Persist delta to database."""
    delta_repo = DeltaRepository(db)
    await delta_repo.persist_delta(delta.dict(), request_id)
    logger.info(f"Delta {delta.delta_id} persisted for basket {delta.basket_id}")


async def list_deltas(db, basket_id: str):
    """List deltas for a basket."""
    delta_repo = DeltaRepository(db)
    return await delta_repo.list_deltas(basket_id)


async def try_apply_delta(db, basket_id: str, delta_id: str) -> bool:
    """Apply delta to basket."""
    delta_repo = DeltaRepository(db)
    success = await delta_repo.apply_delta(basket_id, delta_id)

    if success:
        logger.info(f"Delta {delta_id} applied to basket {basket_id}")

    return success
