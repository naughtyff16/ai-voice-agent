"""Phase 5B.5 -- wraps controlled hardening migration 107_5B5.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/107_5B5.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

107_5B5 is a forward, additive migration driven by the Phase 6M
(Admin/Platform Control-Plane API) STRICT FINAL REMEDIATION review. It
does NOT edit 001-104 (frozen) and does NOT edit 105_5B4.sql or
106_5H3.sql's own text -- it CREATE OR REPLACEs functions those files
defined and narrows/extends GRANTs those files (and 018_5C.sql) issued,
the same override technique 106_5H3.sql already used against
001_5B.sql's is_platform_admin(). Six independent defects are closed:

(A) P0 self-forgery: organization.is_platform_admin() previously trusted
    a single caller-settable GUC (even after 106_5H3's COALESCE fix for
    the NULL-fail-open bug). Any app_api session could run SET app.
    is_platform_admin = 'true' and self-authorize. Now additionally
    binds to session_user = 'app_platform_admin' -- the actual
    authenticated connecting role, fixed at connection time, never
    settable by a SQL session and unaffected by SECURITY DEFINER
    (unlike current_user).

(B) Over-broad EXECUTE grants: every Platform-Admin-only function
    (break-glass grant/release/check, org suspend/reactivate, quota
    override, refund reserve) was also GRANTed to app_api in 087_5B1/
    105_5B4/106_5H3. Narrowed to app_platform_admin only.

(C) P0 raw sensitive-media access: 018_5C.sql's blanket GRANT SELECT,
    INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA voice TO app_
    platform_admin let a Platform Admin (BYPASSRLS) directly read
    voice.recordings.storage_ref, voice.transcript_segments.text,
    voice.conversations.summary_text, and voice.turns.utterance_text/
    response_text across every tenant with no break-glass, no purpose,
    no audit. Superseded with REVOKE ALL + column-level GRANT SELECT
    excluding those columns, plus two new guarded SECURITY DEFINER
    functions (voice.fn_platform_access_recording, voice.fn_platform_
    access_transcript) that are the only remaining path to that
    content, gated on a durable SENSITIVE_MEDIA_ACCESS break-glass
    grant bound to org + admin + session (via the existing organization.
    fn_break_glass_check from 105_5B4) plus an independent resource-
    ownership cross-check. This also closes the transcript break-glass
    parity gap (recording and transcript support now use the identical
    guard).

(D) P1 refund fabrication: fn_platform_settle_refund/fn_platform_fail_
    refund previously accepted a caller-supplied provider_refund_id
    with no independent verification and were callable by app_
    platform_admin, letting a human support connection mark a refund
    SUCCEEDED with a fabricated provider reference. Introduces a new
    dedicated, non-admin, non-superuser principal app_billing_
    reconciler (LOGIN only, no BYPASSRLS -- the same CREATE ROLE
    pattern as app_voice_reconciler/app_billing_webhook_ingress) and
    re-points EXECUTE on both functions to it exclusively, REVOKEd
    from both app_api and app_platform_admin.

(E) P1 audit not atomic: 105_5B4.sql's and 106_5H3.sql's guarded
    mutation functions never called audit.fn_insert_audit_event()
    internally -- the audit write was a separate, non-atomic
    application-layer call. Every touched function now performs its
    audit write in the SAME transaction as its state change via the
    existing 072_5J.sql signature (already GRANTed to app_platform_
    admin/app_worker). fn_platform_suspend_organization/fn_platform_
    reactivate_organization also now persist p_reason (previously
    validated then silently discarded) into the audit resource_
    snapshot.

(F) Vocabulary: introduces action_kind values ORGANIZATION_SUSPENDED,
    ORGANIZATION_REACTIVATED, TRANSCRIPT_ACCESS_GRANTED. audit.
    audit_events.action_kind is unconstrained free text (072_5J.sql),
    so this requires no schema change -- documentation-level 5J
    vocabulary amendment only, tracked separately.

Nothing here reopens Phase 6L's frozen decisions, changes the tenant-
facing recording:read/access_media or transcript:read/access_content
permission model, or grants app_platform_admin workflow-execution-start
ability.

Revision ID: 107_5B5
Revises: 106_5H3
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '107_5B5'
down_revision: Union[str, None] = '106_5H3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '107_5B5.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 107_5B5 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Manual reversal would require, in order, and is NOT "
        "recommended outside of restoring a pre-107 backup because it "
        "reopens every defect this migration closes: DROP FUNCTION IF "
        "EXISTS voice.fn_platform_access_transcript(UUID, UUID, UUID, "
        "TEXT, UUID); DROP FUNCTION IF EXISTS voice.fn_platform_access_"
        "recording(UUID, UUID, UUID, TEXT, UUID); re-issue GRANT SELECT, "
        "INSERT, UPDATE, DELETE ON voice.recordings, voice.transcripts, "
        "voice.transcript_segments, voice.conversations, voice.turns TO "
        "app_platform_admin (restoring 018_5C.sql's original blanket "
        "grant, including unrestricted access to storage_ref/text/"
        "summary_text/utterance_text/response_text -- this recreates "
        "the P0 raw sensitive-media defect); REVOKE EXECUTE ON FUNCTION "
        "billing.fn_platform_settle_refund(UUID, UUID, TEXT), billing."
        "fn_platform_fail_refund(UUID, UUID, TEXT) FROM app_billing_"
        "reconciler and GRANT EXECUTE ... TO app_api, app_platform_admin "
        "(restoring 106_5H3.sql's original grants and the is_platform_"
        "admin()-based check in both function bodies -- this recreates "
        "the P1 refund-fabrication defect); DROP ROLE IF EXISTS app_"
        "billing_reconciler (only after revoking its schema/function "
        "grants and confirming no live connections); revert billing.fn_"
        "platform_reserve_refund, billing.fn_platform_set_quota_"
        "override, organization.fn_platform_suspend_organization, "
        "organization.fn_platform_reactivate_organization, organization."
        "fn_break_glass_release, and both organization.fn_break_glass_"
        "grant overloads to their pre-107 bodies (dropping the internal "
        "audit.fn_insert_audit_event calls and the set_config('app."
        "tenant_id', ...) calls -- this recreates the P1 non-atomic-"
        "audit defect) and re-issue GRANT EXECUTE ... TO app_api on all "
        "of them; GRANT EXECUTE ON FUNCTION organization.fn_break_glass_"
        "check(UUID, UUID, UUID, TEXT, TEXT) TO app_api; finally CREATE "
        "OR REPLACE FUNCTION organization.is_platform_admin() reverting "
        "to the 106_5H3 COALESCE-only body (dropping the session_user = "
        "'app_platform_admin' check -- this recreates the P0 self-"
        "forgery defect, and must be done LAST since every other "
        "function above depends on is_platform_admin() for its own "
        "authorization check during the window it is being reverted).)"
    )
