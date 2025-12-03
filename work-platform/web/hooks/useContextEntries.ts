"use client";

/**
 * useContextEntries - Hook for fetching and managing context entries
 *
 * Provides:
 * - Schema fetching (available context types)
 * - Entry CRUD operations
 * - Completeness tracking
 * - Resolved entries (with asset URLs)
 *
 * See: /docs/architecture/ADR_CONTEXT_ENTRIES.md
 */

import { useCallback, useEffect, useState } from "react";

// ============================================================================
// Types
// ============================================================================

export interface FieldDefinition {
  key: string;
  type: 'text' | 'longtext' | 'array' | 'asset';
  label: string;
  required?: boolean;
  placeholder?: string;
  help?: string;
  item_type?: string;
  accept?: string;
}

export interface ContextEntrySchema {
  anchor_role: string;
  display_name: string;
  description: string;
  icon: string;
  category: 'foundation' | 'market' | 'insight';
  is_singleton: boolean;
  field_schema: {
    fields: FieldDefinition[];
    agent_produced?: boolean;
    refresh_ttl_hours?: number;
  };
  sort_order: number;
}

export interface ContextEntry {
  id: string;
  basket_id: string;
  anchor_role: string;
  entry_key?: string;
  display_name?: string;
  data: Record<string, unknown>;
  completeness_score?: number;
  state: 'active' | 'archived';
  created_at: string;
  updated_at: string;
}

export interface ContextEntryResolved extends ContextEntry {
  resolved_data: Record<string, unknown>;
}

export interface CompletenessData {
  anchor_role: string;
  total_fields: number;
  required_fields: number;
  filled_required: number;
  completeness_score: number;
  missing_required: string[];
  field_status: Record<string, boolean>;
}

// ============================================================================
// useContextSchemas - Fetch available context entry schemas
// ============================================================================

export function useContextSchemas(basketId: string) {
  const [schemas, setSchemas] = useState<ContextEntrySchema[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchSchemas = useCallback(async () => {
    if (!basketId) return;

    try {
      setLoading(true);
      setError(null);

      const response = await fetch(`/api/substrate/baskets/${basketId}/context/schemas`);

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('Please sign in to view context schemas');
        }
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || 'Failed to fetch schemas');
      }

      const data = await response.json();
      setSchemas(data.schemas || []);
      return data.schemas;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      console.error('[useContextSchemas] Error:', err);
    } finally {
      setLoading(false);
    }
  }, [basketId]);

  useEffect(() => {
    fetchSchemas();
  }, [fetchSchemas]);

  // Group schemas by category
  const schemasByCategory = {
    foundation: schemas.filter(s => s.category === 'foundation'),
    market: schemas.filter(s => s.category === 'market'),
    insight: schemas.filter(s => s.category === 'insight'),
  };

  return {
    schemas,
    schemasByCategory,
    loading,
    error,
    refetch: fetchSchemas,
  };
}

// ============================================================================
// useContextEntries - Fetch and manage context entries for a basket
// ============================================================================

export interface UseContextEntriesOptions {
  /** Filter by anchor role */
  anchorRole?: string;
  /** Whether to auto-fetch on mount */
  autoFetch?: boolean;
}

export function useContextEntries(basketId: string, options: UseContextEntriesOptions = {}) {
  const { anchorRole, autoFetch = true } = options;

  const [entries, setEntries] = useState<ContextEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchEntries = useCallback(async () => {
    if (!basketId) return;

    try {
      setLoading(true);
      setError(null);

      let url = `/api/substrate/baskets/${basketId}/context/entries`;
      if (anchorRole) {
        url = `/api/substrate/baskets/${basketId}/context/entries/${anchorRole}`;
      }

      const response = await fetch(url);

      if (!response.ok) {
        if (response.status === 404 && anchorRole) {
          // No entry exists for this role yet - that's okay
          setEntries([]);
          return [];
        }
        if (response.status === 401) {
          throw new Error('Please sign in to view context entries');
        }
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || 'Failed to fetch entries');
      }

      const data = await response.json();

      // Handle single entry vs list
      if (anchorRole) {
        setEntries([data]);
        return [data];
      } else {
        setEntries(data.entries || []);
        return data.entries;
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      console.error('[useContextEntries] Error:', err);
    } finally {
      setLoading(false);
    }
  }, [basketId, anchorRole]);

  useEffect(() => {
    if (autoFetch) {
      fetchEntries();
    }
  }, [fetchEntries, autoFetch]);

  // Create or update an entry
  const saveEntry = useCallback(async (
    role: string,
    data: Record<string, unknown>,
    options?: { entry_key?: string; display_name?: string }
  ) => {
    try {
      const url = `/api/substrate/baskets/${basketId}/context/entries/${role}`;

      const payload: Record<string, unknown> = { data };
      if (options?.entry_key) payload.entry_key = options.entry_key;
      if (options?.display_name) payload.display_name = options.display_name;

      const response = await fetch(url, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.detail || 'Failed to save entry');
      }

      const saved = await response.json();

      // Update local state
      setEntries(prev => {
        const idx = prev.findIndex(e => e.id === saved.id);
        if (idx >= 0) {
          return [...prev.slice(0, idx), saved, ...prev.slice(idx + 1)];
        }
        return [...prev, saved];
      });

      return saved;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      throw err;
    }
  }, [basketId]);

  // Archive an entry
  const archiveEntry = useCallback(async (role: string, entryKey?: string) => {
    try {
      let url = `/api/substrate/baskets/${basketId}/context/entries/${role}`;
      if (entryKey) {
        url += `?entry_key=${encodeURIComponent(entryKey)}`;
      }

      const response = await fetch(url, { method: 'DELETE' });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.detail || 'Failed to archive entry');
      }

      // Update local state
      setEntries(prev => prev.filter(e =>
        !(e.anchor_role === role && (!entryKey || e.entry_key === entryKey))
      ));

      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      throw err;
    }
  }, [basketId]);

  // Get entry by role
  const getEntryByRole = useCallback((role: string, entryKey?: string) => {
    return entries.find(e =>
      e.anchor_role === role && (!entryKey || e.entry_key === entryKey)
    );
  }, [entries]);

  // Group entries by category (needs schemas)
  const getEntriesByCategory = useCallback((schemas: ContextEntrySchema[]) => {
    const result: Record<string, ContextEntry[]> = {
      foundation: [],
      market: [],
      insight: [],
    };

    entries.forEach(entry => {
      const schema = schemas.find(s => s.anchor_role === entry.anchor_role);
      if (schema) {
        result[schema.category].push(entry);
      }
    });

    return result;
  }, [entries]);

  return {
    entries,
    loading,
    error,
    refetch: fetchEntries,
    saveEntry,
    archiveEntry,
    getEntryByRole,
    getEntriesByCategory,
  };
}

// ============================================================================
// useContextCompleteness - Fetch completeness for a specific entry
// ============================================================================

export function useContextCompleteness(basketId: string, anchorRole: string) {
  const [completeness, setCompleteness] = useState<CompletenessData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchCompleteness = useCallback(async () => {
    if (!basketId || !anchorRole) return;

    try {
      setLoading(true);
      setError(null);

      const response = await fetch(
        `/api/substrate/baskets/${basketId}/context/entries/${anchorRole}/completeness`
      );

      if (!response.ok) {
        if (response.status === 404) {
          // No entry exists yet
          setCompleteness(null);
          return null;
        }
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || 'Failed to fetch completeness');
      }

      const data = await response.json();
      setCompleteness(data);
      return data;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      console.error('[useContextCompleteness] Error:', err);
    } finally {
      setLoading(false);
    }
  }, [basketId, anchorRole]);

  useEffect(() => {
    fetchCompleteness();
  }, [fetchCompleteness]);

  return {
    completeness,
    loading,
    error,
    refetch: fetchCompleteness,
    isComplete: completeness?.completeness_score === 1,
    score: completeness?.completeness_score ?? 0,
  };
}

// ============================================================================
// useResolvedEntry - Fetch entry with resolved asset URLs
// ============================================================================

export function useResolvedEntry(basketId: string, anchorRole: string) {
  const [entry, setEntry] = useState<ContextEntryResolved | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchEntry = useCallback(async () => {
    if (!basketId || !anchorRole) return;

    try {
      setLoading(true);
      setError(null);

      const response = await fetch(
        `/api/substrate/baskets/${basketId}/context/entries/${anchorRole}/resolved`
      );

      if (!response.ok) {
        if (response.status === 404) {
          setEntry(null);
          return null;
        }
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || 'Failed to fetch entry');
      }

      const data = await response.json();
      setEntry(data);
      return data;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      console.error('[useResolvedEntry] Error:', err);
    } finally {
      setLoading(false);
    }
  }, [basketId, anchorRole]);

  useEffect(() => {
    fetchEntry();
  }, [fetchEntry]);

  return {
    entry,
    loading,
    error,
    refetch: fetchEntry,
  };
}

// ============================================================================
// useBulkContext - Fetch multiple context entries at once (for recipes)
// ============================================================================

export function useBulkContext(basketId: string) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchBulk = useCallback(async (anchorRoles: string[], options?: {
    resolve_assets?: boolean;
    include_completeness?: boolean;
  }) => {
    if (!basketId || !anchorRoles.length) return {};

    try {
      setLoading(true);
      setError(null);

      const response = await fetch(
        `/api/substrate/baskets/${basketId}/context/bulk`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            anchor_roles: anchorRoles,
            resolve_assets: options?.resolve_assets ?? false,
            include_completeness: options?.include_completeness ?? false,
          }),
        }
      );

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || 'Failed to fetch bulk context');
      }

      const data = await response.json();
      return data.entries || {};
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
      console.error('[useBulkContext] Error:', err);
      return {};
    } finally {
      setLoading(false);
    }
  }, [basketId]);

  return {
    fetchBulk,
    loading,
    error,
  };
}
