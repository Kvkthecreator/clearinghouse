# 🧶 YARNNN Monorepo

**YARNNN is an AI Work Platform where deep context understanding enables superior agent supervision.**

We integrate what others separate: context management + agent work orchestration. The result? Deploy autonomous agents with confidence, not fear.

### What Makes YARNNN Different

- **Separated Governance**: Work supervision (quality) + substrate governance (integrity) = clear boundaries
- **Context-Powered Reasoning**: Agents access deep substrate, not just retrieval
- **Multi-Checkpoint Supervision**: Iterative feedback beats binary approve/reject
- **Complete Provenance**: Every substrate change traces to work session and reasoning

**See**: [Platform Canon v4.0](docs/canon/YARNNN_PLATFORM_CANON_V4.md) for complete philosophy

---

## Architecture (v4.1 - Two-Layer with BFF Pattern)

YARNNN is built on a two-layer architecture with separated governance:

| Layer | Responsibility | Key Components |
|-------|---------------|----------------|
| **Layer 2: Work Orchestration** | Agent sessions, work supervision, tickets | PostgreSQL + FastAPI (work-platform) |
| **Layer 1: Substrate Core** | Blocks, documents, semantic layer, substrate governance | PostgreSQL + FastAPI (substrate-API) |

**Governance Separation**:
- **Work Supervision** (Layer 2): Reviews work output quality (work-platform)
- **Substrate Governance** (Layer 1): P1 proposals pipeline with semantic dedup (substrate-API)

### Technology Stack

- **Frontend**: Next.js on Vercel
- **Backend**: FastAPI on Render
- **Database**: PostgreSQL (Supabase)
- **Auth**: Supabase Auth
- **Realtime**: Supabase Realtime

**See**: [Layered Architecture v4.0](docs/architecture/YARNNN_LAYERED_ARCHITECTURE_V4.md) for complete system design

---

## Local Development  

Most tasks require only the frontend:

./start-dev.sh
If you need to work on the backend:

cd api
source $(poetry env info --path)/bin/activate
export PYTHONPATH=src
uvicorn app.agent_server:app --reload
Set `NEXT_PUBLIC_API_BASE_URL` in `web/.env.local` to point to your backend instance.
After updating the variable, redeploy the Next.js frontend so runtime route handlers pick up the new value.
You can verify the configuration by requesting /api/baskets/<id>/change-queue; the backend logs should show a GET request and a non-500 response.

The /agent endpoint handles agent requests and remains stable across deployments.

When deploying on Render, ensure the `SUPABASE_SERVICE_ROLE_KEY` environment
variable is set. Without it, Supabase requests will fail.

## Testing

yarnnn uses an **Agent-Operable Test Pipeline** for comprehensive testing:

```bash
# Run all tests (recommended)
npm run agent:test -- --subset=all

# Run specific test subsets
npm run agent:test -- --subset=canon        # Canon compliance tests
npm run agent:test -- --subset=features     # Feature E2E tests  
npm run agent:test -- --subset=unit         # Unit tests
npm run agent:test -- --subset=contracts    # Contract validation
```

The pipeline generates structured reports in `artifacts/` and is designed for agent automation. See `docs/TEST_ARCHITECTURE_AUDIT.md` for complete documentation.

## Canon Documentation (v4.0)

Core philosophy and architectural decisions are governed by canon documents:

### Philosophy
- **[Platform Canon v4.0](docs/canon/YARNNN_PLATFORM_CANON_V4.md)** - Core identity and principles
- **[Work Platform Thesis](docs/canon/YARNNN_WORK_PLATFORM_THESIS.md)** - Why context + work integration matters
- **[Governance Philosophy v4.0](docs/canon/YARNNN_GOVERNANCE_PHILOSOPHY_V4.md)** - ⚠️ Vision document (implementation uses separated governance)

### Architecture
- **[Work Orchestration Layer](docs/WORK_ORCHESTRATION_LAYER.md)** - Layer 2 specification
- **[Substrate Canon V3](docs/YARNNN_SUBSTRATE_CANON_V3.md)** - Layer 1 specification

### Legacy (v3.1)
- **[Architecture Canon](docs/YARNNN_ARCHITECTURE_CANON.md)** - Pre-v4.0 architecture (being updated)
- **[Governance Canon V5](docs/YARNNN_GOVERNANCE_CANON_V5.md)** - Superseded by v4.0
- See [Archive](docs/archive/) for historical documentation

## Repository Layout

api/   FastAPI backend
web/   Next.js frontend
tests/ Agent-operable test suites (canon/features/contracts)
scripts/ Agent test orchestration and seeding
codex/ Codex automation tasks
Quick Summary

Component	Local	Hosted
Frontend	✅	Vercel
Backend	optional	Render
DB/Auth	Hosted only	Supabase
## Developer Notes

### \ud83d\udd27 Data Fetching Architecture

Yarnnn uses a strict separation between server-side and client-side data fetching:

| Folder | Usage | SSR Safe | Auth-safe via Supabase |
|----------------------|--------------------|----------|-------------------------|
| `lib/server/*` | \u2705 Server components | \u2705 Yes | \u2705 Yes (via cookies) |
| `lib/api/*` | \u2705 Client components | \u274c No | \u2705 Yes (browser fetch) |
| `app/api/...` routes | Optional proxy | \u2705 N/A | Use sparingly; mostly deprecated |

\ud83d\udc49 Never use `fetch('/api/…')` inside server components. Always use `lib/server/*` helpers.
