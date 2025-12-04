"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/clients";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ArrowLeft, Download, RefreshCw, CheckCircle2, XCircle, Loader2, Clock, AlertTriangle, FileText, Calendar } from "lucide-react";
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

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-6">
      {/* Header */}
      <div className="space-y-2">
        <Link
          href={`/projects/${projectId}/work-tickets-view`}
          className="inline-flex items-center text-sm text-muted-foreground hover:text-foreground mb-2"
        >
          <ArrowLeft className="h-4 w-4 mr-1" />
          Back to Work Tickets
        </Link>
        <div className="flex items-start justify-between">
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <h1 className="text-3xl font-bold text-foreground">{recipeName}</h1>
              {scheduleInfo && (
                <Badge variant="outline" className="text-primary border-primary/30 bg-primary/5">
                  <Calendar className="h-3 w-3 mr-1" />
                  Scheduled
                </Badge>
              )}
            </div>
            <p className="text-muted-foreground mt-1">{projectName}</p>
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

      {/* Main Content Grid */}
      <div className="grid gap-6 lg:grid-cols-3">
        {/* Left Column: Outputs & Progress */}
        <div className="lg:col-span-2 space-y-6">

          {/* Agent Activity - For running tickets: show live progress from Realtime */}
          {isRunning && (
            <Card className="p-6">
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <Loader2 className="h-5 w-5 animate-spin text-primary" />
                Agent Activity
              </h2>
              <RealtimeProgressList currentTodos={ticket.metadata?.current_todos} />
            </Card>
          )}

          {/* Agent Activity - For completed tickets: show execution history */}
          {!isRunning && hasExecutionSteps && (
            <Card className="p-6">
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <CheckCircle2 className="h-5 w-5 text-success" />
                Agent Activity
              </h2>
              <p className="text-sm text-muted-foreground mb-4">
                Steps completed by the agent during execution:
              </p>
              <div className="space-y-2">
                {ticket.metadata.final_todos.map((todo: any, index: number) => (
                  <div key={index} className="flex items-center gap-2 text-sm">
                    <CheckCircle2 className="h-4 w-4 text-success flex-shrink-0" />
                    <span className="text-foreground">
                      {todo.content || todo.activeForm || `Step ${index + 1}`}
                    </span>
                  </div>
                ))}
              </div>
            </Card>
          )}

          {/* Error Message */}
          {isFailed && ticket.error_message && (
            <Card className="p-6 border-surface-danger-border bg-surface-danger">
              <h2 className="text-lg font-semibold mb-2 text-destructive flex items-center gap-2">
                <XCircle className="h-5 w-5" />
                Execution Failed
              </h2>
              <p className="text-sm text-destructive-foreground font-mono bg-destructive/10 p-3 rounded">
                {ticket.error_message}
              </p>
            </Card>
          )}

          {/* Work Outputs */}
          {hasOutputs ? (
            <Card className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-lg font-semibold">Work Outputs ({ticket.work_outputs.length})</h2>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleRefresh}
                  disabled={isRefreshing}
                >
                  <RefreshCw className={cn("h-4 w-4", isRefreshing && "animate-spin")} />
                </Button>
              </div>
              <div className="space-y-4">
                {ticket.work_outputs.map((output) => (
                  <OutputCard key={output.id} output={output} basketId={ticket.basket_id} projectId={projectId} />
                ))}
              </div>
            </Card>
          ) : isCompleted && (
            <Card className="p-6 border-surface-warning-border bg-surface-warning">
              <h2 className="text-lg font-semibold mb-3 text-warning-foreground">No Work Outputs</h2>
              <div className="space-y-3 text-sm text-warning-foreground/90">
                <p>
                  The agent completed execution but did not generate any work outputs.
                  This is unexpected for a {ticket.agent_type} agent working on a {recipeName} task.
                </p>
                <div className="bg-warning/10 border border-surface-warning-border rounded p-3">
                  <p className="font-medium mb-2 text-warning-foreground">Expected Output:</p>
                  <ul className="list-disc list-inside space-y-1 text-xs">
                    {recipeParams.output_format && (
                      <li>Format: {recipeParams.output_format.toUpperCase()} file</li>
                    )}
                    <li>Generation method: Skill tool (professional file generation)</li>
                    <li>Output type: report_draft or final_report</li>
                  </ul>
                </div>
                <p className="text-xs text-warning-foreground/70">
                  This may indicate a bug in the agent execution or a missing emit_work_output call.
                  Check the agent logs for more details.
                </p>
              </div>
            </Card>
          )}
        </div>

        {/* Right Column: Summary */}
        <div className="space-y-6">
          {/* Execution Summary - Consolidated info */}
          <Card className="p-6">
            <h2 className="text-lg font-semibold mb-4">Summary</h2>
            <div className="space-y-4">
              {/* Key metrics */}
              <div className="grid grid-cols-2 gap-4">
                <div className="text-center p-3 bg-muted/50 rounded-lg">
                  <p className={cn(
                    "text-2xl font-bold",
                    hasOutputs ? "text-success" : "text-muted-foreground"
                  )}>
                    {ticket.work_outputs?.length || 0}
                  </p>
                  <p className="text-xs text-muted-foreground">Outputs</p>
                </div>
                <div className="text-center p-3 bg-muted/50 rounded-lg">
                  <p className="text-2xl font-bold text-foreground font-mono">
                    {formatDuration() || '—'}
                  </p>
                  <p className="text-xs text-muted-foreground">Duration</p>
                </div>
              </div>

              {/* Task description */}
              {taskDescription && (
                <div className="pt-3 border-t border-border">
                  <p className="text-xs text-muted-foreground mb-1">Task</p>
                  <p className="text-sm text-foreground">{taskDescription}</p>
                </div>
              )}

              {/* Timeline (compact) */}
              <div className="pt-3 border-t border-border space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Created</span>
                  <span className="text-foreground">{new Date(ticket.created_at).toLocaleDateString()}</span>
                </div>
                {ticket.completed_at && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Completed</span>
                    <span className="text-foreground">{new Date(ticket.completed_at).toLocaleDateString()}</span>
                  </div>
                )}
              </div>

              {/* Agent type badge */}
              <div className="pt-3 border-t border-border">
                <Badge variant="outline" className="capitalize">
                  {ticket.agent_type} agent
                </Badge>
              </div>
            </div>
          </Card>

          {/* Schedule Info (if triggered by schedule) */}
          {scheduleInfo && (
            <Card className="p-6 border-primary/20 bg-primary/5">
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <Calendar className="h-5 w-5 text-primary" />
                Scheduled Run
              </h2>
              <div className="space-y-2 text-sm">
                <p className="text-foreground">
                  {FREQUENCY_LABELS[scheduleInfo.frequency] || scheduleInfo.frequency} on {DAY_NAMES[scheduleInfo.day_of_week]}s
                </p>
                <Link href={`/projects/${projectId}/schedules`}>
                  <Button variant="outline" size="sm" className="w-full mt-2">
                    <Calendar className="h-4 w-4 mr-2" />
                    View Schedule
                  </Button>
                </Link>
              </div>
            </Card>
          )}
        </div>
      </div>
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
