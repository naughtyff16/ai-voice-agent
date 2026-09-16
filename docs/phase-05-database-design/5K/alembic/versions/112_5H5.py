"""Phase 5H.5 -- capacity-quota domain separation: CONCURRENT_CALLS becomes a
governed CAPACITY / ENTITLEMENT quota with its own catalog, its own
administrative override store and its own effective-quota resolver, and the
canonical usage-metric helper is made NULL-safe.

This revision executes the frozen, canonical SQL file
5K/migrations/112_5H5.sql verbatim via op.get_bind().exec_driver_sql()
(through _frozen_sql.run_frozen_sql, the shared helper every 5K revision
wrapper uses). Do not add DDL here: the .sql file is the single source of
truth for the schema change, and this module exists only to place that file
in the Alembic dependency graph.

PROVENANCE.
    FINAL API RECONCILIATION -- CAPACITY-QUOTA FINAL CLOSURE.
    Owner decision FAR-OD-03 = OPTION B (CONCURRENT_CALLS is governed as a
    separate capacity/entitlement quota, NOT added to the canonical 15-metric
    usage vocabulary).
    Closes FAR-P1-06 and FAR-P2-08.

    Both defects were reproduced from the committed sources at head 111_5H4
    before this revision was written; neither was taken on the reviewer's
    word.

    FAR-P1-06 -- CONCURRENT_CALLS cross-phase quota contradiction. SRS
    FR-TEN-005 makes per-tenant concurrent calls a P1 configurable quota, and
    four Phase-6 requirements consume it at runtime: 6D's
    ConcurrentCallQuotaNotExceeded policy on POST /calls, 6D's 429
    QUOTA_EXCEEDED mapping, 6H's ConcurrencyEnforcementService tenant check
    and 6H's MIN(campaign, tenant) dual ceiling. But 111_5H4's canonical
    vocabulary is exactly 15 usage metrics and CONCURRENT_CALLS is not among
    them, so at head 111_5H4 three independent gates reject it:
    fn_resolve_effective_quota raises, fn_platform_set_quota_override raises,
    and chk_qo_metric_canonical structurally forbids the row. 6M section 589
    and section 66.4 already recorded in prose that the dimension "is not
    representable as a quota override" while the same rows continued to
    present FR-TEN-005 as COVERED.

    The second, independent half of FAR-P1-06 is semantic, and is why the fix
    is not simply "add a sixteenth metric". 6K section 25.2 and section 52.4
    define the enforcement hot tier as a MONOTONIC per-period Redis INCR
    counter that explicitly declines reservation and accepts bounded
    over-consumption, and 4F section 13.4 draws the same GET -> compare ->
    INCR flow with no release step. 6D section 413 and 5C section 658/667
    require instead an INSTANTANEOUS count of call_sessions WHERE status =
    'ACTIVE', served by the executed partial index idx_cs_org_status whose
    documented purpose is literally "Active call count; concurrent quota
    check". A counter that only ever increases can never equal the number of
    currently-active calls. 6K section 52.4 had already conceded this class
    distinction for the ACTIVE_AGENTS gauge; CONCURRENT_CALLS is the same
    class and additionally requires an explicit release that no existing
    contract defines. Accumulated usage and instantaneous capacity are two
    quota domains, and owner decision FAR-OD-03 = Option B separates them
    rather than collapsing them into one vocabulary.

    FAR-P2-08 -- a NULL metric did not fail loudly. 111_5H4 implemented
    billing.fn_is_canonical_usage_metric as
    SELECT p_metric = ANY (ARRAY[...15 names...]), which evaluates to SQL
    NULL -- not FALSE -- for a NULL argument. Every caller guards with
    IF NOT billing.fn_is_canonical_usage_metric(p_metric) THEN RAISE, and
    NOT NULL is NULL, which plpgsql's IF treats as not-true, so the guard was
    SKIPPED for NULL. In fn_resolve_effective_quota execution then fell
    through to the override lookup (o.metric = NULL matches nothing) and the
    base lookup (qc.metric = NULL matches nothing) and the function returned
    ZERO ROWS -- which its own contract defines as "no quota configured",
    i.e. unlimited. In fn_platform_set_quota_override a NULL metric was
    stopped only incidentally, by the metric NOT NULL column constraint,
    surfacing as a raw 23502 rather than as a contract violation.

WHAT IT DOES.
    * CREATE OR REPLACEs billing.fn_is_canonical_usage_metric(TEXT) with a
      NULL-safe body, COALESCE(p_metric = ANY (ARRAY[...]), FALSE). The
      vocabulary is reproduced byte-for-byte from 111_5H4: no metric is
      added, none is removed, and the legacy 107_5B5 names remain rejected
      and deliberately NOT aliased. Because the helper is the single
      definition consumed by the table CHECK, the resolver and the override
      function, this one replacement makes all three call sites reject NULL
      without any of them changing. CONCURRENT_CALLS is deliberately still
      NOT a member.

    * Creates billing.fn_is_canonical_capacity_quota_metric(TEXT), the single
      IMMUTABLE definition of the canonical CAPACITY vocabulary, NULL-safe
      from birth. V1 membership is exactly one dimension: CONCURRENT_CALLS.
      The two catalogs are disjoint by construction -- ACTIVE_AGENTS and
      CALL_MINUTES return FALSE here, CONCURRENT_CALLS returns FALSE there --
      so the accumulated and instantaneous domains cannot be silently
      collapsed, and AGENT_COUNT / CONCURRENT_CALL_COUNT and the other legacy
      names are rejected by both.

    * Creates billing.capacity_quota_overrides, an additive table in which
      each Platform-Admin capacity override is its own row, with the same
      shape and the same single-current-row discipline as
      billing.quota_overrides: chk_cqo_metric_canonical bound to the capacity
      catalog, the partial unique index uq_cqo_org_metric_current WHERE
      superseded_at IS NULL, ENABLE + FORCE row level security, a tenant
      SELECT policy and a Platform Admin policy, SELECT granted to app_api,
      app_worker, app_readonly and app_platform_admin, and INSERT/UPDATE/
      DELETE granted to no role at all, so the guarded function is the only
      write path. CONCURRENT_CALLS rows are NOT placed in
      billing.quota_overrides, whose CHECK constraint 111_5H4 bound to the
      usage catalog and which 6K/6E/6M consumers now read as the usage
      override store.

      The COMMERCIAL BASELINE is not moved. It stays in
      billing.quota_configs, which is where 6D section 31.2 and 6H section 99
      / section 1177 already read it and whose .metric column is generic TEXT
      (052_5H declares no metric CHECK). No second pricing system is created
      and no PlanVersion / CPA data is copied. This table is the
      administrative overlay only -- the same base/override split 111_5H4
      established for usage quotas, and the reason an expired capacity
      override falls back to the CURRENT baseline instead of to unlimited.

    * Creates billing.fn_resolve_effective_capacity_quota(UUID, TEXT), a
      SEPARATE resolver. billing.fn_resolve_effective_quota is neither
      overloaded nor modified and continues to reject CONCURRENT_CALLS. The
      capacity resolver mirrors the FAR-OD-02 override semantics exactly:
      the currently-effective non-superseded override wins (source =
      PLATFORM_CAPACITY_OVERRIDE), otherwise the CURRENT
      billing.quota_configs row (source = BASE) read with no
      effective-window filter, otherwise zero rows. expires_at NULL means
      permanent-until-superseded; a superseded override never reactivates;
      the base is never snapshotted into the override row, so a baseline
      changed while an override is active is the value that takes over at
      expiry; and expiry never resolves to unlimited. SECURITY INVOKER over
      the existing RLS policies and SELECT grants, so a tenant reading its
      own effective capacity quota needs no Platform Admin privilege, with
      organization context validated in-function so a missing tenant context
      fails loudly. It returns the effective LIMIT only -- current occupancy
      is a 6K runtime reservation/gauge concern and is never read here.

    * CREATE OR REPLACEs billing.fn_platform_set_quota_override() as a
      governed domain DISPATCHER, with its public 8-argument signature and
      UUID return unchanged, so 6M section 18's single route
      POST /api/v1/platform-admin/organizations/{id}/quota-overrides is
      preserved and no second route is added. A canonical usage metric writes
      billing.quota_overrides exactly as 111_5H4 did; a canonical capacity
      metric writes billing.capacity_quota_overrides; a metric in neither
      catalog -- including NULL, now rejected by name rather than by a column
      constraint -- is rejected. Every 111_5H4 security property is preserved
      in both branches: Platform-Admin-only authorization as the first check,
      required p_admin_user_id, reason length 10..2000, future-dated expiry,
      the 052_5H-consistent limit rules (fractional limits allowed, NULL
      hard_limit still meaning overage-allowed), organization existence
      validation, a transaction-scoped advisory lock taken INSIDE the
      database boundary per frozen 6A section 17.3 and now namespaced by
      domain, supersede-then-insert, the atomic same-transaction audit write,
      SECURITY DEFINER with an explicit safe search_path, EXECUTE revoked
      from PUBLIC and from app_api and granted only to app_platform_admin.
      Neither branch writes billing.quota_configs.

    * Records the FAR-P2-09 audit reconciliation in the dispatcher's
      contract. action_kind remains 'QUOTA_OVERRIDE_SET' and resource_type
      remains 'QUOTA_OVERRIDE' with resource_id = the new override row id,
      for BOTH domains, exactly as 111_5H4 writes it. This is a controlled
      audit-contract extension relative to pre-111 (107_5B5 wrote
      resource_type = 'QUOTA_CONFIG' with the base config id) and is NOT
      reverted, because from 111 onward an override is its own resource and
      naming the base config would misidentify the row that actually
      changed. No additional migration is required for it:
      audit.audit_events.resource_type and .action_kind are free TEXT
      constrained only by chk_ae_resource_type / chk_ae_action_kind
      (length 1..200) in 072_5J, with no enum and no allow-list, and no
      documented 6L or 6M consumer was promised 'QUOTA_CONFIG' as a permanent
      literal -- 6L exposes resource_type only as a generic filter and DTO
      field. The governed domain is carried in the audit snapshot's
      quota_domain key rather than by minting a second resource_type.

    No migration 001-111 is modified, 110_5C2 and 111_5H4 are not amended,
    and no migration 113 is created. No runtime reservation logic is
    implemented here: the Redis reservation/gauge model, acquire/release
    idempotency, crash recovery and reconciliation are 6K-owned API and
    architecture contracts, amended in the Phase-6 documents by this same
    pass. No billing.capacity_quota_overrides row is backfilled: at head
    111_5H4 a CONCURRENT_CALLS override could not be created through any
    sanctioned path, so no such override history exists to migrate.
"""

from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '112_5H5'
down_revision: Union[str, None] = '111_5H4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '112_5H5.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 112_5H5 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Manual reversal would require: dropping table "
        "billing.capacity_quota_overrides, dropping "
        "billing.fn_resolve_effective_capacity_quota and "
        "billing.fn_is_canonical_capacity_quota_metric, and restoring the "
        "111_5H4 bodies of billing.fn_platform_set_quota_override and "
        "billing.fn_is_canonical_usage_metric -- this destroys the "
        "Platform Admin capacity override history that 6M section 18 "
        "reports and that the QUOTA_OVERRIDE_SET audit trail references, "
        "reinstates the NULL-metric fail-open defect FAR-P2-08, and "
        "reinstates the CONCURRENT_CALLS quota contradiction FAR-P1-06 "
        "that owner decision FAR-OD-03 exists to close, leaving SRS "
        "FR-TEN-005 with no representable quota dimension again. It is "
        "NOT recommended outside of restoring a pre-112 backup.)"
    )
