/**
 * API Route: /api/projects/[id]/schedules
 *
 * CRUD operations for project work schedules.
 * Enables users to set up recurring recipe execution.
 */

import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";
import { createRouteHandlerClient } from "@/lib/supabase/clients";

interface RouteContext {
  params: Promise<{ id: string }>;
}

// GET /api/projects/[id]/schedules - List all schedules for a project
export async function GET(request: NextRequest, context: RouteContext) {
  try {
    const { id: projectId } = await context.params;
    const supabase = createRouteHandlerClient({ cookies });

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      return NextResponse.json(
        { detail: "Authentication required" },
        { status: 401 }
      );
    }

    // Get project to verify access
    const { data: project, error: projectError } = await supabase
      .from('projects')
      .select('id, basket_id')
      .eq('id', projectId)
      .maybeSingle();

    if (projectError || !project) {
      return NextResponse.json(
        { detail: "Project not found" },
        { status: 404 }
      );
    }

    // Get schedules with recipe details
    const { data: schedules, error } = await supabase
      .from('project_schedules')
      .select(`
        id,
        project_id,
        recipe_id,
        frequency,
        day_of_week,
        time_of_day,
        recipe_parameters,
        enabled,
        next_run_at,
        last_run_at,
        last_run_status,
        run_count,
        created_at,
        work_recipes (
          id,
          name,
          slug,
          agent_type,
          context_outputs
        )
      `)
      .eq('project_id', projectId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error("[API] Failed to fetch schedules:", error);
      return NextResponse.json(
        { detail: "Failed to fetch schedules" },
        { status: 500 }
      );
    }

    // Transform for frontend
    const transformedSchedules = (schedules || []).map((s: any) => ({
      id: s.id,
      project_id: s.project_id,
      recipe_id: s.recipe_id,
      recipe_name: s.work_recipes?.name,
      recipe_slug: s.work_recipes?.slug,
      agent_type: s.work_recipes?.agent_type,
      context_outputs: s.work_recipes?.context_outputs,
      frequency: s.frequency,
      day_of_week: s.day_of_week,
      time_of_day: s.time_of_day,
      recipe_parameters: s.recipe_parameters,
      enabled: s.enabled,
      next_run_at: s.next_run_at,
      last_run_at: s.last_run_at,
      last_run_status: s.last_run_status,
      run_count: s.run_count,
      created_at: s.created_at,
    }));

    return NextResponse.json({
      schedules: transformedSchedules,
      count: transformedSchedules.length,
    });

  } catch (error: any) {
    console.error("[API] Schedules GET failed:", error);
    return NextResponse.json(
      { detail: error.message || "Internal server error" },
      { status: 500 }
    );
  }
}

// POST /api/projects/[id]/schedules - Create a new schedule
export async function POST(request: NextRequest, context: RouteContext) {
  try {
    const { id: projectId } = await context.params;
    const supabase = createRouteHandlerClient({ cookies });

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      return NextResponse.json(
        { detail: "Authentication required" },
        { status: 401 }
      );
    }

    const body = await request.json();
    const {
      recipe_id,
      frequency,
      day_of_week = 1, // Default to Monday
      time_of_day = "09:00:00",
      recipe_parameters = {},
      enabled = true,
    } = body;

    // Validate required fields
    if (!recipe_id || !frequency) {
      return NextResponse.json(
        { detail: "recipe_id and frequency are required" },
        { status: 400 }
      );
    }

    // Validate frequency
    const validFrequencies = ['weekly', 'biweekly', 'monthly', 'custom'];
    if (!validFrequencies.includes(frequency)) {
      return NextResponse.json(
        { detail: `frequency must be one of: ${validFrequencies.join(', ')}` },
        { status: 400 }
      );
    }

    // Get project to get basket_id
    const { data: project, error: projectError } = await supabase
      .from('projects')
      .select('id, basket_id')
      .eq('id', projectId)
      .maybeSingle();

    if (projectError || !project) {
      return NextResponse.json(
        { detail: "Project not found" },
        { status: 404 }
      );
    }

    // Verify recipe exists
    const { data: recipe, error: recipeError } = await supabase
      .from('work_recipes')
      .select('id, name, slug')
      .eq('id', recipe_id)
      .eq('status', 'active')
      .maybeSingle();

    if (recipeError || !recipe) {
      return NextResponse.json(
        { detail: "Recipe not found or inactive" },
        { status: 404 }
      );
    }

    // Create schedule
    const { data: schedule, error: createError } = await supabase
      .from('project_schedules')
      .insert({
        project_id: projectId,
        recipe_id,
        basket_id: project.basket_id,
        frequency,
        day_of_week,
        time_of_day,
        recipe_parameters,
        enabled,
        created_by: session.user.id,
      })
      .select()
      .single();

    if (createError) {
      // Check for unique constraint violation
      if (createError.code === '23505') {
        return NextResponse.json(
          { detail: "A schedule for this recipe already exists. Update or delete the existing schedule." },
          { status: 409 }
        );
      }
      console.error("[API] Failed to create schedule:", createError);
      return NextResponse.json(
        { detail: "Failed to create schedule" },
        { status: 500 }
      );
    }

    return NextResponse.json({
      schedule,
      message: `Schedule created for ${recipe.name}`,
    }, { status: 201 });

  } catch (error: any) {
    console.error("[API] Schedules POST failed:", error);
    return NextResponse.json(
      { detail: error.message || "Internal server error" },
      { status: 500 }
    );
  }
}
