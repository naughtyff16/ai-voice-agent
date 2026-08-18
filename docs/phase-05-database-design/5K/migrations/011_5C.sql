-- =================================================================
-- Migration 011 (Phase 5C): voice.call_sessions (partitioned)
-- down_revision: 010_5C
-- Transaction: yes
-- Source: 5C §16.3
-- Partition strategy: parent + DEFAULT partition created here;
--   monthly partitions created dynamically by Alembic Python helper
--   (create_monthly_partitions). In SQL-only mode we create the
--   current quarter of partitions inline at deployment time.
-- =================================================================

CREATE TABLE voice.call_sessions (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  started_at             TIMESTAMPTZ NOT NULL,
  organization_id        UUID        NOT NULL,
  direction              TEXT        NOT NULL,
  status                 TEXT        NOT NULL DEFAULT 'INITIATED',
  from_number            TEXT        NOT NULL,
  to_number              TEXT        NOT NULL,
  tenant_phone_number_id UUID        NULL,
  agent_version_id       UUID        NOT NULL,
  conversation_id        UUID        NULL,
  provider_call_ref      TEXT        NULL,
  campaign_lead_ref      TEXT        NULL,
  contact_ref            UUID        NULL,
  transfer_target        TEXT        NULL,
  sessions               JSONB       NOT NULL DEFAULT '[]',
  outcome                TEXT        NULL,
  termination_reason     TEXT        NULL,
  answered_at            TIMESTAMPTZ NULL,
  ended_at               TIMESTAMPTZ NULL,
  duration_seconds       INTEGER     NULL,
  stt_p50_ms             INTEGER     NULL,
  llm_first_token_p50_ms INTEGER     NULL,
  tts_first_audio_p50_ms INTEGER     NULL,
  turn_e2e_p50_ms        INTEGER     NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_call_sessions PRIMARY KEY (id, started_at),
  CONSTRAINT chk_cs_direction CHECK (direction IN ('INBOUND','OUTBOUND')),
  CONSTRAINT chk_cs_status    CHECK (status IN ('INITIATED','RINGING','ANSWERED','ACTIVE','ON_HOLD','TRANSFERRING','WRAP_UP','COMPLETED','FAILED','CANCELLED','NO_ANSWER','VOICEMAIL','ABANDONED','TRANSFERRED')),
  CONSTRAINT chk_cs_outcome   CHECK (outcome IS NULL OR outcome IN ('ANSWERED_COMPLETED','ANSWERED_TRANSFERRED','NO_ANSWER','VOICEMAIL','FAILED','CANCELLED')),
  CONSTRAINT chk_cs_phone_from CHECK (from_number ~ '^\+[1-9][0-9]{6,14}$'),
  CONSTRAINT chk_cs_phone_to   CHECK (to_number   ~ '^\+[1-9][0-9]{6,14}$')
) PARTITION BY RANGE (started_at);

COMMENT ON COLUMN voice.call_sessions.from_number    IS 'pii:phone — E.164 caller number';
COMMENT ON COLUMN voice.call_sessions.to_number      IS 'pii:phone — E.164 called number';
COMMENT ON COLUMN voice.call_sessions.transfer_target IS 'pii:phone — transfer destination';

CREATE INDEX idx_cs_org_status    ON voice.call_sessions (organization_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_cs_org_started   ON voice.call_sessions (organization_id, started_at DESC);
CREATE INDEX idx_cs_conversation  ON voice.call_sessions (conversation_id) WHERE conversation_id IS NOT NULL;
CREATE INDEX idx_cs_agent_version ON voice.call_sessions (organization_id, agent_version_id, started_at);
CREATE INDEX idx_cs_provider_ref  ON voice.call_sessions (provider_call_ref) WHERE provider_call_ref IS NOT NULL;
CREATE INDEX idx_cs_campaign_lead ON voice.call_sessions (campaign_lead_ref) WHERE campaign_lead_ref IS NOT NULL;
CREATE INDEX idx_cs_from_number   ON voice.call_sessions (organization_id, from_number);
CREATE INDEX idx_cs_started_brin  ON voice.call_sessions USING BRIN (organization_id, started_at);

CREATE TRIGGER trg_cs_updated_at BEFORE UPDATE ON voice.call_sessions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.call_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.call_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cs_tenant ON voice.call_sessions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.call_sessions TO app_api, app_worker;

-- Dynamic partitions via DO block (equivalent to Alembic Python helper)
DO $$
DECLARE
  v_start DATE;
  v_end   DATE;
  v_name  TEXT;
  v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'call_sessions_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                   WHERE n.nspname='voice' AND c.relname=v_name) THEN
      EXECUTE format(
        'CREATE TABLE voice.%I PARTITION OF voice.call_sessions FOR VALUES FROM (%L) TO (%L)',
        v_name, v_start, v_end);
    END IF;
  END LOOP;
END
$$;

CREATE TABLE voice.call_sessions_default
  PARTITION OF voice.call_sessions DEFAULT;
