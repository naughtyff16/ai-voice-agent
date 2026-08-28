"""Phase 5D.5 — wraps controlled amendment migration 097_5D5.sql.

CREATE OR REPLACE crm.fn_merge_contacts() to remove Contact PII
(full_name, phone_e164) from the immutable merge-marker Activity payload.
Resolves a GDPR-erasure-boundary defect found by an independent
whole-project review following the Phase 6G CRM Reconciliation
(2026-08-28): crm.activities is append-only and survives Contact GDPR
erasure, so copying a Contact's name/phone into that payload created a
second, erasure-proof PII copy. The marker payload now carries
identifiers/provenance only (event, primary_contact_id,
secondary_contact_id, merged_by). Every other line of the function —
guards, lock ordering, field-fill, mutable-child repointing, merge-
lineage assignment — is unchanged from 093_5D2.sql.

Revision ID: 097_5D5
Revises: '096_5B2'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '097_5D5'
down_revision: Union[str, None] = '096_5B2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '097_5D5.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 097_5D5 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here. (This revision only "
        "replaces one function's body via CREATE OR REPLACE — a manual "
        "rollback, if ever needed, would re-apply 093_5D2.sql's original "
        "CREATE OR REPLACE FUNCTION crm.fn_merge_contacts(...) block, "
        "which would restore the PII-leaking payload; not recommended. "
        "An operational runbook note, not an Alembic-managed downgrade.)"
    )
