"""Phase 5F.10 — wraps controlled correction migration 090_5F10.sql.

Executes 5K/migrations/090_5F10.sql verbatim (see 078_5F1.py's header
for the shared wrapper convention this revision follows).

090_5F10 is a Phase 5L.1 post-reconciliation correction. It closes a
Document<->DocumentVersion knowledge_base_id drift gap: 078_5F1.sql had
re-granted app_api/app_worker column-level UPDATE on every
knowledge.documents column except current_version_id, including
knowledge_base_id/organization_id/source_type/created_by/created_at —
none of which 4E's Document aggregate supports mutating post-creation.
Narrows the grant to only the genuinely mutable columns.

Revision ID: 090_5F10
Revises: '089_5F9'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '090_5F10'
down_revision: Union[str, None] = '089_5F9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '090_5F10.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 090_5F10 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: GRANT UPDATE (knowledge_base_id, "
        "organization_id, source_type, created_by, created_at) ON "
        "knowledge.documents TO app_api, app_worker; — but this "
        "reintroduces the KB/tenant-drift gap this revision closes.)"
    )
