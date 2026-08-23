"""Phase 5J.1 — wraps controlled amendment migration 077_5J1.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/077_5J1.sql verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen once merged) and adding parallel DDL
here would create a second, competing schema history — see
5K/alembic/README.md.

077_5J1 is a controlled amendment on top of the validated 001-076
baseline (075_5J + 076_5K1 corrective patch). It resolves DEP-6C-16
(Phase 6C — Core Platform APIs): no concrete PostgreSQL transactional-
outbox relation existed anywhere in the frozen schema prior to this
revision. It adds exactly one new table (audit.domain_event_outbox)
and three new SECURITY DEFINER functions plus one trigger function, all
inside the already-frozen `audit` schema. No existing 001-076 object is
altered.

See 5K/migrations/077_5J1.sql for full rationale (schema placement, RLS
posture, claiming semantics, retention policy).

Revision ID: 077_5J1
Revises: '076_5K1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = '077_5J1'
down_revision: Union[str, None] = '076_5K1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '077_5J1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 077_5J1 is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/077_5J1.sql). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied. "
        "(This revision only adds new objects — audit.domain_event_outbox "
        "and three new functions — so a manual DROP is also low-risk if "
        "no rows have been written yet: DROP TABLE audit.domain_event_outbox "
        "CASCADE; DROP FUNCTION audit.fn_claim_outbox_events, "
        "audit.fn_mark_outbox_published, audit.fn_mark_outbox_failed, "
        "audit.fn_outbox_tenant_check; — but this is an operational "
        "runbook note, not an Alembic-managed downgrade.)"
    )
