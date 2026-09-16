-- =================================================================
-- Migration 112 (Phase 5H.5): capacity-quota domain separation —
--   CONCURRENT_CALLS becomes a governed CAPACITY / ENTITLEMENT quota
--   with its own catalog, its own administrative override store and
--   its own effective-quota resolver, while the canonical 15-metric
--   USAGE vocabulary established by 111_5H4 is left byte-identical.
-- down_revision: 111_5H4
-- Transaction: yes
-- Source: FINAL API RECONCILIATION — CAPACITY-QUOTA FINAL CLOSURE
--         (owner decision FAR-OD-03 = OPTION B, separate capacity
--         quota domain).
--         Closes FAR-P1-06 (CONCURRENT_CALLS cross-phase quota
--         contradiction) and FAR-P2-08 (NULL metric does not fail
--         loudly).
--
-- WHY THIS MIGRATION EXISTS
-- ------------------------------------------------------------------
-- Two defects were proven against the live migration head (111_5H4)
-- before this file was written. Neither is a reviewer assertion; both
-- were reproduced from the committed sources.
--
-- (P1 / FAR-P1-06)  CONCURRENT_CALLS CROSS-PHASE CONTRADICTION.
--
--   SRS FR-TEN-005 (phase-01-srs §92) makes "concurrent calls" a P1
--   per-tenant configurable quota dimension. Three Phase-6 documents
--   require it at runtime:
--
--     6D §413   ConcurrentCallQuotaNotExceeded is an inline policy on
--               POST /calls, reading the partial index
--               idx_cs_org_status WHERE status = 'ACTIVE'.
--     6D §1309  its violation is the canonical 429 QUOTA_EXCEEDED.
--     6H §882   ConcurrencyEnforcementService requires the tenant's
--               CheckQuota(CONCURRENT_CALLS) result to allow a slot.
--     6H §1177  the tenant-wide ceiling is billing.quota_configs
--               metric CONCURRENT_CALLS, consumed via the same port
--               6D uses.
--
--   But 111_5H4 defined exactly 15 canonical USAGE metrics, and
--   CONCURRENT_CALLS is not among them. Consequently, at head
--   111_5H4:
--
--     billing.fn_resolve_effective_quota(org, 'CONCURRENT_CALLS')
--         RAISES — the dimension cannot be resolved at all;
--     billing.fn_platform_set_quota_override(..., 'CONCURRENT_CALLS', ...)
--         RAISES — the dimension cannot be overridden at all;
--     chk_qo_metric_canonical
--         structurally forbids a CONCURRENT_CALLS override row.
--
--   6M §589 and §66.4 already admitted in prose that CONCURRENT_CALLS
--   "has no canonical metric and is therefore not representable as a
--   quota override", while the same rows continued to present
--   FR-TEN-005 as COVERED. That is the contradiction.
--
--   THE SECOND, INDEPENDENT HALF — RUNTIME SEMANTICS.
--
--   6K §25.2 (line 2048) declares the Redis hot tier
--   "quota:{tenant_id}:{metric} INCR" to be the enforcement mechanism
--   "used by call/campaign-initiation checks", and §25.2's race note
--   (line 2064) accepts bounded over-consumption because "reservation
--   is not required in V1". 6K §52.4 (line 3523) restates this tier as
--   "a monotonic per-period counter". 4F §13.4 (lines 1251-1258) draws
--   the same flow as GET -> compare -> INCR, with no release step.
--
--   A monotonic per-period counter can never equal the number of
--   currently-ACTIVE calls: a concurrency ceiling MUST decrease when a
--   call ends. 6D and 5C both say so structurally — 5C §658 documents
--   idx_cs_org_status's purpose as "Active call count; concurrent
--   quota check" over a partial index that contains only current
--   calls. So the accumulated-usage contract and the instantaneous
--   capacity contract are not the same quota type, and cannot share
--   one vocabulary, one resolver or one Redis model.
--
--   6K §52.4 had already conceded exactly this class distinction for
--   ACTIVE_AGENTS (a gauge, deliberately excluded from the INCR
--   tier). CONCURRENT_CALLS is the same class, and additionally needs
--   an explicit RELEASE, which no existing contract defines.
--
--   OWNER DECISION FAR-OD-03 = OPTION B resolves this by separating
--   the two governed domains rather than by widening the usage
--   vocabulary:
--
--     USAGE QUOTA     accumulated / accounting-oriented,
--                     the canonical 15 metrics, unchanged;
--     CAPACITY QUOTA  instantaneous admission capacity,
--                     V1 vocabulary = { CONCURRENT_CALLS }.
--
-- (P2 / FAR-P2-08)  NULL METRIC DOES NOT FAIL LOUDLY.
--
--   111_5H4's billing.fn_is_canonical_usage_metric(p_metric) is
--   implemented as:
--
--       SELECT p_metric = ANY (ARRAY[ ...15 names... ])
--
--   For p_metric = NULL this evaluates to SQL NULL, not FALSE. Every
--   caller guards with the form:
--
--       IF NOT billing.fn_is_canonical_usage_metric(p_metric) THEN
--           RAISE EXCEPTION ...
--
--   and NOT NULL is NULL, which plpgsql's IF treats as not-true. The
--   guard is therefore SKIPPED for a NULL metric. In
--   fn_resolve_effective_quota the consequence is the exact failure
--   mode 111 was written to prevent: execution falls through to the
--   override lookup (o.metric = NULL matches nothing) and then to the
--   base lookup (qc.metric = NULL matches nothing), and the function
--   returns ZERO ROWS — which its own contract defines as "no quota
--   configured for the pair", i.e. UNLIMITED. A NULL metric silently
--   resolves to unlimited instead of failing loudly.
--
--   This migration replaces the helper with a NULL-safe body. It adds
--   and removes NO metric name and aliases no legacy name; the
--   canonical 15 are reproduced verbatim from 111_5H4.
--
-- WHAT THIS MIGRATION DOES NOT DO
-- ------------------------------------------------------------------
--   * It does not add CONCURRENT_CALLS to the usage vocabulary.
--   * It does not create a second commercial pricing system. The
--     commercial BASE limit for CONCURRENT_CALLS stays exactly where
--     6D §31.2 and 6H §99/§1177 already read it: billing.quota_configs,
--     whose .metric column is generic TEXT (052_5H has no metric
--     CHECK). No PlanVersion/CPA pricing data is copied.
--   * It does not migrate ACTIVE_AGENTS or any other of the 15 into
--     capacity semantics.
--   * It does not implement runtime reservation. The Redis
--     reservation/gauge model, acquire/release idempotency and
--     reconciliation are 6K-owned API/architecture contracts,
--     amended in the Phase-6 documents by this same pass. No
--     application code, no Lua, is authored here.
--   * It does not add a second Platform Admin route. The existing
--     route's function becomes a governed dispatcher.
-- =================================================================

BEGIN;


-- -----------------------------------------------------------------
-- 1. billing.fn_is_canonical_usage_metric — CREATE OR REPLACE,
--    NULL-safe. (FAR-P2-08)
--
--    The vocabulary is byte-for-byte the canonical 15 of 111_5H4.
--    The ONLY change is the NULL-safe wrapper: COALESCE(..., FALSE)
--    makes the three-valued result two-valued, so that every existing
--    caller's `IF NOT fn(...)` guard fires for NULL instead of being
--    skipped. No caller has to change.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION billing.fn_is_canonical_usage_metric(p_metric TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
  SELECT COALESCE(
    p_metric = ANY (ARRAY[
      'CALL_MINUTES',
      'AI_MINUTES',
      'STT_SECONDS',
      'TTS_CHARACTERS',
      'LLM_PROMPT_TOKENS',
      'LLM_COMPLETION_TOKENS',
      'EMBEDDING_TOKENS',
      'CAMPAIGN_CALLS',
      'WORKFLOW_EXECUTIONS',
      'TOOL_EXECUTIONS',
      'KNOWLEDGE_RETRIEVALS',
      'STORAGE_GB',
      'API_REQUESTS',
      'ACTIVE_AGENTS',
      'ACTIVE_PHONE_NUMBERS'
    ]),
    FALSE
  )
$$;

REVOKE ALL ON FUNCTION billing.fn_is_canonical_usage_metric(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_is_canonical_usage_metric(TEXT)
  TO app_api, app_worker, app_readonly, app_platform_admin;

COMMENT ON FUNCTION billing.fn_is_canonical_usage_metric(TEXT) IS
  'Single authoritative definition of the canonical 15-metric USAGE vocabulary owned by 5H §11.1 and consumed by 6K §25.1. Returns TRUE only for a canonical usage metric, and FALSE — never NULL — for everything else including NULL itself (112_5H5 / FAR-P2-08: the 111_5H4 body returned SQL NULL for a NULL metric, which made every caller''s `IF NOT fn(...)` guard silently skip, so fn_resolve_effective_quota returned zero rows and a NULL metric read as "unlimited"). The vocabulary is unchanged from 111_5H4: no metric added, none removed, and the legacy 107_5B5 names (AGENT_COUNT, CONCURRENT_CALL_COUNT, CALL_COUNT, SEAT_COUNT, LLM_TOKEN_COUNT, ...) remain deliberately rejected and NOT aliased. CONCURRENT_CALLS is deliberately NOT a member: under FAR-OD-03 = Option B it is a CAPACITY quota, see billing.fn_is_canonical_capacity_quota_metric(TEXT).';


-- -----------------------------------------------------------------
-- 2. billing.fn_is_canonical_capacity_quota_metric — the CAPACITY
--    catalog. (FAR-OD-03 / FAR-P1-06)
--
--    Deliberately a separate function, not a widened usage list. The
--    two vocabularies are disjoint by construction and each is a
--    single authoritative definition consumed by its own CHECK
--    constraint, its own resolver and the shared Platform Admin
--    dispatcher.
--
--    V1 capacity vocabulary = { CONCURRENT_CALLS }.
--
--    NULL-safe from birth, for exactly the reason section 1 documents.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION billing.fn_is_canonical_capacity_quota_metric(p_metric TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
  SELECT COALESCE(
    p_metric = ANY (ARRAY[
      'CONCURRENT_CALLS'
    ]),
    FALSE
  )
$$;

REVOKE ALL ON FUNCTION billing.fn_is_canonical_capacity_quota_metric(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_is_canonical_capacity_quota_metric(TEXT)
  TO app_api, app_worker, app_readonly, app_platform_admin;

COMMENT ON FUNCTION billing.fn_is_canonical_capacity_quota_metric(TEXT) IS
  'Single authoritative definition of the canonical CAPACITY / ENTITLEMENT quota vocabulary (owner decision FAR-OD-03 = Option B). V1 membership is exactly one dimension: CONCURRENT_CALLS. A capacity quota is instantaneous occupied capacity — it must DECREASE when a reservation is released — and is therefore governed separately from the accumulated 15-metric usage vocabulary in billing.fn_is_canonical_usage_metric(TEXT). The two sets are disjoint: ACTIVE_AGENTS, CALL_MINUTES and the other 13 usage metrics return FALSE here, CONCURRENT_CALLS returns FALSE there. Returns FALSE — never NULL — for NULL (FAR-P2-08). The legacy 107_5B5 name CONCURRENT_CALL_COUNT is NOT accepted and NOT aliased. Runtime acquire/release/reconcile semantics for a capacity metric belong to 6K, not to Phase 5 persistence.';


-- -----------------------------------------------------------------
-- 3. billing.capacity_quota_overrides — the administrative overlay
--    for CAPACITY quotas. (FAR-OD-03)
--
--    Deliberately a separate table from billing.quota_overrides,
--    because 111_5H4 constrained that table to the canonical 15 usage
--    metrics via chk_qo_metric_canonical and 6K/6E/6M consumers now
--    read it as "the usage override store". Putting a CONCURRENT_CALLS
--    row there would either require relaxing that CHECK — re-opening
--    FAR-P1-04's dual-vocabulary problem — or silently collapsing the
--    two domains FAR-OD-03 exists to separate.
--
--    The column set is the minimum that mirrors the usage override
--    model. No pricing fields. No extra capacity metrics.
--
--    soft_limit is retained because capacity semantics genuinely use
--    it: 6K §25.2's warning tier applies to an occupancy gauge
--    ("you are at 45 of 50 concurrent calls") exactly as it does to an
--    accumulated counter, and the Platform Admin dispatcher's existing
--    signature already carries p_soft_limit.
--
--    NOTE ON BASELINE STORAGE: the commercial/base CONCURRENT_CALLS
--    limit is NOT stored here. It remains in billing.quota_configs,
--    which is where 6D §31.2 and 6H §99/§1177 already read it and
--    whose .metric column is generic TEXT. This table is the
--    ADMINISTRATIVE OVERLAY only — the same base/override split
--    111_5H4 established for usage quotas, which is what makes expiry
--    fall back to the CURRENT baseline instead of to unlimited.
-- -----------------------------------------------------------------

CREATE TABLE billing.capacity_quota_overrides (
  id               UUID          NOT NULL DEFAULT public.gen_uuid_v7(),
  organization_id  UUID          NOT NULL,
  metric           TEXT          NOT NULL,
  soft_limit       NUMERIC(18,4) NULL,
  hard_limit       NUMERIC(18,4) NULL,
  unit_label       TEXT          NOT NULL,
  reason           TEXT          NOT NULL,
  effective_from   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ   NULL,
  superseded_at    TIMESTAMPTZ   NULL,
  created_by       UUID          NOT NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_capacity_quota_overrides  PRIMARY KEY (id),
  CONSTRAINT chk_cqo_metric_canonical
    CHECK (billing.fn_is_canonical_capacity_quota_metric(metric)),
  CONSTRAINT chk_cqo_soft_limit          CHECK (soft_limit IS NULL OR soft_limit >= 0),
  CONSTRAINT chk_cqo_hard_limit          CHECK (hard_limit IS NULL OR hard_limit >= 0),
  CONSTRAINT chk_cqo_limits_order        CHECK (soft_limit IS NULL OR hard_limit IS NULL OR soft_limit <= hard_limit),
  CONSTRAINT chk_cqo_expires_after_start CHECK (expires_at IS NULL OR expires_at > effective_from),
  CONSTRAINT chk_cqo_reason_length       CHECK (length(reason) BETWEEN 10 AND 2000),
  CONSTRAINT chk_cqo_unit_label_length   CHECK (length(unit_label) BETWEEN 1 AND 100)
);

-- At most one non-superseded capacity override per (organization, metric).
-- Structural backstop to the advisory lock in the dispatcher, exactly
-- as uq_qo_org_metric_current is for the usage store.
CREATE UNIQUE INDEX uq_cqo_org_metric_current
  ON billing.capacity_quota_overrides (organization_id, metric)
  WHERE superseded_at IS NULL;

-- History listing for the 6M §18 GET read model (ACTIVE/EXPIRED/SUPERSEDED).
CREATE INDEX idx_cqo_org_metric_history
  ON billing.capacity_quota_overrides (organization_id, metric, effective_from DESC);

COMMENT ON TABLE billing.capacity_quota_overrides IS
  'Administrative Platform-Admin overrides for CAPACITY / ENTITLEMENT quotas (owner decision FAR-OD-03 = Option B). Separate from billing.quota_overrides, which 111_5H4 constrained to the canonical 15 USAGE metrics. Each override is its own row; the commercial baseline in billing.quota_configs is never overwritten, so expiry falls back to the CURRENT baseline rather than to unlimited (the FAR-P1-05 property, preserved for the capacity domain). At most one non-superseded row per (organization_id, metric), enforced by uq_cqo_org_metric_current. Rows are written only by billing.fn_platform_set_quota_override(); no role holds INSERT, UPDATE or DELETE. Runtime occupancy (how many slots are currently reserved) is NOT stored here — that is 6K''s reservation/gauge contract, not Phase 5 persistence. 6M owns the Platform Admin API over this table; 5H owns its persistence.';

COMMENT ON COLUMN billing.capacity_quota_overrides.organization_id IS
  'logical ref: organization.organizations.id — 5A convention, no cross-schema FK (billing.quota_configs and billing.quota_overrides are declared the same way). Existence is validated by billing.fn_platform_set_quota_override() before any row is written.';
COMMENT ON COLUMN billing.capacity_quota_overrides.metric IS
  'Canonical CAPACITY quota key. Structurally constrained by chk_cqo_metric_canonical to billing.fn_is_canonical_capacity_quota_metric(), whose V1 membership is exactly { CONCURRENT_CALLS }. The legacy 107_5B5 name CONCURRENT_CALL_COUNT is rejected, not aliased. Usage metrics are structurally impossible here.';
COMMENT ON COLUMN billing.capacity_quota_overrides.soft_limit IS
  'Occupancy warning threshold, NUMERIC(18,4). NULL = no warning threshold. For a capacity metric this is a gauge threshold ("45 of 50 slots occupied"), not an accumulated-consumption threshold.';
COMMENT ON COLUMN billing.capacity_quota_overrides.hard_limit IS
  'Override capacity ceiling — the maximum number of simultaneously-reserved slots. NULL = no ceiling / unlimited capacity, an explicit admin grant, never "no override". A hard capacity ceiling must never be treated as absent merely because the reservation store is unavailable (6K non-fail-open invariant).';
COMMENT ON COLUMN billing.capacity_quota_overrides.effective_from IS
  'When this override starts applying. Server-set to NOW() by fn_platform_set_quota_override(); not client-suppliable.';
COMMENT ON COLUMN billing.capacity_quota_overrides.expires_at IS
  'Optional expiry. NULL = a valid non-expiring administrative override that stays effective until it is superseded. EXPIRED is computed at read time from expires_at <= NOW(); it is never written. Expiry falls back to the CURRENT billing.quota_configs baseline and never terminates an in-flight call — it blocks new acquisitions only (6K/6D admission-control contract).';
COMMENT ON COLUMN billing.capacity_quota_overrides.superseded_at IS
  'NULL = this is the current capacity override for its (organization_id, metric). Set to NOW() when a later override replaces it. A superseded row is never reactivated and never deleted; it is retained as history for the 6M §18 read model and for audit.';
COMMENT ON COLUMN billing.capacity_quota_overrides.created_by IS
  'logical ref: identity.users.id — the platform admin who created this override (5A convention, no cross-schema FK). Supplied as p_admin_user_id and validated NOT NULL.';

-- Row Level Security — ENABLE + FORCE, mirroring billing.quota_overrides.
--
--   rls_cqo_tenant         a tenant may read only its own capacity
--                          override rows, which is what a tenant-facing
--                          effective-capacity read needs. Read-only by
--                          policy AND by grant.
--   rls_cqo_platform_admin the Platform Admin GUC path, gated on the
--                          COALESCE-hardened organization.is_platform_admin()
--                          (106_5H3). FOR ALL because the guarded
--                          SECURITY DEFINER writer must satisfy a WITH
--                          CHECK clause under FORCE RLS.
--
-- A permissive policy confers no privilege of its own: RLS filters
-- rows, ACLs decide who may attempt the statement at all. No tenant
-- role holds INSERT, UPDATE or DELETE on this table, so this policy
-- cannot become a tenant write path.
ALTER TABLE billing.capacity_quota_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.capacity_quota_overrides FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_cqo_tenant ON billing.capacity_quota_overrides
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_cqo_platform_admin ON billing.capacity_quota_overrides
  FOR ALL
  USING (organization.is_platform_admin())
  WITH CHECK (organization.is_platform_admin());

-- ACLs. Read for every consuming role; write for none. The ONLY write
-- path is billing.fn_platform_set_quota_override(). Platform Admin
-- does not need — and does not receive — raw DML here.
REVOKE ALL ON TABLE billing.capacity_quota_overrides FROM PUBLIC;
GRANT SELECT ON billing.capacity_quota_overrides
  TO app_api, app_worker, app_readonly, app_platform_admin;


-- -----------------------------------------------------------------
-- 4. billing.fn_resolve_effective_capacity_quota — the CAPACITY
--    resolver. (FAR-OD-03 / FAR-P1-06)
--
--    A SEPARATE function. billing.fn_resolve_effective_quota() is NOT
--    overloaded and NOT modified: it remains the USAGE resolver, and
--    it continues to reject CONCURRENT_CALLS loudly. Overloading one
--    resolver across both domains would re-collapse exactly the
--    distinction FAR-OD-03 draws, and would let a usage consumer
--    accidentally resolve a capacity dimension.
--
--    Contract, mirroring fn_resolve_effective_quota's FAR-OD-02
--    semantics exactly:
--      (0) organization context validated (tenant-isolation pattern);
--      (1) metric validated against the CAPACITY catalog;
--      (2) active, non-superseded capacity override wins;
--      (3) otherwise the CURRENT billing.quota_configs base row;
--      (4) otherwise zero rows = no configured capacity quota.
--
--    expires_at NULL          = permanent-until-superseded;
--    a superseded override    never reactivates;
--    expiry                   falls back to the CURRENT base, never to
--                             a stale snapshot and never to unlimited.
--
--    SECURITY INVOKER over the existing RLS policies and SELECT
--    grants, so a tenant consumer reading its own effective capacity
--    never needs Platform Admin privilege.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION billing.fn_resolve_effective_capacity_quota(
  p_organization_id UUID,
  p_metric          TEXT
)
RETURNS TABLE (
  metric         TEXT,
  soft_limit     NUMERIC,
  hard_limit     NUMERIC,
  unit_label     TEXT,
  source         TEXT,
  override_id    UUID,
  effective_from TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = billing, organization, pg_catalog
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'fn_resolve_effective_capacity_quota: p_organization_id is required.';
  END IF;

  -- Reject a NULL metric explicitly and first, so the failure names the
  -- real problem instead of reporting an empty metric string. The
  -- catalog helper is NULL-safe as well (FAR-P2-08), so the guard below
  -- would also fire; this is the loud, specific message.
  IF p_metric IS NULL THEN
    RAISE EXCEPTION 'fn_resolve_effective_capacity_quota: p_metric is required and must not be NULL.';
  END IF;

  -- Reject a non-canonical capacity metric loudly. Returning zero rows
  -- for a typo, for a legacy 107_5B5 name, or — critically — for a
  -- USAGE metric such as ACTIVE_AGENTS would be read by every consumer
  -- as "no capacity quota configured", i.e. unlimited capacity.
  IF NOT billing.fn_is_canonical_capacity_quota_metric(p_metric) THEN
    RAISE EXCEPTION 'fn_resolve_effective_capacity_quota: metric % is outside the canonical capacity-quota vocabulary (FAR-OD-03). Usage dimensions resolve through billing.fn_resolve_effective_quota().', p_metric;
  END IF;

  -- Organization-context validation. A Platform Admin may resolve any
  -- organization; every other caller may resolve only its own tenant.
  IF NOT organization.is_platform_admin() THEN
    v_tenant := organization.current_tenant_id();
    IF v_tenant IS NULL THEN
      RAISE EXCEPTION 'fn_resolve_effective_capacity_quota: no tenant context (app.tenant_id is not set).';
    END IF;
    IF p_organization_id IS DISTINCT FROM v_tenant THEN
      RAISE EXCEPTION 'fn_resolve_effective_capacity_quota: organization_id % does not match the current tenant context.', p_organization_id;
    END IF;
  END IF;

  -- (a) currently-effective, non-superseded capacity override.
  --     uq_cqo_org_metric_current guarantees at most one candidate.
  RETURN QUERY
  SELECT
    o.metric,
    o.soft_limit,
    o.hard_limit,
    o.unit_label,
    'PLATFORM_CAPACITY_OVERRIDE'::TEXT,
    o.id,
    o.effective_from,
    o.expires_at
  FROM billing.capacity_quota_overrides o
  WHERE o.organization_id = p_organization_id
    AND o.metric          = p_metric
    AND o.superseded_at   IS NULL
    AND o.effective_from <= NOW()
    AND (o.expires_at IS NULL OR o.expires_at > NOW());

  IF FOUND THEN
    RETURN;
  END IF;

  -- (b) the CURRENT commercial baseline, read live from the shared
  --     base store with no effective-window filter, so that a base
  --     value changed while an override was active is the value that
  --     takes over at expiry. billing.quota_configs.expires_at is
  --     legacy 106_5H3 override metadata and never means the
  --     commercial baseline has disappeared (the FAR-P1-05 rule,
  --     applied identically here).
  RETURN QUERY
  SELECT
    qc.metric,
    qc.soft_limit,
    qc.hard_limit,
    qc.unit_label,
    'BASE'::TEXT,
    NULL::UUID,
    qc.effective_from,
    NULL::TIMESTAMPTZ
  FROM billing.quota_configs qc
  WHERE qc.organization_id = p_organization_id
    AND qc.metric          = p_metric;

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION billing.fn_resolve_effective_capacity_quota(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_resolve_effective_capacity_quota(UUID, TEXT)
  TO app_api, app_worker, app_readonly, app_platform_admin;

COMMENT ON FUNCTION billing.fn_resolve_effective_capacity_quota(UUID, TEXT) IS
  'Canonical effective CAPACITY-quota resolver (owner decision FAR-OD-03 = Option B). Returns at most one row: the currently-effective non-superseded billing.capacity_quota_overrides row (source = PLATFORM_CAPACITY_OVERRIDE) if one exists, otherwise the CURRENT billing.quota_configs row for the same organization+metric (source = BASE). Zero rows = no capacity quota configured. Deliberately SEPARATE from billing.fn_resolve_effective_quota(), which remains the USAGE resolver: this one accepts CONCURRENT_CALLS and rejects ACTIVE_AGENTS, that one does the reverse, and neither accepts NULL. Returns the effective LIMIT only — current occupancy is a 6K runtime reservation/gauge concern and is never read from this function. SECURITY INVOKER over the existing RLS policies and SELECT grants, so tenant consumers never need Platform Admin privileges; organization context is validated in-function so that a missing tenant context fails loudly instead of resolving to "unlimited". Single source of the effective capacity ceiling for 6D POST /calls admission and 6H campaign dispatch.';


-- -----------------------------------------------------------------
-- 5. billing.fn_platform_set_quota_override — CREATE OR REPLACE as a
--    GOVERNED DISPATCHER. (FAR-OD-03)
--
--    The public signature is unchanged from 107_5B5/111_5H4, so 6M
--    §18's endpoint contract, its argument list and the single public
--    route
--      POST /api/v1/platform-admin/organizations/{id}/quota-overrides
--    are all preserved exactly. No second route is added merely
--    because capacity persistence is separate.
--
--    What changes is only the TARGET of the write:
--
--      canonical USAGE metric     -> billing.quota_overrides
--                                    (111_5H4 logic, unchanged)
--      canonical CAPACITY metric  -> billing.capacity_quota_overrides
--                                    (same baseline-safe / supersession
--                                     / audit discipline)
--      anything else, incl. NULL  -> rejected
--
--    PRESERVED FROM 111_5H4 (not reverted):
--      * Platform Admin authorization as the first check;
--      * p_admin_user_id required (created_by + audit attribution);
--      * reason length 10..2000;
--      * p_expires_at must be in the future when supplied;
--      * limit sign and ordering rules;
--      * organization existence validation before any write;
--      * transaction-scoped advisory lock taken INSIDE the database
--        boundary (frozen 6A §17.3), plus the partial unique index as
--        the structural backstop;
--      * supersede-then-insert, never an in-place base overwrite;
--      * the audit event written atomically in the same transaction;
--      * EXECUTE granted to app_platform_admin only.
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION billing.fn_platform_set_quota_override(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_metric          TEXT,
  p_soft_limit      NUMERIC,
  p_hard_limit      NUMERIC,
  p_reason          TEXT,
  p_expires_at      TIMESTAMPTZ DEFAULT NULL,
  p_unit_label      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, organization, pg_catalog
AS $$
DECLARE
  v_id         UUID;
  v_unit_label TEXT;
  v_domain     TEXT;
BEGIN
  -- (1) Caller authorization. Platform Admin only.
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: caller is not authorized.';
  END IF;

  -- (2) Target organization must be identified.
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_organization_id is required.';
  END IF;

  -- (3) Acting admin identity must be supplied. It is written to
  --     created_by and into the audit event, so an unattributed
  --     override must not be creatable.
  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_admin_user_id is required.';
  END IF;

  -- (4) NULL metric is rejected explicitly and first (FAR-P2-08).
  --     Before 112_5H5 a NULL metric skipped the vocabulary guard and
  --     was stopped only incidentally, by the metric NOT NULL column
  --     constraint, surfacing as a raw 23502 rather than as a contract
  --     violation. It now fails loudly and by name.
  IF p_metric IS NULL THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_metric is required and must not be NULL.';
  END IF;

  -- (5) GOVERNED DOMAIN DISPATCH (FAR-OD-03). The two catalogs are
  --     disjoint, so at most one branch can match. A metric in
  --     neither catalog is rejected — arbitrary free-text metrics are
  --     not accepted, and no legacy 107_5B5 name is aliased.
  IF billing.fn_is_canonical_usage_metric(p_metric) THEN
    v_domain := 'USAGE';
  ELSIF billing.fn_is_canonical_capacity_quota_metric(p_metric) THEN
    v_domain := 'CAPACITY';
  ELSE
    RAISE EXCEPTION 'fn_platform_set_quota_override: metric % is outside both governed quota vocabularies — the canonical 15-metric usage set (5H §11.1) and the canonical capacity set (FAR-OD-03).', p_metric;
  END IF;

  -- (6) Reason. Every override is an exception to a commercial
  --     agreement and must say why.
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_reason must be between 10 and 2000 characters.';
  END IF;

  -- (7) Expiry. NULL is valid and means a non-expiring override that
  --     stays effective until superseded.
  IF p_expires_at IS NOT NULL AND p_expires_at <= NOW() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_expires_at must be in the future.';
  END IF;

  -- (8) Limit semantics, mirroring the real 052_5H constraints.
  IF p_soft_limit IS NOT NULL AND p_soft_limit < 0 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_soft_limit must be NULL or >= 0.';
  END IF;
  IF p_hard_limit IS NOT NULL AND p_hard_limit < 0 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_hard_limit must be NULL or >= 0.';
  END IF;
  IF p_soft_limit IS NOT NULL AND p_hard_limit IS NOT NULL AND p_soft_limit > p_hard_limit THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_soft_limit must be <= p_hard_limit.';
  END IF;

  -- (9) Organization existence.
  IF NOT EXISTS (
    SELECT 1 FROM organization.organizations o WHERE o.id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: organization % not found.', p_organization_id;
  END IF;

  -- (10) Canonical unit label, caller-overridable. The capacity
  --      dimension's unit is 'calls' — simultaneously-occupied call
  --      slots, not calls accumulated over a period.
  v_unit_label := COALESCE(p_unit_label, CASE p_metric
    WHEN 'CALL_MINUTES'          THEN 'minutes'
    WHEN 'AI_MINUTES'            THEN 'minutes'
    WHEN 'STT_SECONDS'           THEN 'seconds'
    WHEN 'TTS_CHARACTERS'        THEN 'characters'
    WHEN 'LLM_PROMPT_TOKENS'     THEN 'tokens'
    WHEN 'LLM_COMPLETION_TOKENS' THEN 'tokens'
    WHEN 'EMBEDDING_TOKENS'      THEN 'tokens'
    WHEN 'CAMPAIGN_CALLS'        THEN 'calls'
    WHEN 'WORKFLOW_EXECUTIONS'   THEN 'executions'
    WHEN 'TOOL_EXECUTIONS'       THEN 'executions'
    WHEN 'KNOWLEDGE_RETRIEVALS'  THEN 'queries'
    WHEN 'STORAGE_GB'            THEN 'GB-months'
    WHEN 'API_REQUESTS'          THEN 'requests'
    WHEN 'ACTIVE_AGENTS'         THEN 'count'
    WHEN 'ACTIVE_PHONE_NUMBERS'  THEN 'count'
    WHEN 'CONCURRENT_CALLS'      THEN 'calls'
  END);

  -- (11) Serialize concurrent overrides for this (domain, organization,
  --      metric). Transaction-scoped advisory lock taken INSIDE the
  --      database boundary — the same technique 110_5C2 uses for
  --      ACTIVE_AGENTS admission and the only form frozen 6A §17.3
  --      permits. The lock namespace includes the domain so the two
  --      stores cannot contend with each other. Together with the
  --      partial unique index this removes the check-then-act race
  --      entirely.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(
      CASE v_domain
        WHEN 'USAGE'    THEN 'billing.quota_override:'
        WHEN 'CAPACITY' THEN 'billing.capacity_quota_override:'
      END || p_organization_id::text || ':' || p_metric
    )
  );

  -- (12) Supersede the previously-current override in the SAME domain,
  --      then insert the new one. The row is retained, never deleted,
  --      and can never become current again. Note what is absent in
  --      both branches: billing.quota_configs is not written in any
  --      form, so the commercial baseline is neither overwritten nor
  --      snapshotted into the override row — which is what makes
  --      expiry fall back to the CURRENT baseline.
  IF v_domain = 'USAGE' THEN

    UPDATE billing.quota_overrides o
       SET superseded_at = NOW()
     WHERE o.organization_id = p_organization_id
       AND o.metric          = p_metric
       AND o.superseded_at   IS NULL;

    INSERT INTO billing.quota_overrides (
      organization_id, metric, soft_limit, hard_limit,
      unit_label, reason, effective_from, expires_at, created_by
    ) VALUES (
      p_organization_id, p_metric, p_soft_limit, p_hard_limit,
      v_unit_label, p_reason, NOW(), p_expires_at, p_admin_user_id
    )
    RETURNING id INTO v_id;

  ELSE  -- v_domain = 'CAPACITY'

    UPDATE billing.capacity_quota_overrides o
       SET superseded_at = NOW()
     WHERE o.organization_id = p_organization_id
       AND o.metric          = p_metric
       AND o.superseded_at   IS NULL;

    INSERT INTO billing.capacity_quota_overrides (
      organization_id, metric, soft_limit, hard_limit,
      unit_label, reason, effective_from, expires_at, created_by
    ) VALUES (
      p_organization_id, p_metric, p_soft_limit, p_hard_limit,
      v_unit_label, p_reason, NOW(), p_expires_at, p_admin_user_id
    )
    RETURNING id INTO v_id;

  END IF;

  -- (13) Atomic audit event, in this same transaction. If the audit
  --      write fails the override is not created.
  --
  --      AUDIT CONTRACT (FAR-P2-09). action_kind stays
  --      'QUOTA_OVERRIDE_SET' for BOTH domains, and resource_type
  --      stays 'QUOTA_OVERRIDE' with resource_id = the new override
  --      row id, exactly as 111_5H4 writes it. This is a CONTROLLED
  --      AUDIT-CONTRACT EXTENSION relative to pre-111 (107_5B5 wrote
  --      resource_type = 'QUOTA_CONFIG' with the base config id) and
  --      is NOT reverted: an override is now its own resource, so
  --      naming the base config would misidentify the row that
  --      actually changed. audit.audit_events.resource_type is free
  --      TEXT constrained only by chk_ae_resource_type
  --      (length 1..200), so no enum or check blocks either literal
  --      and no additional migration is required. The governed domain
  --      is carried in the snapshot's quota_domain key rather than by
  --      minting a second resource_type.
  PERFORM set_config('app.tenant_id', p_organization_id::text, true);

  PERFORM audit.fn_insert_audit_event(
    p_organization_id,
    'PLATFORM_ADMIN',
    p_admin_user_id,
    NULL,
    'QUOTA_OVERRIDE_SET',
    'QUOTA_OVERRIDE',
    v_id,
    'SUCCESS',
    NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'metric',         p_metric,
      'quota_domain',   v_domain,
      'soft_limit',     p_soft_limit,
      'hard_limit',     p_hard_limit,
      'reason',         p_reason,
      'effective_from', NOW(),
      'expires_at',     p_expires_at,
      'unit_label',     v_unit_label,
      'override_id',    v_id
    ),
    FALSE
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) TO app_platform_admin;

COMMENT ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) IS
  'Platform-Admin quota override writer and GOVERNED DOMAIN DISPATCHER (owner decision FAR-OD-03 = Option B). Public signature unchanged from 107_5B5/111_5H4, so 6M §18''s single route POST /api/v1/platform-admin/organizations/{id}/quota-overrides is preserved and no second route exists. A canonical USAGE metric writes billing.quota_overrides; a canonical CAPACITY metric writes billing.capacity_quota_overrides; anything in neither catalog — including NULL — is rejected. The two catalogs are disjoint, so at most one branch can match. Both branches share the identical discipline: Platform-Admin-only authorization, required admin identity, validated reason, future-dated expiry, organization existence, an advisory lock in a domain-scoped namespace, supersede-then-insert, and an atomic audit event. billing.quota_configs is never written by either branch, so the commercial baseline survives and expiry falls back to it. Audit: action_kind QUOTA_OVERRIDE_SET, resource_type QUOTA_OVERRIDE, resource_id = the new override row id, with the governed domain in resource_snapshot.quota_domain (FAR-P2-09).';


COMMIT;
