-- =================================================================
-- Migration 029 (Phase 5E): campaign.campaigns
-- down_revision: 028_5E
-- Transaction: yes
-- Source: 5E §14.3
-- Correction: index on (scheduling_policy->>'start_at')::timestamptz
--   is NOT IMMUTABLE and cannot be used in an index expression (5K §10.3).
--   Index uses raw ISO-8601 text instead, which sorts identically for
--   the APScheduler poll query (start_at >= NOW()::text comparisons
--   should use text-based scheduler queries) and passes PostgreSQL's
--   IMMUTABLE requirement for expression indexes.
-- =================================================================

CREATE TABLE campaign.campaigns (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NOT NULL,
  name                   TEXT        NOT NULL,
  description            TEXT        NULL,
  status                 TEXT        NOT NULL DEFAULT 'DRAFT',
  agent_id               UUID        NOT NULL,
  agent_version_id       UUID        NULL,
  phone_number_id        UUID        NOT NULL,
  contact_list_id        UUID        NULL,
  scheduling_policy      JSONB       NOT NULL DEFAULT '{}',
  concurrency_policy     JSONB       NOT NULL DEFAULT '{}',
  rate_limit_policy      JSONB       NOT NULL DEFAULT '{}',
  retry_policy           JSONB       NOT NULL DEFAULT '{}',
  qualification_criteria JSONB       NULL,
  total_contacts         INTEGER     NULL,
  started_at             TIMESTAMPTZ NULL,
  completed_at           TIMESTAMPTZ NULL,
  cancelled_at           TIMESTAMPTZ NULL,
  created_by             UUID        NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaigns         PRIMARY KEY (id),
  CONSTRAINT chk_camp_status      CHECK (status IN ('DRAFT','SCHEDULED','PREPARING','RUNNING','PAUSED','STOPPING','COMPLETED','CANCELLED','FAILED')),
  CONSTRAINT chk_camp_name_len    CHECK (length(name) BETWEEN 1 AND 200),
  CONSTRAINT chk_camp_contacts_nn CHECK (total_contacts IS NULL OR total_contacts >= 0)
);

COMMENT ON COLUMN campaign.campaigns.scheduling_policy IS 'start_at: ISO-8601 string in scheduling_policy JSONB';

CREATE INDEX idx_camp_org_status  ON campaign.campaigns (organization_id, status);
CREATE INDEX idx_camp_org_created ON campaign.campaigns (organization_id, created_at DESC);
CREATE INDEX idx_camp_org_running ON campaign.campaigns (organization_id) WHERE status IN ('RUNNING','PAUSED','STOPPING');

-- Corrected index: index on raw text (IMMUTABLE) instead of ::timestamptz cast
-- (5K §10.3: ::timestamptz is not IMMUTABLE so it cannot appear in an index expression)
CREATE INDEX idx_camp_due_for_start
  ON campaign.campaigns ((scheduling_policy->>'start_at'))
  WHERE status = 'SCHEDULED';

CREATE TRIGGER trg_camp_updated_at BEFORE UPDATE ON campaign.campaigns FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE campaign.campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaigns FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_camp_tenant ON campaign.campaigns FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON campaign.campaigns TO app_api, app_worker;
