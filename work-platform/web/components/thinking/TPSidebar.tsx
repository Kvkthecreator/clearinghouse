'use client';

/**
 * TPSidebar - Right-hand Thinking Partner Panel
 *
 * A persistent sidebar that shows the Thinking Partner chat interface.
 * Features:
 * - Collapsible/expandable
 * - Page awareness (knows current route)
 * - Realtime updates for context changes and work tickets
 * - Navigation follows tool calls
 *
 * See: /docs/architecture/ADR_CONTEXT_ENTRIES.md
 */

import { useState, useEffect, useCallback } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { MessageSquare, ChevronRight, ChevronLeft, X, Loader2, Wifi, WifiOff } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { cn } from '@/lib/utils';
import { TPChatInterface } from './TPChatInterface';
import { useTPRealtimeSubscriptions } from '@/hooks/useTPRealtime';
import type { TPContextChange, WorkOutput } from '@/lib/types/thinking-partner';

interface TPSidebarProps {
  projectId: string;
  basketId: string;
  workspaceId: string;
  className?: string;
}

export function TPSidebar({
  projectId,
  basketId,
  workspaceId,
  className,
}: TPSidebarProps) {
  const [isOpen, setIsOpen] = useState(true);
  const [isMobile, setIsMobile] = useState(false);
  const pathname = usePathname();
  const router = useRouter();

  // Track current page for TP context awareness
  const currentPage = pathname?.split('/').pop() || 'overview';

  // Realtime subscriptions for live updates
  const { context, tickets, isFullyConnected } = useTPRealtimeSubscriptions(basketId, {
    onContextUpdate: (event) => {
      console.log('[TPSidebar] Realtime context update:', event);
      // Could show a toast notification here
    },
    onTicketUpdate: (event) => {
      console.log('[TPSidebar] Realtime ticket update:', event);
      // Could show a toast notification here
    },
  });

  // Mobile detection
  useEffect(() => {
    const checkMobile = () => {
      const mobile = window.innerWidth < 1024;
      setIsMobile(mobile);
      // Close sidebar on mobile by default
      if (mobile) {
        setIsOpen(false);
      }
    };

    checkMobile();
    window.addEventListener('resize', checkMobile);
    return () => window.removeEventListener('resize', checkMobile);
  }, []);

  // Handle context changes from TP - navigate to context page
  const handleContextChange = useCallback(
    (changes: TPContextChange[]) => {
      console.log('[TPSidebar] Context changes detected:', changes);

      // Navigate to context page when context is updated
      if (changes.length > 0 && currentPage !== 'context') {
        router.push(`/projects/${projectId}/context`);
      }
    },
    [projectId, currentPage, router]
  );

  // Handle work outputs from TP - navigate to work tickets
  const handleWorkOutput = useCallback(
    (outputs: WorkOutput[]) => {
      console.log('[TPSidebar] Work outputs detected:', outputs);

      // Navigate to work tickets when work is triggered
      if (outputs.length > 0 && currentPage !== 'work-tickets-view') {
        router.push(`/projects/${projectId}/work-tickets-view`);
      }
    },
    [projectId, currentPage, router]
  );

  // Handle TP state changes for UI feedback
  const handleTPStateChange = useCallback((phase: string) => {
    console.log('[TPSidebar] TP phase changed:', phase);
  }, []);

  // Collapsed state - just show toggle button
  if (!isOpen) {
    return (
      <div className={cn('fixed right-0 top-1/2 -translate-y-1/2 z-40', className)}>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setIsOpen(true)}
          className="rounded-l-lg rounded-r-none border-r-0 shadow-lg bg-card hover:bg-muted"
        >
          <MessageSquare className="h-5 w-5 mr-1" />
          <ChevronLeft className="h-4 w-4" />
        </Button>
      </div>
    );
  }

  return (
    <>
      {/* Mobile overlay */}
      {isMobile && isOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/40"
          onClick={() => setIsOpen(false)}
        />
      )}

      {/* Sidebar panel */}
      <aside
        className={cn(
          'h-full border-l border-border bg-card flex flex-col',
          isMobile
            ? 'fixed right-0 top-0 z-50 w-full max-w-md shadow-xl'
            : 'relative w-[400px] min-w-[320px] max-w-[480px]',
          className
        )}
      >
        {/* Header with collapse button */}
        <div className="flex items-center justify-between border-b border-border bg-card/80 backdrop-blur px-3 py-2">
          <div className="flex items-center gap-2">
            <MessageSquare className="h-4 w-4 text-primary" />
            <span className="text-sm font-medium">Thinking Partner</span>
            {/* Connection status indicator */}
            {isFullyConnected ? (
              <Wifi className="h-3 w-3 text-green-500" />
            ) : (
              <WifiOff className="h-3 w-3 text-muted-foreground" />
            )}
          </div>
          <div className="flex items-center gap-1">
            {/* Pending work indicator */}
            {tickets.hasPendingWork && (
              <div className="flex items-center gap-1 text-xs text-amber-500 px-2 py-1 bg-amber-500/10 rounded">
                <Loader2 className="h-3 w-3 animate-spin" />
                <span>{tickets.pendingTickets.length} working</span>
              </div>
            )}
            {/* Page indicator */}
            <span className="text-xs text-muted-foreground px-2 py-1 bg-muted rounded">
              {currentPage}
            </span>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setIsOpen(false)}
              className="h-7 w-7 p-0"
            >
              {isMobile ? (
                <X className="h-4 w-4" />
              ) : (
                <ChevronRight className="h-4 w-4" />
              )}
            </Button>
          </div>
        </div>

        {/* Chat interface */}
        <div className="flex-1 overflow-hidden">
          <TPChatInterface
            basketId={basketId}
            workspaceId={workspaceId}
            className="h-full"
            onTPStateChange={handleTPStateChange}
            onContextChange={handleContextChange}
            onWorkOutput={handleWorkOutput}
          />
        </div>
      </aside>
    </>
  );
}
