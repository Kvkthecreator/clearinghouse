/**
 * API Route: POST /api/work/process
 *
 * Queue processor endpoint - picks up pending work_tickets and executes them.
 * Routes to the correct workflow endpoint based on agent_type:
 * - research → /api/work/research/execute
 * - content → /api/work/content/execute
 * - reporting → /api/work/reporting/execute
 *
 * Called by cron job every minute.
 *
 * Security: Requires CRON_SECRET or SUBSTRATE_SERVICE_SECRET header.
 *
 * See: /docs/architecture/ADR_UNIFIED_WORK_ORCHESTRATION.md
 */

import { NextRequest, NextResponse } from "next/server";
import { createServiceRoleClient } from "@/lib/supabase/clients";

// Work Platform API URL (FastAPI backend)
const WORK_PLATFORM_API_URL = process.env.WORK_PLATFORM_API_URL || "https://yarnnn-work-platform-api.onrender.com";
const SUBSTRATE_SERVICE_SECRET = process.env.SUBSTRATE_SERVICE_SECRET || "";

interface ClaimedTicket {
  id: string;
  work_request_id: string;
  basket_id: string;
  workspace_id: string;
  agent_type: string;
  metadata: {
    recipe_slug?: string;
    recipe_id?: string;
    parameters?: Record<string, unknown>;
    tp_session_id?: string;
    task_description?: string;
  };
}

// Map agent_type to workflow endpoint
const AGENT_WORKFLOW_ENDPOINTS: Record<string, string> = {
  // Agent types
  research: "/api/work/research/execute",
  content: "/api/work/content/execute",
  reporting: "/api/work/reporting/execute",
  // Research recipes (continuous monitoring)
  "trend-digest": "/api/work/research/execute",
  "market-research": "/api/work/research/execute",
  "competitor-monitor": "/api/work/research/execute",
  // Research recipes (on-demand)
  "research-investigation": "/api/work/research/execute",
  // Content recipes
  "social-media-post": "/api/work/content/execute",
  "twitter-thread": "/api/work/content/execute",
  "blog-article": "/api/work/content/execute",
  // Reporting recipes
  "executive-summary-deck": "/api/work/reporting/execute",
};

// POST /api/work/process - Process pending tickets
export async function POST(request: NextRequest) {
  try {
    // Verify auth
    const authHeader = request.headers.get("authorization");
    const cronSecret = process.env.CRON_SECRET;
    const serviceSecret = process.env.SUBSTRATE_SERVICE_SECRET;

    const isAuthorized =
      (cronSecret && authHeader === `Bearer ${cronSecret}`) ||
      (serviceSecret && authHeader === `Bearer ${serviceSecret}`);

    if (!isAuthorized) {
      return NextResponse.json(
        { detail: "Unauthorized" },
        { status: 401 }
      );
    }

    const supabase = createServiceRoleClient();

    // Parse optional limit from request body
    let limit = 5;
    try {
      const body = await request.json();
      if (body.limit && typeof body.limit === "number") {
        limit = Math.min(Math.max(body.limit, 1), 10);
      }
    } catch {
      // No body or invalid JSON, use default
    }

    // Claim pending tickets
    const { data: pendingTickets, error: claimError } = await supabase
      .from("work_tickets")
      .select(`
        id,
        work_request_id,
        basket_id,
        workspace_id,
        agent_type,
        metadata
      `)
      .eq("status", "pending")
      .order("priority", { ascending: false })
      .order("created_at", { ascending: true })
      .limit(limit);

    if (claimError) {
      console.error("[QUEUE PROCESSOR] Failed to fetch pending tickets:", claimError);
      return NextResponse.json(
        { detail: "Failed to fetch pending tickets" },
        { status: 500 }
      );
    }

    if (!pendingTickets || pendingTickets.length === 0) {
      return NextResponse.json({
        message: "No pending tickets",
        processed: 0,
      });
    }

    console.log(`[QUEUE PROCESSOR] Found ${pendingTickets.length} pending tickets`);

    const results: Array<{
      ticket_id: string;
      agent_type: string;
      status: "completed" | "failed" | "running";
      error?: string;
      outputs_count?: number;
    }> = [];

    // Process each ticket
    for (const ticket of pendingTickets as ClaimedTicket[]) {
      try {
        // Mark as running (optimistic lock)
        const { error: updateError } = await supabase
          .from("work_tickets")
          .update({
            status: "running",
            started_at: new Date().toISOString(),
          })
          .eq("id", ticket.id)
          .eq("status", "pending");

        if (updateError) {
          console.log(`[QUEUE PROCESSOR] Ticket ${ticket.id} already claimed, skipping`);
          continue;
        }

        console.log(`[QUEUE PROCESSOR] Processing ticket ${ticket.id} (${ticket.agent_type})`);

        // Execute via appropriate workflow endpoint
        const executionResult = await executeTicket(ticket, supabase);

        if (executionResult.success) {
          // Note: Workflow endpoint updates ticket status, but we ensure completion
          await supabase
            .from("work_tickets")
            .update({
              status: "completed",
              completed_at: new Date().toISOString(),
            })
            .eq("id", ticket.id)
            .in("status", ["running", "pending"]); // Only if not already updated

          results.push({
            ticket_id: ticket.id,
            agent_type: ticket.agent_type,
            status: "completed",
            outputs_count: executionResult.data?.outputs_count || 0,
          });

          console.log(`[QUEUE PROCESSOR] Completed ticket ${ticket.id}`);

        } else {
          await supabase
            .from("work_tickets")
            .update({
              status: "failed",
              error_message: executionResult.error,
              completed_at: new Date().toISOString(),
            })
            .eq("id", ticket.id);

          results.push({
            ticket_id: ticket.id,
            agent_type: ticket.agent_type,
            status: "failed",
            error: executionResult.error,
          });

          console.error(`[QUEUE PROCESSOR] Failed ticket ${ticket.id}: ${executionResult.error}`);
        }

      } catch (err) {
        console.error(`[QUEUE PROCESSOR] Error processing ticket ${ticket.id}:`, err);

        await supabase
          .from("work_tickets")
          .update({
            status: "failed",
            error_message: err instanceof Error ? err.message : "Unknown error",
            completed_at: new Date().toISOString(),
          })
          .eq("id", ticket.id);

        results.push({
          ticket_id: ticket.id,
          agent_type: ticket.agent_type,
          status: "failed",
          error: err instanceof Error ? err.message : "Unknown error",
        });
      }
    }

    const completedCount = results.filter(r => r.status === "completed").length;
    const failedCount = results.filter(r => r.status === "failed").length;

    return NextResponse.json({
      message: `Processed ${results.length} tickets`,
      processed: results.length,
      completed: completedCount,
      failed: failedCount,
      results,
    });

  } catch (error) {
    console.error("[QUEUE PROCESSOR] Error:", error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 }
    );
  }
}

// Execute a ticket via the appropriate workflow endpoint
async function executeTicket(
  ticket: ClaimedTicket,
  supabase: ReturnType<typeof createServiceRoleClient>
): Promise<{ success: boolean; data?: { outputs_count: number }; error?: string }> {
  try {
    // Determine workflow endpoint based on agent_type or recipe_slug
    const recipeSlug = ticket.metadata?.recipe_slug || ticket.agent_type;
    const workflowPath = AGENT_WORKFLOW_ENDPOINTS[recipeSlug] ||
                         AGENT_WORKFLOW_ENDPOINTS[ticket.agent_type];

    if (!workflowPath) {
      return {
        success: false,
        error: `Unknown agent type: ${ticket.agent_type} (recipe: ${recipeSlug})`,
      };
    }

    // Get user token for the request (from work_request)
    let userToken: string | null = null;
    if (ticket.work_request_id) {
      const { data: workRequest } = await supabase
        .from("work_requests")
        .select("requested_by_user_id")
        .eq("id", ticket.work_request_id)
        .single();

      if (workRequest?.requested_by_user_id) {
        // For service calls, we pass user_id in metadata instead of JWT
        // The workflow endpoint will handle auth via service secret
      }
    }

    // Build execution payload
    const payload = {
      basket_id: ticket.basket_id,
      task_description: ticket.metadata?.task_description ||
                       ticket.metadata?.parameters?.topic ||
                       `Execute ${recipeSlug}`,
      recipe_id: ticket.metadata?.recipe_id || ticket.metadata?.recipe_slug,
      recipe_parameters: ticket.metadata?.parameters || {},
      async_execution: false, // Execute synchronously since we're already in background
      work_ticket_id: ticket.id, // Pass existing ticket ID
    };

    console.log(`[QUEUE PROCESSOR] Calling ${WORK_PLATFORM_API_URL}${workflowPath}`);

    const response = await fetch(
      `${WORK_PLATFORM_API_URL}${workflowPath}`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${SUBSTRATE_SERVICE_SECRET}`,
          "Content-Type": "application/json",
          "X-Service-Name": "queue-processor",
        },
        body: JSON.stringify(payload),
      }
    );

    if (response.ok) {
      const data = await response.json();
      return {
        success: true,
        data: {
          outputs_count: data.outputs_count || data.work_outputs?.length || 0,
        },
      };
    } else {
      const errorText = await response.text();
      return {
        success: false,
        error: `Workflow error ${response.status}: ${errorText.slice(0, 300)}`,
      };
    }

  } catch (err) {
    return {
      success: false,
      error: err instanceof Error ? err.message : "Execution error",
    };
  }
}

// GET /api/work/process - Queue status
export async function GET() {
  try {
    const supabase = createServiceRoleClient();

    // Count by status
    const [pending, running, completed, failed] = await Promise.all([
      supabase.from("work_tickets").select("*", { count: "exact", head: true }).eq("status", "pending"),
      supabase.from("work_tickets").select("*", { count: "exact", head: true }).eq("status", "running"),
      supabase.from("work_tickets").select("*", { count: "exact", head: true }).eq("status", "completed"),
      supabase.from("work_tickets").select("*", { count: "exact", head: true }).eq("status", "failed"),
    ]);

    return NextResponse.json({
      status: "healthy",
      queue: {
        pending: pending.count || 0,
        running: running.count || 0,
        completed: completed.count || 0,
        failed: failed.count || 0,
      },
      workflow_api: WORK_PLATFORM_API_URL,
      checked_at: new Date().toISOString(),
    });

  } catch (error) {
    return NextResponse.json(
      { status: "error", detail: error instanceof Error ? error.message : "Unknown error" },
      { status: 500 }
    );
  }
}
