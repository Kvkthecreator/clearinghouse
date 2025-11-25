import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { createServerComponentClient } from "@/lib/supabase/clients";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { ProjectNavigation } from "@/components/projects/ProjectNavigation";

export default async function ProjectLayout({
  params,
  children,
}: {
  params: Promise<{ id: string }>;
  children: ReactNode;
}) {
  const { id } = await params;

  // Try to authenticate - if it fails, assume this is a public tracking page
  const supabase = createServerComponentClient({ cookies });
  const { data: { user }, error: authError } = await supabase.auth.getUser();

  // If no authentication, use anonymous client for public tracking pages
  if (authError || !user) {
    const anonSupabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    );

    // Verify project exists (minimal check, no auth required)
    const { data: project } = await anonSupabase
      .from('projects')
      .select('id')
      .eq('id', id)
      .maybeSingle();

    if (!project) {
      redirect('/projects');
    }

    // Render without ProjectNavigation for unauthenticated access
    return (
      <div className="min-h-screen bg-background text-foreground">
        <div className="mx-auto">{children}</div>
      </div>
    );
  }

  // For authenticated users, get workspace
  let workspace;
  try {
    const { ensureWorkspaceServer } = await import("@/lib/workspaces/ensureWorkspaceServer");
    workspace = await ensureWorkspaceServer(supabase);
  } catch (error) {
    redirect('/login');
  }

  if (!workspace) {
    redirect('/login');
  }

  // Fetch project to ensure it exists and user has access
  const { data: project } = await supabase
    .from('projects')
    .select('id, workspace_id')
    .eq('id', id)
    .eq('workspace_id', workspace.id)
    .maybeSingle();

  if (!project) {
    redirect('/projects');
  }

  return (
    <div className="min-h-screen bg-background text-foreground">
      <ProjectNavigation projectId={id} />
      <div className="mx-auto">{children}</div>
    </div>
  );
}
