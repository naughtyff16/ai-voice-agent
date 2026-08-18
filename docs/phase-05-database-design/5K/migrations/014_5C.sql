-- =================================================================
-- Migration 014 (Phase 5C): voice recordings, transcripts, transcript_segments
-- down_revision: 013_5C
-- Transaction: yes
-- Source: 5C §16.6
-- =================================================================

CREATE TABLE voice.recordings (
  id               UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID        NOT NULL,
  call_id          UUID        NOT NULL,
  conversation_id  UUID        NULL,
  status           TEXT        NOT NULL DEFAULT 'PENDING',
  storage_ref      TEXT        NULL,
  storage_provider TEXT        NULL,
  content_type     TEXT        NULL,
  duration_seconds INTEGER     NULL,
  file_size_bytes  BIGINT      NULL,
  checksum_sha256  CHAR(64)    NULL,
  recording_policy TEXT        NOT NULL,
  consent_obtained BOOLEAN     NULL,
  retention_days   INTEGER     NULL,
  delete_after     TIMESTAMPTZ NULL,
  deleted_at       TIMESTAMPTZ NULL,
  deleted_by       UUID        NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_recordings            PRIMARY KEY (id),
  CONSTRAINT chk_rec_status           CHECK (status IN ('PENDING','IN_PROGRESS','STORED','FAILED','DELETED')),
  CONSTRAINT chk_rec_policy           CHECK (recording_policy IN ('ENABLED','DISABLED','REQUIRES_CONSENT','REQUIRES_DISCLOSURE')),
  CONSTRAINT chk_rec_storage_ref_path CHECK (storage_ref IS NULL OR storage_ref LIKE 'org/%'),
  CONSTRAINT chk_rec_retention        CHECK (retention_days IS NULL OR retention_days > 0)
);
COMMENT ON COLUMN voice.recordings.storage_ref IS 'pii:voice — S3 path to audio recording';
CREATE UNIQUE INDEX uq_rec_call_id    ON voice.recordings (call_id);
CREATE        INDEX idx_rec_org_status ON voice.recordings (organization_id, status);
CREATE        INDEX idx_rec_retention ON voice.recordings (delete_after) WHERE delete_after IS NOT NULL AND status = 'STORED';
CREATE TRIGGER trg_rec_updated_at BEFORE UPDATE ON voice.recordings FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.recordings ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.recordings FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_rec_tenant ON voice.recordings FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.recordings TO app_api, app_worker;

CREATE TABLE voice.transcripts (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  conversation_id UUID        NOT NULL,
  call_id         UUID        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'IN_PROGRESS',
  total_segments  INTEGER     NOT NULL DEFAULT 0,
  completed_at    TIMESTAMPTZ NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_transcripts     PRIMARY KEY (id),
  CONSTRAINT chk_tr_status      CHECK (status IN ('IN_PROGRESS','COMPLETED')),
  CONSTRAINT chk_tr_segments_nn CHECK (total_segments >= 0)
);
CREATE UNIQUE INDEX uq_tr_conversation ON voice.transcripts (conversation_id);
CREATE        INDEX idx_tr_call_id    ON voice.transcripts (call_id);
CREATE        INDEX idx_tr_org_status ON voice.transcripts (organization_id, status);
CREATE TRIGGER trg_tr_updated_at BEFORE UPDATE ON voice.transcripts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.transcripts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tr_tenant ON voice.transcripts FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.transcripts TO app_api, app_worker;

-- voice.transcript_segments (partitioned, append-only)
CREATE TABLE voice.transcript_segments (
  id                  UUID        NOT NULL DEFAULT gen_uuid_v7(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  organization_id     UUID        NOT NULL,
  transcript_id       UUID        NOT NULL,
  conversation_id     UUID        NOT NULL,
  call_id             UUID        NOT NULL,
  sequence_number     INTEGER     NOT NULL,
  speaker             TEXT        NOT NULL,
  text                TEXT        NOT NULL,
  is_partial          BOOLEAN     NOT NULL DEFAULT FALSE,
  start_ms            INTEGER     NULL,
  end_ms              INTEGER     NULL,
  confidence          NUMERIC(4,3) NULL,
  language            TEXT        NULL,
  stt_provider_id     TEXT        NULL,
  provider_segment_id TEXT        NULL,

  CONSTRAINT pk_ts            PRIMARY KEY (id, created_at),
  CONSTRAINT chk_ts_speaker   CHECK (speaker IN ('CALLER','AGENT','SYSTEM')),
  CONSTRAINT chk_ts_confidence CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  CONSTRAINT chk_ts_seq_nn    CHECK (sequence_number >= 0)
) PARTITION BY RANGE (created_at);
COMMENT ON COLUMN voice.transcript_segments.text IS 'pii:voice — transcript text; append-only';
CREATE INDEX idx_ts_transcript_seq ON voice.transcript_segments (transcript_id, sequence_number ASC);
CREATE INDEX idx_ts_conversation   ON voice.transcript_segments (conversation_id, sequence_number ASC);
CREATE INDEX idx_ts_call_time      ON voice.transcript_segments (call_id, created_at);
CREATE INDEX idx_ts_org_time_brin  ON voice.transcript_segments USING BRIN (organization_id, created_at);
ALTER TABLE voice.transcript_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.transcript_segments FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ts_tenant ON voice.transcript_segments FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON voice.transcript_segments TO app_api, app_worker;
REVOKE UPDATE, DELETE ON voice.transcript_segments FROM app_api, app_worker;

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
    v_name  := 'transcript_segments_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='voice' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE voice.%I PARTITION OF voice.transcript_segments FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END
$$;
CREATE TABLE voice.transcript_segments_default PARTITION OF voice.transcript_segments DEFAULT;
