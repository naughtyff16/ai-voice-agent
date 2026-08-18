-- Migration 056 (Phase 5H): billing.billing_adjustments
-- down_revision: 055_5H
CREATE TABLE billing.billing_adjustments (
  id              UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID          NOT NULL,
  invoice_id      UUID          NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  adjustment_type TEXT          NOT NULL,
  description     TEXT          NOT NULL,
  amount_amount   NUMERIC(18,4) NOT NULL,
  amount_currency CHAR(3)       NOT NULL,
  created_by_ref  TEXT          NOT NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_billing_adjustments PRIMARY KEY (id),
  CONSTRAINT chk_ba_type            CHECK (adjustment_type IN ('CREDIT_NOTE','DEBIT_NOTE','MANUAL_CORRECTION','WRITE_OFF')),
  CONSTRAINT chk_ba_currency        CHECK (amount_currency ~ '^[A-Z]{3}$')
);
CREATE INDEX idx_badj_org     ON billing.billing_adjustments (organization_id);
CREATE INDEX idx_badj_invoice ON billing.billing_adjustments (invoice_id) WHERE invoice_id IS NOT NULL;
REVOKE UPDATE, DELETE ON billing.billing_adjustments FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.billing_adjustments TO app_worker;
GRANT SELECT ON billing.billing_adjustments TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.billing_adjustments TO app_platform_admin;
ALTER TABLE billing.billing_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.billing_adjustments FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_badj_tenant ON billing.billing_adjustments FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
