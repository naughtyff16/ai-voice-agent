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

AMENDED IN PLACE by the FINAL 110_5C2 MICRO-REMEDIATION pass. Migration
110 was not frozen when an independent freeze gate found two P1 defects
and one P2 finding in it, so 110_5C2.sql was corrected in place rather
than superseded by a migration 111. No migration 111 exists and the
single Alembic head remains 110_5C2. The corrections are FAR-P1-02
(fractional hard_limit admission arithmetic), FAR-P1-03 (ACTIVE_AGENTS
counted-set re-entry through raw UPDATE) and FAR-P2-03 (the created_by
trust boundary). They are described in place below.

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

This migration adds five functions, one trigger, and closes two bypass
paths into the ACTIVE_AGENTS counted set:

  - voice.fn_assert_agent_quota_admission(UUID) -- internal guard.
    Derives the tenant id server-side from
    organization.current_tenant_id(), takes a transaction-scoped
    advisory lock on the per-organization quota key, resolves
    billing.quota_configs.hard_limit for metric ACTIVE_AGENTS inside its
    effective_from/expires_at window, counts the canonical counted set
    (same organization, status DRAFT or PUBLISHED, deleted_at IS NULL --
    DEPRECATED frees a slot) and raises SQLSTATE 53400 before any INSERT
    unless the POST-INSERT count would still satisfy the limit. EXECUTE
    is revoked from PUBLIC and granted to no role: it is owner-only and
    reachable exclusively from the two creating functions below.

    FAR-P1-02. hard_limit is NUMERIC(18,4) and the column structurally
    permits fractional commercial limits, so the original condition
    "active >= hard_limit" was wrong: with hard_limit 1.5000 and
    active 1, 1 >= 1.5 is false, the INSERT succeeded, and the committed
    count became 2 > 1.5. Each guarded operation consumes exactly one
    slot, so the enforced condition is now (active + 1) > hard_limit ->
    reject, i.e. post_insert_count <= hard_limit. The configured
    commercial limit is compared as stored; it is never rounded,
    CEIL-ed or FLOOR-ed.

  - voice.fn_assert_agent_actor(UUID, UUID) -- internal guard
    (FAR-P2-03). Both creating functions take p_created_by as a
    parameter, and the original code only checked it for NULL. The
    database has no session actor to appeal to: the only identity
    context this system carries in PostgreSQL is
    organization.current_tenant_id() (app.tenant_id) and
    organization.is_platform_admin() (app.is_platform_admin), both from
    001_5B; no current-user/actor helper exists anywhere in 001-109 and
    none is invented here. The parameter is therefore retained, with the
    trust boundary stated explicitly in the SQL: p_created_by is
    supplied only by the authenticated application layer and is never a
    client request field (6E §30.1 pins the DTO to name/description with
    extra="forbid"; created_by is implicit from the actor), app_api is
    the trusted DB principal boundary, and these functions do not claim
    to independently authenticate the actor. What the guard does add is
    tenant-scoping: the referenced user must appear on this
    organization's organization.memberships roster, so an actor
    belonging to another tenant cannot be stamped onto an Agent.
    Membership is matched in any status ('ACTIVE','SUSPENDED',
    'REMOVED') so that API-key semantics are preserved -- an API key
    outlives changes to its creator's membership status. No concrete
    cross-tenant forgery path reachable from a normal API request was
    identified, so this remains a P2 hardening.

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

  - voice.fn_agents_mutation_guard() + trigger trg_agents_mutation_guard
    (BEFORE UPDATE ... FOR EACH ROW ON voice.agents) -- FAR-P1-03.
    Revoking INSERT closes only one entrance to the counted set. Because
    that set is (status IN ('DRAFT','PUBLISHED') AND deleted_at IS
    NULL), a plain UPDATE could also push a row back INTO it without
    passing the admission guard: DEPRECATED -> DRAFT, DEPRECATED ->
    PUBLISHED, or deleted_at NOT NULL -> NULL. UPDATE is NOT revoked --
    app_api needs it for the existing 6E PATCH, publish and deprecate
    paths -- so the invariant is enforced with the project's established
    BEFORE UPDATE guard-trigger pattern (voice.prevent_agent_version_
    mutation in 009_5C, workflow.prevent_execution_mutation in 039_5G,
    integrations.fn_id_slug_immutable in 060_5I). The permitted status
    transitions are read off the frozen 6E lifecycle rather than
    invented: 6E §31.1's state machine and §31.3's transition guard
    table together permit DRAFT -> PUBLISHED (publish) and PUBLISHED ->
    DEPRECATED (deprecate), with DEPRECATED terminal and no command
    leaving it. Same-state updates (DRAFT -> DRAFT, PUBLISHED ->
    PUBLISHED, DEPRECATED -> DEPRECATED) are untouched, so ordinary
    field edits keep working on every status. The same trigger makes
    organization_id immutable after INSERT -- no frozen contract defines
    an Agent ownership transfer, 6E never exposes organization_id as a
    writable field, and app_platform_admin holds BYPASSRLS, so without
    the rule a raw UPDATE by that role could silently move an Agent
    across tenants and mutate both tenants' counts -- and forbids
    clearing deleted_at. The soft-delete DIRECTION stays legal because
    it can only free a slot; no delete, archive or restore API is
    introduced. Triggers, like table ACLs and unlike row-level security,
    are not bypassed by BYPASSRLS, so the rule binds every role.

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
        "(Manual reversal would require: dropping trigger "
        "trg_agents_mutation_guard and the functions "
        "voice.fn_agents_mutation_guard, voice.fn_create_agent, "
        "voice.fn_clone_agent, voice.fn_assert_agent_actor and "
        "voice.fn_assert_agent_quota_admission, and re-issuing GRANT "
        "INSERT ON voice.agents TO app_api, app_worker, "
        "app_platform_admin -- this reopens both the raw Agent INSERT "
        "bypass and the counted-set re-entry bypass that defeat the "
        "hard ACTIVE_AGENTS quota invariant owner decision FAR-OD-01 "
        "exists to enforce, and is NOT recommended outside of restoring "
        "a pre-110 backup.)"
    )
