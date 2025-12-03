import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { createRouteHandlerClient } from '@/lib/supabase/clients';

/**
 * GET /api/projects/[id]/context/anchors
 *
 * Fetches anchor status for a project's basket.
 * Now reads from context_entries table (new schema-driven system).
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

    // Fetch context entries from new schema-driven table
    const { data: contextEntries, error: entriesError } = await supabase
      .from('context_entries')
      .select('id, anchor_role, entry_key, data, completeness_score, state, refresh_policy, updated_at, created_at')
      .eq('basket_id', basketId)
      .eq('state', 'active');

    if (entriesError) {
      console.error('[ANCHORS API] Error fetching context entries:', entriesError);
      return NextResponse.json(
        { detail: 'Failed to fetch context entries' },
        { status: 500 }
      );
    }

    // Transform context_entries to anchor format expected by frontend
    const anchors = (contextEntries || []).map(entry => {
      // Determine lifecycle based on completeness
      const hasContent = entry.completeness_score && entry.completeness_score > 0;

      // Check if stale (for insight roles with refresh_policy)
      let isStale = false;
      if (entry.refresh_policy?.ttl_hours && entry.updated_at) {
        const updatedAt = new Date(entry.updated_at).getTime();
        const ttlMs = entry.refresh_policy.ttl_hours * 60 * 60 * 1000;
        isStale = Date.now() - updatedAt > ttlMs;
      }

      return {
        anchor_key: entry.anchor_role,
        entry_key: entry.entry_key,
        lifecycle: isStale ? 'stale' : (hasContent ? 'approved' : 'draft'),
        label: ROLE_LABELS[entry.anchor_role] || entry.anchor_role,
        is_stale: isStale,
        last_updated_at: entry.updated_at,
        completeness_score: entry.completeness_score,
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
