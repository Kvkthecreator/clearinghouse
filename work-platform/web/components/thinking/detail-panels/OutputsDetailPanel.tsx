'use client';

/**
 * OutputsDetailPanel
 *
 * Displays work outputs in the detail panel.
 * Shows list view with status filtering, and detail view for specific outputs.
 *
 * Part of Chat-First Architecture v1.0
 * See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
 */

import { useState, useEffect, useMemo } from 'react';
import { cn } from '@/lib/utils';
import {
  Search,
  ChevronRight,
  FileText,
  Lightbulb,
  TrendingUp,
  FileEdit,
  AlertCircle,
  Clock,
  CheckCircle2,
  XCircle,
  RotateCcw,
  ThumbsUp,
  ThumbsDown,
  MessageSquare,
  ExternalLink,
  Download,
  Image,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';

// Work output types (should match API types)
interface WorkOutput {
  id: string;
  output_type: string;
  title?: string;
  body: string;
  confidence?: number;
  supervision_status: 'pending_review' | 'approved' | 'rejected' | 'revision_requested';
  agent_type?: string;
  ticket_id?: string;
  metadata?: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

interface OutputsDetailPanelProps {
  basketId: string;
  outputs?: WorkOutput[];
  loading?: boolean;
  error?: string;
  focusedOutputId?: string;
  onOutputClick?: (output: WorkOutput) => void;
  onApprove?: (outputId: string) => void;
  onReject?: (outputId: string) => void;
  onRequestRevision?: (outputId: string, feedback: string) => void;
  className?: string;
}

// Output type icons
const OUTPUT_TYPE_ICONS: Record<string, React.ElementType> = {
  finding: Lightbulb,
  recommendation: TrendingUp,
  insight: Lightbulb,
  content_draft: FileEdit,
  content_variant: FileEdit,
  content_asset: Image,
  document: FileText,
  error: AlertCircle,
  default: FileText,
};

// Status configuration
const STATUS_CONFIG: Record<string, { label: string; color: string; bgColor: string; Icon: React.ElementType }> = {
  pending_review: {
    label: 'Pending Review',
    color: 'text-amber-600',
    bgColor: 'bg-amber-50 border-amber-200',
    Icon: Clock,
  },
  approved: {
    label: 'Approved',
    color: 'text-green-600',
    bgColor: 'bg-green-50 border-green-200',
    Icon: CheckCircle2,
  },
  rejected: {
    label: 'Rejected',
    color: 'text-red-600',
    bgColor: 'bg-red-50 border-red-200',
    Icon: XCircle,
  },
  revision_requested: {
    label: 'Revision Requested',
    color: 'text-orange-600',
    bgColor: 'bg-orange-50 border-orange-200',
    Icon: RotateCcw,
  },
};

// Agent type labels
const AGENT_LABELS: Record<string, string> = {
  research: 'Research Agent',
  content: 'Content Agent',
  reporting: 'Reporting Agent',
  thinking_partner: 'Thinking Partner',
};

export function OutputsDetailPanel({
  basketId,
  outputs = [],
  loading,
  error,
  focusedOutputId,
  onOutputClick,
  onApprove,
  onReject,
  onRequestRevision,
  className,
}: OutputsDetailPanelProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<string | null>(null);
  const [filterType, setFilterType] = useState<string | null>(null);
  const [selectedOutput, setSelectedOutput] = useState<WorkOutput | null>(null);

  // Focus on specific output when provided
  useEffect(() => {
    if (focusedOutputId) {
      const output = outputs.find((o) => o.id === focusedOutputId);
      if (output) {
        setSelectedOutput(output);
      }
    }
  }, [focusedOutputId, outputs]);

  // Get unique output types for filter
  const outputTypes = useMemo(() => {
    const types = new Set(outputs.map((o) => o.output_type));
    return Array.from(types);
  }, [outputs]);

  // Filter outputs
  const filteredOutputs = useMemo(() => {
    return outputs.filter((output) => {
      // Search filter
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        const title = (output.title || '').toLowerCase();
        const body = output.body.toLowerCase();
        const type = output.output_type.toLowerCase();
        if (!title.includes(query) && !body.includes(query) && !type.includes(query)) {
          return false;
        }
      }

      // Status filter
      if (filterStatus && output.supervision_status !== filterStatus) {
        return false;
      }

      // Type filter
      if (filterType && output.output_type !== filterType) {
        return false;
      }

      return true;
    });
  }, [outputs, searchQuery, filterStatus, filterType]);

  // Group outputs by status
  const groupedOutputs = useMemo(() => {
    const groups: Record<string, WorkOutput[]> = {
      pending_review: [],
      revision_requested: [],
      approved: [],
      rejected: [],
    };

    filteredOutputs.forEach((output) => {
      const status = output.supervision_status || 'pending_review';
      if (!groups[status]) {
        groups[status] = [];
      }
      groups[status].push(output);
    });

    return groups;
  }, [filteredOutputs]);

  const handleOutputClick = (output: WorkOutput) => {
    setSelectedOutput(output);
    onOutputClick?.(output);
  };

  // If viewing specific output
  if (selectedOutput) {
    return (
      <OutputDetail
        output={selectedOutput}
        onBack={() => setSelectedOutput(null)}
        onApprove={onApprove}
        onReject={onReject}
        onRequestRevision={onRequestRevision}
        className={className}
      />
    );
  }

  // Count pending
  const pendingCount = groupedOutputs.pending_review.length + groupedOutputs.revision_requested.length;

  return (
    <div className={cn('flex h-full flex-col', className)}>
      {/* Header with counts */}
      <div className="border-b border-border p-3 space-y-2">
        {/* Pending indicator */}
        {pendingCount > 0 && (
          <div className="flex items-center gap-2 p-2 rounded-md bg-amber-50 border border-amber-200">
            <Clock className="h-4 w-4 text-amber-600" />
            <span className="text-sm text-amber-700 font-medium">
              {pendingCount} output{pendingCount > 1 ? 's' : ''} need{pendingCount === 1 ? 's' : ''} review
            </span>
          </div>
        )}

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search outputs..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-md border border-input bg-background py-2 pl-10 pr-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>

        {/* Filters */}
        <div className="flex items-center gap-2 flex-wrap">
          {/* Status filter */}
          <div className="flex items-center gap-1">
            {Object.entries(STATUS_CONFIG).map(([status, config]) => {
              const StatusIcon = config.Icon;
              const isActive = filterStatus === status;
              const count = groupedOutputs[status]?.length || 0;
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

          {/* Type filter */}
          {outputTypes.length > 1 && (
            <select
              value={filterType || ''}
              onChange={(e) => setFilterType(e.target.value || null)}
              className="rounded-md border border-input bg-background px-2 py-1 text-xs"
            >
              <option value="">All Types</option>
              {outputTypes.map((type) => (
                <option key={type} value={type}>
                  {type.replace('_', ' ')}
                </option>
              ))}
            </select>
          )}
        </div>
      </div>

      {/* Outputs List */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex h-full items-center justify-center">
            <div className="text-sm text-muted-foreground">Loading outputs...</div>
          </div>
        ) : error ? (
          <div className="flex h-full items-center justify-center p-4">
            <div className="text-sm text-red-600">{error}</div>
          </div>
        ) : filteredOutputs.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center p-4 text-center">
            <Lightbulb className="h-12 w-12 text-muted-foreground/50 mb-4" />
            <div className="text-sm font-medium">No work outputs</div>
            <div className="text-xs text-muted-foreground mt-1">
              {searchQuery ? 'Try adjusting your search' : 'Outputs will appear when agents complete work'}
            </div>
          </div>
        ) : (
          <div className="divide-y divide-border">
            {/* Pending review (priority) */}
            {groupedOutputs.pending_review.length > 0 && (
              <OutputGroup
                title="Pending Review"
                status="pending_review"
                outputs={groupedOutputs.pending_review}
                onOutputClick={handleOutputClick}
              />
            )}

            {/* Revision requested */}
            {groupedOutputs.revision_requested.length > 0 && (
              <OutputGroup
                title="Revision Requested"
                status="revision_requested"
                outputs={groupedOutputs.revision_requested}
                onOutputClick={handleOutputClick}
              />
            )}

            {/* Approved */}
            {groupedOutputs.approved.length > 0 && (
              <OutputGroup
                title="Approved"
                status="approved"
                outputs={groupedOutputs.approved}
                onOutputClick={handleOutputClick}
                collapsed
              />
            )}

            {/* Rejected */}
            {groupedOutputs.rejected.length > 0 && (
              <OutputGroup
                title="Rejected"
                status="rejected"
                outputs={groupedOutputs.rejected}
                onOutputClick={handleOutputClick}
                collapsed
              />
            )}
          </div>
        )}
      </div>

      {/* Footer stats */}
      <div className="border-t border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
        {filteredOutputs.length} of {outputs.length} outputs
      </div>
    </div>
  );
}

// ============================================================================
// Output Group
// ============================================================================

interface OutputGroupProps {
  title: string;
  status: string;
  outputs: WorkOutput[];
  onOutputClick: (output: WorkOutput) => void;
  collapsed?: boolean;
}

function OutputGroup({ title, status, outputs, onOutputClick, collapsed }: OutputGroupProps) {
  const [isExpanded, setIsExpanded] = useState(!collapsed);
  const config = STATUS_CONFIG[status] || STATUS_CONFIG.pending_review;

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
          <config.Icon className="h-4 w-4" />
          <span>{title} ({outputs.length})</span>
        </div>
        <ChevronRight
          className={cn(
            'h-4 w-4 transition-transform',
            isExpanded && 'rotate-90'
          )}
        />
      </button>

      {/* Outputs */}
      {isExpanded && (
        <div className="divide-y divide-border/50">
          {outputs.map((output) => (
            <OutputRow
              key={output.id}
              output={output}
              onClick={() => onOutputClick(output)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ============================================================================
// Output Row
// ============================================================================

interface OutputRowProps {
  output: WorkOutput;
  onClick: () => void;
}

function OutputRow({ output, onClick }: OutputRowProps) {
  const Icon = OUTPUT_TYPE_ICONS[output.output_type] || OUTPUT_TYPE_ICONS.default;
  const statusConfig = STATUS_CONFIG[output.supervision_status] || STATUS_CONFIG.pending_review;

  return (
    <button
      onClick={onClick}
      className="flex w-full items-start gap-3 p-3 text-left hover:bg-muted/50 transition-colors"
    >
      {/* Icon */}
      <div className="rounded-md bg-primary/10 p-1.5 shrink-0">
        <Icon className="h-4 w-4 text-primary" />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium truncate">
            {output.title || 'Untitled Output'}
          </span>
          <Badge variant="outline" className="text-xs capitalize shrink-0">
            {output.output_type.replace('_', ' ')}
          </Badge>
        </div>

        <div className="mt-1 text-xs text-muted-foreground line-clamp-2">
          {output.body.slice(0, 150)}...
        </div>

        <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
          <div className={cn('flex items-center gap-1', statusConfig.color)}>
            <statusConfig.Icon className="h-3 w-3" />
            <span>{statusConfig.label}</span>
          </div>
          {output.confidence !== undefined && (
            <>
              <span>·</span>
              <span>{Math.round(output.confidence * 100)}% confidence</span>
            </>
          )}
          {output.agent_type && (
            <>
              <span>·</span>
              <span>{AGENT_LABELS[output.agent_type] || output.agent_type}</span>
            </>
          )}
        </div>
      </div>

      <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
    </button>
  );
}

// ============================================================================
// Output Detail View
// ============================================================================

interface OutputDetailProps {
  output: WorkOutput;
  onBack: () => void;
  onApprove?: (outputId: string) => void;
  onReject?: (outputId: string) => void;
  onRequestRevision?: (outputId: string, feedback: string) => void;
  className?: string;
}

function OutputDetail({
  output,
  onBack,
  onApprove,
  onReject,
  onRequestRevision,
  className,
}: OutputDetailProps) {
  const [revisionFeedback, setRevisionFeedback] = useState('');
  const [showRevisionInput, setShowRevisionInput] = useState(false);

  const Icon = OUTPUT_TYPE_ICONS[output.output_type] || OUTPUT_TYPE_ICONS.default;
  const statusConfig = STATUS_CONFIG[output.supervision_status] || STATUS_CONFIG.pending_review;
  const isPending = output.supervision_status === 'pending_review' || output.supervision_status === 'revision_requested';

  const handleRequestRevision = () => {
    if (revisionFeedback.trim() && onRequestRevision) {
      onRequestRevision(output.id, revisionFeedback);
      setShowRevisionInput(false);
      setRevisionFeedback('');
    }
  };

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
          <div className="rounded-lg bg-primary/10 p-2">
            <Icon className="h-6 w-6 text-primary" />
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold">
                {output.title || 'Untitled Output'}
              </h2>
              <Badge variant="outline" className="capitalize">
                {output.output_type.replace('_', ' ')}
              </Badge>
            </div>
            <div className="flex items-center gap-2 mt-1">
              <div className={cn('flex items-center gap-1 text-sm', statusConfig.color)}>
                <statusConfig.Icon className="h-4 w-4" />
                <span>{statusConfig.label}</span>
              </div>
              {output.agent_type && (
                <>
                  <span className="text-muted-foreground">·</span>
                  <span className="text-sm text-muted-foreground">
                    {AGENT_LABELS[output.agent_type] || output.agent_type}
                  </span>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Confidence */}
        {output.confidence !== undefined && (
          <div className="mt-4">
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-muted-foreground">Confidence</span>
              <span className="font-medium">{Math.round(output.confidence * 100)}%</span>
            </div>
            <div className="h-2 rounded-full bg-muted">
              <div
                className={cn(
                  'h-full rounded-full',
                  output.confidence >= 0.8 ? 'bg-green-500' :
                  output.confidence >= 0.5 ? 'bg-amber-500' : 'bg-red-500'
                )}
                style={{ width: `${output.confidence * 100}%` }}
              />
            </div>
          </div>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        <div className="prose prose-sm max-w-none">
          <div className="whitespace-pre-wrap">{output.body}</div>
        </div>

        {/* Metadata */}
        {output.metadata && Object.keys(output.metadata).length > 0 && (
          <div className="mt-6 pt-6 border-t border-border">
            <h3 className="text-sm font-medium mb-3">Metadata</h3>
            <pre className="rounded-md bg-muted p-3 text-xs overflow-x-auto">
              {JSON.stringify(output.metadata, null, 2)}
            </pre>
          </div>
        )}
      </div>

      {/* Actions (for pending outputs) */}
      {isPending && (
        <div className="border-t border-border bg-card p-4">
          {showRevisionInput ? (
            <div className="space-y-3">
              <textarea
                value={revisionFeedback}
                onChange={(e) => setRevisionFeedback(e.target.value)}
                placeholder="Describe what needs to be revised..."
                className="w-full rounded-md border border-input bg-background p-3 text-sm resize-none h-24"
              />
              <div className="flex items-center gap-2">
                <Button
                  size="sm"
                  onClick={handleRequestRevision}
                  disabled={!revisionFeedback.trim()}
                >
                  <RotateCcw className="h-4 w-4 mr-2" />
                  Request Revision
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowRevisionInput(false)}
                >
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2">
              <Button
                size="sm"
                variant="default"
                className="bg-green-600 hover:bg-green-700"
                onClick={() => onApprove?.(output.id)}
              >
                <ThumbsUp className="h-4 w-4 mr-2" />
                Approve
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setShowRevisionInput(true)}
              >
                <MessageSquare className="h-4 w-4 mr-2" />
                Request Revision
              </Button>
              <Button
                size="sm"
                variant="destructive"
                onClick={() => onReject?.(output.id)}
              >
                <ThumbsDown className="h-4 w-4 mr-2" />
                Reject
              </Button>
            </div>
          )}
        </div>
      )}

      {/* Footer */}
      <div className="border-t border-border bg-muted/30 px-4 py-3">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <div className="flex items-center gap-4">
            <span>Created: {new Date(output.created_at).toLocaleString()}</span>
            {output.ticket_id && (
              <span>Ticket: {output.ticket_id.slice(0, 8)}...</span>
            )}
          </div>
          <span className="font-mono text-[10px]">{output.id.slice(0, 8)}...</span>
        </div>
      </div>
    </div>
  );
}

export default OutputsDetailPanel;
