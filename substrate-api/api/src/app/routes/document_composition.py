"""Document composition API routes for context-driven document creation."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import List, Dict, Any, Optional
from uuid import UUID

from fastapi import APIRouter, HTTPException, Depends, Query

from src.schemas.document_composition_schema import (
    ContextDrivenCompositionRequest, CompositionFromIntentRequest,
    DocumentRecompositionRequest, DocumentEvolutionRequest, DocumentEvolutionResult,
    ContextDrivenDocument, DocumentContextAlignment, AgentCompositionRequest,
    CompositionSuggestion, CompositionOpportunityAnalysis
)
from pydantic import BaseModel
from ..documents.services.context_composition import ContextCompositionService
from ..documents.services.document_architect import DocumentArchitectService
from ..documents.services.lifecycle_management import DocumentLifecycleService
from ..documents.services.coherence_analyzer import CoherenceAnalyzerService
from ..agents.pipeline.presentation_agent import P4PresentationAgent
from ..dependencies import get_current_user
from services.events import EventService

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api/documents", tags=["Document Composition"])


class DocumentEnhancementRequest(BaseModel):
    """Request to enhance existing document content."""
    current_content: str
    enhancement_intent: str
    basket_id: str
    composition_type: str = "enhancement"


class DocumentEnhancementResult(BaseModel):
    """Result of document enhancement."""
    enhanced_content: str
    enhancement_applied: bool
    enhancement_summary: Optional[str] = None


# Context-Driven Composition Endpoints

@router.post("/compose-contextual", response_model=ContextDrivenDocument)
async def compose_contextual_document(
    request: ContextDrivenCompositionRequest,
    current_user = Depends(get_current_user)
):
    """Create a document driven by context DNA."""
    
    try:
        document = await ContextCompositionService.compose_contextual_document(
            request=request,
            workspace_id=current_user.workspace_id,
            created_by=current_user.id
        )
        
        logger.info(f"Contextual document created: {document.id}")
        
        # Emit document composition success event
        try:
            EventService.emit_app_event(
                workspace_id=current_user.workspace_id,
                type="action_result",
                name="document.compose",
                message="Document composed successfully from context",
                severity="success",
                basket_id=request.basket_id,
                entity_id=str(document.id),
                payload={
                    "document_id": str(document.id),
                    "composition_type": "contextual",
                    "title": getattr(document, 'title', 'Untitled')
                }
            )
        except Exception as e:
            logger.warning(f"Failed to emit document composition notification: {e}")
        
        return document
        
    except Exception as e:
        logger.exception(f"Failed to compose contextual document: {e}")
        
        # Emit document composition failure event
        try:
            EventService.emit_app_event(
                workspace_id=current_user.workspace_id,
                type="action_result",
                name="document.compose",
                message="Document composition failed",
                severity="error",
                basket_id=request.basket_id,
                payload={
                    "composition_type": "contextual",
                    "error": str(e)
                }
            )
        except Exception as notify_error:
            logger.warning(f"Failed to emit document composition failure notification: {notify_error}")
        
        raise HTTPException(
            status_code=500,
            detail=f"Failed to compose contextual document: {str(e)}"
        )


@router.post("/compose-from-intent", response_model=ContextDrivenDocument)
async def compose_from_intent(
    request: CompositionFromIntentRequest,
    current_user = Depends(get_current_user)
):
    """Create document based on detected composition intent."""
    
    try:
        document = await ContextCompositionService.compose_from_intent(
            request=request,
            workspace_id=current_user.workspace_id,
            created_by=current_user.id
        )
        
        logger.info(f"Intent-based document created: {document.id}")
        return document
        
    except Exception as e:
        logger.exception(f"Failed to compose from intent: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to compose from intent: {str(e)}"
        )


@router.put("/{document_id}/recompose-contextual", response_model=ContextDrivenDocument)
async def recompose_contextual_document(
    document_id: UUID,
    new_primary_context_ids: Optional[List[UUID]] = None,
    composition_intent: Optional[str] = None,
    target_audience: Optional[str] = None,
    style_preference: Optional[str] = None,
    preserve_custom_content: bool = True,
    recomposition_reason: Optional[str] = None,
    current_user = Depends(get_current_user)
):
    """Recompose existing document with new context DNA."""
    
    try:
        request = DocumentRecompositionRequest(
            document_id=document_id,
            new_primary_context_ids=new_primary_context_ids,
            composition_intent=composition_intent,
            target_audience=target_audience,
            style_preference=style_preference,
            preserve_custom_content=preserve_custom_content,
            recomposition_reason=recomposition_reason
        )
        
        document = await DocumentLifecycleService.recompose_document(
            request=request,
            workspace_id=current_user.workspace_id,
            updated_by=current_user.id
        )
        
        logger.info(f"Document recomposed: {document_id}")
        return document
        
    except Exception as e:
        logger.exception(f"Failed to recompose document: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to recompose document: {str(e)}"
        )


@router.get("/{document_id}/context-analysis", response_model=DocumentContextAlignment)
async def analyze_document_context(
    document_id: UUID,
    current_user = Depends(get_current_user)
):
    """Analyze document's context alignment and coherence."""
    
    try:
        alignment = await CoherenceAnalyzerService.analyze_document_context_alignment(
            document_id=document_id,
            workspace_id=current_user.workspace_id
        )
        
        logger.info(f"Context analysis completed for document {document_id}")
        return alignment
        
    except Exception as e:
        logger.exception(f"Failed to analyze document context: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to analyze document context: {str(e)}"
        )


# Document Architecture and Planning Endpoints

@router.get("/composition-opportunities/{basket_id}", response_model=CompositionOpportunityAnalysis)
async def analyze_composition_opportunities(
    basket_id: UUID,
    current_user = Depends(get_current_user)
):
    """Analyze and suggest document composition opportunities for a basket."""
    
    try:
        analysis = await DocumentArchitectService.analyze_composition_opportunities(
            basket_id=basket_id,
            workspace_id=current_user.workspace_id
        )
        
        logger.info(f"Composition opportunities analyzed for basket {basket_id}")
        return analysis
        
    except Exception as e:
        logger.exception(f"Failed to analyze composition opportunities: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to analyze composition opportunities: {str(e)}"
        )


@router.post("/suggest-structure")
async def suggest_document_structure(
    composition_intent: str,
    target_audience: Optional[str] = None,
    estimated_blocks: int = 10,
    current_user = Depends(get_current_user)  
):
    """Suggest optimal document structure based on intent and constraints."""
    
    try:
        # Create mock discovered blocks for structure suggestion
        from src.schemas.document_composition_schema import DiscoveredBlock
        
        mock_blocks = [
            DiscoveredBlock(
                block_id=UUID("00000000-0000-0000-0000-000000000001"),
                content=f"Mock block {i}",
                semantic_type="insight",
                state="ACCEPTED",
                relevance_score=0.8,
                context_alignment=0.7,
                composition_value=0.8,
                discovery_reasoning="Mock block for structure suggestion"
            )
            for i in range(estimated_blocks)
        ]
        
        structure = DocumentArchitectService.suggest_document_structure(
            composition_intent=composition_intent,
            discovered_blocks=mock_blocks,
            target_audience=target_audience
        )
        
        logger.info(f"Document structure suggested for intent: {composition_intent}")
        return structure
        
    except Exception as e:
        logger.exception(f"Failed to suggest document structure: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to suggest document structure: {str(e)}"
        )


# Agent Composition Endpoints

@router.post("/agents/compose-document", response_model=ContextDrivenDocument)
async def agent_compose_document(
    request: AgentCompositionRequest,
    current_user = Depends(get_current_user)
):
    """Create document using agent-driven composition."""
    
    try:
        # Use canonical P4 presentation agent for document composition
        agent = P4PresentationAgent()
        document_id = await agent.compose_document({
            "basket_id": request.basket_id,
            "workspace_id": current_user.workspace_id,
            "title": request.title,
            "document_type": request.document_type or "narrative",
            "agent_id": request.agent_id
        })
        
        # Get the created document
        from ..utils.supabase_client import supabase_admin_client
        doc_response = supabase_admin_client.table("documents").select("*").eq("id", str(document_id)).single().execute()
        document = doc_response.data
        
        logger.info(f"Agent-composed document created: {document.id} by {request.agent_id}")
        return document
        
    except Exception as e:
        logger.exception(f"Failed to compose document with agent: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to compose document with agent: {str(e)}"
        )


@router.get("/agents/composition-suggestions/{basket_id}")
async def get_agent_composition_suggestions(
    basket_id: UUID,
    agent_id: str,
    agent_type: str = Query(pattern="^tasks_.+"),
    current_user = Depends(get_current_user)
):
    """Get composition suggestions optimized for agent capabilities."""
    
    try:
        # Use canonical P3 reflection agent for composition suggestions
        agent = P3ReflectionAgent()
        suggestions = await agent.suggest_compositions(
            basket_id=basket_id,
            workspace_id=current_user.workspace_id,
            agent_context={"agent_id": agent_id, "agent_type": agent_type}
        )
        
        logger.info(f"Agent composition suggestions generated for basket {basket_id}")
        return {"suggestions": suggestions}
        
    except Exception as e:
        logger.exception(f"Failed to get agent composition suggestions: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get agent composition suggestions: {str(e)}"
        )


# Document Lifecycle Management Endpoints

@router.post("/{document_id}/evolve", response_model=DocumentEvolutionResult)
async def evolve_document(
    document_id: UUID,
    evolution_type: str = Query(pattern="^(refresh|expand|refocus|restructure)$"),
    new_context_ids: List[UUID] = [],
    evolution_guidance: Optional[str] = None,
    preserve_manual_edits: bool = True,
    revalidate_context_alignment: bool = True,
    current_user = Depends(get_current_user)
):
    """Evolve document with new context intelligence."""
    
    try:
        request = DocumentEvolutionRequest(
            document_id=document_id,
            evolution_type=evolution_type,
            new_context_ids=new_context_ids,
            evolution_guidance=evolution_guidance,
            preserve_manual_edits=preserve_manual_edits,
            revalidate_context_alignment=revalidate_context_alignment
        )
        
        result = await DocumentLifecycleService.evolve_document(
            request=request,
            workspace_id=current_user.workspace_id,
            updated_by=current_user.id
        )
        
        logger.info(f"Document evolved: {document_id} ({evolution_type})")
        return result
        
    except Exception as e:
        logger.exception(f"Failed to evolve document: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to evolve document: {str(e)}"
        )


@router.get("/{document_id}/health")
async def check_document_health(
    document_id: UUID,
    current_user = Depends(get_current_user)
):
    """Check overall health and alignment of a document."""
    
    try:
        health_metrics = await DocumentLifecycleService.check_document_health(
            document_id=document_id,
            workspace_id=current_user.workspace_id
        )
        
        logger.info(f"Document health checked: {document_id}")
        return health_metrics
        
    except Exception as e:
        logger.exception(f"Failed to check document health: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to check document health: {str(e)}"
        )


@router.get("/{document_id}/maintenance-suggestions")
async def suggest_document_maintenance(
    document_id: UUID,
    current_user = Depends(get_current_user)
):
    """Suggest maintenance actions for a document."""
    
    try:
        suggestions = await DocumentLifecycleService.suggest_document_maintenance(
            document_id=document_id,
            workspace_id=current_user.workspace_id
        )
        
        logger.info(f"Maintenance suggestions generated for document {document_id}")
        return {"maintenance_suggestions": suggestions}
        
    except Exception as e:
        logger.exception(f"Failed to suggest document maintenance: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to suggest document maintenance: {str(e)}"
        )


# Quality and Coherence Analysis Endpoints

@router.get("/{document_id}/quality-assessment")
async def assess_document_quality(
    document_id: UUID,
    current_user = Depends(get_current_user)
):
    """Comprehensive document quality assessment."""
    
    try:
        assessment = await CoherenceAnalyzerService.assess_document_quality(
            document_id=document_id,
            workspace_id=current_user.workspace_id
        )
        
        logger.info(f"Document quality assessed: {document_id}")
        return assessment
        
    except Exception as e:
        logger.exception(f"Failed to assess document quality: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to assess document quality: {str(e)}"
        )


@router.get("/{document_id}/drift-monitoring")
async def monitor_document_drift(
    document_id: UUID,
    baseline_timestamp: Optional[datetime] = None,
    current_user = Depends(get_current_user)
):
    """Monitor how document alignment drifts from its original context."""
    
    try:
        drift_analysis = await CoherenceAnalyzerService.monitor_document_drift(
            document_id=document_id,
            workspace_id=current_user.workspace_id,
            baseline_timestamp=baseline_timestamp
        )
        
        logger.info(f"Document drift monitored: {document_id}")
        return drift_analysis
        
    except Exception as e:
        logger.exception(f"Failed to monitor document drift: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to monitor document drift: {str(e)}"
        )


# Utility Endpoints

@router.get("/health")
async def health_check():
    """Health check endpoint for document composition services."""
    return {
        "status": "healthy",
        "service": "document-composition",
        "timestamp": datetime.utcnow().isoformat(),
        "features": [
            "context_driven_composition",
            "agent_composition",
            "document_lifecycle",
            "coherence_analysis",
            "composition_architecture"
        ]
    }


@router.post("/enhance-existing", response_model=DocumentEnhancementResult)
async def enhance_existing_document(
    request: DocumentEnhancementRequest,
    current_user = Depends(get_current_user)
):
    """Enhance existing document content using AI composition."""
    
    try:
        from app.agents.pipeline.presentation_agent import P4PresentationAgent
        from infra.substrate.services.llm import get_llm
        
        # Use LLM service to enhance the content with context from basket
        llm = get_llm()
        
        # Build enhancement prompt with basket context
        enhancement_prompt = f"""
Enhance and expand the following document content based on the user's intent:

Current Content:
{request.current_content}

Enhancement Intent: {request.enhancement_intent}

Please provide enhanced content that:
- Expands on key concepts mentioned
- Adds relevant context and background
- Maintains the original tone and structure
- Integrates insights that would be valuable
- Keeps the enhancement focused and relevant

Return only the enhanced document content, no explanations.
"""
        
        llm_response = await llm.get_text_response(
            prompt=enhancement_prompt,
            temperature=1.0,  # Use default temperature for model compatibility
            max_tokens=2000
        )
        
        if llm_response.success and llm_response.content:
            enhanced_content = llm_response.content.strip()
            logger.info(f"Document enhanced for basket {request.basket_id}")
            
            return DocumentEnhancementResult(
                enhanced_content=enhanced_content,
                enhancement_applied=True,
                enhancement_summary="Content enhanced using AI composition with contextual insights"
            )
        else:
            # Fallback if LLM fails
            fallback_content = request.current_content + "\n\n---\n\n*AI enhancement temporarily unavailable.*"
            return DocumentEnhancementResult(
                enhanced_content=fallback_content,
                enhancement_applied=False,
                enhancement_summary="Enhancement service temporarily unavailable"
            )
        
    except Exception as e:
        logger.exception(f"Failed to enhance document: {e}")
        # Return original content with error note rather than failing
        fallback_content = request.current_content + "\n\n---\n\n*Enhancement failed. Please try again later.*"
        return DocumentEnhancementResult(
            enhanced_content=fallback_content,
            enhancement_applied=False,
            enhancement_summary=f"Enhancement failed: {str(e)}"
        )


@router.get("/capabilities")
async def get_composition_capabilities():
    """Get available document composition capabilities."""
    return {
        "composition_methods": ["context_driven", "agent_composed", "intent_based"],
        "document_types": [
            "strategic_analysis",
            "technical_guide", 
            "executive_summary",
            "creative_brief",
            "research_report",
            "action_plan",
            "product_specification",
            "meeting_summary",
            "general_composition"
        ],
        "evolution_types": ["refresh", "expand", "refocus", "restructure"],
        "audience_types": ["executives", "engineers", "designers", "product", "general"],
        "style_types": ["formal", "conversational", "detailed"],
        "agent_capabilities": [
            "context_analysis",
            "composition_planning",
            "document_creation", 
            "audience_adaptation",
            "narrative_intelligence"
        ],
        "analysis_features": [
            "context_alignment",
            "coherence_analysis",
            "quality_assessment",
            "drift_monitoring",
            "health_checking"
        ]
    }