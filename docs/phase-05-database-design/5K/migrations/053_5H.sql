-- Migration 053 (Phase 5H): credits, credit_ledger_entries, fn_billing_apply_credit
-- down_revision: 052_5H
-- Correction: fn_billing_apply_credit gets SET search_path = billing, pg_catalog (5K §10.7)
CREATE TABLE billing.credits (
  id                UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID          NOT NULL,
  billing_account_id UUID         NOT NULL REFERENCES billing.billing_accounts(id) ON DELETE RESTRICT,
  credit_type       TEXT          NOT NULL,
  amount_amount     NUMERIC(18,4) NOT NULL,
  amount_currency   CHAR(3)       NOT NULL,
  reason            TEXT          NOT NULL,
  expires_at        TIMESTAMPTZ   NULL,
  status            TEXT          NOT NULL DEFAULT 'ACTIVE',
  created_by_ref    TEXT          NOT NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_credits      PRIMARY KEY (id),
  CONSTRAINT chk_cr_type     CHECK (credit_type IN ('PROMOTIONAL','MANUAL','REFUND_CREDIT','PRORATION_CREDIT')),
  CONSTRAINT chk_cr_amount   CHECK (amount_amount > 0),
  CONSTRAINT chk_cr_currency CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_cr_status   CHECK (status IN ('ACTIVE','CONSUMED','EXPIRED','REVERSED'))
);
CREATE INDEX idx_cr_org_status ON billing.credits (organization_id, status, expires_at);
CREATE TRIGGER trg_cr_updated_at BEFORE UPDATE ON billing.credits FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.credits ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.credits FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cr_tenant ON billing.credits FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE INSERT, UPDATE ON billing.credits FROM app_api;
GRANT SELECT ON billing.credits TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.credits TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.credits TO app_platform_admin;

CREATE TABLE billing.credit_ledger_entries (
  id              UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID          NOT NULL,
  credit_id       UUID          NOT NULL REFERENCES billing.credits(id) ON DELETE RESTRICT,
  entry_type      TEXT          NOT NULL,
  amount_amount   NUMERIC(18,4) NOT NULL,
  amount_currency CHAR(3)       NOT NULL,
  reference_type  TEXT          NULL,
  reference_id    UUID          NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_cle           PRIMARY KEY (id),
  CONSTRAINT chk_cle_type     CHECK (entry_type IN ('GRANT','CONSUMPTION','EXPIRY','REVERSAL')),
  CONSTRAINT chk_cle_currency CHECK (amount_currency ~ '^[A-Z]{3}$')
);
CREATE INDEX idx_cle_org    ON billing.credit_ledger_entries (organization_id, created_at DESC);
CREATE INDEX idx_cle_credit ON billing.credit_ledger_entries (credit_id);
REVOKE UPDATE, DELETE ON billing.credit_ledger_entries FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.credit_ledger_entries TO app_api, app_worker;
GRANT SELECT ON billing.credit_ledger_entries TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.credit_ledger_entries TO app_platform_admin;
ALTER TABLE billing.credit_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.credit_ledger_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cle_tenant ON billing.credit_ledger_entries FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

CREATE OR REPLACE FUNCTION billing.fn_billing_apply_credit(
  p_organization_id    UUID,
  p_billing_account_id UUID,
  p_credit_type        TEXT,
  p_amount             NUMERIC(18,4),
  p_currency           CHAR(3),
  p_reason             TEXT,
  p_expires_at         TIMESTAMPTZ,
  p_created_by_ref     TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE v_credit_id UUID;
BEGIN
  INSERT INTO billing.credits (organization_id, billing_account_id, credit_type, amount_amount, amount_currency, reason, expires_at, status, created_by_ref)
  VALUES (p_organization_id, p_billing_account_id, p_credit_type, p_amount, p_currency, p_reason, p_expires_at, 'ACTIVE', p_created_by_ref)
  RETURNING id INTO v_credit_id;
  INSERT INTO billing.credit_ledger_entries (organization_id, credit_id, entry_type, amount_amount, amount_currency, reference_type)
  VALUES (p_organization_id, v_credit_id, 'GRANT', p_amount, p_currency, 'CREDIT_GRANT');
  UPDATE billing.billing_accounts
  SET credit_balance_amount = credit_balance_amount + p_amount, updated_at = NOW()
  WHERE id = p_billing_account_id;
  RETURN v_credit_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_billing_apply_credit(UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_billing_apply_credit(UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, TIMESTAMPTZ, TEXT) TO app_worker, app_platform_admin;
