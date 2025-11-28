import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { createRouteHandlerClient } from '@/lib/supabase/clients';

const WORK_PLATFORM_API_URL = process.env.NEXT_PUBLIC_WORK_PLATFORM_API_URL || 'http://localhost:8000';
const SUBSTRATE_API_URL = process.env.SUBSTRATE_API_URL || 'http://localhost:10000';

export async function POST(request: NextRequest) {
  try {
    // Get Supabase session (canonical pattern per AUTH_CANON.md line 39-43)
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

    const token = session.access_token;

    const body = await request.json();
    const { project_name, description, project_context } = body;

    // Validate required fields
    if (!project_name || !project_name.trim()) {
      return NextResponse.json(
        { detail: 'Project name is required' },
        { status: 400 }
      );
    }

    // Forward to work-platform backend (canonical auth pattern)
    const backendPayload = {
      project_name: project_name.trim(),
      initial_context: 'Project created - foundational context pending',
      description: description?.trim() || undefined,
    };

    // Send both Authorization AND sb-access-token headers (per AUTH_CANON.md line 7-9)
    const backendResponse = await fetch(`${WORK_PLATFORM_API_URL}/api/projects/new`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'sb-access-token': token,  // Both headers required
      },
      body: JSON.stringify(backendPayload),
    });

    if (!backendResponse.ok) {
      const errorData = await backendResponse.json().catch(() => ({ detail: 'Failed to create project' }));
      return NextResponse.json(
        errorData,
        { status: backendResponse.status }
      );
    }

    const result = await backendResponse.json();

    // If project_context provided, trigger anchor seeding (fire-and-forget)
    // This generates foundational anchor blocks from the user's context
    if (project_context?.trim() && result.basket_id) {
      console.log(`[CREATE PROJECT API] Triggering anchor seeding for basket ${result.basket_id}`);

      // Fire-and-forget - don't block project creation on seeding
      fetch(`${SUBSTRATE_API_URL}/api/baskets/${result.basket_id}/seed-anchors`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          context: project_context.trim(),
          project_name: project_name.trim(),
        }),
      }).then(res => {
        if (res.ok) {
          console.log(`[CREATE PROJECT API] Anchor seeding initiated for basket ${result.basket_id}`);
        } else {
          console.warn(`[CREATE PROJECT API] Anchor seeding failed for basket ${result.basket_id}: ${res.status}`);
        }
      }).catch(err => {
        console.warn(`[CREATE PROJECT API] Anchor seeding error for basket ${result.basket_id}:`, err);
      });
    }

    return NextResponse.json(result);
  } catch (error) {
    console.error('[CREATE PROJECT API] Error:', error);
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    );
  }
}
