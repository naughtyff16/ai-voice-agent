"""Phase 5C.2 -- wraps the Final API Reconciliation DB remediation
migration 110_5C2.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/110_5C2.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

PROVENANCE. 109_5B7 remains the final migration of the Phase 6M Admin
Platform API closure pass and the historical Phase 6M head; Phase 6M is
not reopened by this revision. 110_5C2 is owned by the FINAL API
RECONCILIATION pass and exists solely to close DEP-6E-20 /
FAR-P1-01 / DB-BLOCKER-FINAL-API-001. It is additive: migrations
001-109 are untouched and remain byte-identical.

WHAT IT DOES. Owner decision FAR-OD-01 selected OPTION B -- a hard,
synchronous, server-authoritative ACTIVE_AGENTS commercial-quota
admission check on POST /api/v1/agents and
POST /api/v1/agents/{agent_id}/clone. The interim API-layer design
acquired its own SELECT pg_advisory_xact_lock(...) from the
service/repository layer, which conflicts with frozen 6A §17.3
(application-level locking is permitted only when encapsulated inside a
Phase-5 SECURITY DEFINER function, or via the existing Campaign Redis
SETNX mechanism). 6A is preserved unchanged; the serialization moves
into the database instead.

This migration adds three functions and closes one privilege bypass:

  - voice.fn_assert_agent_quota_admission(UUID) -- internal guard.
    Derives the tenant id server-side from
    organization.current_tenant_id(), takes a transaction-scoped
    advisory lock on the per-organization quota key, resolves
    billing.quota_configs.hard_limit for metric ACTIVE_AGENTS inside its
    effective_from/expires_at window, counts the canonical counted set
    (same organization, status DRAFT or PUBLISHED, deleted_at IS NULL --
    DEPRECATED frees a slot) and raises SQLSTATE 53400 before any INSERT
    when the tenant is at its limit. EXECUTE is revoked from PUBLIC and
    granted to no role: it is owner-only and reachable exclusively from
    the two functions below.

  - voice.fn_create_agent(UUID, UUID, TEXT, TEXT) -- sole INSERT path
    for POST /api/v1/agents. Accepts only the fields already in the
    frozen 6E §30.1 request DTO; inserts exactly one DRAFT agent and
    never a voice.agent_versions row (AgentVersion creation stays
    publish-only).

  - voice.fn_clone_agent(UUID, UUID, UUID, UUID) -- sole INSERT path for
    POST /api/v1/agents/{agent_id}/clone. Validates source agent (and,
    for a published-source clone, source version) ownership against the
    server-derived tenant id and rejects absent or cross-tenant sources
    identically and non-disclosingly with SQLSTATE P0002, preserving the
    404 the frozen 6E §30.7 contract already specifies. It then passes
    through the same quota guard on the same serialization key as the
    create path, so the two Agent-creating operations contend with each
    other and neither can overshoot the limit.

  - REVOKE INSERT ON voice.agents FROM app_api, app_worker,
    app_platform_admin, with SELECT/UPDATE (and DELETE for
    app_platform_admin) re-stated unchanged. This is what makes the hard
    quota structurally enforceable rather than merely advisory: with raw
    INSERT revoked, no application principal can create an Agent outside
    the guarded path. Table ACLs are not bypassed by BYPASSRLS, so the
    revoke binds app_platform_admin too. Verified beforehand that no
    seed, worker or platform-admin path inserts into voice.agents
    anywhere in migrations 001-109 or the Phase-5 documents, so no
    legitimate writer loses a capability it was using.

The function bodies follow the pattern established by 041_5G.sql's
workflow.fn_start_workflow_execution(): SECURITY DEFINER, explicit safe
search_path, server-derived tenant cross-check as the first statement,
pg_advisory_xact_lock taken inside the function, public.gen_uuid_v7()
for ids, REVOKE ALL FROM PUBLIC, and explicit narrow GRANT EXECUTE
(here: app_api only, the sole principal serving those two endpoints).

Audit events and domain-event outbox rows are NOT written here. They
remain API-issued in the same transaction through the existing
primitives audit.fn_insert_audit_event() and INSERT INTO
audit.domain_event_outbox; no second event mechanism is introduced. A
quota rejection raises before the INSERT and therefore commits neither
the agent row nor any audit or outbox row, and the advisory lock is
released by the surrounding ROLLBACK.

Revision ID: 110_5C2
Revises: 109_5B7
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '110_5C2'
down_revision: Union[str, None] = '109_5B7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '110_5C2.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 110_5C2 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Manual reversal would require: dropping voice.fn_create_agent, "
        "voice.fn_clone_agent and "
        "voice.fn_assert_agent_quota_admission, and re-issuing GRANT "
        "INSERT ON voice.agents TO app_api, app_worker, "
        "app_platform_admin -- this reopens the raw Agent INSERT bypass "
        "that defeats the hard ACTIVE_AGENTS quota invariant owner "
        "decision FAR-OD-01 exists to enforce, and is NOT recommended "
        "outside of restoring a pre-110 backup.)"
    )
