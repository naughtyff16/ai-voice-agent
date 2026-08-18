-- =================================================================
-- Migration 031 (Phase 5E): campaign.call_jobs
-- down_revision: 030_5E
-- Transaction: yes
-- Source: 5E §14.5
-- =================================================================

CREATE TABLE campaign.call_jobs (
  id                  UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID        NOT NULL,
  campaign_id         UUID        NOT NULL,
  campaign_contact_id UUID        NOT NULL,
  phone_e164          TEXT        NOT NULL,
  attempt_number      INTEGER     NOT NULL,
  idempotency_key     CHAR(64)    NOT NULL,
  status              TEXT        NOT NULL DEFAULT 'PENDING',
  call_session_id     UUID        NULL,
  dispatched_at       TIMESTAMPTZ NULL,
  completed_at        TIMESTAMPTZ NULL,
  failure_reason      TEXT        NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_call_jobs          PRIMARY KEY (id),
  CONSTRAINT chk_cj_status         CHECK (status IN ('PENDING','DISPATCHED','SUCCEEDED','FAILED','SUPERSEDED')),
  CONSTRAINT chk_cj_attempt_number CHECK (attempt_number >= 1 AND attempt_number <= 5)
);
COMMENT ON COLUMN campaign.call_jobs.idempotency_key IS 'SHA-256(campaign_id+campaign_contact_id+attempt_number)';
COMMENT ON COLUMN campaign.call_jobs.phone_e164      IS 'pii:phone — GDPR erasure sets to [erased]';
CREATE UNIQUE INDEX uq_cj_idempotency_active  ON campaign.call_jobs (idempotency_key) WHERE status IN ('PENDING','DISPATCHED');
CREATE        INDEX idx_cj_campaign_contact   ON campaign.call_jobs (organization_id, campaign_contact_id);
CREATE        INDEX idx_cj_call_session       ON campaign.call_jobs (call_session_id) WHERE call_session_id IS NOT NULL;
CREATE        INDEX idx_cj_campaign_active    ON campaign.call_jobs (campaign_id, status) WHERE status IN ('PENDING','DISPATCHED');
CREATE TRIGGER trg_cj_updated_at BEFORE UPDATE ON campaign.call_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE campaign.call_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.call_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cj_tenant ON campaign.call_jobs FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON campaign.call_jobs TO app_api, app_worker;
