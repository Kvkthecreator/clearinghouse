'use client';

/**
 * ProjectLayoutClient - Client-side layout wrapper for project pages
 *
 * Provides:
 * - Main content area
 * - Thinking Partner sidebar (right panel)
 * - Page awareness context for TP
 *
 * See: /docs/architecture/ADR_CONTEXT_ENTRIES.md
 */

import type { ReactNode } from 'react';
import { TPSidebar } from '@/components/thinking/TPSidebar';

interface ProjectLayoutClientProps {
  projectId: string;
  basketId: string | null;
  workspaceId: string;
  children: ReactNode;
}

export default function ProjectLayoutClient({
  projectId,
  basketId,
  workspaceId,
  children,
}: ProjectLayoutClientProps) {
  // If no basket, just render children without sidebar
  if (!basketId) {
    return <div className="mx-auto">{children}</div>;
  }

  return (
    <div className="flex h-[calc(100vh-57px)]">
      {/* Main content area */}
      <main className="flex-1 overflow-y-auto">
        {children}
      </main>

      {/* Thinking Partner sidebar */}
      <TPSidebar
        projectId={projectId}
        basketId={basketId}
        workspaceId={workspaceId}
      />
    </div>
  );
}
