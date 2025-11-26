# YARNNN Layered Architecture v4.1

**Two-Layer Architecture with Separated Governance**

**Version**: 4.1 (Corrected Architecture)
**Date**: 2025-11-26
**Status**: ✅ Canonical
**Supersedes**: YARNNN_LAYERED_ARCHITECTURE_V4.md (4-layer legacy)
**Audience**: Engineering, Architecture, Technical PM

---

## 🎯 Overview

YARNNN v4.1 is built on a **two-layer architecture** with **separated governance**. This design enables:

- **Clear domain separation** - Work orchestration vs substrate storage
- **Independent governance** - Work supervision vs substrate validation
- **BFF pattern** - work-platform calls substrate-API via HTTP
- **Separated frontends** - Each layer has independent UI

### **IMPORTANT**: Architecture Correction (2025-11-19)

The original v4.0 vision described a "unified governance" Layer 3 that would merge work quality review and substrate integrity checks. This approach was **deprecated** because:

1. **Governance bypass**: Bypassed substrate's P1 proposals pipeline
2. **Lost semantic dedup**: Direct block creation skipped duplicate detection
3. **Domain confusion**: Mixed work quality concerns with substrate integrity

**Current Reality**: SEPARATED governance (work supervision + substrate governance)

**See**: `docs/archive/legacy-unified-governance/README.md` for deprecation details

---

## 📦 The Two Layers

```
┌────────────────────────────────────────────────────────────┐
│ LAYER 2: WORK ORCHESTRATION (work-platform)                │
│                                                              │
│ Backend (FastAPI on Render):                                │
│ - agent_sessions (persistent Claude SDK sessions)           │
│ - work_requests (user asks: what they want done)            │
│ - work_tickets (execution tracking)                         │
│ - work_outputs (agent deliverables)                         │
│ - work_checkpoints (approval stages)                        │
│ - projects (user-facing work containers)                    │
│                                                              │
│ Frontend (Next.js on Vercel):                               │
│ - Work review UI (WORK SUPERVISION)                         │
│ - Agent dashboards                                          │
│ - Project management                                        │
└────────────────────────────────────────────────────────────┘
                      ↓ BFF calls (HTTP)
┌────────────────────────────────────────────────────────────┐
│ LAYER 1: SUBSTRATE CORE (substrate-API)                    │
│                                                              │
│ Backend (FastAPI - serves as BFF for Layer 2):             │
│ - blocks (knowledge substrate)                              │
│ - work_outputs (agent deliverables - basket-scoped RLS)    │
│ - documents (P4 compositions)                               │
│ - insights (P3 reflections)                                 │
│ - timeline events (activity stream)                         │
│ - proposals (P1 SUBSTRATE GOVERNANCE pipeline)              │
│ - semantic layer (embeddings, relationships)                │
│                                                              │
│ Frontend (Next.js - scaffolding exists, not fully functional)│
│ - Substrate management UI (view blocks, documents)          │
└────────────────────────────────────────────────────────────┘

                  SEPARATED GOVERNANCE
┌──────────────────────────┬──────────────────────────────┐
│ Work Supervision         │ Substrate Governance         │
│ (Layer 2: work-platform) │ (Layer 1: substrate-API)     │
├──────────────────────────┼──────────────────────────────┤
│ - work_outputs review    │ - P1 proposals pipeline      │
│ - pending_review →       │ - Semantic deduplication     │
│   approved/rejected      │ - Quality validation         │
│ - User reviews agent     │ - Block state transitions    │
│   output quality         │ - Merge detection            │
│ - NO auto-substrate      │ - Proposal approval          │
│   update                 │                              │
└──────────────────────────┴──────────────────────────────┘
```

---

## 🔄 Layer 1: Substrate Core (substrate-API)

### Responsibility

**Store and retrieve structured knowledge with semantic intelligence and governance.**

### Key Tables

| Table | Purpose | Governance |
|-------|---------|-----------|
| `blocks` | Structured knowledge units | P1 proposals pipeline |
| `proposals` | Pending block changes | Semantic dedup, quality validation |
| `work_outputs` | Agent deliverables | Basket-scoped RLS |
| `documents` | Immutable compositions | Direct creation (P4) |
| `insights` | Interpretive intelligence | Direct regeneration (P3) |
| `timeline_events` | Activity stream | Append-only |
| `embeddings` | Vector semantic layer | Auto-generated |
| `relationships` | Causal/semantic links | Extracted from blocks |

### Substrate Governance (P1 Pipeline)

```
Block Proposal
  ↓
Semantic Deduplication Check
  ↓
Quality Validation
  ↓
Merge Detection
  ↓
User Approval (if needed)
  ↓
Block Created/Updated (state: ACCEPTED)
  ↓
Timeline Event Emitted
```

**Key Point**: ALL blocks must go through proposals. No direct ACCEPTED block creation.

---

## 🎯 Layer 2: Work Orchestration (work-platform)

### Responsibility

**Manage agent work lifecycle from task intent → execution → supervision → completion.**

### Key Tables

| Table | Purpose | Supervision |
|-------|---------|------------|
| `projects` | User-facing work containers | N/A (metadata only) |
| `agent_sessions` | Persistent Claude SDK sessions | N/A (execution state) |
| `work_requests` | User asks (what they want) | N/A (intent capture) |
| `work_tickets` | Execution tracking | Status transitions |
| `work_outputs` | Agent deliverables | Work supervision (approve/reject) |
| `work_checkpoints` | Mid-work approval points | Checkpoint resolution |
| `project_agents` | Agent instances + configs | N/A (configuration) |

### Work Supervision Flow

```
Work Ticket Created
  ↓
Agent Executes (emits work_outputs via tool calls)
  ↓
work_outputs status: pending_review
  ↓
User Reviews Output Quality
  ↓
approved → work_output.status = 'approved'
rejected → work_output.status = 'rejected'
  ↓
[FUTURE] Approved outputs MAY feed substrate proposals
(currently: no automatic bridge)
```

**Key Point**: Work supervision reviews OUTPUT QUALITY, NOT substrate integrity.

---

## 🔗 Layer Integration (BFF Pattern)

### work-platform → substrate-API Communication

**Pattern**: HTTP calls via `substrate_client.py`

**Example Operations**:
```python
# From work-platform
substrate_client = get_substrate_client()

# Query context for agent reasoning
blocks = substrate_client.get_basket_blocks(basket_id)

# Create raw dump (initial context)
dump_id = substrate_client.create_dump(basket_id, content)

# Fetch semantic search results
results = substrate_client.semantic_search(query, basket_id)
```

**Architecture Compliance**:
- ✅ work-platform NEVER accesses substrate tables directly
- ✅ All substrate operations via HTTP calls
- ✅ Circuit breaker + retries in substrate_client
- ✅ Dual auth: Service-to-service + User JWT

---

## ⚖️ Governance Separation

### Why Separated (Not Unified)?

**Original Vision (v4.0 - Deprecated)**:
- Single user approval → dual effect (work quality + substrate mutation)
- Eliminated "double-approval" pain

**Why It Failed**:
1. **Bypassed substrate governance**: Direct ACCEPTED block creation skipped P1 pipeline
2. **Lost semantic deduplication**: No duplicate detection
3. **Lost quality validation**: No substrate-level quality checks
4. **Domain confusion**: Mixed work concerns with substrate concerns

**Current Approach (v4.1 - Implemented)**:
- **Work Supervision** (work-platform): "Is this output good work?"
- **Substrate Governance** (substrate-API): "Should this become memory?"
- **Intentionally separated**: Each system maintains its own integrity guarantees

### Future Bridge (Deferred)

**Potential Future Flow**:
```
work_output.status = 'approved'
  ↓
[Optional Bridge Layer]
  ↓
Create substrate proposal (NOT direct block)
  ↓
Substrate P1 pipeline validates
  ↓
Proposal approved → block created
  ↓
Notify work-platform of result
```

**Decision**: Deferred until usage patterns understood. For now, separation is intentional.

---

## 🗄️ Database Architecture

### Database Separation

| Database | Owner | Tables |
|----------|-------|--------|
| **Supabase (shared)** | Both layers | All tables (separated by RLS) |

**Key Point**: Single physical database, but logical separation via:
- RLS policies (basket_id, workspace_id scoping)
- Domain boundaries (work-platform vs substrate-API ownership)
- HTTP access patterns (work-platform calls substrate-API)

### Table Ownership

| Table | Owner | Access Pattern |
|-------|-------|----------------|
| `blocks` | substrate-API | HTTP via substrate_client |
| `proposals` | substrate-API | HTTP via substrate_client |
| `work_outputs` | substrate-API | HTTP via substrate_client (basket RLS) |
| `documents` | substrate-API | HTTP via substrate_client |
| `insights` | substrate-API | HTTP via substrate_client |
| `timeline_events` | substrate-API | HTTP via substrate_client |
| `agent_sessions` | work-platform | Direct DB (supabase_client) |
| `work_requests` | work-platform | Direct DB (supabase_client) |
| `work_tickets` | work-platform | Direct DB (supabase_client) |
| `work_checkpoints` | work-platform | Direct DB (supabase_client) |
| `projects` | work-platform | Direct DB (supabase_client) |
| `project_agents` | work-platform | Direct DB (supabase_client) |

---

## 🎨 Frontend Architecture

### Separated Frontends

**work-platform Frontend** (Next.js on Vercel):
- Location: `work-platform/web/`
- Purpose: Work review UI, agent dashboards, project management
- Status: ✅ Fully functional
- Routes: `/projects/[id]`, `/work-tickets`, `/agents`

**substrate-API Frontend** (Next.js - scaffolding):
- Location: `substrate-api/web/`
- Purpose: Substrate management UI (view blocks, documents)
- Status: ⏸️ Scaffolding exists, not fully functional
- Routes: `/baskets/[id]`, `/blocks`, `/documents`

**Key Point**: No shared Layer 4 presentation. Each layer has independent frontend.

---

## 📊 Data Flow Example

### Complete Work Session Flow

```
1. User creates project (work-platform)
   ↓
2. work-platform → substrate-API: Create basket + dump
   ↓
3. User creates work request (work-platform)
   ↓
4. Agent executes (Claude SDK session)
   ↓
5. Agent queries context (substrate-API via HTTP)
   ↓
6. Agent emits work_outputs (tool calls)
   ↓
7. work_outputs.status = 'pending_review'
   ↓
8. User reviews in work-platform UI
   ↓
9. User approves → work_output.status = 'approved'
   ↓
10. [FUTURE] Approved output feeds substrate proposal
   ↓
11. [FUTURE] Substrate P1 pipeline validates
   ↓
12. [FUTURE] Block created (state: ACCEPTED)
```

**Current State**: Steps 10-12 deferred (no automatic bridge)

---

## 🚀 Deployment Architecture

### Services

| Service | Deployment | URL |
|---------|-----------|-----|
| **work-platform API** | Render | `https://yarnnn-app-fullstack.onrender.com` |
| **substrate-API** | Render | `https://yarnnn-enterprise-api.onrender.com` |
| **work-platform Frontend** | Vercel | `https://yarnnn-work-platform.vercel.app` |
| **substrate-API Frontend** | Vercel | `https://yarnnn-substrate-frontend.vercel.app` |
| **Database** | Supabase | `https://galytxxkrbksilekmhcw.supabase.co` |

### Inter-Service Communication

```
work-platform API (Render)
  ↓ HTTP calls
substrate-API (Render)
  ↓ PostgreSQL
Supabase Database
```

**Auth**:
- Service-to-service: `SUBSTRATE_SERVICE_SECRET` header
- User requests: JWT from Supabase Auth

---

## 📚 See Also

- **[YARNNN_PLATFORM_CANON_V4.md](../canon/YARNNN_PLATFORM_CANON_V4.md)** - Philosophy and principles
- **[AGENT_SUBSTRATE_ARCHITECTURE.md](../canon/AGENT_SUBSTRATE_ARCHITECTURE.md)** - Current implementation roadmap
- **[TERMINOLOGY_GLOSSARY.md](../canon/TERMINOLOGY_GLOSSARY.md)** - Domain terminology
- **[Legacy Unified Governance](../archive/legacy-unified-governance/README.md)** - Why it was deprecated

---

**Two layers. Separated governance. Clear boundaries. This is YARNNN v4.1 architecture.**
