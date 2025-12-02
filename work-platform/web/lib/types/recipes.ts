/**
 * Work Recipes Type Definitions
 *
 * Types for recipe-driven work execution with agent-specific routing.
 * Mirrors backend recipe schema and execution models.
 */

export interface RecipeContextRequirements {
  roles?: string[]
  roles_optional?: string[]
  substrate_blocks?: {
    min_blocks?: number
    semantic_types?: string[]
    recency_preference?: string
  }
  reference_assets?: {
    types?: string[]
    required?: boolean
    min_count?: number
  }
}

export interface RecipeContextOutputs {
  role: string
  refresh_policy?: {
    ttl_hours: number
    auto_promote?: boolean
  }
}

export interface Recipe {
  id: string
  slug: string
  name: string
  description: string
  category: string
  agent_type: 'research' | 'content' | 'reporting'
  deliverable_intent: {
    purpose: string
    audience: string
    expected_outcome: string
  }
  configurable_parameters: Record<string, ParameterSchema>
  estimated_duration_seconds: [number, number]  // [min, max]
  estimated_cost_cents: [number, number]  // [min, max]
  context_requirements?: RecipeContextRequirements
  context_outputs?: RecipeContextOutputs
}

export interface ParameterSchema {
  type: 'range' | 'text' | 'multi-select'
  label: string
  optional?: boolean
  default?: any

  // Range-specific
  min?: number
  max?: number

  // Text-specific
  max_length?: number

  // Multi-select-specific
  options?: string[]
}

export interface RecipeExecutionRequest {
  basket_id: string
  task_description: string
  recipe_id: string
  recipe_parameters: Record<string, any>
  reference_asset_ids?: string[]
}

export interface RecipeExecutionResponse {
  work_request_id: string
  work_ticket_id: string
  agent_session_id: string
  status: 'completed' | 'failed'
  outputs: Array<{
    id: string
    content: any
    format: string
    metadata: object
  }>
  execution_time_ms: number
  message: string
  recipe_used: string
}
