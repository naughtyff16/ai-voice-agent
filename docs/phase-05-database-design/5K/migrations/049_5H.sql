-- Migration 049 (Phase 5H): billing.subscriptions and billing.billing_periods
-- down_revision: 048_5H
CREATE TABLE billing.subscriptions (
  id                               UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                  UUID        NOT NULL,
  billing_account_id               UUID        NOT NULL REFERENCES billing.billing_accounts(id) ON DELETE RESTRICT,
  plan_version_id                  UUID        NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  status                           TEXT        NOT NULL DEFAULT 'TRIAL',
  current_period_start             DATE        NOT NULL,
  current_period_end               DATE        NOT NULL,
  trial_ends_at                    DATE        NULL,
  cancelled_at                     TIMESTAMPTZ NULL,
  cancellation_reason              TEXT        NULL,
  scheduled_change_plan_version_id UUID        NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  scheduled_change_effective_at    DATE        NULL,
  created_at                       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_subscriptions  PRIMARY KEY (id),
  CONSTRAINT chk_sub_status    CHECK (status IN ('TRIAL','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED')),
  CONSTRAINT chk_sub_period    CHECK (current_period_end > current_period_start),
  CONSTRAINT chk_sub_trial     CHECK (trial_ends_at IS NULL OR trial_ends_at >= current_period_start),
  CONSTRAINT chk_sub_cancelled CHECK ((status = 'CANCELLED' AND cancelled_at IS NOT NULL) OR status <> 'CANCELLED'),
  CONSTRAINT chk_sub_scheduled CHECK ((scheduled_change_plan_version_id IS NULL) = (scheduled_change_effective_at IS NULL))
);
CREATE UNIQUE INDEX uq_sub_org_active ON billing.subscriptions (organization_id) WHERE status IN ('TRIAL','ACTIVE');
CREATE INDEX idx_sub_org_status ON billing.subscriptions (organization_id, status);
CREATE INDEX idx_sub_ba         ON billing.subscriptions (billing_account_id);
CREATE TRIGGER trg_sub_updated_at BEFORE UPDATE ON billing.subscriptions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE OR REPLACE FUNCTION billing.fn_sub_cancelled_terminal() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'CANCELLED' AND NEW.status <> 'CANCELLED' THEN
    RAISE EXCEPTION 'billing: CANCELLED subscription % cannot be reactivated', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_sub_cancelled_terminal() FROM PUBLIC;
CREATE TRIGGER trg_sub_cancelled_terminal BEFORE UPDATE ON billing.subscriptions FOR EACH ROW EXECUTE FUNCTION billing.fn_sub_cancelled_terminal();
ALTER TABLE billing.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_sub_tenant ON billing.subscriptions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON billing.subscriptions TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.subscriptions TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.subscriptions TO app_platform_admin;

CREATE TABLE billing.billing_periods (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  subscription_id      UUID        NOT NULL REFERENCES billing.subscriptions(id) ON DELETE RESTRICT,
  plan_version_id      UUID        NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  period_start         DATE        NOT NULL,
  period_end           DATE        NOT NULL,
  timezone             TEXT        NOT NULL DEFAULT 'Asia/Kolkata',
  status               TEXT        NOT NULL DEFAULT 'OPEN',
  closed_at            TIMESTAMPTZ NULL,
  invoice_generated_at TIMESTAMPTZ NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_billing_periods PRIMARY KEY (id),
  CONSTRAINT uq_bp_sub_period   UNIQUE (subscription_id, period_start),
  CONSTRAINT chk_bp_period      CHECK (period_end > period_start),
  CONSTRAINT chk_bp_status      CHECK (status IN ('OPEN','CLOSED')),
  CONSTRAINT chk_bp_closed      CHECK ((status = 'CLOSED' AND closed_at IS NOT NULL) OR status = 'OPEN')
);
CREATE INDEX idx_bp_sub      ON billing.billing_periods (subscription_id, period_start DESC);
CREATE INDEX idx_bp_org_open ON billing.billing_periods (organization_id) WHERE status = 'OPEN';
ALTER TABLE billing.billing_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.billing_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_bp_tenant ON billing.billing_periods FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON billing.billing_periods TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.billing_periods TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.billing_periods TO app_platform_admin;
