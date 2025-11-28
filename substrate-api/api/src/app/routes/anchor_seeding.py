"""
Anchor Seeding API - LLM-powered foundational context generation

Generates anchor blocks from user-provided project context.
Uses the same OpenAI integration pattern as P1 substrate agent.

Architecture Doc: docs/architecture/ANCHOR_SEEDING_ARCHITECTURE.md
"""

import json
import logging
import os
import time
from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field

from ..utils.jwt import verify_jwt
from ..utils.supabase_client import supabase_admin_client

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api/baskets", tags=["anchor-seeding"])

# LLM Configuration (same pattern as improved_substrate_agent.py)
MODEL_SEED = os.getenv("LLM_MODEL_SEED", "gpt-4o-mini")
TEMP_SEED = float(os.getenv("LLM_TEMP_SEED", "0.3"))
MAX_TOKENS_SEED = int(os.getenv("LLM_MAX_TOKENS_SEED", "2000"))

# Valid anchor roles (from schema)
ANCHOR_ROLES = ["problem", "customer", "solution", "vision", "feature", "constraint", "metric", "insight"]

# Semantic types that map well to anchors
ANCHOR_SEMANTIC_TYPES = {
    "problem": "finding",
    "customer": "entity",
    "solution": "objective",
    "vision": "objective",
    "feature": "finding",
    "constraint": "constraint",
    "metric": "metric",
    "insight": "insight",
}


# ============================================================================
# Request/Response Models
# ============================================================================


class AnchorSeedRequest(BaseModel):
    """Request for seeding anchors from project context."""
    context: str = Field(..., min_length=10, max_length=5000, description="User's project context")
    project_name: Optional[str] = Field(None, description="Project name for context")


class GeneratedAnchor(BaseModel):
    """A single generated anchor block."""
    anchor_role: str
    title: str
    content: str
    semantic_type: str
    confidence: float


class AnchorSeedResponse(BaseModel):
    """Response from anchor seeding."""
    success: bool
    blocks_created: int
    anchors: List[Dict[str, Any]]
    message: str


# ============================================================================
# LLM Prompt for Anchor Generation
# ============================================================================

ANCHOR_SEED_SYSTEM_PROMPT = """You are an expert at analyzing project descriptions and extracting foundational context.

Given a project description, identify 2-4 key foundational elements that define the project.
For each element, determine which anchor role it best fits:

ANCHOR ROLES:
- problem: What pain point or challenge is being solved
- customer: Who is the target user/audience
- solution: The core approach or product being built
- vision: Long-term goal or aspiration
- feature: Key capability or functionality (optional)
- constraint: Important limitations or requirements (optional)
- metric: Success measure or KPI (optional)
- insight: Key learning or observation (optional)

RULES:
1. Always try to identify: problem, customer, and either solution OR vision
2. Only add feature/constraint/metric/insight if clearly present
3. Keep titles concise (under 10 words)
4. Keep content to 2-3 sentences
5. Be specific, not generic

Return JSON array of objects with: anchor_role, title, content"""

ANCHOR_SEED_USER_TEMPLATE = """Project: {project_name}

Context:
{context}

Analyze this and return a JSON array of 2-4 foundational anchor blocks.
Each object must have: anchor_role, title, content

Example format:
[
  {{"anchor_role": "customer", "title": "Marketing Managers at B2B Companies", "content": "Target users are marketing managers at mid-market B2B companies who need data-driven insights but lack technical analytics skills."}},
  {{"anchor_role": "problem", "title": "Manual Reporting Overhead", "content": "Marketing teams spend 40% of their time creating manual reports, leaving little time for strategic analysis and campaign optimization."}}
]"""


# ============================================================================
# Endpoint
# ============================================================================


@router.post("/{basket_id}/seed-anchors", response_model=AnchorSeedResponse)
async def seed_anchors(
    basket_id: str,
    request: AnchorSeedRequest,
    auth_info: dict = Depends(verify_jwt),
):
    """
    Generate foundational anchor blocks from project context using LLM.

    This endpoint:
    1. Uses LLM to analyze the project context
    2. Generates 2-4 foundational blocks with anchor_role
    3. Creates blocks in the basket with ACCEPTED state
    4. Registers them in the anchored_substrate view

    Args:
        basket_id: Target basket UUID
        request: Project context to analyze

    Returns:
        Created anchor blocks summary
    """
    start_time = time.time()

    try:
        # Validate basket_id
        try:
            basket_uuid = UUID(basket_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid basket_id format")

        # Verify basket exists and get workspace_id
        basket_result = (
            supabase_admin_client.table("baskets")
            .select("id, workspace_id, name")
            .eq("id", str(basket_uuid))
            .single()
            .execute()
        )

        if not basket_result.data:
            raise HTTPException(status_code=404, detail=f"Basket not found: {basket_id}")

        workspace_id = basket_result.data["workspace_id"]
        basket_name = basket_result.data.get("name", "")

        logger.info(f"[ANCHOR SEED] Starting for basket {basket_id}, context length: {len(request.context)}")

        # Generate anchors using LLM
        project_name = request.project_name or basket_name or "Project"
        generated_anchors = await _generate_anchors_llm(request.context, project_name)

        if not generated_anchors:
            return AnchorSeedResponse(
                success=True,
                blocks_created=0,
                anchors=[],
                message="No anchors could be generated from the provided context"
            )

        # Create blocks for each anchor
        created_blocks = []
        for anchor in generated_anchors:
            block_id = str(uuid4())
            semantic_type = ANCHOR_SEMANTIC_TYPES.get(anchor["anchor_role"], "finding")

            block_data = {
                "id": block_id,
                "basket_id": str(basket_uuid),
                "workspace_id": workspace_id,
                "title": anchor["title"],
                "content": anchor["content"],
                "semantic_type": semantic_type,
                "anchor_role": anchor["anchor_role"],
                "anchor_status": "accepted",
                "anchor_confidence": anchor.get("confidence", 0.8),
                "state": "ACCEPTED",
                "confidence_score": anchor.get("confidence", 0.8),
                "metadata": {
                    "source": "anchor_seeding",
                    "seeded_at": datetime.utcnow().isoformat(),
                    "project_context_length": len(request.context),
                },
            }

            try:
                result = (
                    supabase_admin_client.table("blocks")
                    .insert(block_data)
                    .execute()
                )

                created_blocks.append({
                    "id": block_id,
                    "anchor_role": anchor["anchor_role"],
                    "title": anchor["title"],
                    "semantic_type": semantic_type,
                })

                logger.info(f"[ANCHOR SEED] Created block {block_id} with anchor_role={anchor['anchor_role']}")

            except Exception as e:
                logger.warning(f"[ANCHOR SEED] Failed to create block for {anchor['anchor_role']}: {e}")
                continue

        processing_time = round(time.time() - start_time, 2)
        logger.info(f"[ANCHOR SEED] Complete: {len(created_blocks)} blocks created in {processing_time}s")

        return AnchorSeedResponse(
            success=True,
            blocks_created=len(created_blocks),
            anchors=created_blocks,
            message=f"Created {len(created_blocks)} anchor blocks in {processing_time}s"
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"[ANCHOR SEED] Error: {e}")
        raise HTTPException(status_code=500, detail=f"Anchor seeding failed: {str(e)}")


async def _generate_anchors_llm(context: str, project_name: str) -> List[Dict[str, Any]]:
    """
    Use LLM to generate anchor blocks from context.

    Same pattern as improved_substrate_agent.py for consistency.
    """
    if not os.getenv("OPENAI_API_KEY"):
        logger.error("[ANCHOR SEED] OPENAI_API_KEY not set")
        raise HTTPException(status_code=500, detail="LLM configuration error")

    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    user_prompt = ANCHOR_SEED_USER_TEMPLATE.format(
        project_name=project_name,
        context=context
    )

    # Retry logic for reliability
    for attempt in range(3):
        try:
            response = client.chat.completions.create(
                model=MODEL_SEED,
                messages=[
                    {"role": "system", "content": ANCHOR_SEED_SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=TEMP_SEED,
                max_completion_tokens=MAX_TOKENS_SEED,
                response_format={"type": "json_object"},
            )

            raw_response = response.choices[0].message.content
            logger.debug(f"[ANCHOR SEED] LLM response: {raw_response[:500]}")

            # Parse response
            data = json.loads(raw_response)

            # Handle both array and object with "anchors" key
            if isinstance(data, list):
                anchors = data
            elif isinstance(data, dict) and "anchors" in data:
                anchors = data["anchors"]
            else:
                # Try to extract from any key that's a list
                for key, value in data.items():
                    if isinstance(value, list):
                        anchors = value
                        break
                else:
                    logger.warning(f"[ANCHOR SEED] Unexpected response format: {data}")
                    return []

            # Validate and filter anchors
            valid_anchors = []
            for anchor in anchors:
                if not isinstance(anchor, dict):
                    continue

                anchor_role = anchor.get("anchor_role", "").lower()
                if anchor_role not in ANCHOR_ROLES:
                    logger.warning(f"[ANCHOR SEED] Invalid anchor_role: {anchor_role}")
                    continue

                if not anchor.get("title") or not anchor.get("content"):
                    continue

                valid_anchors.append({
                    "anchor_role": anchor_role,
                    "title": anchor["title"][:200],  # Truncate if too long
                    "content": anchor["content"][:2000],
                    "confidence": 0.8,  # Default confidence for seeded anchors
                })

            logger.info(f"[ANCHOR SEED] Generated {len(valid_anchors)} valid anchors")
            return valid_anchors

        except json.JSONDecodeError as e:
            logger.warning(f"[ANCHOR SEED] JSON parse error (attempt {attempt + 1}): {e}")
            if attempt == 2:
                return []
            time.sleep(1.0 * (attempt + 1))

        except Exception as e:
            logger.warning(f"[ANCHOR SEED] LLM error (attempt {attempt + 1}): {e}")
            if attempt == 2:
                return []
            time.sleep(1.0 * (attempt + 1))

    return []
