-- =================================================================
-- Migration 100 (Phase 5G.1 — controlled reconciliation amendment):
--   Workflow runtime safety hardening
-- down_revision: 099_5C1
-- Transaction: yes
-- Source: docs/phase-06-api-design/6I-Workflow-APIs.md Phase 6I Blocker
--   Remediation pass (2026-08-29) — Blocker A (side-effecting Workflow
--   node re-execution after crash/Redis-loss), Blocker B (stale/
--   out-of-order PostgreSQL checkpoint can move a WorkflowExecution
--   backward), Blocker C (app_platform_admin direct-DML bypass of
--   Workflow/Prompt version-identity and lifecycle invariants), and
--   Blocker D (Archive-vs-draft-update race can mutate an ARCHIVED
--   WorkflowDefinition).
--
-- SCOPE DISCIPLINE: this is a controlled, additive amendment to the
-- `workflow` schema, plus two narrowly-scoped identity-immutability
-- trigger hardenings (one in `workflow`, one in `prompt`, the latter
-- because 6I's own adversarial review found the identical gap on
-- `prompt.prompt_versions` while proving out the `workflow.
-- workflow_versions` defect) and privilege REVOKEs on three existing
-- `workflow` tables. It does not add, rename, or redesign any table,
-- schema, bounded context, or business entity beyond what those four
-- blockers require. No `knowledge.*`, `crm.*`, `campaign.*`, `voice.*`
-- (other than reading, never writing, `voice.tool_executions` conceptually
-- via a logical reference column — no FK, no schema touch), `billing.*`,
-- `integrations.*`, `webhooks.*`, `plugins.*`, or `analytics.*` object is
-- touched. Migrations 001-099 are not edited, renumbered, or reordered.
-- =================================================================


-- =================================================================
-- PART A — Blocker A: durable node-side-effect claim/state machine
--
-- Root cause (6I §30, proven against executed DDL, not asserted from
-- prose): no PostgreSQL table anywhere in the frozen schema provides a
-- durable, pre-side-effect commit boundary for a Workflow node
-- evaluation that is about to invoke an external or business side
-- effect (TOOL_CALL / TRANSFER / HUMAN_TRANSFER; WEBHOOK / API_CALL
-- remain execution-blocked pending 6J regardless of this table's
-- existence, per 6I ADR-6I-04, unchanged by this migration).
-- `workflow.workflow_executions.node_execution_history` is an embedded,
-- non-unique JSONB array, checkpointed once per Turn (DDR-4E-002), not
-- a per-attempt claim. `voice.tool_executions` (013_5C.sql, verified
-- directly) has no idempotency key and no unique constraint tying a
-- row to a stable (execution, node, occurrence) identity — it is a
-- plain INSERT-at-start/UPDATE-at-completion table, unmodified by 6I's
-- authority (owned by 5C/6D/6E) and left exactly as-is by this
-- migration (Option B of 6I §8: the new claim table references it by
-- a logical `downstream_ref`, never the reverse).
--
-- STABLE IDENTITY ACROSS WORKER RESTART (6I §4's requirement): the
-- identity key is (organization_id, workflow_execution_id,
-- target_checkpoint_seq, node_id) — NOT a freshly-computed "next
-- attempt number" (which could be recomputed differently across a
-- crash/recovery) and NOT node_id alone (loops legitimately revisit a
-- node). `target_checkpoint_seq` is the Turn-level monotonic sequence
-- this Part B introduces on `workflow_executions` (the checkpoint value
-- the CURRENTLY-EVALUATING Turn will commit as: last-committed
-- checkpoint_seq + 1, read fresh by the runtime before evaluating any
-- node in this Turn). This value is reproducible by construction: a
-- retried/recovered evaluation of the same not-yet-committed Turn
-- always recomputes the identical target_checkpoint_seq (last
-- committed + 1) until that Turn's checkpoint actually lands — at
-- which point the invariant this table exists to prevent (repeating an
-- already-committed Turn's side effect) can no longer arise for that
-- Turn. A single Turn's node-dispatch chain cannot legitimately visit
-- the SAME node_id twice without first producing an outward-facing
-- Directive (SPEAK/EXECUTE_TOOL/TRANSFER/END_CALL/WAIT) — 4E's own
-- cycle-safety invariant (a cycle is only legal through an LLM node,
-- which always yields a Directive) — so this composite key is safe to
-- treat as unique per (execution, node) per Turn.
--
-- STATE MACHINE (mirrors the proven `voice.call_dispatch_keys` design,
-- 099_5C1.sql, exactly — same submission-boundary reasoning, same
-- reclaim-predicate reasoning, adapted from "provider dial" to "any
-- Workflow node side effect"):
--   CLAIMED    — exactly one worker owns the right to prepare this
--                node's side effect, under a time-bounded lease. The
--                external/downstream call has NOT been attempted.
--                Safe to (re)claim if the lease has expired, or if a
--                prior attempt reached FAILED (a proven pre-acceptance
--                failure).
--   SUBMITTING — the durable "external submission may now begin"
--                boundary. Reached only via fn_begin_node_submission(),
--                which commits BEFORE the caller ever invokes the
--                actual tool/transfer/webhook side effect, in the
--                caller's own mandatory contract (6I §6/§30). Once
--                committed, NEVER auto-reclaimed regardless of lease
--                staleness — this is the entire fix, identical in kind
--                to Blocker A of 099_5C1.sql's own design.
--   SUCCEEDED  — the side effect definitely completed; downstream_ref
--                records the caller's own durable reference (e.g. a
--                `voice.tool_executions.id`, a transfer confirmation)
--                for audit/reconciliation. Reached only from SUBMITTING.
--   AMBIGUOUS  — the side effect's outcome could not be determined
--                (timeout, crash after SUBMITTING with no further
--                evidence). Reached only from SUBMITTING. A hard stop
--                for automatic retry — closed only by an application-
--                layer reconciliation process this migration does not
--                itself define (out of 6I's schema-only authority;
--                disclosed as a forward dependency, 6I §54).
--   FAILED     — a definite, proven-pre-acceptance failure (the
--                downstream target rejected the request before there
--                is any chance it was accepted), reached from CLAIMED
--                (local pre-submission abort) or SUBMITTING (a
--                synchronous, unambiguous rejection). Safe to retry —
--                fn_claim_node_execution() permits reclaiming a FAILED
--                row.
-- =================================================================

CREATE TABLE workflow.node_execution_claims (
  id                             UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                UUID          NOT NULL,
  workflow_execution_id          UUID          NOT NULL,   -- logical ref: workflow.workflow_executions.id (partitioned parent; no FK, matches this schema's existing convention for referencing that table, e.g. session_ref)
  workflow_execution_started_at  TIMESTAMPTZ   NOT NULL,   -- logical ref: workflow.workflow_executions.started_at (partition-pruning hint for lookups)
  target_checkpoint_seq          BIGINT        NOT NULL,
  node_id                        UUID          NOT NULL,   -- the WorkflowNode.NodeId from the pinned graph_json
  node_type                      TEXT          NOT NULL,
  claim_state                    TEXT          NOT NULL DEFAULT 'CLAIMED',
  claimed_by                     TEXT          NULL,
  claimed_at                     TIMESTAMPTZ   NULL,
  claim_expires_at                TIMESTAMPTZ   NULL,
  submission_started_at           TIMESTAMPTZ   NULL,
  downstream_ref                  TEXT          NULL,       -- e.g. voice.tool_executions.id::text, a transfer confirmation, a provider callback ref — opaque to this table
  last_error                      TEXT          NULL,
  created_at                      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_node_execution_claims       PRIMARY KEY (id),
  CONSTRAINT uq_nec_identity                UNIQUE (organization_id, workflow_execution_id, target_checkpoint_seq, node_id),
  CONSTRAINT chk_nec_state                  CHECK (claim_state IN ('CLAIMED','SUBMITTING','SUCCEEDED','FAILED','AMBIGUOUS')),
  CONSTRAINT chk_nec_node_type              CHECK (node_type IN ('TOOL_CALL','TRANSFER','HUMAN_TRANSFER','WEBHOOK','API_CALL')),
  CONSTRAINT chk_nec_target_seq_nn          CHECK (target_checkpoint_seq >= 1),
  CONSTRAINT chk_nec_claimed_has_lease      CHECK (claim_state <> 'CLAIMED' OR (claimed_by IS NOT NULL AND claim_expires_at IS NOT NULL)),
  CONSTRAINT chk_nec_submitting_has_marker  CHECK (claim_state <> 'SUBMITTING' OR submission_started_at IS NOT NULL),
  CONSTRAINT chk_nec_succeeded_has_ref      CHECK (claim_state <> 'SUCCEEDED' OR downstream_ref IS NOT NULL)
);

COMMENT ON TABLE workflow.node_execution_claims IS
  'Durable, pre-side-effect claim/state machine for TOOL_CALL/TRANSFER/'
  'HUMAN_TRANSFER/WEBHOOK/API_CALL Workflow node evaluations (WEBHOOK/'
  'API_CALL remain execution-blocked pending 6J regardless — 6I ADR-6I-04, '
  'unchanged). Identity is (organization_id, workflow_execution_id, '
  'target_checkpoint_seq, node_id) — stable across worker restart because '
  'target_checkpoint_seq is derived from workflow_executions.checkpoint_seq '
  '(Part B below), not from a freshly-computed attempt counter. Once '
  'SUBMITTING commits, no automatic reclaim occurs at any lease staleness — '
  'mirrors voice.call_dispatch_keys (099_5C1.sql) exactly.';
COMMENT ON COLUMN workflow.node_execution_claims.target_checkpoint_seq IS
  'The workflow_executions.checkpoint_seq value the CURRENTLY-EVALUATING '
  'Turn will commit as (last committed + 1). Reproducible after crash/'
  'recovery without an external counter: recomputed as last-committed-'
  'seq + 1 every time, until this Turn''s checkpoint actually lands.';
COMMENT ON COLUMN workflow.node_execution_claims.downstream_ref IS
  'Opaque caller-supplied reference to the actual side-effect record '
  '(e.g. voice.tool_executions.id::text). This table never joins to or '
  'constrains that record — Option B of 6I §8: voice.tool_executions is '
  'unmodified by this migration.';

CREATE INDEX idx_nec_org_execution
  ON workflow.node_execution_claims (organization_id, workflow_execution_id);
CREATE INDEX idx_nec_reclaim_sweep
  ON workflow.node_execution_claims (claim_state, claim_expires_at)
  WHERE claim_state = 'CLAIMED';
CREATE INDEX idx_nec_ambiguous
  ON workflow.node_execution_claims (organization_id, claim_state)
  WHERE claim_state = 'AMBIGUOUS';

CREATE TRIGGER trg_nec_updated_at
  BEFORE UPDATE ON workflow.node_execution_claims
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE workflow.node_execution_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow.node_execution_claims FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_nec_tenant ON workflow.node_execution_claims
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- No direct DML grant to any runtime role — every state transition goes
-- through a guarded SECURITY DEFINER function below, matching
-- 099_5C1.sql's own "no ordinary runtime role holds direct INSERT/
-- UPDATE/DELETE" posture for voice.call_dispatch_keys exactly.
GRANT SELECT ON workflow.node_execution_claims TO app_api, app_worker, app_readonly, app_platform_admin;


-- -----------------------------------------------------------------
-- fn_claim_node_execution: the only legal way a worker acquires the
-- right to prepare a side-effecting node's submission. Combines
-- "reserve" and "claim" into one call because the identity key here is
-- fully deterministic (unlike voice's dial-key flow, which separates
-- reservation from claiming because two different concerns — logical
-- call identity vs. provider-submission ownership — are involved).
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_claim_node_execution(
  p_organization_id               UUID,
  p_workflow_execution_id         UUID,
  p_workflow_execution_started_at TIMESTAMPTZ,
  p_target_checkpoint_seq         BIGINT,
  p_node_id                       UUID,
  p_node_type                     TEXT,
  p_worker_id                     TEXT,
  p_lease_seconds                 INTEGER DEFAULT 30
)
RETURNS TABLE(claimed BOOLEAN, claim_id UUID, claim_state TEXT, downstream_ref TEXT, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
-- `public` is REQUIRED here (live-discovered in this pass, not assumed):
-- this function's INSERT relies on node_execution_claims.id's own column
-- DEFAULT gen_uuid_v7(), which itself makes an unqualified, SET-search_
-- path-less internal call to pgcrypto's gen_random_bytes() — identical
-- root cause and fix pattern to 076_5K1.sql's own Group-1 findings
-- (integrations.fn_create_integration_connection et al.), confirmed
-- live: omitting `public` here reproduces
-- "ERROR: function gen_random_bytes(integer) does not exist" on the
-- very first live test of this function, exactly as 076_5K1.sql's
-- header comment describes for its own five functions. Safe order
-- matches 076_5K1.sql's own pattern: own schema first, organization
-- next (for current_tenant_id()), pg_catalog, public last.
SET search_path = workflow, organization, public, pg_catalog
AS $$
#variable_conflict use_column
DECLARE
  v_row workflow.node_execution_claims%ROWTYPE;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_claim_node_execution: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_lease_seconds NOT BETWEEN 5 AND 300 THEN
    RAISE EXCEPTION 'fn_claim_node_execution: p_lease_seconds % out of bounds [5,300]', p_lease_seconds;
  END IF;
  IF p_node_type NOT IN ('TOOL_CALL','TRANSFER','HUMAN_TRANSFER','WEBHOOK','API_CALL') THEN
    RAISE EXCEPTION 'fn_claim_node_execution: invalid p_node_type %', p_node_type;
  END IF;

  -- Fresh claim: identity has never been seen before.
  INSERT INTO workflow.node_execution_claims
    (organization_id, workflow_execution_id, workflow_execution_started_at,
     target_checkpoint_seq, node_id, node_type,
     claim_state, claimed_by, claimed_at, claim_expires_at)
  VALUES
    (p_organization_id, p_workflow_execution_id, p_workflow_execution_started_at,
     p_target_checkpoint_seq, p_node_id, p_node_type,
     'CLAIMED', p_worker_id, NOW(), NOW() + make_interval(secs => p_lease_seconds))
  ON CONFLICT (organization_id, workflow_execution_id, target_checkpoint_seq, node_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NOT NULL THEN
    RETURN QUERY SELECT TRUE, v_row.id, v_row.claim_state, v_row.downstream_ref, NULL::TEXT;
    RETURN;
  END IF;

  -- Identity already exists: reclaim only from a state proving the
  -- side effect never began (RESERVED has no meaning here since claim
  -- and reserve are combined — the only reclaimable prior states are
  -- an expired CLAIMED lease, or a proven-safe FAILED).
  UPDATE workflow.node_execution_claims
  SET claim_state      = 'CLAIMED',
      claimed_by       = p_worker_id,
      claimed_at        = NOW(),
      claim_expires_at  = NOW() + make_interval(secs => p_lease_seconds),
      submission_started_at = NULL,
      last_error        = NULL
  WHERE organization_id = p_organization_id
    AND workflow_execution_id = p_workflow_execution_id
    AND target_checkpoint_seq = p_target_checkpoint_seq
    AND node_id = p_node_id
    AND (
      claim_state = 'FAILED'
      OR (claim_state = 'CLAIMED' AND claim_expires_at < NOW())
      -- Deliberately NO branch for SUBMITTING/AMBIGUOUS at any staleness.
    )
  RETURNING * INTO v_row;

  IF v_row.id IS NOT NULL THEN
    RETURN QUERY SELECT TRUE, v_row.id, v_row.claim_state, v_row.downstream_ref, NULL::TEXT;
    RETURN;
  END IF;

  SELECT * INTO v_row FROM workflow.node_execution_claims
    WHERE organization_id = p_organization_id
      AND workflow_execution_id = p_workflow_execution_id
      AND target_checkpoint_seq = p_target_checkpoint_seq
      AND node_id = p_node_id;

  RETURN QUERY SELECT FALSE, v_row.id, v_row.claim_state, v_row.downstream_ref,
    ('NOT_CLAIMABLE_' || v_row.claim_state)::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_claim_node_execution(UUID,UUID,TIMESTAMPTZ,BIGINT,UUID,TEXT,TEXT,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_claim_node_execution(UUID,UUID,TIMESTAMPTZ,BIGINT,UUID,TEXT,TEXT,INTEGER) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_begin_node_submission: THE durable submission boundary. Mandatory
-- caller contract (6I §6): call this, confirm began=TRUE, and ONLY
-- THEN invoke the actual external/tool/transfer side effect — never
-- before. CAS-guarded on (claim_id, claimed_by, lease still valid).
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_begin_node_submission(
  p_claim_id        UUID,
  p_organization_id UUID,
  p_worker_id       TEXT
)
RETURNS TABLE(began BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE workflow.node_execution_claims
  SET claim_state = 'SUBMITTING',
      submission_started_at = NOW()
  WHERE id = p_claim_id
    AND organization_id = p_organization_id
    AND claim_state = 'CLAIMED'
    AND claimed_by = p_worker_id
    AND claim_expires_at > NOW();
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 THEN
    RETURN QUERY SELECT TRUE, NULL::TEXT;
  ELSE
    RETURN QUERY SELECT FALSE, 'NOT_CLAIM_HOLDER'::TEXT;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_begin_node_submission(UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_begin_node_submission(UUID,UUID,TEXT) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_record_node_succeeded: only legal from SUBMITTING.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_record_node_succeeded(
  p_claim_id        UUID,
  p_organization_id UUID,
  p_worker_id       TEXT,
  p_downstream_ref  TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_downstream_ref IS NULL OR length(p_downstream_ref) = 0 THEN
    RAISE EXCEPTION 'fn_record_node_succeeded: p_downstream_ref is required';
  END IF;

  UPDATE workflow.node_execution_claims
  SET claim_state    = 'SUCCEEDED',
      downstream_ref = p_downstream_ref,
      claimed_by     = NULL,
      claim_expires_at = NULL
  WHERE id = p_claim_id
    AND organization_id = p_organization_id
    AND claim_state = 'SUBMITTING'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_record_node_succeeded(UUID,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_record_node_succeeded(UUID,UUID,TEXT,TEXT) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_record_node_ambiguous: only legal from SUBMITTING. Hard stop for
-- automatic retry — no function in this migration ever transitions
-- AMBIGUOUS back to CLAIMED/SUBMITTING.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_record_node_ambiguous(
  p_claim_id        UUID,
  p_organization_id UUID,
  p_worker_id       TEXT,
  p_error           TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE workflow.node_execution_claims
  SET claim_state = 'AMBIGUOUS',
      last_error  = LEFT(COALESCE(p_error, ''), 2000),
      claimed_by  = NULL,
      claim_expires_at = NULL
  WHERE id = p_claim_id
    AND organization_id = p_organization_id
    AND claim_state = 'SUBMITTING'
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_record_node_ambiguous(UUID,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_record_node_ambiguous(UUID,UUID,TEXT,TEXT) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_record_node_failed: legal from CLAIMED (local pre-submission
-- abort — the side effect was never attempted) or SUBMITTING (only
-- when the outcome is DEFINITELY a rejection, never a timeout/
-- ambiguous response — those go to fn_record_node_ambiguous instead).
-- Safe to retry — fn_claim_node_execution permits reclaiming FAILED.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_record_node_failed(
  p_claim_id        UUID,
  p_organization_id UUID,
  p_worker_id       TEXT,
  p_error           TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE workflow.node_execution_claims
  SET claim_state = 'FAILED',
      last_error  = LEFT(COALESCE(p_error, ''), 2000),
      claimed_by  = NULL,
      claim_expires_at = NULL
  WHERE id = p_claim_id
    AND organization_id = p_organization_id
    AND claim_state IN ('CLAIMED','SUBMITTING')
    AND claimed_by = p_worker_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_record_node_failed(UUID,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_record_node_failed(UUID,UUID,TEXT,TEXT) TO app_api, app_worker;


-- =================================================================
-- PART B — Blocker B: monotonic checkpoint sequence + guarded CAS
--
-- Root cause (6I §37, proven): a plain `UPDATE ... WHERE status =
-- 'ACTIVE'` checkpoint write (5G QP-06) has no defense against a
-- delayed Turn-N checkpoint committing AFTER a Turn-N+1 checkpoint —
-- the `status='ACTIVE'` predicate alone does not encode ordering.
-- Queue-level FIFO ordering is an operational mitigation, not a
-- durable correctness invariant (redelivery/retry/broker-recovery can
-- still violate practical ordering) — PostgreSQL itself must reject a
-- stale checkpoint.
-- =================================================================

ALTER TABLE workflow.workflow_executions
  ADD COLUMN checkpoint_seq BIGINT NOT NULL DEFAULT 0;

ALTER TABLE workflow.workflow_executions
  ADD CONSTRAINT chk_we_checkpoint_seq_nn CHECK (checkpoint_seq >= 0);

COMMENT ON COLUMN workflow.workflow_executions.checkpoint_seq IS
  'Durable, monotonically-increasing per-execution Turn counter. 0 at '
  'StartExecution; incremented by exactly 1 on every successfully '
  'APPLIED checkpoint (workflow.fn_checkpoint_workflow_execution()). '
  'Enforced non-decreasing by both the guarded CAS function''s own WHERE '
  'clause AND, as a second, DB-level layer, by the hardened '
  'prevent_execution_mutation() trigger below — a stale/out-of-order '
  'checkpoint write can never move this value backward through ANY code '
  'path, present or future.';

-- Harden the existing execution-immutability trigger (039_5G.sql, as
-- corrected by 5K) to ALSO reject checkpoint_seq moving backward —
-- belt-and-suspenders alongside the CAS function's own WHERE clause
-- (checkpoint_seq < p_checkpoint_seq), so the invariant holds even if a
-- future code path bypasses the guarded function and attempts a direct
-- UPDATE (which, per Part D below, no runtime role can do any longer —
-- but the trigger closes this at the schema level regardless of grants,
-- exactly as trg_we_immutable already does for workflow_version_id and
-- terminal status).
CREATE OR REPLACE FUNCTION workflow.prevent_execution_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.session_ref <> NEW.session_ref THEN
    RAISE EXCEPTION 'workflow_executions.session_ref is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION 'workflow_executions.organization_id is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.workflow_version_id IS DISTINCT FROM NEW.workflow_version_id THEN
    RAISE EXCEPTION 'workflow_executions.workflow_version_id is immutable after creation. execution_id: %', OLD.id;
  END IF;
  IF OLD.status IN ('COMPLETED','FAILED') THEN
    RAISE EXCEPTION 'COMPLETED or FAILED workflow_executions are immutable. execution_id: %', OLD.id;
  END IF;
  IF NEW.checkpoint_seq < OLD.checkpoint_seq THEN
    RAISE EXCEPTION 'workflow_executions.checkpoint_seq cannot move backward (old=%, new=%). execution_id: %', OLD.checkpoint_seq, NEW.checkpoint_seq, OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
-- CREATE OR REPLACE does not need to re-attach the trigger — it already
-- points at this function (trg_we_immutable, 041_5G.sql).


-- -----------------------------------------------------------------
-- fn_checkpoint_workflow_execution: the sole legal path for a per-Turn
-- checkpoint write. Returns a deterministic outcome rather than a
-- silent no-op, so the caller can distinguish "someone else already
-- applied this or a later checkpoint" from a genuine error.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_checkpoint_workflow_execution(
  p_organization_id        UUID,
  p_execution_id            UUID,
  p_started_at              TIMESTAMPTZ,
  p_checkpoint_seq          BIGINT,
  p_current_node_id         UUID,
  p_slots                   JSONB,
  p_turn_count_at_node      JSONB,
  p_node_execution_history  JSONB
)
RETURNS TEXT   -- APPLIED | STALE_CHECKPOINT | EXECUTION_TERMINAL | NOT_FOUND
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE
  v_rows   INTEGER;
  v_status TEXT;
  v_seq    BIGINT;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_checkpoint_workflow_execution: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_checkpoint_seq < 1 THEN
    RAISE EXCEPTION 'fn_checkpoint_workflow_execution: p_checkpoint_seq must be >= 1';
  END IF;

  UPDATE workflow.workflow_executions
  SET current_node_id        = p_current_node_id,
      slots                  = p_slots,
      turn_count_at_node     = p_turn_count_at_node,
      node_execution_history = p_node_execution_history,
      checkpoint_seq         = p_checkpoint_seq
  WHERE id = p_execution_id
    AND started_at = p_started_at
    AND organization_id = p_organization_id
    AND status = 'ACTIVE'
    AND checkpoint_seq < p_checkpoint_seq;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows > 0 THEN
    RETURN 'APPLIED';
  END IF;

  SELECT status, checkpoint_seq INTO v_status, v_seq
  FROM workflow.workflow_executions
  WHERE id = p_execution_id AND started_at = p_started_at AND organization_id = p_organization_id;

  IF NOT FOUND THEN
    RETURN 'NOT_FOUND';
  ELSIF v_status <> 'ACTIVE' THEN
    RETURN 'EXECUTION_TERMINAL';
  ELSE
    -- v_seq >= p_checkpoint_seq: an equal value means this exact
    -- checkpoint was already applied (idempotent duplicate delivery,
    -- harmless no-op); a greater value means a newer checkpoint has
    -- already landed (the genuine stale-write race this function
    -- exists to reject). Both are reported identically — the caller
    -- does not need to distinguish them, since neither should ever
    -- overwrite current state.
    RETURN 'STALE_CHECKPOINT';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_checkpoint_workflow_execution(UUID,UUID,TIMESTAMPTZ,BIGINT,UUID,JSONB,JSONB,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_checkpoint_workflow_execution(UUID,UUID,TIMESTAMPTZ,BIGINT,UUID,JSONB,JSONB,JSONB) TO app_api, app_worker;


-- -----------------------------------------------------------------
-- fn_complete_workflow_execution / fn_fail_workflow_execution: the
-- sole legal paths to the two terminal states, now that app_api/
-- app_worker's direct UPDATE grant on workflow_executions is revoked
-- (Part D). Both are simple CAS-guarded transitions from ACTIVE.
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION workflow.fn_complete_workflow_execution(
  p_organization_id UUID,
  p_execution_id    UUID,
  p_started_at      TIMESTAMPTZ
)
RETURNS TEXT   -- APPLIED | EXECUTION_TERMINAL | NOT_FOUND
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE
  v_rows INTEGER;
  v_status TEXT;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_complete_workflow_execution: organization_id % does not match current tenant context', p_organization_id;
  END IF;

  UPDATE workflow.workflow_executions
  SET status = 'COMPLETED', completed_at = NOW()
  WHERE id = p_execution_id AND started_at = p_started_at
    AND organization_id = p_organization_id AND status = 'ACTIVE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 THEN RETURN 'APPLIED'; END IF;

  SELECT status INTO v_status FROM workflow.workflow_executions
    WHERE id = p_execution_id AND started_at = p_started_at AND organization_id = p_organization_id;
  IF NOT FOUND THEN RETURN 'NOT_FOUND'; ELSE RETURN 'EXECUTION_TERMINAL'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_complete_workflow_execution(UUID,UUID,TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_complete_workflow_execution(UUID,UUID,TIMESTAMPTZ) TO app_api, app_worker;

CREATE OR REPLACE FUNCTION workflow.fn_fail_workflow_execution(
  p_organization_id UUID,
  p_execution_id    UUID,
  p_started_at      TIMESTAMPTZ
)
RETURNS TEXT   -- APPLIED | EXECUTION_TERMINAL | NOT_FOUND
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE
  v_rows INTEGER;
  v_status TEXT;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_fail_workflow_execution: organization_id % does not match current tenant context', p_organization_id;
  END IF;

  UPDATE workflow.workflow_executions
  SET status = 'FAILED', completed_at = NOW()
  WHERE id = p_execution_id AND started_at = p_started_at
    AND organization_id = p_organization_id AND status = 'ACTIVE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 THEN RETURN 'APPLIED'; END IF;

  SELECT status INTO v_status FROM workflow.workflow_executions
    WHERE id = p_execution_id AND started_at = p_started_at AND organization_id = p_organization_id;
  IF NOT FOUND THEN RETURN 'NOT_FOUND'; ELSE RETURN 'EXECUTION_TERMINAL'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_fail_workflow_execution(UUID,UUID,TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_fail_workflow_execution(UUID,UUID,TIMESTAMPTZ) TO app_api, app_worker;


-- =================================================================
-- PART C — Blocker A/§26/§27: fn_start_workflow_execution() revised
--
-- (1) Deterministic outcome instead of a raised exception for the
--     benign "already ACTIVE" race (6I §26) — mirrors
--     fn_initiate_outbound_call_idempotent()'s own `outcome` TEXT
--     column convention (099_5C1.sql) rather than inventing a new one.
-- (2) Rejects starting a new execution when the WorkflowVersion's
--     parent WorkflowDefinition is ARCHIVED (6I §27) — closes the
--     resolve-then-archive-then-start race at the durable
--     serialization point itself, not merely at the earlier resolver
--     call.
--
-- Return-type change requires DROP + CREATE (cannot CREATE OR REPLACE
-- across a signature/return-type change) — identical precedent to
-- 099_5C1.sql's own `DROP FUNCTION IF EXISTS
-- voice.fn_reconcile_dispatch_outcome(...)` before its replacement.
-- =================================================================

DROP FUNCTION IF EXISTS workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ);

CREATE FUNCTION workflow.fn_start_workflow_execution(
  p_organization_id     UUID,
  p_workflow_version_id UUID,
  p_session_ref         UUID,
  p_started_at          TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE(execution_id UUID, execution_started_at TIMESTAMPTZ, outcome TEXT)
-- outcome: STARTED | REPLAYED_EXISTING | VERSION_CONFLICT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, public, pg_catalog
AS $$
DECLARE
  v_new_id      UUID   := gen_uuid_v7();
  v_existing    workflow.workflow_executions%ROWTYPE;
  v_lock_key    BIGINT;
  v_wfd_status  TEXT;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: p_organization_id is required';
  END IF;
  IF p_workflow_version_id IS NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: p_workflow_version_id is required';
  END IF;
  IF p_session_ref IS NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: p_session_ref is required';
  END IF;

  -- Existence + tenant match for the version, AND its parent
  -- WorkflowDefinition's current status — closes 6I §27's
  -- resolve-then-archive race at the durable serialization point.
  SELECT wd.status INTO v_wfd_status
  FROM workflow.workflow_versions wv
  JOIN workflow.workflow_definitions wd ON wd.id = wv.workflow_definition_id
    AND wd.organization_id = wv.organization_id
  WHERE wv.id = p_workflow_version_id AND wv.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: workflow_version % not found for tenant %', p_workflow_version_id, p_organization_id;
  END IF;
  IF v_wfd_status = 'ARCHIVED' THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: the WorkflowDefinition owning workflow_version % is ARCHIVED; no new execution may start against it', p_workflow_version_id;
  END IF;

  -- Serialize concurrent calls for the same (org, session) pair.
  v_lock_key := hashtext(p_organization_id::text || ':' || p_session_ref::text);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT * INTO v_existing
  FROM workflow.workflow_executions
  WHERE organization_id = p_organization_id AND session_ref = p_session_ref AND status = 'ACTIVE'
  LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.workflow_version_id = p_workflow_version_id THEN
      RETURN QUERY SELECT v_existing.id, v_existing.started_at, 'REPLAYED_EXISTING'::TEXT;
      RETURN;
    ELSE
      RETURN QUERY SELECT v_existing.id, v_existing.started_at, 'VERSION_CONFLICT'::TEXT;
      RETURN;
    END IF;
  END IF;

  INSERT INTO workflow.workflow_executions
    (id, started_at, organization_id, workflow_version_id, session_ref, status, checkpoint_seq)
  VALUES
    (v_new_id, p_started_at, p_organization_id, p_workflow_version_id, p_session_ref, 'ACTIVE', 0);

  RETURN QUERY SELECT v_new_id, p_started_at, 'STARTED'::TEXT;
END;
$$;
REVOKE ALL ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ) TO app_api, app_worker, app_platform_admin;

COMMENT ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ) IS
  'Revised by 100_5G1.sql (6I Blocker Remediation). Now (1) returns a '
  'deterministic outcome (STARTED | REPLAYED_EXISTING | VERSION_CONFLICT) '
  'instead of raising on a duplicate start for the same session, and (2) '
  'rejects starting a new execution when the WorkflowVersion''s parent '
  'WorkflowDefinition is ARCHIVED. Still the sole INSERT path on '
  'workflow_executions; still raises (does not return a row) for a '
  'genuine validation error (missing version, tenant mismatch, archived '
  'workflow) — only the benign duplicate-active-session race is now a '
  'return value rather than an exception.';


-- =================================================================
-- PART D — Blocker C: runtime admin privilege hardening
--
-- Prefer SELECT-only for app_platform_admin on every safety-critical
-- Workflow table, mirroring 099_5C1.sql's own final posture on
-- voice.call_dispatch_keys exactly ("SELECT only, identical in shape
-- to every other runtime role"). No new guarded admin-override
-- function is added — any future administrative correction belongs to
-- 6M through its own guarded/audited operation, not raw table DML
-- (6I §16, explicit instruction; disclosed as a forward dependency).
--
-- Also revokes UPDATE from app_api/app_worker on workflow_executions —
-- Part B's guarded functions (fn_checkpoint_workflow_execution,
-- fn_complete_workflow_execution, fn_fail_workflow_execution) are now
-- the ONLY legal mutation path, closing the "a different, non-CAS code
-- path could still issue a plain UPDATE" residual risk 6I §37
-- disclosed.
-- =================================================================

-- workflow.workflow_definitions: admin loses INSERT/UPDATE/DELETE (was
-- SELECT, INSERT, UPDATE, DELETE via 046_5G.sql's blanket schema
-- grant). app_api/app_worker's own UPDATE grant (needed for ordinary
-- draft/metadata/archive mutations, 040_5G.sql) is untouched — the
-- Part E archived-immutability trigger below is the correct backstop
-- for THAT grant, not a privilege revoke (an app-code bug in the WHERE
-- clause must not be the only thing standing between an ARCHIVED
-- definition and a stray UPDATE).
REVOKE INSERT, UPDATE, DELETE ON workflow.workflow_definitions FROM app_platform_admin;

-- workflow.workflow_versions: admin loses INSERT/UPDATE/DELETE (was
-- SELECT, INSERT, UPDATE, DELETE via 046_5G.sql). app_api/app_worker
-- already hold only SELECT, INSERT (040_5G.sql's own REVOKE UPDATE,
-- DELETE) — unchanged by this migration.
REVOKE INSERT, UPDATE, DELETE ON workflow.workflow_versions FROM app_platform_admin;

-- workflow.workflow_executions: admin loses UPDATE/DELETE (INSERT was
-- already revoked from admin by 076_5K1.sql; this migration completes
-- the same posture for the two remaining privileges). app_api/
-- app_worker lose UPDATE entirely (INSERT was never granted to them —
-- fn_start_workflow_execution is their only INSERT path, unchanged).
REVOKE UPDATE, DELETE ON workflow.workflow_executions FROM app_platform_admin;
REVOKE UPDATE ON workflow.workflow_executions FROM app_api, app_worker;

-- Defensive, per-partition REVOKE — live-discovered in this pass, not
-- assumed: a REVOKE issued against the partitioned PARENT relation does
-- NOT propagate to already-existing partitions' own, separately-
-- inherited ACL entries (each partition's grants were set independently
-- by 041_5G.sql's own creation loop and 046_5G.sql's blanket
-- schema-wide GRANT). PostgreSQL checks the PARENT's privileges for DML
-- routed through the parent relation name, but a direct
-- `UPDATE workflow.workflow_executions_2026_08 ...` against a leaf
-- partition by its own name checks THAT partition's own ACL — exactly
-- the reasoning 076_5K1.sql's own header comment already gives for why
-- its INSERT revoke had to walk pg_inherits explicitly. Applying the
-- identical defensive loop here for UPDATE/DELETE, confirmed necessary
-- by live inspection in this same pass (the parent-only REVOKE above
-- left every pre-existing partition's own UPDATE/DELETE grant to
-- app_platform_admin, and UPDATE grant to app_api/app_worker, fully
-- intact until this loop runs).
DO $$
DECLARE v_partition regclass;
BEGIN
  FOR v_partition IN
    SELECT c.oid::regclass
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'workflow.workflow_executions'::regclass
  LOOP
    EXECUTE format('REVOKE UPDATE, DELETE ON %s FROM app_platform_admin', v_partition);
    EXECUTE format('REVOKE UPDATE ON %s FROM app_api, app_worker', v_partition);
  END LOOP;
END $$;

-- prompt.prompt_versions: identical class of gap found by 6I's own
-- adversarial review while proving out the workflow_versions defect
-- (admin held UPDATE/DELETE via 046_5G.sql's blanket schema grant;
-- app_api/app_worker already hold only SELECT, INSERT per 042_5G.sql's
-- own REVOKE UPDATE, DELETE, unchanged by this migration). Closing
-- this exact sibling gap now, in the same migration that found it,
-- rather than deferring it — no other Prompt behavior is touched.
REVOKE UPDATE, DELETE ON prompt.prompt_versions FROM app_platform_admin;

-- workflow.node_execution_claims: never granted anything beyond SELECT
-- to any runtime role above — restated here for completeness, no-op if
-- already correct (defensive, matches this migration's own posture).
REVOKE INSERT, UPDATE, DELETE ON workflow.node_execution_claims FROM app_platform_admin;


-- =================================================================
-- PART E — Blocker D: WorkflowVersion/PromptVersion identity hardening
--   + WorkflowDefinition archived-immutability guard
-- =================================================================

-- E.1 — harden workflow_versions' immutability trigger to also guard
-- identity columns (workflow_definition_id, organization_id) that the
-- original 039_5G.sql trigger never checked — the exact class of gap
-- the ALREADY-CORRECTED workflow_executions trigger (039_5G.sql, per
-- the 5K corrections) was specifically hardened to close for its own
-- table, never symmetrically applied here until now.
CREATE OR REPLACE FUNCTION workflow.prevent_wf_version_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.graph_json IS DISTINCT FROM NEW.graph_json OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.published_by IS DISTINCT FROM NEW.published_by OR
     OLD.published_at IS DISTINCT FROM NEW.published_at OR
     OLD.workflow_definition_id IS DISTINCT FROM NEW.workflow_definition_id OR
     OLD.organization_id IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION
      'workflow_versions fields are immutable. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- E.2 — identical hardening for prompt_versions (the disclosed sibling
-- gap, 6I §38's own explicit review scope).
CREATE OR REPLACE FUNCTION prompt.prevent_pv_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.content IS DISTINCT FROM NEW.content OR
     OLD.variable_schema IS DISTINCT FROM NEW.variable_schema OR
     OLD.version_number IS DISTINCT FROM NEW.version_number OR
     OLD.published_by IS DISTINCT FROM NEW.published_by OR
     OLD.published_at IS DISTINCT FROM NEW.published_at OR
     OLD.prompt_template_id IS DISTINCT FROM NEW.prompt_template_id OR
     OLD.organization_id IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION
      'prompt_versions fields are immutable. version_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- E.3 — WorkflowDefinition archived-immutability guard (Blocker D,
-- 6I §20-22). ARCHIVED is a terminal aggregate invariant, not merely
-- an API-layer convention — a DB-level guard is required precisely
-- because app_api/app_worker retain an ordinary UPDATE grant on this
-- table (needed for legitimate draft/metadata/archive mutations, Part
-- D above). Once a row is ARCHIVED, no further mutation of any
-- mutable field succeeds through any runtime role, closing 6I's own
-- documented concurrency-matrix contradiction ("archive vs draft
-- update: whichever commits second wins; no invariant violated") —
-- that statement is corrected by this trigger's existence: if Archive
-- commits first, a later draft/metadata UPDATE now fails outright
-- rather than "winning."
CREATE OR REPLACE FUNCTION workflow.prevent_archived_definition_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'ARCHIVED' AND (
       NEW.name IS DISTINCT FROM OLD.name OR
       NEW.description IS DISTINCT FROM OLD.description OR
       NEW.draft_graph IS DISTINCT FROM OLD.draft_graph OR
       NEW.published_version_id IS DISTINCT FROM OLD.published_version_id OR
       NEW.status IS DISTINCT FROM OLD.status
     ) THEN
    RAISE EXCEPTION
      'workflow_definitions: ARCHIVED is terminal — no further mutation is permitted. workflow_id: %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_wfd_archived_immutable
  BEFORE UPDATE ON workflow.workflow_definitions
  FOR EACH ROW EXECUTE FUNCTION workflow.prevent_archived_definition_mutation();

COMMENT ON TRIGGER trg_wfd_archived_immutable ON workflow.workflow_definitions IS
  '6I Blocker D remediation (100_5G1.sql): once status=ARCHIVED, no '
  'mutable field (including a further status change) can be updated by '
  'any runtime role, regardless of the calling code''s own WHERE clause. '
  'Closes the archive-vs-draft-update / archive-vs-metadata-update race.';
