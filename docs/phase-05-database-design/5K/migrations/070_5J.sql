-- Migration 070 (Phase 5J): conversation_turn_stats_daily and usage_cost_daily
-- down_revision: 069_5J
CREATE TABLE analytics.conversation_turn_stats_daily (
  id                    UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID    NOT NULL,
  date_bucket           DATE    NOT NULL,
  agent_id              UUID    NOT NULL,
  total_turns           INTEGER NOT NULL DEFAULT 0,
  total_calls           INTEGER NOT NULL DEFAULT 0,
  barge_in_count        INTEGER NOT NULL DEFAULT 0,
  tool_calls_total      INTEGER NOT NULL DEFAULT 0,
  tool_calls_succeeded  INTEGER NOT NULL DEFAULT 0,
  tool_calls_failed     INTEGER NOT NULL DEFAULT 0,
  sum_turns_per_call    INTEGER NOT NULL DEFAULT 0,
  llm_prompt_tokens     BIGINT  NOT NULL DEFAULT 0,
  llm_completion_tokens BIGINT  NOT NULL DEFAULT 0,
  llm_total_tokens      BIGINT  NOT NULL DEFAULT 0,
  stt_audio_seconds     NUMERIC(12,2) NOT NULL DEFAULT 0,
  tts_characters        BIGINT  NOT NULL DEFAULT 0,
  last_event_id         UUID    NULL,
  last_updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_ctsd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_ctsd_grain UNIQUE (organization_id, date_bucket, agent_id)
) PARTITION BY RANGE (date_bucket);
CREATE TABLE analytics.conversation_turn_stats_daily_y2026m08 PARTITION OF analytics.conversation_turn_stats_daily FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.conversation_turn_stats_daily_y2026m09 PARTITION OF analytics.conversation_turn_stats_daily FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.conversation_turn_stats_daily_default   PARTITION OF analytics.conversation_turn_stats_daily DEFAULT;
CREATE INDEX idx_ctsd_org_date ON analytics.conversation_turn_stats_daily (organization_id, date_bucket DESC);
CREATE INDEX idx_ctsd_agent    ON analytics.conversation_turn_stats_daily (organization_id, agent_id, date_bucket DESC);
ALTER TABLE analytics.conversation_turn_stats_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.conversation_turn_stats_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ctsd_tenant ON analytics.conversation_turn_stats_daily FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.conversation_turn_stats_daily FROM app_api;
GRANT SELECT ON analytics.conversation_turn_stats_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.conversation_turn_stats_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.conversation_turn_stats_daily TO app_platform_admin;

CREATE TABLE analytics.usage_cost_daily (
  id              UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID          NOT NULL,
  date_bucket     DATE          NOT NULL,
  metric          TEXT          NOT NULL,
  provider        TEXT          NOT NULL DEFAULT 'all',
  model           TEXT          NOT NULL DEFAULT 'all',
  unit_count      NUMERIC(18,4) NOT NULL DEFAULT 0,
  cost_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
  cost_currency   CHAR(3)       NOT NULL DEFAULT 'USD',
  event_count     INTEGER       NOT NULL DEFAULT 0,
  last_event_id   UUID          NULL,
  last_updated_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_ucd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_ucd_grain UNIQUE (organization_id, date_bucket, metric, provider, model),
  CONSTRAINT chk_ucd_cost CHECK (cost_amount >= 0 AND unit_count >= 0)
) PARTITION BY RANGE (date_bucket);
CREATE TABLE analytics.usage_cost_daily_y2026m08 PARTITION OF analytics.usage_cost_daily FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.usage_cost_daily_y2026m09 PARTITION OF analytics.usage_cost_daily FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.usage_cost_daily_default   PARTITION OF analytics.usage_cost_daily DEFAULT;
CREATE INDEX idx_ucd_org_date ON analytics.usage_cost_daily (organization_id, date_bucket DESC);
CREATE INDEX idx_ucd_metric   ON analytics.usage_cost_daily (organization_id, metric, date_bucket DESC);
ALTER TABLE analytics.usage_cost_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.usage_cost_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ucd_tenant ON analytics.usage_cost_daily FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.usage_cost_daily FROM app_api;
GRANT SELECT ON analytics.usage_cost_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.usage_cost_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.usage_cost_daily TO app_platform_admin;
