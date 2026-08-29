"""Phase 5G.1 — wraps controlled reconciliation migration 100_5G1.sql.

Phase 6I Blocker Remediation pass (2026-08-29):

  Blocker A — durable node-side-effect claim/state machine
  (workflow.node_execution_claims + fn_claim_node_execution() /
  fn_begin_node_submission() / fn_record_node_succeeded() /
  fn_record_node_ambiguous() / fn_record_node_failed()), mirroring
  voice.call_dispatch_keys' proven RESERVED/CLAIMED/SUBMITTING/
  CONFIRMED|AMBIGUOUS|FAILED design (099_5C1.sql) for TOOL_CALL/
  TRANSFER/HUMAN_TRANSFER Workflow node side effects (WEBHOOK/API_CALL
  remain execution-blocked pending 6J regardless, ADR-6I-04 unchanged).

  Blocker B — workflow.workflow_executions.checkpoint_seq (monotonic,
  DB-enforced non-decreasing via both the new guarded CAS function
  fn_checkpoint_workflow_execution() and a hardened
  prevent_execution_mutation() trigger), plus
  fn_complete_workflow_execution() / fn_fail_workflow_execution() as
  the sole legal terminal-state transitions.

  Blocker A/§26/§27 — fn_start_workflow_execution() revised (DROP +
  CREATE, return-type change): returns a deterministic outcome
  (STARTED | REPLAYED_EXISTING | VERSION_CONFLICT) instead of raising
  on a duplicate-active-session race, and rejects starting a new
  execution when the WorkflowVersion's parent WorkflowDefinition is
  ARCHIVED.

  Blocker C — app_platform_admin reduced to SELECT-only on
  workflow.workflow_definitions, workflow.workflow_versions,
  workflow.workflow_executions, and the new
  workflow.node_execution_claims; app_api/app_worker's own UPDATE on
  workflow_executions revoked (Part B's guarded functions are now the
  sole mutation path); prompt.prompt_versions given the identical
  admin-DML reduction (the disclosed sibling gap found by the same
  review).

  Blocker D — workflow_versions'/prompt_versions' immutability
  triggers hardened to also guard workflow_definition_id/
  prompt_template_id and organization_id (identity columns the
  original triggers never checked); a new
  prevent_archived_definition_mutation() BEFORE UPDATE trigger on
  workflow.workflow_definitions makes ARCHIVED unconditionally
  terminal for every mutable field, closing the archive-vs-draft-
  update / archive-vs-metadata-update race.

Phase 6I FINAL Blocker Remediation pass (same day), extending the above:

  Blocker E — guarded Workflow publish/archive capability. app_api/
  app_worker's raw INSERT on workflow_versions is revoked; their
  table-level UPDATE on workflow_definitions is revoked and re-granted
  only on (name, description, draft_graph) — status/published_version_id
  are no longer writable by any runtime role via raw DML at all. The
  pre-existing 039_5G.sql fn_workflow_publish() (which accepted any
  already-existing version_id with no validation that a real publish
  flow produced it) is dropped outright and replaced by
  fn_publish_workflow() — one guarded, tenant-safe, FOR-UPDATE-
  serialized, exact-draft-precondition transaction owning row lock,
  ARCHIVED rejection, version-number allocation, snapshot, insert, and
  definition update end to end. fn_archive_workflow() restores Archive's
  ability to write `status` (as its owner, not as app_api) despite the
  column-privilege revoke.

  Blocker F — fn_start_workflow_execution()'s ARCHIVED check upgraded
  from an unlocked SELECT to `FOR SHARE OF wd`, sharing the
  WorkflowDefinition row as a real serialization point with
  ArchiveWorkflow's own UPDATE (closing the previously-unlocked-read
  race between StartExecution and Archive — live-proven via a genuine
  two-thread race with measured lock-blocking).

  Blocker G — the four Part-A side-effect functions that never
  cross-checked their caller-supplied p_organization_id against
  organization.current_tenant_id() (fn_begin_node_submission,
  fn_record_node_succeeded, fn_record_node_ambiguous,
  fn_record_node_failed) now all do; fn_claim_node_execution additionally
  validates the caller-supplied workflow_execution_id/started_at/
  target_checkpoint_seq against the REAL WorkflowExecution row (under
  FOR SHARE, same-tenant, ACTIVE, checkpoint_seq+1 match) and the
  node_id/node_type against the execution's own pinned graph_json,
  closing the "claim identity inputs are not authoritative" gap.

Also live-discovered and fixed within this same pass: (a) PostgreSQL's
column-level REVOKE UPDATE has no effect on a role that also holds a
table-level UPDATE grant — the working fix revokes the table-level grant
first, then re-grants UPDATE on only the safe columns; (b)
fn_publish_workflow's RETURNS TABLE OUT parameter `version_number`
collided with the workflow_versions.version_number column (the identical
class of ambiguity 099_5C1.sql's own header comment documents for
fn_claim_dispatch_for_provider_submission), fixed with the same
`#variable_conflict use_column` pragma.

Phase 6I FINAL MICRO-REMEDIATION pass (same day, third pass over this
file), closing two further defects an independent review of the FINAL
pass' own new capabilities found:

  Blocker A (side-effect state machine) — fn_record_node_failed()
  (DROP + CREATE, BOOLEAN -> TABLE(recorded, reason) return-type change)
  no longer accepts SUBMITTING -> FAILED for an ordinary runtime worker.
  FAILED is a reclaimable state, so permitting SUBMITTING -> FAILED let a
  worker that mis-recorded an uncertain or actually-successful
  post-submission outcome as "failed" make an already-in-flight or
  already-succeeded external side effect automatically retryable —
  defeating the entire durable SUBMITTING boundary. Only CLAIMED ->
  FAILED (a provable pre-submission local abort) is legal now; a
  SUBMITTING -> FAILED attempt is rejected with a distinguishable reason
  (NOT_FAILABLE_AFTER_SUBMISSION) instead of an ambiguous boolean FALSE.
  An uncertain post-submission outcome must go to
  fn_record_node_ambiguous() instead — unaffected, still a hard stop.

  Blocker B (publish precondition) — fn_publish_workflow()'s
  p_expected_updated_at is no longer optional (`DEFAULT NULL` removed)
  and is explicitly rejected (RAISE EXCEPTION) if an authorized caller
  passes a literal NULL anyway — the removed default alone would not
  stop that, since PostgreSQL never NOT-NULL-constrains function
  parameters the way table columns are constrained. There is no longer
  any unconditional runtime publish route: every call must supply the
  row's actual current updated_at or the call is rejected outright.

Reviewed (not decided unilaterally) in that same pass: whether
app_platform_admin's EXECUTE grant on fn_start_workflow_execution (which
traces to the original, frozen 041_5G.sql — not introduced or altered by
any prior 6I remediation pass) should be revoked on least-privilege
grounds. Flagged as a genuine product-policy question rather than a
technical gap, since (unlike every other REVOKE in this file) no
invariant is bypassed by this grant — the function is already fully
tenant/archive/version-safe for any caller.

Phase 6I FINAL PRIVILEGE CLEANUP pass (same day, fourth pass over this
file): the product owner has now made that authoritative decision —
app_platform_admin must not be able to directly start a live
WorkflowExecution. This pass changes exactly one GRANT statement:
`GRANT EXECUTE ON FUNCTION workflow.fn_start_workflow_execution(...) TO
app_api, app_worker, app_platform_admin` becomes `TO app_api,
app_worker`. `REVOKE ALL ... FROM PUBLIC` on the same function is
confirmed unchanged. No function body, tenant-validation, ARCHIVED-
locking, duplicate-start-semantics, or advisory-lock behavior is
touched — this is a privilege-only change, live-verified via
`aclexplode(proacl)` to show exactly `{app_api, app_worker}` as the
resulting EXECUTE grantees, `PUBLIC` still denied, and a full
Archive/StartExecution regression (Race A/B, duplicate/version-conflict
semantics) with zero defects reintroduced.

Source: docs/phase-06-api-design/6I-Workflow-APIs.md, Phase 6I Blocker
Remediation pass (all four passes). No table/schema/bounded context is
added beyond what these ten findings require; migrations 001-099 are
not edited, renumbered, or reordered.

Revision ID: 100_5G1
Revises: '099_5C1'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '100_5G1'
down_revision: Union[str, None] = '099_5C1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '100_5G1.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 100_5G1 is part of the frozen, forward-only 5K SQL "
        "package. No rollback DDL is authored here. To revert, restore "
        "from a database backup taken before this revision was applied "
        "(workflow.node_execution_claims and its five functions would "
        "need to be dropped; workflow.workflow_executions.checkpoint_seq "
        "and its CHECK constraint would need to be dropped; "
        "fn_start_workflow_execution/fn_checkpoint_workflow_execution/"
        "fn_complete_workflow_execution/fn_fail_workflow_execution would "
        "need to be reverted to their 041_5G.sql-era shape; fn_publish_"
        "workflow/fn_archive_workflow would need to be dropped and the "
        "original 039_5G.sql fn_workflow_publish() restored; the INSERT/"
        "UPDATE grants on workflow_versions/workflow_definitions would "
        "need to be reverted to their pre-100_5G1 shape; the "
        "immutability/archived-terminal trigger functions would need "
        "reverting/dropping; fn_record_node_failed would need reverting "
        "to its earlier BOOLEAN-returning, SUBMITTING-permitting shape; "
        "and app_platform_admin's EXECUTE grant on "
        "fn_start_workflow_execution would need re-GRANTing — an "
        "operational runbook note, not an Alembic-managed downgrade, "
        "matching every other revision in this package)."
    )
