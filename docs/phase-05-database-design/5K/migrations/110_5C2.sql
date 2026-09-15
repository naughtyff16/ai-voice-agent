-- =================================================================
-- Migration 110 (Phase 5C.2): DB-owned hard ACTIVE_AGENTS quota
--   admission for the two Agent-creating API operations.
-- down_revision: 109_5B7
-- Transaction: yes
-- Source: FINAL API RECONCILIATION — FINAL DB-CONFORMANT CLOSURE PASS
--         (owner decision FAR-OD-01 = OPTION B, hard synchronous quota)
--         Closes FAR-P1-01 (ex FAR-P3-02) and DB-BLOCKER-FINAL-API-001.
--         Closes DEP-6E-20.
-- Amended: FINAL API RECONCILIATION — FINAL 110_5C2 MICRO-REMEDIATION.
--         Migration 110 was not frozen; it is amended in place (no 111).
--         Closes FAR-P1-02 (fractional hard_limit admission arithmetic)
--         and FAR-P1-03 (counted-set re-entry through raw UPDATE), and
--         records the narrow FAR-P2-03 created_by trust boundary.
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
-- Closing raw INSERT alone is not sufficient. The ACTIVE_AGENTS counted
-- set is (status IN ('DRAFT','PUBLISHED') AND deleted_at IS NULL), so a
-- row can also ENTER that set by UPDATE — DEPRECATED -> DRAFT,
-- DEPRECATED -> PUBLISHED, or deleted_at NOT NULL -> NULL — none of
-- which passes through the admission guard. app_api, app_worker and
-- app_platform_admin all legitimately retain UPDATE (6E PATCH, publish
-- and deprecate need it), so the re-entry paths are closed by a
-- BEFORE UPDATE trigger instead of by revoking UPDATE.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------------------------------------------------
--   1. voice.fn_assert_agent_quota_admission() — internal, owner-only
--      guard: derives tenant context server-side, serializes the
--      counted set with a transaction-scoped advisory lock, resolves
--      billing.quota_configs.hard_limit for ACTIVE_AGENTS, counts the
--      canonical ACTIVE_AGENTS set and rejects the request unless the
--      post-insert count still satisfies the configured hard limit.
--   2. voice.fn_assert_agent_actor() — internal, owner-only guard:
--      cross-checks the application-supplied created_by against the
--      tenant's own membership roster (FAR-P2-03).
--   3. voice.fn_create_agent()  — sole INSERT path for POST /agents.
--   4. voice.fn_clone_agent()   — sole INSERT path for POST /agents/{id}/clone.
--   5. REVOKE INSERT ON voice.agents FROM app_api, app_worker,
--      app_platform_admin (SELECT/UPDATE/DELETE unchanged), and
--      REVOKE ALL ON the new functions FROM PUBLIC with EXECUTE granted
--      only to app_api (the sole principal serving those endpoints).
--   6. voice.fn_agents_mutation_guard() + trg_agents_mutation_guard —
--      a BEFORE UPDATE row trigger on voice.agents that enforces the
--      frozen 6E §31.1/§31.3 lifecycle (DEPRECATED is terminal), makes
--      organization_id immutable after INSERT, and forbids resurrecting
--      a soft-deleted Agent. Together with (5) these close every way a
--      row can enter the ACTIVE_AGENTS counted set, so the Option B
--      limit is structurally enforced rather than merely checked on the
--      create path.
--
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT DO
-- ------------------------------------------------------------------
--   - It does NOT create an AgentVersion. AgentVersion creation stays
--     publish-only (6E §18/§30). Nothing here writes voice.agent_versions.
--   - It does NOT change the counted ACTIVE_AGENTS predicate
--     (DRAFT + PUBLISHED, not soft-deleted; DEPRECATED frees a slot).
--   - It does NOT invent a lifecycle. The permitted transitions are
--     read verbatim off frozen 6E §31.1 (state machine) and §31.3
--     (transition guard table); nothing beyond them is asserted.
--   - It does NOT revoke UPDATE on voice.agents from any role, and it
--     does NOT restrict same-state field updates: 6E PATCH on a DRAFT
--     or a PUBLISHED agent, publish, and deprecate all keep working.
--   - It does NOT introduce a delete API, an archive command or a
--     restore command. The soft-delete DIRECTION (deleted_at NULL ->
--     NOT NULL) stays permitted because it only ever frees a slot;
--     only the reverse direction is blocked.
--   - It does NOT add an actor/authentication model to the database.
--     See the p_created_by trust-boundary note on fn_create_agent().
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

  -- Post-admission invariant, NOT a pre-admission comparison.
  -- billing.quota_configs.hard_limit is NUMERIC(18,4) and the column
  -- structurally permits fractional commercial limits, so
  -- "v_active >= v_hard_limit" is wrong: with hard_limit = 1.5000 and
  -- v_active = 1, 1 >= 1.5 is false, the INSERT succeeds and the
  -- committed ACTIVE_AGENTS count becomes 2, which is > 1.5.
  -- Each guarded operation consumes exactly one slot, so the condition
  -- that must hold after the INSERT is (v_active + 1) <= v_hard_limit;
  -- admission therefore rejects exactly its negation. The configured
  -- commercial limit is compared as stored — it is never rounded,
  -- CEIL-ed or FLOOR-ed. (FAR-P1-02.)
  IF (v_active + 1) > v_hard_limit THEN
    -- Fails BEFORE any INSERT is attempted. SQLSTATE 53400
    -- (configuration_limit_exceeded) is the deterministic signal the API
    -- layer maps to the canonical 6K QUOTA_EXCEEDED response. This is a
    -- commercial quota rejection, not a request-rate limit.
    RAISE EXCEPTION 'ACTIVE_AGENTS quota exceeded'
      USING ERRCODE = '53400',
            DETAIL  = pg_catalog.format('metric=ACTIVE_AGENTS; hard_limit=%s; active=%s; requested=%s', v_hard_limit, v_active, v_active + 1);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_assert_agent_quota_admission(UUID) FROM PUBLIC;

COMMENT ON FUNCTION voice.fn_assert_agent_quota_admission(UUID) IS
  'Internal hard ACTIVE_AGENTS admission guard (FAR-OD-01 Option B). Owner-only: no application role holds EXECUTE. Rejects unless the post-insert ACTIVE_AGENTS count still satisfies billing.quota_configs.hard_limit, which is NUMERIC(18,4) and may be fractional. Callable solely from voice.fn_create_agent() and voice.fn_clone_agent().';

-- -----------------------------------------------------------------
-- 2. Internal actor (created_by) guard          [FAR-P2-03]
--
--    TRUST BOUNDARY — stated explicitly, because the two functions
--    below take p_created_by as a parameter:
--
--      * p_created_by is supplied only by the authenticated application
--        layer. It is NEVER a client request field: frozen 6E §30.1
--        pins the CreateAgent DTO to { name, description } with
--        extra="forbid", and created_by is implicit, resolved from the
--        authenticated actor (6E line 221). The clone DTO carries no
--        actor field either.
--      * app_api is the trusted DB principal boundary. EXECUTE on
--        fn_create_agent()/fn_clone_agent() is held by app_api alone;
--        PUBLIC and every other runtime role hold none.
--      * These functions do NOT claim to independently authenticate the
--        actor. Authentication happens in the API tier (6B); the
--        database has no session actor to appeal to — the only identity
--        context PostgreSQL carries in this system is
--        organization.current_tenant_id() (app.tenant_id) and
--        organization.is_platform_admin() (app.is_platform_admin),
--        both established in 001_5B. No current-user/actor helper
--        exists in migrations 001-109, and this migration does not
--        invent one.
--
--    What IS enforced here is the tenant-scoping of the actor: the
--    referenced user must appear on THIS organization's membership
--    roster, so a compromised or buggy caller cannot stamp an Agent
--    with an actor belonging to a different tenant.
--
--    Membership is matched in ANY status ('ACTIVE','SUSPENDED',
--    'REMOVED'), deliberately: an API key survives changes to its
--    creator's membership status (identity.api_keys.created_by is a
--    plain UUID with no lifecycle coupling), so requiring an ACTIVE
--    membership here would break API-key semantics. The check asserts
--    tenant ownership of the actor, not the actor's current standing —
--    authorization remains a 6B/6E API-tier responsibility.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_assert_agent_actor(
  p_organization_id UUID,
  p_created_by      UUID
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = voice, organization, public, pg_catalog
AS $$
BEGIN
  IF p_created_by IS NULL THEN
    RAISE EXCEPTION 'fn_assert_agent_actor: created_by is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM organization.memberships m
    WHERE m.organization_id = p_organization_id
      AND m.user_id         = p_created_by
  ) THEN
    RAISE EXCEPTION 'fn_assert_agent_actor: created_by % is not a member of organization %', p_created_by, p_organization_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_assert_agent_actor(UUID, UUID) FROM PUBLIC;

COMMENT ON FUNCTION voice.fn_assert_agent_actor(UUID, UUID) IS
  'Internal created_by guard (FAR-P2-03). Owner-only: no application role holds EXECUTE. Asserts that the application-supplied actor belongs to the current tenant''s membership roster (any status, so API-key semantics are preserved). It does not authenticate the actor; app_api is the trusted principal boundary.';

-- -----------------------------------------------------------------
-- 3. POST /api/v1/agents  — sole INSERT path
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
  -- p_created_by is application-supplied (see the trust-boundary note
  -- on voice.fn_assert_agent_actor above); it is cross-checked against
  -- this tenant's own membership roster, never merely null-checked.
  PERFORM voice.fn_assert_agent_actor(v_org, p_created_by);
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
-- 4. POST /api/v1/agents/{agent_id}/clone  — sole INSERT path
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
  -- Same actor trust boundary as fn_create_agent().
  PERFORM voice.fn_assert_agent_actor(v_org, p_created_by);
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
-- 5. Close the raw INSERT bypass on voice.agents
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
  'Agent aggregate root. INSERT is available exclusively through voice.fn_create_agent() and voice.fn_clone_agent(), which enforce the hard ACTIVE_AGENTS commercial quota (FAR-OD-01 Option B); raw INSERT is revoked from every application role. UPDATE is retained by app_api/app_worker/app_platform_admin but constrained by trg_agents_mutation_guard, which forbids re-entering the ACTIVE_AGENTS counted set (DEPRECATED is terminal, soft-deleted agents are not restorable) and makes organization_id immutable.';

-- -----------------------------------------------------------------
-- 6. Close the counted-set RE-ENTRY bypass on voice.agents
--                                                     [FAR-P1-03]
--
--    Revoking INSERT is only half of Option B. The ACTIVE_AGENTS
--    counted set is
--        status IN ('DRAFT','PUBLISHED') AND deleted_at IS NULL
--    so a row that is currently OUTSIDE that set can be pushed back
--    INTO it by a plain UPDATE, without ever reaching
--    voice.fn_assert_agent_quota_admission():
--        UPDATE voice.agents SET status='DRAFT'     WHERE status='DEPRECATED'
--        UPDATE voice.agents SET status='PUBLISHED' WHERE status='DEPRECATED'
--        UPDATE voice.agents SET deleted_at=NULL    WHERE deleted_at IS NOT NULL
--    Each of those can drive the committed count above hard_limit.
--
--    UPDATE is NOT revoked: app_api needs it for 6E PATCH, publish and
--    deprecate, and app_worker/app_platform_admin retain their existing
--    grants. The invariant is enforced with the project's established
--    BEFORE UPDATE guard-trigger pattern instead
--    (voice.prevent_agent_version_mutation in 009_5C,
--     workflow.prevent_execution_mutation in 039_5G,
--     integrations.fn_id_slug_immutable in 060_5I).
--
--    The permitted status transitions are NOT invented here. They are
--    read off the frozen 6E lifecycle:
--      6E §31.1 state machine:
--        [*] -> DRAFT, DRAFT -> DRAFT (PATCH), DRAFT -> PUBLISHED,
--        PUBLISHED -> PUBLISHED (PATCH / re-publish),
--        PUBLISHED -> DEPRECATED, DEPRECATED -> [*]
--      6E §31.3 transition guard table:
--        publish   : allowed from DRAFT, PUBLISHED  -> PUBLISHED
--        deprecate : allowed from PUBLISHED         -> DEPRECATED
--    DEPRECATED is terminal: 6E defines no command that leaves it.
--    Anything outside that table is rejected. Same-state updates
--    (DRAFT->DRAFT, PUBLISHED->PUBLISHED, DEPRECATED->DEPRECATED) are
--    untouched, so ordinary field edits — name, description,
--    draft_config, published_version_id, deleted_at in the soft-delete
--    direction — keep working on every status.
--
--    organization_id is made immutable after INSERT. No frozen contract
--    defines an Agent ownership transfer: 6E never exposes
--    organization_id as a writable field in any request body (§30.1,
--    §30.4, schemas are extra="forbid" with server-side allow-lists),
--    there is no transfer/move command in the 6E route set, and the
--    only "transfer" contracts elsewhere in Phase 6 are organization
--    ownership transfer (6C) and live call transfer (6E §37) — neither
--    of which moves an Agent aggregate between tenants. This therefore
--    enforces the Agent aggregate's existing tenant ownership rather
--    than deciding anything new. app_platform_admin holds BYPASSRLS, so
--    without this rule a raw UPDATE by that role could silently move an
--    Agent across tenants and simultaneously mutate both tenants'
--    ACTIVE_AGENTS counts.
--
--    Resurrection of a soft-deleted Agent is forbidden in one direction
--    only. 6E has no delete, archive or restore command (DEP-6E-14) and
--    nothing populates voice.agents.deleted_at today, so this is
--    forward-compatibility: setting deleted_at (leaving the counted set)
--    stays legal because it can only ever free a slot; clearing it
--    (re-entering the counted set) is blocked because it would bypass
--    admission. No public delete API is introduced.
--
--    The trigger is deliberately unconditional — it applies to every
--    role including BYPASSRLS roles, because table ACLs and triggers,
--    unlike row-level security, are not bypassed by that attribute.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION voice.fn_agents_mutation_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- (a) Tenant ownership of the Agent aggregate is immutable.
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'voice.agents.organization_id is immutable after creation. No frozen contract defines an Agent ownership transfer. agent id=%', OLD.id;
  END IF;

  -- (b) A soft-deleted Agent cannot re-enter the ACTIVE_AGENTS counted
  --     set. The opposite direction (soft-deleting) remains permitted.
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    RAISE EXCEPTION 'voice.agents: a soft-deleted agent cannot be restored; restoring it would re-enter the ACTIVE_AGENTS counted set without quota admission. agent id=%', OLD.id;
  END IF;

  -- (c) Frozen 6E §31.1/§31.3 lifecycle. Same-state updates pass
  --     through untouched; DEPRECATED is terminal.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (
         (OLD.status = 'DRAFT'     AND NEW.status = 'PUBLISHED')
      OR (OLD.status = 'PUBLISHED' AND NEW.status = 'DEPRECATED')
    ) THEN
      RAISE EXCEPTION 'voice.agents: illegal lifecycle transition % -> % (6E §31.3 permits only DRAFT->PUBLISHED and PUBLISHED->DEPRECATED; DEPRECATED is terminal). agent id=%', OLD.status, NEW.status, OLD.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION voice.fn_agents_mutation_guard() FROM PUBLIC;

COMMENT ON FUNCTION voice.fn_agents_mutation_guard() IS
  'BEFORE UPDATE guard on voice.agents (FAR-P1-03). Enforces the frozen 6E §31.1/§31.3 lifecycle with DEPRECATED terminal, organization_id immutability, and non-resurrection of soft-deleted agents, so that no raw UPDATE can re-enter a row into the ACTIVE_AGENTS counted set behind the quota admission guard.';

DROP TRIGGER IF EXISTS trg_agents_mutation_guard ON voice.agents;
CREATE TRIGGER trg_agents_mutation_guard
  BEFORE UPDATE ON voice.agents
  FOR EACH ROW EXECUTE FUNCTION voice.fn_agents_mutation_guard();
