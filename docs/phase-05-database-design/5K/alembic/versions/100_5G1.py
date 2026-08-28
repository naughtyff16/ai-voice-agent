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

Source: docs/phase-06-api-design/6I-Workflow-APIs.md, Phase 6I Blocker
Remediation pass. No table/schema/bounded context is added beyond what
these four blockers require; migrations 001-099 are not edited,
renumbered, or reordered.

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
        "need to be reverted to their 041_5G.sql-era shape; the four "
        "REVOKEs would need to be re-GRANTed; and the three trigger "
        "functions plus trg_wfd_archived_immutable would need reverting/"
        "dropping — an operational runbook note, not an Alembic-managed "
        "downgrade, matching every other revision in this package)."
    )
