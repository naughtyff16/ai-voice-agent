-- =================================================================
-- Migration 024 (Phase 5D): crm.consent_records (partitioned),
--                           crm.contact_suppressions, crm.lift_suppression()
-- down_revision: 023_5D
-- Transaction: yes
-- Source: 5D §14.6
-- =================================================================

CREATE TABLE crm.consent_records (
  id                 UUID        NOT NULL DEFAULT gen_uuid_v7(),
  recorded_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  organization_id    UUID        NOT NULL,
  contact_id         UUID        NOT NULL,
  purpose            TEXT        NOT NULL,
  channel            TEXT        NOT NULL,
  status             TEXT        NOT NULL,
  source             TEXT        NOT NULL,
  source_ref         TEXT        NULL,
  evidence           JSONB       NOT NULL DEFAULT '{}',
  obtained_at        TIMESTAMPTZ NULL,
  withdrawn_at       TIMESTAMPTZ NULL,
  expires_at         TIMESTAMPTZ NULL,
  policy_version_ref INTEGER     NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_consent_records PRIMARY KEY (id, recorded_at),
  CONSTRAINT chk_cr_status  CHECK (status IN ('GRANTED','WITHDRAWN','EXPIRED','UNKNOWN')),
  CONSTRAINT chk_cr_channel CHECK (channel IN ('VOICE','SMS','WHATSAPP','EMAIL','ANY')),
  CONSTRAINT chk_cr_purpose CHECK (purpose IN ('OUTBOUND_CALL','MARKETING','TRANSACTIONAL','RECORDING','FOLLOW_UP','WHATSAPP_MESSAGING','SMS_MESSAGING','EMAIL_MESSAGING','DATA_PROCESSING','AI_INTERACTION')),
  CONSTRAINT chk_cr_source  CHECK (source IN ('WEB_FORM','VERBAL_ON_CALL','SMS_REPLY','WHATSAPP_OPT_IN','EMAIL_CONFIRMATION','CONTRACT','CSV_IMPORT_ASSERTED','API_ASSERTED','EXISTING_RELATIONSHIP','MANUAL_ENTRY'))
) PARTITION BY RANGE (recorded_at);

CREATE INDEX idx_cr_contact_purpose_channel ON crm.consent_records (organization_id, contact_id, purpose, channel, recorded_at DESC);
CREATE INDEX idx_cr_org_time_brin ON crm.consent_records USING BRIN (organization_id, recorded_at);
ALTER TABLE crm.consent_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.consent_records FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_consent_read   ON crm.consent_records FOR SELECT USING (organization_id = organization.current_tenant_id());
CREATE POLICY rls_consent_insert ON crm.consent_records FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON crm.consent_records TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.consent_records FROM app_api, app_worker;

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'consent_records_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='crm' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE crm.%I PARTITION OF crm.consent_records FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE crm.consent_records_default PARTITION OF crm.consent_records DEFAULT;

CREATE TABLE crm.contact_suppressions (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NULL,
  phone_e164      TEXT        NOT NULL,
  contact_id      UUID        NULL,
  scope           TEXT        NOT NULL,
  channel         TEXT        NOT NULL,
  reason          TEXT        NOT NULL,
  source          TEXT        NOT NULL,
  source_ref      TEXT        NULL,
  status          TEXT        NOT NULL DEFAULT 'ACTIVE',
  effective_from  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at      TIMESTAMPTZ NULL,
  lifted_at       TIMESTAMPTZ NULL,
  lifted_by_ref   UUID        NULL,
  recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_contact_suppressions PRIMARY KEY (id),
  CONSTRAINT chk_sup_scope    CHECK (scope IN ('ORG','PLATFORM','REGULATORY')),
  CONSTRAINT chk_sup_channel  CHECK (channel IN ('VOICE','SMS','WHATSAPP','EMAIL','ALL')),
  CONSTRAINT chk_sup_status   CHECK (status IN ('ACTIVE','LIFTED','EXPIRED')),
  CONSTRAINT chk_sup_reason   CHECK (reason IN ('CUSTOMER_REQUEST','REGULATORY_REGISTRY','COMPLAINT','INVALID_NUMBER','REPEATED_NO_ANSWER','HARD_BOUNCE','FRAUD_SUSPECTED','ORG_POLICY','LEGAL_HOLD','CONSENT_WITHDRAWN')),
  CONSTRAINT chk_sup_source   CHECK (source IN ('VERBAL_ON_CALL','IVR_OPT_OUT','SMS_STOP','WHATSAPP_BLOCK','EMAIL_UNSUBSCRIBE','ADMIN_ACTION','CSV_IMPORT','API','REGULATORY_SYNC','AUTOMATED_RULE')),
  CONSTRAINT chk_sup_phone    CHECK (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_sup_expires  CHECK (expires_at IS NULL OR expires_at > effective_from),
  CONSTRAINT chk_sup_scope_org_id CHECK ((scope = 'ORG' AND organization_id IS NOT NULL) OR (scope IN ('PLATFORM','REGULATORY') AND organization_id IS NULL))
);
COMMENT ON COLUMN crm.contact_suppressions.phone_e164 IS 'pii:phone — suppression key';
CREATE INDEX idx_sup_org_phone_status ON crm.contact_suppressions (organization_id, phone_e164, status);
CREATE INDEX idx_sup_platform_phone   ON crm.contact_suppressions (phone_e164, scope) WHERE scope IN ('PLATFORM','REGULATORY');
CREATE INDEX idx_sup_contact          ON crm.contact_suppressions (organization_id, contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX idx_sup_expires          ON crm.contact_suppressions (expires_at) WHERE expires_at IS NOT NULL AND status = 'ACTIVE';
ALTER TABLE crm.contact_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.contact_suppressions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_suppression_read   ON crm.contact_suppressions FOR SELECT USING (organization_id = organization.current_tenant_id() OR (organization_id IS NULL AND scope IN ('PLATFORM','REGULATORY')));
CREATE POLICY rls_suppression_insert ON crm.contact_suppressions FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id() AND scope = 'ORG');
GRANT SELECT, INSERT ON crm.contact_suppressions TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.contact_suppressions FROM app_api, app_worker;

CREATE OR REPLACE FUNCTION crm.lift_suppression(
  p_suppression_id  UUID,
  p_lifted_by_ref   UUID,
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = crm, organization, pg_temp
AS $$
DECLARE
  v_scope  TEXT;
  v_status TEXT;
  v_org_id UUID;
BEGIN
  SELECT scope, status, organization_id INTO v_scope, v_status, v_org_id
  FROM crm.contact_suppressions WHERE id = p_suppression_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Suppression record not found: %', p_suppression_id;
  END IF;
  IF v_status != 'ACTIVE' THEN
    RAISE EXCEPTION 'Suppression % is not ACTIVE (current: %). Cannot lift.', p_suppression_id, v_status;
  END IF;
  IF v_scope IN ('PLATFORM','REGULATORY') AND p_organization_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only platform administrators may lift PLATFORM/REGULATORY suppressions. suppression_id: %', p_suppression_id;
  END IF;
  IF v_scope = 'ORG' AND p_organization_id IS NOT NULL AND v_org_id IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'Tenant % does not own suppression %.', p_organization_id, p_suppression_id;
  END IF;
  UPDATE crm.contact_suppressions SET status = 'LIFTED', lifted_at = NOW(), lifted_by_ref = p_lifted_by_ref WHERE id = p_suppression_id;
END;
$$;
REVOKE ALL ON FUNCTION crm.lift_suppression(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.lift_suppression(UUID, UUID, UUID) TO app_api, app_worker, app_platform_admin;
