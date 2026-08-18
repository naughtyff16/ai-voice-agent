-- =================================================================
-- Migration 030 (Phase 5E): campaign.campaign_contacts (partitioned)
-- down_revision: 029_5E
-- Transaction: yes
-- Source: 5E §14.4
-- =================================================================

CREATE TABLE campaign.campaign_contacts (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  imported_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  organization_id      UUID        NOT NULL,
  campaign_id          UUID        NOT NULL,
  contact_id           UUID        NOT NULL,
  phone_e164           TEXT        NOT NULL,
  status               TEXT        NOT NULL DEFAULT 'PENDING',
  attempt_count        INTEGER     NOT NULL DEFAULT 0,
  max_attempts         INTEGER     NOT NULL,
  last_attempt_at      TIMESTAMPTZ NULL,
  next_attempt_at      TIMESTAMPTZ NULL,
  outcome              TEXT        NULL,
  qualification_result TEXT        NULL,
  qualification_reason TEXT        NULL,
  lead_score_at_call   INTEGER     NULL,
  is_dnc               BOOLEAN     NOT NULL DEFAULT FALSE,
  ineligibility_reason TEXT        NULL,
  call_session_refs    UUID[]      NOT NULL DEFAULT '{}',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaign_contacts PRIMARY KEY (id, imported_at),
  CONSTRAINT chk_cc_status        CHECK (status IN ('PENDING','CALLING','ANSWERED','NO_ANSWER','BUSY','VOICEMAIL','FAILED','RETRY_SCHEDULED','COMPLETED','QUALIFIED','DISQUALIFIED','EXHAUSTED','DNC_SKIPPED','INELIGIBLE')),
  CONSTRAINT chk_cc_attempt_count CHECK (attempt_count >= 0 AND attempt_count <= 5),
  CONSTRAINT chk_cc_max_attempts  CHECK (max_attempts BETWEEN 1 AND 5),
  CONSTRAINT chk_cc_outcome       CHECK (outcome IS NULL OR outcome IN ('ANSWERED_COMPLETED','ANSWERED_TRANSFERRED','NO_ANSWER','VOICEMAIL','FAILED','CANCELLED')),
  CONSTRAINT chk_cc_qual_result   CHECK (qualification_result IS NULL OR qualification_result IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE')),
  CONSTRAINT chk_cc_score_range   CHECK (lead_score_at_call IS NULL OR (lead_score_at_call >= 0 AND lead_score_at_call <= 100)),
  CONSTRAINT chk_cc_refs_len      CHECK (cardinality(call_session_refs) <= 5)
) PARTITION BY RANGE (imported_at);

COMMENT ON COLUMN campaign.campaign_contacts.phone_e164 IS 'pii:phone — cached; GDPR erasure sets to [erased]';
CREATE INDEX idx_cc_campaign_status  ON campaign.campaign_contacts (organization_id, campaign_id, status);
CREATE INDEX idx_cc_campaign_retry   ON campaign.campaign_contacts (campaign_id, next_attempt_at) WHERE status = 'RETRY_SCHEDULED';
CREATE INDEX idx_cc_campaign_pending ON campaign.campaign_contacts (campaign_id, id) WHERE status = 'PENDING';
CREATE INDEX idx_cc_contact_id       ON campaign.campaign_contacts (organization_id, contact_id);
CREATE INDEX idx_cc_org_time_brin    ON campaign.campaign_contacts USING BRIN (organization_id, imported_at);
CREATE TRIGGER trg_cc_updated_at BEFORE UPDATE ON campaign.campaign_contacts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE campaign.campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaign_contacts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cc_tenant ON campaign.campaign_contacts FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON campaign.campaign_contacts TO app_api, app_worker;

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'campaign_contacts_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='campaign' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE campaign.%I PARTITION OF campaign.campaign_contacts FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE campaign.campaign_contacts_default PARTITION OF campaign.campaign_contacts DEFAULT;
