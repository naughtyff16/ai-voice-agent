-- =================================================================
-- Migration 028 (Phase 5E): campaign.contact_lists, campaign.csv_import_jobs
-- down_revision: 027_5E
-- Transaction: yes
-- Source: 5E §14.2
-- =================================================================

CREATE TABLE campaign.contact_lists (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  name            TEXT        NOT NULL,
  source          TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'PENDING',
  contact_count   INTEGER     NULL,
  csv_import_job_id UUID      NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_contact_lists  PRIMARY KEY (id),
  CONSTRAINT chk_cl_source     CHECK (source IN ('CSV_IMPORT','CRM_FILTER','MANUAL')),
  CONSTRAINT chk_cl_status     CHECK (status IN ('PENDING','BUILDING','READY','FAILED')),
  CONSTRAINT chk_cl_count_nn   CHECK (contact_count IS NULL OR contact_count >= 0)
);
CREATE INDEX idx_cl_org_status  ON campaign.contact_lists (organization_id, status);
CREATE INDEX idx_cl_org_created ON campaign.contact_lists (organization_id, created_at DESC);
CREATE TRIGGER trg_cl_updated_at BEFORE UPDATE ON campaign.contact_lists FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE campaign.contact_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.contact_lists FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cl_tenant ON campaign.contact_lists FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON campaign.contact_lists TO app_api, app_worker;

CREATE TABLE campaign.csv_import_jobs (
  id               UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID        NOT NULL,
  contact_list_id  UUID        NOT NULL,
  campaign_id      UUID        NULL,
  status           TEXT        NOT NULL DEFAULT 'PENDING',
  storage_ref      TEXT        NOT NULL,
  total_rows       INTEGER     NULL,
  processed_rows   INTEGER     NOT NULL DEFAULT 0,
  skipped_rows     INTEGER     NOT NULL DEFAULT 0,
  dnc_skipped_rows INTEGER     NOT NULL DEFAULT 0,
  errors           JSONB       NOT NULL DEFAULT '[]',
  created_by       UUID        NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_csv_import_jobs    PRIMARY KEY (id),
  CONSTRAINT fk_cij_contact_list   FOREIGN KEY (contact_list_id) REFERENCES campaign.contact_lists(id) ON DELETE RESTRICT,
  CONSTRAINT chk_cij_status        CHECK (status IN ('PENDING','PROCESSING','COMPLETED','FAILED')),
  CONSTRAINT chk_cij_storage_path  CHECK (storage_ref LIKE 'org/%'),
  CONSTRAINT chk_cij_rows_nn       CHECK (processed_rows >= 0 AND skipped_rows >= 0 AND dnc_skipped_rows >= 0)
);
CREATE INDEX idx_cij_contact_list ON campaign.csv_import_jobs (contact_list_id);
CREATE INDEX idx_cij_campaign     ON campaign.csv_import_jobs (campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX idx_cij_org_status   ON campaign.csv_import_jobs (organization_id, status);
CREATE TRIGGER trg_cij_updated_at BEFORE UPDATE ON campaign.csv_import_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE campaign.csv_import_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.csv_import_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cij_tenant ON campaign.csv_import_jobs FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON campaign.csv_import_jobs TO app_api, app_worker;
