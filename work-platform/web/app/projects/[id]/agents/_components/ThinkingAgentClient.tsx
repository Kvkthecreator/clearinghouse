"use client";

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Card } from '@/components/ui/Card';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { TPChatInterface } from '@/components/thinking/TPChatInterface';
import { LiveContextPane } from '@/components/thinking/LiveContextPane';
import type { TPPhase } from '@/lib/types/thinking-partner';
import { AGENT_CONFIG } from '../config';

interface ThinkingAgentClientProps {
  project: {
    id: string;
    name: string;
  };
  basketId: string;
  workspaceId: string;
}

export function ThinkingAgentClient({
  project,
  basketId,
  workspaceId,
}: ThinkingAgentClientProps) {
  const router = useRouter();
  const config = AGENT_CONFIG.thinking;
  const [tpPhase, setTPPhase] = useState<TPPhase>('idle');

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-6">
      <header className="flex flex-col gap-3">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="text-sm text-muted-foreground">{project.name}</p>
            <div className="mt-1 flex items-center gap-3">
              <config.icon className="h-5 w-5 text-primary" />
              <h1 className="text-3xl font-bold text-foreground">{config.label}</h1>
              <Badge variant="outline" className="border-primary/40 text-primary">
                Interactive
              </Badge>
            </div>
            <p className="mt-2 max-w-2xl text-muted-foreground">
              {config.description}
            </p>
          </div>
          <div className="flex gap-2">
            <Button
              variant="secondary"
              onClick={() => router.push(`/projects/${project.id}/work-tickets-view`)}
            >
              View Work Tickets
            </Button>
          </div>
        </div>
      </header>

      <Card className="overflow-hidden border">
        <div className="flex h-[70vh] min-h-[600px]">
          <TPChatInterface
            basketId={basketId}
            workspaceId={workspaceId}
            className="w-2/5 border-r"
            onTPStateChange={(phase) => setTPPhase(phase as TPPhase)}
          />
          <LiveContextPane
            basketId={basketId}
            className="flex-1"
            tpPhase={tpPhase}
          />
        </div>
      </Card>
    </div>
  );
}
