'use client';

/**
 * TPChatInterface (v3.0 - Desktop UI)
 *
 * Main chat interface for Thinking Partner.
 * Updated for Desktop UI with floating windows and tool-triggered window opening.
 *
 * See:
 * - /docs/implementation/THINKING_PARTNER_IMPLEMENTATION_PLAN.md
 * - /docs/implementation/DESKTOP_UI_IMPLEMENTATION_PLAN.md
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import { Send, Loader2, Plus, History, X } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Textarea } from '@/components/ui/Textarea';
import { cn } from '@/lib/utils';
import type { TPMessage, TPContextChange, WorkOutput } from '@/lib/types/thinking-partner';
import { useTPChat } from '@/hooks/useTPChat';
import { useActiveTPSession } from '@/hooks/useTPSession';
import { useTPToolWindowIntegration } from '@/hooks/useTPToolWindowIntegration';
import { TPMessageList } from './TPMessageList';
import { useChatFirstLayout } from './ChatFirstLayout';
import { useDesktopSafe } from '@/components/desktop/DesktopProvider';

interface TPChatInterfaceProps {
  basketId: string;
  workspaceId: string;
  className?: string;
  onTPStateChange?: (phase: string) => void;
  onContextChange?: (changes: TPContextChange[]) => void;
  onWorkOutput?: (outputs: WorkOutput[]) => void;
  // Navigation callbacks (can be provided or use ChatFirstLayout context)
  onNavigateToContext?: (itemId?: string) => void;
  onNavigateToOutput?: (outputId?: string) => void;
  onNavigateToTicket?: (ticketId?: string) => void;
  onViewAllContext?: () => void;
}

export function TPChatInterface({
  basketId,
  workspaceId,
  className,
  onTPStateChange,
  onContextChange,
  onWorkOutput,
  onNavigateToContext: propNavigateToContext,
  onNavigateToOutput: propNavigateToOutput,
  onNavigateToTicket: propNavigateToTicket,
  onViewAllContext: propViewAllContext,
}: TPChatInterfaceProps) {
  const [inputMessage, setInputMessage] = useState('');
  const [showSessionList, setShowSessionList] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Get layout context for navigation (fallback if not in ChatFirstLayout)
  const layoutContext = useChatFirstLayout();

  // Tool → Window integration (processes tool calls and opens/pulses windows)
  // This hook is safe to call even if not in DesktopProvider (returns no-op functions)
  const toolWindowIntegration = useTPToolWindowIntegration({
    autoOpen: false, // Don't auto-open, just pulse
    showPulse: true,
  });

  // Get Desktop context for window control (safe version that returns null if not available)
  const desktopContext = useDesktopSafe();

  // Navigation handlers - use props if provided, then Desktop context, then layout context
  const handleNavigateToContext = useCallback((itemId?: string) => {
    if (propNavigateToContext) {
      propNavigateToContext(itemId);
    } else if (desktopContext) {
      desktopContext.openWindow('context', itemId ? { itemIds: [itemId], action: 'reading' } : undefined);
    } else if (layoutContext.openDetailPanel) {
      layoutContext.openDetailPanel('context', itemId);
    }
  }, [propNavigateToContext, desktopContext, layoutContext]);

  const handleNavigateToOutput = useCallback((outputId?: string) => {
    if (propNavigateToOutput) {
      propNavigateToOutput(outputId);
    } else if (desktopContext) {
      desktopContext.openWindow('outputs', outputId ? { itemIds: [outputId], action: 'reading' } : undefined);
    } else if (layoutContext.openDetailPanel) {
      layoutContext.openDetailPanel('outputs', outputId);
    }
  }, [propNavigateToOutput, desktopContext, layoutContext]);

  const handleNavigateToTicket = useCallback((ticketId?: string) => {
    if (propNavigateToTicket) {
      propNavigateToTicket(ticketId);
    } else if (desktopContext) {
      desktopContext.openWindow('work', ticketId ? { itemIds: [ticketId], action: 'reading' } : undefined);
    } else if (layoutContext.openDetailPanel) {
      layoutContext.openDetailPanel('tickets', ticketId);
    }
  }, [propNavigateToTicket, desktopContext, layoutContext]);

  const handleViewAllContext = useCallback(() => {
    if (propViewAllContext) {
      propViewAllContext();
    } else if (desktopContext) {
      desktopContext.openWindow('context');
    } else if (layoutContext.openDetailPanel) {
      layoutContext.openDetailPanel('context');
    }
  }, [propViewAllContext, desktopContext, layoutContext]);

  // Session management
  const {
    sessionId,
    session,
    sessions,
    loading: sessionsLoading,
    startNewSession,
    switchSession,
    archiveCurrentSession,
  } = useActiveTPSession(basketId);

  // Wrap context/output callbacks to integrate with Desktop windows
  const handleContextChange = useCallback((changes: TPContextChange[]) => {
    // Process context changes for window badges/pulses
    toolWindowIntegration.processContextChanges(changes);
    // Call original callback
    onContextChange?.(changes);
  }, [toolWindowIntegration, onContextChange]);

  const handleWorkOutput = useCallback((outputs: WorkOutput[]) => {
    // Process work outputs for window badges/pulses
    toolWindowIntegration.processWorkOutputs(outputs);
    // Call original callback
    onWorkOutput?.(outputs);
  }, [toolWindowIntegration, onWorkOutput]);

  // Chat state
  const {
    messages,
    isLoading,
    error,
    sendMessage,
    clearMessages,
    loadMessages,
    lastContextChanges,
    lastWorkOutputs,
    lastToolCalls,
  } = useTPChat({
    basketId,
    sessionId,
    initialMessages: session?.messages || [],
    onContextChange: handleContextChange,
    onWorkOutput: handleWorkOutput,
  });

  // Process tool calls for window integration
  useEffect(() => {
    if (lastToolCalls.length > 0) {
      toolWindowIntegration.processToolCalls(lastToolCalls);
    }
  }, [lastToolCalls, toolWindowIntegration]);

  // Load messages when session changes
  useEffect(() => {
    if (session?.messages && sessionId) {
      loadMessages(session.messages, sessionId);
    }
  }, [session?.messages, sessionId, loadMessages]);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  // Notify parent of TP state changes
  useEffect(() => {
    if (lastWorkOutputs.length > 0) {
      onTPStateChange?.('reviewing');
    }
  }, [lastWorkOutputs, onTPStateChange]);

  const handleSendMessage = useCallback(async () => {
    if (!inputMessage.trim() || isLoading) {
      return;
    }

    const messageToSend = inputMessage.trim();
    setInputMessage('');

    await sendMessage(messageToSend);
  }, [inputMessage, isLoading, sendMessage]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Send on Enter (without Shift)
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSendMessage();
    }
  };

  const handleNewSession = async () => {
    clearMessages();
    await startNewSession();
    setShowSessionList(false);
  };

  const handleSwitchSession = async (newSessionId: string) => {
    switchSession(newSessionId);
    setShowSessionList(false);
  };

  return (
    <div className={cn('flex h-full flex-col bg-background', className)}>
      {/* Header */}
      <div className="border-b border-border bg-card p-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-foreground">
              Thinking Partner
            </h2>
            <p className="text-sm text-muted-foreground">
              Chat to manage context and orchestrate work
            </p>
          </div>
          <div className="flex items-center gap-2">
            {/* Session indicator */}
            {sessionId && (
              <div className="text-xs text-muted-foreground">
                {session?.title || `Session ${sessionId.slice(0, 8)}...`}
              </div>
            )}

            {/* Session history button */}
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowSessionList(!showSessionList)}
              className="relative"
            >
              <History className="h-4 w-4" />
              {sessions.length > 1 && (
                <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[10px] text-primary-foreground">
                  {sessions.length}
                </span>
              )}
            </Button>

            {/* New session button */}
            <Button variant="ghost" size="sm" onClick={handleNewSession}>
              <Plus className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Session list dropdown */}
        {showSessionList && sessions.length > 0 && (
          <div className="absolute right-4 top-16 z-50 w-64 rounded-lg border border-border bg-card shadow-lg">
            <div className="flex items-center justify-between border-b border-border p-3">
              <span className="text-sm font-medium">Recent Sessions</span>
              <Button
                variant="ghost"
                size="sm"
                className="h-6 w-6 p-0"
                onClick={() => setShowSessionList(false)}
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
            <div className="max-h-64 overflow-y-auto">
              {sessions.map((s) => (
                <button
                  key={s.id}
                  onClick={() => handleSwitchSession(s.id)}
                  className={cn(
                    'flex w-full items-start gap-3 p-3 text-left hover:bg-muted/50',
                    s.id === sessionId && 'bg-muted'
                  )}
                >
                  <div className="flex-1 min-w-0">
                    <div className="truncate text-sm font-medium">
                      {s.title || `Session ${s.id.slice(0, 8)}...`}
                    </div>
                    <div className="text-xs text-muted-foreground">
                      {s.message_count} messages
                    </div>
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {new Date(s.updated_at).toLocaleDateString()}
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4">
        <TPMessageList
          messages={messages}
          onNavigateToContext={handleNavigateToContext}
          onNavigateToOutput={handleNavigateToOutput}
          onNavigateToTicket={handleNavigateToTicket}
          onViewAllContext={handleViewAllContext}
        />
        <div ref={messagesEndRef} />

        {/* Loading indicator */}
        {isLoading && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Thinking Partner is processing...</span>
          </div>
        )}

        {/* Error message */}
        {error && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-600">
            {error}
          </div>
        )}

        {/* Empty state */}
        {messages.length === 0 && !isLoading && (
          <div className="flex h-full items-center justify-center text-center">
            <div className="max-w-md space-y-2">
              <h3 className="text-lg font-medium text-foreground">
                Start a conversation
              </h3>
              <p className="text-sm text-muted-foreground">
                Ask me to help with your project context, trigger research, or
                orchestrate work.
              </p>
              <div className="mt-4 space-y-2 text-xs text-muted-foreground">
                <p>
                  <strong>Examples:</strong>
                </p>
                <ul className="space-y-1 text-left">
                  <li>• "What context do we have so far?"</li>
                  <li>• "Help me define our target customer"</li>
                  <li>• "Research our main competitors"</li>
                  <li>• "What recipes are available?"</li>
                </ul>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Input */}
      <div className="border-t border-border bg-card p-4">
        <div className="flex gap-2">
          <Textarea
            value={inputMessage}
            onChange={(e) => setInputMessage(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask Thinking Partner..."
            className="min-h-[60px] max-h-[200px] resize-none"
            disabled={isLoading}
          />
          <Button
            onClick={handleSendMessage}
            disabled={!inputMessage.trim() || isLoading}
            className="self-end"
          >
            {isLoading ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Send className="h-4 w-4" />
            )}
          </Button>
        </div>
        <div className="mt-2 text-xs text-muted-foreground">
          Press <kbd className="rounded bg-muted px-1">Enter</kbd> to send,{' '}
          <kbd className="rounded bg-muted px-1">Shift+Enter</kbd> for new line
        </div>
      </div>
    </div>
  );
}
