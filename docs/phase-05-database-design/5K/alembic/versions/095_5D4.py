"""Phase 5D.4 — wraps controlled amendment migration 095_5D4.sql.

crm.fn_apply_lead_score(): CAS-safe denormalized score/temperature apply,
fixing the out-of-order-overwrite race the prior 6G design accepted as a
risk (Phase 6G CRM Reconciliation, 2026-08-28). No new column: uses a
Contact-row lock plus a (computed_at, id) recency check against the
already-existing, append-only crm.lead_score_records history.

Revision ID: 095_5D4
Revises: '094_5D3'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '095_5D4'
down_revision: Union[str, None] = '094_5D3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '095_5D4.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 095_5D4 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here. (This revision only "
        "adds one new function — a manual rollback, if ever needed, "
        "would be: DROP FUNCTION crm.fn_apply_lead_score; — an "
        "operational runbook note, not an Alembic-managed downgrade.)"
    )
