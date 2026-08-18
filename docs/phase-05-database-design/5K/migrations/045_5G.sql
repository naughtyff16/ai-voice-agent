-- =================================================================
-- Migration 045 (Phase 5G): memory.session_memories, memory.customer_memories
-- down_revision: 044_5F
-- Transaction: yes
-- Source: 5G §16.4
-- =================================================================

CREATE TABLE memory.session_memories (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  session_ref       UUID        NOT NULL,
  conversation_ref  UUID        NOT NULL,
  contact_ref       UUID        NULL,
  status            TEXT        NOT NULL DEFAULT 'ACTIVE',
  compression_level TEXT        NOT NULL DEFAULT 'NONE',
  turns             JSONB       NOT NULL DEFAULT '[]',
  summary           TEXT        NULL,
  started_at        TIMESTAMPTZ NOT NULL,
  completed_at      TIMESTAMPTZ NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_session_memories  PRIMARY KEY (id),
  CONSTRAINT uq_sm_session_ref    UNIQUE (session_ref),
  CONSTRAINT chk_sm_status        CHECK (status IN ('ACTIVE','COMPLETED','SUMMARIZED')),
  CONSTRAINT chk_sm_compression   CHECK (compression_level IN ('NONE','SUMMARIZED','COMPRESSED'))
);
COMMENT ON COLUMN memory.session_memories.turns          IS 'pii:voice — turn text transcripts';
COMMENT ON COLUMN memory.session_memories.summary        IS 'pii:voice — LLM-generated call summary';
COMMENT ON COLUMN memory.session_memories.session_ref    IS 'logical ref: voice.call_sessions.id';
COMMENT ON COLUMN memory.session_memories.conversation_ref IS 'logical ref: voice.conversations.id';
COMMENT ON COLUMN memory.session_memories.contact_ref    IS 'logical ref: crm.contacts.id';
CREATE INDEX idx_sm_contact_ref ON memory.session_memories (organization_id, contact_ref) WHERE contact_ref IS NOT NULL;
CREATE INDEX idx_sm_org_status  ON memory.session_memories (organization_id, status);
CREATE TRIGGER trg_sm_updated_at      BEFORE UPDATE ON memory.session_memories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_sm_turns_immutable BEFORE UPDATE ON memory.session_memories FOR EACH ROW EXECUTE FUNCTION memory.prevent_completed_turns_mutation();
ALTER TABLE memory.session_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory.session_memories FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_sm_tenant ON memory.session_memories FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON memory.session_memories TO app_api, app_worker;

CREATE TABLE memory.customer_memories (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  contact_ref       UUID        NOT NULL,
  facts             JSONB       NOT NULL DEFAULT '[]',
  last_call_summary TEXT        NULL,
  last_call_at      TIMESTAMPTZ NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_customer_memories PRIMARY KEY (id),
  CONSTRAINT uq_cm_contact_ref    UNIQUE (organization_id, contact_ref)
);
COMMENT ON COLUMN memory.customer_memories.facts           IS 'pii:potential — customer facts extracted from calls';
COMMENT ON COLUMN memory.customer_memories.last_call_summary IS 'pii:voice — summary from last call';
COMMENT ON COLUMN memory.customer_memories.contact_ref     IS 'logical ref: crm.contacts.id';
CREATE TRIGGER trg_cm_updated_at BEFORE UPDATE ON memory.customer_memories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE memory.customer_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory.customer_memories FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cm_tenant ON memory.customer_memories FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON memory.customer_memories TO app_api, app_worker;
