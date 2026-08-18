-- Migration 068 (Phase 5J): analytics_event_dedup, analytics_events, analytics_projection_events,
--                           all analytics SECURITY DEFINER ingestion/projection functions
-- down_revision: 067_5J
-- Correction: fn_ingest_analytics_event calls gen_uuid_v7() → search_path includes public (5K §10.10)
-- All other functions in this migration do NOT call gen_uuid_v7() → search_path = analytics, pg_catalog

CREATE TABLE analytics.analytics_event_dedup (
  dedup_key       TEXT        NOT NULL,
  event_id        UUID        NOT NULL,
  occurred_at     TIMESTAMPTZ NOT NULL,
  organization_id UUID        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_analytics_event_dedup PRIMARY KEY (dedup_key),
  CONSTRAINT chk_aed_key_len          CHECK (length(dedup_key) BETWEEN 1 AND 500)
);
CREATE INDEX idx_aed_event_id    ON analytics.analytics_event_dedup (event_id);
CREATE INDEX idx_aed_org_created ON analytics.analytics_event_dedup (organization_id, created_at);
ALTER TABLE analytics.analytics_event_dedup ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.analytics_event_dedup FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_aed_tenant ON analytics.analytics_event_dedup FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE INSERT, UPDATE, DELETE ON analytics.analytics_event_dedup FROM app_api, app_worker;
GRANT SELECT ON analytics.analytics_event_dedup TO app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.analytics_event_dedup TO app_platform_admin;

CREATE TABLE analytics.analytics_events (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  event_type        TEXT        NOT NULL,
  event_version     TEXT        NOT NULL DEFAULT '1',
  dedup_key         TEXT        NOT NULL,
  occurred_at       TIMESTAMPTZ NOT NULL,
  ingested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  entity_type       TEXT        NULL,
  entity_id         UUID        NULL,
  actor_type        TEXT        NULL,
  actor_id          UUID        NULL,
  correlation_id    UUID        NULL,
  causation_id      UUID        NULL,
  call_id           UUID        NULL,
  campaign_id       UUID        NULL,
  agent_id          UUID        NULL,
  provider          TEXT        NULL,
  model             TEXT        NULL,
  dimensions        JSONB       NOT NULL DEFAULT '{}',
  measures          JSONB       NOT NULL DEFAULT '{}',
  processing_status TEXT        NOT NULL DEFAULT 'PENDING',
  processed_at      TIMESTAMPTZ NULL,
  error_detail      TEXT        NULL,
  CONSTRAINT pk_analytics_events      PRIMARY KEY (id, occurred_at),
  CONSTRAINT uq_ae_dedup_key_local    UNIQUE (dedup_key, occurred_at),
  CONSTRAINT chk_ae_processing_status CHECK (processing_status IN ('PENDING','PROJECTED','FAILED','DEAD_LETTER')),
  CONSTRAINT chk_ae_event_type        CHECK (length(event_type) BETWEEN 1 AND 200),
  CONSTRAINT chk_ae_dedup_key         CHECK (length(dedup_key) BETWEEN 1 AND 500)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE analytics.analytics_events_y2026m08 PARTITION OF analytics.analytics_events FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.analytics_events_y2026m09 PARTITION OF analytics.analytics_events FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.analytics_events_y2026m10 PARTITION OF analytics.analytics_events FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics.analytics_events_default   PARTITION OF analytics.analytics_events DEFAULT;

CREATE INDEX idx_ae_occurred_at       ON analytics.analytics_events USING BRIN (occurred_at);
CREATE INDEX idx_ae_org_type_occurred ON analytics.analytics_events (organization_id, event_type, occurred_at DESC);
CREATE INDEX idx_ae_entity            ON analytics.analytics_events (organization_id, entity_type, entity_id) WHERE entity_id IS NOT NULL;
CREATE INDEX idx_ae_pending           ON analytics.analytics_events (organization_id, occurred_at) WHERE processing_status = 'PENDING';
REVOKE INSERT, UPDATE, DELETE ON analytics.analytics_events FROM app_api, app_worker;
GRANT SELECT ON analytics.analytics_events TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.analytics_events TO app_platform_admin;
ALTER TABLE analytics.analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.analytics_events FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ae_tenant ON analytics.analytics_events FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

CREATE TABLE analytics.analytics_projection_events (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  projection_name    TEXT        NOT NULL,
  analytics_event_id UUID        NOT NULL,
  occurred_at        TIMESTAMPTZ NOT NULL,
  processed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_ape                  PRIMARY KEY (id),
  CONSTRAINT uq_ape_projection_event UNIQUE (projection_name, analytics_event_id),
  CONSTRAINT chk_ape_projection_name CHECK (length(projection_name) BETWEEN 1 AND 100)
);
CREATE INDEX idx_ape_event    ON analytics.analytics_projection_events (analytics_event_id);
CREATE INDEX idx_ape_occurred ON analytics.analytics_projection_events (occurred_at);
REVOKE ALL ON analytics.analytics_projection_events FROM PUBLIC;
GRANT SELECT, INSERT ON analytics.analytics_projection_events TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.analytics_projection_events TO app_platform_admin;

-- fn_ingest_analytics_event: calls gen_uuid_v7() → search_path includes public (5K §10.10)
CREATE OR REPLACE FUNCTION analytics.fn_ingest_analytics_event(
  p_organization_id UUID, p_event_type TEXT, p_event_version TEXT, p_dedup_key TEXT,
  p_occurred_at TIMESTAMPTZ, p_entity_type TEXT, p_entity_id UUID, p_actor_type TEXT,
  p_actor_id UUID, p_correlation_id UUID, p_causation_id UUID, p_call_id UUID,
  p_campaign_id UUID, p_agent_id UUID, p_provider TEXT, p_model TEXT,
  p_dimensions JSONB, p_measures JSONB
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path = analytics, pg_catalog, public AS $$
DECLARE v_event_id UUID := gen_uuid_v7(); v_inserted INTEGER;
BEGIN
  IF p_organization_id IS NULL THEN RAISE EXCEPTION 'analytics: organization_id is required'; END IF;
  IF p_dedup_key IS NULL OR length(p_dedup_key) < 1 THEN RAISE EXCEPTION 'analytics: dedup_key is required'; END IF;
  INSERT INTO analytics.analytics_event_dedup (dedup_key, event_id, occurred_at, organization_id)
  VALUES (p_dedup_key, v_event_id, p_occurred_at, p_organization_id) ON CONFLICT (dedup_key) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN RETURN FALSE; END IF;
  INSERT INTO analytics.analytics_events (id, organization_id, event_type, event_version, dedup_key, occurred_at, entity_type, entity_id, actor_type, actor_id, correlation_id, causation_id, call_id, campaign_id, agent_id, provider, model, dimensions, measures)
  VALUES (v_event_id, p_organization_id, p_event_type, p_event_version, p_dedup_key, p_occurred_at, p_entity_type, p_entity_id, p_actor_type, p_actor_id, p_correlation_id, p_causation_id, p_call_id, p_campaign_id, p_agent_id, p_provider, p_model, COALESCE(p_dimensions,'{}'), COALESCE(p_measures,'{}'));
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_ingest_analytics_event(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,TEXT,TEXT,JSONB,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_ingest_analytics_event(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,UUID,UUID,UUID,UUID,UUID,UUID,TEXT,TEXT,JSONB,JSONB) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION analytics.fn_claim_projection_slot(p_projection_name TEXT, p_analytics_event_id UUID, p_occurred_at TIMESTAMPTZ)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog AS $$
DECLARE v_inserted INTEGER;
BEGIN
  INSERT INTO analytics.analytics_projection_events (projection_name, analytics_event_id, occurred_at)
  VALUES (p_projection_name, p_analytics_event_id, p_occurred_at) ON CONFLICT (projection_name, analytics_event_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted > 0;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_claim_projection_slot(TEXT, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_claim_projection_slot(TEXT, UUID, TIMESTAMPTZ) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION analytics.fn_apply_projection_call_metrics(
  p_analytics_event_id UUID, p_occurred_at TIMESTAMPTZ, p_organization_id UUID,
  p_hour_bucket TIMESTAMPTZ, p_agent_id UUID, p_direction TEXT, p_call_outcome TEXT,
  p_provider TEXT, p_language_code TEXT, p_total_calls INTEGER, p_answered_calls INTEGER,
  p_failed_calls INTEGER, p_total_duration_s BIGINT, p_talk_time_s BIGINT,
  p_wait_time_s BIGINT, p_transfer_count INTEGER, p_recording_count INTEGER
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog AS $$
DECLARE v_claimed BOOLEAN;
BEGIN
  v_claimed := analytics.fn_claim_projection_slot('call_metrics_hourly', p_analytics_event_id, p_occurred_at);
  IF NOT v_claimed THEN RETURN FALSE; END IF;
  INSERT INTO analytics.call_metrics_hourly
    (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code,
     total_calls, answered_calls, failed_calls, total_duration_s, talk_time_s, wait_time_s,
     transfer_count, recording_count, last_event_id)
  VALUES (p_organization_id, p_hour_bucket, p_agent_id, p_direction, p_call_outcome, p_provider, p_language_code,
    p_total_calls, p_answered_calls, p_failed_calls, p_total_duration_s, p_talk_time_s, p_wait_time_s,
    p_transfer_count, p_recording_count, p_analytics_event_id)
  ON CONFLICT (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code)
  DO UPDATE SET total_calls = analytics.call_metrics_hourly.total_calls + EXCLUDED.total_calls,
    answered_calls = analytics.call_metrics_hourly.answered_calls + EXCLUDED.answered_calls,
    failed_calls = analytics.call_metrics_hourly.failed_calls + EXCLUDED.failed_calls,
    total_duration_s = analytics.call_metrics_hourly.total_duration_s + EXCLUDED.total_duration_s,
    talk_time_s = analytics.call_metrics_hourly.talk_time_s + EXCLUDED.talk_time_s,
    wait_time_s = analytics.call_metrics_hourly.wait_time_s + EXCLUDED.wait_time_s,
    transfer_count = analytics.call_metrics_hourly.transfer_count + EXCLUDED.transfer_count,
    recording_count = analytics.call_metrics_hourly.recording_count + EXCLUDED.recording_count,
    last_event_id = EXCLUDED.last_event_id, last_updated_at = NOW();
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_apply_projection_call_metrics(UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,UUID,TEXT,TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,BIGINT,BIGINT,BIGINT,INTEGER,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_apply_projection_call_metrics(UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,UUID,TEXT,TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,BIGINT,BIGINT,BIGINT,INTEGER,INTEGER) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION analytics.fn_mark_event_projected(p_event_id UUID, p_occurred_at TIMESTAMPTZ, p_org_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog AS $$
BEGIN
  UPDATE analytics.analytics_events SET processing_status = 'PROJECTED', processed_at = NOW()
  WHERE id = p_event_id AND occurred_at = p_occurred_at AND organization_id = p_org_id AND processing_status = 'PENDING';
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_mark_event_projected(UUID, TIMESTAMPTZ, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_mark_event_projected(UUID, TIMESTAMPTZ, UUID) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION analytics.fn_mark_event_dead_letter(p_event_id UUID, p_occurred_at TIMESTAMPTZ, p_org_id UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog AS $$
BEGIN
  UPDATE analytics.analytics_events SET processing_status = 'DEAD_LETTER', processed_at = NOW(), error_detail = LEFT(p_reason, 2000)
  WHERE id = p_event_id AND occurred_at = p_occurred_at AND organization_id = p_org_id AND processing_status IN ('PENDING','FAILED');
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_mark_event_dead_letter(UUID, TIMESTAMPTZ, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_mark_event_dead_letter(UUID, TIMESTAMPTZ, UUID, TEXT) TO app_worker, app_platform_admin;
