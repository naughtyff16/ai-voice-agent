-- Migration 048 (Phase 5H): billing.billing_accounts
-- down_revision: 047_5H
CREATE TABLE billing.billing_accounts (
  id                      UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID          NOT NULL,
  billing_status          TEXT          NOT NULL DEFAULT 'ACTIVE',
  currency                CHAR(3)       NOT NULL DEFAULT 'INR',
  billing_contact_name    TEXT          NULL,
  billing_contact_email   TEXT          NULL,
  grace_period_ends_at    TIMESTAMPTZ   NULL,
  credit_balance_amount   NUMERIC(18,4) NOT NULL DEFAULT 0,
  credit_balance_currency CHAR(3)       NOT NULL DEFAULT 'INR',
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_billing_accounts   PRIMARY KEY (id),
  CONSTRAINT uq_ba_org             UNIQUE (organization_id),
  CONSTRAINT chk_ba_status         CHECK (billing_status IN ('ACTIVE','PAST_DUE','SUSPENDED','CLOSED')),
  CONSTRAINT chk_ba_currency       CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ba_credit_balance CHECK (credit_balance_amount >= 0),
  CONSTRAINT chk_ba_grace_period   CHECK ((billing_status = 'PAST_DUE' AND grace_period_ends_at IS NOT NULL) OR (billing_status <> 'PAST_DUE'))
);
COMMENT ON COLUMN billing.billing_accounts.billing_contact_name  IS 'pii:name';
COMMENT ON COLUMN billing.billing_accounts.billing_contact_email IS 'pii:email';
CREATE OR REPLACE FUNCTION billing.fn_ba_currency_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.currency <> OLD.currency THEN RAISE EXCEPTION 'billing_accounts.currency is immutable'; END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_ba_currency_immutable() FROM PUBLIC;
CREATE TRIGGER trg_ba_currency_immutable BEFORE UPDATE ON billing.billing_accounts FOR EACH ROW EXECUTE FUNCTION billing.fn_ba_currency_immutable();
CREATE TRIGGER trg_ba_updated_at BEFORE UPDATE ON billing.billing_accounts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.billing_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.billing_accounts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ba_tenant ON billing.billing_accounts FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON billing.billing_accounts TO app_api, app_worker;
GRANT SELECT ON billing.billing_accounts TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.billing_accounts TO app_platform_admin;
