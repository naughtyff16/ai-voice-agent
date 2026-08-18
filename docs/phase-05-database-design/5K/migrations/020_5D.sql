-- =================================================================
-- Migration 020 (Phase 5D): crm.contacts and crm.companies
-- down_revision: 019_5D
-- Transaction: yes
-- Source: 5D §14.2
-- =================================================================

CREATE TABLE crm.contacts (
  id                       UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id          UUID        NOT NULL,
  full_name                TEXT        NOT NULL,
  phone_e164               TEXT        NOT NULL,
  phone_country            TEXT        NOT NULL,
  phone_type               TEXT        NULL,
  phone_verified           BOOLEAN     NOT NULL DEFAULT FALSE,
  phone_normalized_at      TIMESTAMPTZ NULL,
  communication_status     TEXT        NOT NULL DEFAULT 'UNKNOWN',
  secondary_phone_e164     TEXT        NULL,
  primary_email            TEXT        NULL,
  primary_email_normalized TEXT        NULL,
  company_id               UUID        NULL,
  owned_by                 UUID        NULL,
  lead_status              TEXT        NOT NULL DEFAULT 'NEW',
  qualification_status     TEXT        NOT NULL DEFAULT 'UNSET',
  qualification_reason     TEXT        NULL,
  lead_score               INTEGER     NULL,
  lead_temperature         TEXT        NULL,
  tags                     TEXT[]      NOT NULL DEFAULT '{}',
  address_line1            TEXT        NULL,
  address_line2            TEXT        NULL,
  address_city             TEXT        NULL,
  address_state            TEXT        NULL,
  address_postal_code      TEXT        NULL,
  address_country_code     TEXT        NULL,
  source                   TEXT        NOT NULL,
  campaign_ref             UUID        NULL,
  do_not_call              BOOLEAN     NOT NULL DEFAULT FALSE,
  consent_status           TEXT        NOT NULL DEFAULT 'UNKNOWN',
  last_contacted_at        TIMESTAMPTZ NULL,
  converted_at             TIMESTAMPTZ NULL,
  custom_field_values      JSONB       NOT NULL DEFAULT '[]',
  deleted_at               TIMESTAMPTZ NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_contacts               PRIMARY KEY (id),
  CONSTRAINT chk_contacts_lead_status  CHECK (lead_status IN ('NEW','CONTACTED','QUALIFIED','DISQUALIFIED','NURTURING','CONVERTED')),
  CONSTRAINT chk_contacts_qual_status  CHECK (qualification_status IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE','UNSET')),
  CONSTRAINT chk_contacts_score        CHECK (lead_score IS NULL OR (lead_score >= 0 AND lead_score <= 100)),
  CONSTRAINT chk_contacts_temperature  CHECK (lead_temperature IS NULL OR lead_temperature IN ('HOT','WARM','COLD','UNSCORED')),
  CONSTRAINT chk_contacts_source       CHECK (source IN ('INBOUND_CALL','OUTBOUND_CALL','CSV_IMPORT','MANUAL','API','WEBHOOK')),
  CONSTRAINT chk_contacts_consent      CHECK (consent_status IN ('UNKNOWN','GIVEN','WITHDRAWN')),
  CONSTRAINT chk_contacts_comm_status  CHECK (communication_status IN ('REACHABLE','UNREACHABLE','INVALID','UNKNOWN')),
  CONSTRAINT chk_contacts_phone        CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_contacts_sec_phone    CHECK (secondary_phone_e164 IS NULL OR secondary_phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_contacts_tag_count    CHECK (cardinality(tags) <= 20)
);
COMMENT ON COLUMN crm.contacts.full_name IS 'pii:name';
COMMENT ON COLUMN crm.contacts.phone_e164 IS 'pii:phone — canonical E.164';
COMMENT ON COLUMN crm.contacts.do_not_call IS 'DENORMALIZED from contact_suppressions';
CREATE UNIQUE INDEX uq_contacts_phone     ON crm.contacts (organization_id, phone_e164) WHERE deleted_at IS NULL;
CREATE        INDEX idx_contacts_org_lead_status    ON crm.contacts (organization_id, lead_status);
CREATE        INDEX idx_contacts_org_score          ON crm.contacts (organization_id, lead_score DESC) WHERE lead_score IS NOT NULL;
CREATE        INDEX idx_contacts_org_temperature    ON crm.contacts (organization_id, lead_temperature) WHERE lead_temperature IN ('HOT','WARM');
CREATE        INDEX idx_contacts_org_qualification  ON crm.contacts (organization_id, qualification_status) WHERE qualification_status != 'UNSET';
CREATE        INDEX idx_contacts_company            ON crm.contacts (organization_id, company_id) WHERE company_id IS NOT NULL;
CREATE        INDEX idx_contacts_campaign           ON crm.contacts (organization_id, campaign_ref) WHERE campaign_ref IS NOT NULL;
CREATE        INDEX idx_contacts_owner              ON crm.contacts (organization_id, owned_by) WHERE owned_by IS NOT NULL;
CREATE        INDEX idx_contacts_email_norm         ON crm.contacts (organization_id, primary_email_normalized) WHERE primary_email_normalized IS NOT NULL;
CREATE        INDEX idx_contacts_last_contacted     ON crm.contacts (organization_id, last_contacted_at DESC) WHERE last_contacted_at IS NOT NULL;
CREATE        INDEX idx_contacts_org_created        ON crm.contacts (organization_id, created_at DESC);
CREATE TRIGGER trg_contacts_updated_at BEFORE UPDATE ON crm.contacts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.contacts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_contacts_tenant ON crm.contacts FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.contacts TO app_api, app_worker;

CREATE TABLE crm.companies (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  company_name         TEXT        NOT NULL,
  email_domain         TEXT        NULL,
  industry             TEXT        NULL,
  size                 TEXT        NULL,
  website              TEXT        NULL,
  address_line1        TEXT        NULL,
  address_line2        TEXT        NULL,
  address_city         TEXT        NULL,
  address_state        TEXT        NULL,
  address_postal_code  TEXT        NULL,
  address_country_code TEXT        NULL,
  owned_by             UUID        NULL,
  custom_field_values  JSONB       NOT NULL DEFAULT '[]',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_companies  PRIMARY KEY (id),
  CONSTRAINT chk_comp_size CHECK (size IS NULL OR size IN ('STARTUP','SMB','MID_MARKET','ENTERPRISE'))
);
CREATE UNIQUE INDEX uq_companies_domain ON crm.companies (organization_id, email_domain) WHERE email_domain IS NOT NULL;
CREATE        INDEX idx_companies_org   ON crm.companies (organization_id);
CREATE        INDEX idx_companies_owner ON crm.companies (organization_id, owned_by) WHERE owned_by IS NOT NULL;
CREATE TRIGGER trg_companies_updated_at BEFORE UPDATE ON crm.companies FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.companies FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_companies_tenant ON crm.companies FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.companies TO app_api, app_worker;
