'use client';

/**
 * LiveContextPane
 *
 * Spatial co-presence visualization for Thinking Partner.
 * Morphs UI based on TP's current state (idle, planning, delegating, executing, reviewing).
 *
 * This creates the "agent sees what I see" experience.
 */

import { useState, useEffect } from 'react';
import type { TPPhase, TPState } from '@/lib/types/thinking-partner';
import { cn } from '@/lib/utils';
import {
  Brain,
  Search,
  Pencil,
  FileText,
  CheckCircle2,
  Loader2,
} from 'lucide-react';
import { Badge } from '@/components/ui/Badge';

interface LiveContextPaneProps {
  basketId: string;
  className?: string;
  tpPhase?: TPPhase;
}

export function LiveContextPane({
  basketId,
  className,
  tpPhase = 'idle',
}: LiveContextPaneProps) {
  return (
    <div className={cn('flex h-full flex-col bg-muted/30', className)}>
      {/* State indicator */}
      <div className="border-b border-border bg-card p-4">
        <TPStateIndicator phase={tpPhase} />
      </div>

      {/* Morphing content based on TP state */}
      <div className="flex-1 overflow-y-auto p-6">
        {tpPhase === 'idle' && <IdleView basketId={basketId} />}
        {tpPhase === 'planning' && <PlanningView />}
        {tpPhase === 'delegating' && <DelegatingView />}
        {tpPhase === 'executing' && <ExecutingView />}
        {tpPhase === 'reviewing' && <ReviewingView />}
        {tpPhase === 'responding' && <RespondingView />}
      </div>
    </div>
  );
}

// ============================================================================
// State Indicator
// ============================================================================

interface TPStateIndicatorProps {
  phase: TPPhase;
}

function TPStateIndicator({ phase }: TPStateIndicatorProps) {
  const stateConfig: Record<
    TPPhase,
    { icon: React.ReactNode; label: string; color: string }
  > = {
    idle: {
      icon: <Brain className="h-4 w-4" />,
      label: 'Ready',
      color: 'bg-slate-100 text-slate-700 border-slate-200',
    },
    planning: {
      icon: <Loader2 className="h-4 w-4 animate-spin" />,
      label: 'Planning Workflow',
      color: 'bg-blue-100 text-blue-700 border-blue-200',
    },
    delegating: {
      icon: <Loader2 className="h-4 w-4 animate-spin" />,
      label: 'Delegating to Agent',
      color: 'bg-purple-100 text-purple-700 border-purple-200',
    },
    executing: {
      icon: <Loader2 className="h-4 w-4 animate-spin" />,
      label: 'Agent Executing',
      color: 'bg-amber-100 text-amber-700 border-amber-200',
    },
    reviewing: {
      icon: <CheckCircle2 className="h-4 w-4" />,
      label: 'Reviewing Outputs',
      color: 'bg-green-100 text-green-700 border-green-200',
    },
    responding: {
      icon: <Loader2 className="h-4 w-4 animate-spin" />,
      label: 'Formulating Response',
      color: 'bg-indigo-100 text-indigo-700 border-indigo-200',
    },
  };

  const config = stateConfig[phase];

  return (
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-medium text-foreground">Live Context</h3>
        <Badge variant="outline" className={cn('border', config.color)}>
          <span className="flex items-center gap-1.5">
            {config.icon}
            <span className="text-xs">{config.label}</span>
          </span>
        </Badge>
      </div>
    </div>
  );
}

// ============================================================================
// Phase Views
// ============================================================================

function IdleView({ basketId }: { basketId: string }) {
  return (
    <div className="space-y-6">
      <div className="text-center">
        <Brain className="mx-auto h-12 w-12 text-muted-foreground/50" />
        <h3 className="mt-4 text-lg font-medium text-foreground">
          Thinking Partner is Ready
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Start a conversation to see the system in action
        </p>
      </div>

      {/* Substrate overview */}
      <div className="space-y-3 rounded-lg border border-border bg-card p-4">
        <h4 className="text-sm font-medium text-foreground">
          Substrate Overview
        </h4>
        <div className="grid grid-cols-2 gap-4">
          <MetricCard label="Knowledge Blocks" value="—" loading />
          <MetricCard label="Documents" value="—" loading />
          <MetricCard label="Recent Work" value="—" loading />
          <MetricCard label="Agents Active" value="—" loading />
        </div>
      </div>

      {/* Recent activity placeholder */}
      <div className="space-y-3 rounded-lg border border-border bg-card p-4">
        <h4 className="text-sm font-medium text-foreground">Recent Activity</h4>
        <p className="text-xs text-muted-foreground">
          No recent activity. Start a Thinking Partner session to create work requests.
        </p>
      </div>
    </div>
  );
}

function PlanningView() {
  return (
    <div className="space-y-4">
      <div className="text-center">
        <Loader2 className="mx-auto h-12 w-12 animate-spin text-blue-500" />
        <h3 className="mt-4 text-lg font-medium text-foreground">
          Planning Multi-Step Workflow
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Analyzing requirements and breaking down into executable steps...
        </p>
      </div>

      {/* Workflow steps placeholder */}
      <div className="space-y-2 rounded-lg border border-border bg-card p-4">
        <h4 className="text-sm font-medium text-foreground">Workflow Steps</h4>
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="flex items-center gap-3 rounded-md border border-border bg-muted/30 p-3"
            >
              <div className="flex h-6 w-6 items-center justify-center rounded-full bg-primary/10 text-xs font-medium text-primary">
                {i}
              </div>
              <div className="h-4 flex-1 animate-pulse rounded bg-muted" />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function DelegatingView() {
  return (
    <div className="space-y-4">
      <div className="text-center">
        <Loader2 className="mx-auto h-12 w-12 animate-spin text-purple-500" />
        <h3 className="mt-4 text-lg font-medium text-foreground">
          Delegating to Specialist Agent
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Selecting appropriate agent and preparing work request...
        </p>
      </div>

      {/* Agent selection */}
      <div className="space-y-3 rounded-lg border border-border bg-card p-4">
        <h4 className="text-sm font-medium text-foreground">
          Agent Selection
        </h4>
        <div className="grid gap-3">
          <AgentCard
            name="Research Agent"
            icon={<Search className="h-4 w-4" />}
            status="selected"
          />
          <AgentCard
            name="Content Agent"
            icon={<Pencil className="h-4 w-4" />}
            status="idle"
          />
          <AgentCard
            name="Reporting Agent"
            icon={<FileText className="h-4 w-4" />}
            status="idle"
          />
        </div>
      </div>
    </div>
  );
}

function ExecutingView() {
  return (
    <div className="space-y-4">
      <div className="text-center">
        <Loader2 className="mx-auto h-12 w-12 animate-spin text-amber-500" />
        <h3 className="mt-4 text-lg font-medium text-foreground">
          Agent Executing Work
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Specialist agent is processing your request...
        </p>
      </div>

      {/* Progress */}
      <div className="space-y-3 rounded-lg border border-border bg-card p-4">
        <h4 className="text-sm font-medium text-foreground">
          Execution Progress
        </h4>
        <div className="space-y-2">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Status</span>
            <Badge variant="outline" className="bg-amber-50 text-amber-700">
              Running
            </Badge>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">Started</span>
            <span className="text-foreground">
              {new Date().toLocaleTimeString()}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

function ReviewingView() {
  return (
    <div className="space-y-4">
      <div className="text-center">
        <CheckCircle2 className="mx-auto h-12 w-12 text-green-500" />
        <h3 className="mt-4 text-lg font-medium text-foreground">
          Reviewing Work Outputs
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Analyzing agent deliverables and preparing response...
        </p>
      </div>

      {/* Work outputs summary */}
      <div className="space-y-3 rounded-lg border border-border bg-card p-4">
        <h4 className="text-sm font-medium text-foreground">
          Work Outputs Generated
        </h4>
        <p className="text-sm text-muted-foreground">
          Check the Thinking Partner pane for detailed work outputs
        </p>
      </div>
    </div>
  );
}

function RespondingView() {
  return (
    <div className="space-y-4">
      <div className="text-center">
        <Loader2 className="mx-auto h-12 w-12 animate-spin text-indigo-500" />
        <h3 className="mt-4 text-lg font-medium text-foreground">
          Formulating Response
        </h3>
        <p className="mt-2 text-sm text-muted-foreground">
          Synthesizing information and preparing conversational response...
        </p>
      </div>
    </div>
  );
}

// ============================================================================
// Helper Components
// ============================================================================

interface MetricCardProps {
  label: string;
  value: string;
  loading?: boolean;
}

function MetricCard({ label, value, loading }: MetricCardProps) {
  return (
    <div className="space-y-1">
      <div className="text-xs text-muted-foreground">{label}</div>
      {loading ? (
        <div className="h-6 w-16 animate-pulse rounded bg-muted" />
      ) : (
        <div className="text-lg font-semibold text-foreground">{value}</div>
      )}
    </div>
  );
}

interface AgentCardProps {
  name: string;
  icon: React.ReactNode;
  status: 'selected' | 'idle';
}

function AgentCard({ name, icon, status }: AgentCardProps) {
  return (
    <div
      className={cn(
        'flex items-center gap-3 rounded-md border p-3',
        status === 'selected'
          ? 'border-primary bg-primary/5'
          : 'border-border bg-muted/30'
      )}
    >
      <div
        className={cn(
          'flex h-8 w-8 items-center justify-center rounded-full',
          status === 'selected'
            ? 'bg-primary/10 text-primary'
            : 'bg-muted text-muted-foreground'
        )}
      >
        {icon}
      </div>
      <div className="flex-1">
        <div className="text-sm font-medium text-foreground">{name}</div>
      </div>
      {status === 'selected' && (
        <CheckCircle2 className="h-4 w-4 text-primary" />
      )}
    </div>
  );
}
