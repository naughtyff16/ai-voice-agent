# Phase 6K — Billing + Usage APIs

## Enterprise AI Voice Agent SaaS — Production API Design

| | |
|---|---|
| **Phase** | 6K — Billing + Usage APIs |
| **Bounded context** | `billing` (Phase 5H) |
| **Depends on** | 6A (standards), 6B (auth/permissions), 6C (organization), 6D (call usage), 6E (AI usage), 6F (knowledge usage), 6H (campaign usage), 6I (workflow usage), 6J (webhook/event catalog, inbound-provider security pattern), 5H (billing schema), 5J (audit/outbox) |
| **Precedes** | Phase 6L (analytics), Phase 6M (platform admin) |
| **PostgreSQL baseline** | PostgreSQL 18.x (per `MIGRATION_MANIFEST.md`, "PostgreSQL 18 Baseline Reconciliation," superseding the original PG16 target — engine-version only, no DDL implication) |
| **Alembic head at start of this phase** | `101_5I1` (`down_revision = '100_5G1'`) |
| **Alembic head after this phase** | `102_5H2` (`down_revision = '101_5I1'`) — one additive migration, **live-validated on PostgreSQL 18.6**, see §12 and `docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` |
| **Status** | See §49 — **READY FOR INDEPENDENT FREEZE-GATE REVIEW**. All four owner decisions (DEC-6K-01/02/03/04) are **ACCEPTED, FINAL**. Migration `102_5H2` is live-validated (fresh + incremental, PostgreSQL 18.6, single head) — see the validation report for full evidence and the blocker-closure table. |

---

## 1. Document Control

This document defines Phase 6K only. Phases 6A–6J are approved/frozen and are **not redesigned** here. Phase 5H (Billing/Usage Schema) is approved and is **not redesigned** here — it is extended by exactly one additive migration (§12, `102_5H2`, live-validated on PostgreSQL 18.6, amended in place across four remediation passes) to close a genuine, business-required schema gap (§11) plus a further sequence of confirmed defects that three independent freeze-gate reviews found across the first three drafts. No previously-applied migration (001–101) is edited. No application implementation code is written — this document specifies contracts, not code; the migration itself, however, is real, executable SQL that has been run end-to-end (fresh and incremental) against a live database, not idealized pseudo-SQL.

Every business/pricing decision this document could not derive from an approved source was surfaced as an owner decision. **All four (DEC-6K-01/02/03/04) have since been reviewed and accepted by the product owner — see §48. They are FINAL and are not re-litigated anywhere in this document.**

## 2. Purpose

Define the complete, production-ready REST + internal-contract surface for: billing accounts, plan catalog (tenant-facing read), commercial pricing agreements (a new capability, §11–§14), subscriptions, billing periods, usage metering and ingestion, quotas, invoices, credits, adjustments, tax/GST presentation, payments (provider-abstracted), refunds, and the billing-domain webhook event producer contract 6J already reserved for this phase.

## 3. Scope

**In scope — 6K owns:** billing accounts; plans/plan versions/plan prices (tenant-facing read only — see §17 for write-ownership handoff); commercial pricing agreements (new, §11–§14); subscriptions; billing periods; usage events/records; quota configs (read + enforcement contract); credits; billing adjustments; invoices/invoice lines/tax lines; payment attempts; refunds; cost entries (internal); the billing-domain webhook event producer contract for `invoice.*`/`payment.*`/`subscription.*`/`usage.*` (6J §19.2's named forward dependency, closed here).

**Out of scope — not redesigned:** voice call lifecycle (6D), CRM (6G), campaign execution (6H), workflow execution (6I), integrations/webhooks transport mechanics (6J), analytics projections (future 6L), platform administration (future 6M — see §41 for the explicit handoff list).

## 4. Non-Goals

- No new payment provider is added (Razorpay remains V1, Cashfree remains the documented second adapter, per 4I §13).
- No programmable/expression-based pricing language — §12.5's `p_metrics` JSONB is a flat array of `{metric, included_quantity_override, overage_rate_override}` values only, never a formula/expression field.
- No customer-selectable invoice currency in V1 (§32 — architecture is multi-currency-capable; V1 stays single-currency-per-account).
- No `SubscriptionItem`/add-on REST surface (§9.3 — confirmed conceptual-only in 4F, never built in 5H's executed DDL; classified `FUTURE ENHANCEMENT`, not a blocking V1 gap).
- No platform-admin REST surface for plan/pricing/tax administration (§41 — 6K defines the domain/DB contract; the REST surface is 6M's).
- No tenant-visible provider cost/margin data (§28).

## 5. Source Documents

Phase 1 SRS; Phase 2 HLA; Phase 3A/3E (outbox/publisher pattern, RBAC caching); Phase 4F (Billing/Usage/Integrations DDD — subscription state machine, proration, `PaymentProviderPort`); Phase 4I (India-First closure — GST model, payment provider decision, currency model); Phase 5A (DB standards); Phase 5B (identity/RLS/permission seed data — `organization.permissions`, `organization.role_permissions`); Phase 5H (Billing/Usage Schema, migrations 047–058, amendment 086_5H1); Phase 5J (Audit/Outbox Schema, migration 077_5J1 — `audit.domain_event_outbox`); `MIGRATION_MANIFEST.md` (PostgreSQL 18 baseline declaration); 6A (API standards — money format, error contract, idempotency, response envelope); 6B (permission catalog, `BILLING_ADMIN` role); 6C (organization lifecycle — `organization:suspend`, distinct from billing-account suspension); 6D (Voice — `call.ended` domain event); 6E (AI Agent — `conversation.turn_completed`); 6F (Knowledge/RAG — `document.indexed`); 6H (Campaign — `campaign.contact.call_attempted`); 6I (Workflow — `workflow.execution.completed`, and 6I's own named forward dependency on 6K for LLM token cost, item 12 of its dependency register); 6J (Integrations/Webhooks — External Event Catalog §19 naming `invoice.created`/`invoice.paid`/`payment.failed`/`usage.threshold_reached`/`subscription.changed` as 6K's forward responsibility, §19.2; Inbound Provider Webhooks §24 architecture pattern reused for payment-provider callbacks, §27).

## 6. Terminology

| Term | Meaning |
|---|---|
| **Plan / PlanVersion / PlanPrice** | Existing 5H concepts — a published, global, versioned commercial offer. Unchanged by this document. |
| **Commercial Pricing Agreement** | New (§11). An organization-specific, versioned overlay on top of a base PlanVersion, negotiated for one tenant. Not a standalone plan. |
| **Commercial Pricing Agreement Version** | New (§11). The immutable, financially-binding unit inside an Agreement. Exactly one may be `ACTIVE` per agreement at a time. |
| **Effective Pricing** | The resolved set of (base price, per-metric included quantity, per-metric overage rate) actually used to bill one billing period — agreement override where present, plan price otherwise (§14). |
| **Usage Event** | A raw, append-only fact of consumption (5H, unchanged). |
| **Usage Record** | A period-aggregated usage total (5H, unchanged). |
| **Billable Usage** | A usage metric for which the effective pricing contract defines a non-null overage rate or included-quantity-based charge (§20 — distinct from "tracked"). |
| **Cost Entry** | Platform's own provider cost (5H, unchanged) — never the customer's charge. |

## 7. Bounded Context Ownership

### 7.1 6K Owns

Billing accounts; plan catalog (read); commercial pricing agreements (domain/DB contract); subscriptions; billing periods; usage events/records; quota configs; credits; billing adjustments; invoices/invoice lines/tax lines; payment attempts; refunds; cost entries; the `invoice.*`/`payment.*`/`subscription.*`/`usage.*` webhook-event production (writing into `audit.domain_event_outbox`, closing 6J §19.2).

### 7.2 Not Redesigned Here

| Context | Owns | 6K's relationship |
|---|---|---|
| 6D Voice | Call lifecycle | 6K consumes `call.ended` (duration) as a usage fact only |
| 6E AI Agent | Conversation turns | 6K consumes `conversation.turn_completed` (token/STT/TTS counts) only |
| 6F Knowledge/RAG | Document ingestion | 6K consumes `document.indexed` (embedding tokens) only |
| 6G CRM | Contacts/deals | No usage relationship in V1 |
| 6H Campaign | Campaign execution | 6K consumes `campaign.contact.call_attempted` only |
| 6I Workflow | Workflow execution | 6K consumes `workflow.execution.completed` only — this closes 6I's own named forward dependency (6I §"Dependency Register" item 12) |
| 6J Integrations/Webhooks | Outbound delivery transport, inbound-provider dedup/verification pattern | 6K is a **producer** into the outbox/webhook pipeline 6J already built; 6K does not redesign delivery, retry, or signing mechanics |
| Future 6L Analytics | Cross-domain projections | 6K exposes read APIs; heavy analytics/margin reporting is 6L's |
| Future 6M Platform Admin | Plan/pricing/tax administration, manual credits, billing-account suspension override | 6K defines the DB-level contract (functions, grants); the REST surface is 6M's, per §41 |

Per 5H §3/§11.2, billing does not query voice/CRM/campaign/knowledge/workflow tables directly — usage arrives only as domain events, consumed into `billing.usage_events`.

## 8. PostgreSQL 18 Baseline

Per `MIGRATION_MANIFEST.md`'s "PostgreSQL 18 Baseline Reconciliation" entry (2026-08-29), PostgreSQL 18.x is the platform's authoritative database engine baseline, confirmed live-validated on a disposable PG18.6 cluster through the full `001→101` chain. This is an engine-version declaration only — no column, function, grant, or migration file changed as a result. The additive migration in §12 targets this same PG18 baseline and is written and validated against it directly (no PG16 compatibility concern remains, per the same manifest entry).

The platform-wide `public.gen_uuid_v7()` `search_path` defect (fixed in `101_5I1.sql`, affecting any `SECURITY DEFINER` function nesting a call to it) is already closed as of the current head; the new functions in §12 are written with an explicit `SET search_path` from the outset and are unaffected by that historical defect.

---

## 9. Repository Review Findings

This section records what the mandatory repository review (task §0) found, before any design decision is made on top of it.

### 9.1 Phase 5H SECURITY DEFINER Audit (per task §53–§54)

Every `SECURITY DEFINER` function in the frozen `billing` schema (047–058, plus the 086_5H1 amendment) was inspected for the tenant-forgery class of defect the 6I/6J remediation passes found and fixed (an `app_api`-callable function taking `p_organization_id` without independently binding it to `organization.current_tenant_id()`).

| Function | Migration | Grantees | Takes `p_organization_id`? | Binds to `current_tenant_id()`? | Verdict |
|---|---|---|---|---|---|
| `fn_allocate_invoice_number` | 052 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |
| `fn_billing_apply_credit` | 053 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |
| `fn_finalize_invoice` | 057 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |
| `fn_mark_invoice_paid` | 057 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |
| `fn_void_invoice` | 057 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |
| `fn_update_payment_status` | 057 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |
| `fn_create_billing_adjustment` | 086_5H1 | `app_worker`, `app_platform_admin` | Yes | No | **PASS** — not `app_api`-callable |

**Finding: no gap of the 6I/6J class exists in 5H.** Every existing billing `SECURITY DEFINER` function that takes `p_organization_id` is granted only to `app_worker`/`app_platform_admin` — never `app_api`. The tenant-forgery lesson (an interactively-authenticated tenant caller supplying an arbitrary `p_organization_id` to a function trusted to act on it) does not apply the same way here, because `app_worker` does not execute inside an RLS-scoped, tenant-bound interactive session the way `app_api` does under 6A §9.1's pipeline (tenant resolution → `SET LOCAL app.tenant_id` happens only on the `app_api` request path). `app_worker`'s trust boundary is instead: **the calling application service, not the database, is responsible for ensuring `p_organization_id` passed into these functions originates from the domain event or authenticated-and-authorized request that triggered the worker action, never from unvalidated client input.**

This is stated as a binding **service-layer invariant** for every 6K application service that calls these functions (§44, INV-6K-21), and the same invariant is carried forward for the seven new functions this document adds (§12.5) — they follow the identical `app_worker`/`app_platform_admin`-only grant pattern, for the same reason, and are documented with the same caveat rather than silently assumed safe. **Live-confirmed, not merely asserted:** `docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §6 re-runs this exact audit against the actually-executed migration on PostgreSQL 18.6 (`has_function_privilege()` for all four roles, all 11 new function objects including the 4 new trigger functions) and additionally confirms, by direct code inspection, that every new function independently re-validates its target row's `organization_id` against the caller-supplied `p_organization_id` before mutating anything.

### 9.2 Confirmed Phase 5H Schema Gap: No Commercial Pricing Persistence

5H's executed DDL (verified directly, not from a conceptual document) contains `plans` → `plan_versions` → `plan_prices` (global, versioned, immutable-once-published) and `subscriptions.plan_version_id` / `billing_periods.plan_version_id` (pinned). It contains **no** table for an organization-specific negotiated price, base-price override, per-metric rate override, or agreement effective-dating. `credits` and `billing_adjustments` exist but are, per their own DDL and ADRs (ADR-5H-004, INV-BILL-10), one-off ledger entries — not a recurring pricing source. Confirmed by direct search: no `negotiated`, `custom pricing`, `commercial agreement`, or `pricing override` term appears anywhere in 4F or 4I. This is a genuine, business-required, additive **Phase 5H schema gap** — not an oversight to route around with credits, and not something to design around by mutating `plan_versions` for one tenant. Closed in §11–§14 with the additive migration in §12.

### 9.3 Confirmed Phase 5H Non-Gap: `SubscriptionItem` / Add-ons

4F §Domain Model conceptually defines `Subscription.Items: list[SubscriptionItem]` (`BASE | ADDON`, ≤20 items). 5H's executed DDL never built this — `subscriptions` has no child items table. Per task §48, this is flagged as `PHASE 5H SCHEMA GAP — FUTURE ENHANCEMENT`, not built here: no V1 business requirement in 4F/4I forces add-on persistence for 6K's own scope (client-specific pricing, §11, is solved without it — a negotiated agreement can express a different base price and different per-metric rates without needing a separate line-item aggregate). No add-on REST surface is designed in this document.

### 9.4 Business Rules — Upstream-Resolved and Owner-Accepted

- **PAST_DUE grace policy (DEC-6K-03, ACCEPTED, FINAL):** 4F §7.1's state machine and 5H §9.2 already specified a 7-day default (configurable) grace period, full platform access during grace, API rejection only after `SUSPENDED` — the product owner has since explicitly accepted this as DEC-6K-03, with the additional binding requirement that a `SUSPENDED` tenant retain read/recovery access (§15.3's explicit eligibility matrix implements this precisely).
- **Proration:** 4F §4.2/§9's `ProratedCreditService` — upgrades are immediate with a prorated credit; downgrades are scheduled for the next period boundary; downgrade proration is explicitly an `OPEN DESIGN DECISION` in 5H (ODD-5H-02) and remains genuinely open upstream — 6K does not resolve it, since no V1 execution path in this document requires it resolved (§33 restates this classification precisely).
- **Payment provider abstraction:** 4F/4I's `PaymentProviderPort` (Razorpay first adapter, Cashfree second, documented interface at 4I §13.2) and the normalized `FailureCode` enum (`INSUFFICIENT_FUNDS | CARD_DECLINED | AUTHENTICATION_FAILED | NETWORK_ERROR | GATEWAY_ERROR | INVALID_METHOD | EXPIRED_METHOD`) and `PaymentMethodKind` enum (`CARD | UPI | NETBANKING | WALLET | MANDATE | BANK_TRANSFER`) are reused verbatim (§26–§30).
- **Call-minute conversion (DEC-6K-02, ACCEPTED, FINAL):** exact `duration_seconds / 60`, no `CEIL`, no per-call rounding, no provider-pulse rounding for customer billing (provider pulse billing may affect internal provider-cost accounting only, never the customer charge). Matches 4F's own worked example exactly (`127 seconds / 60 = 2.12`). Exact numeric handling specified in §22.3.

---

## 10. Billing Domain Model (Unchanged Aggregates, Reused Verbatim)

5H's aggregate → table mapping (§5 of that document) is reused without modification: `BillingAccount`, `Plan`/`PlanVersion`/`PlanPrice`, `Subscription`, `BillingPeriod`, `UsageEvent`, `UsageRecord`, `CostEntry`, `QuotaConfig`, `Credit`/`CreditLedgerEntry`, `Invoice`/`InvoiceLine`/`TaxLine`, `TaxProfile`/`TaxRule`, `InvoiceNumberSequence`, `PaymentAttempt`, `Refund`, `BillingAdjustment`, `FxRate`. This document adds exactly one new aggregate, `CommercialPricingAgreement` (§11), and pins two existing aggregates (`Subscription`, `BillingPeriod`) to it via two new nullable FK columns (§12.3).

```
Plan ──▶ PlanVersion ──▶ PlanPrice (per metric)
                 │
                 │  (optional overlay, new)
                 ▼
      CommercialPricingAgreement ──▶ CommercialPricingAgreementVersion ──▶ CommercialPricingMetric (per metric)
                 │                              │
                 ▼                              ▼
            Subscription ───────────▶ BillingPeriod  (both pin the ACTIVE version, independently, at their own creation time)
                                              │
                                              ▼
                                        UsageRecord + Effective Pricing (§14)
                                              │
                                              ▼
                                        InvoiceLine (snapshotted, §14.4)
```

---

## 11. Commercial Pricing Agreements — Design

### 11.1 Requirement Recap

Per the authoritative business requirement (task §1): the platform must support different negotiated commercial terms per organization (higher/lower base fee, different included quotas, different per-metric rates) without separate application code, hard-coded organization IDs, mutated historical invoices, edited published `PlanVersion`s, or a full bespoke plan duplicated per customer.

### 11.2 Architecture

A `CommercialPricingAgreement` is a **named commercial relationship** between the platform and one organization, anchored to a base `Plan` (not a `PlanVersion` — the specific version is pinned per-agreement-*version*, so a renegotiation can move the tenant onto a newer base `PlanVersion` without starting an entirely new agreement). It is a thin, mostly-immutable parent row; all financially-binding content lives in its child `CommercialPricingAgreementVersion` rows.

A `CommercialPricingAgreementVersion`:
- References exactly one `plan_versions` row (`base_plan_version_id`) — a published version of the agreement's base plan. Feature entitlements and normal plan semantics come from that `PlanVersion` unchanged (per task §70/§71: a commercial agreement is not a standalone plan and never carries feature/entitlement overrides — only financial overrides).
- Carries an optional `base_price_override_{amount,currency}` — `NULL` means "inherit the base `PlanVersion`'s `base_price_amount`."
- Owns zero or more `CommercialPricingMetric` child rows, each overriding `included_quantity` and/or `overage_rate` for exactly one metric. A metric with no override row inherits the corresponding `plan_prices` row unchanged.
- Has `effective_from`/`effective_to` dates, a `contract_reference`, a `reason`, `created_by_ref`/`approved_by_ref`, and a `status` (`DRAFT | ACTIVE | SUPERSEDED | EXPIRED`).
- Becomes financially immutable the moment it leaves `DRAFT` (§12.4) — per **DEC-6K-01** (§48), designed under Option A (immutable, versioned agreement terms).

One organization has at most one `CommercialPricingAgreement` in V1 (`UNIQUE (organization_id)`) — multiple concurrent commercial relationships per tenant (e.g. per-product) are out of scope; nothing in 4F/4I's business requirement calls for it, and this keeps the additive migration to the "smallest necessary" bar the task requires.

### 11.3 Why Not Credits or a Mutable Override Column

Per task §2/§28: a credit is a one-off ledger adjustment to an invoice/account balance — it has no memory of "this org's call-minute rate is ₹3, not ₹2" for the *next* invoice. Reproducing negotiated pricing via a recurring manual credit would require an operator to compute and re-issue the differential every single billing period, is not auditable as "the rate," and breaks the moment usage volume changes (a credit sized for one period's usage is wrong for the next). A mutable override column on `subscriptions` (or a JSONB blob) was rejected per task §3/§69: it cannot answer "what rate produced *this* historical invoice" once the value is later changed — exactly the determinism failure `plan_versions` immutability (ADR-5H-001) already exists to prevent, now reapplied to organization-specific pricing.

---

## 12. Additive Phase 5H Migration — `102_5H2` (Live-Validated on PostgreSQL 18.6)

### 12.1 Placement and Scope Discipline

Continuing the established Phase 5H amendment sequence (`086_5H1` was the first controlled amendment), this is migration **`102_5H2`**, `down_revision = '101_5I1'` — a **new** revision, not an in-place amendment of any existing file (confirmed no `102` file existed anywhere in `5K/alembic/versions/` or `5K/migrations/` before this pass). It is additive-only: four new tables, two nullable composite-FK'd columns on two existing tables, three new columns on `invoice_lines`, three new columns on `billing_adjustments`, two `ALTER COLUMN` statements on `payment_attempts` (one `DROP NOT NULL`, one `ADD COLUMN`), eleven new functions (7 `SECURITY DEFINER`, 4 plain triggers). No existing 5H table, column, constraint, index, function, or grant from migrations 001–101 is altered except the two documented `ALTER TABLE`/`ALTER COLUMN` statements on `payment_attempts`. Nothing in migrations 001–101 is edited.

**Live-validated, not merely specified:** the exact SQL below is the file that was actually run — fresh (`001_5B → 102_5H2`, 102 revisions) and incremental (`101_5I1` pinned, then `102_5H2` applied alone) both `PASS`, exit 0, single Alembic head, `current == head`, on a genuinely fresh, disposable local PostgreSQL 18.6 instance. Full evidence: `docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`; raw logs: `docs/phase-05-database-design/5K/execution_logs/`, prefix `20260830T020000Z_`.

**Corrected in this pass, relative to a first draft (full rationale in each part's own comments below):** an adversarial re-review found and fixed five further defects beyond the core commercial-pricing gap — a pre-existing, confirmed-blocking `payment_attempts.provider_transaction_id NOT NULL` column that made the required payment-transaction-boundary sequence (local row committed *before* the provider is called) structurally impossible; a webhook-dedup design that relied on `UPDATE` rather than an atomic `INSERT ... ON CONFLICT ... RETURNING`; a `usage_events` idempotency-key collision between same-`source_system` multi-metric producer events (live-reproduced, then fixed); missing composite tenant-scoped foreign-key integrity between the new pricing tables and their consumers; and a future-dated-activation gap that could prematurely supersede a still-current commercial agreement version.

### 12.2 Part A — Commercial Pricing Agreements

```sql
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
-- unconditionally, from creation (the parent agreement has no DRAFT/ACTIVE
-- staging concept the way a version does — it exists the moment it is
-- created). Live-confirmed: rejected even for app_platform_admin.
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

-- FINAL freeze-gate correction (FB-6K-01/02): NO raw DML for ANY role,
-- including app_platform_admin. SECURITY DEFINER functions run as their
-- owner, never the caller — Part D's four functions are unaffected. Every
-- OTHER role's SELECT-only grant is unchanged; only app_platform_admin's
-- INSERT/UPDATE/DELETE is removed here, closing the raw-UPDATE/DELETE
-- lifecycle bypass a freeze-gate review found in this table's first-pass
-- design (live-confirmed, §12.8).
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
  status_reason                  TEXT    NULL,         -- mutable via lifecycle functions only: why status changed
  created_by_ref                 TEXT    NOT NULL,
  approved_by_ref                TEXT    NOT NULL,
  activated_at                   TIMESTAMPTZ NULL,
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cpav                  PRIMARY KEY (id),
  CONSTRAINT uq_cpav_agreement_ver    UNIQUE (agreement_id, version_number),
  CONSTRAINT uq_cpav_id_org           UNIQUE (id, organization_id),
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
-- version below: a version is never activated while it would overlap a
-- still-current ACTIVE version's own interval, so this partial unique
-- index and "no temporal gap/overlap" hold together without a GiST
-- exclusion constraint / btree_gist extension.
CREATE UNIQUE INDEX uq_cpav_one_active ON billing.commercial_pricing_agreement_versions (agreement_id)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_cpav_org       ON billing.commercial_pricing_agreement_versions (organization_id, status);
CREATE INDEX idx_cpav_agreement ON billing.commercial_pricing_agreement_versions (agreement_id, version_number DESC);

-- Financial immutability once a version leaves DRAFT — the FULL field
-- list (not merely base price/currency/plan-version/effective_from):
-- organization_id, agreement_id, version_number, contract_reference,
-- reason, created_by_ref, approved_by_ref are all frozen too.
-- status/effective_to/activated_at/status_reason are the only columns a
-- non-DRAFT row may ever change, and only via the guarded lifecycle
-- functions in §12.5. Live-confirmed rejected even for app_platform_admin.
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

-- FINAL freeze-gate correction: same rationale as commercial_pricing_
-- agreements above — this is the table the raw-UPDATE bypass most
-- directly targeted (a version's status/effective_to/activated_at are
-- deliberately mutable-in-principle, per fn_cpav_immutability's own
-- guard list, "for the lifecycle functions" — but nothing previously
-- restricted WHO could reach them via raw SQL). No DELETE grant means a
-- non-DRAFT version can never be erased either — live-confirmed.
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
-- DRAFT. Covers INSERT, UPDATE, *and* DELETE — a first draft's guard only
-- covered UPDATE/DELETE, silently permitting a new metric row to be added
-- to an already-ACTIVE version via plain INSERT. All three verbs
-- individually live-confirmed rejected.
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

-- FINAL freeze-gate correction: consistent with the two tables above.
GRANT SELECT ON billing.commercial_pricing_metrics TO app_api, app_worker, app_readonly, app_platform_admin;
```

### 12.3 Part B — Pinning Columns (Composite, Tenant-Scoped)

```sql
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

-- Cross-column consistency the composite FK above cannot express alone:
-- when a period pins an agreement version, that version's OWN
-- base_plan_version_id must equal the period's plan_version_id — an
-- agreement negotiated against PlanVersion v3 must never silently apply
-- to a period pinned to v4. Applied to both subscriptions (the "current"
-- pointer) and billing_periods (the authoritative historical pin) for
-- symmetric protection. Live-confirmed: rejects a mismatched pin,
-- accepts a matching one.
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

-- Invoice line provenance — FIELD-LEVEL (task requirement), not one vague
-- label: unit_price_source explains the monetary rate actually charged;
-- included_quantity_source explains the allowance that produced an
-- OVERAGE line's billable quantity (NULL where not applicable). A
-- contradictory combination (a source claims AGREEMENT with no linked
-- version, or vice versa) is CHECK-rejected — live-confirmed.
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
```

`invoice_lines` keeps its existing `REVOKE UPDATE, DELETE FROM app_api, app_worker` (058_5H.sql) — the three new columns are populated only at `INSERT` time.

### 12.4 Part C — Payment Flow Correctness

```sql
-- Confirmed-blocking defect fix: local payment_attempts row must be
-- insertable BEFORE the provider is ever called (task's own required
-- transaction-boundary invariant) — but provider_transaction_id was NOT
-- NULL (055_5H.sql), making that ordering impossible. Metadata-only
-- change; no table rewrite. uq_pa_provider_tx continues working
-- correctly with multiple NULLs (PostgreSQL's standard NULL-
-- distinctness semantics for unique constraints — live-confirmed).
ALTER TABLE billing.payment_attempts ALTER COLUMN provider_transaction_id DROP NOT NULL;

-- payment_method_kind: the API's own response model needs a stable,
-- persisted, provider-confirmed value. Populated only by the
-- reconciliation step (fn_link_payment_provider_transaction below), never
-- a raw client hint written as authoritative.
ALTER TABLE billing.payment_attempts
  ADD COLUMN payment_method_kind TEXT NULL;
ALTER TABLE billing.payment_attempts
  ADD CONSTRAINT chk_pa_method_kind CHECK (payment_method_kind IS NULL OR payment_method_kind IN
    ('CARD','UPI','NETBANKING','WALLET','MANDATE','BANK_TRANSFER'));

-- FINAL freeze-gate correction (FB-6K-05): billing.payment_attempts has
-- carried GRANT SELECT, INSERT ... TO app_api, app_worker; since the
-- frozen 055_5H.sql — unedited here. Under 6K's own payment-intent API
-- this became financially dangerous: a raw app_api INSERT can supply
-- invoice_id/amount/currency/provider/status directly, and RLS proves
-- only tenant ownership, never that the amount matches the invoice's own
-- unpaid balance. Fixed with a REVOKE (a later-migration statement, not
-- an edit of 055_5H.sql) + a guarded creation function below.
REVOKE INSERT ON billing.payment_attempts FROM app_api;

-- fn_create_payment_attempt: the sole tenant-reachable path to create a
-- local payment_attempts row — and the FIRST app_api-callable billing
-- SECURITY DEFINER function in this schema (every other one is worker/
-- admin-only). Takes NO p_organization_id parameter at all — organization
-- is derived exclusively from organization.current_tenant_id(),
-- eliminating the tenant-forgery vector by construction. Every financial
-- value is server-derived: amount = the invoice's own unpaid balance
-- (FOR UPDATE-locked, serializing a concurrent duplicate call), currency
-- = the invoice's own currency, provider = a fixed server-side policy
-- (V1: RAZORPAY, 4I §13.1). p_payment_method_hint is accepted for API-
-- contract completeness but is inert at the DB layer — never written
-- anywhere. Cross-tenant/nonexistent invoice_id and a not-OPEN invoice
-- both raise the same generic exception (task's own "generic not-found
-- semantics" requirement) — the API layer never distinguishes "doesn't
-- exist" from "isn't yours."
CREATE OR REPLACE FUNCTION billing.fn_create_payment_attempt(
  p_invoice_id            UUID,
  p_payment_method_hint   TEXT DEFAULT NULL
) RETURNS TABLE(payment_attempt_id UUID, payment_provider TEXT, amount_amount NUMERIC(18,4), amount_currency CHAR(3))
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, organization, pg_catalog AS $$
DECLARE
  v_tenant_id UUID; v_invoice_org UUID; v_status TEXT;
  v_total_due NUMERIC(18,4); v_amount_paid NUMERIC(18,4); v_currency CHAR(3);
  v_remaining NUMERIC(18,4); v_provider TEXT; v_existing_nonterminal UUID; v_id UUID;
BEGIN
  v_tenant_id := organization.current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'billing: no tenant context set';
  END IF;

  SELECT organization_id, status, total_due_amount, amount_paid_amount, currency
    INTO v_invoice_org, v_status, v_total_due, v_amount_paid, v_currency
  FROM billing.invoices WHERE id = p_invoice_id FOR UPDATE;

  IF v_invoice_org IS NULL OR v_invoice_org <> v_tenant_id THEN
    RAISE EXCEPTION 'billing: invoice % not found', p_invoice_id;
  END IF;
  IF v_status <> 'OPEN' THEN
    RAISE EXCEPTION 'billing: invoice % is not payable (status = %)', p_invoice_id, v_status;
  END IF;

  SELECT id INTO v_existing_nonterminal FROM billing.payment_attempts
  WHERE invoice_id = p_invoice_id AND status IN ('INITIATED','PENDING') LIMIT 1;
  IF v_existing_nonterminal IS NOT NULL THEN
    RAISE EXCEPTION 'billing: invoice % already has a non-terminal payment attempt %', p_invoice_id, v_existing_nonterminal;
  END IF;

  v_remaining := v_total_due - v_amount_paid;
  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'billing: invoice % has no remaining balance', p_invoice_id;
  END IF;

  v_provider := 'RAZORPAY';  -- server-side policy, V1 single default

  INSERT INTO billing.payment_attempts (organization_id, invoice_id, payment_provider, status, amount_amount, amount_currency)
  VALUES (v_tenant_id, p_invoice_id, v_provider, 'INITIATED', v_remaining, v_currency)
  RETURNING id INTO v_id;

  RETURN QUERY SELECT v_id, v_provider, v_remaining, v_currency;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_create_payment_attempt(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_create_payment_attempt(UUID, TEXT)
  TO app_api, app_worker, app_platform_admin;

-- Durable, atomically-deduplicated inbound payment-webhook receipt —
-- mirrors 6J §24.3's own INSERT ... ON CONFLICT ... RETURNING pattern
-- exactly (a first draft's UPDATE-against-payment_attempts dedup attempt
-- was not the same atomic "insert once" guarantee). No RLS — mirrors
-- audit.domain_event_outbox's own precedent (5J §077): organization_id
-- is populated only once resolved, post-verification, never trusted from
-- the payload before that.
CREATE TABLE billing.payment_webhook_receipts (
  id                    UUID        NOT NULL DEFAULT gen_uuid_v7(),
  payment_provider      TEXT        NOT NULL,
  provider_event_id     TEXT        NOT NULL,
  received_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processing_status     TEXT        NOT NULL DEFAULT 'RECEIVED',
  payload_hash          CHAR(64)    NULL,
  payment_attempt_id    UUID        NULL REFERENCES billing.payment_attempts(id),
  organization_id       UUID        NULL,
  attempt_count         INTEGER     NOT NULL DEFAULT 0,
  last_error            TEXT        NULL,
  processed_at          TIMESTAMPTZ NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_pwr                PRIMARY KEY (id),
  CONSTRAINT uq_pwr_provider_event UNIQUE (payment_provider, provider_event_id),  -- NOT DEFERRABLE — the atomic dedup gate requires an immediate constraint
  CONSTRAINT chk_pwr_processing    CHECK (processing_status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED')),
  CONSTRAINT chk_pwr_last_error_len CHECK (last_error IS NULL OR length(last_error) <= 2000),
  CONSTRAINT chk_pwr_processed     CHECK ((processing_status IN ('PROCESSED','FAILED')) = (processed_at IS NOT NULL))
);

CREATE INDEX idx_pwr_status  ON billing.payment_webhook_receipts (processing_status, received_at);
CREATE INDEX idx_pwr_attempt ON billing.payment_webhook_receipts (payment_attempt_id) WHERE payment_attempt_id IS NOT NULL;

-- FINAL freeze-gate correction (FB-6K-03/04): app_api's SELECT is removed
-- — this table carries no RLS (above), so a broad app_api SELECT grant
-- would let any tenant session read every organization's provider/event-
-- id/payment-attempt/failure metadata; ordinary tenant endpoints already
-- serve payment state from the RLS-protected payment_attempts table.
-- app_api's raw INSERT is also removed — a compromised/buggy tenant-
-- facing code path could otherwise pre-claim a real provider event ID
-- (poisoning the dedup key) or inject fabricated receipts. Replaced below
-- by a narrow SECURITY DEFINER ingress function accepting only the three
-- fields available BEFORE any tenant/financial identity is known.
GRANT SELECT ON billing.payment_webhook_receipts TO app_worker, app_readonly;

-- FREEZE-gate correction (fourth pass, FREEZE-6K-01): the prior state
-- granted app_platform_admin full SELECT/INSERT/UPDATE/DELETE here. A raw
-- table grant would let a platform-admin session bypass the dedicated
-- app_billing_webhook_ingress path entirely — pre-claim/poison a real
-- (payment_provider, provider_event_id) pair, overwrite processing state
-- or linkage, or DELETE a receipt row outright, rewriting the platform's
-- own webhook ingestion history (security/audit evidence). INSERT/UPDATE/
-- DELETE are removed; SELECT is retained (a narrow, read-only support/
-- incident-response allowance that does not undermine ingress/processing
-- write isolation). No role — app_api, app_billing_webhook_ingress,
-- app_worker, or app_platform_admin — holds DELETE on this table.
GRANT SELECT ON billing.payment_webhook_receipts TO app_platform_admin;

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
  RETURN v_id;  -- NULL means "already recorded" — the caller's own
                -- enqueue-gating logic must treat this exactly like a
                -- zero-row RETURNING result (6J §24.3's discipline).
END;
$$;

-- FINAL-6K-01 correction (third freeze-gate pass): accepting no financial
-- fields does not, by itself, close the dedup-poisoning threat — a caller
-- holding EXECUTE can still call the function at all and consume
-- uq_pwr_provider_event for a real, not-yet-arrived provider event ID
-- before the genuine webhook arrives, causing the real delivery to be
-- silently treated as a duplicate. app_api (general tenant-facing runtime)
-- and app_platform_admin (human/break-glass, not an automated ingress
-- path) are therefore NOT granted EXECUTE here. A new, single-purpose
-- role is introduced instead, LOGIN-only and NOT BYPASSRLS, modeled
-- directly on the app_voice_reconciler precedent (5K §B1, migration
-- 099_5C1): the platform's own verified-webhook-signature ingress path
-- runs as this role and nothing else does.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_billing_webhook_ingress') THEN
    CREATE ROLE app_billing_webhook_ingress LOGIN;
  END IF;
END
$$;
GRANT USAGE ON SCHEMA billing TO app_billing_webhook_ingress;

REVOKE ALL ON FUNCTION billing.fn_record_payment_webhook_receipt(TEXT, TEXT, CHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_record_payment_webhook_receipt(TEXT, TEXT, CHAR)
  TO app_billing_webhook_ingress;
-- app_api and app_platform_admin deliberately hold NO grant on this
-- function (before this pass they both did — see FINAL-6K-01 in §49).
-- app_billing_webhook_ingress otherwise has no other table privilege in
-- this schema: it cannot SELECT payment_attempts, payment_webhook_receipts,
-- or invoices — its only reachable surface is this one function call.

-- Controlled status-transition + linkage path (app_worker-only — these
-- transitions happen only inside async webhook processing, never the
-- synchronous inbound HTTP path). Idempotent for same-terminal-status;
-- rejects terminal->different-terminal.
--
-- FINAL freeze-gate correction (task's own significant finding, folded
-- into FB-6K-05's fix): the original signature accepted
-- p_payment_attempt_id/p_organization_id as direct caller-supplied
-- inputs, written through with only a "don't overwrite once set" guard
-- — unsafe provenance even for a worker/admin-only caller. Corrected: the
-- caller supplies only p_provider_transaction_id (extracted from the
-- verified webhook payload); this function independently RESOLVES the
-- originating payment_attempts row (and, through it, the owning
-- organization) from the platform's own authoritative data. The
-- resolution join also requires the receipt's own payment_provider to
-- match the resolved attempt's payment_provider — a cross-provider
-- linking attempt fails closed rather than silently linking (live-
-- confirmed, §12.8).
CREATE OR REPLACE FUNCTION billing.fn_process_payment_webhook_receipt(
  p_receipt_id                UUID,
  p_new_status                 TEXT,
  p_provider_transaction_id    TEXT DEFAULT NULL,
  p_error                      TEXT DEFAULT NULL
) RETURNS TABLE(resolved BOOLEAN, resolved_payment_attempt_id UUID, resolved_organization_id UUID)
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE
  v_current TEXT; v_receipt_provider TEXT;
  v_already_linked_attempt UUID; v_already_linked_org UUID;
  v_resolved_attempt_id UUID; v_resolved_org UUID;
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

  -- Resolve linkage internally, once. Never resolved from a caller-
  -- supplied attempt/organization id directly.
  v_resolved_attempt_id := v_already_linked_attempt;
  v_resolved_org := v_already_linked_org;
  IF v_resolved_attempt_id IS NULL AND p_provider_transaction_id IS NOT NULL THEN
    SELECT pa.id, i.organization_id INTO v_resolved_attempt_id, v_resolved_org
    FROM billing.payment_attempts pa
    JOIN billing.invoices i ON i.id = pa.invoice_id
    WHERE pa.provider_transaction_id = p_provider_transaction_id
      AND pa.payment_provider = v_receipt_provider;  -- cross-provider linking fails closed
    -- v_resolved_attempt_id staying NULL (unknown transaction
    -- correlation) is not itself an exception — the caller decides the
    -- outcome (typically p_new_status = 'FAILED' with p_error naming
    -- UNKNOWN_TRANSACTION_CORRELATION, §36).
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

-- fn_link_payment_provider_transaction: the sole path linking a local
-- INITIATED row to the provider's real transaction reference once the
-- provider responds. Deliberately a NEW, distinctly-named function
-- rather than an appended parameter on the existing (057_5H.sql)
-- fn_update_payment_status: live-tested and confirmed that appending a
-- new DEFAULT-valued trailing parameter via CREATE OR REPLACE does NOT
-- replace an existing function — PostgreSQL creates a second, separately
-- (and more permissively, PUBLIC-by-default) privileged overload sharing
-- the same name. A distinctly-named function avoids this and leaves
-- fn_update_payment_status completely untouched (confirmed exactly one
-- overload, post-migration). Idempotent for a re-link with the SAME
-- value; rejects a re-link with a DIFFERENT value; rejects linking onto
-- a terminal-state attempt.
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
```

### 12.5 Part D — Commercial Pricing Lifecycle Functions

```sql
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

-- p_metrics JSONB array: [{"metric":"CALL_MINUTES","included_quantity_override":500,
--   "overage_rate_override_amount":3.0000,"overage_rate_override_currency":"INR"}, ...]
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
  v_id UUID; v_agreement_org UUID; v_agreement_plan_id UUID;
  v_pv_plan_id UUID; v_pv_published BOOLEAN; v_account_currency CHAR(3);
  v_next_version INTEGER; v_metric JSONB;
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
-- CORRECTED: refuses to supersede a still-currently-valid ACTIVE version
-- early. If a prior ACTIVE version exists AND the version being activated
-- has a future effective_from, the call is rejected — live-confirmed:
-- the prior version is left completely unchanged, still ACTIVE. If NO
-- prior ACTIVE version exists (the agreement's very first version), a
-- future effective_from activates immediately without issue — live-
-- confirmed — since §13.3's resolution correctly falls back to plan
-- pricing for any period opened before that date. When superseding IS
-- performed, the boundary is exact and half-open: v_prior.effective_to
-- := new.effective_from (no "-1 day" — zero gap, zero overlap, live-
-- confirmed via direct row comparison).
CREATE OR REPLACE FUNCTION billing.fn_activate_commercial_pricing_agreement_version(
  p_organization_id UUID,
  p_agreement_version_id UUID
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql SET search_path = billing, pg_catalog AS $$
DECLARE
  v_agreement_id UUID; v_status TEXT; v_effective_from DATE; v_org UUID; v_prior_id UUID;
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
-- replacement. Uses status_reason (mutable), never mutates the immutable
-- reason column (a first draft attempted to append to `reason`, which
-- fn_cpav_immutability now correctly forbids).
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
```

### 12.6 Part E — Late-Arriving Usage Adjustment Provenance (DEC-6K-04)

```sql
ALTER TABLE billing.billing_adjustments
  ADD COLUMN late_usage_billing_period_id UUID NULL REFERENCES billing.billing_periods(id),
  ADD COLUMN late_usage_metric TEXT NULL,
  ADD COLUMN late_usage_provenance JSONB NULL;
  -- shape: {"plan_version_id": "...", "commercial_pricing_agreement_version_id": "..."|null,
  --          "usage_event_ids": ["...", ...], "quantity": "12.5000",
  --          "unit_price": {"amount": "3.0000", "currency": "INR"}}

CREATE INDEX idx_badj_late_period ON billing.billing_adjustments (late_usage_billing_period_id)
  WHERE late_usage_billing_period_id IS NOT NULL;

-- The sole write path for a late-usage correction. Always
-- adjustment_type = 'MANUAL_CORRECTION'. Mirrors fn_create_billing_
-- adjustment's own validation (086_5H1.sql) without editing that
-- existing function.
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
```

### 12.7 State Machine

```
DRAFT ──(fn_activate_commercial_pricing_agreement_version)──▶ ACTIVE
ACTIVE ──(a newer version activated on/after its own effective_from)──▶ SUPERSEDED  (effective_to set exactly to the new version's effective_from — half-open, no gap, no overlap)
ACTIVE ──(fn_expire_commercial_pricing_agreement_version)──▶ EXPIRED  (no replacement)
```

`SUPERSEDED` and `EXPIRED` are both terminal; financial fields are already frozen at `ACTIVE` (§12.2's trigger). A `DRAFT` version may be freely edited (including its `commercial_pricing_metrics` children) or discarded before activation.

### 12.7a Part F — Exact-Aggregate Call-Minute Billing (FB-6K-06)

A freeze-gate review found a confirmed, live-reproducible defect in DEC-6K-02's own implementation: rounding each call's `CALL_MINUTES` quantity to 4 decimal places *before* summing (the original §22.3 design) is not mathematically equivalent to "exact seconds/60" once many calls are aggregated. Live-reproduced: 1000 one-second calls, each pre-rounded to `0.0167` and summed, total **16.7000** minutes; the true aggregate (`1000/60`, rounded once) is **16.6667** — a real, provable overstatement of the customer's usage.

```sql
ALTER TABLE billing.usage_events
  ADD COLUMN source_quantity_seconds NUMERIC(18,4) NULL;
ALTER TABLE billing.usage_events
  ADD CONSTRAINT chk_ue_source_quantity_seconds CHECK (
    (metric <> 'CALL_MINUTES' OR source_quantity_seconds IS NOT NULL)
    AND (source_quantity_seconds IS NULL OR source_quantity_seconds >= 0)
  );
-- ADD COLUMN/ADD CONSTRAINT on this partitioned parent table apply
-- automatically to every existing and future partition.
```

`quantity` keeps its existing per-row, already-rounded value (audit/display of that single call only — never the billing aggregation input for this metric). `source_quantity_seconds` preserves the exact pre-conversion seconds value; §22.3 specifies the corrected aggregation algorithm (sum exact seconds, round once).

**FINAL-6K-02 correction (third freeze-gate pass):** the constraint as first shipped only forbade a *negative* `source_quantity_seconds` — it left the column nullable even for `CALL_MINUTES` rows, so the exact-aggregation guarantee above depended entirely on the ingestion consumer's own discipline, not a structural DB invariant. The `metric <> 'CALL_MINUTES' OR source_quantity_seconds IS NOT NULL` clause (added this pass) makes the column mandatory specifically — and only — for `CALL_MINUTES`; every other metric is unaffected and may still omit it. No pre-existing rows were affected: migration `102_5H2` has never been applied to a persistent database (§12.8/§49).

### 12.7b Part G — Broader Least-Privilege Hardening

The freeze-gate review's own broader audit mandate, beyond the six items above: every direct `app_api`/`app_worker` DML grant on a billing table was re-inspected for whether the grantee can supply an authoritative financial value. None of the statements below edit a frozen 001–101 file — every one is a `REVOKE` issued by this later, still-unapplied migration (the established `087_5B1`/`096_5B2`/`101_5I1` pattern).

```sql
-- usage_events / cost_entries: app_api's INSERT (050_5H/051_5H) is
-- unnecessary — usage ingestion and cost recording are exclusively
-- app_worker responsibilities (§22.1/§35); closes "usage-event forgery"
-- (§40) at the DB layer, not merely the "no endpoint exists" layer.
REVOKE INSERT ON billing.usage_events FROM app_api;
REVOKE INSERT ON billing.cost_entries FROM app_api;

-- invoice_lines / tax_lines: app_api's INSERT (054_5H) is unnecessary —
-- line creation happens exclusively inside the invoice-generation
-- worker's own transaction (§26.2); no 6K tenant-facing endpoint ever
-- creates a line.
REVOKE INSERT ON billing.invoice_lines FROM app_api;
REVOKE INSERT ON billing.tax_lines FROM app_api;

-- credits / credit_ledger_entries: 5H's OWN stated security model (§20
-- of the 5H schema document) already declares credits are "created only
-- via SECURITY DEFINER fn_billing_apply_credit" — but the executed
-- grants (053_5H) contradicted that stated intent by giving app_worker
-- direct INSERT on both tables. Reconciled here with 5H's own
-- already-declared intent, not a new restriction invented from nothing.
REVOKE INSERT ON billing.credits FROM app_worker;
REVOKE INSERT ON billing.credit_ledger_entries FROM app_api, app_worker;

-- refunds: app_api's INSERT (055_5H) directly contradicted §31.2's own
-- "no tenant-facing refund creation in V1" design. app_worker's grant is
-- retained as the path 6M's future admin/support refund surface uses
-- (fn_validate_refund_amount's existing trigger remains the amount guard).
REVOKE INSERT ON billing.refunds FROM app_api;
```

### 12.8 Migration Plan Entry and Real Validation Results

```
102_5H2
    down_revision = '101_5I1'  (new revision in its first pass; amended in
                                place a second time for the freeze-gate
                                fixes, then a third time for the FINAL-6K-01/
                                02 fixes below — never applied to a
                                persistent database at any point, confirmed
                                before each amendment)
    purpose: Parts A-G above — commercial pricing agreements (with NO raw
             DML for any role, including app_platform_admin, Parts A/B);
             payment-flow correctness (provider_transaction_id nullable,
             payment_method_kind, payment_webhook_receipts with ingress
             restricted to the dedicated app_billing_webhook_ingress role,
             fn_create_payment_attempt as the sole app_api-callable billing
             function, internally-deriving webhook-receipt linkage);
             exact-aggregate call-minute billing, now DB-mandatory for
             CALL_MINUTES (Part F); late-usage adjustment provenance
             (Part E); broader least-privilege hardening across 7 other
             billing tables (Part G)
    transaction: standard (no CONCURRENTLY; every new column is NULL-default
                 or constant-default; every DROP NOT NULL is metadata-only)
```

**Downgrade:** `NotImplementedError`, per the established 5K forward-only convention (full manual-reversal SQL documented in `102_5H2.py`'s own docstring for disaster-recovery reference; not exercised in this pass, since forward-only is this codebase's own stated policy since `001_5B`).

**Live validation results, first and second passes (PostgreSQL 18.6, genuinely fresh disposable instances); the third pass's own results follow immediately below:**

| Check | Result |
|---|---|
| Fresh `001 → 102` (both passes, final file) | **PASS**, exit 0 |
| Incremental `101 → 102` (separate database, both passes) | **PASS**, exit 0 |
| `alembic heads` / `current` | Single head, `102_5H2 (head)` |
| `alembic history` | 102 lines, linear, no branch |
| Cross-tenant RLS (Org B reads Org A's agreement/version/metrics) | **PASS** — 0 rows |
| `app_api` cannot `INSERT`/`EXECUTE` any pricing-write path | **PASS** — permission denied |
| `app_worker` legitimate create → draft → activate | **PASS** |
| **FB-6K-01/02:** Raw `UPDATE`/`DELETE` on lifecycle fields, even as `app_platform_admin` | **PASS** — `permission denied` (grant removed entirely, second pass — stronger than the first pass's trigger-only rejection) |
| Metric row `INSERT`/`UPDATE`/`DELETE` on `ACTIVE` version | **PASS** — all three rejected |
| Parent agreement identity immutability | **PASS** |
| Composite-FK cross-org rejection (both under RLS and under `BYPASSRLS`) | **PASS** — two independent layers, both confirmed |
| Plan-version consistency trigger | **PASS** — both branches |
| Future-dated activation with a prior ACTIVE version | **PASS** — rejected, prior version unchanged |
| Future-dated activation with no prior ACTIVE version | **PASS** — succeeds |
| Half-open supersede boundary exactness | **PASS** — zero gap, zero overlap |
| Historical resolution of a `SUPERSEDED` version | **PASS** — resolves correctly, no artificial `ACTIVE`-only restriction |
| **FB-6K-03/04:** `app_api` `SELECT`/`INSERT` on `payment_webhook_receipts` | **PASS** — both `permission denied`; `fn_record_payment_webhook_receipt` (callable only by `app_billing_webhook_ingress` — see FINAL-6K-01/FREEZE-6K-01 rows below, ingress-safe fields only) works and dedups |
| **FB-6K-05:** `app_api` raw `INSERT` on `payment_attempts` | **PASS** — `permission denied`; `fn_create_payment_attempt` derives amount (exact invoice balance)/currency/provider server-side, rejects duplicate non-terminal attempts, cross-tenant invoices, and missing tenant context |
| `fn_link_payment_provider_transaction` — link, idempotent re-link, rejected different-value re-link, rejected duplicate real value | **PASS**, all sub-cases |
| `payment_method_kind` governed-vocabulary rejection | **PASS** |
| **Significant (linkage):** `fn_process_payment_webhook_receipt` resolves attempt/org from `provider_transaction_id`, cross-provider linkage fails closed | **PASS** — resolved id matches the real attempt exactly; cross-provider resolves NULL, `FAILED`/`UNKNOWN_TRANSACTION_CORRELATION` |
| Webhook-receipt state machine | **PASS** — idempotent + illegal-transition rejection |
| Usage-idempotency collision reproduced, then fixed | **PASS** (bug reproduced; fix confirmed) |
| **FB-6K-06:** 1000×1s calls vs. 1×1000s call; 100×7s calls vs. 1×700s call | **PASS** — buggy `SUM(quantity)` = 16.7000 (bug reproduced exactly); fixed `SUM(source_quantity_seconds)/60` = 16.6667 = single-call figure both cases |
| Quota semantics (`overage_allowed = hard_limit IS NULL`) | **PASS** |
| Late-usage adjustment — provenance + original-invoice-unchanged | **PASS** |
| Invoice-line provenance CHECK | **PASS** |
| **Broader audit:** `app_api` `INSERT` denied on `cost_entries`/`invoice_lines`/`tax_lines`/`refunds`; `app_worker` `INSERT` denied on `credits`/`credit_ledger_entries` | **PASS**, all; `fn_billing_apply_credit` unaffected |
| `SECURITY DEFINER` inventory, all functions (pre-third-pass state) | **PASS** — `fn_create_payment_attempt`/`fn_record_payment_webhook_receipt` were the only two `app_api`-granted billing functions; this second reference is now superseded — see the third-pass rows below (**FINAL-6K-01**) |
| `fn_update_payment_status` (057_5H, frozen) still exactly one overload | **PASS** |
| Full original 28-test suite re-run verbatim against the corrected file | **PASS** — zero true regressions; new denials occur exactly where this pass's hardening intentionally narrowed access |

**Third-pass live validation (PostgreSQL 18.6, genuinely fresh disposable instance, `.tmp_pgdata_6kf2`), closing the two findings a further independent freeze-gate review made against the state above:**

| Check | Result |
|---|---|
| Fresh `001 → 102` (third-pass file) | **PASS**, exit 0 |
| Incremental `101 → 102` (separate database) | **PASS**, exit 0 |
| `app_billing_webhook_ingress` role sanity (`LOGIN=true`, `BYPASSRLS=false`) | **PASS** |
| **FINAL-6K-01:** grant matrix on `fn_record_payment_webhook_receipt` — `app_api=false`, `app_worker=false`, `app_platform_admin=false`, `app_billing_webhook_ingress=true`, `PUBLIC=false` | **PASS** |
| **FINAL-6K-01:** `app_api` calls the ingress function | **PASS** — `permission denied` (closes the dedup-poisoning path) |
| **FINAL-6K-01:** `app_api` `SELECT`/`INSERT` on the table directly (regression) | **PASS** — both `permission denied`, unaffected |
| **FINAL-6K-01:** `app_worker` calls the ingress function | **PASS** — `permission denied` (too broad, per rationale) |
| **FINAL-6K-01:** `app_platform_admin` calls the ingress function | **PASS** — `permission denied` (mirrors `app_voice_reconciler` precedent) |
| **FINAL-6K-01:** `app_billing_webhook_ingress` calls it — first delivery + duplicate | **PASS** — first call returns a UUID, duplicate returns `NULL` |
| **FINAL-6K-01:** `app_billing_webhook_ingress` has no other table privilege (`payment_attempts`/`payment_webhook_receipts`/`invoices` `SELECT`) | **PASS** — all `false` |
| **FINAL-6K-02:** `CALL_MINUTES` with `source_quantity_seconds = NULL` | **PASS** — `chk_ue_source_quantity_seconds` violation |
| **FINAL-6K-02:** `CALL_MINUTES` with `source_quantity_seconds = -1` | **PASS** — constraint violation |
| **FINAL-6K-02:** `CALL_MINUTES` with `source_quantity_seconds = 127` | **PASS** — succeeds |
| **FINAL-6K-02:** non-`CALL_MINUTES` metric with `source_quantity_seconds = NULL` | **PASS** — succeeds (constraint is `CALL_MINUTES`-scoped only, no over-broad restriction) |
| **FINAL-6K-02:** aggregation equivalence reconfirmed under the now-mandatory regime (1000×1s vs. 1×1000s; 100×7s vs. 1×700s) | **PASS** — 16.6667=16.6667; 11.6667=11.6667 |
| Regression: `app_api` `INSERT` on `usage_events`, `payment_attempts` (FB-6K-05) | **PASS** — both `permission denied`, unaffected |
| Regression: `app_platform_admin` `EXECUTE` on `fn_create_commercial_pricing_agreement` | **PASS** — grant intact (call reaches the function's own business-rule check) |
| `SECURITY DEFINER` inventory, all functions (state after the third pass; the table-DML story below is what the fourth pass corrects) | **PASS** — `fn_create_payment_attempt` remains `app_api`-granted; `fn_record_payment_webhook_receipt` is now granted **only** to `app_billing_webhook_ingress` (`app_api` and `app_platform_admin` grants removed this pass); every other function remains worker/admin-only |

**Fourth-pass live validation (PostgreSQL 18.6, genuinely fresh disposable instance, `.tmp_pgdata_6kfreeze`), closing one further blocker (a raw-table-DML path the third pass's own function-`EXECUTE` fix did not close) plus a documentation-consistency blocker and an evidence-preservation gap a further independent freeze-gate review found against the state above:**

| Check | Result |
|---|---|
| Fresh `001 → 102` (fourth-pass file) | **PASS**, exit 0 |
| Incremental `101 → 102` (separate database) | **PASS**, exit 0 |
| Final checksum vs. `MIGRATION_MANIFEST.md` row 102 | **Match** — `3ea497b0a0727cc39c0ef0d4c0781f21139727aa6959198d788f48ee85dd7259`, 82365 bytes |
| **FREEZE-6K-01:** grant matrix on `payment_webhook_receipts` — `app_api`/`app_billing_webhook_ingress` all four verbs `false`; `app_worker`/`app_platform_admin` `SELECT=true`, `INSERT`/`UPDATE`/`DELETE=false` | **PASS** |
| **FREEZE-6K-01:** `app_platform_admin` direct `INSERT`/`UPDATE`/`DELETE` | **PASS** — all three `permission denied` |
| **FREEZE-6K-01:** `app_platform_admin` direct `SELECT` (intentionally retained) | **PASS** — succeeds, returns the seeded row |
| Regression: `app_api`/`app_billing_webhook_ingress`/`app_worker` raw-DML boundaries on the table | **PASS** — unaffected, all previously-denied paths still denied, `app_worker` `SELECT` still succeeds |
| Positive controlled path: trusted ingress creates + dedups; `app_worker` links + transitions via the controlled function, resolving attempt/org internally | **PASS** — `linkage_correct = true` |
| Regression: `app_api` direct `INSERT` on `payment_attempts` denied; guarded `fn_create_payment_attempt` succeeds | **PASS** |
| Regression: `CALL_MINUTES` NULL/negative rejected, valid accepted, 1000×1s = 1×1000s aggregation | **PASS** — 16.6667=16.6667 |
| Regression: commercial-pricing raw `UPDATE`/`DELETE` denied for `app_platform_admin`; controlled create/version/activate succeeds end to end | **PASS** |
| Regression: `fn_create_late_usage_billing_adjustment`/`fn_create_payment_attempt` grants unaffected | **PASS** |
| `SECURITY DEFINER` inventory, all functions (current, post-fourth-pass) | **PASS** — `fn_record_payment_webhook_receipt` grantees: `{app_billing_webhook_ingress}` only (plus the owning role); every other function's grantee set unchanged from the third pass |

Full per-test narrative, raw transcripts, and the complete blocker-closure table (all four passes): `docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`.

---

## 13. Pricing Resolution — The One Canonical Algorithm

### 13.1 Precedence

```
1. Active organization-specific agreement price (pinned per billing period, never "current")
       ↓ if absent
2. Subscription's pinned PlanVersion price
```

**Never** "the current `PlanVersion`" if the subscription is pinned to an older one, and **never** "the current `ACTIVE` agreement version" for a historical period — every resolution is anchored to `billing_periods`' own two pinned FKs (`plan_version_id`, `commercial_pricing_agreement_version_id`), set once at period-open time and never re-read afterward.

### 13.2 Per-Field Resolution

```
effective_base_subscription_price =
    agreement_version.base_price_override_{amount,currency}   -- if agreement pinned AND override IS NOT NULL
    OR plan_version.base_price_{amount,currency}                -- otherwise

effective_included_quantity(metric) =
    commercial_pricing_metrics.included_quantity_override        -- if agreement pinned AND a row exists for this metric AND override IS NOT NULL
    OR plan_prices.included_quantity                              -- otherwise (plan_prices row for this metric on the pinned plan_version)
    OR 0                                                            -- if no plan_prices row exists for this metric either (metric untracked-for-pricing, §20)

effective_overage_rate(metric) =
    commercial_pricing_metrics.overage_rate_override_{amount,currency}  -- if agreement pinned AND override IS NOT NULL
    OR plan_prices.overage_rate_{amount,currency}                        -- otherwise
    OR NULL                                                                -- if neither exists → metric is not billable (§20)
```

Each of the three fields resolves **independently** — an agreement may override the base price but not `CALL_MINUTES`'s rate, in which case `CALL_MINUTES` still falls through to the plan's own `plan_prices` row. This is a field-level override, not an all-or-nothing agreement replacement of the plan.

### 13.3 Billing-Period Resolution Algorithm (Invoked at Period-Open Time, §21.2)

```
1. Read subscription.plan_version_id                         → the plan_version this org is currently pinned to.
2. Read subscription.commercial_pricing_agreement_version_id → NULL, or the agreement version currently ACTIVE
                                                                  as of subscription's last plan-change/renewal check.
3. Re-validate at period-open time (not merely trusted from the subscription row):
   SELECT id FROM billing.commercial_pricing_agreement_versions
   WHERE organization_id = $org_id AND status = 'ACTIVE'
     AND effective_from <= $period_start
     AND (effective_to IS NULL OR effective_to > $period_start)
   -- 0 rows → this period pins commercial_pricing_agreement_version_id = NULL (falls back to plan pricing)
   -- 1 row  → this period pins that row's id (uq_cpav_one_active guarantees at most one)
4. INSERT billing_periods with both plan_version_id (from step 1) and
   commercial_pricing_agreement_version_id (from step 3) — both pinned, both immutable
   for the life of that billing_periods row.
```

Step 3's independent re-check (rather than trusting `subscriptions.commercial_pricing_agreement_version_id` verbatim) is what makes a billing period crossing an agreement-version boundary correct without special-casing: each new period re-derives its own pin from the agreement's state *as of that period's own start date*, so a period that opens after `fn_activate_commercial_pricing_agreement_version` moved v1→v2 correctly pins v2, while an already-open, not-yet-closed period keeps whatever it pinned at its own open time — it is never retroactively repriced by a later activation (task §13.8, §89).

### 13.4 Campaign Double-Charge Protection (Usage ≠ Billing Charge)

Per task §6/§88: recording a `CAMPAIGN_CALLS` usage event and a `CALL_MINUTES` usage event for the same underlying call is correct and expected (§22's usage-ingestion table — a campaign call genuinely emits both facts). Whether either fact becomes a **monetary** invoice line is decided **only** by §13.2's `effective_overage_rate(metric)` resolution at invoice-generation time (§25), never by the act of recording usage:

| Effective pricing has... | `CALL_MINUTES` charged? | `CAMPAIGN_CALLS` charged? |
|---|---|---|
| Only `CALL_MINUTES` priced (`plan_prices`/agreement row with a non-null overage rate) | Yes | No — usage recorded, `quantity_used` visible in `GET /billing/usage`, zero monetary line |
| Only `CAMPAIGN_CALLS` priced | No | Yes |
| Both priced | Yes | Yes |
| Neither priced | No (usage recorded, zero charge) | No (usage recorded, zero charge) |

This is enforced structurally: invoice-line generation (§25.3) iterates `usage_records` and, for each metric, calls `effective_overage_rate(metric)` — a `NULL` result means **no `USAGE`/`OVERAGE` invoice line is created for that metric in that period**, full stop. There is no code path that charges a metric merely because it has a nonzero `quantity_used`.

---

## 14. Pricing Provenance and Snapshotting

Per task §27/§68/§89: an invoice must never recompute from mutable current pricing after the fact. Every `invoice_lines` row of type `BASE_FEE`, `USAGE`, or `OVERAGE` snapshots, at `INSERT` time: `unit_price_amount`/`unit_price_currency` (already existing 5H columns), `quantity`, `metric` (existing), plus the three new columns from §12.3 — **field-level**, not one vague label (task §16's own explicit requirement):

- `unit_price_source` (`'PLAN'` or `'AGREEMENT'`) — which source produced the monetary rate actually charged on *this* line (the base price for a `BASE_FEE` line; the overage rate for a `USAGE`/`OVERAGE` line).
- `included_quantity_source` (`'PLAN'`, `'AGREEMENT'`, or `NULL`) — which source produced the included-quantity allowance that determined this `OVERAGE` line's billable quantity (`NULL` where not applicable, e.g. `BASE_FEE`/`CREDIT`/`TAX`/`ADJUSTMENT` lines).
- `commercial_pricing_agreement_version_id` — the exact version, populated whenever *either* source above is `'AGREEMENT'`; `NULL` when both are plan-sourced. A contradictory combination (a source claims `'AGREEMENT'` with no linked version, or a version linked with both sources `'PLAN'`) is rejected by `chk_il_pricing_provenance` at the database layer — not merely a documentation promise (live-confirmed, §12.8).

Because `invoice_lines` keeps its existing `REVOKE UPDATE, DELETE` and `commercial_pricing_agreement_version_id`/`base_price_override_amount` are themselves financially immutable once a version leaves `DRAFT` (§12.7), a fully reconstructed answer to "why did this customer pay this price" is always available by joining one finalized invoice line back through its own pinned FKs — never through "whatever the agreement/plan says today." This directly answers all four provenance questions task §16 requires: which source produced the included quantity, which source produced the monetary unit price, which `PlanVersion` was involved (via the invoice's `billing_period_id → plan_version_id`, already existing), and which `CommercialPricingAgreementVersion` was involved (this line's own FK).

**Provenance chain, concretely:** `invoice_line.commercial_pricing_agreement_version_id` (if not NULL) → that row's own `base_price_override_amount`/`commercial_pricing_metrics` children (immutable) → `base_plan_version_id` → that `plan_versions` row (immutable once published) → `plan_prices` (for any metric the agreement didn't override). Every step in this chain is either a frozen historical FK or an immutable row. No step ever re-reads "the current" anything.

**Historical resolution never requires the pinned version to still be `ACTIVE` (task §14):** the read path above is a plain FK traversal — it does not, and must not, filter on `commercial_pricing_agreement_versions.status`. A `billing_period`/invoice pinned to a version that has since moved to `SUPERSEDED` or `EXPIRED` resolves identically to one pinned to a still-`ACTIVE` version; live-confirmed in `102_5H2`'s own validation pass (a period pinned to a now-`SUPERSEDED` version correctly reads back its original `base_price_override_amount`). The `PRICING_AGREEMENT_NOT_ACTIVE` error code (§36) applies **only** to §13.3's period-open *new-pinning* resolution step — never to reading an already-pinned historical FK.

---

## 15. Billing Account APIs

### 15.1 `GET /api/v1/billing/account`

- **Purpose:** the caller's organization's billing account.
- **Permission:** `billing:read`.
- **Response `200`:** `id`, `billing_status`, `currency`, `billing_contact_name`, `billing_contact_email`, `credit_balance` (Money), `grace_period_ends_at` (nullable), `created_at`. Never exposes `payment_method_ref` values in bulk here (those live under `GET /billing/payments`, per-attempt).
- **Errors:** `404 BILLING_ACCOUNT_NOT_FOUND` (should not occur for any organization past provisioning — surfaced defensively).

### 15.2 `PATCH /api/v1/billing/account`

- **Purpose:** update `billing_contact_name`/`billing_contact_email` only.
- **Permission:** `billing:manage`.
- **Body:** `{"billing_contact_name"?: string, "billing_contact_email"?: string}` — 6A §7.5 null-vs-absent semantics apply.
- **Explicitly rejected fields:** `currency` (immutable per `INV-BILL-01`/`fn_ba_currency_immutable`, 5H §7 — a `400 VALIDATION_ERROR` on any attempt, not a silent ignore), `billing_status`, `credit_balance` (both server-derived/system-transitioned only).
- **Idempotency:** not required (safe field update, no duplicate-side-effect risk).
- **Audit:** `BILLING_ACCOUNT_CONTACT_UPDATED` (new governed vocabulary value, §45.3).

### 15.3 No Tenant-Facing Suspend/Reactivate

Per task §8's own instruction to verify Phase 5H lifecycle and 6B permissions before assuming these exist: `billing_accounts.billing_status` (`ACTIVE|PAST_DUE|SUSPENDED|CLOSED`) is a **system/worker-driven** state machine — `PAST_DUE`→`SUSPENDED` fires automatically on grace-period expiry (4F §7.1, §19), and recovery fires automatically on payment success. This is a materially different concept from `organization:suspend` (6C — an `OWNER`-only, immediate, manual organization-wide suspension, unrelated to payment state). **No `POST /billing/account/suspend` or `.../reactivate` tenant-facing endpoint is designed here.** A manual override (fraud, collections, goodwill reactivation) is a platform-admin/support action, handed to 6M (§41) — 6K exposes only the read-only `billing_status` field so tenants can see their own account's state, never a self-service mutation of it.

### 15.4 Billing Eligibility Matrix (DEC-6K-03, ACCEPTED, FINAL)

Per task §31: a blanket rejection of every API call while `SUSPENDED` is explicitly forbidden — a suspended tenant must remain able to see their own billing state and cure the debt.

| `billing_status` | New billable operations (6D calls, 6H campaign dispatch, etc.) | `GET /billing/account`, `/invoices`, `/payments`, `/summary`, `/periods` | `POST /billing/invoices/{id}/payment-intent` |
|---|---|---|---|
| `ACTIVE` | Allowed | Allowed | Allowed |
| `PAST_DUE` (within grace) | Allowed (task/DEC-6K-03 — grace means "service continues") | Allowed | Allowed |
| `SUSPENDED` | **Denied**, before consumption — the initiating context (6D/6H) checks eligibility *before* placing the call/dispatch, never charges for a rejected operation | **Allowed** — read/recovery access is explicitly preserved | **Allowed** — this is precisely how a suspended tenant cures the debt |
| `CLOSED` | Denied | Allowed (historical read only) | Denied — no invoice can newly become payable on a closed account |

### 15.5 Reusable Billing Eligibility Guard (Internal Contract)

Per task §31's own requirement for "a reusable billing eligibility guard for other bounded contexts": 6D/6H (and any future billable-operation-initiating context) check eligibility by reading `billing.billing_accounts.billing_status` for the caller's own tenant — already RLS-scoped, already `SELECT`-granted to `app_worker` (5H §48, unchanged) — no new database object is required for this. The check is: `billing_status IN ('ACTIVE', 'PAST_DUE')` → eligible; `billing_status IN ('SUSPENDED', 'CLOSED')` → **`403 BILLING_ACCOUNT_SUSPENDED`** (§36), raised by the initiating context's own request handler, before any usage-generating side effect occurs. This is a plain read, not a new `SECURITY DEFINER` function — it carries no elevated privilege and needs none.

---

## 16. Plan Catalog APIs

### 16.1 `GET /api/v1/billing/plans`

- **Purpose:** browse the platform's published, active commercial plans (for self-service subscription/upgrade decisions).
- **Permission:** `organization:read` (broadest role bar already possessed by every seeded role including `VIEWER` — matches the DB grant model, 5H §24: `plans`/`plan_versions`/`plan_prices` carry no RLS and are `GRANT SELECT`-broad to `app_api`; gating behind `billing:read` would be stricter than the DB layer itself and would hide the catalog from a `VIEWER` evaluating the product, which is not the intent).
- **Filter:** only `plans.is_active = TRUE` and the plan's current published `plan_versions.is_published = TRUE` row are ever returned — an unpublished/draft version, or a superseded (non-current) published version, is never listed here (it remains reachable only through a specific subscription's own pin, §18).
- **Response `200`:** paginated list of `{id, name, description, current_version: {id, version_number, billing_cycle, base_price: Money, effective_from}}`. Per-metric `plan_prices` are on the detail endpoint only (§16.2), to keep the list payload small (6A §15).
- **What tenants never see here:** any other organization's `CommercialPricingAgreement` (never listed on this catalog endpoint at all — an agreement is not a "plan" a tenant browses, task §70), unpublished plan versions, `is_active = FALSE` plans.

### 16.2 `GET /api/v1/billing/plans/{plan_id}`

- **Permission:** same as §16.1.
- **Response `200`:** adds the full `plan_prices` breakdown for the current published version: `[{metric, unit_label, included_quantity, overage_rate: Money | null}]`. `overage_rate: null` for a metric that is tracked but not priced under this plan (§20) — the response is explicit about this rather than omitting the metric.
- **Errors:** `404 RESOURCE_NOT_FOUND` if the plan doesn't exist or `is_active = FALSE`.

### 16.3 No Tenant Write Access

Per task §9: ordinary tenants never create plans, publish plan versions, or change global prices — 5H's own grants already enforce this at the DB layer (`app_api` has `SELECT` only on `plans`/`plan_versions`/`plan_prices`; only `app_platform_admin` can `INSERT`/`UPDATE`). No mutating endpoint is designed here; plan/pricing administration is 6M's (§41).

---

## 17. Commercial Pricing Agreement — Domain Contract and Admin Handoff

Per task §10/§78: 6K defines the billing-domain service contract (§12's functions, §13's resolution algorithm) but does **not** design the platform-admin REST surface for creating/activating/expiring agreements — that surface belongs to future Phase 6M, using a `PlatformAdminOnly` actor-type authorization pattern (6B §18.2/§18.3 — an actor-type check, not an RBAC permission string, exactly like break-glass) rather than a per-organization RBAC permission, since agreement administration is inherently cross-tenant (one commercial team manages agreements for many organizations).

**What 6K does specify, for 6M to build against:**

| 6M REST responsibility (not built here) | Calls (already specified, §12.5) |
|---|---|
| Create a commercial relationship for an org | `billing.fn_create_commercial_pricing_agreement` |
| Draft a new negotiated version | `billing.fn_create_commercial_pricing_agreement_version` |
| Activate a drafted version | `billing.fn_activate_commercial_pricing_agreement_version` |
| End a relationship early, no replacement | `billing.fn_expire_commercial_pricing_agreement_version` |
| List/view agreements (cross-tenant) | Plain `SELECT` — `app_platform_admin` bypasses RLS (5B §"Platform admin" — `BYPASSRLS`), all cross-tenant reads/writes audited separately per 5B's own stated policy |

**What 6K *does* expose to the tenant, narrowly (read-only, own-org):** the tenant's own `GET /billing/subscription` response (§18.1) includes a `pricing_source: "PLAN" | "AGREEMENT"` field and, when `"AGREEMENT"`, the agreement version's `contract_reference` and `effective_from`/`effective_to` — so an enterprise customer's own finance team can see *that* they are on negotiated terms and reference their own contract, without exposing the negotiation mechanics, other tenants' agreements, or platform pricing strategy. No endpoint lets a tenant enumerate `commercial_pricing_agreement_versions` history or see un-redacted rate figures beyond what already appears on their own invoices/quota responses (§21, §24).

**Authority boundary restated (task §69), strengthened by the freeze-gate pass:** no tenant `OWNER`/`ADMIN`/`BILLING_ADMIN` permission — present or future — grants access to §12.5's functions. `billing:manage` (the broadest tenant billing permission that exists) never authorizes a call to any `fn_*commercial_pricing*` function; this is enforced by the grant list itself (`app_worker`/`app_platform_admin` only, §12.5), not merely by an application-layer permission check that could be misconfigured — the DB will reject an `app_api`-role call to any of these four functions regardless of what the application layer intended. As of the freeze-gate remediation pass (§12.2/§12.8), this boundary is stronger still: `app_platform_admin` itself holds **no raw `INSERT`/`UPDATE`/`DELETE`** on any of the three commercial-pricing tables either — even a platform-admin actor with a live database session cannot activate, supersede, expire, or delete a commercial term via raw SQL; the four guarded functions are the *only* write path for anyone, full stop (live-confirmed, `docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §15).

---

## 18. Subscription Lifecycle APIs

### 18.1 `GET /api/v1/billing/subscription`

- **Permission:** `billing:read`.
- **Response `200`:**
```json
{
  "data": {
    "id": "01930000-...",
    "status": "ACTIVE",
    "plan": { "id": "...", "name": "Growth", "version_number": 3 },
    "pricing_source": "AGREEMENT",
    "commercial_agreement": {
      "contract_reference": "MSA-2026-0417",
      "effective_from": "2026-04-01",
      "effective_to": null
    },
    "current_period_start": "2026-08-01",
    "current_period_end": "2026-09-01",
    "trial_ends_at": null,
    "scheduled_change": null
  },
  "meta": { "request_id": "..." }
}
```
`commercial_agreement` is `null` when `pricing_source = "PLAN"`. `scheduled_change`, when present, is `{"new_plan": {...}, "effective_at": "..."}` (§19.2).

### 18.2 `POST /api/v1/billing/subscription`

- **Purpose:** create the organization's first subscription (one-time; a `CANCELLED` subscription is terminal per `INV-BILL-06`/`fn_sub_cancelled_terminal`, so a former subscriber creates a genuinely new row, not a reactivation of the old one).
- **Permission:** `billing:manage`.
- **Idempotency-Key:** required (task §55 — subscription create is a dangerous-duplicate-effect POST).
- **Body:** `{"plan_id": "...", "billing_cycle"?: "MONTHLY" | "ANNUAL"}`. The server resolves `plan_id` → its current published `plan_versions` row server-side (client never supplies a `plan_version_id` directly — task §51) and re-checks §13.3's agreement lookup so a pre-existing `ACTIVE` `CommercialPricingAgreement` (created for this org ahead of their first subscription, e.g. during enterprise onboarding) is picked up on the very first period.
- **Errors:** `409 SUBSCRIPTION_ALREADY_ACTIVE` (partial unique index `uq_sub_org_active` already guarantees at most one `TRIAL`/`ACTIVE` row — the API surfaces the DB's own guarantee, not a redundant pre-check race), `404 PLAN_NOT_FOUND`, `404 PLAN_VERSION_NOT_AVAILABLE` (plan exists but has no published version).
- **Response `201`:** the created subscription (§18.1 shape). **Audit:** `SUBSCRIPTION_CREATED` (synchronous, per §45.1). **Domain event:** `subscription.changed` (outbox, §45).

### 18.3 `POST /api/v1/billing/subscription/change-plan`

- **Permission:** `billing:manage`.
- **Idempotency-Key:** required.
- **Body:** `{"plan_id": "..."}`.
- **Semantics — reused verbatim from 4F/5H, not re-decided here (§19):**
  - **Upgrade** (new plan's `base_price_amount` under the *currently effective* pricing — agreement-aware, §13.2 — is higher than the current one): applied **immediately**. Modelled, per 4F §9.2, as cancel-current + create-new within one unit of work (never a mutation of the existing `subscriptions` row's `plan_version_id` in place, since `billing_periods` already open under the old pin must remain pinned to it). A prorated credit for the unused portion of the current period is issued via `fn_billing_apply_credit` (5H §53) for the current plan's remaining days, computed at the *currently effective* base price (agreement-aware).
  - **Downgrade:** scheduled via `subscriptions.scheduled_change_plan_version_id`/`scheduled_change_effective_at` (5H's own existing columns, `chk_sub_scheduled`), applied by the renewal worker at `current_period_end` (§18.4). No proration (5H ODD-5H-02, unresolved upstream — carried forward, not decided here).
  - **Agreement behavior across a plan change (task §13.3/§13.6):** if the target plan differs from the agreement's `base_plan_id`, the agreement no longer applies from the change's effective date forward — the new subscription/period resolves pricing from the new plan alone (`commercial_pricing_agreement_version_id` pin resolves to `NULL` at the next period-open, §13.3, since no agreement version references that plan). If the target plan **is** the agreement's base plan (e.g. upgrading within the same negotiated family to a newer published version of it), the agreement's currently `ACTIVE` version continues to apply, re-validated against the new `plan_version_id` exactly as §12.5's function already validates plan/version consistency at creation time — no special-case code path, since §13.3's per-period re-derivation already handles this uniformly.
- **Response `200`:** for an immediate upgrade, the new subscription (§18.1 shape) plus `proration_credit: Money`. For a scheduled downgrade, the current subscription with `scheduled_change` populated.
- **Errors:** `409 PLAN_CHANGE_NOT_ALLOWED` (e.g. target plan not active/published), `404 SUBSCRIPTION_NOT_FOUND`, `409 SUBSCRIPTION_CANCELLED`.

### 18.4 `POST /api/v1/billing/subscription/cancel`

- **Permission:** `billing:manage`.
- **Idempotency-Key:** required.
- **Body:** `{"reason"?: string}`.
- **Semantics:** end-of-period cancellation (4F §7.1 — `ACTIVE --> CANCELLED: CancelSubscription (end of period)`), not immediate service termination — `subscriptions.cancelled_at` is set now, `status` moves to `CANCELLED` at `current_period_end` via the renewal worker (mirrors the existing `fn_sub_cancelled_terminal` trigger's own "terminal" enforcement — once `CANCELLED`, no reactivation, only a new subscription per `INV-BILL-06`).
- **Response `200`:** the subscription with `cancelled_at` populated. **Audit:** `SUBSCRIPTION_CANCELLED` (synchronous). **Domain event:** `subscription.changed`.

---

## 19. Plan Change Semantics — Full Consequence Table

| Aspect | Rule | Source |
|---|---|---|
| Upgrade effective date | Immediate | 4F §9.2 |
| Upgrade pricing pin | New `plan_version_id` (and re-resolved agreement pin) on a *new* `billing_periods` row opened now | 5H ADR-5H-005 |
| Upgrade proration | Credited via `fn_billing_apply_credit`, `credit_type = 'PRORATION_CREDIT'` | 5H §14.2 |
| Downgrade effective date | Scheduled, next period boundary | 4F §7.1 |
| Downgrade proration | **Not defined upstream — ODD-5H-02, carried forward, not decided by 6K** | 5H §31 |
| Quota reseeding | `quota_configs` reseeded from the new (or newly-pinned) `plan_prices`/`commercial_pricing_metrics` at the same transaction that opens the new period | 5H §13 |
| Credits | Unaffected by a plan change except the proration credit itself; existing credit balance carries forward | 5H §14 |
| Invoice consequences | The just-closed period's invoice (if already generated) is unaffected — immutable, §44 | INV-BILL-02 |
| Idempotency | `Idempotency-Key` required on both `change-plan` and `cancel` | §55 |
| Audit | `SUBSCRIPTION_PLAN_CHANGED` (immediate upgrade or downgrade-scheduled alike — one governed value covers both, per the existing vocabulary, §45.3) | 5J §14.3 |
| Outbox event | `subscription.changed` | §45.1 |
| Published `PlanVersion` immutability | Never touched by a plan change — a change always *points* the subscription at a different, already-published version; it never edits one | INV-BILL-05 |

---

## 20. Billing Period APIs

### 20.1 `GET /api/v1/billing/periods`

- **Permission:** `billing:read`. Cursor-paginated (6A §14), default sort `period_start DESC`.
- **Response `200`:** `[{id, period_start, period_end, status, timezone, invoice_id | null}]`. No internal worker state (`invoice_generated_at` raw timestamp, advisory-lock details) is exposed — only `status` (`OPEN`/`CLOSED`) and, once an invoice exists for the period, its `id` for the client to follow to `GET /billing/invoices/{id}`.

### 20.2 `GET /api/v1/billing/periods/{period_id}`

- **Permission:** `billing:read`.
- **Response `200`:** adds `plan_version: {id, version_number}`, `pricing_source`, `commercial_agreement_version: {contract_reference, effective_from, effective_to} | null` — the exact historical pin this period used (§13.3/§14), so a tenant's finance team can independently verify why a given period's invoice looks the way it does.
- **Timezone:** `billing_periods.timezone` (5H — the tenant's `LocalizationProfile.timezone` at period creation, `Asia/Kolkata` default) is returned verbatim; period boundaries are computed in that timezone at period-open time and are not recomputed if the tenant's localization later changes (5H §10).

### 20.3 Period Lifecycle (Restated, Not Redesigned)

`OPEN` → `CLOSED` (5H §10) — closed once its invoice is generated (§25); a closed period is immutable (reopening is ODD-5H-03, unresolved upstream, not decided here). Period-open pins both `plan_version_id` and `commercial_pricing_agreement_version_id` per §13.3's algorithm, in the same transaction as the `billing_periods` `INSERT` (advisory lock `pg_advisory_xact_lock(hashtext(org_id || period_id))`, 5H §21, reused unchanged).

---

## 21. Usage Metering

### 21.1 Usage Metrics — Governed, Not a Closed REST-Layer Enum

Per task §15/§18: metrics are stored as `TEXT` in `usage_events.metric` (5H ADR-5H-002 — deliberately not a DB `CHECK ... IN (...)` enum, so a new metric is a new data row, not a migration). The REST layer mirrors this: `GET /billing/usage`'s `metric` filter accepts any string and the response never silently drops an unrecognized one — but the **billing-significant behavior of every currently-known metric** is governed application configuration, not hard-coded in this document's endpoints:

| Metric | Unit | Tracked | Quota-bearing | Billable (V1 default*) | Producer event | Source system |
|---|---|---|---|---|---|---|
| `CALL_MINUTES` | minutes | Yes | Yes | Yes | `call.ended` (6D) | `VOICE_CALL` |
| `AI_MINUTES` | minutes | Yes | Yes | No (V1: informational, superseded by the LLM/STT/TTS component metrics below for pricing granularity) | `conversation.turn_completed` (6E) | `VOICE_CALL` |
| `STT_SECONDS` | seconds | Yes | Yes | Plan-dependent | `conversation.turn_completed` (6E) | `STT_COMPLETION` |
| `TTS_CHARACTERS` | characters | Yes | Yes | Plan-dependent | `conversation.turn_completed` (6E) | `TTS_COMPLETION` |
| `LLM_PROMPT_TOKENS` | tokens | Yes | Yes | Plan-dependent | `conversation.turn_completed` (6E), `workflow.execution.completed` (6I, for non-voice automations) | `LLM_COMPLETION` |
| `LLM_COMPLETION_TOKENS` | tokens | Yes | Yes | Plan-dependent | Same as above | `LLM_COMPLETION` |
| `EMBEDDING_TOKENS` | tokens | Yes | Yes | Plan-dependent | `document.indexed` (6F) | `EMBEDDING_GENERATION` |
| `CAMPAIGN_CALLS` | calls | Yes | Yes | Plan-dependent — see §13.4's double-charge table | `campaign.contact.call_attempted` (6H) | `CAMPAIGN_CALL` |
| `WORKFLOW_EXECUTIONS` | executions | Yes | Yes | Plan-dependent | `workflow.execution.completed` (6I) | `WORKFLOW_EXECUTION` |
| `TOOL_EXECUTIONS` | executions | Yes | Yes | Plan-dependent | *(producer not yet built — 6I/6E tool-call telemetry; forward dependency, non-blocking, §46)* | `TOOL_EXECUTION` |
| `KNOWLEDGE_RETRIEVALS` | queries | Yes | Yes | Plan-dependent | *(producer not yet built — 6F/6E RAG-query telemetry; forward dependency, non-blocking, §46)* | `KNOWLEDGE_RETRIEVAL` |
| `STORAGE_GB` | GB-months | Yes | Yes | Plan-dependent | Periodic snapshot (scheduled worker computing document/recording storage, not an event stream) | `STORAGE_OPERATION` |
| `API_REQUESTS` | requests | Yes | Yes | No (V1: platform-protection quota only, never priced) | Periodic aggregation from `platform_http_requests_total` (6A §25) | `API_REQUEST` |
| `ACTIVE_AGENTS` | count | Yes | Yes | No (V1: quota/entitlement gate only, not metered) | Periodic snapshot (`COUNT` of `voice.agents` in a billable state) | — |
| `ACTIVE_PHONE_NUMBERS` | count | Yes | Yes | Plan-dependent | Periodic snapshot | — |

\* "Plan-dependent" means: billable if and only if the effective pricing (§13.2) resolves a non-null `overage_rate` for that metric on the org's currently pinned plan/agreement — **this table does not itself fix any rate or billability decision**; it records which metrics *can* legitimately carry a price, consistent with task §18's requirement that each metric separately answer tracked/quota-bearing/billable/included/overage/hard-limit/soft-limit, with the actual yes/no for "billable" coming from the pricing contract, not this document.

### 21.2 `GET /api/v1/billing/usage`

- **Permission:** `billing:read`.
- **Query params:** `period` (`current` default, or an explicit `period_id`), `metric` (repeatable filter, allow-listed against §21.1's known set — an unrecognized value returns an empty result, not a `422`, since the metric vocabulary is intentionally open at the DB layer).
- **Response `200`:** `[{metric, unit_label, quantity_used, included_quantity, overage_quantity, overage_rate: Money | null, quota: {soft_limit, hard_limit} | null}]`. `included_quantity`/`overage_rate` are §13.2's resolved *effective* values for that specific period (not "today's plan"), so a `GET` on a past, closed period returns the same numbers its invoice used (§14).

### 21.3 `GET /api/v1/billing/usage/summary`

- **Permission:** `billing:read`.
- **Purpose:** a bounded dashboard rollup — total usage-driven charge **so far** for the current, still-open period, labeled explicitly as an estimate (§32.2).
- **Response `200`:** `{period: {...}, metrics: [...], estimated_usage_charge: Money}` — `estimated_usage_charge` sums `overage_quantity × overage_rate` across all currently-billable metrics; it is **not** authoritative (late usage, credits, tax, and further consumption before period close can all change the final number).

---

## 22. Usage Ingestion — Internal, Not a Tenant API

Per task §16/§17: `UsageEvent` creation is **never** a tenant-facing REST endpoint. No `POST /api/v1/billing/usage-events` exists in this document, in any form — exposing one would let a tenant manufacture or suppress billable usage (§40's threat model, "usage-event forgery"/"usage suppression").

### 22.1 Ingestion Path (Internal Contract)

```
Producer bounded context (6D/6E/6F/6H/6I)
    → its own transaction: domain mutation + audit.fn_insert_audit_event() + audit.domain_event_outbox INSERT (same txn)
    → outbox publisher (audit.fn_claim_outbox_events / fn_mark_outbox_published, 5J §077) → Redis Streams
    → billing's usage-ingestion Celery consumer (app_worker)
    → billing.usage_events INSERT ... ON CONFLICT (organization_id, source_system, source_event_id, occurred_at) DO NOTHING
```

This is `/api/internal/v1/...`-shaped in spirit (6A §8.5) but is not even an HTTP endpoint in the common case — it is a Celery consumer reading the same Redis Streams / outbox mechanism 6J's own webhook dispatch already reads from (§45.2), authenticated as `app_worker` (a service principal, 6A §23.4), never a tenant JWT.

### 22.2 Idempotency — Exact Mechanism, Not Approximated

Per task §17: 5H's actual, executed constraint (not a conceptual approximation) is `UNIQUE (organization_id, source_system, source_event_id, occurred_at)` on `usage_events` (`uq_ue_idempotency`, partition-key-inclusive per ADR-5H-010) — **`metric` is not part of this key.** The ingestion consumer's `source_event_id` for each producer maps to that producer's own **outbox `id`** (the `audit.domain_event_outbox.id` UUID — already the stable, canonical per-event identifier every producer's transaction commits exactly once, per 5J §077's own `id` column comment: "doubles as the event's own event_id").

**Confirmed, live-reproduced defect and its fix (task §26 — closed in the `102_5H2` remediation pass):** because `metric` is not part of the uniqueness key, a single multi-metric producer event (e.g. one `conversation.turn_completed` yielding both `LLM_PROMPT_TOKENS` and `LLM_COMPLETION_TOKENS` under the identical `source_system = 'LLM_COMPLETION'`) would, if both rows were inserted with the *same* `source_event_id`, silently lose the second row to `ON CONFLICT DO NOTHING` — live-reproduced during validation (`docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §5, test T20: confirmed only one row survives without the fix). **Binding fix, requires no schema change** (`source_event_id` is already `TEXT`): for any producer event capable of yielding more than one `usage_events` row, the ingestion consumer suffixes `source_event_id` with `:<metric>` — `<outbox_event_id>:<metric>` — for every row it derives from that event. A single-metric producer event uses the bare outbox `id`, unsuffixed. Live-confirmed: with the suffix, both rows persist, and a replay of the fixed-scheme event (the exact same outbox id + metric) is correctly absorbed as a no-op duplicate.

| Producer | `source_system` | `source_event_id` | `occurred_at` |
|---|---|---|---|
| `call.ended` (6D) | `VOICE_CALL` | outbox event `id` (single metric — unsuffixed) | `payload.ended_at` |
| `conversation.turn_completed` (6E) | `LLM_COMPLETION` (×2 rows) / `STT_COMPLETION` / `TTS_COMPLETION` — up to 4 `usage_events` rows per turn | `<outbox_event_id>:<metric>` for every row (multi-metric event — suffix required even where `source_system` already differs between some rows, since the two `LLM_COMPLETION`-scoped rows, `LLM_PROMPT_TOKENS` and `LLM_COMPLETION_TOKENS`, share it) | `payload.turn_completed_at` |
| `document.indexed` (6F) | `EMBEDDING_GENERATION` | outbox event `id` (single metric — unsuffixed) | `payload.indexed_at` |
| `campaign.contact.call_attempted` (6H) | `CAMPAIGN_CALL` | outbox event `id` (single metric — unsuffixed) | `payload.attempted_at` |
| `workflow.execution.completed` (6I) | `WORKFLOW_EXECUTION` (+ `LLM_COMPLETION` where the workflow made its own LLM calls, §23.3) | `<outbox_event_id>:<metric>` for every row this event yields | `payload.completed_at` |

**Retry-safety, concretely:** the outbox's own `fn_claim_outbox_events`/`fn_mark_outbox_failed` retry loop (5J §077) may redeliver the same outbox row to Redis Streams more than once (at-least-once, matching 6A §28's own outbound-webhook guarantee); the consumer's `ON CONFLICT DO NOTHING` on `uq_ue_idempotency` absorbs any resulting duplicate `usage_events` `INSERT` attempt for the same (suffixed, where applicable) source_event_id — this is the DB-level backstop task §17 requires, not an application-layer "have I seen this before" check alone (5H ADR-5H-003's own stated rejection of that weaker pattern).

### 22.3 Call-Minute Conversion — DEC-6K-02, ACCEPTED, FINAL

`call.ended`'s `duration_seconds` field (6D §11.7's payload shape) is the sole input to `CALL_MINUTES`. Per DEC-6K-02 (§48, owner-accepted): **exact `duration_seconds / 60`, no `CEIL`, no per-call rounding, no telephony-provider pulse rounding for the customer charge** (provider pulse billing may affect the platform's own `cost_entries` provider-cost accounting — §24 — but never the customer-facing `usage_events.quantity`).

**Corrected aggregation algorithm (FB-6K-06, task §13/§28) — per-call rounding before summation is NOT exact, and a freeze-gate review live-proved this:** a first draft of this section stored `quantity = ROUND(duration_seconds/60, 4)` per call and summed those already-rounded values across a period (`usage_records`, 5H's own QP-06 `SUM` pattern), claiming this "introduces no systematic upward bias." **That claim was wrong.** 1000 one-second calls, each contributing `ROUND(1/60, 4) = 0.0167`, sum to `16.7000` minutes; the true aggregate — `1000` total seconds, divided by 60 and rounded exactly once — is `16.6667`. The discrepancy is systematic, not noise: `1/60 = 0.016666...` always rounds *up* to `0.0167` at 4 decimal places, so every additional short call compounds the same upward bias linearly. Live-reproduced exactly to this decimal (`docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §15, FB-6K-06).

**Fixed, additive, live-validated:** `billing.usage_events` gains a nullable `source_quantity_seconds NUMERIC(18,4)` column (§12.7a). The ingestion consumer populates **both** columns per `CALL_MINUTES` row: `quantity = ROUND(duration_seconds::NUMERIC / 60, 4)` (kept only as a per-row audit/display convenience for that single call — never the billing aggregation input) and `source_quantity_seconds = duration_seconds` (the exact, unrounded seconds value). **Billing aggregation for `CALL_MINUTES` uses `ROUND(SUM(source_quantity_seconds) / 60, 4)`** — summing exact seconds first (integer/exact-decimal addition introduces zero precision loss regardless of how many rows are summed) and rounding **once**, at the end — never `SUM(quantity)` for this metric. Metrics that need no such correction (already-exact integer counts like `CAMPAIGN_CALLS`, `WORKFLOW_EXECUTIONS`) leave `source_quantity_seconds` `NULL` and continue using the existing `SUM(quantity)` pattern unchanged.

| `duration_seconds` | `CALL_MINUTES` (`ROUND(seconds/60, 4)`, this single call) |
|---|---|
| 1 | 0.0167 |
| 30 | 0.5000 |
| 59 | 0.9833 |
| 60 | 1.0000 |
| 61 | 1.0167 |
| 90 | 1.5000 |
| 127 | 2.1167 |

**Aggregate equivalence, live-proven, not asserted:** 1000 × 1-second calls (`SUM(source_quantity_seconds)/60`, rounded once) = `16.6667` = a single 1000-second call (`1000/60`, rounded once) = `16.6667`. 100 × 7-second calls = `11.6667` = a single 700-second call = `11.6667`. No per-call ceiling exists anywhere in this conversion, and — with the fix — no per-call-rounding-induced drift survives aggregation either.

### 22.4 Late-Arriving Usage — DEC-6K-04, ACCEPTED, FINAL

A `usage_events` row that arrives (via §22.1's async path) **before** its `billing_periods` row has finalized (a bounded reconciliation window, configurable, before `fn_finalize_invoice` runs) is incorporated into the still-`DRAFT` invoice normally. Per DEC-6K-04 (§48, owner-accepted): a `usage_events` row that arrives **after** the period's invoice has already reached `OPEN`/`PAID` **never mutates that invoice** (`INV-BILL-02`, §44, non-negotiable) — it becomes a next-cycle `billing_adjustments` row instead, created via `fn_create_late_usage_billing_adjustment` (§12.6), always `adjustment_type = 'MANUAL_CORRECTION'`, carrying full structured provenance: `late_usage_billing_period_id` (the *original* period this usage belongs to), `late_usage_metric`, and `late_usage_provenance` JSONB (the original period's pinned `plan_version_id`, `commercial_pricing_agreement_version_id` if applicable, the specific late `usage_events` row ids, the quantity, and the unit price — all from the **original period's pinned pricing**, never today's plan/agreement). Live-confirmed: creating such an adjustment leaves the original, already-finalized invoice's `total_due_amount` numerically unchanged (`docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md` §5, test T22).

---

## 23. Voice, Campaign, AI, and Knowledge Usage — Exact Wiring

### 23.1 Voice → `CALL_MINUTES`

`call.ended` (6D, outbox) → billing consumer → one `usage_events` row, `metric = 'CALL_MINUTES'`, `quantity` = `ROUND(payload.duration_seconds::NUMERIC / 60, 4)` per DEC-6K-02 (§22.3), `source_context = {"call_id": ..., "direction": ...}` (never the transcript/recording URL — 6J §20.2's "never in the envelope" discipline applies equally to what billing persists in `source_context`).

### 23.2 Campaign → `CAMPAIGN_CALLS`

`campaign.contact.call_attempted` (6H, outbox, "Billing's own metered-usage trigger" per 6H's own §24.1) → one `usage_events` row per attempt, `metric = 'CAMPAIGN_CALLS'`, `quantity = 1`. **Idempotency for a retried campaign event:** 6H's own outbox insert happens once per genuine dispatch outcome (6H §24.1's "corrected two-statement, dual-CAS transaction," published after commit); a re-publish of the *same* outbox row (transport-level retry) is absorbed by §22.2's `source_event_id` = outbox `id` mechanism exactly as any other producer — no campaign-specific idempotency logic is needed in billing.

### 23.3 AI (LLM/STT/TTS/Embedding) → Component Token/Second/Character Metrics

`conversation.turn_completed` (6E, internal Redis Stream event per 6E §"Internal Redis Stream event" table, "feeds Analytics/Billing token-usage projections") → up to four `usage_events` rows (`LLM_PROMPT_TOKENS`, `LLM_COMPLETION_TOKENS`, `STT_SECONDS`, `TTS_CHARACTERS`), one per non-zero component in the turn's payload. `document.indexed` (6F) → one `usage_events` row, `metric = 'EMBEDDING_TOKENS'`.

**Overlap with `workflow.execution.completed` — corrected (task §27):** 4E §25 and 6I both name `workflow.execution.completed` as a required Billing input "for LLM token usage." A first draft of this document claimed distinct `source_event_id`s alone prevent double-counting — **that claim was wrong and has been corrected.** Distinct event IDs prevent each producer's *own* event from being counted twice (replay-safety); they do **nothing** to stop two *different* producers from each legitimately emitting a `usage_events` row for the *same underlying LLM call* (a voice-triggered workflow node's LLM invocation), which would then be recorded — and billed — twice, once under each producer's own distinct, valid, non-colliding `source_event_id`.

Since no shared, stable, cross-context LLM-invocation correlation ID was found to exist in either 6E's or 6I's reviewed documents (neither names a `provider_request_id`, `model_invocation_id`, or equivalent field that both bounded contexts would independently emit for the same call), this document does **not** fabricate one. Instead it states a strict, binding **producer ownership rule**, and records the field-shape verification this rule depends on as a disclosed, non-blocking cross-phase coordination item — mirroring 6J's own precedent for `DEP-6J-12` (disclosed, not silently claimed closed):

- **Ownership rule:** a workflow execution that runs *as part of* an active voice conversation turn (i.e., invoked from within the call, its LLM usage already covered by that turn's own `conversation.turn_completed` event) **must not** re-emit `LLM_PROMPT_TOKENS`/`LLM_COMPLETION_TOKENS` usage via its own `workflow.execution.completed` event for that same LLM call. `workflow.execution.completed` emits LLM token usage **only** for a workflow execution's *own* LLM calls that are not already covered by a voice turn — i.e., text/automation-triggered executions with no owning `conversation.turn_completed` event at all.
- **DEP-6K-05 (new, non-blocking, disclosed):** whether `workflow.execution.completed`'s payload actually carries a field distinguishing "invoked from within a voice turn" vs. "standalone execution" was not confirmed in the reviewed 6E/6I documents. This is required for 6E/6I's own application code to correctly implement the ownership rule above; 6K states the rule and the requirement, and flags the verification as a forward cross-phase coordination item, exactly as 6J did for the analogous `graph_json` field-shape gap.
- **Defense in depth, not a replacement:** even if this ownership rule were violated by a producer-side bug (both events fire for the same call), the idempotency mechanism (§22.2) still prevents a *literal* duplicate of the same row — it does not, and structurally cannot, prevent two *different, both-valid* rows from the two producers. The ownership rule, not the idempotency key, is the actual control here; this is stated plainly rather than implied to be solved by a mechanism that does not solve it.

### 23.4 Not Yet Wired (Forward, Non-Blocking)

`TOOL_EXECUTIONS` and `KNOWLEDGE_RETRIEVALS` (§21.1) have no confirmed producer event in the reviewed 6D–6I documents. This is recorded as a forward dependency (§46), not fabricated here — consistent with 6I's own precedent of naming a forward Billing dependency rather than inventing the missing half of the contract unilaterally.

---

## 24. Cost Tracking vs. Customer Charge

Per task §22/§75: `cost_entries` (5H, existing, unchanged) is the platform's own provider cost — never read by any tenant-facing endpoint in this document. `GET /billing/usage`, `GET /billing/invoices`, and `GET /billing/summary` (§32) expose only customer-facing figures derived from `usage_records` + effective pricing (§13) + `invoice_lines`. No endpoint in this document joins `cost_entries` into a tenant response, and no field name in any response model in this document is populated from `cost_entries.amount_amount`, `fx_rate_used`, or `provider`. Cost/margin reporting (provider cost vs. customer charge, gross margin) is explicitly **future 6L/6M internal-analytics** territory (task §23/§75) — 6K's only relationship to `cost_entries` is that its own internal ingestion pipeline (§34.5) writes to it, exactly as 5H already specifies, with no new column or endpoint added here.

---

## 25. Quotas

### 25.1 `GET /api/v1/billing/quotas`

- **Permission:** `billing:read`.
- **Response `200`:** `[{metric, unit_label, soft_limit, hard_limit, current_usage, remaining, overage_allowed, overage_rate: Money | null, period: {period_start, period_end}}]`.
- **`overage_allowed` — corrected (task §30):** a first draft conflated enforcement (whether consumption is blocked) with pricing (whether it's charged), deriving `overage_allowed` from *either* condition. This is wrong: an explicit `hard_limit` is a real, unconditional enforcement stop regardless of whether the metric happens to be priced. Corrected definition: **`overage_allowed = (hard_limit IS NULL)`** — full stop. Whether consumption beyond `included_quantity` is *billed* is a completely separate question, already answered by the sibling `overage_rate` field (non-null iff `effective_overage_rate(metric)`, §13.2, resolves one) — the two fields are never merged into one. A metric can therefore be in any of four independent states: enforced-and-priced, enforced-and-unpriced (blocked at `hard_limit`, and any usage up to that point is free), unenforced-and-priced (no hard stop, but overage beyond `included_quantity` is billed), or unenforced-and-unpriced (tracked only).
- **No self-service quota mutation:** per task §24 — quota mutation belongs to plan provisioning, an active commercial agreement, or platform admin, never an ordinary tenant call. No `PATCH`/`POST` exists on this resource in this document.

### 25.2 Quota Enforcement — Hot Path

Per task §25: PostgreSQL `quota_configs` + `usage_records` remain the durable source of truth (5H §13); Redis (`quota:{tenant_id}:{metric}` `INCR`, per 4F's own sequence diagram) is the enforcement hot-tier used by call/campaign-initiation checks, which **are** latency-sensitive (6D/6H's own request paths), separate from billing's own report/invoice/payment endpoints, which are not (§43).

```
Call/campaign initiation (6D/6H) requests a quota check
    → Redis INCR quota:{org_id}:{metric} (atomic, sub-ms)
    → if result > hard_limit (from a Redis-cached copy of quota_configs, TTL-bounded):
          reject BEFORE the call/campaign-send is placed — nothing is charged for
          an operation rejected before consumption (task §25's own explicit requirement)
    → else: proceed; the eventual usage_events row (§22) is the durable record
    → nightly reconciliation job recomputes Redis counters from
      billing.usage_records (5H §12) — corrects any pod-crash divergence
```

- **Soft limit:** exceeding it is a warning signal only (surfaced via `usage.threshold_reached`, §45.1) — the operation proceeds.
- **Hard limit, overage not allowed:** the initiating context's own request is rejected with a billing-owned error code (`QUOTA_EXCEEDED`, §36) surfaced through 6D/6H's own response contract — 6K does not itself receive that inbound request; it only owns the Redis-backed check contract and the reconciliation job.
- **Race handling:** Redis `INCR` is atomic per-key; a burst of concurrent call-initiation attempts against a near-exhausted quota is bounded by Redis's own atomicity, not by any billing-side locking — consistent with 6A §17.3's prohibition on a second, API-layer locking scheme.
- **Reservation:** not required in V1 — a slight, bounded over-consumption past a soft/hard limit during a race window is an accepted, disclosed limitation (matches 5H's own "Redis is the enforcement hot-tier; Postgres is the audit authority" framing, §12) rather than a fabricated distributed-reservation protocol.

### 25.3 Quota Read APIs Are Not the Enforcement Path

`GET /billing/quotas` (§25.1) is a reporting endpoint for the tenant's own dashboard — it is explicitly **not** on 6D/6H's call/campaign-initiation hot path (§43's latency-tier separation). The initiation path reads Redis directly (or through 6D/6H's own thin internal client), never round-trips through this REST endpoint.

---

## 26. Invoice Generation

### 26.1 Deterministic Input Set (Task §67)

```
BillingAccount (currency)
Subscription (for context; not itself a pricing input once the period is pinned)
BillingPeriod (plan_version_id, commercial_pricing_agreement_version_id — both pinned, §13.3)
PlanVersion (base_price, immutable once published)
PlanPrice (per metric, immutable once published)
CommercialPricingAgreementVersion + CommercialPricingMetric (if pinned; immutable once ACTIVE, §12.4)
UsageRecords (aggregated quantities for this period, 5H §12)
Credits (active, unexpired, this org)
TaxProfile / TaxRule (versioned, effective as of the period)
```

No step reads "the current plan" or "the current agreement" — every input above is either already pinned on the `billing_periods` row or is itself an immutable historical row (5H §16, restated with the agreement addition from §13–§14).

### 26.2 Generation Pipeline

```
1. Period closes (period_end reached, renewal worker)
2. billing.invoices INSERT (status = DRAFT), FK'd to billing_period_id
3. For each usage_records row in this period:
     a. Resolve effective_included_quantity(metric) [+ its source], effective_overage_rate(metric) [+ its source]  [§13.2, from the PINNED plan/agreement]
     b. overage_quantity = GREATEST(0, quantity_used - effective_included_quantity)
     c. IF effective_overage_rate IS NOT NULL AND overage_quantity > 0:
            INSERT invoice_lines (line_type='OVERAGE', metric, quantity=overage_quantity,
                                   unit_price=effective_overage_rate,
                                   unit_price_source, included_quantity_source, commercial_pricing_agreement_version_id)
        -- a metric with a null effective_overage_rate produces NO line (§13.4) --
4. INSERT invoice_lines (line_type='BASE_FEE', quantity=1, unit_price=effective_base_subscription_price,
                          unit_price_source, commercial_pricing_agreement_version_id)
5. Apply active, unexpired Credits (line_type='CREDIT', negative-amount lines; never below zero, INV-BILL-04)
6. TaxComputationService reads billing.tax_rules effective as of period_end → INSERT tax_lines (5H §16, unchanged)
7. UPDATE invoices SET subtotal_amount, total_credits_amount, total_tax_amount, total_due_amount (computed, never client-set)
8. billing.fn_finalize_invoice(...) → status DRAFT → OPEN, invoice_number allocated (5H §57, unchanged)
9. audit.fn_insert_audit_event(p_action_kind => 'INVOICE_GENERATED') + audit.domain_event_outbox INSERT ('invoice.created') — same transaction as step 8
10. billing_periods.status → CLOSED, invoice_generated_at set (advisory-lock-guarded, 5H §21)
```

Steps 3–7 are the only place a metric's billability is decided (§13.4) — usage recording (§22) never itself creates a monetary line.

### 26.2.1 No Double-Charge — Worked Test (Task §88)

Given a period with `10 CALL_MINUTES` and `5 CAMPAIGN_CALLS` recorded:

| Effective pricing state | `CALL_MINUTES` line | `CAMPAIGN_CALLS` line | Total usage-driven charge |
|---|---|---|---|
| Only `CALL_MINUTES` priced (₹2/min, no included quota) | `OVERAGE`, qty 10, ₹20 | none | ₹20 |
| Only `CAMPAIGN_CALLS` priced (₹1/call) | none | `OVERAGE`, qty 5, ₹5 | ₹5 |
| Both priced | `OVERAGE` ₹20 + `OVERAGE` ₹5 | — | ₹25 |
| Neither priced | none | none | ₹0 (both `usage_records` rows still exist and are visible via `GET /billing/usage`) |

### 26.3 `GET /api/v1/billing/invoices`

- **Permission:** `invoice:read`. Cursor-paginated, filterable by `status`.
- **Response `200`:** `[{id, invoice_number, invoice_kind, status, issue_date, due_date, total_due: Money, amount_paid: Money}]`.

### 26.4 `GET /api/v1/billing/invoices/{invoice_id}`

- **Permission:** `invoice:read`, tenant-scoped (RLS + explicit ownership check — cross-org id → `404 RESOURCE_NOT_FOUND`, never `403`, per 6A §9.2/6B's own established convention).
- **Response `200`:** full invoice including `lines: [{line_type, description, metric, quantity, unit_price: Money, line_total: Money, unit_price_source, included_quantity_source}]`, `tax_lines: [{component_code, rate_percent, taxable_amount: Money, tax_amount: Money}]`, `place_of_supply`, `tax_profile_snapshot` (sanitized — GSTIN/address as recorded at issuance, per 5H §16.3), `e_invoice_ref` (if present).
- **No client mutation of any field on this resource** — the entire object is server-computed; there is no `PATCH` on this resource in this document (task §26).

### 26.5 Invoice Number Security

Per task §43: `invoice_number` is always server-generated via `fn_allocate_invoice_number`'s row-locked sequence (5H §52/ADR-5H-011) — a client can never propose one; the request body for any endpoint in this document has no `invoice_number` field, full stop. Gaps in the sequence (a `DRAFT` invoice that is later `VOID`ed before ever reaching `OPEN`, so the number was never allocated — allocation happens only at `fn_finalize_invoice`, i.e. at the `OPEN` transition, not at `DRAFT` creation) are handled exactly as 5H's own design already dictates: a number, once allocated, is never reused or renumbered (5H §16.1's gapless-per-allocation guarantee applies to *allocated* numbers, not to the count of `DRAFT` invoices that never reach `OPEN` — those simply never consume a number at all, so no gap is created by them in the first place).

---

## 27. Credits, Discounts, Negotiated Pricing, and Adjustments — Explicitly Distinguished

Per task §28:

| Concept | What it changes | Mechanism | Recurs automatically? |
|---|---|---|---|
| **Negotiated pricing** | The *recurring effective price itself* (base fee, included quantity, overage rate) | `CommercialPricingAgreementVersion` (§11–§14) | Yes — applies to every period while `ACTIVE` |
| **Discount** | A rule-based reduction applied at invoice time (e.g. "10% off first 3 months") | *Not built in V1* — no `discount` concept exists anywhere in 5H's DDL or 4F's domain model; `invoice_lines.line_type` includes `'DISCOUNT'` as a governed value but no service/API in this document ever inserts one. Flagged as `FUTURE ENHANCEMENT`, not fabricated here. | N/A |
| **Credit** | A stored, non-negative account balance, consumed against future invoices | `credits` + `credit_ledger_entries` (5H §14, unchanged) | Only if manually re-granted each time — this is precisely why it is the *wrong* mechanism for negotiated pricing (§11.3) |
| **Billing adjustment** | A one-off manual financial correction, tied or untied to a specific invoice | `billing_adjustments`, via `fn_create_billing_adjustment` (086_5H1, unchanged) | No — always a single, explicit, reasoned correction |

Negotiated enterprise pricing is never implemented as a recurring manual credit (task §28's explicit prohibition) — §11–§14 exist specifically so it doesn't have to be.

### 27.1 `GET /api/v1/billing/credits`

- **Permission:** `billing:read`.
- **Response `200`:** `[{id, credit_type, amount: Money, reason, status, expires_at}]` plus the account's current `credit_balance` (Money, already on `GET /billing/account`, §15.1). Balance is the derived-and-cached `billing_accounts.credit_balance_amount`, reconciled nightly against `SUM(credit_ledger_entries)` per 5H ADR-5H-004 — on divergence, the ledger sum is authoritative (unchanged from 5H).
- **No creation endpoint:** credit issuance is platform support/refund-process/proration-only (task §29) — `fn_billing_apply_credit` is `app_worker`/`app_platform_admin`-only (5H §53, confirmed in §9.1's audit), never `app_api`. A tenant-facing `POST /billing/credits` is not designed here; manual credit issuance is 6M's (§41).

---

## 28. Tax / GST

Per task §41/§42: no GST percentage, CGST/SGST/IGST split, or threshold appears anywhere in this document's endpoint contracts, exactly as 5H's own DDL contains none (ADR-5H-009, INV-BILL-12). Every rate comes from the effective, versioned `tax_rules` row at invoice-generation time (§26.2 step 6).

- **`GET /api/v1/billing/invoices/{invoice_id}`** (§26.4) already exposes the resolved `tax_lines` and `tax_profile_snapshot` for that specific invoice — this is the only tenant-facing tax surface in this document.
- **Tax profile visibility:** a tenant's own `tax_profiles` row (GSTIN, place of supply, billing address) is **not** newly exposed by this document — it is owned and surfaced by 6C's organization-settings surface (per 4I §25.4's own table placing `tax_profiles` fields there) and referenced, read-only, by the invoice snapshot above. 6K does not duplicate a `GET/PATCH /billing/tax-profile` endpoint that 6C may already own; if no such endpoint exists yet in 6C, that is a 6C-scope gap, not one this document manufactures a competing surface to fill.
- **India invoice requirements (task §42):** `invoice_kind` (`TAX_INVOICE|CREDIT_NOTE|DEBIT_NOTE|PROFORMA`), `place_of_supply`, `tax_rule_versions_applied`, gapless fiscal-year invoice numbering, and `e_invoice_ref` (reserved, no IRN integration in V1 per ODD-5H-09) are all reused verbatim from 5H §16.3 — none redesigned. Exact HSN/SAC codes and GDPR-vs-statutory-retention conflict resolution remain `ODD-5H-05`/`ODD-5H-07`, explicitly requiring legal review upstream — not resolved by this document (task §42's own instruction not to provide legal guarantees beyond frozen source material).

---

## 29. Payment Architecture

### 29.1 Provider Abstraction — Preserved, Not Redesigned

Reused verbatim from 4F/4I (§9.4): `PaymentProviderPort` (Protocol) with `RazorpayAdapter` (V1) and `CashfreeAdapter` (documented second), interface `create_payment_intent`/`capture`/`refund`/`get_status`/`verify_webhook` (4I §13.2). `payment_attempts.payment_provider TEXT CHECK (...IN ('RAZORPAY','CASHFREE','STRIPE','OTHER'))` (5H §17.1) — no provider-specific column anywhere; `ProviderMetadata`/`provider_transaction_id` carry everything provider-specific, never read by domain logic outside the adapter. Switching the *active* provider for future payment attempts requires no billing schema, invoice, or subscription redesign (task §39/§31) — historical `payment_attempts.payment_provider`/`provider_transaction_id` values are never rewritten by a provider switch (task §39's explicit requirement); only new attempts route to the newly-configured provider.

### 29.2 Provider Selection — Platform Policy, Not Client-Chosen

Per task §31: the payment-intent endpoint (§29.4) never accepts a client-supplied `"provider"` field. Provider routing is `BillingAccount`-level configuration (a platform-config value, defaulting to Razorpay for all INR accounts per 4I §13.1) resolved server-side inside the application service, before `PaymentProviderPort` is invoked — the client never selects, and the server never trusts a client hint about, which adapter handles a given invoice's payment.

### 29.3 Payment Methods — Opaque References Only

Per task §32: `payment_attempts.payment_method_ref` is an opaque, provider-issued token (5H §17.1, `INV-BILL-14` — no PAN/CVV/UPI-PIN/bank-credential/mandate-secret column exists anywhere in the schema, confirmed by direct inspection in §9). `PaymentMethodKind` (`CARD|UPI|NETBANKING|WALLET|MANDATE|BANK_TRANSFER`, 4I §13.4) is used only for display/policy, never persisted as anything beyond that enum value alongside the opaque ref.

### 29.4 `POST /api/v1/billing/invoices/{invoice_id}/payment-intent`

- **Permission:** `billing:manage` (payment initiation reuses the existing broadest tenant billing permission — task §50 explicitly allows deriving this rather than inventing a `payment:manage` string where none of 6B's seeded catalog defines one; `billing:manage` is held only by `OWNER`/`BILLING_ADMIN`, per 5B's own seed data, §9.1's authorization-matrix source).
- **Idempotency-Key:** **required** (task §56 — a client retry must never create two provider payment attempts for one logical request).
- **Body:** `{"payment_method_hint"?: "UPI" | "CARD" | ...}` — a *hint* only (which method screen the client wants the provider checkout to open on); never an amount, currency, or provider.
- **Server-side sequence — corrected and now internally coherent (task §17/§18, closed by `102_5H2`; step 7 further hardened by the freeze-gate pass, FB-6K-05):** a first draft's sequence was self-contradictory (it inserted a `payment_attempts` row before calling the provider, yet the DDL it referenced required `provider_transaction_id NOT NULL` at that same moment — structurally impossible). Fixed at the schema layer (§12.4 — `provider_transaction_id` is now nullable). A second draft still had step 7 as a raw `INSERT`, which a freeze-gate review found `app_api` could reach directly (the frozen 055_5H.sql grant), supplying its own amount/currency/provider — fixed by revoking that grant and routing step 7 through a guarded function instead:
```
1. Authenticate + tenant-resolve (6A §9.1 pipeline)
2-6. All folded into billing.fn_create_payment_attempt(invoice_id, payment_method_hint)
     (§12.4) — the function itself: derives organization from
     organization.current_tenant_id() (no parameter to forge); FOR UPDATE-locks
     and verifies the invoice belongs to this tenant and is OPEN (cross-tenant/
     nonexistent → the same generic exception either way); rejects a second call
     while a non-terminal attempt already exists; computes amount = total_due_amount
     - amount_paid_amount; reads currency from the invoice; resolves provider from
     server-side policy (§29.2); INSERTs the local INITIATED row
     (provider_transaction_id = NULL) -- COMMITs. Live-confirmed (§12.8): this
     succeeds, and a second concurrent INITIATED attempt (also NULL) does not
     collide, under uq_pa_provider_tx's standard NULL-distinctness semantics.
     app_api holds EXECUTE on this function and NO direct INSERT on
     payment_attempts at all (REVOKEd, §12.4) -- this is the first app_api-
     callable billing SECURITY DEFINER function in the schema, for exactly
     this reason.
7. provider_adapter.create_payment_intent(invoice_ref, amount, payment_method_ref, tenant_id)
   -- a synchronous call within this same HTTP request, but NOT inside any open DB
   -- transaction (step 2-6 already committed) -- this is what "outside the DB
   -- transaction" means precisely: no transaction is held open across the network
   -- call, not that the call happens after the HTTP response.
8. On a successful provider response: billing.fn_link_payment_provider_transaction(...)
   (§12.4/§29.5, a short follow-up transaction) records the real provider_transaction_id
   and moves status INITIATED -> PENDING, + audit PAYMENT_ATTEMPTED (outbox events for
   payment.failed/invoice.paid fire only on a later terminal outcome, §45.1, via the
   webhook path, §30)
9. The 202 response, returned after step 8, carries the REAL provider checkout
   instructions (order id, checkout key) -- by response time they already exist.
```
This endpoint's latency is therefore bound by the provider's own round-trip (step 7) — Tier B's 8s timeout ceiling accommodates this; it is not expected to hit Tier B's 100ms/300ms p50/p95 targets the way a pure-DB Tier B operation does, and is documented as the one deliberate exception in §43.
- **Response `202`:** `{"data": {"payment_attempt_id": "...", "provider": "RAZORPAY", "client_instructions": {...opaque, provider-shaped...}}}` — never the platform's raw provider secret, never a card/UPI collection field constructed by the platform itself (the provider's own hosted checkout / SDK owns that surface).
- **Errors:** `409 INVOICE_NOT_PAYABLE` (wrong status), `404 INVOICE_NOT_FOUND`, `409 PAYMENT_ALREADY_IN_PROGRESS` (an `INITIATED`/`PENDING` attempt already exists for this invoice — surfaced from a partial-unique-style application check, since 5H's own schema allows multiple `payment_attempts` rows per invoice by design, e.g. a failed attempt followed by a retry; "already in progress" specifically means a **non-terminal** attempt exists), `503 PAYMENT_PROVIDER_UNAVAILABLE` (step 8 failed/timed out — the committed `INITIATED` row from step 7 is left for the reconciliation worker, §29.5, never silently retried by the request handler itself).

### 29.5 Payment Intent Idempotency and Provider-Timeout Reconciliation

Per task §56.1: `Idempotency-Key` → cached `payment_attempt_id` (Redis, 6A §16.2's standard mechanism) → the provider's own idempotency key where supported (the local `payment_attempts.id`, already generated by `fn_create_payment_attempt` before the provider is ever called, is passed through as the platform-side correlation reference in `create_payment_intent`'s own request — most providers support a client-supplied reference/notes field for exactly this purpose). A provider timeout with an unknown outcome is **never** resolved by silently creating a second charge — the reconciliation worker calls `PaymentProviderPort.get_status(provider_payment_ref)` (4I §13.2) before any retry is permitted to create a new `payment_attempts` row; if `get_status` itself times out, the attempt stays `INITIATED`/`PENDING` and is retried by the *same* reconciliation path, not by a fresh client-initiated `POST`. Once the provider's real transaction id is known, `billing.fn_link_payment_provider_transaction` (§12.4) is idempotent for a re-link with the same value and rejects a re-link with a different one — live-confirmed, §12.8 — so a reconciliation retry can never silently reassign an already-linked attempt to a different provider transaction.

### 29.6 `GET /api/v1/billing/payments` / `GET /api/v1/billing/payments/{payment_attempt_id}`

- **Permission:** `invoice:read`.
- **Response:** `{id, invoice_id, status, amount: Money, payment_method_kind, failure_code | null, initiated_at, completed_at}`. `payment_method_kind` is now a real, persisted, provider-confirmed column (`payment_attempts.payment_method_kind`, §12.4) — set only via `fn_link_payment_provider_transaction`, never a raw client-supplied value (§20's own requirement, closed) — never `provider_transaction_id`'s raw value to an ordinary tenant caller beyond what the provider's own customer-facing receipt already shows, never `payment_method_ref` (opaque token, no display value beyond `payment_method_kind`), never `ProviderMetadata` JSONB.

### 29.7 Payment Failure Normalization

Per task §80: a provider-specific error (e.g. a Razorpay error code) is mapped, inside the adapter, to the normalized `FailureCode` enum (§9.4, reused verbatim from 4I §13.3) before ever reaching `payment_attempts.failure_code` or any API response. No endpoint in this document ever returns a raw provider error string.

---

## 30. Payment Provider Webhooks (Inbound)

### 30.1 Why This Is Not 6J's `IntegrationConnection` Route

6J §24.6's generic inbound-provider endpoint (`POST /api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}`) is routed by a **tenant-created** `IntegrationConnection` — the right shape for a CRM/calendar/messaging provider a tenant individually connects. A payment provider (Razorpay/Cashfree) is a **platform-level** merchant relationship, not a per-tenant `IntegrationConnection` row — there is one platform Razorpay account (or, at most, a small number of platform-configured merchant sub-accounts), not one per organization. So 6K defines its **own** dedicated inbound endpoint, mirroring 6D/Exotel's own precedent (6J §24.5 — "6D owns its own dedicated telephony-callback endpoint path... using the identical `webhooks.inbound_webhook_events` dedup key") rather than misusing the tenant-connection-routed generic path for a relationship that isn't tenant-scoped at all.

### 30.2 `POST /api/v1/billing/payment-providers/{provider_slug}/webhook`

**Corrected mechanism (task §21/§22, closed by `102_5H2`; ingress authority and linkage further hardened across three freeze-gate passes, FB-6K-03/04/07, FINAL-6K-01, and FREEZE-6K-01):** a first draft proposed deduplicating via an `UPDATE` against `payment_attempts.provider_webhook_event_id` — not the same atomic "insert once" guarantee `INSERT ... ON CONFLICT ... RETURNING` provides. Fixed with a dedicated durable receipt table, `billing.payment_webhook_receipts` (§12.4), reusing 6J §24's pipeline **pattern** exactly (verify → fast ACK → dedup insert → normalize → async processing), platform-level routing instead of connection-level routing. A freeze-gate review then found the ingress path itself (`app_api` granted direct `SELECT`/`INSERT` on the receipt table) and the linkage-resolution function (accepting `p_payment_attempt_id`/`p_organization_id` as direct, trusted parameters) were both unsafe — corrected. A further freeze-gate review then found that closing the *table* for `app_api` was not sufficient: `app_api` still held `EXECUTE` on the ingress function itself, which — even though the function accepts no financial fields — let the general tenant-facing role pre-claim a real, not-yet-arrived provider event ID and poison the dedup key (FINAL-6K-01). A fourth, still further freeze-gate review then found `app_platform_admin` still held raw `INSERT`/`UPDATE`/`DELETE` directly on the receipt *table* — a platform-admin session could bypass the dedicated ingress function entirely and rewrite the platform's own webhook ingestion history (FREEZE-6K-01); closed by revoking that raw DML (`SELECT` only is retained, for narrow support/incident-response reading). The inbound HTTP handler now runs the ingress call as a dedicated, single-purpose role, `app_billing_webhook_ingress` (§12.4), rather than as `app_api`:

**Principal separation, made explicit (HTTP caller ≠ application actor ≠ PostgreSQL role):**

| Layer | Value |
|---|---|
| HTTP caller | `PROVIDER` (Razorpay/Cashfree) |
| HTTP authentication | Provider signature verification (`PaymentProviderPort.verify_webhook`) — never a JWT; 6A §28.2's own carve-out |
| DB ingress principal (durable receipt creation) | `app_billing_webhook_ingress` — `EXECUTE` on `fn_record_payment_webhook_receipt` only, no table DML |
| Async processor | `app_worker` — `EXECUTE` on `fn_process_payment_webhook_receipt` only, no raw table DML on the receipt table |
| Tenant application DB role | `app_api` — no webhook-receipt capability of any kind (no `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`EXECUTE`) |
| Platform-admin DB role | `app_platform_admin` — `SELECT` only (read-only support/incident-response), no `INSERT`/`UPDATE`/`DELETE`, no `EXECUTE` on the ingress function |

```
Provider (Razorpay/Cashfree) → this endpoint
    → PaymentProviderPort.verify_webhook(payload_bytes, signature_header)   [§30.3 — payload not trusted before this]
    → billing.fn_record_payment_webhook_receipt(payment_provider, provider_event_id, payload_hash)
       -- a narrow SECURITY DEFINER function, callable ONLY by app_billing_webhook_ingress
       -- (a dedicated role for this one inbound handler — FINAL-6K-01; app_api and
       -- app_platform_admin were both granted EXECUTE before this pass and are not
       -- afterward), accepting ONLY these three ingress-safe fields (never
       -- organization_id/payment_attempt_id/processing_status) -- internally does
       -- INSERT ... ON CONFLICT (payment_provider, provider_event_id) DO NOTHING
       -- RETURNING id (the atomic, durable dedup gate — live-confirmed: a duplicate
       -- delivery returns NULL / 0 rows). None of app_api, app_billing_webhook_ingress,
       -- or app_platform_admin has any direct INSERT/UPDATE/DELETE grant on
       -- payment_webhook_receipts (§12.4, FB-6K-03/04, FREEZE-6K-01) — this function
       -- is the only WRITE path reachable by anyone; app_platform_admin retains
       -- SELECT-only (narrow support/incident-response reading, not a bypass).
       -- No role holds DELETE at all.
    → fast 2xx ACK returned immediately after the function call returns (never after domain
      processing, mirrors 6J §24.4)
    → async processing enqueued IF AND ONLY IF the function returned a non-NULL id (mirrors
      6J §24.3's exact enqueue-gating discipline)
    → async (Celery, app_worker): fn_process_payment_webhook_receipt(receipt_id, 'PROCESSING',
       provider_transaction_id)
       → normalize provider payload → the function ITSELF resolves the ORIGINATING
         payment_attempts row from provider_transaction_id (never a caller-supplied
         attempt id) → derives organization_id from that row's own invoice_id →
         invoices.organization_id internally, cross-checking the receipt's own
         payment_provider matches the resolved attempt's provider (§30.3/§39, FB-6K-07 —
         a cross-provider linkage attempt resolves NULL, fails closed)
       → §30.6's amount/currency verification (application layer, comparing the verified
         payload against the resolved payment_attempts row)
       → billing.fn_update_payment_status(...) (057_5H, unchanged) → on SUCCEEDED:
         billing.fn_mark_invoice_paid(...)
       → fn_process_payment_webhook_receipt(receipt_id, 'PROCESSED'/'FAILED', ...) to close
         out the receipt
       + audit PAYMENT_SUCCEEDED/PAYMENT_FAILED + outbox 'invoice.paid'/'payment.failed' (same transaction, §45)
```

- **Auth:** none (JWT) — the caller is the provider, not a tenant, exactly as 6A §28.2's carve-out and 6J §24.6 already establish for every other inbound-provider callback.
- **Verification:** `PaymentProviderPort.verify_webhook` (4I §13.2, adapter-specific — Razorpay's own HMAC scheme, Cashfree's own) against a platform-held webhook secret (resolved via `CredentialRef`, 4I §13.5 — never a tenant-configured secret, since there is no tenant `IntegrationConnection` here). An unverified webhook is discarded and logged, never reaching a domain command (4I §13.5, verbatim) — no `payment_webhook_receipts` row is ever created for a signature that failed verification; `fn_record_payment_webhook_receipt` is never called until after verification succeeds — this function is a durability/dedup layer, never itself a security boundary against a forged payload.
- **Rate limiting:** layered exactly per 6J §24.6's own scheme — edge per-source-IP, then a global per-`provider_slug` ceiling — the tenant API quota system never applies here (6A §28.2's carve-out, restated for this endpoint too).

### 30.3 Tenant Resolution Sequence — Never Trust the Payload First

Mirroring 6J §24.6's corrected resolution sequence (ADR-6J-10) exactly, applied to a platform-level relationship instead of a per-connection one:

1. `provider_slug` (path segment) selects which adapter's verification material to use — routing only, establishes nothing about authenticity yet.
2. That adapter's `verify_webhook` call succeeds or fails against the platform-held secret.
3. **Only after verification succeeds** does the durable-receipt call happen (§30.2, via `fn_record_payment_webhook_receipt`), and only in async processing does `fn_process_payment_webhook_receipt` — supplied only a `provider_transaction_id` extracted from the verified payload — internally resolve the *originating* `payment_attempts` row (created server-side by `fn_create_payment_attempt` at §29.4, when the platform itself initiated the intent) and, through it, `organization_id` (`invoice_id → invoices.organization_id`) — cross-checking the receipt's own `payment_provider` matches the resolved attempt's provider before trusting the linkage at all (a cross-provider attempt resolves `NULL`, fails closed, live-confirmed). `payment_webhook_receipts.payment_attempt_id`/`.organization_id` are populated exclusively by this internal resolution, never from a caller-supplied value — the function's own signature no longer even accepts one (§12.4, FB-6K-07). The webhook payload's own claimed org/invoice identity, if any, is never itself the trust anchor — exactly 6J §24.6's confused-deputy correction, applied here.
4. If step 2 fails, the request is rejected/silently dropped per the provider's own expected contract — never processed as if step 3 had succeeded.

### 30.4 Deduplication

`UNIQUE (payment_provider, provider_event_id)` on `billing.payment_webhook_receipts` (§12.4, `uq_pwr_provider_event`, deliberately **not** `DEFERRABLE` — the atomic `ON CONFLICT` dedup gate requires an immediate constraint) is the actual DB-level guarantee — live-confirmed: the identical duplicate delivery to `fn_record_payment_webhook_receipt` returns `NULL` on the second call, and the async processing task is enqueued **if and only if** the first call returned a non-`NULL` id, mirroring 6J §24.3's exact enqueue-gating discipline.

### 30.5 Webhook Receipt vs. Originating Attempt — Two Separate Rows, Two Separate Concerns

A `payment_webhook_receipts` row is the durable record of *having received this exact webhook delivery* (created fresh, once per unique `(payment_provider, provider_event_id)`, §30.4, via the narrow ingress function only). The *financial* state transition happens on the pre-existing `payment_attempts` row `fn_create_payment_attempt` already created (`INITIATED`/`PENDING`) — via `billing.fn_update_payment_status` (5H §57, unchanged), which is itself idempotent for a same-terminal-status replay (5H's own existing guarantee, confirmed in §9.1's audit) and rejects an illegal transition (`SUCCEEDED → FAILED`) outright. The two tables are linked once `fn_process_payment_webhook_receipt`'s own internal resolution succeeds (§30.3) — this two-table split is what makes both "did we ever receive this webhook before" (receipt-level, always answerable even before any attempt is resolved) and "what is this payment's current state" (attempt-level, the actual financial truth) independently and atomically correct, rather than conflating the two into one row's mutation.

### 30.6 Amount / Currency Verification — Mandatory

Per task §35: the webhook handler compares the provider-reported settled amount/currency against `payment_attempts.amount_amount`/`amount_currency` (the value `fn_create_payment_attempt` computed server-side at §29.4, never client-supplied) **before** calling `fn_mark_invoice_paid`. A mismatch (provider claims ₹1 settled against a ₹10,000 `payment_attempts` row) is treated as `FAILED`. The classification stored in `payment_attempts.failure_code` for this case is a **distinct, internal-only governed vocabulary** — never conflated with the customer-facing, provider-normalized `FailureCode` enum (§9.4/§29.7): `AMOUNT_MISMATCH | CURRENCY_MISMATCH | UNKNOWN_TRANSACTION_CORRELATION` (§36). This is never presented to the customer as a card-decline-shaped reason (a mismatch is a security anomaly, not a customer-actionable payment failure) — the tenant-facing `GET /billing/payments` response (§29.6) surfaces it only as a generic `GATEWAY_ERROR`-shaped message ("payment could not be verified — contact support"), while the internal classification drives alerting (§40/§42). Never a partial success, never a proportional credit applied automatically.

### 30.7 State Machine and Concurrency (Task §36–§37)

Payment-attempt state machine reused verbatim from 5H §57/§17.2 (confirmed in §9.1's audit, unaffected by this migration): `INITIATED → PENDING → SUCCEEDED | FAILED | CANCELLED`, no state string beyond these five, enforced entirely inside `fn_update_payment_status`'s own transition table. The webhook-receipt state machine (`billing.payment_webhook_receipts.processing_status`, §12.4) is a **separate, new, smaller** machine — `RECEIVED → PROCESSING → PROCESSED | FAILED` — governing only "have we finished handling this delivery," never conflated with the payment's own financial state (§30.5). **Races** (manual client retry + provider webhook + a reconciliation-worker `get_status` poll, all arriving concurrently) are resolved the same way 5H already guarantees: `fn_update_payment_status`'s `SELECT ... FOR UPDATE` on the target `payment_attempts` row serializes all three callers, and its terminal-state idempotency (same-terminal-status = no-op, different-terminal-status = exception) guarantees exactly one successful settlement ever reaches `fn_mark_invoice_paid` for a given invoice — the second caller to reach the `FOR UPDATE` lock either finds the row already terminal (no-op) or finds `invoices.status` already `PAID` (its own `fn_mark_invoice_paid` call then raises, per 5H §57's own `v_status <> 'OPEN'` guard, confirmed in the frozen DDL). Both state machines, and their interaction, are live-tested end to end (§12.8).

---

## 31. Refunds

### 31.1 `GET /api/v1/billing/refunds` / `GET /api/v1/billing/refunds/{refund_id}`

- **Permission:** `invoice:read`.
- **Response:** `{id, payment_attempt_id, amount: Money, reason, status, initiated_at, completed_at}`.

### 31.2 No Tenant-Initiated Refund Creation in V1

Per task §38: no frozen source in 4F/4I/5H grants ordinary tenants a self-service refund trigger, and none is invented here — refund creation is a support/admin action, handed to 6M (§41), which will call the existing `billing.fn_billing_create_refund`-equivalent path (5H names this function in its own security-matrix table, §20, as the sole legal `credits`-adjacent write path for refunds — reused unchanged; note 5H's actual migration 055 DDL implements refund-amount validation via `fn_validate_refund_amount` as a table trigger rather than requiring every refund to route through a single named creation function, so 6M's own write path is: `INSERT INTO billing.refunds` under `app_worker`/`app_platform_admin`'s existing grant, guarded by that trigger — no new function is required by 6K, and none is added in §12).

### 31.3 Refund Invariants (Reused Verbatim)

Must reference a `SUCCEEDED` `payment_attempts` row; sum of `PENDING`+`SUCCEEDED` refunds for one payment must never exceed the original `amount_amount` (`fn_validate_refund_amount`, 5H §55, confirmed unchanged); idempotent via `UNIQUE (payment_provider, provider_refund_id)`; goes through `PaymentProviderPort.refund(...)` (4I §13.2); produces a `REFUND_CREDIT`-type `credits` row where the refund is issued as account credit rather than a reversed charge (5H §14.2, application-service decision, not decided by this document which of "reversed charge" vs. "credit" applies per case — that is a support-workflow policy question outside 6K's scope).

---

## 32. Multi-Currency (INR-First)

Per task §40/§32: `billing_accounts.currency` is immutable (`fn_ba_currency_immutable`, confirmed in §9.1) and every monetary value on every endpoint in this document is the `{amount, currency}` pair (§43's Money DTO, matching 6A §7.5). No endpoint in this document accepts a client-chosen invoice currency different from the account's own — "pay this specific invoice in a different currency than my account" is explicitly **not** a V1 capability (5H ODD-5H-10), and no `payment-intent` request body field in §29.4 offers one. `cost_entries`' own FX handling (provider cost in USD, converted to billing currency with a captured `fx_rate_used`, 5H §7) is internal-only (§24) — never surfaced to a tenant. The architecture is multi-currency-*capable* (a different org could have `currency = 'USD'` and every mechanism in this document — pricing resolution, invoice generation, payment intent — works identically per-account) without any V1 code path letting one invoice mix currencies or letting a client pick one ad hoc.

---

## 33. Billing Summary and Projected Charges

### 33.1 `GET /api/v1/billing/summary`

- **Permission:** `billing:read`.
- **Purpose:** one bounded dashboard read, entirely from already-materialized platform state — no synchronous provider call (task §73).
- **Response `200`:**
```json
{
  "data": {
    "subscription": { "status": "ACTIVE", "plan_name": "Growth", "pricing_source": "AGREEMENT" },
    "current_period": { "period_start": "2026-08-01", "period_end": "2026-09-01" },
    "estimated_usage_charge": { "amount": "4820.0000", "currency": "INR" },
    "credit_balance": { "amount": "0.0000", "currency": "INR" },
    "open_invoice": { "id": "...", "total_due": { "amount": "12999.0000", "currency": "INR" }, "due_date": "2026-08-15" } ,
    "payment_status": "NONE_PENDING"
  },
  "meta": { "request_id": "..." }
}
```

### 33.2 Projected Charges Are Always Labeled Estimates

Per task §74: `estimated_usage_charge` is never called `amount_due` and always carries the field name `estimated_usage_charge`, never presented alongside a false precision claim — late usage (§22.4), credits applied at finalization, tax, proration, and further consumption before period close can all change the final invoiced amount. `open_invoice.total_due`, by contrast, is authoritative (it is a real, already-finalized `OPEN` invoice's server-computed total) — the two fields are never conflated in the same response field.

### 33.3 Cost Breakdown Boundary

Per task §75: the only breakdown this endpoint (or any endpoint in this document) ever shows is the customer's own charge composition — `subscription` (base fee), `usage`/`overage`, `discount` (if ever populated, §27), `tax`, `credit`. It never shows provider procurement cost, FX spread, or platform gross margin (§24) — that breakdown, if built, is 6L/6M's internal endpoint, not this one.

---

## 34. Endpoint Inventory

Money values below are always the `{amount, currency}` DTO (6A §7.5, §43's restatement); every listed path is prefixed `/api/v1`.

| Method | Path | Purpose | Permission | Idempotency-Key | Async | Audit |
|---|---|---|---|---|---|---|
| GET | `/billing/account` | Own billing account | `billing:read` | — | No | — |
| PATCH | `/billing/account` | Update billing contact | `billing:manage` | No | No | `BILLING_ACCOUNT_CONTACT_UPDATED` |
| GET | `/billing/plans` | List published plans | `organization:read` | — | No | — |
| GET | `/billing/plans/{plan_id}` | Plan detail + prices | `organization:read` | — | No | — |
| GET | `/billing/subscription` | Own subscription | `billing:read` | — | No | — |
| POST | `/billing/subscription` | Create subscription | `billing:manage` | **Required** | No | `SUBSCRIPTION_CREATED` |
| POST | `/billing/subscription/change-plan` | Upgrade/schedule downgrade | `billing:manage` | **Required** | No | `SUBSCRIPTION_PLAN_CHANGED` |
| POST | `/billing/subscription/cancel` | Cancel at period end | `billing:manage` | **Required** | No | `SUBSCRIPTION_CANCELLED` |
| GET | `/billing/periods` | List billing periods | `billing:read` | — | No | — |
| GET | `/billing/periods/{period_id}` | Period detail | `billing:read` | — | No | — |
| GET | `/billing/usage` | Per-metric usage | `billing:read` | — | No | — |
| GET | `/billing/usage/summary` | Current-period rollup | `billing:read` | — | No | — |
| GET | `/billing/quotas` | Quota status | `billing:read` | — | No | — |
| GET | `/billing/invoices` | List invoices | `invoice:read` | — | No | — |
| GET | `/billing/invoices/{invoice_id}` | Invoice detail | `invoice:read` | — | No | — |
| POST | `/billing/invoices/{invoice_id}/payment-intent` | Initiate payment | `billing:manage` | **Required** | No (202, provider round-trip is async) | `PAYMENT_ATTEMPTED` |
| GET | `/billing/payments` | List payment attempts | `invoice:read` | — | No | — |
| GET | `/billing/payments/{payment_attempt_id}` | Payment attempt detail | `invoice:read` | — | No | — |
| GET | `/billing/refunds` | List refunds | `invoice:read` | — | No | — |
| GET | `/billing/refunds/{refund_id}` | Refund detail | `invoice:read` | — | No | — |
| GET | `/billing/credits` | List credits + balance | `billing:read` | — | No | — |
| GET | `/billing/summary` | Dashboard rollup | `billing:read` | — | No | — |
| POST | `/billing/payment-providers/{provider_slug}/webhook` | Inbound provider webhook | None (provider-signed, §30) | N/A (provider dedup key) | Yes (fast-ACK, async processing) | `PAYMENT_SUCCEEDED`/`PAYMENT_FAILED` |

Every endpoint above is authenticated (6A §9.1's pipeline) except the last, which is 6A §28.2's explicit inbound-provider carve-out. Every `GET` on a per-resource path (`{invoice_id}`, `{payment_attempt_id}`, `{refund_id}`, `{period_id}`) is tenant-scoped (RLS + explicit ownership check) and returns `404 RESOURCE_NOT_FOUND`, not `403`, for a cross-tenant ID (6A §9.2, 6B's established convention, §37).

---

## 35. Internal (Non-REST) Contracts

Per task §77 — not every 6K operation is an HTTP endpoint:

| Contract | Trigger | Consumes | Produces |
|---|---|---|---|
| Usage ingestion consumer | Redis Streams (outbox-published) | `call.ended`, `conversation.turn_completed`, `document.indexed`, `campaign.contact.call_attempted`, `workflow.execution.completed` | `billing.usage_events` rows (§22) |
| Quota reconciliation worker | Scheduled (nightly) | `billing.usage_records` | Rewritten Redis `quota:{org_id}:{metric}` counters (§25.2) |
| Subscription renewal worker | Scheduled (per subscription's `current_period_end`) | `subscriptions`, `scheduled_change_*` | New `billing_periods` row (pinned per §13.3), applies scheduled downgrade, triggers invoice generation |
| Invoice generation worker | Billing-period close (renewal worker, or manual admin trigger via 6M) | §26.1's deterministic input set | `DRAFT`→`OPEN` invoice, `invoice.created` outbox event |
| Payment webhook processor | `POST /billing/payment-providers/{slug}/webhook` (§30) fast-ACK, then async | Verified provider payload | `payment_attempts` status transition, `invoice.paid`/`payment.failed` outbox events |
| Cost recording ingestion | Provider usage/billing API poll (adapter-specific, out of this document's scope — mirrors `cost_entries`' existing 5H shape) | Provider cost data | `billing.cost_entries` rows (§24, internal-only) |
| Credit expiry job | Scheduled (daily) | `credits.expires_at` | `status = 'EXPIRED'` + compensating `credit_ledger_entries` row (5H §14.3, unchanged) |
| Outbox publisher | Continuous (Celery worker pool) | `audit.domain_event_outbox` (`fn_claim_outbox_events`) | Redis Streams publish + `fn_mark_outbox_published`/`fn_mark_outbox_failed` (5J §077, unchanged, reused by every 6K producer) |

None of these are documented in the public OpenAPI surface (6A §31); none are reachable via a tenant JWT.

---

## 36. Error Catalog

Reconciled against 6A §24.2's illustrative families and 6B §22's concrete table — no code below collides with either.

| HTTP | `code` | Meaning | Retryable | Applicable endpoints |
|---|---|---|---|---|
| 404 | `BILLING_ACCOUNT_NOT_FOUND` | No billing account for this org (should not occur post-provisioning) | No | `/billing/account` |
| 403 | `BILLING_ACCOUNT_SUSPENDED` | Account `SUSPENDED`; billable operations blocked per DEC-6K-03's grace policy (§48) | No | Any billable-action endpoint |
| 404 | `PLAN_NOT_FOUND` | `plan_id` doesn't exist or `is_active = FALSE` | No | `/billing/plans/{id}`, subscription create/change |
| 409 | `PLAN_VERSION_NOT_AVAILABLE` | Plan exists but has no published version | No | Subscription create/change |
| 409 | `SUBSCRIPTION_ALREADY_ACTIVE` | `TRIAL`/`ACTIVE` subscription already exists (`uq_sub_org_active`) | No | `POST /billing/subscription` |
| 404 | `SUBSCRIPTION_NOT_FOUND` | No subscription for this org | No | `/billing/subscription/*` |
| 409 | `SUBSCRIPTION_CANCELLED` | Subscription is terminal (`INV-BILL-06`) | No | `/billing/subscription/*` |
| 409 | `PLAN_CHANGE_NOT_ALLOWED` | Target plan invalid for a change (inactive, unpublished, or an agreement-plan mismatch not yet reconciled) | No | `change-plan` |
| 404 | `PRICING_AGREEMENT_NOT_FOUND` | Internal — a pinned `commercial_pricing_agreement_version_id` no longer resolves (should not occur; immutability guarantees this) | No | Internal only |
| 409 | `PRICING_AGREEMENT_NOT_ACTIVE` | §13.3's period-open **new-pinning** resolution found no `ACTIVE` version valid as of the period start (falls back to plan pricing — not itself an error condition at that call site). **Never** raised when reading an already-pinned historical FK (§14) — a `SUPERSEDED`/`EXPIRED` version resolves identically to an `ACTIVE` one on read, live-confirmed | No | Internal only |
| 400 | `PRICING_CURRENCY_MISMATCH` | Agreement currency ≠ billing account currency (should be rejected at creation, §12.5 — defensive) | No | Internal only |
| 429 | `QUOTA_EXCEEDED` | Hard limit reached, no overage priced/allowed | No | 6D/6H's own initiation endpoints (billing-owned code, foreign surface, §25.2) |
| 404 | `INVOICE_NOT_FOUND` | Cross-tenant or nonexistent invoice ID | No | `/billing/invoices/{id}`, `payment-intent` |
| 409 | `INVOICE_NOT_PAYABLE` | Invoice not `OPEN` (still `DRAFT`, or `VOID`) | No | `payment-intent` |
| 409 | `INVOICE_ALREADY_PAID` | Invoice already `PAID` | No | `payment-intent` |
| 409 | `PAYMENT_ALREADY_IN_PROGRESS` | A non-terminal `payment_attempts` row already exists for this invoice | Yes (poll existing attempt) | `payment-intent` |
| 503 | `PAYMENT_PROVIDER_UNAVAILABLE` | Adapter call failed/timed out before a `payment_attempts` row could reach `PENDING` | Yes | `payment-intent` |
| 402 | `PAYMENT_FAILED` | Terminal provider failure, normalized `FailureCode` in `details` | No | `payment-intent` (via async result), webhook |
| 409 | `PAYMENT_AMOUNT_MISMATCH` | Webhook-reported amount ≠ `payment_attempts.amount_amount` (§30.6). Internal-only classification, distinct from the customer-facing `FailureCode` enum (§9.4) — never presented to a tenant as a card-decline-shaped reason | No | Webhook only (never client-facing) |
| 409 | `PAYMENT_CURRENCY_MISMATCH` | Webhook-reported currency ≠ `payment_attempts.amount_currency`. Same internal-only classification discipline as above | No | Webhook only |
| 409 | `UNKNOWN_TRANSACTION_CORRELATION` | A verified webhook's `provider_transaction_id` does not resolve to any originating `payment_attempts` row (task §35's "unknown transaction correlation" — a security-relevant anomaly, e.g. a stale/replayed provider environment) | No | Webhook only |
| 409 | `REFUND_NOT_ALLOWED` | No `SUCCEEDED` payment to refund against | No | Internal/6M only |
| 409 | `REFUND_AMOUNT_EXCEEDED` | Would exceed refundable balance (`fn_validate_refund_amount`) | No | Internal/6M only |
| 402 | `CREDIT_INSUFFICIENT` | N/A in V1 (credits never block an operation, only reduce a total, floor at zero — reserved for a future credit-gated feature) | No | Reserved |
| 409 | `IDEMPOTENCY_KEY_REUSE_MISMATCH` | 6A §16.2/6B §22 code, reused verbatim | No | Every Idempotency-Key-bearing POST above |
| 404 | `RESOURCE_NOT_FOUND` | Cross-tenant reference, 6A §9.2 convention | No | Every per-ID `GET` above |

All other cross-cutting codes (`VALIDATION_ERROR`, `AUTHENTICATION_REQUIRED`, `AUTHORIZATION_DENIED`, `RATE_LIMIT_EXCEEDED`, `DEPENDENCY_UNAVAILABLE`, `INTERNAL_ERROR`) are 6A §24.2's own family, reused without a billing-specific redefinition.

---

## 37. Authorization Matrix

| Endpoint | Principal | Org Scope | Permission | Ownership Check | Financial Sensitivity |
|---|---|---|---|---|---|
| `GET /billing/account` | `USER` | Own | `billing:read` | RLS | Low (contact info, status) |
| `PATCH /billing/account` | `USER` | Own | `billing:manage` | RLS | Low |
| `GET /billing/plans[/{id}]` | `USER` | Platform-global | `organization:read` | N/A (no RLS on `plans`) | None |
| `GET /billing/subscription` | `USER` | Own | `billing:read` | RLS | Medium |
| `POST /billing/subscription` | `USER` | Own | `billing:manage` | RLS + `uq_sub_org_active` | High |
| `POST /billing/subscription/change-plan` | `USER` | Own | `billing:manage` | RLS | High |
| `POST /billing/subscription/cancel` | `USER` | Own | `billing:manage` | RLS | High |
| `GET /billing/periods[/{id}]` | `USER` | Own | `billing:read` | RLS + explicit ID check | Medium |
| `GET /billing/usage[/summary]` | `USER` | Own | `billing:read` | RLS | Medium |
| `GET /billing/quotas` | `USER` | Own | `billing:read` | RLS | Low |
| `GET /billing/invoices[/{id}]` | `USER` | Own | `invoice:read` | RLS + explicit ID check | High |
| `POST /billing/invoices/{id}/payment-intent` | `USER` | Own | `billing:manage` | RLS + explicit ID check | **Critical** |
| `GET /billing/payments[/{id}]` | `USER` | Own | `invoice:read` | RLS + explicit ID check | High |
| `GET /billing/refunds[/{id}]` | `USER` | Own | `invoice:read` | RLS + explicit ID check | High |
| `GET /billing/credits` | `USER` | Own | `billing:read` | RLS | Medium |
| `GET /billing/summary` | `USER` | Own | `billing:read` | RLS | Medium |
| `POST /billing/payment-providers/{slug}/webhook` | `PROVIDER` (unauthenticated, signature-verified) | Resolved post-verification (§30.3) | N/A | Explicit, post-verification only | **Critical** |
| §12's seven `SECURITY DEFINER` functions (commercial pricing lifecycle, payment linkage, late-usage adjustment) | `WORKER` / `PLATFORM_ADMIN` only | Cross-tenant (admin) | N/A (actor-type check, not RBAC — §17) | N/A / `BYPASSRLS`, audited separately (5B) — no `app_api` grant on any, live-confirmed §12.8 | **Critical** |

Confirms task §81/§50's requirement directly: no `VIEWER`-level role holds `billing:read`, `billing:manage`, or `invoice:read` in 5B's seeded matrix (§9.1's authorization-matrix source, §6B's own confirming table) — a `VIEWER` cannot reach any endpoint in this document. `billing:manage` is held only by `OWNER` and `BILLING_ADMIN` — not `ADMIN` (5B §2381: `ADMIN` gets `billing:read`/`invoice:read` but not `billing:manage`) — so an ordinary `ADMIN` can see billing state but cannot initiate a subscription change or a payment; this is 5B's own frozen grant, not a new restriction invented here.

---

## 38. Database Traceability

| API Resource / Operation | Table(s) | Function(s) | Migration | Status |
|---|---|---|---|---|
| Billing account read/update | `billing.billing_accounts` | `set_updated_at` (trigger) | 048_5H | EXISTING |
| Plan catalog | `billing.plans`, `plan_versions`, `plan_prices` | — | 047_5H | EXISTING |
| Commercial pricing agreement | `billing.commercial_pricing_agreements` | `fn_create_commercial_pricing_agreement`, `fn_cpa_identity_immutable` (trigger) — `SELECT`-only for every role incl. `app_platform_admin` (freeze-gate hardened, FB-6K-01) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Commercial pricing agreement version | `billing.commercial_pricing_agreement_versions` | `fn_create_commercial_pricing_agreement_version`, `fn_activate_commercial_pricing_agreement_version`, `fn_expire_commercial_pricing_agreement_version`, `fn_cpav_immutability` (trigger) — `SELECT`-only for every role incl. `app_platform_admin` (freeze-gate hardened, FB-6K-01/02) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Commercial pricing metric override | `billing.commercial_pricing_metrics` | `fn_cpm_parent_draft_guard` (trigger) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Subscription lifecycle | `billing.subscriptions` | `fn_sub_cancelled_terminal` (trigger) | 049_5H | EXISTING |
| Subscription agreement pin | `subscriptions.commercial_pricing_agreement_version_id` | `fn_bp_agreement_plan_consistency` (trigger, shared with billing_periods) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Billing period | `billing.billing_periods` | — | 049_5H | EXISTING |
| Billing period agreement pin | `billing_periods.commercial_pricing_agreement_version_id` | `fn_bp_agreement_plan_consistency` (trigger) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Usage ingestion | `billing.usage_events` | — (constraint-only idempotency; metric-suffixed `source_event_id` convention, §22.2, no DDL change); `app_api` `INSERT` revoked (freeze-gate broader audit, Part G) | 050_5H | EXISTING (convention fix + grant hardening) |
| Exact-aggregate call billing | `usage_events.source_quantity_seconds` (new) | — (CHECK-enforced, `chk_ue_source_quantity_seconds`, strengthened to require non-`NULL` for `CALL_MINUTES`) | **102_5H2** | **NEW 6K PATCH — live-validated (FB-6K-06, FINAL-6K-02)** |
| Usage aggregation | `billing.usage_records` | — | 050_5H | EXISTING |
| Quota read/enforcement | `billing.quota_configs` | — | 052_5H | EXISTING |
| Credits | `billing.credits`, `credit_ledger_entries` | `fn_billing_apply_credit` — `app_worker` direct `INSERT` on both revoked, reconciled with 5H's own §20 intent (freeze-gate broader audit, Part G) | 053_5H | EXISTING + **grant hardened, 102_5H2** |
| Invoices | `billing.invoices` | `fn_finalize_invoice`, `fn_mark_invoice_paid`, `fn_void_invoice` | 054_5H, 057_5H | EXISTING |
| Invoice line provenance | `invoice_lines.unit_price_source`, `.included_quantity_source`, `.commercial_pricing_agreement_version_id` | — (CHECK-enforced, `chk_il_pricing_provenance`); `app_api` `INSERT` on `invoice_lines`/`tax_lines` revoked (Part G) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Invoice number allocation | `billing.invoice_number_sequences` | `fn_allocate_invoice_number` | 052_5H | EXISTING |
| Tax | `billing.tax_profiles`, `tax_categories`, `tax_rules`, `tax_lines` | — | 047_5H, 052_5H, 054_5H | EXISTING |
| Payment attempts | `billing.payment_attempts` | `fn_update_payment_status` (unchanged, confirmed still one overload); `fn_link_payment_provider_transaction` (new); `fn_create_payment_attempt` (new, `app_api`-callable, FB-6K-05) — `app_api` direct `INSERT` revoked | 055_5H, 057_5H; **102_5H2** | EXISTING + **NEW 6K PATCH — live-validated** |
| Payment-attempt schema fix | `payment_attempts.provider_transaction_id` (now nullable), `.payment_method_kind` (new) | `fn_link_payment_provider_transaction`, `fn_create_payment_attempt` | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Inbound payment-webhook durability | `billing.payment_webhook_receipts` | `fn_process_payment_webhook_receipt` (internally-deriving linkage, FB-6K-07); `fn_record_payment_webhook_receipt` (new — `EXECUTE` restricted to the dedicated `app_billing_webhook_ingress` role only, FB-6K-03/04 + FINAL-6K-01) — `app_api` direct `SELECT`/`INSERT` on the table revoked, `app_api`/`app_platform_admin` `EXECUTE` on the function also revoked, and `app_platform_admin`'s raw `INSERT`/`UPDATE`/`DELETE` on the table itself also revoked (`SELECT`-only retained, FREEZE-6K-01) — no role holds `DELETE` at all | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Refunds | `billing.refunds` | `fn_validate_refund_amount` (trigger) — `app_api` direct `INSERT` revoked (Part G) | 055_5H | EXISTING + **grant hardened, 102_5H2** |
| Billing adjustments | `billing.billing_adjustments` | `fn_create_billing_adjustment` (existing, unedited) | 056_5H, 086_5H1 | EXISTING |
| Late-usage adjustment provenance | `billing_adjustments.late_usage_billing_period_id`, `.late_usage_metric`, `.late_usage_provenance` | `fn_create_late_usage_billing_adjustment` (new, separate from `fn_create_billing_adjustment`) | **102_5H2** | **NEW 6K PATCH — live-validated** |
| Cost entries | `billing.cost_entries` | — `app_api` direct `INSERT` revoked (Part G) | 051_5H | EXISTING + **grant hardened, 102_5H2** |
| Outbox producer path | `audit.domain_event_outbox` | `fn_claim_outbox_events`, `fn_mark_outbox_published`, `fn_mark_outbox_failed` | 077_5J1 | EXISTING |
| Audit trail | `audit.audit_events` | `fn_insert_audit_event` | 067–075_5J | EXISTING |
| `SubscriptionItem` / add-ons | — | — | — | **FUTURE 6M ADMIN SURFACE** (not built, §9.3) |
| Plan/PlanVersion/PlanPrice administration | `billing.plans`, `plan_versions`, `plan_prices` | — (existing `app_platform_admin` grants) | 047_5H | **FUTURE 6M ADMIN SURFACE** (REST layer only — DB layer already exists) |
| Manual credit issuance REST surface | `billing.credits` | `fn_billing_apply_credit` | 053_5H | **FUTURE 6M ADMIN SURFACE** |
| Billing account suspend/reactivate override REST surface | `billing.billing_accounts` | — | 048_5H | **FUTURE 6M ADMIN SURFACE** |
| Commercial pricing agreement administration REST surface | `billing.commercial_pricing_agreements`/`...versions`/`...metrics` | §12.5's functions (DB layer already exists) | **102_5H2** | **FUTURE 6M ADMIN SURFACE** (REST layer only) |

---

## 39. Test Matrices

### 39.1 Pricing Resolution (Task §87 — Test Values Only)

**Fixture:** Global plan — base ₹10,000; `CALL_MINUTES` ₹2/min; `CAMPAIGN_CALLS` unpriced. Org A agreement — base ₹75,000; `CALL_MINUTES` ₹3/min; `CAMPAIGN_CALLS` ₹1/call. Org B — no agreement.

| Case | Expected effective pricing |
|---|---|
| Org A, agreement `ACTIVE` covering the period | base ₹75,000; `CALL_MINUTES` ₹3/min; `CAMPAIGN_CALLS` ₹1/call — the agreement, in full |
| Org B, no agreement ever created | Global plan pricing — base ₹10,000; `CALL_MINUTES` ₹2/min; `CAMPAIGN_CALLS` unpriced |
| Org A, agreement `EXPIRED` before the period's `period_start` | Falls back to global plan pricing for that period (§13.3 step 3 finds 0 rows) |
| Org A, agreement v2 activated mid-way, a new period opens after v2's `effective_from` | New period pins v2's terms |
| Org A, a historical `PAID` invoice generated during v1's tenure, queried after v2 exists | Unchanged — invoice line amounts reflect v1's snapshotted rates (§14), never recomputed against v2 |

### 39.2 No Double-Bill (Task §88)

Covered exhaustively in §26.2.1's worked table — reproduced here as the required pass/fail assertion: usage of `10 CALL_MINUTES` + `5 CAMPAIGN_CALLS` produces exactly the charge implied by which of the two metrics has a non-null `effective_overage_rate`, never more, never for an unpriced metric.

### 39.3 Invoice Determinism (Task §89)

After an invoice is finalized (`OPEN`/`PAID`): publishing a new global `PlanVersion`, creating a new `CommercialPricingAgreementVersion` for the same org, or updating a `tax_rules` row for a future `effective_from` must each leave the already-finalized invoice's `subtotal_amount`/`total_tax_amount`/`total_due_amount` and every `invoice_lines`/`tax_lines` row numerically unchanged — guaranteed structurally by `fn_invoice_immutability` (existing), `fn_plan_version_immutability` (existing), `fn_cpav_immutability` (§12.2, new), and `tax_rules.effective_from` never applying retroactively (5H, unchanged).

### 39.4 Payment Security Matrix (Task §90)

| Scenario | Expected result |
|---|---|
| Client sends a wrong invoice amount to `payment-intent` | Impossible — amount is server-computed inside `fn_create_payment_attempt`, request body has no amount field |
| Client sends a wrong currency | Impossible — currency is server-computed |
| Client attempts a raw `INSERT` into `payment_attempts` directly (bypassing the API) | **Impossible** — `app_api` has no `INSERT` grant on this table at all (FB-6K-05, live-confirmed) |
| Duplicate `payment-intent` call, same `Idempotency-Key` | Cached response returned, no second `payment_attempts` row (§29.5) |
| Provider timeout, outcome unknown | Reconciliation worker calls `get_status` before any new attempt is created (§29.5) |
| Provider webhook arrives before the `payment-intent` response reaches the client | Handled correctly — the webhook path resolves and updates the already-`INITIATED` row via `provider_transaction_id` (`fn_process_payment_webhook_receipt`, §30.3); the client's own poll/response path reads the same row's eventual state |
| Duplicate provider webhook | `uq_pwr_provider_event` (atomic `ON CONFLICT`, `fn_record_payment_webhook_receipt`) + `fn_update_payment_status`'s same-terminal idempotency → no-op (§30.4/§30.7) |
| Forged webhook signature | `verify_webhook` fails → discarded, never reaches `fn_record_payment_webhook_receipt` at all (§30.2) |
| A tenant attempts to read/manufacture a webhook receipt directly | **Impossible** — `app_api` has no `SELECT`/`INSERT` grant on `payment_webhook_receipts` at all (FB-6K-03/04, live-confirmed) |
| A tenant (`app_api`) attempts to call `fn_record_payment_webhook_receipt` itself, to pre-claim a real provider event ID before the genuine webhook arrives | **Impossible** — `app_api` (and `app_worker`, and `app_platform_admin`) has no `EXECUTE` grant on this function; only the dedicated `app_billing_webhook_ingress` role can call it (FINAL-6K-01, live-confirmed) |
| `app_platform_admin` attempts a raw `INSERT`/`UPDATE`/`DELETE` directly on `payment_webhook_receipts`, bypassing the dedicated ingress/processing functions entirely | **Impossible** — `app_platform_admin` holds `SELECT` only on this table; all three raw-DML attempts are `permission denied` (FREEZE-6K-01, live-confirmed) |
| Any role attempts `DELETE` on `payment_webhook_receipts` | **Impossible for every role** — no role (`app_api`, `app_billing_webhook_ingress`, `app_worker`, `app_platform_admin`) holds `DELETE`; archival/retention is a separately governed operation, not a runtime grant (FREEZE-6K-01) |
| Webhook amount mismatch | `AMOUNT_MISMATCH`, marked `FAILED`, invoice never marked paid (§30.6) |
| Webhook currency mismatch | `CURRENCY_MISMATCH`, same handling |
| Webhook references an unknown/never-issued `provider_transaction_id` | `fn_process_payment_webhook_receipt` resolves `NULL`, recorded `FAILED`/`UNKNOWN_TRANSACTION_CORRELATION` (§30.3/§36, live-confirmed, FB-6K-07) |
| A verified webhook's provider disagrees with the resolved attempt's own provider (cross-provider linkage) | Resolves `NULL`, fails closed — never silently links (§30.3, live-confirmed) |
| Webhook/payment for another tenant's invoice | Structurally impossible post-§30.3 — tenant context is derived from the *originating* `payment_attempts` row, never the webhook payload's own claim |
| Payment attempted after invoice already `PAID` | `409 INVOICE_ALREADY_PAID` at `payment-intent`; `fn_mark_invoice_paid`'s own `v_status <> 'OPEN'` guard rejects a stray webhook reaching this state too |
| Provider switch mid-flight, historical payment queried | Historical `payment_attempts.payment_provider`/`provider_transaction_id` unchanged (§29.1/task §39) |
| Double refund | `fn_validate_refund_amount` rejects the second refund once the sum would exceed the original payment (5H §55, unchanged) |
| A tenant attempts a raw `INSERT` into `refunds` directly | **Impossible** — `app_api` has no `INSERT` grant on this table (freeze-gate broader audit, live-confirmed) |

---

## 40. Threat Model

| Threat | Control | Residual Risk |
|---|---|---|
| Tenant price manipulation (self-negotiate a lower rate) | `billing:manage` never authorizes any §12.5 function; those functions are `app_worker`/`app_platform_admin`-only at the DB grant level (§12.5, §17) | None identified — DB-enforced, not merely app-layer |
| Commercial-pricing lifecycle bypass via raw SQL, including by `app_platform_admin` (FB-6K-01/02) | `commercial_pricing_agreements`/`...agreement_versions`/`...metrics` grant `SELECT` only to every role including `app_platform_admin` (§12.2/§12.8, live-confirmed) — every write, including by a platform-admin database session, goes through the four guarded functions | None identified — DB-enforced for every role without exception |
| Cross-tenant invoice/payment/refund access | RLS on every tenant table + explicit ownership check → `404` (§37) | None identified |
| Usage-event forgery | No tenant-facing usage-ingestion endpoint exists (§22); `app_api` also holds no direct `INSERT` grant on `usage_events`/`cost_entries` at the DB layer either (freeze-gate broader audit, Part G — closes this at the grant layer, not merely the "no endpoint" layer) | A compromised producer bounded context (6D/6E/6F/6H/6I) could still emit false usage — out of 6K's control surface, same residual risk 5H already accepted for its own ingestion boundary |
| Usage suppression (a producer simply not emitting an event) | Out of 6K's control — mitigated at the producer's own reliability layer (outbox at-least-once delivery); 6K's reconciliation job (§25.2) detects Redis/Postgres drift but not a producer that never emitted at all | Residual — a silent producer-side bug under-bills; flagged, not solved by 6K alone |
| Duplicate usage → double charge | `uq_ue_idempotency` (5H, unchanged) + §22.2's stable, metric-suffixed `source_event_id` | None identified |
| Usage-quantity overstatement via per-call rounding compounding (FB-6K-06) | `source_quantity_seconds` preserves exact pre-conversion values; aggregation sums exact seconds and rounds once (§12.7a/§22.3, live-confirmed) | None identified |
| A `CALL_MINUTES` usage row is stored with `source_quantity_seconds = NULL`, silently defeating the exact-aggregation guarantee above at the DB layer (FINAL-6K-02) | `chk_ue_source_quantity_seconds` now requires `source_quantity_seconds IS NOT NULL` whenever `metric = 'CALL_MINUTES'`, structurally — not merely by ingestion-consumer convention (§12.7a, live-confirmed); every other metric is unaffected | None identified — DB-enforced |
| Invoice tampering | `REVOKE UPDATE, DELETE` + `fn_invoice_immutability` (5H, unchanged); `app_api` also holds no `INSERT` on `invoice_lines`/`tax_lines` (Part G) | None identified |
| Tenant manufactures a payment (wrong amount/currency/provider) via direct table access (FB-6K-05) | `app_api` has no `INSERT` grant on `payment_attempts` at all; `fn_create_payment_attempt` derives every financial value server-side with no forgeable tenant parameter (§12.4, live-confirmed) | None identified — DB-enforced |
| Webhook dedup poisoning — a tenant, a general worker code path, or a raw platform-admin table write manufactures/pre-claims a webhook receipt or mutates its processing/linkage state, bypassing the dedicated ingress path entirely (FB-6K-03/04, FINAL-6K-01, FREEZE-6K-01) | Control: `app_api` cannot read the receipt table (no `SELECT`); cannot write it (no `INSERT`/`UPDATE`/`DELETE`); cannot execute the ingress function (no `EXECUTE`). `app_platform_admin` cannot raw-mutably `INSERT`/`UPDATE`/`DELETE` receipt rows (`SELECT` only, retained for narrow support/incident-response reading — not a write path). Only the dedicated `app_billing_webhook_ingress` role can invoke the one narrow `SECURITY DEFINER` ingress function, and it holds no other table privilege at all. Provider signature verification (`PaymentProviderPort.verify_webhook`, §30.2) precedes every invocation. `uq_pwr_provider_event` provides the durable, atomic dedup gate. No role of any kind holds `DELETE` — a future archival need is a separately governed retention operation, never an ordinary runtime grant (§12.4, live-confirmed) | Residual, explicitly not "none": compromise of the dedicated `app_billing_webhook_ingress` service's own credential; compromise of the platform's own webhook-signing secret (mitigated by `CredentialRef` rotation discipline, 4F/4I, out of this document's scope to redesign) — both are deployment/credential-management concerns, not DB-role-level bypasses, and neither is closed by any grant correction alone |
| Payment webhook forgery | `PaymentProviderPort.verify_webhook`, discarded on failure (§30.2) — no `payment_webhook_receipts` row is ever created for an unverified payload | Compromise of the platform's own webhook secret — mitigated by `CredentialRef` rotation discipline (4F/4I, out of this document's scope to redesign) |
| Payment amount/currency mismatch | §30.6's mandatory comparison before `fn_mark_invoice_paid`; internal-only `AMOUNT_MISMATCH`/`CURRENCY_MISMATCH` classification, never surfaced to the tenant as a card-decline reason | None identified |
| Webhook resolves to the wrong payment_attempt (weak linkage provenance, task's significant finding) | `fn_process_payment_webhook_receipt` internally resolves attempt/organization from `provider_transaction_id` against the platform's own data, cross-checking `payment_provider` — a cross-provider linkage attempt resolves `NULL`, fails closed (§12.4/§30.3, live-confirmed) | None identified |
| Duplicate payment | `uq_pwr_provider_event` (atomic, `fn_record_payment_webhook_receipt`) + `fn_update_payment_status` idempotency (§30.4/§30.7) | None identified |
| Refund abuse | `fn_validate_refund_amount`; `app_api` holds no `INSERT` grant on `refunds` (Part G, closing a confirmed gap the frozen 055_5H grant had left open) | None identified |
| Credit abuse | No tenant-facing credit creation; `fn_billing_apply_credit` is the sole write path for `credits`/`credit_ledger_entries` — `app_worker`'s own direct `INSERT` on both is also revoked (Part G, reconciling the executed grants with 5H's own stated §20 intent) | None identified |
| Pricing race (concurrent agreement activation) | `SELECT ... FOR UPDATE` inside `fn_activate_commercial_pricing_agreement_version` + `uq_cpav_one_active` partial unique index (§12.5) | None identified |
| Plan-version manipulation | Existing 5H immutability (`fn_plan_version_immutability`), unchanged | None identified |
| Commercial-agreement manipulation, including by `app_platform_admin` | `fn_cpav_immutability` (§12.2) blocks financial-field mutation once non-`DRAFT`; **no role, including `app_platform_admin`, holds any raw `INSERT`/`UPDATE`/`DELETE`** — only the four guarded functions can write at all (freeze-gate strengthening) | None identified |
| Tax-rule manipulation | `app_platform_admin`-only write (5H, unchanged); no rate ever appears in 6K's own contracts | None identified |
| `SECURITY DEFINER` tenant forgery | §9.1's audit found no gap in existing 5H functions; §12.5's commercial-pricing functions and the late-usage/webhook-processing functions follow the identical `app_worker`/`app_platform_admin`-only pattern for the identical reason. `fn_create_payment_attempt` is the sole `app_api`-callable billing function (eliminates the forgery vector by construction — no `p_organization_id`/financial parameter exists to pass, not by an internal check alone); `fn_record_payment_webhook_receipt` was `app_api`-callable through the second freeze-gate pass but is now callable only by the dedicated `app_billing_webhook_ingress` role (FINAL-6K-01) — no tenant-facing runtime role can reach it at all | Service-layer trust in `app_worker`'s caller for the worker/admin-only functions (§9.1's stated invariant, INV-6K-21, §44); trust in the inbound webhook handler's own deployment to run as `app_billing_webhook_ingress` and no broader role — not a DB-level residual risk, but a documented service-layer obligation |
| Payment provider outage | `503 PAYMENT_PROVIDER_UNAVAILABLE`, retryable; circuit-breaker pattern per 6A §21 (reused, not redesigned) | Standard availability risk, unchanged from any external-dependency call |
| Provider timeout, unknown payment result | §29.5's `get_status`-before-retry reconciliation | None identified |
| Replay attacks (webhook, idempotency key) | Webhook: dedup constraint (§30.4). Idempotency-Key: 24h TTL + fingerprint mismatch → `409` (6A §16.2) | None identified within the TTL window; a replay after TTL expiry is, by 6A §16.2's own design, treated as a new request — accepted residual, matching platform-wide policy |

---

## 41. Admin Handoff to Future Phase 6M

Per task §78, the following are explicitly **not** built as REST endpoints in this document — 6K supplies the DB-level contract (existing 5H grants/functions, or §12.5's new ones); 6M supplies the platform-admin REST surface, gated by `PlatformAdminOnly` (6B §18) rather than a per-org RBAC permission:

- Create/deactivate a `Plan`; publish a `PlanVersion`; configure `plan_prices` (existing `app_platform_admin` grants, 5H §47/052).
- Create/activate/expire a `CommercialPricingAgreement`/`...Version` (§12.5's four new functions — the entire reason 6M's surface, once built, needs no further DB work).
- Issue a manual `credits` grant (`fn_billing_apply_credit`, existing).
- Create a manual `billing_adjustments` correction (`fn_create_billing_adjustment`, existing, 086_5H1).
- Override/suspend a `billing_accounts` row outside the automatic grace-period state machine (§15.3 — no function exists yet for this specific manual override; a small additive function may be needed when 6M is designed, out of 6K's scope to add speculatively here).
- `tax_rules`/`tax_categories` administration (existing `app_platform_admin` grants).
- Payment-provider routing policy configuration (§29.2 — currently a platform-config value; 6M may formalize this into a proper admin-editable resource).
- Refund creation (§31.2 — existing DB write path, `app_worker`/`app_platform_admin`-grant already sufficient, no REST surface here).

---

## 42. Observability

Per task §93 — low-cardinality metrics only, no `organization_id`/`invoice_id`/`subscription_id`/`payment_attempt_id` in any Prometheus label (traces/logs carry those, per 6A §25's own established discipline, reused unchanged):

`platform_billing_payment_attempts_total{status}`, `platform_billing_payment_provider_latency_seconds{provider}`, `platform_billing_invoice_generation_failures_total`, `platform_billing_usage_ingestion_lag_seconds` (outbox-publish-to-`usage_events`-insert), `platform_billing_usage_dedup_total` (`ON CONFLICT DO NOTHING` hit count), `platform_billing_quota_exceeded_total{metric}`, `platform_billing_reconciliation_drift_total` (Redis-vs-Postgres divergence found by the nightly job), `platform_billing_subscription_status_count{status}` (gauge), `platform_billing_overdue_invoices_total`, `platform_billing_refund_failures_total`.

---

## 43. Performance

Billing endpoints are not on the voice hot path (6A §11's Tier E). Applying 6A §11's own tier table:

| Endpoint class | Tier | Notes |
|---|---|---|
| Account/subscription/usage/quota/credit reads | Tier A (Interactive) | Single indexed query or Redis-cached RBAC check |
| Subscription create/change-plan/cancel | Tier B (Operational) | Acknowledges once the guarded transition function commits durably — does not wait for a downstream outbox publish to confirm |
| Invoice list/detail | Tier A/C boundary — Tier C if the list grows large enough to need a pre-computed projection (not expected at V1 tenant scale) | |
| `payment-intent` | Tier B, but explicitly **never performs the provider HTTP call inline with a synchronous read/response** for any *other* billing endpoint (task §94) — the provider call itself happens after the `202`, per §29.4's transaction-boundary design | |
| Quota hot-path check (6D/6H's own initiation path, not a 6K endpoint) | Tier E-adjacent — sub-millisecond Redis `INCR`, kept fully separate from every Tier A/B/C endpoint in §34 (§25.3) | |
| Invoice generation, payment provider calls, billing reports | Never inline with a normal read endpoint — always the async paths in §35 | |

---

## 44. Financial Invariants

Restated as the binding checklist (task §92), each traced to its enforcement mechanism:

| # | Invariant | Enforcement |
|---|---|---|
| INV-6K-01 | Client cannot set invoice total | Server-computed only, §26.2 step 7 |
| INV-6K-02 | Client cannot set negotiated pricing | §12.5 functions are `app_worker`/`app_platform_admin`-only |
| INV-6K-03 | Published `PlanVersion` cannot be financially edited | `fn_plan_version_immutability`, existing |
| INV-6K-04 | Active `CommercialPricingAgreementVersion` cannot be financially edited | `fn_cpav_immutability`, §12.2 |
| INV-6K-05 | Invoice line prices are snapshotted | `invoice_lines` columns populated at INSERT only, §14 |
| INV-6K-06 | `PAID`/`VOID` invoice is immutable | `fn_invoice_immutability`, existing |
| INV-6K-07 | Usage events are append-only | `REVOKE UPDATE, DELETE`, existing |
| INV-6K-08 | Duplicate usage cannot double charge | `uq_ue_idempotency` + §22.2, existing/restated |
| INV-6K-09 | Duplicate payment webhook cannot double settle | `uq_pwr_provider_event` (atomic dedup gate, `fn_record_payment_webhook_receipt`, §12.4) + `fn_update_payment_status`'s terminal-state idempotency |
| INV-6K-10 | Payment amount/currency must match invoice | §30.6, new binding requirement for the new webhook endpoint |
| INV-6K-11 | Credit cannot make invoice total negative | `INV-BILL-04`, existing |
| INV-6K-12 | Refund cannot exceed refundable settled amount | `fn_validate_refund_amount`, existing |
| INV-6K-13 | `BillingAccount` currency immutable | `fn_ba_currency_immutable`, existing |
| INV-6K-14 | No implicit FX | §32, restated |
| INV-6K-15 | Every financial mutation audited | §45.3's vocabulary, existing + extended |
| INV-6K-16 | Cross-tenant billing access rejected | RLS + explicit checks, §37 |
| INV-6K-17 | Tenant cannot grant itself a lower price | Same mechanism as INV-6K-02 |
| INV-6K-18 | Provider cost ≠ customer price | §24 — `cost_entries` never joined into a tenant response |
| INV-6K-19 | Usage-metric tracking ≠ automatic billability | §13.4/§20/§26.2.1 |
| INV-6K-20 | DB state + outbox event commit atomically | §45.2 — every producer's domain mutation and its `audit.domain_event_outbox` INSERT share one transaction |
| INV-6K-21 | `app_worker`-callable financial functions trust their caller's `p_organization_id` only when it originates from an authenticated/authorized request or a verified domain event — never from unvalidated input | §9.1's service-layer obligation, restated |
| INV-6K-22 | No commercial pricing agreement financial field is ever mutated by a raw `UPDATE` outside `fn_cpav_immutability`'s guard, regardless of caller role | §12.2/§12.5, new |
| INV-6K-23 | No role, including `app_platform_admin`, holds any raw `INSERT`/`UPDATE`/`DELETE` on `commercial_pricing_agreements`/`...agreement_versions`/`...metrics` — the four guarded functions are the only write path for anyone | §12.2/§12.8, freeze-gate hardened, live-confirmed (FB-6K-01/02) |
| INV-6K-24 | `app_api` holds no direct table grant (`SELECT` or `INSERT`) on `payment_webhook_receipts` — the only reachable path is `fn_record_payment_webhook_receipt`, which cannot accept `organization_id`/`payment_attempt_id`/`processing_status` as input | §12.4, freeze-gate hardened, live-confirmed (FB-6K-03/04) |
| INV-6K-29 | No tenant-facing or general internal DB role (`app_api`, `app_worker`, `app_platform_admin`) holds `EXECUTE` on `fn_record_payment_webhook_receipt` — only the dedicated, minimal-surface `app_billing_webhook_ingress` role can call it, so no session outside the platform's own verified-webhook ingress path can pre-claim a real provider event ID | §12.4, third freeze-gate pass, live-confirmed (FINAL-6K-01) |
| INV-6K-30 | A `usage_events` row with `metric = 'CALL_MINUTES'` cannot be stored with `source_quantity_seconds IS NULL` — the exact-aggregation guarantee (INV-6K-27) is a structural DB invariant, not merely an ingestion-consumer convention | §12.7a, third freeze-gate pass, live-confirmed (FINAL-6K-02) |
| INV-6K-31 | **Webhook Receipt Write Isolation.** Payment-provider webhook receipt state (`billing.payment_webhook_receipts`) may only be created or transitioned through the two dedicated controlled functions (`fn_record_payment_webhook_receipt` for creation, `fn_process_payment_webhook_receipt` for state transition/linkage). No tenant runtime (`app_api`), no raw worker DML path (`app_worker` holds `SELECT` only on the table), and no raw platform-admin DML path (`app_platform_admin` holds `SELECT` only on the table) may pre-claim or rewrite provider webhook receipt state; no role of any kind holds `DELETE` | §12.4, fourth freeze-gate pass, live-confirmed (FREEZE-6K-01) |
| INV-6K-25 | `app_api` holds no direct `INSERT` on `payment_attempts` — `fn_create_payment_attempt` is the sole tenant-reachable creation path, deriving amount/currency/provider entirely server-side with no forgeable financial parameter | §12.4, freeze-gate hardened, live-confirmed (FB-6K-05) |
| INV-6K-26 | A webhook receipt's linkage to a `payment_attempts`/organization is always internally resolved from `provider_transaction_id` against the platform's own data — never accepted as a direct, trusted caller parameter; a cross-provider resolution attempt fails closed | §12.4/§30.3, freeze-gate hardened, live-confirmed (FB-6K-07) |
| INV-6K-27 | `CALL_MINUTES` billing aggregation sums exact pre-conversion seconds and rounds once — never rounds per call before summing, which would compound a systematic overstatement | §12.7a/§22.3, freeze-gate hardened, live-confirmed (FB-6K-06) |
| INV-6K-28 | `app_api`/`app_worker` hold no direct `INSERT` on any billing table whose write path has a guarded function or is exclusively a worker-internal responsibility (`usage_events`, `cost_entries`, `invoice_lines`, `tax_lines`, `credits`, `credit_ledger_entries`, `refunds`, all for `app_api`; `credits`/`credit_ledger_entries` additionally for `app_worker`) | §12.7b (Part G), freeze-gate broader audit, live-confirmed |

---

## 45. Event Catalog / Webhook Producer Contract

### 45.1 Domain Event → External Webhook Mapping

Closing 6J §19.2's named forward dependency exactly — no topic renamed, no new topic invented beyond what 6J already reserved:

| Internal domain event (outbox `event_type`) | External webhook topic (6J §19.1, unchanged) | Producer point | Resource ID field | Sensitive? |
|---|---|---|---|---|
| `invoice.generated` (internal) | `invoice.created` | §26.2 step 9 | `invoice_id` | Financial |
| `invoice.paid` | `invoice.paid` | §30.2's async processing, on `SUCCEEDED` | `invoice_id` | Financial |
| `payment.failed` | `payment.failed` | §30.2's async processing, on terminal `FAILED` | `payment_attempt_id` | Financial |
| `subscription.changed` | `subscription.changed` | §18.2/§18.3/§18.4 (create/change-plan/cancel, all three) | `subscription_id` | No |
| `usage.threshold_reached` | `usage.threshold_reached` | §25.2, on a soft-limit crossing | `organization_id` only | No |

Every row above uses 6J §20.1's exact envelope (`id`, `type`, `version: 1`, `occurred_at`, `organization_id`, `data.object`, `request_id`) — no second envelope shape is introduced. `data.object` for each is a minimized, allow-listed serializer (6J §20.2's discipline): `invoice.created`/`invoice.paid` never embed `tax_profile_snapshot`'s raw GSTIN/address, only `{invoice_id, invoice_number, total_due, currency, status}`; `payment.failed` never embeds `provider_transaction_id` or raw provider error text, only `{payment_attempt_id, invoice_id, failure_code}`.

### 45.2 Transactional Outbox (Reused Verbatim)

Every one of §45.1's internal events is written into `audit.domain_event_outbox` (5J §077, unchanged) in the **same transaction** as the financial state change that produced it — never a separate write, never called while a provider HTTP call is outstanding (INV-6K-20). Fanning an outbox row out into per-tenant `webhooks.webhook_deliveries` rows for subscribed `WebhookEndpoint`s (matching `topics`) is existing 6J/5I consumer infrastructure — 6K does not redesign that fan-out, it only produces correctly into the shared outbox exactly as 6C/6D/6F already do for their own domain events (§22.1's pipeline diagram, reused for the write direction here).

### 45.3 Audit Vocabulary — Governed Extension

5J §14.3's existing Billing category (`SUBSCRIPTION_CREATED`, `SUBSCRIPTION_PLAN_CHANGED`, `SUBSCRIPTION_CANCELLED`, `INVOICE_GENERATED`, `PAYMENT_ATTEMPTED`, `PAYMENT_SUCCEEDED`, `PAYMENT_FAILED`, `REFUND_ISSUED`, `BILLING_ADJUSTMENT_CREATED`) covers most of this document's write paths already. Per the same governance pattern 6B/6D/6F/6G each already used (5J §14.3's `†`/`‡`/`§`/`¶` amendments — a **pure vocabulary addition**, since `chk_ae_action_kind` is only `CHECK (length(action_kind) BETWEEN 1 AND 200)`, not an enum or `IN`-list, confirmed in 5J's own text), 6K requires exactly these new governed values, added the same way (no SQL migration touches `audit.audit_events`):

`BILLING_ACCOUNT_CONTACT_UPDATED` (§15.2's `PATCH`), `COMMERCIAL_PRICING_AGREEMENT_CREATED`, `COMMERCIAL_PRICING_AGREEMENT_VERSION_CREATED`, `COMMERCIAL_PRICING_AGREEMENT_VERSION_ACTIVATED`, `COMMERCIAL_PRICING_AGREEMENT_VERSION_EXPIRED` (§12.5's four functions, called by 6M once it exists), `INVOICE_VOIDED` (`fn_void_invoice`, existing function, previously-ungoverned action name), `CREDIT_GRANTED` (`fn_billing_apply_credit`, same situation).

Per 6A §14.5's synchrony table, Billing events remain **asynchronous** by default (unchanged) — none of 6K's write paths join the named Voice-control-plane synchronous exception list (5J §14.5's `‡` amendment applies only to the fifteen named 6D operations).

---

## 46. Cross-Phase Traceability

| Phase | Relationship |
|---|---|
| 6A | Response envelope, Money DTO, error contract, idempotency, pagination, async job vocabulary — all reused verbatim (§43, §36, throughout) |
| 6B | Permission catalog (`billing:read`, `billing:manage`, `invoice:read`, `tax:manage`), `BILLING_ADMIN` role, `PlatformAdminOnly` pattern for §41's handoff |
| 6C | Organization lifecycle (`organization:suspend`, distinct from `billing_status`, §15.3); `tax_profiles` surface ownership boundary (§28) |
| 6D | `call.ended` → `CALL_MINUTES` (§23.1) |
| 6E | `conversation.turn_completed` → LLM/STT/TTS component metrics (§23.3) |
| 6F | `document.indexed` → `EMBEDDING_TOKENS` (§23.3) |
| 6H | `campaign.contact.call_attempted` → `CAMPAIGN_CALLS` (§23.2) |
| 6I | `workflow.execution.completed` → `WORKFLOW_EXECUTIONS`/LLM tokens — **closes 6I's own named forward dependency** (6I's dependency-register item naming 6K explicitly) |
| 6J | External event catalog (§45.1 — closes 6J §19.2's forward dependency); inbound-provider webhook architecture pattern reused (§30.1–§30.3) |
| 5H | This document's entire domain model; one additive migration (§12) |
| 5J | `audit.domain_event_outbox` (§45.2), governed audit vocabulary (§45.3) |
| Future 6L | Analytics/margin projections consume 6K's usage/invoice data; not built here (§24) |
| Future 6M | Platform-admin REST surface for §41's handoff list |

### 46.1 Forward Dependencies Register (Non-Blocking)

| ID | Item | Status | Owner |
|---|---|---|---|
| DEP-6K-01 | `TOOL_EXECUTIONS` usage producer | Not yet built anywhere in 6D–6I | Future 6I/6E amendment |
| DEP-6K-02 | `KNOWLEDGE_RETRIEVALS` usage producer | Not yet built anywhere in 6D–6I | Future 6F/6E amendment |
| DEP-6K-03 | 6M's manual `billing_accounts` suspend/reactivate override function | Not built (no V1 requirement forces it now) | Future 6M + a small 5H additive migration if needed |
| DEP-6K-04 | 6C's own `GET/PATCH` tax-profile endpoint existence | Not verified to exist in the reviewed 6C document | Future 6C reconciliation (6K does not duplicate a competing surface, §28) |
| DEP-6K-05 | Whether `workflow.execution.completed`'s payload carries a field distinguishing "invoked from within an active voice conversation turn" vs. "standalone execution" — required for 6E/6I's own application code to correctly implement §23.3's LLM-usage producer-ownership rule | Not confirmed in the reviewed 6E/6I documents (disclosed, not silently assumed) | Future 6E/6I field-shape confirmation, mirroring 6J's own `DEP-6J-12` precedent |

---

## 47. ADRs

### ADR-6K-01: Organization-Specific Pricing as a Versioned Overlay, Not a Standalone Plan

**Decision:** `CommercialPricingAgreement`/`...Version`/`...Metric` reference a base `PlanVersion` and override only financial fields (§11.2). **Rationale:** task §70/§71 — feature entitlements must stay tied to the plan; duplicating a full bespoke plan per enterprise customer would decouple entitlements from pricing and multiply administrative surface area for every future plan feature. **Alternatives rejected:** (a) a fully independent per-org "custom plan" — rejected, breaks entitlement consistency and requires re-deriving every plan feature per customer; (b) a mutable JSONB override column on `subscriptions` — rejected per §11.3, no historical determinism. **Consequences:** an agreement can never grant a feature the base plan doesn't already have; a genuinely bespoke feature set (not just price) is out of this mechanism's scope and would require a real new `PlanVersion`.

### ADR-6K-02: Immutable, Versioned Agreement Terms (DEC-6K-01, ACCEPTED, FINAL)

See §48. **Decision:** Option A — immutable, versioned agreement terms. **Rationale:** deterministic historical invoices, enterprise contract traceability, dispute safety — identical reasoning to `plan_versions`' own immutability (ADR-5H-001), now extended to organization-specific pricing. **Live-validated:** the full field-level immutability guard, the composite tenant-scoped FK integrity, and the future-dated-activation guard are all confirmed working on PostgreSQL 18.6 (§12.8).

### ADR-6K-03: Pricing Resolution Is Agreement-First, Never "Current Anything"

**Decision:** §13.1's two-tier precedence, resolved and pinned per-billing-period (§13.3), never recomputed from "the current plan" or "the current agreement" at invoice-generation time. **Rationale:** task §5's explicit prohibition on recomputing from mutable current pricing; mirrors 5H's own `plan_version_id` pinning discipline exactly, extended rather than replaced. **Consequences:** every new capability that touches pricing (a future add-on system, a future discount engine) must pin its own inputs at period-open time the same way, or risk breaking invoice determinism.

### ADR-6K-04: Campaign Metric Billability Is a Pricing-Contract Decision, Not a Usage-Recording Decision

**Decision:** `usage_events`/`usage_records` recording is unconditional and metric-agnostic; whether a metric produces a monetary `invoice_lines` row is decided solely by `effective_overage_rate(metric)` at invoice-generation time (§13.4/§26.2). **Rationale:** task §6/§88's explicit requirement — a campaign call legitimately emits both `CALL_MINUTES` and `CAMPAIGN_CALLS` facts, and which (if either) is billable is a commercial decision that must be changeable per-plan/per-agreement without touching the usage-ingestion pipeline. **Consequences:** any future metric follows the identical pattern automatically — no per-metric billing code branch is ever needed in the ingestion path.

### ADR-6K-05: Payment Provider Abstraction — Reused, Not Redesigned

**Decision:** no change to `PaymentProviderPort`, `payment_attempts.payment_provider`, or the `FailureCode`/`PaymentMethodKind` enums (4F/4I/5H, all confirmed unchanged in §9.4/§29.1). **Rationale:** already-approved, already-correct abstraction; 6K's job is to build the API surface on top of it, not to re-litigate it. **Consequences:** none beyond what 4F/4I/5H already accepted.

### ADR-6K-06: Invoice Line Pricing Snapshot Extended for Field-Level Agreement Provenance

**Decision:** `invoice_lines` gains `unit_price_source`/`included_quantity_source`/`commercial_pricing_agreement_version_id` (§12.3) rather than requiring every invoice-line reader to re-derive provenance by joining through `billing_periods`, and rather than one combined label that cannot independently answer "which source produced the rate" vs. "which source produced the included allowance" (task §16's own explicit two-question requirement). **Rationale:** task §27/§68's explicit provenance-reconstruction requirement — a support engineer or auditor should be able to answer "why this price" from the invoice line itself, not by re-running the resolution algorithm. **Alternatives rejected:** one combined `pricing_source` label — rejected during this document's own remediation pass as insufficiently granular (task §16's finding); provenance derivable only via `billing_periods` join — rejected as strictly harder to query and easier to get wrong in a support/dispute context.

### ADR-6K-07: Payment Transaction Boundary — Provider Call Outside the DB Transaction, Nullable `provider_transaction_id`

**Decision:** §29.4's exact sequence — `payment_attempts` `INSERT` commits (with `provider_transaction_id = NULL`) before the provider adapter is ever called; a short follow-up transaction (`fn_link_payment_provider_transaction`, §12.4) links the real transaction id once the provider responds. **Rationale:** task §64's explicit requirement; never hold a DB transaction open across a network call to an external payment provider — this requires `provider_transaction_id` to be nullable at the moment of the initial `INSERT`, which the frozen 055_5H.sql schema did not originally allow (a confirmed, now-fixed defect, §12.4). **Consequences:** a crash between steps 7 and 8 of §29.4 leaves a `payment_attempts` row `INITIATED` with no provider-side counterpart yet — recovered by the reconciliation worker's own `get_status` polling (§29.5), not by any special crash-recovery code path. **A related alternative rejected during this pass's own live validation:** appending `p_provider_transaction_id` as a new default parameter directly onto the existing (057_5H.sql) `fn_update_payment_status` via `CREATE OR REPLACE` — live-tested and found to create a second, separately (and more permissively) privileged function overload rather than replacing the original; a distinctly-named function (`fn_link_payment_provider_transaction`) was used instead, for exactly this reason.

### ADR-6K-08: Usage vs. Cost Kept Structurally Separate

**Decision:** no endpoint in this document ever joins `cost_entries` into a customer-facing response (§24). **Rationale:** task §22/§75 — provider cost and customer charge are never the same number, and conflating them even accidentally in one response model would leak negotiated provider rates. **Consequences:** any future tenant-facing "cost" language in a UI must be understood to mean "your charge," never "our cost" — a naming discipline this document's response models enforce structurally by never having a cost field to begin with.

### ADR-6K-09: Late-Arriving Usage — Bounded Window, Then Next-Cycle Adjustment With Full Provenance (DEC-6K-04, ACCEPTED, FINAL)

See §48. **Decision:** a bounded reconciliation window before finalization; after that, a fully-provenanced `billing_adjustments` correction on the next cycle (`fn_create_late_usage_billing_adjustment`, §12.6 — carrying the originating period, metric, and full pricing-basis JSONB, not merely a free-text description), never a mutation of a finalized invoice. **Rationale:** `INV-BILL-02`'s immutability is non-negotiable; a plain-text `description` field alone (a first draft's approach) does not give support/audit a structurally queryable answer to "which period/metric/pricing basis does this correction relate to" — task §32's explicit requirement. **Live-validated:** creating such an adjustment leaves the original invoice's total numerically unchanged (§12.8).

### ADR-6K-10: Quota Enforcement Stays Redis-Hot / Postgres-Durable; Enforcement and Pricing Are Independent Axes

**Decision:** no new enforcement mechanism introduced; 5H §12's existing split is reused (§25.2). `overage_allowed` is corrected to mean exactly `hard_limit IS NULL` — never conflated with whether the metric happens to be priced (task §30's finding, corrected in §25.1). **Rationale:** already correct, already approved; 6K's only addition is the reporting endpoint (§25.1) and the explicit statement that it is not on the hot path (§25.3/§43) — plus the corrected, unconflated semantics.

### ADR-6K-11: LLM-Usage Producer Ownership Is a Stated Rule, Not a Fabricated Shared-ID Mechanism (Corrected)

**Decision:** rather than claiming distinct `source_event_id`s alone prevent double-counting the same LLM call across `conversation.turn_completed` (6E) and `workflow.execution.completed` (6I) — a claim this document's own first draft made and which does not hold (§23.3) — this document states a binding producer-ownership rule and discloses the unconfirmed field-shape dependency it relies on as `DEP-6K-05` (§46.1), mirroring 6J's own precedent for `DEP-6J-12`. **Rationale:** task §27's explicit instruction not to invent a shared correlation ID that was not found to exist. **Consequences:** correct enforcement of this rule depends on a future 6E/6I field-shape confirmation this document cannot itself perform.

### ADR-6K-12: Durable Inbound-Payment-Webhook Receipt, Separate From the Payment Attempt

**Decision:** `billing.payment_webhook_receipts` (§12.4) is a new table, distinct from `payment_attempts`, providing the atomic `INSERT ... ON CONFLICT ... RETURNING`-based dedup guarantee 6J §24.3 already establishes as the pattern for inbound provider events. **Rationale:** an `UPDATE`-based dedup against `payment_attempts.provider_webhook_event_id` (a first draft's approach) does not provide the same atomicity — task §21/§22's finding. **Consequences:** two related but independent state machines now exist (`payment_webhook_receipts.processing_status` and `payment_attempts.status`), deliberately not merged (§30.5/§30.7) — each answers a different question ("did we handle this delivery" vs. "what is the payment's financial state").

### ADR-6K-13: No Raw-DML Escape Hatch for Commercial Pricing, Even for `app_platform_admin` (FB-6K-01/02)

**Decision:** `commercial_pricing_agreements`/`...agreement_versions`/`...metrics` grant `SELECT` only, to every role without exception — unlike 5H's own general precedent (ADR-5H-006) of leaving `app_platform_admin` full raw CRUD on other financial tables as an "operational corrections" escape hatch. **Rationale:** a freeze-gate review found this table's risk profile is materially different from invoices/payment_attempts/credits — a single raw `UPDATE`/`DELETE` here can directly manufacture below-market negotiated pricing or erase a binding commercial term with no lifecycle guard in the way at all, not merely correct an already-bounded, already-audited record after the fact; `SECURITY DEFINER` functions never need the caller's own table grants (they execute as their owner), so nothing is lost by removing it. **Alternatives rejected:** matching 5H's general precedent and leaving `app_platform_admin` full CRUD (rejected — this is precisely the bypass the freeze-gate review found live-exploitable); a session-variable "trusted lifecycle context" trick the functions would set before writing (rejected — the task's own explicit instruction: "do not use a security mechanism an ordinary SQL caller can trivially set themselves"). **Consequences:** genuine emergency repair of a commercial term requires re-issuing the guarded create/activate/expire sequence — itself immutable, audited history — never a silent overwrite.

### ADR-6K-14: `app_api`-Callable Financial Functions Eliminate the Forgery Vector by Construction, Not by Internal Check Alone (FB-6K-05)

**Decision:** `fn_create_payment_attempt` (§12.4) takes no `p_organization_id` parameter at all — tenant context is derived exclusively from `organization.current_tenant_id()` inside the function body. **Rationale:** every other 6K/5H billing `SECURITY DEFINER` function that takes `p_organization_id` is worker/admin-only (§9.1's audit); this is the first one reachable by an ordinary tenant session, so it is held to a stricter construction than "validate the parameter matches" — there is no parameter to validate, and therefore no code path that could regress into trusting an unvalidated one. **Alternatives rejected:** accepting `p_organization_id` and checking it against `current_tenant_id()` (the pattern 6I/6J's own remediation used for their own app_api-callable functions) — considered, but rejected here as strictly weaker than not accepting the parameter at all for a function that never legitimately needs a caller-supplied value in the first place. **Consequences:** this function's signature is a template for any future `app_api`-callable billing function — no financial-identity parameter should ever be accepted from the caller if it can instead be derived from session context.

### ADR-6K-15: Payment Provider Webhook Ingress Uses a Dedicated Least-Privilege Service Principal (FB-6K-03/04, FINAL-6K-01, FREEZE-6K-01/02)

**Decision:** Provider callback ingress uses `app_billing_webhook_ingress` — not `app_api`, not `app_worker`, not `app_platform_admin` — for durable receipt creation. `fn_record_payment_webhook_receipt` (§12.4) accepts only three ingress-safe fields (provider, event id, payload hash), never `organization_id`/`payment_attempt_id`/`processing_status`, and `EXECUTE` on it is granted to `app_billing_webhook_ingress` alone. No role holds any raw `INSERT`/`UPDATE`/`DELETE` on `billing.payment_webhook_receipts` — `app_platform_admin` retains `SELECT` only (a narrow, read-only support/incident-response allowance), `app_worker`/`app_readonly` retain `SELECT` only, and `app_api` holds nothing at all on this table or this function.

**Flow:**
```text
Provider HTTP callback
→ provider signature verification
→ DB connection / execution context = app_billing_webhook_ingress
→ fn_record_payment_webhook_receipt
→ durable dedup receipt
→ commit
→ fast ACK
→ app_worker async processor (fn_process_payment_webhook_receipt)
```

**Rationale:** the provider event ID is a security-sensitive dedup key (`UNIQUE (payment_provider, provider_event_id)`). Any tenant-facing runtime role capable of pre-claiming it could suppress a legitimate provider event before it genuinely arrives — accepting no financial fields is not the same guarantee as "cannot call this function/table at all," a distinction two successive freeze-gate reviews found this document's own earlier drafts conflated (FINAL-6K-01 closed the function-`EXECUTE` path; FREEZE-6K-01 closed the remaining raw-table-DML path for `app_platform_admin`). Therefore the durable-ingress command must be isolated from tenant application execution, from the general worker role, and from platform-admin raw table access alike — not merely from tenant-facing code. **Alternatives rejected:** granting `EXECUTE`/table access to `app_worker` (rejected — `app_worker` is broad and shared by many unrelated functions; granting it here would let every one of those unrelated code paths also record a provider webhook receipt, mirroring the exact "broader than a single function needs" problem the existing `app_voice_reconciler` precedent, `099_5C1.sql` §B1, already rejected for its own analogous case); granting `app_platform_admin` continued raw table CRUD as an "operational corrections" escape hatch, the general 5H precedent (ADR-5H-006) used elsewhere (rejected — platform-admin authority must not mean authority to rewrite provider webhook ingestion history, which is security/audit evidence, not an ordinary correctable financial record). **Consequences:** tenant API (`app_api`) cannot manufacture a receipt or pre-claim an event ID; the general worker role cannot impersonate ingress; platform admin cannot raw-write webhook history (read-only `SELECT` only); the trusted ingress service has exactly one narrow capability — `EXECUTE` on one function, nothing else. Residual risk is confined to compromise of the dedicated ingress service's own credential or of the provider's signing secret (§40) — not to any DB-role-level bypass.

---

## 48. Owner Decisions — Resolved and Binding

All four decisions this document originally raised have been reviewed and accepted by the product owner. They are **FINAL** and are not re-litigated anywhere else in this document; every dependent section (§11–§18, §22–§23, §29–§30, §37–§39, §44) is written to match the accepted option directly, not conditionally.

### DEC-6K-01 — Commercial Pricing Agreement Versioning

**Status: ACCEPTED, FINAL.**

**Decision: Option A — immutable, versioned agreement terms.** Once `ACTIVE`, a version's financial fields cannot change; renegotiation creates a new `DRAFT` version, activated to supersede the old one (never before its own `effective_from`, if a prior version is still current — §12.5). Historical billing periods stay pinned to the exact version that was active when they opened (§13.3), and remain resolvable through that pin regardless of the version's current status (§14).

**Implemented and live-validated:** `102_5H2` (§12) — three tables, composite tenant-scoped foreign keys, full-field financial immutability, a future-dated-activation guard, exact half-open effective-date boundaries. Fresh and incremental migration both pass on PostgreSQL 18.6; the full adversarial test matrix (immutability, cross-org rejection under both RLS and `BYPASSRLS`, plan-version consistency, historical resolution) passes — `docs/phase-05-database-design/5K/validation/6K_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`.

### DEC-6K-02 — Customer Call-Minute Rounding

**Status: ACCEPTED, FINAL.**

**Decision: exact `duration_seconds / 60`.** No `CEIL`. No next-whole-minute rounding. No telephony-provider pulse rounding applied to the customer charge. Provider pulse billing may affect the platform's own internal provider-cost accounting (`cost_entries`, §24) only — never the customer-facing `usage_events.quantity` or any downstream invoice line.

**Implemented:** `quantity = ROUND(duration_seconds::NUMERIC / 60, 4)`, banker's rounding, reusing 5H §7's already-established platform-wide rounding rule (§22.3). Worked values for seconds 1/30/59/60/61/90/127 are specified in §22.3.

### DEC-6K-03 — Payment-Failure / Grace / Suspension Policy

**Status: ACCEPTED, FINAL.**

**Decision:** configurable grace period; service continues during grace per the approved policy; after grace expires, `billing_status` moves to `SUSPENDED` and new billable operations are blocked at the initiating context, before consumption. A `SUSPENDED` tenant retains: `GET /billing/account`, `/invoices`, `/payments`, `/summary`, `/periods` (full read access), and `POST /billing/invoices/{id}/payment-intent` (the path to cure the debt) — never a blanket API denial.

**Implemented:** §15.4's explicit eligibility matrix and §15.5's reusable eligibility-guard contract (a plain RLS-scoped read of `billing_accounts.billing_status`, no new database object required) directly encode this decision.

### DEC-6K-04 — Late-Arriving Usage After Invoice Finalization

**Status: ACCEPTED, FINAL.**

**Decision:** late usage arriving before finalization is absorbed into the still-`DRAFT` invoice, within a bounded, configurable reconciliation window. Late usage arriving **after** finalization (`OPEN`/`PAID`) never modifies the finalized invoice — it becomes a next-cycle `billing_adjustments` row with full, structured provenance back to the original billing period and the original pricing basis (never today's plan/agreement rate).

**Implemented and live-validated:** `fn_create_late_usage_billing_adjustment` (§12.6) — `late_usage_billing_period_id`, `late_usage_metric`, `late_usage_provenance` JSONB (original `plan_version_id`, `commercial_pricing_agreement_version_id` if applicable, the specific late `usage_events` row ids, quantity, and unit price). Live-confirmed: the original, already-finalized invoice's total is numerically unchanged by the adjustment.

---

## 49. Final Approval Status

```
PHASE 6K — BILLING + USAGE APIs
(Four remediation passes, all 2026-08-30: FINAL Blocker Remediation, then an
 independent freeze-gate review's own FINAL Freeze-Gate Remediation, then a
 further independent freeze-gate review's own FINAL Two-Issue Freeze
 Remediation, then a further independent freeze-gate review's own FINAL
 Freeze-Gate Remediation Pass)

Billing account APIs:              DESIGNED
Plan catalog APIs (tenant read):   DESIGNED
Commercial pricing agreements:     DESIGNED, IMPLEMENTED, LIVE-VALIDATED, FREEZE-GATE HARDENED —
                                    DB contract, resolution algorithm, additive migration 102_5H2
                                    complete; DEC-6K-01 ACCEPTED/FINAL; fresh + incremental
                                    migration PASS on PostgreSQL 18.6, full adversarial test
                                    matrix PASS; a freeze-gate review found the first pass's own
                                    design still let app_platform_admin bypass the lifecycle via
                                    raw UPDATE/DELETE (FB-6K-01/02) — closed: NO role, including
                                    app_platform_admin, holds any raw INSERT/UPDATE/DELETE on any
                                    of the three pricing tables; only the four guarded functions
                                    can write, for anyone, live-confirmed
Subscription lifecycle APIs:       DESIGNED
Plan change semantics:             DESIGNED (downgrade proration remains ODD-5H-02, genuinely
                                    unresolved upstream, correctly carried forward, not decided
                                    here — no V1 execution path in this document requires it)
Billing period APIs:               DESIGNED
Usage metering / ingestion:        DESIGNED, IMPLEMENTED, FREEZE-GATE HARDENED — call-minute
                                    rounding DEC-6K-02 ACCEPTED/FINAL; a confirmed usage-
                                    idempotency collision (multi-metric producer events) live-
                                    reproduced and fixed (metric-suffixed source_event_id
                                    convention); a SECOND confirmed defect (FB-6K-06) found by the
                                    freeze-gate review — per-call rounding before aggregation
                                    systematically overstated usage (1000x1s calls: 16.7000 vs.
                                    the true 16.6667) — fixed with source_quantity_seconds,
                                    exact-sum-then-round-once, live-proven equal to a single
                                    equivalent-duration call in two independent test cases;
                                    app_api's unnecessary direct INSERT on usage_events/
                                    cost_entries also revoked (broader audit); TOOL_EXECUTIONS/
                                    KNOWLEDGE_RETRIEVALS producers — DEP-6K-01/02 — non-blocking
                                    forward dependency; LLM cross-context double-bill risk
                                    corrected to a stated ownership rule + disclosed DEP-6K-05;
                                    a THIRD confirmed defect (FINAL-6K-02, significant) found by a
                                    further freeze-gate review — source_quantity_seconds remained
                                    nullable even for CALL_MINUTES, so the exact-aggregation
                                    guarantee depended on ingestion-consumer discipline, not a DB
                                    invariant — closed with a strengthened
                                    chk_ue_source_quantity_seconds requiring the column non-NULL
                                    specifically for CALL_MINUTES, live-confirmed with negative
                                    (NULL, negative-value) and positive tests, aggregation
                                    equivalence reconfirmed
Quota APIs / enforcement:          DESIGNED — overage_allowed/hard_limit conflation found and
                                    fixed (now strictly hard_limit IS NULL)
Invoice generation / APIs:         DESIGNED, IMPLEMENTED — field-level pricing provenance
                                    (unit_price_source, included_quantity_source) added and
                                    CHECK-enforced, live-validated; app_api's unnecessary direct
                                    INSERT on invoice_lines/tax_lines revoked (broader audit)
Credits / adjustments:             DESIGNED, IMPLEMENTED, FREEZE-GATE HARDENED — late-usage
                                    adjustment provenance (DEC-6K-04) added and live-validated;
                                    no tenant-facing creation surface (existing 5H mechanism);
                                    app_worker's direct INSERT on credits/credit_ledger_entries
                                    revoked, reconciling the executed grants with 5H's own
                                    already-stated §20 security-model intent (broader audit)
Tax / GST presentation:            DESIGNED (no rate ever hard-coded; reuses 5H unchanged)
Payment architecture:              DESIGNED, IMPLEMENTED, LIVE-VALIDATED, FREEZE-GATE HARDENED —
                                    a confirmed-blocking payment_attempts.provider_transaction_id
                                    NOT NULL defect found and fixed; payment-transaction-boundary
                                    sequence corrected and made internally coherent; durable,
                                    atomically-deduplicated inbound-webhook receipt table added;
                                    payment_method_kind now persisted; a freeze-gate review then
                                    found THREE further confirmed blockers the first pass missed:
                                    (a) app_api still held direct INSERT on payment_attempts
                                    itself (FB-6K-05) — closed with fn_create_payment_attempt,
                                    the first app_api-callable billing SECURITY DEFINER function,
                                    deriving amount/currency/provider entirely server-side with
                                    no forgeable parameter; (b) app_api held direct SELECT+INSERT
                                    on payment_webhook_receipts (FB-6K-03/04) — closed with a
                                    narrow fn_record_payment_webhook_receipt accepting only
                                    ingress-safe fields; (c) the webhook-processing function
                                    accepted payment_attempt_id/organization_id as direct, trusted
                                    parameters (significant finding) — closed by having it
                                    internally resolve linkage from provider_transaction_id
                                    against the platform's own data, cross-provider-checked;
                                    app_api's unnecessary direct INSERT on refunds also revoked
                                    (broader audit); a further freeze-gate review then found ONE
                                    more confirmed blocker the second pass missed: app_api (and
                                    app_worker, and app_platform_admin) still held EXECUTE on
                                    fn_record_payment_webhook_receipt itself (FINAL-6K-01) —
                                    accepting no financial fields did not mean the function
                                    couldn't be CALLED at all, and any app_api session could
                                    pre-claim a real, not-yet-arrived provider event ID, poisoning
                                    the dedup key before the genuine webhook arrived; closed by
                                    introducing a single-purpose role, app_billing_webhook_ingress
                                    (modeled directly on the existing app_voice_reconciler
                                    precedent, 5K §B1/099_5C1), and granting EXECUTE only to it —
                                    app_api/app_worker/app_platform_admin now all confirmed
                                    permission denied; a fourth freeze-gate review then found ONE
                                    more confirmed blocker the third pass missed: app_platform_admin
                                    still held raw INSERT/UPDATE/DELETE directly on the
                                    payment_webhook_receipts TABLE itself (FREEZE-6K-01) — closing
                                    EXECUTE on the ingress function did not close this separate raw-
                                    table-DML bypass, which could still pre-claim/poison a real
                                    provider event ID or rewrite/delete receipt rows outright; closed
                                    by revoking INSERT/UPDATE/DELETE from app_platform_admin (SELECT
                                    retained, a narrow read-only support/incident-response
                                    allowance) — no role, including app_platform_admin, holds DELETE
                                    on this table; all live-validated on PostgreSQL 18.6
Refunds:                           DESIGNED (read-only tenant exposure; creation remains
                                    admin/support, handed to 6M)
Multi-currency:                    DESIGNED (V1 stays single-currency-per-account, per 5H ODD-5H-10)
Webhook event producer contract:   DESIGNED — closes 6J §19.2's named forward dependency
Endpoint inventory:                COMPLETE (§34)
Authorization matrix:              COMPLETE (§37) — no new 6B permission string required
Error catalog:                     COMPLETE (§36) — no collision with 6A/6B; distinct internal-
                                    only settlement-mismatch vocabulary added (now including
                                    UNKNOWN_TRANSACTION_CORRELATION), never conflated with the
                                    customer-facing FailureCode enum
Database traceability:             COMPLETE (§38) — every new/changed object marked and
                                    cross-referenced to live validation evidence, all four passes
Threat model:                      COMPLETE (§40) — 9 new/updated threat rows across the
                                    freeze-gate findings, each with a live-confirmed control (the
                                    webhook-dedup-poisoning row now covers the table-DML path too,
                                    FREEZE-6K-01, and explicitly names residual, non-DB-role risk)
Financial invariants:              COMPLETE (§44) — INV-6K-23 through INV-6K-31 added for the
                                    freeze-gate findings
Test matrices:                     COMPLETE (§39) — pricing resolution, no-double-bill, invoice
                                    determinism, payment security, all with worked test values;
                                    28 first-pass + ~20 second-pass + 12 third-pass + 22 fourth-pass
                                    assertions were additionally run for real against live
                                    PostgreSQL 18.6 instances (§12.8, validation report §29), plus a
                                    full regression re-run of the complete original 28-test suite
                                    against the corrected file (and targeted regression smoke tests
                                    in the third and fourth passes against the most relevant prior
                                    fixes)

Phase 5H schema gap (commercial pricing):     IDENTIFIED AND CLOSED — 102_5H2, live-validated
Phase 5H SECURITY DEFINER audit:              COMPLETE — no gap found (§9.1), re-confirmed live
                                               for every function across all four passes
                                               (validation report §6/§16/§23/§30) —
                                               fn_create_payment_attempt is the sole
                                               app_api-granted billing function;
                                               fn_record_payment_webhook_receipt is granted only
                                               to the dedicated app_billing_webhook_ingress role
                                               (FINAL-6K-01, no longer app_api-granted), and no
                                               role holds any raw table DML on
                                               payment_webhook_receipts beyond SELECT
                                               (FREEZE-6K-01)
Phase 5H non-gap (SubscriptionItem):          CONFIRMED, correctly NOT built (§9.3)
Phase 5H confirmed defect (provider_transaction_id NOT NULL): FOUND AND FIXED (§12.4)

First-pass findings (5 further defects beyond the core schema gap) — ALL FOUND AND FIXED:
  usage-idempotency collision, incomplete AgreementVersion immutability, mutable parent
  agreement identity, future-dated-activation gap, missing composite FK integrity,
  incoherent webhook dedup, incorrect LLM double-bill claim, quota-semantics conflation,
  payment_method_kind schema/API mismatch (full 23-item blocker-closure table: validation
  report §8)

Second-pass (freeze-gate) findings (5 BLOCKERS + 1 SIGNIFICANT the first pass missed,
explicitly disclosed, not hidden — validation report §0) — ALL FOUND AND FIXED:
  FB-6K-01  Raw commercial-pricing lifecycle UPDATE bypass (incl. by app_platform_admin) — FIXED
  FB-6K-02  Non-DRAFT commercial agreement version DELETE — FIXED
  FB-6K-03  app_api global SELECT on payment webhook receipts — FIXED
  FB-6K-04  app_api raw INSERT on payment webhook receipts — FIXED
  FB-6K-05  app_api raw INSERT on payment attempts — FIXED
  FB-6K-06  Per-call 4-decimal CALL_MINUTES quantization drift — FIXED
  FB-6K-07  Webhook receipt organization/payment-attempt linkage not derived strongly enough — FIXED
  (full closure table with live evidence: validation report §17)
Plus a broader least-privilege audit (task-authorized, beyond the 7 items above): app_api's
unnecessary INSERT on usage_events/cost_entries/invoice_lines/tax_lines/refunds revoked;
app_worker's INSERT on credits/credit_ledger_entries revoked — ALL FIXED, live-confirmed

Third-pass (freeze-gate) findings (1 BLOCKER + 1 SIGNIFICANT the second pass missed,
explicitly disclosed, not hidden — validation report §19) — ALL FOUND AND FIXED:
  FINAL-6K-01  app_api retained EXECUTE on fn_record_payment_webhook_receipt, allowing the
               general tenant role to pre-claim/poison a real provider event ID before the
               genuine webhook arrived, despite the function itself accepting no financial
               fields — FIXED: EXECUTE now granted only to a new dedicated role,
               app_billing_webhook_ingress (modeled on the app_voice_reconciler precedent),
               with app_api/app_worker/app_platform_admin all confirmed permission denied
  FINAL-6K-02  CALL_MINUTES usage_events rows could be inserted with
               source_quantity_seconds = NULL, leaving the exact-aggregation billing
               guarantee dependent on ingestion-consumer discipline rather than a DB
               invariant — FIXED: chk_ue_source_quantity_seconds strengthened to require the
               column non-NULL specifically for CALL_MINUTES; every other metric unaffected
  (full closure table with live evidence: validation report §24)

Fourth-pass (freeze-gate) findings (1 BLOCKER + 1 documentation BLOCKER + 1 SIGNIFICANT the
third pass missed, explicitly disclosed, not hidden — validation report §25) — ALL FOUND AND FIXED:
  FREEZE-6K-01  app_platform_admin retained raw INSERT/UPDATE/DELETE directly on
                payment_webhook_receipts — closing EXECUTE on the ingress function (third pass)
                did not close this separate raw-table-DML bypass, which could still pre-claim/
                poison a real provider event ID or rewrite/delete receipt rows outright — FIXED:
                INSERT/UPDATE/DELETE revoked; SELECT retained (narrow, read-only, documented);
                no role holds DELETE on this table at all
  FREEZE-6K-02  6K-Billing-Usage-APIs.md's own ADR-6K-15 and one §12.8 table row still described
                the ingress function as app_api-reachable/callable, stale relative to the third
                pass's own fix — FIXED: ADR-6K-15 rewritten in full; every cross-referencing
                section checked and corrected; whole-document grep sweep confirms zero stale
                matches remain
  FREEZE-6K-03  No preserved fresh/incremental Alembic migration transcript existed proving the
                third pass's own final checksum — FIXED: fresh + incremental migration re-run
                against the exact final file, checksum cross-checked against the manifest
  (full closure table with live evidence: validation report §31)

CRITICAL issues:      NONE
SIGNIFICANT issues:   NONE (the second pass's own significant finding — webhook linkage
                       provenance — remains fixed, folded into FB-6K-05's closure; the third
                       pass's significant finding — FINAL-6K-02 — remains fixed; the fourth
                       pass's evidence-gap finding — FREEZE-6K-03 — is fixed, folded into this
                       closure table)
BLOCKING ISSUES:      NONE — all four owner decisions are ACCEPTED/FINAL; the additive migration
                       (amended in place a fourth time, never applied to a persistent database at
                       any point) is live-validated (fresh + incremental, PostgreSQL 18.6, single
                       head, checksum-verified) after all four remediation passes; the complete
                       original regression suite plus targeted regression smoke tests in the
                       third and fourth passes were re-run against the corrected file and show
                       zero true regressions

Remaining items (explicitly non-blocking, not silently omitted):
  DEP-6K-01 — TOOL_EXECUTIONS usage producer (not yet built anywhere upstream)
  DEP-6K-02 — KNOWLEDGE_RETRIEVALS usage producer (not yet built anywhere upstream)
  DEP-6K-03 — 6M's manual billing-account suspend/reactivate override function (no V1
              requirement forces it; a small future 5H additive migration if ever needed)
  DEP-6K-04 — 6C's own tax-profile endpoint existence (unverified, not duplicated here)
  DEP-6K-05 — 6E/6I field-shape confirmation for the LLM-usage producer ownership rule
  ODD-5H-02 — downgrade proration (genuinely open upstream, not a 6K blocker)

PHASE 6K STATUS = READY FOR INDEPENDENT FREEZE-GATE REVIEW
  — every section is designed, and the database layer is implemented and live-validated across
    four full remediation passes, each correcting the blockers/significant issues an
    independent review found in the previous pass's own supposedly-final state;
  — migration 102_5H2 is real, executable SQL, run fresh and incrementally against genuine
    PostgreSQL 18.6 instances after each pass, with full adversarial/security/functional test
    evidence, a verified checksum, and zero true regressions between passes;
  — final freeze is reserved for independent review, per this pass's own governing instruction,
    not declared unilaterally here — this document does not claim its own prior "READY" verdict
    was sufficient; it discloses exactly what that verdict missed and shows the fix, each time.
```

---

## 50. API Examples (Representative)

Additional to the inline examples already shown in §18.1 (`GET /billing/subscription`) and §33.1 (`GET /billing/summary`). Money is always `{amount, currency}` (6A §7.5); no example below shows a real payment secret.

**`GET /billing/invoices/{invoice_id}` — 200:**
```json
{
  "data": {
    "id": "01930000-0000-7000-8000-0000000000f1",
    "invoice_number": "INV/2026/000042",
    "invoice_kind": "TAX_INVOICE",
    "status": "OPEN",
    "currency": "INR",
    "issue_date": "2026-08-01",
    "due_date": "2026-08-15",
    "subtotal": { "amount": "77000.0000", "currency": "INR" },
    "total_credits": { "amount": "0.0000", "currency": "INR" },
    "total_tax": { "amount": "13860.0000", "currency": "INR" },
    "total_due": { "amount": "90860.0000", "currency": "INR" },
    "amount_paid": { "amount": "0.0000", "currency": "INR" },
    "place_of_supply": "KA",
    "lines": [
      { "line_type": "BASE_FEE", "description": "Growth plan — negotiated", "quantity": "1",
        "unit_price": { "amount": "75000.0000", "currency": "INR" },
        "line_total": { "amount": "75000.0000", "currency": "INR" },
        "unit_price_source": "AGREEMENT", "included_quantity_source": null },
      { "line_type": "OVERAGE", "description": "CALL_MINUTES overage", "metric": "CALL_MINUTES",
        "quantity": "666.6700", "unit_price": { "amount": "3.0000", "currency": "INR" },
        "line_total": { "amount": "2000.0000", "currency": "INR" },
        "unit_price_source": "AGREEMENT", "included_quantity_source": "AGREEMENT" }
    ],
    "tax_lines": [
      { "component_code": "CGST", "rate_percent": "9.0000",
        "taxable_amount": { "amount": "77000.0000", "currency": "INR" },
        "tax_amount": { "amount": "6930.0000", "currency": "INR" } },
      { "component_code": "SGST", "rate_percent": "9.0000",
        "taxable_amount": { "amount": "77000.0000", "currency": "INR" },
        "tax_amount": { "amount": "6930.0000", "currency": "INR" } }
    ]
  },
  "meta": { "request_id": "01930000-0000-7000-8000-000000000200" }
}
```

**`POST /billing/invoices/{invoice_id}/payment-intent` — 202:**
```json
{
  "data": {
    "payment_attempt_id": "01930000-0000-7000-8000-0000000000f2",
    "provider": "RAZORPAY",
    "client_instructions": { "order_id": "order_opaque_ref", "checkout_key": "opaque_public_key" }
  },
  "meta": { "request_id": "..." }
}
```

**Payment failure — surfaced via `GET /billing/payments/{id}`:**
```json
{
  "data": {
    "id": "01930000-0000-7000-8000-0000000000f2",
    "invoice_id": "01930000-0000-7000-8000-0000000000f1",
    "status": "FAILED",
    "amount": { "amount": "90860.0000", "currency": "INR" },
    "payment_method_kind": "UPI",
    "failure_code": "INSUFFICIENT_FUNDS",
    "initiated_at": "2026-08-02T10:15:00.000Z",
    "completed_at": "2026-08-02T10:15:42.000Z"
  }
}
```

**`GET /billing/quotas` — 200 (excerpt):**
```json
{
  "data": [
    { "metric": "CALL_MINUTES", "unit_label": "minutes", "soft_limit": "600.0000", "hard_limit": null,
      "current_usage": "666.6700", "remaining": null, "overage_allowed": true,
      "period": { "period_start": "2026-08-01", "period_end": "2026-09-01" } },
    { "metric": "ACTIVE_PHONE_NUMBERS", "unit_label": "count", "soft_limit": "8.0000", "hard_limit": "10.0000",
      "current_usage": "9.0000", "remaining": "1.0000", "overage_allowed": false,
      "period": { "period_start": "2026-08-01", "period_end": "2026-09-01" } }
  ]
}
```

**Error — cross-tenant invoice access:**
```json
{ "error": { "code": "RESOURCE_NOT_FOUND", "message": "The requested resource could not be found.",
  "details": {}, "request_id": "...", "retryable": false } }
```

**Error — quota exceeded (surfaced by 6D/6H, billing-owned code):**
```json
{ "error": { "code": "QUOTA_EXCEEDED", "message": "CALL_MINUTES hard limit reached for the current billing period.",
  "details": { "metric": "CALL_MINUTES", "hard_limit": "1000.0000", "current_usage": "1000.0000" },
  "request_id": "...", "retryable": false } }
```


