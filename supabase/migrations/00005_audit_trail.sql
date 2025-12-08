-- =============================================================================
-- CLEARINGHOUSE: Audit Trail Schema
-- Migration: 00005_audit_trail.sql
-- Purpose: Complete provenance tracking via timeline events
-- =============================================================================

-- =============================================================================
-- TIMELINE EVENTS (Audit Trail)
-- =============================================================================

CREATE TABLE timeline_events (
    id BIGSERIAL PRIMARY KEY,

    -- Scope
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE,
    catalog_id UUID REFERENCES catalogs(id) ON DELETE CASCADE,

    -- Event classification
    event_type TEXT NOT NULL,
    -- Event types:
    -- Rights: 'rights_entity_created', 'rights_entity_updated', 'rights_entity_archived'
    -- Governance: 'proposal_created', 'proposal_approved', 'proposal_rejected'
    -- Licensing: 'license_granted', 'license_terminated', 'usage_reported'
    -- System: 'catalog_created', 'workspace_created', 'user_joined'

    -- Entity reference
    entity_type TEXT NOT NULL,  -- 'rights_entity', 'proposal', 'license_grant', 'catalog', etc.
    entity_id UUID NOT NULL,

    -- Event content
    summary TEXT NOT NULL,  -- Human-readable summary
    payload JSONB DEFAULT '{}',  -- Full event data
    -- payload example:
    -- {
    --   "before": {...},
    --   "after": {...},
    --   "changed_fields": ["ai_permissions.training"],
    --   "reason": "Updated AI training permission"
    -- }

    -- Actor
    actor_type TEXT NOT NULL,  -- 'user', 'system', 'api', 'webhook'
    actor_id TEXT,  -- user UUID, API client ID, etc.

    -- Context
    source_ip TEXT,
    user_agent TEXT,
    request_id TEXT,  -- For tracing

    -- Timestamp
    created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE timeline_events IS 'Complete audit trail for all system events - immutable append-only log';
COMMENT ON COLUMN timeline_events.payload IS 'Full event data including before/after states for changes';
COMMENT ON COLUMN timeline_events.actor_type IS 'Who triggered this event: user, system, api, webhook';

-- Indexes for efficient querying
CREATE INDEX idx_timeline_events_workspace ON timeline_events(workspace_id, created_at DESC);
CREATE INDEX idx_timeline_events_catalog ON timeline_events(catalog_id, created_at DESC);
CREATE INDEX idx_timeline_events_entity ON timeline_events(entity_type, entity_id);
CREATE INDEX idx_timeline_events_type ON timeline_events(event_type);
CREATE INDEX idx_timeline_events_actor ON timeline_events(actor_type, actor_id);
CREATE INDEX idx_timeline_events_created_at ON timeline_events(created_at DESC);

-- =============================================================================
-- TIMELINE EVENT HELPER FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION emit_timeline_event(
    p_workspace_id UUID,
    p_catalog_id UUID,
    p_event_type TEXT,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_summary TEXT,
    p_payload JSONB DEFAULT '{}',
    p_actor_type TEXT DEFAULT 'system',
    p_actor_id TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_event_id BIGINT;
BEGIN
    INSERT INTO timeline_events (
        workspace_id,
        catalog_id,
        event_type,
        entity_type,
        entity_id,
        summary,
        payload,
        actor_type,
        actor_id
    ) VALUES (
        p_workspace_id,
        p_catalog_id,
        p_event_type,
        p_entity_type,
        p_entity_id,
        p_summary,
        p_payload,
        p_actor_type,
        p_actor_id
    )
    RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION emit_timeline_event IS 'Helper function to emit timeline events with consistent structure';

-- =============================================================================
-- AUTO-EMIT TRIGGERS
-- =============================================================================

-- Trigger function for rights_entities
CREATE OR REPLACE FUNCTION trg_rights_entity_timeline()
RETURNS TRIGGER AS $$
DECLARE
    v_catalog RECORD;
    v_event_type TEXT;
    v_summary TEXT;
    v_payload JSONB;
BEGIN
    -- Get catalog and workspace info
    SELECT c.*, w.id as workspace_id
    INTO v_catalog
    FROM catalogs c
    JOIN workspaces w ON w.id = c.workspace_id
    WHERE c.id = COALESCE(NEW.catalog_id, OLD.catalog_id);

    IF TG_OP = 'INSERT' THEN
        v_event_type := 'rights_entity_created';
        v_summary := format('Created %s: %s', NEW.rights_type, NEW.title);
        v_payload := jsonb_build_object(
            'rights_type', NEW.rights_type,
            'title', NEW.title,
            'entity_key', NEW.entity_key,
            'created_by', NEW.created_by
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'active' AND NEW.status = 'archived' THEN
            v_event_type := 'rights_entity_archived';
            v_summary := format('Archived %s: %s', NEW.rights_type, NEW.title);
        ELSE
            v_event_type := 'rights_entity_updated';
            v_summary := format('Updated %s: %s', NEW.rights_type, NEW.title);
        END IF;
        v_payload := jsonb_build_object(
            'before', jsonb_build_object(
                'title', OLD.title,
                'status', OLD.status,
                'ai_permissions', OLD.ai_permissions,
                'version', OLD.version
            ),
            'after', jsonb_build_object(
                'title', NEW.title,
                'status', NEW.status,
                'ai_permissions', NEW.ai_permissions,
                'version', NEW.version
            ),
            'updated_by', NEW.updated_by
        );
    END IF;

    PERFORM emit_timeline_event(
        v_catalog.workspace_id,
        v_catalog.id,
        v_event_type,
        'rights_entity',
        COALESCE(NEW.id, OLD.id),
        v_summary,
        v_payload,
        'system',
        COALESCE(NEW.updated_by, NEW.created_by)
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for rights_entities
CREATE TRIGGER trg_rights_entities_timeline
    AFTER INSERT OR UPDATE ON rights_entities
    FOR EACH ROW EXECUTE FUNCTION trg_rights_entity_timeline();

-- Trigger function for proposals
CREATE OR REPLACE FUNCTION trg_proposal_timeline()
RETURNS TRIGGER AS $$
DECLARE
    v_catalog RECORD;
    v_event_type TEXT;
    v_summary TEXT;
    v_payload JSONB;
BEGIN
    -- Get catalog and workspace info
    SELECT c.*, w.id as workspace_id
    INTO v_catalog
    FROM catalogs c
    JOIN workspaces w ON w.id = c.workspace_id
    WHERE c.id = COALESCE(NEW.catalog_id, OLD.catalog_id);

    IF TG_OP = 'INSERT' THEN
        v_event_type := 'proposal_created';
        v_summary := format('Proposal created: %s', NEW.proposal_type);
        v_payload := jsonb_build_object(
            'proposal_type', NEW.proposal_type,
            'target_entity_id', NEW.target_entity_id,
            'created_by', NEW.created_by
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'pending' AND NEW.status = 'approved' THEN
            v_event_type := 'proposal_approved';
            v_summary := format('Proposal approved: %s', NEW.proposal_type);
        ELSIF OLD.status = 'pending' AND NEW.status = 'rejected' THEN
            v_event_type := 'proposal_rejected';
            v_summary := format('Proposal rejected: %s', NEW.proposal_type);
        ELSE
            v_event_type := 'proposal_updated';
            v_summary := format('Proposal updated: %s', NEW.proposal_type);
        END IF;
        v_payload := jsonb_build_object(
            'proposal_type', NEW.proposal_type,
            'old_status', OLD.status,
            'new_status', NEW.status,
            'reviewed_by', NEW.reviewed_by,
            'review_notes', NEW.review_notes
        );
    END IF;

    PERFORM emit_timeline_event(
        v_catalog.workspace_id,
        v_catalog.id,
        v_event_type,
        'proposal',
        COALESCE(NEW.id, OLD.id),
        v_summary,
        v_payload,
        'system',
        COALESCE(NEW.reviewed_by::text, NEW.created_by)
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for proposals
CREATE TRIGGER trg_proposals_timeline
    AFTER INSERT OR UPDATE ON proposals
    FOR EACH ROW EXECUTE FUNCTION trg_proposal_timeline();

-- Trigger function for license_grants
CREATE OR REPLACE FUNCTION trg_license_grant_timeline()
RETURNS TRIGGER AS $$
DECLARE
    v_rights_entity RECORD;
    v_event_type TEXT;
    v_summary TEXT;
    v_payload JSONB;
BEGIN
    -- Get rights entity, catalog, and workspace info
    SELECT re.*, c.id as catalog_id, c.workspace_id
    INTO v_rights_entity
    FROM rights_entities re
    JOIN catalogs c ON c.id = re.catalog_id
    WHERE re.id = COALESCE(NEW.rights_entity_id, OLD.rights_entity_id);

    IF TG_OP = 'INSERT' THEN
        v_event_type := 'license_granted';
        v_summary := format('License granted for: %s', v_rights_entity.title);
        v_payload := jsonb_build_object(
            'licensee_id', NEW.licensee_id,
            'status', NEW.status,
            'territory', NEW.territory,
            'created_by', NEW.created_by
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.status IN ('terminated', 'revoked') AND OLD.status = 'active' THEN
            v_event_type := 'license_terminated';
            v_summary := format('License terminated for: %s', v_rights_entity.title);
        ELSE
            v_event_type := 'license_updated';
            v_summary := format('License updated for: %s', v_rights_entity.title);
        END IF;
        v_payload := jsonb_build_object(
            'old_status', OLD.status,
            'new_status', NEW.status,
            'licensee_id', NEW.licensee_id
        );
    END IF;

    PERFORM emit_timeline_event(
        v_rights_entity.workspace_id,
        v_rights_entity.catalog_id,
        v_event_type,
        'license_grant',
        COALESCE(NEW.id, OLD.id),
        v_summary,
        v_payload,
        'system',
        NEW.created_by
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for license_grants
CREATE TRIGGER trg_license_grants_timeline
    AFTER INSERT OR UPDATE ON license_grants
    FOR EACH ROW EXECUTE FUNCTION trg_license_grant_timeline();

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE timeline_events ENABLE ROW LEVEL SECURITY;

-- Timeline events: workspace members can view
CREATE POLICY "timeline_events_select_members"
ON timeline_events FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM workspace_memberships wm
        WHERE wm.workspace_id = timeline_events.workspace_id
        AND wm.user_id = auth.uid()
    )
);

-- Timeline events: only service role can insert (via triggers/functions)
CREATE POLICY "timeline_events_service_role"
ON timeline_events FOR ALL TO service_role
USING (true) WITH CHECK (true);

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON timeline_events TO authenticated;
GRANT ALL ON timeline_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE timeline_events_id_seq TO service_role;
GRANT USAGE, SELECT ON SEQUENCE timeline_events_id_seq TO authenticated;
