import { cookies } from 'next/headers';
import { notFound } from 'next/navigation';
import { createServerComponentClient } from '@/lib/supabase/clients';
import { getAuthenticatedUser } from '@/lib/auth/getAuthenticatedUser';
import AgentDashboardClient, { type WorkTicket, type Recipe } from '../_components/AgentDashboardClient';
import { ThinkingAgentClient } from '../_components/ThinkingAgentClient';
import { isAgentType, type AgentType } from '../config';

interface PageProps {
  params: Promise<{ id: string; agentType: string }>;
}

export default async function AgentPage({ params }: PageProps) {
  const { id: projectId, agentType } = await params;

  if (!isAgentType(agentType)) {
    notFound();
  }

  const supabase = createServerComponentClient({ cookies });
  await getAuthenticatedUser(supabase);

  const { data: project } = await supabase
    .from('projects')
    .select('id, name, status, basket_id, workspace_id')
    .eq('id', projectId)
    .maybeSingle();

  if (!project) {
    notFound();
  }

  if (agentType === 'thinking') {
    return (
      <ThinkingAgentClient
        project={{ id: project.id, name: project.name }}
        basketId={project.basket_id}
        workspaceId={project.workspace_id}
      />
    );
  }

  const { data: agentRow } = await supabase
    .from('project_agents')
    .select('id, display_name, agent_type, is_active, created_at')
    .eq('project_id', projectId)
    .eq('agent_type', agentType)
    .maybeSingle();

  // Fetch recent work tickets for this agent type
  const tickets: WorkTicket[] = project.basket_id
    ? (
        await supabase
          .from('work_tickets')
          .select('id, status, agent_type, created_at, completed_at, metadata')
          .eq('basket_id', project.basket_id)
          .eq('agent_type', agentType)
          .order('created_at', { ascending: false })
          .limit(5)
      ).data || []
    : [];

  // Fetch recipes for this agent type
  const { data: recipesData } = await supabase
    .from('work_recipes')
    .select('id, name, slug, description, agent_type')
    .eq('status', 'active')
    .eq('agent_type', agentType)
    .order('name', { ascending: true });

  const recipes: Recipe[] = (recipesData || []).map((r) => ({
    id: r.id,
    slug: r.slug,
    name: r.name,
    description: r.description,
  }));

  return (
    <AgentDashboardClient
      project={{ id: project.id, name: project.name }}
      agentRow={agentRow}
      tickets={tickets}
      recipes={recipes}
      agentType={agentType as AgentType}
    />
  );
}
