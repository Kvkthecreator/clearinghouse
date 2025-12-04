import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { createRouteHandlerClient } from '@/lib/supabase/clients';

/**
 * GET /api/projects/[id]/context/anchors
 *
 * Fetches anchor status for a project's basket.
 * Reads from context_items table (unified context architecture).
 *
 * See: /docs/architecture/ADR_CONTEXT_ITEMS_UNIFIED.md
 *
 * Returns:
 * - anchors: Array of AnchorStatusSummary
 * - stats: Anchor counts by lifecycle
 */

// Role display labels (matching ANCHOR_CONFIG in components)
const ROLE_LABELS: Record<string, string> = {
  problem: 'Problem',
  customer: 'Customer',
  vision: 'Vision',
  brand: 'Brand',
  competitor: 'Competitor',
  trend_digest: 'Trend Digest',
  competitor_snapshot: 'Competitor Snapshot',
};

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: projectId } = await params;
    const supabase = createRouteHandlerClient({ cookies });

    // Get Supabase session for auth
    const {
      data: { session },
      error: authError,
    } = await supabase.auth.getSession();

    if (authError || !session) {
      return NextResponse.json(
        { detail: 'Authentication required' },
        { status: 401 }
      );
    }

    // Fetch project to get basket_id
    const projectResponse = await supabase
      .from('projects')
      .select('id, basket_id, name')
      .eq('id', projectId)
      .single();

    if (projectResponse.error || !projectResponse.data) {
      return NextResponse.json(
        { detail: 'Project not found' },
        { status: 404 }
      );
    }

    const { basket_id: basketId } = projectResponse.data;

    if (!basketId) {
      return NextResponse.json(
        { detail: 'Project has no associated basket' },
        { status: 400 }
      );
    }

    // Fetch context items from unified context_items table
    const { data: contextItems, error: itemsError } = await supabase
      .from('context_items')
      .select('id, item_type, item_key, content, completeness_score, status, tier, expires_at, updated_at, created_at')
      .eq('basket_id', basketId)
      .eq('status', 'active');

    if (itemsError) {
      console.error('[ANCHORS API] Error fetching context items:', itemsError);
      return NextResponse.json(
        { detail: 'Failed to fetch context items' },
        { status: 500 }
      );
    }

    // Fetch schema info for TTL-based staleness checking
    const { data: schemas } = await supabase
      .from('context_entry_schemas')
      .select('anchor_role, field_schema');

    const schemaMap = new Map(
      (schemas || []).map(s => [s.anchor_role, s.field_schema])
    );

    // Transform context_items to anchor format expected by frontend
    const anchors = (contextItems || []).map(item => {
      // Determine lifecycle based on completeness
      const hasContent = item.completeness_score && item.completeness_score > 0;

      // Check if stale (for working tier items with TTL in schema)
      let isStale = false;
      if (item.tier === 'working' && item.updated_at) {
        const fieldSchema = schemaMap.get(item.item_type);
        const refreshTtlHours = fieldSchema?.refresh_ttl_hours;

        if (refreshTtlHours) {
          const updatedAt = new Date(item.updated_at).getTime();
          const ttlMs = refreshTtlHours * 60 * 60 * 1000;
          isStale = Date.now() - updatedAt > ttlMs;
        }
      }

      // Check expires_at for ephemeral tier
      if (item.tier === 'ephemeral' && item.expires_at) {
        const expiresAt = new Date(item.expires_at).getTime();
        isStale = Date.now() > expiresAt;
      }

      return {
        anchor_key: item.item_type,
        entry_key: item.item_key,
        lifecycle: isStale ? 'stale' : (hasContent ? 'approved' : 'draft'),
        label: ROLE_LABELS[item.item_type] || item.item_type,
        is_stale: isStale,
        last_updated_at: item.updated_at,
        completeness_score: item.completeness_score,
        tier: item.tier,
      };
    });

    // Calculate stats
    const stats = {
      total: anchors.length,
      approved: anchors.filter(a => a.lifecycle === 'approved').length,
      draft: anchors.filter(a => a.lifecycle === 'draft').length,
      stale: anchors.filter(a => a.lifecycle === 'stale').length,
      missing: 0, // Not applicable with new system
    };

    return NextResponse.json({
      anchors,
      stats,
      basket_id: basketId,
    });

  } catch (error) {
    console.error('[ANCHORS API] Error:', error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    );
  }
}
