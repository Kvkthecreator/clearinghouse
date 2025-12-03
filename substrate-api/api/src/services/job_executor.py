"""
Job Executor: Infrastructure Layer
===================================

This module provides the infrastructure abstraction for job execution.
It handles HOW jobs are claimed and processed, NOT what they do.

The executor interface is stable and can be swapped without changing
domain logic. Current implementation uses Supabase as the job store.

See docs/features/scheduling.md for architecture details.

Future swap options:
- PostgreSQL pg_cron
- Redis + Bull
- AWS SQS
- Celery
"""

import logging
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional
import uuid

logger = logging.getLogger(__name__)


class JobExecutor(ABC):
    """
    Abstract base class for job execution strategies.

    This is the INFRASTRUCTURE interface - implementations handle
    the mechanics of job claiming, completion, and failure.

    Domain logic lives in job_handlers.py, not here.
    """

    @abstractmethod
    async def claim_jobs(
        self,
        job_types: List[str],
        limit: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Atomically claim pending jobs for processing.

        Args:
            job_types: List of job types to claim (e.g., ['scheduled_work', 'stale_refresh'])
            limit: Maximum number of jobs to claim

        Returns:
            List of claimed job dictionaries with id, job_type, payload, etc.
        """
        pass

    @abstractmethod
    async def complete_job(
        self,
        job_id: str,
        result: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Mark a job as successfully completed.

        Args:
            job_id: The job UUID
            result: Optional result data to store

        Returns:
            True if job was updated, False if not found
        """
        pass

    @abstractmethod
    async def fail_job(
        self,
        job_id: str,
        error: str
    ) -> bool:
        """
        Mark a job as failed. May schedule retry if attempts < max_attempts.

        Args:
            job_id: The job UUID
            error: Error message to record

        Returns:
            True if job was updated, False if not found
        """
        pass

    @abstractmethod
    async def check_schedules(self) -> List[Dict[str, Any]]:
        """
        Check for due schedules and create corresponding jobs.

        Returns:
            List of created jobs (schedule_id, job_id pairs)
        """
        pass

    @abstractmethod
    async def check_stale_anchors(self) -> List[Dict[str, Any]]:
        """
        Check for stale context anchors and create refresh jobs.

        Returns:
            List of created jobs (block_id, job_id pairs)
        """
        pass


class SupabaseJobExecutor(JobExecutor):
    """
    Job executor that uses Supabase as the job store.

    This implementation:
    - Uses RPC functions for atomic operations
    - Polls the jobs table for pending work
    - Handles retry logic via database functions

    Can be replaced with Redis, SQS, etc. by implementing a new executor.
    """

    def __init__(self, supabase_client, worker_id: Optional[str] = None):
        """
        Initialize the Supabase job executor.

        Args:
            supabase_client: Authenticated Supabase client
            worker_id: Unique identifier for this worker instance
        """
        self.supabase = supabase_client
        self.worker_id = worker_id or f"worker-{uuid.uuid4().hex[:8]}"
        logger.info(f"[JobExecutor] Initialized with worker_id={self.worker_id}")

    async def claim_jobs(
        self,
        job_types: List[str],
        limit: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Claim jobs using atomic RPC function.

        The database function uses SELECT ... FOR UPDATE SKIP LOCKED
        to prevent race conditions between workers.
        """
        try:
            # supabase-py client is synchronous
            result = self.supabase.rpc(
                'claim_jobs',
                {
                    'p_worker_id': self.worker_id,
                    'p_job_types': job_types,
                    'p_limit': limit
                }
            ).execute()

            jobs = result.data or []
            if jobs:
                logger.info(f"[JobExecutor] Claimed {len(jobs)} jobs: {[j['job_type'] for j in jobs]}")
            return jobs

        except Exception as e:
            logger.error(f"[JobExecutor] Failed to claim jobs: {e}")
            return []

    async def complete_job(
        self,
        job_id: str,
        result: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Mark job as completed via RPC.
        """
        try:
            # supabase-py client is synchronous
            response = self.supabase.rpc(
                'complete_job',
                {
                    'p_job_id': job_id,
                    'p_result': result
                }
            ).execute()

            success = response.data
            if success:
                logger.info(f"[JobExecutor] Completed job {job_id}")
            else:
                logger.warning(f"[JobExecutor] Job {job_id} not found or already completed")
            return success

        except Exception as e:
            logger.error(f"[JobExecutor] Failed to complete job {job_id}: {e}")
            return False

    async def fail_job(
        self,
        job_id: str,
        error: str
    ) -> bool:
        """
        Mark job as failed via RPC. Database handles retry scheduling.
        """
        try:
            # supabase-py client is synchronous
            response = self.supabase.rpc(
                'fail_job',
                {
                    'p_job_id': job_id,
                    'p_error': error[:1000]  # Truncate long errors
                }
            ).execute()

            success = response.data
            logger.warning(f"[JobExecutor] Failed job {job_id}: {error[:100]}")
            return success

        except Exception as e:
            logger.error(f"[JobExecutor] Failed to mark job {job_id} as failed: {e}")
            return False

    async def check_schedules(self) -> List[Dict[str, Any]]:
        """
        Check for due schedules and create jobs.

        This is called periodically by the worker to find schedules
        where next_run_at <= NOW() and create corresponding jobs.
        """
        try:
            # supabase-py client is synchronous
            result = self.supabase.rpc(
                'check_and_queue_due_schedules'
            ).execute()

            jobs = result.data or []
            if jobs:
                logger.info(f"[JobExecutor] Created {len(jobs)} jobs from due schedules")
            return jobs

        except Exception as e:
            logger.error(f"[JobExecutor] Failed to check schedules: {e}")
            return []

    async def check_stale_anchors(self) -> List[Dict[str, Any]]:
        """
        Check for stale context anchors and create refresh jobs.

        This is called periodically (less frequently than schedule checks)
        to find blocks where updated_at + TTL < NOW().
        """
        try:
            # supabase-py client is synchronous
            result = self.supabase.rpc(
                'check_and_queue_stale_anchors'
            ).execute()

            jobs = result.data or []
            if jobs:
                logger.info(f"[JobExecutor] Created {len(jobs)} stale refresh jobs")
            return jobs

        except Exception as e:
            logger.error(f"[JobExecutor] Failed to check stale anchors: {e}")
            return []

    async def get_job_stats(self) -> Dict[str, int]:
        """
        Get job queue statistics for monitoring.

        Returns:
            Dict with counts by status
        """
        try:
            # supabase-py client is synchronous
            result = self.supabase.table('jobs').select(
                'status',
                count='exact'
            ).execute()

            # Aggregate by status
            stats = {
                'pending': 0,
                'claimed': 0,
                'running': 0,
                'completed': 0,
                'failed': 0
            }

            # This is a simplified version - you might want a proper GROUP BY
            for row in result.data or []:
                status = row.get('status', 'unknown')
                stats[status] = stats.get(status, 0) + 1

            return stats

        except Exception as e:
            logger.error(f"[JobExecutor] Failed to get job stats: {e}")
            return {}


# Factory function for creating executor
def create_job_executor(
    supabase_client,
    worker_id: Optional[str] = None,
    executor_type: str = "supabase"
) -> JobExecutor:
    """
    Create a job executor instance.

    This factory function allows swapping executor implementations
    without changing calling code.

    Args:
        supabase_client: Authenticated Supabase client
        worker_id: Unique worker identifier
        executor_type: Type of executor ('supabase', 'redis', etc.)

    Returns:
        JobExecutor instance
    """
    if executor_type == "supabase":
        return SupabaseJobExecutor(supabase_client, worker_id)
    else:
        raise ValueError(f"Unknown executor type: {executor_type}")
