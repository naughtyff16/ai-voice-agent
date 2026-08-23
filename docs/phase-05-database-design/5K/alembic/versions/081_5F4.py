"""Phase 5F.4 — wraps controlled amendment migration 081_5F4.sql.

Executes 5K/migrations/081_5F4.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

081_5F4 is a Phase 5L Global Database Reconciliation migration. It
resolves DEP-6F-15 by adding knowledge.fn_docver_gdpr_erase() and
knowledge.fn_document_gdpr_delete() — two new SECURITY DEFINER
functions, no existing object changed.

Revision ID: 081_5F4
Revises: '080_5F3'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '081_5F4'
down_revision: Union[str, None] = '080_5F3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '081_5F4.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 081_5F4 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. GDPR "
        "erasure is inherently irreversible by design — a downgrade "
        "cannot and must not attempt to un-erase data even if the "
        "functions themselves were dropped."
    )
