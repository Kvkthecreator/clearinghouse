# Substrate Data Types

**Version**: 3.0
**Date**: 2025-12-04
**Status**: Canonical
**Purpose**: Define the foundational data taxonomy for YARNNN's substrate layer
**Changelog**: v3.0 introduces unified Context Items architecture with tiered governance

---

## Overview

YARNNN's substrate is a **source-agnostic knowledge layer** where both humans and AI agents contribute, access, and build upon shared context. This document defines the core data types that comprise the substrate.

### Design Principles

1. **Source Agnostic**: All data types can be created and accessed by both users AND agents
2. **Tiered Context**: Context Items use tiered governance (foundation, working, ephemeral)
3. **Multi-Modal Unity**: Context Items embed asset references directly, unifying text and media
4. **Token Efficiency**: Field-level context selection enables minimal, focused agent prompts
5. **Equal Authorship**: Human and agent contributions are equivalent (`created_by` tracks but doesn't restrict)
6. **Interoperability Vision**: Substrate should be shareable with any AI system (Claude, ChatGPT, Gemini)

---

## Data Type Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                     SUBSTRATE LAYER                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │          CONTEXT ITEMS (Primary for Work Recipes)         │   │
│  │                                                           │   │
│  │  Unified, tiered context with schema-driven structure     │   │
│  │  Tiers: foundation, working, ephemeral                    │   │
│  │  Tables: context_entry_schemas, context_items             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              │ embeds references to              │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              REFERENCE ASSETS (Storage Layer)             │   │
│  │                                                           │   │
│  │  Blob storage for files (images, PDFs, documents)         │   │
│  │  Table: reference_assets                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           BLOCKS (Knowledge Extraction Layer)             │   │
│  │                                                           │   │
│  │  Semantic knowledge units for RAG, search, provenance     │   │
│  │  Table: blocks                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Type 1: Context Items (Primary for Work Recipes)

**Definition**: Unified, tiered context with schema-driven structure and equal authorship.

**Characteristics**:
- **Tiered Governance**: foundation (stable), working (accumulating), ephemeral (temporary)
- One item per type per basket (singleton) or multiple (arrays like competitors)
- Structured JSONB content following type-specific field schemas
- Embedded asset references via `asset://uuid` pattern
- Completeness scoring for UX guidance
- Field-level access for token-efficient agent prompting
- Equal human + agent authorship (`created_by` tracks but doesn't restrict)
- Versioning-ready columns (Phase 2)

**Backend Tables**:
- `context_entry_schemas` - Defines available fields per item type
- `context_items` - Unified context data with tiered governance

**Schema**:
```sql
-- Schema definitions (unchanged)
CREATE TABLE context_entry_schemas (
    anchor_role TEXT PRIMARY KEY,  -- item_type
    display_name TEXT NOT NULL,
    description TEXT,
    icon TEXT,
    category TEXT CHECK (category IN ('foundation', 'market', 'insight')),
    is_singleton BOOLEAN DEFAULT true,
    field_schema JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Unified context items
CREATE TABLE context_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,

    -- Classification
    tier TEXT NOT NULL CHECK (tier IN ('foundation', 'working', 'ephemeral')),
    item_type TEXT NOT NULL,  -- 'problem', 'customer', 'vision', etc.
    item_key TEXT,            -- For non-singleton types (e.g., competitor name)

    -- Content (flexible, multi-modal)
    title TEXT,
    content JSONB NOT NULL DEFAULT '{}',
    schema_id TEXT REFERENCES context_entry_schemas(anchor_role),

    -- Multi-modal support
    asset_ids UUID[] DEFAULT '{}',
    tags TEXT[] DEFAULT '{}',
    embedding VECTOR(1536),

    -- Authorship (human OR agent, equal access)
    created_by TEXT NOT NULL,  -- 'user:{id}' or 'agent:{type}'
    updated_by TEXT,

    -- Lifecycle
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'superseded')),
    expires_at TIMESTAMPTZ,
    completeness_score FLOAT,

    -- Versioning (Phase 2)
    version INTEGER DEFAULT 1,
    previous_version_id UUID,
    source_type TEXT,
    source_ref JSONB,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    UNIQUE(basket_id, item_type, item_key)
);
```

**Example Item**:
```json
{
  "tier": "foundation",
  "item_type": "brand",
  "content": {
    "name": "Acme Corp",
    "tagline": "Building tomorrow, today.",
    "voice": "Professional yet approachable. Use active voice.",
    "logo": "asset://550e8400-e29b-41d4-a716-446655440000",
    "colors": ["#FF5733", "#3498DB", "#2ECC71"],
    "guidelines_doc": "asset://6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  },
  "created_by": "user:abc-123",
  "completeness_score": 1.0
}
```

**Use Case**: Work recipe context injection. Recipes declare which types and fields they need.

**See**: [ADR_CONTEXT_ITEMS_UNIFIED.md](../architecture/ADR_CONTEXT_ITEMS_UNIFIED.md) for full architecture.

---

## Type 2: Reference Assets (Storage Layer)

**Definition**: Blob storage for file-based content with classification metadata.

**Characteristics**:
- Files stored in Supabase Storage
- LLM-powered automatic classification
- Referenced from Context Entries via `asset://uuid` pattern
- Permanence rules (permanent vs temporary)

**Backend Table**: `reference_assets`

**Key Fields**:
```sql
id, basket_id, storage_path, file_name, mime_type,
asset_type, asset_category, classification_status,
classification_confidence, work_session_id, created_by_user_id,
context_item_id, context_field_key  -- Links to context items
```

**MIME Type Categories**:

| Category | MIME Types | Examples |
|----------|------------|----------|
| Images | `image/*` | PNG, JPEG, GIF, WebP, SVG |
| Documents | `application/pdf`, `application/vnd.openxmlformats-*` | PDF, DOCX, XLSX, PPTX |
| Data | `text/csv`, `application/json` | CSV, JSON |

**Source Identification**:
- `created_by_user_id` set → User upload
- `work_session_id` set → Agent-generated file

**Relationship to Context Items**:
- Assets are **storage units** (blobs + metadata)
- Context Items **reference** assets via `asset://uuid`
- Assets gain semantic meaning through their context item field
- Assets can link back via `context_item_id` and `context_field_key`

---

## Type 3: Blocks (Knowledge Extraction Layer)

**Definition**: Propositional knowledge units with semantic types and vector embeddings.

**Characteristics**:
- Smallest unit of extractable meaning
- Has semantic type (fact, decision, constraint, assumption, etc.)
- State-based lifecycle (PROPOSED → ACCEPTED → LOCKED)
- Vector embeddings for semantic retrieval
- Governance workflow for mutations
- Optional anchor_role for legacy compatibility

**Backend Table**: `blocks`

**Key Fields**:
```sql
id, basket_id, title, content, semantic_type, state,
embedding, anchor_role, anchor_status,
derived_from_asset_id, origin_ref, created_at
```

**Use Cases**:
- RAG (Retrieval Augmented Generation)
- Semantic search across project knowledge
- Knowledge extraction from documents
- Audit trail of extracted/approved knowledge

**NOT Used For** (as of v3.0):
- Primary work recipe context (use Context Items instead)
- Asset organization (use Context Items with embedded refs)

---

## Type 4: Entries (Legacy - Raw Content)

**Definition**: Raw text content from various sources.

**Status**: Legacy pattern. New projects should use Context Items for structured content.

**Backend Tables**:
- `raw_dumps` - User-pasted text (capture layer)
- `work_outputs` - Agent-generated text (supervision layer)

**Future**: May be deprecated as Context Items handle structured input.

---

## Source Metadata Pattern

All substrate types support source identification:

| Field | Meaning |
|-------|---------|
| `created_by_user_id` | UUID of user who created (user source) |
| `work_session_id` | UUID of agent session that created (agent source) |
| `created_by` | Formatted creator reference (Context Items): `user:{id}` or `agent:{type}` |

**UI Source Badge Logic**:
```typescript
function getSourceBadge(item: SubstrateItem) {
  if (item.work_session_id || item.agent_type) {
    return { label: 'Agent', variant: 'secondary' };
  }
  if (item.created_by_user_id || item.created_by) {
    return { label: 'User', variant: 'outline' };
  }
  return { label: 'System', variant: 'ghost' };
}
```

---

## Architectural Diagram (v3.0)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           USER INPUT LAYER                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   User fills Context Forms ──────────────► context_items (structured)    │
│           │                                      │                       │
│           │ uploads files                        │ references            │
│           ▼                                      ▼                       │
│   reference_assets ◄──────────────────── asset://uuid patterns          │
│   (blob storage)                                                         │
│                                                                          │
│   Thinking Partner Chat ──► Agent extracts ──► context_items (working)  │
│                                                                          │
│   User pastes raw text ──────────────────► raw_dumps (legacy capture)   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         PROCESSING LAYER                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   reference_assets ──► LLM Classification ──► asset_type, description   │
│                        (only for agent-produced files)                   │
│                                                                          │
│   raw_dumps ──► P0 Capture ──► P1 Extraction ──► blocks (proposed)      │
│                                                                          │
│   Document Upload ──► Context Extraction ──► context_items (fields)     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     WORK RECIPE CONTEXT ASSEMBLY                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Recipe declares:                                                       │
│     context_required:                                                    │
│       - "brand"                                                          │
│       - "customer"                                                       │
│       - "vision"                                                         │
│                                                                          │
│   ContextProvisioner:                                                    │
│     1. Query context_items by type and tier                             │
│     2. Project only required fields                                      │
│     3. Resolve asset:// references                                       │
│     4. Track staleness for working tier items                           │
│     5. Inject structured context into prompt                             │
│                                                                          │
│   Result: 500-1,500 tokens (vs 3,000-15,000 with blocks)                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            UI LAYER                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │  Context Page (Tiered Cards)                                     │  │
│   │                                                                  │  │
│   │  Foundation:                                                     │  │
│   │  [🎯 Problem 100%] [👥 Customer 80%] [🔮 Vision 40%] [🏷️ Brand] │  │
│   │                                                                  │  │
│   │  Working:                                                        │  │
│   │  [📊 Competitors 3] [📈 Trend Digest] [📋 Competitor Snapshot]  │  │
│   │                                                                  │  │
│   │  Click card → Form-based editor per schema                       │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   Legacy Views (if needed):                                              │
│   [ Blocks ] [ Raw Entries ] [ Assets ]                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Item Type Vocabulary

Context Items are organized by **item type** (formerly anchor role) and **tier**:

### Foundation Tier (Human-Established, Stable)

| Type | Description | Singleton | Governance |
|------|-------------|-----------|------------|
| `problem` | The pain point being solved | Yes | High |
| `customer` | Who this is for (persona) | Yes | High |
| `vision` | Where this is going | Yes | High |
| `brand` | Brand identity and voice | Yes | High |

### Working Tier (Human or Agent, Accumulating)

| Type | Description | Singleton | Governance |
|------|-------------|-----------|------------|
| `competitor` | Competitive intelligence | No (array) | Medium |
| `market_segment` | Market segment details | No (array) | Medium |
| `trend_digest` | Synthesized market trends | Yes | Medium (auto-accept) |
| `competitor_snapshot` | Competitive analysis summary | Yes | Medium (auto-accept) |

### Ephemeral Tier (Agent-Produced, Temporary)

| Type | Description | Singleton | Governance |
|------|-------------|-----------|------------|
| Session notes | Temporary insights | No | Low (auto-expire) |
| Draft outputs | Work in progress | No | Low (auto-expire) |

---

## Migration History

### v1.0 → v2.0 (Context Entries)

| v1.0 | v2.0 |
|------|------|
| Blocks as primary context | Context Entries as primary context |
| Assets disconnected from roles | Assets embedded in entries via `asset://` |
| Full block content in prompts | Field-level projection |
| Flat text, unstructured | Schema-driven, typed fields |

### v2.0 → v3.0 (Context Items Unified)

| v2.0 | v3.0 |
|------|------|
| `context_entries` table | `context_items` unified table |
| `anchor_role`, `entry_key`, `data` | `item_type`, `item_key`, `content` |
| No tier concept | Tiered governance (foundation/working/ephemeral) |
| Human-primary authorship | Equal human + agent authorship |
| No versioning | Versioning-ready columns (Phase 2) |
| `state` column | `status` column |

### Coexistence Strategy

- **Context Items**: New unified context management (work recipes)
- **Blocks**: Knowledge extraction, RAG, search (unchanged)
- **Reference Assets**: Storage layer (now referenced from items)
- **raw_dumps**: Legacy capture (may be deprecated)

---

## Related Documents

- [ADR_CONTEXT_ITEMS_UNIFIED.md](../architecture/ADR_CONTEXT_ITEMS_UNIFIED.md) - Unified Context Items architecture
- [CONTEXT_ROLES_ARCHITECTURE.md](CONTEXT_ROLES_ARCHITECTURE.md) - Legacy anchor role architecture
- [TERMINOLOGY_GLOSSARY.md](TERMINOLOGY_GLOSSARY.md) - Terminology standards
- [AGENT_SUBSTRATE_ARCHITECTURE.md](AGENT_SUBSTRATE_ARCHITECTURE.md) - Agent integration patterns

---

**End of Document**
