-- =================================================================
-- Migration 077 (Phase 5J.1 — controlled amendment): audit.domain_event_outbox
--   + fn_claim_outbox_events(), fn_mark_outbox_published(), fn_mark_outbox_failed()
-- down_revision: 076_5K1
-- Transaction: yes (no CREATE INDEX CONCURRENTLY; no extension install needed —
--   pgcrypto/gen_uuid_v7() already installed by migration 001)
-- Source: docs/phase-06-api-design/6C-Core-Platform-APIs.md DEP-6C-16
--   (Phase 6C — Core Platform APIs, Revision 4/5) and DEP-6C-07/10/11/14/15
--   (audit-vocabulary gaps — governance-only, see 5J-Analytics-Audit-Schema.md
--   §14.3 amendment note; this file's DDL covers DEP-6C-16 exclusively).
--
-- Scope discipline (per the governing task's explicit constraint):
--   This is a CONTROLLED AMENDMENT, not a Phase 5 rewrite. It adds exactly one
--   new table, three new SECURITY DEFINER functions, and one new trigger
--   function, all inside the already-frozen `audit` schema. It does not alter
--   any existing 5A-5J table, column, constraint, index, function, or RLS
--   policy. audit.audit_events, audit.audit_chain, and fn_insert_audit_event()
--   are untouched.
--
-- Why `audit` schema, not a new schema (5A §1: "prefer a new table in an
-- existing schema... the bar is high" for a new schema):
--   audit.domain_event_outbox is conceptually DISTINCT from audit.audit_events
--   (security/compliance audit trail) — it is transactional-outbox reliability
--   infrastructure for internal domain eventing (Phase 2 approves Redis Streams
--   as the event bus; Phase 3A §6.3 defines the publisher/outbox/consumer
--   module shape; 4A §5.1 invokes the outbox-write-in-same-transaction
--   invariant). It is placed in `audit` because `audit` is already this
--   platform's one precedented home for a single, cross-cutting,
--   mixed-tenancy (nullable organization_id), append-heavy, every-bounded-
--   context-writes-into-it table — the identical shape this table needs.
--   No new schema is created; 5A's "bar is high" instruction is satisfied by
--   reusing the closest existing structural analog rather than inventing a
--   fourteenth-plus-one schema for one table.
--
-- RLS posture — deliberately NO row-level security on this table (see body
--   comment above CREATE TABLE for full reasoning). This is NOT a BYPASSRLS
--   workaround: the table simply carries no RLS policy at all, the same
--   documented pattern already used for identity.sessions and
--   identity.password_reset_tokens (5B §16.3) — tables whose access pattern is
--   not "ordinary tenant-scoped read", so RLS would either block the
--   legitimate cross-tenant publisher-claim workload or require every claim
--   to run as a BYPASSRLS role, which the governing task explicitly forbids.
--   Tenant-forgery protection on INSERT is instead provided by a BEFORE
--   INSERT trigger reusing the existing organization.current_tenant_id()
--   helper (5B §16.2) — structural, not merely a documentation promise.
-- =================================================================

CREATE TABLE audit.domain_event_outbox (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),  -- doubles as the event's own event_id (6A §27.3 envelope)
  event_type        TEXT        NOT NULL,                        -- e.g. 'organization.created', 'compliance.policy_activated'
  event_version     INTEGER     NOT NULL DEFAULT 1,               -- independent of API URL versioning (6A §27.3)
  organization_id   UUID        NULL,                             -- nullable: genuinely platform-scoped events: exist for
                                                                    -- parity with audit.audit_events (5B §14.3's own nullable
                                                                    -- pattern); both of 6C's current flows always set this
  aggregate_type    TEXT        NULL,                             -- e.g. 'organization', 'compliance_policy'; free-text, no FK
                                                                    -- (polymorphic — cannot target one aggregate table; matches
                                                                    -- 5A §2.2's cross-schema "logical reference only" rule)
  aggregate_id      UUID        NULL,                             -- the aggregate root's own id (6A §27.3's "resource_id")
  payload           JSONB       NOT NULL,
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status            TEXT        NOT NULL DEFAULT 'PENDING',
  attempt_count     INTEGER     NOT NULL DEFAULT 0,
  max_attempts      INTEGER     NOT NULL DEFAULT 10,
  available_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),           -- claim eligibility; bumped forward on retry backoff
  claimed_by        TEXT        NULL,                             -- publisher worker identifier holding the current claim
  claimed_at        TIMESTAMPTZ NULL,
  published_at      TIMESTAMPTZ NULL,                              -- set only once Redis Streams publish is confirmed
  last_attempt_at   TIMESTAMPTZ NULL,
  last_error        TEXT        NULL,
  CONSTRAINT pk_outbox                    PRIMARY KEY (id),
  CONSTRAINT chk_outbox_status            CHECK (status IN ('PENDING','CLAIMED','PUBLISHED','FAILED')),
  CONSTRAINT chk_outbox_event_type_len    CHECK (length(event_type) BETWEEN 1 AND 200),
  CONSTRAINT chk_outbox_attempt_count     CHECK (attempt_count >= 0),
  CONSTRAINT chk_outbox_max_attempts      CHECK (max_attempts BETWEEN 1 AND 20),
  CONSTRAINT chk_outbox_published_state   CHECK ((status = 'PUBLISHED') = (published_at IS NOT NULL)),
  CONSTRAINT chk_outbox_payload_size      CHECK (length(payload::TEXT) <= 262144),
  CONSTRAINT chk_outbox_last_error_len    CHECK (last_error IS NULL OR length(last_error) <= 2000)
);
-- No PARTITION BY: unlike audit.audit_events (7-year retention, high volume),
-- this table's rows are deleted shortly after successful publish (retention
-- policy below) and current event volume is a handful of event types — 5A
-- §14's partitioning standard is reserved for genuinely high-volume,
-- long-retention append-only tables; a single unpartitioned table is the
-- simpler, correct choice here (5A's own anti-over-engineering bias, §1).

-- Primary claim-scan index: the publisher's SELECT ... FOR UPDATE SKIP LOCKED
-- (inside fn_claim_outbox_events below) filters exactly this predicate.
CREATE INDEX idx_outbox_claim ON audit.domain_event_outbox (available_at, id) WHERE status = 'PENDING';
-- Stuck-claim detection/reclaim (a worker that claimed but never completed).
CREATE INDEX idx_outbox_claimed_stuck ON audit.domain_event_outbox (claimed_at) WHERE status = 'CLAIMED';
-- Observability: "show me this org's recent events" / operational dashboards.
CREATE INDEX idx_outbox_org_type ON audit.domain_event_outbox (organization_id, event_type, occurred_at DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX idx_outbox_status   ON audit.domain_event_outbox (status, occurred_at DESC);

-- ---------------------------------------------------------------
-- Tenant-forgery guard on INSERT (structural, not RLS — see header comment).
-- Only fires when BOTH a tenant context is set on this session AND the
-- inserted row claims a non-NULL organization_id that disagrees with it.
-- A NULL organization_id (platform-scoped event) or an INSERT with no tenant
-- context set (a genuinely platform-scoped background process) is allowed
-- through unchanged — this mirrors 6A §23.2's "cross-checked, never silently
-- substituted" discipline applied to a write instead of a read.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.fn_outbox_tenant_check()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = audit, organization, pg_catalog AS $$
DECLARE v_tenant UUID;
BEGIN
  v_tenant := organization.current_tenant_id();
  IF v_tenant IS NOT NULL AND NEW.organization_id IS NOT NULL AND NEW.organization_id <> v_tenant THEN
    RAISE EXCEPTION 'audit: domain_event_outbox.organization_id (%) does not match session tenant context (%)', NEW.organization_id, v_tenant;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_outbox_tenant_check() FROM PUBLIC;
CREATE TRIGGER trg_outbox_tenant_check BEFORE INSERT ON audit.domain_event_outbox
  FOR EACH ROW EXECUTE FUNCTION audit.fn_outbox_tenant_check();

-- No RLS on this table by design — see header comment. Grants below are the
-- entire access-control surface: INSERT is the only privilege granted to the
-- tenant-request role (app_api) and to worker processes that may themselves
-- emit events (app_worker); all status-transition mutation is routed through
-- the three SECURITY DEFINER functions below, never a raw UPDATE grant.
REVOKE ALL ON audit.domain_event_outbox FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT INSERT ON audit.domain_event_outbox TO app_api, app_worker;
GRANT SELECT ON audit.domain_event_outbox TO app_readonly, app_worker, app_platform_admin;
GRANT UPDATE, DELETE ON audit.domain_event_outbox TO app_platform_admin;  -- manual/emergency intervention only

-- ---------------------------------------------------------------
-- fn_claim_outbox_events: the publisher's sole claiming path.
-- SELECT ... FOR UPDATE SKIP LOCKED inside a SECURITY DEFINER function — this
-- is internal queue-worker locking, NOT the API-layer locking 6A §17.3
-- forbids (that prohibition targets request-handler code; this function is
-- never reachable from any /api/v1/* or /api/internal/v1/* route, only from
-- the background outbox-publisher process). Mirrors webhooks.fn_claim_delivery
-- (5I, migration 063) exactly, generalized from one event type to any.
-- Opportunistically reclaims stuck CLAIMED rows in the same scan (no separate
-- cron/reaper needed) — a row is reclaimable once its claim exceeds
-- p_claim_timeout_seconds, treated as though the prior worker crashed.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.fn_claim_outbox_events(
  p_worker_id TEXT,
  p_limit INTEGER DEFAULT 50,
  p_claim_timeout_seconds INTEGER DEFAULT 300
)
RETURNS SETOF audit.domain_event_outbox LANGUAGE plpgsql SECURITY DEFINER SET search_path = audit, pg_catalog AS $$
BEGIN
  RETURN QUERY
  UPDATE audit.domain_event_outbox
  SET status = 'CLAIMED', claimed_by = p_worker_id, claimed_at = NOW(),
      attempt_count = attempt_count + 1, last_attempt_at = NOW()
  WHERE id IN (
    SELECT id FROM audit.domain_event_outbox
    WHERE (status = 'PENDING' AND available_at <= NOW())
       OR (status = 'CLAIMED' AND claimed_at < NOW() - make_interval(secs => p_claim_timeout_seconds))
    ORDER BY available_at ASC, id ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_claim_outbox_events(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_claim_outbox_events(TEXT, INTEGER, INTEGER) TO app_worker, app_platform_admin;

-- ---------------------------------------------------------------
-- fn_mark_outbox_published: the publisher's sole "done" path. CAS-guarded on
-- (id, claimed_by, status='CLAIMED') so only the worker currently holding the
-- claim can complete it — a reclaimed row's original (crashed) worker calling
-- this late is a no-op (0 rows affected), not a corruption of the new
-- claimant's work.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.fn_mark_outbox_published(p_id UUID, p_worker_id TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = audit, pg_catalog AS $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE audit.domain_event_outbox
  SET status = 'PUBLISHED', published_at = NOW(), claimed_by = NULL, claimed_at = NULL
  WHERE id = p_id AND claimed_by = p_worker_id AND status = 'CLAIMED';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_mark_outbox_published(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_mark_outbox_published(UUID, TEXT) TO app_worker, app_platform_admin;

-- ---------------------------------------------------------------
-- fn_mark_outbox_failed: records a failed publish attempt. Reverts CLAIMED
-- back to PENDING (with available_at pushed forward for backoff) unless
-- attempt_count has reached max_attempts, in which case the row moves to the
-- terminal FAILED status (mirrors webhooks.fn_delivery_failed's DEAD_LETTER-
-- on-exhaustion pattern, 5I migration 063) — a stuck/poison event is
-- observable via idx_outbox_status rather than retried forever.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit.fn_mark_outbox_failed(
  p_id UUID,
  p_worker_id TEXT,
  p_error TEXT DEFAULT NULL,
  p_next_attempt_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = audit, pg_catalog AS $$
DECLARE v_count INTEGER; v_max INTEGER; v_new_status TEXT;
BEGIN
  SELECT attempt_count, max_attempts INTO v_count, v_max
  FROM audit.domain_event_outbox
  WHERE id = p_id AND claimed_by = p_worker_id AND status = 'CLAIMED' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;  -- already reclaimed by another worker or already terminal; not this worker's to fail
  END IF;
  IF v_count >= v_max THEN
    v_new_status := 'FAILED';
  ELSE
    v_new_status := 'PENDING';
  END IF;
  UPDATE audit.domain_event_outbox
  SET status = v_new_status,
      last_error = LEFT(COALESCE(p_error, ''), 2000),
      available_at = CASE WHEN v_new_status = 'PENDING' THEN COALESCE(p_next_attempt_at, NOW() + INTERVAL '30 seconds') ELSE available_at END,
      claimed_by = NULL, claimed_at = NULL
  WHERE id = p_id;
  RETURN v_new_status;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_mark_outbox_failed(UUID, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_mark_outbox_failed(UUID, TEXT, TEXT, TIMESTAMPTZ) TO app_worker, app_platform_admin;

-- ---------------------------------------------------------------
-- Retention: PUBLISHED rows are deleted after 7 days (matches the platform's
-- existing documented-but-not-DB-scheduled cleanup pattern, e.g.
-- identity.password_reset_tokens, 5B §9.3 — "a background job may clean up
-- ... but must not rely on expiry for security"). FAILED rows are retained
-- longer (30 days) for operator investigation before cleanup. No pg_cron job
-- is defined here — none exists anywhere else in this frozen schema, and
-- inventing scheduled-job DB infrastructure is out of this migration's scope;
-- the cleanup query below is documented for whichever operational process
-- (existing or future) performs this class of housekeeping:
--   DELETE FROM audit.domain_event_outbox WHERE status = 'PUBLISHED' AND published_at < NOW() - INTERVAL '7 days';
--   DELETE FROM audit.domain_event_outbox WHERE status = 'FAILED' AND last_attempt_at < NOW() - INTERVAL '30 days';
-- ---------------------------------------------------------------

COMMENT ON TABLE audit.domain_event_outbox IS
  'Transactional-outbox persistence for internal domain events (Phase 2 Redis Streams event bus; Phase 3A §6.3 publisher/outbox/consumer pattern). Distinct from audit.audit_events (security/compliance audit trail). Added by controlled Phase 5.x amendment 077_5J1 to resolve 6C DEP-6C-16. No RLS by design — see migration header comment; tenant-forgery on INSERT is guarded by trg_outbox_tenant_check instead.';
