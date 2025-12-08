-- =============================================================================
-- CLEARINGHOUSE: Licensing Schema
-- Migration: 00004_licensing.sql
-- Purpose: License templates and grants for IP licensing
-- =============================================================================

-- =============================================================================
-- LICENSE TEMPLATES (Reusable License Terms)
-- =============================================================================

CREATE TABLE license_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Template info
    name TEXT NOT NULL,
    description TEXT,
    license_type TEXT NOT NULL,  -- 'exclusive', 'non_exclusive', 'sync', 'mechanical', 'ai_training', etc.

    -- Standard terms
    terms JSONB NOT NULL DEFAULT '{}',
    -- Example:
    -- {
    --   "exclusivity": "non_exclusive",
    --   "duration_type": "perpetual" | "fixed" | "renewable",
    --   "territory": ["worldwide"] | ["US", "CA"],
    --   "attribution_required": true,
    --   "derivative_works": false,
    --   "sublicensing": false
    -- }

    -- AI-specific terms (first-class citizen)
    ai_terms JSONB DEFAULT '{}',
    -- Example:
    -- {
    --   "training_allowed": true,
    --   "generation_allowed": false,
    --   "style_reference_allowed": true,
    --   "model_types": ["music_generation", "style_transfer"],
    --   "output_restrictions": {
    --     "commercial_use": "requires_additional_license",
    --     "attribution": "required"
    --   }
    -- }

    -- Pricing model
    pricing JSONB DEFAULT '{}',
    -- Example:
    -- {
    --   "model": "per_use" | "flat_fee" | "revenue_share" | "negotiable",
    --   "base_rate": 0.01,
    --   "currency": "USD",
    --   "usage_tiers": [...]
    -- }

    -- Template status
    is_active BOOLEAN DEFAULT true,
    is_public BOOLEAN DEFAULT false,  -- Can other workspaces see/use this template?

    -- Audit
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE license_templates IS 'Reusable license term templates';
COMMENT ON COLUMN license_templates.ai_terms IS 'AI-specific licensing terms (training, generation, etc.)';
COMMENT ON COLUMN license_templates.is_public IS 'If true, template is visible to other workspaces';

CREATE INDEX idx_license_templates_workspace ON license_templates(workspace_id);
CREATE INDEX idx_license_templates_type ON license_templates(license_type);
CREATE INDEX idx_license_templates_public ON license_templates(is_public) WHERE is_public = true;

-- =============================================================================
-- LICENSEES (External Parties Receiving Licenses)
-- =============================================================================

CREATE TABLE licensees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Licensee info
    name TEXT NOT NULL,
    entity_type TEXT DEFAULT 'organization' CHECK (entity_type IN ('organization', 'individual', 'platform')),

    -- Contact
    contact_email TEXT,
    contact_name TEXT,

    -- Platform-specific (for AI platforms)
    platform_info JSONB DEFAULT '{}',
    -- Example for AI platform:
    -- {
    --   "platform_name": "Suno",
    --   "platform_type": "ai_music_generation",
    --   "api_integration": true,
    --   "usage_reporting_enabled": true
    -- }

    -- Verification
    verification_status TEXT DEFAULT 'unverified',

    -- Metadata
    metadata JSONB DEFAULT '{}',

    -- Audit
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE licensees IS 'External parties (companies, platforms) that receive licenses';

CREATE INDEX idx_licensees_workspace ON licensees(workspace_id);

-- =============================================================================
-- LICENSE GRANTS (Active Licenses)
-- =============================================================================

CREATE TABLE license_grants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Parties
    rights_entity_id UUID NOT NULL REFERENCES rights_entities(id) ON DELETE CASCADE,
    licensee_id UUID REFERENCES licensees(id) ON DELETE SET NULL,
    template_id UUID REFERENCES license_templates(id) ON DELETE SET NULL,

    -- Terms (copied from template + any overrides)
    terms JSONB NOT NULL DEFAULT '{}',
    ai_terms JSONB DEFAULT '{}',

    -- Scope
    territory TEXT[] DEFAULT ARRAY['worldwide'],

    -- Duration
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date DATE,  -- NULL = perpetual

    -- Status
    status TEXT DEFAULT 'active' CHECK (status IN (
        'draft',
        'pending_approval',
        'active',
        'suspended',
        'expired',
        'terminated',
        'revoked'
    )),

    -- Usage tracking
    usage_tracking_enabled BOOLEAN DEFAULT false,
    usage_reporting_frequency TEXT,  -- 'realtime', 'daily', 'weekly', 'monthly'

    -- Financial
    pricing JSONB DEFAULT '{}',
    total_paid NUMERIC(12,2) DEFAULT 0,

    -- Reference documents
    contract_asset_id UUID REFERENCES reference_assets(id),

    -- Approval (if required)
    requires_approval BOOLEAN DEFAULT false,
    approved_by UUID REFERENCES auth.users(id),
    approved_at TIMESTAMPTZ,

    -- Audit
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE license_grants IS 'Active licenses granted for rights entities';
COMMENT ON COLUMN license_grants.terms IS 'Negotiated terms (may override template)';
COMMENT ON COLUMN license_grants.usage_tracking_enabled IS 'Whether to track usage for this license';

CREATE INDEX idx_license_grants_entity ON license_grants(rights_entity_id);
CREATE INDEX idx_license_grants_licensee ON license_grants(licensee_id) WHERE licensee_id IS NOT NULL;
CREATE INDEX idx_license_grants_status ON license_grants(status) WHERE status = 'active';
CREATE INDEX idx_license_grants_dates ON license_grants(start_date, end_date);

-- =============================================================================
-- USAGE RECORDS (Track License Usage)
-- =============================================================================

CREATE TABLE usage_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    license_grant_id UUID NOT NULL REFERENCES license_grants(id) ON DELETE CASCADE,

    -- Usage info
    usage_type TEXT NOT NULL,  -- 'training_sample', 'generation', 'api_call', etc.
    usage_count INTEGER DEFAULT 1,

    -- Context
    usage_context JSONB DEFAULT '{}',
    -- Example:
    -- {
    --   "model_id": "suno-v3",
    --   "generation_id": "abc123",
    --   "output_type": "audio",
    --   "duration_seconds": 120
    -- }

    -- Reporting
    reported_by TEXT,  -- 'api:{client}', 'manual', 'webhook'
    reported_at TIMESTAMPTZ DEFAULT now(),

    -- Financial
    billable BOOLEAN DEFAULT true,
    amount_due NUMERIC(12,4),

    created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE usage_records IS 'Tracks usage of licensed content for reporting and settlement';

CREATE INDEX idx_usage_records_grant ON usage_records(license_grant_id);
CREATE INDEX idx_usage_records_reported_at ON usage_records(reported_at DESC);

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE license_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE licensees ENABLE ROW LEVEL SECURITY;
ALTER TABLE license_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_records ENABLE ROW LEVEL SECURITY;

-- License templates: workspace members can view their templates + public templates
CREATE POLICY "license_templates_select_members"
ON license_templates FOR SELECT TO authenticated
USING (
    is_public = true
    OR EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = license_templates.workspace_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "license_templates_insert_members"
ON license_templates FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = license_templates.workspace_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "license_templates_update_admins"
ON license_templates FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = license_templates.workspace_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

CREATE POLICY "license_templates_service_role"
ON license_templates FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- Licensees: workspace members
CREATE POLICY "licensees_select_members"
ON licensees FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = licensees.workspace_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "licensees_manage_members"
ON licensees FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = licensees.workspace_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "licensees_service_role"
ON licensees FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- License grants: based on rights entity access
CREATE POLICY "license_grants_select_members"
ON license_grants FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = license_grants.rights_entity_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "license_grants_insert_members"
ON license_grants FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = license_grants.rights_entity_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "license_grants_update_admins"
ON license_grants FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM rights_entities re
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE re.id = license_grants.rights_entity_id
        AND wm.user_id = auth.uid()
        AND wm.role IN ('owner', 'admin')
    )
);

CREATE POLICY "license_grants_service_role"
ON license_grants FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- Usage records: same as license grants
CREATE POLICY "usage_records_select_members"
ON usage_records FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM license_grants lg
        JOIN rights_entities re ON re.id = lg.rights_entity_id
        JOIN catalogs c ON c.id = re.catalog_id
        JOIN workspace_memberships wm ON wm.workspace_id = c.workspace_id
        WHERE lg.id = usage_records.license_grant_id
        AND wm.user_id = auth.uid()
    )
);

CREATE POLICY "usage_records_insert_service"
ON usage_records FOR INSERT TO service_role
WITH CHECK (true);

CREATE POLICY "usage_records_service_role"
ON usage_records FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

CREATE TRIGGER trg_license_templates_updated_at
    BEFORE UPDATE ON license_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_licensees_updated_at
    BEFORE UPDATE ON licensees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_license_grants_updated_at
    BEFORE UPDATE ON license_grants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT ALL ON license_templates TO authenticated;
GRANT ALL ON license_templates TO service_role;
GRANT ALL ON licensees TO authenticated;
GRANT ALL ON licensees TO service_role;
GRANT ALL ON license_grants TO authenticated;
GRANT ALL ON license_grants TO service_role;
GRANT ALL ON usage_records TO authenticated;
GRANT ALL ON usage_records TO service_role;
