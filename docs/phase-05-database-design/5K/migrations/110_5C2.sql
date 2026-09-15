-- =================================================================
-- Migration 110 (Phase 5C.2): DB-owned hard ACTIVE_AGENTS quota
--   admission for the two Agent-creating API operations.
-- down_revision: 109_5B7
-- Transaction: yes
-- Source: FINAL API RECONCILIATION — FINAL DB-CONFORMANT CLOSURE PASS
--         (owner decision FAR-OD-01 = OPTION B, hard synchronous quota)
--         Closes FAR-P1-01 (ex FAR-P3-02) and DB-BLOCKER-FINAL-API-001.
--         Closes DEP-6E-20.
--
-- WHY THIS MIGRATION EXISTS
-- ------------------------------------------------------------------
-- Phase 6E §43 (Option B) requires a hard, synchronous,
-- server-authoritative ACTIVE_AGENTS admission check on:
--     POST /api/v1/agents
--     POST /api/v1/agents/{agent_id}/clone
-- The interim API-layer design executed
--     SELECT pg_advisory_xact_lock(hashtext('voice.agent_quota:' || org))
-- from the service/repository layer. That directly conflicts with
-- frozen 6A §17.3, which permits application-level locking ONLY when it
-- is encapsulated inside a Phase-5 SECURITY DEFINER function (or the
-- existing Campaign Redis SETNX mechanism). 6A is preserved; the
-- serialization is moved into the database instead.
--
-- Additionally, an advisory lock taken by the API layer is advisory in
-- the literal sense: any other holder of raw INSERT on voice.agents
-- could still bypass the quota. This migration therefore removes the
-- raw INSERT bypass so that the hard quota is STRUCTURALLY enforceable,
-- exactly as migration 041_5G did for workflow.workflow_executions.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------------------------------------------------
--   1. voice.fn_assert_agent_quota_admission() — internal, owner-only
--      guard: derives tenant context server-side, serializes the
--      counted set with a transaction-scoped advisory lock, resolves
--      billing.quota_configs.hard_limit for ACTIVE_AGENTS, counts the
--      canonical ACTIVE_AGENTS set and raises SQLSTATE 53400 at limit.
--   2. voice.fn_create_agent()  — sole INSERT path for POST /agents.
--   3. voice.fn_clone_agent()   — sole INSERT path for POST /agents/{id}/clone.
--   4. REVOKE INSERT ON voice.agents FROM app_api, app_worker,
--      app_platform_admin  (SELECT/UPDATE/DELETE unchanged).
--   5. REVOKE ALL ON the new functions FROM PUBLIC; EXECUTE granted
--      only to app_api (the sole principal serving those endpoints).
--
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT DO
-- ------------------------------------------------------------------
--   - It does NOT create an AgentVersion. AgentVersion creation stays
--     publish-only (6E §18/§30). Nothing here writes voice.agent_versions.
--   - It does NOT change the counted ACTIVE_AGENTS predicate
--     (DRAFT + PUBLISHED, not soft-deleted; DEPRECATED frees a slot).
--   - It does NOT emit audit events or outbox rows. Those remain
--     API-issued in the SAME transaction through the existing
--     primitives audit.fn_insert_audit_event() and
--     INSERT INTO audit.domain_event_outbox. No second event
--     mechanism is introduced.
--   - It does NOT weaken RLS. Every policy from 010_5C/016_5C stands;
--     the guarded functions filter on the server-derived tenant id.
--   - It does NOT add a new API error code. SQLSTATE 53400 maps onto
--     the already-canonical 6K QUOTA_EXCEEDED.
-- =================================================================

-- -----------------------------------------------------------------
-- 1. Internal quota-admission guard
--
--    SECURITY INVOKER by design: it is only ever called from inside
--    the two SECURITY DEFINER functions below and therefore executes
--    with their definer privileges. EXECUTE is revoked from PUBLIC and
--    granted to no role, so no application principal can call it
--    directly, and no principal can "pre-acquire" the admission slot
--    without also performing the guarded INSERT in the same statement.
--
--    The advisory lock is transaction-scoped: it is released
--    automatically on COMMIT and on ROLLBACK, so a rejected or
--    rolled-back attempt permanently consumes no slot and strands no
--    lock.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_assert_agent_quota_admission(
  p_organization_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = voice, billing, organization, public, pg_catalog
AS $$
DECLARE
  v_org        UUID;
  v_hard_limit NUMERIC(18,4);   -- billing.quota_configs.hard_limit is NUMERIC(18,4)
  v_active     BIGINT;
BEGIN
  -- Tenant context is derived server-side; the supplied organization_id
  -- is only ever cross-checked against it, never trusted on its own.
  v_org := organization.current_tenant_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fn_assert_agent_quota_admission: no tenant context (app.tenant_id is not set)';
  END IF;
  IF p_organization_id IS NULL OR p_organization_id IS DISTINCT FROM v_org THEN
    RAISE EXCEPTION 'fn_assert_agent_quota_admission: organization_id % does not match current tenant context', p_organization_id;
  END IF;

  -- Serialize every quota-counted Agent creation for this organization.
  -- Taken BEFORE the count so that count-then-insert is atomic against
  -- concurrent admissions for the same tenant. Different tenants hash to
  -- different keys and do not contend.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('voice.agent_quota:' || v_org::text)
  );

  -- Server-authoritative limit resolution. No caller-supplied limit,
  -- plan or current-count value participates. uq_qc_org_metric makes
  -- this at most one row per (organization_id, metric).
  SELECT qc.hard_limit
    INTO v_hard_limit
  FROM billing.quota_configs qc
  WHERE qc.organization_id = v_org
    AND qc.metric          = 'ACTIVE_AGENTS'
    AND qc.effective_from <= NOW()
    AND (qc.expires_at IS NULL OR qc.expires_at > NOW());

  -- No configured row, or an explicitly unlimited row: unenforced.
  -- (6K §25.1: overage_allowed is true exactly when hard_limit IS NULL.)
  IF NOT FOUND OR v_hard_limit IS NULL THEN
    RETURN;
  END IF;

  -- Canonical ACTIVE_AGENTS counted set (6E §43.2), unchanged by this
  -- migration: same organization, status DRAFT or PUBLISHED, not
  -- soft-deleted. DEPRECATED does not consume a slot.
  SELECT COUNT(*)
    INTO v_active
  FROM voice.agents a
  WHERE a.organization_id = v_org
    AND a.status IN ('DRAFT', 'PUBLISHED')
    AND a.deleted_at IS NULL;

  IF v_active >= v_hard_limit THEN
    -- Fails BEFORE any INSERT is attempted. SQLSTATE 53400
    -- (configuration_limit_exceeded) is the deterministic signal the API
    -- layer maps to the canonical 6K QUOTA_EXCEEDED response. This is a
    -- commercial quota rejection, not a request-rate limit.
    RAISE EXCEPTION 'ACTIVE_AGENTS quota exceeded'
      USING ERRCODE = '53400',
            DETAIL  = pg_catalog.format('metric=ACTIVE_AGENTS; hard_limit=%s; active=%s', v_hard_limit, v_active);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_assert_agent_quota_admission(UUID) FROM PUBLIC;

COMMENT ON FUNCTION voice.fn_assert_agent_quota_admission(UUID) IS
  'Internal hard ACTIVE_AGENTS admission guard (FAR-OD-01 Option B). Owner-only: no application role holds EXECUTE. Callable solely from voice.fn_create_agent() and voice.fn_clone_agent().';

-- -----------------------------------------------------------------
-- 2. POST /api/v1/agents  — sole INSERT path
--
--    Accepts only the fields already present in the frozen 6E §30.1
--    request DTO (name, optional description). The public DTO is not
--    expanded. Exactly one DRAFT voice.agents row is inserted and no
--    voice.agent_versions row is created.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_create_agent(
  p_organization_id UUID,
  p_created_by      UUID,
  p_name            TEXT,
  p_description     TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, billing, organization, public, pg_catalog
AS $$
DECLARE
  v_org    UUID;
  v_new_id UUID := public.gen_uuid_v7();
BEGIN
  v_org := organization.current_tenant_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fn_create_agent: no tenant context (app.tenant_id is not set)';
  END IF;
  IF p_organization_id IS NULL OR p_organization_id IS DISTINCT FROM v_org THEN
    RAISE EXCEPTION 'fn_create_agent: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_created_by IS NULL THEN
    RAISE EXCEPTION 'fn_create_agent: p_created_by is required';
  END IF;
  IF p_name IS NULL THEN
    RAISE EXCEPTION 'fn_create_agent: p_name is required';
  END IF;

  -- Hard, synchronous, server-authoritative admission. Raises 53400
  -- before any row is written when the tenant is at its limit.
  PERFORM voice.fn_assert_agent_quota_admission(v_org);

  INSERT INTO voice.agents
    (id, organization_id, name, description, status, published_version_id, draft_config, created_by)
  VALUES
    (v_new_id, v_org, p_name, p_description, 'DRAFT', NULL, '{}'::JSONB, p_created_by);

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_create_agent(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_create_agent(UUID, UUID, TEXT, TEXT) TO app_api;

COMMENT ON FUNCTION voice.fn_create_agent(UUID, UUID, TEXT, TEXT) IS
  'Sole INSERT path for POST /api/v1/agents. Enforces the hard ACTIVE_AGENTS quota inside the database (6A §17.3-compliant). Creates exactly one DRAFT agent and never an agent_version.';

-- -----------------------------------------------------------------
-- 3. POST /api/v1/agents/{agent_id}/clone  — sole INSERT path
--
--    p_source_version_id IS NULL  -> clone the source agent's current
--                                    draft_config ("source": "draft")
--    p_source_version_id NOT NULL -> clone that published version's
--                                    snapshot_json
--
--    Source ownership is validated against the server-derived tenant id
--    before anything else. A source agent or version belonging to
--    another tenant, or absent, is rejected identically and
--    non-disclosingly with SQLSTATE P0002 (no_data_found), which the API
--    layer maps to the same 404 the frozen 6E §30.7 contract already
--    specifies. Clone existence and cross-tenant existence are therefore
--    indistinguishable to the caller.
--
--    Copy semantics follow 6E §18.3 unchanged: name and description are
--    copied verbatim (no "(copy)" suffix), status is always DRAFT,
--    published_version_id is always NULL, versions are never copied, and
--    id / created_at / updated_at / created_by are new.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_clone_agent(
  p_organization_id   UUID,
  p_created_by        UUID,
  p_source_agent_id   UUID,
  p_source_version_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = voice, billing, organization, public, pg_catalog
AS $$
DECLARE
  v_org       UUID;
  v_new_id    UUID := public.gen_uuid_v7();
  v_name      TEXT;
  v_desc      TEXT;
  v_config    JSONB;
BEGIN
  v_org := organization.current_tenant_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fn_clone_agent: no tenant context (app.tenant_id is not set)';
  END IF;
  IF p_organization_id IS NULL OR p_organization_id IS DISTINCT FROM v_org THEN
    RAISE EXCEPTION 'fn_clone_agent: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_created_by IS NULL THEN
    RAISE EXCEPTION 'fn_clone_agent: p_created_by is required';
  END IF;
  IF p_source_agent_id IS NULL THEN
    RAISE EXCEPTION 'fn_clone_agent: p_source_agent_id is required';
  END IF;

  -- Source ownership check, scoped to the server-derived tenant id.
  SELECT a.name, a.description, a.draft_config
    INTO v_name, v_desc, v_config
  FROM voice.agents a
  WHERE a.id              = p_source_agent_id
    AND a.organization_id = v_org
    AND a.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_clone_agent: source agent not found'
      USING ERRCODE = 'P0002';
  END IF;

  -- Published-source clone: the snapshot replaces the draft config.
  -- The version must belong to BOTH the source agent and this tenant.
  IF p_source_version_id IS NOT NULL THEN
    SELECT av.snapshot_json
      INTO v_config
    FROM voice.agent_versions av
    WHERE av.id              = p_source_version_id
      AND av.agent_id        = p_source_agent_id
      AND av.organization_id = v_org;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'fn_clone_agent: source version not found'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  -- Same hard quota guard, same serialization key, same counted set as
  -- the create path: the two Agent-creating operations contend with each
  -- other and neither can overshoot the limit.
  PERFORM voice.fn_assert_agent_quota_admission(v_org);

  INSERT INTO voice.agents
    (id, organization_id, name, description, status, published_version_id, draft_config, created_by)
  VALUES
    (v_new_id, v_org, v_name, v_desc, 'DRAFT', NULL, v_config, p_created_by);

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_clone_agent(UUID, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION voice.fn_clone_agent(UUID, UUID, UUID, UUID) TO app_api;

COMMENT ON FUNCTION voice.fn_clone_agent(UUID, UUID, UUID, UUID) IS
  'Sole INSERT path for POST /api/v1/agents/{agent_id}/clone. Validates source ownership non-disclosingly, enforces the same hard ACTIVE_AGENTS quota as fn_create_agent, inserts exactly one DRAFT agent and never an agent_version.';

-- -----------------------------------------------------------------
-- 4. Close the raw INSERT bypass on voice.agents
--
--    Mirrors 041_5G. Table ACLs are NOT bypassed by BYPASSRLS, so this
--    is equally effective against app_platform_admin and app_migration
--    -level roles that hold BYPASSRLS. SELECT / UPDATE / DELETE grants
--    are re-stated unchanged so that every existing 6E read and update
--    path keeps working.
--
--    No pre-existing seed, worker or platform-admin code path inserts
--    into voice.agents (verified: zero `INSERT INTO voice.agents`
--    occurrences across migrations 001–109 and the Phase-5 documents),
--    so no legitimate writer loses a capability it was using.
-- -----------------------------------------------------------------
REVOKE INSERT ON voice.agents FROM app_api, app_worker, app_platform_admin;
GRANT SELECT, UPDATE ON voice.agents TO app_api, app_worker;
GRANT SELECT, UPDATE, DELETE ON voice.agents TO app_platform_admin;

COMMENT ON TABLE voice.agents IS
  'Agent aggregate root. INSERT is available exclusively through voice.fn_create_agent() and voice.fn_clone_agent(), which enforce the hard ACTIVE_AGENTS commercial quota (FAR-OD-01 Option B). Raw INSERT is revoked from every application role.';
