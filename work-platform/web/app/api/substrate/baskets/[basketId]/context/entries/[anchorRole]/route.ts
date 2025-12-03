import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { createRouteHandlerClient } from '@/lib/supabase/clients';

const SUBSTRATE_API_URL = process.env.SUBSTRATE_API_URL || 'https://substrate-api.onrender.com';

/**
 * GET /api/substrate/baskets/[basketId]/context/entries/[anchorRole]
 *
 * Get a specific context entry by anchor role.
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ basketId: string; anchorRole: string }> }
) {
  try {
    const { basketId, anchorRole } = await params;

    // Get Supabase session
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

    // Forward query params (entry_key)
    const searchParams = request.nextUrl.searchParams;
    const queryString = searchParams.toString();
    const url = `${SUBSTRATE_API_URL}/api/substrate/baskets/${basketId}/context/entries/${anchorRole}${queryString ? `?${queryString}` : ''}`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ detail: 'Failed to fetch entry' }));
      return NextResponse.json(error, { status: response.status });
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('[CONTEXT ENTRY GET] Error:', error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * PUT /api/substrate/baskets/[basketId]/context/entries/[anchorRole]
 *
 * Create or update a context entry.
 */
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ basketId: string; anchorRole: string }> }
) {
  try {
    const { basketId, anchorRole } = await params;

    // Get Supabase session
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

    const body = await request.json();

    const response = await fetch(
      `${SUBSTRATE_API_URL}/api/substrate/baskets/${basketId}/context/entries/${anchorRole}`,
      {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      }
    );

    if (!response.ok) {
      const error = await response.json().catch(() => ({ detail: 'Failed to save entry' }));
      return NextResponse.json(error, { status: response.status });
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('[CONTEXT ENTRY PUT] Error:', error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    );
  }
}

/**
 * DELETE /api/substrate/baskets/[basketId]/context/entries/[anchorRole]
 *
 * Archive a context entry.
 */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ basketId: string; anchorRole: string }> }
) {
  try {
    const { basketId, anchorRole } = await params;

    // Get Supabase session
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

    // Forward query params (entry_key)
    const searchParams = request.nextUrl.searchParams;
    const queryString = searchParams.toString();
    const url = `${SUBSTRATE_API_URL}/api/substrate/baskets/${basketId}/context/entries/${anchorRole}${queryString ? `?${queryString}` : ''}`;

    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ detail: 'Failed to archive entry' }));
      return NextResponse.json(error, { status: response.status });
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('[CONTEXT ENTRY DELETE] Error:', error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    );
  }
}
