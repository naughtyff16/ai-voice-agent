-- =================================================================
-- Migration 111 (Phase 5H.4): true temporary Platform-Admin quota
--   overrides with live commercial-baseline fallback, one canonical
--   effective-quota resolver, and restoration of the canonical
--   5H §11.1 usage-metric vocabulary.
-- down_revision: 110_5C2
-- Transaction: yes
-- Source: FINAL API RECONCILIATION — FINAL BILLING / QUOTA OVERRIDE
--         CLOSURE (owner decision FAR-OD-02 = OPTION B, true temporary
--         overrides with baseline fallback).
--         Closes FAR-P1-04 (107_5B5 metric-vocabulary regression),
--         FAR-P1-05 (base-quota overwrite / expiry-to-unlimited),
--         FAR-OD-02, FAR-P2-04 and FAR-P2-05.
--
-- WHY THIS MIGRATION EXISTS
-- ------------------------------------------------------------------
-- Two independent P1 defects were proven against the live migration
-- head before this file was written. Neither is a reviewer assertion;
-- both were reproduced from the committed sources.
--
-- (P1-A / FAR-P1-04)  METRIC-VOCABULARY REGRESSION IN 107_5B5.
-- 106_5H3 created billing.fn_platform_set_quota_override() with the
-- canonical 15-metric allow-list owned by 5H §11.1 and consumed by
-- 6K §25.1. 107_5B5 then issued a CREATE OR REPLACE of the same
-- function carrying a DIFFERENT 15-name allow-list. The two sets were
-- compared programmatically, not by eye:
--
--     canonical set (5H §11.1)            15 names
--     107_5B5 allow-list                  15 names
--     intersection                         2 names
--         CALL_MINUTES, STORAGE_GB
--     canonical names absent from 107     13 names
--         ACTIVE_AGENTS, ACTIVE_PHONE_NUMBERS, AI_MINUTES,
--         API_REQUESTS, CAMPAIGN_CALLS, EMBEDDING_TOKENS,
--         KNOWLEDGE_RETRIEVALS, LLM_COMPLETION_TOKENS,
--         LLM_PROMPT_TOKENS, STT_SECONDS, TOOL_EXECUTIONS,
--         TTS_CHARACTERS, WORKFLOW_EXECUTIONS
--     non-canonical names present in 107  13 names
--         AGENT_COUNT, API_REQUEST_COUNT, CALL_COUNT,
--         CONCURRENT_CALL_COUNT, INTEGRATION_COUNT,
--         KNOWLEDGE_BASE_DOCUMENT_COUNT, LLM_TOKEN_COUNT,
--         RECORDING_STORAGE_GB, SEAT_COUNT, SMS_COUNT,
--         WEBHOOK_DELIVERY_COUNT, WHATSAPP_MESSAGE_COUNT,
--         WORKFLOW_EXECUTION_COUNT
--
-- The operative consequence: at head 110_5C2 the metric string
-- 'ACTIVE_AGENTS' is NOT representable through the Platform Admin
-- override function at all. 6E §43 admission reads exactly that
-- metric, so the only supported way to configure the limit 6E enforces
-- was to write billing.quota_configs by hand. 6E §43.3's claim that the
-- allow-list "already contains 'ACTIVE_AGENTS'" was true of 106_5H3 and
-- false of the live head; that documentation defect is corrected in the
-- same pass rather than quietly rewritten.
--
-- This migration restores the canonical vocabulary. It deliberately
-- does NOT alias AGENT_COUNT -> ACTIVE_AGENTS, and does not retain any
-- other 107_5B5 legacy name. An alias would establish a permanent dual
-- vocabulary in which two different metric strings address the same
-- commercial dimension, and every consumer (6K reporting, 6E
-- admission, the Redis hot tier key space quota:{org_id}:{metric}, the
-- nightly reconciliation from billing.usage_records) would have to
-- normalise it forever. The legacy names are rejected outright.
--
-- (P1-B / FAR-P1-05)  BASE-QUOTA OVERWRITE AND EXPIRY-TO-UNLIMITED.
-- billing.quota_configs (052_5H) carries exactly one row per
-- (organization_id, metric) — constraint uq_qc_org_metric. 106_5H3 and
-- 107_5B5 both implement the Platform Admin override as
--     INSERT ... ON CONFLICT ON CONSTRAINT uq_qc_org_metric DO UPDATE
--         SET soft_limit = EXCLUDED.soft_limit,
--             hard_limit = EXCLUDED.hard_limit, ...
-- i.e. the temporary override OVERWRITES the commercial baseline in
-- place. The baseline is not copied anywhere first, so it is destroyed
-- and unrecoverable.
--
-- 110_5C2's admission guard then reads that single row through the
-- effective window and fails open when the window has closed:
--     SELECT qc.hard_limit INTO v_hard_limit FROM billing.quota_configs qc
--      WHERE qc.organization_id = v_org AND qc.metric = 'ACTIVE_AGENTS'
--        AND qc.effective_from <= NOW()
--        AND (qc.expires_at IS NULL OR qc.expires_at > NOW());
--     IF NOT FOUND OR v_hard_limit IS NULL THEN RETURN; END IF;
--
-- So the end-to-end behaviour at head 110_5C2 is: a plan with
-- hard_limit 2 receives a temporary override to 3; the override
-- expires; the single row falls out of its effective window; the
-- admission guard takes the NOT FOUND branch and returns without
-- objection — the organization is now UNLIMITED, and the commercial
-- limit of 2 no longer exists anywhere in the database. The same row is
-- the one 6K §25.1 reports from, so the tenant-facing quota response
-- degrades identically. A temporary grant that permanently deletes the
-- commercial limit it was granted against is the defect; expiry must
-- restore the baseline, not remove all enforcement.
--
-- OWNER DECISION FAR-OD-02 = OPTION B.
-- A commercial/base quota and a temporary Platform-Admin override are
-- two distinct layers of state. The override never overwrites, edits or
-- destroys the base. The effective quota is resolved at read time as:
-- the currently-effective, non-superseded override if one exists, else
-- the CURRENT base row. On expiry the effective quota falls back to
-- whatever the base row says AT THAT MOMENT — not to unlimited, and not
-- to a stale baseline value snapshotted when the override was granted.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------------------------------------------------
--   1. billing.fn_is_canonical_usage_metric(TEXT) — the single, IMMUTABLE
--      definition of the 5H §11.1 15-metric vocabulary. It is used by
--      the table CHECK constraint, by the override function and by the
--      resolver, so no second copy of the vocabulary can drift.
--   2. billing.quota_overrides — a new, additive table holding temporary
--      Platform-Admin overrides as their own rows. billing.quota_configs
--      is NOT overloaded again and its limit columns are never written
--      by the override path.
--   3. billing.fn_resolve_effective_quota(UUID, TEXT) — the one canonical
--      server-side resolver. Every consumer (6E admission, 6K reporting,
--      cache seeding, Platform Admin diagnostics) reads effective quota
--      through it and through nothing else.
--   4. billing.fn_platform_set_quota_override(...) — CREATE OR REPLACE,
--      same public signature. Keeps every 107_5B5 security remediation,
--      restores every 106_5H3 validation, restores the canonical
--      vocabulary, and now atomically supersedes the previous override
--      and INSERTs a new override row instead of overwriting the base.
--   5. voice.fn_assert_agent_quota_admission(UUID) — CREATE OR REPLACE.
--      ONLY the source of the effective hard limit changes: it now calls
--      the resolver. Every 110_5C2 invariant is preserved verbatim.
--   6. Documentation-only COMMENT ON COLUMN statements marking the
--      106_5H3 override columns on billing.quota_configs as legacy
--      compatibility metadata. No column is dropped.
--
-- WHAT THIS MIGRATION DOES NOT DO
-- ------------------------------------------------------------------
--   * It does not modify migrations 001-110. 110_5C2 is not amended.
--   * It does not create migration 112.
--   * It does not drop billing.quota_configs.effective_from, .expires_at,
--     .updated_by or .override_reason (106_5H3). Dropping them would be
--     a destructive rewrite of frozen structure for no correctness gain.
--   * It does not backfill billing.quota_overrides from the legacy
--     override metadata on billing.quota_configs, and it does not invent
--     a "what the baseline used to be" value for any row. See the
--     LEGACY OVERRIDE DATA note below.
--   * It does not redesign the 6K §25.2 Redis hot tier, introduce a
--     message bus, or add any pricing/PlanVersion/CPA field.
--
-- LEGACY OVERRIDE DATA (pre-production cutover)
-- ------------------------------------------------------------------
-- Rows already present in billing.quota_configs at 111 cutover are
-- treated as the commercial BASE for their (organization, metric). That
-- is the only honest reading available: where 106/107 overwrote a base
-- with an override value, the original base was destroyed in place and
-- is not recoverable from the database. Fabricating a "restored"
-- baseline would be production-data fiction, so none is fabricated.
-- Any legacy override metadata on those rows (override_reason,
-- effective_from, expires_at, updated_by) is retained for audit
-- readability but is no longer consulted by the resolver. All overrides
-- created from 111 onward live exclusively in billing.quota_overrides.
-- =================================================================


-- -----------------------------------------------------------------
-- 1. Canonical usage-metric vocabulary (5H §11.1)
--
--    One IMMUTABLE definition, referenced by the CHECK constraint on
--    billing.quota_overrides, by fn_platform_set_quota_override() and
--    by fn_resolve_effective_quota(). 6K owns this vocabulary; 5H
--    §11.1 is the authoritative table. Contrast 107_5B5, which carried
--    a second, silently divergent copy inline — the defect this
--    single definition exists to make structurally impossible.
--
--    The function takes no relation references at all, so its result
--    cannot depend on search_path or on any tenant's data; the
--    explicit SET search_path is retained for consistency with the
--    project-wide rule rather than out of necessity.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION billing.fn_is_canonical_usage_metric(p_metric TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
  SELECT p_metric = ANY (ARRAY[
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
  ])
$$;

REVOKE ALL ON FUNCTION billing.fn_is_canonical_usage_metric(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_is_canonical_usage_metric(TEXT)
  TO app_api, app_worker, app_readonly, app_platform_admin;

COMMENT ON FUNCTION billing.fn_is_canonical_usage_metric(TEXT) IS
  'Single authoritative definition of the canonical 15-metric usage vocabulary owned by 5H §11.1 and consumed by 6K §25.1. Returns TRUE only for a canonical metric key. The legacy names introduced by 107_5B5 (AGENT_COUNT, CALL_COUNT, SEAT_COUNT, LLM_TOKEN_COUNT, ...) are deliberately NOT accepted and are NOT aliased to canonical names: an alias would create a permanent dual vocabulary that every consumer would have to normalise. FAR-P1-04.';


-- -----------------------------------------------------------------
-- 2. billing.quota_overrides — temporary Platform-Admin overrides
--
--    The smallest additive structure that satisfies owner decision
--    FAR-OD-02. Deliberately excluded: every pricing field (rates,
--    currency, Money), any PlanVersion or cost-per-action duplication,
--    and any copy of the base limit. The base is never snapshotted
--    into this table — that is precisely what makes the fallback in
--    §8 read the CURRENT base rather than a stale one.
--
--    SUPERSESSION (§7). The "current" override for an (organization,
--    metric) pair is the row with superseded_at IS NULL. A partial
--    unique index enforces that at most one such row can exist. This
--    is the established repo convention for a single-current-row
--    invariant — the same shape as uq_sub_org_active (049_5H),
--    uq_memberships_active (003_5B) and uq_compliance_policy_active
--    (004_5B), among sixteen existing examples. No is_current boolean
--    and no superseded_by pointer is introduced: the supersession
--    chain for a pair is fully reconstructible by ordering its rows on
--    effective_from, and a redundant pointer column would be a second
--    thing to keep consistent.
--
--    A superseded row is never reactivated and never deleted: history
--    is retained for 6M §18's SUPERSEDED listing and for audit.
--
--    NULL SEMANTICS, inherited verbatim from billing.quota_configs
--    (052_5H) so that BASE and PLATFORM_OVERRIDE rows mean the same
--    thing to every consumer:
--      hard_limit IS NULL -> no hard stop for this metric; overage is
--        allowed. This is a legitimate override intent (an admin
--        lifting the ceiling entirely) and is NOT treated as "no
--        override configured". 6K §25.1 reports it as
--        overage_allowed = true.
--      soft_limit IS NULL -> no warning threshold.
--      Both NULL -> an explicit, auditable grant of unlimited use for
--        this metric until the override expires or is superseded.
--    Limits are NUMERIC(18,4) and may be fractional; nothing in this
--    migration rounds, CEILs or FLOORs a configured limit.
-- -----------------------------------------------------------------
CREATE TABLE billing.quota_overrides (
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

  CONSTRAINT pk_quota_overrides         PRIMARY KEY (id),
  CONSTRAINT chk_qo_metric_canonical    CHECK (billing.fn_is_canonical_usage_metric(metric)),
  CONSTRAINT chk_qo_soft_limit          CHECK (soft_limit IS NULL OR soft_limit >= 0),
  CONSTRAINT chk_qo_hard_limit          CHECK (hard_limit IS NULL OR hard_limit >= 0),
  CONSTRAINT chk_qo_limits_order        CHECK (soft_limit IS NULL OR hard_limit IS NULL OR soft_limit <= hard_limit),
  CONSTRAINT chk_qo_expires_after_start CHECK (expires_at IS NULL OR expires_at > effective_from),
  CONSTRAINT chk_qo_reason_length       CHECK (length(reason) BETWEEN 10 AND 2000),
  CONSTRAINT chk_qo_unit_label_length   CHECK (length(unit_label) BETWEEN 1 AND 100)
);

-- At most one non-superseded override per (organization, metric).
-- This is the structural half of §7: even if two concurrent callers
-- were to bypass the advisory lock, the second INSERT fails on this
-- index rather than producing two simultaneously-current overrides.
CREATE UNIQUE INDEX uq_qo_org_metric_current
  ON billing.quota_overrides (organization_id, metric)
  WHERE superseded_at IS NULL;

-- History listing for 6M §18 (ACTIVE / EXPIRED / SUPERSEDED).
CREATE INDEX idx_qo_org_metric_history
  ON billing.quota_overrides (organization_id, metric, effective_from DESC);

COMMENT ON TABLE billing.quota_overrides IS
  'Temporary Platform-Admin quota overrides (owner decision FAR-OD-02 = Option B). Each override is its own row; the commercial baseline in billing.quota_configs is never overwritten, so expiry falls back to the CURRENT baseline instead of to unlimited (FAR-P1-05). At most one non-superseded row exists per (organization_id, metric), enforced by uq_qo_org_metric_current. Rows are written only by billing.fn_platform_set_quota_override(); no role holds INSERT, UPDATE or DELETE. 6M owns the Platform Admin API over this table; 5H owns its persistence.';

COMMENT ON COLUMN billing.quota_overrides.organization_id IS
  'logical ref: organization.organizations.id — 5A convention, no cross-schema FK (billing.quota_configs is declared the same way). Existence is validated by billing.fn_platform_set_quota_override() before any row is written.';
COMMENT ON COLUMN billing.quota_overrides.metric IS
  'Canonical 5H §11.1 usage-metric key. Structurally constrained to the canonical 15 by chk_qo_metric_canonical; legacy 107_5B5 names are rejected, not aliased.';
COMMENT ON COLUMN billing.quota_overrides.soft_limit IS
  'Override warning threshold, NUMERIC(18,4), may be fractional. NULL = no warning threshold. Same semantics as billing.quota_configs.soft_limit.';
COMMENT ON COLUMN billing.quota_overrides.hard_limit IS
  'Override hard ceiling, NUMERIC(18,4), may be fractional. NULL = no hard stop / overage allowed (6K §25.1 binding rule overage_allowed = hard_limit IS NULL). NULL here is an explicit admin grant, never "no override".';
COMMENT ON COLUMN billing.quota_overrides.effective_from IS
  'When this override starts applying. Server-set to NOW() by fn_platform_set_quota_override(); not client-suppliable.';
COMMENT ON COLUMN billing.quota_overrides.expires_at IS
  'Optional expiry (6M §18). NULL = a valid non-expiring administrative override that stays effective until it is superseded. EXPIRED is computed at read time from expires_at <= NOW(); it is never written, matching the crm.contact_suppressions / break_glass_grants pattern. No cleanup job is required for correctness.';
COMMENT ON COLUMN billing.quota_overrides.superseded_at IS
  'NULL = this is the current override for its (organization_id, metric). Set to NOW() when a later override replaces it. A superseded row is never reactivated and never deleted; it is retained as history for 6M §18 and for audit.';
COMMENT ON COLUMN billing.quota_overrides.created_by IS
  'logical ref: identity.users.id — the platform admin who created this override (5A convention, no cross-schema FK). Supplied as p_admin_user_id and validated NOT NULL.';

-- Row Level Security. ENABLE + FORCE, matching billing.quota_configs.
--
--   rls_qo_tenant          tenants read only their own override rows,
--                          which is what 6K §25.1 effective-quota
--                          reporting needs. Read-only by policy AND by
--                          grant.
--   rls_qo_platform_admin  the Platform Admin GUC path, gated on the
--                          COALESCE-hardened organization.is_platform_admin()
--                          (106_5H3). It is FOR ALL because the guarded
--                          SECURITY DEFINER writer must satisfy a WITH
--                          CHECK clause under FORCE RLS, which applies
--                          to the table owner too.
--
-- A permissive policy confers no privilege of its own: RLS filters
-- rows, ACLs decide who may attempt the statement at all. No tenant
-- role holds INSERT, UPDATE or DELETE on this table, so this policy
-- cannot become a tenant write path.
ALTER TABLE billing.quota_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.quota_overrides FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_qo_tenant ON billing.quota_overrides
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_qo_platform_admin ON billing.quota_overrides
  FOR ALL
  USING (organization.is_platform_admin())
  WITH CHECK (organization.is_platform_admin());

-- ACLs. Read for every consuming role; write for none.
--
-- Note the difference from billing.quota_configs (052_5H), which
-- grants INSERT/UPDATE to app_worker and full DML to
-- app_platform_admin. Overrides are security-relevant state whose
-- every mutation must carry a validated reason, a validated admin
-- identity and an atomic audit event, so the ONLY write path is
-- billing.fn_platform_set_quota_override(). Platform Admin does not
-- need — and does not receive — raw DML here.
REVOKE ALL ON TABLE billing.quota_overrides FROM PUBLIC;
GRANT SELECT ON billing.quota_overrides
  TO app_api, app_worker, app_readonly, app_platform_admin;


-- -----------------------------------------------------------------
-- 3. billing.fn_resolve_effective_quota — the canonical resolver
--
--    Returns at most one row. Zero rows means no quota is configured
--    for the pair at all, which every consumer already treats as
--    unconfigured/unlimited (110_5C2's admission guard takes exactly
--    that branch).
--
--    RESOLUTION ORDER (FAR-OD-02):
--      (a) the currently-effective, non-superseded override, if one
--          exists  -> source = 'PLATFORM_OVERRIDE'
--      (b) otherwise the CURRENT billing.quota_configs row
--                  -> source = 'BASE'
--
--    An override is currently effective iff
--        superseded_at IS NULL
--    AND effective_from <= NOW()
--    AND (expires_at IS NULL OR expires_at > NOW())
--    computed at read time (§14). Nothing has to run on a schedule for
--    an expiry to take effect.
--
--    THE BASE ROW IS READ WITHOUT AN EFFECTIVE-WINDOW FILTER. This is
--    the direct fix for FAR-P1-05. 110_5C2 filtered the single
--    quota_configs row on effective_from/expires_at, so once a legacy
--    in-place override expired, the row vanished from the query and
--    enforcement disappeared with it. The commercial baseline does not
--    expire: billing.quota_configs.expires_at is legacy 106_5H3
--    override metadata, NOT a statement that the base quota ceases to
--    exist. Accordingly a BASE result reports expires_at as NULL.
--
--    TRUST BOUNDARY. SECURITY INVOKER, relying on the RLS policies and
--    SELECT grants already established on both tables, because that is
--    strictly narrower than a SECURITY DEFINER wrapper would be and
--    needs no privilege elevation for tenant callers: a tenant reading
--    its own effective quota does NOT require Platform Admin rights.
--    Organization context is additionally validated in-function so
--    that a caller without the right tenant context gets a loud error
--    rather than an empty result silently read as "unlimited" — the
--    exact fail-open shape this migration exists to remove.
--
--    Platform Admin diagnostic callers: billing.quota_configs carries
--    a tenant-only RLS policy from 052_5H (frozen), so reading the
--    BASE layer for an arbitrary organization requires app.tenant_id
--    to be set to that organization, as 6M's GET path already does for
--    quota_configs. This migration does not widen 052_5H's policy.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION billing.fn_resolve_effective_quota(
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
    RAISE EXCEPTION 'fn_resolve_effective_quota: p_organization_id is required.';
  END IF;

  -- Reject a non-canonical metric loudly. Returning zero rows for a
  -- typo or a legacy 107_5B5 name would be read by every consumer as
  -- "no quota configured" — i.e. unlimited — which is the worst
  -- possible interpretation of a misspelling.
  IF NOT billing.fn_is_canonical_usage_metric(p_metric) THEN
    RAISE EXCEPTION 'fn_resolve_effective_quota: metric % is outside the canonical 5H §11.1 usage-dimension vocabulary.', p_metric;
  END IF;

  -- Organization-context validation. A Platform Admin may resolve any
  -- organization; every other caller may resolve only its own tenant.
  IF NOT organization.is_platform_admin() THEN
    v_tenant := organization.current_tenant_id();
    IF v_tenant IS NULL THEN
      RAISE EXCEPTION 'fn_resolve_effective_quota: no tenant context (app.tenant_id is not set).';
    END IF;
    IF p_organization_id IS DISTINCT FROM v_tenant THEN
      RAISE EXCEPTION 'fn_resolve_effective_quota: organization_id % does not match the current tenant context.', p_organization_id;
    END IF;
  END IF;

  -- (a) currently-effective, non-superseded override.
  --     uq_qo_org_metric_current guarantees at most one candidate.
  RETURN QUERY
  SELECT
    o.metric,
    o.soft_limit,
    o.hard_limit,
    o.unit_label,
    'PLATFORM_OVERRIDE'::TEXT,
    o.id,
    o.effective_from,
    o.expires_at
  FROM billing.quota_overrides o
  WHERE o.organization_id = p_organization_id
    AND o.metric          = p_metric
    AND o.superseded_at   IS NULL
    AND o.effective_from <= NOW()
    AND (o.expires_at IS NULL OR o.expires_at > NOW());

  IF FOUND THEN
    RETURN;
  END IF;

  -- (b) the CURRENT commercial baseline. Read live, with no effective
  --     window filter, so that a base value changed while an override
  --     was active is the value that takes over at expiry (§8).
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

REVOKE ALL ON FUNCTION billing.fn_resolve_effective_quota(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_resolve_effective_quota(UUID, TEXT)
  TO app_api, app_worker, app_readonly, app_platform_admin;

COMMENT ON FUNCTION billing.fn_resolve_effective_quota(UUID, TEXT) IS
  'Canonical effective-quota resolver (owner decision FAR-OD-02 = Option B). Returns at most one row: the currently-effective non-superseded billing.quota_overrides row (source = PLATFORM_OVERRIDE) if one exists, otherwise the CURRENT billing.quota_configs row (source = BASE). Zero rows = no quota configured for the pair. The base row is read with NO effective-window filter: billing.quota_configs.expires_at is legacy 106_5H3 override metadata and never means the commercial baseline has disappeared (FAR-P1-05). SECURITY INVOKER over the existing RLS policies and SELECT grants, so tenant consumers never need Platform Admin privileges; organization context is validated in-function so that a missing tenant context fails loudly instead of resolving to "unlimited". Single source of effective quota for 6E §43 admission, 6K §25.1 reporting and Redis cache seeding.';


-- -----------------------------------------------------------------
-- 4. billing.fn_platform_set_quota_override — CREATE OR REPLACE
--
--    The public signature is unchanged from 107_5B5, so 6M §18's
--    endpoint contract and its argument list are preserved exactly.
--    What changes is the vocabulary, the validation set and, crucially,
--    the target of the write.
--
--    PRESERVED FROM 107_5B5 (security remediations — not reverted):
--      * organization existence validation before any write;
--      * the audit event written atomically in the same transaction;
--      * EXECUTE granted to app_platform_admin only;
--      * EXECUTE explicitly revoked from app_api;
--      * SECURITY DEFINER with an explicit, safe search_path and
--        schema-qualified cross-schema references.
--
--    RESTORED FROM 106_5H3 (validations lost in the 107_5B5 replace):
--      * p_admin_user_id IS NOT NULL;
--      * reason length 10..2000;
--      * the canonical 5H §11.1 metric allow-list;
--      * p_expires_at must be in the future when non-NULL;
--      * the full canonical unit-label derivation for all 15 metrics.
--
--    DELIBERATELY NOT REINSTATED from 107_5B5:
--      * "soft_limit and hard_limit must both be positive". That
--        contradicts the real column semantics. 052_5H permits either
--        limit to be NULL and permits 0, and 6K §25.1's binding rule
--        overage_allowed = (hard_limit IS NULL) depends on NULL being
--        expressible. Requiring both to be non-NULL and > 0 would make
--        an "overage allowed" override impossible to create through the
--        only sanctioned write path. The checks enforced here mirror
--        the actual constraints: each limit NULL or >= 0, and
--        soft_limit <= hard_limit when both are present.
--      * integer-only limits. Limits are NUMERIC(18,4) and fractional
--        values are legitimate; nothing here rounds them.
--
--    THE WRITE. Under an advisory lock scoped to (organization,
--    metric), any previously-current override is marked superseded and
--    a NEW override row is inserted. billing.quota_configs is not
--    touched: no INSERT, no UPDATE, no ON CONFLICT. The commercial
--    baseline survives the override, survives its expiry, and remains
--    the row the resolver falls back to.
--
--    UNIT LABELS are derived from 5H §11.1 verbatim, because 5H owns
--    the vocabulary and its units. Three of them differ from the
--    labels 106_5H3 used, and the difference is recorded rather than
--    smoothed over: KNOWLEDGE_RETRIEVALS is 'queries' (106 used
--    'retrievals'), STORAGE_GB is 'GB-months' (106 used 'GB'), and both
--    ACTIVE_AGENTS and ACTIVE_PHONE_NUMBERS are 'count' (106 used
--    'agents' and 'phone_numbers'). unit_label is descriptive display
--    metadata that never gates an authorization decision, and an
--    explicit p_unit_label always wins over the derived default.
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
BEGIN
  -- (1) Caller authorization. Platform Admin only.
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: caller is not authorized.';
  END IF;

  -- (2) Target organization must be identified.
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_organization_id is required.';
  END IF;

  -- (3) Acting admin identity must be supplied (restored from 106_5H3).
  --     It is written to created_by and into the audit event, so an
  --     unattributed override must not be creatable.
  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_admin_user_id is required.';
  END IF;

  -- (4) Canonical metric vocabulary (restored from 106_5H3; FAR-P1-04).
  IF NOT billing.fn_is_canonical_usage_metric(p_metric) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: metric % is outside the canonical 5H §11.1 usage-dimension vocabulary.', p_metric;
  END IF;

  -- (5) Reason (restored from 106_5H3). Every override is an
  --     exception to a commercial agreement and must say why.
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_reason must be between 10 and 2000 characters.';
  END IF;

  -- (6) Expiry (restored from 106_5H3). NULL is valid and means a
  --     non-expiring override that stays effective until superseded.
  IF p_expires_at IS NOT NULL AND p_expires_at <= NOW() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_expires_at must be in the future.';
  END IF;

  -- (7) Limit semantics, mirroring the real 052_5H constraints.
  IF p_soft_limit IS NOT NULL AND p_soft_limit < 0 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_soft_limit must be NULL or >= 0.';
  END IF;
  IF p_hard_limit IS NOT NULL AND p_hard_limit < 0 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_hard_limit must be NULL or >= 0.';
  END IF;
  IF p_soft_limit IS NOT NULL AND p_hard_limit IS NOT NULL AND p_soft_limit > p_hard_limit THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_soft_limit must be <= p_hard_limit.';
  END IF;

  -- (8) Organization existence (preserved from 107_5B5).
  IF NOT EXISTS (
    SELECT 1 FROM organization.organizations o WHERE o.id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: organization % not found.', p_organization_id;
  END IF;

  -- (9) Canonical unit label (5H §11.1), caller-overridable.
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
  END);

  -- (10) Serialize concurrent overrides for this (organization, metric).
  --      Transaction-scoped advisory lock taken INSIDE the database
  --      boundary, the same technique 110_5C2 uses for ACTIVE_AGENTS
  --      admission and the only form frozen 6A §17.3 permits. Together
  --      with uq_qo_org_metric_current this removes the check-then-act
  --      race entirely: the lock serializes the supersede+insert pair,
  --      and the partial unique index is the structural backstop.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('billing.quota_override:' || p_organization_id::text || ':' || p_metric)
  );

  -- (11) Supersede the previously-current override, if any. The row is
  --      retained, never deleted, and can never become current again.
  UPDATE billing.quota_overrides o
     SET superseded_at = NOW()
   WHERE o.organization_id = p_organization_id
     AND o.metric          = p_metric
     AND o.superseded_at   IS NULL;

  -- (12) Insert the NEW override. Note what is absent: billing.quota_configs
  --      is not written here in any form. The commercial baseline is
  --      neither overwritten nor copied into this row, which is what
  --      makes expiry fall back to the CURRENT baseline (§8).
  INSERT INTO billing.quota_overrides (
    organization_id, metric, soft_limit, hard_limit,
    unit_label, reason, effective_from, expires_at, created_by
  ) VALUES (
    p_organization_id, p_metric, p_soft_limit, p_hard_limit,
    v_unit_label, p_reason, NOW(), p_expires_at, p_admin_user_id
  )
  RETURNING id INTO v_id;

  -- (13) Atomic audit event, in this same transaction. If the audit
  --      write fails the override is not created.
  --      audit.fn_insert_audit_event() requires the tenant context to
  --      match p_organization_id for a non-platform-scoped event, so
  --      the transaction-local tenant GUC is set first, exactly as
  --      107_5B5 does.
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
  'Sole write path for Platform-Admin quota overrides (6M §18). Verifies the Platform Admin caller, the acting admin identity, organization existence, the canonical 5H §11.1 metric vocabulary, the reason, a future expiry and the 052_5H limit semantics; derives the canonical unit label when omitted; serializes on (organization, metric) with a transaction-scoped advisory lock; atomically supersedes the previously-current override and INSERTs a new billing.quota_overrides row; writes the QUOTA_OVERRIDE_SET audit event in the same transaction; returns the new override id. It NEVER writes billing.quota_configs, so the commercial baseline survives the override and its expiry (FAR-P1-05). Restores the canonical vocabulary lost in 107_5B5 (FAR-P1-04) without aliasing any legacy name.';


-- -----------------------------------------------------------------
-- 5. voice.fn_assert_agent_quota_admission — CREATE OR REPLACE
--
--    110_5C2 is NOT amended. This is a forward replace of the function
--    body from migration 111, and ONE thing changes: where the
--    effective hard limit comes from. Everything else is the 110_5C2
--    text, preserved deliberately and verbatim:
--
--      * tenant context is derived server-side from
--        organization.current_tenant_id() and the caller-supplied
--        p_organization_id must match it;
--      * the transaction-scoped advisory lock stays inside the database
--        boundary (frozen 6A §17.3), on the same key
--        'voice.agent_quota:' || org;
--      * the fractional-safe post-insert comparison
--        (v_active + 1) > v_hard_limit  (FAR-P1-02). The limit is
--        compared as stored and is never rounded;
--      * NULL hard limit = unlimited, return without objection;
--      * the counted set is status IN ('DRAFT','PUBLISHED') AND
--        deleted_at IS NULL — DRAFT and PUBLISHED count, DEPRECATED
--        frees a slot, soft-deleted rows are excluded;
--      * SQLSTATE 53400 with the same DETAIL payload, which 6K maps to
--        the canonical QUOTA_EXCEEDED / 429 error;
--      * SECURITY INVOKER, owner-only, no EXECUTE grant: it remains
--        reachable only from voice.fn_create_agent() and
--        voice.fn_clone_agent();
--      * the raw-INSERT revoke, the mutation trigger and the actor
--        assertion from 110_5C2 are untouched by this migration and
--        continue to apply unchanged.
--
--    The substitution: the direct, window-filtered read of
--    billing.quota_configs becomes a call to
--    billing.fn_resolve_effective_quota(v_org, 'ACTIVE_AGENTS'). That
--    single change gives 6E §43 the effective limit — an active
--    override while one is in force, and the CURRENT commercial
--    baseline once it expires, instead of 110_5C2's fail-open
--    NOT FOUND -> unlimited.
--
--    Both functions are SECURITY INVOKER and the resolver is called
--    with the tenant context already established, so the tenant RLS
--    policies on billing.quota_overrides and billing.quota_configs
--    apply normally. No Platform Admin privilege is involved in an
--    ordinary Agent creation.
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
  v_hard_limit NUMERIC(18,4);
  v_active     BIGINT;
BEGIN
  v_org := organization.current_tenant_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'fn_assert_agent_quota_admission: no tenant context (app.tenant_id is not set)';
  END IF;

  IF p_organization_id IS NULL OR p_organization_id IS DISTINCT FROM v_org THEN
    RAISE EXCEPTION 'fn_assert_agent_quota_admission: organization_id % does not match current tenant context', p_organization_id;
  END IF;

  -- Serialize the counted set for this organization for the remainder
  -- of the transaction (6A §17.3: inside the DB boundary).
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('voice.agent_quota:' || v_org::text)
  );

  -- EFFECTIVE quota, not the raw base row (FAR-P1-05 / FAR-OD-02).
  SELECT r.hard_limit
    INTO v_hard_limit
    FROM billing.fn_resolve_effective_quota(v_org, 'ACTIVE_AGENTS') r;

  -- No quota configured at all, or an explicit unlimited ceiling.
  IF NOT FOUND OR v_hard_limit IS NULL THEN
    RETURN;
  END IF;

  SELECT COUNT(*)
    INTO v_active
    FROM voice.agents a
   WHERE a.organization_id = v_org
     AND a.status IN ('DRAFT','PUBLISHED')
     AND a.deleted_at IS NULL;

  -- Post-insert invariant, fractional-safe (FAR-P1-02). Each guarded
  -- operation consumes exactly one slot.
  IF (v_active + 1) > v_hard_limit THEN
    RAISE EXCEPTION 'ACTIVE_AGENTS quota exceeded'
      USING ERRCODE = '53400',
            DETAIL  = pg_catalog.format(
              'metric=ACTIVE_AGENTS; hard_limit=%s; active=%s; requested=%s',
              v_hard_limit, v_active, v_active + 1
            );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION voice.fn_assert_agent_quota_admission(UUID) FROM PUBLIC;

COMMENT ON FUNCTION voice.fn_assert_agent_quota_admission(UUID) IS
  'Internal, owner-only ACTIVE_AGENTS admission guard for 6E §43 (110_5C2, quota source replaced by 111_5H4). Derives tenant context server-side, serializes the counted set with a transaction-scoped advisory lock, obtains the EFFECTIVE hard limit from billing.fn_resolve_effective_quota(org, ACTIVE_AGENTS) — an active Platform-Admin override while one is in force, otherwise the current commercial baseline — counts the canonical set (DRAFT or PUBLISHED, not soft-deleted) and raises SQLSTATE 53400 unless the post-insert count still satisfies the limit. The comparison (active + 1) > hard_limit is fractional-safe and the limit is never rounded. NULL hard limit = unlimited. No EXECUTE is granted: it is reachable only from voice.fn_create_agent() and voice.fn_clone_agent().';


-- -----------------------------------------------------------------
-- 6. Legacy 106_5H3 override columns on billing.quota_configs
--
--    Documentation only. No column is dropped, no constraint is
--    altered, no data is rewritten. From 111 onward these four columns
--    are legacy compatibility metadata: they describe the last
--    pre-111 in-place override for readability and audit, and the
--    resolver does not consult any of them. In particular
--    quota_configs.expires_at no longer removes a base quota from
--    enforcement — that reading was FAR-P1-05.
-- -----------------------------------------------------------------
COMMENT ON COLUMN billing.quota_configs.override_reason IS
  'LEGACY (111_5H4). Reason text of the last pre-111 in-place override. Retained for audit readability; not read by billing.fn_resolve_effective_quota(). Override reasons are now billing.quota_overrides.reason.';
COMMENT ON COLUMN billing.quota_configs.effective_from IS
  'LEGACY as override metadata (111_5H4). Kept as the row''s own start marker, but the commercial baseline does not expire and the resolver applies no effective-window filter to this table. Override windows are now billing.quota_overrides.effective_from / .expires_at.';
COMMENT ON COLUMN billing.quota_configs.expires_at IS
  'LEGACY (111_5H4). Expiry of the last pre-111 in-place override. billing.fn_resolve_effective_quota() deliberately IGNORES this column: interpreting it as "the base quota disappears" is exactly the fail-open defect FAR-P1-05. NULL or past, the base row is always the fallback layer.';
COMMENT ON COLUMN billing.quota_configs.updated_by IS
  'LEGACY (111_5H4). Platform admin who last set a pre-111 in-place override. Retained for audit readability; new override attribution is billing.quota_overrides.created_by.';

COMMENT ON TABLE billing.quota_configs IS
  'Commercial BASE quota per (organization_id, metric) — the layer a subscription/plan configures. It is never written by the Platform-Admin override path from 111_5H4 onward; temporary overrides live in billing.quota_overrides and the effective value is resolved by billing.fn_resolve_effective_quota(). Rows present at 111 cutover are treated as the base, and no historical baseline is fabricated for rows a pre-111 in-place override had already overwritten.';
