-- Migration 051 (Phase 5H): billing.cost_entries (partitioned)
-- down_revision: 050_5H
CREATE TABLE billing.cost_entries (
  id                                   UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                      UUID          NOT NULL,
  metric                               TEXT          NOT NULL,
  provider                             TEXT          NOT NULL,
  source_system                        TEXT          NOT NULL,
  source_event_id                      TEXT          NOT NULL,
  unit_count                           NUMERIC(18,4) NOT NULL,
  amount_amount                        NUMERIC(18,4) NOT NULL,
  amount_currency                      CHAR(3)       NOT NULL,
  amount_in_billing_currency_amount    NUMERIC(18,4) NULL,
  amount_in_billing_currency_currency  CHAR(3)       NULL,
  fx_rate_used                         NUMERIC(12,6) NULL,
  fx_rate_source                       TEXT          NULL,
  fx_rate_captured_at                  TIMESTAMPTZ   NULL,
  recorded_at                          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_cost_entries        PRIMARY KEY (id, recorded_at),
  CONSTRAINT uq_ce_source           UNIQUE (source_system, source_event_id, recorded_at),
  CONSTRAINT chk_ce_amount          CHECK (amount_amount >= 0),
  CONSTRAINT chk_ce_currency        CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ce_billing_currency CHECK ((amount_in_billing_currency_amount IS NULL) = (amount_in_billing_currency_currency IS NULL))
) PARTITION BY RANGE (recorded_at);

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'cost_entries_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='billing' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE billing.%I PARTITION OF billing.cost_entries FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE billing.cost_entries_default PARTITION OF billing.cost_entries DEFAULT;

CREATE INDEX idx_ce_org_metric ON billing.cost_entries (organization_id, metric, recorded_at DESC);
CREATE INDEX idx_ce_source     ON billing.cost_entries (source_system, source_event_id);
REVOKE UPDATE, DELETE ON billing.cost_entries FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.cost_entries TO app_api, app_worker;
GRANT SELECT ON billing.cost_entries TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.cost_entries TO app_platform_admin;
ALTER TABLE billing.cost_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.cost_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ce_tenant ON billing.cost_entries FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
