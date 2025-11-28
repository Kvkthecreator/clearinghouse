"use client";

import { useMemo, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Label } from '@/components/ui/Label';
import { Textarea } from '@/components/ui/Textarea';
import { useRouter } from 'next/navigation';
import { AlertCircle, CheckCircle2, Loader2, Sparkles, ChevronDown, ChevronUp } from 'lucide-react';
import { cn } from '@/lib/utils';

interface CreateProjectDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function CreateProjectDialog({ open, onOpenChange }: CreateProjectDialogProps) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [projectName, setProjectName] = useState('');
  const [description, setDescription] = useState('');
  const [projectContext, setProjectContext] = useState('');
  const [showContextInput, setShowContextInput] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const canSubmit = useMemo(() => {
    return projectName.trim().length > 0;
  }, [projectName]);

  const resetState = () => {
    setProjectName('');
    setDescription('');
    setProjectContext('');
    setShowContextInput(false);
    setError(null);
    setSubmitting(false);
    setSuccess(false);
  };

  const handleClose = (nextOpen: boolean) => {
    if (submitting) return;
    onOpenChange(nextOpen);
    if (!nextOpen) resetState();
  };

  const handleSubmit = async () => {
    if (!canSubmit || submitting) return;
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch('/api/projects/new', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          project_name: projectName.trim(),
          description: description.trim() || undefined,
          project_context: projectContext.trim() || undefined,
        }),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: 'Failed to create project' }));
        throw new Error(typeof errorData.detail === 'string' ? errorData.detail : errorData.detail?.message || 'Failed to create project');
      }

      const result = await response.json();

      setSuccess(true);
      handleClose(false);
      resetState();

      // Navigate to project context page to set up foundational context
      router.push(`/projects/${result.project_id}/context`);
      router.refresh();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create project';
      setError(message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Create New Project</DialogTitle>
          <DialogDescription>
            Create a project workspace. You'll set up foundational context on the next screen.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-6">
          <section className="flex flex-col gap-4">
            <FieldBlock label="Project Name" required>
              <Input
                placeholder="e.g., Healthcare AI Research"
                value={projectName}
                onChange={(e) => setProjectName(e.target.value)}
                autoFocus
              />
            </FieldBlock>

            <FieldBlock label="Description" hint="Optional · Brief summary visible on project cards">
              <Textarea
                placeholder="What is this project about?"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={3}
                className="resize-none"
                maxLength={1000}
              />
            </FieldBlock>

            {/* Collapsible rich context input */}
            <div className="border-t pt-4">
              <button
                type="button"
                onClick={() => setShowContextInput(!showContextInput)}
                className="flex w-full items-center justify-between text-sm font-medium text-slate-700 hover:text-slate-900"
              >
                <div className="flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-amber-500" />
                  <span>Add project context for AI seeding</span>
                  <span className="text-xs font-normal text-muted-foreground">(optional)</span>
                </div>
                {showContextInput ? (
                  <ChevronUp className="h-4 w-4" />
                ) : (
                  <ChevronDown className="h-4 w-4" />
                )}
              </button>

              {showContextInput && (
                <div className="mt-3 space-y-2">
                  <p className="text-xs text-muted-foreground">
                    Describe your project, target audience, problem being solved, or vision.
                    AI will automatically generate foundational anchors from this context.
                  </p>
                  <Textarea
                    placeholder="e.g., We're building a SaaS analytics platform for marketing teams. Main problem is they spend too much time on manual reporting. Target: mid-market B2B companies..."
                    value={projectContext}
                    onChange={(e) => setProjectContext(e.target.value)}
                    rows={5}
                    className="resize-none text-sm"
                    maxLength={3000}
                  />
                  <p className="text-xs text-muted-foreground text-right">
                    {projectContext.length}/3000
                  </p>
                </div>
              )}
            </div>
          </section>

          {error && (
            <div className="flex items-center gap-2 rounded border border-destructive/50 bg-destructive/10 p-3 text-sm text-destructive">
              <AlertCircle className="h-4 w-4" />
              <span>{error}</span>
            </div>
          )}

          {success && (
            <div className="flex items-center gap-2 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">
              <CheckCircle2 className="h-4 w-4" />
              <span>Project created successfully. Redirecting…</span>
            </div>
          )}
        </div>

        <DialogFooter>
          <Button type="button" variant="ghost" onClick={() => handleClose(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button type="button" onClick={handleSubmit} disabled={!canSubmit || submitting}>
            {submitting ? (
              <span className="inline-flex items-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin" />
                Creating…
              </span>
            ) : (
              'Create Project'
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function FieldBlock({
  label,
  hint,
  required,
  children,
}: {
  label: string;
  hint?: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2 text-sm font-medium text-slate-800">
        <Label className={cn('text-sm font-medium text-slate-800', required && 'after:ml-1 after:text-destructive after:content-["*"]')}>
          {label}
        </Label>
        {hint && <span className="text-xs text-muted-foreground">{hint}</span>}
      </div>
      {children}
    </div>
  );
}
