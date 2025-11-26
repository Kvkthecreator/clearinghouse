"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/clients";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ArrowLeft, Download, RefreshCw, CheckCircle2, XCircle, Loader2, Clock } from "lucide-react";
import Link from "next/link";
import { TaskProgressList } from "@/components/TaskProgressList";
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

interface TicketTrackingClientProps {
  projectId: string;
  projectName: string;
  ticket: WorkTicket;
  recipeName: string;
  recipeParams: Record<string, any>;
  taskDescription: string;
}

export default function TicketTrackingClient({
  projectId,
  projectName,
  ticket: initialTicket,
  recipeName,
  recipeParams,
  taskDescription,
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
        (payload) => {
          console.log('[Realtime] Ticket updated:', payload.new);
          setTicket((prev) => ({
            ...prev,
            ...(payload.new as any),
          }));

          // Refresh outputs when completed
          if (payload.new.status === 'completed' || payload.new.status === 'failed') {
            handleRefresh();
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
        return <CheckCircle2 className="h-5 w-5 text-green-600" />;
      case 'failed':
        return <XCircle className="h-5 w-5 text-red-600" />;
      case 'running':
        return <Loader2 className="h-5 w-5 text-blue-600 animate-spin" />;
      default:
        return <Clock className="h-5 w-5 text-gray-400" />;
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
            <h1 className="text-3xl font-bold text-foreground">{recipeName}</h1>
            <p className="text-muted-foreground mt-1">{projectName}</p>
          </div>
          <div className="flex items-center gap-2">
            {getStatusIcon()}
            {getStatusBadge()}
          </div>
        </div>
      </div>

      {/* Main Content Grid */}
      <div className="grid gap-6 lg:grid-cols-3">
        {/* Left Column: Metadata & Progress */}
        <div className="lg:col-span-2 space-y-6">
          {/* Recipe Parameters */}
          <Card className="p-6">
            <h2 className="text-lg font-semibold mb-4">Configuration</h2>
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                <Badge variant="outline" className="capitalize">
                  {ticket.agent_type}
                </Badge>
                {ticket.metadata?.output_format && (
                  <Badge variant="outline" className="uppercase">
                    {ticket.metadata.output_format}
                  </Badge>
                )}
              </div>

              {taskDescription && (
                <div>
                  <span className="text-sm font-medium text-muted-foreground">Task:</span>
                  <p className="text-sm text-foreground mt-1">{taskDescription}</p>
                </div>
              )}

              {Object.keys(recipeParams).length > 0 && (
                <div>
                  <span className="text-sm font-medium text-muted-foreground">Parameters:</span>
                  <dl className="mt-2 space-y-2">
                    {Object.entries(recipeParams).map(([key, value]) => (
                      <div key={key} className="flex gap-2 text-sm">
                        <dt className="font-medium text-muted-foreground capitalize">
                          {key.replace(/_/g, ' ')}:
                        </dt>
                        <dd className="text-foreground">
                          {Array.isArray(value) ? value.join(', ') : String(value)}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </div>
              )}
            </div>
          </Card>

          {/* Task Progress */}
          {(ticket.status === 'running' || ticket.status === 'pending') && (
            <Card className="p-6">
              <h2 className="text-lg font-semibold mb-4">Execution Progress</h2>
              <TaskProgressList workTicketId={ticket.id} enabled={true} />
            </Card>
          )}

          {/* Historical TodoWrite (for completed tickets) */}
          {ticket.status === 'completed' && ticket.metadata?.final_todos && (
            <Card className="p-6">
              <h2 className="text-lg font-semibold mb-4">Execution Summary</h2>
              <div className="space-y-2">
                {ticket.metadata.final_todos.map((todo: any, index: number) => (
                  <div key={index} className="flex items-center gap-2 text-sm text-muted-foreground">
                    <CheckCircle2 className="h-4 w-4 text-green-600" />
                    <span>{todo.content}</span>
                  </div>
                ))}
              </div>
            </Card>
          )}

          {/* Error Message */}
          {ticket.status === 'failed' && ticket.error_message && (
            <Card className="p-6 border-red-500/20 bg-red-500/5">
              <h2 className="text-lg font-semibold mb-2 text-red-600">Execution Failed</h2>
              <p className="text-sm text-red-600/80">{ticket.error_message}</p>
            </Card>
          )}

          {/* Output Preview */}
          {ticket.work_outputs && ticket.work_outputs.length > 0 && (
            <Card className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-lg font-semibold">Outputs ({ticket.work_outputs.length})</h2>
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
                  <OutputCard key={output.id} output={output} />
                ))}
              </div>
            </Card>
          )}
        </div>

        {/* Right Column: Metadata */}
        <div className="space-y-6">
          {/* Timeline */}
          <Card className="p-6">
            <h2 className="text-lg font-semibold mb-4">Timeline</h2>
            <div className="space-y-3 text-sm">
              <div>
                <span className="text-muted-foreground">Created:</span>
                <p className="text-foreground">{new Date(ticket.created_at).toLocaleString()}</p>
              </div>
              {ticket.started_at && (
                <div>
                  <span className="text-muted-foreground">Started:</span>
                  <p className="text-foreground">{new Date(ticket.started_at).toLocaleString()}</p>
                </div>
              )}
              {ticket.completed_at && (
                <div>
                  <span className="text-muted-foreground">Completed:</span>
                  <p className="text-foreground">{new Date(ticket.completed_at).toLocaleString()}</p>
                </div>
              )}
              {formatDuration() && (
                <div>
                  <span className="text-muted-foreground">Duration:</span>
                  <p className="text-foreground font-mono">{formatDuration()}</p>
                </div>
              )}
            </div>
          </Card>

          {/* Actions */}
          <Card className="p-6">
            <h2 className="text-lg font-semibold mb-4">Actions</h2>
            <div className="space-y-2">
              <Button
                variant="outline"
                className="w-full"
                onClick={handleRefresh}
                disabled={isRefreshing}
              >
                <RefreshCw className={cn("h-4 w-4 mr-2", isRefreshing && "animate-spin")} />
                Refresh
              </Button>
              <Link href={`/projects/${projectId}/work-tickets-view`} className="block">
                <Button variant="outline" className="w-full">
                  View All Tickets
                </Button>
              </Link>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}

function OutputCard({ output }: { output: WorkOutput }) {
  const isFileOutput = output.file_id && output.file_format;

  return (
    <div className="border rounded-lg p-4 space-y-3">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <h3 className="font-medium text-foreground">{output.title}</h3>
          <div className="flex items-center gap-2 mt-1">
            <Badge variant="outline" className="text-xs">
              {output.output_type}
            </Badge>
            {output.file_format && (
              <Badge variant="secondary" className="text-xs uppercase">
                {output.file_format}
              </Badge>
            )}
            <span className="text-xs text-muted-foreground">
              {output.generation_method}
            </span>
          </div>
        </div>
        {isFileOutput && (
          <Button variant="ghost" size="sm">
            <Download className="h-4 w-4" />
          </Button>
        )}
      </div>

      {/* Preview body for text outputs */}
      {!isFileOutput && output.body && (
        <div className="text-sm text-muted-foreground max-h-32 overflow-auto">
          <pre className="whitespace-pre-wrap font-sans">{output.body.slice(0, 300)}...</pre>
        </div>
      )}

      {/* File download info */}
      {isFileOutput && (
        <div className="text-sm text-muted-foreground">
          File ready for download
        </div>
      )}
    </div>
  );
}
