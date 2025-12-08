-- Create reflection_cache table for derived read-model (cache-only, not client-writable)
CREATE TABLE reflection_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  basket_id UUID NOT NULL REFERENCES baskets(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  substrate_hash TEXT NOT NULL, -- Hash of substrate window for deduplication
  reflection_text TEXT NOT NULL,
  substrate_window_start TIMESTAMP WITH TIME ZONE NOT NULL,
  substrate_window_end TIMESTAMP WITH TIME ZONE NOT NULL,
  computation_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  last_accessed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  meta JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Unique constraint for cache deduplication
CREATE UNIQUE INDEX reflection_cache_uq ON reflection_cache (basket_id, substrate_hash);

-- Indexes for efficient querying
CREATE INDEX idx_reflection_cache_basket_id ON reflection_cache(basket_id);
CREATE INDEX idx_reflection_cache_computation_timestamp ON reflection_cache(computation_timestamp DESC);
CREATE INDEX idx_reflection_cache_basket_computation ON reflection_cache(basket_id, computation_timestamp DESC);

-- Row Level Security
ALTER TABLE reflection_cache ENABLE ROW LEVEL SECURITY;

-- Read allowed for workspace members
CREATE POLICY reflection_cache_read ON reflection_cache
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM workspace_memberships m
    WHERE m.user_id = auth.uid()
      AND m.workspace_id = reflection_cache.workspace_id
  )
);

-- Block end-user writes (server-only via service key)
CREATE POLICY reflection_cache_no_user_insert ON reflection_cache
FOR INSERT WITH CHECK (false);

CREATE POLICY reflection_cache_no_user_update ON reflection_cache
FOR UPDATE USING (false) WITH CHECK (false);

CREATE POLICY reflection_cache_no_user_delete ON reflection_cache
FOR DELETE USING (false);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_reflection_cache_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER reflection_cache_updated_at_trigger
  BEFORE UPDATE ON reflection_cache
  FOR EACH ROW
  EXECUTE FUNCTION update_reflection_cache_updated_at();