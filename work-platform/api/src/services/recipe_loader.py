"""
Recipe Loader - Dynamic Work Recipe Execution Engine

Loads work_recipes from database, validates user parameters, and generates
execution context for recipe-driven agent work.

Design Philosophy:
- Recipes define WHAT can be customized (configurable_parameters)
- Users provide values within bounds (recipe_parameters)
- RecipeLoader validates, interpolates, and generates execution context
- Agents receive complete instructions via execution_template

Usage:
    from services.recipe_loader import RecipeLoader, Recipe

    loader = RecipeLoader()

    # Load recipe by slug
    recipe = await loader.load_recipe(slug="executive-summary-deck")

    # Validate user parameters
    validated_params = loader.validate_parameters(
        recipe=recipe,
        user_parameters={"slide_count": 5, "focus_area": "Q4 performance"}
    )

    # Generate execution context for agent
    execution_context = loader.generate_execution_context(
        recipe=recipe,
        validated_parameters=validated_params
    )
"""

import logging
from typing import Any, Dict, List, Optional
from dataclasses import dataclass
from uuid import UUID

from app.utils.supabase_client import supabase_admin_client as supabase

logger = logging.getLogger(__name__)


@dataclass
class Recipe:
    """Structured representation of a work_recipe."""
    id: str
    slug: str
    name: str
    description: str
    category: str
    agent_type: str
    deliverable_intent: Dict[str, Any]
    configurable_parameters: Dict[str, Any]
    output_specification: Dict[str, Any]
    context_requirements: Dict[str, Any]
    execution_template: Dict[str, Any]
    estimated_duration_seconds_range: List[int]
    estimated_cost_cents_range: List[int]
    status: str
    version: int


class RecipeValidationError(Exception):
    """Raised when recipe parameter validation fails."""
    pass


class RecipeLoader:
    """Loads and validates work recipes for dynamic execution."""

    def __init__(self):
        self.supabase = supabase

    async def load_recipe(
        self,
        recipe_id: Optional[str] = None,
        slug: Optional[str] = None
    ) -> Recipe:
        """
        Load a recipe by ID or slug.

        Args:
            recipe_id: UUID of the recipe
            slug: Slug identifier (e.g., "executive-summary-deck")

        Returns:
            Recipe object

        Raises:
            ValueError: If neither recipe_id nor slug provided
            RecipeValidationError: If recipe not found or inactive
        """
        if not recipe_id and not slug:
            raise ValueError("Must provide either recipe_id or slug")

        query = self.supabase.table("work_recipes").select("*")

        if recipe_id:
            query = query.eq("id", recipe_id)
        else:
            query = query.eq("slug", slug)

        response = query.single().execute()

        if not response.data:
            identifier = recipe_id or slug
            raise RecipeValidationError(f"Recipe not found: {identifier}")

        recipe_data = response.data

        if recipe_data["status"] != "active":
            raise RecipeValidationError(
                f"Recipe '{recipe_data['name']}' is {recipe_data['status']}, not active"
            )

        return Recipe(
            id=recipe_data["id"],
            slug=recipe_data["slug"],
            name=recipe_data["name"],
            description=recipe_data.get("description", ""),
            category=recipe_data.get("category", ""),
            agent_type=recipe_data["agent_type"],
            deliverable_intent=recipe_data.get("deliverable_intent", {}),
            configurable_parameters=recipe_data.get("configurable_parameters", {}),
            output_specification=recipe_data["output_specification"],
            context_requirements=recipe_data.get("context_requirements", {}),
            execution_template=recipe_data["execution_template"],
            estimated_duration_seconds_range=recipe_data.get("estimated_duration_seconds_range", [180, 360]),
            estimated_cost_cents_range=recipe_data.get("estimated_cost_cents_range", [300, 500]),
            status=recipe_data["status"],
            version=recipe_data.get("version", 1),
        )

    def validate_parameters(
        self,
        recipe: Recipe,
        user_parameters: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Validate user parameters against recipe's configurable_parameters schema.

        Args:
            recipe: Recipe object
            user_parameters: User-provided parameter values

        Returns:
            Validated parameters with defaults applied

        Raises:
            RecipeValidationError: If validation fails
        """
        validated = {}
        config_params = recipe.configurable_parameters

        # Validate each configurable parameter
        for param_name, param_schema in config_params.items():
            user_value = user_parameters.get(param_name)

            # Check if required
            if user_value is None:
                if param_schema.get("optional", False):
                    # Use default if available
                    if "default" in param_schema:
                        validated[param_name] = param_schema["default"]
                    continue
                else:
                    # Required parameter missing
                    raise RecipeValidationError(
                        f"Required parameter '{param_name}' not provided"
                    )

            # Validate based on type
            param_type = param_schema.get("type")

            if param_type == "range":
                # Validate numeric range
                min_val = param_schema.get("min")
                max_val = param_schema.get("max")

                if not isinstance(user_value, (int, float)):
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' must be numeric, got {type(user_value)}"
                    )

                if min_val is not None and user_value < min_val:
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' must be >= {min_val}, got {user_value}"
                    )

                if max_val is not None and user_value > max_val:
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' must be <= {max_val}, got {user_value}"
                    )

                validated[param_name] = user_value

            elif param_type == "text":
                # Validate text
                if not isinstance(user_value, str):
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' must be text, got {type(user_value)}"
                    )

                max_length = param_schema.get("max_length")
                if max_length and len(user_value) > max_length:
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' exceeds max length {max_length}"
                    )

                validated[param_name] = user_value

            elif param_type == "multi-select":
                # Validate multi-select
                if not isinstance(user_value, list):
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' must be a list, got {type(user_value)}"
                    )

                options = param_schema.get("options", [])
                for val in user_value:
                    if val not in options:
                        raise RecipeValidationError(
                            f"Invalid option '{val}' for parameter '{param_name}'. "
                            f"Valid options: {options}"
                        )

                min_count = param_schema.get("min", 0)
                max_count = param_schema.get("max")

                if len(user_value) < min_count:
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' requires at least {min_count} selections"
                    )

                if max_count and len(user_value) > max_count:
                    raise RecipeValidationError(
                        f"Parameter '{param_name}' allows max {max_count} selections"
                    )

                validated[param_name] = user_value

            else:
                # Unknown type, pass through
                validated[param_name] = user_value

        # Check for unexpected parameters
        for user_param in user_parameters:
            if user_param not in config_params:
                logger.warning(
                    f"Unexpected parameter '{user_param}' provided for recipe {recipe.slug}"
                )

        return validated

    def generate_execution_context(
        self,
        recipe: Recipe,
        validated_parameters: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate execution context for agent from recipe and parameters.

        Interpolates validated_parameters into execution_template.

        Args:
            recipe: Recipe object
            validated_parameters: Validated user parameters

        Returns:
            Execution context with:
            - system_prompt_additions: Additional system prompt text
            - task_breakdown: List of steps with parameter interpolation
            - validation_instructions: Output validation rules
            - output_specification: Expected output structure
            - deliverable_intent: Purpose, audience, outcome
        """
        execution_template = recipe.execution_template

        # Interpolate parameters into task_breakdown
        task_breakdown = execution_template.get("task_breakdown", [])
        interpolated_tasks = []

        for task in task_breakdown:
            # Simple {{parameter}} interpolation
            interpolated_task = task
            for param_name, param_value in validated_parameters.items():
                placeholder = f"{{{{{param_name}}}}}"  # {{param_name}}
                if placeholder in interpolated_task:
                    interpolated_task = interpolated_task.replace(
                        placeholder, str(param_value)
                    )

            interpolated_tasks.append(interpolated_task)

        # Also interpolate output_specification (e.g., slide_count validation)
        output_spec = recipe.output_specification.copy()
        validation_rules = output_spec.get("validation_rules", {})

        # Update validation rules with actual parameter values
        for param_name, param_value in validated_parameters.items():
            # Example: slide_count_in_range → check actual value
            if param_name in str(validation_rules):
                # Store actual expected values
                validation_rules[f"{param_name}_expected"] = param_value

        output_spec["validation_rules"] = validation_rules

        return {
            "system_prompt_additions": execution_template.get("system_prompt_additions", ""),
            "task_breakdown": interpolated_tasks,
            "validation_instructions": execution_template.get("validation_instructions", ""),
            "output_specification": output_spec,
            "deliverable_intent": recipe.deliverable_intent,
            "context_requirements": recipe.context_requirements,
            "recipe_metadata": {
                "recipe_id": recipe.id,
                "recipe_slug": recipe.slug,
                "recipe_name": recipe.name,
                "agent_type": recipe.agent_type,
                "parameters_used": validated_parameters,
            }
        }

    async def list_active_recipes(
        self,
        agent_type: Optional[str] = None,
        category: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        List all active recipes (for frontend recipe selection).

        Args:
            agent_type: Filter by agent type (optional)
            category: Filter by category (optional)

        Returns:
            List of recipe summaries (id, slug, name, description, parameters, estimates)
        """
        query = self.supabase.table("work_recipes").select(
            "id, slug, name, description, category, agent_type, "
            "configurable_parameters, estimated_duration_seconds_range, "
            "estimated_cost_cents_range, deliverable_intent"
        ).eq("status", "active")

        if agent_type:
            query = query.eq("agent_type", agent_type)

        if category:
            query = query.eq("category", category)

        response = query.execute()

        return response.data or []
