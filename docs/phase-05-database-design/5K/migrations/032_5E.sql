-- =================================================================
-- Migration 032 (Phase 5E): campaign.campaign_outcomes
-- down_revision: 031_5E
-- Transaction: yes
-- Source: 5E §14.6
-- =================================================================

CREATE TABLE campaign.campaign_outcomes (
  id                          UUID           NOT NULL DEFAULT gen_uuid_v7(),
  organization_id             UUID           NOT NULL,
  campaign_id                 UUID           NOT NULL,
  computed_at                 TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  total_contacts              INTEGER        NOT NULL DEFAULT 0,
  attempted                   INTEGER        NOT NULL DEFAULT 0,
  answered                    INTEGER        NOT NULL DEFAULT 0,
  no_answer                   INTEGER        NOT NULL DEFAULT 0,
  busy                        INTEGER        NOT NULL DEFAULT 0,
  failed                      INTEGER        NOT NULL DEFAULT 0,
  voicemail                   INTEGER        NOT NULL DEFAULT 0,
  dnc_skipped                 INTEGER        NOT NULL DEFAULT 0,
  ineligible                  INTEGER        NOT NULL DEFAULT 0,
  exhausted                   INTEGER        NOT NULL DEFAULT 0,
  qualified                   INTEGER        NOT NULL DEFAULT 0,
  disqualified                INTEGER        NOT NULL DEFAULT 0,
  inconclusive                INTEGER        NOT NULL DEFAULT 0,
  answer_rate_pct             NUMERIC(5,2)   NOT NULL DEFAULT 0.00,
  qualification_rate_pct      NUMERIC(5,2)   NOT NULL DEFAULT 0.00,
  total_call_minutes          NUMERIC(12,2)  NOT NULL DEFAULT 0.00,
  total_cost_amount           NUMERIC(18,4)  NULL,
  total_cost_currency         CHAR(3)        NULL,
  estimated_revenue_amount    NUMERIC(18,4)  NULL,
  estimated_revenue_currency  CHAR(3)        NULL,
  roi_pct                     NUMERIC(8,2)   NULL,
  created_at                  TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_campaign_outcomes PRIMARY KEY (id),
  CONSTRAINT fk_co_campaign       FOREIGN KEY (campaign_id) REFERENCES campaign.campaigns(id) ON DELETE RESTRICT,
  CONSTRAINT uq_co_campaign       UNIQUE (campaign_id),
  CONSTRAINT chk_co_rates         CHECK (answer_rate_pct BETWEEN 0 AND 100 AND qualification_rate_pct BETWEEN 0 AND 100),
  CONSTRAINT chk_co_minutes       CHECK (total_call_minutes >= 0),
  CONSTRAINT chk_co_counts_nn     CHECK (total_contacts >= 0 AND attempted >= 0),
  CONSTRAINT chk_co_cost_pair     CHECK ((total_cost_amount IS NULL) = (total_cost_currency IS NULL)),
  CONSTRAINT chk_co_revenue_pair  CHECK ((estimated_revenue_amount IS NULL) = (estimated_revenue_currency IS NULL))
);
CREATE INDEX idx_co_org ON campaign.campaign_outcomes (organization_id);
CREATE TRIGGER trg_co_updated_at BEFORE UPDATE ON campaign.campaign_outcomes FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE campaign.campaign_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign.campaign_outcomes FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_co_tenant ON campaign.campaign_outcomes FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON campaign.campaign_outcomes TO app_api, app_worker;
