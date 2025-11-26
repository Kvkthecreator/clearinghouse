# YARNNN Layered Architecture v4.0

**Complete System Design: Four-Layer Model**

**Version**: 4.0
**Date**: 2025-10-31
**Status**: ✅ Canonical
**Supersedes**: YARNNN_ARCHITECTURE_CANON.md
**Audience**: Engineering, Architecture, Technical PM

---

## 🎯 Overview

YARNNN v4.0 is built on a **four-layer architecture** where each layer has clear responsibilities and clean interfaces. This design enables:

- **Separation of concerns** - Each layer focuses on one responsibility
- **Independent scaling** - Layers can scale independently
- **Clean testing** - Each layer can be tested in isolation
- **Evolutionary architecture** - Layers can evolve without breaking others

### The Four Layers

```
┌────────────────────────────────────────────────────────────┐
│ LAYER 4: PRESENTATION                                       │
│ Responsibility: User interaction and visualization          │
│ Technology: Next.js, React, Tailwind CSS                    │
└────────────────────────────────────────────────────────────┘
                          ↓ HTTP/WebSocket
┌────────────────────────────────────────────────────────────┐
│ LAYER 3: UNIFIED GOVERNANCE                                 │
│ Responsibility: Work quality + substrate integrity          │
│ Technology: Python, FastAPI orchestrator                    │
└────────────────────────────────────────────────────────────┘
                          ↓ Database operations
┌────────────────────────────────────────────────────────────┐
│ LAYER 2: WORK ORCHESTRATION                                 │
│ Responsibility: Agent work lifecycle management             │
│ Technology: PostgreSQL tables, Python services              │
└────────────────────────────────────────────────────────────┘
                          ↓ Queries/Updates
┌────────────────────────────────────────────────────────────┐
│ LAYER 1: SUBSTRATE CORE                                     │
│ Responsibility: Context storage and semantic intelligence   │
│ Technology: PostgreSQL, pgvector, Supabase                  │
└────────────────────────────────────────────────────────────┘
```

**Key Insight**: Layers 2-3 are **new in v4.0**. Layer 1 existed in v3.1 but was the entire system. Now it's the foundation.

---

## 📦 Layer 1: Substrate Core (Context Management)

### Responsibility

**Store and retrieve structured knowledge with semantic understanding.**

This layer is the **foundation** - the knowledge base that agents query and (with approval) update.

### Components

#### 1. Blocks (Universal Substrate)

**Purpose**: Structured knowledge units

**Table**: `blocks`

**Key Fields**:
```sql
blocks (
  id uuid PRIMARY KEY,
  basket_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  parent_block_id uuid,              -- Versioning chain
  semantic_type text,                -- 'fact', 'intent', 'entity', etc.
  content text NOT NULL,
  state block_state,                 -- PROPOSED, ACCEPTED, LOCKED, CONSTANT
  scope text,                        -- BASKET, WORKSPACE, ORG, GLOBAL
  version integer,
  created_at timestamptz
)
```

**States**:
- `PROPOSED` - Awaiting approval (from user or agent work)
- `ACCEPTED` - Approved, part of active substrate
- `LOCKED` - Finalized, editable only with special permissions
- `CONSTANT` - Immutable facts (e.g., definitions)
- `SUPERSEDED` - Replaced by newer version
- `REJECTED` - Not accepted

**See**: [YARNNN_SUBSTRATE_CANON_V3.md](../../YARNNN_SUBSTRATE_CANON_V3.md)

#### 2. Documents (P4 Compositions)

**Purpose**: Immutable narrative compositions from substrate

**Table**: `documents`, `document_versions`

**Document Types**:
- `document_canon` - Basket context brief (one per basket)
- `starter_prompt` - Reasoning capsules for external AI hosts
- `task_request` - Task context envelopes [NEW in v4.0]
- `artifact_other` - General documents

**Key Pattern**: Git-inspired immutability
```sql
documents (
  id uuid,
  current_version_hash varchar(64)  -- Points to document_versions
)

document_versions (
  version_hash varchar(64) PRIMARY KEY,  -- Content-addressable
  document_id uuid,
  content text NOT NULL,                 -- Immutable snapshot
  parent_version_hash varchar(64),       -- Lineage
  substrate_refs_snapshot jsonb          -- Blocks used
)
```

#### 3. Insights (P3 Reflections)

**Purpose**: Interpretive intelligence layer

**Types**:
- `insight_canon` - "What matters now" (one per basket)
- `doc_insight` - Document-scoped interpretations
- `timeboxed_insight` - Temporal window understanding

**Regeneration**: Direct operation (not governed), triggered by substrate changes

#### 4. Timeline Events

**Purpose**: Append-only activity stream

**Table**: `timeline_events`

**Event Types**:
- Substrate events: `block_created`, `block_updated`, `block_locked`
- Work events [NEW]: `work_session_started`, `work_session_completed`, `work_artifact_approved`
- Governance events [NEW]: `checkpoint_reviewed`, `iteration_created`
- System events: `document_regenerated`, `insight_refreshed`

#### 5. Semantic Layer

**Purpose**: Vector embeddings + causal relationships

**Tables**: `block_embeddings`, `substrate_relationships`

**Capabilities**:
- Semantic search via pgvector
- Relationship discovery (causal, temporal, hierarchical)
- Context-aware retrieval for agents

**See**: [YARNNN_SUBSTRATE_CANON_V3.md](../YARNNN_SUBSTRATE_CANON_V3.md) - Semantic layer is integrated in v4.0 substrate

### APIs (Layer 1)

```
GET  /api/baskets/{id}/blocks          - List blocks
GET  /api/blocks/{id}                  - Get block details
GET  /api/baskets/{id}/documents       - List documents
GET  /api/documents/{id}               - Get document
POST /api/baskets/{id}/query           - Semantic search
GET  /api/timeline                     - Get timeline events
```

**Note**: Layer 1 APIs are **read-heavy**. Writes flow through Layer 2 (work orchestration) or Layer 3 (governance).

---

## 🔄 Layer 2: Work Orchestration (Agent Work Management)

### Responsibility

**Manage agent work lifecycle from task creation to completion.**

This layer tracks what agents are doing, what outputs they produce, and orchestrates multi-checkpoint workflows.

### Components [NEW in v4.0]

#### 1. Work Sessions

**Purpose**: Track agent execution lifecycle

**Table**: `work_sessions`

**Lifecycle**:
```
INITIALIZED → IN_PROGRESS → AWAITING_CHECKPOINT → AWAITING_FINAL_APPROVAL → APPROVED
                                                                              ↓
                                                                           REJECTED
```

**Key Fields**:
```sql
work_sessions (
  id uuid PRIMARY KEY,
  workspace_id uuid,
  basket_id uuid,
  initiated_by_user_id uuid,
  executed_by_agent_id text,        -- Agent SDK agent_id
  agent_session_id text,            -- Links to Agent SDK execution session

  task_intent text NOT NULL,
  task_type text,                   -- research, synthesis, analysis, etc.
  task_document_id uuid,            -- P4 context envelope

  status text,
  approval_strategy text,           -- checkpoint_required, final_only, auto_approve_low_risk

  artifacts_count integer,
  substrate_mutations_count integer,

  reasoning_trail jsonb[],
  created_at timestamptz
)
```

**Session Linking**: `agent_session_id` links to Agent SDK for cross-system traceability.

#### 2. Work Artifacts

**Purpose**: Agent outputs awaiting approval

**Table**: `work_artifacts`

**Artifact Types**:
- `block_proposal` - Will become block in substrate
- `block_update` - Will supersede existing block
- `document_creation` - Will create document
- `insight` - Reflection/insight
- `external_deliverable` - File/link (no substrate impact)

**Key Fields**:
```sql
work_artifacts (
  id uuid PRIMARY KEY,
  work_session_id uuid NOT NULL,
  artifact_type text,
  content jsonb NOT NULL,

  -- Substrate linkage (populated after approval)
  becomes_block_id uuid,
  supersedes_block_id uuid,
  creates_document_id uuid,

  agent_confidence numeric,
  agent_reasoning text,
  source_context_ids uuid[],

  status text,                      -- draft, pending_review, approved, applied_to_substrate
  risk_level text,                  -- low, medium, high

  reviewed_by_user_id uuid,
  reviewed_at timestamptz
)
```

**Key Pattern**: Artifacts exist BEFORE substrate application. Links populated during approval.

#### 3. Work Checkpoints

**Purpose**: Multi-stage approval workflow

**Table**: `work_checkpoints`

**Checkpoint Types**:
- `plan_approval` - Before work starts
- `mid_work_review` - During execution
- `artifact_review` - Per-artifact (optional)
- `final_approval` - Before substrate application (always required)

**Key Fields**:
```sql
work_checkpoints (
  id uuid PRIMARY KEY,
  work_session_id uuid NOT NULL,
  checkpoint_sequence integer,
  checkpoint_type text,

  review_scope text,
  artifacts_at_checkpoint uuid[],

  agent_confidence numeric,
  agent_reasoning text,
  agent_summary text,

  status text,                      -- pending, approved, rejected, skipped

  reviewed_by_user_id uuid,
  user_decision text,               -- approve, reject, request_changes
  user_feedback text,
  changes_requested jsonb
)
```

#### 4. Work Iterations

**Purpose**: Feedback loops and revisions

**Table**: `work_iterations`

**Triggers**:
- `checkpoint_rejection` - User rejected checkpoint
- `user_feedback` - User requested changes
- `agent_self_correction` - Agent detected error
- `context_staleness` - Substrate changed during work

**Key Fields**:
```sql
work_iterations (
  id uuid PRIMARY KEY,
  work_session_id uuid NOT NULL,
  iteration_number integer,

  triggered_by text,
  user_feedback_text text,
  changes_requested jsonb,

  agent_interpretation text,
  revised_approach text,
  artifacts_revised uuid[],

  resolved boolean,
  resolved_at timestamptz
)
```

**Bounded**: Max 3 iterations per session (prevents infinite loops)

#### 5. Work Context Mutations

**Purpose**: Audit trail of substrate changes from work

**Table**: `work_context_mutations`

**Mutation Types**:
- `block_created` - New block added
- `block_updated` - Block content changed
- `block_superseded` - Block replaced with newer version
- `block_locked` - Block state changed to LOCKED
- `document_created` - New document created
- `document_updated` - Document regenerated

**Key Fields**:
```sql
work_context_mutations (
  id uuid PRIMARY KEY,
  work_session_id uuid NOT NULL,
  artifact_id uuid,

  mutation_type text,
  substrate_id uuid NOT NULL,
  substrate_type text,              -- block, document

  before_state jsonb,
  after_state jsonb NOT NULL,

  mutation_risk text,
  applied_at timestamptz
)
```

**Purpose**: Complete provenance from work → substrate changes

### APIs (Layer 2)

```
POST /api/work/sessions                - Create work session
GET  /api/work/sessions/{id}          - Get session status
PATCH /api/work/sessions/{id}         - Update session
POST /api/work/sessions/{id}/artifacts - Create artifact
GET  /api/work/sessions/{id}/artifacts - List artifacts
POST /api/work/sessions/{id}/checkpoint - Request checkpoint review
GET  /api/work/tasks/pending          - Poll for pending tasks (Agent SDK integration)
```

**See**: [WORK_ORCHESTRATION_LAYER.md](../../WORK_ORCHESTRATION_LAYER.md)

---

## ⚖️ Layer 3: Unified Governance (Work Quality + Context Integrity)

### Responsibility

**Single approval process handling both work quality review and substrate mutation application.**

This layer orchestrates the "single approval → dual effect" pattern that eliminates redundant double-governance.

### Components

#### 1. Unified Approval Orchestrator

**Purpose**: Orchestrate work review and substrate application

**Implementation**: `api/src/app/governance/unified_approval.py`

**Core Method**:
```python
class UnifiedApprovalOrchestrator:
    async def review_work_session(
        work_session_id: UUID,
        user_id: UUID,
        decision: WorkReviewDecision
    ) -> WorkReviewResult:
        """
        Single approval with dual effect:
        1. Work quality assessment
        2. Substrate application (if approved)
        """

        # Step 1: Check work quality
        if decision.work_quality != "approved":
            reject_work_session()
            return WorkReviewResult(status="rejected")

        # Step 2: Per-artifact processing
        for artifact in artifacts:
            if decision.artifacts[artifact.id] == "apply_to_substrate":
                substrate_id = apply_artifact_to_substrate(artifact)
                log_context_mutation(artifact, substrate_id)

        # Step 3: Update session status
        complete_work_session(status="approved")

        # Step 4: Emit timeline event
        emit_work_completion_event()

        return WorkReviewResult(artifacts_applied=X, substrate_mutations=[...])
```

**Key Pattern**: Work was already reviewed → Blocks go straight to `ACCEPTED` state (no separate proposal)

#### 2. Risk Assessment Engine

**Purpose**: Calculate artifact risk scores

**Factors**:
1. **Mutation Type**: Create (medium) vs. Update (high) vs. Delete (highest)
2. **Agent Confidence**: High confidence reduces risk
3. **Context Impact**: Number of related blocks affected
4. **Agent Track Record**: Approval rate history
5. **Novelty Detection**: New topics vs. confirming existing knowledge

**Algorithm**:
```python
def calculate_risk_level(artifact, agent_history, substrate):
    risk_score = 0

    # Factor 1: Mutation type
    if artifact.type == "block_created": risk_score += 2
    elif artifact.type == "block_update": risk_score += 3
    elif artifact.type == "block_superseded": risk_score += 4

    # Factor 2: Agent confidence
    if artifact.agent_confidence < 0.7: risk_score += 3
    elif artifact.agent_confidence < 0.85: risk_score += 1

    # Factor 3: Context impact
    related_blocks = count_related_blocks(artifact, substrate)
    if related_blocks > 5: risk_score += 2

    # Factor 4: Track record
    if agent_history.approval_rate < 0.7: risk_score += 2

    # Factor 5: Novelty
    if is_new_topic(artifact, substrate): risk_score += 2

    # Classification
    if risk_score <= 3: return "low"
    elif risk_score <= 6: return "medium"
    else: return "high"
```

#### 3. Checkpoint Orchestrator

**Purpose**: Manage multi-stage approval workflow

**Configuration**: Per-workspace approval strategy

```python
if workspace.approval_strategy == "checkpoint_required":
    # Create plan approval checkpoint
    checkpoint = create_checkpoint(type="plan_approval")
    await wait_for_approval(checkpoint)

    # Agent works
    # ...

    # Create mid-work checkpoint
    checkpoint = create_checkpoint(type="mid_work_review")
    await wait_for_approval(checkpoint)

    # Agent completes
    # ...

    # Create final checkpoint (always required)
    checkpoint = create_checkpoint(type="final_approval")
    await wait_for_approval(checkpoint)

elif workspace.approval_strategy == "final_only":
    # Skip intermediate checkpoints
    # Only require final approval

elif workspace.approval_strategy == "auto_approve_low_risk":
    # Auto-approve if low risk + high confidence + trusted agent
    if can_auto_approve(artifact, agent, workspace):
        auto_approve()
    else:
        require_final_approval()
```

#### 4. Auto-Approval Engine

**Purpose**: Trust calibration for proven agents

**Conditions**:
```python
def can_auto_approve(artifact, agent, workspace):
    return (
        artifact.risk_level == "low"
        and artifact.agent_confidence > workspace.confidence_threshold
        and agent.approval_rate > 0.85
        and workspace.enable_auto_approve == True
    )
```

**Safety**: Auto-approved work still logged in timeline with "revert" option

### APIs (Layer 3)

```
POST /api/governance/work-review        - Review work session (unified approval)
GET  /api/governance/sessions/{id}/risk - Get risk assessment
POST /api/governance/checkpoint/{id}/review - Review checkpoint
GET  /api/agents/{id}/track-record     - Get agent approval history
```

**See**: [YARNNN_UNIFIED_GOVERNANCE.md](./YARNNN_UNIFIED_GOVERNANCE.md)

---

## 🎨 Layer 4: Presentation (User Interface)

### Responsibility

**Provide intuitive interfaces for work review and substrate management.**

This layer translates complex backend operations into user-friendly workflows.

### Components

#### 1. Work Review UI [NEW in v4.0]

**Purpose**: Review agent work sessions

**Views**:
- **Work Queue**: List of pending work sessions
- **Session Detail**: Artifacts, reasoning trail, risk assessment
- **Checkpoint Review**: Mid-work approval interface
- **Artifact Inspector**: Per-artifact review and decisions

**Key UX Patterns**:
```typescript
// Work session review interface
interface WorkSessionReviewProps {
  session: WorkSession
  artifacts: WorkArtifact[]
  checkpoints: WorkCheckpoint[]
  riskAssessment: RiskAssessment
}

// User can:
// - Approve all artifacts
// - Approve some, reject others (granular)
// - Request changes (trigger iteration)
// - View complete reasoning trail
// - See risk scores and confidence levels
```

#### 2. Substrate Management UI [Existing, Enhanced]

**Purpose**: Browse and manage knowledge substrate

**Views**:
- **Block Browser**: List/search blocks by semantic type, state, basket
- **Document Viewer**: Read P4 composed documents
- **Timeline**: Activity stream with work events [NEW]
- **Semantic Graph**: Visualize relationships [v3.1 feature]

#### 3. Governance Dashboard [NEW in v4.0]

**Purpose**: Track agent performance and trust

**Views**:
- **Agent Track Record**: Approval rates, confidence calibration
- **Workspace Policies**: Configure approval strategies
- **Context Mutations Log**: Audit trail of substrate changes
- **Auto-Approval Settings**: Trust calibration configuration

#### 4. Notification System

**Purpose**: Alert users to pending work and governance events

**Channels**:
- In-app notifications
- Email digests
- Real-time updates (Supabase Realtime)

**Event Types** [Enhanced in v4.0]:
- Work session requires review
- Checkpoint awaiting approval
- Agent requests feedback (iteration)
- Auto-approved work completed (FYI)
- Context mutation occurred

### Technology Stack

- **Framework**: Next.js 14 (App Router)
- **UI Library**: React 18
- **Styling**: Tailwind CSS
- **State Management**: React Query + Context
- **Realtime**: Supabase Realtime subscriptions
- **Deployment**: Vercel

**See**: web/README.md for current frontend architecture (Next.js app in `/web` directory)

---

## 🔄 Complete Data Flow

### User Creates Task → Agent Works → User Reviews → Context Updated

```
[1] USER: Create Task
  ↓
POST /api/work/sessions
  {
    basket_id: "basket_123",
    task_intent: "Research AI memory competitors",
    task_type: "research",
    approval_strategy: "final_only"
  }
  ↓
Layer 2: work_sessions row created (status = "initialized")
  ↓
[2] AGENT SDK: Poll for Tasks
  ↓
GET /api/work/tasks/pending?agent_id=research_bot_001
  ↓
Layer 2: Returns pending work sessions
  ↓
[3] AGENT SDK: Execute Task
  ↓
Agent queries context:
  GET /api/baskets/basket_123/query?q="AI memory systems"
  ↓
Layer 1: Semantic search returns relevant blocks
  ↓
Agent reasons with Claude SDK (uses block content as context)
  ↓
Agent creates artifacts:
  POST /api/work/sessions/{id}/artifacts
  {
    artifact_type: "block_proposal",
    content: {...},
    agent_confidence: 0.89,
    agent_reasoning: "Based on research...",
    source_context_ids: ["block_abc", "block_xyz"]
  }
  ↓
Layer 2: work_artifacts rows created (status = "draft")
  ↓
Agent updates session:
  PATCH /api/work/sessions/{id}
  {
    status: "awaiting_final_approval"
  }
  ↓
[4] LAYER 2: Emit Notification
  ↓
Timeline event: "work_session_awaiting_review"
  ↓
Layer 4: User sees notification
  ↓
[5] USER: Review Work
  ↓
GET /api/work/sessions/{id}
  - Fetches session, artifacts, reasoning trail
  ↓
Layer 4: Displays work review UI
  - Shows artifacts with risk scores
  - Shows agent reasoning
  - Shows source context used
  ↓
User decision:
  {
    work_quality: "approved",
    artifacts: {
      artifact_1: "apply_to_substrate",
      artifact_2: "apply_to_substrate",
      artifact_3: "apply_to_substrate"
    }
  }
  ↓
POST /api/governance/work-review
  ↓
[6] LAYER 3: Unified Approval Orchestrator
  ↓
For each approved artifact:
  - Apply to substrate (create block in ACCEPTED state)
    INSERT INTO blocks (state = 'ACCEPTED', ...)
  - Update artifact (link to block)
    UPDATE work_artifacts SET becomes_block_id = block_id
  - Log context mutation
    INSERT INTO work_context_mutations (mutation_type = 'block_created', ...)
  ↓
Update session:
  UPDATE work_sessions SET status = 'approved', substrate_mutations_count = 3
  ↓
Emit timeline event:
  INSERT INTO timeline_events (event_type = 'work_session_completed', ...)
  ↓
[7] LAYER 1: Substrate Updated
  ↓
3 new blocks in substrate (state = ACCEPTED)
Timeline event emitted
Documents marked stale (if needed)
  ↓
[8] LAYER 4: User Sees Confirmation
  ↓
Notification: "3 blocks added from agent work session"
Timeline updated with new event
Substrate browser shows new blocks
```

**Key Observations**:
- **Single approval** (step 5) handles both work quality AND substrate mutation (step 6)
- **Complete provenance**: Timeline event → work session → artifacts → blocks
- **Agent SDK abstraction**: Agent doesn't know about Layer 2/3 complexity

---

## 🔌 External Integrations

### Agent SDK Integration

**Repository**: `github.com/Kvkthecreator/claude-agentsdk-yarnnn`

**Providers Implemented**:

```python
# YarnnnMemory (MemoryProvider)
memory = YarnnnMemory(
    basket_id="basket_123",
    api_url="https://api.yarnnn.com",
    api_key="..."
)

# Agent queries context
contexts = await memory.query("AI memory systems")
# Returns: List[Context] with block content + metadata

# YarnnnGovernance (GovernanceProvider)
governance = YarnnnGovernance(
    work_session_id="work_session_xyz",
    api_url="https://api.yarnnn.com",
    api_key="..."
)

# Agent proposes changes (creates work artifacts)
proposal = await governance.propose(
    changes=[Change(...)],
    confidence=0.89,
    reasoning="Based on research..."
)
# Returns: Proposal with artifact_id

# YarnnnTasks (TaskProvider)
tasks = YarnnnTasks(
    api_url="https://api.yarnnn.com",
    api_key="..."
)

# Agent polls for work
pending_tasks = await tasks.get_pending_tasks(agent_id="research_bot_001")
# Returns: List[Task] with work session IDs
```

**Session Linking**:
```python
# Agent SDK creates session
agent_session = AgentSession(
    id="session_abc123",
    agent_id="research_bot_001",
    task_id="work_session_xyz"  # Links to YARNNN
)

# YARNNN tracks agent session
UPDATE work_sessions
SET agent_session_id = "session_abc123"
WHERE id = "work_session_xyz"
```

**Benefit**: Cross-system traceability for debugging

---

## 🔒 Security & RLS

### Workspace Isolation (All Layers)

**Principle**: Users can only access data in workspaces they're members of.

**Enforcement**:
```sql
-- RLS policy pattern (all work tables)
CREATE POLICY "workspace_isolation"
  ON work_sessions FOR SELECT
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_memberships WHERE user_id = auth.uid()
    )
  );
```

**Applied To**:
- Layer 1: `blocks`, `documents`, `timeline_events`
- Layer 2: `work_sessions`, `work_artifacts`, `work_checkpoints`, `work_iterations`, `work_context_mutations`
- Layer 3: N/A (operates via service role)

### Agent Authorization

**Principle**: Agents cannot directly mutate substrate. They create artifacts awaiting approval.

**Enforcement**:
```sql
-- Agents CANNOT directly insert blocks
CREATE POLICY "no_agent_direct_mutations"
  ON blocks FOR INSERT
  WITH CHECK (
    -- Only users or unified governance orchestrator
    current_user IN (SELECT user_id FROM workspace_memberships)
  );

-- Agents CAN create work artifacts
CREATE POLICY "agents_create_artifacts"
  ON work_artifacts FOR INSERT
  WITH CHECK (
    -- Via API with valid service role token
    true
  );
```

**Result**: Substrate integrity guaranteed via governance layer

---

## 📊 Performance Considerations

### Layer 1 (Substrate)

**Read-Heavy Workload**:
- Indexes on `basket_id`, `workspace_id`, `semantic_type`, `state`
- pgvector indexes for semantic search
- Timeline events partitioned by date (future)

**Optimization**:
- Connection pooling (Supabase Pooler)
- Query result caching (15 min TTL for document compositions)

### Layer 2 (Work Orchestration)

**Write-Heavy During Agent Work**:
- Indexes on `work_session_id`, `status`
- Triggers for auto-counters (artifacts_count, mutations_count)

**Optimization**:
- Batch artifact creation (single transaction)
- Async timeline event emission

### Layer 3 (Unified Governance)

**Transactional Consistency Critical**:
- Work approval + substrate application in single transaction
- Rollback on any failure (artifact applied but timeline event fails → full rollback)

**Optimization**:
- Parallel artifact application (when independent)
- Risk assessment pre-computed (cached in artifacts table)

### Layer 4 (Presentation)

**Realtime Updates Important**:
- Supabase Realtime subscriptions for work queue
- Optimistic UI updates

**Optimization**:
- Server components for initial page load
- Client components for interactive elements
- Incremental Static Regeneration (ISR) for public docs

---

## 🧪 Testing Strategy (By Layer)

### Layer 1 Tests
- Unit: Block state transitions, document versioning
- Integration: Semantic search accuracy, timeline event emission
- E2E: User creates block → appears in timeline

### Layer 2 Tests
- Unit: Work session state machine, artifact risk calculation
- Integration: Session → artifacts → checkpoints flow
- E2E: Agent creates work session → artifacts → awaiting approval

### Layer 3 Tests
- Unit: Risk assessment algorithm, auto-approval conditions
- Integration: Unified approval → substrate application → timeline
- E2E: User reviews work → substrate updated correctly

### Layer 4 Tests
- Unit: UI component rendering
- Integration: API client → React Query caching
- E2E: User reviews work in UI → backend updated → UI reflects change

---

## 🚀 Deployment Architecture

### Production Environment

```
                    [Cloudflare CDN]
                           ↓
                    [Vercel (Layer 4)]
                    Next.js frontend
                           ↓
                    [Render (Layer 2+3)]
                    FastAPI backend
                           ↓
                    [Supabase (Layer 1)]
              PostgreSQL + Auth + Realtime
```

**Horizontal Scaling**:
- Layer 4: Vercel auto-scales (serverless)
- Layer 2+3: Render scales via instance count
- Layer 1: Supabase handles scaling (managed PostgreSQL)

**Vertical Scaling**:
- Layer 2+3: Increase CPU/memory per instance
- Layer 1: Upgrade Supabase plan (more connections, storage)

---

## ✅ Summary

**YARNNN v4.0 four-layer architecture**:

1. **Layer 1: Substrate Core** - Knowledge storage with semantic intelligence
2. **Layer 2: Work Orchestration** - Agent work lifecycle management
3. **Layer 3: Unified Governance** - Single approval for work + substrate
4. **Layer 4: Presentation** - User-friendly work review and substrate management

**Key Benefits**:
- Clear separation of concerns
- Independent layer evolution
- Single approval eliminates redundancy
- Complete provenance via work sessions
- Agent SDK integration via clean providers

**The Integration**: Layers 2-3 are new in v4.0, transforming YARNNN from "Context OS" to "AI Work Platform" while preserving the substrate foundation (Layer 1).

---

## 📎 See Also

- [YARNNN_PLATFORM_CANON_V4.md](../canon/YARNNN_PLATFORM_CANON_V4.md) - Platform philosophy
- [WORK_ORCHESTRATION_LAYER.md](../../WORK_ORCHESTRATION_LAYER.md) - Layer 2 detailed spec
- [YARNNN_UNIFIED_GOVERNANCE.md](./YARNNN_UNIFIED_GOVERNANCE.md) - Layer 3 detailed spec
- [YARNNN_SUBSTRATE_CANON_V3.md](../../YARNNN_SUBSTRATE_CANON_V3.md) - Layer 1 reference
- [YARNNN_DATA_FLOW_V4.md](./YARNNN_DATA_FLOW_V4.md) - Complete request flows

---

**Four layers. Clear boundaries. Unified governance. This is YARNNN v4.0 architecture.**
