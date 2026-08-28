"""Phase 5D.3 — wraps controlled amendment migration 094_5D3.sql.

Durable CRM event-consumer idempotency: crm.event_consumer_dedup (true
PRIMARY KEY on (consumer_name, source_event_id)) + crm.fn_claim_event().
Resolves Blocker C (Phase 6G CRM Reconciliation, 2026-08-28): the prior
6G design used a race-prone "SELECT for existing call_ref, then INSERT"
pattern for at-least-once Voice->CRM event delivery. CRM-owned (not a
reuse of analytics.analytics_event_dedup), separate from
audit.domain_event_outbox (the publisher-side durable queue, 077_5J1) —
this is the consumer-side dedup ledger.

Revision ID: 094_5D3
Revises: '093_5D2'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '094_5D3'
down_revision: Union[str, None] = '093_5D2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '094_5D3.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 094_5D3 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. (This "
        "revision only adds one new table and one new function — a "
        "manual rollback, if ever needed with no rows yet written, would "
        "be: DROP FUNCTION crm.fn_claim_event; DROP TABLE "
        "crm.event_consumer_dedup CASCADE; — an operational runbook "
        "note, not an Alembic-managed downgrade.)"
    )
