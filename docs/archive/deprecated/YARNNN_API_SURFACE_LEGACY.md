# YARNNN API Surface

**Complete API Reference for Four-Layer Architecture**

**Version**: 4.0
**Date**: 2025-10-31
**Status**: ✅ Canonical
**Layer**: All layers
**Supersedes**: N/A (new document)

---

## 🎯 Overview

This document provides the complete API surface for YARNNN v4.0, organized by architectural layer. Each endpoint includes request/response schemas, authentication requirements, and usage examples.

**Base URL**: `https://api.yarnnn.com` (production) or `http://localhost:8000` (local)

**Authentication**: All endpoints require Bearer token authentication via Supabase Auth unless otherwise noted.

---

## 📚 Table of Contents

- [Layer 1: Substrate Core API](#layer-1-substrate-core-api)
  - [Blocks](#blocks)
  - [Documents](#documents)
  - [Semantic Search](#semantic-search)
  - [Relationships](#relationships)
  - [Timeline](#timeline)
- [Layer 2: Work Orchestration API](#layer-2-work-orchestration-api)
  - [Work Sessions](#work-sessions)
  - [Work Artifacts](#work-artifacts)
  - [Work Checkpoints](#work-checkpoints)
  - [Work Iterations](#work-iterations)
- [Layer 3: Unified Governance API](#layer-3-unified-governance-api)
  - [Session Review](#session-review)
  - [Checkpoint Review](#checkpoint-review)
  - [Risk Assessment](#risk-assessment)
  - [Agent Metrics](#agent-metrics)
  - [Workspace Policies](#workspace-policies)
- [Layer 4: Presentation API](#layer-4-presentation-api)
  - [Notifications](#notifications)
  - [User Preferences](#user-preferences)
  - [Dashboard Data](#dashboard-data)
- [Common Types](#common-types)
- [Error Responses](#error-responses)

---

## 🏗️ Layer 1: Substrate Core API

### Blocks

#### List Blocks

**GET** `/api/substrate/blocks`

List blocks in a workspace/basket with optional filtering.

**Query Parameters**:
```typescript
{
  workspace_id: UUID        // Required
  basket_id?: UUID          // Optional: filter by basket
  state?: BlockState        // Optional: ACCEPTED | PROPOSED | REJECTED | SUPERSEDED
  block_type?: string       // Optional: note | research_finding | recommendation | etc.
  created_after?: ISO8601   // Optional: filter by creation date
  limit?: number            // Optional: default 50, max 200
  offset?: number           // Optional: for pagination
}
```

**Response**:
```typescript
{
  blocks: Block[]
  total: number
  limit: number
  offset: number
}

interface Block {
  id: UUID
  workspace_id: UUID
  basket_id: UUID
  content: {
    text: string
    entities?: string[]
    tags?: string[]
    [key: string]: any
  }
  block_type: string
  state: BlockState
  metadata: Record<string, any>
  embedding?: number[]      // Optional: vector embedding
  created_by: UUID
  created_at: ISO8601
  superseded_by?: UUID      // If state = SUPERSEDED
  supersedes?: UUID         // If this block supersedes another
}
```

**Example**:
```bash
curl -X GET "https://api.yarnnn.com/api/substrate/blocks?workspace_id=ws-123&state=ACCEPTED&limit=10" \
  -H "Authorization: Bearer ${TOKEN}"
```

---

#### Get Block

**GET** `/api/substrate/blocks/{block_id}`

Retrieve a single block by ID.

**Path Parameters**:
- `block_id` (UUID): Block identifier

**Response**:
```typescript
{
  block: Block
  relationships?: {
    outgoing: Relationship[]  // Relationships where this block is source
    incoming: Relationship[]  // Relationships where this block is target
  }
  provenance?: {
    work_session_id?: UUID
    work_artifact_id?: UUID
    created_by_agent?: string
    approved_by_user?: UUID
  }
}
```

**Example**:
```bash
curl -X GET "https://api.yarnnn.com/api/substrate/blocks/block-123" \
  -H "Authorization: Bearer ${TOKEN}"
```

---

#### Create Block

**POST** `/api/substrate/blocks`

Create a new block in the substrate.

**Request Body**:
```typescript
{
  workspace_id: UUID
  basket_id: UUID
  content: {
    text: string
    entities?: string[]
    tags?: string[]
    [key: string]: any
  }
  block_type: string
  state?: BlockState        // Default: ACCEPTED
  metadata?: Record<string, any>
}
```

**Response**:
```typescript
{
  block: Block
}
```

**Note**: Direct block creation is typically restricted to humans. Agents create blocks via work artifacts (Layer 2).

**Example**:
```bash
curl -X POST "https://api.yarnnn.com/api/substrate/blocks" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "workspace_id": "ws-123",
    "basket_id": "basket-456",
    "content": {
      "text": "User prefers privacy-first tools",
      "entities": ["privacy"]
    },
    "block_type": "preference"
  }'
```

---

#### Update Block

**PATCH** `/api/substrate/blocks/{block_id}`

Update a block's metadata or state (content updates use supersession).

**Path Parameters**:
- `block_id` (UUID): Block identifier

**Request Body**:
```typescript
{
  metadata?: Record<string, any>  // Merge with existing metadata
  state?: BlockState              // Update state
  tags?: string[]                 // Replace tags
}
```

**Response**:
```typescript
{
  block: Block
}
```

---

#### Supersede Block

**POST** `/api/substrate/blocks/{block_id}/supersede`

Create a new version of a block, marking the old one as SUPERSEDED.

**Path Parameters**:
- `block_id` (UUID): Block to supersede

**Request Body**:
```typescript
{
  new_content: {
    text: string
    entities?: string[]
    tags?: string[]
    [key: string]: any
  }
  supersession_reason: string
  metadata?: Record<string, any>
}
```

**Response**:
```typescript
{
  old_block: Block          // State changed to SUPERSEDED
  new_block: Block          // Newly created block
}
```

**Example**:
```bash
curl -X POST "https://api.yarnnn.com/api/substrate/blocks/block-123/supersede" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "new_content": {
      "text": "Updated pricing: Mem now charges $10/month (increased from $8)"
    },
    "supersession_reason": "Pricing changed as of 2025-01"
  }'
```

---

#### Delete Block

**DELETE** `/api/substrate/blocks/{block_id}`

Soft-delete a block (marks as deleted, doesn't remove from database).

**Path Parameters**:
- `block_id` (UUID): Block identifier

**Response**:
```typescript
{
  success: boolean
  message: string
}
```

---

### Documents

#### List Documents

**GET** `/api/substrate/documents`

List documents in a workspace/basket.

**Query Parameters**:
```typescript
{
  workspace_id: UUID
  basket_id?: UUID
  document_type?: string    // composition | research_report | meeting_notes | etc.
  created_after?: ISO8601
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  documents: Document[]
  total: number
  limit: number
  offset: number
}

interface Document {
  id: UUID
  workspace_id: UUID
  basket_id: UUID
  title: string
  document_type: string
  metadata: Record<string, any>
  created_by: UUID
  created_at: ISO8601
  updated_at: ISO8601
  version_number: number
  content_hash?: string     // SHA256 of content
}
```

---

#### Get Document

**GET** `/api/substrate/documents/{document_id}`

Retrieve a document with its constituent blocks.

**Path Parameters**:
- `document_id` (UUID): Document identifier

**Query Parameters**:
```typescript
{
  include_blocks?: boolean  // Default: true
}
```

**Response**:
```typescript
{
  document: Document
  blocks?: Array<{
    block: Block
    sequence_order: number
  }>
  provenance?: {
    work_session_id?: UUID
    work_artifact_id?: UUID
  }
}
```

---

#### Create Document

**POST** `/api/substrate/documents`

Create a new document (composition of blocks).

**Request Body**:
```typescript
{
  workspace_id: UUID
  basket_id: UUID
  title: string
  document_type: string
  content_blocks: Array<{
    block_id?: UUID         // Reference existing block
    inline_content?: {      // Or create inline content
      text: string
      [key: string]: any
    }
    sequence_order: number
  }>
  metadata?: Record<string, any>
}
```

**Response**:
```typescript
{
  document: Document
  blocks: Block[]           // Blocks created from inline_content
}
```

---

#### Update Document

**PUT** `/api/substrate/documents/{document_id}`

Update document title, metadata, or block composition.

**Path Parameters**:
- `document_id` (UUID): Document identifier

**Request Body**:
```typescript
{
  title?: string
  metadata?: Record<string, any>
  content_blocks?: Array<{
    block_id: UUID
    sequence_order: number
  }>
}
```

**Response**:
```typescript
{
  document: Document
}
```

---

### Semantic Search

#### Search Blocks

**POST** `/api/substrate/semantic/search`

Semantic similarity search across substrate blocks.

**Request Body**:
```typescript
{
  workspace_id: UUID
  basket_id?: UUID          // Optional: search within basket
  query_text: string
  limit?: number            // Default: 10, max 50
  min_similarity?: number   // Default: 0.7 (range: 0-1)
  filters?: {
    block_type?: string[]
    state?: BlockState[]
    created_after?: ISO8601
  }
}
```

**Response**:
```typescript
{
  results: Array<{
    block: Block
    similarity: number      // Cosine similarity score (0-1)
    highlights?: string[]   // Relevant text excerpts
  }>
  query_embedding?: number[] // Optional: return query embedding
}
```

**Example**:
```bash
curl -X POST "https://api.yarnnn.com/api/substrate/semantic/search" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "workspace_id": "ws-123",
    "query_text": "AI memory tools pricing",
    "limit": 10,
    "min_similarity": 0.75
  }'
```

---

#### Search Documents

**POST** `/api/substrate/semantic/search-documents`

Semantic search across documents.

**Request Body**:
```typescript
{
  workspace_id: UUID
  basket_id?: UUID
  query_text: string
  limit?: number
  min_similarity?: number
  filters?: {
    document_type?: string[]
    created_after?: ISO8601
  }
}
```

**Response**:
```typescript
{
  results: Array<{
    document: Document
    similarity: number
    relevant_blocks?: Array<{
      block: Block
      similarity: number
    }>
  }>
}
```

---

### Relationships

#### List Relationships

**GET** `/api/substrate/relationships`

List relationships between blocks.

**Query Parameters**:
```typescript
{
  workspace_id: UUID
  source_block_id?: UUID    // Filter by source
  target_block_id?: UUID    // Filter by target
  relationship_type?: string // causal | temporal | semantic | contradiction | etc.
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  relationships: Relationship[]
  total: number
}

interface Relationship {
  id: UUID
  source_block_id: UUID
  target_block_id: UUID
  relationship_type: string
  confidence?: number
  metadata?: Record<string, any>
  created_at: ISO8601
  created_by?: UUID
}
```

---

#### Create Relationship

**POST** `/api/substrate/relationships`

Create a relationship between two blocks.

**Request Body**:
```typescript
{
  source_block_id: UUID
  target_block_id: UUID
  relationship_type: string
  confidence?: number       // 0-1
  metadata?: Record<string, any>
}
```

**Response**:
```typescript
{
  relationship: Relationship
}
```

---

### Timeline

#### List Timeline Events

**GET** `/api/substrate/timeline`

List timeline events in a workspace.

**Query Parameters**:
```typescript
{
  workspace_id: UUID
  basket_id?: UUID
  event_type?: string       // work_approved | block_created | document_updated | etc.
  actor_type?: string       // user | agent | system
  actor_id?: UUID
  after?: ISO8601          // Events after this time
  before?: ISO8601         // Events before this time
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  events: TimelineEvent[]
  total: number
}

interface TimelineEvent {
  id: UUID
  workspace_id: UUID
  basket_id?: UUID
  event_type: string
  event_data: Record<string, any>
  actor_type: string
  actor_id?: UUID
  created_at: ISO8601
}
```

---

#### Get Timeline Event

**GET** `/api/substrate/timeline/{event_id}`

Retrieve a single timeline event with related entities.

**Path Parameters**:
- `event_id` (UUID): Event identifier

**Response**:
```typescript
{
  event: TimelineEvent
  related_entities?: {
    blocks?: Block[]
    documents?: Document[]
    work_sessions?: WorkSession[]
  }
}
```

---

## 🔧 Layer 2: Work Orchestration API

### Work Sessions

#### Create Work Session

**POST** `/api/work/sessions`

Create a new work session (task assignment for agent).

**Request Body**:
```typescript
{
  workspace_id: UUID
  basket_id: UUID
  task_intent: string       // Natural language task description
  task_type?: string        // research | synthesis | analysis | recommendation | etc.
  task_document_id?: UUID   // Optional: P4 document providing context
  approval_strategy?: string // checkpoint_required | final_only | auto_approve_low_risk
  executed_by_agent_id?: string
  agent_session_id?: string // Links to Agent SDK session
}
```

**Response**:
```typescript
{
  session: WorkSession
}

interface WorkSession {
  id: UUID
  workspace_id: UUID
  basket_id: UUID
  initiated_by_user_id: UUID
  executed_by_agent_id?: string
  agent_session_id?: string

  task_intent: string
  task_type?: string
  task_document_id?: UUID

  status: WorkSessionStatus
  approval_strategy: string

  artifacts_count: number
  substrate_mutations_count: number

  reasoning_trail?: Array<{
    timestamp: ISO8601
    reasoning: string
  }>

  created_at: ISO8601
  started_at?: ISO8601
  completed_at?: ISO8601
  approved_at?: ISO8601
  approved_by?: UUID
}

type WorkSessionStatus =
  | 'initialized'
  | 'in_progress'
  | 'pending_review'
  | 'iteration_requested'
  | 'completed_approved'
  | 'rejected'
```

**Example**:
```bash
curl -X POST "https://api.yarnnn.com/api/work/sessions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "workspace_id": "ws-123",
    "basket_id": "basket-456",
    "task_intent": "Research competitors in AI memory space",
    "task_type": "research",
    "approval_strategy": "final_only"
  }'
```

---

#### List Work Sessions

**GET** `/api/work/sessions`

List work sessions in a workspace.

**Query Parameters**:
```typescript
{
  workspace_id: UUID
  basket_id?: UUID
  status?: WorkSessionStatus[]
  initiated_by?: UUID
  executed_by_agent_id?: string
  created_after?: ISO8601
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  sessions: WorkSession[]
  total: number
}
```

---

#### Get Work Session

**GET** `/api/work/sessions/{session_id}`

Retrieve a work session with artifacts and checkpoints.

**Path Parameters**:
- `session_id` (UUID): Session identifier

**Query Parameters**:
```typescript
{
  include_artifacts?: boolean    // Default: true
  include_checkpoints?: boolean  // Default: true
  include_iterations?: boolean   // Default: true
}
```

**Response**:
```typescript
{
  session: WorkSession
  artifacts?: WorkArtifact[]
  checkpoints?: WorkCheckpoint[]
  iterations?: WorkIteration[]
}
```

---

#### Update Work Session Status

**PATCH** `/api/work/sessions/{session_id}/status`

Update work session status (typically called by agent).

**Path Parameters**:
- `session_id` (UUID): Session identifier

**Request Body**:
```typescript
{
  status: WorkSessionStatus
  reasoning_entry?: {
    reasoning: string
    timestamp?: ISO8601
  }
}
```

**Response**:
```typescript
{
  session: WorkSession
}
```

---

### Work Artifacts

#### Create Work Artifact

**POST** `/api/work/artifacts`

Create a work artifact (agent-generated output).

**Request Body**:
```typescript
{
  work_session_id: UUID
  artifact_type: ArtifactType
  content: Record<string, any>
  agent_confidence?: number  // 0-1
  agent_reasoning?: string
  source_context_ids?: UUID[] // Blocks used for reasoning
}

type ArtifactType =
  | 'block_proposal'
  | 'block_update_proposal'
  | 'block_lock_proposal'
  | 'document_creation'
  | 'insight'
  | 'external_deliverable'
```

**Response**:
```typescript
{
  artifact: WorkArtifact
  risk_assessment: RiskCalculation
}

interface WorkArtifact {
  id: UUID
  work_session_id: UUID
  artifact_type: ArtifactType
  content: Record<string, any>

  // Substrate linkage (populated after approval)
  becomes_block_id?: UUID
  supersedes_block_id?: UUID
  creates_document_id?: UUID

  agent_confidence?: number
  agent_reasoning?: string
  source_context_ids: UUID[]

  status: ArtifactStatus
  risk_level?: RiskLevel

  created_at: ISO8601
}

type ArtifactStatus =
  | 'draft'
  | 'pending_review'
  | 'approved'
  | 'rejected'
  | 'applied_to_substrate'

type RiskLevel = 'low' | 'medium' | 'high'
```

**Example**:
```bash
curl -X POST "https://api.yarnnn.com/api/work/artifacts" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "work_session_id": "session-123",
    "artifact_type": "block_proposal",
    "content": {
      "block_content": {
        "text": "Mem (YC W22) - Personal memory assistant using vector embeddings",
        "entities": ["Mem", "YC", "vector embeddings"]
      },
      "block_type": "research_finding"
    },
    "agent_confidence": 0.95,
    "agent_reasoning": "Found on official website, verified launch date"
  }'
```

---

#### List Work Artifacts

**GET** `/api/work/artifacts`

List artifacts for a work session.

**Query Parameters**:
```typescript
{
  work_session_id: UUID
  artifact_type?: ArtifactType[]
  status?: ArtifactStatus[]
  risk_level?: RiskLevel[]
}
```

**Response**:
```typescript
{
  artifacts: WorkArtifact[]
  total: number
}
```

---

#### Get Work Artifact

**GET** `/api/work/artifacts/{artifact_id}`

Retrieve a single artifact with risk assessment and provenance.

**Path Parameters**:
- `artifact_id` (UUID): Artifact identifier

**Response**:
```typescript
{
  artifact: WorkArtifact
  risk_assessment: RiskCalculation
  source_blocks?: Block[]   // If source_context_ids present
  becomes_block?: Block     // If applied to substrate
}
```

---

### Work Checkpoints

#### List Work Checkpoints

**GET** `/api/work/checkpoints`

List checkpoints for a work session.

**Query Parameters**:
```typescript
{
  work_session_id: UUID
  checkpoint_type?: CheckpointType[]
  status?: CheckpointStatus[]
}

type CheckpointType =
  | 'plan_approval'
  | 'mid_work_review'
  | 'artifact_review'
  | 'final_approval'

type CheckpointStatus =
  | 'pending'
  | 'approved'
  | 'rejected'
  | 'iteration_requested'
```

**Response**:
```typescript
{
  checkpoints: WorkCheckpoint[]
  total: number
}

interface WorkCheckpoint {
  id: UUID
  work_session_id: UUID
  checkpoint_type: CheckpointType
  checkpoint_number: number

  review_context: {
    artifacts?: UUID[]
    progress?: Record<string, any>
    plan?: Record<string, any>
  }

  status: CheckpointStatus
  decision?: CheckpointDecision
  reviewed_by?: UUID
  reviewed_at?: ISO8601

  created_at: ISO8601
}
```

---

### Work Iterations

#### List Work Iterations

**GET** `/api/work/iterations`

List iterations for a work session.

**Query Parameters**:
```typescript
{
  work_session_id: UUID
}
```

**Response**:
```typescript
{
  iterations: WorkIteration[]
  total: number
}

interface WorkIteration {
  id: UUID
  work_session_id: UUID
  iteration_number: number
  triggered_by: string      // user_feedback | agent_self_correction | checkpoint_failure

  user_feedback_text?: string
  changes_requested?: ChangeRequest[]

  status: string            // pending | in_progress | completed

  requested_by?: UUID
  completed_at?: ISO8601
  created_at: ISO8601
}

interface ChangeRequest {
  artifact_id?: UUID
  request_type: 'approach' | 'focus' | 'data_quality' | 'scope'
  description: string
  priority: 'critical' | 'important' | 'nice_to_have'
}
```

---

## ⚖️ Layer 3: Unified Governance API

### Session Review

#### Review Work Session

**POST** `/api/governance/sessions/{session_id}/review`

Submit approval/rejection decision for work session.

**Path Parameters**:
- `session_id` (UUID): Session identifier

**Request Body**:
```typescript
{
  decision: WorkReviewDecision
}

interface WorkReviewDecision {
  workQuality: 'approved' | 'rejected' | 'needs_revision'
  artifactDecisions?: Record<UUID, ArtifactDecision>
  feedback?: string
  changeRequests?: ChangeRequest[]
}

type ArtifactDecision =
  | 'apply_to_substrate'
  | 'approve_only'
  | 'reject'
  | 'defer'
```

**Response**:
```typescript
{
  result: WorkReviewResult
}

interface WorkReviewResult {
  status: 'approved' | 'rejected' | 'iteration_requested'
  substrateChanges?: {
    blocksCreated: UUID[]
    blocksUpdated: UUID[]
    blocksLocked: UUID[]
    documentsCreated: UUID[]
    mutationsApplied: number
  }
  rejectionReason?: string
  iterationId?: UUID
  timelineEventId: UUID
  notificationsSent: Array<{
    id: UUID
    user_id: UUID
    type: string
  }>
}
```

**Example**:
```bash
curl -X POST "https://api.yarnnn.com/api/governance/sessions/session-123/review" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "decision": {
      "workQuality": "approved",
      "artifactDecisions": {
        "artifact-1": "apply_to_substrate",
        "artifact-2": "apply_to_substrate",
        "artifact-3": "reject"
      }
    }
  }'
```

---

#### Get Review Data

**GET** `/api/governance/sessions/{session_id}/review-data`

Fetch all data needed for UI review (session, artifacts, risk assessments, agent metrics).

**Path Parameters**:
- `session_id` (UUID): Session identifier

**Response**:
```typescript
{
  session: WorkSession
  artifacts: WorkArtifact[]
  riskAssessments: Record<UUID, RiskCalculation>
  agentMetrics: AgentPerformanceMetrics
  workspacePolicy: WorkspaceApprovalPolicy
  relatedBlocks?: Block[]  // Source context blocks
}
```

---

#### Revert Approved Work

**POST** `/api/governance/sessions/{session_id}/revert`

Undo previously approved work (removes substrate mutations).

**Path Parameters**:
- `session_id` (UUID): Session identifier

**Request Body**:
```typescript
{
  reason: string
}
```

**Response**:
```typescript
{
  success: boolean
  blocksRemoved: UUID[]
  documentsRemoved: UUID[]
  timelineEventId: UUID
}
```

---

### Checkpoint Review

#### Review Checkpoint

**POST** `/api/governance/checkpoints/{checkpoint_id}/review`

Submit decision for a specific checkpoint.

**Path Parameters**:
- `checkpoint_id` (UUID): Checkpoint identifier

**Request Body**:
```typescript
{
  decision: CheckpointDecision
}

interface CheckpointDecision {
  outcome: 'approve' | 'reject' | 'request_iteration'
  feedback?: string
  changeRequests?: ChangeRequest[]
}
```

**Response**:
```typescript
{
  result: CheckpointResult
  nextCheckpoint?: WorkCheckpoint  // If workflow continues
}
```

---

### Risk Assessment

#### Assess Artifact Risk

**POST** `/api/governance/risk/assess-artifact`

Calculate risk level for a specific artifact (typically called automatically).

**Request Body**:
```typescript
{
  artifact_id: UUID
  work_session_id: UUID
}
```

**Response**:
```typescript
{
  calculation: RiskCalculation
}

interface RiskCalculation {
  finalRisk: RiskLevel
  baseRisk: RiskLevel
  modifiers: RiskModifier[]
  reasoning: string
}

interface RiskModifier {
  factor: string  // confidence | context_impact | track_record | novelty
  direction: 'increase' | 'decrease' | 'none'
  magnitude: number
  reason: string
}
```

---

### Agent Metrics

#### Get Agent Performance

**GET** `/api/governance/agents/{agent_id}/metrics`

Retrieve performance metrics for an agent.

**Path Parameters**:
- `agent_id` (string): Agent identifier

**Query Parameters**:
```typescript
{
  workspace_id?: UUID      // Optional: filter by workspace
  time_range?: string      // 7d | 30d | 90d | all
}
```

**Response**:
```typescript
{
  metrics: AgentPerformanceMetrics
}

interface AgentPerformanceMetrics {
  agent_id: string

  // Session-level
  totalSessions: number
  sessionsApproved: number
  sessionsRejected: number
  sessionsPartialApproval: number
  approvalRate: number

  // Artifact-level
  totalArtifacts: number
  artifactsAppliedToSubstrate: number
  artifactsRejected: number
  artifactApprovalRate: number

  // Confidence calibration
  avgClaimedConfidence: number
  avgActualApprovalRate: number
  confidenceCalibrationError: number

  // Iterations
  avgIterationsPerSession: number

  // Risk distribution
  lowRiskArtifacts: number
  mediumRiskArtifacts: number
  highRiskArtifacts: number

  // Time range
  metricsCalculatedFrom: ISO8601
  metricsCalculatedTo: ISO8601
}
```

---

#### List Agent Activity

**GET** `/api/governance/agents/{agent_id}/activity`

List recent work sessions for an agent.

**Path Parameters**:
- `agent_id` (string): Agent identifier

**Query Parameters**:
```typescript
{
  workspace_id?: UUID
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  sessions: WorkSession[]
  total: number
}
```

---

### Workspace Policies

#### Get Workspace Policy

**GET** `/api/governance/workspaces/{workspace_id}/policy`

Retrieve governance policy for a workspace.

**Path Parameters**:
- `workspace_id` (UUID): Workspace identifier

**Response**:
```typescript
{
  policy: WorkspaceApprovalPolicy
}

interface WorkspaceApprovalPolicy {
  workspace_id: UUID

  defaultStrategy: 'checkpoint_required' | 'final_only' | 'auto_approve_low_risk'

  // Checkpoint configuration
  enablePlanApproval: boolean
  enableMidWorkReview: boolean
  enableArtifactReview: boolean
  finalApprovalRequired: boolean  // Always true

  // Auto-approval rules
  autoApproveEnabled: boolean
  autoApproveConfidenceMin: number
  autoApproveAgentApprovalRateMin: number
  autoApproveRiskLevels: RiskLevel[]

  // Iteration limits
  maxIterationsPerSession: number  // Default: 3

  updated_at: ISO8601
}
```

---

#### Update Workspace Policy

**PUT** `/api/governance/workspaces/{workspace_id}/policy`

Update governance policy for a workspace (admin only).

**Path Parameters**:
- `workspace_id` (UUID): Workspace identifier

**Request Body**:
```typescript
{
  policy: Partial<WorkspaceApprovalPolicy>
}
```

**Response**:
```typescript
{
  policy: WorkspaceApprovalPolicy
}
```

**Example**:
```bash
curl -X PUT "https://api.yarnnn.com/api/governance/workspaces/ws-123/policy" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "autoApproveEnabled": true,
      "autoApproveRiskLevels": ["low"],
      "autoApproveConfidenceMin": 0.9,
      "autoApproveAgentApprovalRateMin": 0.85
    }
  }'
```

---

## 🖼️ Layer 4: Presentation API

### Notifications

#### List Notifications

**GET** `/api/notifications`

List notifications for current user.

**Query Parameters**:
```typescript
{
  workspace_id?: UUID
  read?: boolean           // Filter by read status
  notification_type?: string[]
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  notifications: Notification[]
  unreadCount: number
  total: number
}

interface Notification {
  id: UUID
  user_id: UUID
  workspace_id: UUID
  notification_type: string
  title: string
  message: string
  action_url?: string
  read: boolean
  read_at?: ISO8601
  created_at: ISO8601
}
```

---

#### Mark Notification Read

**PATCH** `/api/notifications/{notification_id}/read`

Mark a notification as read.

**Path Parameters**:
- `notification_id` (UUID): Notification identifier

**Response**:
```typescript
{
  notification: Notification
}
```

---

#### Mark All Notifications Read

**POST** `/api/notifications/mark-all-read`

Mark all notifications as read for current user.

**Request Body**:
```typescript
{
  workspace_id?: UUID  // Optional: mark read for specific workspace only
}
```

**Response**:
```typescript
{
  success: boolean
  markedCount: number
}
```

---

### User Preferences

#### Get User Preferences

**GET** `/api/users/me/preferences`

Retrieve current user's preferences.

**Response**:
```typescript
{
  preferences: UserPreferences
}

interface UserPreferences {
  user_id: UUID

  // Notification preferences
  emailNotifications: boolean
  emailDigestFrequency: 'none' | 'daily' | 'weekly'

  // UI preferences
  theme: 'light' | 'dark' | 'system'
  defaultView: 'timeline' | 'substrate' | 'work'

  // Work preferences
  defaultApprovalStrategy: string
  autoWatchWorkSessions: boolean

  updated_at: ISO8601
}
```

---

#### Update User Preferences

**PUT** `/api/users/me/preferences`

Update current user's preferences.

**Request Body**:
```typescript
{
  preferences: Partial<UserPreferences>
}
```

**Response**:
```typescript
{
  preferences: UserPreferences
}
```

---

### Dashboard Data

#### Get Workspace Dashboard

**GET** `/api/dashboard/workspaces/{workspace_id}`

Fetch aggregated data for workspace dashboard.

**Path Parameters**:
- `workspace_id` (UUID): Workspace identifier

**Query Parameters**:
```typescript
{
  time_range?: string  // 7d | 30d | 90d
}
```

**Response**:
```typescript
{
  dashboard: WorkspaceDashboard
}

interface WorkspaceDashboard {
  workspace: Workspace

  // Work activity
  pendingReviewSessions: number
  completedSessionsCount: number
  activeAgents: number

  // Substrate growth
  totalBlocks: number
  blocksAddedRecently: number
  totalDocuments: number

  // Governance metrics
  avgReviewTimeSeconds: number
  approvalRate: number
  autoApprovalRate: number

  // Recent activity
  recentSessions: WorkSession[]
  recentTimelineEvents: TimelineEvent[]

  // Agent performance
  topAgents: Array<{
    agent_id: string
    sessions_completed: number
    approval_rate: number
  }>
}
```

---

#### Get User Activity Feed

**GET** `/api/dashboard/users/me/activity`

Fetch personalized activity feed for current user.

**Query Parameters**:
```typescript
{
  workspace_id?: UUID
  limit?: number
  offset?: number
}
```

**Response**:
```typescript
{
  activities: Activity[]
  total: number
}

interface Activity {
  id: UUID
  type: string
  title: string
  description: string
  workspace_id: UUID
  related_entity_type: string
  related_entity_id: UUID
  action_url: string
  timestamp: ISO8601
}
```

---

## 📝 Common Types

### Authentication

All API requests require authentication via Bearer token:

```
Authorization: Bearer <supabase_access_token>
```

**Obtaining Token**:
```typescript
// Frontend (Next.js)
import { createClient } from '@/lib/supabase/client'

const supabase = createClient()
const { data: { session } } = await supabase.auth.getSession()
const token = session?.access_token

// Use token in API requests
fetch('/api/work/sessions', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
})
```

---

### Pagination

Endpoints that return lists support pagination:

**Request**:
```typescript
{
  limit?: number   // Default: 50, max: 200
  offset?: number  // Default: 0
}
```

**Response**:
```typescript
{
  items: T[]
  total: number
  limit: number
  offset: number
  hasMore: boolean  // offset + limit < total
}
```

---

### Filtering

Many list endpoints support filtering:

```typescript
// Single value
?status=pending_review

// Multiple values (comma-separated)
?status=pending_review,in_progress

// Date ranges
?created_after=2025-01-01T00:00:00Z
?created_before=2025-12-31T23:59:59Z
```

---

### Sorting

List endpoints support sorting via `sort` query parameter:

```typescript
// Ascending
?sort=created_at

// Descending (prefix with -)
?sort=-created_at

// Multiple fields (comma-separated)
?sort=-created_at,title
```

---

## ❌ Error Responses

### Standard Error Format

```typescript
{
  error: {
    code: string
    message: string
    details?: Record<string, any>
  }
}
```

### Error Codes

| HTTP Status | Error Code | Description |
|-------------|-----------|-------------|
| 400 | `invalid_request` | Malformed request body or parameters |
| 401 | `unauthorized` | Missing or invalid authentication token |
| 403 | `forbidden` | User lacks permission for requested resource |
| 404 | `not_found` | Resource does not exist |
| 409 | `conflict` | Request conflicts with current state (e.g., duplicate) |
| 422 | `validation_error` | Request validation failed |
| 429 | `rate_limit_exceeded` | Too many requests |
| 500 | `internal_error` | Server error |
| 503 | `service_unavailable` | Service temporarily unavailable |

### Example Error Responses

**401 Unauthorized**:
```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid or expired authentication token"
  }
}
```

**403 Forbidden**:
```json
{
  "error": {
    "code": "forbidden",
    "message": "User is not a member of workspace ws-123",
    "details": {
      "workspace_id": "ws-123",
      "user_id": "user-456"
    }
  }
}
```

**422 Validation Error**:
```json
{
  "error": {
    "code": "validation_error",
    "message": "Request validation failed",
    "details": {
      "fields": {
        "workspace_id": "Required field missing",
        "task_intent": "Must be non-empty string"
      }
    }
  }
}
```

---

## 🔒 Rate Limiting

**Rate limits** (per user):
- Authenticated requests: 1000 requests/minute
- Work session creation: 10 requests/minute
- Governance reviews: 50 requests/minute

**Response Headers**:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 847
X-RateLimit-Reset: 1704067200
```

**429 Rate Limit Response**:
```json
{
  "error": {
    "code": "rate_limit_exceeded",
    "message": "Rate limit exceeded. Retry after 60 seconds.",
    "details": {
      "limit": 1000,
      "reset_at": "2025-01-01T00:00:00Z"
    }
  }
}
```

---

## 🔌 Webhooks (Optional)

YARNNN supports webhooks for asynchronous event notifications.

### Configuring Webhooks

**POST** `/api/webhooks`

Create a webhook subscription.

**Request Body**:
```typescript
{
  workspace_id: UUID
  url: string              // Your webhook endpoint
  events: string[]         // Event types to subscribe to
  secret?: string          // Optional: for signature verification
}
```

**Example Events**:
- `work_session.created`
- `work_session.completed`
- `work_session.approved`
- `work_session.rejected`
- `block.created`
- `document.created`
- `timeline_event.created`

### Webhook Payload

```typescript
{
  event: string
  workspace_id: UUID
  timestamp: ISO8601
  data: Record<string, any>
  signature?: string  // HMAC-SHA256 signature if secret provided
}
```

**Example**:
```json
{
  "event": "work_session.approved",
  "workspace_id": "ws-123",
  "timestamp": "2025-01-15T10:30:00Z",
  "data": {
    "session_id": "session-456",
    "approved_by": "user-789",
    "blocks_created": 3,
    "documents_created": 1
  }
}
```

---

## 📚 SDK Libraries

Official SDKs available:

### JavaScript/TypeScript

```bash
npm install @yarnnn/sdk
```

```typescript
import { YarnnnClient } from '@yarnnn/sdk'

const client = new YarnnnClient({
  apiKey: process.env.YARNNN_API_KEY,
  baseUrl: 'https://api.yarnnn.com'
})

// Create work session
const session = await client.work.createSession({
  workspace_id: 'ws-123',
  basket_id: 'basket-456',
  task_intent: 'Research competitors'
})

// List blocks
const { blocks } = await client.substrate.listBlocks({
  workspace_id: 'ws-123',
  state: 'ACCEPTED'
})
```

### Python

```bash
pip install yarnnn-sdk
```

```python
from yarnnn import YarnnnClient

client = YarnnnClient(
    api_key=os.environ['YARNNN_API_KEY'],
    base_url='https://api.yarnnn.com'
)

# Create work session
session = client.work.create_session(
    workspace_id='ws-123',
    basket_id='basket-456',
    task_intent='Research competitors'
)

# List blocks
blocks = client.substrate.list_blocks(
    workspace_id='ws-123',
    state='ACCEPTED'
)
```

---

## 🧪 Testing & Sandbox

### Sandbox Environment

**Base URL**: `https://sandbox.api.yarnnn.com`

- Completely isolated from production
- Test workspaces auto-deleted after 7 days
- Rate limits: 10x more generous
- Free for development

### API Playground

Interactive API documentation available at:
- **Production**: https://docs.yarnnn.com/api
- **Sandbox**: https://sandbox.docs.yarnnn.com/api

---

## ✅ Summary

YARNNN v4.0 provides **comprehensive REST APIs** across four architectural layers:

1. **Layer 1 (Substrate)**: Blocks, documents, semantic search, relationships, timeline
2. **Layer 2 (Work Orchestration)**: Work sessions, artifacts, checkpoints, iterations
3. **Layer 3 (Governance)**: Review orchestration, risk assessment, agent metrics, policies
4. **Layer 4 (Presentation)**: Notifications, user preferences, dashboard data

**Key Features**:
- Bearer token authentication (Supabase)
- RLS-enforced workspace isolation
- Consistent error responses
- Pagination, filtering, sorting
- Rate limiting
- Webhook support (optional)
- Official SDKs (JS/Python)

**Design Principles**:
- RESTful conventions
- JSON request/response
- Predictable URLs
- Comprehensive error messages
- Backward compatibility

---

## 📎 See Also

- [YARNNN_LAYERED_ARCHITECTURE_V4.md](./YARNNN_LAYERED_ARCHITECTURE_V4.md) - System architecture
- [YARNNN_DATA_FLOW_V4.md](./YARNNN_DATA_FLOW_V4.md) - Request flows
- [YARNNN_UNIFIED_GOVERNANCE.md](./YARNNN_UNIFIED_GOVERNANCE.md) - Governance layer
- [API Playground](https://docs.yarnnn.com/api) - Interactive documentation

---

**Complete API surface. Every layer accessible, every flow supported.**
