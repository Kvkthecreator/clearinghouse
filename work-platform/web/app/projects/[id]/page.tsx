import { redirect } from 'next/navigation';

interface PageProps {
  params: Promise<{ id: string }>;
}

/**
 * Legacy project root: redirect to Thinking Partner agent view for consistency
 */
export default async function ProjectPage({ params }: PageProps) {
  const { id: projectId } = await params;
  redirect(`/projects/${projectId}/agents/thinking`);
}
