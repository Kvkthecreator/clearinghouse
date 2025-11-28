# Anchor Seeding Architecture

**Version**: 2.0
**Date**: 2025-11-28
**Status**: ✅ Implemented
**Category**: Substrate Architecture Enhancement
**Supersedes**: CONTEXT_TEMPLATES_ARCHITECTURE.md

---

## Executive Summary

**Anchor Seeding** is an LLM-powered approach to bootstrap foundational context in new baskets. Rather than fixed template schemas, it leverages the existing `anchor_role` infrastructure to create project-specific foundational blocks from minimal user input.

**Key Decision**: Context Templates (fixed schemas) are **replaced** by Anchor Seeding (LLM-generated blocks with anchor roles). This provides:

1. **Flexibility** - No rigid template schemas; LLM decides what's relevant
2. **Magic UX** - Users describe their project; system creates foundational blocks
3. **Existing Infrastructure** - Leverages `anchor_role`, `basket_anchors`, lifecycle management
4. **Fluid Context** - Anchors are quality signals, not execution gates

---

## Critical Design Decision: Anchors Are Advisory, Not Mandatory

### The Anti-Pattern (What We Avoided)

```python
# ❌ WRONG - This is just Context Templates with different names
required_anchors = ['customer', 'problem']
if not basket_has_anchors(required_anchors):
    raise "Cannot execute recipe - missing required anchors"
```

### The Correct Pattern (What We Implemented)

```python
# ✅ RIGHT - Anchors are quality signals for agent context assembly
def assemble_context(basket_id, task):
    blocks = get_basket_blocks(basket_id)

    # Anchors get priority in context window
    anchor_blocks = [b for b in blocks if b.anchor_role]
    regular_blocks = [b for b in blocks if not b.anchor_role]

    # Agent works with whatever context is available
    return anchor_blocks + relevant_regular_blocks
```

### Why This Matters

| Aspect | Mandatory Anchors (wrong) | Advisory Anchors (correct) |
|--------|---------------------------|----------------------------|
| **Philosophy** | Prescriptive gates | Emergent quality signals |
| **User Experience** | "You can't proceed until..." | "Here's what I found..." |
| **Agent Behavior** | Blocked without context | Resourceful with available context |
| **Recipe Coupling** | Tight (recipe → anchor) | Loose (agent queries what exists) |
| **Evolution** | Schema changes break recipes | Anchors evolve independently |

### How Agents Use Anchors

1. **Context Assembly**: Anchor blocks are prioritized in the agent's context window
2. **Quality Signal**: Presence of anchors indicates mature, well-defined project
3. **No Hard Dependencies**: Agent executes regardless of anchor presence
4. **Graceful Degradation**: Less context = less targeted output, but still functional

---

## Decision History

### Why Context Templates Were Considered

The original goal was to ensure baskets have foundational context for agents:

- **Problem**: New baskets start empty; agents lack context
- **Initial Solution**: Fixed templates (brand_identity, competitor_registry, etc.)
- **Implementation**: `context_template_catalog` table, form-based filling

### Why We Pivoted to Anchor Seeding

During implementation review, we identified:

1. **Redundancy**: Anchor Blocks already solve the "important blocks" problem
2. **Rigidity**: Fixed templates create recipe → template dependencies
3. **Better Fit**: `anchor_role` is more primitive and LLM-friendly
4. **Existing Infrastructure**: `basket_anchors`, `anchor_role` column, lifecycle code

### The Core Insight

```
Context Templates: "Every basket should have a Brand Identity block"
Anchor Blocks:     "This block is foundationally important (customer anchor)"

Templates prescribe CONTENT STRUCTURE.
Anchors mark SEMANTIC IMPORTANCE.
```

Anchors don't dictate what a "customer" anchor looks like - they signal that this particular block captures customer understanding.

---

## Architecture Design

### Anchor Roles (Existing Schema)

```sql
anchor_role IN ('problem', 'customer', 'solution', 'feature',
                'constraint', 'metric', 'insight', 'vision')
```

These 8 roles represent foundational context categories:

| Role | Purpose | Example |
|------|---------|---------|
| `problem` | What pain point is being solved | "Marketing teams lack real-time metrics" |
| `customer` | Who is this for | "Marketing managers at mid-size B2B companies" |
| `solution` | How is it solved | "Real-time analytics dashboard with AI insights" |
| `vision` | Where is this going | "Democratize data-driven marketing" |
| `feature` | Key capabilities | "Custom report builder" |
| `constraint` | Limitations/requirements | "Must integrate with existing CRM" |
| `metric` | Success measures | "50% reduction in reporting time" |
| `insight` | Key learnings | "Users prefer visual dashboards over tables" |

### Anchor Seeding Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PROJECT CREATION                                 │
│                                                                          │
│   User Input:                                                            │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │ Project Name: [Analytics Dashboard]                               │  │
│   │ Description: [Optional brief description]                         │  │
│   │                                                                    │  │
│   │ Add project context for AI seeding (optional)                     │  │
│   │ ┌────────────────────────────────────────────────────────────┐   │  │
│   │ │ We're building a SaaS analytics platform for marketing     │   │  │
│   │ │ teams. Main problem is they spend too much time on manual  │   │  │
│   │ │ reporting. Target: mid-market B2B companies...             │   │  │
│   │ └────────────────────────────────────────────────────────────┘   │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                              │                                           │
│                              ▼                                           │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                    ANCHOR SEEDING ENDPOINT                        │  │
│   │                    POST /api/baskets/{id}/seed-anchors            │  │
│   │                                                                    │  │
│   │  LLM analyzes input and generates 2-4 foundational blocks:       │  │
│   │                                                                    │  │
│   │  Block 1: semantic_type=entity, anchor_role=customer              │  │
│   │           "Marketing managers at mid-market B2B companies"        │  │
│   │                                                                    │  │
│   │  Block 2: semantic_type=finding, anchor_role=problem              │  │
│   │           "Manual reporting consumes 40% of analyst time"         │  │
│   │                                                                    │  │
│   │  Block 3: semantic_type=objective, anchor_role=vision             │  │
│   │           "Automate insights delivery for marketing teams"        │  │
│   │                                                                    │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                              │                                           │
│                              ▼                                           │
│                    Blocks created with anchor_role                       │
│                    state=ACCEPTED (immediately usable)                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Project Creation Options

**Option A: Light Start (skip rich input)**
```
Name + Description → Empty basket → User adds context later
```
- Project created without seeded anchors
- User can manually create blocks or use "Seed Anchors" later
- Agents work with whatever context exists

**Option B: Rich Start (provide context)**
```
Name + Description + Rich Input → LLM seeds anchor blocks → Basket has foundation
```
- Immediate value
- User can edit/refine generated blocks
- Agents have strong foundational context from day one

Both paths are valid; rich input is **encouraged but optional**.

---

## Implementation Status

### ✅ Phase 1: Cleanup (Complete)

- [x] Dropped `context_template_catalog` table
- [x] Removed `required_templates`/`recommended_templates` from `work_recipes`
- [x] Deleted template routes from substrate-api
- [x] Deleted template components from work-platform/web
- [x] Deleted template BFF routes

### ✅ Phase 2: Anchor Seeding Endpoint (Complete)

**Endpoint**: `POST /api/baskets/{basket_id}/seed-anchors`
**Location**: `substrate-api/api/src/app/routes/anchor_seeding.py`

```python
class AnchorSeedRequest(BaseModel):
    context: str  # User's rich input (10-5000 chars)
    project_name: Optional[str]

class AnchorSeedResponse(BaseModel):
    success: bool
    blocks_created: int
    anchors: List[Dict[str, Any]]
    message: str
```

**Features**:
- Uses GPT-4o-mini for fast, cost-effective generation
- Generates 2-4 foundational blocks
- Creates blocks with `state=ACCEPTED` (immediately usable)
- Retry logic for reliability (3 attempts)
- JSON response format enforcement

### ✅ Phase 3: Frontend Integration (Complete)

- [x] `CreateProjectDialog` - Added collapsible "Add project context for AI seeding" section
- [x] Project creation API - Triggers anchor seeding fire-and-forget when context provided
- [x] `AnchorStatusSection` - Shows anchor health on Context page

### N/A Phase 4: Recipe Integration

**Decision**: No recipe integration needed.

Recipes do NOT declare required anchors. Instead:
- Recipes specify `context_requirements.substrate_blocks` with `semantic_types` and `min_blocks`
- Agents query substrate and prioritize anchor blocks in context assembly
- This is already how recipes work - no changes needed

---

## How Recipes Use Context (No Changes Needed)

Current recipe `context_requirements` pattern:

```json
{
  "substrate_blocks": {
    "min_blocks": 3,
    "semantic_types": ["insight", "finding", "recommendation"],
    "recency_preference": "last_90_days"
  }
}
```

This is **already fluid** - it specifies preferences, not requirements. Agents:
1. Query blocks matching these criteria
2. Prioritize anchor blocks (they're foundationally important)
3. Fill remaining context with relevant non-anchor blocks
4. Execute regardless of what's available

---

## Comparison: Templates vs Anchors

| Aspect | Context Templates (removed) | Anchor Seeding (implemented) |
|--------|----------------------------|------------------------------|
| **Schema** | Fixed fields per template | Standard block + anchor_role |
| **Creation** | User fills form | LLM generates from context |
| **Flexibility** | Low (predefined schemas) | High (8 generic roles) |
| **Query Pattern** | `metadata.template_id = 'brand_identity'` | `anchor_role IS NOT NULL` |
| **Recipe Binding** | Tight (recipe → template) | None (anchors are advisory) |
| **User Effort** | Fill 5 forms | Paste context, review blocks |
| **Agent Behavior** | Blocked without templates | Works with available context |

---

## Success Metrics

1. **Basket Bootstrap Time**: < 5 seconds to seed anchors from context
2. **Anchor Coverage**: Track % of baskets with at least 2 anchors
3. **User Editing Rate**: Track how often users edit seeded blocks (validates quality)
4. **Agent Output Quality**: Compare outputs for baskets with/without anchors

---

## Related Documentation

- [SEMANTIC_TYPES_QUICK_REFERENCE.txt](../../SEMANTIC_TYPES_QUICK_REFERENCE.txt) - Anchor role inference
- [basket_anchors migration](../../supabase/migrations/20250928_add_basket_anchor_registry.sql) - Anchor registry schema
- [anchor_substrate_metadata migration](../../supabase/migrations/20251003_anchor_substrate_metadata.sql) - anchor_role column

---

**Document Status**: ✅ Implementation Complete
**Last Updated**: 2025-11-28
**Owner**: Architecture Team
