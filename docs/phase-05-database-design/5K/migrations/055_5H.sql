-- Migration 055 (Phase 5H): payment_attempts, refunds, fn_validate_refund_amount
-- down_revision: 054_5H
CREATE TABLE billing.payment_attempts (
  id                        UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id           UUID          NOT NULL,
  invoice_id                UUID          NOT NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  payment_provider          TEXT          NOT NULL,
  provider_transaction_id   TEXT          NOT NULL,
  provider_webhook_event_id TEXT          NULL,
  payment_method_ref        TEXT          NULL,
  status                    TEXT          NOT NULL DEFAULT 'INITIATED',
  amount_amount             NUMERIC(18,4) NOT NULL,
  amount_currency           CHAR(3)       NOT NULL,
  failure_code              TEXT          NULL,
  failure_message           TEXT          NULL,
  initiated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  completed_at              TIMESTAMPTZ   NULL,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_payment_attempts PRIMARY KEY (id),
  CONSTRAINT uq_pa_provider_tx   UNIQUE (payment_provider, provider_transaction_id),
  CONSTRAINT uq_pa_webhook_event UNIQUE (payment_provider, provider_webhook_event_id) DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT chk_pa_status       CHECK (status IN ('INITIATED','PENDING','SUCCEEDED','FAILED','CANCELLED')),
  CONSTRAINT chk_pa_amount       CHECK (amount_amount > 0),
  CONSTRAINT chk_pa_currency     CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_pa_provider     CHECK (payment_provider IN ('RAZORPAY','CASHFREE','STRIPE','OTHER'))
);
CREATE INDEX idx_pa_invoice    ON billing.payment_attempts (invoice_id);
CREATE INDEX idx_pa_org_status ON billing.payment_attempts (organization_id, status);
REVOKE UPDATE, DELETE ON billing.payment_attempts FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.payment_attempts TO app_api, app_worker;
GRANT SELECT ON billing.payment_attempts TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.payment_attempts TO app_platform_admin;
ALTER TABLE billing.payment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.payment_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pa_tenant ON billing.payment_attempts FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

CREATE TABLE billing.refunds (
  id                 UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id    UUID          NOT NULL,
  payment_attempt_id UUID          NOT NULL REFERENCES billing.payment_attempts(id) ON DELETE RESTRICT,
  payment_provider   TEXT          NOT NULL,
  provider_refund_id TEXT          NOT NULL,
  amount_amount      NUMERIC(18,4) NOT NULL,
  amount_currency    CHAR(3)       NOT NULL,
  reason             TEXT          NOT NULL,
  status             TEXT          NOT NULL DEFAULT 'PENDING',
  initiated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  completed_at       TIMESTAMPTZ   NULL,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_refunds           PRIMARY KEY (id),
  CONSTRAINT uq_refund_provider   UNIQUE (payment_provider, provider_refund_id),
  CONSTRAINT chk_ref_status       CHECK (status IN ('PENDING','SUCCEEDED','FAILED')),
  CONSTRAINT chk_ref_amount       CHECK (amount_amount > 0),
  CONSTRAINT chk_ref_currency     CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ref_provider     CHECK (payment_provider IN ('RAZORPAY','CASHFREE','STRIPE','OTHER'))
);
CREATE INDEX idx_ref_payment ON billing.refunds (payment_attempt_id);
CREATE INDEX idx_ref_org     ON billing.refunds (organization_id);
REVOKE UPDATE, DELETE ON billing.refunds FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.refunds TO app_api, app_worker;
GRANT SELECT ON billing.refunds TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.refunds TO app_platform_admin;
ALTER TABLE billing.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.refunds FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ref_tenant ON billing.refunds FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

CREATE OR REPLACE FUNCTION billing.fn_validate_refund_amount()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_paid NUMERIC(18,4); v_refunded NUMERIC(18,4);
BEGIN
  SELECT pa.amount_amount INTO v_paid FROM billing.payment_attempts pa WHERE pa.id = NEW.payment_attempt_id;
  SELECT COALESCE(SUM(r.amount_amount), 0) INTO v_refunded FROM billing.refunds r
  WHERE r.payment_attempt_id = NEW.payment_attempt_id AND r.status IN ('PENDING','SUCCEEDED') AND r.id <> NEW.id;
  IF (v_refunded + NEW.amount_amount) > v_paid THEN
    RAISE EXCEPTION 'billing: refund would exceed original payment amount';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_validate_refund_amount() FROM PUBLIC;
CREATE TRIGGER trg_refund_amount_check BEFORE INSERT ON billing.refunds FOR EACH ROW EXECUTE FUNCTION billing.fn_validate_refund_amount();
