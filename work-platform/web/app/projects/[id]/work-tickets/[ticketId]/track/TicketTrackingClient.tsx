"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/clients";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ArrowLeft, Download, RefreshCw, CheckCircle2, XCircle, Loader2, Clock, AlertTriangle, FileText, Calendar, Bot, User } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils";

interface WorkOutput {
  id: string;
  title: string;
  body: string;
  output_type: string;
  agent_type: string;
  file_id: string | null;
  file_format: string | null;
  generation_method: string;
  supervision_status: string;
  created_at: string;
}

interface WorkTicket {
  id: string;
  status: string;
  agent_type: string;
  source: string;  // 'manual' | 'thinking_partner' | 'schedule' | 'api'
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
  error_message: string | null;
  metadata: any;
  basket_id: string;
  work_outputs: WorkOutput[];
}

interface ScheduleInfo {
  id: string;
  frequency: string;
  day_of_week: number;
  time_of_day: string;
}

interface TicketTrackingClientProps {
  projectId: string;
  projectName: string;
  ticket: WorkTicket;
  recipeName: string;
  recipeParams: Record<string, any>;
  taskDescription: string;
  scheduleInfo?: ScheduleInfo | null;
}

const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const FREQUENCY_LABELS: Record<string, string> = {
  weekly: 'Weekly',
  biweekly: 'Every 2 weeks',
  monthly: 'Monthly',
};

export default function TicketTrackingClient({
  projectId,
  projectName,
  ticket: initialTicket,
  recipeName,
  recipeParams,
  taskDescription,
  scheduleInfo,
}: TicketTrackingClientProps) {
  const router = useRouter();
  const [ticket, setTicket] = useState<WorkTicket>(initialTicket);
  const [isRefreshing, setIsRefreshing] = useState(false);

  // Create authenticated Supabase client for Realtime (singleton pattern)
  const supabase = createBrowserClient();

  // Subscribe to real-time ticket updates
  useEffect(() => {
    const channel = supabase
      .channel(`work_ticket_${ticket.id}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'work_tickets',
          filter: `id=eq.${ticket.id}`,
        },
        async (payload) => {
          console.log('[Realtime] Ticket updated:', payload.new);
          setTicket((prev) => ({
            ...prev,
            ...(payload.new as any),
          }));

          // Fetch work_outputs when completed
          if (payload.new.status === 'completed' || payload.new.status === 'failed') {
            console.log('[Realtime] Ticket completed, fetching outputs...');
            // Fetch work_outputs for this ticket
            const { data: outputs } = await supabase
              .from('work_outputs')
              .select('id, title, body, output_type, agent_type, file_id, file_format, generation_method, created_at, supervision_status')
              .eq('work_ticket_id', ticket.id)
              .order('created_at', { ascending: false });

            if (outputs && outputs.length > 0) {
              console.log('[Realtime] Found outputs:', outputs.length);
              setTicket((prev) => ({
                ...prev,
                work_outputs: outputs,
              }));
            } else {
              console.log('[Realtime] No outputs found, triggering full refresh');
              handleRefresh();
            }
          }
        }
      )
      .subscribe();

    return () => {
      channel.unsubscribe();
    };
  }, [ticket.id, supabase]);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    router.refresh();
    setTimeout(() => setIsRefreshing(false), 1000);
  };

  const getStatusIcon = () => {
    switch (ticket.status) {
      case 'completed':
        return <CheckCircle2 className="h-5 w-5 text-success" />;
      case 'failed':
        return <XCircle className="h-5 w-5 text-destructive" />;
      case 'running':
        return <Loader2 className="h-5 w-5 text-primary animate-spin" />;
      default:
        return <Clock className="h-5 w-5 text-muted-foreground" />;
    }
  };

  const getStatusBadge = () => {
    const variants: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
      completed: 'default',
      running: 'secondary',
      failed: 'destructive',
      pending: 'outline',
    };
    return <Badge variant={variants[ticket.status] || 'outline'} className="capitalize">{ticket.status}</Badge>;
  };

  const formatDuration = () => {
    if (!ticket.started_at) return null;
    const start = new Date(ticket.started_at).getTime();
    const end = ticket.completed_at ? new Date(ticket.completed_at).getTime() : Date.now();
    const duration = Math.floor((end - start) / 1000);

    if (duration < 60) return `${duration}s`;
    const minutes = Math.floor(duration / 60);
    const seconds = duration % 60;
    return `${minutes}m ${seconds}s`;
  };

  // Check if execution produced expected results
  const hasOutputs = ticket.work_outputs && ticket.work_outputs.length > 0;
  const hasExecutionSteps = ticket.metadata?.final_todos && ticket.metadata.final_todos.length > 0;
  const executionTimeMs = ticket.metadata?.execution_time_ms;
  const isCompleted = ticket.status === 'completed';
  const isFailed = ticket.status === 'failed';
  const isRunning = ticket.status === 'running' || ticket.status === 'pending';

  // Count outputs by supervision status
  const pendingReviewOutputs = ticket.work_outputs?.filter(o => o.supervision_status === 'pending_review') || [];
  const approvedOutputs = ticket.work_outputs?.filter(o => o.supervision_status === 'approved') || [];
  const hasPendingReview = pendingReviewOutputs.length > 0;

  // Determine if this is a problematic execution
  const isProblematicExecution = isCompleted && !hasOutputs && !isFailed;

  // Source label helper
  const getSourceLabel = () => {
    switch (ticket.source) {
      case 'thinking_partner':
        return { label: 'Thinking Partner', icon: Bot, color: 'text-primary' };
      case 'schedule':
        return { label: 'Scheduled', icon: Calendar, color: 'text-blue-600' };
      case 'manual':
        return { label: 'Manual', icon: User, color: 'text-muted-foreground' };
      default:
        return { label: ticket.source || 'Unknown', icon: User, color: 'text-muted-foreground' };
    }
  };
  const sourceInfo = getSourceLabel();

  return (
    <div className="mx-auto max-w-3xl space-y-4 p-6">
      {/* Header - Compact */}
      <div className="space-y-2">
        <Link
          href={`/projects/${projectId}/work-tickets-view`}
          className="inline-flex items-center text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4 mr-1" />
          Back to Work Tickets
        </Link>
        <div className="flex items-start justify-between">
          <div className="flex-1">
            <h1 className="text-2xl font-bold text-foreground">{recipeName}</h1>
            <p className="text-sm text-muted-foreground">{projectName}</p>
          </div>
          <div className="flex items-center gap-2">
            {getStatusIcon()}
            {getStatusBadge()}
          </div>
        </div>
      </div>

      {/* Warning Banner for problematic executions */}
      {isProblematicExecution && (
        <Card className="p-4 border-surface-warning-border bg-surface-warning">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <h3 className="font-semibold text-warning-foreground">Execution Completed Without Outputs</h3>
              <p className="text-sm text-warning-foreground/80 mt-1">
                The agent executed for {executionTimeMs ? `${(executionTimeMs / 1000).toFixed(1)}s` : 'an unknown duration'} but did not produce any work outputs or detailed execution steps.
                This may indicate the agent did not follow the recipe requirements properly.
              </p>
              <p className="text-xs text-warning-foreground/70 mt-2">
                Expected: {recipeParams.output_format ? recipeParams.output_format.toUpperCase() : 'file'} output via Skill tool • Actual: No outputs
              </p>
            </div>
          </div>
        </Card>
      )}

      {/* Pending Review Banner - Prominent CTA for completed tickets with pending outputs */}
      {isCompleted && hasPendingReview && (
        <Card className="p-4 border-yellow-500/30 bg-yellow-500/5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <FileText className="h-5 w-5 text-yellow-600" />
              <div>
                <p className="font-semibold text-foreground">
                  {pendingReviewOutputs.length} {pendingReviewOutputs.length === 1 ? 'output' : 'outputs'} ready for review
                </p>
                <p className="text-sm text-muted-foreground">
                  Review the agent's work before it can be used
                </p>
              </div>
            </div>
            <Link href={`/projects/${projectId}/work-tickets-view`}>
              <Button className="bg-yellow-600 hover:bg-yellow-700">
                View All Tickets
              </Button>
            </Link>
          </div>
        </Card>
      )}

      {/* Single Card Layout */}
      <Card className="p-6">
        {/* Summary Bar - Compact metrics inline */}
        <div className="flex items-center justify-between pb-4 border-b border-border mb-4">
          <div className="flex items-center gap-4">
            {/* Source badge */}
            <div className={cn("flex items-center gap-1.5 text-sm", sourceInfo.color)}>
              <sourceInfo.icon className="h-4 w-4" />
              <span>{sourceInfo.label}</span>
            </div>

            {/* Schedule badge if applicable */}
            {scheduleInfo && (
              <Badge variant="outline" className="text-blue-600 border-blue-600/30 bg-blue-50">
                <Calendar className="h-3 w-3 mr-1" />
                {FREQUENCY_LABELS[scheduleInfo.frequency] || scheduleInfo.frequency}
              </Badge>
            )}

            {/* Agent type */}
            <Badge variant="outline" className="capitalize">
              {ticket.agent_type}
            </Badge>
          </div>

          <div className="flex items-center gap-4 text-sm text-muted-foreground">
            <span>{ticket.work_outputs?.length || 0} outputs</span>
            <span>{formatDuration() || '—'}</span>
            <span>{new Date(ticket.created_at).toLocaleDateString()}</span>
            <Button
              variant="ghost"
              size="sm"
              onClick={handleRefresh}
              disabled={isRefreshing}
            >
              <RefreshCw className={cn("h-4 w-4", isRefreshing && "animate-spin")} />
            </Button>
          </div>
        </div>

        {/* Agent Activity - For running tickets */}
        {isRunning && (
          <div className="mb-4">
            <h3 className="text-sm font-medium mb-2 flex items-center gap-2">
              <Loader2 className="h-4 w-4 animate-spin text-primary" />
              Agent Activity
            </h3>
            <RealtimeProgressList currentTodos={ticket.metadata?.current_todos} />
          </div>
        )}

        {/* Agent Activity - For completed tickets */}
        {!isRunning && hasExecutionSteps && (
          <div className="mb-4">
            <h3 className="text-sm font-medium mb-2 flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-success" />
              Completed Steps
            </h3>
            <div className="space-y-1">
              {ticket.metadata.final_todos.slice(0, 5).map((todo: any, index: number) => (
                <div key={index} className="flex items-center gap-2 text-sm text-muted-foreground">
                  <CheckCircle2 className="h-3 w-3 text-success flex-shrink-0" />
                  <span className="truncate">{todo.content || todo.activeForm || `Step ${index + 1}`}</span>
                </div>
              ))}
              {ticket.metadata.final_todos.length > 5 && (
                <p className="text-xs text-muted-foreground pl-5">
                  +{ticket.metadata.final_todos.length - 5} more steps
                </p>
              )}
            </div>
          </div>
        )}

        {/* Error Message */}
        {isFailed && ticket.error_message && (
          <div className="mb-4 p-3 rounded bg-destructive/10 border border-destructive/20">
            <h3 className="text-sm font-medium text-destructive flex items-center gap-2 mb-1">
              <XCircle className="h-4 w-4" />
              Execution Failed
            </h3>
            <p className="text-xs text-destructive-foreground font-mono">
              {ticket.error_message}
            </p>
          </div>
        )}

        {/* Work Outputs */}
        {hasOutputs ? (
          <div>
            <h3 className="text-sm font-medium mb-3">Work Outputs ({ticket.work_outputs.length})</h3>
            <div className="space-y-3">
              {ticket.work_outputs.map((output) => (
                <OutputCard key={output.id} output={output} basketId={ticket.basket_id} projectId={projectId} />
              ))}
            </div>
          </div>
        ) : isCompleted && (
          <div className="p-3 rounded bg-yellow-500/10 border border-yellow-500/20">
            <h3 className="text-sm font-medium text-yellow-700 mb-1">No Work Outputs</h3>
            <p className="text-xs text-yellow-600">
              The agent completed but did not generate outputs. This may indicate an execution issue.
            </p>
          </div>
        )}
      </Card>
    </div>
  );
}

function OutputCard({ output, basketId, projectId }: { output: WorkOutput; basketId: string; projectId: string }) {
  const isFileOutput = output.file_id && output.file_format;
  const [isDownloading, setIsDownloading] = useState(false);
  const [downloadError, setDownloadError] = useState<string | null>(null);

  const supervisionStatus = output.supervision_status || 'pending_review';
  const isPending = supervisionStatus === 'pending_review';
  const isApproved = supervisionStatus === 'approved';

  const handleDownload = async () => {
    if (!isFileOutput) return;

    setIsDownloading(true);
    setDownloadError(null);

    try {
      const response = await fetch(
        `/api/work-outputs/${output.id}/download?basket_id=${basketId}`
      );

      if (!response.ok) {
        const error = await response.json().catch(() => ({ detail: 'Download failed' }));
        throw new Error(error.detail || 'Download failed');
      }

      // Get filename from Content-Disposition header or generate one
      const contentDisposition = response.headers.get('Content-Disposition');
      let filename = `${output.title}.${output.file_format}`;
      if (contentDisposition) {
        const match = contentDisposition.match(/filename="(.+)"/);
        if (match) {
          filename = match[1];
        }
      }

      // Create blob and download
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Download failed:', error);
      setDownloadError(error instanceof Error ? error.message : 'Download failed');
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <div className={cn(
      "border rounded-lg p-4 space-y-3",
      isPending ? "border-yellow-500/30 bg-yellow-500/5" : "border-border"
    )}>
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <h3 className="font-medium text-foreground">{output.title}</h3>
          <div className="flex items-center gap-2 mt-1 flex-wrap">
            <Badge variant="outline" className="text-xs">
              {output.output_type}
            </Badge>
            {output.file_format && (
              <Badge variant="secondary" className="text-xs uppercase">
                {output.file_format}
              </Badge>
            )}
            {/* Supervision Status Badge */}
            <Badge
              variant="outline"
              className={cn(
                "text-xs",
                isPending && "bg-yellow-500/10 text-yellow-700 border-yellow-500/30",
                isApproved && "bg-green-500/10 text-green-700 border-green-500/30",
                supervisionStatus === 'rejected' && "bg-red-500/10 text-red-700 border-red-500/30"
              )}
            >
              {isPending ? 'Pending Review' : isApproved ? 'Approved' : supervisionStatus.replace('_', ' ')}
            </Badge>
            <span className="text-xs text-muted-foreground">
              {output.generation_method}
            </span>
            {!isFileOutput && output.body && (
              <span className="text-xs text-muted-foreground">
                ({output.body.length} chars)
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {isPending && (
            <Badge variant="warning">Pending</Badge>
          )}
          {isFileOutput && (
            <Button
              variant="ghost"
              size="sm"
              onClick={handleDownload}
              disabled={isDownloading}
            >
              {isDownloading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Download className="h-4 w-4" />
              )}
            </Button>
          )}
        </div>
      </div>

      {/* Preview body for text outputs */}
      {!isFileOutput && output.body && (
        <OutputBodyPreview body={output.body} />
      )}

      {/* File download info */}
      {isFileOutput && !downloadError && (
        <div className="text-sm text-success-foreground bg-surface-success border border-surface-success-border rounded p-2">
          File ready for download
        </div>
      )}

      {/* Download error */}
      {downloadError && (
        <div className="text-sm text-destructive bg-surface-danger border border-surface-danger-border rounded p-2">
          {downloadError}
        </div>
      )}
    </div>
  );
}

/**
 * Real-time progress list component - displays current_todos from metadata
 * Updated via Supabase Realtime subscription in parent component
 */
interface TodoItem {
  content: string;
  status: "pending" | "in_progress" | "completed" | "failed";
  activeForm: string;
}

function RealtimeProgressList({ currentTodos }: { currentTodos?: TodoItem[] }) {
  if (!currentTodos || currentTodos.length === 0) {
    return (
      <div className="text-sm text-muted-foreground italic flex items-center gap-2">
        <Loader2 className="h-4 w-4 animate-spin" />
        Agent is working...
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {currentTodos.map((todo, index) => {
        const statusIcon = {
          pending: <Clock className="h-4 w-4 text-muted-foreground" />,
          in_progress: <Loader2 className="h-4 w-4 text-primary animate-spin" />,
          completed: <CheckCircle2 className="h-4 w-4 text-success" />,
          failed: <XCircle className="h-4 w-4 text-destructive" />,
        }[todo.status] || <Clock className="h-4 w-4 text-muted-foreground" />;

        const statusColor = {
          pending: "text-muted-foreground",
          in_progress: "text-primary",
          completed: "text-success",
          failed: "text-destructive",
        }[todo.status] || "text-muted-foreground";

        return (
          <div key={index} className={cn("flex items-start gap-2 text-sm", statusColor)}>
            <span className="flex-shrink-0 mt-0.5">{statusIcon}</span>
            <div className="flex-1 min-w-0">
              <p className="truncate" title={todo.activeForm}>
                {todo.activeForm || todo.content}
              </p>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/**
 * Smart body preview - parses JSON and formats nicely, or shows plain text
 */
function OutputBodyPreview({ body }: { body: string }) {
  // Try to parse as JSON for better formatting
  let parsedContent: Record<string, any> | null = null;
  try {
    parsedContent = JSON.parse(body);
  } catch {
    // Not JSON, show as plain text
  }

  if (parsedContent && typeof parsedContent === 'object') {
    // Render structured JSON content
    return (
      <div className="text-sm bg-muted rounded p-3 space-y-2 max-h-48 overflow-auto">
        {Object.entries(parsedContent).slice(0, 5).map(([key, value]) => (
          <div key={key}>
            <p className="text-xs font-medium text-muted-foreground capitalize">
              {key.replace(/_/g, ' ')}
            </p>
            <p className="text-foreground text-sm">
              {typeof value === 'string'
                ? value.slice(0, 200) + (value.length > 200 ? '...' : '')
                : JSON.stringify(value).slice(0, 200)}
            </p>
          </div>
        ))}
        {Object.keys(parsedContent).length > 5 && (
          <p className="text-xs text-muted-foreground">
            +{Object.keys(parsedContent).length - 5} more fields
          </p>
        )}
      </div>
    );
  }

  // Plain text fallback
  return (
    <div className="text-sm text-muted-foreground max-h-32 overflow-auto bg-muted rounded p-3">
      <p className="whitespace-pre-wrap text-xs">
        {body.slice(0, 500)}{body.length > 500 ? '...' : ''}
      </p>
    </div>
  );
}
