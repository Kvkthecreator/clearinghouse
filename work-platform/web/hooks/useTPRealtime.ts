"use client";

/**
 * useTPRealtime - Realtime subscriptions for Thinking Partner sidebar
 *
 * Provides live updates for:
 * - Context items (when TP updates context)
 * - Work tickets (when recipes are triggered and executed)
 * - TP messages (optional - for multi-device sync)
 *
 * See: /docs/architecture/ADR_CONTEXT_ENTRIES.md
 */

import { useEffect, useState, useCallback } from "react";
import { createBrowserClient } from "@/lib/supabase/clients";

// ============================================================================
// Types
// ============================================================================

export interface RealtimeContextItem {
  id: string;
  item_type: string;
  status: string;
  updated_at: string;
}

export interface RealtimeWorkTicket {
  id: string;
  status: string;
  agent_type: string;
  created_at: string;
  completed_at?: string;
  metadata?: Record<string, unknown>;
}

export interface RealtimeEvent<T> {
  type: 'INSERT' | 'UPDATE' | 'DELETE';
  data: T;
  timestamp: string;
}

// ============================================================================
// useContextItemsRealtime
// ============================================================================

export function useContextItemsRealtime(
  basketId: string,
  onUpdate?: (event: RealtimeEvent<RealtimeContextItem>) => void
) {
  const [lastUpdate, setLastUpdate] = useState<RealtimeEvent<RealtimeContextItem> | null>(null);
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    if (!basketId) return;

    const supabase = createBrowserClient();

    const channel = supabase
      .channel(`context_items_${basketId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'context_items',
          filter: `basket_id=eq.${basketId}`,
        },
        (payload) => {
          console.log('[TPRealtime] Context item event:', payload.eventType, payload.new);

          const event: RealtimeEvent<RealtimeContextItem> = {
            type: payload.eventType as 'INSERT' | 'UPDATE' | 'DELETE',
            data: payload.new as RealtimeContextItem,
            timestamp: new Date().toISOString(),
          };

          setLastUpdate(event);
          onUpdate?.(event);
        }
      )
      .subscribe((status) => {
        console.log('[TPRealtime] Context subscription status:', status);
        setIsConnected(status === 'SUBSCRIBED');
      });

    return () => {
      channel.unsubscribe();
    };
  }, [basketId, onUpdate]);

  return {
    lastUpdate,
    isConnected,
  };
}

// ============================================================================
// useWorkTicketsRealtime
// ============================================================================

export function useWorkTicketsRealtime(
  basketId: string,
  onUpdate?: (event: RealtimeEvent<RealtimeWorkTicket>) => void
) {
  const [lastUpdate, setLastUpdate] = useState<RealtimeEvent<RealtimeWorkTicket> | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [pendingTickets, setPendingTickets] = useState<RealtimeWorkTicket[]>([]);

  useEffect(() => {
    if (!basketId) return;

    const supabase = createBrowserClient();

    const channel = supabase
      .channel(`work_tickets_${basketId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'work_tickets',
          filter: `basket_id=eq.${basketId}`,
        },
        (payload) => {
          console.log('[TPRealtime] New work ticket:', payload.new);

          const event: RealtimeEvent<RealtimeWorkTicket> = {
            type: 'INSERT',
            data: payload.new as RealtimeWorkTicket,
            timestamp: new Date().toISOString(),
          };

          setLastUpdate(event);
          setPendingTickets(prev => [...prev, payload.new as RealtimeWorkTicket]);
          onUpdate?.(event);
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'work_tickets',
          filter: `basket_id=eq.${basketId}`,
        },
        (payload) => {
          console.log('[TPRealtime] Work ticket updated:', payload.new);

          const event: RealtimeEvent<RealtimeWorkTicket> = {
            type: 'UPDATE',
            data: payload.new as RealtimeWorkTicket,
            timestamp: new Date().toISOString(),
          };

          setLastUpdate(event);

          // Remove from pending if completed or failed
          const ticket = payload.new as RealtimeWorkTicket;
          if (['completed', 'failed', 'cancelled'].includes(ticket.status)) {
            setPendingTickets(prev => prev.filter(t => t.id !== ticket.id));
          } else {
            setPendingTickets(prev =>
              prev.map(t => t.id === ticket.id ? ticket : t)
            );
          }

          onUpdate?.(event);
        }
      )
      .subscribe((status) => {
        console.log('[TPRealtime] Tickets subscription status:', status);
        setIsConnected(status === 'SUBSCRIBED');
      });

    return () => {
      channel.unsubscribe();
    };
  }, [basketId, onUpdate]);

  return {
    lastUpdate,
    isConnected,
    pendingTickets,
    hasPendingWork: pendingTickets.length > 0,
  };
}

// ============================================================================
// useTPMessagesRealtime (optional - for multi-device sync)
// ============================================================================

export interface RealtimeTPMessage {
  id: string;
  session_id: string;
  role: string;
  content: string;
  created_at: string;
}

export function useTPMessagesRealtime(
  sessionId: string | null,
  onNewMessage?: (message: RealtimeTPMessage) => void
) {
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    if (!sessionId) return;

    const supabase = createBrowserClient();

    const channel = supabase
      .channel(`tp_messages_${sessionId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'tp_messages',
          filter: `session_id=eq.${sessionId}`,
        },
        (payload) => {
          console.log('[TPRealtime] New message:', payload.new);
          onNewMessage?.(payload.new as RealtimeTPMessage);
        }
      )
      .subscribe((status) => {
        console.log('[TPRealtime] Messages subscription status:', status);
        setIsConnected(status === 'SUBSCRIBED');
      });

    return () => {
      channel.unsubscribe();
    };
  }, [sessionId, onNewMessage]);

  return {
    isConnected,
  };
}

// ============================================================================
// Combined hook for full realtime experience
// ============================================================================

export function useTPRealtimeSubscriptions(
  basketId: string,
  options?: {
    onContextUpdate?: (event: RealtimeEvent<RealtimeContextItem>) => void;
    onTicketUpdate?: (event: RealtimeEvent<RealtimeWorkTicket>) => void;
  }
) {
  const context = useContextItemsRealtime(basketId, options?.onContextUpdate);
  const tickets = useWorkTicketsRealtime(basketId, options?.onTicketUpdate);

  return {
    context,
    tickets,
    isFullyConnected: context.isConnected && tickets.isConnected,
  };
}
