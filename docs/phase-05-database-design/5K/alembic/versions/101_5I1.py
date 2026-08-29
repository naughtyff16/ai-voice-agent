"""Phase 5I.1 — wraps controlled amendment migration 101_5I1.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/101_5I1.sql verbatim via
op.get_bind().exec_driver_sql(). Do not add DDL here; edit is
forbidden on the .sql file (frozen once merged) and adding parallel DDL
here would create a second, competing schema history — see
5K/alembic/README.md.

101_5I1 is a controlled amendment on top of the validated 001-100
baseline. It resolves the Phase 6J remediation pass (2026-08-29)
findings against docs/phase-06-api-design/6J-Integrations-Webhooks-
Plugins-APIs.md: DEP-6J-01 (P0 — no integration_connections
status-transition path), DEP-6J-02 (P0 — no plugin_installations
suspend/reactivate/config-update path), the OAuth-callback
tenant-bootstrap defect (P0), the webhook-secret dual-signature
rotation defect (P0), DEP-6J-04 (oauth_attempts.connection_id),
DEP-6J-05 (OAuth denial path), and DEP-6J-09 (is_active enforcement
inside fn_create_integration_connection).

It adds: 5 new columns (2 on integrations.oauth_attempts, 2 on
webhooks.webhook_endpoints — all nullable, all additive), 11 new
SECURITY DEFINER functions, 1 CREATE OR REPLACE on a pre-existing
function body (fn_create_integration_connection — same signature,
adds one additional check), and 5 EXECUTE-grant widenings on
pre-existing 059-066 functions. No existing 001-100 object's PRIMARY
KEY, RLS policy, or pre-existing REVOKE baseline is altered.

See 5K/migrations/101_5I1.sql for full rationale (including the direct
citation proving app_migration/app_platform_admin already carry
BYPASSRLS, which is why the OAuth-callback fix did not require
removing RLS from oauth_attempts).

Revision ID: 101_5I1
Revises: '100_5G1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

# revision identifiers, used by Alembic.
revision: str = '101_5I1'
down_revision: Union[str, None] = '100_5G1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '101_5I1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 101_5I1 is part of the frozen, forward-only 5K SQL "
        "package (5K/migrations/101_5I1.sql). No rollback DDL exists for "
        "it and none is authored here, to avoid creating schema changes "
        "outside the canonical migration files. To revert, restore from "
        "a database backup taken before this revision was applied. "
        "(This revision only adds new objects and widens EXECUTE grants "
        "— it narrows nothing and drops nothing — so a manual reversal is "
        "also low-risk if no rows have been written to the new columns "
        "yet: REVOKE the 5 widened grants; DROP FUNCTION "
        "integrations.fn_activate_integration_connection, "
        "integrations.fn_fail_integration_connection, "
        "integrations.fn_degrade_integration_connection, "
        "integrations.fn_disconnect_integration_connection, "
        "integrations.fn_update_integration_connection_config, "
        "integrations.fn_record_integration_sync_result, "
        "integrations.fn_redeem_oauth_callback_state, "
        "integrations.fn_fail_oauth_callback_state, "
        "plugins.fn_suspend_plugin_installation, "
        "plugins.fn_reactivate_plugin_installation, "
        "plugins.fn_update_plugin_installation_config, "
        "plugins.fn_rotate_plugin_installation_credential, "
        "webhooks.fn_rotate_webhook_secret; "
        "ALTER TABLE integrations.oauth_attempts DROP COLUMN connection_id, "
        "DROP COLUMN failure_reason; ALTER TABLE webhooks.webhook_endpoints "
        "DROP COLUMN previous_signing_secret_ref, DROP COLUMN "
        "previous_secret_expires_at; restore fn_create_integration_connection "
        "to its 061_5I body (CREATE OR REPLACE with that file's exact text) — "
        "but this is an operational runbook note, not an Alembic-managed "
        "downgrade.)"
    )
