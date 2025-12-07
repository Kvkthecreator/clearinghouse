'use client';

/**
 * useTPToolWindowIntegration
 *
 * Hook that bridges TP tool calls to Desktop window actions.
 * Automatically opens/highlights relevant windows based on TP tool executions.
 *
 * Tool → Window Mapping:
 * - context_* tools → Context window (highlight items being read/written)
 * - agent_orchestration → Work window (show ticket creation)
 * - steps_planner → Work window (show planned workflow)
 * - governance_* → Outputs window (pending approvals)
 *
 * Part of Desktop UI Architecture v1.0
 * See: /docs/implementation/DESKTOP_UI_IMPLEMENTATION_PLAN.md
 */

import { useCallback, useRef } from 'react';
import { useDesktopSafe, type WindowId, type WindowHighlight } from '@/components/desktop/DesktopProvider';
import type { TPToolCall, TPContextChange, WorkOutput } from '@/lib/types/thinking-partner';

// ============================================================================
// Tool → Window Mapping
// ============================================================================

interface ToolWindowConfig {
  windowId: WindowId;
  action: WindowHighlight['action'];
  extractItemIds?: (input: Record<string, unknown>) => string[];
}

const TOOL_TO_WINDOW: Record<string, ToolWindowConfig> = {
  // Context tools
  context_read: {
    windowId: 'context',
    action: 'reading',
    extractItemIds: (input) => {
      if (typeof input.item_id === 'string') return [input.item_id];
      if (Array.isArray(input.item_ids)) return input.item_ids as string[];
      return [];
    },
  },
  context_write: {
    windowId: 'context',
    action: 'writing',
    extractItemIds: (input) => {
      if (typeof input.item_id === 'string') return [input.item_id];
      return [];
    },
  },
  context_search: {
    windowId: 'context',
    action: 'reading',
  },
  context_list: {
    windowId: 'context',
    action: 'reading',
  },

  // Work orchestration tools
  agent_orchestration: {
    windowId: 'work',
    action: 'using',
    extractItemIds: (input) => {
      if (typeof input.ticket_id === 'string') return [input.ticket_id];
      return [];
    },
  },
  steps_planner: {
    windowId: 'work',
    action: 'using',
  },
  run_recipe: {
    windowId: 'work',
    action: 'using',
    extractItemIds: (input) => {
      if (typeof input.ticket_id === 'string') return [input.ticket_id];
      return [];
    },
  },

  // Output tools
  governance_approve: {
    windowId: 'outputs',
    action: 'using',
    extractItemIds: (input) => {
      if (typeof input.output_id === 'string') return [input.output_id];
      return [];
    },
  },
  governance_reject: {
    windowId: 'outputs',
    action: 'using',
    extractItemIds: (input) => {
      if (typeof input.output_id === 'string') return [input.output_id];
      return [];
    },
  },

  // Recipe tools
  list_recipes: {
    windowId: 'recipes',
    action: 'reading',
  },
  get_recipe: {
    windowId: 'recipes',
    action: 'reading',
    extractItemIds: (input) => {
      if (typeof input.recipe_slug === 'string') return [input.recipe_slug];
      return [];
    },
  },
};

// ============================================================================
// Hook
// ============================================================================

export interface UseTPToolWindowIntegrationOptions {
  /** Whether to auto-open windows on tool calls */
  autoOpen?: boolean;
  /** Whether to show pulses on dock for background tool calls */
  showPulse?: boolean;
}

export function useTPToolWindowIntegration(
  options: UseTPToolWindowIntegrationOptions = {}
) {
  const { autoOpen = false, showPulse = true } = options;

  // Get Desktop context safely (may be null if not within DesktopProvider)
  const desktop = useDesktopSafe();

  // Track if we're in a TP response cycle
  const responseInProgressRef = useRef(false);

  /**
   * Process a single tool call and update windows accordingly
   */
  const processToolCall = useCallback(
    (toolCall: TPToolCall) => {
      // Early return if not within DesktopProvider
      if (!desktop) return;

      const config = TOOL_TO_WINDOW[toolCall.name];
      if (!config) return;

      const { windowId, action, extractItemIds } = config;
      const itemIds = extractItemIds ? extractItemIds(toolCall.input) : undefined;

      if (autoOpen) {
        // Auto-open the window with highlight
        desktop.openWindow(windowId, { itemIds, action });
      } else if (showPulse) {
        // Just pulse the dock icon to draw attention
        desktop.setPulse(windowId, true);
        // Clear pulse after 3 seconds
        setTimeout(() => desktop.setPulse(windowId, false), 3000);
      }

      // Set highlight even if we don't open
      if (itemIds?.length) {
        desktop.setHighlight(windowId, { itemIds, action });
      }
    },
    [autoOpen, showPulse, desktop]
  );

  /**
   * Process multiple tool calls from a TP response
   */
  const processToolCalls = useCallback(
    (toolCalls: TPToolCall[]) => {
      for (const toolCall of toolCalls) {
        processToolCall(toolCall);
      }
    },
    [processToolCall]
  );

  /**
   * Handle context changes - increment badge on context window
   */
  const processContextChanges = useCallback(
    (changes: TPContextChange[]) => {
      // Early return if not within DesktopProvider
      if (!desktop) return;
      if (changes.length === 0) return;

      // Increment badge to show new context items
      desktop.incrementBadge('context');

      // Pulse if not auto-opening
      if (!autoOpen && showPulse) {
        desktop.setPulse('context', true);
        setTimeout(() => desktop.setPulse('context', false), 3000);
      }
    },
    [autoOpen, showPulse, desktop]
  );

  /**
   * Handle work outputs - increment badge on outputs window
   */
  const processWorkOutputs = useCallback(
    (outputs: WorkOutput[]) => {
      // Early return if not within DesktopProvider
      if (!desktop) return;
      if (outputs.length === 0) return;

      // Increment badge for each new output
      outputs.forEach(() => desktop.incrementBadge('outputs'));

      // Pulse if not auto-opening
      if (!autoOpen && showPulse) {
        desktop.setPulse('outputs', true);
        setTimeout(() => desktop.setPulse('outputs', false), 3000);
      }
    },
    [autoOpen, showPulse, desktop]
  );

  /**
   * Start tracking a TP response (for grouping related events)
   */
  const startResponseTracking = useCallback(() => {
    responseInProgressRef.current = true;
  }, []);

  /**
   * End tracking a TP response
   */
  const endResponseTracking = useCallback(() => {
    responseInProgressRef.current = false;
  }, []);

  return {
    processToolCall,
    processToolCalls,
    processContextChanges,
    processWorkOutputs,
    startResponseTracking,
    endResponseTracking,
  };
}

export default useTPToolWindowIntegration;
