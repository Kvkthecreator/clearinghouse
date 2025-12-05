"use client";

/**
 * ContextEntriesPanel - Display context entries with inline content visibility
 *
 * Refactored for TP sidebar integration:
 * - Inline content display (not just previews)
 * - Expandable/collapsible cards
 * - "Last updated by" badges (user vs agent)
 * - Realtime updates via Supabase
 * - Edit button opens modal (viewing is inline)
 *
 * See: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md
 */

import { useState, useEffect, useMemo } from 'react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Badge } from '@/components/ui/Badge';
import {
  Plus,
  Pencil,
  ChevronDown,
  ChevronRight,
  CheckCircle,
  AlertCircle,
  AlertTriangle,
  Users,
  Eye,
  Palette,
  Target,
  TrendingUp,
  BarChart3,
  Loader2,
  RefreshCw,
  User,
  Bot,
  Sparkles,
  ExternalLink,
  Lightbulb,
} from 'lucide-react';
import Link from 'next/link';
import {
  useContextSchemas,
  useContextEntries,
  type ContextEntrySchema,
  type ContextEntry,
} from '@/hooks/useContextEntries';
import { useContextItemsRealtime } from '@/hooks/useTPRealtime';
import ContextEntryEditor from './ContextEntryEditor';

// Icon mapping for anchor roles
const ROLE_ICONS: Record<string, React.ElementType> = {
  problem: AlertTriangle,
  customer: Users,
  vision: Eye,
  brand: Palette,
  competitor: Target,
  trend_digest: TrendingUp,
  market_intel: Lightbulb,
  competitor_snapshot: BarChart3,
};

// Tier display config
const TIER_CONFIG: Record<string, { label: string; color: string; bgColor: string }> = {
  foundation: { label: 'Foundation', color: 'text-blue-700', bgColor: 'bg-blue-500/10 border-blue-500/30' },
  working: { label: 'Working', color: 'text-purple-700', bgColor: 'bg-purple-500/10 border-purple-500/30' },
  ephemeral: { label: 'Ephemeral', color: 'text-gray-600', bgColor: 'bg-gray-500/10 border-gray-500/30' },
};

// Item type display labels
const ITEM_TYPE_LABELS: Record<string, string> = {
  trend_digest: 'Trend Digest',
  market_intel: 'Market Intelligence',
  competitor_snapshot: 'Competitor Snapshot',
  problem: 'Problem',
  customer: 'Customer',
  vision: 'Vision',
  brand: 'Brand',
  competitor: 'Competitor',
};

// Category display config
const CATEGORY_CONFIG = {
  foundation: {
    title: 'Foundation',
    description: 'Core context that defines your project',
    color: 'bg-blue-500',
  },
  market: {
    title: 'Market Intelligence',
    description: 'Competitive landscape and market data',
    color: 'bg-purple-500',
  },
  insight: {
    title: 'Agent Insights',
    description: 'AI-generated analysis and recommendations',
    color: 'bg-green-500',
  },
};

interface ContextEntriesPanelProps {
  projectId: string;
  basketId: string;
  initialAnchorRole?: string;
}

export default function ContextEntriesPanel({
  projectId,
  basketId,
  initialAnchorRole,
}: ContextEntriesPanelProps) {
  // Fetch schemas and entries
  const {
    schemas,
    schemasByCategory,
    loading: schemasLoading,
    error: schemasError,
    refetch: refetchSchemas,
  } = useContextSchemas(basketId);

  const {
    entries,
    loading: entriesLoading,
    error: entriesError,
    refetch: refetchEntries,
    getEntryByRole,
  } = useContextEntries(basketId);

  // Realtime updates
  useContextItemsRealtime(basketId, () => {
    refetchEntries();
  });

  // Expanded state for cards
  const [expandedCards, setExpandedCards] = useState<Set<string>>(new Set());

  // Editor modal state
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingSchema, setEditingSchema] = useState<ContextEntrySchema | null>(null);
  const [editingEntry, setEditingEntry] = useState<ContextEntry | null>(null);
  const [editingEntryKey, setEditingEntryKey] = useState<string | undefined>();
  const [initialRoleHandled, setInitialRoleHandled] = useState(false);

  // Toggle card expansion
  const toggleExpanded = (roleKey: string) => {
    setExpandedCards((prev) => {
      const next = new Set(prev);
      if (next.has(roleKey)) {
        next.delete(roleKey);
      } else {
        next.add(roleKey);
      }
      return next;
    });
  };

  // Open editor for a schema
  const openEditor = (schema: ContextEntrySchema, entry?: ContextEntry, entryKey?: string) => {
    setEditingSchema(schema);
    setEditingEntry(entry || null);
    setEditingEntryKey(entryKey);
    setEditorOpen(true);
  };

  // Auto-open editor for initialAnchorRole when data is loaded
  useEffect(() => {
    if (initialAnchorRole && !initialRoleHandled && schemas.length > 0 && !schemasLoading) {
      const schema = schemas.find((s) => s.anchor_role === initialAnchorRole);
      if (schema) {
        const entry = getEntryByRole(initialAnchorRole);
        openEditor(schema, entry || undefined);
        setInitialRoleHandled(true);
      }
    }
  }, [initialAnchorRole, schemas, schemasLoading, initialRoleHandled, getEntryByRole]);

  // Close editor
  const closeEditor = () => {
    setEditorOpen(false);
    setEditingSchema(null);
    setEditingEntry(null);
    setEditingEntryKey(undefined);
  };

  // Handle successful save
  const handleEditorSuccess = () => {
    refetchEntries();
    closeEditor();
  };

  // Calculate overall completeness
  const overallCompleteness = useMemo(() => {
    const foundationSchemas = schemasByCategory.foundation;
    if (foundationSchemas.length === 0) return 0;

    let filled = 0;
    foundationSchemas.forEach((schema) => {
      const entry = getEntryByRole(schema.anchor_role);
      if (entry && Object.keys(entry.data).length > 0) {
        filled++;
      }
    });

    return filled / foundationSchemas.length;
  }, [schemasByCategory.foundation, getEntryByRole]);

  // Filter agent-generated working-tier insights (trend_digest, market_intel, competitor_snapshot)
  const agentInsights = useMemo(() => {
    return entries.filter(
      (entry) =>
        entry.tier === 'working' &&
        entry.source_type === 'agent' &&
        ['trend_digest', 'market_intel', 'competitor_snapshot'].includes(entry.anchor_role)
    );
  }, [entries]);

  const loading = schemasLoading || entriesLoading;
  const error = schemasError || entriesError;

  if (loading && schemas.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center">
        <AlertCircle className="h-8 w-8 text-destructive mb-2" />
        <p className="text-sm text-muted-foreground">{error}</p>
        <Button
          variant="outline"
          size="sm"
          className="mt-4"
          onClick={() => {
            refetchSchemas();
            refetchEntries();
          }}
        >
          <RefreshCw className="h-4 w-4 mr-2" />
          Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Overall completeness */}
      <div className="flex items-center gap-4 p-4 bg-muted/50 rounded-lg">
        <div className="flex-1">
          <div className="flex items-center justify-between text-sm mb-2">
            <span className="font-medium">Foundation Completeness</span>
            <span className="text-muted-foreground">
              {Math.round(overallCompleteness * 100)}%
            </span>
          </div>
          <div className="h-2 bg-muted rounded-full overflow-hidden">
            <div
              className={`h-full transition-all ${
                overallCompleteness === 1
                  ? 'bg-green-500'
                  : overallCompleteness >= 0.5
                  ? 'bg-yellow-500'
                  : 'bg-red-500'
              }`}
              style={{ width: `${overallCompleteness * 100}%` }}
            />
          </div>
        </div>
        {overallCompleteness === 1 ? (
          <CheckCircle className="h-6 w-6 text-green-500" />
        ) : (
          <AlertCircle className="h-6 w-6 text-muted-foreground" />
        )}
      </div>

      {/* Render each category */}
      {(Object.keys(CATEGORY_CONFIG) as Array<keyof typeof CATEGORY_CONFIG>).map((category) => {
        const config = CATEGORY_CONFIG[category];
        const categorySchemas = schemasByCategory[category];

        if (categorySchemas.length === 0) return null;

        return (
          <div key={category} className="space-y-4">
            {/* Category header */}
            <div className="flex items-center gap-3">
              <div className={`w-1 h-6 rounded-full ${config.color}`} />
              <div>
                <h3 className="font-semibold">{config.title}</h3>
                <p className="text-sm text-muted-foreground">{config.description}</p>
              </div>
            </div>

            {/* Schema cards */}
            <div className="grid gap-3">
              {categorySchemas.map((schema) => {
                const entry = getEntryByRole(schema.anchor_role);
                const Icon = ROLE_ICONS[schema.anchor_role] || AlertCircle;
                const hasContent = entry && Object.keys(entry.data).length > 0;
                const isAgentProduced = schema.field_schema.agent_produced;
                const isExpanded = expandedCards.has(schema.anchor_role);

                return (
                  <Card
                    key={schema.anchor_role}
                    className={`overflow-hidden transition-all ${
                      hasContent ? '' : 'border-dashed'
                    }`}
                  >
                    {/* Card header - always visible */}
                    <div
                      className="p-4 cursor-pointer hover:bg-muted/50 transition-colors"
                      onClick={() => hasContent && toggleExpanded(schema.anchor_role)}
                    >
                      <div className="flex items-center gap-4">
                        {/* Icon */}
                        <div
                          className={`p-2 rounded-lg ${
                            hasContent ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'
                          }`}
                        >
                          <Icon className="h-5 w-5" />
                        </div>

                        {/* Title and meta */}
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className="font-medium">{schema.display_name}</span>
                            {isAgentProduced && (
                              <Badge variant="secondary" className="text-xs">
                                Agent
                              </Badge>
                            )}
                            {/* Last updated by badge */}
                            {entry && (
                              <LastUpdatedBadge entry={entry} />
                            )}
                          </div>
                          {!hasContent && (
                            <p className="text-sm text-muted-foreground truncate">
                              {schema.description}
                            </p>
                          )}
                        </div>

                        {/* Actions */}
                        <div className="flex items-center gap-2">
                          {hasContent ? (
                            <>
                              {/* View Details Link */}
                              <Link
                                href={`/projects/${projectId}/context/${entry.id}`}
                                className="h-8 w-8 p-0 inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors hover:bg-accent hover:text-accent-foreground"
                                onClick={(e) => e.stopPropagation()}
                              >
                                <ExternalLink className="h-4 w-4" />
                              </Link>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="h-8 w-8 p-0"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  openEditor(schema, entry);
                                }}
                              >
                                <Pencil className="h-4 w-4" />
                              </Button>
                              {isExpanded ? (
                                <ChevronDown className="h-4 w-4 text-muted-foreground" />
                              ) : (
                                <ChevronRight className="h-4 w-4 text-muted-foreground" />
                              )}
                            </>
                          ) : (
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={(e) => {
                                e.stopPropagation();
                                openEditor(schema);
                              }}
                            >
                              <Plus className="h-4 w-4 mr-1" />
                              Add
                            </Button>
                          )}
                        </div>
                      </div>
                    </div>

                    {/* Expanded content */}
                    {hasContent && isExpanded && (
                      <div className="px-4 pb-4 border-t border-border pt-4">
                        <ContextContentDisplay
                          entry={entry}
                          schema={schema}
                        />
                      </div>
                    )}
                  </Card>
                );
              })}

              {/* Add competitor button for market category */}
              {category === 'market' && (
                <Button
                  variant="outline"
                  className="border-dashed justify-start gap-2"
                  onClick={() => {
                    const competitorSchema = categorySchemas.find(
                      (s) => s.anchor_role === 'competitor'
                    );
                    if (competitorSchema) {
                      openEditor(competitorSchema, undefined, `competitor-${Date.now()}`);
                    }
                  }}
                >
                  <Plus className="h-4 w-4" />
                  Add Competitor
                </Button>
              )}
            </div>
          </div>
        );
      })}

      {/* Agent Insights Section - Working tier, agent-generated items */}
      {agentInsights.length > 0 && (
        <div className="space-y-4">
          {/* Section header */}
          <div className="flex items-center gap-3">
            <div className="w-1 h-6 rounded-full bg-purple-500" />
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <h3 className="font-semibold">Agent Insights</h3>
                <Badge variant="secondary" className="text-xs">
                  {agentInsights.length}
                </Badge>
              </div>
              <p className="text-sm text-muted-foreground">
                AI-generated analysis from scheduled research
              </p>
            </div>
          </div>

          {/* Agent insight cards */}
          <div className="grid gap-3">
            {agentInsights.map((entry) => (
              <AgentInsightCard
                key={entry.id}
                entry={entry}
                projectId={projectId}
                isExpanded={expandedCards.has(entry.id)}
                onToggle={() => toggleExpanded(entry.id)}
              />
            ))}
          </div>
        </div>
      )}

      {/* Editor modal */}
      {editingSchema && (
        <ContextEntryEditor
          projectId={projectId}
          basketId={basketId}
          anchorRole={editingSchema.anchor_role}
          entryKey={editingEntryKey}
          schema={editingSchema}
          entry={editingEntry}
          open={editorOpen}
          onClose={closeEditor}
          onSuccess={handleEditorSuccess}
        />
      )}
    </div>
  );
}

/**
 * Badge showing who last updated the entry
 */
function LastUpdatedBadge({ entry }: { entry: ContextEntry }) {
  // Parse the updated_by or created_by field
  // Format: 'user:{id}' or 'agent:{type}'
  const updatedBy = entry.updated_by || entry.created_by;

  if (!updatedBy) return null;

  const isAgent = updatedBy.startsWith('agent:');
  const agentType = isAgent ? updatedBy.replace('agent:', '') : null;

  return (
    <Badge
      variant="outline"
      className="text-xs gap-1 font-normal"
    >
      {isAgent ? (
        <>
          <Bot className="h-3 w-3" />
          <span>{agentType || 'Agent'}</span>
        </>
      ) : (
        <>
          <User className="h-3 w-3" />
          <span>You</span>
        </>
      )}
    </Badge>
  );
}

/**
 * Display the actual content of a context entry
 */
function ContextContentDisplay({
  entry,
  schema
}: {
  entry: ContextEntry;
  schema: ContextEntrySchema;
}) {
  const fields = schema.field_schema.fields;
  const data = entry.data;

  return (
    <div className="space-y-4">
      {fields.map((field) => {
        const value = data[field.key];

        // Skip empty fields
        if (!value || (Array.isArray(value) && value.length === 0)) {
          return null;
        }

        return (
          <div key={field.key} className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
              {field.label}
            </label>
            <div className="text-sm">
              {field.type === 'array' && Array.isArray(value) ? (
                <div className="flex flex-wrap gap-1">
                  {value.map((item, idx) => (
                    <Badge key={idx} variant="secondary" className="text-xs">
                      {String(item)}
                    </Badge>
                  ))}
                </div>
              ) : field.type === 'longtext' ? (
                <p className="whitespace-pre-wrap text-foreground leading-relaxed">
                  {String(value)}
                </p>
              ) : field.type === 'asset' && typeof value === 'string' && value.startsWith('asset://') ? (
                <Badge variant="outline" className="text-xs">
                  📎 {value.replace('asset://', '').slice(0, 8)}...
                </Badge>
              ) : (
                <p className="text-foreground">{String(value)}</p>
              )}
            </div>
          </div>
        );
      })}

      {/* Timestamps */}
      <div className="pt-2 border-t border-border/50 text-xs text-muted-foreground">
        Updated {new Date(entry.updated_at).toLocaleDateString()} at{' '}
        {new Date(entry.updated_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
      </div>
    </div>
  );
}

/**
 * Card for displaying agent-generated insights (working tier)
 */
function AgentInsightCard({
  entry,
  projectId,
  isExpanded,
  onToggle,
}: {
  entry: ContextEntry;
  projectId: string;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  const Icon = ROLE_ICONS[entry.anchor_role] || Sparkles;
  const tierConfig = TIER_CONFIG[entry.tier || 'working'];
  const typeLabel = ITEM_TYPE_LABELS[entry.anchor_role] || entry.anchor_role;

  // Parse source_ref for provenance
  const sourceRef = entry.source_ref as { work_ticket_id?: string; agent_type?: string } | null;
  const workTicketId = sourceRef?.work_ticket_id;
  const agentType = sourceRef?.agent_type;

  const data = (entry.data || {}) as Record<string, string | string[] | Record<string, unknown>>;
  const hasContent = Object.keys(data).length > 0;
  const summary = typeof data.summary === 'string' ? data.summary : null;

  return (
    <Card className={`overflow-hidden border-purple-500/20 bg-purple-500/5`}>
      {/* Card header */}
      <div
        className="p-4 cursor-pointer hover:bg-purple-500/10 transition-colors"
        onClick={onToggle}
      >
        <div className="flex items-center gap-4">
          {/* Icon */}
          <div className="p-2 rounded-lg bg-purple-500/10 text-purple-600">
            <Icon className="h-5 w-5" />
          </div>

          {/* Title and meta */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-medium">
                {entry.display_name || typeLabel}
              </span>
              {/* Tier badge */}
              <Badge
                variant="outline"
                className={`text-xs ${tierConfig.bgColor} ${tierConfig.color}`}
              >
                {tierConfig.label}
              </Badge>
              {/* Agent badge */}
              <Badge variant="secondary" className="text-xs gap-1">
                <Bot className="h-3 w-3" />
                {agentType || 'Agent'}
              </Badge>
            </div>
            {/* Summary preview when collapsed */}
            {!isExpanded && summary && (
              <p className="text-sm text-muted-foreground truncate mt-1">
                {summary}
              </p>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center gap-2">
            {/* View Details Link */}
            <Link
              href={`/projects/${projectId}/context/${entry.id}`}
              className="h-8 w-8 p-0 inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors hover:bg-purple-500/10"
              onClick={(e) => e.stopPropagation()}
            >
              <ExternalLink className="h-4 w-4 text-purple-600" />
            </Link>
            {isExpanded ? (
              <ChevronDown className="h-4 w-4 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-4 w-4 text-muted-foreground" />
            )}
          </div>
        </div>
      </div>

      {/* Expanded content */}
      {isExpanded && hasContent && (
        <div className="px-4 pb-4 border-t border-purple-500/20 pt-4 space-y-4">
          {/* Render all content fields */}
          <AgentInsightContent data={data} />

          {/* Provenance footer */}
          <div className="pt-3 border-t border-border/50 flex items-center justify-between text-xs text-muted-foreground">
            <span>
              Generated {new Date(entry.created_at).toLocaleDateString()} at{' '}
              {new Date(entry.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </span>
            {workTicketId && (
              <Link
                href={`/projects/${projectId}/work-tickets/${workTicketId}/track`}
                className="text-primary hover:underline flex items-center gap-1"
              >
                View Work Ticket
                <ExternalLink className="h-3 w-3" />
              </Link>
            )}
          </div>
        </div>
      )}
    </Card>
  );
}

/**
 * Display structured content from an agent insight
 */
function AgentInsightContent({ data }: { data: Record<string, unknown> }) {
  const contentKeys = Object.keys(data);

  return (
    <div className="space-y-4">
      {contentKeys.map((key) => {
        const value = data[key];
        if (!value) return null;

        // Format the key as a label
        const label = key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

        return (
          <div key={key} className="space-y-1">
            <label className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
              {label}
            </label>
            <div className="text-sm">
              {Array.isArray(value) ? (
                <ul className="list-disc list-inside space-y-1 text-foreground">
                  {value.slice(0, 10).map((item, idx) => (
                    <li key={idx} className="text-sm">
                      {typeof item === 'object' ? JSON.stringify(item) : String(item)}
                    </li>
                  ))}
                  {value.length > 10 && (
                    <li className="text-muted-foreground text-xs">+{value.length - 10} more</li>
                  )}
                </ul>
              ) : typeof value === 'object' ? (
                <pre className="text-xs bg-muted p-2 rounded overflow-auto max-h-32">
                  {JSON.stringify(value, null, 2)}
                </pre>
              ) : (
                <p className="text-foreground whitespace-pre-wrap leading-relaxed">
                  {String(value).slice(0, 2000)}
                  {String(value).length > 2000 ? '...' : ''}
                </p>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
