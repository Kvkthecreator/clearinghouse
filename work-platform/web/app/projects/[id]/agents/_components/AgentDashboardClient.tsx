"use client";

import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { formatDistanceToNow } from 'date-fns';
import { ArrowRight } from 'lucide-react';
import { AGENT_CONFIG, type AgentType } from '../config';
import { cn } from '@/lib/utils';
import AgentConfigForm from './AgentConfigForm';
import { ContextReadinessCard } from './ContextReadinessCard';

export type WorkTicket = {
  id: string;
  status: string;
  agent_type: string;
  created_at: string;
  completed_at: string | null;
  metadata: Record<string, any> | null;
};

export type Recipe = {
  id: string;
  slug: string;
  name: string;
  description: string | null;
};

interface AgentDashboardClientProps {
  project: {
    id: string;
    name: string;
  };
  agentRow: {
    id: string;
    display_name: string;
    agent_type: string;
    is_active: boolean;
    created_at: string;
  } | null;
  tickets: WorkTicket[];
  recipes: Recipe[];
  agentType: AgentType;
}

export default function AgentDashboardClient({ project, agentRow, tickets, recipes, agentType }: AgentDashboardClientProps) {
  const router = useRouter();
  const config = AGENT_CONFIG[agentType];

  const statusBadge = agentRow?.is_active ? 'Active' : 'Disabled';
  const lastTicket = tickets[0];
  const isDisabled = !agentRow?.is_active;

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-6">
      <header className="flex flex-col gap-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="text-sm text-muted-foreground">{project.name}</p>
            <div className="mt-1 flex items-center gap-3">
              <config.icon className="h-5 w-5 text-primary" />
              <h1 className="text-3xl font-bold text-foreground">{config.label}</h1>
              <Badge variant="outline" className={cn('capitalize', agentRow?.is_active ? 'text-primary border-primary/40' : 'text-muted-foreground')}>
                {statusBadge}
              </Badge>
            </div>
            <p className="mt-2 text-muted-foreground max-w-2xl">{config.description}</p>
          </div>
        </div>
      </header>

      {/* Context Readiness Indicator */}
      <ContextReadinessCard projectId={project.id} agentType={agentType} />

      {/* Available Work Recipes */}
      <Card className="p-6">
        <h2 className="text-lg font-semibold text-foreground mb-4">What I Can Do</h2>
        {recipes.length > 0 ? (
          <div className="grid gap-3 sm:grid-cols-2">
            {recipes.map((recipe) => (
              <button
                key={recipe.id}
                onClick={() => router.push(`/projects/${project.id}/work-tickets/new/configure?recipe=${recipe.slug}`)}
                disabled={isDisabled}
                className={cn(
                  "text-left rounded-xl border p-4 transition-all",
                  isDisabled
                    ? "opacity-50 cursor-not-allowed bg-muted"
                    : "hover:border-primary hover:shadow-sm cursor-pointer bg-card"
                )}
              >
                <h3 className="font-medium text-foreground">{recipe.name}</h3>
                {recipe.description && (
                  <p className="text-sm text-muted-foreground mt-1 line-clamp-2">
                    {recipe.description}
                  </p>
                )}
              </button>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            No work recipes available for this agent yet.
          </p>
        )}
        {isDisabled && recipes.length > 0 && (
          <p className="text-xs text-muted-foreground mt-3">
            Enable this agent to start work requests.
          </p>
        )}
      </Card>

      <Card className="p-6">
        <h2 className="text-lg font-semibold text-foreground mb-4">Recent Activity</h2>
        {lastTicket ? (
          <div className="space-y-2">
            <p className="text-sm text-muted-foreground">
              Last run {formatDistanceToNow(new Date(lastTicket.created_at), { addSuffix: true })}
            </p>
            <p className="text-foreground font-medium">
              {lastTicket.metadata?.task_intent || lastTicket.metadata?.description || 'Work ticket'}
            </p>
            <Badge variant="outline" className="capitalize">{lastTicket.status}</Badge>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">No work tickets yet. Kick off your first task.</p>
        )}
      </Card>

      {/* Configuration Section */}
      {agentRow && (
        <AgentConfigForm
          projectId={project.id}
          agentId={agentRow.id}
          agentType={agentType}
        />
      )}

      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-foreground">Work History</h2>
          {agentRow && tickets.length > 0 && (
            <Link
              href={`/projects/${project.id}/work-tickets-view?agent=${agentRow.id}`}
              className="text-sm text-primary hover:underline inline-flex items-center gap-1"
            >
              View all <ArrowRight className="h-3 w-3" />
            </Link>
          )}
        </div>
        {tickets.length === 0 ? (
          <p className="text-sm text-muted-foreground">Work history will appear here once this agent starts running tasks.</p>
        ) : (
          <div className="space-y-3">
            {tickets.map((ticket) => (
              <Link
                key={ticket.id}
                href={`/projects/${project.id}/work-tickets/${ticket.id}/track`}
                className="block rounded-lg border border-border p-4 hover:border-ring transition-colors"
              >
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">{new Date(ticket.created_at).toLocaleString()}</span>
                  <Badge variant="outline" className="capitalize">{ticket.status}</Badge>
                </div>
                <p className="mt-2 text-foreground text-sm font-medium">
                  {ticket.metadata?.task_intent || ticket.metadata?.description || 'Work ticket'}
                </p>
              </Link>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
