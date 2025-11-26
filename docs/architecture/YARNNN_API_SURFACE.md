# YARNNN API Surface v4.1

**Complete API Reference for Two-Layer Architecture**

**Version**: 4.1
**Date**: 2025-11-26
**Status**: ✅ Canonical
**Supersedes**: YARNNN_API_SURFACE.md (4-layer legacy)

---

## 🎯 Overview

YARNNN v4.1 exposes APIs across two layers:

- **Layer 2 (work-platform)**: Work orchestration, supervision, projects
- **Layer 1 (substrate-API)**: Substrate storage, semantic layer, governance

**Key Pattern**: work-platform calls substrate-API via HTTP (BFF pattern)

---

## 📦 Layer 1: Substrate Core API (substrate-API)

**Base URL**: `https://yarnnn-enterprise-api.onrender.com`

### Baskets (Context Containers)

```
POST   /api/baskets                    Create basket
GET    /api/baskets/{id}               Get basket details
PATCH  /api/baskets/{id}               Update basket metadata
GET    /api/baskets                    List user's baskets
```

### Raw Dumps (Initial Context)

```
POST   /api/dumps/new                  Create raw dump
GET    /api/dumps/{id}                 Get dump content
GET    /api/baskets/{id}/dumps         List basket dumps
```

### Blocks (Knowledge Substrate)

```
GET    /api/baskets/{id}/blocks        List basket blocks
GET    /api/blocks/{id}                Get block details
POST   /api/blocks/search              Semantic search
```

**Note**: Block creation goes through proposals (no direct POST /api/blocks)

### Work Outputs (Agent Deliverables)

```
POST   /api/work/outputs/new           Create work output
GET    /api/work/outputs/{id}          Get output details
PATCH  /api/work/outputs/{id}          Update output (review)
GET    /api/work/outputs               List outputs (filtered)
```

**RLS**: Scoped to basket_id (users only see their basket's outputs)

### Proposals (Substrate Governance)

```
POST   /api/proposals                  Create proposal
GET    /api/proposals/{id}             Get proposal details
PATCH  /api/proposals/{id}/approve     Approve proposal
PATCH  /api/proposals/{id}/reject      Reject proposal
GET    /api/proposals                  List pending proposals
```

**P1 Pipeline**: Proposals go through semantic dedup → quality validation → approval

### Documents (P4 Compositions)

```
GET    /api/documents/{id}             Get document
GET    /api/baskets/{id}/documents     List basket documents
POST   /api/documents/regenerate       Trigger regeneration
```

### Semantic Layer

```
POST   /substrate/semantic/search      Semantic search across blocks
GET    /substrate/relationships/{id}   Get block relationships
```

---

## 🎯 Layer 2: Work Orchestration API (work-platform)

**Base URL**: `https://yarnnn-app-fullstack.onrender.com`

### Projects (User-Facing Containers)

```
POST   /api/projects/new               Create project (scaffolds basket + dump)
GET    /api/projects/{id}              Get project details
PATCH  /api/projects/{id}              Update project metadata
GET    /api/projects                   List user's projects
```

**Scaffolding**: Creates basket (Layer 1) + project (Layer 2) + raw_dump

### Work Requests (User Asks)

```
POST   /api/work/requests              Create work request
GET    /api/work/requests/{id}         Get request details
GET    /api/work/requests              List user's requests
```

### Work Tickets (Execution Tracking)

```
GET    /api/work/tickets/{id}          Get ticket details
GET    /api/work/tickets               List tickets (filtered)
PATCH  /api/work/tickets/{id}/status   Update ticket status
```

**Status Flow**: pending → in_progress → pending_review → completed/failed

### Work Outputs Review (Work Supervision)

```
GET    /api/work/tickets/{id}/outputs  List ticket outputs
POST   /api/work/outputs/{id}/review   Review output (approve/reject)
```

**Review Decision**:
```json
{
  "status": "approved|rejected",
  "review_feedback": "Optional feedback text"
}
```

**Effect**: Updates work_output.status, does NOT create blocks

### Work Checkpoints (Mid-Work Review)

```
GET    /api/work/tickets/{id}/checkpoints     List checkpoints
POST   /api/work/checkpoints/{id}/resolve     Resolve checkpoint
```

**Checkpoint Resolution**:
```json
{
  "user_decision": "continue|reject|modify",
  "user_feedback": "Optional feedback"
}
```

### Agent Sessions

```
POST   /api/agents/sessions            Create agent session
GET    /api/agents/sessions/{id}       Get session state
PATCH  /api/agents/sessions/{id}       Resume/update session
```

### Agent Execution (Claude SDK)

```
POST   /api/agents/run                 Run agent (legacy)
POST   /api/work/execute               Execute work ticket
```

---

## 🔗 Inter-Layer Communication

### work-platform → substrate-API Calls

**Pattern**: HTTP via `substrate_client.py`

**Example**: Project Creation
```python
# work-platform code
from clients.substrate_client import get_substrate_client

substrate_client = get_substrate_client()

# Step 1: Create basket (Layer 1)
basket_response = substrate_client.create_basket(
    workspace_id=workspace_id,
    name="Research Project",
    metadata={"agent_type": "research"}
)
basket_id = basket_response["basket_id"]

# Step 2: Create raw dump (Layer 1)
dump_response = substrate_client.create_dump(
    basket_id=basket_id,
    content="Initial research context..."
)
dump_id = dump_response["dump_id"]

# Step 3: Create project (Layer 2)
supabase.table("projects").insert({
    "workspace_id": workspace_id,
    "name": "Research Project",
    "basket_id": basket_id
}).execute()
```

**Auth**: Service-to-service via `SUBSTRATE_SERVICE_SECRET` header

---

## ⚖️ Governance API Separation

### Work Supervision (work-platform)

**Endpoints**:
- `POST /api/work/outputs/{id}/review` - Approve/reject work output
- `POST /api/work/checkpoints/{id}/resolve` - Resolve checkpoint

**Effect**: Updates work_output.status, work_ticket.status

**Does NOT**: Create blocks, mutate substrate

### Substrate Governance (substrate-API)

**Endpoints**:
- `POST /api/proposals` - Create proposal
- `PATCH /api/proposals/{id}/approve` - Approve proposal → creates block
- `PATCH /api/proposals/{id}/reject` - Reject proposal

**Effect**: Creates/updates blocks via P1 pipeline

**Independent**: Works without work-platform

---

## 🔐 Authentication

### User Auth (JWT)

**Provider**: Supabase Auth

**Header**: `Authorization: Bearer <jwt_token>`

**Scopes**: User can only access their workspace's data (enforced by RLS)

### Service-to-Service Auth

**work-platform → substrate-API**:
```
Headers:
  X-Service-Secret: <SUBSTRATE_SERVICE_SECRET>
  Authorization: Bearer <user_jwt>  (optional, for user context)
```

**Purpose**: Bypass RLS for cross-service operations

---

## 📊 API Response Formats

### Success Response

```json
{
  "id": "uuid",
  "name": "Resource name",
  "created_at": "2025-11-26T10:00:00Z",
  ...
}
```

### Error Response

```json
{
  "detail": "Error message",
  "error_code": "VALIDATION_ERROR",
  "status_code": 400
}
```

### List Response

```json
{
  "data": [
    {"id": "uuid1", ...},
    {"id": "uuid2", ...}
  ],
  "count": 2,
  "pagination": {
    "limit": 20,
    "offset": 0
  }
}
```

---

## 🚀 Deployment URLs

| Service | Environment | URL |
|---------|------------|-----|
| **work-platform API** | Production | `https://yarnnn-app-fullstack.onrender.com` |
| **substrate-API** | Production | `https://yarnnn-enterprise-api.onrender.com` |
| **work-platform Frontend** | Production | `https://yarnnn-work-platform.vercel.app` |

---

## 📚 See Also

- **[YARNNN_LAYERED_ARCHITECTURE_V4.md](./YARNNN_LAYERED_ARCHITECTURE_V4.md)** - Two-layer architecture
- **[YARNNN_DATA_FLOW_V4.md](./YARNNN_DATA_FLOW_V4.md)** - Complete data flows
- **[YARNNN_PLATFORM_CANON_V4.md](../canon/YARNNN_PLATFORM_CANON_V4.md)** - Separated governance philosophy

---

**Two layers. Separated APIs. Clear boundaries. This is YARNNN v4.1 API surface.**
