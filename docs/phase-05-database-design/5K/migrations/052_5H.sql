-- Migration 052 (Phase 5H): quota_configs, tax_profiles, invoice_number_sequences + fn_allocate_invoice_number
-- down_revision: 051_5H
-- Correction: fn_allocate_invoice_number gets SET search_path = billing, pg_catalog (5K §10.7)
CREATE TABLE billing.quota_configs (
  id              UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID          NOT NULL,
  metric          TEXT          NOT NULL,
  soft_limit      NUMERIC(18,4) NULL,
  hard_limit      NUMERIC(18,4) NULL,
  unit_label      TEXT          NOT NULL,
  override_reason TEXT          NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_quota_configs    PRIMARY KEY (id),
  CONSTRAINT uq_qc_org_metric    UNIQUE (organization_id, metric),
  CONSTRAINT chk_qc_soft_limit   CHECK (soft_limit IS NULL OR soft_limit >= 0),
  CONSTRAINT chk_qc_hard_limit   CHECK (hard_limit IS NULL OR hard_limit >= 0),
  CONSTRAINT chk_qc_limits_order CHECK (soft_limit IS NULL OR hard_limit IS NULL OR soft_limit <= hard_limit)
);
CREATE TRIGGER trg_qc_updated_at BEFORE UPDATE ON billing.quota_configs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.quota_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.quota_configs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_qc_tenant ON billing.quota_configs FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT ON billing.quota_configs TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.quota_configs TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.quota_configs TO app_platform_admin;

CREATE TABLE billing.tax_profiles (
  id                       UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id          UUID        NOT NULL,
  tax_regime               TEXT        NOT NULL DEFAULT 'IN_GST',
  is_registered            BOOLEAN     NOT NULL DEFAULT FALSE,
  registration_number      TEXT        NULL,
  registration_verified_at TIMESTAMPTZ NULL,
  place_of_supply          TEXT        NULL,
  billing_address          JSONB       NOT NULL DEFAULT '{}',
  exemption_ref            TEXT        NULL,
  exemption_valid_until    DATE        NULL,
  default_tax_category_id  UUID        NULL REFERENCES billing.tax_categories(id),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_tax_profiles PRIMARY KEY (id),
  CONSTRAINT uq_tp_org       UNIQUE (organization_id)
);
COMMENT ON COLUMN billing.tax_profiles.registration_number IS 'pii:business-id — GSTIN or equivalent';
COMMENT ON COLUMN billing.tax_profiles.billing_address     IS 'pii:address';
CREATE TRIGGER trg_tp_updated_at BEFORE UPDATE ON billing.tax_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.tax_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.tax_profiles FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tp_tenant ON billing.tax_profiles FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON billing.tax_profiles TO app_api, app_worker;
GRANT SELECT ON billing.tax_profiles TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.tax_profiles TO app_platform_admin;

CREATE TABLE billing.invoice_number_sequences (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  fiscal_year     INTEGER     NOT NULL,
  prefix          TEXT        NOT NULL DEFAULT 'INV',
  next_number     INTEGER     NOT NULL DEFAULT 1,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_ins               PRIMARY KEY (id),
  CONSTRAINT uq_ins_org_fy_prefix UNIQUE (organization_id, fiscal_year, prefix),
  CONSTRAINT chk_ins_next_number  CHECK (next_number >= 1),
  CONSTRAINT chk_ins_fiscal_year  CHECK (fiscal_year >= 2024)
);
CREATE TRIGGER trg_ins_updated_at BEFORE UPDATE ON billing.invoice_number_sequences FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE billing.invoice_number_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.invoice_number_sequences FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ins_tenant ON billing.invoice_number_sequences FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE INSERT, UPDATE ON billing.invoice_number_sequences FROM app_api;
GRANT SELECT ON billing.invoice_number_sequences TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.invoice_number_sequences TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.invoice_number_sequences TO app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_allocate_invoice_number(
  p_organization_id UUID,
  p_fiscal_year     INTEGER,
  p_prefix          TEXT DEFAULT 'INV'
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE v_next INTEGER;
BEGIN
  INSERT INTO billing.invoice_number_sequences (organization_id, fiscal_year, prefix)
  VALUES (p_organization_id, p_fiscal_year, p_prefix)
  ON CONFLICT (organization_id, fiscal_year, prefix) DO NOTHING;
  UPDATE billing.invoice_number_sequences
  SET next_number = next_number + 1, updated_at = NOW()
  WHERE organization_id = p_organization_id AND fiscal_year = p_fiscal_year AND prefix = p_prefix
  RETURNING next_number - 1 INTO v_next;
  RETURN p_prefix || '/' || p_fiscal_year || '/' || LPAD(v_next::TEXT, 6, '0');
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_allocate_invoice_number(UUID, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_allocate_invoice_number(UUID, INTEGER, TEXT) TO app_worker, app_platform_admin;
