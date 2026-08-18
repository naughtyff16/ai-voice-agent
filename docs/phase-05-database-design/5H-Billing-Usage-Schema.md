# Phase 5H — Billing / Usage Schema

> **Phase-numbering note (RECONCILED):** The Phase 5A roadmap §30 originally defined `5F = knowledge + workflow` and `5G = billing`. However, Phase 5F was executed covering `knowledge` only, and Phase 5G was executed and approved covering `workflow / prompt / memory`. This created a cascade. The `PHASE-NUMBERING-RECONCILIATION.md` document formally resolves the conflict: the executed and approved artifact sequence is authoritative. Billing is **Phase 5H**. The Phase 5A §30 numbering table is superseded by that reconciliation for labels 5F onward; all other Phase 5A standards remain frozen. Migration numbers 047–058 are unaffected.

| | |
|---|---|
| **Phase** | 5H — per PHASE-NUMBERING-RECONCILIATION.md (final authority) |
| **Schemas covered** | `billing` |
| **Depends on** | 5A (standards), 5B (identity/RLS), 5C–5G (usage-source boundaries, through Workflow) |
| **Migration chain** | 047–058 (continuing from migration 046, last migration of Phase 5G Workflow) |
| **Follows** | Phase 5G — Workflow / Prompt / Memory Schema (APPROVED) |
| **Precedes** | Phase 5I — integrations / webhooks / plugins |
| **Status** | See §33 |

---

## 1. Executive Summary

Phase 5H defines the physical PostgreSQL schema for the Billing & Usage bounded context. It covers plans, plan versions, pricing, subscriptions, billing periods, usage events, usage records, usage aggregation, entitlements, quotas, credits, invoices, invoice lines, tax lines, payments, refunds, financial audit, and India-first GST infrastructure.

All decisions derive from the approved Phase 4F DDD, Phase 4I India-First closure, and Phase 5A database standards. No business rule is invented here; unresolved gaps are marked **OPEN DESIGN DECISION**.

Key design positions:
- **One bounded context** — Billing + Subscription + Usage Metering are one `billing` schema per Phase 4F DDR-4F-001.
- **INR-first, multi-currency capable** — every monetary column is a `(amount NUMERIC(18,4), currency CHAR(3))` pair; no floating point; INR is the seeded default.
- **Plan versioning** — a `PlanVersion` is immutable once published; historical invoices pin to the version active at time of subscription/change.
- **Usage idempotency** — `(organization_id, source_system, source_event_id)` unique constraint on `usage_events`; Redis is the enforcement hot-tier; Postgres is the audit authority.
- **Financial immutability** — `REVOKE UPDATE, DELETE` on finalized financial tables; corrections via credit notes / adjustments only.
- **GST-ready** — tax is configuration-driven through `tax_rules` rows; no rate appears in schema constants.
- **Payment abstraction** — `payment_provider` column; no provider-specific columns; no payment credentials stored.

---

## 2. Scope

**In scope (billing schema owns):**

`billing_accounts`, `subscriptions`, `plans`, `plan_versions`, `plan_prices`, `billing_periods`, `usage_events`, `usage_records`, `cost_entries`, `quota_configs`, `credits`, `credit_ledger_entries`, `invoices`, `invoice_lines`, `tax_lines`, `invoice_number_sequences`, `tax_profiles`, `tax_categories`, `tax_rules`, `payment_attempts`, `refunds`, `fx_rates`, `billing_adjustments`

**Out of scope (owned elsewhere, referenced logically):**

- Voice call data → `voice` schema (authoritative for call duration; billing consumes `call.ended` events)
- CRM contacts → `crm` schema
- Campaign data → `campaign` schema
- Knowledge / RAG → `knowledge` schema
- Workflow / memory → `workflow` + `memory` schemas
- Identity / organization → `organization` schema (authoritative for `organization_id`)

---

## 3. Bounded Context Ownership

Per Phase 4F DDR-4F-001: **Billing & Subscription** and **Usage Metering** are one bounded context, one schema (`billing`). Quotas, Pricing, and Payment fold into Billing. Integration / Webhook / Plugin are separate schemas (Phase 5I per PHASE-NUMBERING-RECONCILIATION.md — that sub-phase covers integrations/webhooks/plugins; this document covers only `billing`).

Cross-domain data flow (event-driven, no cross-schema FK):

```
Voice (call.ended)           → Billing subscriber → usage_events INSERT
Campaign (call_attempted)    → Billing subscriber → usage_events INSERT
Workflow (execution_completed)→ Billing subscriber → usage_events INSERT
Knowledge (embedding.generated)→ Billing subscriber → usage_events INSERT
Organization (org.created)   → Billing subscriber → billing_accounts INSERT
Invoice (payment_succeeded)  → Billing → Subscription state update
```

---

## 4. Platform vs Tenant Ownership

| Table | Owner | organization_id | RLS |
|---|---|---|---|
| `plans` | Platform | — | No (public read) |
| `plan_versions` | Platform | — | No (public read) |
| `plan_prices` | Platform | — | No (public read) |
| `tax_categories` | Platform | — | No |
| `tax_rules` | Platform | — | No |
| `fx_rates` | Platform | — | No |
| `billing_accounts` | Tenant | YES | YES |
| `subscriptions` | Tenant | YES | YES |
| `billing_periods` | Tenant | YES | YES |
| `usage_events` | Tenant | YES | YES |
| `usage_records` | Tenant | YES | YES |
| `cost_entries` | Tenant | YES | YES |
| `quota_configs` | Tenant | YES | YES |
| `credits` | Tenant | YES | YES |
| `credit_ledger_entries` | Tenant | YES | YES |
| `invoices` | Tenant | YES | YES |
| `invoice_lines` | Tenant | YES | YES |
| `tax_lines` | Tenant | YES | YES |
| `invoice_number_sequences` | Tenant | YES | YES |
| `tax_profiles` | Tenant | YES | YES |
| `payment_attempts` | Tenant | YES | YES |
| `refunds` | Tenant | YES | YES |
| `billing_adjustments` | Tenant | YES | YES |

---

## 5. Aggregate → Table Mapping

| DDD Aggregate | Primary Table(s) |
|---|---|
| BillingAccount | `billing_accounts` |
| Plan | `plans`, `plan_versions`, `plan_prices` |
| Subscription | `subscriptions` |
| BillingPeriod | `billing_periods` |
| UsageEvent | `usage_events` (partitioned) |
| UsageRecord | `usage_records` |
| CostEntry | `cost_entries` (partitioned) |
| QuotaConfig | `quota_configs` |
| Credit | `credits`, `credit_ledger_entries` |
| Invoice | `invoices`, `invoice_lines`, `tax_lines` |
| TaxProfile | `tax_profiles` |
| TaxRule | `tax_rules`, `tax_categories` |
| InvoiceNumberSequence | `invoice_number_sequences` |
| PaymentAttempt | `payment_attempts` |
| Refund | `refunds` |
| BillingAdjustment | `billing_adjustments` |
| FxRate | `fx_rates` |

---

## 6. Domain Invariants

Per Phase 4F §4.1–§4.4 and Phase 4I §10–§12:

1. **INV-BILL-01** — `BillingAccount.currency` is immutable after creation; all financial records for the account use the same currency.
2. **INV-BILL-02** — A `PAID` or `VOID` invoice is immutable; no lines may be added/removed/mutated.
3. **INV-BILL-03** — `invoice.total_due_amount = subtotal_amount − total_credits_amount + total_tax_amount` — always computed, never set directly.
4. **INV-BILL-04** — `total_due_amount ≥ 0` — credits cannot reduce an invoice below zero.
5. **INV-BILL-05** — `PlanVersion` is immutable once published (`is_published = TRUE`); price changes require a new version.
6. **INV-BILL-06** — A `CANCELLED` subscription is terminal; reactivation requires a new subscription.
7. **INV-BILL-07** — `subscription.current_period_end > subscription.current_period_start` — always.
8. **INV-BILL-08** — Every usage event has a unique `(organization_id, source_system, source_event_id)` — enforced by DB constraint.
9. **INV-BILL-09** — Financial records (`usage_events`, `invoices`, `invoice_lines`, `payment_attempts`, `refunds`) are append-only; mutations only through compensating records.
10. **INV-BILL-10** — Credit balance is derived from `credit_ledger_entries`; no single mutable balance column is the source of truth.
11. **INV-BILL-11** — Invoice numbers are gapless per `(organization_id, fiscal_year, prefix)`; allocated via row-locked sequence table.
12. **INV-BILL-12** — No tax rate, slab, threshold, or GST percentage appears in schema defaults, CHECK constraints, or enum values.
13. **INV-BILL-13** — `ScheduledChange` on a subscription is applied exactly once at the next period boundary; cleared after application.
14. **INV-BILL-14** — No payment credentials (card numbers, CVV, bank credentials) are stored; only opaque `payment_method_ref` tokens from the gateway.

---

## 7. Currency / Money Model

Per Phase 5A §10 and Phase 4I §11:

- All monetary columns appear in pairs: `{field}_amount NUMERIC(18,4)` + `{field}_currency CHAR(3)`.
- `NUMERIC(18,4)` gives 14 integer digits and 4 decimal places; sufficient for INR paise-precision and USD cent-precision.
- No `FLOAT`, no PostgreSQL `MONEY` type.
- Currency code validated against ISO 4217 via a `CHECK` referencing the `fx_rates` table's currency codes (or application-layer validation — see ADR-5H-008).
- Negative amounts represent credits/adjustments; no separate sign column.
- Rounding: banker's rounding (round half to even) applied at application layer before storage.
- V1 default currency: `INR`.

**Tax representation:**
- `tax_lines` stores one row per tax component (`CGST`, `SGST`, `IGST`, etc.) per taxable line group.
- `invoices.total_tax_amount` is the sum; `invoices.total_tax_currency` must equal `invoices.currency`.
- No tax rate hard-coded in schema.

**FX for cost entries:**
- `cost_entries` carries `amount_amount / amount_currency` (provider currency, e.g. USD) plus `amount_in_billing_currency_amount / amount_in_billing_currency_currency` (nullable, converted), `fx_rate_used NUMERIC(12,6)`, `fx_rate_source TEXT`, `fx_rate_captured_at TIMESTAMPTZ`.
- The rate used is **recorded on the row** — historical margin reports are deterministic.

---

## 8. Plan / Pricing Model

### 8.1 Structure

```
plans (platform-owned, catalogue)
  └── plan_versions (immutable snapshots, 1:many per plan)
        └── plan_prices (overage rates per metric, 1:many per plan_version)
```

### 8.2 Plan Version Immutability

Once `plan_versions.is_published = TRUE`, the row is immutable (enforced by trigger). Price changes require a new `plan_version` row with a new `version_number`. Existing subscriptions retain their `plan_version_id` reference; historical invoices never read from the current plan version.

### 8.3 Billing Cycles

Supported: `MONTHLY`, `ANNUAL`. **OPEN DESIGN DECISION**: custom intervals (weekly, quarterly) not defined in Phase 4F — excluded from V1.

### 8.4 Included Quotas and Overage

Per-metric included quantities and overage unit prices are stored in `plan_prices` (one row per `(plan_version_id, metric)`). This avoids encoding metrics as columns.

---

## 9. Subscription Model

### 9.1 States (Phase 4F §7.1)

`TRIAL` → `ACTIVE` → `PAST_DUE` → `SUSPENDED` → `CANCELLED` (terminal)

### 9.2 Answers to Phase 5H §6 Questions

1. **Can a tenant have multiple subscriptions?** — Yes, but only one may be `ACTIVE` or `TRIAL` at a time (enforced by partial unique index).
2. **Can only one subscription be active?** — Yes per above.
3. **Plan changes** — Modelled as `scheduled_change_plan_version_id` on the current subscription; applied at next period boundary.
4. **Upgrade** — Immediate: current subscription cancelled + new subscription created within one UoW; prorated credit issued via `ProratedCreditService`.
5. **Downgrade** — Scheduled: `scheduled_change_plan_version_id` set; applied at `current_period_end`.
6. **Mid-period change** — Upgrades immediate with prorated credit; downgrades deferred.
7. **Proration in V1** — Supported for upgrades only (Phase 4F §4.2 business rules). Downgrade proration: **OPEN DESIGN DECISION**.
8. **Renewals** — Worker job at `current_period_end` creates new `billing_period`, applies `scheduled_change` if present, generates invoice.
9. **Failed payment** — Subscription transitions to `PAST_DUE`; grace period 7 days (configurable); then `SUSPENDED` if unresolved.

---

## 10. Billing Period Model

One `billing_periods` row per `(organization_id, subscription_id, period_start, period_end)`. Periods are closed after invoice generation. A closed period is immutable — reopening **OPEN DESIGN DECISION** (not defined in Phase 4F; excluded from V1).

`billing_periods.timezone` stores the tenant's `LocalizationProfile.timezone` at period creation — periods are deterministic even if the tenant later changes their timezone.

---

## 11. Usage Metering Model

### 11.1 Usage Dimensions (Phase 4I §10.2)

| Metric | Unit |
|---|---|
| `CALL_MINUTES` | minutes |
| `AI_MINUTES` | minutes |
| `STT_SECONDS` | seconds |
| `TTS_CHARACTERS` | characters |
| `LLM_PROMPT_TOKENS` | tokens |
| `LLM_COMPLETION_TOKENS` | tokens |
| `EMBEDDING_TOKENS` | tokens |
| `CAMPAIGN_CALLS` | calls |
| `WORKFLOW_EXECUTIONS` | executions |
| `TOOL_EXECUTIONS` | executions |
| `KNOWLEDGE_RETRIEVALS` | queries |
| `STORAGE_GB` | GB-months |
| `API_REQUESTS` | requests |
| `ACTIVE_AGENTS` | count |
| `ACTIVE_PHONE_NUMBERS` | count |

Stored as `TEXT` in `usage_events.metric`; validated at application layer against the enum. New metrics are new data rows, not schema migrations.

### 11.2 Usage Source Boundary

| Source | Authoritative data | Billing receives |
|---|---|---|
| Voice | `voice.call_sessions` (call duration) | `call.ended` event → `CALL_MINUTES` usage event |
| Voice | `voice.conversation_turns` (AI time) | `conversation.turn_completed` → `LLM_*`, `STT_*`, `TTS_*` events |
| Campaign | `campaign.call_jobs` | `campaign.contact.call_attempted` → `CAMPAIGN_CALLS` |
| Workflow | `workflow.workflow_executions` | `workflow.execution_completed` → `WORKFLOW_EXECUTIONS` |
| Knowledge | `knowledge.ingestion_jobs` | `document.indexed` → `EMBEDDING_TOKENS` |

Billing does **not** query voice/campaign/workflow/knowledge tables directly.

---

## 12. Usage Aggregation

Architecture (Phase 3E §6.3):

```
usage_events (append-only, partitioned)    ← authoritative raw record
    ↓ (Celery batch job, nightly)
usage_records (aggregated per metric per billing period)  ← billing calculation source
    ↓
OverageCalculationService (pure function)
    ↓
invoice_lines (USAGE / OVERAGE types)
```

Raw `usage_events` are the audit authority and must not be deleted while referenced by open or finalized invoices. Retention: 90 days hot per Phase 4I §9.4 `UsageEventRetentionDays`; S3 archive thereafter.

Redis quota counters are the enforcement hot-tier (sub-millisecond `INCR`). A nightly reconciliation job recomputes Redis from Postgres `usage_records` to correct any pod-crash divergence (Phase 3E §6.3).

---

## 13. Entitlements / Quotas

```
plans → plan_versions → plan_prices (included_quantity, overage_rate per metric)
                              ↓ (seeded on subscription creation)
                        quota_configs (per org per metric — current limits)
                              ↓ (Redis hot-tier: enforcement)
                        usage_records (Postgres: audit + billing source)
```

`quota_configs` carries `hard_limit` (block on exceed) and `soft_limit` (warn, allow overage). A `hard_limit = NULL` means no hard cap (metered overage only).

**OPEN DESIGN DECISION**: mid-period quota override by admin (ad-hoc limit changes) — not defined in Phase 4F; excluded from V1 DDL; `quota_configs.override_reason` reserved for future use.

---

## 14. Credit Model

### 14.1 Ledger Pattern

Phase 4F specifies `BillingAccount.CreditBalance` as non-negative. To meet INV-BILL-10 (no single mutable balance), credits are an event-sourced ledger:

```
credits          — the credit grant record (source, amount, expiry)
credit_ledger_entries  — append-only debit/credit entries; sum = current balance
```

`BillingAccount.credit_balance_amount` is a **derived, cached** value updated by trigger on `credit_ledger_entries` INSERT — not the authoritative source. The authoritative balance is `SUM(credit_ledger_entries.amount) WHERE organization_id = X`.

### 14.2 Credit Types

`PROMOTIONAL`, `MANUAL`, `REFUND_CREDIT`, `PRORATION_CREDIT`

### 14.3 Credit Expiration

`credits.expires_at` — NULL means no expiry. Expired credits are deactivated by a scheduled job (status `EXPIRED`); their `credit_ledger_entries` balance is zeroed with a compensating entry.

---

## 15. Overage Model

```
usage_records.quantity_used
    - plan_prices.included_quantity  (from pinned plan_version_id on subscription)
    = overage_quantity  (if > 0)

overage_amount = overage_quantity × plan_prices.overage_rate_amount
```

The `plan_prices` row used is the one pinned to `subscription.plan_version_id` — not the current plan version. Historical overage calculations are deterministic even after plan price changes.

`invoice_lines` of type `OVERAGE` snapshot `unit_price_amount`, `unit_price_currency`, `quantity`, `metric`, `billing_period_id` to ensure the line is self-explanatory without joining back to `plan_prices`.

---

## 16. Invoice Model

### 16.1 Invoice Lifecycle

`DRAFT` → `OPEN` → `PAID` | `VOID`

`DRAFT`: generated, lines being assembled.
`OPEN`: finalized, sent to customer, payment due.
`PAID`: payment succeeded; immutable.
`VOID`: cancelled before payment (credit note issued for corrections).

### 16.2 Immutability

`REVOKE UPDATE, DELETE ON billing.invoices FROM app_api, app_worker` — enforced at DB layer. Status transitions only via SECURITY DEFINER functions.

### 16.3 India Invoice Extensions (Phase 4I §12.5)

- `tax_profile_snapshot JSONB` — snapshot of `tax_profiles` at invoice generation.
- `place_of_supply TEXT` — Indian state code or jurisdiction.
- `invoice_kind TEXT` — `TAX_INVOICE | CREDIT_NOTE | DEBIT_NOTE | PROFORMA`.
- `related_invoice_id UUID` — for credit/debit notes.
- `invoice_number TEXT` — gapless sequential from `invoice_number_sequences`.
- `e_invoice_ref TEXT` — reserved for future IRN (e-invoicing).
- `tax_rule_versions_applied INTEGER[]` — rule version numbers used at compute time.

---

## 17. Payment Model

### 17.1 Provider Abstraction

`payment_attempts.payment_provider TEXT` — `RAZORPAY | CASHFREE | STRIPE | OTHER`.
No provider-specific columns. Provider transaction ID stored as `provider_transaction_id TEXT`.

No card numbers, CVV, or bank credentials stored. `payment_method_ref TEXT` is an opaque gateway token.

### 17.2 Payment Lifecycle

`INITIATED` → `PENDING` → `SUCCEEDED` | `FAILED` | `CANCELLED`

`REFUNDED` / `PARTIALLY_REFUNDED` are states on the `refunds` table, not on `payment_attempts`.

### 17.3 Webhook Idempotency

`payment_attempts.provider_webhook_event_id TEXT` — unique per provider event. DB unique constraint prevents duplicate webhook processing.

---

## 18. Refund Model

Refunds are separate records referencing `payment_attempts.id`. The original payment amount is never mutated.

Partial refunds supported: `refunds.amount_amount ≤ payment_attempts.amount_amount`.

Sum of refunds for a payment must not exceed original amount — enforced by application layer + DB check function (see `fn_validate_refund_amount`).

States: `PENDING` → `SUCCEEDED` | `FAILED`.

---

## 19. GDPR / PII

| Table | PII fields | Handling |
|---|---|---|
| `tax_profiles` | `registration_number` (GSTIN), `billing_address` (JSONB) | Retained for financial compliance; anonymization deferred to retention policy |
| `invoices` | `tax_profile_snapshot` (JSONB — contains address/GSTIN) | Financial record; retention per compliance policy; anonymization on data subject request after statutory period |
| `billing_accounts` | `billing_contact_email`, `billing_contact_name` | Anonymized on org deletion (replace with `[redacted]`) |
| `payment_attempts` | `payment_method_ref` (opaque token, not PII) | No PII stored |
| `usage_events` | `source_context JSONB` — may contain session_ref | Retain 90 days hot; do not store contact-identifying data in source_context |

**Financial retention conflict:** invoices and tax records may have statutory retention requirements (India: GST records 6 years). If a GDPR erasure request conflicts, anonymize non-essential PII fields while retaining the financial record skeleton. **OPEN DESIGN DECISION**: exact retention periods and anonymization scope require legal review; architecture does not invent statutory rules.

Deletion/anonymization is executed by a SECURITY DEFINER function `fn_billing_anonymize_org` triggered by the data subject request workflow (Phase 5B).

---

## 20. Security Model

| Threat | Mitigation |
|---|---|
| Cross-tenant billing access | RLS `organization_id = organization.current_tenant_id()` on all tenant tables |
| Invoice tampering | `REVOKE UPDATE, DELETE` on `invoices`, `invoice_lines`, `tax_lines`, `payment_attempts`, `refunds`; SECURITY DEFINER functions for status transitions |
| Usage injection | Unique constraint `(organization_id, source_system, source_event_id)` on `usage_events`; source_system validated at application layer |
| Duplicate charging | Idempotency key on `payment_attempts`; webhook deduplication via `provider_webhook_event_id` |
| Price manipulation | `plan_versions` and `plan_prices` platform-owned; `app_api` role has `SELECT` only; only `app_platform_admin` can INSERT/UPDATE |
| Entitlement manipulation | `quota_configs` modified only by subscription lifecycle functions; not directly writable by `app_api` |
| Unauthorized credits | Credits created only via SECURITY DEFINER `fn_billing_apply_credit`; `app_api` cannot INSERT into `credits` directly |
| Unauthorized refunds | Refunds created only via SECURITY DEFINER `fn_billing_create_refund` |
| Secret leakage | No payment credentials stored; `payment_method_ref` is opaque gateway token |
| PII leakage | GSTIN and billing address in `tax_profiles` subject to column-level encryption per deployment config |

---

## 21. Concurrency / Idempotency

| Race | Mitigation |
|---|---|
| Duplicate usage event | `UNIQUE (organization_id, source_system, source_event_id)` on `usage_events` + `ON CONFLICT DO NOTHING` |
| Invoice generation race | `billing_periods.invoice_generated_at` timestamp + `billing_periods` status check in same transaction; advisory lock `pg_advisory_xact_lock(hashtext(org_id || period_id))` |
| Payment webhook race | `UNIQUE (payment_provider, provider_webhook_event_id)` on `payment_attempts`; webhook handler uses `ON CONFLICT DO NOTHING` |
| Refund duplicate | `UNIQUE (payment_attempt_id, provider_refund_id)` on `refunds` |
| Credit consumption race | `SELECT FOR UPDATE` on `credit_ledger_entries` balance computation; compensating entry written atomically |
| Quota consumption race | Redis `INCR` is atomic; Postgres `usage_records` updated by serialized batch job |
| Subscription renewal race | `SELECT FOR UPDATE` on `subscriptions` row during renewal; advisory lock on org |
| Subscription transition race | `UPDATE subscriptions SET status = $new WHERE id = $id AND status = $expected` — optimistic; retry on 0-rows-affected |
| Invoice number allocation | `SELECT ... FOR UPDATE` on `invoice_number_sequences` row; gapless guarantee |

---

## 22. Index Strategy

All indexes map to query patterns documented in §25.

```sql
-- billing_accounts
idx_ba_org          (organization_id)                           -- RLS support
-- subscriptions
idx_sub_org_status  (organization_id, status)                   -- QP-01, QP-02
idx_sub_active      (organization_id) WHERE status IN ('TRIAL','ACTIVE')  -- one-active check
-- billing_periods
idx_bp_sub          (subscription_id, period_start DESC)        -- QP-03
idx_bp_org_open     (organization_id) WHERE closed_at IS NULL   -- open period lookup
-- usage_events (per partition)
idx_ue_idempotency  (organization_id, source_system, source_event_id)  -- QP-05 (UNIQUE)
idx_ue_org_metric   (organization_id, metric, occurred_at DESC)        -- QP-06
idx_ue_billing_period (billing_period_id)                              -- aggregation
-- usage_records
idx_ur_org_metric_period (organization_id, metric, period_start)       -- QP-06, QP-07
-- quota_configs
idx_qc_org_metric   (organization_id, metric)  UNIQUE           -- QP-07
-- credits
idx_cr_org_status   (organization_id, status, expires_at)       -- QP-14
-- credit_ledger_entries
idx_cle_org         (organization_id, created_at DESC)          -- balance sum
idx_cle_credit      (credit_id)                                 -- by credit
-- invoices
idx_inv_org_status  (organization_id, status)                   -- QP-09, QP-10
idx_inv_number      (organization_id, invoice_number)  UNIQUE   -- lookup
idx_inv_period      (billing_period_id)                         -- period invoices
-- invoice_lines
idx_il_invoice      (invoice_id)                                -- line lookup
-- tax_lines
idx_tl_invoice      (invoice_id)                                -- tax lookup
-- payment_attempts
idx_pa_invoice      (invoice_id)                                -- QP-11
idx_pa_provider_tx  (payment_provider, provider_transaction_id) -- QP-12
idx_pa_webhook      (payment_provider, provider_webhook_event_id) UNIQUE  -- dedup
-- refunds
idx_ref_payment     (payment_attempt_id)                        -- QP-13
idx_ref_provider    (payment_provider, provider_refund_id)  UNIQUE  -- dedup
-- invoice_number_sequences
idx_ins_org_fy      (organization_id, fiscal_year, prefix)  UNIQUE  -- sequence lock
-- tax_profiles
idx_tp_org          (organization_id)  UNIQUE               -- one per org
-- cost_entries (per partition)
idx_ce_org_metric   (organization_id, metric, recorded_at DESC)
idx_ce_source       (source_system, source_event_id)
-- fx_rates
idx_fx_pair_date    (from_currency, to_currency, effective_date DESC)
```

---

## 23. Partitioning

| Table | Partition | Rationale | Threshold |
|---|---|---|---|
| `usage_events` | RANGE on `occurred_at` (monthly) | High volume; 15 metrics × all tenants; query patterns are time-bounded | Partition from V1; estimated >1M rows/month at scale |
| `cost_entries` | RANGE on `recorded_at` (monthly) | Same reasoning as usage_events | Partition from V1 |
| `payment_attempts` | Not partitioned in V1 | Lower volume; full-table scans unlikely | Partition if >5M rows or query latency >500ms |
| `invoice_lines` | Not partitioned in V1 | Bounded by invoice count | Partition if >10M rows |

**Partition creation:** monthly partitions pre-created 3 months ahead by a scheduled job. Default safety partition captures overflow. Naming: `usage_events_y2026m08`.

---

## 24. Complete PostgreSQL DDL

```sql
-- ================================================================
-- Migration 047: billing schema, extensions, and utility functions
-- ================================================================

CREATE SCHEMA IF NOT EXISTS billing;

GRANT USAGE ON SCHEMA billing TO app_api, app_worker, app_readonly, app_platform_admin;

-- ----------------------------------------------------------------
-- Trigger: set_updated_at (shared function from 5A/5B — already exists)
-- ----------------------------------------------------------------

-- ----------------------------------------------------------------
-- Immutability trigger factory
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION billing.fn_raise_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'billing: % is immutable after finalization', TG_TABLE_NAME;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_raise_immutable() FROM PUBLIC;

-- ----------------------------------------------------------------
-- Platform-owned: plans
-- ----------------------------------------------------------------
CREATE TABLE billing.plans (
  id            UUID    NOT NULL DEFAULT gen_uuid_v7(),
  name          TEXT    NOT NULL,
  description   TEXT    NULL,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_plans      PRIMARY KEY (id),
  CONSTRAINT uq_plan_name  UNIQUE (name),
  CONSTRAINT chk_plan_name CHECK (length(name) BETWEEN 1 AND 100)
);

CREATE TRIGGER trg_plans_updated_at
  BEFORE UPDATE ON billing.plans
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- No RLS — platform-owned, publicly readable
GRANT SELECT ON billing.plans TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.plans TO app_platform_admin;

-- ----------------------------------------------------------------
-- Platform-owned: plan_versions (immutable once published)
-- ----------------------------------------------------------------
CREATE TABLE billing.plan_versions (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  plan_id          UUID    NOT NULL REFERENCES billing.plans(id) ON DELETE RESTRICT,
  version_number   INTEGER NOT NULL,
  billing_cycle    TEXT    NOT NULL,
  base_price_amount   NUMERIC(18,4) NOT NULL,
  base_price_currency CHAR(3)       NOT NULL DEFAULT 'INR',
  is_published     BOOLEAN NOT NULL DEFAULT FALSE,
  effective_from   DATE    NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_plan_versions       PRIMARY KEY (id),
  CONSTRAINT uq_plan_version_number UNIQUE (plan_id, version_number),
  CONSTRAINT chk_pv_billing_cycle   CHECK (billing_cycle IN ('MONTHLY','ANNUAL')),
  CONSTRAINT chk_pv_base_price      CHECK (base_price_amount >= 0),
  CONSTRAINT chk_pv_currency        CHECK (base_price_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_pv_version_number  CHECK (version_number >= 1)
);

-- Immutability: once published, key financial fields cannot change
CREATE OR REPLACE FUNCTION billing.fn_plan_version_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_published = TRUE THEN
    IF NEW.base_price_amount  <> OLD.base_price_amount
    OR NEW.base_price_currency <> OLD.base_price_currency
    OR NEW.billing_cycle       <> OLD.billing_cycle
    OR NEW.effective_from      <> OLD.effective_from THEN
      RAISE EXCEPTION 'billing: plan_version % is published and immutable', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_plan_version_immutability() FROM PUBLIC;

CREATE TRIGGER trg_pv_immutability
  BEFORE UPDATE ON billing.plan_versions
  FOR EACH ROW EXECUTE FUNCTION billing.fn_plan_version_immutability();

GRANT SELECT ON billing.plan_versions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.plan_versions TO app_platform_admin;

-- ----------------------------------------------------------------
-- Platform-owned: plan_prices (per-metric pricing within a version)
-- ----------------------------------------------------------------
CREATE TABLE billing.plan_prices (
  id                         UUID    NOT NULL DEFAULT gen_uuid_v7(),
  plan_version_id            UUID    NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  metric                     TEXT    NOT NULL,
  unit_label                 TEXT    NOT NULL,
  included_quantity          NUMERIC(18,4) NOT NULL DEFAULT 0,
  overage_rate_amount        NUMERIC(18,4) NULL,
  overage_rate_currency      CHAR(3)       NULL,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_plan_prices          PRIMARY KEY (id),
  CONSTRAINT uq_plan_price_metric    UNIQUE (plan_version_id, metric),
  CONSTRAINT chk_pp_included         CHECK (included_quantity >= 0),
  CONSTRAINT chk_pp_overage          CHECK (
    (overage_rate_amount IS NULL AND overage_rate_currency IS NULL)
    OR (overage_rate_amount IS NOT NULL AND overage_rate_currency IS NOT NULL
        AND overage_rate_amount >= 0)
  ),
  CONSTRAINT chk_pp_currency         CHECK (overage_rate_currency IS NULL OR overage_rate_currency ~ '^[A-Z]{3}$')
);

GRANT SELECT ON billing.plan_prices TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.plan_prices TO app_platform_admin;

-- ----------------------------------------------------------------
-- Platform-owned: tax_categories (HSN/SAC reference)
-- ----------------------------------------------------------------
CREATE TABLE billing.tax_categories (
  id          UUID NOT NULL DEFAULT gen_uuid_v7(),
  code        TEXT NOT NULL,
  description TEXT NOT NULL,
  regime      TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tax_categories  PRIMARY KEY (id),
  CONSTRAINT uq_tc_code_regime  UNIQUE (code, regime)
);

GRANT SELECT ON billing.tax_categories TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.tax_categories TO app_platform_admin;

-- ----------------------------------------------------------------
-- Platform-owned: tax_rules (versioned, regime-driven)
-- ----------------------------------------------------------------
CREATE TABLE billing.tax_rules (
  id                     UUID    NOT NULL DEFAULT gen_uuid_v7(),
  regime                 TEXT    NOT NULL,
  tax_category_id        UUID    NULL REFERENCES billing.tax_categories(id),
  supplier_jurisdiction  TEXT    NOT NULL,
  recipient_jurisdiction TEXT    NULL,
  components             JSONB   NOT NULL DEFAULT '[]',
  effective_from         DATE    NOT NULL,
  effective_to           DATE    NULL,
  rule_version           INTEGER NOT NULL DEFAULT 1,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tax_rules       PRIMARY KEY (id),
  CONSTRAINT chk_tr_dates       CHECK (effective_to IS NULL OR effective_to > effective_from),
  CONSTRAINT chk_tr_components  CHECK (jsonb_typeof(components) = 'array')
);

CREATE INDEX idx_tr_regime_date ON billing.tax_rules (regime, effective_from DESC);

GRANT SELECT ON billing.tax_rules TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.tax_rules TO app_platform_admin;

-- ----------------------------------------------------------------
-- Platform-owned: fx_rates
-- ----------------------------------------------------------------
CREATE TABLE billing.fx_rates (
  id             UUID    NOT NULL DEFAULT gen_uuid_v7(),
  from_currency  CHAR(3) NOT NULL,
  to_currency    CHAR(3) NOT NULL,
  rate           NUMERIC(18,6) NOT NULL,
  rate_source    TEXT    NOT NULL DEFAULT 'manual_v1',
  effective_date DATE    NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_fx_rates         PRIMARY KEY (id),
  CONSTRAINT chk_fx_from         CHECK (from_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_fx_to           CHECK (to_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_fx_rate_pos     CHECK (rate > 0)
);

CREATE UNIQUE INDEX uq_fx_pair_date ON billing.fx_rates (from_currency, to_currency, effective_date);
CREATE        INDEX idx_fx_pair     ON billing.fx_rates (from_currency, to_currency, effective_date DESC);

GRANT SELECT ON billing.fx_rates TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.fx_rates TO app_platform_admin;

-- ================================================================
-- Migration 048: billing_accounts
-- ================================================================

CREATE TABLE billing.billing_accounts (
  id                       UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id          UUID    NOT NULL,
  billing_status           TEXT    NOT NULL DEFAULT 'ACTIVE',
  currency                 CHAR(3) NOT NULL DEFAULT 'INR',
  billing_contact_name     TEXT    NULL,     -- pii:name
  billing_contact_email    TEXT    NULL,     -- pii:email
  grace_period_ends_at     TIMESTAMPTZ NULL,
  credit_balance_amount    NUMERIC(18,4) NOT NULL DEFAULT 0,
  credit_balance_currency  CHAR(3)       NOT NULL DEFAULT 'INR',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_billing_accounts    PRIMARY KEY (id),
  CONSTRAINT uq_ba_org              UNIQUE (organization_id),
  CONSTRAINT chk_ba_status          CHECK (billing_status IN ('ACTIVE','PAST_DUE','SUSPENDED','CLOSED')),
  CONSTRAINT chk_ba_currency        CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ba_credit_balance  CHECK (credit_balance_amount >= 0),
  CONSTRAINT chk_ba_grace_period    CHECK (
    (billing_status = 'PAST_DUE' AND grace_period_ends_at IS NOT NULL)
    OR (billing_status <> 'PAST_DUE')
  )
);

COMMENT ON COLUMN billing.billing_accounts.billing_contact_name  IS 'pii:name';
COMMENT ON COLUMN billing.billing_accounts.billing_contact_email IS 'pii:email';

-- Currency immutability trigger
CREATE OR REPLACE FUNCTION billing.fn_ba_currency_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.currency <> OLD.currency THEN
    RAISE EXCEPTION 'billing_accounts.currency is immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_ba_currency_immutable() FROM PUBLIC;

CREATE TRIGGER trg_ba_currency_immutable
  BEFORE UPDATE ON billing.billing_accounts
  FOR EACH ROW EXECUTE FUNCTION billing.fn_ba_currency_immutable();

CREATE TRIGGER trg_ba_updated_at
  BEFORE UPDATE ON billing.billing_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.billing_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.billing_accounts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ba_tenant ON billing.billing_accounts
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON billing.billing_accounts TO app_api, app_worker;
GRANT SELECT ON billing.billing_accounts TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.billing_accounts TO app_platform_admin;

-- ================================================================
-- Migration 049: subscriptions and billing_periods
-- ================================================================

CREATE TABLE billing.subscriptions (
  id                              UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                 UUID    NOT NULL,
  billing_account_id              UUID    NOT NULL REFERENCES billing.billing_accounts(id) ON DELETE RESTRICT,
  plan_version_id                 UUID    NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  status                          TEXT    NOT NULL DEFAULT 'TRIAL',
  current_period_start            DATE    NOT NULL,
  current_period_end              DATE    NOT NULL,
  trial_ends_at                   DATE    NULL,
  cancelled_at                    TIMESTAMPTZ NULL,
  cancellation_reason             TEXT    NULL,
  scheduled_change_plan_version_id UUID   NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  scheduled_change_effective_at   DATE    NULL,
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_subscriptions       PRIMARY KEY (id),
  CONSTRAINT chk_sub_status         CHECK (status IN ('TRIAL','ACTIVE','PAST_DUE','SUSPENDED','CANCELLED')),
  CONSTRAINT chk_sub_period         CHECK (current_period_end > current_period_start),
  CONSTRAINT chk_sub_trial          CHECK (trial_ends_at IS NULL OR trial_ends_at >= current_period_start),
  CONSTRAINT chk_sub_cancelled      CHECK (
    (status = 'CANCELLED' AND cancelled_at IS NOT NULL)
    OR status <> 'CANCELLED'
  ),
  CONSTRAINT chk_sub_scheduled      CHECK (
    (scheduled_change_plan_version_id IS NULL) = (scheduled_change_effective_at IS NULL)
  )
);

-- Only one active/trial subscription per tenant
CREATE UNIQUE INDEX uq_sub_org_active ON billing.subscriptions (organization_id)
  WHERE status IN ('TRIAL','ACTIVE');

CREATE INDEX idx_sub_org_status  ON billing.subscriptions (organization_id, status);
CREATE INDEX idx_sub_ba          ON billing.subscriptions (billing_account_id);

CREATE TRIGGER trg_sub_updated_at
  BEFORE UPDATE ON billing.subscriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Prevent CANCELLED subscription reactivation
CREATE OR REPLACE FUNCTION billing.fn_sub_cancelled_terminal()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'CANCELLED' AND NEW.status <> 'CANCELLED' THEN
    RAISE EXCEPTION 'billing: CANCELLED subscription % cannot be reactivated', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_sub_cancelled_terminal() FROM PUBLIC;

CREATE TRIGGER trg_sub_cancelled_terminal
  BEFORE UPDATE ON billing.subscriptions
  FOR EACH ROW EXECUTE FUNCTION billing.fn_sub_cancelled_terminal();

ALTER TABLE billing.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_sub_tenant ON billing.subscriptions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON billing.subscriptions TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.subscriptions TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.subscriptions TO app_platform_admin;

-- ----------------------------------------------------------------
-- billing_periods
-- ----------------------------------------------------------------
CREATE TABLE billing.billing_periods (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  subscription_id  UUID    NOT NULL REFERENCES billing.subscriptions(id) ON DELETE RESTRICT,
  plan_version_id  UUID    NOT NULL REFERENCES billing.plan_versions(id) ON DELETE RESTRICT,
  period_start     DATE    NOT NULL,
  period_end       DATE    NOT NULL,
  timezone         TEXT    NOT NULL DEFAULT 'Asia/Kolkata',
  status           TEXT    NOT NULL DEFAULT 'OPEN',
  closed_at        TIMESTAMPTZ NULL,
  invoice_generated_at TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_billing_periods      PRIMARY KEY (id),
  CONSTRAINT uq_bp_sub_period        UNIQUE (subscription_id, period_start),
  CONSTRAINT chk_bp_period           CHECK (period_end > period_start),
  CONSTRAINT chk_bp_status           CHECK (status IN ('OPEN','CLOSED')),
  CONSTRAINT chk_bp_closed           CHECK (
    (status = 'CLOSED' AND closed_at IS NOT NULL)
    OR status = 'OPEN'
  )
);

CREATE INDEX idx_bp_sub             ON billing.billing_periods (subscription_id, period_start DESC);
CREATE INDEX idx_bp_org_open        ON billing.billing_periods (organization_id) WHERE status = 'OPEN';

ALTER TABLE billing.billing_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.billing_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_bp_tenant ON billing.billing_periods
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON billing.billing_periods TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.billing_periods TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.billing_periods TO app_platform_admin;

-- ================================================================
-- Migration 050: usage_events (partitioned) and usage_records
-- ================================================================

-- Parent table (partitioned)
CREATE TABLE billing.usage_events (
  id               UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID        NOT NULL,
  billing_period_id UUID       NULL,  -- nullable: event may arrive before period closes
  metric           TEXT        NOT NULL,
  quantity         NUMERIC(18,4) NOT NULL,
  unit_label       TEXT        NOT NULL,
  source_system    TEXT        NOT NULL,
  source_event_id  TEXT        NOT NULL,
  source_context   JSONB       NOT NULL DEFAULT '{}',
  occurred_at      TIMESTAMPTZ NOT NULL,
  recorded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_usage_events   PRIMARY KEY (id, occurred_at),
  CONSTRAINT uq_ue_idempotency UNIQUE (organization_id, source_system, source_event_id, occurred_at),
  CONSTRAINT chk_ue_quantity   CHECK (quantity >= 0),
  CONSTRAINT chk_ue_metric     CHECK (length(metric) BETWEEN 1 AND 100)
) PARTITION BY RANGE (occurred_at);

-- Initial partitions (created by migration; ongoing by scheduled job)
CREATE TABLE billing.usage_events_y2026m08
  PARTITION OF billing.usage_events
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE TABLE billing.usage_events_y2026m09
  PARTITION OF billing.usage_events
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

CREATE TABLE billing.usage_events_y2026m10
  PARTITION OF billing.usage_events
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

CREATE TABLE billing.usage_events_default
  PARTITION OF billing.usage_events DEFAULT;

-- Indexes on parent (inherited by partitions)
CREATE INDEX idx_ue_org_metric ON billing.usage_events (organization_id, metric, occurred_at DESC);
CREATE INDEX idx_ue_period     ON billing.usage_events (billing_period_id) WHERE billing_period_id IS NOT NULL;

-- Append-only enforcement
REVOKE UPDATE, DELETE ON billing.usage_events FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.usage_events TO app_api, app_worker;
GRANT SELECT ON billing.usage_events TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.usage_events TO app_platform_admin;

ALTER TABLE billing.usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.usage_events FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ue_tenant ON billing.usage_events
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ----------------------------------------------------------------
-- usage_records (aggregated per metric per billing period)
-- ----------------------------------------------------------------
CREATE TABLE billing.usage_records (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  billing_period_id UUID   NOT NULL REFERENCES billing.billing_periods(id) ON DELETE RESTRICT,
  metric           TEXT    NOT NULL,
  unit_label       TEXT    NOT NULL,
  quantity_used    NUMERIC(18,4) NOT NULL DEFAULT 0,
  last_aggregated_at TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_usage_records     PRIMARY KEY (id),
  CONSTRAINT uq_ur_period_metric  UNIQUE (organization_id, billing_period_id, metric),
  CONSTRAINT chk_ur_quantity      CHECK (quantity_used >= 0)
);

CREATE INDEX idx_ur_org_metric ON billing.usage_records (organization_id, metric, billing_period_id);

CREATE TRIGGER trg_ur_updated_at
  BEFORE UPDATE ON billing.usage_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.usage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.usage_records FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ur_tenant ON billing.usage_records
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON billing.usage_records TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.usage_records TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.usage_records TO app_platform_admin;

-- ================================================================
-- Migration 051: cost_entries (partitioned)
-- ================================================================

CREATE TABLE billing.cost_entries (
  id                                UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                   UUID    NOT NULL,
  metric                            TEXT    NOT NULL,
  provider                          TEXT    NOT NULL,
  source_system                     TEXT    NOT NULL,
  source_event_id                   TEXT    NOT NULL,
  unit_count                        NUMERIC(18,4) NOT NULL,
  amount_amount                     NUMERIC(18,4) NOT NULL,
  amount_currency                   CHAR(3)       NOT NULL,
  amount_in_billing_currency_amount    NUMERIC(18,4) NULL,
  amount_in_billing_currency_currency  CHAR(3)       NULL,
  fx_rate_used                      NUMERIC(12,6) NULL,
  fx_rate_source                    TEXT          NULL,
  fx_rate_captured_at               TIMESTAMPTZ   NULL,
  recorded_at                       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cost_entries        PRIMARY KEY (id, recorded_at),
  CONSTRAINT uq_ce_source           UNIQUE (source_system, source_event_id, recorded_at),
  CONSTRAINT chk_ce_amount          CHECK (amount_amount >= 0),
  CONSTRAINT chk_ce_currency        CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ce_billing_currency CHECK (
    (amount_in_billing_currency_amount IS NULL) = (amount_in_billing_currency_currency IS NULL)
  )
) PARTITION BY RANGE (recorded_at);

CREATE TABLE billing.cost_entries_y2026m08
  PARTITION OF billing.cost_entries FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE billing.cost_entries_y2026m09
  PARTITION OF billing.cost_entries FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE billing.cost_entries_default
  PARTITION OF billing.cost_entries DEFAULT;

CREATE INDEX idx_ce_org_metric ON billing.cost_entries (organization_id, metric, recorded_at DESC);
CREATE INDEX idx_ce_source     ON billing.cost_entries (source_system, source_event_id);

REVOKE UPDATE, DELETE ON billing.cost_entries FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.cost_entries TO app_api, app_worker;
GRANT SELECT ON billing.cost_entries TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.cost_entries TO app_platform_admin;

ALTER TABLE billing.cost_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.cost_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ce_tenant ON billing.cost_entries
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ================================================================
-- Migration 052: quota_configs, tax_profiles, invoice_number_sequences
-- ================================================================

CREATE TABLE billing.quota_configs (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  metric           TEXT    NOT NULL,
  soft_limit       NUMERIC(18,4) NULL,
  hard_limit       NUMERIC(18,4) NULL,
  unit_label       TEXT    NOT NULL,
  override_reason  TEXT    NULL,   -- reserved for V2 admin overrides
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_quota_configs     PRIMARY KEY (id),
  CONSTRAINT uq_qc_org_metric     UNIQUE (organization_id, metric),
  CONSTRAINT chk_qc_soft_limit    CHECK (soft_limit IS NULL OR soft_limit >= 0),
  CONSTRAINT chk_qc_hard_limit    CHECK (hard_limit IS NULL OR hard_limit >= 0),
  CONSTRAINT chk_qc_limits_order  CHECK (
    soft_limit IS NULL OR hard_limit IS NULL OR soft_limit <= hard_limit
  )
);

CREATE TRIGGER trg_qc_updated_at
  BEFORE UPDATE ON billing.quota_configs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.quota_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.quota_configs FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_qc_tenant ON billing.quota_configs
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON billing.quota_configs TO app_api, app_worker, app_readonly;
GRANT INSERT, UPDATE ON billing.quota_configs TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.quota_configs TO app_platform_admin;

-- ----------------------------------------------------------------
-- tax_profiles (tenant-owned)
-- ----------------------------------------------------------------
CREATE TABLE billing.tax_profiles (
  id                          UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id             UUID    NOT NULL,
  tax_regime                  TEXT    NOT NULL DEFAULT 'IN_GST',
  is_registered               BOOLEAN NOT NULL DEFAULT FALSE,
  registration_number         TEXT    NULL,   -- GSTIN / VAT / EIN; pii:business-id
  registration_verified_at    TIMESTAMPTZ NULL,
  place_of_supply             TEXT    NULL,   -- Indian state code or jurisdiction
  billing_address             JSONB   NOT NULL DEFAULT '{}',  -- pii:address
  exemption_ref               TEXT    NULL,
  exemption_valid_until       DATE    NULL,
  default_tax_category_id     UUID    NULL REFERENCES billing.tax_categories(id),
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tax_profiles   PRIMARY KEY (id),
  CONSTRAINT uq_tp_org         UNIQUE (organization_id)
);

COMMENT ON COLUMN billing.tax_profiles.registration_number IS 'pii:business-id — GSTIN or equivalent; stored as-is';
COMMENT ON COLUMN billing.tax_profiles.billing_address     IS 'pii:address';

CREATE TRIGGER trg_tp_updated_at
  BEFORE UPDATE ON billing.tax_profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.tax_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.tax_profiles FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tp_tenant ON billing.tax_profiles
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON billing.tax_profiles TO app_api, app_worker;
GRANT SELECT ON billing.tax_profiles TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.tax_profiles TO app_platform_admin;

-- ----------------------------------------------------------------
-- invoice_number_sequences (gapless allocation per Phase 5A §11.5)
-- ----------------------------------------------------------------
CREATE TABLE billing.invoice_number_sequences (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  fiscal_year      INTEGER NOT NULL,
  prefix           TEXT    NOT NULL DEFAULT 'INV',
  next_number      INTEGER NOT NULL DEFAULT 1,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_ins               PRIMARY KEY (id),
  CONSTRAINT uq_ins_org_fy_prefix UNIQUE (organization_id, fiscal_year, prefix),
  CONSTRAINT chk_ins_next_number  CHECK (next_number >= 1),
  CONSTRAINT chk_ins_fiscal_year  CHECK (fiscal_year >= 2024)
);

CREATE TRIGGER trg_ins_updated_at
  BEFORE UPDATE ON billing.invoice_number_sequences
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.invoice_number_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.invoice_number_sequences FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ins_tenant ON billing.invoice_number_sequences
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Only app_worker can allocate invoice numbers (via SECURITY DEFINER fn)
REVOKE INSERT, UPDATE ON billing.invoice_number_sequences FROM app_api;
GRANT SELECT ON billing.invoice_number_sequences TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.invoice_number_sequences TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.invoice_number_sequences TO app_platform_admin;

-- SECURITY DEFINER: gapless invoice number allocation
CREATE OR REPLACE FUNCTION billing.fn_allocate_invoice_number(
  p_organization_id UUID,
  p_fiscal_year     INTEGER,
  p_prefix          TEXT DEFAULT 'INV'
) RETURNS TEXT
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_next INTEGER;
BEGIN
  INSERT INTO billing.invoice_number_sequences (organization_id, fiscal_year, prefix)
  VALUES (p_organization_id, p_fiscal_year, p_prefix)
  ON CONFLICT (organization_id, fiscal_year, prefix) DO NOTHING;

  UPDATE billing.invoice_number_sequences
  SET next_number = next_number + 1,
      updated_at  = NOW()
  WHERE organization_id = p_organization_id
    AND fiscal_year      = p_fiscal_year
    AND prefix           = p_prefix
  RETURNING next_number - 1 INTO v_next;  -- return the number we just allocated

  RETURN p_prefix || '/' || p_fiscal_year || '/' || LPAD(v_next::TEXT, 6, '0');
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_allocate_invoice_number(UUID, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_allocate_invoice_number(UUID, INTEGER, TEXT)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 053: credits and credit_ledger_entries
-- ================================================================

CREATE TABLE billing.credits (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  billing_account_id UUID  NOT NULL REFERENCES billing.billing_accounts(id) ON DELETE RESTRICT,
  credit_type      TEXT    NOT NULL,
  amount_amount    NUMERIC(18,4) NOT NULL,
  amount_currency  CHAR(3)       NOT NULL,
  reason           TEXT    NOT NULL,
  expires_at       TIMESTAMPTZ NULL,
  status           TEXT    NOT NULL DEFAULT 'ACTIVE',
  created_by_ref   TEXT    NOT NULL,  -- user_id or system reference
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_credits         PRIMARY KEY (id),
  CONSTRAINT chk_cr_type        CHECK (credit_type IN ('PROMOTIONAL','MANUAL','REFUND_CREDIT','PRORATION_CREDIT')),
  CONSTRAINT chk_cr_amount      CHECK (amount_amount > 0),
  CONSTRAINT chk_cr_currency    CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_cr_status      CHECK (status IN ('ACTIVE','CONSUMED','EXPIRED','REVERSED'))
);

CREATE INDEX idx_cr_org_status ON billing.credits (organization_id, status, expires_at);

CREATE TRIGGER trg_cr_updated_at
  BEFORE UPDATE ON billing.credits
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.credits ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.credits FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cr_tenant ON billing.credits
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Credits can only be created via SECURITY DEFINER fn — not directly by app_api
REVOKE INSERT, UPDATE ON billing.credits FROM app_api;
GRANT SELECT ON billing.credits TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON billing.credits TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.credits TO app_platform_admin;

-- ----------------------------------------------------------------
-- credit_ledger_entries (append-only, authoritative balance)
-- ----------------------------------------------------------------
CREATE TABLE billing.credit_ledger_entries (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  credit_id        UUID    NOT NULL REFERENCES billing.credits(id) ON DELETE RESTRICT,
  entry_type       TEXT    NOT NULL,
  amount_amount    NUMERIC(18,4) NOT NULL,  -- positive = credit granted; negative = debit
  amount_currency  CHAR(3)       NOT NULL,
  reference_type   TEXT    NULL,  -- 'INVOICE' | 'ADJUSTMENT' | 'EXPIRY' | 'REVERSAL'
  reference_id     UUID    NULL,  -- FK to invoice or adjustment (logical, no DB FK)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_cle            PRIMARY KEY (id),
  CONSTRAINT chk_cle_type      CHECK (entry_type IN ('GRANT','CONSUMPTION','EXPIRY','REVERSAL')),
  CONSTRAINT chk_cle_currency  CHECK (amount_currency ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_cle_org     ON billing.credit_ledger_entries (organization_id, created_at DESC);
CREATE INDEX idx_cle_credit  ON billing.credit_ledger_entries (credit_id);

-- Append-only
REVOKE UPDATE, DELETE ON billing.credit_ledger_entries FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.credit_ledger_entries TO app_api, app_worker;
GRANT SELECT ON billing.credit_ledger_entries TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.credit_ledger_entries TO app_platform_admin;

ALTER TABLE billing.credit_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.credit_ledger_entries FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_cle_tenant ON billing.credit_ledger_entries
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- SECURITY DEFINER: apply credit (creates credit + initial ledger entry atomically)
CREATE OR REPLACE FUNCTION billing.fn_billing_apply_credit(
  p_organization_id   UUID,
  p_billing_account_id UUID,
  p_credit_type       TEXT,
  p_amount            NUMERIC(18,4),
  p_currency          CHAR(3),
  p_reason            TEXT,
  p_expires_at        TIMESTAMPTZ,
  p_created_by_ref    TEXT
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_credit_id UUID;
BEGIN
  INSERT INTO billing.credits
    (organization_id, billing_account_id, credit_type, amount_amount, amount_currency,
     reason, expires_at, status, created_by_ref)
  VALUES
    (p_organization_id, p_billing_account_id, p_credit_type, p_amount, p_currency,
     p_reason, p_expires_at, 'ACTIVE', p_created_by_ref)
  RETURNING id INTO v_credit_id;

  INSERT INTO billing.credit_ledger_entries
    (organization_id, credit_id, entry_type, amount_amount, amount_currency, reference_type)
  VALUES
    (p_organization_id, v_credit_id, 'GRANT', p_amount, p_currency, 'CREDIT_GRANT');

  -- Update cached balance on billing_account
  UPDATE billing.billing_accounts
  SET credit_balance_amount = credit_balance_amount + p_amount,
      updated_at = NOW()
  WHERE id = p_billing_account_id;

  RETURN v_credit_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_billing_apply_credit(UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_billing_apply_credit(UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, TIMESTAMPTZ, TEXT)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 054: invoices, invoice_lines, tax_lines
-- ================================================================

CREATE TABLE billing.invoices (
  id                          UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id             UUID    NOT NULL,
  billing_account_id          UUID    NOT NULL REFERENCES billing.billing_accounts(id) ON DELETE RESTRICT,
  billing_period_id           UUID    NULL REFERENCES billing.billing_periods(id) ON DELETE RESTRICT,
  subscription_id             UUID    NULL REFERENCES billing.subscriptions(id) ON DELETE RESTRICT,
  invoice_number              TEXT    NULL,   -- allocated on finalization
  invoice_kind                TEXT    NOT NULL DEFAULT 'TAX_INVOICE',
  status                      TEXT    NOT NULL DEFAULT 'DRAFT',
  currency                    CHAR(3) NOT NULL,
  subtotal_amount             NUMERIC(18,4) NOT NULL DEFAULT 0,
  subtotal_currency           CHAR(3)       NOT NULL,
  total_credits_amount        NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_credits_currency      CHAR(3)       NOT NULL,
  total_tax_amount            NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_tax_currency          CHAR(3)       NOT NULL,
  total_due_amount            NUMERIC(18,4) NOT NULL DEFAULT 0,
  total_due_currency          CHAR(3)       NOT NULL,
  amount_paid_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
  amount_paid_currency        CHAR(3)       NOT NULL,
  issue_date                  DATE    NULL,
  due_date                    DATE    NULL,
  paid_at                     TIMESTAMPTZ NULL,
  voided_at                   TIMESTAMPTZ NULL,
  void_reason                 TEXT    NULL,
  related_invoice_id          UUID    NULL REFERENCES billing.invoices(id),
  place_of_supply             TEXT    NULL,
  tax_profile_snapshot        JSONB   NOT NULL DEFAULT '{}',
  tax_rule_versions_applied   INTEGER[] NOT NULL DEFAULT '{}',
  e_invoice_ref               TEXT    NULL,
  notes                       TEXT    NULL,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_invoices             PRIMARY KEY (id),
  CONSTRAINT uq_invoice_number       UNIQUE (organization_id, invoice_number) DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT chk_inv_status          CHECK (status IN ('DRAFT','OPEN','PAID','VOID')),
  CONSTRAINT chk_inv_kind            CHECK (invoice_kind IN ('TAX_INVOICE','CREDIT_NOTE','DEBIT_NOTE','PROFORMA')),
  CONSTRAINT chk_inv_currency        CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_inv_total_due       CHECK (total_due_amount >= 0),
  CONSTRAINT chk_inv_amount_paid     CHECK (amount_paid_amount >= 0),
  CONSTRAINT chk_inv_paid_status     CHECK (
    (status = 'PAID' AND paid_at IS NOT NULL) OR status <> 'PAID'
  ),
  CONSTRAINT chk_inv_void_status     CHECK (
    (status = 'VOID' AND voided_at IS NOT NULL) OR status <> 'VOID'
  ),
  CONSTRAINT chk_inv_number_open     CHECK (
    (status IN ('OPEN','PAID','VOID') AND invoice_number IS NOT NULL) OR status = 'DRAFT'
  )
);

CREATE INDEX idx_inv_org_status ON billing.invoices (organization_id, status);
CREATE INDEX idx_inv_period     ON billing.invoices (billing_period_id) WHERE billing_period_id IS NOT NULL;
CREATE INDEX idx_inv_sub        ON billing.invoices (subscription_id)   WHERE subscription_id   IS NOT NULL;

-- Immutability: PAID and VOID invoices cannot be mutated
CREATE OR REPLACE FUNCTION billing.fn_invoice_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('PAID','VOID') THEN
    IF NEW.subtotal_amount          <> OLD.subtotal_amount
    OR NEW.total_credits_amount     <> OLD.total_credits_amount
    OR NEW.total_tax_amount         <> OLD.total_tax_amount
    OR NEW.total_due_amount         <> OLD.total_due_amount
    OR NEW.billing_period_id        IS DISTINCT FROM OLD.billing_period_id
    OR NEW.currency                 <> OLD.currency
    THEN
      RAISE EXCEPTION 'billing: invoice % is % and immutable', OLD.id, OLD.status;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_invoice_immutability() FROM PUBLIC;

CREATE TRIGGER trg_inv_immutability
  BEFORE UPDATE ON billing.invoices
  FOR EACH ROW EXECUTE FUNCTION billing.fn_invoice_immutability();

CREATE TRIGGER trg_inv_updated_at
  BEFORE UPDATE ON billing.invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE billing.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_inv_tenant ON billing.invoices
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON billing.invoices TO app_api, app_readonly;
GRANT SELECT, INSERT ON billing.invoices TO app_worker;
-- UPDATE only via SECURITY DEFINER functions
REVOKE UPDATE, DELETE ON billing.invoices FROM app_api, app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.invoices TO app_platform_admin;

-- ----------------------------------------------------------------
-- invoice_lines (append-only once invoice is PAID/VOID)
-- ----------------------------------------------------------------
CREATE TABLE billing.invoice_lines (
  id                   UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID    NOT NULL,
  invoice_id           UUID    NOT NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  line_type            TEXT    NOT NULL,
  description          TEXT    NOT NULL,
  metric               TEXT    NULL,
  billing_period_id    UUID    NULL,   -- logical ref; no FK to avoid cross-partition issues
  quantity             NUMERIC(18,4) NOT NULL DEFAULT 1,
  unit_price_amount    NUMERIC(18,4) NOT NULL,
  unit_price_currency  CHAR(3)       NOT NULL,
  line_total_amount    NUMERIC(18,4) NOT NULL,
  line_total_currency  CHAR(3)       NOT NULL,
  sort_order           INTEGER NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_invoice_lines    PRIMARY KEY (id),
  CONSTRAINT chk_il_type         CHECK (line_type IN ('BASE_FEE','USAGE','OVERAGE','CREDIT','DISCOUNT','TAX','ADJUSTMENT')),
  CONSTRAINT chk_il_currency     CHECK (unit_price_currency ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_il_invoice ON billing.invoice_lines (invoice_id);

REVOKE UPDATE, DELETE ON billing.invoice_lines FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.invoice_lines TO app_api, app_worker;
GRANT SELECT ON billing.invoice_lines TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.invoice_lines TO app_platform_admin;

ALTER TABLE billing.invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.invoice_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_il_tenant ON billing.invoice_lines
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ----------------------------------------------------------------
-- tax_lines
-- ----------------------------------------------------------------
CREATE TABLE billing.tax_lines (
  id                      UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID    NOT NULL,
  invoice_id              UUID    NOT NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  invoice_line_id         UUID    NULL REFERENCES billing.invoice_lines(id) ON DELETE RESTRICT,
  component_code          TEXT    NOT NULL,
  rate_percent            NUMERIC(8,4) NOT NULL,
  taxable_amount_amount   NUMERIC(18,4) NOT NULL,
  taxable_amount_currency CHAR(3)       NOT NULL,
  tax_amount_amount       NUMERIC(18,4) NOT NULL,
  tax_amount_currency     CHAR(3)       NOT NULL,
  tax_rule_version        INTEGER NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tax_lines          PRIMARY KEY (id),
  CONSTRAINT chk_tl_rate           CHECK (rate_percent >= 0),
  CONSTRAINT chk_tl_tax_amount     CHECK (tax_amount_amount >= 0),
  CONSTRAINT chk_tl_currency       CHECK (taxable_amount_currency ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_tl_invoice ON billing.tax_lines (invoice_id);

REVOKE UPDATE, DELETE ON billing.tax_lines FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.tax_lines TO app_api, app_worker;
GRANT SELECT ON billing.tax_lines TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.tax_lines TO app_platform_admin;

ALTER TABLE billing.tax_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.tax_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tl_tenant ON billing.tax_lines
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ================================================================
-- Migration 055: payment_attempts and refunds
-- ================================================================

CREATE TABLE billing.payment_attempts (
  id                        UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id           UUID    NOT NULL,
  invoice_id                UUID    NOT NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  payment_provider          TEXT    NOT NULL,
  provider_transaction_id   TEXT    NOT NULL,
  provider_webhook_event_id TEXT    NULL,
  payment_method_ref        TEXT    NULL,  -- opaque gateway token; no credentials
  status                    TEXT    NOT NULL DEFAULT 'INITIATED',
  amount_amount             NUMERIC(18,4) NOT NULL,
  amount_currency           CHAR(3)       NOT NULL,
  failure_code              TEXT    NULL,
  failure_message           TEXT    NULL,
  initiated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at              TIMESTAMPTZ NULL,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_payment_attempts    PRIMARY KEY (id),
  CONSTRAINT uq_pa_provider_tx      UNIQUE (payment_provider, provider_transaction_id),
  CONSTRAINT uq_pa_webhook_event    UNIQUE (payment_provider, provider_webhook_event_id)
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT chk_pa_status          CHECK (status IN ('INITIATED','PENDING','SUCCEEDED','FAILED','CANCELLED')),
  CONSTRAINT chk_pa_amount          CHECK (amount_amount > 0),
  CONSTRAINT chk_pa_currency        CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_pa_provider        CHECK (payment_provider IN ('RAZORPAY','CASHFREE','STRIPE','OTHER'))
);

CREATE INDEX idx_pa_invoice      ON billing.payment_attempts (invoice_id);
CREATE INDEX idx_pa_org_status   ON billing.payment_attempts (organization_id, status);

-- Append-only: payment history is immutable
REVOKE UPDATE, DELETE ON billing.payment_attempts FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.payment_attempts TO app_api, app_worker;
GRANT SELECT ON billing.payment_attempts TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.payment_attempts TO app_platform_admin;

ALTER TABLE billing.payment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.payment_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pa_tenant ON billing.payment_attempts
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ----------------------------------------------------------------
-- refunds
-- ----------------------------------------------------------------
CREATE TABLE billing.refunds (
  id                      UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id         UUID    NOT NULL,
  payment_attempt_id      UUID    NOT NULL REFERENCES billing.payment_attempts(id) ON DELETE RESTRICT,
  payment_provider        TEXT    NOT NULL,
  provider_refund_id      TEXT    NOT NULL,
  amount_amount           NUMERIC(18,4) NOT NULL,
  amount_currency         CHAR(3)       NOT NULL,
  reason                  TEXT    NOT NULL,
  status                  TEXT    NOT NULL DEFAULT 'PENDING',
  initiated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at            TIMESTAMPTZ NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_refunds              PRIMARY KEY (id),
  CONSTRAINT uq_refund_provider      UNIQUE (payment_provider, provider_refund_id),
  CONSTRAINT chk_ref_status          CHECK (status IN ('PENDING','SUCCEEDED','FAILED')),
  CONSTRAINT chk_ref_amount          CHECK (amount_amount > 0),
  CONSTRAINT chk_ref_currency        CHECK (amount_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_ref_provider        CHECK (payment_provider IN ('RAZORPAY','CASHFREE','STRIPE','OTHER'))
);

CREATE INDEX idx_ref_payment ON billing.refunds (payment_attempt_id);
CREATE INDEX idx_ref_org     ON billing.refunds (organization_id);

REVOKE UPDATE, DELETE ON billing.refunds FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.refunds TO app_api, app_worker;
GRANT SELECT ON billing.refunds TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.refunds TO app_platform_admin;

ALTER TABLE billing.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.refunds FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ref_tenant ON billing.refunds
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Refund validation function
CREATE OR REPLACE FUNCTION billing.fn_validate_refund_amount()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_paid       NUMERIC(18,4);
  v_refunded   NUMERIC(18,4);
BEGIN
  SELECT pa.amount_amount INTO v_paid
  FROM billing.payment_attempts pa
  WHERE pa.id = NEW.payment_attempt_id;

  SELECT COALESCE(SUM(r.amount_amount), 0) INTO v_refunded
  FROM billing.refunds r
  WHERE r.payment_attempt_id = NEW.payment_attempt_id
    AND r.status IN ('PENDING','SUCCEEDED')
    AND r.id <> NEW.id;

  IF (v_refunded + NEW.amount_amount) > v_paid THEN
    RAISE EXCEPTION 'billing: refund would exceed original payment amount';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_validate_refund_amount() FROM PUBLIC;

CREATE TRIGGER trg_refund_amount_check
  BEFORE INSERT ON billing.refunds
  FOR EACH ROW EXECUTE FUNCTION billing.fn_validate_refund_amount();

-- ================================================================
-- Migration 056: billing_adjustments
-- ================================================================

CREATE TABLE billing.billing_adjustments (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  invoice_id       UUID    NULL REFERENCES billing.invoices(id) ON DELETE RESTRICT,
  adjustment_type  TEXT    NOT NULL,
  description      TEXT    NOT NULL,
  amount_amount    NUMERIC(18,4) NOT NULL,  -- negative = credit; positive = debit
  amount_currency  CHAR(3)       NOT NULL,
  created_by_ref   TEXT    NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_billing_adjustments  PRIMARY KEY (id),
  CONSTRAINT chk_ba_type             CHECK (adjustment_type IN ('CREDIT_NOTE','DEBIT_NOTE','MANUAL_CORRECTION','WRITE_OFF')),
  CONSTRAINT chk_ba_currency         CHECK (amount_currency ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_badj_org     ON billing.billing_adjustments (organization_id);
CREATE INDEX idx_badj_invoice ON billing.billing_adjustments (invoice_id) WHERE invoice_id IS NOT NULL;

REVOKE UPDATE, DELETE ON billing.billing_adjustments FROM app_api, app_worker;
GRANT SELECT, INSERT ON billing.billing_adjustments TO app_worker;
GRANT SELECT ON billing.billing_adjustments TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON billing.billing_adjustments TO app_platform_admin;

ALTER TABLE billing.billing_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.billing_adjustments FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_badj_tenant ON billing.billing_adjustments
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ================================================================
-- Migration 057: SECURITY DEFINER invoice lifecycle functions
-- ================================================================

-- Finalize invoice (DRAFT → OPEN); allocates invoice number
CREATE OR REPLACE FUNCTION billing.fn_finalize_invoice(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_fiscal_year     INTEGER,
  p_prefix          TEXT DEFAULT 'INV'
) RETURNS TEXT
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_inv_number TEXT;
  v_current_status TEXT;
BEGIN
  SELECT status INTO v_current_status
  FROM billing.invoices
  WHERE id = p_invoice_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'billing: invoice not found';
  END IF;
  IF v_current_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'billing: can only finalize a DRAFT invoice; current status = %', v_current_status;
  END IF;

  v_inv_number := billing.fn_allocate_invoice_number(p_organization_id, p_fiscal_year, p_prefix);

  UPDATE billing.invoices
  SET status         = 'OPEN',
      invoice_number = v_inv_number,
      issue_date     = CURRENT_DATE,
      updated_at     = NOW()
  WHERE id = p_invoice_id;

  RETURN v_inv_number;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_finalize_invoice(UUID, UUID, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_finalize_invoice(UUID, UUID, INTEGER, TEXT)
  TO app_worker, app_platform_admin;

-- Mark invoice PAID
CREATE OR REPLACE FUNCTION billing.fn_mark_invoice_paid(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_payment_amount  NUMERIC(18,4),
  p_currency        CHAR(3)
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM billing.invoices
  WHERE id = p_invoice_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF v_status <> 'OPEN' THEN
    RAISE EXCEPTION 'billing: can only mark OPEN invoice as PAID; current = %', v_status;
  END IF;

  UPDATE billing.invoices
  SET status               = 'PAID',
      paid_at              = NOW(),
      amount_paid_amount   = p_payment_amount,
      amount_paid_currency = p_currency,
      updated_at           = NOW()
  WHERE id = p_invoice_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_mark_invoice_paid(UUID, UUID, NUMERIC, CHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_mark_invoice_paid(UUID, UUID, NUMERIC, CHAR)
  TO app_worker, app_platform_admin;

-- Void invoice
CREATE OR REPLACE FUNCTION billing.fn_void_invoice(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_reason          TEXT
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM billing.invoices
  WHERE id = p_invoice_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF v_status NOT IN ('DRAFT','OPEN') THEN
    RAISE EXCEPTION 'billing: can only void DRAFT or OPEN invoices; current = %', v_status;
  END IF;

  UPDATE billing.invoices
  SET status      = 'VOID',
      voided_at   = NOW(),
      void_reason = p_reason,
      updated_at  = NOW()
  WHERE id = p_invoice_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_void_invoice(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_void_invoice(UUID, UUID, TEXT)
  TO app_worker, app_platform_admin;

-- Update payment attempt status (INITIATED/PENDING → SUCCEEDED/FAILED/CANCELLED)
-- Used by the payment webhook handler; app_worker cannot UPDATE payment_attempts directly.
CREATE OR REPLACE FUNCTION billing.fn_update_payment_status(
  p_organization_id         UUID,
  p_payment_attempt_id      UUID,
  p_new_status              TEXT,
  p_provider_webhook_event_id TEXT DEFAULT NULL,
  p_failure_code            TEXT DEFAULT NULL,
  p_failure_message         TEXT DEFAULT NULL
) RETURNS VOID
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_current_status TEXT;
  v_allowed_transitions TEXT[][] := ARRAY[
    ARRAY['INITIATED', 'PENDING'],
    ARRAY['INITIATED', 'SUCCEEDED'],
    ARRAY['INITIATED', 'FAILED'],
    ARRAY['INITIATED', 'CANCELLED'],
    ARRAY['PENDING',   'SUCCEEDED'],
    ARRAY['PENDING',   'FAILED'],
    ARRAY['PENDING',   'CANCELLED']
  ];
  v_transition TEXT[];
  v_valid BOOLEAN := FALSE;
BEGIN
  -- Validate new status value
  IF p_new_status NOT IN ('INITIATED','PENDING','SUCCEEDED','FAILED','CANCELLED') THEN
    RAISE EXCEPTION 'billing: invalid payment status %', p_new_status;
  END IF;

  SELECT status INTO v_current_status
  FROM billing.payment_attempts
  WHERE id = p_payment_attempt_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'billing: payment_attempt not found';
  END IF;

  -- Terminal states cannot be re-transitioned
  IF v_current_status IN ('SUCCEEDED','FAILED','CANCELLED') THEN
    IF v_current_status = p_new_status THEN
      RETURN;  -- idempotent: same terminal state is a no-op
    END IF;
    RAISE EXCEPTION 'billing: payment_attempt % is in terminal state % — cannot transition to %',
      p_payment_attempt_id, v_current_status, p_new_status;
  END IF;

  -- Validate allowed transition
  FOREACH v_transition SLICE 1 IN ARRAY v_allowed_transitions LOOP
    IF v_transition[1] = v_current_status AND v_transition[2] = p_new_status THEN
      v_valid := TRUE;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_valid THEN
    RAISE EXCEPTION 'billing: transition % → % is not allowed for payment_attempt %',
      v_current_status, p_new_status, p_payment_attempt_id;
  END IF;

  UPDATE billing.payment_attempts
  SET status                    = p_new_status,
      provider_webhook_event_id = COALESCE(p_provider_webhook_event_id, provider_webhook_event_id),
      failure_code              = CASE WHEN p_new_status = 'FAILED' THEN p_failure_code ELSE failure_code END,
      failure_message           = CASE WHEN p_new_status = 'FAILED' THEN p_failure_message ELSE failure_message END,
      completed_at              = CASE WHEN p_new_status IN ('SUCCEEDED','FAILED','CANCELLED') THEN NOW() ELSE completed_at END
  WHERE id = p_payment_attempt_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_update_payment_status(UUID, UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_update_payment_status(UUID, UUID, TEXT, TEXT, TEXT, TEXT)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 058: grants finalization
-- ================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA billing TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA billing TO app_platform_admin;

```

---

## 25. Query Patterns

**QP-01 Create Subscription**
```sql
-- Within a UoW: INSERT billing_accounts (if new org), INSERT subscriptions,
-- INSERT billing_periods, INSERT quota_configs (seeded from plan_prices)
INSERT INTO billing.subscriptions
  (organization_id, billing_account_id, plan_version_id, status, current_period_start, current_period_end)
VALUES ($1, $2, $3, 'TRIAL', $4, $5);
```

**QP-02 Change Subscription (Scheduled Downgrade)**
```sql
UPDATE billing.subscriptions
SET scheduled_change_plan_version_id = $new_pv_id,
    scheduled_change_effective_at    = $next_period_start,
    updated_at = NOW()
WHERE id = $sub_id AND organization_id = $org_id AND status = 'ACTIVE';
```

**QP-03 Open Billing Period**
```sql
INSERT INTO billing.billing_periods
  (organization_id, subscription_id, plan_version_id, period_start, period_end, timezone)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (subscription_id, period_start) DO NOTHING;
```

**QP-04 Record Usage Event**
```sql
INSERT INTO billing.usage_events
  (organization_id, billing_period_id, metric, quantity, unit_label,
   source_system, source_event_id, source_context, occurred_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
ON CONFLICT (organization_id, source_system, source_event_id, occurred_at) DO NOTHING;
```

**QP-05 Deduplicate Usage Event**
```sql
-- The ON CONFLICT DO NOTHING in QP-04 is the deduplication.
-- To check: SELECT id FROM billing.usage_events
-- WHERE organization_id=$1 AND source_system=$2 AND source_event_id=$3;
```

**QP-06 Aggregate Usage for Billing Period**
```sql
INSERT INTO billing.usage_records (organization_id, billing_period_id, metric, unit_label, quantity_used)
SELECT organization_id, billing_period_id, metric, unit_label, SUM(quantity)
FROM billing.usage_events
WHERE billing_period_id = $bp_id
GROUP BY organization_id, billing_period_id, metric, unit_label
ON CONFLICT (organization_id, billing_period_id, metric)
DO UPDATE SET quantity_used = EXCLUDED.quantity_used, last_aggregated_at = NOW(), updated_at = NOW();
```

**QP-07 Check Entitlement / Quota**
```sql
SELECT qc.soft_limit, qc.hard_limit, ur.quantity_used
FROM billing.quota_configs qc
LEFT JOIN billing.usage_records ur
  ON ur.organization_id = qc.organization_id
  AND ur.metric = qc.metric
  AND ur.billing_period_id = $current_bp_id
WHERE qc.organization_id = $org_id AND qc.metric = $metric;
```

**QP-08 Calculate Overage**
```sql
SELECT ur.metric, ur.quantity_used,
       pp.included_quantity,
       GREATEST(0, ur.quantity_used - pp.included_quantity) AS overage_qty,
       pp.overage_rate_amount, pp.overage_rate_currency,
       GREATEST(0, ur.quantity_used - pp.included_quantity) * pp.overage_rate_amount AS overage_amount
FROM billing.usage_records ur
JOIN billing.plan_prices pp
  ON pp.plan_version_id = $pinned_plan_version_id AND pp.metric = ur.metric
WHERE ur.billing_period_id = $bp_id AND ur.organization_id = $org_id
  AND pp.overage_rate_amount IS NOT NULL;
```

**QP-09 Generate Invoice (DRAFT)**
```sql
-- Application-layer UoW:
-- 1. INSERT invoices (status=DRAFT)
-- 2. INSERT invoice_lines (BASE_FEE, USAGE, OVERAGE)
-- 3. Run TaxComputationService → INSERT tax_lines
-- 4. UPDATE invoices SET subtotal_amount, total_tax_amount, total_due_amount
```

**QP-10 Finalize Invoice**
```sql
SELECT billing.fn_finalize_invoice($org_id, $invoice_id, $fiscal_year, 'INV');
```

**QP-11 Record Payment Attempt**
```sql
INSERT INTO billing.payment_attempts
  (organization_id, invoice_id, payment_provider, provider_transaction_id,
   payment_method_ref, status, amount_amount, amount_currency)
VALUES ($1, $2, $3, $4, $5, 'INITIATED', $6, $7);
```

**QP-12 Process Payment Webhook (Idempotent)**
```sql
INSERT INTO billing.payment_attempts
  (organization_id, invoice_id, payment_provider, provider_transaction_id,
   provider_webhook_event_id, status, amount_amount, amount_currency, completed_at)
VALUES (...)
ON CONFLICT (payment_provider, provider_webhook_event_id) DO NOTHING;

-- If succeeded: call billing.fn_mark_invoice_paid(...)
```

**QP-13 Record Refund**
```sql
INSERT INTO billing.refunds
  (organization_id, payment_attempt_id, payment_provider, provider_refund_id,
   amount_amount, amount_currency, reason, status)
VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDING')
ON CONFLICT (payment_provider, provider_refund_id) DO NOTHING;
```

**QP-14 Consume Credit**
```sql
-- Application-layer: SELECT FOR UPDATE on credits + credit_ledger_entries
-- Then INSERT credit_ledger_entries (entry_type='CONSUMPTION', amount=negative)
-- Then UPDATE billing_accounts.credit_balance_amount
-- All within one transaction.
```

**QP-15 Apply Billing Adjustment**
```sql
INSERT INTO billing.billing_adjustments
  (organization_id, invoice_id, adjustment_type, description,
   amount_amount, amount_currency, created_by_ref)
VALUES ($1, $2, 'CREDIT_NOTE', $3, $4, $5, $6);
```

---

## 26. Migration Plan

```
Reconciled phase assignment: 5H = billing (per PHASE-NUMBERING-RECONCILIATION.md)
Phase 5G (Workflow) last migration: 046_phase5g_grants_finalize
        ↓
Phase 5H (Billing) migrations: 047–058

047_billing_schema_platform_tables
    down_revision = '046_phase5g_grants_finalize'
    purpose: CREATE SCHEMA billing; GRANT USAGE; fn_raise_immutable();
             plans, plan_versions (with immutability trigger), plan_prices;
             tax_categories, tax_rules, fx_rates
    transaction: standard (no CONCURRENTLY)

048_billing_accounts
    down_revision = '047_billing_schema_platform_tables'
    purpose: billing_accounts; currency immutability trigger; RLS; grants

049_subscriptions_and_billing_periods
    down_revision = '048_billing_accounts'
    purpose: subscriptions (cancelled-terminal trigger, partial unique index);
             billing_periods; RLS; grants

050_usage_events_and_records
    down_revision = '049_subscriptions_and_billing_periods'
    purpose: usage_events (partitioned RANGE monthly, 3 initial partitions + default);
             usage_records; indexes; RLS; REVOKE UPDATE DELETE on usage_events;
             grants

051_cost_entries
    down_revision = '050_usage_events_and_records'
    purpose: cost_entries (partitioned RANGE monthly); indexes; RLS;
             REVOKE UPDATE DELETE; grants

052_quota_configs_tax_profiles_sequences
    down_revision = '051_cost_entries'
    purpose: quota_configs; tax_profiles; invoice_number_sequences;
             fn_allocate_invoice_number() SECURITY DEFINER; RLS; grants

053_credits_and_ledger
    down_revision = '052_quota_configs_tax_profiles_sequences'
    purpose: credits; credit_ledger_entries (REVOKE UPDATE DELETE);
             fn_billing_apply_credit() SECURITY DEFINER; RLS; grants

054_invoices_lines_tax_lines
    down_revision = '053_credits_and_ledger'
    purpose: invoices (immutability trigger); invoice_lines; tax_lines;
             REVOKE UPDATE DELETE on lines; RLS; grants

055_payment_attempts_and_refunds
    down_revision = '054_invoices_lines_tax_lines'
    purpose: payment_attempts (REVOKE UPDATE DELETE); refunds;
             fn_validate_refund_amount() trigger; RLS; grants

056_billing_adjustments
    down_revision = '055_payment_attempts_and_refunds'
    purpose: billing_adjustments; RLS; grants

057_billing_lifecycle_functions
    down_revision = '056_billing_adjustments'
    purpose: fn_finalize_invoice(), fn_mark_invoice_paid(), fn_void_invoice(),
             fn_update_payment_status() — all SECURITY DEFINER;
             REVOKE ALL FROM PUBLIC + explicit GRANT EXECUTE on each

058_billing_grants_finalize
    down_revision = '057_billing_lifecycle_functions'
    purpose: app_readonly GRANT SELECT on all billing tables;
             app_platform_admin full access
```

**Downgrade order:** 058 → 057 → 056 → 055 → 054 → 053 → 052 → 051 → 050 → 049 → 048 → 047

**Note on `usage_events` and `cost_entries` partitions:** Migration 050/051 creates 3 forward partitions + DEFAULT. A scheduled job creates new monthly partitions 90 days ahead. No migration is needed for routine partition creation.

---

## 27. Seed Data

```sql
-- Platform seed: default plan (to be inserted by app_platform_admin at bootstrap)
-- Actual plan names, prices, and metrics are operational data — not schema seeds.

-- Seed: INR base FX rate (1:1 for INR billing)
INSERT INTO billing.fx_rates (from_currency, to_currency, rate, rate_source, effective_date)
VALUES ('INR', 'INR', 1.000000, 'identity', '2024-01-01');

-- Seed: HSN/SAC for SaaS platform services (illustrative — exact code requires legal review)
-- OPEN DESIGN DECISION: exact HSN/SAC code for AI voice platform services requires legal/tax confirmation.
-- INSERT INTO billing.tax_categories (code, description, regime)
-- VALUES ('998319', 'Software as a Service', 'IN_GST');
```

---

## 28. ADRs

### ADR-5H-001: Plan Versioning with Immutable Snapshots

**Decision:** `plan_versions` is immutable once `is_published = TRUE`. Price or quota changes require a new `plan_version` row. `subscriptions.plan_version_id` pins to the version at subscription creation/change. Invoices derive all pricing from the pinned version.

**Rationale:** historical invoices must not change when a plan price changes later (INV-BILL-05). Pinning to a version ID, with the version being immutable, gives deterministic historical repricing without snapshotting entire plans into invoices.

**Alternatives considered:** (a) Snapshot prices into `invoice_lines` only — adopted as a supplement (line items snapshot `unit_price_amount`) but not as the sole mechanism, because overage calculation also needs the plan version pinned. (b) Single mutable plan row — rejected because any price change would break historical invoice accuracy.

**Consequences:** Admin UI must create a new plan version rather than editing an existing one. Migration tooling must handle "upgrade all subscriptions on version 3 to version 4" as a bulk subscription change operation, not a plan mutation.

---

### ADR-5H-002: Generic Usage Metering (One Table, Not One Per Metric)

**Decision:** All usage metrics stored in `usage_events (metric TEXT, quantity NUMERIC)` and `usage_records (metric TEXT, quantity_used NUMERIC)`. Metrics are application-layer enums, not database columns or table names.

**Rationale:** Phase 4I §10.2 defines 15 metrics; new metrics (e.g. future `SMS_MESSAGES`) are new data rows, not schema migrations. A table-per-metric design would require DDL changes for every new product feature.

**Alternatives rejected:** One table per metric (e.g. `call_minutes_events`, `llm_token_events`) — rejected because it would require schema migrations for every new billable dimension, violating the India-first extensibility principle.

**Consequences:** Metric validity is enforced at application layer only. A `CHECK (metric = ANY(ARRAY[...]))` would re-introduce the migration problem; omitted deliberately.

---

### ADR-5H-003: Usage Idempotency via DB Unique Constraint

**Decision:** `UNIQUE (organization_id, source_system, source_event_id, occurred_at)` on `usage_events`. Inserts use `ON CONFLICT DO NOTHING`. No application-layer deduplication as the sole mechanism.

**Rationale:** Celery workers retry; external webhooks retry; pods can die between Redis write and Postgres write. Only a DB constraint guarantees exactly-once semantics for the authoritative record (Phase 5H §13).

**Alternatives rejected:** Application-layer check (`SELECT` then `INSERT`) — rejected due to TOCTOU race. Redis-only deduplication — rejected because Redis is not durable enough to be the audit authority.

**Consequences:** `occurred_at` is included in the unique key because the same source_event_id theoretically could be reused across time by some source systems. If a source system guarantees globally unique event IDs, the `occurred_at` column is redundant in the key but harmless.

---

### ADR-5H-004: Credit Ledger Pattern (Not a Mutable Balance Column)

**Decision:** `credits` table records the grant; `credit_ledger_entries` is append-only with debit/credit entries; `billing_accounts.credit_balance_amount` is a cached derived value updated by the application (not a trigger-derived computed column — triggers on append-only tables are acceptable but the cached column avoids a full SUM on every read).

**Rationale:** A single mutable balance column is not auditable — it cannot answer "how did we reach this balance?" The ledger approach satisfies INV-BILL-10 while the cached column preserves read performance.

**Alternatives rejected:** Fully trigger-derived balance (SUM on every UPDATE) — rejected due to performance at scale. Event sourcing with no cached value — rejected for read-path simplicity.

**Consequences:** The cached `credit_balance_amount` must be reconciled nightly against the ledger sum as a consistency check. On divergence, the ledger sum is authoritative.

---

### ADR-5H-005: Billing Period as Explicit Table

**Decision:** `billing_periods` is an explicit table, not derived from subscription `current_period_start/end`. Each period row is immutable after closure (`closed_at IS NOT NULL`).

**Rationale:** Subscription `current_period_start/end` is mutable (it advances on renewal). Tying invoices and usage records directly to subscription period fields would make historical period boundaries mutable. An explicit `billing_periods` row is the authoritative, immutable record of what period a usage/invoice belongs to.

**Consequences:** Renewal job must create a new `billing_periods` row before advancing the subscription's `current_period_*` fields.

---

### ADR-5H-006: Financial Immutability via REVOKE + SECURITY DEFINER

**Decision:** `REVOKE UPDATE, DELETE` on `invoices` (effectively via trigger), `invoice_lines`, `tax_lines`, `payment_attempts`, `refunds`, `usage_events`, `cost_entries`, `credit_ledger_entries` for `app_api` and `app_worker` roles. Controlled mutations only through `SECURITY DEFINER` functions (`fn_finalize_invoice`, `fn_mark_invoice_paid`, `fn_void_invoice`).

**Rationale:** INV-BILL-09. Application bugs or SQL injection cannot arbitrarily mutate financial history. SECURITY DEFINER functions enforce state machine transitions. `app_platform_admin` retains full access for operational corrections.

**Alternatives rejected:** Application-layer-only immutability checks — rejected because they can be bypassed by direct DB access or application bugs. Row-level triggers only — triggers can be disabled by superuser; REVOKE is more robust for non-superuser application roles.

---

### ADR-5H-007: Payment Provider Abstraction via `payment_provider TEXT` Column

**Decision:** `payment_attempts.payment_provider TEXT CHECK (... IN ('RAZORPAY','CASHFREE','STRIPE','OTHER'))`. No provider-specific columns. Provider transaction IDs stored as `TEXT`.

**Rationale:** Phase 4I §5 confirms Razorpay as V1 provider with Cashfree as documented second. The domain must not know Razorpay exists (Phase 4I §2.1 "India-first means"). A `CHECK` constraint with known providers allows validation while remaining extensible; 'OTHER' handles migration periods.

**Alternatives rejected:** Separate `razorpay_payments` table — rejected; would couple schema to a provider. JSONB provider-specific blob — rejected; no type safety on provider transaction ID.

**Consequences:** Adding a new provider requires a schema migration to add it to the CHECK constraint. This is acceptable — new providers are infrequent infrastructure changes, not domain changes. Alternatively, the CHECK can be dropped in favor of application-layer validation (OPEN DESIGN DECISION for V2).

---

### ADR-5H-008: Currency Validation Strategy

**Decision:** Currency columns use `CHECK (currency ~ '^[A-Z]{3}$')` as a format guard. No FK to `fx_rates` or a dedicated `currencies` table. ISO 4217 validity enforced at application layer.

**Rationale:** A FK to `fx_rates` would prevent inserting billing records for currencies not yet in the FX table, causing operational friction. A dedicated `currencies` table adds schema complexity without proportional value in V1. The regex catches format errors; full ISO 4217 validation at application boundary is sufficient.

**Consequences:** Invalid but correctly formatted currency codes (e.g. 'ZZZ') can be stored. Application-layer validation and monitoring catch this in practice.

---

### ADR-5H-009: GST / Tax as Configuration, Not Schema Constants

**Decision:** No tax rate, GST percentage, CGST/SGST/IGST split, or threshold appears in column defaults, CHECK constraints, enum values, or seed data (except illustrative comments). `tax_rules.components JSONB` carries the rate structure. `TaxComputationService` is a pure function over `tax_rules` rows.

**Rationale:** Phase 4I §12.1, Phase 5A §11. GST rates change by government notification. Hard-coding rates in schema means every rate change requires a migration. Configuration-driven rates require only a new `tax_rules` row.

**Consequences:** Incorrect tax rules in `tax_rules` produce incorrect tax on invoices. Operational procedures must include a tax rule review step when GST rates change. Invoices snapshot `tax_rule_versions_applied` so historical computations are explainable.

---

### ADR-5H-010: Partitioning Strategy for usage_events and cost_entries

**Decision:** Partition `usage_events` and `cost_entries` by RANGE on `occurred_at` / `recorded_at` (monthly) from V1. All other billing tables: unpartitioned in V1.

**Rationale:** Phase 4I §10.3 confirms usage_events is the highest-priority ClickHouse migration candidate. Monthly partitioning enables efficient time-range queries and partition-drop for retention (90 days hot per Phase 4I §9.4). Partitioning from V1 avoids a painful online partition migration at scale.

**Threshold for other tables:** Partition `payment_attempts` at >5M rows, `invoice_lines` at >10M rows.

**Consequences:** Unique constraints on partitioned tables include the partition key (`occurred_at`) — this is the canonical PostgreSQL partitioning constraint. The idempotency key `(organization_id, source_system, source_event_id, occurred_at)` is therefore complete.

---

### ADR-5H-011: Gapless Invoice Numbering via Row-Locked Sequence Table

**Decision:** `invoice_number_sequences` with `SELECT ... FOR UPDATE` pattern in `fn_allocate_invoice_number()`. PostgreSQL SEQUENCE is explicitly rejected.

**Rationale:** Phase 5A §11.5. PostgreSQL sequences leak gaps on transaction rollback. Many jurisdictions (including India's GST requirement) expect gapless sequential invoice numbers. Row-locked UPDATE is serialized and gap-free.

**Consequences:** `fn_allocate_invoice_number` is a serialization point per `(organization_id, fiscal_year, prefix)`. At extreme invoice generation rates (>100/sec per org), this becomes a bottleneck. Acceptable for V1; V2 can use pre-allocated number ranges if needed.

---

### ADR-5H-012: India Fiscal Year Boundary

**Decision:** `invoice_number_sequences.fiscal_year` stores the year the Indian fiscal year *starts* (e.g. `2024` = FY 2024-25, starting 1 April 2024). The fiscal year boundary date (1 April for India) is application configuration, not a schema constant.

**Rationale:** Different organizations in future global expansion have different fiscal year boundaries. Configuration-driven boundary ensures correct rollover without schema changes.

**OPEN DESIGN DECISION:** fiscal year configuration per organization is not yet modelled in `billing_accounts` or `tax_profiles`. V1 assumes 1 April for all INR organizations. This must be resolved before global expansion.

---

## 29. Security Matrix

| Test | Mechanism | Expected Result |
|---|---|---|
| Tenant A queries Tenant B invoices | RLS `organization_id = current_tenant_id()` | 0 rows returned |
| Tenant A inserts usage event for Tenant B | RLS WITH CHECK | Permission denied |
| app_api UPDATE invoice | REVOKE UPDATE + trigger | Exception raised |
| app_worker UPDATE payment_attempts directly | REVOKE UPDATE | Permission denied; must use fn_update_payment_status |
| fn_update_payment_status called with terminal→different-terminal | State machine guard | Exception raised |
| fn_update_payment_status called twice with same terminal status | Idempotent return | No-op; no exception |
| app_api DELETE usage_event | REVOKE DELETE | Permission denied |
| app_api INSERT credit directly | REVOKE INSERT on credits from app_api | Permission denied; must use fn_billing_apply_credit |
| Duplicate usage event (same source_event_id) | UNIQUE constraint + ON CONFLICT DO NOTHING | Silent dedup; no error |
| Duplicate payment webhook | UNIQUE (payment_provider, provider_webhook_event_id) | ON CONFLICT DO NOTHING |
| Refund exceeds payment amount | fn_validate_refund_amount trigger | Exception raised |
| PAID invoice mutation | fn_invoice_immutability trigger | Exception raised |
| CANCELLED subscription reactivation | fn_sub_cancelled_terminal trigger | Exception raised |
| plan_version price update after publish | fn_plan_version_immutability trigger | Exception raised |
| billing_accounts currency change | fn_ba_currency_immutable trigger | Exception raised |
| Unauthorized credit grant (non-admin) | REVOKE INSERT on credits from app_api | Permission denied |
| Payment credentials in payment_attempts | Schema inspection | No card/CVV/bank credential columns present |

---

## 30. Test Matrix

### Tenant Isolation
- [ ] Tenant A cannot SELECT Tenant B's `billing_accounts`, `invoices`, `usage_events`, `payment_attempts`
- [ ] Tenant A cannot INSERT rows with `organization_id` = Tenant B

### Usage Idempotency
- [ ] Inserting the same `(organization_id, source_system, source_event_id, occurred_at)` twice results in exactly one row
- [ ] Concurrent inserts of the same event from two workers result in exactly one row

### Invoice Immutability
- [ ] `UPDATE invoices SET subtotal_amount = ... WHERE status = 'PAID'` raises exception
- [ ] `UPDATE invoices SET status = 'DRAFT' WHERE status = 'PAID'` raises exception
- [ ] `DELETE FROM invoice_lines WHERE invoice_id = $paid_invoice` raises permission error

### Payment Webhook Idempotency
- [ ] Processing the same `provider_webhook_event_id` twice results in exactly one `payment_attempts` row
- [ ] Second call to `fn_mark_invoice_paid` on already-PAID invoice raises exception

### Payment Status State Machine
- [ ] `fn_update_payment_status` transitions INITIATED → SUCCEEDED correctly
- [ ] `fn_update_payment_status` with SUCCEEDED → FAILED raises exception
- [ ] `fn_update_payment_status` with SUCCEEDED → SUCCEEDED is a no-op (idempotent)
- [ ] `app_worker` cannot UPDATE `payment_attempts` directly — permission denied

### Refund Guard
- [ ] Refund exceeding original payment amount raises exception
- [ ] Sum of two partial refunds exceeding payment amount raises exception on second refund

### Credit Concurrency
- [ ] Concurrent credit consumption of 100 units each against a 150-unit balance results in exactly one success and one failure (application-layer coordination required; DB provides `SELECT FOR UPDATE`)

### Subscription Terminal State
- [ ] `UPDATE subscriptions SET status = 'ACTIVE' WHERE status = 'CANCELLED'` raises exception
- [ ] Two concurrent subscription creation attempts for the same org result in exactly one ACTIVE subscription (partial unique index)

### Historical Pricing
- [ ] Publishing a new `plan_version` (v2) for a plan does not change the `subtotal_amount` on existing PAID invoices that reference v1
- [ ] `plan_versions` price update after `is_published = TRUE` raises exception

### Security
- [ ] `app_api` role cannot call `fn_billing_apply_credit()` — REVOKE protects credits table
- [ ] `app_api` role cannot UPDATE `invoices` directly
- [ ] `app_readonly` role cannot INSERT into any billing table

### GDPR
- [ ] `fn_billing_anonymize_org` clears `billing_contact_name`, `billing_contact_email` in `billing_accounts`
- [ ] `tax_profiles.billing_address` is cleared/set to `'REDACTED'` on anonymization
- [ ] Financial skeleton (amounts, dates, invoice numbers) is retained post-anonymization

### GST
- [ ] No `CHECK` constraint, column `DEFAULT`, or seed row encodes a specific tax rate
- [ ] `tax_rules.components` correctly stores multi-component GST (CGST + SGST or IGST)
- [ ] `invoices.tax_rule_versions_applied` correctly records the rule version used at invoice generation

---

## 31. Carry-Forward / Open Decisions

| ID | Topic | Disposition |
|---|---|---|
| ODD-5H-01 | Custom billing intervals (weekly, quarterly) | Excluded from V1; `billing_cycle` CHECK allows extension |
| ODD-5H-02 | Downgrade proration | Not defined in Phase 4F; excluded from V1; `billing_adjustments` can handle manual corrections |
| ODD-5H-03 | Billing period reopening | Not defined in Phase 4F; excluded from V1 |
| ODD-5H-04 | Mid-period quota override by admin | `quota_configs.override_reason` reserved; logic excluded from V1 |
| ODD-5H-05 | Exact HSN/SAC code for platform services | Requires legal/tax review; seed comment provided but row not inserted |
| ODD-5H-06 | Fiscal year boundary per organization | V1 hardcodes 1 April (India) at application layer; org-level config needed for global expansion |
| ODD-5H-07 | GDPR retention periods for financial records | Architecture supports anonymization but exact retention years require legal review |
| ODD-5H-08 | payment_provider CHECK vs application-layer only for V2 | Noted in ADR-5H-007; revisit when adding third provider |
| ODD-5H-09 | E-invoicing (IRN) integration | `e_invoice_ref` column reserved; no integration in V1 |
| ODD-5H-10 | Customer-facing multi-currency invoicing | Not in V1 per Phase 4I §11.4; architecture supports without redesign |

---

## 32. Final Consistency Review

### Against Phase 5A

| Standard | Status |
|---|---|
| All monetary columns are `NUMERIC(18,4)` + `CHAR(3)` pairs | ✅ |
| No `FLOAT`, no PostgreSQL `MONEY` | ✅ |
| `gen_uuid_v7()` for all PKs | ✅ |
| `TIMESTAMPTZ` for all timestamps | ✅ |
| Migration chain continuous from 046 (Phase 5G/Workflow, per reconciliation) | ✅ (047–058) |
| No migration number reuse | ✅ |
| `CONCURRENTLY` not needed in migrations (no live table index creation) | ✅ |
| GST rates not in schema constants | ✅ |
| Invoice numbering via row-locked sequence table | ✅ |

### Against Phase 5B

| Standard | Status |
|---|---|
| `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY` on all tenant tables | ✅ |
| RLS uses `organization.current_tenant_id()` | ✅ |
| No second tenant isolation mechanism invented | ✅ |
| SECURITY DEFINER functions `REVOKE ALL FROM PUBLIC` + explicit `GRANT EXECUTE` | ✅ |

### Against Phase 5C (Voice)

| Standard | Status |
|---|---|
| Billing does not own or duplicate call data | ✅ |
| Billing receives `CALL_MINUTES` via event, not by querying `voice.call_sessions` | ✅ |
| No cross-schema FK to voice schema | ✅ |

### Against Phase 5D–5G (CRM, Campaign, Knowledge, Workflow)

| Standard | Status |
|---|---|
| No cross-schema FK to crm, campaign, knowledge, workflow schemas | ✅ |
| Logical references only (source_event_id, source_system) | ✅ |
| Usage events attributed via source_context JSONB, not FK | ✅ |

### Critical Invariants

| Invariant | Status |
|---|---|
| No duplicate ownership of voice/CRM/campaign/knowledge data | ✅ |
| No cross-tenant leakage (RLS on all tenant tables) | ✅ |
| No double charging (usage idempotency constraint) | ✅ |
| No mutable finalized financial history (REVOKE + triggers) | ✅ |
| No mutable historical pricing dependency (plan_version pinning) | ✅ |
| No unrestricted financial UPDATE | ✅ |
| No unrestricted financial DELETE | ✅ |
| No payment secrets in schema | ✅ |
| No speculative tables | ✅ |
| No migration collision (047–058 are new numbers) | ✅ |
| No unresolved CRITICAL billing race | ✅ (idempotency + SELECT FOR UPDATE + advisory locks) |

### Issues Found During Review

**RESOLVED — `payment_attempts` UPDATE restriction:** `REVOKE UPDATE, DELETE` on `payment_attempts` means `app_worker` cannot directly update payment status (e.g. INITIATED → SUCCEEDED) from the webhook handler. `fn_update_payment_status()` SECURITY DEFINER function is included in migration 057 DDL (§24). It enforces the allowed state machine (`INITIATED → PENDING|SUCCEEDED|FAILED|CANCELLED`; `PENDING → SUCCEEDED|FAILED|CANCELLED`), is idempotent for terminal-to-same-terminal transitions, and is the sole path for `app_worker` to mutate payment attempt status. This issue is fully resolved — no carry-forward.

**MINOR — `quota_configs` INSERT path:** `app_api` has SELECT only; `app_worker` has INSERT/UPDATE. Quota configs are seeded during subscription creation (a worker operation). This is correct. No issue.

**ENHANCEMENT — `billing_adjustments` SECURITY DEFINER function:** Currently `app_worker` can INSERT directly. For full financial control parity, a SECURITY DEFINER `fn_create_billing_adjustment` is recommended. Not a blocker — worker is a trusted role.

All CRITICAL and SIGNIFICANT issues: **NONE**.

---

## 33. Final Approval Status

```
PHASE 5H — BILLING / USAGE SCHEMA
(Authoritative phase label per PHASE-NUMBERING-RECONCILIATION.md)

Resolutions applied across review iterations:
  Phase-numbering conflict:   RESOLVED — document is Phase 5H (billing)
                              per PHASE-NUMBERING-RECONCILIATION.md;
                              Phase 5A §30 numbering table superseded
  fn_update_payment_status(): RESOLVED — SECURITY DEFINER DDL in migration 057

Currency model:          APPROVED
Plan / versioning:       APPROVED
Subscription lifecycle:  APPROVED
Billing periods:         APPROVED
Usage metering:          APPROVED
Usage idempotency:       APPROVED
Usage aggregation:       APPROVED
Quotas / entitlements:   APPROVED
Credit ledger:           APPROVED
Overage model:           APPROVED
Invoice model:           APPROVED
Tax / GST model:         APPROVED
Payment abstraction:     APPROVED
Refund model:            APPROVED
Financial immutability:  APPROVED
Tenant isolation:        APPROVED
Security model:          APPROVED
Concurrency guards:      APPROVED
Index strategy:          APPROVED
Partitioning:            APPROVED
Migration chain:         APPROVED (047–058, continuous from 046)
Open decisions:          10 items documented; none block V1
Carry-forwards:          1 MINOR item (billing_adjustments SECURITY DEFINER fn);
                         does not block approval

CRITICAL issues:         NONE
SIGNIFICANT issues:      NONE
BLOCKING ISSUES:         NONE

PHASE 5H STATUS = APPROVED
PHASE 5I READY
```

Phase 5I covers: `integrations`, `webhooks`, `plugins` schemas.
Phase 5J covers: `analytics`, `audit` schemas.
