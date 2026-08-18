-- =================================================================
-- Migration 004 (Phase 5B): organization compliance tables
-- down_revision: 003_5B
-- Transaction: yes
-- Source: 5B §33.3 (compliance_policies, data_subject_requests)
-- Note: §33.4 in source mislabels this as "Migration 004: Seed"
--       but the 5K specification places compliance tables here
--       and seed data in migration 007. §34.1 is authoritative.
-- =================================================================

-- organization.compliance_policies
CREATE TABLE organization.compliance_policies (
  id                             UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                UUID        NOT NULL,
  name                           TEXT        NOT NULL,
  status                         TEXT        NOT NULL DEFAULT 'DRAFT',
  version                        INTEGER     NOT NULL DEFAULT 1,
  require_consent_for_outbound   BOOLEAN     NOT NULL DEFAULT TRUE,
  required_consent_purposes      TEXT[]      NOT NULL DEFAULT '{OUTBOUND_CALL}',
  recording_policy               TEXT        NOT NULL DEFAULT 'ENABLED',
  recording_disclosure_prompt_id UUID        NULL,
  calling_windows                JSONB       NOT NULL DEFAULT '[]',
  holiday_calendar_ref           TEXT        NULL,
  allowed_phone_types            TEXT[]      NOT NULL DEFAULT '{MOBILE,LANDLINE}',
  max_attempts_per_contact       INTEGER     NOT NULL DEFAULT 3,
  attempt_window_days            INTEGER     NOT NULL DEFAULT 7,
  suppression_scope              TEXT        NOT NULL DEFAULT 'ORG',
  block_on_policy_failure        BOOLEAN     NOT NULL DEFAULT TRUE,
  retention_profile              JSONB       NOT NULL DEFAULT '{}',
  policy_version                 INTEGER     NOT NULL DEFAULT 1,
  effective_from                 TIMESTAMPTZ NULL,
  created_by                     UUID        NOT NULL,
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_compliance_policies      PRIMARY KEY (id),
  CONSTRAINT fk_cp_org                   FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE RESTRICT,
  CONSTRAINT chk_cp_status               CHECK (status IN ('DRAFT','ACTIVE','ARCHIVED')),
  CONSTRAINT chk_cp_recording_policy     CHECK (recording_policy IN ('DISABLED','ENABLED','REQUIRES_CONSENT','REQUIRES_DISCLOSURE')),
  CONSTRAINT chk_cp_suppression_scope    CHECK (suppression_scope IN ('ORG','ORG_AND_PLATFORM')),
  CONSTRAINT chk_cp_max_attempts         CHECK (max_attempts_per_contact BETWEEN 1 AND 10),
  CONSTRAINT chk_cp_window_days          CHECK (attempt_window_days BETWEEN 1 AND 90)
);
CREATE UNIQUE INDEX uq_compliance_policy_active ON organization.compliance_policies (organization_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_cp_org_status ON organization.compliance_policies (organization_id, status);
CREATE TRIGGER trg_cp_updated_at BEFORE UPDATE ON organization.compliance_policies FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE organization.compliance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.compliance_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_compliance_policies_tenant ON organization.compliance_policies FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON organization.compliance_policies TO app_api, app_worker;

-- organization.data_subject_requests
CREATE TABLE organization.data_subject_requests (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id    UUID        NOT NULL,
  request_type       TEXT        NOT NULL,
  subject_contact_id UUID        NULL,
  subject_email      TEXT        NULL,
  subject_phone_e164 TEXT        NULL,
  status             TEXT        NOT NULL DEFAULT 'RECEIVED',
  requested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verified_at        TIMESTAMPTZ NULL,
  completed_at       TIMESTAMPTZ NULL,
  due_at             TIMESTAMPTZ NULL,
  requested_by       UUID        NULL,
  completed_by       UUID        NULL,
  resolution_notes   TEXT        NULL,
  export_storage_ref TEXT        NULL,
  rejection_reason   TEXT        NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_data_subject_requests  PRIMARY KEY (id),
  CONSTRAINT fk_dsr_org                FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE RESTRICT,
  CONSTRAINT chk_dsr_type              CHECK (request_type IN ('ACCESS','EXPORT','DELETE','RECTIFY','RESTRICT')),
  CONSTRAINT chk_dsr_status            CHECK (status IN ('RECEIVED','VERIFYING','IN_PROGRESS','COMPLETED','REJECTED','ON_HOLD')),
  CONSTRAINT chk_dsr_subject_present   CHECK (subject_contact_id IS NOT NULL OR subject_email IS NOT NULL OR subject_phone_e164 IS NOT NULL)
);
CREATE INDEX idx_dsr_org_status      ON organization.data_subject_requests (organization_id, status);
CREATE INDEX idx_dsr_org_requested_at ON organization.data_subject_requests (organization_id, requested_at);
CREATE INDEX idx_dsr_subject_contact ON organization.data_subject_requests (subject_contact_id) WHERE subject_contact_id IS NOT NULL;
CREATE TRIGGER trg_dsr_updated_at BEFORE UPDATE ON organization.data_subject_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE organization.data_subject_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.data_subject_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_data_subject_requests_tenant ON organization.data_subject_requests FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON organization.data_subject_requests TO app_api, app_worker;
