"use client";

/**
 * ContextItemDetailClient - Canvas-style detail view for a context item
 *
 * Features:
 * - Bento-box layout for multimodal content display
 * - Field-type-specific renderers (text, longtext, array, asset, url)
 * - Tier and source indicators
 * - Version history rail
 * - Edit modal integration
 *
 * Design Philosophy:
 * - Visual hierarchy through tile sizing
 * - Responsive masonry-like grid
 * - Rich previews for assets (images, PDFs)
 * - Clear provenance tracking
 */

import { useState, useMemo } from 'react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Badge } from '@/components/ui/Badge';
import {
  Pencil,
  User,
  Bot,
  Calendar,
  Clock,
  ExternalLink,
  FileText,
  Image as ImageIcon,
  Link as LinkIcon,
  List,
  Type,
  AlignLeft,
  Paperclip,
  History,
  AlertTriangle,
  Users,
  Eye,
  Palette,
  Target,
  TrendingUp,
  BarChart3,
  Lightbulb,
  CheckCircle,
} from 'lucide-react';
import Link from 'next/link';
import ContextEntryEditor from '@/components/context/ContextEntryEditor';

// Types
interface ContextItem {
  id: string;
  basket_id: string;
  item_type: string;
  title: string | null;
  content: Record<string, unknown>;
  tier: 'foundation' | 'working' | 'ephemeral';
  schema_id: string | null;
  source_type: string | null;
  source_ref: Record<string, unknown> | null;
  created_by: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

// Extended field type for display (includes 'url' for rendering)
type DisplayFieldType = 'text' | 'longtext' | 'array' | 'asset' | 'url';

// Editor field type (what ContextEntryEditor accepts)
type EditorFieldType = 'text' | 'longtext' | 'array' | 'asset';

interface FieldDefinition {
  key: string;
  type: DisplayFieldType;
  label: string;
  required?: boolean;
  placeholder?: string;
  help?: string;
}

// Schema type for editor (with restricted field types)
interface EditorFieldDefinition {
  key: string;
  type: EditorFieldType;
  label: string;
  required?: boolean;
  placeholder?: string;
  help?: string;
  item_type?: string;
  accept?: string;
}

interface Schema {
  id: string;
  anchor_role: string;
  display_name: string;
  description: string;
  icon: string;
  category: 'foundation' | 'market' | 'insight';
  is_singleton: boolean;
  field_schema: {
    fields: FieldDefinition[];
    agent_produced?: boolean;
  };
}

// Icon mapping
const ITEM_TYPE_ICONS: Record<string, React.ElementType> = {
  problem: AlertTriangle,
  customer: Users,
  vision: Eye,
  brand: Palette,
  competitor: Target,
  trend_digest: TrendingUp,
  market_intel: Lightbulb,
  competitor_snapshot: BarChart3,
};

// Tier config
const TIER_CONFIG: Record<string, { label: string; color: string; bgColor: string; description: string }> = {
  foundation: {
    label: 'Foundation',
    color: 'text-blue-700',
    bgColor: 'bg-blue-500/10 border-blue-500/30',
    description: 'Core context that defines your project',
  },
  working: {
    label: 'Working',
    color: 'text-purple-700',
    bgColor: 'bg-purple-500/10 border-purple-500/30',
    description: 'Active context being refined',
  },
  ephemeral: {
    label: 'Ephemeral',
    color: 'text-gray-600',
    bgColor: 'bg-gray-500/10 border-gray-500/30',
    description: 'Temporary context that may expire',
  },
};

// Field type icons
const FIELD_TYPE_ICONS: Record<string, React.ElementType> = {
  text: Type,
  longtext: AlignLeft,
  array: List,
  asset: Paperclip,
  url: LinkIcon,
};

interface ContextItemDetailClientProps {
  projectId: string;
  basketId: string;
  item: ContextItem;
  schema: Schema | null;
}

export default function ContextItemDetailClient({
  projectId,
  basketId,
  item,
  schema,
}: ContextItemDetailClientProps) {
  const [editorOpen, setEditorOpen] = useState(false);
  const [currentItem, setCurrentItem] = useState(item);

  const Icon = ITEM_TYPE_ICONS[currentItem.item_type] || FileText;
  const tierConfig = TIER_CONFIG[currentItem.tier || 'foundation'];

  // Parse source info
  const isAgentGenerated = currentItem.source_type === 'agent';
  const sourceRef = currentItem.source_ref as { work_ticket_id?: string; agent_type?: string } | null;

  // Get fields from schema or infer from content
  const fields = useMemo(() => {
    if (schema?.field_schema?.fields) {
      return schema.field_schema.fields;
    }
    // Infer fields from content keys
    return Object.keys(currentItem.content || {}).map((key) => ({
      key,
      type: inferFieldType(currentItem.content[key]),
      label: formatLabel(key),
    }));
  }, [schema, currentItem.content]);

  // Categorize fields by size for bento layout
  const { largeFields, mediumFields, smallFields } = useMemo(() => {
    const large: typeof fields = [];
    const medium: typeof fields = [];
    const small: typeof fields = [];

    fields.forEach((field) => {
      const value = currentItem.content[field.key];
      if (!value) return;

      if (field.type === 'longtext' || (typeof value === 'string' && value.length > 200)) {
        large.push(field);
      } else if (field.type === 'array' || field.type === 'asset') {
        medium.push(field);
      } else {
        small.push(field);
      }
    });

    return { largeFields: large, mediumFields: medium, smallFields: small };
  }, [fields, currentItem.content]);

  const handleEditorSuccess = () => {
    // Refresh the page to get updated data
    window.location.reload();
  };

  return (
    <div className="mx-auto max-w-7xl px-6 py-8">
      {/* Hero Section */}
      <div className="mb-8">
        <div className="flex items-start justify-between">
          <div className="flex items-start gap-4">
            {/* Icon */}
            <div className={`p-4 rounded-xl ${tierConfig.bgColor}`}>
              <Icon className={`h-8 w-8 ${tierConfig.color}`} />
            </div>

            {/* Title and Meta */}
            <div>
              <h1 className="text-3xl font-bold text-foreground">
                {currentItem.title || schema?.display_name || formatLabel(currentItem.item_type)}
              </h1>
              <p className="text-muted-foreground mt-1">
                {schema?.description || tierConfig.description}
              </p>

              {/* Badges Row */}
              <div className="flex items-center gap-2 mt-3 flex-wrap">
                {/* Tier Badge */}
                <Badge variant="outline" className={`${tierConfig.bgColor} ${tierConfig.color}`}>
                  {tierConfig.label}
                </Badge>

                {/* Category Badge */}
                {schema?.category && (
                  <Badge variant="secondary" className="capitalize">
                    {schema.category}
                  </Badge>
                )}

                {/* Source Badge */}
                <Badge variant="outline" className="gap-1">
                  {isAgentGenerated ? (
                    <>
                      <Bot className="h-3 w-3" />
                      {sourceRef?.agent_type || 'Agent'}
                    </>
                  ) : (
                    <>
                      <User className="h-3 w-3" />
                      You
                    </>
                  )}
                </Badge>

                {/* Completeness */}
                {schema && (
                  <CompletenessIndicator
                    fields={schema.field_schema.fields}
                    content={currentItem.content}
                  />
                )}
              </div>
            </div>
          </div>

          {/* Actions */}
          <Button onClick={() => setEditorOpen(true)}>
            <Pencil className="h-4 w-4 mr-2" />
            Edit
          </Button>
        </div>
      </div>

      {/* Bento Grid */}
      <div className="grid grid-cols-12 gap-4 auto-rows-min">
        {/* Large fields - full width or 2/3 width */}
        {largeFields.map((field) => (
          <div key={field.key} className="col-span-12 lg:col-span-8">
            <FieldTile
              field={field}
              value={currentItem.content[field.key]}
              size="large"
            />
          </div>
        ))}

        {/* Medium fields - half width */}
        {mediumFields.map((field) => (
          <div key={field.key} className="col-span-12 sm:col-span-6 lg:col-span-4">
            <FieldTile
              field={field}
              value={currentItem.content[field.key]}
              size="medium"
            />
          </div>
        ))}

        {/* Small fields - third width or quarter */}
        {smallFields.map((field) => (
          <div key={field.key} className="col-span-12 sm:col-span-6 lg:col-span-3">
            <FieldTile
              field={field}
              value={currentItem.content[field.key]}
              size="small"
            />
          </div>
        ))}
      </div>

      {/* Provenance Footer */}
      <div className="mt-8 pt-6 border-t border-border">
        <div className="flex items-center justify-between text-sm text-muted-foreground">
          <div className="flex items-center gap-6">
            <div className="flex items-center gap-2">
              <Calendar className="h-4 w-4" />
              <span>Created {formatDate(currentItem.created_at)}</span>
            </div>
            <div className="flex items-center gap-2">
              <Clock className="h-4 w-4" />
              <span>Updated {formatDate(currentItem.updated_at)}</span>
            </div>
          </div>

          {/* Link to work ticket if agent-generated */}
          {isAgentGenerated && sourceRef?.work_ticket_id && (
            <Link
              href={`/projects/${projectId}/work-tickets/${sourceRef.work_ticket_id}/track`}
              className="text-primary hover:underline flex items-center gap-1"
            >
              View Source Work Ticket
              <ExternalLink className="h-3 w-3" />
            </Link>
          )}
        </div>

        {/* Version History Placeholder */}
        <div className="mt-4 p-4 bg-muted/50 rounded-lg">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <History className="h-4 w-4" />
            <span>Version history coming soon</span>
          </div>
        </div>
      </div>

      {/* Editor Modal */}
      {schema && (
        <ContextEntryEditor
          projectId={projectId}
          basketId={basketId}
          anchorRole={currentItem.item_type}
          schema={{
            anchor_role: schema.anchor_role,
            display_name: schema.display_name,
            description: schema.description,
            icon: schema.icon,
            category: schema.category,
            is_singleton: schema.is_singleton,
            field_schema: {
              // Convert 'url' type to 'text' for editor compatibility
              fields: schema.field_schema.fields.map((field): EditorFieldDefinition => ({
                ...field,
                type: field.type === 'url' ? 'text' : field.type as EditorFieldType,
              })),
              agent_produced: schema.field_schema.agent_produced,
            },
          }}
          entry={{
            id: currentItem.id,
            basket_id: currentItem.basket_id,
            anchor_role: currentItem.item_type,
            data: currentItem.content,
            state: 'active',
            created_at: currentItem.created_at,
            updated_at: currentItem.updated_at,
          }}
          open={editorOpen}
          onClose={() => setEditorOpen(false)}
          onSuccess={handleEditorSuccess}
        />
      )}
    </div>
  );
}

/**
 * Field Tile - Renders a single field in the bento grid
 */
function FieldTile({
  field,
  value,
  size,
}: {
  field: FieldDefinition;
  value: unknown;
  size: 'small' | 'medium' | 'large';
}) {
  const FieldIcon = FIELD_TYPE_ICONS[field.type] || Type;

  if (!value && value !== 0) {
    return null;
  }

  return (
    <Card className="h-full overflow-hidden hover:shadow-md transition-shadow">
      {/* Field Header */}
      <div className="px-4 py-3 border-b border-border bg-muted/30">
        <div className="flex items-center gap-2">
          <FieldIcon className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm font-medium text-foreground">{field.label}</span>
        </div>
      </div>

      {/* Field Content */}
      <div className={`p-4 ${size === 'large' ? 'min-h-[200px]' : size === 'medium' ? 'min-h-[120px]' : ''}`}>
        <FieldRenderer field={field} value={value} />
      </div>
    </Card>
  );
}

/**
 * Field Renderer - Type-specific rendering
 */
function FieldRenderer({ field, value }: { field: FieldDefinition; value: unknown }) {
  // Text
  if (field.type === 'text') {
    return <p className="text-foreground">{String(value)}</p>;
  }

  // Long Text
  if (field.type === 'longtext') {
    return (
      <div className="prose prose-sm max-w-none">
        <p className="text-foreground whitespace-pre-wrap leading-relaxed">
          {String(value)}
        </p>
      </div>
    );
  }

  // Array
  if (field.type === 'array' && Array.isArray(value)) {
    return (
      <div className="flex flex-wrap gap-2">
        {value.map((item, idx) => (
          <Badge key={idx} variant="secondary" className="text-sm">
            {typeof item === 'object' ? JSON.stringify(item) : String(item)}
          </Badge>
        ))}
      </div>
    );
  }

  // Asset
  if (field.type === 'asset' && typeof value === 'string') {
    if (value.startsWith('asset://')) {
      const assetId = value.replace('asset://', '');
      return (
        <div className="flex items-center gap-2 p-3 bg-muted rounded-lg">
          <Paperclip className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm text-muted-foreground font-mono">{assetId.slice(0, 8)}...</span>
        </div>
      );
    }
    // Direct URL (image)
    if (value.match(/\.(jpg|jpeg|png|gif|webp)/i)) {
      return (
        <div className="relative rounded-lg overflow-hidden bg-muted">
          <img
            src={value}
            alt={field.label}
            className="w-full h-auto max-h-64 object-contain"
          />
        </div>
      );
    }
  }

  // URL
  if (field.type === 'url' && typeof value === 'string') {
    return (
      <a
        href={value}
        target="_blank"
        rel="noopener noreferrer"
        className="text-primary hover:underline flex items-center gap-1"
      >
        <LinkIcon className="h-4 w-4" />
        {value.length > 50 ? value.slice(0, 50) + '...' : value}
        <ExternalLink className="h-3 w-3" />
      </a>
    );
  }

  // Fallback for arrays (if not detected as array type)
  if (Array.isArray(value)) {
    return (
      <ul className="list-disc list-inside space-y-1">
        {value.slice(0, 10).map((item, idx) => (
          <li key={idx} className="text-sm text-foreground">
            {typeof item === 'object' ? JSON.stringify(item) : String(item)}
          </li>
        ))}
        {value.length > 10 && (
          <li className="text-sm text-muted-foreground">+{value.length - 10} more</li>
        )}
      </ul>
    );
  }

  // Fallback for objects
  if (typeof value === 'object' && value !== null) {
    return (
      <pre className="text-xs bg-muted p-3 rounded-lg overflow-auto max-h-48">
        {JSON.stringify(value, null, 2)}
      </pre>
    );
  }

  // Default text
  return <p className="text-foreground">{String(value)}</p>;
}

/**
 * Completeness Indicator
 */
function CompletenessIndicator({
  fields,
  content,
}: {
  fields: FieldDefinition[];
  content: Record<string, unknown>;
}) {
  const requiredFields = fields.filter((f) => f.required);
  const filledRequired = requiredFields.filter((f) => {
    const value = content[f.key];
    return value !== undefined && value !== null && value !== '' &&
      !(Array.isArray(value) && value.length === 0);
  });

  const score = requiredFields.length > 0
    ? Math.round((filledRequired.length / requiredFields.length) * 100)
    : 100;

  return (
    <Badge
      variant="outline"
      className={`gap-1 ${
        score === 100
          ? 'bg-green-500/10 text-green-700 border-green-500/30'
          : score >= 50
          ? 'bg-yellow-500/10 text-yellow-700 border-yellow-500/30'
          : 'bg-red-500/10 text-red-700 border-red-500/30'
      }`}
    >
      {score === 100 ? (
        <CheckCircle className="h-3 w-3" />
      ) : (
        <span className="text-xs">{score}%</span>
      )}
      {score === 100 ? 'Complete' : 'Complete'}
    </Badge>
  );
}

// Utility functions
function inferFieldType(value: unknown): FieldDefinition['type'] {
  if (Array.isArray(value)) return 'array';
  if (typeof value === 'string') {
    if (value.startsWith('asset://')) return 'asset';
    if (value.startsWith('http://') || value.startsWith('https://')) return 'url';
    if (value.length > 200) return 'longtext';
  }
  return 'text';
}

function formatLabel(key: string): string {
  return key
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays === 0) {
    return `today at ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
  } else if (diffDays === 1) {
    return 'yesterday';
  } else if (diffDays < 7) {
    return `${diffDays} days ago`;
  } else {
    return date.toLocaleDateString();
  }
}
