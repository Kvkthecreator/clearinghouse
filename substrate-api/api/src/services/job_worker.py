"""
Job Worker: Background Processing Loop
=======================================

This module runs in the existing Render service alongside the
canonical_queue_processor. It handles:

1. Checking for due schedules (every SCHEDULE_CHECK_INTERVAL)
2. Checking for stale anchors (every STALE_CHECK_INTERVAL)
3. Processing pending jobs (every JOB_POLL_INTERVAL)

See docs/features/scheduling.md for architecture details.

Configuration via environment variables:
- JOB_POLL_INTERVAL: Seconds between job polls (default: 30)
- SCHEDULE_CHECK_INTERVAL: Seconds between schedule checks (default: 900 = 15min)
- STALE_CHECK_INTERVAL: Seconds between stale anchor checks (default: 3600 = 1hr)
- JOB_BATCH_SIZE: Max jobs to claim per poll (default: 5)
"""

import asyncio
import logging
import os
import time
from datetime import datetime
from typing import Optional

from .job_executor import JobExecutor, create_job_executor
from .job_handlers import JobHandlerRegistry, get_all_job_types

logger = logging.getLogger(__name__)


class JobWorker:
    """
    Background worker that processes jobs from the queue.

    This worker:
    - Runs as an async task in the existing Render service
    - Periodically checks for due schedules and creates jobs
    - Periodically checks for stale anchors and creates refresh jobs
    - Continuously processes pending jobs

    The worker is designed to be resilient:
    - Errors in one job don't affect others
    - Restart picks up where it left off (jobs stay in queue)
    - Multiple workers can run concurrently (atomic claiming)
    """

    def __init__(
        self,
        supabase_client,
        worker_id: Optional[str] = None,
    ):
        """
        Initialize the job worker.

        Args:
            supabase_client: Authenticated Supabase client
            worker_id: Unique identifier for this worker
        """
        self.executor = create_job_executor(supabase_client, worker_id)
        self.running = False
        self._task: Optional[asyncio.Task] = None

        # Configuration from environment
        self.job_poll_interval = int(os.getenv('JOB_POLL_INTERVAL', '30'))
        self.schedule_check_interval = int(os.getenv('SCHEDULE_CHECK_INTERVAL', '900'))
        self.stale_check_interval = int(os.getenv('STALE_CHECK_INTERVAL', '3600'))
        self.job_batch_size = int(os.getenv('JOB_BATCH_SIZE', '5'))

        # Tracking for periodic checks
        self._last_schedule_check = 0
        self._last_stale_check = 0

        # Job types to process
        self._job_types = get_all_job_types()

        logger.info(
            f"[JobWorker] Initialized with "
            f"poll_interval={self.job_poll_interval}s, "
            f"schedule_check={self.schedule_check_interval}s, "
            f"stale_check={self.stale_check_interval}s, "
            f"batch_size={self.job_batch_size}"
        )

    async def start(self):
        """
        Start the worker loop as a background task.

        Call this during application startup (e.g., in agent_server.py lifespan).
        """
        if self.running:
            logger.warning("[JobWorker] Already running")
            return

        self.running = True
        self._task = asyncio.create_task(self._run_loop())
        logger.info("[JobWorker] Started background job processing")

    async def stop(self):
        """
        Gracefully stop the worker.

        Call this during application shutdown.
        """
        if not self.running:
            return

        self.running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("[JobWorker] Stopped")

    async def _run_loop(self):
        """
        Main worker loop.

        This runs continuously, checking for:
        1. Due schedules (creates jobs)
        2. Stale anchors (creates jobs)
        3. Pending jobs (processes them)
        """
        while self.running:
            try:
                current_time = time.time()

                # Check schedules periodically
                if current_time - self._last_schedule_check >= self.schedule_check_interval:
                    await self._check_schedules()
                    self._last_schedule_check = current_time

                # Check stale anchors periodically (less frequently)
                if current_time - self._last_stale_check >= self.stale_check_interval:
                    await self._check_stale_anchors()
                    self._last_stale_check = current_time

                # Process pending jobs
                await self._process_jobs()

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"[JobWorker] Error in main loop: {e}", exc_info=True)

            # Wait before next iteration
            await asyncio.sleep(self.job_poll_interval)

    async def _check_schedules(self):
        """
        Check for due schedules and create jobs.

        This calls the database function that finds schedules where
        next_run_at <= NOW() and creates corresponding jobs.
        """
        try:
            created = await self.executor.check_schedules()
            if created:
                logger.info(f"[JobWorker] Created {len(created)} scheduled jobs")
        except Exception as e:
            logger.error(f"[JobWorker] Failed to check schedules: {e}")

    async def _check_stale_anchors(self):
        """
        Check for stale context anchors and create refresh jobs.

        This calls the database function that finds blocks where
        updated_at + TTL < NOW() and creates corresponding jobs.
        """
        try:
            created = await self.executor.check_stale_anchors()
            if created:
                logger.info(f"[JobWorker] Created {len(created)} stale refresh jobs")
        except Exception as e:
            logger.error(f"[JobWorker] Failed to check stale anchors: {e}")

    async def _process_jobs(self):
        """
        Claim and process pending jobs.

        Jobs are processed one at a time to ensure proper error handling.
        Failed jobs are retried according to their max_attempts setting.
        """
        try:
            # Claim a batch of jobs
            jobs = await self.executor.claim_jobs(
                job_types=self._job_types,
                limit=self.job_batch_size
            )

            if not jobs:
                return

            # Process each job
            for job in jobs:
                await self._process_single_job(job)

        except Exception as e:
            logger.error(f"[JobWorker] Failed to process jobs: {e}")

    async def _process_single_job(self, job: dict):
        """
        Process a single job with error handling.

        Args:
            job: Job dict from the queue
        """
        job_id = job.get('id')
        job_type = job.get('job_type')

        try:
            # Route to handler
            result = await JobHandlerRegistry.handle(job)

            # Mark as completed
            await self.executor.complete_job(job_id, result)

        except Exception as e:
            logger.error(f"[JobWorker] Job {job_id} ({job_type}) failed: {e}")
            await self.executor.fail_job(job_id, str(e))

    def get_status(self) -> dict:
        """
        Get worker status for health checks.

        Returns:
            Status dict with running state and last check times
        """
        return {
            'running': self.running,
            'worker_id': self.executor.worker_id if hasattr(self.executor, 'worker_id') else 'unknown',
            'last_schedule_check': datetime.fromtimestamp(self._last_schedule_check).isoformat()
                if self._last_schedule_check else None,
            'last_stale_check': datetime.fromtimestamp(self._last_stale_check).isoformat()
                if self._last_stale_check else None,
            'job_types': self._job_types,
            'config': {
                'job_poll_interval': self.job_poll_interval,
                'schedule_check_interval': self.schedule_check_interval,
                'stale_check_interval': self.stale_check_interval,
                'job_batch_size': self.job_batch_size,
            }
        }


# ============================================================================
# GLOBAL WORKER INSTANCE
# ============================================================================

_job_worker: Optional[JobWorker] = None


async def start_job_worker(supabase_client, worker_id: Optional[str] = None):
    """
    Start the global job worker instance.

    Call this during application startup.
    """
    global _job_worker

    if _job_worker is not None:
        logger.warning("[JobWorker] Worker already exists, stopping first")
        await stop_job_worker()

    _job_worker = JobWorker(supabase_client, worker_id)
    await _job_worker.start()
    return _job_worker


async def stop_job_worker():
    """
    Stop the global job worker instance.

    Call this during application shutdown.
    """
    global _job_worker

    if _job_worker is not None:
        await _job_worker.stop()
        _job_worker = None


def get_job_worker() -> Optional[JobWorker]:
    """
    Get the global job worker instance.

    Returns None if worker hasn't been started.
    """
    return _job_worker


def get_job_worker_status() -> dict:
    """
    Get job worker status for health checks.
    """
    if _job_worker is None:
        return {'running': False, 'error': 'Worker not initialized'}
    return _job_worker.get_status()
