"""Phase 5D.2 — wraps controlled amendment migration 093_5D2.sql.

Contact merge-lineage support: adds crm.contacts.merged_into_contact_id /
merged_at, three guard triggers (cross-tenant, immutable-once-set, plus
the FK/CHECK constraints), and crm.fn_merge_contacts() — the sole guarded
write path for MergeContacts (4C SS6.2). Resolves DEP-6G-01 (Phase 6G CRM
Reconciliation, 2026-08-28): the prior 6G design represented a merged-away
Contact via deleted_at, conflating merge with GDPR erasure. This revision
gives merge its own physical representation, distinct from erasure, and
re-points only the mutable child aggregates (Deals/Tasks/Notes/
Appointments) that already hold real UPDATE grants — crm.activities and
crm.lead_score_records remain untouched and append-only, per the explicit
instruction not to broaden those privileges.

Revision ID: 093_5D2
Revises: '092_5F12'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '093_5D2'
down_revision: Union[str, None] = '092_5F12'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '093_5D2.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 093_5D2 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. (This "
        "revision only adds new columns/triggers/functions to "
        "crm.contacts and one new function each — a manual rollback, if "
        "ever needed with no rows yet written, would be: DROP FUNCTION "
        "crm.fn_merge_contacts, crm.prevent_remerge, "
        "crm.prevent_cross_tenant_merge CASCADE; ALTER TABLE crm.contacts "
        "DROP COLUMN merged_into_contact_id, DROP COLUMN merged_at; — an "
        "operational runbook note, not an Alembic-managed downgrade.)"
    )
