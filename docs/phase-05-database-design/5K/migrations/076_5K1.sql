-- =================================================================
-- Migration 076 (Phase 5K.1): corrective patch
-- down_revision: 075_5J
-- Transaction: yes
-- Source: Phase 5K final validation — validation/MIGRATION_RECONCILIATION_REPORT.md
--         §2 (Fix 1) and §3 (Fix 2)
--
-- This migration does NOT modify, renumber, or reorder migrations
-- 001-075. It does not add, rename, or redesign any table, schema,
-- bounded context, or business entity. It corrects exactly two
-- confirmed BLOCKING defects discovered by Phase 5K's live validation
-- of the already-approved 001-075 package. Both corrections are
-- narrowly scoped to the specific objects the live evidence identified
-- as broken — nothing else is touched.
-- =================================================================

-- -----------------------------------------------------------------
-- FIX 1: SECURITY DEFINER search_path completeness
--
-- Root cause (MIGRATION_RECONCILIATION_REPORT.md §2): 24 SECURITY
-- DEFINER functions across migrations 060,061,062,063,064,065,068,069
-- have a SET search_path that omits `public`. This is only a defect
-- for a function that needs something defined in `public` — which
-- means, specifically, a function whose body contains an INSERT INTO
-- a table whose id column defaults to public.gen_uuid_v7(), which
-- itself calls pgcrypto's public.gen_random_bytes(). Of the 24 flagged
-- functions, a mechanical audit of every function body (grep for
-- "INSERT INTO") sorted them into exactly three groups; ONLY the first
-- two groups (5 functions total) are patched here:
--
--   Group 1 — confirmed broken, live-tested (3):
--     integrations.fn_create_integration_connection   (061_5I.sql)
--     plugins.fn_create_plugin_installation            (065_5I.sql)
--     analytics.fn_claim_projection_slot               (068_5J.sql)
--
--   Group 2 — broken by construction: each calls a Group-1 function
--   as its first action, so it fails identically without needing a
--   separate live connection to prove it (2):
--     analytics.fn_apply_projection_call_metrics       (068_5J.sql)
--     analytics.fn_apply_projection_call_latency        (069_5J.sql)
--
--   Group 3 — confirmed NOT affected, deliberately NOT touched by this
--   migration (19): every other flagged function is a pure trigger
--   guard (fn_id_slug_immutable, fn_ic_terminal_guard,
--   fn_redeem_oauth_attempt, fn_rotate_integration_credential,
--   fn_integrations_anonymize_org, fn_update_inbound_event_status,
--   fn_wd_identity_immutable, fn_claim_delivery, fn_delivery_succeeded,
--   fn_delivery_failed, fn_plug_slug_immutable, fn_pv_manifest_immutable,
--   fn_pi_version_immutable, fn_pi_terminal_guard, fn_activate_plugin,
--   fn_uninstall_plugin, fn_upgrade_plugin, fn_mark_event_projected,
--   fn_mark_event_dead_letter) with no INSERT INTO at all — they never
--   touch `public`, so their missing search_path entry is harmless and
--   adding `public` to them would be an unjustified, unrequired change
--   to an otherwise-correct security boundary. Two already-correct
--   sibling functions in the same files (webhooks.fn_replay_webhook_delivery
--   in 063_5I.sql, analytics.fn_ingest_analytics_event in 068_5J.sql)
--   already include `public` and are untouched here for the same reason.
--
-- Each function below is reproduced via CREATE OR REPLACE FUNCTION
-- with an IDENTICAL body/signature/return type/owner to the version
-- shipped in its original migration file — the only change in each is
-- appending `, public` to the SET search_path clause. CREATE OR REPLACE
-- FUNCTION does not reset a function's existing GRANT/REVOKE state, so
-- the EXECUTE privileges already established in 061/065/068/069 are
-- preserved unchanged (verified below in FIX 1 verification comment).
-- The safe order chosen — own schema, pg_catalog, public — matches the
-- pattern already used correctly by the two sibling functions above:
-- own schema first (so unqualified calls to sibling functions/tables
-- resolve there first), pg_catalog next (required system functions/
-- types), public last (only for gen_uuid_v7()/pgcrypto). No other
-- schema is added; ownership, arguments, and return types are
-- unchanged; SECURITY DEFINER is preserved on every function.
-- -----------------------------------------------------------------

-- integrations.fn_create_integration_connection (originally 061_5I.sql)
CREATE OR REPLACE FUNCTION integrations.fn_create_integration_connection(
  p_organization_id UUID, p_definition_id UUID, p_display_name TEXT,
  p_credential_ref TEXT, p_configuration JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog, public AS $$
DECLARE v_existing_id UUID; v_new_id UUID;
BEGIN
  IF p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: credential_ref must be a secret_manager:// reference';
  END IF;
  SELECT id INTO v_existing_id FROM integrations.integration_connections
  WHERE organization_id = p_organization_id AND definition_id = p_definition_id AND status NOT IN ('DISCONNECTED','FAILED')
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION 'integrations: a non-terminal connection (id=%) already exists for this (org, definition). Disconnect it first.', v_existing_id;
  END IF;
  INSERT INTO integrations.integration_connections (organization_id, definition_id, display_name, credential_ref, configuration, status)
  VALUES (p_organization_id, p_definition_id, p_display_name, p_credential_ref, p_configuration, 'CONNECTING')
  RETURNING id INTO v_new_id;
  INSERT INTO integrations.integration_health (organization_id, integration_connection_id)
  VALUES (p_organization_id, v_new_id) ON CONFLICT (integration_connection_id) DO NOTHING;
  RETURN v_new_id;
END;
$$;

-- plugins.fn_create_plugin_installation (originally 065_5I.sql)
CREATE OR REPLACE FUNCTION plugins.fn_create_plugin_installation(p_organization_id UUID, p_plugin_id UUID, p_plugin_version_id UUID, p_configuration JSONB DEFAULT '{}', p_credential_ref TEXT DEFAULT NULL, p_installed_by_ref UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog, public AS $$
DECLARE v_plugin_status TEXT; v_version_status TEXT; v_version_plugin UUID; v_new_id UUID;
BEGIN
  SELECT pv.status, pv.plugin_id, pl.status INTO v_version_status, v_version_plugin, v_plugin_status
  FROM plugins.plugin_versions pv JOIN plugins.plugins pl ON pl.id = pv.plugin_id WHERE pv.id = p_plugin_version_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plugins: plugin version % not found', p_plugin_version_id; END IF;
  IF v_version_plugin <> p_plugin_id THEN RAISE EXCEPTION 'plugins: version % does not belong to plugin %', p_plugin_version_id, p_plugin_id; END IF;
  IF v_plugin_status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: plugin % is not APPROVED (status=%)', p_plugin_id, v_plugin_status; END IF;
  IF v_version_status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: version % is not APPROVED (status=%)', p_plugin_version_id, v_version_status; END IF;
  IF p_credential_ref IS NOT NULL AND p_credential_ref NOT LIKE 'secret_manager://%' THEN RAISE EXCEPTION 'plugins: credential_ref must be a secret_manager:// reference'; END IF;
  INSERT INTO plugins.plugin_installations (organization_id, plugin_id, plugin_version_id, configuration, credential_ref, installed_by_ref)
  VALUES (p_organization_id, p_plugin_id, p_plugin_version_id, p_configuration, p_credential_ref, p_installed_by_ref) RETURNING id INTO v_new_id;
  RETURN v_new_id;
END;
$$;

-- analytics.fn_claim_projection_slot (originally 068_5J.sql)
CREATE OR REPLACE FUNCTION analytics.fn_claim_projection_slot(p_projection_name TEXT, p_analytics_event_id UUID, p_occurred_at TIMESTAMPTZ)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog, public AS $$
DECLARE v_inserted INTEGER;
BEGIN
  INSERT INTO analytics.analytics_projection_events (projection_name, analytics_event_id, occurred_at)
  VALUES (p_projection_name, p_analytics_event_id, p_occurred_at) ON CONFLICT (projection_name, analytics_event_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted > 0;
END;
$$;

-- analytics.fn_apply_projection_call_metrics (originally 068_5J.sql)
CREATE OR REPLACE FUNCTION analytics.fn_apply_projection_call_metrics(
  p_analytics_event_id UUID, p_occurred_at TIMESTAMPTZ, p_organization_id UUID,
  p_hour_bucket TIMESTAMPTZ, p_agent_id UUID, p_direction TEXT, p_call_outcome TEXT,
  p_provider TEXT, p_language_code TEXT, p_total_calls INTEGER, p_answered_calls INTEGER,
  p_failed_calls INTEGER, p_total_duration_s BIGINT, p_talk_time_s BIGINT,
  p_wait_time_s BIGINT, p_transfer_count INTEGER, p_recording_count INTEGER
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog, public AS $$
DECLARE v_claimed BOOLEAN;
BEGIN
  v_claimed := analytics.fn_claim_projection_slot('call_metrics_hourly', p_analytics_event_id, p_occurred_at);
  IF NOT v_claimed THEN RETURN FALSE; END IF;
  INSERT INTO analytics.call_metrics_hourly
    (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code,
     total_calls, answered_calls, failed_calls, total_duration_s, talk_time_s, wait_time_s,
     transfer_count, recording_count, last_event_id)
  VALUES (p_organization_id, p_hour_bucket, p_agent_id, p_direction, p_call_outcome, p_provider, p_language_code,
    p_total_calls, p_answered_calls, p_failed_calls, p_total_duration_s, p_talk_time_s, p_wait_time_s,
    p_transfer_count, p_recording_count, p_analytics_event_id)
  ON CONFLICT (organization_id, hour_bucket, agent_id, direction, call_outcome, provider, language_code)
  DO UPDATE SET total_calls = analytics.call_metrics_hourly.total_calls + EXCLUDED.total_calls,
    answered_calls = analytics.call_metrics_hourly.answered_calls + EXCLUDED.answered_calls,
    failed_calls = analytics.call_metrics_hourly.failed_calls + EXCLUDED.failed_calls,
    total_duration_s = analytics.call_metrics_hourly.total_duration_s + EXCLUDED.total_duration_s,
    talk_time_s = analytics.call_metrics_hourly.talk_time_s + EXCLUDED.talk_time_s,
    wait_time_s = analytics.call_metrics_hourly.wait_time_s + EXCLUDED.wait_time_s,
    transfer_count = analytics.call_metrics_hourly.transfer_count + EXCLUDED.transfer_count,
    recording_count = analytics.call_metrics_hourly.recording_count + EXCLUDED.recording_count,
    last_event_id = EXCLUDED.last_event_id, last_updated_at = NOW();
  RETURN TRUE;
END;
$$;

-- analytics.fn_apply_projection_call_latency (originally 069_5J.sql)
CREATE OR REPLACE FUNCTION analytics.fn_apply_projection_call_latency(
  p_analytics_event_id UUID, p_occurred_at TIMESTAMPTZ, p_organization_id UUID,
  p_hour_bucket TIMESTAMPTZ, p_provider TEXT, p_provider_category TEXT,
  p_model TEXT, p_latency_ms INTEGER, p_is_error BOOLEAN
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = analytics, pg_catalog, public AS $$
DECLARE v_claimed BOOLEAN; v_bucket INTEGER;
BEGIN
  v_claimed := analytics.fn_claim_projection_slot('call_latency_stage_hourly', p_analytics_event_id, p_occurred_at);
  IF NOT v_claimed THEN RETURN FALSE; END IF;
  v_bucket := CASE
    WHEN p_is_error THEN NULL
    WHEN p_latency_ms <= 10   THEN 10
    WHEN p_latency_ms <= 25   THEN 25
    WHEN p_latency_ms <= 50   THEN 50
    WHEN p_latency_ms <= 100  THEN 100
    WHEN p_latency_ms <= 150  THEN 150
    WHEN p_latency_ms <= 250  THEN 250
    WHEN p_latency_ms <= 500  THEN 500
    WHEN p_latency_ms <= 750  THEN 750
    WHEN p_latency_ms <= 1000 THEN 1000
    WHEN p_latency_ms <= 1500 THEN 1500
    WHEN p_latency_ms <= 2000 THEN 2000
    WHEN p_latency_ms <= 5000 THEN 5000
    ELSE -1 END;
  IF v_bucket IS NOT NULL THEN
    INSERT INTO analytics.call_latency_stage_hourly (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms, bucket_count, last_event_id)
    VALUES (p_organization_id, p_hour_bucket, p_provider, p_provider_category, p_model, v_bucket, 1, p_analytics_event_id)
    ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
    DO UPDATE SET bucket_count = analytics.call_latency_stage_hourly.bucket_count + 1, last_event_id = EXCLUDED.last_event_id, last_updated_at = NOW();
  ELSE
    INSERT INTO analytics.call_latency_stage_hourly (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms, bucket_count, error_count, last_event_id)
    VALUES (p_organization_id, p_hour_bucket, p_provider, p_provider_category, p_model, 5000, 0, 1, p_analytics_event_id)
    ON CONFLICT (organization_id, hour_bucket, provider, provider_category, model, bucket_upper_ms)
    DO UPDATE SET error_count = analytics.call_latency_stage_hourly.error_count + 1, last_event_id = EXCLUDED.last_event_id, last_updated_at = NOW();
  END IF;
  RETURN TRUE;
END;
$$;

-- -----------------------------------------------------------------
-- FIX 2: workflow.workflow_executions INSERT privilege regression
--
-- Root cause (MIGRATION_RECONCILIATION_REPORT.md §3): 041_5G.sql
-- deliberately revoked INSERT on workflow.workflow_executions from
-- app_api, app_worker, AND app_platform_admin, so that the only
-- INSERT path is the SECURITY DEFINER function
-- workflow.fn_start_workflow_execution (which enforces the
-- one-ACTIVE-execution-per-session invariant). Five migrations later,
-- 046_5G.sql's blanket `GRANT ... ON ALL TABLES IN SCHEMA workflow TO
-- app_platform_admin` silently re-granted INSERT on every current
-- table in the workflow schema, including workflow_executions and its
-- partitions, undoing 041's deliberate revoke for app_platform_admin
-- only (app_api/app_worker were not touched by 046's grant target list
-- and remain correctly denied).
--
-- This restores 041's original intent narrowly: it revokes INSERT
-- from app_platform_admin on workflow.workflow_executions (the parent
-- partitioned table, which is what PostgreSQL checks for an
-- unqualified `INSERT INTO workflow.workflow_executions ...`) and,
-- defensively, on every existing partition of that table individually
-- (046's blanket grant touched each partition's own ACL too, so the
-- revoke is applied symmetrically). It does NOT touch
-- workflow.workflow_definitions or workflow.workflow_versions —
-- app_platform_admin's INSERT/UPDATE/DELETE on those two tables was
-- not part of 041's restriction and is left exactly as 046 granted it.
-- app_platform_admin's SELECT, UPDATE, DELETE on workflow_executions
-- (granted correctly by 041 and re-granted by 046) are unaffected by
-- this migration — only INSERT is revoked.
-- -----------------------------------------------------------------

REVOKE INSERT ON workflow.workflow_executions FROM app_platform_admin;

DO $$
DECLARE v_partition regclass;
BEGIN
  FOR v_partition IN
    SELECT c.oid::regclass
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'workflow.workflow_executions'::regclass
  LOOP
    EXECUTE format('REVOKE INSERT ON %s FROM app_platform_admin', v_partition);
  END LOOP;
END $$;

-- fn_start_workflow_execution remains the sole INSERT path for
-- app_api, app_worker, AND app_platform_admin (its EXECUTE grant to
-- all three, set in 041_5G.sql, is untouched by this migration).
