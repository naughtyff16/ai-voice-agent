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
--   WorkflowDefinition) — extended by the Phase 6I FINAL Blocker
--   Remediation pass (same day) with three further defects an
--   adversarial second-pass review found in this same file's own first
--   version: (E) ordinary runtime roles (`app_api`/`app_worker`) still
--   held raw DML sufficient to bypass guarded Workflow publishing
--   entirely (direct `INSERT` on `workflow_versions`, plus the
--   pre-existing `fn_workflow_publish()` from `039_5G.sql` remaining
--   callable with an arbitrary already-existing `version_id` — together
--   these let ordinary code "publish" a stale or fabricated version
--   without ever running graph validation or the version-number
--   allocation path); (F) `fn_start_workflow_execution()`'s
--   Archive-status check was a plain, unlocked `SELECT` — it did not
--   share a serialization point with `ArchiveWorkflow`'s own row
--   `UPDATE`, leaving a narrow window where an execution could start
--   using a `WorkflowVersion` whose parent had just been (or was about
--   to be) archived; (G) four of Part A's five side-effect functions
--   (`fn_begin_node_submission`, `fn_record_node_succeeded`,
--   `fn_record_node_ambiguous`, `fn_record_node_failed`) filtered their
--   `UPDATE` by a caller-supplied `p_organization_id` without ever
--   cross-checking it against `organization.current_tenant_id()` —
--   exactly the "do not trust a SECURITY DEFINER caller argument" class
--   of defect `fn_claim_node_execution`/`fn_checkpoint_workflow_
--   execution`/`fn_start_workflow_execution` were already correctly
--   guarded against in this same file's first version, never applied
--   symmetrically to their four siblings; and `fn_claim_node_execution`
--   itself additionally never validated that the `workflow_execution_id`/
--   `workflow_execution_started_at`/`target_checkpoint_seq` a caller
--   supplied actually corresponded to a real, `ACTIVE`,
--   same-tenant `WorkflowExecution` at its true current `checkpoint_seq`
--   — a caller could otherwise manufacture a claim identity for an
--   execution that does not exist, belongs to another tenant, is already
--   terminal, or names a `target_checkpoint_seq` unrelated to reality.
--
-- REVISION NOTE, matching `099_5C1.sql`'s own established precedent
-- exactly: `100_5G1.sql` has not been applied to any real/production
-- database — every validation pass so far ran against disposable,
-- throwaway local PostgreSQL 16 instances, torn down at the end of each
-- batch. There is therefore no "frozen, already-applied" version of this
-- file to preserve, and it is corrected in place here for the second
-- time rather than superseded by a new `101_5G2.sql` — identical
-- reasoning to why `099_5C1.sql` itself absorbed six remediation passes
-- in place before ever being frozen.
--
-- SCOPE DISCIPLINE: this remains a controlled, additive amendment to the
-- `workflow` schema, plus two narrowly-scoped identity-immutability
-- trigger hardenings (one in `workflow`, one in `prompt`) and privilege
-- REVOKEs on three existing `workflow` tables plus `workflow_versions`'
-- own INSERT grant and `workflow_definitions`' `status`/
-- `published_version_id` columns specifically (Part F, this pass). It
-- does not add, rename, or redesign any table, schema, bounded context,
-- or business entity beyond what these seven findings require. No
-- `knowledge.*`, `crm.*`, `campaign.*`, `voice.*` (other than reading,
-- never writing, `voice.tool_executions` conceptually via a logical
-- reference column — no FK, no schema touch), `billing.*`,
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
  v_row       workflow.node_execution_claims%ROWTYPE;
  v_exec      workflow.workflow_executions%ROWTYPE;
  v_graph     JSONB;
  v_node_ok   BOOLEAN;
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

  -- Live-discovered gap, this pass (Blocker C2 of the FINAL remediation
  -- pass): the caller-supplied workflow_execution_id/started_at/
  -- target_checkpoint_seq were never validated against the real
  -- WorkflowExecution row — a caller could otherwise manufacture a claim
  -- identity for an execution that does not exist, belongs to another
  -- tenant, is already terminal, or names a target_checkpoint_seq
  -- unrelated to the execution's true current checkpoint_seq. `FOR
  -- SHARE` (not FOR UPDATE) is deliberate: it conflicts with a
  -- concurrent checkpoint's own UPDATE (which takes the ordinary
  -- FOR-NO-KEY-UPDATE row lock every plain UPDATE acquires), forcing the
  -- two to serialize and closing the TOCTOU window between "read
  -- checkpoint_seq" and "insert the claim row" — but it does NOT
  -- conflict with another concurrent FOR SHARE reader, so two workers
  -- validating against the same execution for two DIFFERENT nodes in
  -- the same Turn never block each other. The lock is held only for
  -- this short claim-creation transaction, never across the external
  -- side effect itself (6I §19's own explicit requirement).
  SELECT * INTO v_exec
  FROM workflow.workflow_executions
  WHERE id = p_workflow_execution_id
    AND started_at = p_workflow_execution_started_at
    AND organization_id = p_organization_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_claim_node_execution: workflow_execution % (started_at %) not found for tenant % — or the identity does not match a real execution', p_workflow_execution_id, p_workflow_execution_started_at, p_organization_id;
  END IF;
  IF v_exec.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'fn_claim_node_execution: workflow_execution % is not ACTIVE (status=%) — no new side-effect claim may be created against a terminal execution', p_workflow_execution_id, v_exec.status;
  END IF;
  IF p_target_checkpoint_seq <> v_exec.checkpoint_seq + 1 THEN
    RAISE EXCEPTION 'fn_claim_node_execution: target_checkpoint_seq % does not match the execution''s real current checkpoint_seq+1 (%)', p_target_checkpoint_seq, v_exec.checkpoint_seq + 1;
  END IF;

  -- Bound node-reference validation against the execution's own pinned
  -- WorkflowVersion.graph_json (6I §17's "at minimum" requirement) — a
  -- lightweight existence+type check, not a re-implementation of the
  -- full discriminated-union config validation 6I §11 already enforces
  -- at publish time (that would be redundant/heavy to duplicate here on
  -- the claim hot path; this check only bounds a forged/incorrect
  -- node_id or node_type reference).
  SELECT graph_json INTO v_graph
  FROM workflow.workflow_versions
  WHERE id = v_exec.workflow_version_id AND organization_id = p_organization_id;

  SELECT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(v_graph->'nodes', '[]'::jsonb)) n
    WHERE n->>'node_id' = p_node_id::text AND n->>'node_type' = p_node_type
  ) INTO v_node_ok;

  IF NOT v_node_ok THEN
    RAISE EXCEPTION 'fn_claim_node_execution: node % (type %) is not present in the execution''s pinned graph_json', p_node_id, p_node_type;
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
-- `organization` added to search_path for the explicit tenant check
-- below — live-discovered missing in this pass' adversarial second
-- review: the original version of this function filtered its UPDATE by
-- a caller-supplied p_organization_id with no cross-check against the
-- session's actual tenant context, meaning an Org-A-authenticated caller
-- who supplied (or correctly guessed — organization_id is not secret,
-- it routinely appears in URLs/API responses) Org B's real
-- organization_id on a claim_id it also somehow obtained could mutate
-- Org B's claim. This is exactly the "do not rely on claim_id/worker_id
-- secrecy as authorization" hazard — fixed identically to
-- fn_claim_node_execution's own pre-existing guard.
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_begin_node_submission: organization_id % does not match current tenant context', p_organization_id;
  END IF;

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
-- `organization` added — same missing-tenant-check defect as
-- fn_begin_node_submission above, found and fixed identically.
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_record_node_succeeded: organization_id % does not match current tenant context', p_organization_id;
  END IF;
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
-- `organization` added — same missing-tenant-check defect, fixed
-- identically.
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_record_node_ambiguous: organization_id % does not match current tenant context', p_organization_id;
  END IF;

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
-- `organization` added — same missing-tenant-check defect, fixed
-- identically.
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE v_rows INTEGER;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_record_node_failed: organization_id % does not match current tenant context', p_organization_id;
  END IF;

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
  --
  -- `FOR SHARE OF wd` is the live-discovered fix this pass adds: the
  -- first version of this function read wd.status via a plain,
  -- UNLOCKED SELECT — under READ COMMITTED that reads whatever was last
  -- committed at the instant of the read, with no serialization against
  -- a concurrent ArchiveWorkflow UPDATE racing to commit ARCHIVED at
  -- effectively the same moment. `FOR SHARE OF wd` forces this
  -- transaction to hold a shared lock on the SPECIFIC WorkflowDefinition
  -- row for the remainder of this transaction (i.e. through the INSERT
  -- below) — Archive's own plain UPDATE needs the ordinary
  -- FOR-NO-KEY-UPDATE row lock, which conflicts with FOR SHARE, so the
  -- two are forced to serialize on this exact row: whichever commits
  -- first is authoritative, and the loser observes the winner's
  -- post-commit state. `OF wd` (not `OF wv`) deliberately locks only the
  -- definition, not the version row, since nothing else needs to
  -- serialize against a version read. Multiple concurrent
  -- StartExecution calls against the SAME popular workflow do not block
  -- each other (FOR SHARE is compatible with FOR SHARE) — only a
  -- concurrent Archive forces a wait.
  SELECT wd.status INTO v_wfd_status
  FROM workflow.workflow_versions wv
  JOIN workflow.workflow_definitions wd ON wd.id = wv.workflow_definition_id
    AND wd.organization_id = wv.organization_id
  WHERE wv.id = p_workflow_version_id AND wv.organization_id = p_organization_id
  FOR SHARE OF wd;

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
  'Revised by 100_5G1.sql (6I Blocker Remediation, two passes). Now (1) '
  'returns a deterministic outcome (STARTED | REPLAYED_EXISTING | '
  'VERSION_CONFLICT) instead of raising on a duplicate start for the '
  'same session, (2) rejects starting a new execution when the '
  'WorkflowVersion''s parent WorkflowDefinition is ARCHIVED, and (3) '
  '(FINAL pass) takes that ARCHIVED check under FOR SHARE OF wd, sharing '
  'the WorkflowDefinition row as a real serialization point with '
  'ArchiveWorkflow''s own UPDATE — closing the previously-unlocked-read '
  'race between the two. Still the sole INSERT path on '
  'workflow_executions; still raises (does not return a row) for a '
  'genuine validation error (missing version, tenant mismatch, archived '
  'workflow) — only the benign duplicate-active-session race is a return '
  'value rather than an exception.';


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


-- =================================================================
-- PART F (FINAL Blocker Remediation pass, same day) — Blocker E:
--   guarded Workflow publish/archive capability, raw-DML bypass closed
--
-- Root cause, found by this pass' own adversarial second review of
-- Part A-E's first version: 040_5G.sql grants `app_api`/`app_worker`
-- plain `INSERT` on `workflow.workflow_versions`, and this file's own
-- Part D never touched that grant (it only revoked app_platform_admin's
-- INSERT/UPDATE/DELETE on the table). Combined with `039_5G.sql`'s
-- pre-existing `fn_workflow_publish(p_workflow_id, p_new_version_id,
-- p_organization_id)` — which still ends this file's first version with
-- an unrevoked EXECUTE grant to app_api/app_worker/app_platform_admin —
-- ordinary application code could: (1) raw-INSERT an arbitrary
-- `workflow_versions` row (any `graph_json`, any `version_number`,
-- skipping every publish-time validation 6I §14 requires), then (2)
-- call `fn_workflow_publish()` naming that row, which only checks
-- ownership/tenant/ARCHIVED — never that the version was actually
-- produced by a validated publish flow. Worse: `fn_workflow_publish()`
-- accepts ANY existing version belonging to the workflow, including an
-- OLD, already-superseded one — a caller could "republish" a stale
-- version without creating a new one or bumping `version_number`,
-- silently rolling back `published_version_id` outside any approved
-- rollback command. INV-6I-PUB-01/02 (6I §41, FINAL pass) require that
-- NO normal runtime role can create a WorkflowVersion or set
-- `published_version_id`/`status='PUBLISHED'` except through one
-- guarded, tenant-safe, exact-draft transaction.
--
-- THE FIX: `fn_workflow_publish()` is dropped outright (its capability
-- is fully absorbed by the new all-in-one `fn_publish_workflow()` below
-- — leaving the old function in place, even unused by any approved
-- flow, would leave its dangerous "point published_version_id at any
-- existing version" capability reachable by anyone who could name a
-- version_id, which is not secret). `workflow_versions.INSERT` is
-- revoked from app_api/app_worker. `workflow_definitions.status` and
-- `.published_version_id` receive PostgreSQL COLUMN-LEVEL UPDATE
-- revokes from app_api/app_worker — deliberately column-level, not a
-- blanket table UPDATE revoke, per 6I §29's explicit anti-over-
-- engineering instruction ("keep simple safe fields simple... do not
-- rewrite the whole module"): ordinary `name`/`description`/
-- `draft_graph` edits remain plain, ungoverned UPDATEs (no new guarded
-- function needed for them), while the two lifecycle-guarded columns
-- become unwritable by ordinary runtime roles at the SQL-privilege
-- layer itself — the strongest possible enforcement, since PostgreSQL
-- refuses a column-level-unauthorized UPDATE at parse time, before any
-- trigger or application check even runs. `ArchiveWorkflow` — which
-- only ever needs to write `status` (to 'ARCHIVED', never 'PUBLISHED')
-- — is centralized into a new `fn_archive_workflow()` (6I §28) so it
-- keeps working despite the column-level revoke, using the same
-- owner-privilege mechanism every other guarded function in this schema
-- already relies on (a SECURITY DEFINER function's body runs with its
-- OWNER's privileges, not the caller's — the owning role already holds
-- full privileges on every object it creates, independent of any GRANT
-- statement, identical in kind to `099_5C1.sql`'s own documented
-- reasoning for `app_migration`).
-- =================================================================

-- F.1 — remove the raw-DML publish bypass.
REVOKE INSERT ON workflow.workflow_versions FROM app_api, app_worker;

-- Live-discovered in THIS pass, not assumed: PostgreSQL's column-level
-- `REVOKE UPDATE (col) ... FROM role` has NO effect when that role also
-- holds a table-level `UPDATE` grant on the same table — per PostgreSQL's
-- own privilege model, a table-level grant implicitly covers every
-- column, and a column-level REVOKE narrows only a column-level GRANT,
-- never a table-level one. The first attempt at this fix
-- (`REVOKE UPDATE (status, published_version_id) ... FROM app_api,
-- app_worker`, leaving 040_5G.sql's table-level `UPDATE` grant
-- untouched) was live-tested and proven NOT to block either column —
-- both `UPDATE ... SET published_version_id = ...` and
-- `UPDATE ... SET status = 'PUBLISHED'` still succeeded as app_api. The
-- correct, working pattern is to revoke the table-level grant entirely
-- first, then re-grant UPDATE on only the columns ordinary runtime code
-- legitimately needs to write directly (`name`, `description`,
-- `draft_graph` — `updated_at` does not need an explicit grant: the
-- existing `set_updated_at()` BEFORE UPDATE trigger sets it on NEW
-- regardless of which columns the caller's own SET-list named, and
-- PostgreSQL's column-privilege check looks only at the columns
-- actually referenced in the statement's own SET clause, not at what a
-- trigger subsequently changes). `status`/`published_version_id` are
-- deliberately excluded from the re-grant — `fn_publish_workflow()` and
-- `fn_archive_workflow()` below write them as their OWNER, not as
-- app_api/app_worker, so no grant on those two columns is needed or
-- given to either runtime role.
REVOKE UPDATE ON workflow.workflow_definitions FROM app_api, app_worker;
GRANT UPDATE (name, description, draft_graph) ON workflow.workflow_definitions TO app_api, app_worker;

-- The old three-argument publish function is fully superseded by
-- fn_publish_workflow() below — dropped, not merely left unused, to
-- close the "existing version can be re-pointed-to without validation"
-- capability described above. No other object depends on this exact
-- name/signature (grep-verified against every migration file in this
-- package before dropping).
DROP FUNCTION IF EXISTS workflow.fn_workflow_publish(UUID, UUID, UUID);

-- -----------------------------------------------------------------
-- fn_publish_workflow: the ONE guarded capability that creates a
-- WorkflowVersion and moves a WorkflowDefinition to PUBLISHED. Owns the
-- entire durable publish transaction end to end — no application code
-- performs a raw INSERT into workflow_versions or a raw UPDATE of
-- published_version_id/status anywhere in the approved flow.
--
-- `p_expected_updated_at`: the exact-draft precondition (6I §8/ADR-6I-08
-- / INV-6I-PUB-03). This is the same information a weak `hash(id,
-- updated_at)` API-layer ETag already carries (id is fixed by
-- p_workflow_id; updated_at is therefore the only free variable an ETag
-- match actually verifies) — the function is not asked to recompute an
-- API-layer hash formula, only to compare the one underlying value that
-- formula depends on, resolved fresh under the row lock below (never
-- trusting a client-generated hash as authoritative by itself, per 6I
-- §8's explicit instruction). NULL bypasses the precondition entirely
-- (a caller that genuinely does not want optimistic-concurrency
-- protection may omit it) — the API layer, per 6I §52, always supplies
-- it in the approved flow.
--
-- `FOR UPDATE` (not FOR SHARE) on workflow_definitions: this is the
-- publish-side counterpart to fn_start_workflow_execution's FOR SHARE —
-- publish genuinely intends to WRITE the row (published_version_id,
-- status, updated_at), so it needs the exclusive lock, which serializes
-- it against every other publisher, every StartExecution's FOR SHARE
-- (a competing FOR SHARE blocks a FOR UPDATE and vice versa), and
-- ArchiveWorkflow's own FOR-NO-KEY-UPDATE-acquiring plain UPDATE.
-- -----------------------------------------------------------------
CREATE FUNCTION workflow.fn_publish_workflow(
  p_organization_id      UUID,
  p_workflow_id          UUID,
  p_published_by         UUID,
  p_expected_updated_at  TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(version_id UUID, version_number INTEGER, published_at TIMESTAMPTZ, outcome TEXT)
-- outcome: PUBLISHED | PRECONDITION_FAILED | ARCHIVED | NOT_FOUND
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, public, pg_catalog
AS $$
#variable_conflict use_column
-- Live-discovered necessary in this pass, reproducing the identical
-- diagnosis 099_5C1.sql's own header comment already gives for
-- fn_claim_dispatch_for_provider_submission: this function's
-- RETURNS TABLE OUT parameter `version_number` shares its name with
-- workflow_versions.version_number, producing the exact
-- "column reference is ambiguous" error inside the
-- `SELECT COALESCE(MAX(version_number), 0) + 1 FROM workflow_versions`
-- allocation query below — confirmed live, not assumed, on the very
-- first functional test of this function. This pragma makes every bare
-- identifier prefer the table column over the like-named OUT parameter,
-- the correct resolution here (the OUT parameter is only ever set via
-- the explicit RETURN QUERY SELECT ... v_next_version at the end, never
-- read back from itself).
DECLARE
  v_wfd            workflow.workflow_definitions%ROWTYPE;
  v_next_version   INTEGER;
  v_new_version_id UUID := gen_uuid_v7();
  v_now            TIMESTAMPTZ := NOW();
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_publish_workflow: organization_id % does not match current tenant context', p_organization_id;
  END IF;
  IF p_published_by IS NULL THEN
    RAISE EXCEPTION 'fn_publish_workflow: p_published_by is required';
  END IF;

  -- THE serialization point — every publisher, every concurrent
  -- StartExecution (FOR SHARE), and Archive (plain UPDATE) all
  -- contend on this single row lock.
  SELECT * INTO v_wfd
  FROM workflow.workflow_definitions
  WHERE id = p_workflow_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::UUID, NULL::INTEGER, NULL::TIMESTAMPTZ, 'NOT_FOUND'::TEXT;
    RETURN;
  END IF;

  IF v_wfd.status = 'ARCHIVED' THEN
    RETURN QUERY SELECT NULL::UUID, NULL::INTEGER, NULL::TIMESTAMPTZ, 'ARCHIVED'::TEXT;
    RETURN;
  END IF;

  IF p_expected_updated_at IS NOT NULL AND v_wfd.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RETURN QUERY SELECT NULL::UUID, NULL::INTEGER, NULL::TIMESTAMPTZ, 'PRECONDITION_FAILED'::TEXT;
    RETURN;
  END IF;

  -- Safe under the FOR UPDATE lock already held on wfd above — no
  -- concurrent publisher for this SAME workflow can be mid-flight past
  -- this point, so MAX(version_number)+1 cannot race with another
  -- publisher's own allocation. uq_wv_version_number remains the
  -- unique-constraint backstop if this invariant is ever violated by a
  -- future code path that forgets the lock.
  SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
  FROM workflow.workflow_versions
  WHERE workflow_definition_id = p_workflow_id AND organization_id = p_organization_id;

  INSERT INTO workflow.workflow_versions
    (id, organization_id, workflow_definition_id, version_number, graph_json, published_by, published_at)
  VALUES
    (v_new_version_id, p_organization_id, p_workflow_id, v_next_version, v_wfd.draft_graph, p_published_by, v_now);

  UPDATE workflow.workflow_definitions
  SET published_version_id = v_new_version_id,
      status               = 'PUBLISHED',
      updated_at           = v_now
  WHERE id = p_workflow_id AND organization_id = p_organization_id;

  RETURN QUERY SELECT v_new_version_id, v_next_version, v_now, 'PUBLISHED'::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_publish_workflow(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC;
-- app_api only: PublishWorkflow is a synchronous, user-initiated REST
-- action (6I §6.1, POST /workflows/{id}/publish) — no approved Workflow
-- capability in 4E/6I has a Celery worker publish on a tenant's behalf,
-- so app_worker's EXECUTE grant (which the pre-existing
-- fn_workflow_publish() carried forward unexamined from an earlier
-- pattern) is deliberately NOT restored here. If a genuine future
-- worker-initiated publish need arises, it is a new, separately
-- justified GRANT, not a default inherited from this function's
-- predecessor.
GRANT EXECUTE ON FUNCTION workflow.fn_publish_workflow(UUID, UUID, UUID, TIMESTAMPTZ) TO app_api;

COMMENT ON FUNCTION workflow.fn_publish_workflow(UUID, UUID, UUID, TIMESTAMPTZ) IS
  '100_5G1.sql FINAL pass — the sole guarded path to create a '
  'WorkflowVersion and move a WorkflowDefinition to PUBLISHED. Replaces '
  'the dropped 039_5G.sql fn_workflow_publish() and the raw-INSERT-then-'
  'call pattern it depended on. Owns the whole durable publish '
  'transaction: row lock, ARCHIVED rejection, exact-draft precondition, '
  'version-number allocation, snapshot, insert, and definition update — '
  'all inside one transaction, closing every publish-concurrency race '
  '6I §36 analyzes.';


-- -----------------------------------------------------------------
-- fn_archive_workflow: the sole guarded path to ARCHIVED, restoring
-- Archive's ability to write `status` despite F.1's column-level
-- revoke (this function runs with its OWNER's privileges, not the
-- caller's — no GRANT on workflow_definitions.status is needed for it
-- to succeed). Legal source states unchanged from 6I's original design
-- (DRAFT or PUBLISHED); the trg_wfd_archived_immutable trigger (Part E)
-- remains the independent, unconditional backstop regardless of which
-- role or function attempts a later mutation.
-- -----------------------------------------------------------------
CREATE FUNCTION workflow.fn_archive_workflow(
  p_organization_id UUID,
  p_workflow_id     UUID
)
RETURNS TEXT   -- ARCHIVED | ALREADY_ARCHIVED | NOT_FOUND
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, pg_catalog
AS $$
DECLARE
  v_rows   INTEGER;
  v_status TEXT;
BEGIN
  IF p_organization_id IS DISTINCT FROM organization.current_tenant_id() THEN
    RAISE EXCEPTION 'fn_archive_workflow: organization_id % does not match current tenant context', p_organization_id;
  END IF;

  UPDATE workflow.workflow_definitions
  SET status = 'ARCHIVED', updated_at = NOW()
  WHERE id = p_workflow_id AND organization_id = p_organization_id
    AND status IN ('DRAFT', 'PUBLISHED');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 THEN RETURN 'ARCHIVED'; END IF;

  SELECT status INTO v_status FROM workflow.workflow_definitions
    WHERE id = p_workflow_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN RETURN 'NOT_FOUND'; ELSE RETURN 'ALREADY_ARCHIVED'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_archive_workflow(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_archive_workflow(UUID, UUID) TO app_api;

COMMENT ON FUNCTION workflow.fn_archive_workflow(UUID, UUID) IS
  '100_5G1.sql FINAL pass — restores ArchiveWorkflow''s ability to write '
  '`status` despite F.1''s column-level UPDATE revoke on app_api/'
  'app_worker (this function runs as its owner, not the caller). '
  'Idempotent: archiving an already-ARCHIVED workflow returns '
  'ALREADY_ARCHIVED rather than erroring. trg_wfd_archived_immutable '
  '(Part E) remains the unconditional backstop against any future '
  'mutation of an ARCHIVED row through any path.';
