"""
Job Handlers: Domain Layer
===========================

This module contains the DOMAIN LOGIC for each job type.
Handlers receive a payload and return a result - they don't know
about infrastructure (how they were triggered, where results go).

See docs/features/scheduling.md for architecture details.

To add a new job type:
1. Create a handler function
2. Register it with @JobHandlerRegistry.register('job_type')
3. The worker will automatically route jobs to your handler
"""

import logging
from typing import Any, Callable, Dict, Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class JobHandlerRegistry:
    """
    Registry for job type handlers.

    This provides a clean separation between:
    - Infrastructure (job_executor.py) - HOW jobs are claimed/completed
    - Domain (this file) - WHAT each job type does

    Handlers are pure async functions: payload -> result
    """

    _handlers: Dict[str, Callable] = {}

    @classmethod
    def register(cls, job_type: str):
        """
        Decorator to register a handler for a job type.

        Usage:
            @JobHandlerRegistry.register('scheduled_work')
            async def handle_scheduled_work(payload: dict) -> dict:
                # Do something
                return {'status': 'ok'}
        """
        def decorator(func: Callable):
            cls._handlers[job_type] = func
            logger.info(f"[JobHandlers] Registered handler for '{job_type}'")
            return func
        return decorator

    @classmethod
    async def handle(cls, job: Dict[str, Any]) -> Dict[str, Any]:
        """
        Route a job to its registered handler.

        Args:
            job: Job dict with 'job_type' and 'payload'

        Returns:
            Handler result dict

        Raises:
            ValueError: If no handler registered for job_type
        """
        job_type = job.get('job_type')
        handler = cls._handlers.get(job_type)

        if not handler:
            raise ValueError(f"No handler registered for job type: {job_type}")

        payload = job.get('payload', {})
        logger.info(f"[JobHandlers] Handling {job_type} job {job.get('id')}")

        try:
            result = await handler(payload)
            logger.info(f"[JobHandlers] Completed {job_type} job {job.get('id')}")
            return result
        except Exception as e:
            logger.error(f"[JobHandlers] Failed {job_type} job {job.get('id')}: {e}")
            raise

    @classmethod
    def get_registered_types(cls) -> list:
        """Get list of registered job types."""
        return list(cls._handlers.keys())


# ============================================================================
# JOB HANDLERS
# ============================================================================

@JobHandlerRegistry.register('scheduled_work')
async def handle_scheduled_work(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute a scheduled work recipe.

    This handler creates a work_ticket for the scheduled recipe,
    which is then picked up by the canonical_queue_processor.

    Payload:
        - schedule_id: UUID of the project_schedule
        - project_id: Project UUID
        - recipe_id: Recipe UUID
        - recipe_slug: Recipe slug for logging
        - basket_id: Basket UUID
        - recipe_parameters: Dict of recipe params
        - context_outputs: Optional context role targeting
        - triggered_at: When the job was created

    Returns:
        - work_ticket_id: Created ticket UUID
        - status: 'queued'
    """
    # Import here to avoid circular imports
    from app.utils.supabase import supabase_admin

    supabase = supabase_admin()

    basket_id = payload.get('basket_id')
    recipe_id = payload.get('recipe_id')
    recipe_slug = payload.get('recipe_slug')
    recipe_parameters = payload.get('recipe_parameters', {})
    context_outputs = payload.get('context_outputs')
    schedule_id = payload.get('schedule_id')

    logger.info(
        f"[scheduled_work] Creating work ticket for recipe={recipe_slug}, "
        f"basket={basket_id}, schedule={schedule_id}"
    )

    # Build work ticket metadata
    metadata = {
        'source': 'scheduled',
        'schedule_id': str(schedule_id) if schedule_id else None,
        'recipe_slug': recipe_slug,
        'recipe_parameters': recipe_parameters,
        'triggered_at': payload.get('triggered_at'),
    }

    # Add context outputs if present
    if context_outputs:
        metadata['context_outputs'] = context_outputs

    # Create work ticket (synchronous supabase client)
    result = supabase.table('work_tickets').insert({
        'basket_id': basket_id,
        'status': 'pending',
        'priority': 5,
        'source': 'scheduled',
        'metadata': metadata,
    }).execute()

    work_ticket_id = result.data[0].get('id') if result.data else None

    # Update schedule's last_run tracking
    if schedule_id and work_ticket_id:
        supabase.table('project_schedules').update({
            'last_run_at': datetime.utcnow().isoformat(),
            'last_run_status': 'success',
            'last_run_ticket_id': work_ticket_id,
        }).eq('id', schedule_id).execute()

    logger.info(f"[scheduled_work] Created work_ticket {work_ticket_id}")

    return {
        'work_ticket_id': work_ticket_id,
        'status': 'queued',
        'recipe_slug': recipe_slug,
    }


@JobHandlerRegistry.register('stale_refresh')
async def handle_stale_refresh(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Refresh a stale context anchor by re-running its producing recipe.

    This handler creates a work_ticket targeting the same context role,
    which will update the existing anchor block when approved.

    Payload:
        - block_id: UUID of the stale block
        - basket_id: Basket UUID
        - anchor_role: The context role (e.g., 'trend_digest')
        - recipe_id: Recipe UUID that produces this role
        - recipe_slug: Recipe slug
        - context_outputs: Context targeting config
        - triggered_at: When the job was created

    Returns:
        - work_ticket_id: Created ticket UUID
        - status: 'queued'
        - anchor_role: The role being refreshed
    """
    from app.utils.supabase import supabase_admin

    supabase = supabase_admin()

    basket_id = payload.get('basket_id')
    block_id = payload.get('block_id')
    anchor_role = payload.get('anchor_role')
    recipe_id = payload.get('recipe_id')
    recipe_slug = payload.get('recipe_slug')
    context_outputs = payload.get('context_outputs', {})

    logger.info(
        f"[stale_refresh] Refreshing {anchor_role} for basket={basket_id}, "
        f"stale_block={block_id}"
    )

    # Build work ticket metadata
    metadata = {
        'source': 'stale_refresh',
        'stale_block_id': str(block_id),
        'anchor_role': anchor_role,
        'recipe_slug': recipe_slug,
        'triggered_at': payload.get('triggered_at'),
        'context_outputs': {
            'target_context_role': anchor_role,
            'auto_promote': context_outputs.get('refresh_policy', {}).get('auto_promote', True),
        },
    }

    # Create work ticket (synchronous supabase client)
    result = supabase.table('work_tickets').insert({
        'basket_id': basket_id,
        'status': 'pending',
        'priority': 3,  # Lower priority than user-initiated
        'source': 'stale_refresh',
        'metadata': metadata,
    }).execute()

    work_ticket_id = result.data[0].get('id') if result.data else None

    logger.info(f"[stale_refresh] Created work_ticket {work_ticket_id} for {anchor_role}")

    return {
        'work_ticket_id': work_ticket_id,
        'status': 'queued',
        'anchor_role': anchor_role,
        'stale_block_id': str(block_id),
    }


@JobHandlerRegistry.register('email_notification')
async def handle_email_notification(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Send email notification (placeholder for future implementation).

    Payload:
        - recipient: Email address
        - template: Email template name
        - data: Template data

    Returns:
        - status: 'sent' or 'failed'
        - message_id: Email provider message ID
    """
    # TODO: Implement with Resend, SendGrid, or similar
    logger.info(f"[email_notification] Would send email to {payload.get('recipient')}")

    return {
        'status': 'skipped',
        'reason': 'Email service not yet implemented',
    }


@JobHandlerRegistry.register('llm_batch')
async def handle_llm_batch(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process LLM batch API results (placeholder for future implementation).

    Payload:
        - batch_id: Provider batch ID
        - provider: 'openai' or 'anthropic'
        - callback_data: Data from webhook

    Returns:
        - status: 'processed'
        - results_count: Number of results processed
    """
    # TODO: Implement when batch API is needed
    logger.info(f"[llm_batch] Would process batch {payload.get('batch_id')}")

    return {
        'status': 'skipped',
        'reason': 'LLM batch processing not yet implemented',
    }


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_all_job_types() -> list:
    """Get list of all registered job types."""
    return JobHandlerRegistry.get_registered_types()
