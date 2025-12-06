'use client';

/**
 * TicketsDetailPanel
 *
 * Displays work tickets in the detail panel.
 * Shows active/queued tickets with progress tracking.
 *
 * Part of Chat-First Architecture v1.0
 * See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
 */

import { useState, useEffect, useMemo } from 'react';
import { cn } from '@/lib/utils';
import {
  Search,
  ChevronRight,
  Clock,
  Play,
  CheckCircle2,
  XCircle,
  Pause,
  AlertCircle,
  Zap,
  FileText,
  RefreshCw,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';

// Work ticket types (should match API types)
interface WorkTicket {
  id: string;
  recipe_slug?: string;
  recipe_name?: string;
  description?: string;
  status: 'queued' | 'running' | 'completed' | 'failed' | 'cancelled';
  priority?: number;
  progress_pct?: number;
  current_step?: string;
  agent_type?: string;
  outputs_count?: number;
  error_message?: string;
  started_at?: string;
  completed_at?: string;
  created_at: string;
  updated_at: string;
}

interface TicketsDetailPanelProps {
  basketId: string;
  tickets?: WorkTicket[];
  loading?: boolean;
  error?: string;
  focusedTicketId?: string;
  onTicketClick?: (ticket: WorkTicket) => void;
  onCancelTicket?: (ticketId: string) => void;
  onRetryTicket?: (ticketId: string) => void;
  className?: string;
}

// Status configuration
const STATUS_CONFIG: Record<string, { label: string; color: string; bgColor: string; Icon: React.ElementType }> = {
  queued: {
    label: 'Queued',
    color: 'text-blue-600',
    bgColor: 'bg-blue-50 border-blue-200',
    Icon: Clock,
  },
  running: {
    label: 'Running',
    color: 'text-amber-600',
    bgColor: 'bg-amber-50 border-amber-200',
    Icon: Play,
  },
  completed: {
    label: 'Completed',
    color: 'text-green-600',
    bgColor: 'bg-green-50 border-green-200',
    Icon: CheckCircle2,
  },
  failed: {
    label: 'Failed',
    color: 'text-red-600',
    bgColor: 'bg-red-50 border-red-200',
    Icon: XCircle,
  },
  cancelled: {
    label: 'Cancelled',
    color: 'text-gray-600',
    bgColor: 'bg-gray-50 border-gray-200',
    Icon: Pause,
  },
};

// Agent type labels
const AGENT_LABELS: Record<string, string> = {
  research: 'Research',
  content: 'Content',
  reporting: 'Reporting',
  thinking_partner: 'TP',
};

export function TicketsDetailPanel({
  basketId,
  tickets = [],
  loading,
  error,
  focusedTicketId,
  onTicketClick,
  onCancelTicket,
  onRetryTicket,
  className,
}: TicketsDetailPanelProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<string | null>(null);
  const [selectedTicket, setSelectedTicket] = useState<WorkTicket | null>(null);

  // Focus on specific ticket when provided
  useEffect(() => {
    if (focusedTicketId) {
      const ticket = tickets.find((t) => t.id === focusedTicketId);
      if (ticket) {
        setSelectedTicket(ticket);
      }
    }
  }, [focusedTicketId, tickets]);

  // Filter tickets
  const filteredTickets = useMemo(() => {
    return tickets.filter((ticket) => {
      // Search filter
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        const name = (ticket.recipe_name || ticket.recipe_slug || '').toLowerCase();
        const desc = (ticket.description || '').toLowerCase();
        if (!name.includes(query) && !desc.includes(query)) {
          return false;
        }
      }

      // Status filter
      if (filterStatus && ticket.status !== filterStatus) {
        return false;
      }

      return true;
    });
  }, [tickets, searchQuery, filterStatus]);

  // Group tickets by status
  const groupedTickets = useMemo(() => {
    const groups: Record<string, WorkTicket[]> = {
      running: [],
      queued: [],
      completed: [],
      failed: [],
      cancelled: [],
    };

    filteredTickets.forEach((ticket) => {
      const status = ticket.status || 'queued';
      if (!groups[status]) {
        groups[status] = [];
      }
      groups[status].push(ticket);
    });

    return groups;
  }, [filteredTickets]);

  const handleTicketClick = (ticket: WorkTicket) => {
    setSelectedTicket(ticket);
    onTicketClick?.(ticket);
  };

  // Count active
  const activeCount = groupedTickets.running.length + groupedTickets.queued.length;

  // If viewing specific ticket
  if (selectedTicket) {
    return (
      <TicketDetail
        ticket={selectedTicket}
        onBack={() => setSelectedTicket(null)}
        onCancel={onCancelTicket}
        onRetry={onRetryTicket}
        className={className}
      />
    );
  }

  return (
    <div className={cn('flex h-full flex-col', className)}>
      {/* Header */}
      <div className="border-b border-border p-3 space-y-2">
        {/* Active indicator */}
        {activeCount > 0 && (
          <div className="flex items-center gap-2 p-2 rounded-md bg-amber-50 border border-amber-200">
            <Zap className="h-4 w-4 text-amber-600 animate-pulse" />
            <span className="text-sm text-amber-700 font-medium">
              {activeCount} ticket{activeCount > 1 ? 's' : ''} in progress
            </span>
          </div>
        )}

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search tickets..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-md border border-input bg-background py-2 pl-10 pr-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>

        {/* Status filters */}
        <div className="flex items-center gap-1 flex-wrap">
          {Object.entries(STATUS_CONFIG).map(([status, config]) => {
            const StatusIcon = config.Icon;
            const isActive = filterStatus === status;
            const count = groupedTickets[status]?.length || 0;
            if (count === 0 && !isActive) return null;
            return (
              <button
                key={status}
                onClick={() => setFilterStatus(isActive ? null : status)}
                className={cn(
                  'flex items-center gap-1 rounded-md px-2 py-1 text-xs transition-colors',
                  isActive
                    ? `${config.bgColor} ${config.color} border`
                    : 'bg-muted text-muted-foreground hover:bg-muted/80'
                )}
              >
                <StatusIcon className="h-3 w-3" />
                {count}
              </button>
            );
          })}
        </div>
      </div>

      {/* Tickets List */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex h-full items-center justify-center">
            <div className="text-sm text-muted-foreground">Loading tickets...</div>
          </div>
        ) : error ? (
          <div className="flex h-full items-center justify-center p-4">
            <div className="text-sm text-red-600">{error}</div>
          </div>
        ) : filteredTickets.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center p-4 text-center">
            <Zap className="h-12 w-12 text-muted-foreground/50 mb-4" />
            <div className="text-sm font-medium">No work tickets</div>
            <div className="text-xs text-muted-foreground mt-1">
              {searchQuery ? 'Try adjusting your search' : 'Tickets appear when you trigger recipes'}
            </div>
          </div>
        ) : (
          <div className="divide-y divide-border">
            {/* Running (priority) */}
            {groupedTickets.running.length > 0 && (
              <TicketGroup
                title="Running"
                status="running"
                tickets={groupedTickets.running}
                onTicketClick={handleTicketClick}
              />
            )}

            {/* Queued */}
            {groupedTickets.queued.length > 0 && (
              <TicketGroup
                title="Queued"
                status="queued"
                tickets={groupedTickets.queued}
                onTicketClick={handleTicketClick}
              />
            )}

            {/* Completed */}
            {groupedTickets.completed.length > 0 && (
              <TicketGroup
                title="Completed"
                status="completed"
                tickets={groupedTickets.completed}
                onTicketClick={handleTicketClick}
                collapsed
              />
            )}

            {/* Failed */}
            {groupedTickets.failed.length > 0 && (
              <TicketGroup
                title="Failed"
                status="failed"
                tickets={groupedTickets.failed}
                onTicketClick={handleTicketClick}
              />
            )}

            {/* Cancelled */}
            {groupedTickets.cancelled.length > 0 && (
              <TicketGroup
                title="Cancelled"
                status="cancelled"
                tickets={groupedTickets.cancelled}
                onTicketClick={handleTicketClick}
                collapsed
              />
            )}
          </div>
        )}
      </div>

      {/* Footer stats */}
      <div className="border-t border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
        {filteredTickets.length} of {tickets.length} tickets
      </div>
    </div>
  );
}

// ============================================================================
// Ticket Group
// ============================================================================

interface TicketGroupProps {
  title: string;
  status: string;
  tickets: WorkTicket[];
  onTicketClick: (ticket: WorkTicket) => void;
  collapsed?: boolean;
}

function TicketGroup({ title, status, tickets, onTicketClick, collapsed }: TicketGroupProps) {
  const [isExpanded, setIsExpanded] = useState(!collapsed);
  const config = STATUS_CONFIG[status] || STATUS_CONFIG.queued;

  return (
    <div>
      {/* Group header */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className={cn(
          'flex w-full items-center justify-between px-3 py-2 text-xs font-medium',
          config.bgColor, config.color
        )}
      >
        <div className="flex items-center gap-2">
          <config.Icon className={cn('h-4 w-4', status === 'running' && 'animate-spin')} />
          <span>{title} ({tickets.length})</span>
        </div>
        <ChevronRight
          className={cn(
            'h-4 w-4 transition-transform',
            isExpanded && 'rotate-90'
          )}
        />
      </button>

      {/* Tickets */}
      {isExpanded && (
        <div className="divide-y divide-border/50">
          {tickets.map((ticket) => (
            <TicketRow
              key={ticket.id}
              ticket={ticket}
              onClick={() => onTicketClick(ticket)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ============================================================================
// Ticket Row
// ============================================================================

interface TicketRowProps {
  ticket: WorkTicket;
  onClick: () => void;
}

function TicketRow({ ticket, onClick }: TicketRowProps) {
  const statusConfig = STATUS_CONFIG[ticket.status] || STATUS_CONFIG.queued;
  const isRunning = ticket.status === 'running';

  return (
    <button
      onClick={onClick}
      className="flex w-full items-start gap-3 p-3 text-left hover:bg-muted/50 transition-colors"
    >
      {/* Icon */}
      <div className={cn('rounded-md p-1.5 shrink-0', statusConfig.bgColor)}>
        <statusConfig.Icon className={cn('h-4 w-4', statusConfig.color, isRunning && 'animate-spin')} />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium truncate">
            {ticket.recipe_name || ticket.recipe_slug || 'Work Ticket'}
          </span>
          {ticket.agent_type && (
            <Badge variant="outline" className="text-xs shrink-0">
              {AGENT_LABELS[ticket.agent_type] || ticket.agent_type}
            </Badge>
          )}
        </div>

        {ticket.description && (
          <div className="mt-1 text-xs text-muted-foreground line-clamp-1">
            {ticket.description}
          </div>
        )}

        {/* Progress */}
        {isRunning && (
          <div className="mt-2">
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-muted-foreground">
                {ticket.current_step || 'Processing...'}
              </span>
              {ticket.progress_pct !== undefined && (
                <span className="font-medium">{Math.round(ticket.progress_pct)}%</span>
              )}
            </div>
            <div className="h-1.5 rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-amber-500 transition-all"
                style={{ width: `${ticket.progress_pct || 0}%` }}
              />
            </div>
          </div>
        )}

        <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
          <span>{new Date(ticket.created_at).toLocaleString()}</span>
          {ticket.outputs_count !== undefined && ticket.outputs_count > 0 && (
            <>
              <span>·</span>
              <span>{ticket.outputs_count} output{ticket.outputs_count > 1 ? 's' : ''}</span>
            </>
          )}
        </div>
      </div>

      <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
    </button>
  );
}

// ============================================================================
// Ticket Detail View
// ============================================================================

interface TicketDetailProps {
  ticket: WorkTicket;
  onBack: () => void;
  onCancel?: (ticketId: string) => void;
  onRetry?: (ticketId: string) => void;
  className?: string;
}

function TicketDetail({
  ticket,
  onBack,
  onCancel,
  onRetry,
  className,
}: TicketDetailProps) {
  const statusConfig = STATUS_CONFIG[ticket.status] || STATUS_CONFIG.queued;
  const isRunning = ticket.status === 'running';
  const isFailed = ticket.status === 'failed';
  const canCancel = ticket.status === 'queued' || ticket.status === 'running';

  return (
    <div className={cn('flex h-full flex-col', className)}>
      {/* Header */}
      <div className="border-b border-border p-4">
        <Button
          variant="ghost"
          size="sm"
          onClick={onBack}
          className="mb-3 -ml-2"
        >
          <ChevronRight className="h-4 w-4 rotate-180 mr-1" />
          Back to list
        </Button>

        <div className="flex items-start gap-3">
          <div className={cn('rounded-lg p-2', statusConfig.bgColor)}>
            <statusConfig.Icon className={cn('h-6 w-6', statusConfig.color, isRunning && 'animate-spin')} />
          </div>
          <div className="flex-1">
            <h2 className="text-lg font-semibold">
              {ticket.recipe_name || ticket.recipe_slug || 'Work Ticket'}
            </h2>
            <div className="flex items-center gap-2 mt-1">
              <Badge className={cn(statusConfig.bgColor, statusConfig.color)}>
                {statusConfig.label}
              </Badge>
              {ticket.agent_type && (
                <span className="text-sm text-muted-foreground">
                  {AGENT_LABELS[ticket.agent_type] || ticket.agent_type}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Progress (for running tickets) */}
        {isRunning && (
          <div className="mt-4">
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-muted-foreground">
                {ticket.current_step || 'Processing...'}
              </span>
              {ticket.progress_pct !== undefined && (
                <span className="font-medium">{Math.round(ticket.progress_pct)}%</span>
              )}
            </div>
            <div className="h-2 rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-amber-500 transition-all"
                style={{ width: `${ticket.progress_pct || 0}%` }}
              />
            </div>
          </div>
        )}

        {/* Error message */}
        {isFailed && ticket.error_message && (
          <div className="mt-4 p-3 rounded-md bg-red-50 border border-red-200">
            <div className="flex items-start gap-2">
              <AlertCircle className="h-4 w-4 text-red-600 mt-0.5 shrink-0" />
              <div className="text-sm text-red-700">{ticket.error_message}</div>
            </div>
          </div>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {ticket.description && (
          <div className="mb-6">
            <h3 className="text-sm font-medium mb-2">Description</h3>
            <p className="text-sm text-muted-foreground">{ticket.description}</p>
          </div>
        )}

        {/* Timeline */}
        <div>
          <h3 className="text-sm font-medium mb-3">Timeline</h3>
          <div className="space-y-3">
            <TimelineEvent
              label="Created"
              timestamp={ticket.created_at}
              icon={FileText}
            />
            {ticket.started_at && (
              <TimelineEvent
                label="Started"
                timestamp={ticket.started_at}
                icon={Play}
              />
            )}
            {ticket.completed_at && (
              <TimelineEvent
                label={ticket.status === 'completed' ? 'Completed' : 'Ended'}
                timestamp={ticket.completed_at}
                icon={ticket.status === 'completed' ? CheckCircle2 : XCircle}
              />
            )}
          </div>
        </div>

        {/* Outputs count */}
        {ticket.outputs_count !== undefined && ticket.outputs_count > 0 && (
          <div className="mt-6 pt-6 border-t border-border">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium">Outputs Generated</h3>
              <Badge variant="outline">{ticket.outputs_count}</Badge>
            </div>
          </div>
        )}
      </div>

      {/* Actions */}
      {(canCancel || isFailed) && (
        <div className="border-t border-border bg-card p-4">
          <div className="flex items-center gap-2">
            {canCancel && onCancel && (
              <Button
                size="sm"
                variant="destructive"
                onClick={() => onCancel(ticket.id)}
              >
                <XCircle className="h-4 w-4 mr-2" />
                Cancel Ticket
              </Button>
            )}
            {isFailed && onRetry && (
              <Button
                size="sm"
                variant="outline"
                onClick={() => onRetry(ticket.id)}
              >
                <RefreshCw className="h-4 w-4 mr-2" />
                Retry
              </Button>
            )}
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="border-t border-border bg-muted/30 px-4 py-3">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <span>Updated: {new Date(ticket.updated_at).toLocaleString()}</span>
          <span className="font-mono text-[10px]">{ticket.id.slice(0, 8)}...</span>
        </div>
      </div>
    </div>
  );
}

// Timeline event component
interface TimelineEventProps {
  label: string;
  timestamp: string;
  icon: React.ElementType;
}

function TimelineEvent({ label, timestamp, icon: Icon }: TimelineEventProps) {
  return (
    <div className="flex items-center gap-3">
      <div className="rounded-full bg-muted p-1.5">
        <Icon className="h-3 w-3 text-muted-foreground" />
      </div>
      <div className="flex-1">
        <span className="text-sm font-medium">{label}</span>
      </div>
      <span className="text-xs text-muted-foreground">
        {new Date(timestamp).toLocaleString()}
      </span>
    </div>
  );
}

export default TicketsDetailPanel;
