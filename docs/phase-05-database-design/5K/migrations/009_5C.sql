-- =================================================================
-- Migration 009 (Phase 5C): Voice schema functions and triggers
-- down_revision: 008_5B
-- Transaction: yes
-- Source: 5C §16.1
-- Note: resolve_inbound_phone_number() is NOT created here
--       because it references voice.tenant_phone_numbers, which
--       does not exist until migration 015 (5K §10.3 correction).
-- =================================================================

GRANT USAGE ON SCHEMA voice TO app_api, app_worker, app_readonly, app_platform_admin;

CREATE OR REPLACE FUNCTION voice.prevent_agent_version_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.snapshot_json IS DISTINCT FROM NEW.snapshot_json OR
     OLD.language_policy IS DISTINCT FROM NEW.language_policy THEN
    RAISE EXCEPTION 'voice.agent_versions is immutable after creation. Attempted mutation on id=%', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION voice.prevent_tool_exec_arguments_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.arguments IS DISTINCT FROM NEW.arguments THEN
    RAISE EXCEPTION 'voice.tool_executions.arguments is immutable after creation. id=%', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
