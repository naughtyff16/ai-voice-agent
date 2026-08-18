-- Migration 063 (Phase 5I): webhook_deliveries (partitioned) + SECURITY DEFINER functions
-- down_revision: 062_5I
-- Correction: fn_replay_webhook_delivery calls gen_uuid_v7() → search_path includes public (5K §10.8)
-- All other functions in this migration do NOT call gen_uuid_v7() → search_path = webhooks, pg_catalog
CREATE TABLE webhooks.webhook_deliveries (
  id                         UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id            UUID        NOT NULL,
  webhook_endpoint_id        UUID        NOT NULL,
  event_type                 TEXT        NOT NULL,
  event_id                   UUID        NOT NULL,
  payload_json               TEXT        NOT NULL,
  payload_hash               TEXT        NOT NULL,
  status                     TEXT        NOT NULL DEFAULT 'PENDING',
  attempt_count              INTEGER     NOT NULL DEFAULT 0,
  max_attempts               INTEGER     NOT NULL DEFAULT 7,
  next_attempt_at            TIMESTAMPTZ NULL,
  last_attempt_at            TIMESTAMPTZ NULL,
  last_response_code         INTEGER     NULL,
  last_response_body_preview TEXT        NULL,
  claimed_by                 TEXT        NULL,
  claimed_at                 TIMESTAMPTZ NULL,
  completed_at               TIMESTAMPTZ NULL,
  failure_reason             TEXT        NULL,
  replay_of_delivery_id      UUID        NULL,
  replay_count               INTEGER     NOT NULL DEFAULT 0,
  last_replayed_at           TIMESTAMPTZ NULL,
  resolved_at                TIMESTAMPTZ NULL,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_webhook_deliveries     PRIMARY KEY (id, created_at),
  CONSTRAINT chk_wd_status             CHECK (status IN ('PENDING','DELIVERING','DELIVERED','FAILED','DEAD_LETTER','CANCELLED')),
  CONSTRAINT chk_wd_max_attempts       CHECK (max_attempts BETWEEN 1 AND 10),
  CONSTRAINT chk_wd_attempt_count      CHECK (attempt_count >= 0),
  CONSTRAINT chk_wd_preview_length     CHECK (last_response_body_preview IS NULL OR length(last_response_body_preview) <= 512),
  CONSTRAINT chk_wd_failure_reason_len CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000),
  CONSTRAINT chk_wd_payload_nonempty   CHECK (length(payload_json) > 0)
) PARTITION BY RANGE (created_at);

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'webhook_deliveries_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='webhooks' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE webhooks.%I PARTITION OF webhooks.webhook_deliveries FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE webhooks.webhook_deliveries_default PARTITION OF webhooks.webhook_deliveries DEFAULT;

CREATE INDEX idx_wd_pending  ON webhooks.webhook_deliveries (organization_id, next_attempt_at) WHERE status = 'PENDING';
CREATE INDEX idx_wd_endpoint ON webhooks.webhook_deliveries (webhook_endpoint_id, created_at DESC);
CREATE INDEX idx_wd_status   ON webhooks.webhook_deliveries (organization_id, status);
CREATE INDEX idx_wd_replay   ON webhooks.webhook_deliveries (replay_of_delivery_id) WHERE replay_of_delivery_id IS NOT NULL;

CREATE OR REPLACE FUNCTION webhooks.fn_wd_identity_immutable()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
BEGIN
  IF NEW.payload_json <> OLD.payload_json OR NEW.payload_hash <> OLD.payload_hash
  OR NEW.event_id <> OLD.event_id OR NEW.event_type <> OLD.event_type
  OR NEW.webhook_endpoint_id <> OLD.webhook_endpoint_id OR NEW.organization_id <> OLD.organization_id THEN
    RAISE EXCEPTION 'webhooks: delivery identity/content fields are immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_wd_identity_immutable() FROM PUBLIC;
CREATE TRIGGER trg_wd_identity_immutable BEFORE UPDATE ON webhooks.webhook_deliveries FOR EACH ROW EXECUTE FUNCTION webhooks.fn_wd_identity_immutable();
ALTER TABLE webhooks.webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks.webhook_deliveries FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wd_tenant ON webhooks.webhook_deliveries FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON webhooks.webhook_deliveries FROM app_api, app_worker;
GRANT SELECT, INSERT ON webhooks.webhook_deliveries TO app_api, app_worker;
GRANT SELECT ON webhooks.webhook_deliveries TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON webhooks.webhook_deliveries TO app_platform_admin;

CREATE OR REPLACE FUNCTION webhooks.fn_claim_delivery(p_worker_id TEXT, p_limit INTEGER DEFAULT 10)
RETURNS SETOF UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
BEGIN
  RETURN QUERY
  UPDATE webhooks.webhook_deliveries SET status = 'DELIVERING', claimed_by = p_worker_id, claimed_at = NOW()
  WHERE id IN (
    SELECT id FROM webhooks.webhook_deliveries WHERE status = 'PENDING'
      AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())
    ORDER BY next_attempt_at ASC NULLS FIRST, created_at ASC LIMIT p_limit FOR UPDATE SKIP LOCKED
  ) RETURNING id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_claim_delivery(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_claim_delivery(TEXT, INTEGER) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION webhooks.fn_delivery_succeeded(p_delivery_id UUID, p_created_at TIMESTAMPTZ, p_response_code INTEGER, p_response_preview TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
BEGIN
  UPDATE webhooks.webhook_deliveries
  SET status = 'DELIVERED', last_response_code = p_response_code,
      last_response_body_preview = LEFT(COALESCE(p_response_preview,''), 512),
      attempt_count = attempt_count + 1, last_attempt_at = NOW(), completed_at = NOW(), claimed_by = NULL, claimed_at = NULL
  WHERE id = p_delivery_id AND created_at = p_created_at AND status = 'DELIVERING';
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_delivery_succeeded(UUID, TIMESTAMPTZ, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_delivery_succeeded(UUID, TIMESTAMPTZ, INTEGER, TEXT) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION webhooks.fn_delivery_failed(p_delivery_id UUID, p_created_at TIMESTAMPTZ, p_response_code INTEGER DEFAULT NULL, p_response_preview TEXT DEFAULT NULL, p_failure_reason TEXT DEFAULT NULL, p_next_attempt_at TIMESTAMPTZ DEFAULT NULL)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
DECLARE v_current_count INTEGER; v_max_attempts INTEGER; v_new_count INTEGER; v_new_status TEXT; v_next_at TIMESTAMPTZ;
BEGIN
  SELECT attempt_count, max_attempts INTO v_current_count, v_max_attempts FROM webhooks.webhook_deliveries
  WHERE id = p_delivery_id AND created_at = p_created_at AND status = 'DELIVERING' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'webhooks: delivery % not found or not in DELIVERING state', p_delivery_id; END IF;
  v_new_count := v_current_count + 1;
  IF v_new_count >= v_max_attempts THEN v_new_status := 'DEAD_LETTER'; v_next_at := NULL;
  ELSE v_new_status := 'PENDING'; v_next_at := p_next_attempt_at; END IF;
  UPDATE webhooks.webhook_deliveries
  SET status = v_new_status, attempt_count = v_new_count, last_attempt_at = NOW(),
      last_response_code = p_response_code,
      last_response_body_preview = LEFT(COALESCE(p_response_preview,''), 512),
      failure_reason = LEFT(COALESCE(p_failure_reason, failure_reason,''), 2000),
      next_attempt_at = v_next_at,
      completed_at = CASE WHEN v_new_status = 'DEAD_LETTER' THEN NOW() ELSE NULL END,
      claimed_by = NULL, claimed_at = NULL
  WHERE id = p_delivery_id AND created_at = p_created_at;
  RETURN v_new_status;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_delivery_failed(UUID, TIMESTAMPTZ, INTEGER, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_delivery_failed(UUID, TIMESTAMPTZ, INTEGER, TEXT, TEXT, TIMESTAMPTZ) TO app_worker, app_platform_admin;

-- fn_replay_webhook_delivery: calls gen_uuid_v7() → search_path includes public (5K §10.8)
CREATE OR REPLACE FUNCTION webhooks.fn_replay_webhook_delivery(p_organization_id UUID, p_delivery_id UUID, p_created_at TIMESTAMPTZ)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog, public AS $$
DECLARE v_orig RECORD; v_new_id UUID := gen_uuid_v7(); v_existing_replay UUID;
BEGIN
  SELECT * INTO v_orig FROM webhooks.webhook_deliveries
  WHERE id = p_delivery_id AND created_at = p_created_at AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'webhooks: delivery not found'; END IF;
  IF v_orig.status NOT IN ('DEAD_LETTER','DELIVERED') THEN
    RAISE EXCEPTION 'webhooks: only DEAD_LETTER or DELIVERED deliveries can be replayed; status = %', v_orig.status;
  END IF;
  SELECT id INTO v_existing_replay FROM webhooks.webhook_deliveries WHERE replay_of_delivery_id = p_delivery_id AND status IN ('PENDING','DELIVERING');
  IF FOUND THEN RETURN v_existing_replay; END IF;
  INSERT INTO webhooks.webhook_deliveries (id, organization_id, webhook_endpoint_id, event_type, event_id, payload_json, payload_hash, status, max_attempts, next_attempt_at, replay_of_delivery_id)
  VALUES (v_new_id, p_organization_id, v_orig.webhook_endpoint_id, v_orig.event_type, v_orig.event_id, v_orig.payload_json, v_orig.payload_hash, 'PENDING', v_orig.max_attempts, NOW(), p_delivery_id);
  UPDATE webhooks.webhook_deliveries SET replay_count = replay_count + 1, last_replayed_at = NOW()
  WHERE id = p_delivery_id AND created_at = p_created_at;
  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_replay_webhook_delivery(UUID, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_replay_webhook_delivery(UUID, UUID, TIMESTAMPTZ) TO app_worker, app_platform_admin;
