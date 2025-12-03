/**
 * API Route: /api/projects/[id]/schedules/[scheduleId]
 *
 * Individual schedule operations: GET, PATCH, DELETE
 */

import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";
import { createRouteHandlerClient } from "@/lib/supabase/clients";

interface RouteContext {
  params: Promise<{ id: string; scheduleId: string }>;
}

// GET /api/projects/[id]/schedules/[scheduleId] - Get a specific schedule
export async function GET(request: NextRequest, context: RouteContext) {
  try {
    const { id: projectId, scheduleId } = await context.params;
    const supabase = createRouteHandlerClient({ cookies });

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      return NextResponse.json(
        { detail: "Authentication required" },
        { status: 401 }
      );
    }

    const { data: schedule, error } = await supabase
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
        last_run_ticket_id,
        run_count,
        created_at,
        updated_at,
        work_recipes (
          id,
          name,
          slug,
          agent_type,
          context_outputs
        )
      `)
      .eq('id', scheduleId)
      .eq('project_id', projectId)
      .maybeSingle();

    if (error) {
      console.error("[API] Failed to fetch schedule:", error);
      return NextResponse.json(
        { detail: "Failed to fetch schedule" },
        { status: 500 }
      );
    }

    if (!schedule) {
      return NextResponse.json(
        { detail: "Schedule not found" },
        { status: 404 }
      );
    }

    return NextResponse.json({ schedule });

  } catch (error: any) {
    console.error("[API] Schedule GET failed:", error);
    return NextResponse.json(
      { detail: error.message || "Internal server error" },
      { status: 500 }
    );
  }
}

// PATCH /api/projects/[id]/schedules/[scheduleId] - Update a schedule
export async function PATCH(request: NextRequest, context: RouteContext) {
  try {
    const { id: projectId, scheduleId } = await context.params;
    const supabase = createRouteHandlerClient({ cookies });

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      return NextResponse.json(
        { detail: "Authentication required" },
        { status: 401 }
      );
    }

    const body = await request.json();
    const allowedFields = [
      'frequency',
      'day_of_week',
      'time_of_day',
      'recipe_parameters',
      'enabled',
    ];

    // Filter to only allowed fields
    const updateData: Record<string, any> = {};
    for (const field of allowedFields) {
      if (body[field] !== undefined) {
        updateData[field] = body[field];
      }
    }

    if (Object.keys(updateData).length === 0) {
      return NextResponse.json(
        { detail: "No valid fields to update" },
        { status: 400 }
      );
    }

    // Validate frequency if provided
    if (updateData.frequency) {
      const validFrequencies = ['weekly', 'biweekly', 'monthly', 'custom'];
      if (!validFrequencies.includes(updateData.frequency)) {
        return NextResponse.json(
          { detail: `frequency must be one of: ${validFrequencies.join(', ')}` },
          { status: 400 }
        );
      }
    }

    // Validate day_of_week if provided
    if (updateData.day_of_week !== undefined) {
      if (updateData.day_of_week < 0 || updateData.day_of_week > 6) {
        return NextResponse.json(
          { detail: "day_of_week must be between 0 (Sunday) and 6 (Saturday)" },
          { status: 400 }
        );
      }
    }

    const { data: schedule, error } = await supabase
      .from('project_schedules')
      .update(updateData)
      .eq('id', scheduleId)
      .eq('project_id', projectId)
      .select()
      .single();

    if (error) {
      console.error("[API] Failed to update schedule:", error);
      return NextResponse.json(
        { detail: "Failed to update schedule" },
        { status: 500 }
      );
    }

    if (!schedule) {
      return NextResponse.json(
        { detail: "Schedule not found" },
        { status: 404 }
      );
    }

    return NextResponse.json({
      schedule,
      message: "Schedule updated",
    });

  } catch (error: any) {
    console.error("[API] Schedule PATCH failed:", error);
    return NextResponse.json(
      { detail: error.message || "Internal server error" },
      { status: 500 }
    );
  }
}

// DELETE /api/projects/[id]/schedules/[scheduleId] - Delete a schedule
export async function DELETE(request: NextRequest, context: RouteContext) {
  try {
    const { id: projectId, scheduleId } = await context.params;
    const supabase = createRouteHandlerClient({ cookies });

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      return NextResponse.json(
        { detail: "Authentication required" },
        { status: 401 }
      );
    }

    const { error } = await supabase
      .from('project_schedules')
      .delete()
      .eq('id', scheduleId)
      .eq('project_id', projectId);

    if (error) {
      console.error("[API] Failed to delete schedule:", error);
      return NextResponse.json(
        { detail: "Failed to delete schedule" },
        { status: 500 }
      );
    }

    return NextResponse.json({
      message: "Schedule deleted",
    });

  } catch (error: any) {
    console.error("[API] Schedule DELETE failed:", error);
    return NextResponse.json(
      { detail: error.message || "Internal server error" },
      { status: 500 }
    );
  }
}
