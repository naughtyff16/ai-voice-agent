"""Phase 5C.1 — wraps controlled amendment migration 099_5C1.sql.

Adds voice.fn_new_uuid_v7(), extends voice.call_dispatch_keys with a
provider-submission-boundary dispatch state machine (RESERVED -> CLAIMED ->
SUBMITTING -> CONFIRMED | AMBIGUOUS | FAILED, FAILED also reachable
directly from CLAIMED), voice.fn_initiate_outbound_call_idempotent()
(revised — tenant + payload-fingerprint replay validation),
voice.fn_claim_dispatch_for_provider_submission() (revised — never
reclaims SUBMITTING regardless of lease staleness), voice.
fn_begin_provider_submission() (new — the durable pre-network-call
boundary), voice.fn_record_dispatch_confirmed(), voice.
fn_record_dispatch_ambiguous(), voice.fn_record_dispatch_failed()
(revised source states); voice.fn_reconcile_dispatch_outcome_internal()
(new name/shape this pass — the actual reconciliation mechanism, never
directly granted EXECUTE to any role); voice.fn_reconcile_dispatch_from_
provider() (new this pass — EXECUTE: app_voice_reconciler only; can only
ever record PROVIDER_CALLBACK/PROVIDER_LOOKUP provenance); voice.
fn_reconcile_dispatch_by_operator() (new this pass — EXECUTE:
app_platform_admin only; hardcodes OPERATOR provenance, takes no source
parameter). Ten voice.fn_* functions total in this migration (up from
eight — replaces the single fn_reconcile_dispatch_outcome() with three).
Also creates one new PostgreSQL role, app_voice_reconciler (LOGIN, not
BYPASSRLS, no table DML — EXECUTE on exactly one function), introduced by
the prior (Final Blocker Remediation) pass.

Resolves Phase 6H Campaign remediation Blocker #3 (Campaign -> Voice
in-process dispatch idempotency), its follow-on Blocker C
(crash-before-provider-submission durability hole), the Final Blocker
Remediation pass's Blocker A (expired-CLAIMED-lease double-dial hazard),
Blocker C (direct-INSERT privilege bypass — see the GRANT statements in
099_5C1.sql), and Blocker D (idempotency replay tenant/payload
validation); the Final Micro-Remediation pass's reconciliation-
authorization-boundary fix (WHO may reconcile: app_voice_reconciler /
app_platform_admin only, revoked from app_api/app_worker); and this final
pass's reconciliation-PROVENANCE fix (WHICH provenance category a given
credential can ever produce — the single fn_reconcile_dispatch_outcome()
still let either authorized caller freely choose PROVIDER_CALLBACK /
PROVIDER_LOOKUP / OPERATOR via a plain parameter, meaning the automated
reconciler could falsely record itself as an operator decision or vice
versa — an audit-integrity defect. Splitting into two capability-specific
functions, each hardcoding the provenance/actor_type its own EXECUTE grant
is allowed to produce, makes this impossible by construction rather than
by convention. Additive only — voice.call_sessions itself is untouched.
See 099_5C1.sql's own header comment for full rationale.

Revision ID: 099_5C1
Revises: '098_5E1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '099_5C1'
down_revision: Union[str, None] = '098_5E1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '099_5C1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 099_5C1 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here. To revert, restore "
        "from a database backup taken before this revision was applied "
        "(the ten new voice.fn_* functions would need to be dropped, "
        "then voice.call_dispatch_keys itself, then the app_voice_reconciler "
        "role — an operational runbook note, not an Alembic-managed "
        "downgrade)."
    )
