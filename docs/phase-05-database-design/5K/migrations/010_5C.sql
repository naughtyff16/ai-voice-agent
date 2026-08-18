-- =================================================================
-- Migration 010 (Phase 5C): voice.agents and voice.agent_versions
-- down_revision: 009_5C
-- Transaction: yes
-- Source: 5C §16.2
-- =================================================================

CREATE TABLE voice.agents (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  name                 TEXT        NOT NULL,
  description          TEXT        NULL,
  status               TEXT        NOT NULL DEFAULT 'DRAFT',
  published_version_id UUID        NULL,
  draft_config         JSONB       NOT NULL DEFAULT '{}',
  created_by           UUID        NOT NULL,
  deleted_at           TIMESTAMPTZ NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_agents          PRIMARY KEY (id),
  CONSTRAINT chk_agents_status  CHECK (status IN ('DRAFT','PUBLISHED','DEPRECATED')),
  CONSTRAINT chk_agents_name_len CHECK (length(name) BETWEEN 2 AND 100)
);
CREATE INDEX idx_agents_org_status ON voice.agents (organization_id, status);
CREATE INDEX idx_agents_published  ON voice.agents (organization_id, published_version_id) WHERE status = 'PUBLISHED';
CREATE INDEX idx_agents_org_created ON voice.agents (organization_id, created_at DESC);
CREATE TRIGGER trg_agents_updated_at BEFORE UPDATE ON voice.agents FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.agents FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_agents_tenant ON voice.agents FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.agents TO app_api, app_worker;

CREATE TABLE voice.agent_versions (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  agent_id        UUID        NOT NULL,
  version_number  INTEGER     NOT NULL,
  snapshot_json   JSONB       NOT NULL,
  language_policy JSONB       NOT NULL,
  published_by    UUID        NOT NULL,
  published_at    TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_agent_versions PRIMARY KEY (id),
  CONSTRAINT fk_av_agent       FOREIGN KEY (agent_id) REFERENCES voice.agents(id) ON DELETE CASCADE,
  CONSTRAINT uq_av_version     UNIQUE (agent_id, version_number)
);
CREATE INDEX idx_av_agent_id ON voice.agent_versions (agent_id);
CREATE INDEX idx_av_org      ON voice.agent_versions (organization_id);
CREATE TRIGGER trg_agent_version_immutable BEFORE UPDATE ON voice.agent_versions FOR EACH ROW EXECUTE FUNCTION voice.prevent_agent_version_mutation();
ALTER TABLE voice.agent_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.agent_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_agent_versions_tenant ON voice.agent_versions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON voice.agent_versions TO app_api, app_worker;
