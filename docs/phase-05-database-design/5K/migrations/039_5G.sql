-- =================================================================
-- Migration 039 (Phase 5G): workflow/prompt/memory schemas + all functions
-- down_revision: 038_5F
-- Transaction: yes
-- Source: 5G §14 (triggers), §15 (SECURITY DEFINER), §16.1
-- Corrections:
--   - CREATE SCHEMA added for prompt and memory (5K §10.5):
--     5G source only issues GRANT USAGE without CREATE SCHEMA;
--     without this, migrations 042 (prompt tables) and 045 (memory tables)
--     would fail with "schema does not exist".
-- =================================================================

CREATE SCHEMA IF NOT EXISTS prompt;
CREATE SCHEMA IF NOT EXISTS memory;

GRANT USAGE ON SCHEMA workflow TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA prompt   TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA memory   TO app_api, app_worker, app_readonly, app_platform_admin;

-- Trigger functions
CREATE OR REPLACE FUNCTION workflow.prevent_wf_version_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.graph_json IS DISTINCT FROM NEW.graph_json OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.published_by IS DISTINCT FROM NEW.published_by OR
     OLD.published_at IS DISTINCT FROM NEW.published_at THEN
    RAISE EXCEPTION 'workflow_versions fields are immutable. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- Extended trigger — corrected version (5K §11.3):
-- Adds session_ref and organization_id immutability on top of INV-WF-03/INV-WF-04
CREATE OR REPLACE FUNCTION workflow.prevent_execution_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.session_ref <> NEW.session_ref THEN
    RAISE EXCEPTION 'workflow_executions.session_ref is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION 'workflow_executions.organization_id is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.workflow_version_id IS DISTINCT FROM NEW.workflow_version_id THEN
    RAISE EXCEPTION 'workflow_executions.workflow_version_id is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.status IN ('COMPLETED','FAILED') THEN
    RAISE EXCEPTION 'COMPLETED or FAILED workflow_executions are immutable. execution_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION prompt.prevent_pv_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.content IS DISTINCT FROM NEW.content OR
     OLD.variable_schema IS DISTINCT FROM NEW.variable_schema OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.published_by IS DISTINCT FROM NEW.published_by OR
     OLD.published_at IS DISTINCT FROM NEW.published_at THEN
    RAISE EXCEPTION 'prompt_versions fields are immutable. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION memory.prevent_completed_turns_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'COMPLETED' AND OLD.turns IS DISTINCT FROM NEW.turns THEN
    RAISE EXCEPTION 'session_memories.turns is immutable after status=COMPLETED. session_memory_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- SECURITY DEFINER: publish a workflow version
CREATE OR REPLACE FUNCTION workflow.fn_workflow_publish(
  p_workflow_id     UUID,
  p_new_version_id  UUID,
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM workflow.workflow_versions
    WHERE id = p_new_version_id
      AND workflow_definition_id = p_workflow_id
      AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_workflow_publish: version does not belong to this workflow or tenant. workflow_id: %, version_id: %', p_workflow_id, p_new_version_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM workflow.workflow_definitions
    WHERE id = p_workflow_id AND organization_id = p_organization_id AND status != 'ARCHIVED'
  ) THEN
    RAISE EXCEPTION 'fn_workflow_publish: workflow not found, not owned by tenant, or ARCHIVED. workflow_id: %', p_workflow_id;
  END IF;
  UPDATE workflow.workflow_definitions
  SET published_version_id = p_new_version_id, status = 'PUBLISHED', updated_at = NOW()
  WHERE id = p_workflow_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION workflow.fn_workflow_publish(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_workflow_publish(UUID, UUID, UUID) TO app_api, app_worker, app_platform_admin;

-- SECURITY DEFINER: set active prompt version per environment
CREATE OR REPLACE FUNCTION prompt.fn_prompt_set_active(
  p_prompt_id       UUID,
  p_version_number  INTEGER,
  p_environment     TEXT,
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = prompt, organization, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM prompt.prompt_versions
    WHERE prompt_template_id = p_prompt_id
      AND version_number = p_version_number
      AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_prompt_set_active: version % not found for prompt % and tenant.', p_version_number, p_prompt_id;
  END IF;
  IF p_environment NOT IN ('local','staging','production') THEN
    RAISE EXCEPTION 'Invalid environment: %. Must be local, staging, or production.', p_environment;
  END IF;
  UPDATE prompt.prompt_templates
  SET active_versions = jsonb_set(active_versions, ARRAY[p_environment], to_jsonb(p_version_number)),
      updated_at = NOW()
  WHERE id = p_prompt_id AND organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION prompt.fn_prompt_set_active(UUID, INTEGER, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION prompt.fn_prompt_set_active(UUID, INTEGER, TEXT, UUID) TO app_api, app_worker, app_platform_admin;
