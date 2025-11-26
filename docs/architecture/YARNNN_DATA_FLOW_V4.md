# YARNNN Data Flow v4.1

**Complete Work Flow with Separated Governance**

**Version**: 4.1
**Date**: 2025-11-26
**Status**: ✅ Canonical
**Supersedes**: YARNNN_DATA_FLOW_V4.md (unified governance legacy)

---

## 🎯 Overview

This document traces complete data flows through YARNNN's two-layer architecture with **separated governance**:

- **Work Supervision** (work-platform): Reviews work output quality
- **Substrate Governance** (substrate-API): P1 proposals with semantic dedup

**Key Insight**: YARNNN's value emerges from tight integration between work orchestration (Layer 2) and substrate core (Layer 1), but with INDEPENDENT governance systems.

---

## 📋 Complete Work Session Flow

### Phase 1: Project Creation

```
User Action: Create new project
  ↓
POST /api/projects/new (work-platform)
  ↓
work-platform → substrate-API: POST /api/baskets
  ↓
Basket created (substrate-API DB)
  ↓
work-platform → substrate-API: POST /api/dumps/new
  ↓
raw_dump created (initial context)
  ↓
work-platform DB: INSERT INTO projects
  ↓
Response: {project_id, basket_id, dump_id}
```

**Tables Modified**:
- `baskets` (substrate-API)
- `raw_dumps` (substrate-API)
- `projects` (work-platform)

---

### Phase 2: Work Request Creation

```
User Action: Create work request
  ↓
POST /api/work/requests (work-platform)
  ↓
work-platform DB: INSERT INTO work_requests
  ↓
work-platform DB: INSERT INTO work_tickets (status: pending)
  ↓
Response: {work_request_id, work_ticket_id}
```

**Tables Modified**:
- `work_requests` (work-platform)
- `work_tickets` (work-platform)

---

### Phase 3: Agent Execution

```
Agent Starts (Claude SDK session)
  ↓
work-platform DB: UPDATE work_tickets SET status='in_progress'
  ↓
Agent Tool Call: query_context(query_text)
  ↓
work-platform → substrate-API: POST /substrate/semantic/search
  ↓
substrate-API: SELECT * FROM blocks + embeddings (semantic search)
  ↓
Response: [block1, block2, block3] (relevant context)
  ↓
Agent reasons with Claude + context
  ↓
Agent Tool Call: emit_work_output(output_type, content)
  ↓
work-platform → substrate-API: POST /work/outputs/new
  ↓
substrate-API DB: INSERT INTO work_outputs (status: pending_review)
  ↓
Agent continues until task complete
  ↓
work-platform DB: UPDATE work_tickets SET status='pending_review'
```

**Tables Modified**:
- `work_tickets` (work-platform - status updates)
- `work_outputs` (substrate-API - basket-scoped RLS)
- Timeline queries to `blocks`, `embeddings` (substrate-API - read-only)

**Key Point**: work_outputs stored in substrate-API for basket-scoped RLS, but referenced by work-platform

---

### Phase 4: Work Supervision (Layer 2)

```
User Action: Review work outputs
  ↓
GET /api/work/tickets/{ticket_id}/outputs (work-platform)
  ↓
work-platform → substrate-API: GET /work/outputs?work_ticket_id={id}
  ↓
Response: [output1 (pending_review), output2 (pending_review)]
  ↓
User Decision: Approve output1, Reject output2
  ↓
POST /api/work/outputs/{output1_id}/review (work-platform)
  body: {status: "approved", feedback: "Good work"}
  ↓
work-platform → substrate-API: PATCH /work/outputs/{output1_id}
  ↓
substrate-API DB: UPDATE work_outputs
  SET status='approved', reviewed_at=NOW()
  WHERE id=output1_id
  ↓
POST /api/work/outputs/{output2_id}/review (work-platform)
  body: {status: "rejected", feedback: "Needs more evidence"}
  ↓
work-platform → substrate-API: PATCH /work/outputs/{output2_id}
  ↓
substrate-API DB: UPDATE work_outputs SET status='rejected'
  ↓
work-platform DB: UPDATE work_tickets SET status='completed'
```

**Tables Modified**:
- `work_outputs` (substrate-API - status, review fields)
- `work_tickets` (work-platform - status transition)

**Key Point**: Work supervision ends here. NO automatic substrate mutation.

---

### Phase 5: Substrate Governance (Layer 1) - [FUTURE]

**Current State**: No automatic bridge. Approved work_outputs do NOT auto-create blocks.

**Future Bridge Flow** (Deferred):
```
work_output.status = 'approved'
  ↓
[Manual or Automated Trigger]
  ↓
substrate-API: INSERT INTO proposals
  (content=work_output.body, source=work_output_id)
  ↓
P1 Pipeline: Semantic Deduplication Check
  ↓
P1 Pipeline: Quality Validation
  ↓
P1 Pipeline: Merge Detection
  ↓
(If needed) User approves proposal
  ↓
substrate-API DB: INSERT INTO blocks (state: ACCEPTED)
  ↓
substrate-API DB: UPDATE proposals SET status='approved'
  ↓
Timeline event: block_created
  ↓
Notify work-platform of result (optional)
```

**Decision**: Deferred until usage patterns understood. Maintains substrate integrity.

---

## 🔄 Alternative Flow: Direct Substrate Proposal (No Work Platform)

Users can still create substrate proposals directly without work-platform:

```
User Action: Create proposal (via substrate frontend or API)
  ↓
POST /api/proposals (substrate-API)
  ↓
substrate-API DB: INSERT INTO proposals
  ↓
P1 Pipeline (same as above)
  ↓
Block created
```

**Key Point**: Substrate governance works independently of work-platform.

---

## 📊 Data Flow Diagram

```
┌──────────────────────────────────────────────────────────┐
│ User creates project                                      │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ work-platform: projects, work_requests, work_tickets     │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ substrate-API: baskets, raw_dumps                        │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ Agent executes (queries substrate context)               │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ Agent emits work_outputs (stored in substrate-API)       │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ WORK SUPERVISION: User reviews outputs (work-platform)   │
│ → approved/rejected (no substrate mutation)              │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ [FUTURE] Approved outputs → substrate proposals          │
└────────────┬─────────────────────────────────────────────┘
             ↓
┌──────────────────────────────────────────────────────────┐
│ SUBSTRATE GOVERNANCE: P1 pipeline validates              │
│ → blocks created (state: ACCEPTED)                       │
└──────────────────────────────────────────────────────────┘
```

---

## 🗄️ Table Interactions Summary

### Work-Platform Tables (Direct Access)

| Table | Create | Read | Update | Delete |
|-------|--------|------|--------|--------|
| `projects` | ✅ | ✅ | ✅ | ⏸️ |
| `work_requests` | ✅ | ✅ | ❌ | ❌ |
| `work_tickets` | ✅ | ✅ | ✅ (status) | ❌ |
| `work_checkpoints` | ✅ | ✅ | ✅ (resolve) | ❌ |
| `agent_sessions` | ✅ | ✅ | ✅ | ❌ |

### Substrate-API Tables (HTTP Access via substrate_client)

| Table | Create | Read | Update | Delete |
|-------|--------|------|--------|--------|
| `baskets` | ✅ (HTTP) | ✅ (HTTP) | ✅ (HTTP) | ❌ |
| `raw_dumps` | ✅ (HTTP) | ✅ (HTTP) | ❌ | ❌ |
| `blocks` | ❌ | ✅ (HTTP) | ❌ | ❌ |
| `work_outputs` | ✅ (HTTP) | ✅ (HTTP) | ✅ (HTTP) | ❌ |
| `proposals` | ⏸️ (future) | ✅ (HTTP) | ❌ | ❌ |
| `documents` | ❌ | ✅ (HTTP) | ❌ | ❌ |

**Key**: ✅ = Supported, ❌ = Not supported, ⏸️ = Deferred/partial

---

## 📚 See Also

- **[YARNNN_LAYERED_ARCHITECTURE_V4.md](./YARNNN_LAYERED_ARCHITECTURE_V4.md)** - Two-layer architecture
- **[YARNNN_PLATFORM_CANON_V4.md](../canon/YARNNN_PLATFORM_CANON_V4.md)** - Separated governance philosophy
- **[Legacy Unified Governance](../archive/legacy-unified-governance/README.md)** - Why it was deprecated

---

**Two layers. Separated governance. Clear data flows. This is YARNNN v4.1.**
