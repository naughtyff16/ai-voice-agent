-- =================================================================
-- Migration 047 (Phase 5H): billing schema, utility functions, reference tables
-- down_revision: 046_5G
-- Transaction: yes
-- Source: 5H §24 Migration 047
-- Corrections: SECURITY DEFINER functions get SET search_path = billing, pg_catalog (5K §10.7)
-- =================================================================

CREATE SCHEMA IF NOT EXISTS billing;
GRANT USAGE ON SCHEMA billing TO app_api, app_worker, app_readonly, app_platform_admin;

-- Immutability trigger factory
CREATE OR REPLACE FUNCTION billing.fn_raise_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'billing: % is immutable after finalization', TG_TABLE_NAME;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_raise_immutable() FROM PUBLIC;

-- billing.plans (platform-owned)
CREATE TABLE billing.plans (
  id          UUID        NOT NULL DEFAULT gen_uuid_v7(),
  name        TEXT        NOT NULL,
  description TEXT        NULL,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_plans      PRIMARY KEY (id),
  CONSTRAINT uq_plan_name  UNIQUE (name),
  CONSTRAINT chk_plan_name CHECK (length(name) BETWEEN 1 AND 100)
);
CREATE TRIGGER trg_plans_updated_at BEFORE UPDATE ON billing.plans FOR EACH ROW EXECUTE FUNCTION set_updated_at();
GRANT SELECT ON billing.plans TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.plans TO app_platform_admin;

-- billing.plan_versions (immutable once published)
CREATE TABLE billing.plan_versions (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  plan_id               UUID          NOT NULL REFERENCES billing.plans(id) ON DELETE RESTRICT,
  version_number        INTEGER       NOT NULL,
  billing_cycle         TEXT          NOT NULL,
  base_price_amount     NUMERIC(18,4) NOT NULL,
  base_price_currency   CHAR(3)       NOT NULL DEFAULT 'INR',
  is_published          BOOLEAN       NOT NULL DEFAULT FALSE,
  effective_from        DATE          NOT NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_plan_versions        PRIMARY KEY (id),
  CONSTRAINT uq_plan_version_number  UNIQUE (plan_id, version_number),
  CONSTRAINT chk_pv_billing_cycle    CHECK (billing_cycle IN ('MONTHLY','ANNUAL')),
  CONSTRAINT chk_pv_base_price       CHECK (base_price_amount >= 0),
  CONSTRAINT chk_pv_currency         CHECK (base_price_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_pv_version_number   CHECK (version_number >= 1)
);
CREATE OR REPLACE FUNCTION billing.fn_plan_version_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_published = TRUE THEN
    IF NEW.base_price_amount <> OLD.base_price_amount
    OR NEW.base_price_currency <> OLD.base_price_currency
    OR NEW.billing_cycle <> OLD.billing_cycle
    OR NEW.effective_from <> OLD.effective_from THEN
      RAISE EXCEPTION 'billing: plan_version % is published and immutable', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_plan_version_immutability() FROM PUBLIC;
CREATE TRIGGER trg_pv_immutability BEFORE UPDATE ON billing.plan_versions FOR EACH ROW EXECUTE FUNCTION billing.fn_plan_version_immutability();
GRANT SELECT ON billing.plan_versions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.plan_versions TO app_platform_admin;

-- billing.plan_prices
CREATE TABLE billing.plan_prices (
  id                     UUID          NOT NULL DEFAULT gen_uuid_v7(),
  plan_version_id        UUID          NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  metric                 TEXT          NOT NULL,
  unit_label             TEXT          NOT NULL,
  included_quantity      NUMERIC(18,4) NOT NULL DEFAULT 0,
  overage_rate_amount    NUMERIC(18,4) NULL,
  overage_rate_currency  CHAR(3)       NULL,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_plan_prices         PRIMARY KEY (id),
  CONSTRAINT uq_plan_price_metric   UNIQUE (plan_version_id, metric),
  CONSTRAINT chk_pp_included        CHECK (included_quantity >= 0),
  CONSTRAINT chk_pp_overage         CHECK ((overage_rate_amount IS NULL AND overage_rate_currency IS NULL) OR (overage_rate_amount IS NOT NULL AND overage_rate_currency IS NOT NULL AND overage_rate_amount >= 0)),
  CONSTRAINT chk_pp_currency        CHECK (overage_rate_currency IS NULL OR overage_rate_currency ~ '^[A-Z]{3}$')
);
GRANT SELECT ON billing.plan_prices TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.plan_prices TO app_platform_admin;

-- billing.tax_categories (HSN/SAC reference)
CREATE TABLE billing.tax_categories (
  id          UUID        NOT NULL DEFAULT gen_uuid_v7(),
  code        TEXT        NOT NULL,
  description TEXT        NOT NULL,
  regime      TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_tax_categories PRIMARY KEY (id),
  CONSTRAINT uq_tc_code_regime UNIQUE (code, regime)
);
GRANT SELECT ON billing.tax_categories TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.tax_categories TO app_platform_admin;

-- billing.tax_rules
CREATE TABLE billing.tax_rules (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  regime                 TEXT        NOT NULL,
  tax_category_id        UUID        NULL REFERENCES billing.tax_categories(id),
  supplier_jurisdiction  TEXT        NOT NULL,
  recipient_jurisdiction TEXT        NULL,
  components             JSONB       NOT NULL DEFAULT '[]',
  effective_from         DATE        NOT NULL,
  effective_to           DATE        NULL,
  rule_version           INTEGER     NOT NULL DEFAULT 1,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_tax_rules   PRIMARY KEY (id),
  CONSTRAINT chk_tr_dates   CHECK (effective_to IS NULL OR effective_to > effective_from),
  CONSTRAINT chk_tr_comp    CHECK (jsonb_typeof(components) = 'array')
);
CREATE INDEX idx_tr_regime_date ON billing.tax_rules (regime, effective_from DESC);
GRANT SELECT ON billing.tax_rules TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.tax_rules TO app_platform_admin;

-- billing.fx_rates
CREATE TABLE billing.fx_rates (
  id             UUID          NOT NULL DEFAULT gen_uuid_v7(),
  from_currency  CHAR(3)       NOT NULL,
  to_currency    CHAR(3)       NOT NULL,
  rate           NUMERIC(18,6) NOT NULL,
  rate_source    TEXT          NOT NULL DEFAULT 'manual_v1',
  effective_date DATE          NOT NULL,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_fx_rates     PRIMARY KEY (id),
  CONSTRAINT chk_fx_from     CHECK (from_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_fx_to       CHECK (to_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_fx_rate_pos CHECK (rate > 0)
);
CREATE UNIQUE INDEX uq_fx_pair_date ON billing.fx_rates (from_currency, to_currency, effective_date);
CREATE        INDEX idx_fx_pair     ON billing.fx_rates (from_currency, to_currency, effective_date DESC);
GRANT SELECT ON billing.fx_rates TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.fx_rates TO app_platform_admin;
