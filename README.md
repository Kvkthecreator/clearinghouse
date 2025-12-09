# Clearinghouse

**IP Licensing Infrastructure for the AI Era**

Clearinghouse is a platform for registering intellectual property rights, managing AI training permissions, and licensing creative works with complete provenance tracking.

## Core Capabilities

- **Rights Registry**: Register musical works, sound recordings, voice likenesses, character IP, and visual works with industry-standard identifiers (ISRC, ISWC, etc.)
- **AI Permissions**: Define granular permissions for AI training, generation, style transfer, voice cloning, and derivative works
- **Semantic Search**: Vector-based search across your IP catalog using OpenAI embeddings
- **Governance Pipeline**: Proposal-based workflow for rights changes with configurable auto-approval rules
- **License Management**: Create license templates, grant licenses to platforms, and track usage
- **Complete Provenance**: Immutable timeline of all events with before/after states and full audit trail

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (Next.js 15)                     │
│                         /web                                 │
│                       Vercel                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   API Layer (FastAPI)                        │
│                  /substrate-api/api                          │
│                       Render                                 │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌────────────────┐    │
│  │Workspaces│ │ Catalogs │ │Entities│ │   Proposals    │    │
│  └──────────┘ └──────────┘ └────────┘ └────────────────┘    │
│  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌────────────────┐    │
│  │ Licenses │ │ Timeline │ │ Search │ │     Jobs       │    │
│  └──────────┘ └──────────┘ └────────┘ └────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 Database (PostgreSQL)                        │
│                      Supabase                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Core: workspaces, catalogs, rights_entities           │  │
│  │ Schemas: rights_schemas (extensible IP types)         │  │
│  │ Governance: proposals, governance_rules               │  │
│  │ Licensing: license_templates, grants, usage           │  │
│  │ Search: entity_embeddings (pgvector)                  │  │
│  │ Audit: timeline_events (immutable log)                │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Supported IP Types

Schema-driven architecture supports any intellectual property type. Pre-configured schemas:

| Category | IP Type | Key Fields |
|----------|---------|------------|
| Music | `musical_work` | ISWC, writers, publishers, genres |
| Music | `sound_recording` | ISRC, artist, label, duration |
| Voice | `voice_likeness` | talent_name, agency, union_affiliation |
| Character | `character_ip` | character_name, franchise, visual_assets |
| Visual | `visual_work` | artist, medium, dimensions, style |

## Technology Stack

- **Frontend**: Next.js 15 + Tailwind CSS (Vercel)
- **Backend**: FastAPI + Python (Render)
- **Database**: PostgreSQL + pgvector (Supabase)
- **Auth**: Supabase Auth with Google OAuth
- **Embeddings**: OpenAI text-embedding-3-small

## Repository Structure

```
clearinghouse/
├── web/                      # Next.js frontend (Vercel)
│   └── src/
│       ├── app/              # App router pages
│       ├── components/       # React components
│       └── lib/              # API client, Supabase, utilities
├── substrate-api/
│   └── api/                  # FastAPI backend (Render)
│       └── src/app/
│           ├── routes/       # API endpoints
│           ├── services/     # Business logic (embeddings, etc.)
│           └── main.py       # Application entry point
├── supabase/
│   └── migrations/           # Database schema
└── docs/                     # Documentation
```

## Quick Start

### Prerequisites

- Python 3.11+
- Node.js 18+
- Supabase account
- OpenAI API key (for embeddings)

### Environment Setup

1. Copy environment template:
```bash
cp .env.example .env
```

2. Configure credentials in `.env`:
```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
DATABASE_URL=postgresql://...

# OpenAI (for embeddings)
OPENAI_API_KEY=sk-...

# Frontend
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
NEXT_PUBLIC_API_URL=http://localhost:10000
```

### Run Migrations

See [SQL Execution Guide](docs/SQL_EXECUTION_GUIDE.md) for running migrations against Supabase.

### Start Development

**Frontend:**
```bash
cd web
npm install
npm run dev
```

**Backend:**
```bash
cd substrate-api/api
pip install -r requirements.txt
uvicorn src.app.main:app --reload --port 10000
```

## API Endpoints

### Health
- `GET /health` - API health check
- `GET /health/db` - Database connectivity
- `GET /health/tables` - Schema validation

### Workspaces
- `GET /api/v1/workspaces` - List user's workspaces
- `POST /api/v1/workspaces` - Create workspace
- `GET /api/v1/workspaces/{id}` - Get workspace details

### Catalogs
- `GET /api/v1/workspaces/{id}/catalogs` - List catalogs
- `POST /api/v1/workspaces/{id}/catalogs` - Create catalog

### Rights Entities
- `GET /api/v1/rights-schemas` - List IP type schemas
- `GET /api/v1/catalogs/{id}/entities` - List entities in catalog
- `POST /api/v1/catalogs/{id}/entities` - Create entity (governance-aware)
- `GET /api/v1/entities/{id}` - Get entity details
- `PATCH /api/v1/entities/{id}` - Update entity (governance-aware)
- `POST /api/v1/entities/{id}/process` - Trigger embedding generation

### Search
- `POST /api/v1/search/semantic` - Semantic search across entities
- `POST /api/v1/search/similar` - Find similar entities
- `POST /api/v1/search/filter` - Filter by permissions/attributes
- `GET /api/v1/entities/{id}/permissions` - Get entity permissions
- `POST /api/v1/query/permissions` - Batch permission check

### Governance
- `GET /api/v1/catalogs/{id}/proposals` - List proposals
- `POST /api/v1/proposals/{id}/review` - Approve/reject proposal

### Licensing
- `GET /api/v1/workspaces/{id}/license-templates` - List templates
- `POST /api/v1/entities/{id}/licenses` - Grant license

### Timeline
- `GET /api/v1/workspaces/{id}/timeline` - Workspace events
- `GET /api/v1/entities/{id}/timeline` - Entity history

## Deployments

| Service | Platform | URL |
|---------|----------|-----|
| Frontend | Vercel | https://clearinghouse.vercel.app |
| Backend | Render | https://rightnow-agent-app-fullstack.onrender.com |
| Database | Supabase | (managed) |

## Documentation

- [Infrastructure Overview](docs/CLEARINGHOUSE_INFRASTRUCTURE.md) - System design and architecture
- [Domain Model](docs/DOMAIN_MODEL.md) - Core entities and relationships
- [Data Architecture](docs/DATA_ARCHITECTURE_IMPLEMENTATION.md) - Embedding pipeline and search
- [SQL Execution Guide](docs/SQL_EXECUTION_GUIDE.md) - Database migrations
- [Migration Checklist](docs/MIGRATION_CHECKLIST.md) - Setup and deployment guide

## License

MIT License - see [LICENSE](LICENSE) for details.
