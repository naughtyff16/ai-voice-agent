"""Phase 5H.4 -- true temporary Platform-Admin quota overrides with live
commercial-baseline fallback, one canonical effective-quota resolver, and
restoration of the canonical 5H section 11.1 usage-metric vocabulary.

This revision executes the frozen, canonical SQL file
5K/migrations/111_5H4.sql verbatim via op.get_bind().exec_driver_sql()
(through _frozen_sql.run_frozen_sql, the shared helper every 5K revision
wrapper uses). Do not add DDL here: the .sql file is the single source of
truth for the schema change, and this module exists only to place that file
in the Alembic dependency graph.

PROVENANCE.
    FINAL API RECONCILIATION -- FINAL BILLING / QUOTA OVERRIDE CLOSURE.
    Owner decision FAR-OD-02 = OPTION B (true temporary overrides with
    baseline fallback).
    Closes FAR-P1-04, FAR-P1-05, FAR-OD-02, FAR-P2-04 and FAR-P2-05.

    Two P1 defects were reproduced from the committed sources before this
    revision was written; neither was taken on the reviewer's word.

    FAR-P1-04 -- metric-vocabulary regression. 107_5B5 issued a
    CREATE OR REPLACE of billing.fn_platform_set_quota_override() carrying a
    different 15-name allow-list from the canonical one 106_5H3 had
    established. Compared programmatically, the two sets intersect in only
    two names (CALL_MINUTES, STORAGE_GB); thirteen canonical metrics are
    absent from 107_5B5 and thirteen non-canonical legacy names are present.
    The operative consequence is that at head 110_5C2 the metric string
    'ACTIVE_AGENTS' -- the one 6E section 43 admission enforces -- was not
    representable through the Platform Admin override function at all.

    FAR-P1-05 -- base-quota overwrite and expiry-to-unlimited.
    billing.quota_configs holds exactly one row per (organization_id,
    metric) under uq_qc_org_metric, and both 106_5H3 and 107_5B5 implemented
    the override as INSERT ... ON CONFLICT ON CONSTRAINT uq_qc_org_metric
    DO UPDATE against that same row. The temporary override therefore
    overwrote the commercial baseline in place, destroying it. 110_5C2's
    admission guard then read that row through an effective window and took
    its NOT FOUND branch once the window closed, so an expired override left
    the organization UNLIMITED with no record of the commercial limit
    anywhere in the database.

WHAT IT DOES.
    * Creates billing.fn_is_canonical_usage_metric(TEXT), the single
      IMMUTABLE definition of the canonical 15-metric vocabulary owned by
      5H section 11.1. The table CHECK constraint, the override function and
      the resolver all consume it, so a second copy cannot silently diverge
      the way 107_5B5's inline list did. Legacy 107_5B5 names are rejected
      and deliberately NOT aliased to canonical ones -- an alias would
      establish a permanent dual vocabulary that 6K reporting, 6E admission,
      the Redis hot-tier key space and the nightly reconciliation would all
      have to normalise forever.

    * Creates billing.quota_overrides, an additive table in which each
      temporary Platform-Admin override is its own row. billing.quota_configs
      is not overloaded again and its limit columns are never written by the
      override path. At most one non-superseded override exists per
      (organization_id, metric), enforced by the partial unique index
      uq_qo_org_metric_current -- the same single-current-row convention as
      uq_sub_org_active (049_5H) and uq_memberships_active (003_5B).
      ENABLE + FORCE row level security, a tenant SELECT policy and a
      Platform Admin policy; SELECT granted to app_api, app_worker,
      app_readonly and app_platform_admin, and INSERT/UPDATE/DELETE granted
      to no role at all, so the guarded function is the only write path.

    * Creates billing.fn_resolve_effective_quota(UUID, TEXT), the one
      canonical resolver. It returns the currently-effective non-superseded
      override (source = PLATFORM_OVERRIDE) if one exists, otherwise the
      CURRENT billing.quota_configs row (source = BASE). The base row is read
      with NO effective-window filter: quota_configs.expires_at is legacy
      106_5H3 override metadata and never means the commercial baseline has
      disappeared. Because the base is never copied into an override row, a
      baseline changed while an override is active is the value that takes
      over at expiry. SECURITY INVOKER over the existing RLS policies and
      SELECT grants, so a tenant reading its own effective quota needs no
      Platform Admin privilege; organization context is validated in-function
      so a missing tenant context fails loudly instead of resolving to
      "unlimited", and a non-canonical metric raises rather than returning
      zero rows that every consumer would read as unlimited.

    * CREATE OR REPLACEs billing.fn_platform_set_quota_override() with its
      public 8-argument signature and UUID return unchanged, so 6M
      section 18's endpoint contract is preserved. It keeps every 107_5B5
      security remediation (organization existence validation, atomic audit
      write, app_platform_admin-only EXECUTE, EXECUTE revoked from app_api,
      SECURITY DEFINER with an explicit safe search_path) and restores every
      106_5H3 validation lost in that replace (p_admin_user_id NOT NULL,
      reason length, the canonical allow-list, future expiry, the full
      unit-label derivation). It does NOT reinstate 107_5B5's "both limits
      non-NULL and > 0" rule, which contradicts the real 052_5H column
      semantics and would make an overage-allowed override (hard_limit NULL,
      6K section 25.1's binding rule) impossible to create through the only
      sanctioned write path; limits stay NUMERIC(18,4) and may be fractional.
      Under a transaction-scoped advisory lock on (organization, metric) it
      atomically supersedes the previously-current override and INSERTs a new
      row, then writes the QUOTA_OVERRIDE_SET audit event in the same
      transaction. It never writes billing.quota_configs.

    * CREATE OR REPLACEs voice.fn_assert_agent_quota_admission(UUID).
      110_5C2 is not amended; this is a forward replace, and exactly one
      thing changes -- the source of the effective hard limit becomes
      billing.fn_resolve_effective_quota(org, 'ACTIVE_AGENTS'). Every
      110_5C2 invariant is preserved verbatim: server-side tenant derivation
      and the organization-match check, the advisory lock held inside the
      database boundary (frozen 6A section 17.3), the fractional-safe
      post-insert comparison (v_active + 1) > v_hard_limit with the limit
      never rounded (FAR-P1-02), NULL hard limit = unlimited, the counted set
      of DRAFT and PUBLISHED agents excluding soft-deleted rows, SQLSTATE
      53400 with an identical DETAIL payload, and owner-only reachability
      with no EXECUTE grant. The raw-INSERT revoke, the mutation trigger and
      the actor assertion from 110_5C2 are untouched and continue to apply.

    * Adds documentation-only COMMENT ON COLUMN markers recording
      billing.quota_configs.override_reason, .effective_from, .expires_at and
      .updated_by as legacy compatibility metadata from 111 onward. No
      column added by 106_5H3 is dropped and no data is rewritten.

    No migration 001-110 is modified, 110_5C2 is not amended, and no
    migration 112 is created. No billing.quota_overrides row is backfilled
    from the legacy override metadata on billing.quota_configs: where a
    pre-111 in-place override had already overwritten a commercial baseline,
    that baseline was destroyed in place and is not recoverable, and
    fabricating a replacement would be production-data fiction.
"""

from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '111_5H4'
down_revision: Union[str, None] = '110_5C2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '111_5H4.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 111_5H4 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Manual reversal would require: dropping table "
        "billing.quota_overrides, dropping "
        "billing.fn_resolve_effective_quota and "
        "billing.fn_is_canonical_usage_metric, and restoring the 107_5B5 "
        "bodies of billing.fn_platform_set_quota_override and the 110_5C2 "
        "body of voice.fn_assert_agent_quota_admission -- this destroys "
        "the Platform Admin override history that 6M section 18 reports "
        "and that the QUOTA_OVERRIDE_SET audit trail references, and "
        "reinstates both the metric-vocabulary regression FAR-P1-04 and "
        "the base-quota overwrite / expiry-to-unlimited defect FAR-P1-05 "
        "that owner decision FAR-OD-02 exists to close. It is NOT "
        "recommended outside of restoring a pre-111 backup.)"
    )
