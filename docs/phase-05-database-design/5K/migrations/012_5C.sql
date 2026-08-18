-- =================================================================
-- Migration 012 (Phase 5C): voice.conversations and voice.turns
-- down_revision: 011_5C
-- Transaction: yes
-- Source: 5C §16.4
-- =================================================================

CREATE TABLE voice.conversations (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NOT NULL,
  call_id                UUID        NOT NULL,
  agent_version_id       UUID        NOT NULL,
  contact_ref            UUID        NULL,
  status                 TEXT        NOT NULL DEFAULT 'ACTIVE',
  qualification_outcome  TEXT        NULL,
  sentiment_label        TEXT        NULL,
  sentiment_score        NUMERIC(4,3) NULL,
  summary_text           TEXT        NULL,
  prompt_tokens_used     INTEGER     NOT NULL DEFAULT 0,
  completion_tokens_used INTEGER     NOT NULL DEFAULT 0,
  total_tokens_used      INTEGER     NOT NULL DEFAULT 0,
  total_turns            INTEGER     NOT NULL DEFAULT 0,
  started_at             TIMESTAMPTZ NOT NULL,
  completed_at           TIMESTAMPTZ NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_conversations        PRIMARY KEY (id),
  CONSTRAINT chk_conv_status         CHECK (status IN ('ACTIVE','COMPLETED','SUMMARIZED')),
  CONSTRAINT chk_conv_qualification  CHECK (qualification_outcome IS NULL OR qualification_outcome IN ('QUALIFIED','DISQUALIFIED','INCONCLUSIVE')),
  CONSTRAINT chk_conv_sent_label     CHECK (sentiment_label IS NULL OR sentiment_label IN ('POSITIVE','NEUTRAL','NEGATIVE')),
  CONSTRAINT chk_conv_sent_score     CHECK (sentiment_score IS NULL OR sentiment_score BETWEEN 0 AND 1),
  CONSTRAINT chk_conv_tokens_nn      CHECK (prompt_tokens_used >= 0 AND completion_tokens_used >= 0 AND total_tokens_used >= 0)
);
COMMENT ON COLUMN voice.conversations.summary_text IS 'pii:voice — LLM-generated call summary';
CREATE UNIQUE INDEX uq_conv_call_id     ON voice.conversations (call_id);
CREATE        INDEX idx_conv_org_status ON voice.conversations (organization_id, status);
CREATE        INDEX idx_conv_contact    ON voice.conversations (organization_id, contact_ref) WHERE contact_ref IS NOT NULL;
CREATE        INDEX idx_conv_qualified  ON voice.conversations (organization_id, qualification_outcome) WHERE qualification_outcome = 'QUALIFIED';
CREATE        INDEX idx_conv_org_started ON voice.conversations (organization_id, started_at DESC);
CREATE TRIGGER trg_conv_updated_at BEFORE UPDATE ON voice.conversations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.conversations FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_conv_tenant ON voice.conversations FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.conversations TO app_api, app_worker;

CREATE TABLE voice.turns (
  id                              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                 UUID        NOT NULL,
  conversation_id                 UUID        NOT NULL,
  sequence_number                 INTEGER     NOT NULL,
  speaker_role                    TEXT        NOT NULL,
  utterance_text                  TEXT        NULL,
  utterance_confidence            NUMERIC(4,3) NULL,
  utterance_start_ms              INTEGER     NULL,
  utterance_end_ms                INTEGER     NULL,
  detected_language               TEXT        NULL,
  detected_languages              TEXT[]      NULL,
  code_switch_detected            BOOLEAN     NULL,
  language_detection_confidence   NUMERIC(4,3) NULL,
  response_text                   TEXT        NULL,
  directive_kind                  TEXT        NULL,
  workflow_node_ref               TEXT        NULL,
  tool_execution_ids              UUID[]      NOT NULL DEFAULT '{}',
  llm_provider_id                 TEXT        NULL,
  stt_provider_id                 TEXT        NULL,
  stt_ms                          INTEGER     NULL,
  llm_first_token_ms              INTEGER     NULL,
  tts_first_audio_ms              INTEGER     NULL,
  turn_e2e_ms                     INTEGER     NULL,
  barge_in_occurred               BOOLEAN     NOT NULL DEFAULT FALSE,
  completed_at                    TIMESTAMPTZ NULL,
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_turns             PRIMARY KEY (id),
  CONSTRAINT fk_turns_conversation FOREIGN KEY (conversation_id) REFERENCES voice.conversations(id) ON DELETE CASCADE,
  CONSTRAINT uq_turns_seq         UNIQUE (conversation_id, sequence_number),
  CONSTRAINT chk_turns_speaker    CHECK (speaker_role IN ('USER','ASSISTANT','SYSTEM','TOOL')),
  CONSTRAINT chk_turns_directive  CHECK (directive_kind IS NULL OR directive_kind IN ('SPEAK','TRANSFER','END_CALL','TOOL_CALL','WAIT')),
  CONSTRAINT chk_turns_confidence CHECK (utterance_confidence IS NULL OR utterance_confidence BETWEEN 0 AND 1),
  CONSTRAINT chk_turns_seq_nn     CHECK (sequence_number >= 0)
);
COMMENT ON COLUMN voice.turns.utterance_text IS 'pii:voice — STT transcript of utterance';
COMMENT ON COLUMN voice.turns.response_text  IS 'pii:voice — LLM-generated agent response';
CREATE INDEX idx_turns_conv_seq ON voice.turns (conversation_id, sequence_number ASC);
CREATE INDEX idx_turns_org      ON voice.turns (organization_id);
ALTER TABLE voice.turns ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.turns FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_turns_tenant ON voice.turns FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON voice.turns TO app_api, app_worker;
