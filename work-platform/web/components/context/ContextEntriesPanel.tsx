"use client";

/**
 * ContextEntriesPanel - Display context entries organized by category
 *
 * Shows:
 * - Foundation context (problem, customer, vision, brand)
 * - Market context (competitors)
 * - Insight context (trend_digest, competitor_snapshot)
 *
 * Each entry shows completeness and allows editing via ContextEntryEditor.
 */

import { useState, useEffect, useMemo } from 'react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Badge } from '@/components/ui/Badge';
import {
  Plus,
  Pencil,
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
} from 'lucide-react';
import {
  useContextSchemas,
  useContextEntries,
  type ContextEntrySchema,
  type ContextEntry,
} from '@/hooks/useContextEntries';
import ContextEntryEditor from './ContextEntryEditor';

// Icon mapping for anchor roles
const ROLE_ICONS: Record<string, React.ElementType> = {
  problem: AlertTriangle,
  customer: Users,
  vision: Eye,
  brand: Palette,
  competitor: Target,
  trend_digest: TrendingUp,
  competitor_snapshot: BarChart3,
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
}

export default function ContextEntriesPanel({
  projectId,
  basketId,
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

  // Editor modal state
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingSchema, setEditingSchema] = useState<ContextEntrySchema | null>(null);
  const [editingEntry, setEditingEntry] = useState<ContextEntry | null>(null);
  const [editingEntryKey, setEditingEntryKey] = useState<string | undefined>();

  // Open editor for a schema
  const openEditor = (schema: ContextEntrySchema, entry?: ContextEntry, entryKey?: string) => {
    setEditingSchema(schema);
    setEditingEntry(entry || null);
    setEditingEntryKey(entryKey);
    setEditorOpen(true);
  };

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

                return (
                  <Card
                    key={schema.anchor_role}
                    className={`p-4 cursor-pointer hover:bg-muted/50 transition-colors ${
                      hasContent ? '' : 'border-dashed'
                    }`}
                    onClick={() => openEditor(schema, entry || undefined)}
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

                      {/* Content */}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{schema.display_name}</span>
                          {isAgentProduced && (
                            <Badge variant="secondary" className="text-xs">
                              Agent
                            </Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted-foreground truncate">
                          {hasContent
                            ? getPreviewText(entry.data, schema)
                            : schema.description}
                        </p>
                      </div>

                      {/* Status */}
                      <div className="flex items-center gap-2">
                        {hasContent ? (
                          <CheckCircle className="h-5 w-5 text-green-500" />
                        ) : (
                          <Plus className="h-5 w-5 text-muted-foreground" />
                        )}
                        <ChevronRight className="h-4 w-4 text-muted-foreground" />
                      </div>
                    </div>
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
 * Get preview text from entry data based on schema
 */
function getPreviewText(data: Record<string, unknown>, schema: ContextEntrySchema): string {
  const fields = schema.field_schema.fields;

  // Try to get text from the first text/longtext field
  for (const field of fields) {
    if (field.type === 'text' || field.type === 'longtext') {
      const value = data[field.key];
      if (typeof value === 'string' && value.trim()) {
        return value.length > 100 ? value.slice(0, 100) + '...' : value;
      }
    }
  }

  // Fallback to field count
  const filledCount = Object.keys(data).filter((k) => {
    const val = data[k];
    if (Array.isArray(val)) return val.length > 0;
    return val !== null && val !== undefined && val !== '';
  }).length;

  return `${filledCount} of ${fields.length} fields filled`;
}
