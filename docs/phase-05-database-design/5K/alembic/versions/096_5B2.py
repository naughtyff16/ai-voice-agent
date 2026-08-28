"""Phase 5B.2 — wraps controlled amendment migration 096_5B2.sql.

Permission catalog amendment: adds crm_field:manage (OWNER/ADMIN only),
resolving DEP-6G-10 (Phase 6G CRM Reconciliation, 2026-08-28) — CRM
custom-field-definition administration has tenant-wide schema impact and
was previously mapped onto the MEMBER-eligible contact:write for lack of
a dedicated scope. Purely additive (ON CONFLICT DO NOTHING, matching
007_5B.sql's own idempotent seeding pattern); does not modify 007_5B.sql
or any other permission/role/role-permission row.

Revision ID: 096_5B2
Revises: '095_5D4'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '096_5B2'
down_revision: Union[str, None] = '095_5D4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '096_5B2.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 096_5B2 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here. (Manual rollback, if "
        "ever needed: DELETE FROM organization.role_permissions WHERE "
        "permission_id = (SELECT id FROM organization.permissions WHERE "
        "name = 'crm_field:manage'); DELETE FROM organization.permissions "
        "WHERE name = 'crm_field:manage'; — an operational runbook note, "
        "not an Alembic-managed downgrade.)"
    )
