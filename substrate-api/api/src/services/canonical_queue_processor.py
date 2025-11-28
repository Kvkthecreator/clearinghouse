"""
Canonical Queue Processor - YARNNN Canon v2.3 Compliant

Orchestrates substrate pipeline agents (P0-P2) for governed substrate mutations
while respecting Sacred Principles and substrate/artifact boundaries.
Integrates with Universal Work Tracker for comprehensive status visibility.

Canon v2.3 Pipeline Processing Sequence:
1. P0 Capture: Raw dump ingestion (direct, no governance)
2. P1 Substrate: Block/context creation (governed proposals)
3. P2 Graph: Relationship mapping (governed proposals)  
(P3 Reflection: Direct artifact operations via /api/reflections)
(P4 Document Composition: Direct artifact operations via /api/documents)
"""
# V3.0 DEPRECATION NOTICE:
# This file contains references to context_items table which was merged into blocks table.
# Entity blocks are now identified by semantic_type='entity'.
# This file is legacy/supporting code - update if actively maintained.


import asyncio
import logging
import math
import os
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from uuid import uuid4, UUID

from app.agents.pipeline import (
    P0CaptureAgent,
    P1SubstrateAgent,
    P3ReflectionAgent
)
from app.agents.pipeline.composition_agent_v2 import P4CompositionAgent, CompositionRequest
from app.agents.pipeline.capture_agent import DumpIngestionRequest
from app.agents.pipeline.improved_substrate_agent import ImprovedP1SubstrateAgent
from app.agents.pipeline.reflection_agent import ReflectionComputationRequest
from app.agents.pipeline.governance_processor import GovernanceDumpProcessor
from infra.utils.supabase_client import supabase_admin_client as supabase
from contracts.basket import BasketDelta, BasketChangeRequest
from services.clock import now_iso
from services.universal_work_tracker import universal_work_tracker
from services.events import EventService

logger = logging.getLogger("uvicorn.error")


class CanonicalQueueProcessor:
    """
    Canonical queue processor implementing YARNNN Canon v2.1 pipeline boundaries.
    
    This processor orchestrates P0-P3 agents in strict sequence while maintaining
    Sacred Principles and pipeline boundaries. Integrates with Universal Work Tracker
    for comprehensive status visibility across all async operations.
    """
    
    def __init__(self, worker_id: Optional[str] = None, poll_interval: int = 10):
        if not supabase:
            raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY required for canonical queue processing")
        
        self.worker_id = worker_id or f"canonical-worker-{uuid4().hex[:8]}"
        self.poll_interval = poll_interval
        self.running = False
        
        # Initialize canonical pipeline agents
        self.p0_capture = P0CaptureAgent()
        self.p1_governance = GovernanceDumpProcessor()  # Canonical governance with quality extraction
        self.p3_reflection = P3ReflectionAgent()
        self.p4_composition = P4CompositionAgent()  # Document composition

        # Note: P2 (Graph/Relationships) removed in Canon v3.1 - replaced by Neural Map
        
        # Note: Always use improved extraction (no feature flag needed)
        
        logger.info(f"Canonical Queue Processor initialized: {self.worker_id}")
        
    async def start(self):
        """Start the canonical queue processing loop."""
        self.running = True
        logger.info(f"Starting Canonical Queue Processor: {self.worker_id}")
        
        while self.running:
            try:
                # Claim work from queue (handles all work types now)
                queue_entries = await self._claim_work()
                
                if queue_entries:
                    logger.info(f"Claimed {len(queue_entries)} work items for canonical processing")
                    
                    # Process each claimed work item based on work_type
                    for entry in queue_entries:
                        try:
                            work_type = entry.get('work_type', 'P1_SUBSTRATE')  # Default for legacy entries

                            if work_type in ['P0_CAPTURE', 'P1_SUBSTRATE']:
                                # Traditional dump-based processing
                                await self._process_dump_canonically(entry)
                            elif work_type == 'P2_GRAPH':
                                # P2_GRAPH deprecated in Canon v3.1 - mark as completed
                                logger.info(f"Skipping deprecated P2_GRAPH work: {entry.get('work_id')}")
                                await self._mark_completed(entry['work_id'], {
                                    "status": "deprecated",
                                    "message": "P2 Graph removed in Canon v3.1 - use Neural Map for visualization"
                                })
                            # P3_REFLECTION removed - now direct artifact operations via /api/reflections
                            # P4_COMPOSE_NEW and P4_RECOMPOSE removed - now direct artifact operations via /api/documents
                            else:
                                # Governance-only items like MANUAL_EDIT are not processed here.
                                # Return the entry to pending to be handled by governance/proposal executors.
                                logger.info(f"Skipping non-pipeline work type: {work_type} (queue_id={entry.get('id')})")
                                try:
                                    await self._update_queue_state(entry['id'], 'pending')
                                except Exception:
                                    pass
                                continue
                        except Exception as e:
                            logger.exception(f"Work processing failed for {entry.get('work_id', entry['id'])}: {e}")
                            await self._mark_failed(entry['id'], str(e))
                else:
                    # No work available, wait before next poll
                    await asyncio.sleep(self.poll_interval)
                    
            except Exception as e:
                logger.exception(f"Canonical queue processing error: {e}")
                await asyncio.sleep(self.poll_interval)
    
    async def stop(self):
        """Stop the canonical queue processing loop."""
        self.running = False
        logger.info(f"Stopping Canonical Queue Processor: {self.worker_id}")

    def _get_dump_word_count(self, dump_id: UUID) -> int:
        """Fetch dump body and return approximate word count."""
        try:
            response = (
                supabase.table("raw_dumps")
                .select("body_md,text_dump")
                .eq("id", str(dump_id))
                .limit(1)
                .execute()
            )
            if not response.data:
                return 0
            record = response.data[0] if isinstance(response.data, list) else response.data
            body = (record.get("body_md") or record.get("text_dump") or "").strip()
            if not body:
                return 0
            return len(body.split())
        except Exception as exc:
            logger.warning(f"Failed to load dump content for {dump_id}: {exc}")
            return 0

    def _estimate_block_cap(self, word_count: int, dumps_count: int) -> int:
        """Estimate a safe block cap based on total content size and batch size."""
        if word_count <= 40:
            base = 2
        elif word_count <= 120:
            base = 4
        elif word_count <= 300:
            base = 6
        elif word_count <= 600:
            base = 10
        else:
            base = min(25, math.ceil(word_count / 120))

        base = max(base, dumps_count)
        return max(2, min(25, base))
    
    async def process_basket_work(self, basket_id: str, work_req, workspace_id: str) -> BasketDelta:
        """Process BasketWorkRequest through canonical pipeline."""
        logger.info(f"Processing basket work request for basket {basket_id} (canonical)")
        
        # For now, return a placeholder delta indicating canonical processing is queued
        # In the future, this could trigger immediate processing or queue the work
        return BasketDelta(
            delta_id=str(uuid4()),
            basket_id=basket_id,
            summary="Canonical processing queued",
            changes=[],
            recommended_actions=[],
            explanations=[{"by": "canonical_queue_processor", "text": "Work request queued for canonical pipeline processing"}],
            confidence=0.8,
            created_at=now_iso(),
        )
    
    async def process_basket_change(self, basket_id: str, req: BasketChangeRequest, workspace_id: str) -> BasketDelta:
        """Process legacy BasketChangeRequest through canonical pipeline."""
        logger.info(f"Processing basket change request for basket {basket_id} (canonical)")
        
        # For now, return a placeholder delta indicating canonical processing is queued
        # In the future, this could trigger immediate processing or queue the work
        return BasketDelta(
            delta_id=str(uuid4()),
            basket_id=basket_id,
            summary="Canonical processing queued",
            changes=[],
            recommended_actions=[],
            explanations=[{"by": "canonical_queue_processor", "text": "Change request queued for canonical pipeline processing"}],
            confidence=0.8,
            created_at=now_iso(),
        )
    
    async def _claim_work(self, limit: int = 5) -> List[Dict[str, Any]]:
        """Atomically claim work from the queue (all work types)."""
        try:
            response = supabase.rpc(
                'fn_claim_pipeline_work',
                {
                    'p_worker_id': self.worker_id,
                    'p_limit': limit,
                    'p_stale_after_minutes': 5
                }
            ).execute()
            
            if response.data:
                logger.info(f"Successfully claimed {len(response.data)} work items")
                return response.data
            else:
                return []
            
        except Exception as e:
            logger.error(f"Failed to claim work: {e}")
            return []
    
    async def _process_dump_canonically(self, queue_entry: Dict[str, Any]):
        """
        Process dump through canonical pipeline sequence (P0 → P1 → P2 → P3).
        
        Sacred Principles enforced:
        1. Capture is Sacred: P0 only processes existing dumps
        2. All Substrates are Peers: P1 treats all substrate types equally
        3. Narrative is Deliberate: P4 not triggered in queue processing
        4. Agent Intelligence is Mandatory: All pipeline processing required
        """
        # Normalize IDs: queue entries may already contain UUID objects depending on client/driver
        def _to_uuid(val):
            if isinstance(val, UUID):
                return val
            return UUID(str(val))

        dump_id = _to_uuid(queue_entry['dump_id'])
        basket_id = _to_uuid(queue_entry['basket_id'])
        workspace_id = _to_uuid(queue_entry['workspace_id'])
        queue_id = queue_entry['id']
        
        logger.info(f"Starting canonical processing: dump_id={dump_id}")
        
        # Emit job started event
        try:
            EventService.emit_job_started(
                workspace_id=str(workspace_id),
                job_id=str(queue_id),
                job_name="canonical.process",
                message=f"Started canonical processing for dump {dump_id}",
                basket_id=str(basket_id),
                correlation_id=queue_entry.get('correlation_id')
            )
        except Exception as e:
            logger.warning(f"Failed to emit job started notification: {e}")
        
        try:
            # Mark as processing
            await self._update_queue_state(queue_id, 'processing')
            
            # P0 CAPTURE: Process dump ingestion (already done, but validate)
            # Note: P0 work was done when dump was created, but we validate here
            await self._validate_p0_capture(dump_id, workspace_id)
            logger.info(f"P0 Capture validated for dump {dump_id}")
            
            # Determine heuristic block cap based on dump content
            dump_word_counts = {str(dump_id): self._get_dump_word_count(dump_id)}
            block_cap = self._estimate_block_cap(dump_word_counts[str(dump_id)], 1)
            
            # P1 GOVERNANCE: Create proposals using comprehensive review or single dump processing
            # Sacred Rule: All substrate mutations flow through governed proposals
            batch_dumps = await self._get_batch_group(dump_id)
            
            # If batch mode detected, include additional dumps in heuristic cap
            if len(batch_dumps) > 1:
                for sibling_dump in batch_dumps:
                    if sibling_dump == str(dump_id):
                        continue
                    dump_word_counts[sibling_dump] = self._get_dump_word_count(_to_uuid(sibling_dump))
                total_words = sum(dump_word_counts.values())
                block_cap = self._estimate_block_cap(total_words, len(batch_dumps))
            
            # Use canonical governance processor with quality extraction
            if len(batch_dumps) > 1:
                governance_result = await self.p1_governance.process_batch_dumps(
                    dump_ids=[_to_uuid(did) for did in batch_dumps],
                    basket_id=basket_id,
                    workspace_id=workspace_id,
                    max_blocks=block_cap
                )
                logger.info(
                    "Using canonical governance batch mode (%s dumps, max_blocks=%s)",
                    len(batch_dumps),
                    block_cap
                )
            else:
                governance_result = await self.p1_governance.process_dump(
                    dump_id=dump_id,
                    basket_id=basket_id,
                    workspace_id=workspace_id,
                    max_blocks=block_cap
                )
                logger.info(
                    "Using canonical governance (quality extraction) for dump %s (max_blocks=%s)",
                    dump_id,
                    block_cap
                )
            
            logger.info(
                f"P1 Governance completed: {governance_result['proposals_created']} proposals created, "
                f"confidence: {governance_result.get('confidence', 'unknown')}"
            )
            
            # Skip P2/P3 if no proposals were created
            if governance_result['proposals_created'] == 0:
                logger.info("Skipping P2/P3 - no substrate proposals generated")
                await self._update_queue_state(queue_id, 'completed')
                return
            
            # P2/P3 deferred until proposals are approved
            # In governance workflow, substrate doesn't exist until approval
            # P2 Graph and P3 Reflection will run on approved substrate via cascade events
            logger.info("P2/P3 deferred - proposals must be approved before relationship mapping and reflection")
            
            # Mark as completed with work result
            work_result = {
                'proposals_created': governance_result['proposals_created'],
                'confidence': governance_result.get('confidence', 0.0),
                'summary': f"P1 governance completed: {governance_result['proposals_created']} proposals"
            }
            
            # Update universal work tracker if work_id exists
            if queue_entry.get('work_id'):
                await universal_work_tracker.complete_work(
                    queue_entry['work_id'], 
                    work_result,
                    'P1_governance_completed'
                )
            
            await self._update_queue_state(queue_id, 'completed')
            
            logger.info(f"Canonical processing completed successfully for dump {dump_id}")
            
            # Emit job succeeded event
            try:
                EventService.emit_job_succeeded(
                    workspace_id=str(workspace_id),
                    job_id=str(queue_id),
                    job_name="canonical.process",
                    message=f"Canonical processing completed successfully for dump {dump_id}",
                    basket_id=str(basket_id),
                    correlation_id=queue_entry.get('correlation_id'),
                    payload={"dump_id": str(dump_id), "result": work_result}
                )
            except Exception as e:
                logger.warning(f"Failed to emit job success notification: {e}")
            
        except Exception as e:
            logger.exception(f"Canonical processing failed for dump {dump_id}: {e}")
            
            # Update universal work tracker for failure
            if queue_entry.get('work_id'):
                await universal_work_tracker.fail_work(
                    queue_entry['work_id'],
                    str(e)
                )
            
            await self._mark_failed(queue_id, str(e))
            
            # Emit job failed event
            try:
                EventService.emit_job_failed(
                    workspace_id=str(workspace_id),
                    job_id=str(queue_id),
                    job_name="canonical.process",
                    message=f"Canonical processing failed for dump {dump_id}",
                    basket_id=str(basket_id),
                    correlation_id=queue_entry.get('correlation_id'),
                    error=str(e)
                )
            except Exception as notify_error:
                logger.warning(f"Failed to emit job failure notification: {notify_error}")
            
            raise
    
    # P4 composition methods removed - now direct artifact operations per Canon v2.3
    # Document composition happens via /api/documents/compose and /api/documents/[id]/recompose

    # P2 Graph processing removed in Canon v3.1 - replaced by Neural Map (client-side visualization)
    
    async def _get_batch_group(self, dump_id: str) -> List[str]:
        """
        Get batch group for Share Updates comprehensive processing.
        
        Looks for dumps created within same time window with batch metadata
        to support comprehensive multi-dump analysis.
        """
        try:
            # Check if dump has batch metadata indicating Share Updates origin
            dump_response = supabase.table("raw_dumps").select(
                "id,source_meta,created_at"
            ).eq("id", dump_id).single().execute()
            
            if not dump_response.data:
                return [dump_id]  # Single dump fallback
                
            dump = dump_response.data
            source_meta = dump.get("source_meta", {})
            
            # Check for batch processing metadata
            batch_id = source_meta.get("batch_id")
            if not batch_id:
                return [dump_id]  # Single dump
                
            # Find all dumps in the same batch
            batch_response = supabase.table("raw_dumps").select("id").eq(
                "source_meta->>batch_id", batch_id
            ).order("created_at").execute()
            
            if batch_response.data:
                return [d["id"] for d in batch_response.data]
            else:
                return [dump_id]  # Fallback to single dump
                
        except Exception as e:
            logger.warning(f"Failed to get batch group for dump {dump_id}: {e}")
            return [dump_id]  # Safe fallback
    
    async def _validate_p0_capture(self, dump_id: UUID, workspace_id: UUID):
        """
        Validate that P0 Capture was completed properly.
        P0 should have created the raw_dump with proper content.
        """
        try:
            dump_resp = supabase.table("raw_dumps").select(
                "id,body_md,file_url,source_meta,workspace_id,basket_id"
            ).eq("id", str(dump_id)).eq("workspace_id", str(workspace_id)).single().execute()
            
            if not dump_resp.data:
                raise ValueError(f"P0 Capture validation failed: dump {dump_id} not found")
            
            dump = dump_resp.data
            if not dump.get("body_md") and not dump.get("file_url"):
                raise ValueError(f"P0 Capture validation failed: dump {dump_id} has no content")
                
            logger.info(f"P0 Capture validation passed for dump {dump_id}")
            
        except Exception as e:
            logger.error(f"P0 Capture validation failed: {e}")
            raise
    
    async def _update_queue_state(self, queue_id: str, state: str, error: Optional[str] = None):
        """Update queue entry state."""
        try:
            supabase.rpc('fn_update_queue_state', {
                'p_id': queue_id,
                'p_state': state,
                'p_error': error
            }).execute()
        except Exception as e:
            logger.error(f"Failed to update queue state for {queue_id}: {e}")
    
    async def _mark_failed(self, queue_id: str, error: str):
        """Mark queue entry as failed."""
        await self._update_queue_state(queue_id, 'failed', error)
    
    def get_processor_info(self) -> Dict[str, Any]:
        """Get canonical processor information."""
        return {
            "processor_name": "CanonicalQueueProcessor",
            "worker_id": self.worker_id,
            "canon_version": "v2.3",
            "pipeline_agents": {
                "P0_CAPTURE": self.p0_capture.get_agent_info(),
                "P1_GOVERNANCE": self.p1_governance.get_agent_info()
                # P2_GRAPH removed in Canon v3.1 - replaced by Neural Map
                # P3_REFLECTION removed - now direct artifact operations via /api/reflections
                # P4_COMPOSITION removed - now direct artifact operations via /api/documents
            },
            "processing_sequence": ["P0_CAPTURE", "P1_GOVERNANCE", "P2_DEFERRED"],
            "sacred_principles": [
                "Capture is Sacred",
                "All Substrates are Peers",
                "Narrative is Deliberate", 
                "Agent Intelligence is Mandatory"
            ],
            "status": "running" if self.running else "stopped"
        }
    
    # P4 document composition methods removed - now direct artifact operations per Canon v2.3
    # New documents: POST /api/documents/compose
    # Recomposition: POST /api/documents/[id]/recompose


# Global canonical processor instance for lifecycle management  
_canonical_processor: Optional[CanonicalQueueProcessor] = None


async def start_canonical_queue_processor():
    """Start the global canonical queue processor."""
    global _canonical_processor
    if _canonical_processor is None:
        _canonical_processor = CanonicalQueueProcessor()
        asyncio.create_task(_canonical_processor.start())
        logger.info("Canonical queue processor started - Canon v2.1 compliant")


async def stop_canonical_queue_processor():
    """Stop the global canonical queue processor."""
    global _canonical_processor
    if _canonical_processor:
        await _canonical_processor.stop()
        _canonical_processor = None
        logger.info("Canonical queue processor stopped")


async def get_canonical_queue_health() -> Dict[str, Any]:
    """Get canonical queue health metrics."""
    try:
        # Get basic queue health from database
        response = supabase.rpc('fn_queue_health').execute()
        queue_stats = response.data or []
        
        # Get processor information
        processor_info = _canonical_processor.get_processor_info() if _canonical_processor else {
            "processor_name": "CanonicalQueueProcessor",
            "status": "not_running"
        }
        
        return {
            "status": "healthy",
            "canon_version": "v2.1",
            "queue_stats": queue_stats,
            "processor_info": processor_info,
            "pipeline_boundaries_enforced": True,
            "sacred_principles_active": True
        }
        
    except Exception as e:
        logger.error(f"Failed to get canonical queue health: {e}")
        return {
            "status": "unhealthy",
            "canon_version": "v2.1",
            "error": str(e),
            "processor_running": False
        }
