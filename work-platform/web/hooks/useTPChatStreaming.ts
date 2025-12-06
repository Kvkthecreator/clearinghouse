"use client";

/**
 * useTPChatStreaming - Enhanced chat hook with streaming support
 *
 * Features:
 * - Optimistic message updates
 * - Server-Sent Events (SSE) streaming for responses
 * - Fallback to non-streaming when streaming not available
 * - Real-time typing indicator
 * - Rich message enrichment (context changes, work outputs)
 *
 * Part of Chat-First Architecture v1.0
 * See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
 */

import { useCallback, useState, useRef, useEffect } from "react";
import type {
  TPMessage,
  TPChatRequest,
  TPChatResponse,
  TPToolCall,
  TPContextChange,
  WorkOutput,
  TPContextChangeRich,
  TPWorkOutputPreview,
  TPRecipeExecution,
  TPExecutionStep,
} from "@/lib/types/thinking-partner";

// ============================================================================
// Types
// ============================================================================

export interface StreamingChunk {
  type: 'text' | 'tool_start' | 'tool_result' | 'context_change' | 'work_output' | 'recipe_progress' | 'done' | 'error';
  content?: string;
  data?: Record<string, unknown>;
}

// Extended tool call for streaming (includes tracking id)
interface StreamingToolCall extends TPToolCall {
  _streamId?: string;
}

export interface TPStreamingState {
  isStreaming: boolean;
  currentText: string;
  pendingToolCalls: StreamingToolCall[];
  pendingContextChanges: TPContextChangeRich[];
  pendingWorkOutputs: TPWorkOutputPreview[];
  currentRecipeExecution?: TPRecipeExecution;
  currentExecutionSteps: TPExecutionStep[];
}

export interface UseTPChatStreamingOptions {
  /** Basket ID */
  basketId: string;
  /** Initial session ID (optional) */
  sessionId?: string | null;
  /** Initial messages */
  initialMessages?: TPMessage[];
  /** Enable streaming (if server supports it) */
  enableStreaming?: boolean;
  /** Callback when context changes */
  onContextChange?: (changes: TPContextChangeRich[]) => void;
  /** Callback when work outputs are created */
  onWorkOutput?: (outputs: TPWorkOutputPreview[]) => void;
  /** Callback when recipe execution updates */
  onRecipeProgress?: (execution: TPRecipeExecution) => void;
}

// ============================================================================
// useTPChatStreaming
// ============================================================================

export function useTPChatStreaming(options: UseTPChatStreamingOptions) {
  const {
    basketId,
    sessionId: initialSessionId = null,
    initialMessages = [],
    enableStreaming = true,
    onContextChange,
    onWorkOutput,
    onRecipeProgress,
  } = options;

  // Core state
  const [messages, setMessages] = useState<TPMessage[]>(initialMessages);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(initialSessionId);

  // Streaming state
  const [streamingState, setStreamingState] = useState<TPStreamingState>({
    isStreaming: false,
    currentText: '',
    pendingToolCalls: [],
    pendingContextChanges: [],
    pendingWorkOutputs: [],
    currentExecutionSteps: [],
  });

  // Stream abort controller
  const abortControllerRef = useRef<AbortController | null>(null);

  // Last response metadata (for non-streaming compatibility)
  const [lastToolCalls, setLastToolCalls] = useState<TPToolCall[]>([]);
  const [lastContextChanges, setLastContextChanges] = useState<TPContextChangeRich[]>([]);
  const [lastWorkOutputs, setLastWorkOutputs] = useState<TPWorkOutputPreview[]>([]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      abortControllerRef.current?.abort();
    };
  }, []);

  /**
   * Parse SSE stream chunk
   */
  const parseStreamChunk = useCallback((line: string): StreamingChunk | null => {
    if (!line.startsWith('data: ')) return null;

    const data = line.slice(6);
    if (data === '[DONE]') {
      return { type: 'done' };
    }

    try {
      return JSON.parse(data);
    } catch {
      // Plain text chunk
      return { type: 'text', content: data };
    }
  }, []);

  /**
   * Send message with streaming
   */
  const sendMessageStreaming = useCallback(async (content: string): Promise<void> => {
    if (!content.trim()) return;

    // Create optimistic user message
    const userMessage: TPMessage = {
      id: `temp-${Date.now()}`,
      session_id: sessionId || '',
      role: 'user',
      content: content.trim(),
      created_at: new Date().toISOString(),
    };

    // Add user message immediately
    setMessages(prev => [...prev, userMessage]);
    setIsLoading(true);
    setError(null);

    // Initialize streaming state
    setStreamingState({
      isStreaming: true,
      currentText: '',
      pendingToolCalls: [],
      pendingContextChanges: [],
      pendingWorkOutputs: [],
      currentExecutionSteps: [],
    });

    // Create placeholder assistant message
    const assistantMessageId = `temp-assistant-${Date.now()}`;
    const placeholderMessage: TPMessage = {
      id: assistantMessageId,
      session_id: sessionId || '',
      role: 'assistant',
      content: '',
      created_at: new Date().toISOString(),
    };
    setMessages(prev => [...prev, placeholderMessage]);

    // Setup abort controller
    abortControllerRef.current = new AbortController();

    try {
      const request: TPChatRequest = {
        basket_id: basketId,
        message: content.trim(),
        session_id: sessionId,
      };

      const response = await fetch('/api/tp/chat/stream', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
        signal: abortControllerRef.current.signal,
      });

      if (!response.ok) {
        // Fallback to non-streaming if streaming endpoint not available
        if (response.status === 404) {
          console.log('[TPChat] Streaming not available, falling back to non-streaming');
          // Remove placeholder and use non-streaming
          setMessages(prev => prev.filter(m => m.id !== assistantMessageId));
          setStreamingState(prev => ({ ...prev, isStreaming: false }));
          await sendMessageNonStreaming(content, userMessage);
          return;
        }

        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.detail || 'Failed to send message');
      }

      if (!response.body) {
        throw new Error('No response body');
      }

      // Read SSE stream
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let fullText = '';
      const collectedToolCalls: TPToolCall[] = [];
      const collectedContextChanges: TPContextChangeRich[] = [];
      const collectedWorkOutputs: TPWorkOutputPreview[] = [];
      const collectedExecutionSteps: TPExecutionStep[] = [];
      let recipeExecution: TPRecipeExecution | undefined;
      let newSessionId = sessionId;
      let messageId = assistantMessageId;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          const chunk = parseStreamChunk(line);
          if (!chunk) continue;

          switch (chunk.type) {
            case 'text':
              fullText += chunk.content || '';
              setStreamingState(prev => ({
                ...prev,
                currentText: fullText,
              }));
              // Update placeholder message content
              setMessages(prev => prev.map(m =>
                m.id === assistantMessageId
                  ? { ...m, content: fullText }
                  : m
              ));
              break;

            case 'tool_start':
              if (chunk.data) {
                const streamId = chunk.data.id as string || `tool-${Date.now()}`;
                const toolCall: StreamingToolCall = {
                  _streamId: streamId,
                  name: chunk.data.name as string,
                  input: chunk.data.input as Record<string, unknown> || {},
                };
                setStreamingState(prev => ({
                  ...prev,
                  pendingToolCalls: [...prev.pendingToolCalls, toolCall],
                }));
              }
              break;

            case 'tool_result':
              if (chunk.data) {
                const streamId = chunk.data.id as string;
                const completedCall: TPToolCall = {
                  name: chunk.data.name as string,
                  input: chunk.data.input as Record<string, unknown> || {},
                  result: chunk.data.result as Record<string, unknown>,
                };
                collectedToolCalls.push(completedCall);
                setStreamingState(prev => ({
                  ...prev,
                  pendingToolCalls: prev.pendingToolCalls.filter(t => t._streamId !== streamId),
                }));
              }
              break;

            case 'context_change':
              if (chunk.data) {
                // Build rich context change from stream data
                const change: TPContextChangeRich = {
                  item_type: chunk.data.item_type as string || 'unknown',
                  action: (chunk.data.action as TPContextChangeRich['action']) || 'written',
                  item_id: chunk.data.item_id as string,
                  title: chunk.data.title as string,
                  tier: chunk.data.tier as TPContextChangeRich['tier'],
                  preview: chunk.data.preview as string,
                  completeness_score: chunk.data.completeness_score as number,
                };
                collectedContextChanges.push(change);
                setStreamingState(prev => ({
                  ...prev,
                  pendingContextChanges: [...prev.pendingContextChanges, change],
                }));
              }
              break;

            case 'work_output':
              if (chunk.data) {
                // Build work output preview from stream data
                const output: TPWorkOutputPreview = {
                  id: chunk.data.id as string || `output-${Date.now()}`,
                  output_type: chunk.data.output_type as string || 'finding',
                  title: chunk.data.title as string,
                  body_preview: chunk.data.body_preview as string,
                  supervision_status: (chunk.data.supervision_status as TPWorkOutputPreview['supervision_status']) || 'pending_review',
                  confidence: chunk.data.confidence as number,
                  agent_type: chunk.data.agent_type as string,
                  created_at: chunk.data.created_at as string || new Date().toISOString(),
                };
                collectedWorkOutputs.push(output);
                setStreamingState(prev => ({
                  ...prev,
                  pendingWorkOutputs: [...prev.pendingWorkOutputs, output],
                }));
              }
              break;

            case 'recipe_progress':
              if (chunk.data) {
                // Build recipe execution from stream data
                recipeExecution = {
                  recipe_slug: chunk.data.recipe_slug as string || 'unknown',
                  recipe_name: chunk.data.recipe_name as string,
                  ticket_id: chunk.data.ticket_id as string || '',
                  status: (chunk.data.status as TPRecipeExecution['status']) || 'running',
                  progress_pct: chunk.data.progress_pct as number,
                  current_step: chunk.data.current_step as string,
                };
                if (chunk.data.current_step) {
                  const step: TPExecutionStep = {
                    step_number: collectedExecutionSteps.length + 1,
                    description: chunk.data.current_step as string,
                    status: chunk.data.status === 'completed' ? 'completed' : 'running',
                  };
                  collectedExecutionSteps.push(step);
                }
                setStreamingState(prev => ({
                  ...prev,
                  currentRecipeExecution: recipeExecution,
                  currentExecutionSteps: collectedExecutionSteps,
                }));
                onRecipeProgress?.(recipeExecution);
              }
              break;

            case 'done':
              if (chunk.data) {
                newSessionId = chunk.data.session_id as string || sessionId;
                messageId = chunk.data.message_id as string || assistantMessageId;
              }
              break;

            case 'error':
              throw new Error(chunk.content || 'Stream error');
          }
        }
      }

      // Finalize message
      setSessionId(newSessionId);
      setMessages(prev => prev.map(m => {
        if (m.id === userMessage.id) {
          return { ...m, session_id: newSessionId || '' };
        }
        if (m.id === assistantMessageId) {
          return {
            ...m,
            id: messageId,
            session_id: newSessionId || '',
            content: fullText,
            tool_calls: collectedToolCalls,
            context_changes: collectedContextChanges,
            work_outputs: collectedWorkOutputs,
            recipe_execution: recipeExecution,
            execution_steps: collectedExecutionSteps,
          };
        }
        return m;
      }));

      // Update last metadata
      setLastToolCalls(collectedToolCalls);
      setLastContextChanges(collectedContextChanges);
      setLastWorkOutputs(collectedWorkOutputs);

      // Fire callbacks
      if (collectedContextChanges.length > 0) {
        onContextChange?.(collectedContextChanges);
      }
      if (collectedWorkOutputs.length > 0) {
        onWorkOutput?.(collectedWorkOutputs);
      }

    } catch (err) {
      if (err instanceof Error && err.name === 'AbortError') {
        // User cancelled
        console.log('[TPChat] Stream aborted by user');
      } else {
        const message = err instanceof Error ? err.message : 'Unknown error';
        setError(message);
        // Remove placeholder on error
        setMessages(prev => prev.filter(m =>
          m.id !== assistantMessageId && m.id !== userMessage.id
        ));
      }
    } finally {
      setIsLoading(false);
      setStreamingState(prev => ({ ...prev, isStreaming: false }));
      abortControllerRef.current = null;
    }
  }, [basketId, sessionId, parseStreamChunk, onContextChange, onWorkOutput, onRecipeProgress]);

  /**
   * Send message without streaming (fallback)
   */
  const sendMessageNonStreaming = useCallback(async (
    content: string,
    existingUserMessage?: TPMessage
  ): Promise<{ success: boolean; error?: string }> => {
    const userMessage = existingUserMessage || {
      id: `temp-${Date.now()}`,
      session_id: sessionId || '',
      role: 'user' as const,
      content: content.trim(),
      created_at: new Date().toISOString(),
    };

    if (!existingUserMessage) {
      setMessages(prev => [...prev, userMessage]);
    }

    setIsLoading(true);
    setError(null);

    try {
      const request: TPChatRequest = {
        basket_id: basketId,
        message: content.trim(),
        session_id: sessionId,
      };

      const response = await fetch('/api/tp/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        const errorMessage = errorData.detail || 'Failed to send message';
        setError(errorMessage);
        setMessages(prev => prev.filter(m => m.id !== userMessage.id));
        return { success: false, error: errorMessage };
      }

      const data: TPChatResponse = await response.json();

      // Update session ID
      setSessionId(data.session_id);

      // Create assistant message with rich data
      // Note: WorkOutput uses camelCase (outputType, createdAt), TPContextChange uses snake_case
      const assistantMessage: TPMessage = {
        id: data.message_id,
        session_id: data.session_id,
        role: 'assistant',
        content: data.message,
        tool_calls: data.tool_calls,
        work_output_ids: data.work_outputs.map(wo => wo.id),
        // Enrich with v3.0 fields - use rich versions if available
        context_changes: data.context_changes_rich || data.context_changes?.map(c => ({
          item_type: c.item_type,
          action: c.action || 'written',
        })) as TPContextChangeRich[] | undefined,
        // Convert WorkOutput (camelCase) to TPWorkOutputPreview (snake_case)
        work_outputs: data.work_output_previews || data.work_outputs?.map(wo => ({
          id: wo.id,
          output_type: wo.outputType || 'finding',
          title: wo.title,
          body_preview: wo.body?.slice(0, 200),
          supervision_status: 'pending_review' as const,
          confidence: wo.confidence,
          created_at: wo.createdAt || new Date().toISOString(),
        })) as TPWorkOutputPreview[] | undefined,
        recipe_execution: data.recipe_execution,
        execution_steps: data.execution_steps,
        tp_phase: data.tp_phase,
        created_at: new Date().toISOString(),
      };

      // Replace temp user message and add assistant message
      setMessages(prev => [
        ...prev.filter(m => m.id !== userMessage.id),
        { ...userMessage, session_id: data.session_id },
        assistantMessage,
      ]);

      // Update last metadata
      setLastToolCalls(data.tool_calls);
      const richContextChanges = data.context_changes_rich || data.context_changes as TPContextChangeRich[];
      setLastContextChanges(richContextChanges);
      const richWorkOutputs = (assistantMessage.work_outputs || []) as TPWorkOutputPreview[];
      setLastWorkOutputs(richWorkOutputs);

      // Fire callbacks
      if (richContextChanges?.length > 0) {
        onContextChange?.(richContextChanges);
      }
      if (richWorkOutputs?.length > 0) {
        onWorkOutput?.(richWorkOutputs);
      }

      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      setMessages(prev => prev.filter(m => m.id !== userMessage.id));
      return { success: false, error: message };
    } finally {
      setIsLoading(false);
    }
  }, [basketId, sessionId, onContextChange, onWorkOutput]);

  /**
   * Send message (auto-selects streaming vs non-streaming)
   */
  const sendMessage = useCallback(async (content: string) => {
    if (enableStreaming) {
      await sendMessageStreaming(content);
      return { success: true };
    } else {
      return sendMessageNonStreaming(content);
    }
  }, [enableStreaming, sendMessageStreaming, sendMessageNonStreaming]);

  /**
   * Cancel current stream
   */
  const cancelStream = useCallback(() => {
    abortControllerRef.current?.abort();
  }, []);

  /**
   * Clear messages
   */
  const clearMessages = useCallback(() => {
    setMessages([]);
    setSessionId(null);
    setError(null);
    setLastToolCalls([]);
    setLastContextChanges([]);
    setLastWorkOutputs([]);
    setStreamingState({
      isStreaming: false,
      currentText: '',
      pendingToolCalls: [],
      pendingContextChanges: [],
      pendingWorkOutputs: [],
      currentExecutionSteps: [],
    });
  }, []);

  /**
   * Load messages from session
   */
  const loadMessages = useCallback((newMessages: TPMessage[], newSessionId: string) => {
    setMessages(newMessages);
    setSessionId(newSessionId);
    setError(null);
  }, []);

  return {
    // Core state
    messages,
    isLoading,
    error,
    sessionId,

    // Streaming state
    streamingState,
    isStreaming: streamingState.isStreaming,

    // Last response metadata
    lastToolCalls,
    lastContextChanges,
    lastWorkOutputs,

    // Actions
    sendMessage,
    cancelStream,
    clearMessages,
    loadMessages,
  };
}
