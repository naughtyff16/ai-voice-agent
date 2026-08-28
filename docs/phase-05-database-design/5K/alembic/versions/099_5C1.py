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
(revised source states), voice.fn_reconcile_dispatch_outcome() (new —
identity-correlated resolution of a SUBMITTING/AMBIGUOUS row, e.g. from a
delayed provider callback). Eight voice.fn_* functions total in this
migration. Resolves Phase 6H Campaign remediation Blocker #3 (Campaign ->
Voice in-process dispatch idempotency), its follow-on Blocker C
(crash-before-provider-submission durability hole), and the Final Blocker
Remediation pass's Blocker A (expired-CLAIMED-lease double-dial hazard),
Blocker C (direct-INSERT privilege bypass — see the GRANT statements in
099_5C1.sql), and Blocker D (idempotency replay tenant/payload
validation). Additive only — voice.call_sessions itself is untouched. See
099_5C1.sql's own header comment for full rationale.

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
        "(the eight new voice.fn_* functions would need to be dropped, "
        "then voice.call_dispatch_keys itself — an operational runbook "
        "note, not an Alembic-managed downgrade)."
    )
