/**
 * Live Work Ticket Tracking Page
 *
 * Shows real-time execution progress for a work ticket:
 * - Ticket metadata (recipe, parameters, agent)
 * - Real-time status updates (Supabase Realtime)
 * - TodoWrite task progress (SSE)
 * - Output preview when completed
 * - Actions (view output, retry, download)
 */

import { createClient } from "@supabase/supabase-js";
import { notFound } from "next/navigation";
import TicketTrackingClient from "./TicketTrackingClient";

interface PageProps {
  params: Promise<{ id: string; ticketId: string }>;
}

export default async function TicketTrackingPage({ params }: PageProps) {
  const { id: projectId, ticketId } = await params;

  console.log('[TicketTrackingPage] Loading ticket:', { projectId, ticketId });

  // Use anon client for public ticket viewing (RLS handles security)
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  // Fetch work ticket with outputs
  const { data: ticket, error: ticketError } = await supabase
    .from('work_tickets')
    .select(`
      id,
      status,
      agent_type,
      created_at,
      started_at,
      completed_at,
      error_message,
      metadata,
      basket_id,
      workspace_id,
      work_outputs (
        id,
        title,
        body,
        output_type,
        agent_type,
        file_id,
        file_format,
        generation_method,
        created_at
      )
    `)
    .eq('id', ticketId)
    .maybeSingle();

  console.log('[TicketTrackingPage] Ticket query result:', { ticket, ticketError });

  if (!ticket) {
    console.error('[TicketTrackingPage] Ticket not found:', ticketId);
    notFound();
  }

  // Fetch project from ticket's basket
  const { data: project, error: projectError } = await supabase
    .from('projects')
    .select('id, name, basket_id')
    .eq('basket_id', ticket.basket_id)
    .maybeSingle();

  console.log('[TicketTrackingPage] Project query result:', { project, projectError });

  if (!project) {
    console.error('[TicketTrackingPage] Project not found for basket:', ticket.basket_id);
    notFound();
  }

  // Extract recipe info from metadata
  const recipeName = ticket.metadata?.recipe_slug || 'Work Request';
  const recipeParams = ticket.metadata?.recipe_parameters || {};
  const taskDescription = ticket.metadata?.task_description || '';

  console.log('[TicketTrackingPage] Rendering TicketTrackingClient');

  return (
    <TicketTrackingClient
      projectId={projectId}
      projectName={project.name}
      ticket={ticket}
      recipeName={recipeName}
      recipeParams={recipeParams}
      taskDescription={taskDescription}
    />
  );
}
