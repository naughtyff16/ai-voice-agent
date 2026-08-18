-- Migration 071 (Phase 5J): agent_utilization_hourly, lead_funnel_daily,
--   campaign_outcome_summary, tool_execution_stats_daily, webhook_delivery_stats_daily,
--   roi_by_campaign, billing_revenue_monthly, provider_health_5min
-- down_revision: 070_5J
-- Correction applied (5K §10.11):
--   Source defines billing_revenue_monthly.year_bucket as GENERATED ALWAYS.
--   PostgreSQL 16 prohibits a generated column as a partition key.
--   Also, the UNIQUE constraint uq_brm_grain did not include year_bucket (the partition key).
--   Fix: plain INTEGER column + CHECK constraint. Partition key added to UNIQUE.

CREATE TABLE analytics.agent_utilization_hourly (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NOT NULL,
  hour_bucket            TIMESTAMPTZ NOT NULL,
  agent_id               UUID        NOT NULL,
  calls_started          INTEGER     NOT NULL DEFAULT 0,
  calls_ended            INTEGER     NOT NULL DEFAULT 0,
  peak_concurrent        INTEGER     NOT NULL DEFAULT 0,
  sum_concurrent_samples INTEGER     NOT NULL DEFAULT 0,
  sample_count           INTEGER     NOT NULL DEFAULT 0,
  last_event_id          UUID        NULL,
  last_updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_auh       PRIMARY KEY (id, hour_bucket),
  CONSTRAINT uq_auh_grain UNIQUE (organization_id, hour_bucket, agent_id)
) PARTITION BY RANGE (hour_bucket);
CREATE TABLE analytics.agent_utilization_hourly_y2026m08 PARTITION OF analytics.agent_utilization_hourly FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.agent_utilization_hourly_y2026m09 PARTITION OF analytics.agent_utilization_hourly FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.agent_utilization_hourly_default   PARTITION OF analytics.agent_utilization_hourly DEFAULT;
CREATE INDEX idx_auh_org_hour ON analytics.agent_utilization_hourly (organization_id, hour_bucket DESC);
ALTER TABLE analytics.agent_utilization_hourly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.agent_utilization_hourly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_auh_tenant ON analytics.agent_utilization_hourly FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.agent_utilization_hourly FROM app_api;
GRANT SELECT ON analytics.agent_utilization_hourly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.agent_utilization_hourly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.agent_utilization_hourly TO app_platform_admin;

CREATE TABLE analytics.lead_funnel_daily (
  id                  UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID    NOT NULL,
  date_bucket         DATE    NOT NULL,
  campaign_id         UUID    NULL,
  leads_contacted     INTEGER NOT NULL DEFAULT 0,
  leads_answered      INTEGER NOT NULL DEFAULT 0,
  leads_qualified     INTEGER NOT NULL DEFAULT 0,
  leads_disqualified  INTEGER NOT NULL DEFAULT 0,
  leads_converted     INTEGER NOT NULL DEFAULT 0,
  appointments_booked INTEGER NOT NULL DEFAULT 0,
  dnc_encounters      INTEGER NOT NULL DEFAULT 0,
  last_event_id       UUID    NULL,
  last_updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_lfd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_lfd_grain UNIQUE NULLS NOT DISTINCT (organization_id, date_bucket, campaign_id)
) PARTITION BY RANGE (date_bucket);
CREATE TABLE analytics.lead_funnel_daily_y2026m08 PARTITION OF analytics.lead_funnel_daily FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.lead_funnel_daily_y2026m09 PARTITION OF analytics.lead_funnel_daily FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.lead_funnel_daily_default   PARTITION OF analytics.lead_funnel_daily DEFAULT;
CREATE INDEX idx_lfd_org_date ON analytics.lead_funnel_daily (organization_id, date_bucket DESC);
CREATE INDEX idx_lfd_campaign ON analytics.lead_funnel_daily (organization_id, campaign_id, date_bucket DESC) WHERE campaign_id IS NOT NULL;
ALTER TABLE analytics.lead_funnel_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.lead_funnel_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_lfd_tenant ON analytics.lead_funnel_daily FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.lead_funnel_daily FROM app_api;
GRANT SELECT ON analytics.lead_funnel_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.lead_funnel_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.lead_funnel_daily TO app_platform_admin;

CREATE TABLE analytics.campaign_outcome_summary (
  id                            UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id               UUID          NOT NULL,
  campaign_id                   UUID          NOT NULL,
  calls_attempted               INTEGER       NOT NULL DEFAULT 0,
  calls_connected               INTEGER       NOT NULL DEFAULT 0,
  calls_completed               INTEGER       NOT NULL DEFAULT 0,
  calls_failed                  INTEGER       NOT NULL DEFAULT 0,
  unique_contacts               INTEGER       NOT NULL DEFAULT 0,
  qualified_contacts            INTEGER       NOT NULL DEFAULT 0,
  converted_contacts            INTEGER       NOT NULL DEFAULT 0,
  appointments_booked           INTEGER       NOT NULL DEFAULT 0,
  total_duration_s              BIGINT        NOT NULL DEFAULT 0,
  total_telephony_cost_amount   NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_telephony_cost_currency CHAR(3)       NOT NULL DEFAULT 'USD',
  total_ai_cost_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_ai_cost_currency        CHAR(3)       NOT NULL DEFAULT 'USD',
  status                        TEXT          NOT NULL DEFAULT 'ACTIVE',
  last_event_id                 UUID          NULL,
  last_updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_cos          PRIMARY KEY (id),
  CONSTRAINT uq_cos_campaign UNIQUE (campaign_id),
  CONSTRAINT chk_cos_status  CHECK (status IN ('ACTIVE','COMPLETED','CANCELLED'))
);
CREATE INDEX idx_cos_org    ON analytics.campaign_outcome_summary (organization_id);
CREATE INDEX idx_cos_status ON analytics.campaign_outcome_summary (organization_id, status);
ALTER TABLE analytics.campaign_outcome_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.campaign_outcome_summary FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cos_tenant ON analytics.campaign_outcome_summary FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE DELETE ON analytics.campaign_outcome_summary FROM app_api, app_worker;
GRANT SELECT ON analytics.campaign_outcome_summary TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.campaign_outcome_summary TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.campaign_outcome_summary TO app_platform_admin;

CREATE TABLE analytics.tool_execution_stats_daily (
  id              UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID    NOT NULL,
  date_bucket     DATE    NOT NULL,
  tool_name       TEXT    NOT NULL,
  agent_id        UUID    NULL,
  invocations     INTEGER NOT NULL DEFAULT 0,
  succeeded       INTEGER NOT NULL DEFAULT 0,
  failed          INTEGER NOT NULL DEFAULT 0,
  timed_out       INTEGER NOT NULL DEFAULT 0,
  sum_latency_ms  BIGINT  NOT NULL DEFAULT 0,
  last_event_id   UUID    NULL,
  last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_tesd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_tesd_grain UNIQUE NULLS NOT DISTINCT (organization_id, date_bucket, tool_name, agent_id)
) PARTITION BY RANGE (date_bucket);
CREATE TABLE analytics.tool_execution_stats_daily_y2026m08 PARTITION OF analytics.tool_execution_stats_daily FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.tool_execution_stats_daily_y2026m09 PARTITION OF analytics.tool_execution_stats_daily FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.tool_execution_stats_daily_default   PARTITION OF analytics.tool_execution_stats_daily DEFAULT;
CREATE INDEX idx_tesd_org_date ON analytics.tool_execution_stats_daily (organization_id, date_bucket DESC);
ALTER TABLE analytics.tool_execution_stats_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.tool_execution_stats_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tesd_tenant ON analytics.tool_execution_stats_daily FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.tool_execution_stats_daily FROM app_api;
GRANT SELECT ON analytics.tool_execution_stats_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.tool_execution_stats_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.tool_execution_stats_daily TO app_platform_admin;

CREATE TABLE analytics.webhook_delivery_stats_daily (
  id                   UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID    NOT NULL,
  date_bucket          DATE    NOT NULL,
  deliveries_attempted INTEGER NOT NULL DEFAULT 0,
  deliveries_succeeded INTEGER NOT NULL DEFAULT 0,
  deliveries_failed    INTEGER NOT NULL DEFAULT 0,
  dead_lettered        INTEGER NOT NULL DEFAULT 0,
  retries              INTEGER NOT NULL DEFAULT 0,
  sum_latency_ms       BIGINT  NOT NULL DEFAULT 0,
  last_event_id        UUID    NULL,
  last_updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_wdsd       PRIMARY KEY (id, date_bucket),
  CONSTRAINT uq_wdsd_grain UNIQUE (organization_id, date_bucket)
) PARTITION BY RANGE (date_bucket);
CREATE TABLE analytics.webhook_delivery_stats_daily_y2026m08 PARTITION OF analytics.webhook_delivery_stats_daily FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.webhook_delivery_stats_daily_y2026m09 PARTITION OF analytics.webhook_delivery_stats_daily FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.webhook_delivery_stats_daily_default   PARTITION OF analytics.webhook_delivery_stats_daily DEFAULT;
CREATE INDEX idx_wdsd_org_date ON analytics.webhook_delivery_stats_daily (organization_id, date_bucket DESC);
ALTER TABLE analytics.webhook_delivery_stats_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.webhook_delivery_stats_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wdsd_tenant ON analytics.webhook_delivery_stats_daily FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.webhook_delivery_stats_daily FROM app_api;
GRANT SELECT ON analytics.webhook_delivery_stats_daily TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.webhook_delivery_stats_daily TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.webhook_delivery_stats_daily TO app_platform_admin;

CREATE TABLE analytics.roi_by_campaign (
  id                         UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id            UUID          NOT NULL,
  campaign_id                UUID          NOT NULL,
  total_cost_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_cost_currency        CHAR(3)       NOT NULL DEFAULT 'USD',
  estimated_revenue_amount   NUMERIC(18,4) NULL,
  estimated_revenue_currency CHAR(3)       NULL,
  roi_pct                    NUMERIC(8,4)  NULL,
  cost_per_call              NUMERIC(18,4) NULL,
  cost_per_qualified         NUMERIC(18,4) NULL,
  cost_per_converted         NUMERIC(18,4) NULL,
  computed_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_rbc          PRIMARY KEY (id),
  CONSTRAINT uq_rbc_campaign UNIQUE (campaign_id)
);
CREATE INDEX idx_rbc_org ON analytics.roi_by_campaign (organization_id);
ALTER TABLE analytics.roi_by_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.roi_by_campaign FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_rbc_tenant ON analytics.roi_by_campaign FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON analytics.roi_by_campaign TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.roi_by_campaign TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.roi_by_campaign TO app_platform_admin;

-- billing_revenue_monthly — CORRECTED: plain integer column + CHECK (5K §10.11)
-- Source used GENERATED ALWAYS AS which PostgreSQL 16 prohibits as a partition key.
-- Source also omitted year_bucket from the UNIQUE constraint (partition key must be included).
CREATE TABLE analytics.billing_revenue_monthly (
  id                     UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID          NOT NULL,
  year_month             CHAR(7)       NOT NULL,
  year_bucket            INTEGER       NOT NULL,
  invoices_generated     INTEGER       NOT NULL DEFAULT 0,
  invoices_paid          INTEGER       NOT NULL DEFAULT 0,
  billed_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
  billed_currency        CHAR(3)       NOT NULL DEFAULT 'INR',
  provider_cost_amount   NUMERIC(18,4) NOT NULL DEFAULT 0,
  provider_cost_currency CHAR(3)       NOT NULL DEFAULT 'USD',
  subscription_plan_id   UUID          NULL,
  last_event_id          UUID          NULL,
  last_updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_brm             PRIMARY KEY (id, year_bucket),
  CONSTRAINT uq_brm_grain       UNIQUE (organization_id, year_month, year_bucket),
  CONSTRAINT chk_brm_year_month CHECK (year_month ~ '^\d{4}-\d{2}$'),
  CONSTRAINT chk_brm_year_bucket CHECK (year_bucket = CAST(LEFT(year_month, 4) AS INTEGER))
) PARTITION BY RANGE (year_bucket);
CREATE TABLE analytics.billing_revenue_monthly_before2027 PARTITION OF analytics.billing_revenue_monthly FOR VALUES FROM (2026) TO (2027);
CREATE TABLE analytics.billing_revenue_monthly_2027        PARTITION OF analytics.billing_revenue_monthly FOR VALUES FROM (2027) TO (2028);
CREATE TABLE analytics.billing_revenue_monthly_default     PARTITION OF analytics.billing_revenue_monthly DEFAULT;
CREATE INDEX idx_brm_org ON analytics.billing_revenue_monthly (organization_id, year_month DESC);
ALTER TABLE analytics.billing_revenue_monthly ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.billing_revenue_monthly FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_brm_tenant ON analytics.billing_revenue_monthly FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE UPDATE, DELETE ON analytics.billing_revenue_monthly FROM app_api;
GRANT SELECT ON analytics.billing_revenue_monthly TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.billing_revenue_monthly TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.billing_revenue_monthly TO app_platform_admin;

CREATE TABLE analytics.provider_health_5min (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  five_min_bucket   TIMESTAMPTZ NOT NULL,
  provider          TEXT        NOT NULL,
  provider_category TEXT        NOT NULL,
  model             TEXT        NOT NULL DEFAULT 'all',
  request_count     INTEGER     NOT NULL DEFAULT 0,
  error_count       INTEGER     NOT NULL DEFAULT 0,
  failover_count    INTEGER     NOT NULL DEFAULT 0,
  circuit_open_count INTEGER    NOT NULL DEFAULT 0,
  circuit_close_count INTEGER   NOT NULL DEFAULT 0,
  sum_latency_ms    BIGINT      NOT NULL DEFAULT 0,
  last_updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_phf       PRIMARY KEY (id, five_min_bucket),
  CONSTRAINT uq_phf_grain UNIQUE (five_min_bucket, provider, provider_category, model),
  CONSTRAINT chk_phf_category CHECK (provider_category IN ('LLM','STT','TTS','TELEPHONY','EMBEDDING'))
) PARTITION BY RANGE (five_min_bucket);
CREATE TABLE analytics.provider_health_5min_y2026m08 PARTITION OF analytics.provider_health_5min FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics.provider_health_5min_y2026m09 PARTITION OF analytics.provider_health_5min FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics.provider_health_5min_default   PARTITION OF analytics.provider_health_5min DEFAULT;
CREATE INDEX idx_phf_bucket ON analytics.provider_health_5min (five_min_bucket DESC, provider, provider_category);
REVOKE ALL ON analytics.provider_health_5min FROM app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.provider_health_5min TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON analytics.provider_health_5min TO app_platform_admin;
