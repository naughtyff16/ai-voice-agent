-- Migration 050 (Phase 5H): billing.usage_events (partitioned) and usage_records
-- down_revision: 049_5H
CREATE TABLE billing.usage_events (
  id               UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  billing_period_id UUID         NULL,
  metric           TEXT          NOT NULL,
  quantity         NUMERIC(18,4) NOT NULL,
  unit_label       TEXT          NOT NULL,
  source_system    TEXT          NOT NULL,
  source_event_id  TEXT          NOT NULL,
  source_context   JSONB         NOT NULL DEFAULT '{}',
  occurred_at      TIMESTAMPTZ   NOT NULL,
  recorded_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_usage_events   PRIMARY KEY (id, occurred_at),
  CONSTRAINT uq_ue_idempotency UNIQUE (organization_id, source_system, source_event_id, occurred_at),
  CONSTRAINT chk_ue_quantity   CHECK (quantity >= 0),
  CONSTRAINT chk_ue_metric     CHECK (length(metric) BETWEEN 1 AND 100)
) PARTITION BY RANGE (occurred_at);

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'usage_events_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='billing' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE billing.%I PARTITION OF billing.usage_events FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE billing.usage_events_default PARTITION OF billing.usage_events DEFAULT;

CREATE INDEX idx_ue_org_metric ON billing.usage_events (organization_id, metric, occurred_at DESC);
CREATE INDEX idx_ue_period     ON billing.usage_events (billing_period_id) WHERE billing_period_id IS NOT NULL;
REVOKE UPDATE, DELETE ON billing.usage_events FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.usage_events TO app_api, app_worker;
GRANT SELECT ON billing.usage_events TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.usage_events TO app_platform_admin;
ALTER TABLE billing.usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.usage_events FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ue_tenant ON billing.usage_events FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

CREATE TABLE billing.usage_records (
  id                 UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id    UUID          NOT NULL,
  billing_period_id  UUID          NOT NULL REFERENCES billing.billing_periods(id) ON DELETE RESTRICT,
  metric             TEXT          NOT NULL,
  unit_label         TEXT          NOT NULL,
  quantity_used      NUMERIC(18,4) NOT NULL DEFAULT 0,
  last_aggregated_at TIMESTAMPTZ   NULL,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_usage_records    PRIMARY KEY (id),
  CONSTRAINT uq_ur_period_metric UNIQUE (organization_id, billing_period_id, metric),
  CONSTRAINT chk_ur_quantity     CHECK (quantity_used >= 0)
);
CREATE INDEX idx_ur_org_metric ON billing.usage_records (organization_id, metric, billing_period_id);
CREATE TRIGGER trg_ur_updated_at BEFORE UPDATE ON billing.usage_records FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.usage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.usage_records FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ur_tenant ON billing.usage_records FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON billing.usage_records TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.usage_records TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.usage_records TO app_platform_admin;
