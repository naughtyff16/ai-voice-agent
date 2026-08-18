-- =================================================================
-- Migration 013 (Phase 5C): voice.tool_definitions and voice.tool_executions
-- down_revision: 012_5C
-- Transaction: yes
-- Source: 5C §16.5
-- =================================================================

CREATE TABLE voice.tool_definitions (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NULL,
  tool_name              TEXT        NOT NULL,
  description            TEXT        NOT NULL,
  input_schema           JSONB       NOT NULL,
  output_schema          JSONB       NOT NULL,
  is_builtin             BOOLEAN     NOT NULL DEFAULT FALSE,
  timeout_ms             INTEGER     NOT NULL DEFAULT 5000,
  requires_confirmation  BOOLEAN     NOT NULL DEFAULT FALSE,
  max_retries_on_timeout INTEGER     NOT NULL DEFAULT 1,
  is_active              BOOLEAN     NOT NULL DEFAULT TRUE,
  created_by             UUID        NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tool_defs       PRIMARY KEY (id),
  CONSTRAINT chk_td_timeout     CHECK (timeout_ms BETWEEN 100 AND 30000),
  CONSTRAINT chk_td_max_retries CHECK (max_retries_on_timeout BETWEEN 0 AND 2),
  CONSTRAINT chk_td_name_format CHECK (tool_name ~ '^[a-z][a-zA-Z0-9]{1,63}$')
);
CREATE UNIQUE INDEX uq_td_platform_name ON voice.tool_definitions (tool_name) WHERE organization_id IS NULL;
CREATE UNIQUE INDEX uq_td_tenant_name   ON voice.tool_definitions (organization_id, tool_name) WHERE organization_id IS NOT NULL;
CREATE        INDEX idx_td_org_active   ON voice.tool_definitions (organization_id, is_active) WHERE is_active = TRUE;
CREATE TRIGGER trg_td_updated_at BEFORE UPDATE ON voice.tool_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE voice.tool_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.tool_definitions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_td_read   ON voice.tool_definitions FOR SELECT USING (organization_id = organization.current_tenant_id() OR organization_id IS NULL);
CREATE POLICY rls_td_insert ON voice.tool_definitions FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());
CREATE POLICY rls_td_modify ON voice.tool_definitions FOR UPDATE USING (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.tool_definitions TO app_api, app_worker;

CREATE TABLE voice.tool_executions (
  id                       UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id          UUID        NOT NULL,
  conversation_id          UUID        NOT NULL,
  turn_id                  UUID        NOT NULL,
  call_id                  UUID        NOT NULL,
  tool_definition_id       UUID        NOT NULL,
  tool_name                TEXT        NOT NULL,
  status                   TEXT        NOT NULL DEFAULT 'PENDING',
  arguments                JSONB       NOT NULL,
  arguments_hash           CHAR(64)    NOT NULL,
  result                   JSONB       NULL,
  error_message            TEXT        NULL,
  error_code               TEXT        NULL,
  attempt_count            INTEGER     NOT NULL DEFAULT 1,
  authorized               BOOLEAN     NOT NULL DEFAULT FALSE,
  authorized_by_permission TEXT        NULL,
  timeout_ms               INTEGER     NOT NULL,
  started_at               TIMESTAMPTZ NOT NULL,
  completed_at             TIMESTAMPTZ NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tool_executions PRIMARY KEY (id),
  CONSTRAINT fk_te_tool_def     FOREIGN KEY (tool_definition_id) REFERENCES voice.tool_definitions(id) ON DELETE RESTRICT,
  CONSTRAINT chk_te_status      CHECK (status IN ('PENDING','RUNNING','SUCCEEDED','FAILED','TIMED_OUT')),
  CONSTRAINT chk_te_attempt     CHECK (attempt_count >= 1),
  CONSTRAINT chk_te_timeout     CHECK (timeout_ms BETWEEN 100 AND 30000)
);
CREATE INDEX idx_te_conversation ON voice.tool_executions (conversation_id, started_at);
CREATE INDEX idx_te_call_id      ON voice.tool_executions (organization_id, call_id, started_at);
CREATE INDEX idx_te_turn_id      ON voice.tool_executions (turn_id);
CREATE INDEX idx_te_org_tool     ON voice.tool_executions (organization_id, tool_name, started_at);
CREATE INDEX idx_te_org_status   ON voice.tool_executions (organization_id, status) WHERE status IN ('PENDING','RUNNING');
CREATE TRIGGER trg_te_args_immutable BEFORE UPDATE ON voice.tool_executions FOR EACH ROW EXECUTE FUNCTION voice.prevent_tool_exec_arguments_mutation();
ALTER TABLE voice.tool_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice.tool_executions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_te_tenant ON voice.tool_executions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON voice.tool_executions TO app_api, app_worker;
