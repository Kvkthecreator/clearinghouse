/**
 * Quick Work Outputs View
 * Temporary page to view work outputs directly
 */
import { cookies } from "next/headers";
import { createServerComponentClient } from "@/lib/supabase/clients";
import { getAuthenticatedUser } from "@/lib/auth/getAuthenticatedUser";
import Link from "next/link";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { ArrowLeft, FileText } from 'lucide-react';

interface PageProps {
  params: Promise<{ id: string }>;
}

export default async function WorkOutputsPage({ params }: PageProps) {
  const { id: projectId } = await params;

  const supabase = createServerComponentClient({ cookies });
  const { userId } = await getAuthenticatedUser(supabase);

  // Fetch project
  const { data: project } = await supabase
    .from('projects')
    .select('id, name, basket_id')
    .eq('id', projectId)
    .maybeSingle();

  if (!project) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="text-center">
          <h2 className="text-xl font-semibold text-foreground">Project not found</h2>
        </div>
      </div>
    );
  }

  // Fetch work outputs with work ticket info
  const { data: outputs } = await supabase
    .from('work_outputs')
    .select(`
      id,
      title,
      body,
      output_type,
      agent_type,
      confidence,
      generation_method,
      file_id,
      file_format,
      created_at,
      work_ticket_id,
      work_tickets!inner(
        id,
        status,
        created_at
      )
    `)
    .eq('basket_id', project.basket_id)
    .order('created_at', { ascending: false })
    .limit(20);

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-6">
      {/* Header */}
      <div>
        <Link href={`/projects/${projectId}/overview`} className="mb-2 inline-flex items-center text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-4 w-4 mr-1" />
          Back to Project
        </Link>
        <h1 className="text-3xl font-bold text-foreground">Work Outputs</h1>
        <p className="text-muted-foreground mt-1">{project.name}</p>
      </div>

      {/* Outputs List */}
      {!outputs || outputs.length === 0 ? (
        <Card className="p-12 text-center border-dashed">
          <FileText className="h-12 w-12 mx-auto mb-4 text-muted-foreground" />
          <h3 className="text-xl font-semibold text-foreground mb-2">
            No work outputs yet
          </h3>
          <p className="text-muted-foreground">
            Execute a recipe to generate work outputs.
          </p>
        </Card>
      ) : (
        <div className="space-y-4">
          {outputs.map((output: any) => (
            <Card key={output.id} className="p-6">
              <div className="flex items-start justify-between mb-4">
                <div className="flex-1">
                  <h3 className="text-lg font-semibold text-foreground mb-2">
                    {output.title}
                  </h3>
                  <div className="flex items-center gap-2 flex-wrap">
                    <Badge variant="outline" className="text-xs capitalize">
                      {output.output_type}
                    </Badge>
                    <Badge variant="secondary" className="text-xs capitalize">
                      {output.agent_type}
                    </Badge>
                    <Badge variant="secondary" className="text-xs">
                      {output.generation_method}
                    </Badge>
                    {output.file_format && (
                      <Badge variant="default" className="text-xs uppercase">
                        {output.file_format}
                      </Badge>
                    )}
                    {output.confidence && (
                      <span className="text-xs text-muted-foreground">
                        Confidence: {(output.confidence * 100).toFixed(0)}%
                      </span>
                    )}
                    <span className="text-xs text-muted-foreground">
                      {new Date(output.created_at).toLocaleString()}
                    </span>
                  </div>
                </div>
              </div>

              {/* Body Content */}
              {output.body && (
                <div className="mt-4">
                  <div className="rounded-lg border bg-muted/30 p-4 max-h-96 overflow-auto">
                    <pre className="text-sm whitespace-pre-wrap font-mono text-foreground">
                      {typeof output.body === 'string'
                        ? output.body.slice(0, 2000) + (output.body.length > 2000 ? '...' : '')
                        : JSON.stringify(output.body, null, 2).slice(0, 2000)
                      }
                    </pre>
                  </div>
                </div>
              )}

              {/* File Info */}
              {output.file_id && (
                <div className="mt-4 p-4 rounded-lg border bg-blue-500/5 border-blue-500/20">
                  <div className="flex items-center gap-2 text-sm">
                    <FileText className="h-4 w-4 text-blue-500" />
                    <span className="text-foreground">
                      File: <code className="text-xs bg-muted px-2 py-1 rounded">{output.file_id}</code>
                    </span>
                    <Badge variant="default" className="text-xs uppercase">
                      {output.file_format}
                    </Badge>
                  </div>
                </div>
              )}
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
