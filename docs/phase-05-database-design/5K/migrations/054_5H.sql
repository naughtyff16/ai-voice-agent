-- Migration 054 (Phase 5H): invoices, invoice_lines, tax_lines
-- down_revision: 053_5H
CREATE TABLE billing.invoices (
  id                        UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id           UUID          NOT NULL,
  billing_account_id        UUID          NOT NULL REFERENCES billing.billing_accounts(id) ON DELETE RESTRICT,
  billing_period_id         UUID          NULL REFERENCES billing.billing_periods(id) ON DELETE RESTRICT,
  subscription_id           UUID          NULL REFERENCES billing.subscriptions(id) ON DELETE RESTRICT,
  invoice_number            TEXT          NULL,
  invoice_kind              TEXT          NOT NULL DEFAULT 'TAX_INVOICE',
  status                    TEXT          NOT NULL DEFAULT 'DRAFT',
  currency                  CHAR(3)       NOT NULL,
  subtotal_amount           NUMERIC(18,4) NOT NULL DEFAULT 0,
  subtotal_currency         CHAR(3)       NOT NULL,
  total_credits_amount      NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_credits_currency    CHAR(3)       NOT NULL,
  total_tax_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_tax_currency        CHAR(3)       NOT NULL,
  total_due_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_due_currency        CHAR(3)       NOT NULL,
  amount_paid_amount        NUMERIC(18,4) NOT NULL DEFAULT 0,
  amount_paid_currency      CHAR(3)       NOT NULL,
  issue_date                DATE          NULL,
  due_date                  DATE          NULL,
  paid_at                   TIMESTAMPTZ   NULL,
  voided_at                 TIMESTAMPTZ   NULL,
  void_reason               TEXT          NULL,
  related_invoice_id        UUID          NULL REFERENCES billing.invoices(id),
  place_of_supply           TEXT          NULL,
  tax_profile_snapshot      JSONB         NOT NULL DEFAULT '{}',
  tax_rule_versions_applied INTEGER[]     NOT NULL DEFAULT '{}',
  e_invoice_ref             TEXT          NULL,
  notes                     TEXT          NULL,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_invoices          PRIMARY KEY (id),
  CONSTRAINT uq_invoice_number    UNIQUE (organization_id, invoice_number) DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT chk_inv_status       CHECK (status IN ('DRAFT','OPEN','PAID','VOID')),
  CONSTRAINT chk_inv_kind         CHECK (invoice_kind IN ('TAX_INVOICE','CREDIT_NOTE','DEBIT_NOTE','PROFORMA')),
  CONSTRAINT chk_inv_currency     CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_inv_total_due    CHECK (total_due_amount >= 0),
  CONSTRAINT chk_inv_amount_paid  CHECK (amount_paid_amount >= 0),
  CONSTRAINT chk_inv_paid_status  CHECK ((status = 'PAID' AND paid_at IS NOT NULL) OR status <> 'PAID'),
  CONSTRAINT chk_inv_void_status  CHECK ((status = 'VOID' AND voided_at IS NOT NULL) OR status <> 'VOID'),
  CONSTRAINT chk_inv_number_open  CHECK ((status IN ('OPEN','PAID','VOID') AND invoice_number IS NOT NULL) OR status = 'DRAFT')
);
CREATE INDEX idx_inv_org_status ON billing.invoices (organization_id, status);
CREATE INDEX idx_inv_period     ON billing.invoices (billing_period_id) WHERE billing_period_id IS NOT NULL;
CREATE INDEX idx_inv_sub        ON billing.invoices (subscription_id) WHERE subscription_id IS NOT NULL;
CREATE OR REPLACE FUNCTION billing.fn_invoice_immutability() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('PAID','VOID') THEN
    IF NEW.subtotal_amount <> OLD.subtotal_amount OR NEW.total_credits_amount <> OLD.total_credits_amount
    OR NEW.total_tax_amount <> OLD.total_tax_amount OR NEW.total_due_amount <> OLD.total_due_amount
    OR NEW.billing_period_id IS DISTINCT FROM OLD.billing_period_id OR NEW.currency <> OLD.currency THEN
      RAISE EXCEPTION 'billing: invoice % is % and immutable', OLD.id, OLD.status;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_invoice_immutability() FROM PUBLIC;
CREATE TRIGGER trg_inv_immutability BEFORE UPDATE ON billing.invoices FOR EACH ROW EXECUTE FUNCTION billing.fn_invoice_immutability();
CREATE TRIGGER trg_inv_updated_at   BEFORE UPDATE ON billing.invoices FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_inv_tenant ON billing.invoices FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON billing.invoices TO app_api, app_readonly;
GRANT SELECT, INSERT ON billing.invoices TO app_worker;
REVOKE UPDATE, DELETE ON billing.invoices FROM app_api, app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.invoices TO app_platform_admin;

CREATE TABLE billing.invoice_lines (
  id                  UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID          NOT NULL,
  invoice_id          UUID          NOT NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  line_type           TEXT          NOT NULL,
  description         TEXT          NOT NULL,
  metric              TEXT          NULL,
  billing_period_id   UUID          NULL,
  quantity            NUMERIC(18,4) NOT NULL DEFAULT 1,
  unit_price_amount   NUMERIC(18,4) NOT NULL,
  unit_price_currency CHAR(3)       NOT NULL,
  line_total_amount   NUMERIC(18,4) NOT NULL,
  line_total_currency CHAR(3)       NOT NULL,
  sort_order          INTEGER       NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_invoice_lines PRIMARY KEY (id),
  CONSTRAINT chk_il_type      CHECK (line_type IN ('BASE_FEE','USAGE','OVERAGE','CREDIT','DISCOUNT','TAX','ADJUSTMENT')),
  CONSTRAINT chk_il_currency  CHECK (unit_price_currency ~ '^[A-Z]{3}$')
);
CREATE INDEX idx_il_invoice ON billing.invoice_lines (invoice_id);
REVOKE UPDATE, DELETE ON billing.invoice_lines FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.invoice_lines TO app_api, app_worker;
GRANT SELECT ON billing.invoice_lines TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.invoice_lines TO app_platform_admin;
ALTER TABLE billing.invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.invoice_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_il_tenant ON billing.invoice_lines FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

CREATE TABLE billing.tax_lines (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID          NOT NULL,
  invoice_id              UUID          NOT NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  invoice_line_id         UUID          NULL REFERENCES billing.invoice_lines(id) ON DELETE RESTRICT,
  component_code          TEXT          NOT NULL,
  rate_percent            NUMERIC(8,4)  NOT NULL,
  taxable_amount_amount   NUMERIC(18,4) NOT NULL,
  taxable_amount_currency CHAR(3)       NOT NULL,
  tax_amount_amount       NUMERIC(18,4) NOT NULL,
  tax_amount_currency     CHAR(3)       NOT NULL,
  tax_rule_version        INTEGER       NOT NULL,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_tax_lines      PRIMARY KEY (id),
  CONSTRAINT chk_tl_rate       CHECK (rate_percent >= 0),
  CONSTRAINT chk_tl_tax_amount CHECK (tax_amount_amount >= 0),
  CONSTRAINT chk_tl_currency   CHECK (taxable_amount_currency ~ '^[A-Z]{3}$')
);
CREATE INDEX idx_tl_invoice ON billing.tax_lines (invoice_id);
REVOKE UPDATE, DELETE ON billing.tax_lines FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.tax_lines TO app_api, app_worker;
GRANT SELECT ON billing.tax_lines TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.tax_lines TO app_platform_admin;
ALTER TABLE billing.tax_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.tax_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tl_tenant ON billing.tax_lines FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
