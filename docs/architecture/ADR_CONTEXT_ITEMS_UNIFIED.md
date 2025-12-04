# ADR: Unified Context Items Architecture

**ADR Number**: ADR-2025-12-04
**Title**: Unified Context Items with Tiered Memory Model
**Status**: Proposed
**Date**: 2025-12-04
**Author**: Architecture Team
**Supersedes**: ADR_CONTEXT_ENTRIES.md (refinement, not replacement)

---

## Executive Summary

This ADR documents the evolution of the Context Entries architecture toward a **unified `context_items` table** that:

1. Consolidates all context tiers (foundation, working, ephemeral) in one table
2. Supports human AND agent authorship equally
3. Prepares for versioning without implementing it yet
4. Enables the Thinking Partner use case as a stress test
5. Aligns with cognitive memory type patterns

This is a refinement of the Context Entries architecture, not a complete rewrite.

---

## How We Got Here: The Discussion Journey

### Starting Point: Context Entries Pivot (Dec 3)

The initial Context Entries architecture solved key problems:
- **Unstructured blocks** → Structured schemas with typed fields
- **Asset disconnection** → Assets embedded via `asset://uuid` pattern
- **Token inefficiency** → Field-level projection in recipes
- **Non-determinism** → Schema-driven, predictable retrieval

### Second-Order Questions Emerged (Dec 4)

After committing to the pivot, deeper considerations surfaced:

1. **Rigidity vs Flexibility**
   - Fixed entry types (anchor roles) are bound to schemas
   - What about context that doesn't fit predefined categories?
   - Are we losing the "magic" of fluid, chat-based context discovery?

2. **Philosophy Gap from Original Blocks**
   - Original blocks had: evolution (versioning), governance, provenance
   - Current entries have: determinism, multi-modal, predictability
   - Something was lost in the trade

3. **Who Can Author Context?**
   - Current design privileges human form-filling
   - Thinking Partner (agent) should have equal authorship
   - This opens the input/storage/retrieval mode separation

4. **Version Control / Evolution**
   - Current entries are flat (latest state only)
   - Founder's understanding evolves over time
   - No way to see "how did my thinking change?"

### Key Insight: Memory Type Parallel

The tier system maps to cognitive memory types:

| Memory Type | Context Tier | Characteristics |
|-------------|--------------|-----------------|
| **Semantic** | Foundation | Stable, definitional, slow to change |
| **Episodic** | Working | Event-based, accumulates, fades |
| **Working** | Ephemeral | Short-term, request-scoped, discarded |

This isn't accidental - we're building a cognitive architecture for a business.

### The Stress Test Proposal

**Reverse engineer from chat LLM interfaces** to validate the architecture:

If a Thinking Partner chat interface can work well with this context system, then:
- Deterministic recipes are just a constrained subset
- The architecture serves both fluid and structured use cases
- We've proven the general case

---

## Decision Statement

**We will unify all context into a single `context_items` table with tier-based governance.**

Key aspects:

1. **Single table, all tiers** - No separate tables for different context types
2. **Human + Agent equal** - `created_by` doesn't privilege either
3. **Versioning-ready** - Columns present but not enforced yet
4. **Provenance-ready** - Source tracking built in
5. **Flexible item types** - Start with known types, add more without migrations
6. **Thinking Partner as validator** - Chat interface proves the architecture

---

## Design Principles

### 1. Separation of Concerns

```
INPUT MODE:      How context ENTERS the system
                 (forms, chat extraction, agent production, import)

STORAGE MODE:    How context is ORGANIZED
                 (unified table, tiered governance)

RETRIEVAL MODE:  How context is USED
                 (tier-based queries, tag matching, semantic search)
```

These are decoupled. Fluid input can feed structured storage.

### 2. Governance by Tier, Not by Table

| Tier | Governance Level | Versioning | Primary Authors |
|------|------------------|------------|-----------------|
| **Foundation** | High (changes are significant) | Full history (Phase 2) | Human primary, agent can propose |
| **Working** | Medium (auto-accept, can revert) | Recent history (Phase 2) | Human + agent equal |
| **Ephemeral** | Low (append-only, auto-expire) | None | Agent primary |

### 3. Equal Authorship

Context entries should be equally accessible to:
- Human via forms
- Human via chat (Thinking Partner extracts)
- Agent via work outputs
- Agent via direct contribution (Thinking Partner writes)

The `created_by` field tracks author but doesn't restrict operations.

### 4. Additive Schema Design

Leave room for future columns without requiring them now:
- Version tracking columns present, nullable
- Provenance columns present, nullable
- Embeddings column present for semantic search

---

## Schema Design: `context_items`

```sql
CREATE TABLE context_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,

    -- Classification
    tier TEXT NOT NULL CHECK (tier IN ('foundation', 'working', 'ephemeral')),
    item_type TEXT NOT NULL,  -- 'problem', 'customer', 'note', 'insight', etc.
    item_key TEXT,            -- For non-singleton types (e.g., competitor name)

    -- Content (flexible, multi-modal)
    title TEXT,
    content JSONB NOT NULL DEFAULT '{}',  -- Structured fields OR freeform

    -- Schema reference (optional - for structured types)
    schema_id TEXT REFERENCES context_entry_schemas(anchor_role),

    -- Multi-modal support
    asset_ids UUID[] DEFAULT '{}',  -- Direct asset references

    -- Retrieval support
    tags TEXT[] DEFAULT '{}',       -- User/agent-defined tags
    embedding VECTOR(1536),         -- For semantic search

    -- Authorship (human OR agent, equal access)
    created_by TEXT NOT NULL,       -- 'user:{id}' or 'agent:{type}'
    updated_by TEXT,

    -- Lifecycle
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'archived', 'superseded')),
    expires_at TIMESTAMPTZ,         -- For ephemeral tier

    -- PHASE 2: Versioning (columns present, not enforced)
    version INTEGER DEFAULT 1,
    previous_version_id UUID REFERENCES context_items(id),

    -- PHASE 2: Provenance (columns present, not enforced)
    source_type TEXT,               -- 'manual', 'extracted', 'generated', 'imported'
    source_ref JSONB,               -- {"work_output_id": "..."} or {"url": "..."}

    -- Completeness (for structured types)
    completeness_score FLOAT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    -- Uniqueness (for structured singletons)
    UNIQUE(basket_id, item_type, item_key)
);

-- Indexes for different retrieval patterns
CREATE INDEX idx_context_items_basket_tier ON context_items(basket_id, tier);
CREATE INDEX idx_context_items_type ON context_items(basket_id, item_type);
CREATE INDEX idx_context_items_tags ON context_items USING GIN(tags);
CREATE INDEX idx_context_items_active ON context_items(basket_id) WHERE status = 'active';
CREATE INDEX idx_context_items_schema ON context_items(schema_id) WHERE schema_id IS NOT NULL;
```

### Why Single Table is Future-Proof

**Concern**: Is a single table limiting?

**Answer**: No, for these reasons:

1. **Tier is just a column** - Query foundation only, or all tiers, with simple WHERE
2. **Type is flexible** - Add new types without migrations, just insert
3. **Schema is optional** - Structured types reference schemas, freeform types don't
4. **Versioning is additive** - When we implement, we just start using the columns
5. **Provenance is additive** - Same pattern
6. **Indexes are targeted** - Different access patterns covered by specific indexes

**When would we need multiple tables?**

Only if different tiers need fundamentally different:
- Column sets (unlikely - they're all context)
- RLS policies (possible - but can be tier-based in one table)
- Performance characteristics (unlikely at our scale)

At current and projected scale, single table with tier column is simpler and equally performant.

---

## Migration Strategy: Replacing Context Entries

### Current State

```
context_entry_schemas  (7 anchor roles seeded)
context_entries        (structured entries per basket)
reference_assets       (has context_entry_id, context_field_key)
```

### Target State

```
context_entry_schemas  (kept - defines field structure for structured types)
context_items          (unified table - replaces context_entries)
reference_assets       (updated - context_item_id replaces context_entry_id)
```

### Migration Steps

**Phase 1: Create New Table (Non-Destructive)**

```sql
-- Create context_items table
-- Migrate existing context_entries data
-- Update reference_assets FK
```

**Phase 2: Update Application Code**

- Substrate-API: New routes for context_items CRUD
- Work Platform API: Update ContextProvisioner
- Frontend: Update context page to use new endpoints

**Phase 3: Cleanup**

```sql
-- Drop context_entries table
-- Update reference_assets constraint
```

### Data Migration Query

```sql
-- Migrate context_entries → context_items
INSERT INTO context_items (
    id,
    basket_id,
    tier,
    item_type,
    item_key,
    title,
    content,
    schema_id,
    status,
    completeness_score,
    created_by,
    created_at,
    updated_at
)
SELECT
    ce.id,
    ce.basket_id,
    ces.category AS tier,  -- foundation/market/insight → foundation/working/ephemeral
    ce.anchor_role AS item_type,
    ce.entry_key AS item_key,
    ce.display_name AS title,
    ce.data AS content,
    ce.anchor_role AS schema_id,
    ce.state AS status,
    ce.completeness_score,
    COALESCE('user:' || ce.created_by::text, 'user:unknown') AS created_by,
    ce.created_at,
    ce.updated_at
FROM context_entries ce
JOIN context_entry_schemas ces ON ces.anchor_role = ce.anchor_role;
```

### Tier Mapping

| context_entry_schemas.category | context_items.tier |
|--------------------------------|-------------------|
| foundation | foundation |
| market | working |
| insight | ephemeral (or working, based on TTL) |

---

## Thinking Partner Integration

### Tool Definitions

The Thinking Partner agent gets these tools:

```python
# 1. Read Context
read_context(basket_id, tier=None, item_type=None, tags=None)
# Returns context items matching filters

# 2. Write Context
write_context(basket_id, tier, item_type, content, tags=None, schema_id=None)
# Creates/updates context item
# For foundation tier, may require user confirmation

# 3. List Work Recipes
list_recipes(basket_id)
# Returns available recipes with context requirements

# 4. Trigger Work
trigger_work(basket_id, recipe_slug, params=None)
# Creates work ticket from recipe
```

### Conversation Flow

```
User: "Help me write a landing page for my SaaS"

Thinking Partner:
1. read_context(basket_id, tier='foundation')
   → Gets problem, customer, vision, brand

2. If incomplete:
   → Chat to extract missing info
   → write_context(basket_id, 'foundation', 'customer', {...})

3. list_recipes(basket_id)
   → Finds "landing-page-copy" recipe

4. trigger_work(basket_id, 'landing-page-copy')
   → Creates work ticket

5. Returns progress to user
```

### Why This Validates Everything

If Thinking Partner works well:
- Context retrieval serves open-ended use ✓
- Context can be authored by agents naturally ✓
- Work orchestration can be triggered conversationally ✓
- Structured substrate doesn't fight fluid interface ✓

**The chat interface IS the proving ground.**

---

## What's Deferred to Phase 2

### Versioning

When we implement:
- Each edit creates new row with incremented version
- `previous_version_id` links to prior version
- Query always gets MAX(version) for active view
- History view shows all versions for an item

### Provenance

When we implement:
- Track source of each context item
- Show "extracted from: [document name]"
- Show "generated by: [recipe name]"
- Enable trust calibration

### Evolution View

When we implement:
- Timeline of changes per item
- "How has my customer definition evolved?"
- Diff between versions

---

## Relationship to Existing Systems

### Kept (No Changes)

| Component | Purpose |
|-----------|---------|
| `context_entry_schemas` | Defines field structure for structured types |
| `blocks` table | Knowledge extraction, RAG, semantic search |
| `reference_assets` | File storage layer |

### Replaced

| Old | New | Notes |
|-----|-----|-------|
| `context_entries` | `context_items` | More flexible, tier-based |
| `context_entries.anchor_role` | `context_items.item_type` | Same concept, clearer name |
| `context_entries.data` | `context_items.content` | Same structure |

### Updated

| Component | Change |
|-----------|--------|
| `reference_assets.context_entry_id` | → `context_item_id` |
| ContextProvisioner | Query from `context_items` |
| Recipe context requirements | Same format, different table |

---

## Success Criteria

1. **Thinking Partner can have natural conversations** that create/update context
2. **Deterministic recipes work unchanged** (or with minimal changes)
3. **Foundation context feels deliberate**, working context feels fluid
4. **No data loss** during migration
5. **Versioning can be added later** without schema changes

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Single table becomes bloated | Tier-based archival, ephemeral expiration |
| Thinking Partner scope creep | Timebox MVP to 4 tools only |
| Migration breaks existing flows | Feature flag, parallel operation period |
| Versioning complexity deferred too long | Columns present, can implement incrementally |

---

## Open Questions

1. **Should `trend_digest` and `competitor_snapshot` be ephemeral or working tier?**
   - Leaning: Working tier with TTL-based staleness, not hard expiration

2. **How does semantic search interact with tiers?**
   - Leaning: Search across all tiers, weight by tier in ranking

3. **Should Thinking Partner edits to foundation require approval?**
   - Leaning: Yes for foundation, no for working/ephemeral

---

## Appendix: Discussion Transcript Themes

### Theme 1: Structured vs Derived Context

**Question**: Should context be explicitly structured or derived from chat?

**Resolution**: Both. Structured storage, multiple input modes. The architecture supports:
- Explicit forms (current)
- Chat-based extraction (Thinking Partner)
- Agent production (work outputs)
- Import (documents, URLs)

### Theme 2: Memory Type Analogy

**Observation**: The tier system mirrors cognitive memory:
- Semantic memory → Foundation (stable, definitional)
- Episodic memory → Working (event-based, accumulates)
- Working memory → Ephemeral (short-term, discards)

**Implication**: Not accidental. We're building a cognitive architecture.

### Theme 3: Thinking Partner as Stress Test

**Proposal**: Build Thinking Partner first to validate architecture.

**Rationale**: If the most general case (open-ended chat) works, constrained cases (recipes) definitely work.

### Theme 4: Versioning Deferral

**Decision**: Add columns now, implement later.

**Rationale**: Focus on landing context types and tiers. Version control is Phase 2.

### Theme 5: Equal Authorship

**Principle**: Human and agent context contributions should be equivalent.

**Implementation**: `created_by` tracks author but doesn't restrict operations.

---

**Document Status**: Proposed
**Last Updated**: 2025-12-04
**Owner**: Architecture Team
