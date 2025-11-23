# Work Recipes - Dynamic Scaffolding Implementation

**Date**: 2025-11-23
**Status**: Phase 1 Foundation Complete (Backend Core Ready)
**Next**: ReportingAgentSDK Integration + Frontend Discussion

---

## ✅ COMPLETED

### 1. Database Schema & Migration
**File**: `supabase/migrations/20251123_work_recipes_dynamic_scaffolding.sql`

- Created `work_recipes` table with full JSONB schema for dynamic execution
- Extended `work_requests` table with recipe linkage columns:
  - `recipe_id` (UUID, references work_recipes)
  - `recipe_parameters` (JSONB, validated user parameters)
  - `reference_asset_ids` (UUID[], user-uploaded context assets)
- **Migration Applied Successfully** (1 active recipe seeded)

**Seed Data**: "Executive Summary Deck" recipe
- Parameterized: `slide_count` (3-7 range), `focus_area` (optional text)
- Output: PPTX format with validation rules
- Estimated: 3-6 minutes, $3-5

### 2. RecipeLoader Service
**File**: `work-platform/api/src/services/recipe_loader.py`

**Features**:
- Load recipes by ID or slug
- Validate user parameters against configurable_parameters schema
- Support for parameter types: range, text, multi-select
- Generate execution context with parameter interpolation
- List active recipes for frontend

**Key Methods**:
```python
loader = RecipeLoader()
recipe = await loader.load_recipe(slug="executive-summary-deck")
validated = loader.validate_parameters(recipe, user_parameters)
context = loader.generate_execution_context(recipe, validated)
recipes = await loader.list_active_recipes(agent_type="reporting")
```

### 3. Work Recipes API
**File**: `work-platform/api/src/app/routes/work_recipes.py`

**Endpoints**:
1. `GET /api/work/recipes` - List active recipes (with filters)
2. `GET /api/work/recipes/{slug}` - Get recipe details
3. `POST /api/work/recipes/{slug}/execute` - Execute recipe-driven work request

**Execution Flow**:
1. Load recipe + validate parameters
2. Create work_request with recipe linkage
3. Load WorkBundle (substrate_blocks + reference_assets)
4. Generate execution context from recipe template
5. Execute agent (ReportingAgentSDK)
6. Return structured outputs

---

## ⏳ REMAINING WORK

### 1. ReportingAgentSDK Integration
**File to Modify**: `work-platform/api/src/agents_sdk/reporting_agent_sdk.py`

**Required**: Add `execute_recipe()` method

```python
async def execute_recipe(
    self,
    recipe_context: Dict[str, Any],
    claude_session_id: Optional[str] = None
) -> Dict[str, Any]:
    """
    Execute recipe-driven report generation.

    Args:
        recipe_context: Execution context from RecipeLoader
          - system_prompt_additions
          - task_breakdown
          - validation_instructions
          - output_specification
          - deliverable_intent
        claude_session_id: Resume session if available

    Returns:
        {
            "output_count": int,
            "work_outputs": List[dict],
            "validation_results": dict
        }
    """
    # 1. Build system prompt (base + recipe additions)
    system_prompt = REPORTING_AGENT_SYSTEM_PROMPT + "\n\n" + \
                    recipe_context["system_prompt_additions"]

    # 2. Build user prompt from task_breakdown
    task_instructions = "\n".join([
        f"{i+1}. {task}"
        for i, task in enumerate(recipe_context["task_breakdown"])
    ])

    user_prompt = f"""
{recipe_context["deliverable_intent"]["purpose"]}

Task Breakdown:
{task_instructions}

Validation Requirements:
{recipe_context["validation_instructions"]}

Expected Output:
- Format: {recipe_context["output_specification"]["format"]}
- Required Sections: {recipe_context["output_specification"]["required_sections"]}

Execute this recipe and emit work_output with validation metadata.
"""

    # 3. Execute via ClaudeSDKClient (same pattern as deep_dive)
    async with ClaudeSDKClient(options=self._options) as client:
        result = await client.create_session(
            system_prompt=system_prompt,
            initial_message=user_prompt,
            session_id=claude_session_id,  # Resume if available
        )

    # 4. Collect work_outputs emitted by agent
    outputs = []  # Extract from result.tool_uses (emit_work_output calls)

    # 5. Validate outputs against recipe output_specification
    validation_results = self._validate_recipe_outputs(
        outputs, recipe_context["output_specification"]
    )

    return {
        "output_count": len(outputs),
        "work_outputs": outputs,
        "validation_results": validation_results
    }
```

**Validation Helper**:
```python
def _validate_recipe_outputs(
    self,
    outputs: List[dict],
    output_spec: Dict[str, Any]
) -> Dict[str, Any]:
    """Validate outputs against recipe specification."""
    validation = {"passed": True, "errors": []}

    # Check format
    expected_format = output_spec.get("format")
    # Check required sections
    # Check slide count (for PPTX)
    # etc.

    return validation
```

### 2. Register Router in agent_server.py
**File**: `work-platform/api/src/app/agent_server.py`

**Add**:
```python
from .routes.work_recipes import router as work_recipes_router

routers = (
    # ... existing routers ...
    work_recipes_router,  # ADD THIS
)
```

### 3. Test E2E (Backend)
Create test similar to `test_workflows.py`:

```bash
curl -X POST 'http://localhost:10000/api/work/recipes/executive-summary-deck/execute' \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "basket_id": "uuid",
    "recipe_parameters": {
      "slide_count": 5,
      "focus_area": "Q4 performance highlights"
    },
    "reference_asset_ids": []
  }'
```

### 4. Update TERMINOLOGY_GLOSSARY.md
Add work_recipes definition:

```markdown
## Work Recipes (Phase 1 - 2025-11-23)

**Problem**: Need deterministic, cost-efficient work execution with bounded flexibility.

| Term | Implementation | Purpose |
|------|----------------|---------|
| **Work Recipes** | `work_recipes` table (JSONB) | Predefined executable patterns with parameterized configuration |
| **Configurable Parameters** | JSONB schema (range, text, multi-select) | User customization within bounds |
| **Execution Template** | JSONB (system_prompt_additions, task_breakdown) | Agent instructions with parameter interpolation |
| **Output Specification** | JSONB (format, required_sections, validation_rules) | Deterministic output validation |

**Key Insight**: Recipes define WHAT can be customized, users provide values within bounds, agents execute with complete instructions.
```

### 5. Frontend Integration (Separate Discussion)
**Requirements Doc to Create**: `FRONTEND_WORK_RECIPES_INTEGRATION.md`

**UI Flows**:
1. Recipe Selection Page
   - List recipes (GET /api/work/recipes)
   - Display: name, description, estimates
   - Filter by category/agent_type

2. Recipe Configuration Page
   - Show configurable_parameters
   - Render input controls based on parameter type:
     - range → slider
     - text → text input
     - multi-select → checkboxes
   - Optional: reference asset upload

3. Execution & Results
   - Submit to /api/work/recipes/{slug}/execute
   - Show progress (work_ticket status)
   - Display outputs when complete

---

## 📦 FILES CREATED

1. **Migration**: `supabase/migrations/20251123_work_recipes_dynamic_scaffolding.sql` ✅ Applied
2. **Service**: `work-platform/api/src/services/recipe_loader.py` ✅ Complete
3. **API**: `work-platform/api/src/app/routes/work_recipes.py` ✅ Complete
4. **Status Doc**: `WORK_RECIPES_IMPLEMENTATION_STATUS.md` (this file)

---

## 🎯 NEXT IMMEDIATE STEPS

1. Add `execute_recipe()` to ReportingAgentSDK (15 min)
2. Register work_recipes_router in agent_server.py (2 min)
3. Test E2E execution (10 min)
4. Commit + push (5 min)
5. Frontend integration discussion (separate session)

---

## 🚀 DEPLOYMENT NOTES

**Pre-Users**: Can deploy directly to main with flexibility
**Migration Applied**: Database ready in production
**No Breaking Changes**: Additive only (recipe_id optional in work_requests)
**Backward Compatible**: Existing workflows unaffected

---

## 💡 ARCHITECTURE DECISIONS

**Why Parameterized Recipes (Not Fully Dynamic)**:
- ✅ Bounded flexibility = predictable costs/time
- ✅ Validation against schema = quality floor
- ✅ Parameter interpolation = execution clarity
- ✅ Room to grow = can add more recipes over time

**Why JSONB Over Separate Tables**:
- ✅ Faster iteration (no migration per recipe tweak)
- ✅ Flexible schema evolution
- ✅ Single source of truth per recipe
- ❌ Trade-off: No relational constraints on parameters

**Why Recipe-First (Not Agent-First)**:
- ✅ User selects WHAT they want (outcome-focused)
- ✅ System determines HOW to execute (agent abstracted)
- ✅ Future: Multi-agent recipes (research → reporting flow)
