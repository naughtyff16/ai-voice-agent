-- =================================================================
-- Migration 023 (Phase 5D): appointments, lead_score_records, crm_field_definitions
-- down_revision: 022_5D
-- Transaction: yes
-- Source: 5D §14.5
-- =================================================================

CREATE TABLE crm.appointments (
  id                  UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID        NOT NULL,
  contact_id          UUID        NOT NULL,
  organizer_ref       UUID        NOT NULL,
  attendees           UUID[]      NOT NULL DEFAULT '{}',
  title               TEXT        NOT NULL,
  scheduled_start     TIMESTAMPTZ NOT NULL,
  scheduled_end       TIMESTAMPTZ NOT NULL,
  location_type       TEXT        NULL,
  location_detail     TEXT        NULL,
  status              TEXT        NOT NULL DEFAULT 'SCHEDULED',
  source              TEXT        NOT NULL DEFAULT 'MANUAL',
  conversation_ref    UUID        NULL,
  cancellation_reason TEXT        NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_appointments          PRIMARY KEY (id),
  CONSTRAINT chk_appt_status          CHECK (status IN ('SCHEDULED','CONFIRMED','CANCELLED','COMPLETED','NO_SHOW')),
  CONSTRAINT chk_appt_source          CHECK (source IN ('MANUAL','AI_AGENT','WORKFLOW')),
  CONSTRAINT chk_appt_location_type   CHECK (location_type IS NULL OR location_type IN ('VIRTUAL','IN_PERSON')),
  CONSTRAINT chk_appt_end_after_start CHECK (scheduled_end > scheduled_start),
  CONSTRAINT chk_appt_title_len       CHECK (length(title) BETWEEN 1 AND 200)
);
CREATE INDEX idx_appt_contact  ON crm.appointments (organization_id, contact_id, status);
CREATE INDEX idx_appt_organizer ON crm.appointments (organization_id, organizer_ref, scheduled_start);
CREATE INDEX idx_appt_status   ON crm.appointments (organization_id, status, scheduled_start);
CREATE INDEX idx_appt_upcoming ON crm.appointments (organization_id, scheduled_start) WHERE status IN ('SCHEDULED','CONFIRMED');
CREATE TRIGGER trg_appt_updated_at BEFORE UPDATE ON crm.appointments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.appointments FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_appointments_tenant ON crm.appointments FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.appointments TO app_api, app_worker;

CREATE TABLE crm.lead_score_records (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  contact_id           UUID        NOT NULL,
  score                INTEGER     NOT NULL,
  previous_score       INTEGER     NULL,
  score_version        TEXT        NOT NULL,
  signals              JSONB       NOT NULL,
  computed_at          TIMESTAMPTZ NOT NULL,
  computed_by          TEXT        NOT NULL,
  computed_by_user_ref UUID        NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_lead_score_records PRIMARY KEY (id),
  CONSTRAINT chk_lsr_score         CHECK (score >= 0 AND score <= 100),
  CONSTRAINT chk_lsr_prev_score    CHECK (previous_score IS NULL OR (previous_score >= 0 AND previous_score <= 100)),
  CONSTRAINT chk_lsr_computed_by   CHECK (computed_by IN ('RULE_ENGINE','AI_AGENT','MANUAL'))
);
CREATE INDEX idx_lsr_contact_time ON crm.lead_score_records (organization_id, contact_id, computed_at DESC);
ALTER TABLE crm.lead_score_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_score_records FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_lsr_read   ON crm.lead_score_records FOR SELECT USING (organization_id = organization.current_tenant_id());
CREATE POLICY rls_lsr_insert ON crm.lead_score_records FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON crm.lead_score_records TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.lead_score_records FROM app_api, app_worker;

CREATE TABLE crm.crm_field_definitions (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  fields          JSONB       NOT NULL DEFAULT '[]',
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_crm_field_definitions PRIMARY KEY (id)
);
CREATE UNIQUE INDEX uq_cfd_org ON crm.crm_field_definitions (organization_id);
CREATE TRIGGER trg_cfd_updated_at BEFORE UPDATE ON crm.crm_field_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.crm_field_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.crm_field_definitions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cfd_tenant ON crm.crm_field_definitions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.crm_field_definitions TO app_api, app_worker;
