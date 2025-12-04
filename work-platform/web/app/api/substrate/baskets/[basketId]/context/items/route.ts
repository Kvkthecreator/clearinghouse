import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { createRouteHandlerClient, createServiceRoleClient } from '@/lib/supabase/clients';

/**
 * GET /api/substrate/baskets/[basketId]/context/items
 *
 * Fetches context items directly from Supabase (no proxy).
 * Includes created_by/updated_by for source badges.
 *
 * v3.0 Terminology:
 * - item_type: Type of context item (problem, customer, vision, brand, etc.)
 * - item_key: Optional key for non-singleton types
 * - content: Structured JSONB data
 * - tier: Governance tier (foundation, working, ephemeral)
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ basketId: string }> }
) {
  try {
    const { basketId } = await params;

    // Get Supabase session for auth check
    const supabase = createRouteHandlerClient({ cookies });
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

    // Query params
    const searchParams = request.nextUrl.searchParams;
    const itemType = searchParams.get('item_type');
    const tier = searchParams.get('tier');
    const status = searchParams.get('status') || 'active';

    // Use service role client for query (bypasses RLS for simplicity)
    const serviceClient = createServiceRoleClient();

    // Build query
    let query = serviceClient
      .from('context_items')
      .select(`
        id,
        basket_id,
        tier,
        item_type,
        item_key,
        title,
        content,
        schema_id,
        created_by,
        updated_by,
        status,
        completeness_score,
        created_at,
        updated_at
      `)
      .eq('basket_id', basketId)
      .eq('status', status)
      .order('item_type');

    if (itemType) {
      query = query.eq('item_type', itemType);
    }
    if (tier) {
      query = query.eq('tier', tier);
    }

    const { data: items, error: queryError } = await query;

    if (queryError) {
      console.error('[CONTEXT ITEMS] Query error:', queryError);
      return NextResponse.json(
        { detail: 'Failed to fetch context items' },
        { status: 500 }
      );
    }

    // Transform to response format (maintaining backward compat)
    const entries = (items || []).map((item) => ({
      id: item.id,
      basket_id: item.basket_id,
      anchor_role: item.item_type,  // Map item_type -> anchor_role for compat
      entry_key: item.item_key,
      display_name: item.title,
      data: item.content,
      completeness_score: item.completeness_score,
      state: item.status,
      created_by: item.created_by,
      updated_by: item.updated_by,
      created_at: item.created_at,
      updated_at: item.updated_at,
    }));

    return NextResponse.json({ entries, basket_id: basketId });
  } catch (error) {
    console.error('[CONTEXT ITEMS] Error:', error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    );
  }
}
