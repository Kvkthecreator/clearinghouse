-- =====================================================================
-- Phase 5: Work-Request-Based Agent Trials
-- =====================================================================
-- Business Model:
--   • 10 FREE work requests total (across ALL agents)
--   • After trial → subscribe to specific agent ($19-$39/month)
--   • Subscription = unlimited work requests for that agent
--
-- Architecture:
--   • agent_catalog: Available agents with pricing
--   • agent_work_requests: Tracks every work request (trial or paid)
--   • user_agent_subscriptions: Active subscriptions per agent
--   • check_trial_limit(): Enforces 10 total trial requests globally
-- =====================================================================

BEGIN;

-- =====================================================================
-- 1. Agent Catalog Table
-- =====================================================================
-- Stores available agents with pricing and trial configuration
CREATE TABLE IF NOT EXISTS agent_catalog (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_type text NOT NULL UNIQUE, -- 'research', 'content', 'reporting'
    name text NOT NULL, -- 'Research Agent', 'Content Creator', etc.
    description text NOT NULL,
    monthly_price_cents integer NOT NULL, -- Price in cents (e.g., 1900 = $19.00)
    trial_work_requests integer NOT NULL DEFAULT 10, -- Global trial limit (shared across all agents)
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Constraints
    CONSTRAINT agent_type_lowercase CHECK (agent_type = lower(agent_type)),
    CONSTRAINT monthly_price_positive CHECK (monthly_price_cents > 0),
    CONSTRAINT trial_requests_positive CHECK (trial_work_requests >= 0)
);

-- Index for active agents lookup
CREATE INDEX idx_agent_catalog_active ON agent_catalog(is_active) WHERE is_active = true;

-- Seed agent catalog with Phase 4 agents
INSERT INTO agent_catalog (agent_type, name, description, monthly_price_cents, trial_work_requests) VALUES
    ('research', 'Research Agent', 'Monitors domains, synthesizes findings, and proposes knowledge blocks', 1900, 10),
    ('content', 'Content Creator Agent', 'Creates brand-aligned content for multiple platforms', 2900, 10),
    ('reporting', 'Reporting Agent', 'Generates executive reports and analytics', 3900, 10)
ON CONFLICT (agent_type) DO NOTHING;

COMMENT ON TABLE agent_catalog IS 'Available agents with pricing and trial configuration';
COMMENT ON COLUMN agent_catalog.trial_work_requests IS 'Global trial limit shared across all agents (10 total)';


-- =====================================================================
-- 2. Work Requests Tracking Table
-- =====================================================================
-- Tracks every work request made by users (trial or paid)
CREATE TABLE IF NOT EXISTS agent_work_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL, -- From auth.users
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    basket_id uuid REFERENCES baskets(id) ON DELETE SET NULL, -- Basket context for request
    agent_type text NOT NULL, -- 'research', 'content', 'reporting'

    -- Trial vs Subscription
    is_trial_request boolean NOT NULL DEFAULT false,
    subscription_id uuid, -- References user_agent_subscriptions if paid

    -- Request details
    work_mode text, -- 'governance_proposal', 'synthesis', etc.
    request_payload jsonb, -- Original request parameters

    -- Execution tracking
    status text NOT NULL DEFAULT 'pending', -- 'pending', 'running', 'completed', 'failed'
    result_summary text, -- Brief summary of result
    error_message text, -- Error if failed

    -- Timestamps
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,

    -- Constraints
    CONSTRAINT agent_type_fk CHECK (agent_type IN ('research', 'content', 'reporting')),
    CONSTRAINT status_valid CHECK (status IN ('pending', 'running', 'completed', 'failed')),
    CONSTRAINT subscription_for_paid CHECK (
        (is_trial_request = true AND subscription_id IS NULL) OR
        (is_trial_request = false AND subscription_id IS NOT NULL)
    )
);

-- Indexes for common queries
CREATE INDEX idx_work_requests_user_workspace ON agent_work_requests(user_id, workspace_id);
CREATE INDEX idx_work_requests_trial ON agent_work_requests(user_id, workspace_id, is_trial_request)
    WHERE is_trial_request = true;
CREATE INDEX idx_work_requests_subscription ON agent_work_requests(subscription_id)
    WHERE subscription_id IS NOT NULL;
CREATE INDEX idx_work_requests_status ON agent_work_requests(status, created_at);

COMMENT ON TABLE agent_work_requests IS 'Tracks every work request (trial or paid) for rate limiting and billing';
COMMENT ON COLUMN agent_work_requests.is_trial_request IS 'True if part of 10 free trial requests, false if paid subscription';


-- =====================================================================
-- 3. User Agent Subscriptions Table
-- =====================================================================
-- Tracks active subscriptions for agents (one subscription per agent type per user)
CREATE TABLE IF NOT EXISTS user_agent_subscriptions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL, -- From auth.users
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    agent_type text NOT NULL, -- 'research', 'content', 'reporting'

    -- Subscription lifecycle
    status text NOT NULL DEFAULT 'active', -- 'active', 'cancelled', 'expired'
    started_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz, -- NULL = no expiration (monthly auto-renew)
    cancelled_at timestamptz,

    -- Billing integration (placeholder for future Stripe integration)
    stripe_subscription_id text, -- Stripe subscription ID
    stripe_customer_id text, -- Stripe customer ID
    monthly_price_cents integer NOT NULL, -- Locked-in price at subscription time

    -- Metadata
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    -- Constraints
    CONSTRAINT agent_type_fk CHECK (agent_type IN ('research', 'content', 'reporting')),
    CONSTRAINT status_valid CHECK (status IN ('active', 'cancelled', 'expired')),
    CONSTRAINT price_positive CHECK (monthly_price_cents > 0),

    -- One active subscription per agent type per user
    CONSTRAINT unique_active_subscription UNIQUE (user_id, workspace_id, agent_type, status)
        DEFERRABLE INITIALLY DEFERRED
);

-- Indexes for common queries
CREATE INDEX idx_subscriptions_user_workspace ON user_agent_subscriptions(user_id, workspace_id);
CREATE INDEX idx_subscriptions_active ON user_agent_subscriptions(user_id, workspace_id, agent_type)
    WHERE status = 'active';
CREATE INDEX idx_subscriptions_stripe ON user_agent_subscriptions(stripe_subscription_id)
    WHERE stripe_subscription_id IS NOT NULL;

COMMENT ON TABLE user_agent_subscriptions IS 'Active agent subscriptions (one per agent type per user)';
COMMENT ON COLUMN user_agent_subscriptions.expires_at IS 'NULL for auto-renew subscriptions, set for cancelled/expired';


-- =====================================================================
-- 4. Trial Limit Checking Function
-- =====================================================================
-- Checks if user can make a work request (trial or subscription)
CREATE OR REPLACE FUNCTION check_trial_limit(
    p_user_id uuid,
    p_workspace_id uuid,
    p_agent_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_used_count integer;
    v_remaining integer;
    v_has_subscription boolean;
    v_subscription_id uuid;
BEGIN
    -- Check if user has active subscription for this agent type
    SELECT EXISTS (
        SELECT 1 FROM user_agent_subscriptions
        WHERE user_id = p_user_id
          AND workspace_id = p_workspace_id
          AND agent_type = p_agent_type
          AND status = 'active'
    ) INTO v_has_subscription;

    -- If subscribed, unlimited requests allowed
    IF v_has_subscription THEN
        SELECT id INTO v_subscription_id
        FROM user_agent_subscriptions
        WHERE user_id = p_user_id
          AND workspace_id = p_workspace_id
          AND agent_type = p_agent_type
          AND status = 'active'
        LIMIT 1;

        RETURN jsonb_build_object(
            'can_request', true,
            'is_subscribed', true,
            'subscription_id', v_subscription_id,
            'remaining_trial_requests', NULL
        );
    END IF;

    -- Count TOTAL trial requests across ALL agents (global limit)
    SELECT COUNT(*) INTO v_used_count
    FROM agent_work_requests
    WHERE user_id = p_user_id
      AND workspace_id = p_workspace_id
      AND is_trial_request = true;

    v_remaining := 10 - v_used_count;

    -- Return trial status
    RETURN jsonb_build_object(
        'can_request', v_remaining > 0,
        'is_subscribed', false,
        'subscription_id', NULL,
        'remaining_trial_requests', GREATEST(0, v_remaining),
        'used_trial_requests', v_used_count,
        'total_trial_limit', 10
    );
END;
$$;

COMMENT ON FUNCTION check_trial_limit IS 'Checks if user can make work request (10 total trial or subscription)';


-- =====================================================================
-- 5. Row Level Security (RLS)
-- =====================================================================
-- Enable RLS on new tables
ALTER TABLE agent_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_work_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_agent_subscriptions ENABLE ROW LEVEL SECURITY;

-- Agent catalog: Public read access (anyone can see available agents)
CREATE POLICY agent_catalog_read ON agent_catalog
    FOR SELECT
    USING (is_active = true);

-- Work requests: Users can only see their own requests
CREATE POLICY work_requests_user_read ON agent_work_requests
    FOR SELECT
    USING (auth.uid() = user_id);

-- Work requests: Service role can insert/update (API creates requests)
CREATE POLICY work_requests_service_write ON agent_work_requests
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Subscriptions: Users can only see their own subscriptions
CREATE POLICY subscriptions_user_read ON user_agent_subscriptions
    FOR SELECT
    USING (auth.uid() = user_id);

-- Subscriptions: Service role can manage (API handles billing)
CREATE POLICY subscriptions_service_write ON user_agent_subscriptions
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');


-- =====================================================================
-- 6. Updated_at Trigger Function (if not exists)
-- =====================================================================
-- Create update_updated_at_column function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 7. Updated_at Triggers
-- =====================================================================
-- Trigger for agent_catalog
CREATE TRIGGER set_updated_at_agent_catalog
    BEFORE UPDATE ON agent_catalog
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for user_agent_subscriptions
CREATE TRIGGER set_updated_at_subscriptions
    BEFORE UPDATE ON user_agent_subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- =====================================================================
-- 8. Grant Permissions
-- =====================================================================
-- Service role needs full access
GRANT ALL ON agent_catalog TO service_role;
GRANT ALL ON agent_work_requests TO service_role;
GRANT ALL ON user_agent_subscriptions TO service_role;

-- Authenticated users need read access to catalog
GRANT SELECT ON agent_catalog TO authenticated;

-- Authenticated users need access to their own data (via RLS)
GRANT SELECT ON agent_work_requests TO authenticated;
GRANT SELECT ON user_agent_subscriptions TO authenticated;

-- Grant execute on function
GRANT EXECUTE ON FUNCTION check_trial_limit TO service_role;
GRANT EXECUTE ON FUNCTION check_trial_limit TO authenticated;

COMMIT;

-- =====================================================================
-- Phase 5 Migration Complete
-- =====================================================================
-- Summary:
--   ✅ agent_catalog: 3 agents seeded ($19, $29, $39/month)
--   ✅ agent_work_requests: Tracks all requests (trial or paid)
--   ✅ user_agent_subscriptions: Per-agent subscriptions
--   ✅ check_trial_limit(): Enforces 10 TOTAL trial requests globally
--   ✅ RLS policies: Users see only their own data
--
-- Next Steps (work-platform API):
--   1. Create permissions.py utility module
--   2. Update agent_orchestration.py routes
--   3. Test trial → subscription flow
-- =====================================================================
