-- =================================================================
-- Migration 102 (Phase 5H.2 — controlled amendment): Commercial Pricing
--   Agreements, payment-flow correctness, usage-idempotency correctness,
--   late-usage adjustment provenance.
-- down_revision: 101_5I1
-- Transaction: yes (no CONCURRENTLY; every new column is NULL-default or
--   constant-default; every ALTER COLUMN DROP NOT NULL is metadata-only)
-- Source: docs/phase-06-api-design/6K-Billing-Usage-APIs.md (Phase 6K
--   FINAL Blocker Remediation pass). Closes the confirmed Phase 5H
--   schema gap (no persistence for organization-specific negotiated
--   recurring pricing) plus five further confirmed defects an
--   adversarial review of the first 6K draft found in its own new
--   design and in one pre-existing 5H column:
--
--   1. billing.payment_attempts.provider_transaction_id NOT NULL
--      (047-058_5H.sql, migration 055) makes it IMPOSSIBLE to insert the
--      local payment_attempts row BEFORE the provider is called — but
--      that ordering (local row first, provider call second, outside any
--      DB transaction) is the platform's own required payment-transaction-
--      boundary invariant (6A/4F — never hold a DB transaction open across
--      an external network call). Fixed here: DROP NOT NULL. Multiple
--      concurrent NULL values are already correctly non-colliding under
--      the existing uq_pa_provider_tx UNIQUE constraint (PostgreSQL
--      standard NULL-distinctness semantics) — no constraint redesign
--      needed, confirmed live in this migration's own validation pass.
--   2. No durable, atomically-deduplicated inbound payment-webhook
--      receipt existed — the first 6K draft proposed deduplicating via
--      an UPDATE against payment_attempts.provider_webhook_event_id,
--      which is not an atomic "insert once" guarantee the way
--      INSERT ... ON CONFLICT ... RETURNING is. Fixed here: new
--      billing.payment_webhook_receipts table, mirroring 6J §24.3's own
--      inbound-webhook dedup pattern exactly.
--   3. billing.usage_events' idempotency key
--      (organization_id, source_system, source_event_id, occurred_at)
--      does NOT include metric — a single conversation.turn_completed
--      event producing both LLM_PROMPT_TOKENS and LLM_COMPLETION_TOKENS
--      rows under the same source_system would silently lose the second
--      row to ON CONFLICT DO NOTHING. No schema change was needed to fix
--      this (source_event_id is already TEXT) — fixed by a documented,
--      binding ingestion-consumer rule (6K §22.2): a multi-metric
--      producer event's source_event_id is suffixed ':<metric>' per row.
--      This migration adds no DDL for this fix; it is recorded here for
--      completeness since it was found during this same remediation pass.
--   4. No composite (id, organization_id) tenant-scoped FK existed between
--      the three new commercial-pricing tables, or from subscriptions/
--      billing_periods/invoice_lines into commercial_pricing_agreement_
--      versions — an application bug could otherwise persist a
--      cross-tenant pricing relationship with only a trigger (easy to
--      miss) rather than the FK layer itself rejecting it. Fixed here
--      via UNIQUE (id, organization_id) on both new parent-side tables
--      plus composite FKs from every child/consumer table.
--   5. The originally-proposed activation function could supersede a
--      still-currently-valid ACTIVE agreement version the moment a
--      future-dated renegotiated version was activated — creating a
--      window where old terms are gone and new terms are not yet
--      applicable. Fixed here: fn_activate_commercial_pricing_agreement_
--      version refuses to supersede an existing ACTIVE version early: it
--      raises if a prior ACTIVE version exists and the version being
--      activated has a future effective_from. (A brand-new agreement's
--      very first version, with no prior ACTIVE version to disrupt, may
--      still be activated with a future effective_from — §13.3's
--      period-open resolution already correctly treats "not yet
--      effective" as "falls back to plan pricing," so this causes no
--      gap.) A scheduled worker (documented, not a DB object — this
--      migration adds no pg_cron job, matching the platform's existing
--      no-DB-scheduled-job convention, 5J §077's own precedent) re-tries
--      activation once effective_from arrives.
--
-- SECOND PASS (2026-08-30, same day — amended in place, per the same
--   "never applied to any real database" policy 086_5H1/101_5I1's own
--   amendment history already established for this codebase; confirmed
--   before this pass began — the only prior applications of this file
--   were against genuinely disposable, already-deleted local PostgreSQL
--   18.6 validation instances). An independent freeze-gate review found
--   5 further BLOCKERS and 1 SIGNIFICANT issue in this file's own first
--   pass, none previously caught:
--
--   FB-6K-01/02. commercial_pricing_agreements/...agreement_versions
--      granted app_platform_admin full raw INSERT/UPDATE/DELETE. Because
--      fn_cpav_immutability's guard list deliberately excludes status/
--      effective_to/activated_at/status_reason (they must remain mutable
--      FOR the lifecycle functions), a raw UPDATE by app_platform_admin
--      could activate/supersede/expire a version, or rewrite its
--      effective dates, bypassing every lifecycle rule entirely — and no
--      trigger fired on DELETE at all, so a non-DRAFT (financially
--      effective) version could simply be erased. Fixed: Part A's own
--      GRANT statements are corrected in place to SELECT-only for every
--      role including app_platform_admin — SECURITY DEFINER functions
--      never need the caller's own table grants (they execute as their
--      owner), so Part D's functions are completely unaffected.
--   FB-6K-03/04. payment_webhook_receipts granted app_api both SELECT
--      (cross-tenant metadata exposure — the table carries no RLS by
--      design) and raw INSERT (a compromised/buggy tenant-facing path
--      could pre-claim a real provider event ID or inject fabricated
--      receipts). Fixed: both grants removed; a new, narrow
--      fn_record_payment_webhook_receipt() accepts only the three
--      ingress-safe fields (never organization_id/payment_attempt_id/
--      processing_status).
--   FB-6K-05. billing.payment_attempts (055_5H.sql, frozen, unedited)
--      grants app_api direct INSERT — dangerous under 6K's own payment-
--      intent API, since a raw insert can supply invoice_id/amount/
--      currency/provider/status directly; RLS proves tenant ownership
--      only, never that the amount matches the invoice's own unpaid
--      balance. Fixed: REVOKE (a later-migration statement, not an edit
--      of 055_5H.sql) + new fn_create_payment_attempt(), the first
--      app_api-callable billing SECURITY DEFINER function in this
--      schema, deriving every financial value server-side and binding
--      tenant context via organization.current_tenant_id() with no
--      p_organization_id parameter to forge in the first place.
--   FB-6K-06. Per-call CALL_MINUTES rounding (ROUND(seconds/60, 4) at
--      usage_events insert time, then SUM()'d into usage_records) is not
--      mathematically equivalent to DEC-6K-02's own "exact seconds/60"
--      mandate once aggregated: 1000 one-second calls, rounded per-call,
--      sum to 16.7000 minutes; the true aggregate (1000/60, rounded
--      once) is 16.6667 — a real, provable overstatement. Fixed: new
--      nullable usage_events.source_quantity_seconds column preserves
--      the exact pre-conversion seconds value; aggregation is corrected
--      to sum exact seconds first and round once, never per call.
--   SIGNIFICANT (not separately FB-numbered by the review, folded into
--      the FB-6K-05 fix). fn_process_payment_webhook_receipt originally
--      accepted p_payment_attempt_id/p_organization_id as direct
--      caller-supplied inputs, writing them through with only a "don't
--      overwrite once set" guard — unsafe provenance even for a
--      worker/admin-only caller. Fixed: the function now takes
--      p_provider_transaction_id instead and independently RESOLVES the
--      originating payment_attempts row (and, through it, the owning
--      organization) from the platform's own data, cross-checking that
--      the receipt's own payment_provider matches the resolved attempt's
--      provider (a cross-provider linkage attempt fails closed).
--
--   Broader least-privilege audit (task's own explicit mandate, beyond
--   the 6 items above): app_api's unnecessary direct INSERT on
--   usage_events, cost_entries, invoice_lines, and tax_lines (none ever
--   legitimately reached by a tenant-facing code path under 6K's own
--   architecture) is revoked; app_worker's direct INSERT on credits and
--   credit_ledger_entries is revoked (reconciling the executed grants
--   with 5H's OWN already-stated security-model intent, §20 of the 5H
--   schema document, that credits are created only via
--   fn_billing_apply_credit — the grants had never actually matched that
--   stated intent); app_api's direct INSERT on refunds is revoked
--   (contradicted 6K's own "no tenant-facing refund creation" design).
-- =================================================================


-- =================================================================
-- PART A — Commercial Pricing Agreements
-- =================================================================

CREATE TABLE billing.commercial_pricing_agreements (
  id                  UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id     UUID    NOT NULL,
  base_plan_id        UUID    NOT NULL REFERENCES billing.plans(id) ON DELETE RESTRICT,
  status              TEXT    NOT NULL DEFAULT 'ACTIVE',
  contract_reference  TEXT    NULL,
  created_by_ref      TEXT    NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cpa            PRIMARY KEY (id),
  CONSTRAINT uq_cpa_org        UNIQUE (organization_id),
  -- Composite-FK support target for every child table below (task
  -- requirement: DB-enforced, not application-convention, tenant
  -- consistency between an agreement and everything hanging off it).
  CONSTRAINT uq_cpa_id_org     UNIQUE (id, organization_id),
  CONSTRAINT chk_cpa_status    CHECK (status IN ('ACTIVE','CLOSED'))
);

CREATE TRIGGER trg_cpa_updated_at
  BEFORE UPDATE ON billing.commercial_pricing_agreements
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- organization_id / base_plan_id are immutable for the life of the row —
-- a commercial relationship must never be reassigned to a different
-- tenant or a different base plan family after creation. Unlike
-- fn_cpav_immutability below (which only freezes fields once a *version*
-- leaves DRAFT), this guard applies unconditionally from creation,
-- because the parent agreement itself has no DRAFT/ACTIVE staging concept
-- — it exists the moment it is created (task §9).
CREATE OR REPLACE FUNCTION billing.fn_cpa_identity_immutable()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
BEGIN
  IF NEW.organization_id <> OLD.organization_id THEN
    RAISE EXCEPTION 'billing: commercial_pricing_agreements.organization_id is immutable';
  END IF;
  IF NEW.base_plan_id <> OLD.base_plan_id THEN
    RAISE EXCEPTION 'billing: commercial_pricing_agreements.base_plan_id is immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_cpa_identity_immutable() FROM PUBLIC;

CREATE TRIGGER trg_cpa_identity_immutable
  BEFORE UPDATE ON billing.commercial_pricing_agreements
  FOR EACH ROW EXECUTE FUNCTION billing.fn_cpa_identity_immutable();

ALTER TABLE billing.commercial_pricing_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.commercial_pricing_agreements FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cpa_tenant ON billing.commercial_pricing_agreements
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- FINAL freeze-gate correction (FB-6K-01/02): SECURITY DEFINER functions run
-- as their OWNER, not the calling role — they never need the caller to hold
-- direct table grants. Unlike several OTHER 5H financial tables (invoices,
-- payment_attempts, credits), which deliberately retain app_platform_admin's
-- full raw CRUD as a documented "operational corrections" escape hatch
-- (ADR-5H-006), commercial pricing agreements carry a materially different
-- risk profile: a single raw UPDATE/DELETE here can directly manufacture
-- below-market negotiated pricing or erase a binding commercial term with no
-- lifecycle guard in the way, not merely correct an already-bounded,
-- already-audited financial record after the fact. This table therefore has
-- NO raw-DML escape hatch at all, for ANY role including app_platform_admin —
-- every mutation, including by platform-admin/commercial-management actors,
-- goes through the four guarded functions in Part D, which remain fully
-- functional despite this (they execute as the function owner). SELECT-only
-- for every application role; genuine emergency repair (e.g. a mis-entered
-- contract_reference before activation) requires re-issuing the SECURITY
-- DEFINER create sequence, itself immutable, audited history — never a
-- silent overwrite.
GRANT SELECT ON billing.commercial_pricing_agreements TO app_api, app_worker, app_readonly, app_platform_admin;

-- ----------------------------------------------------------------
CREATE TABLE billing.commercial_pricing_agreement_versions (
  id                             UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                UUID    NOT NULL,
  agreement_id                   UUID    NOT NULL,
  version_number                 INTEGER NOT NULL,
  base_plan_version_id           UUID    NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  currency                       CHAR(3) NOT NULL,
  base_price_override_amount     NUMERIC(18,4) NULL,
  base_price_override_currency   CHAR(3)       NULL,
  status                         TEXT    NOT NULL DEFAULT 'DRAFT',
  effective_from                 DATE    NOT NULL,
  effective_to                   DATE    NULL,        -- half-open interval [effective_from, effective_to)
  contract_reference             TEXT    NULL,
  reason                         TEXT    NOT NULL,     -- immutable once non-DRAFT: why this version was negotiated
  status_reason                  TEXT    NULL,         -- mutable via lifecycle functions only: why status changed (e.g. early-expiry note)
  created_by_ref                 TEXT    NOT NULL,
  approved_by_ref                TEXT    NOT NULL,
  activated_at                   TIMESTAMPTZ NULL,
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cpav                  PRIMARY KEY (id),
  CONSTRAINT uq_cpav_agreement_ver    UNIQUE (agreement_id, version_number),
  -- Composite-FK support target for commercial_pricing_metrics and every
  -- consumer table (subscriptions, billing_periods, invoice_lines) below.
  CONSTRAINT uq_cpav_id_org           UNIQUE (id, organization_id),
  -- Tenant-scoped composite FK to the parent agreement — structurally
  -- guarantees this version's organization_id can never disagree with
  -- its own agreement's organization_id (task §15, item 1).
  CONSTRAINT fk_cpav_agreement        FOREIGN KEY (agreement_id, organization_id)
                                       REFERENCES billing.commercial_pricing_agreements (id, organization_id)
                                       ON DELETE RESTRICT,
  CONSTRAINT chk_cpav_status          CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED','EXPIRED')),
  CONSTRAINT chk_cpav_dates           CHECK (effective_to IS NULL OR effective_to > effective_from),
  CONSTRAINT chk_cpav_currency        CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_cpav_base_override   CHECK (
    (base_price_override_amount IS NULL AND base_price_override_currency IS NULL)
    OR (base_price_override_amount IS NOT NULL AND base_price_override_currency IS NOT NULL
        AND base_price_override_amount >= 0)
  ),
  CONSTRAINT chk_cpav_version_number  CHECK (version_number >= 1),
  CONSTRAINT chk_cpav_activated       CHECK ((status IN ('ACTIVE','SUPERSEDED','EXPIRED')) = (activated_at IS NOT NULL))
);

-- At most one ACTIVE version per agreement — valid under the sequential-
-- activation model enforced by fn_activate_commercial_pricing_agreement_
-- version (Part D): a version is never activated while it would overlap
-- a still-current ACTIVE version's own [effective_from, effective_to)
-- interval, so "one ACTIVE row" and "no temporal gap/overlap" hold
-- simultaneously without needing a GiST exclusion constraint / btree_gist
-- extension (task §13's "smallest safe implementation" instruction).
CREATE UNIQUE INDEX uq_cpav_one_active ON billing.commercial_pricing_agreement_versions (agreement_id)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_cpav_org       ON billing.commercial_pricing_agreement_versions (organization_id, status);
CREATE INDEX idx_cpav_agreement ON billing.commercial_pricing_agreement_versions (agreement_id, version_number DESC);

-- Financial immutability once a version leaves DRAFT — the full field
-- list task §10 requires, not merely the four originally proposed.
-- status / effective_to / activated_at / status_reason are the only
-- columns a non-DRAFT row may ever change, and only via the guarded
-- lifecycle functions in Part D (which themselves never touch a
-- financial field) — a raw privileged UPDATE cannot rewrite financial
-- history even if attempted.
CREATE OR REPLACE FUNCTION billing.fn_cpav_immutability()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
BEGIN
  IF OLD.status <> 'DRAFT' THEN
    IF NEW.organization_id               <> OLD.organization_id
    OR NEW.agreement_id                  <> OLD.agreement_id
    OR NEW.version_number                <> OLD.version_number
    OR NEW.base_plan_version_id          <> OLD.base_plan_version_id
    OR NEW.currency                      <> OLD.currency
    OR NEW.base_price_override_amount    IS DISTINCT FROM OLD.base_price_override_amount
    OR NEW.base_price_override_currency  IS DISTINCT FROM OLD.base_price_override_currency
    OR NEW.effective_from                <> OLD.effective_from
    OR NEW.contract_reference            IS DISTINCT FROM OLD.contract_reference
    OR NEW.reason                        <> OLD.reason
    OR NEW.created_by_ref                <> OLD.created_by_ref
    OR NEW.approved_by_ref               <> OLD.approved_by_ref
    THEN
      RAISE EXCEPTION 'billing: commercial_pricing_agreement_version % is % and financially/contractually immutable', OLD.id, OLD.status;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_cpav_immutability() FROM PUBLIC;

CREATE TRIGGER trg_cpav_immutability
  BEFORE UPDATE ON billing.commercial_pricing_agreement_versions
  FOR EACH ROW EXECUTE FUNCTION billing.fn_cpav_immutability();

ALTER TABLE billing.commercial_pricing_agreement_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.commercial_pricing_agreement_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cpav_tenant ON billing.commercial_pricing_agreement_versions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- FINAL freeze-gate correction (FB-6K-01/02, same rationale as
-- commercial_pricing_agreements above): NO raw DML for any role, including
-- app_platform_admin. Every lifecycle transition (activate/expire) and every
-- version creation happens exclusively through Part D's guarded functions,
-- which are unaffected by this REVOKE since SECURITY DEFINER functions run
-- as their owner. This closes the specific bypass class the freeze-gate
-- review found: fn_cpav_immutability's trigger only ever guarded the
-- FINANCIAL fields once a row left DRAFT — it never restricted WHO could
-- still freely UPDATE status/effective_to/activated_at/status_reason via
-- raw SQL, or DELETE a non-DRAFT row outright (no trigger fires on DELETE
-- at all). Removing all non-SELECT grants closes both gaps at once, for
-- every role, unconditionally — not just for the DRAFT-vs-non-DRAFT cases
-- the immutability trigger already handled.
GRANT SELECT ON billing.commercial_pricing_agreement_versions TO app_api, app_worker, app_readonly, app_platform_admin;

-- ----------------------------------------------------------------
CREATE TABLE billing.commercial_pricing_metrics (
  id                              UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                 UUID    NOT NULL,
  agreement_version_id            UUID    NOT NULL,
  metric                          TEXT    NOT NULL,
  included_quantity_override      NUMERIC(18,4) NULL,
  overage_rate_override_amount    NUMERIC(18,4) NULL,
  overage_rate_override_currency  CHAR(3)       NULL,
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cpm                PRIMARY KEY (id),
  CONSTRAINT uq_cpm_version_metric UNIQUE (agreement_version_id, metric),
  -- Tenant-scoped composite FK to the parent version (task §15, item 2).
  CONSTRAINT fk_cpm_agreement_ver  FOREIGN KEY (agreement_version_id, organization_id)
                                    REFERENCES billing.commercial_pricing_agreement_versions (id, organization_id)
                                    ON DELETE RESTRICT,
  CONSTRAINT chk_cpm_included      CHECK (included_quantity_override IS NULL OR included_quantity_override >= 0),
  CONSTRAINT chk_cpm_overage       CHECK (
    (overage_rate_override_amount IS NULL AND overage_rate_override_currency IS NULL)
    OR (overage_rate_override_amount IS NOT NULL AND overage_rate_override_currency IS NOT NULL
        AND overage_rate_override_amount >= 0)
  )
);

CREATE INDEX idx_cpm_version ON billing.commercial_pricing_metrics (agreement_version_id);

-- Append-only while parent version is DRAFT; frozen once parent leaves
-- DRAFT. Covers INSERT, UPDATE, *and* DELETE (task §11 — the originally
-- proposed guard only covered UPDATE/DELETE, silently permitting a new
-- metric row to be added to an already-ACTIVE version via plain INSERT).
CREATE OR REPLACE FUNCTION billing.fn_cpm_parent_draft_guard()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE v_parent_status TEXT;
BEGIN
  SELECT status INTO v_parent_status FROM billing.commercial_pricing_agreement_versions
  WHERE id = COALESCE(NEW.agreement_version_id, OLD.agreement_version_id);
  IF v_parent_status IS DISTINCT FROM 'DRAFT' THEN
    RAISE EXCEPTION 'billing: commercial_pricing_metrics rows may only be inserted/changed while the parent version is DRAFT (parent status = %)', v_parent_status;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_cpm_parent_draft_guard() FROM PUBLIC;

CREATE TRIGGER trg_cpm_draft_guard
  BEFORE INSERT OR UPDATE OR DELETE ON billing.commercial_pricing_metrics
  FOR EACH ROW EXECUTE FUNCTION billing.fn_cpm_parent_draft_guard();

ALTER TABLE billing.commercial_pricing_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.commercial_pricing_metrics FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cpm_tenant ON billing.commercial_pricing_metrics
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- FINAL freeze-gate correction: consistent with the two tables above — no
-- raw DML for any role. fn_cpm_parent_draft_guard already blocked
-- post-activation INSERT/UPDATE/DELETE for every role including
-- app_platform_admin (live-confirmed in the prior validation pass); removing
-- the raw grants entirely additionally closes the DRAFT-stage case (a
-- metric row can no longer be hand-crafted outside
-- fn_create_commercial_pricing_agreement_version's own JSONB-array path,
-- consistent with "no arbitrary SQL/expressions in pricing," task §69).
GRANT SELECT ON billing.commercial_pricing_metrics TO app_api, app_worker, app_readonly, app_platform_admin;


-- =================================================================
-- PART B — Pinning Columns on Existing Tables (composite, tenant-scoped)
-- =================================================================

ALTER TABLE billing.subscriptions
  ADD COLUMN commercial_pricing_agreement_version_id UUID NULL;
ALTER TABLE billing.subscriptions
  ADD CONSTRAINT fk_sub_cpav FOREIGN KEY (commercial_pricing_agreement_version_id, organization_id)
    REFERENCES billing.commercial_pricing_agreement_versions (id, organization_id) ON DELETE RESTRICT;
CREATE INDEX idx_sub_cpav ON billing.subscriptions (commercial_pricing_agreement_version_id)
  WHERE commercial_pricing_agreement_version_id IS NOT NULL;

ALTER TABLE billing.billing_periods
  ADD COLUMN commercial_pricing_agreement_version_id UUID NULL;
ALTER TABLE billing.billing_periods
  ADD CONSTRAINT fk_bp_cpav FOREIGN KEY (commercial_pricing_agreement_version_id, organization_id)
    REFERENCES billing.commercial_pricing_agreement_versions (id, organization_id) ON DELETE RESTRICT;
CREATE INDEX idx_bp_cpav ON billing.billing_periods (commercial_pricing_agreement_version_id)
  WHERE commercial_pricing_agreement_version_id IS NOT NULL;

-- Cross-column consistency the composite FK above cannot express by
-- itself: when a billing_period pins a commercial_pricing_agreement_
-- version, that version's OWN base_plan_version_id must equal the
-- period's plan_version_id — an agreement version negotiated against
-- PlanVersion v3 must never silently apply to a period pinned to v4
-- (task §7). Applied to both subscriptions (the "current pointer") and
-- billing_periods (the authoritative historical pin, task §15) for
-- symmetric protection.
CREATE OR REPLACE FUNCTION billing.fn_bp_agreement_plan_consistency()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE v_base_plan_version_id UUID;
BEGIN
  IF NEW.commercial_pricing_agreement_version_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT base_plan_version_id INTO v_base_plan_version_id
  FROM billing.commercial_pricing_agreement_versions
  WHERE id = NEW.commercial_pricing_agreement_version_id;
  IF v_base_plan_version_id IS DISTINCT FROM NEW.plan_version_id THEN
    RAISE EXCEPTION 'billing: % row''s plan_version_id (%) does not match its pinned commercial_pricing_agreement_version''s base_plan_version_id (%)',
      TG_TABLE_NAME, NEW.plan_version_id, v_base_plan_version_id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_bp_agreement_plan_consistency() FROM PUBLIC;

CREATE TRIGGER trg_bp_agreement_plan_consistency
  BEFORE INSERT OR UPDATE OF plan_version_id, commercial_pricing_agreement_version_id ON billing.billing_periods
  FOR EACH ROW EXECUTE FUNCTION billing.fn_bp_agreement_plan_consistency();

CREATE TRIGGER trg_sub_agreement_plan_consistency
  BEFORE INSERT OR UPDATE OF plan_version_id, commercial_pricing_agreement_version_id ON billing.subscriptions
  FOR EACH ROW EXECUTE FUNCTION billing.fn_bp_agreement_plan_consistency();

-- Invoice line provenance (task §14/§16) — FIELD-LEVEL, not one vague
-- label. unit_price_source explains the monetary rate actually charged
-- (base price for a BASE_FEE line, overage rate for a USAGE/OVERAGE
-- line); included_quantity_source explains the allowance that produced
-- an OVERAGE line's billable quantity (NULL where not applicable, e.g.
-- BASE_FEE/CREDIT/TAX/ADJUSTMENT lines). commercial_pricing_agreement_
-- version_id is populated whenever either source is 'AGREEMENT', and
-- must be NULL when both are 'PLAN'/NULL — enforced below, not merely
-- documented.
ALTER TABLE billing.invoice_lines
  ADD COLUMN unit_price_source TEXT NOT NULL DEFAULT 'PLAN',
  ADD COLUMN included_quantity_source TEXT NULL,
  ADD COLUMN commercial_pricing_agreement_version_id UUID NULL;

ALTER TABLE billing.invoice_lines
  ADD CONSTRAINT chk_il_unit_price_source CHECK (unit_price_source IN ('PLAN','AGREEMENT')),
  ADD CONSTRAINT chk_il_included_qty_source CHECK (included_quantity_source IS NULL OR included_quantity_source IN ('PLAN','AGREEMENT')),
  ADD CONSTRAINT chk_il_pricing_provenance CHECK (
    (unit_price_source = 'AGREEMENT' OR included_quantity_source = 'AGREEMENT')
    = (commercial_pricing_agreement_version_id IS NOT NULL)
  ),
  ADD CONSTRAINT fk_il_cpav FOREIGN KEY (commercial_pricing_agreement_version_id, organization_id)
    REFERENCES billing.commercial_pricing_agreement_versions (id, organization_id);

-- invoice_lines keeps its existing REVOKE UPDATE, DELETE FROM app_api,
-- app_worker (058_5H.sql, untouched) — the three new columns are
-- populated only at INSERT time, alongside every other line field.


-- =================================================================
-- PART C — Payment Flow Correctness
-- =================================================================

-- Bug #1 (this file's header): a local payment_attempts row must be
-- insertable BEFORE the provider is ever called (the platform's own
-- required transaction-boundary invariant) — but provider_transaction_id
-- was NOT NULL, making that ordering impossible. Metadata-only change;
-- no table rewrite (PostgreSQL DROP NOT NULL never rewrites a table).
-- Existing uq_pa_provider_tx UNIQUE (payment_provider, provider_
-- transaction_id) is UNCHANGED and continues to work correctly with
-- multiple NULLs — PostgreSQL treats NULL <> NULL for uniqueness
-- purposes by default, confirmed live in this migration's validation
-- pass (§ live test PAY-1).
ALTER TABLE billing.payment_attempts ALTER COLUMN provider_transaction_id DROP NOT NULL;

-- payment_method_kind: the 6K API's own response model (GET /billing/
-- payments) needs a stable, persisted, provider-confirmed value — never
-- derivable from the opaque payment_method_ref token alone (task §20).
-- Populated only by the reconciliation step once the provider confirms
-- the method actually used; a client-supplied "hint" at payment-intent
-- creation time is never written here directly.
ALTER TABLE billing.payment_attempts
  ADD COLUMN payment_method_kind TEXT NULL;
ALTER TABLE billing.payment_attempts
  ADD CONSTRAINT chk_pa_method_kind CHECK (payment_method_kind IS NULL OR payment_method_kind IN
    ('CARD','UPI','NETBANKING','WALLET','MANDATE','BANK_TRANSFER'));

-- FINAL freeze-gate correction (FB-6K-05): billing.payment_attempts has
-- carried `GRANT SELECT, INSERT ON billing.payment_attempts TO app_api,
-- app_worker;` since the frozen 055_5H.sql — unchanged, unedited here.
-- Under 6K's own payment-intent API this became financially dangerous: a
-- raw app_api INSERT can supply invoice_id, amount, currency, provider,
-- and status directly, and RLS proves only tenant ownership, never that
-- the amount equals the invoice's authoritative unpaid balance, that the
-- currency matches the invoice, or that the provider is server-selected
-- policy rather than caller choice. REVOKE (not an edit of 055_5H.sql —
-- a later migration statement, exactly the established pattern
-- 087_5B1/096_5B2/101_5I1 already used to harden frozen grants) + a
-- guarded creation function below that derives every financial value
-- itself, matching the same discipline already applied to invoices/
-- credits/payment status transitions elsewhere in 5H.
REVOKE INSERT ON billing.payment_attempts FROM app_api;

-- fn_create_payment_attempt: the sole tenant-reachable path to create a
-- local payment_attempts row. Deliberately takes NO p_organization_id
-- parameter at all — organization is derived exclusively from
-- organization.current_tenant_id() (the same interactive-session tenant
-- binding 6A §9.1's pipeline already establishes before this function is
-- ever reachable), eliminating the tenant-forgery vector by construction
-- rather than by an internal equality check a future edit could
-- accidentally drop. This is the FIRST app_api-callable billing
-- SECURITY DEFINER function in this schema (every other one, §9.1 of the
-- API document, is worker/admin-only) — held to the strictest possible
-- construction for exactly that reason.
--
-- Every financial value is derived server-side: amount = invoice's own
-- unpaid balance (total_due_amount - amount_paid_amount, FOR UPDATE-
-- locked to serialize a concurrent duplicate call), currency = invoice's
-- own currency, provider = a fixed server-side policy (V1: single default
-- per the platform's own INR-first design, 4I §13.1 — no BillingAccount-
-- level payment-provider-policy column exists yet to read from; documented
-- here rather than inventing one). p_payment_method_hint is accepted for
-- API-contract completeness (6K §29.4's own request body shape) but is
-- inert at the DB layer — never written anywhere; it exists only for the
-- calling service to shape which checkout screen the provider opens on,
-- entirely outside this function's own responsibility.
--
-- Cross-tenant/nonexistent invoice_id and a not-`OPEN` invoice both raise
-- the same generic "not payable" class of exception — the calling API
-- layer maps both to the same 404/409-shaped response (task §11's own
-- "generic not-found semantics" requirement), never distinguishing
-- "doesn't exist" from "isn't yours."
CREATE OR REPLACE FUNCTION billing.fn_create_payment_attempt(
  p_invoice_id            UUID,
  p_payment_method_hint   TEXT DEFAULT NULL
) RETURNS TABLE(payment_attempt_id UUID, payment_provider TEXT, amount_amount NUMERIC(18,4), amount_currency CHAR(3))
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, organization, pg_catalog AS $$
DECLARE
  v_tenant_id UUID;
  v_invoice_org UUID;
  v_status TEXT;
  v_total_due NUMERIC(18,4);
  v_amount_paid NUMERIC(18,4);
  v_currency CHAR(3);
  v_remaining NUMERIC(18,4);
  v_provider TEXT;
  v_existing_nonterminal UUID;
  v_id UUID;
BEGIN
  v_tenant_id := organization.current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'billing: no tenant context set';
  END IF;

  SELECT organization_id, status, total_due_amount, amount_paid_amount, currency
    INTO v_invoice_org, v_status, v_total_due, v_amount_paid, v_currency
  FROM billing.invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF v_invoice_org IS NULL OR v_invoice_org <> v_tenant_id THEN
    RAISE EXCEPTION 'billing: invoice % not found', p_invoice_id;  -- deliberately identical wording/shape whether the invoice does not exist or belongs to a different tenant
  END IF;
  IF v_status <> 'OPEN' THEN
    RAISE EXCEPTION 'billing: invoice % is not payable (status = %)', p_invoice_id, v_status;
  END IF;

  SELECT id INTO v_existing_nonterminal
  FROM billing.payment_attempts
  WHERE invoice_id = p_invoice_id AND status IN ('INITIATED','PENDING')
  LIMIT 1;
  IF v_existing_nonterminal IS NOT NULL THEN
    RAISE EXCEPTION 'billing: invoice % already has a non-terminal payment attempt %', p_invoice_id, v_existing_nonterminal;
  END IF;

  v_remaining := v_total_due - v_amount_paid;
  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'billing: invoice % has no remaining balance', p_invoice_id;
  END IF;

  -- Server-side provider policy resolution — V1: single default provider
  -- (RAZORPAY, 4I §13.1's own V1 decision). A future BillingAccount-level
  -- payment-provider-policy column, if added, would be read here instead;
  -- the client never supplies this value under any circumstance.
  v_provider := 'RAZORPAY';

  INSERT INTO billing.payment_attempts
    (organization_id, invoice_id, payment_provider, status, amount_amount, amount_currency)
  VALUES
    (v_tenant_id, p_invoice_id, v_provider, 'INITIATED', v_remaining, v_currency)
  RETURNING id INTO v_id;

  RETURN QUERY SELECT v_id, v_provider, v_remaining, v_currency;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_create_payment_attempt(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_create_payment_attempt(UUID, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- ----------------------------------------------------------------
-- Durable, atomically-deduplicated inbound payment-webhook receipt
-- (task §21/§22) — mirrors 6J §24.3's own INSERT ... ON CONFLICT ...
-- RETURNING pattern exactly, which is the actual atomic "insert once"
-- guarantee an UPDATE-based dedup against payment_attempts cannot
-- provide. No RLS — mirrors audit.domain_event_outbox's own precedent
-- (5J §077): this is not an ordinary tenant-scoped read pattern (the
-- receipt exists before any tenant/organization is even known, task
-- §23's trust-boundary sequence), so RLS would either block the
-- pre-identity write or require a BYPASSRLS role for an ordinary insert
-- path — organization_id is populated only once resolved, post-
-- verification, exactly like audit.domain_event_outbox's own nullable
-- organization_id column.
CREATE TABLE billing.payment_webhook_receipts (
  id                    UUID        NOT NULL DEFAULT gen_uuid_v7(),
  payment_provider      TEXT        NOT NULL,
  provider_event_id     TEXT        NOT NULL,
  received_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processing_status     TEXT        NOT NULL DEFAULT 'RECEIVED',
  payload_hash          CHAR(64)    NULL,   -- SHA-256 of the raw, already-verified payload bytes; raw payload itself never stored (5I ADR-5I-010 precedent)
  payment_attempt_id    UUID        NULL REFERENCES billing.payment_attempts(id),
  organization_id       UUID        NULL,   -- populated only once payment_attempt_id resolves it (§23) — never trusted from the payload before that
  attempt_count         INTEGER     NOT NULL DEFAULT 0,
  last_error            TEXT        NULL,
  processed_at          TIMESTAMPTZ NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_pwr                PRIMARY KEY (id),
  CONSTRAINT uq_pwr_provider_event UNIQUE (payment_provider, provider_event_id),  -- NOT DEFERRABLE: the atomic ON CONFLICT dedup gate requires an immediate constraint
  CONSTRAINT chk_pwr_processing    CHECK (processing_status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED')),
  CONSTRAINT chk_pwr_last_error_len CHECK (last_error IS NULL OR length(last_error) <= 2000),
  CONSTRAINT chk_pwr_processed     CHECK ((processing_status IN ('PROCESSED','FAILED')) = (processed_at IS NOT NULL))
);

CREATE INDEX idx_pwr_status  ON billing.payment_webhook_receipts (processing_status, received_at);
CREATE INDEX idx_pwr_attempt ON billing.payment_webhook_receipts (payment_attempt_id) WHERE payment_attempt_id IS NOT NULL;

-- The inbound webhook HTTP handler (unauthenticated by JWT — 6A §28.2's
-- carve-out — but still executing as the API service's own DB role, not
-- a tenant's) performs the durable, atomic dedup INSERT directly —
-- mirrors 5J §077's own domain_event_outbox INSERT grant to app_api,
-- no wrapping SECURITY DEFINER function needed for a plain gated INSERT.
-- ----------------------------------------------------------------
-- fn_link_payment_provider_transaction: the sole path by which a local
-- payment_attempts row (created INITIATED, provider_transaction_id NULL
-- — Part C's own fix) is later linked to the provider's real transaction
-- reference, once the provider responds (task §17/§18's transaction-
-- boundary requirement — this call happens AFTER the provider's network
-- response, in a short follow-up transaction, never while a provider
-- HTTP call is outstanding).
--
-- Deliberately a NEW, distinctly-named function rather than an
-- additional CREATE OR REPLACE overload of the existing (057_5H.sql)
-- fn_update_payment_status: live-tested during this migration's own
-- validation pass and confirmed that appending a new DEFAULT-valued
-- trailing parameter to an existing function via CREATE OR REPLACE does
-- NOT replace it — PostgreSQL creates a second, separately-privileged
-- overload sharing the same name, which defaults to PUBLIC EXECUTE like
-- any newly created function until explicitly revoked, and is a
-- confusing "which overload fired" hazard for a financial function
-- either way. A distinctly-named function avoids both problems and
-- leaves 057_5H.sql's fn_update_payment_status completely untouched —
-- its existing state machine (INITIATED->PENDING->SUCCEEDED|FAILED|
-- CANCELLED) is reused verbatim for every transition after linkage.
-- Idempotent for a re-link with the SAME provider_transaction_id;
-- rejects a re-link attempt with a DIFFERENT one (protects an already-
-- linked attempt from being silently reassigned) and rejects linking
-- onto a terminal-state attempt (use fn_update_payment_status for
-- terminal transitions, unchanged).
-- p_payment_method_kind: optional, provider-confirmed only (never a raw
-- client hint written here as authoritative, task §20) — accepted here
-- too since the provider typically confirms both the transaction
-- reference and the method used in the same reconciliation step; the
-- column's own CHECK constraint (chk_pa_method_kind, Part C) is the
-- actual governed-vocabulary guard, not this function.
CREATE OR REPLACE FUNCTION billing.fn_link_payment_provider_transaction(
  p_organization_id          UUID,
  p_payment_attempt_id       UUID,
  p_provider_transaction_id  TEXT,
  p_new_status                TEXT DEFAULT 'PENDING',
  p_payment_method_kind      TEXT DEFAULT NULL
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE
  v_current_status TEXT;
  v_existing_provider_tx TEXT;
BEGIN
  SELECT status, provider_transaction_id INTO v_current_status, v_existing_provider_tx
  FROM billing.payment_attempts
  WHERE id = p_payment_attempt_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'billing: payment_attempt % not found', p_payment_attempt_id;
  END IF;
  IF v_existing_provider_tx IS NOT NULL AND v_existing_provider_tx <> p_provider_transaction_id THEN
    RAISE EXCEPTION 'billing: payment_attempt % is already linked to a different provider_transaction_id', p_payment_attempt_id;
  END IF;
  IF v_current_status NOT IN ('INITIATED','PENDING') THEN
    RAISE EXCEPTION 'billing: cannot link a provider transaction to a terminal-state payment_attempt (status = %)', v_current_status;
  END IF;
  IF p_new_status NOT IN ('INITIATED','PENDING') THEN
    RAISE EXCEPTION 'billing: fn_link_payment_provider_transaction may only set a non-terminal status; use fn_update_payment_status for a terminal transition';
  END IF;

  UPDATE billing.payment_attempts
  SET provider_transaction_id = p_provider_transaction_id,
      status = p_new_status,
      payment_method_kind = COALESCE(p_payment_method_kind, payment_method_kind)
  WHERE id = p_payment_attempt_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_link_payment_provider_transaction(UUID, UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_link_payment_provider_transaction(UUID, UUID, TEXT, TEXT, TEXT)
  TO app_worker, app_platform_admin;

-- FINAL freeze-gate correction (FB-6K-03/04): the original design granted
-- app_api both SELECT and raw INSERT directly on this table. Both are
-- removed:
--   * SELECT: app_api is the general TENANT-facing runtime role (every
--     ordinary HTTP request, 6A §9.1) — this table carries no RLS (§ above),
--     so a broad app_api SELECT grant would let any authenticated tenant
--     session read every organization's provider/event-id/payment-attempt/
--     failure metadata. Ordinary tenant endpoints (GET /billing/payments,
--     §29.6) already serve payment state from the RLS-protected
--     payment_attempts table — they have no legitimate need to read this
--     table at all, so no application capability is lost.
--   * INSERT: an app_api-executed raw INSERT is dangerous in a different
--     way — a compromised or merely buggy tenant-facing code path reachable
--     through app_api's own DB session could pre-claim a real provider
--     event ID (poisoning the dedup key before the genuine webhook arrives,
--     causing the real delivery to be silently treated as a duplicate) or
--     inject fabricated receipt rows. Fixed below with a narrow SECURITY
--     DEFINER ingress function that accepts only the three fields available
--     BEFORE any tenant/financial identity is known — never organization_id,
--     payment_attempt_id, or processing_status — so even a full compromise
--     of the inbound HTTP handler's own request-shaping logic cannot use
--     this path to manufacture financial state, only to record "a
--     (possibly bogus, but signature-unverified-payload-only) delivery
--     arrived." Verification (PaymentProviderPort.verify_webhook, §30.2 of
--     the API document) happens in the calling code BEFORE this function is
--     ever invoked — this function is not itself a security boundary
--     against a forged payload, only the durability/dedup layer, exactly as
--     designed; a payload that fails verification never reaches this call
--     at all.
GRANT SELECT ON billing.payment_webhook_receipts TO app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.payment_webhook_receipts TO app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_record_payment_webhook_receipt(
  p_payment_provider  TEXT,
  p_provider_event_id TEXT,
  p_payload_hash       CHAR(64) DEFAULT NULL
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO billing.payment_webhook_receipts (payment_provider, provider_event_id, payload_hash)
  VALUES (p_payment_provider, p_provider_event_id, p_payload_hash)
  ON CONFLICT (payment_provider, provider_event_id) DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;  -- NULL means "already recorded" (duplicate delivery) — the
                -- caller's own enqueue-gating logic (6J §24.3's discipline,
                -- 6K §30.4) must treat a NULL return exactly like a
                -- zero-row RETURNING result: skip enqueueing async
                -- processing, proceed straight to the fast-ACK.
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_record_payment_webhook_receipt(TEXT, TEXT, CHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_record_payment_webhook_receipt(TEXT, TEXT, CHAR)
  TO app_api, app_platform_admin;

-- Controlled status-transition + linkage path — mirrors fn_update_
-- payment_status's own state-machine-guard pattern. app_worker-only:
-- these transitions happen only inside the async webhook-processing
-- task (§30.2), never from the synchronous inbound HTTP request path.
--
-- FINAL freeze-gate correction (FB-6K-07): the original signature accepted
-- p_payment_attempt_id/p_organization_id as direct caller-supplied inputs
-- and wrote them through unvalidated (beyond "don't overwrite once set").
-- This is unsafe provenance even though the caller is worker/admin-only —
-- nothing forced the linkage to actually be correct. Corrected: the caller
-- supplies only p_provider_transaction_id (extracted from the verified
-- webhook payload); this function independently RESOLVES the originating
-- payment_attempts row (and, through it, the owning organization) from the
-- platform's own authoritative data — a payload-claimed identity is never
-- trusted, only used as a lookup key against data the platform itself
-- created (§29.4's own payment-intent flow). The resolution join also
-- requires the receipt's own payment_provider to match the resolved
-- attempt's payment_provider — a cross-provider linking attempt (a
-- Razorpay-signed receipt somehow resolving to a Cashfree-provider
-- attempt, which should never legitimately happen) fails closed rather
-- than silently linking.
CREATE OR REPLACE FUNCTION billing.fn_process_payment_webhook_receipt(
  p_receipt_id                UUID,
  p_new_status                 TEXT,
  p_provider_transaction_id    TEXT DEFAULT NULL,
  p_error                      TEXT DEFAULT NULL
) RETURNS TABLE(resolved BOOLEAN, resolved_payment_attempt_id UUID, resolved_organization_id UUID)
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE
  v_current TEXT;
  v_receipt_provider TEXT;
  v_already_linked_attempt UUID;
  v_already_linked_org UUID;
  v_resolved_attempt_id UUID;
  v_resolved_org UUID;
  v_allowed TEXT[][] := ARRAY[
    ARRAY['RECEIVED', 'PROCESSING'],
    ARRAY['PROCESSING', 'PROCESSED'],
    ARRAY['PROCESSING', 'FAILED'],
    ARRAY['RECEIVED', 'FAILED']
  ];
  v_pair TEXT[];
  v_valid BOOLEAN := FALSE;
BEGIN
  IF p_new_status NOT IN ('PROCESSING','PROCESSED','FAILED') THEN
    RAISE EXCEPTION 'billing: invalid payment_webhook_receipts status %', p_new_status;
  END IF;

  SELECT processing_status, payment_provider, payment_attempt_id, organization_id
    INTO v_current, v_receipt_provider, v_already_linked_attempt, v_already_linked_org
  FROM billing.payment_webhook_receipts WHERE id = p_receipt_id FOR UPDATE;

  IF v_current IS NULL THEN
    RAISE EXCEPTION 'billing: payment_webhook_receipt % not found', p_receipt_id;
  END IF;
  IF v_current IN ('PROCESSED','FAILED') THEN
    IF v_current = p_new_status THEN
      RETURN QUERY SELECT TRUE, v_already_linked_attempt, v_already_linked_org; RETURN;
    END IF;
    RAISE EXCEPTION 'billing: payment_webhook_receipt % is terminal (%) — cannot transition to %', p_receipt_id, v_current, p_new_status;
  END IF;

  FOREACH v_pair SLICE 1 IN ARRAY v_allowed LOOP
    IF v_pair[1] = v_current AND v_pair[2] = p_new_status THEN v_valid := TRUE; EXIT; END IF;
  END LOOP;
  IF NOT v_valid THEN
    RAISE EXCEPTION 'billing: transition % -> % not allowed for payment_webhook_receipt %', v_current, p_new_status, p_receipt_id;
  END IF;

  -- Resolve linkage internally, once, on the first call that supplies a
  -- provider_transaction_id and finds none already linked. Never resolved
  -- from a caller-supplied attempt/organization id directly.
  v_resolved_attempt_id := v_already_linked_attempt;
  v_resolved_org := v_already_linked_org;
  IF v_resolved_attempt_id IS NULL AND p_provider_transaction_id IS NOT NULL THEN
    SELECT pa.id, i.organization_id INTO v_resolved_attempt_id, v_resolved_org
    FROM billing.payment_attempts pa
    JOIN billing.invoices i ON i.id = pa.invoice_id
    WHERE pa.provider_transaction_id = p_provider_transaction_id
      AND pa.payment_provider = v_receipt_provider;  -- cross-provider linking fails closed: no row if providers disagree
    -- v_resolved_attempt_id staying NULL here (unknown transaction
    -- correlation) is not itself an exception — the caller decides the
    -- outcome (typically p_new_status = 'FAILED' with p_error naming the
    -- UNKNOWN_TRANSACTION_CORRELATION classification, 6K §30.6/§36); this
    -- function's own job is resolution, not the security-anomaly decision.
  END IF;

  UPDATE billing.payment_webhook_receipts
  SET processing_status  = p_new_status,
      payment_attempt_id = v_resolved_attempt_id,
      organization_id    = v_resolved_org,
      attempt_count       = attempt_count + 1,
      last_error          = CASE WHEN p_new_status = 'FAILED' THEN p_error ELSE last_error END,
      processed_at        = CASE WHEN p_new_status IN ('PROCESSED','FAILED') THEN NOW() ELSE processed_at END
  WHERE id = p_receipt_id;

  RETURN QUERY SELECT TRUE, v_resolved_attempt_id, v_resolved_org;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_process_payment_webhook_receipt(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_process_payment_webhook_receipt(UUID, TEXT, TEXT, TEXT)
  TO app_worker, app_platform_admin;


-- =================================================================
-- PART D — Commercial Pricing Agreement Lifecycle Functions
-- =================================================================
-- Following the exact pattern of every existing 5H financial function:
-- app_worker/app_platform_admin-only grants, REVOKE ALL FROM PUBLIC,
-- explicit SET search_path, no app_api grant. Consistent with every
-- existing 5H function, these do NOT call audit.fn_insert_audit_event()
-- or insert into audit.domain_event_outbox internally — the calling
-- application service does both, in the same transaction, immediately
-- after the function call succeeds (matching the 6C/6D precedent, e.g.
-- AGENT_PUBLISHED).

CREATE OR REPLACE FUNCTION billing.fn_create_commercial_pricing_agreement(
  p_organization_id  UUID,
  p_base_plan_id     UUID,
  p_contract_reference TEXT,
  p_created_by_ref   TEXT
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM billing.billing_accounts WHERE organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'billing: no billing account for organization %', p_organization_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM billing.plans WHERE id = p_base_plan_id AND is_active) THEN
    RAISE EXCEPTION 'billing: base_plan_id % is not an active plan', p_base_plan_id;
  END IF;

  INSERT INTO billing.commercial_pricing_agreements
    (organization_id, base_plan_id, contract_reference, created_by_ref)
  VALUES (p_organization_id, p_base_plan_id, p_contract_reference, p_created_by_ref)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_create_commercial_pricing_agreement(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_create_commercial_pricing_agreement(UUID, UUID, TEXT, TEXT)
  TO app_worker, app_platform_admin;

-- p_metrics: JSONB array [{"metric": "CALL_MINUTES", "included_quantity_override": 500,
--   "overage_rate_override_amount": 3.0000, "overage_rate_override_currency": "INR"}, ...]
-- No metric name is validated against a closed enum (5H ADR-5H-002 —
-- metrics are an open, application-governed vocabulary, not a DB enum).
CREATE OR REPLACE FUNCTION billing.fn_create_commercial_pricing_agreement_version(
  p_organization_id             UUID,
  p_agreement_id                UUID,
  p_base_plan_version_id        UUID,
  p_currency                    CHAR(3),
  p_base_price_override_amount  NUMERIC(18,4),
  p_base_price_override_currency CHAR(3),
  p_effective_from              DATE,
  p_effective_to                DATE,
  p_contract_reference          TEXT,
  p_reason                      TEXT,
  p_created_by_ref              TEXT,
  p_approved_by_ref             TEXT,
  p_metrics                     JSONB DEFAULT '[]'
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE
  v_id UUID;
  v_agreement_org UUID;
  v_agreement_plan_id UUID;
  v_pv_plan_id UUID;
  v_pv_published BOOLEAN;
  v_account_currency CHAR(3);
  v_next_version INTEGER;
  v_metric JSONB;
BEGIN
  SELECT organization_id, base_plan_id INTO v_agreement_org, v_agreement_plan_id
  FROM billing.commercial_pricing_agreements WHERE id = p_agreement_id;
  IF v_agreement_org IS NULL THEN
    RAISE EXCEPTION 'billing: commercial_pricing_agreement % not found', p_agreement_id;
  END IF;
  IF v_agreement_org <> p_organization_id THEN
    RAISE EXCEPTION 'billing: agreement % does not belong to organization %', p_agreement_id, p_organization_id;
  END IF;

  SELECT plan_id, is_published INTO v_pv_plan_id, v_pv_published
  FROM billing.plan_versions WHERE id = p_base_plan_version_id;
  IF v_pv_plan_id IS NULL OR NOT v_pv_published THEN
    RAISE EXCEPTION 'billing: base_plan_version_id % is not a published plan version', p_base_plan_version_id;
  END IF;
  IF v_pv_plan_id <> v_agreement_plan_id THEN
    RAISE EXCEPTION 'billing: plan_version % does not belong to this agreement''s base plan %', p_base_plan_version_id, v_agreement_plan_id;
  END IF;

  SELECT currency INTO v_account_currency FROM billing.billing_accounts WHERE organization_id = p_organization_id;
  IF p_currency <> v_account_currency THEN
    RAISE EXCEPTION 'billing: agreement currency % does not match billing_accounts.currency %', p_currency, v_account_currency;
  END IF;

  SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
  FROM billing.commercial_pricing_agreement_versions WHERE agreement_id = p_agreement_id;

  INSERT INTO billing.commercial_pricing_agreement_versions
    (organization_id, agreement_id, version_number, base_plan_version_id, currency,
     base_price_override_amount, base_price_override_currency,
     effective_from, effective_to, contract_reference, reason, created_by_ref, approved_by_ref)
  VALUES
    (p_organization_id, p_agreement_id, v_next_version, p_base_plan_version_id, p_currency,
     p_base_price_override_amount, p_base_price_override_currency,
     p_effective_from, p_effective_to, p_contract_reference, p_reason, p_created_by_ref, p_approved_by_ref)
  RETURNING id INTO v_id;

  FOR v_metric IN SELECT * FROM jsonb_array_elements(p_metrics) LOOP
    INSERT INTO billing.commercial_pricing_metrics
      (organization_id, agreement_version_id, metric,
       included_quantity_override, overage_rate_override_amount, overage_rate_override_currency)
    VALUES
      (p_organization_id, v_id, v_metric->>'metric',
       NULLIF(v_metric->>'included_quantity_override','')::NUMERIC(18,4),
       NULLIF(v_metric->>'overage_rate_override_amount','')::NUMERIC(18,4),
       NULLIF(v_metric->>'overage_rate_override_currency',''));
  END LOOP;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_create_commercial_pricing_agreement_version(
  UUID, UUID, UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_create_commercial_pricing_agreement_version(
  UUID, UUID, UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, TEXT, JSONB)
  TO app_worker, app_platform_admin;

-- fn_activate_commercial_pricing_agreement_version: DRAFT -> ACTIVE.
--
-- Corrected (task §13): refuses to supersede a still-currently-valid
-- ACTIVE version early. If a prior ACTIVE version exists for this
-- agreement AND the version being activated has a future effective_from,
-- the call is rejected — activation must be retried once effective_from
-- has arrived (a scheduled worker's responsibility, documented, not a
-- DB job). If no prior ACTIVE version exists (this is the agreement's
-- very first version), a future effective_from is safe to activate
-- immediately — §13.3's period-open resolution already treats "not yet
-- effective" as "fall back to plan pricing" for any period opened before
-- that date, so no gap is created.
--
-- When superseding IS performed, the boundary is exact and half-open:
-- v_prior.effective_to := new.effective_from (no "-1 day" subtraction —
-- v1 covers [v1.effective_from, v2.effective_from) and v2 covers
-- [v2.effective_from, ...) — zero gap, zero overlap).
CREATE OR REPLACE FUNCTION billing.fn_activate_commercial_pricing_agreement_version(
  p_organization_id UUID,
  p_agreement_version_id UUID
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE
  v_agreement_id UUID;
  v_status TEXT;
  v_effective_from DATE;
  v_org UUID;
  v_prior_id UUID;
BEGIN
  SELECT agreement_id, status, effective_from, organization_id
    INTO v_agreement_id, v_status, v_effective_from, v_org
  FROM billing.commercial_pricing_agreement_versions
  WHERE id = p_agreement_version_id
  FOR UPDATE;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'billing: commercial_pricing_agreement_version % not found', p_agreement_version_id;
  END IF;
  IF v_org <> p_organization_id THEN
    RAISE EXCEPTION 'billing: agreement version % does not belong to organization %', p_agreement_version_id, p_organization_id;
  END IF;
  IF v_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'billing: can only activate a DRAFT version; current status = %', v_status;
  END IF;

  SELECT id INTO v_prior_id
  FROM billing.commercial_pricing_agreement_versions
  WHERE agreement_id = v_agreement_id AND status = 'ACTIVE'
  FOR UPDATE;

  IF v_prior_id IS NOT NULL AND v_effective_from > CURRENT_DATE THEN
    RAISE EXCEPTION 'billing: cannot activate version % now — its effective_from (%) is in the future and an existing ACTIVE version (%) would be prematurely superseded; retry once effective_from has arrived',
      p_agreement_version_id, v_effective_from, v_prior_id;
  END IF;

  IF v_prior_id IS NOT NULL THEN
    UPDATE billing.commercial_pricing_agreement_versions
    SET status = 'SUPERSEDED',
        effective_to = v_effective_from,
        status_reason = 'Superseded by version ' || p_agreement_version_id::TEXT
    WHERE id = v_prior_id;
  END IF;

  UPDATE billing.commercial_pricing_agreement_versions
  SET status = 'ACTIVE', activated_at = NOW()
  WHERE id = p_agreement_version_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_activate_commercial_pricing_agreement_version(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_activate_commercial_pricing_agreement_version(UUID, UUID)
  TO app_worker, app_platform_admin;

-- fn_expire_commercial_pricing_agreement_version: ACTIVE -> EXPIRED, no
-- replacement. Uses status_reason (mutable) rather than mutating the
-- immutable reason column (corrected — the original draft attempted to
-- append to `reason`, which fn_cpav_immutability now correctly forbids).
CREATE OR REPLACE FUNCTION billing.fn_expire_commercial_pricing_agreement_version(
  p_organization_id UUID,
  p_agreement_version_id UUID,
  p_reason TEXT
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE v_status TEXT; v_org UUID;
BEGIN
  SELECT status, organization_id INTO v_status, v_org
  FROM billing.commercial_pricing_agreement_versions
  WHERE id = p_agreement_version_id
  FOR UPDATE;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'billing: commercial_pricing_agreement_version % not found', p_agreement_version_id;
  END IF;
  IF v_org <> p_organization_id THEN
    RAISE EXCEPTION 'billing: agreement version % does not belong to organization %', p_agreement_version_id, p_organization_id;
  END IF;
  IF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'billing: can only expire an ACTIVE version; current status = %', v_status;
  END IF;

  UPDATE billing.commercial_pricing_agreement_versions
  SET status = 'EXPIRED',
      effective_to = COALESCE(effective_to, CURRENT_DATE),
      status_reason = p_reason
  WHERE id = p_agreement_version_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_expire_commercial_pricing_agreement_version(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_expire_commercial_pricing_agreement_version(UUID, UUID, TEXT)
  TO app_worker, app_platform_admin;


-- =================================================================
-- PART E — Late-Arriving Usage Adjustment Provenance (DEC-6K-04)
-- =================================================================
-- billing_adjustments (056_5H.sql) has no structured field for "which
-- period/metric/pricing-basis does this correction relate to" — a late-
-- usage correction's own reason text alone is not sufficient provenance
-- for support/audit reconstruction (task §32). Additive, nullable
-- columns; only populated by the new function below, never by the
-- existing fn_create_billing_adjustment (086_5H1.sql, untouched).

ALTER TABLE billing.billing_adjustments
  ADD COLUMN late_usage_billing_period_id UUID NULL REFERENCES billing.billing_periods(id),
  ADD COLUMN late_usage_metric TEXT NULL,
  ADD COLUMN late_usage_provenance JSONB NULL;
  -- late_usage_provenance shape: {"plan_version_id": "...",
  --   "commercial_pricing_agreement_version_id": "..." | null,
  --   "usage_event_ids": ["...", ...], "quantity": "12.5000",
  --   "unit_price": {"amount": "3.0000", "currency": "INR"}}

CREATE INDEX idx_badj_late_period ON billing.billing_adjustments (late_usage_billing_period_id)
  WHERE late_usage_billing_period_id IS NOT NULL;

-- fn_create_late_usage_billing_adjustment: the sole write path for a
-- late-usage correction. Always adjustment_type = 'MANUAL_CORRECTION'
-- (DEC-6K-04's own design — a late-usage correction is definitionally a
-- manual correction, never a CREDIT_NOTE/DEBIT_NOTE/WRITE_OFF). Mirrors
-- fn_create_billing_adjustment's own validation (086_5H1.sql — billing
-- account exists, invoice ownership if provided) without editing that
-- existing, frozen function.
CREATE OR REPLACE FUNCTION billing.fn_create_late_usage_billing_adjustment(
  p_organization_id             UUID,
  p_invoice_id                  UUID,
  p_description                 TEXT,
  p_amount_amount                NUMERIC(18,4),
  p_amount_currency              CHAR(3),
  p_created_by_ref               TEXT,
  p_late_usage_billing_period_id UUID,
  p_late_usage_metric            TEXT,
  p_late_usage_provenance        JSONB
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM billing.billing_accounts WHERE organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'billing: no billing account for organization %', p_organization_id;
  END IF;
  IF p_invoice_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM billing.invoices WHERE id = p_invoice_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'billing: invoice % does not belong to organization %', p_invoice_id, p_organization_id;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM billing.billing_periods WHERE id = p_late_usage_billing_period_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'billing: billing_period % does not belong to organization %', p_late_usage_billing_period_id, p_organization_id;
  END IF;

  INSERT INTO billing.billing_adjustments (
    organization_id, invoice_id, adjustment_type, description,
    amount_amount, amount_currency, created_by_ref,
    late_usage_billing_period_id, late_usage_metric, late_usage_provenance
  ) VALUES (
    p_organization_id, p_invoice_id, 'MANUAL_CORRECTION', p_description,
    p_amount_amount, p_amount_currency, p_created_by_ref,
    p_late_usage_billing_period_id, p_late_usage_metric, p_late_usage_provenance
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_create_late_usage_billing_adjustment(
  UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_create_late_usage_billing_adjustment(
  UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, UUID, TEXT, JSONB)
  TO app_worker, app_platform_admin;

-- billing_adjustments keeps its existing REVOKE INSERT FROM app_worker
-- (086_5H1.sql — app_worker must go through fn_create_billing_adjustment
-- OR, for the late-usage case specifically, this new function; direct
-- INSERT remains unavailable to app_worker either way).


-- =================================================================
-- PART F — Exact-Aggregate Call-Minute Billing (FB-6K-06)
-- =================================================================
-- Confirmed defect: DEC-6K-02's own "exact duration_seconds / 60" mandate
-- was previously implemented by rounding EACH call's own quantity to 4
-- decimal minutes at usage_events insert time, then summing those already-
-- rounded values into usage_records.quantity_used (5H's own existing QP-06
-- aggregation pattern, unchanged DDL). Per-call rounding before summation
-- is NOT mathematically equivalent to summing exact values and rounding
-- once: 1000 calls of 1 second each, rounded per-call, sum to 16.7000
-- minutes (1000 x ROUND(1/60, 4) = 1000 x 0.0167); the true aggregate is
-- 1000/60 = 16.6666... which itself rounds to 16.6667 — a real, provable
-- overstatement of the customer's exact usage, violating DEC-6K-02.
--
-- Fixed with one additive, nullable column: the exact pre-conversion
-- source quantity (seconds, for CALL_MINUTES; reserved generically for any
-- future metric with the same lossless-aggregation requirement) is
-- preserved on the raw usage_events row, separate from `quantity` (which
-- keeps its existing per-row, already-rounded value for audit/display of
-- that single call only — never used as the billing aggregation input for
-- this metric class). The billing usage-aggregation algorithm (6K §22.3)
-- is corrected to SUM(source_quantity_seconds) — an exact sum, since
-- seconds figures are summed before any rounding is ever applied — and
-- convert to minutes with a SINGLE ROUND(..., 4) at the end, never per row.
-- Metrics that need no such correction (CAMPAIGN_CALLS, WORKFLOW_EXECUTIONS,
-- etc. — already-exact integer counts with no fractional-unit-conversion
-- step) simply leave this column NULL and continue using the existing
-- SUM(quantity) pattern unchanged.
ALTER TABLE billing.usage_events
  ADD COLUMN source_quantity_seconds NUMERIC(18,4) NULL;
ALTER TABLE billing.usage_events
  ADD CONSTRAINT chk_ue_source_quantity_seconds CHECK (source_quantity_seconds IS NULL OR source_quantity_seconds >= 0);
-- Partitioned parent table: ADD COLUMN/ADD CONSTRAINT here apply
-- automatically to every existing and future partition — no per-partition
-- DDL required (standard PostgreSQL partitioned-table behavior).


-- =================================================================
-- PART G — Broader Least-Privilege Hardening (Task's Own §12 Audit)
-- =================================================================
-- The freeze-gate review's own broader audit mandate, beyond the 7 named
-- findings: every direct app_api/app_worker DML grant on a billing table
-- was re-inspected for whether the grantee can supply an authoritative
-- financial value, and whether a guarded function already exists (or
-- should) as the correct sole path. None of the statements below edit a
-- frozen 001-101 file — every one is a REVOKE issued by this later,
-- still-unapplied migration, the same established pattern
-- 087_5B1/096_5B2/101_5I1 already used.
--
-- usage_events / cost_entries: app_api's direct INSERT (050_5H.sql /
-- 051_5H.sql) is unnecessary under 6K's own architecture — usage
-- ingestion and cost recording are EXCLUSIVELY app_worker (Celery
-- consumer) responsibilities (6K §22.1/§35); no application code path
-- ever legitimately reaches either table as app_api. Removing the grant
-- closes "usage-event forgery" (6K §40's own named threat) at the DB
-- layer, not merely at the "no endpoint was built for it" layer.
REVOKE INSERT ON billing.usage_events FROM app_api;
REVOKE INSERT ON billing.cost_entries FROM app_api;

-- invoice_lines / tax_lines: app_api's direct INSERT (054_5H.sql) is
-- unnecessary — invoice-line and tax-line creation happens exclusively
-- inside the invoice-generation worker's own transaction (6K §26.2); no
-- 6K tenant-facing endpoint ever creates a line. app_worker's own grant
-- is retained (it is the legitimate, intended writer).
REVOKE INSERT ON billing.invoice_lines FROM app_api;
REVOKE INSERT ON billing.tax_lines FROM app_api;

-- credits / credit_ledger_entries: 5H's OWN stated security model (§20 of
-- the schema document) already declares "Credits created only via
-- SECURITY DEFINER fn_billing_apply_credit" — but the executed grants
-- (053_5H.sql) contradicted that stated intent by giving app_worker
-- direct INSERT on BOTH tables (app_api's INSERT on `credits` was already
-- correctly revoked by 053_5H.sql itself; credit_ledger_entries was not).
-- A tenant-facing bug reaching app_worker's own credit_ledger_entries
-- INSERT grant (or any bug in app_worker's own code) could otherwise
-- manufacture arbitrary account credit by inserting a positive-amount
-- ledger row directly, bypassing fn_billing_apply_credit entirely — this
-- is squarely "financial authority," reconciled here with 5H's own
-- already-declared intent, not a new restriction invented from nothing.
REVOKE INSERT ON billing.credits FROM app_worker;
REVOKE INSERT ON billing.credit_ledger_entries FROM app_api, app_worker;

-- refunds: app_api's direct INSERT (055_5H.sql) directly contradicts 6K
-- §31.2's own explicit design ("no tenant-facing refund creation in V1")
-- — an ordinary tenant session could otherwise self-issue a refund up to
-- the full original payment amount (bounded only by fn_validate_refund_
-- amount's own trigger, which checks the sum against the original
-- payment but enforces no approval/authorization step at all). Revoked
-- for app_api; app_worker's own grant is retained as the path 6M's
-- future admin/support refund surface will use (5H's own existing
-- fn_validate_refund_amount trigger remains the amount guard on that
-- path) — a dedicated SECURITY DEFINER refund-creation function is a
-- disclosed FUTURE ENHANCEMENT (task explicitly permits "if raw INSERT
-- is retained for [a legitimate internal path], prove that no
-- financially effective row can be manufactured [by the ordinary tenant
-- role]" — satisfied here for app_api; app_worker is a trusted service
-- principal, not a tenant-reachable one).
REVOKE INSERT ON billing.refunds FROM app_api;
