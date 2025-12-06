"use client";

/**
 * useTPRealtimeEnhanced - Enhanced realtime subscriptions for Chat-First
 *
 * Provides unified realtime updates for:
 * - Context items changes
 * - Work tickets progress
 * - Work outputs (new)
 * - TP message sync (multi-device)
 *
 * Enhanced features:
 * - Batched updates to reduce re-renders
 * - Optimistic update matching
 * - Connection recovery
 *
 * Part of Chat-First Architecture v1.0
 * See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
 */

import { useEffect, useState, useCallback, useRef, useMemo } from "react";
import { createBrowserClient } from "@/lib/supabase/clients";
import type { RealtimeChannel, RealtimePostgresChangesPayload } from "@supabase/supabase-js";
import type {
  TPContextChangeRich,
  TPWorkOutputPreview,
} from "@/lib/types/thinking-partner";

// ============================================================================
// Types
// ============================================================================

export type RealtimeEventType = 'INSERT' | 'UPDATE' | 'DELETE';

export interface RealtimeUpdate<T> {
  type: RealtimeEventType;
  table: string;
  data: T;
  old?: T;
  timestamp: string;
}

export interface ContextItemUpdate {
  id: string;
  item_type: string;
  title?: string;
  tier: 'foundation' | 'working' | 'ephemeral';
  status: string;
  completeness_score?: number;
  updated_at: string;
}

export interface WorkTicketUpdate {
  id: string;
  status: 'queued' | 'running' | 'completed' | 'failed' | 'cancelled';
  recipe_slug?: string;
  agent_type?: string;
  progress_pct?: number;
  current_step?: string;
  created_at: string;
  completed_at?: string;
}

export interface WorkOutputUpdate {
  id: string;
  output_type: string;
  title?: string;
  supervision_status: string;
  confidence?: number;
  agent_type?: string;
  ticket_id?: string;
  created_at: string;
}

export interface TPMessageUpdate {
  id: string;
  session_id: string;
  role: string;
  content: string;
  tool_calls?: unknown[];
  work_output_ids?: string[];
  created_at: string;
}

export interface RealtimeState {
  // Connection state
  isConnected: boolean;
  isReconnecting: boolean;
  connectionError?: string;

  // Latest updates by type
  latestContextUpdate?: RealtimeUpdate<ContextItemUpdate>;
  latestTicketUpdate?: RealtimeUpdate<WorkTicketUpdate>;
  latestOutputUpdate?: RealtimeUpdate<WorkOutputUpdate>;
  latestMessageUpdate?: RealtimeUpdate<TPMessageUpdate>;

  // Active items for quick access
  activeTickets: WorkTicketUpdate[];
  pendingOutputs: WorkOutputUpdate[];
  recentContextChanges: ContextItemUpdate[];
}

export interface UseTPRealtimeEnhancedOptions {
  basketId: string;
  sessionId?: string | null;

  // Callbacks for updates
  onContextUpdate?: (update: RealtimeUpdate<ContextItemUpdate>) => void;
  onTicketUpdate?: (update: RealtimeUpdate<WorkTicketUpdate>) => void;
  onOutputUpdate?: (update: RealtimeUpdate<WorkOutputUpdate>) => void;
  onMessageUpdate?: (update: RealtimeUpdate<TPMessageUpdate>) => void;

  // Options
  batchUpdates?: boolean;
  batchDelayMs?: number;
  enableMessageSync?: boolean;
}

// ============================================================================
// useTPRealtimeEnhanced
// ============================================================================

export function useTPRealtimeEnhanced(options: UseTPRealtimeEnhancedOptions) {
  const {
    basketId,
    sessionId,
    onContextUpdate,
    onTicketUpdate,
    onOutputUpdate,
    onMessageUpdate,
    batchUpdates = true,
    batchDelayMs = 100,
    enableMessageSync = false,
  } = options;

  // State
  const [state, setState] = useState<RealtimeState>({
    isConnected: false,
    isReconnecting: false,
    activeTickets: [],
    pendingOutputs: [],
    recentContextChanges: [],
  });

  // Refs for callbacks (avoid re-subscribing)
  const callbacksRef = useRef({
    onContextUpdate,
    onTicketUpdate,
    onOutputUpdate,
    onMessageUpdate,
  });
  callbacksRef.current = {
    onContextUpdate,
    onTicketUpdate,
    onOutputUpdate,
    onMessageUpdate,
  };

  // Batch update buffer
  const updateBufferRef = useRef<{
    context: RealtimeUpdate<ContextItemUpdate>[];
    tickets: RealtimeUpdate<WorkTicketUpdate>[];
    outputs: RealtimeUpdate<WorkOutputUpdate>[];
    messages: RealtimeUpdate<TPMessageUpdate>[];
  }>({
    context: [],
    tickets: [],
    outputs: [],
    messages: [],
  });

  // Batch flush function
  const flushUpdates = useCallback(() => {
    const buffer = updateBufferRef.current;

    // Process context updates
    if (buffer.context.length > 0) {
      const updates = [...buffer.context];
      buffer.context = [];

      setState(prev => ({
        ...prev,
        latestContextUpdate: updates[updates.length - 1],
        recentContextChanges: [
          ...updates.map(u => u.data),
          ...prev.recentContextChanges,
        ].slice(0, 20),
      }));

      updates.forEach(update => {
        callbacksRef.current.onContextUpdate?.(update);
      });
    }

    // Process ticket updates
    if (buffer.tickets.length > 0) {
      const updates = [...buffer.tickets];
      buffer.tickets = [];

      setState(prev => {
        let activeTickets = [...prev.activeTickets];

        updates.forEach(update => {
          const ticket = update.data;
          const isActive = ['queued', 'running'].includes(ticket.status);

          if (update.type === 'INSERT' && isActive) {
            activeTickets = [ticket, ...activeTickets];
          } else if (update.type === 'UPDATE') {
            if (isActive) {
              const idx = activeTickets.findIndex(t => t.id === ticket.id);
              if (idx >= 0) {
                activeTickets[idx] = ticket;
              } else {
                activeTickets = [ticket, ...activeTickets];
              }
            } else {
              activeTickets = activeTickets.filter(t => t.id !== ticket.id);
            }
          } else if (update.type === 'DELETE') {
            activeTickets = activeTickets.filter(t => t.id !== ticket.id);
          }
        });

        return {
          ...prev,
          latestTicketUpdate: updates[updates.length - 1],
          activeTickets,
        };
      });

      updates.forEach(update => {
        callbacksRef.current.onTicketUpdate?.(update);
      });
    }

    // Process output updates
    if (buffer.outputs.length > 0) {
      const updates = [...buffer.outputs];
      buffer.outputs = [];

      setState(prev => {
        let pendingOutputs = [...prev.pendingOutputs];

        updates.forEach(update => {
          const output = update.data;
          const isPending = output.supervision_status === 'pending_review';

          if (update.type === 'INSERT' && isPending) {
            pendingOutputs = [output, ...pendingOutputs];
          } else if (update.type === 'UPDATE') {
            if (isPending) {
              const idx = pendingOutputs.findIndex(o => o.id === output.id);
              if (idx >= 0) {
                pendingOutputs[idx] = output;
              }
            } else {
              pendingOutputs = pendingOutputs.filter(o => o.id !== output.id);
            }
          }
        });

        return {
          ...prev,
          latestOutputUpdate: updates[updates.length - 1],
          pendingOutputs,
        };
      });

      updates.forEach(update => {
        callbacksRef.current.onOutputUpdate?.(update);
      });
    }

    // Process message updates
    if (buffer.messages.length > 0) {
      const updates = [...buffer.messages];
      buffer.messages = [];

      setState(prev => ({
        ...prev,
        latestMessageUpdate: updates[updates.length - 1],
      }));

      updates.forEach(update => {
        callbacksRef.current.onMessageUpdate?.(update);
      });
    }
  }, []);

  // Batch timer
  const batchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const queueUpdate = useCallback((
    type: 'context' | 'tickets' | 'outputs' | 'messages',
    update: RealtimeUpdate<unknown>
  ) => {
    (updateBufferRef.current[type] as RealtimeUpdate<unknown>[]).push(update);

    if (batchUpdates) {
      if (batchTimerRef.current) {
        clearTimeout(batchTimerRef.current);
      }
      batchTimerRef.current = setTimeout(flushUpdates, batchDelayMs);
    } else {
      flushUpdates();
    }
  }, [batchUpdates, batchDelayMs, flushUpdates]);

  // Channel refs
  const channelsRef = useRef<RealtimeChannel[]>([]);

  // Setup subscriptions
  useEffect(() => {
    if (!basketId) return;

    const supabase = createBrowserClient();

    // Cleanup previous channels
    channelsRef.current.forEach(ch => ch.unsubscribe());
    channelsRef.current = [];

    // Track connection state
    let connectedCount = 0;
    const totalChannels = enableMessageSync && sessionId ? 4 : 3;

    const handleSubscriptionStatus = (status: string) => {
      if (status === 'SUBSCRIBED') {
        connectedCount++;
        if (connectedCount === totalChannels) {
          setState(prev => ({
            ...prev,
            isConnected: true,
            isReconnecting: false,
            connectionError: undefined,
          }));
        }
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        setState(prev => ({
          ...prev,
          isConnected: false,
          isReconnecting: true,
          connectionError: `Subscription error: ${status}`,
        }));
      }
    };

    // Context items channel
    const contextChannel = supabase
      .channel(`context_items_enhanced_${basketId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'context_items',
          filter: `basket_id=eq.${basketId}`,
        },
        (payload: RealtimePostgresChangesPayload<ContextItemUpdate>) => {
          const update: RealtimeUpdate<ContextItemUpdate> = {
            type: payload.eventType as RealtimeEventType,
            table: 'context_items',
            data: payload.new as ContextItemUpdate,
            old: payload.old as ContextItemUpdate | undefined,
            timestamp: new Date().toISOString(),
          };
          queueUpdate('context', update);
        }
      )
      .subscribe(handleSubscriptionStatus);

    channelsRef.current.push(contextChannel);

    // Work tickets channel
    const ticketsChannel = supabase
      .channel(`work_tickets_enhanced_${basketId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'work_tickets',
          filter: `basket_id=eq.${basketId}`,
        },
        (payload: RealtimePostgresChangesPayload<WorkTicketUpdate>) => {
          const update: RealtimeUpdate<WorkTicketUpdate> = {
            type: payload.eventType as RealtimeEventType,
            table: 'work_tickets',
            data: payload.new as WorkTicketUpdate,
            old: payload.old as WorkTicketUpdate | undefined,
            timestamp: new Date().toISOString(),
          };
          queueUpdate('tickets', update);
        }
      )
      .subscribe(handleSubscriptionStatus);

    channelsRef.current.push(ticketsChannel);

    // Work outputs channel (new in Phase 4)
    const outputsChannel = supabase
      .channel(`work_outputs_${basketId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'work_outputs',
          filter: `basket_id=eq.${basketId}`,
        },
        (payload: RealtimePostgresChangesPayload<WorkOutputUpdate>) => {
          const update: RealtimeUpdate<WorkOutputUpdate> = {
            type: payload.eventType as RealtimeEventType,
            table: 'work_outputs',
            data: payload.new as WorkOutputUpdate,
            old: payload.old as WorkOutputUpdate | undefined,
            timestamp: new Date().toISOString(),
          };
          queueUpdate('outputs', update);
        }
      )
      .subscribe(handleSubscriptionStatus);

    channelsRef.current.push(outputsChannel);

    // TP messages channel (optional, for multi-device sync)
    if (enableMessageSync && sessionId) {
      const messagesChannel = supabase
        .channel(`tp_messages_sync_${sessionId}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'tp_messages',
            filter: `session_id=eq.${sessionId}`,
          },
          (payload: RealtimePostgresChangesPayload<TPMessageUpdate>) => {
            const update: RealtimeUpdate<TPMessageUpdate> = {
              type: 'INSERT',
              table: 'tp_messages',
              data: payload.new as TPMessageUpdate,
              timestamp: new Date().toISOString(),
            };
            queueUpdate('messages', update);
          }
        )
        .subscribe(handleSubscriptionStatus);

      channelsRef.current.push(messagesChannel);
    }

    // Cleanup
    return () => {
      if (batchTimerRef.current) {
        clearTimeout(batchTimerRef.current);
      }
      channelsRef.current.forEach(ch => ch.unsubscribe());
      channelsRef.current = [];
    };
  }, [basketId, sessionId, enableMessageSync, queueUpdate]);

  // Derived values
  const hasActiveWork = useMemo(() => {
    return state.activeTickets.length > 0;
  }, [state.activeTickets]);

  const hasPendingReview = useMemo(() => {
    return state.pendingOutputs.length > 0;
  }, [state.pendingOutputs]);

  const runningTicketsCount = useMemo(() => {
    return state.activeTickets.filter(t => t.status === 'running').length;
  }, [state.activeTickets]);

  return {
    // State
    ...state,

    // Derived
    hasActiveWork,
    hasPendingReview,
    runningTicketsCount,
  };
}

// ============================================================================
// Simplified combined hook for common use case
// ============================================================================

export function useTPRealtimeSimple(basketId: string) {
  return useTPRealtimeEnhanced({
    basketId,
    batchUpdates: true,
    batchDelayMs: 100,
  });
}
