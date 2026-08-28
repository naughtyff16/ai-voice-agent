-- =================================================================
-- Migration 094 (Phase 5D.3): crm.event_consumer_dedup +
--   crm.fn_claim_event() — durable CRM event-consumer idempotency
-- down_revision: 093_5D2
-- Transaction: yes
-- Source: Phase 6G CRM Reconciliation (2026-08-28), Blocker C
--
-- WHY THIS EXISTS
-- ----------------
-- 6G's first pass protected against duplicate `call.ended` /
-- `conversation.qualification_set` / `conversation.summarization_completed`
-- delivery with a "SELECT for existing call_ref, then INSERT if absent"
-- pattern in application code. Under at-least-once delivery, two
-- concurrent deliveries of the same event can both observe "no existing
-- row" and both proceed to INSERT — a genuine TOCTOU race, not merely a
-- theoretical one (the same class of race 6G's own §16.1/§27 already
-- flagged and fixed for Contact phone uniqueness via a real partial
-- unique index; this migration applies the identical discipline to CRM
-- event-consumer idempotency instead of leaving it as an accepted risk).
--
-- This migration adds a small, CRM-owned, non-partitioned table with a
-- true PRIMARY KEY on (consumer_name, source_event_id), and a single
-- SECURITY DEFINER claim function every CRM event subscriber calls
-- exactly once, in the same transaction as its side effect:
--
--   BEGIN;
--     claimed := crm.fn_claim_event(consumer_name, event_id, org_id);
--     IF claimed THEN
--       -- perform the CRM side effect (RecordActivity / SetQualification
--       -- Status / AddNote / lead-score apply) in this same transaction
--     END IF;
--   COMMIT;
--
-- The claim and the side effect commit atomically: if the side effect
-- raises, the whole transaction (including the claim row) rolls back
-- together, so a genuinely failed attempt is retryable — a duplicate
-- delivery is only ever suppressed once its corresponding side effect has
-- actually committed successfully.
--
-- This table is CRM-owned, not a reuse of analytics.analytics_event_dedup
-- — the governing task explicitly requires CRM-owned persistence for CRM
-- consumer idempotency rather than a cross-context write into Analytics.
--
-- This is separate from audit.domain_event_outbox (5J, migration 077):
-- the outbox is the platform-wide *publisher*-side durable queue Voice
-- writes events into; this table is the *consumer*-side dedup ledger CRM
-- uses when reacting to whatever event source it is actually wired to
-- (the outbox today, or, for the in-process Tool Runner paths that never
-- touch the outbox at all — see 6G §23 — the tool call's own idempotent
-- application-service semantics). Both durability mechanisms are real
-- and serve different ends of the same pipe; this migration does not
-- collapse them into one table.
-- =================================================================

CREATE TABLE crm.event_consumer_dedup (
  consumer_name    TEXT        NOT NULL,
  source_event_id  UUID        NOT NULL,
  organization_id  UUID        NOT NULL,
  result_ref       UUID        NULL,
  processed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_event_consumer_dedup PRIMARY KEY (consumer_name, source_event_id),
  CONSTRAINT chk_ecd_consumer_name_len CHECK (length(consumer_name) BETWEEN 1 AND 200)
);

COMMENT ON TABLE crm.event_consumer_dedup IS
  'CRM-owned durable idempotency ledger for domain-event consumers (Voice->CRM subscribers, lead-scoring worker). One row per (consumer_name, source_event_id) that has been successfully claimed and processed. Not partitioned: retention is short (see cleanup note below), volume is bounded by actual event throughput, not by long-term audit retention.';
COMMENT ON COLUMN crm.event_consumer_dedup.consumer_name IS
  'Stable identifier for the specific subscriber, e.g. crm.call_ended_subscriber, crm.qualification_set_subscriber, crm.summarization_completed_subscriber, crm.lead_scoring_worker.';
COMMENT ON COLUMN crm.event_consumer_dedup.source_event_id IS
  'The event envelope''s own id (6A §27.3 event_id / audit.domain_event_outbox.id) — the identity a redelivery is expected to preserve.';
COMMENT ON COLUMN crm.event_consumer_dedup.result_ref IS
  'Optional: the CRM entity id this event produced/updated (e.g. a Contact, Activity, or Note id), for observability only — never relied on for the dedup guarantee itself, which is the primary key alone.';

CREATE INDEX idx_ecd_org_time ON crm.event_consumer_dedup (organization_id, processed_at DESC);

ALTER TABLE crm.event_consumer_dedup ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.event_consumer_dedup FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_event_consumer_dedup_tenant ON crm.event_consumer_dedup
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- app_worker is the only ordinary caller (event subscribers and the
-- scoring worker are background processes, never the request-time API);
-- app_api is not granted access — no REST endpoint reads or writes this
-- table directly. DELETE is granted for the documented retention
-- housekeeping below, mirroring audit.domain_event_outbox's own
-- documented-but-not-pg_cron-scheduled cleanup pattern (077_5J1.sql).
GRANT SELECT, INSERT, DELETE ON crm.event_consumer_dedup TO app_worker;
GRANT SELECT ON crm.event_consumer_dedup TO app_readonly, app_platform_admin;

-- Retention (documented, not scheduled — no pg_cron job exists anywhere
-- in this frozen schema; this is an operational runbook note, exactly
-- like 077_5J1.sql's own retention comment):
--   DELETE FROM crm.event_consumer_dedup WHERE processed_at < NOW() - INTERVAL '30 days';
-- 30 days comfortably exceeds any plausible at-least-once redelivery
-- window for the event sources this table protects against.

-- ---------------------------------------------------------------
-- crm.fn_claim_event(): atomic claim-or-detect-duplicate.
-- Returns TRUE if this call is the first (and therefore authoritative)
-- claim for (consumer_name, source_event_id) — the caller should proceed
-- with its CRM side effect in the SAME transaction. Returns FALSE if the
-- tuple was already claimed by a prior, already-committed call — the
-- caller must treat this as a no-op success and perform no side effect.
--
-- SECURITY DEFINER is not required for privilege elevation here either
-- (app_worker already holds INSERT on this table) — chosen for the same
-- centralization reason as crm.fn_merge_contacts(): one narrow, safe,
-- reusable primitive every CRM event subscriber calls identically,
-- rather than four different call sites each hand-rolling their own
-- ON CONFLICT clause.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.fn_claim_event(
  p_consumer_name    TEXT,
  p_source_event_id  UUID,
  p_organization_id  UUID,
  p_result_ref       UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = crm, pg_catalog
AS $$
BEGIN
  INSERT INTO crm.event_consumer_dedup (consumer_name, source_event_id, organization_id, result_ref, processed_at)
  VALUES (p_consumer_name, p_source_event_id, p_organization_id, p_result_ref, NOW())
  ON CONFLICT (consumer_name, source_event_id) DO NOTHING;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION crm.fn_claim_event(TEXT, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.fn_claim_event(TEXT, UUID, UUID, UUID) TO app_worker, app_platform_admin;
