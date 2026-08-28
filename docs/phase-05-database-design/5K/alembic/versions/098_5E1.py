"""Phase 5E.1 — wraps controlled amendment migration 098_5E1.sql.

Adds campaign.campaign_contact_identities, campaign.fn_new_uuid_v7(),
campaign.fn_enqueue_contact(), campaign.fn_reserve_dispatch(). Resolves
Phase 6H Campaign remediation Blocker #1 (CampaignContact duplicate-enqueue
race, DEP-6H-03) and Blocker #2 (durable Pause/Stop-vs-dispatch
serialization). Additive only — no existing 5E table/column/constraint/
grant is altered. See 098_5E1.sql's own header comment for full rationale.

Revision ID: 098_5E1
Revises: '097_5D5'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '098_5E1'
down_revision: Union[str, None] = '097_5D5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '098_5E1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 098_5E1 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here. To revert, restore "
        "from a database backup taken before this revision was applied "
        "(campaign.campaign_contact_identities and its three new "
        "functions would need to be dropped, in dependency order: "
        "fn_reserve_dispatch, fn_enqueue_contact, fn_new_uuid_v7, then "
        "the table — an operational runbook note, not an Alembic-managed "
        "downgrade)."
    )
