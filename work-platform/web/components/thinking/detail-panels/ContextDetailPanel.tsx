'use client';

/**
 * ContextDetailPanel
 *
 * Displays context items in the detail panel.
 * Shows list view with search/filter, and detail view for specific items.
 *
 * Part of Chat-First Architecture v1.0
 * See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
 */

import { useState, useEffect, useMemo } from 'react';
import { cn } from '@/lib/utils';
import {
  Search,
  Filter,
  ChevronRight,
  Plus,
  FileText,
  User,
  Target,
  Palette,
  TrendingUp,
  Users,
  Lightbulb,
  Clock,
  CheckCircle2,
  AlertCircle,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Badge } from '@/components/ui/Badge';

// Context item types (should match API types)
interface ContextItem {
  id: string;
  item_type: string;
  title?: string;
  data: Record<string, unknown>;
  tier: 'foundation' | 'working' | 'ephemeral';
  status: 'draft' | 'active' | 'archived';
  completeness_score?: number;
  source?: string;
  created_at: string;
  updated_at: string;
}

interface ContextDetailPanelProps {
  basketId: string;
  items?: ContextItem[];
  loading?: boolean;
  error?: string;
  focusedItemId?: string;
  onItemClick?: (item: ContextItem) => void;
  onCreateItem?: (itemType: string) => void;
  className?: string;
}

// Item type icons
const ITEM_TYPE_ICONS: Record<string, React.ElementType> = {
  problem: Target,
  customer: Users,
  vision: Lightbulb,
  brand: Palette,
  competitor: TrendingUp,
  trend_digest: TrendingUp,
  market_intel: TrendingUp,
  note: FileText,
  insight: Lightbulb,
  default: FileText,
};

// Tier colors
const TIER_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  foundation: { bg: 'bg-blue-50', text: 'text-blue-700', border: 'border-blue-200' },
  working: { bg: 'bg-purple-50', text: 'text-purple-700', border: 'border-purple-200' },
  ephemeral: { bg: 'bg-gray-50', text: 'text-gray-600', border: 'border-gray-200' },
};

export function ContextDetailPanel({
  basketId,
  items = [],
  loading,
  error,
  focusedItemId,
  onItemClick,
  onCreateItem,
  className,
}: ContextDetailPanelProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [filterTier, setFilterTier] = useState<string | null>(null);
  const [filterType, setFilterType] = useState<string | null>(null);
  const [selectedItem, setSelectedItem] = useState<ContextItem | null>(null);

  // Focus on specific item when provided
  useEffect(() => {
    if (focusedItemId) {
      const item = items.find((i) => i.id === focusedItemId);
      if (item) {
        setSelectedItem(item);
      }
    }
  }, [focusedItemId, items]);

  // Get unique item types for filter
  const itemTypes = useMemo(() => {
    const types = new Set(items.map((i) => i.item_type));
    return Array.from(types);
  }, [items]);

  // Filter items
  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      // Search filter
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        const title = (item.title || '').toLowerCase();
        const type = item.item_type.toLowerCase();
        const dataStr = JSON.stringify(item.data).toLowerCase();
        if (!title.includes(query) && !type.includes(query) && !dataStr.includes(query)) {
          return false;
        }
      }

      // Tier filter
      if (filterTier && item.tier !== filterTier) {
        return false;
      }

      // Type filter
      if (filterType && item.item_type !== filterType) {
        return false;
      }

      return true;
    });
  }, [items, searchQuery, filterTier, filterType]);

  // Group items by tier
  const groupedItems = useMemo(() => {
    const groups: Record<string, ContextItem[]> = {
      foundation: [],
      working: [],
      ephemeral: [],
    };

    filteredItems.forEach((item) => {
      const tier = item.tier || 'working';
      if (!groups[tier]) {
        groups[tier] = [];
      }
      groups[tier].push(item);
    });

    return groups;
  }, [filteredItems]);

  const handleItemClick = (item: ContextItem) => {
    setSelectedItem(item);
    onItemClick?.(item);
  };

  // If viewing specific item
  if (selectedItem) {
    return (
      <ContextItemDetail
        item={selectedItem}
        onBack={() => setSelectedItem(null)}
        className={className}
      />
    );
  }

  return (
    <div className={cn('flex h-full flex-col', className)}>
      {/* Search and Filter Bar */}
      <div className="border-b border-border p-3 space-y-2">
        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search context items..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-md border border-input bg-background py-2 pl-10 pr-4 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>

        {/* Filters */}
        <div className="flex items-center gap-2 flex-wrap">
          {/* Tier filter */}
          <div className="flex items-center gap-1">
            {['foundation', 'working', 'ephemeral'].map((tier) => {
              const colors = TIER_COLORS[tier];
              const isActive = filterTier === tier;
              return (
                <button
                  key={tier}
                  onClick={() => setFilterTier(isActive ? null : tier)}
                  className={cn(
                    'rounded-md px-2 py-1 text-xs capitalize transition-colors',
                    isActive
                      ? `${colors.bg} ${colors.text} ${colors.border} border`
                      : 'bg-muted text-muted-foreground hover:bg-muted/80'
                  )}
                >
                  {tier}
                </button>
              );
            })}
          </div>

          {/* Type filter */}
          {itemTypes.length > 0 && (
            <select
              value={filterType || ''}
              onChange={(e) => setFilterType(e.target.value || null)}
              className="rounded-md border border-input bg-background px-2 py-1 text-xs"
            >
              <option value="">All Types</option>
              {itemTypes.map((type) => (
                <option key={type} value={type}>
                  {type.replace('_', ' ')}
                </option>
              ))}
            </select>
          )}

          {/* Clear filters */}
          {(filterTier || filterType) && (
            <button
              onClick={() => {
                setFilterTier(null);
                setFilterType(null);
              }}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              Clear
            </button>
          )}
        </div>
      </div>

      {/* Items List */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex h-full items-center justify-center">
            <div className="text-sm text-muted-foreground">Loading context...</div>
          </div>
        ) : error ? (
          <div className="flex h-full items-center justify-center p-4">
            <div className="text-sm text-red-600">{error}</div>
          </div>
        ) : filteredItems.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center p-4 text-center">
            <FileText className="h-12 w-12 text-muted-foreground/50 mb-4" />
            <div className="text-sm font-medium">No context items</div>
            <div className="text-xs text-muted-foreground mt-1">
              {searchQuery ? 'Try adjusting your search' : 'Start by adding context'}
            </div>
            {onCreateItem && !searchQuery && (
              <Button
                variant="outline"
                size="sm"
                className="mt-4"
                onClick={() => onCreateItem('note')}
              >
                <Plus className="h-4 w-4 mr-2" />
                Add Context
              </Button>
            )}
          </div>
        ) : (
          <div className="divide-y divide-border">
            {/* Foundation items */}
            {groupedItems.foundation.length > 0 && (
              <ContextItemGroup
                title="Foundation"
                tier="foundation"
                items={groupedItems.foundation}
                onItemClick={handleItemClick}
              />
            )}

            {/* Working items */}
            {groupedItems.working.length > 0 && (
              <ContextItemGroup
                title="Working"
                tier="working"
                items={groupedItems.working}
                onItemClick={handleItemClick}
              />
            )}

            {/* Ephemeral items */}
            {groupedItems.ephemeral.length > 0 && (
              <ContextItemGroup
                title="Ephemeral"
                tier="ephemeral"
                items={groupedItems.ephemeral}
                onItemClick={handleItemClick}
              />
            )}
          </div>
        )}
      </div>

      {/* Footer stats */}
      <div className="border-t border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
        {filteredItems.length} of {items.length} items
      </div>
    </div>
  );
}

// ============================================================================
// Context Item Group
// ============================================================================

interface ContextItemGroupProps {
  title: string;
  tier: string;
  items: ContextItem[];
  onItemClick: (item: ContextItem) => void;
}

function ContextItemGroup({ title, tier, items, onItemClick }: ContextItemGroupProps) {
  const [isExpanded, setIsExpanded] = useState(true);
  const colors = TIER_COLORS[tier] || TIER_COLORS.working;

  return (
    <div>
      {/* Group header */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className={cn(
          'flex w-full items-center justify-between px-3 py-2 text-xs font-medium',
          colors.bg, colors.text
        )}
      >
        <span>{title} ({items.length})</span>
        <ChevronRight
          className={cn(
            'h-4 w-4 transition-transform',
            isExpanded && 'rotate-90'
          )}
        />
      </button>

      {/* Items */}
      {isExpanded && (
        <div className="divide-y divide-border/50">
          {items.map((item) => (
            <ContextItemRow
              key={item.id}
              item={item}
              onClick={() => onItemClick(item)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ============================================================================
// Context Item Row
// ============================================================================

interface ContextItemRowProps {
  item: ContextItem;
  onClick: () => void;
}

function ContextItemRow({ item, onClick }: ContextItemRowProps) {
  const Icon = ITEM_TYPE_ICONS[item.item_type] || ITEM_TYPE_ICONS.default;
  const tierColors = TIER_COLORS[item.tier] || TIER_COLORS.working;

  // Get preview text from data
  const previewText = useMemo(() => {
    const data = item.data;
    // Try common field names
    const textFields = ['description', 'summary', 'content', 'text', 'body', 'note'];
    for (const field of textFields) {
      if (typeof data[field] === 'string') {
        return (data[field] as string).slice(0, 120);
      }
    }
    // Fall back to first string value
    for (const value of Object.values(data)) {
      if (typeof value === 'string' && value.length > 10) {
        return value.slice(0, 120);
      }
    }
    return '';
  }, [item.data]);

  return (
    <button
      onClick={onClick}
      className="flex w-full items-start gap-3 p-3 text-left hover:bg-muted/50 transition-colors"
    >
      {/* Icon */}
      <div className={cn('rounded-md p-1.5 shrink-0', tierColors.bg)}>
        <Icon className={cn('h-4 w-4', tierColors.text)} />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium truncate">
            {item.title || item.item_type.replace('_', ' ')}
          </span>
          <Badge variant="outline" className="text-xs capitalize shrink-0">
            {item.item_type.replace('_', ' ')}
          </Badge>
        </div>

        {previewText && (
          <div className="mt-1 text-xs text-muted-foreground line-clamp-2">
            {previewText}
          </div>
        )}

        <div className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
          {item.completeness_score !== undefined && (
            <span>{Math.round(item.completeness_score * 100)}% complete</span>
          )}
          {item.source && (
            <>
              <span>·</span>
              <span className="capitalize">{item.source}</span>
            </>
          )}
          <span>·</span>
          <span>{new Date(item.updated_at).toLocaleDateString()}</span>
        </div>
      </div>

      <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
    </button>
  );
}

// ============================================================================
// Context Item Detail View
// ============================================================================

interface ContextItemDetailProps {
  item: ContextItem;
  onBack: () => void;
  className?: string;
}

function ContextItemDetail({ item, onBack, className }: ContextItemDetailProps) {
  const Icon = ITEM_TYPE_ICONS[item.item_type] || ITEM_TYPE_ICONS.default;
  const tierColors = TIER_COLORS[item.tier] || TIER_COLORS.working;

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
          <div className={cn('rounded-lg p-2', tierColors.bg)}>
            <Icon className={cn('h-6 w-6', tierColors.text)} />
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold">
                {item.title || item.item_type.replace('_', ' ')}
              </h2>
              <Badge className={cn('capitalize', tierColors.bg, tierColors.text, tierColors.border)}>
                {item.tier}
              </Badge>
            </div>
            <div className="flex items-center gap-2 mt-1 text-sm text-muted-foreground">
              <span className="capitalize">{item.item_type.replace('_', ' ')}</span>
              <span>·</span>
              <span>{item.status}</span>
              {item.source && (
                <>
                  <span>·</span>
                  <span>via {item.source}</span>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Completeness */}
        {item.completeness_score !== undefined && (
          <div className="mt-4">
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-muted-foreground">Completeness</span>
              <span className="font-medium">{Math.round(item.completeness_score * 100)}%</span>
            </div>
            <div className="h-2 rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-primary"
                style={{ width: `${item.completeness_score * 100}%` }}
              />
            </div>
          </div>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        <div className="space-y-4">
          {Object.entries(item.data).map(([key, value]) => (
            <div key={key}>
              <label className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                {key.replace('_', ' ')}
              </label>
              <div className="mt-1 text-sm">
                {typeof value === 'string' ? (
                  <p className="whitespace-pre-wrap">{value}</p>
                ) : Array.isArray(value) ? (
                  <ul className="list-disc list-inside space-y-1">
                    {value.map((v, i) => (
                      <li key={i}>{String(v)}</li>
                    ))}
                  </ul>
                ) : (
                  <pre className="rounded-md bg-muted p-2 text-xs overflow-x-auto">
                    {JSON.stringify(value, null, 2)}
                  </pre>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Footer */}
      <div className="border-t border-border bg-muted/30 px-4 py-3">
        <div className="flex items-center justify-between text-xs text-muted-foreground">
          <div className="flex items-center gap-4">
            <span>Created: {new Date(item.created_at).toLocaleString()}</span>
            <span>Updated: {new Date(item.updated_at).toLocaleString()}</span>
          </div>
          <span className="font-mono text-[10px]">{item.id.slice(0, 8)}...</span>
        </div>
      </div>
    </div>
  );
}

export default ContextDetailPanel;
