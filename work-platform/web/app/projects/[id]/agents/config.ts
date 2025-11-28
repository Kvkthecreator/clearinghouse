import { Brain, PenSquare, BarChart3, MessageSquare, type LucideIcon } from 'lucide-react';

export type AgentType = 'thinking' | 'research' | 'content' | 'reporting';

export type AgentConfig = {
  label: string;
  description: string;
  icon: LucideIcon;
};

export const AGENT_CONFIG: Record<AgentType, AgentConfig> = {
  thinking: {
    label: 'Thinking Partner',
    description: 'Conversational agent for orchestration, triage, and live context navigation.',
    icon: MessageSquare,
  },
  research: {
    label: 'Research Agent',
    description: 'Monitors markets, competitors, and signals with autonomous sweeps.',
    icon: Brain,
  },
  content: {
    label: 'Content Agent',
    description: 'Plans and drafts recurring content across channels.',
    icon: PenSquare,
  },
  reporting: {
    label: 'Reporting Agent',
    description: 'Transforms context and work history into structured reports.',
    icon: BarChart3,
  },
};

export function isAgentType(value: string): value is AgentType {
  return value in AGENT_CONFIG;
}
