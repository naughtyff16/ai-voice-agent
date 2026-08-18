-- =================================================================
-- Migration 041 (Phase 5G): workflow.workflow_executions (partitioned)
-- down_revision: 040_5G
-- Transaction: yes
-- Source: 5G §16.2 + 5K §11 (full corrected design)
-- Corrections (5K §11):
--   - Invalid UNIQUE index on partitioned table omitting partition key
--     replaced with non-unique index + SECURITY DEFINER function
--     fn_start_workflow_execution() using pg_advisory_xact_lock
--   - REVOKE INSERT from all app roles (enforced via SECURITY DEFINER only)
--   - Extended trigger enforces session_ref/org_id immutability
-- =================================================================

CREATE TABLE workflow.workflow_executions (
  id                    UUID        NOT NULL DEFAULT gen_uuid_v7(),
  started_at            TIMESTAMPTZ NOT NULL,
  organization_id       UUID        NOT NULL,
  workflow_version_id   UUID        NOT NULL,
  session_ref           UUID        NOT NULL,
  status                TEXT        NOT NULL DEFAULT 'ACTIVE',
  current_node_id       UUID        NULL,
  slots                 JSONB       NOT NULL DEFAULT '{}',
  turn_count_at_node    JSONB       NOT NULL DEFAULT '{}',
  node_execution_history JSONB      NOT NULL DEFAULT '[]',
  completed_at          TIMESTAMPTZ NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_workflow_executions PRIMARY KEY (id, started_at),
  CONSTRAINT chk_we_status          CHECK (status IN ('ACTIVE','COMPLETED','FAILED'))
) PARTITION BY RANGE (started_at);

COMMENT ON COLUMN workflow.workflow_executions.workflow_version_id IS 'Pinned at execution start (INV-WF-03) — immutable. Enforced by trigger.';
COMMENT ON COLUMN workflow.workflow_executions.session_ref IS 'logical ref: voice.call_sessions.id — IMMUTABLE after creation. Enforced by trigger.';
COMMENT ON COLUMN workflow.workflow_executions.organization_id IS 'IMMUTABLE after creation. Enforced by trigger.';

-- Non-unique supporting index (replaces the invalid UNIQUE from 5G source)
-- One-ACTIVE-per-session invariant enforced by fn_start_workflow_execution()
CREATE INDEX idx_we_active_session ON workflow.workflow_executions (organization_id, session_ref) WHERE status = 'ACTIVE';
CREATE INDEX idx_we_session_ref    ON workflow.workflow_executions (session_ref, organization_id);
CREATE INDEX idx_we_org_active     ON workflow.workflow_executions (organization_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_we_version        ON workflow.workflow_executions (organization_id, workflow_version_id, started_at DESC);
CREATE INDEX idx_we_brin           ON workflow.workflow_executions USING BRIN (organization_id, started_at);

CREATE TRIGGER trg_we_updated_at BEFORE UPDATE ON workflow.workflow_executions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_we_immutable   BEFORE UPDATE ON workflow.workflow_executions FOR EACH ROW EXECUTE FUNCTION workflow.prevent_execution_mutation();

ALTER TABLE workflow.workflow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.workflow_executions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_we_tenant ON workflow.workflow_executions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());

-- All INSERTs must go through fn_start_workflow_execution()
REVOKE INSERT ON workflow.workflow_executions FROM app_api, app_worker, app_platform_admin;
GRANT SELECT, UPDATE ON workflow.workflow_executions TO app_api, app_worker;
GRANT SELECT, UPDATE, DELETE ON workflow.workflow_executions TO app_platform_admin;

-- SECURITY DEFINER: sole INSERT path; enforces one-ACTIVE-per-session invariant
CREATE OR REPLACE FUNCTION workflow.fn_start_workflow_execution(
  p_organization_id     UUID,
  p_workflow_version_id UUID,
  p_session_ref         UUID,
  p_started_at          TIMESTAMPTZ DEFAULT NOW()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, public, pg_catalog
AS $$
DECLARE
  v_new_id      UUID   := gen_uuid_v7();
  v_existing_id UUID;
  v_lock_key    BIGINT;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: p_organization_id is required';
  END IF;
  IF p_workflow_version_id IS NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: p_workflow_version_id is required';
  END IF;
  IF p_session_ref IS NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: p_session_ref is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM workflow.workflow_versions
    WHERE id = p_workflow_version_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: workflow_version % not found for tenant %', p_workflow_version_id, p_organization_id;
  END IF;
  -- Serialize concurrent calls for the same (org, session) pair
  v_lock_key := hashtext(p_organization_id::text || ':' || p_session_ref::text);
  PERFORM pg_advisory_xact_lock(v_lock_key);
  SELECT id INTO v_existing_id
  FROM workflow.workflow_executions
  WHERE organization_id = p_organization_id AND session_ref = p_session_ref AND status = 'ACTIVE'
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: session % already has an ACTIVE workflow execution (id=%). Complete or fail it first.', p_session_ref, v_existing_id;
  END IF;
  INSERT INTO workflow.workflow_executions
    (id, started_at, organization_id, workflow_version_id, session_ref, status)
  VALUES
    (v_new_id, p_started_at, p_organization_id, p_workflow_version_id, p_session_ref, 'ACTIVE');
  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ) TO app_api, app_worker, app_platform_admin;

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'workflow_executions_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='workflow' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE workflow.%I PARTITION OF workflow.workflow_executions FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE workflow.workflow_executions_default PARTITION OF workflow.workflow_executions DEFAULT;
