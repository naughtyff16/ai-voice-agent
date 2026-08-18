-- Migration 069 (Phase 5J): call_metrics_hourly, call_latency_stage_hourly, fn_apply_projection_call_latency
-- down_revision: 068_5J
-- Note: fn_apply_projection_call_metrics in 068 inserts INTO call_metrics_hourly; this table
-- must therefore be created BEFORE that function is called at runtime, but NOT before the function
-- is defined. Since the function is only invoked by workers at runtime (not at migration time),
-- the ordering is safe: table created in 069, function defined in 068.
CREATE TABLE analytics.call_metrics_hourly (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  hour_bucket     TIMESTAMPTZ NOT NULL,
  agent_id        UUID        NULL,
  direction       TEXT        NOT NULL DEFAULT 'ALL',
  call_outcome    TEXT        NOT NULL DEFAULT 'ALL',
  provider        TEXT        NOT NULL DEFAULT 'all',
  language_code   TEXT        NOT NULL DEFAULT 'all',
  total_calls     INTEGER     NOT NULL DEFAULT 0,
  answered_calls  INTEGER     NOT NULL DEFAULT 0,
  failed_calls    INTEGER     NOT NULL DEFAULT 0,
  total_duration_s BIGINT     NOT NULL DEFAULT 0,
  talk_time_s     BIGINT      NOT NULL DEFAULT 0,
  wait_time_s     BIGINT      NOT NULL DEFAULT 0,
  transfer_count  INTEGER     NOT NULL DEFAULT 0,
  recording_count INTEGER     NOT NULL DEFAULT 0,
  last_event_id   UUID        NULL,
  last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_call_metrics_hourly PRIMARY KEY (id, hour_bucket),
  CONSTRAINT uq_cmh_grain           UNIQUE NULLS NOT DISTINCT (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code),
  CONSTRAINT chk_cmh_direction      CHECK (direction IN ('INBOUND','OUTBOUND','ALL')),
  CONSTRAINT chk_cmh_calls_nn       CHECK (total_calls >= 0 AND answered_calls >= 0)
) PARTITION BY RANGE (hour_bucket);

CREATE TABLE analytics.call_metrics_hourly_y2026m08 PARTITION OF analytics.call_metrics_hourly FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.call_metrics_hourly_y2026m09 PARTITION OF analytics.call_metrics_hourly FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.call_metrics_hourly_y2026m10 PARTITION OF analytics.call_metrics_hourly FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics.call_metrics_hourly_default   PARTITION OF analytics.call_metrics_hourly DEFAULT;
CREATE INDEX idx_cmh_org_hour  ON analytics.call_metrics_hourly (organization_id, hour_bucket DESC);
CREATE INDEX idx_cmh_org_agent ON analytics.call_metrics_hourly (organization_id, agent_id, hour_bucket DESC) WHERE agent_id IS NOT NULL;
ALTER TABLE analytics.call_metrics_hourly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.call_metrics_hourly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cmh_tenant ON analytics.call_metrics_hourly FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.call_metrics_hourly FROM app_api;
GRANT SELECT ON analytics.call_metrics_hourly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.call_metrics_hourly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.call_metrics_hourly TO app_platform_admin;

CREATE TABLE analytics.call_latency_stage_hourly (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  hour_bucket       TIMESTAMPTZ NOT NULL,
  provider          TEXT        NOT NULL,
  provider_category TEXT        NOT NULL,
  model             TEXT        NOT NULL DEFAULT 'all',
  bucket_upper_ms   INTEGER     NOT NULL,
  bucket_count      BIGINT      NOT NULL DEFAULT 0,
  error_count       INTEGER     NOT NULL DEFAULT 0,
  last_event_id     UUID        NULL,
  last_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_clsh        PRIMARY KEY (id, hour_bucket),
  CONSTRAINT uq_clsh_grain  UNIQUE (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms),
  CONSTRAINT chk_clsh_cat   CHECK (provider_category IN ('LLM','STT','TTS','TELEPHONY','EMBEDDING')),
  CONSTRAINT chk_clsh_bucket CHECK (bucket_upper_ms IN (10,25,50,100,150,250,500,750,1000,1500,2000,5000,-1)),
  CONSTRAINT chk_clsh_count_nn CHECK (bucket_count >= 0)
) PARTITION BY RANGE (hour_bucket);

CREATE TABLE analytics.call_latency_stage_hourly_y2026m08 PARTITION OF analytics.call_latency_stage_hourly FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.call_latency_stage_hourly_y2026m09 PARTITION OF analytics.call_latency_stage_hourly FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.call_latency_stage_hourly_y2026m10 PARTITION OF analytics.call_latency_stage_hourly FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics.call_latency_stage_hourly_default   PARTITION OF analytics.call_latency_stage_hourly DEFAULT;
CREATE INDEX idx_clsh_org_hour ON analytics.call_latency_stage_hourly (organization_id, hour_bucket DESC);
CREATE INDEX idx_clsh_provider ON analytics.call_latency_stage_hourly (provider, provider_category, hour_bucket DESC);
ALTER TABLE analytics.call_latency_stage_hourly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.call_latency_stage_hourly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_clsh_tenant ON analytics.call_latency_stage_hourly FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.call_latency_stage_hourly FROM app_api;
GRANT SELECT ON analytics.call_latency_stage_hourly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.call_latency_stage_hourly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.call_latency_stage_hourly TO app_platform_admin;

CREATE OR REPLACE FUNCTION analytics.fn_apply_projection_call_latency(
  p_analytics_event_id UUID, p_occurred_at TIMESTAMPTZ, p_organization_id UUID,
  p_hour_bucket TIMESTAMPTZ, p_provider TEXT, p_provider_category TEXT,
  p_model TEXT, p_latency_ms INTEGER, p_is_error BOOLEAN
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog AS $$
DECLARE v_claimed BOOLEAN; v_bucket INTEGER;
BEGIN
  v_claimed := analytics.fn_claim_projection_slot('call_latency_stage_hourly', p_analytics_event_id, p_occurred_at);
  IF NOT v_claimed THEN RETURN FALSE; END IF;
  v_bucket := CASE
    WHEN p_is_error THEN NULL
    WHEN p_latency_ms <= 10   THEN 10
    WHEN p_latency_ms <= 25   THEN 25
    WHEN p_latency_ms <= 50   THEN 50
    WHEN p_latency_ms <= 100  THEN 100
    WHEN p_latency_ms <= 150  THEN 150
    WHEN p_latency_ms <= 250  THEN 250
    WHEN p_latency_ms <= 500  THEN 500
    WHEN p_latency_ms <= 750  THEN 750
    WHEN p_latency_ms <= 1000 THEN 1000
    WHEN p_latency_ms <= 1500 THEN 1500
    WHEN p_latency_ms <= 2000 THEN 2000
    WHEN p_latency_ms <= 5000 THEN 5000
    ELSE -1 END;
  IF v_bucket IS NOT NULL THEN
    INSERT INTO analytics.call_latency_stage_hourly (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms, bucket_count, last_event_id)
    VALUES (p_organization_id, p_hour_bucket, p_provider, p_provider_category, p_model, v_bucket, 1, p_analytics_event_id)
    ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
    DO UPDATE SET bucket_count = analytics.call_latency_stage_hourly.bucket_count + 1, last_event_id = EXCLUDED.last_event_id, last_updated_at = NOW();
  ELSE
    INSERT INTO analytics.call_latency_stage_hourly (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms, bucket_count, error_count, last_event_id)
    VALUES (p_organization_id, p_hour_bucket, p_provider, p_provider_category, p_model, 5000, 0, 1, p_analytics_event_id)
    ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
    DO UPDATE SET error_count = analytics.call_latency_stage_hourly.error_count + 1, last_event_id = EXCLUDED.last_event_id, last_updated_at = NOW();
  END IF;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION analytics.fn_apply_projection_call_latency(UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,INTEGER,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.fn_apply_projection_call_latency(UUID,TIMESTAMPTZ,UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,INTEGER,BOOLEAN) TO app_worker, app_platform_admin;
