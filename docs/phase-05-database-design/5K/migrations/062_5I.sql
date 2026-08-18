-- Migration 062 (Phase 5I): webhook_endpoints and inbound_webhook_events
-- down_revision: 061_5I
CREATE TABLE webhooks.webhook_endpoints (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  display_name         TEXT        NOT NULL,
  target_url           TEXT        NOT NULL,
  signing_secret_ref   TEXT        NOT NULL,
  topics               TEXT[]      NOT NULL,
  status               TEXT        NOT NULL DEFAULT 'ACTIVE',
  max_attempts         INTEGER     NOT NULL DEFAULT 7,
  timeout_ms           INTEGER     NOT NULL DEFAULT 10000,
  endpoint_verified_at TIMESTAMPTZ NULL,
  created_by_ref       UUID        NULL,
  last_delivery_at     TIMESTAMPTZ NULL,
  disabled_at          TIMESTAMPTZ NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_webhook_endpoints      PRIMARY KEY (id),
  CONSTRAINT chk_we_target_https       CHECK (target_url LIKE 'https://%'),
  CONSTRAINT chk_we_signing_secret_ref CHECK (signing_secret_ref LIKE 'secret_manager://%'),
  CONSTRAINT chk_we_topics_nonempty    CHECK (array_length(topics, 1) > 0),
  CONSTRAINT chk_we_status             CHECK (status IN ('ACTIVE','DISABLED','SUSPENDED')),
  CONSTRAINT chk_we_max_attempts       CHECK (max_attempts BETWEEN 1 AND 10),
  CONSTRAINT chk_we_timeout_ms         CHECK (timeout_ms BETWEEN 1000 AND 30000),
  CONSTRAINT chk_we_display_name       CHECK (length(display_name) BETWEEN 1 AND 200)
);
CREATE INDEX idx_we_org_status ON webhooks.webhook_endpoints (organization_id, status);
CREATE INDEX idx_we_org_topics ON webhooks.webhook_endpoints USING GIN (topics) WHERE status = 'ACTIVE';
CREATE TRIGGER trg_we_updated_at BEFORE UPDATE ON webhooks.webhook_endpoints FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE webhooks.webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks.webhook_endpoints FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_we_tenant ON webhooks.webhook_endpoints FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON webhooks.webhook_endpoints TO app_api, app_worker;
GRANT SELECT ON webhooks.webhook_endpoints TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON webhooks.webhook_endpoints TO app_platform_admin;

CREATE TABLE webhooks.inbound_webhook_events (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  provider_slug     TEXT        NOT NULL,
  provider_event_id TEXT        NOT NULL,
  event_type        TEXT        NOT NULL,
  signature_header  TEXT        NULL,
  signature_valid   BOOLEAN     NULL,
  raw_payload_ref   TEXT        NULL,
  status            TEXT        NOT NULL DEFAULT 'RECEIVED',
  received_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at      TIMESTAMPTZ NULL,
  failure_reason    TEXT        NULL,
  CONSTRAINT pk_inbound_webhook_events  PRIMARY KEY (id),
  CONSTRAINT uq_iwe_org_provider_event  UNIQUE (organization_id, provider_slug, provider_event_id),
  CONSTRAINT chk_iwe_status             CHECK (status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED','SKIPPED')),
  CONSTRAINT chk_iwe_provider_slug      CHECK (length(provider_slug) BETWEEN 1 AND 100),
  CONSTRAINT chk_iwe_provider_event_id  CHECK (length(provider_event_id) BETWEEN 1 AND 500),
  CONSTRAINT chk_iwe_failure_reason_len CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000)
);
CREATE INDEX idx_iwe_org_status ON webhooks.inbound_webhook_events (organization_id, status, received_at DESC);
CREATE INDEX idx_iwe_org_type   ON webhooks.inbound_webhook_events (organization_id, event_type, received_at DESC);
ALTER TABLE webhooks.inbound_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks.inbound_webhook_events FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_iwe_tenant ON webhooks.inbound_webhook_events FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON webhooks.inbound_webhook_events FROM app_api, app_worker;
GRANT SELECT, INSERT ON webhooks.inbound_webhook_events TO app_api, app_worker;
GRANT SELECT ON webhooks.inbound_webhook_events TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON webhooks.inbound_webhook_events TO app_platform_admin;

CREATE OR REPLACE FUNCTION webhooks.fn_update_inbound_event_status(
  p_id UUID, p_organization_id UUID, p_new_status TEXT, p_failure_reason TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
DECLARE v_current TEXT;
BEGIN
  IF p_new_status NOT IN ('PROCESSING','PROCESSED','FAILED','SKIPPED') THEN
    RAISE EXCEPTION 'webhooks: invalid target status %', p_new_status;
  END IF;
  SELECT status INTO v_current FROM webhooks.inbound_webhook_events WHERE id = p_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'webhooks: inbound event not found'; END IF;
  IF v_current IN ('PROCESSED','SKIPPED') THEN RETURN; END IF;
  UPDATE webhooks.inbound_webhook_events
  SET status = p_new_status,
      processed_at = CASE WHEN p_new_status IN ('PROCESSED','FAILED','SKIPPED') THEN NOW() ELSE processed_at END,
      failure_reason = CASE WHEN p_failure_reason IS NOT NULL THEN LEFT(p_failure_reason, 2000) ELSE failure_reason END
  WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_update_inbound_event_status(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_update_inbound_event_status(UUID, UUID, TEXT, TEXT) TO app_worker, app_platform_admin;
