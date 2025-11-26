"""Work supervision orchestrator for work sessions.

⚠️ ARCHITECTURE NOTE: SEPARATED GOVERNANCE (Not Unified)

YARNNN uses SEPARATED governance architecture (as of 2025-11-19):
- **Work Supervision** (this module): Reviews work_outputs quality in work-platform
- **Substrate Governance**: Independent P1 proposals pipeline in substrate-API

CURRENT STATE:
- ✅ Work quality assessment (review work sessions and outputs)
- ❌ Substrate mutation (INTENTIONALLY DISABLED - substrate has its own governance)

FUTURE BRIDGE (Deferred):
- Approved work_outputs MAY feed into substrate proposals (not automatic)
- See: docs/canon/YARNNN_PLATFORM_CANON_V4.md - Section on Separated Governance
- See: docs/archive/legacy-unified-governance/README.md - Why unified approach was deprecated

This module provides work supervision only. Substrate changes go through substrate-API's
P1 governance pipeline (semantic dedup, quality validation, proposals).
"""

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID

from pydantic import BaseModel
from supabase import Client

from app.models.block import Block
from app.models.document import Document
from app.work.models import (
    WorkTicket,
    WorkOutput,
    WorkOutputType,
    WorkOutputStatus,
    WorkContextMutation,
    WorkMutationType,
    SubstrateType,
    RiskLevel,
)


class ArtifactDecision(str, Enum):
    """Decision for individual output."""

    APPLY_TO_SUBSTRATE = "apply_to_substrate"
    SAVE_AS_DRAFT = "save_as_draft"
    REJECT = "reject"


class WorkReviewDecision(BaseModel):
    """User's review decision for work session."""

    work_quality: str  # 'approved' or 'rejected'
    feedback: Optional[str] = None
    outputs: Dict[UUID, ArtifactDecision]  # per-output decisions
    output_feedback: Dict[UUID, str] = {}  # optional feedback per output


class WorkReviewResult(BaseModel):
    """Result of work review."""

    status: str  # 'approved', 'rejected', or 'partial'
    reason: Optional[str] = None
    outputs_applied: int
    substrate_mutations: List[UUID]
    rejected_outputs: List[UUID] = []


class UnifiedApprovalOrchestrator:
    """
    Orchestrates work supervision for work sessions.

    ⚠️ LEGACY NAME: "UnifiedApprovalOrchestrator" is kept for backward compatibility,
    but this is now WORK SUPERVISION only (not unified governance).

    CURRENT RESPONSIBILITIES:
    1. Work quality assessment (approve/reject work outputs)
    2. Output status management (approved, rejected, pending_review)

    INTENTIONALLY EXCLUDED:
    - Substrate mutations (handled by substrate-API's P1 governance)
    - Block creation (must go through proposals)
    - Document creation (architecture TBD)

    See docs/canon/YARNNN_PLATFORM_CANON_V4.md for separated governance architecture.
    """

    def __init__(self, db: Client):
        """Initialize orchestrator with database client."""
        self.db = db

    async def review_work_ticket(
        self,
        work_ticket_id: UUID,
        user_id: UUID,
        decision: WorkReviewDecision,
    ) -> WorkReviewResult:
        """
        Review work session and apply approved outputs to substrate.

        Args:
            work_ticket_id: Work session to review
            user_id: User performing review
            decision: Review decision

        Returns:
            WorkReviewResult with outcome details
        """
        # Fetch session and outputs
        session = await self._get_work_ticket(work_ticket_id)
        outputs = await self._get_outputs(work_ticket_id)

        # Step 1: Work Quality Assessment
        if decision.work_quality != "approved":
            await self._reject_work_ticket(session, decision.feedback, user_id)
            return WorkReviewResult(
                status="rejected",
                reason=decision.feedback or "Work quality did not meet standards",
                outputs_applied=0,
                substrate_mutations=[],
                rejected_outputs=[a.id for a in outputs],
            )

        # Step 2: Per-Artifact Processing
        applied_outputs = []
        rejected_outputs = []
        substrate_mutations = []

        for output in outputs:
            output_decision = decision.outputs.get(
                output.id, ArtifactDecision.APPLY_TO_SUBSTRATE
            )

            if output_decision == ArtifactDecision.APPLY_TO_SUBSTRATE:
                # Apply to substrate based on output type
                substrate_id = await self._apply_output_to_substrate(
                    output, session, user_id
                )
                if substrate_id:
                    applied_outputs.append(output.id)
                    substrate_mutations.append(substrate_id)

            elif output_decision == ArtifactDecision.SAVE_AS_DRAFT:
                # Mark approved but don't apply to substrate
                await self._update_output_status(
                    output.id,
                    WorkOutputStatus.APPROVED,
                    user_id,
                    decision.output_feedback.get(output.id),
                )
                applied_outputs.append(output.id)

            elif output_decision == ArtifactDecision.REJECT:
                # Reject output
                await self._update_output_status(
                    output.id,
                    WorkOutputStatus.REJECTED,
                    user_id,
                    decision.output_feedback.get(output.id),
                )
                rejected_outputs.append(output.id)

        # Step 3: Update Session Status
        await self._complete_work_ticket(
            session,
            len(applied_outputs) > 0,
            user_id,
        )

        # Step 4: Emit Timeline Events
        await self._emit_work_completion_event(
            session, applied_outputs, substrate_mutations
        )

        return WorkReviewResult(
            status="approved" if len(applied_outputs) > 0 else "rejected",
            outputs_applied=len(applied_outputs),
            substrate_mutations=substrate_mutations,
            rejected_outputs=rejected_outputs,
        )

    async def _apply_output_to_substrate(
        self,
        output: WorkOutput,
        session: WorkTicket,
        user_id: UUID,
    ) -> Optional[UUID]:
        """
        Apply output to substrate based on type.

        ⚠️ NOT IMPLEMENTED: This method bypasses substrate governance (proposals)
        and directly creates blocks, which violates the substrate purity principle.

        TODO (Future Implementation):
        1. Submit approved outputs to substrate-api as proposals
        2. Let substrate governance (P1) validate and create blocks
        3. Handle semantic deduplication and quality checks
        4. Track proposal status and notify work-platform of results

        For now, this raises NotImplementedError to prevent governance violations.
        """
        raise NotImplementedError(
            "Substrate mutations from work-platform are not yet implemented. "
            "This functionality needs to be designed to work with substrate "
            "governance (proposals) rather than bypassing it. "
            "See: docs/architecture/GOVERNANCE_SEPARATION_REFACTOR_PLAN.md"
        )

        # DISABLED CODE (kept for reference):
        # if output.output_type == WorkOutputType.BLOCK_PROPOSAL:
        #     return await self._create_block_from_output(output, session, user_id)
        # elif output.output_type == WorkOutputType.BLOCK_UPDATE:
        #     return await self._supersede_block_from_output(output, session, user_id)
        # elif output.output_type == WorkOutputType.DOCUMENT_CREATION:
        #     return await self._create_document_from_output(output, session, user_id)
        # elif output.output_type == WorkOutputType.EXTERNAL_DELIVERABLE:
        #     await self._store_external_output(output)
        #     return None
        # return None

    async def _create_block_from_output(
        self,
        output: WorkOutput,
        session: WorkTicket,
        user_id: UUID,
    ) -> UUID:
        """
        ⚠️ DISABLED: Direct block creation bypasses substrate governance.

        PROBLEM: This method creates blocks directly with state="ACCEPTED",
        which bypasses:
        - P1 proposal governance
        - Semantic duplicate detection
        - Quality validation
        - Merge detection

        This violates the substrate purity principle that ALL blocks must be
        created via proposals.

        TODO (Future): Replace with substrate proposal submission.
        """
        raise NotImplementedError(
            "Direct block creation is disabled. Must go through substrate proposals."
        )

        # DISABLED CODE - DO NOT UNCOMMENT WITHOUT FIXING GOVERNANCE BYPASS
        # # Extract block data from output content
        # block_data = {
        #     "basket_id": str(session.basket_id),
        #     "workspace_id": str(session.workspace_id),
        #     "content": output.content.get("content"),
        #     "semantic_type": output.content.get("semantic_type", "general"),
        #     "state": "ACCEPTED",  # ❌ BYPASSES PROPOSALS!
        #     "scope": output.content.get("scope", "BASKET"),
        #     "version": 1,
        #     "metadata": {
        #         "created_from_work_ticket": str(session.id),
        #         "created_from_output": str(output.id),
        #         "agent_confidence": output.agent_confidence,
        #         "agent_reasoning": output.agent_reasoning,
        #     },
        # }
        #
        # # Insert block
        # result = self.db.table("blocks").insert(block_data).execute()
        # block_id = UUID(result.data[0]["id"])
        #
        # # Update output with block link
        # await self._update_output(
        #     output.id,
        #     {
        #         "becomes_block_id": str(block_id),
        #         "status": WorkOutputStatus.APPLIED_TO_SUBSTRATE.value,
        #         "applied_at": datetime.utcnow().isoformat(),
        #         "reviewed_by_user_id": str(user_id),
        #         "reviewed_at": datetime.utcnow().isoformat(),
        #         "review_decision": "approved",
        #     },
        # )
        #
        # # Log substrate mutation
        # await self._log_context_mutation(
        #     work_ticket_id=session.id,
        #     output_id=output.id,
        #     mutation_type=WorkMutationType.BLOCK_CREATED,
        #     substrate_id=block_id,
        #     substrate_type=SubstrateType.BLOCK,
        #     after_state=block_data,
        #     risk_level=output.risk_level,
        # )
        #
        # return block_id

    async def _supersede_block_from_output(
        self,
        output: WorkOutput,
        session: WorkTicket,
        user_id: UUID,
    ) -> UUID:
        """
        ⚠️ DISABLED: Direct block superseding bypasses substrate governance.

        TODO (Future): Replace with substrate proposal submission.
        """
        raise NotImplementedError(
            "Direct block superseding is disabled. Must go through substrate proposals."
        )

    async def _create_document_from_output(
        self,
        output: WorkOutput,
        session: WorkTicket,
        user_id: UUID,
    ) -> UUID:
        """
        ⚠️ DISABLED: Direct document creation bypasses substrate governance.

        TODO (Future): Determine if documents should go through proposals
        or if they can be created directly (documents != memory blocks).
        """
        raise NotImplementedError(
            "Direct document creation is disabled pending architecture decision."
        )

    async def _store_external_output(self, output: WorkOutput) -> None:
        """Store reference to external output (no substrate impact)."""
        await self._update_output(
            output.id,
            {
                "status": WorkOutputStatus.APPROVED.value,
                "applied_at": datetime.utcnow().isoformat(),
            },
        )

    async def _log_context_mutation(
        self,
        work_ticket_id: UUID,
        output_id: UUID,
        mutation_type: WorkMutationType,
        substrate_id: UUID,
        substrate_type: SubstrateType,
        after_state: Dict[str, Any],
        before_state: Optional[Dict[str, Any]] = None,
        risk_level: Optional[RiskLevel] = None,
    ) -> None:
        """Log substrate mutation to work_context_mutations."""
        mutation_data = {
            "work_ticket_id": str(work_ticket_id),
            "output_id": str(output_id),
            "mutation_type": mutation_type.value,
            "substrate_id": str(substrate_id),
            "substrate_type": substrate_type.value,
            "before_state": before_state,
            "after_state": after_state,
            "mutation_risk": risk_level.value if risk_level else None,
        }
        self.db.table("work_context_mutations").insert(mutation_data).execute()

    async def _update_output_status(
        self,
        output_id: UUID,
        status: WorkOutputStatus,
        user_id: UUID,
        feedback: Optional[str] = None,
    ) -> None:
        """Update output status."""
        await self._update_output(
            output_id,
            {
                "status": status.value,
                "reviewed_by_user_id": str(user_id),
                "reviewed_at": datetime.utcnow().isoformat(),
                "review_feedback": feedback,
            },
        )

    async def _update_output(self, output_id: UUID, updates: Dict[str, Any]) -> None:
        """Update output in database."""
        self.db.table("work_outputs").update(updates).eq("id", str(output_id)).execute()

    async def _reject_work_ticket(
        self, session: WorkTicket, reason: Optional[str], user_id: UUID
    ) -> None:
        """Mark work session as rejected."""
        self.db.table("work_tickets").update(
            {
                "status": "rejected",
                "ended_at": datetime.utcnow().isoformat(),
                "metadata": {
                    **(session.metadata or {}),
                    "rejection_reason": reason,
                    "rejected_by": str(user_id),
                    "rejected_at": datetime.utcnow().isoformat(),
                },
            }
        ).eq("id", str(session.id)).execute()

    async def _complete_work_ticket(
        self, session: WorkTicket, approved: bool, user_id: UUID
    ) -> None:
        """Mark work session as complete."""
        self.db.table("work_tickets").update(
            {
                "status": "approved" if approved else "rejected",
                "ended_at": datetime.utcnow().isoformat(),
                "metadata": {
                    **(session.metadata or {}),
                    "approved_by": str(user_id),
                    "approved_at": datetime.utcnow().isoformat(),
                },
            }
        ).eq("id", str(session.id)).execute()

    async def _get_work_ticket(self, ticket_id: UUID) -> WorkTicket:
        """Fetch work session from database."""
        result = self.db.table("work_tickets").select("*").eq("id", str(ticket_id)).execute()
        if not result.data:
            raise ValueError(f"Work session {ticket_id} not found")
        return WorkTicket(**result.data[0])

    async def _get_outputs(self, ticket_id: UUID) -> List[WorkOutput]:
        """Fetch all outputs for work session."""
        result = (
            self.db.table("work_outputs")
            .select("*")
            .eq("work_ticket_id", str(ticket_id))
            .execute()
        )
        return [WorkOutput(**data) for data in result.data]

    async def _emit_work_completion_event(
        self,
        session: WorkTicket,
        output_ids: List[UUID],
        substrate_ids: List[UUID],
    ) -> None:
        """Emit timeline event for work completion."""
        event_data = {
            "workspace_id": str(session.workspace_id),
            "basket_id": str(session.basket_id),
            "event_type": "work_ticket_completed",
            "event_subtype": session.task_type,
            "description": f"Work session completed: {session.task_intent}",
            "metadata": {
                "work_ticket_id": str(session.id),
                "outputs_applied": len(output_ids),
                "substrate_mutations": len(substrate_ids),
                "agent_id": session.executed_by_agent_id,
            },
        }
        self.db.table("timeline_events").insert(event_data).execute()
