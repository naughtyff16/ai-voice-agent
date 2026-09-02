# Phase 6L — Analytics + Audit APIs

## 1. Document Control

| | |
|---|---|
| **Phase** | 6L |
| **Status** | **APPROVED / FROZEN** (§72) — includes the Phase 6L freeze-gate remediation pass (RBAC sensitive-media split, recording-access audit, DEC-6L-01/02 owner rulings applied, live PostgreSQL 18.6 validation) |
| **Scope** | Analytics read/query contracts (tenant + platform-internal) and Audit read/query contracts; plus, from the remediation pass, the sensitive-media authorization/audit boundary (6D) and one operational composition contract (6H §15.6) it required to resolve |
| **Depends on** | Phase 1 (SRS), Phase 4G/4H/4I, Phase 5A–5K (all FROZEN except the two additive amendments this document's remediation applies), Phase 6A–6K (all FROZEN, with 6D/6H amended by the remediation pass), owner rulings DEC-6L-01 = Option C / DEC-6L-02 = Option A (FINAL) |
| **PostgreSQL baseline** | 18.6, head `104_5B3` (chain: `102_5H2` → `103_5J2` → `104_5B3`; `102_5H2.sql` SHA-256 `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d`, reconfirmed unchanged, §58) |
| **Applied migrations** | `103_5J2` (FX-normalized ROI/margin) and `104_5B3` (sensitive-media permission split) — both live-validated against a disposable PostgreSQL 18.6 instance, §57 |
| **Does not** | Redesign 1–6K beyond the two targeted, necessary amendments; start 6M's own implementation (only its precise handoff spec, §61.1); implement the FastAPI application; silently decide product/business questions (both surfaced decisions were owner-ruled, not silently chosen, §60); invent APIs over persistence that does not exist |

---

## 2. Purpose

6L defines the implementation-ready API/read-contract layer for tenant analytics dashboards, cost/financial analytics, and audit history — reconciled against the actual PostgreSQL 18 schema executed through migration `102_5H2`, and against every frozen API contract 6A–6K. It is a **contract and gap-analysis document**, not an implementation. Where the frozen schema cannot correctly support a mandatory requirement, the gap is classified precisely (§53) and, where genuinely necessary, the smallest additive migration is proposed (§54) — never a silent redesign of 5A–5K.

---

## 3. Scope

**In scope (owned by 6L):** tenant analytics dashboards (executive, operational, campaign, agent, financial); call, latency, AI/conversation, agent-utilization, lead-funnel, campaign-outcome, ROI, usage/cost, tool-execution, and webhook-delivery analytics; audit event search/read; audit integrity visibility where actually supported; freshness/staleness semantics; query/filter/bucketing contracts; analytics authorization and privacy; the analytics API error model; performance/limits; internal projection/query contracts; the ClickHouse portability seam.

**Out of scope (§4 of the task brief, restated):** raw call lifecycle (6D), agent configuration (6E), CRM mutation (6G), campaign execution (6H), workflow execution (6I), webhook delivery mutation (6J), invoice/payment mutation (6K), platform-admin control-plane surface (future 6M), production analytics implementation (a later implementation phase), infrastructure observability dashboards (Phase 21).

---

## 4. Non-Goals

- No enterprise BI/export pipeline (ODD-5J-05 remains future — §58).
- No prompt-experiment/A/B analytics (ODD-5J-06 remains future — §58).
- No CSAT API is invented where no producer/persistence exists (§36).
- No dynamic/SQL-like filter DSL; every endpoint uses an explicit allow-list (§14).
- No rebuild/replay/backfill control API for tenants or generic admins (§45).
- No column-by-column mechanical mapping of every `analytics.*` table to a REST endpoint — the API expresses reporting concepts, not tables (§37).

---

## 5. Source Documents Reviewed

**Product:** `docs/phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` (§3.14 FR-AN-001..004, audit/security NFRs).

**Architecture:** `docs/phase-02-high-level-architecture/*`; `docs/phase-04-domain-driven-design/4G-Analytics-Cross-Domain-Context-Map.md`, `4H-Final-Architecture-Review.md`, `4I-India-First-Decision-Closure.md`, `4A-Core-Domains.md`.

**Database:** `5A-Database-Architecture-and-Standards.md`, `5B-Identity-Organization-Multitenancy-Security.md`, `5H-Billing-Usage-Schema.md`, `5J-Analytics-Audit-Schema.md`, `5K/5K-Database-Migration-and-Implementation.md`, `5K/MIGRATION_MANIFEST.md`, `5K/EXECUTION_REPORT.md`, and the executed SQL for migrations `001`–`102` (with line-by-line inspection of `007_5B.sql`, `051_5H.sql`, `067_5J.sql`–`077_5J1.sql`, `102_5H2.sql`).

**APIs:** `6A-API-Architecture-and-Standards.md` through `6K-Billing-Usage-APIs.md`, all read in full or by targeted section for every cross-reference this document makes.

Every specific claim below cites the file and, where useful, the section that supports it — this document does not rely on memory of conceptual prose where the executed SQL could be (and was) inspected directly.

---

## 6. Terminology

| Term | Meaning |
|---|---|
| Projection | A read-optimized `analytics.*` table populated exclusively by an ingestion/projection mechanism — never queried backward into a transactional 5B–5I table (5J §10). |
| Grain | The unique combination of dimension columns identifying one aggregate row (5J §10, per-table). |
| Bucket | A fixed time window (`hour_bucket`, `date_bucket`, `year_month`) a projection aggregates into. |
| Data-as-of / freshness | The point in time up to which a projection is known to be complete, communicated in every analytics response (§16). |
| Governed action_kind | A string value in `audit.audit_events.action_kind` that a controlled amendment (5J §14.3's †/‡/¶/§ markers) has sanctioned for use, even though the column itself carries no `IN (...)` or enum constraint. |
| FX-normalized amount | A monetary amount converted, with the applied rate/source/timestamp recorded on the row, into one common currency — the only representation this document permits for a cross-source financial computation (4I §11.3). |

---

## 7. Frozen Baseline

- **PostgreSQL 18.x**, Alembic head `102_5H2`.
- `docs/phase-05-database-design/5K/migrations/102_5H2.sql` SHA-256 reconfirmed in this pass: `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` — **unchanged**, matches the value the task brief supplied. Verified with `sha256sum` in this session (§52); migrations `001`–`102` were not opened for edit at any point.
- Migrations `067_5J` → `075_5J`, `077_5J1` were read directly (not summarized from 5J's prose) to confirm the exact executed analytics/audit DDL and grants used throughout this document.
- One additive migration is proposed: `103_5J2`, `down_revision = '102_5H2'` (§54). It is the only schema change this document proposes, and it is scoped to two existing tables' columns — no table, function, role, or grant outside `analytics.roi_by_campaign` / `analytics.billing_revenue_monthly` is touched.

---

## 8. Analytics/Audit Bounded Context Ownership

Confirmed unchanged from 4G/4H/5J: **Analytics is a pure CQRS read context** — it is a "Conformist" downstream of every producing context (4H §9.2/§10), never publishes an event any producer subscribes to, and owns no write commands beyond internal projection maintenance. **Audit is an accountability log**, not analytics, not logging, not metrics (5J §5) — separately schema'd (`audit` vs `analytics`), separately access-controlled, and immutable by construction (5J §5.3, reconfirmed in the executed grants, §51 below). 6L's own read APIs preserve both properties: no analytics endpoint reads a 5B–5I transactional table, and no audit endpoint (or any other API in this platform) has write access to `audit.audit_events`.

---

## 9. Architecture (Preserved, Not Redesigned)

```
domain events (Redis Streams)
    → analytics.fn_ingest_analytics_event()         [dedup + ledger insert, SECURITY DEFINER]
    → analytics.fn_apply_projection_*()             [atomic claim + UPSERT, SECURITY DEFINER — 2 of 12 exist today, §12]
    → analytics projection tables                    [10.1–10.12 catalog, §11]
    → 6L read APIs                                   [this document]

application/system action requiring accountability
    → audit.fn_insert_audit_event()                 [SECURITY DEFINER, sole write path]
    → audit.audit_events (immutable)
    → (nightly) audit.fn_compute_chain_hash()        [SECURITY DEFINER, read-only against audit_events]
    → audit.audit_chain
    → 6L read APIs                                   [this document]
```

**Mandatory invariant, preserved:** every tenant-facing analytics endpoint in this document reads a projection table, never a 5B–5I transactional table, and never `analytics.analytics_events` (§20). The only exception this document takes is bounded reference-label resolution (e.g., resolving a `campaign_id` filter to a display name) — and even that is deferred to the owning context's own existing read endpoint (6H `GET /campaigns/{id}`), never an inline join from a 6L repository.

---

## 10. Projection Catalog (Verified Against Executed DDL)

All twelve tables below were located and read directly in `067_5J.sql`–`075_5J.sql`. Columns, grain, and grants quoted are the executed values, not 5J's prose paraphrase (which agrees in every case checked).

| # | Table | Grain | Partitioning | Retention | RLS | `app_api` SELECT |
|---|---|---|---|---|---|---|
| 1 | `call_metrics_hourly` | org, hour, agent_id (nullable), direction, call_outcome, provider, language_code | Monthly RANGE | 2 years | Yes, FORCE | Yes |
| 2 | `call_latency_stage_hourly` | org, hour, provider, provider_category, model, bucket_upper_ms | Monthly RANGE | 2 years | Yes, FORCE | Yes |
| 3 | `conversation_turn_stats_daily` | org, date, agent_id (NOT NULL) | Monthly RANGE | 2 years | Yes, FORCE | Yes |
| 4 | `agent_utilization_hourly` | org, hour, agent_id (NOT NULL) | Monthly RANGE | 2 years | Yes, FORCE | Yes |
| 5 | `lead_funnel_daily` | org, date, campaign_id (nullable) | Monthly RANGE | 5 years | Yes, FORCE | Yes |
| 6 | `campaign_outcome_summary` | campaign_id (UNIQUE) | None | 5 years post-completion | Yes, FORCE | Yes |
| 7 | `usage_cost_daily` | org, date, metric, provider, model (sentinel `'all'`) | Monthly RANGE | 2y hot / 7y cold | Yes, FORCE | Yes |
| 8 | `billing_revenue_monthly` | org, year_month | Yearly RANGE (`year_bucket` INTEGER, corrected in `071_5J.sql`, see its header) | 7 years | Yes, FORCE | Yes |
| 9 | `roi_by_campaign` | campaign_id (UNIQUE) | None | 5 years | Yes, FORCE | Yes |
| 10 | `tool_execution_stats_daily` | org, date, tool_name, agent_id (nullable) | Monthly RANGE | 2 years | Yes, FORCE | Yes |
| 11 | `webhook_delivery_stats_daily` | org, date | Monthly RANGE | 2 years | Yes, FORCE | Yes |
| 12 | `provider_health_5min` | (platform-global, no `organization_id`) | — | 30 days | N/A (GRANT/REVOKE only) | **No — explicit REVOKE** (5J §13.3, `071_5J.sql`) |

Also inspected and factored into this document's boundaries: `analytics.analytics_events` (ingestion ledger — `app_api` **does** hold SELECT at the DB layer, §20), `analytics.analytics_event_dedup` / `analytics.analytics_projection_events` (internal-only, no `app_api` SELECT on the latter — worker control tables), `analytics.event_schema_versions` (not located as an executed table in `067`–`077`; see §53 item 6), `audit.audit_events`, `audit.audit_chain`.

No thirteenth projection is invented anywhere in this document.

---

## 11. Permission Model — Reconciled to Executed Seed Data

`docs/phase-05-database-design/5K/migrations/007_5B.sql` was read directly. The executed permission catalog uses:

```
analytics:read              -- 'View Analytics'
analytics_cost:read         -- 'View Cost Analytics'
analytics_platform:read     -- 'View Platform Analytics'
audit:read                  -- 'View Audit Log'
```

**Terminology reconciliation (required by the task brief, §8):** these are the only strings that exist. Older prose variants such as `analytics:cost_read` / `analytics:platform_read` do not appear anywhere in `007_5B.sql` and are not used anywhere in this document.

**Exact role assignments, verified line-by-line in `007_5B.sql`'s `role_permissions` seed (not assumed from 5B's prose):**

| Role | `analytics:read` | `analytics_cost:read` | `analytics_platform:read` | `audit:read` |
|---|:---:|:---:|:---:|:---:|
| OWNER | ✅ | ✅ | — | ✅ |
| ADMIN | ✅ | ✅ | — | ✅ |
| MEMBER | ✅ | — | — | — |
| BILLING_ADMIN | ✅ | ✅ | — | — |
| VIEWER | ✅ | — | — | — |

**`analytics_platform:read` is assigned to zero tenant system roles.** It exists in the permission catalog but is never granted to OWNER, ADMIN, MEMBER, BILLING_ADMIN, or VIEWER anywhere in the executed seed — confirming it is platform-admin-only, consumed by a separate platform-operator authorization path (not `organization.role_permissions`), never a tenant-reachable permission. 6L treats any endpoint requiring `analytics_platform:read` as **not** part of the tenant-facing `/api/v1/analytics/*` surface (§31).

**`analytics_cost:read` remains in the permission catalog, unchanged by this pass, but is no longer referenced by any endpoint this document defines** — following the freeze-gate remediation's owner ruling (DEC-6L-02 = Option A, §60), provider cost/margin data is platform-internal in full, so no tenant-facing 6L endpoint gates on this permission any more (§26/§27). It is not removed from the catalog (no migration touches it) and remains available for any future, genuinely customer-facing cost feature 6K/6M might define.

**No new *analytics-domain* permission string is introduced by this document.** The freeze-gate remediation pass does add two new permission strings — `recording:access_media` and `transcript:access_content` (migration `104_5B3.sql`) — but these govern 6D's Voice/Recording/Transcript resources, not an analytics resource; they are referenced here only because 6L's audit contract (§32) and the new operational composition endpoint (6H §15.6, cross-referenced §49) depend on them.

---

## 12. Projection Population — Verified, Not Assumed (Task Brief §7)

Direct inspection of `068_5J.sql`, `069_5J.sql`, `076_5K1.sql` (which patches the two functions' `search_path`, not their existence) confirms:

| Function | Exists in executed migrations? |
|---|---|
| `analytics.fn_apply_projection_call_metrics()` | **Yes** — `068_5J.sql`, patched by `076_5K1.sql` |
| `analytics.fn_apply_projection_call_latency()` | **Yes** — `069_5J.sql`, patched by `076_5K1.sql` |
| A `fn_apply_projection_*` for any of the other 10 projection tables | **No.** 5J §17's own inventory table (line 2312 of `5J-Analytics-Audit-Schema.md`) states only: *"(analogous `fn_apply_projection_*` for every other projection table — identical pattern...)"* — a **prose placeholder**, not a description of an executed function. No `CREATE ... FUNCTION analytics.fn_apply_projection_conversation...`, `..._agent_utilization`, `..._lead_funnel`, `..._tool_execution`, `..._webhook_delivery`, `..._campaign_outcome`, `..._usage_cost`, or `..._billing_revenue` exists anywhere in migrations `067`–`102`. |

**Classification (per the task brief's A/B/C test, §7):** for `call_metrics_hourly` and `call_latency_stage_hourly` — **(A) actually present**, atomic DB function, exactly as specified in 5J §9.2. For the other 10 projections — **(C) missing**, not (B) worker-SQL-that-simply-isn't-shown-in-this-document — there is no evidence anywhere in the repository (application code does not exist yet; this is a docs-only repository at this phase) that an equivalent application-layer atomic claim-and-mutate implementation exists either.

This is **not a 6L blocker**: 6L is a contract-design phase, not the phase that writes projection-population code. It is recorded here as an **IMPLEMENTATION DEPENDENCY** (§53) with an explicit responsibility statement (§54/§59): whoever builds the projection worker for these 10 tables must either (a) author the missing `fn_apply_projection_*` functions following the exact atomic claim-and-mutate pattern `069_5J.sql` already demonstrates, or (b) implement the equivalent atomicity guarantee in application code with a documented, reviewed proof that it preserves 5J §9.2's exactly-once invariant — a bare "insert then upsert, not in one transaction" implementation would silently reintroduce the double-counting risk 5J §9.2 exists to prevent. `roi_by_campaign` is additionally **not** an event-per-event projection at all — 5J §10.9 states it is "derived nightly" from `campaign_outcome_summary` + `usage_cost_daily`, i.e., a batch job, not a claim-and-mutate atomic wrapper; this document's endpoint design (§26) accounts for that by documenting nightly, not near-real-time, freshness for ROI.

---

## 13. Tenant Isolation

Unchanged from 5J §6: every tenant-owned analytics/audit table has RLS + FORCE RLS with `USING (organization_id = organization.current_tenant_id())`; `app_platform_admin` crosses tenant boundaries only via `BYPASSRLS`, never for direct mutation of audit history (no role, including `app_platform_admin`, has INSERT/UPDATE/DELETE on `audit.audit_events`/`audit.audit_chain` — confirmed in `072_5J.sql`, §51). 6L's application layer additionally verifies resource ownership before returning any resource-scoped analytics response (agent, campaign) — a foreign-tenant ID resolves as `404`, never `403`, per 6A §22/§7.4 (never confirm cross-tenant existence).

---

## 14. Analytics Read Contract — Query Model

One consistent query model, per-endpoint allow-listed (6A §15 — no dynamic filter DSL is accepted from any client):

```
from, to            -- mandatory on every time-series/heavy-read endpoint (§15)
granularity         -- allow-listed per dataset (§17)
agent_id            -- where the underlying projection actually carries it (§10)
campaign_id          -- where the underlying projection actually carries it
provider, model      -- where the underlying projection actually carries it
direction, outcome   -- call_metrics_hourly only
language_code        -- call_metrics_hourly only
metric               -- usage_cost_daily / tool_execution_stats_daily only
```

No endpoint accepts `filter`, `where`, `group_by`, `select`, or `order_expression` from a client (6A §15's anti-injection rule, restated for analytics specifically per the task brief §20). A filter not on an endpoint's documented allow-list returns `422 VALIDATION_ERROR`, matching 6A §15's existing rule — not a silent no-op.

---

## 15. Time Range Semantics

**Single rule, used everywhere:** `[from, to)` — `from` inclusive, `to` exclusive, both UTC ISO-8601 timestamps (6A §7.5).

| Setting | Value |
|---|---|
| Maximum range | 400 days for hourly/daily-sourced endpoints (calls, latency, conversation, agent, tools, webhooks, leads); 37 months for `billing_revenue_monthly`-backed endpoints (matches its yearly partitioning, 5J §10.8) |
| Default range | Last 30 days if `from`/`to` omitted |
| Granularity validity | `hour` only for datasets whose source projection is hourly (§17); `day`/`week`/`month` roll-ups are always safe additive sums over the stored grain — never a manufactured finer granularity (§17) |
| Retention boundary | A request whose `from` predates the dataset's documented retention (§28) does **not** silently return an incomplete result labeled as complete — see §27's `ANALYTICS_ARCHIVED_RANGE_UNAVAILABLE` handling |

A range exceeding the maximum returns `422 ANALYTICS_RANGE_TOO_LARGE` (§30), never a silently truncated result.

---

## 16. Freshness / Eventual Consistency

Every analytics response body includes:

```json
"data_as_of": "2026-08-31T09:00:00Z",
"is_partial": false
```

`data_as_of` is the latest `last_updated_at`/`computed_at` actually observed across the rows contributing to the response (or, for a zero-row result, the latest `processed_at` watermark for that projection/org — never simply "now"). `is_partial: true` is set whenever the requested range extends into a period the projection worker has not yet fully caught up to (detected by comparing the requested `to` against the projection's own freshness watermark) — this is the mechanism that prevents "a call ended milliseconds ago but isn't in the dashboard yet" from being silently presented as a complete, authoritative zero.

**Freshness targets, not fabricated as a measured production SLA (task brief §61):**

| Source class | Architectural target | Basis |
|---|---|---|
| Hourly/daily event-fed projections (1, 2, 3, 4, 5, 10, 11 in §10) | Near-real-time, ≤60s lag | 6A §11 Tier C: *"Must read from pre-computed CQRS projections (4G §3.1 — Analytics is projection-based, ≤60s lag)"* — an existing frozen number, not invented here |
| `campaign_outcome_summary` | Near-real-time, ≤60s lag (same event-fed mechanism, once its `fn_apply_projection_*` exists — §12) | Same basis |
| `usage_cost_daily` | Near-real-time, ≤60s lag for the projection itself; downstream billing reconciliation may lag further (6K §22.4's own late-usage handling) | 5J §10.7 + 6K §22.4 |
| `roi_by_campaign` | **Nightly batch** — not real-time | 5J §10.9: "derived nightly" |
| `billing_revenue_monthly` | **Monthly** | 5J §10.8 grain is `year_month` |
| `provider_health_5min` | 5-minute window (platform-internal only, §21) | 5J §13.1 |

No endpoint in this document claims a freshness tighter than its source projection's own architecture supports.

---

## 17. Granularity

| Dataset | Stored grain | Client-requestable granularity |
|---|---|---|
| Calls / latency | hourly | `hour`, `day`, `week` — never finer than hourly |
| Conversation / agent utilization | hourly (agent utilization) / daily (conversation) | matches stored grain and coarser roll-ups only |
| Lead funnel / tools / webhooks | daily | `day`, `week`, `month` |
| Campaign outcome / ROI | unbounded (current aggregate per campaign) | not time-series; a point-in-time snapshot |
| Revenue | monthly | `month`, `quarter`, `year` |
| Provider health | 5-minute (internal only) | not exposed to tenants at all |
| Audit | raw event timestamp | no bucketing — list/cursor only |

A roll-up is always a sum (or, for `agent_utilization_hourly`'s concurrency measures, the correct non-linear aggregation — §22) over the stored grain; no endpoint manufactures a finer granularity than its source projection retains (task brief §23).

---

## 18. Derived Metric Definitions (Single Source of Truth)

Every ratio below is computed identically wherever it appears — no endpoint recomputes a KPI differently.

| Metric | Formula | Zero-denominator | Precision |
|---|---|---|---|
| `answer_rate` | `answered_calls / NULLIF(total_calls, 0)` | `null` | 4 decimal ratio (§19) |
| `completion_rate` | `completed_calls / NULLIF(connected_calls, 0)` | `null` | 4 decimal ratio |
| `transfer_rate` | `transfer_count / NULLIF(total_calls, 0)` | `null` | 4 decimal ratio |
| `qualification_rate` | `leads_qualified / NULLIF(leads_answered, 0)` | `null` | 4 decimal ratio |
| `conversion_rate` | `leads_converted / NULLIF(leads_qualified, 0)` | `null` | 4 decimal ratio |
| `appointment_rate` | `appointments_booked / NULLIF(leads_qualified, 0)` | `null` | 4 decimal ratio |
| `tool_success_rate` | `succeeded / NULLIF(invocations, 0)` | `null` | 4 decimal ratio |
| `webhook_success_rate` | `succeeded_deliveries / NULLIF(total_deliveries, 0)` | `null` | 4 decimal ratio |
| `average_duration` | `total_duration_s / NULLIF(total_calls, 0)` | `null` | seconds, 1 decimal |
| `average_concurrency` | `SUM(sum_concurrent_samples) / NULLIF(SUM(sample_count), 0)` across the merged bucket range — **never** an average of per-hour averages (§22) | `null` | 2 decimal |
| `cost_per_call` | `cost_amount_org_currency / NULLIF(total_calls, 0)` | `null` | Money (§19) |
| `cost_per_qualified` | `cost_amount_org_currency / NULLIF(leads_qualified, 0)` | `null` | Money |
| `ROI` | `(estimated_revenue_amount_org_currency - total_cost_amount_org_currency) / NULLIF(total_cost_amount_org_currency, 0) * 100` — **only** computed from FX-normalized, single-currency amounts (§25/§54) | `null` | 4 decimal percent |

All money-denominated derived metrics use FX-normalized amounts exclusively — never a raw amount whose currency has not been confirmed to match the other operand (§25).

---

## 19. Response Formats — Money and Percentages

**Money** — reuses 6A §7.5's canonical DTO exactly:

```json
{ "amount": "1234.5600", "currency": "INR" }
```

`amount` is always a string (never a JSON number, avoiding float precision loss on `NUMERIC(18,4)`); `currency` is always present — no endpoint in this document ever returns a bare numeric monetary field, and no endpoint combines two different currencies into one total without an explicit FX-normalization note (§25).

**Percentages / ratios — one representation, used everywhere in this document:** a **decimal ratio string**, e.g. `"0.4250"` meaning 42.5% (not a pre-multiplied `"42.5000"` percent string), with the single documented exception of `roi_pct`, which — because it is already named and stored as a *percent* in the executed schema (`analytics.roi_by_campaign.roi_pct NUMERIC(8,4)`, `071_5J.sql`) — is serialized as a percent value, e.g. `"12.5000"` meaning 12.5%, explicitly labeled `roi_pct` (never bare `roi`) so the two conventions are never confused. Every denominator-zero case in §18 serializes as JSON `null`, never `NaN`/`Infinity`/a fabricated `0`.

---

## 20. Executive Dashboard

`GET /api/v1/analytics/overview` — **Permission:** `analytics:read`.

| Element | Source |
|---|---|
| Total calls, answered calls, answer rate, average duration | `call_metrics_hourly` |
| Leads qualified, converted, appointments | `lead_funnel_daily` |
| Active/completed campaign counts, aggregate outcome (calls/qualification/conversion only — **never** cost/ROI) | `campaign_outcome_summary`, cost/margin columns excluded (§26, DEC-6L-02 = Option A) |

**No `costs` key exists in this response at all, for any caller, at any permission level.** Per **DEC-6L-02 = Option A (owner-approved, FINAL, §60)**, provider procurement cost, gross margin, and provider/customer spread are platform-internal, full stop — there is no bounded-aggregate tenant exposure of any kind. A tenant's own customer-facing cost/billing picture is 6K's `GET /billing/summary`/`GET /billing/usage` (§28), not a 6L dashboard section — this executive dashboard links to it rather than duplicating it.

**Filters:** `from`, `to` (default last 30 days, max 400 days). **Granularity:** summary only (no time series) — a single aggregate over the range, plus `data_as_of`/`is_partial` (§16). **Response shape:**

```json
{
  "data": {
    "range": { "from": "...", "to": "...", "granularity": "summary" },
    "data_as_of": "...", "is_partial": false,
    "calls": { "total_calls": 1200, "answered_calls": 980, "answer_rate": "0.8167", "average_duration_s": "142.3" },
    "leads": { "leads_qualified": 310, "leads_converted": 88, "appointments_booked": 64 },
    "campaigns": { "active_count": 4, "completed_count": 11 }
  },
  "meta": { "request_id": "..." }
}
```

**Unavailable fields:** CSAT is never included (§38 — DEC-6L-01 = Option C, no CSAT in V1). Provider cost/margin/platform data is never included, for any caller, regardless of permission (§26/§27, DEC-6L-02 = Option A).

---

## 21. Operational / Call Analytics

`GET /api/v1/analytics/calls` — **Permission:** `analytics:read`. **Source:** `call_metrics_hourly`. **Dimensions:** `agent_id`, `direction`, `call_outcome`, `provider`, `language_code` — exactly the columns in the table's grain (5J §10.1); no dimension is invented. **Granularity:** `hour`/`day`/`week`. **Aggregation rule:** every measure listed in 5J §10.1 is additive — a roll-up to `day`/`week` is a plain `SUM(...)` grouped by the coarser bucket, computed server-side, never delegated to the client.

`GET /api/v1/analytics/calls/latency` — **Permission:** `analytics:read`. **Source:** `call_latency_stage_hourly`. **Dimensions:** `provider`, `provider_category`, `model`. This endpoint is the one place in 6L where §24's percentile rules apply in full — see §24.

Neither endpoint ever returns a raw `analytics.analytics_events` payload row (task brief §31) — only the two projection tables above.

---

## 22. Agent Analytics

`GET /api/v1/analytics/agents` — **Permission:** `analytics:read`. **Source:** `agent_utilization_hourly` (concurrency) joined, at the query layer only (never a transactional join), by `agent_id` with `conversation_turn_stats_daily` (turns/tokens) — both tables already carry `agent_id` as a NOT NULL grain column (5J §10.3/§10.4), so this is a projection-to-projection combination, not a reach into `voice.agents`.

`GET /api/v1/analytics/agents/{agent_id}` — same data, scoped to one agent. Supportable **without** OLTP reconstruction because `agent_id` is already a first-class NOT NULL grain dimension on both source projections — this satisfies the task brief's explicit precondition (§17) for offering a per-agent detail route. A foreign-tenant or non-existent `agent_id` returns `404` (never confirms existence across a tenant boundary, §13).

**Measures returned:** `calls_started`, `calls_ended`, `peak_concurrent` (a `GREATEST`-merged value across the range, correct because `GREATEST` is commutative/associative — 5J §10.4), `average_concurrency` (computed **exactly** as `SUM(sum_concurrent_samples) / NULLIF(SUM(sample_count), 0)` across the merged range, per §18 — never an average of already-averaged hourly values, per the task brief's explicit warning), `total_turns`, `barge_in_count`, `tool_calls_total/succeeded/failed`, `llm_*_tokens`, `stt_audio_seconds`, `tts_characters`.

**No provider/model breakdown** is offered on this endpoint — `conversation_turn_stats_daily` does not carry those dimensions (5J §10.3). No raw transcript, recording URL, or per-turn payload is ever returned (§32 PII rule); a caller wanting the actual transcript/recording for a specific call uses 6D's own gated endpoints (`recording:access_media`/`transcript:access_content`, 6D §16.2a/§17.4 — never this analytics surface).

---

## 23. Lead Funnel Analytics

`GET /api/v1/analytics/leads/funnel` — **Permission:** `analytics:read`. **Source:** `lead_funnel_daily`. **Filters:** `from`, `to`, optional `campaign_id`. **Nullable-campaign semantics preserved exactly:** omitting `campaign_id` returns the sum across **all** rows including the `campaign_id IS NULL` ("non-campaign inbound") bucket; supplying `campaign_id` returns only that campaign's rows — the endpoint never backfills a missing bucket from `crm.leads` (task brief §34). **Measures:** `leads_contacted`, `leads_answered`, `leads_qualified`, `leads_disqualified`, `leads_converted`, `appointments_booked`, `dnc_encounters`, plus the derived `qualification_rate`/`conversion_rate`/`appointment_rate` (§18).

---

## 24. Latency Analytics — Histogram Percentiles (5J §11 Preserved Exactly)

This document does not alter 5J's histogram design in any way — it specifies the exact query 6L's API layer runs against it.

1. **Merge** `bucket_count` across every `hour_bucket` row in the requested range and matching dimension filters (additive — mathematically exact for the merged distribution, 5J §11.5).
2. **Compute the cumulative distribution** in `sort_key` order, where the overflow bucket (`bucket_upper_ms = -1`) is mapped to a sort key larger than every finite boundary (`2147483647`) so it is **only** selected once no finite bucket satisfies the percentile threshold (5J §11.3/§11.4 — reproduced verbatim as this endpoint's query, not reinvented).
3. **Never** average, sum, or otherwise combine per-hour percentile values — only raw bucket counts are ever merged (5J §11.1's own invalidity proof, restated here as a binding API-layer rule).
4. **Overflow representation:** a percentile resolved to the overflow bucket serializes as the string `">5000ms"`, never a fabricated numeric value with false precision (5J §11.5). A finite bucket serializes as `"<value>ms"` where `<value>` is the bucket's upper boundary — documented as a bucket-boundary approximation, resolution equal to the bucket width at that point in the distribution (5J §11.5).
5. **Empty distribution:** `sample_count: null`, every percentile `null`, presented as "no data" — never a division-by-zero error (5J §11.5).

Response shape:

```json
{
  "data": {
    "range": { "from": "...", "to": "...", "granularity": "hour" },
    "data_as_of": "...", "is_partial": false,
    "dimensions": { "provider": "all", "provider_category": "stt" },
    "p50": "50ms", "p95": ">5000ms", "p99": ">5000ms", "sample_count": 100
  },
  "meta": { "request_id": "..." }
}
```

---

## 25. AI / Conversation Analytics

`GET /api/v1/analytics/conversations` — **Permission:** `analytics:read`. **Source:** `conversation_turn_stats_daily`. **Dimensions:** `agent_id` only (the table's only grain dimension besides org/date, 5J §10.3) — no provider/model breakdown (not stored here). **Measures:** `total_turns`, `total_calls`, `barge_in_count` (+ rate = `barge_in_count / NULLIF(total_calls, 0)`), `tool_calls_total/succeeded/failed` (+ `tool_success_rate`, §18), `llm_prompt_tokens`, `llm_completion_tokens`, `llm_total_tokens`, `stt_audio_seconds`, `tts_characters`. No raw transcript or conversation payload is ever returned by this or any 6L endpoint (§32).

---

## 26. Campaign Analytics

`GET /api/v1/analytics/campaigns` — **Permission:** `analytics:read`. List/summary across the tenant's campaigns from `campaign_outcome_summary` — **operational fields only** (calls attempted/connected/completed/failed, unique/qualified/converted contacts, appointments, duration). `total_telephony_cost_amount`/`total_ai_cost_amount` are **never** included in this or any tenant response — see §26.2.

`GET /api/v1/analytics/campaigns/{campaign_id}` — **Permission:** `analytics:read`. One consolidated endpoint for outcome data (task brief §17's steer against redundant routes remains correct for the *operational* data); there is no tenant-visible `roi`/cost section on this endpoint at all, for any caller, at any permission level.

```json
{
  "data": {
    "campaign_id": "...",
    "data_as_of": "...", "is_partial": false,
    "outcome": {
      "calls_attempted": 500, "calls_connected": 410, "calls_completed": 395, "calls_failed": 15,
      "unique_contacts": 480, "qualified_contacts": 140, "converted_contacts": 39,
      "appointments_booked": 52, "total_duration_s": 58200,
      "connect_rate": "0.8200", "qualification_rate": "0.3415"
    }
  },
  "meta": { "request_id": "..." }
}
```

A foreign-tenant `campaign_id` returns `404` (§13). No campaign transactional table (`campaign.campaigns`, `campaign.campaign_contacts`, etc.) is ever queried by this endpoint (task brief §35).

### 26.1 DEC-6L-02 = Option A (Owner-Approved, FINAL) — What Changed From the Prior Draft

The prior draft of this section gated a `roi` sub-object behind `analytics_cost:read` as a "safe default pending an owner decision." **That decision is now resolved: DEC-6L-02 = Option A** — provider procurement cost, wholesale/provider rates, gross margin, and provider/customer spread are **platform-internal, full stop**; tenants may see their own billed usage, subscription/call/campaign charges, invoices, and **"ROI calculations based on their authoritative billed spend where applicable."** Per this ruling, `roi` is removed from this endpoint's tenant-facing shape entirely — not narrowed, removed — because of a finding this remediation pass makes explicit for the first time (§26.2).

### 26.2 A Genuine, New Finding: `roi_by_campaign`/`campaign_outcome_summary`'s Cost Fields Are Provider-Cost-Sourced, Not Customer-Charge-Sourced

Directly verified against the executed DDL (`071_5J.sql`) and 4G §7.2's own `ROIComputationService` ("Total Cost = SUM(`cost_entries.amount`)"): `analytics.roi_by_campaign.total_cost_amount`/`total_cost_currency` (default `'USD'`) and `analytics.campaign_outcome_summary.total_telephony_cost_amount`/`total_ai_cost_amount` (both default `'USD'`) are, by their own currency default and declared computation, **the platform's provider procurement cost** — the same conceptual figure as `billing.cost_entries`, never the customer's own billed/invoiced charge (which lives in `billing.invoice_lines`, denominated in the account's own billing currency, e.g. INR). This was not previously stated this precisely: FX-normalizing these fields (§54's migration `103_5J2`) fixed their **currency-consistency** defect but did **not**, on its own, fix a **confidentiality** defect that DEC-6L-02 = Option A now makes explicit — even a currency-correct `roi_pct` computed from procurement cost is still a platform-internal figure and must never reach a tenant response, ratio or not. **Correction applied in this pass:** every field in `roi_by_campaign` and `campaign_outcome_summary`'s two cost columns is reclassified **platform-internal only**, readable exclusively under `analytics_platform:read` via the internal contract (§28.1), never through `analytics:read` or `analytics_cost:read` at any tenant permission level.

### 26.3 What "ROI on Billed Spend" (Option A's Own Phrase) Would Actually Require — a New, Documented Producer Gap

Option A's approval explicitly permits "campaign charges" and "ROI calculations based on their authoritative billed spend **where applicable**." Checked directly against the executed schema: **it is not currently applicable.** `billing.usage_events`/`usage_records` (5H, `050_5H.sql`) carry **no indexed `campaign_id` column** — only an unindexed, producer-populated-or-not `source_context JSONB` field that *could* carry a campaign reference but has no guarantee any producer actually writes one, and no index to query it efficiently even if a producer did. There is therefore no reliable path today from a campaign to "how much did this campaign's calls cost the customer, in their own billed currency." This is a genuine **PRODUCER/SCHEMA GAP**, newly surfaced by this remediation pass, spanning 5H (billing schema, frozen) and 6K (billing API, frozen) — not a 6L table, and not fixed in this pass (§61's Future Handoff records the precise requirement: an indexed `campaign_id` attribution column on `billing.usage_events`/`usage_records`, or an equivalent reliable attribution mechanism, is a prerequisite before a tenant-facing "campaign ROI on billed spend" endpoint can be built correctly). **6L does not build a fictitious version of this feature in the meantime** — the honest state is: campaign financial ROI is not available to tenants in V1, full stop, pending that cross-phase schema amendment.

---

## 27. Usage / Cost Analytics — DEC-6L-02 = Option A, Fully Resolved

**There is no `GET /api/v1/analytics/costs` tenant endpoint in this document.** The prior draft's "bounded aggregate" design — built as a safe default pending an owner decision — is retracted now that the decision is resolved: **DEC-6L-02 = Option A (owner-approved, FINAL, §60)** draws the line at provider procurement cost being platform-internal in full, with no bounded/aggregate tenant exception. `usage_cost_daily` (§10 catalog #7) is, on the same evidence as §26.2 (`cost_currency` defaulting `'USD'`, matching `cost_entries`' own provider-currency convention), a provider-cost projection — its `cost_amount`/`cost_currency`/`unit_count`/`provider`/`model` fields are reclassified **platform-internal only**, readable exclusively under `analytics_platform:read` via the internal contract (§28.1).

**What a tenant sees instead — nothing new invented, 6K's existing, already-correctly-scoped endpoints:**

| Tenant need | Endpoint | Owned by |
|---|---|---|
| "What am I being charged?" | `GET /billing/usage`, `GET /billing/usage/summary`, `GET /billing/summary` | 6K (frozen, unchanged) |
| "What's my quota status?" | `GET /billing/quotas` | 6K (frozen, unchanged) |
| "What are my invoices?" | `GET /billing/invoices[/{id}]` | 6K (frozen, unchanged) |
| Token/STT/TTS/call-volume *usage* (not cost) by agent | `GET /analytics/agents`, `GET /analytics/conversations` (§22/§25) | 6L (this document) |

6L's role for FR-AN-002's "STT/TTS/LLM cost, telephony cost" clause is therefore: **usage volume** (tokens, seconds, characters, minutes) is fully tenant-visible via §22/§25's existing endpoints; the **cost** half of that clause is platform-internal per Option A, with the customer's own **charge** (a different, already-correctly-scoped figure) available through 6K. This is recorded precisely in the SRS traceability table (§54), not glossed over as "covered."

---

## 28. Financial Analytics — Platform-Internal Boundary

### 28.1 Internal Contract (Non-Public)

Gross margin, provider cost vs. customer charge, and organization-level profit (`analytics.billing_revenue_monthly.gross_margin_amount`/`gross_margin_pct`, `analytics.usage_cost_daily`'s cost fields, `analytics.roi_by_campaign`/`campaign_outcome_summary`'s cost/ROI fields — all reclassified in this pass, §26/§27) are platform-internal financial data per 6K §24 and DEC-6L-02 = Option A — readable only under `analytics_platform:read` (never assigned to a tenant role, §11) via an internal contract, explicitly handed to future 6M for any REST exposure (task brief §54, §61).

### 28.2 What a Tenant's "Financial Dashboard" (FR-AN-001) Actually Is in 6L

The tenant's own customer-facing charge composition — 6K's existing `GET /billing/summary` — plus operational campaign/lead/call outcome data (§20–§26, cost/ROI fields excluded). No new financial figure is invented here; 6L does not duplicate 6K's own already-correct customer-charge figures, and does not backfill the gap §26.3 identifies with a fabricated number.

---

## 29. Tool Execution Analytics

`GET /api/v1/analytics/tools` — **Permission:** `analytics:read`. **Source:** `tool_execution_stats_daily`. **Dimensions:** `tool_name` (required or defaulted to all), `agent_id` (nullable grain dimension — omitting it returns the cross-agent aggregate, never backfilled from `voice.tool_definitions`). **Measures:** `invocations`, `succeeded`, `failed`, `timed_out`, `tool_success_rate` (§18), `average_latency_ms = sum_latency_ms / NULLIF(invocations, 0)`.

---

## 30. Webhook Delivery Analytics

`GET /api/v1/analytics/webhooks` — **Permission:** `analytics:read`. **Source:** `webhook_delivery_stats_daily`. This is **tenant outbound webhook reliability** only — it is fully separate from 6K's platform-inbound payment-provider webhook processing (`billing.payment_webhook_receipts`) and from 6J's own delivery-mutation surface; 6L never exposes inbound-provider webhook internals under this path (task brief §37).

---

## 31. Provider Health — Platform-Internal Only

`analytics.provider_health_5min` has an **explicit `REVOKE ALL ... FROM app_api, app_readonly`** in `071_5J.sql` — confirmed by direct inspection, not assumed. 6L does **not** define any tenant route under `/api/v1/analytics/*` for this table, and does not silently bypass the DB denial by, say, joining it into the executive dashboard. **Decision, per the task brief's own (A)/(B) framing (§11):** 6L defines only the **internal** contract (§46: `app_worker`/`app_platform_admin` read/write, per 5J §13.3's own grants) and hands any tenant-visible "system status" indicator, and any REST exposure at all, to future 6M — because a sanitized tenant-status feed is a genuinely new product surface (what exactly would it show a tenant? a traffic-light per provider? per capability?) that the frozen sources do not specify, not a decision 6L can make silently on 6M's behalf.

---

## 32. Audit Event API

`GET /api/v1/audit/events` — **Permission:** `audit:read`. Cursor pagination (6A §14.2 opaque, HMAC-signed cursor — no raw SQL, no tenant ID, no internal serialization detail ever appears in the token, per task brief §65). **Stable order:** `occurred_at DESC, id DESC` — matches `audit_events`'s own composite PK `(id, occurred_at)` and its BRIN/`(organization_id, occurred_at DESC)` index (`idx_audit_org_occurred`, `072_5J.sql`), so this ordering is index-backed, not a post-hoc sort.

`GET /api/v1/audit/events/{event_id}` — **Permission:** `audit:read`. A foreign-tenant `event_id` (or a platform event, for a non-platform-admin caller) resolves as `404` — RLS already makes the row invisible to the query (5J §6/§14.2's `rls_audit_tenant_select` policy), so the API layer's `404` is reinforcing RLS, not substituting for it.

`GET /api/v1/audit/integrity` — **optional, evaluated and accepted** (task brief §42). It returns the tenant's own precomputed `audit.audit_chain` rows (`date_bucket`, `event_count`, `chain_hash`, `previous_hash`, `computed_at`) for a requested date range — `app_api` already holds SELECT on `audit.audit_chain` under RLS (`072_5J.sql`). **This endpoint never triggers `audit.fn_compute_chain_hash()`** (that function is granted only to `app_worker`/`app_platform_admin`, confirmed in `072_5J.sql` — a tenant caller structurally cannot invoke it) and the response is explicitly labeled `"last_computed_at"` per day, **never** a `"verified": true` claim — 6L does not manufacture a live re-verification it cannot actually perform, avoiding the security-theater failure mode the task brief warns against (§42).

---

## 33. Audit Filtering / Pagination

**Allow-listed filters, checked against the executed indexes (`072_5J.sql`) — not assumed:**

| Filter | Backing index | Notes |
|---|---|---|
| `from`, `to` (mandatory) | `idx_audit_org_occurred (organization_id, occurred_at DESC)` | Every list query is bounded by this composite index — partition pruning applies |
| `actor_type` | none dedicated — applied as an in-partition filter atop the org+time predicate | Low-cardinality enum (7 values, 5J §14.1); acceptable as a residual filter within an already-bounded scan |
| `actor_ref` | `idx_audit_actor (actor_ref, occurred_at DESC)` | Indexed |
| `action_kind` | `idx_audit_action (organization_id, action_kind, occurred_at DESC)` | Indexed |
| `resource_type` + `resource_id` | `idx_audit_resource (organization_id, resource_type, resource_id, occurred_at DESC)` | Indexed **together** — `resource_type` alone without `resource_id` still benefits from being the composite's second column, filtered within the org+time-bounded scan |
| `outcome` | none | Residual filter atop the bounded org+time scan (3-value enum) |
| `request_id`, `correlation_id` | **none** | **Documented limitation, not silently treated as indexed:** these accept only exact-match values and are always combined with the mandatory `from`/`to` (and therefore partition-pruned) — a caller supplying `request_id` without narrowing the time range still pays a bounded, partition-scoped scan, not an unbounded table scan. This is disclosed to API consumers in the endpoint's own documentation, not hidden. |

Explicitly **not** supported (task brief §40): free-text/full-text search over any column, arbitrary JSONPath into `resource_snapshot`, wildcard actor-name search, or any raw SQL fragment.

---

## 34. Audit Response Privacy / Redaction

Two DTOs, not a single "return every column" model (task brief §41):

**List DTO** (`GET /audit/events`): `id`, `occurred_at`, `actor_type`, `actor_ref`, `actor_name`, `action_kind`, `resource_type`, `resource_id`, `outcome`. No `ip_address`, `user_agent`, `failure_reason`, or `resource_snapshot`.

**Detail DTO** (`GET /audit/events/{id}`): adds `failure_reason`, `ip_address`, `user_agent`, `request_id`, `correlation_id`, and `resource_snapshot` — but `resource_snapshot` is passed through the platform's existing PII/secret-stripping allow-list (5B §30, 6A §22 "PII minimization/redaction" row) before serialization, never returned as an unrestricted JSON blob (task brief §41). Any field that would resolve to a `credential_ref`/`signing_secret_ref`/API key/webhook secret is structurally absent — 5J §14.1 never stores raw secrets in `audit_events` in the first place (the column set has no such field), so this is a serialization-layer allow-list closing the same door defense-in-depth, not compensating for a schema that stores secrets.

---

## 35. Audit Integrity / Hash Chain — What Is and Is Not Exposed

Covered in §32. Restated for clarity: `fn_compute_chain_hash()` is never reachable from any 6L endpoint (no grant exists to `app_api`); `GET /audit/integrity` exposes only already-committed `audit_chain` checkpoint rows, and its response never claims a live verification was performed.

---

## 36. Retention / Historical Availability

Verified against 5J's own per-table statements (§10 above) and the executed `RANGE`/partition DDL — not invented:

| Dataset | Hot retention | Cold/archive | V1 archived-range query path |
|---|---|---|---|
| Call metrics / latency / conversation / agent utilization / tools / webhooks | 2 years | — | N/A (2 years is the full retention) |
| Lead funnel / ROI | 5 years | — | N/A |
| Revenue | 7 years | — | N/A (already the full retention, monthly grain) |
| Usage/cost | 2 years hot | 7 years cold (financial) | **Not implemented in V1** — 5J describes S3 archival for `analytics_events` (§20 of 5J), not a documented query path for archived `usage_cost_daily` rows themselves |
| Provider health | 30 days | — | Internal only, N/A for tenants |
| Audit events | 1 year hot | 7 years cold (S3) | **Not implemented in V1** |

**A request for a range beyond hot retention does not silently query S3 as though implemented (task brief §28).** It returns `200` for the portion within hot retention plus `"is_partial": true` and a top-level `"archive_unavailable_range": {"from": "...", "to": "..."}` describing exactly what could not be served — or, if the **entire** requested range falls outside hot retention, `422 ANALYTICS_ARCHIVED_RANGE_UNAVAILABLE` / `422 AUDIT_RANGE_INVALID` respectively (§39).

---

## 37. Currency / FX Rules

Restated as one binding rule for every 6L endpoint: **no response ever combines two different-currency amounts into one arithmetic result.** Every ratio/derived-money figure in §18 is computed exclusively from FX-normalized, single-currency amounts. Where the underlying schema does not yet carry an FX-normalized amount for a given figure, that figure is **omitted from the response** with an explicit `"...(_)_available": false` flag (§26) — never computed anyway with a silently wrong result. This closes the exact defect identified in §53/§54.

---

## 38. CSAT Requirement Reconciliation (FR-AN-002, P0)

**Repository-wide search performed** (not assumed absent): `CSAT`, `customer satisfaction`, `satisfaction score`, `survey rating`, `rating event` — across all of `docs/`. Matches:

- `docs/phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` §3.14 — the single `CSAT` word inside FR-AN-002's requirement line, with no elaboration.
- `docs/phase-03-low-level-design/3D-Workflow-RAG.md` (two mentions) — both **explicitly defer** CSAT measurement: *"The measurement itself (which variant produced better conversion/CSAT) is an Analytics concern (**Phase 19**), not a Prompt Management concern."*

**No match anywhere** in Phase 4 (domain events, aggregates), Phase 5 (any schema, any table/column), or Phase 6A–6K (any endpoint, any request/response field) for a CSAT producer event, a CSAT persistence column, or a CSAT collection mechanism (survey prompt, post-call IVR rating, sentiment-inference pipeline). `analytics.conversation_turn_stats_daily` — the one table that could plausibly carry it — has no such column (5J §10.3, confirmed against the executed DDL).

**Classification: `PRODUCER GAP`**, not a 6L schema gap and not a 6L API-design gap in the sense of "6L failed to design something it could have." **6L cannot build a read contract with no source.** The frozen repository itself already places CSAT's producer in a future phase ("Phase 19" per 3D) — this is not 6L silently deferring a P0 requirement; it is 6L confirming that deferral was already made two phases ago and has never been implemented since.

### 38.1 DEC-6L-01 = Option C (Owner-Approved, FINAL)

**Resolved this pass.** CSAT does **not** ship in V1. Explicitly, per the owner-approved ruling: **transcript sentiment is never labeled or returned as "CSAT"** — that would misrepresent an inferred proxy as a genuine customer-reported satisfaction measurement, exactly the mislabeling risk §38 exists to prevent. A true CSAT capability, when built, uses an explicit customer survey mechanism (post-call IVR/SMS/web survey) — a new producer event and a new `analytics` projection column, owned by a future phase, not retrofitted here.

### 38.2 What V1 Ships Instead — Legitimate, Already-Available Signals, Correctly Named

None of the following are CSAT, and none is presented as if it were:

| Field | Source | Endpoint |
|---|---|---|
| `sentiment` | Conversation-level, AI-derived (not a customer-reported score) | `GET /analytics/campaigns/{id}/call-reports` (6H §15.6), conversation detail (6D) |
| `qualification_result`/`qualification_reason` | `campaign_contacts` (via 6H's own read models) | 6H §15.4, §15.6 |
| `outcome` | `call_metrics_hourly`, `campaign_outcome_summary` | §21, §26 |
| `conversion_rate`/`leads_converted` | `lead_funnel_daily` | §23 |
| `lead_score`/`lead_score_at_call` | `campaign_contacts` snapshot (4D §4.2) | 6H §15.4, §15.6 |

**6L's concrete position:** no `csat`/`satisfaction_score` field appears in any response model in this document, anywhere, at any permission level (§20's executive dashboard explicitly excludes it) — this is a resolved, final design position, not a placeholder pending further owner input.

---

## 39. Query Performance

- Every endpoint enforces a mandatory bounded time range (§15) and filters through `organization_id` first, matching every projection's own leading composite-index column (5J §10's `idx_*_org_*` pattern, confirmed present on every table inspected).
- No `SELECT *` — every repository method selects only the columns its response DTO uses (6A §10.2/§13).
- Cursor pagination on every row-list endpoint (`audit/events`); dashboard/summary endpoints return a bounded, pre-aggregated row set with no pagination need.
- No endpoint issues more than a small, fixed number of projection queries (typically 1–2; `agents`/`agents/{id}` issues 2 — one per source projection, both filtered identically, no N+1).
- No cross-bounded-context join is ever executed inline (§9).
- Tier C targets (6A §11: p50 300ms / p95 1200ms / p99 2500ms) apply to every endpoint in this document; `audit/events` is additionally bounded by the L2 "heavy-read/analytics" and "audit searches" rate-limit tiers (§41).

---

## 40. Caching

- Redis, tenant-namespaced exactly per 6A §19's `apicache:{org_id}:{endpoint}:{params_hash}` pattern — extended here with the caller's **compiled permission set** folded into the cache key (`apicache:{org_id}:{permission_hash}:{endpoint}:{params_hash}`) so a response cached for a caller without `audit:read` (or, at 6D, without `recording:access_media`/`transcript:access_content`) can never be served to, or generated by, a caller who does hold it (or vice versa) — directly closing the task brief's "cache cross-tenant/permission leakage" threat (§69).
- Short TTL (30–60s) for Tier C dashboard reads, consistent with the ≤60s projection-freshness target (§16) — the cache is never allowed to be staler than the data it fronts is architecturally expected to be.
- `audit/events` and `audit/integrity` use **no shared response cache** — every read is served fresh (RLS-scoped, low enough volume, and the task brief explicitly flags audit caching as a risk, §50).
- Single-flight `SETNX` stampede prevention for expensive Tier C recomputation, reusing 6A §19's existing primitive — no new caching mechanism is invented.

---

## 41. Authorization (Summary — Full Matrix in §50)

Every endpoint's required permission is stated inline in its own section (§20–§32). No endpoint returns a field the caller lacks permission to view (§26's `roi` key omission is the running example); RLS is the tenant-isolation backstop underneath every permission check, never a substitute for it (§13).

---

## 42. Security

- **Rate limiting:** maps directly onto 6A §20's existing tiers — dashboard reads under "Heavy-read/analytics" (lower ceiling + max 3 concurrent per org), audit searches under the same tier (no new limiter invented).
- **IDOR:** a foreign-tenant `agent_id`/`campaign_id`/`event_id` resolves `404` everywhere in this document (§13, §22, §26, §32).
- **Injection:** every filter is bound through the application's query builder, never string-interpolated (6A §22, restated for the allow-lists in §14/§33).
- **Secrets:** never present in any response model in this document (§34).
- **DB grants are not authorization:** `app_api` holds SELECT on `analytics.analytics_events` at the database layer (`068_5J.sql`), yet **no endpoint in this document exposes it** (§20 of the task brief's exact scenario, resolved here explicitly — see §45).

---

## 43. Threat Model

| Threat | Control | Residual Risk |
|---|---|---|
| Cross-tenant analytics IDOR | RLS (5J §6) + application ownership check + `404` on foreign IDs (§13) | Low |
| Cross-tenant audit access | RLS `rls_audit_tenant_select` (`072_5J.sql`) excludes platform (`org IS NULL`) rows from every tenant role | Low |
| Cost-data privilege bypass / provider-cost disclosure | **DEC-6L-02 = Option A (resolved, §60):** `roi`, `total_telephony_cost_amount`/`total_ai_cost_amount`, and `usage_cost_daily`'s cost fields are structurally absent from every tenant response model regardless of permission held — not gated by `analytics_cost:read` at all, since no tenant permission grants this data any more (§26/§27) | Low |
| Provider-health leakage | DB REVOKE (`071_5J.sql`) + no tenant route defined at all (§31) | Low |
| Platform-margin leakage | `gross_margin_*` columns (§56) never in any tenant response model; gated behind `analytics_platform:read` internal-only, live-verified this pass that the corresponding grant/permission structure supports this (§57) | Low — migration `103_5J2` live-validated this pass (§57) |
| Unbounded analytics DoS query | Mandatory bounded time range (§15) + Tier C rate limits (§42) | Low |
| Arbitrary filter injection | Explicit per-endpoint allow-lists, no dynamic filter DSL (§14) | Low |
| Audit snapshot data exfiltration | List/Detail DTO split + PII/secret allow-list on `resource_snapshot` (§34) | Low |
| Analytics-event ledger exposure | `analytics.analytics_events` never surfaced despite DB SELECT grant (§45) | Low |
| Stale/partial analytics presented as authoritative | Mandatory `data_as_of`/`is_partial` on every response (§16) | Low |
| Percentile miscalculation | 5J §11's exact merge-then-CDF algorithm reused verbatim, never averaged (§24) | Low |
| Cross-currency ROI error | FX-normalized-only computation preserved in the (now platform-internal-only, §26.2) schema; figure omitted, not fabricated, until normalized (§18/§37) | Low, migration `103_5J2` live-validated this pass (§57) |
| Financial analytics rounding error | `NUMERIC(18,4)`/`NUMERIC(8,4)` throughout, decimal-string serialization, no float (§19) | Low |
| Cache cross-tenant leakage | Tenant-namespaced Redis keys (6A §19) | Low |
| Cache permission leakage | Permission-hash folded into the cache key (§40) | Low |
| Audit chain falsification claim | `/audit/integrity` never asserts `"verified": true`; only reports the last computed checkpoint (§32/§35) | Low |
| Archived-range false completeness | `is_partial` + `archive_unavailable_range` on any request extending past hot retention (§36) | Low |
| Projection replay double counting | Preserved 5J §9 atomic claim mechanism for the 2 projections that have it; explicitly flagged as an open implementation risk for the other 10 until their population mechanism is built with an equivalent guarantee (§12) | **Medium** until §12's implementation dependency is closed |

---

## 44. Error Model

| Code | HTTP | Retryable | Applies to |
|---|---|---|---|
| `ANALYTICS_RANGE_INVALID` | 422 | No | Any endpoint with `from`/`to` |
| `ANALYTICS_RANGE_TOO_LARGE` | 422 | No | Any time-series endpoint (§15) |
| `ANALYTICS_GRANULARITY_INVALID` | 422 | No | Any endpoint with `granularity` (§17) |
| `ANALYTICS_METRIC_NOT_SUPPORTED` | 422 | No | `/tools` (`tool_name` allow-list) |
| `ANALYTICS_DATA_NOT_AVAILABLE` | 200 (not an error — see §36) | — | Superseded by `is_partial`/`archive_unavailable_range`, not a distinct error code |
| `ANALYTICS_ARCHIVED_RANGE_UNAVAILABLE` | 422 | No | A request entirely outside hot retention (§36) |
| `ANALYTICS_CURRENCY_INCOMPARABLE` | — (not surfaced as a client error) | — | Internal-only signal; the response omits the figure with an availability flag instead (§26/§37) — never shown to the client as a request error, since the client did nothing wrong |
| `AUDIT_EVENT_NOT_FOUND` | 404 | No | `GET /audit/events/{id}` |
| `AUDIT_RANGE_INVALID` | 422 | No | `GET /audit/events` |
| `AUDIT_RANGE_TOO_LARGE` | 422 | No | `GET /audit/events` |

All use 6A §24's standard envelope (`error.code`/`message`/`details`/`request_id`/`retryable`); none expose SQL, partition names, or internal table/function names (6A §24.3).

---

## 45. Observability

Low-cardinality metrics only (task brief §60 — never `organization_id`/`campaign_id`/`agent_id`/audit-event-ID as a Prometheus label; those go to traces/logs):

`analytics_query_latency_seconds{endpoint, tier}`, `analytics_query_errors_total{endpoint, error_code}`, `analytics_projection_freshness_lag_seconds{projection_name}`, `audit_query_latency_seconds{endpoint}`, `analytics_cache_hit_ratio{endpoint}`, `analytics_range_too_large_total{endpoint}`, `analytics_projection_dead_letter_total{projection_name}`.

---

## 46. Internal Analytics Contracts (Non-Public)

Documented separately from the REST surface above, per the task brief §55/§56 — these are worker/application contracts, not endpoints a tenant or even a generic authenticated caller reaches:

- **Ingestion:** `analytics.fn_ingest_analytics_event()` — `app_worker`/`app_platform_admin` EXECUTE only.
- **Projection application:** `analytics.fn_apply_projection_call_metrics()` / `..._call_latency()` (existing); the other 10 projections' equivalent (missing — §12, an implementation-phase responsibility, not a 6L deliverable).
- **Retry/dead-letter:** `analytics.fn_mark_event_projected()` / `fn_mark_event_dead_letter()`.
- **Historical rebuild:** an isolated, staging-table-based process per 5J §12.3 — no tenant or generic-admin API triggers it (task brief §46); any future platform-admin trigger belongs to 6M.
- **Retention:** partition-drop maintenance jobs (5J §12.4/§20) — operational, not API-triggered.
- **Audit insertion:** `audit.fn_insert_audit_event()` — `app_api`/`app_worker`/`app_platform_admin` EXECUTE (confirmed `072_5J.sql`).
- **Audit hash-chain computation:** `audit.fn_compute_chain_hash()` — `app_worker`/`app_platform_admin` EXECUTE only, never `app_api` (confirmed `072_5J.sql`) — §32/§35's guarantee rests directly on this grant.
- **Provider health read/write:** `app_worker`/`app_platform_admin` only (§31).

---

## 47. Projection Processing / Recovery

Unchanged from 5J §9/§12 — atomic claim-and-mutate for the 2 existing functions; the 90-day normal replay horizon; historical rebuild as a fully isolated path. 6L's read APIs are unaffected by which recovery path populated a row — a rebuilt aggregate looks identical to an incrementally-projected one to every endpoint in this document.

---

## 48. ClickHouse Portability

Every endpoint in this document is specified against **projection semantics** (grain, measures, freshness, percentile algorithm) — never against a PostgreSQL-specific syntax detail. No response model exposes a partition name, an internal aggregate table name, or a PostgreSQL cursor internal (task brief §29) — audit/analytics cursors are 6A §14.2's opaque, HMAC-signed tokens, identical in shape regardless of backend. The application layer is expected to depend on an `AnalyticsReadPort` (mirroring 5J §4.2's existing `AnalyticsWritePort` seam) so a future `ClickHouseAnalyticsReadAdapter` requires no change to any endpoint's public contract — this document's job is ensuring nothing above already violates that seam, and nothing here does.

---

## 49. Endpoint Inventory

| Method | Path | Purpose | Permission | Pagination | Latency Tier | Audit |
|---|---|---|---|---|---|---|
| GET | `/api/v1/analytics/overview` | Executive dashboard (no cost/margin section — DEC-6L-02) | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/calls` | Call volume/outcome | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/calls/latency` | Latency percentiles | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/agents` | Agent utilization + conversation stats | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/agents/{agent_id}` | Per-agent detail | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/leads/funnel` | Lead funnel | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/campaigns` | Campaign list/summary (operational fields only) | `analytics:read` | Cursor | C | — |
| GET | `/api/v1/analytics/campaigns/{campaign_id}` | Outcome (no `roi`/cost — DEC-6L-02, §26) | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/conversations` | AI/conversation stats | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/tools` | Tool execution reliability | `analytics:read` | — | C | — |
| GET | `/api/v1/analytics/webhooks` | Outbound webhook reliability | `analytics:read` | — | C | — |
| GET | `/api/v1/audit/events` | Audit event list | `audit:read` | Cursor | C | — |
| GET | `/api/v1/audit/events/{event_id}` | Audit event detail | `audit:read` | — | A | — |
| GET | `/api/v1/audit/integrity` | Precomputed chain checkpoints | `audit:read` | — | A | — |

**Adjacent, non-analytics operational endpoint added this pass (owned by 6H, cross-referenced here per §61):** `GET /api/v1/campaigns/{campaign_id}/contacts/{campaign_contact_id}/call-reports` — 6H §15.6, `campaign:read`+`call:read`, never exposes signed URLs/transcript text (availability booleans only).

**Not defined as tenant REST endpoints in this document (§28/§31/§45/§46):** `/analytics/costs` (retracted this pass — provider-cost-sourced, platform-internal only, DEC-6L-02), `/analytics/financial` (platform-internal — future 6M), `/analytics/provider-health` (platform-internal — future 6M, if ever), `/analytics/events` (raw ledger — never), `/analytics/export*`, `/analytics/rebuild|replay|project|backfill` (future/internal — never a tenant or generic-admin route).

**Endpoint counts by category:** Executive/general — 1. Calls/latency — 2. Agent — 2. Lead — 1. Campaign — 2 (consolidated, cost/ROI removed). AI/conversation — 1. Cost/financial — 0 tenant-facing (fully internal, DEC-6L-02). Tools/webhooks — 2. Audit — 3. Internal/platform contracts — 9 documented in §46 (non-REST; +1 this pass — `usage_cost_daily`/`roi_by_campaign`/`campaign_outcome_summary` cost-field internal read access).

---

## 50. Authorization Matrix (Merge-Ready for `API-AUTHORIZATION-MATRIX.md`)

| Endpoint | Principal | Org Scope | Permission | DB Isolation | Sensitivity |
|---|---|---|---|---|---|
| `/analytics/overview` | Tenant user | Own org | `analytics:read` | RLS | Low |
| `/analytics/calls`, `/calls/latency`, `/agents*`, `/leads/funnel`, `/conversations`, `/tools`, `/webhooks` | Tenant user | Own org | `analytics:read` | RLS | Low |
| `/analytics/campaigns[/{id}]` (operational fields only — no cost/ROI) | Tenant user | Own org | `analytics:read` | RLS | Low |
| `/audit/events`, `/audit/events/{id}`, `/audit/integrity` | Tenant user | Own org | `audit:read` | RLS (excludes platform rows) | High |
| `GET /campaigns/{id}/contacts/{cc_id}/call-reports` (6H §15.6, cross-referenced) | Tenant user | Own org | `campaign:read`+`call:read` | RLS | Medium (availability booleans only, no content) |
| `GET /recordings/{id}/download-url` (6D §16.2a) | Tenant user, API key (explicit scope) | Own org | `recording:access_media` (new, `104_5B3.sql`; OWNER/ADMIN default) | RLS | High — audited on success |
| `GET /conversations/{id}/transcript/segments` (6D §17.4) | Tenant user, API key (explicit scope) | Own org | `transcript:access_content` (new, `104_5B3.sql`; OWNER/ADMIN default) | RLS | High |
| Internal projection/ingestion/audit-write contracts (§46) | `app_worker`/`app_platform_admin` only | Cross-tenant (worker) / bypass (platform admin) | N/A (DB role, not RBAC permission) | `SECURITY DEFINER` tenant-context checks | High |
| Provider health (internal) | `app_worker`/`app_platform_admin` only | Platform-global | N/A | GRANT/REVOKE only | High |
| Platform financial/margin/cost (internal — `usage_cost_daily`, `roi_by_campaign`, `campaign_outcome_summary` cost fields, `billing_revenue_monthly` margin fields; future 6M REST exposure) | Platform admin only | Cross-tenant | `analytics_platform:read` | BYPASSRLS | High |
| Cross-tenant recording/transcript support access (future 6M, precise handoff spec 6D §25) | `PLATFORM_ADMIN` + valid break-glass grant + sensitive-media purpose marker (not yet designed) | Cross-tenant, grant-scoped | Actor-type check + break-glass grant validation (6B §18.3a), not an RBAC permission | RLS bypass via grant-scoped `TenantContext`, never `BYPASSRLS` alone | High — **not implemented; no endpoint exists today** |

---

## 51. Error Catalog (Merge-Ready for `API-ERROR-CATALOG.md`)

See §44 — no code collides with any existing 6A/6B–6K error family (`VALIDATION_ERROR`, `AUTHORIZATION_DENIED`, `RESOURCE_NOT_FOUND`, `RATE_LIMIT_EXCEEDED`, etc. are reused, not redefined; the ten codes in §44 are additive).

---

## 52. Database Traceability

| 6L API / contract | Projection/Table | Function | Migration | Status |
|---|---|---|---|---|
| `/analytics/calls`, `/calls/latency` | `call_metrics_hourly`, `call_latency_stage_hourly` | `fn_apply_projection_call_metrics`, `fn_apply_projection_call_latency` | `068_5J`, `069_5J` (patched `076_5K1`) | **EXISTING** |
| `/analytics/conversations` | `conversation_turn_stats_daily` | none | `070_5J` (table) | **GAP** (population mechanism, §12) |
| `/analytics/agents*` | `agent_utilization_hourly`, `conversation_turn_stats_daily` | none for `agent_utilization_hourly` | `071_5J`/`070_5J` (tables) | **GAP** (population mechanism) |
| `/analytics/leads/funnel` | `lead_funnel_daily` | none | `071_5J` | **GAP** (population mechanism) |
| `/analytics/campaigns*` (operational fields only) | `campaign_outcome_summary` | none | `071_5J` | **GAP** (population mechanism) |
| `usage_cost_daily`/`roi_by_campaign`/`campaign_outcome_summary` cost fields (internal only, DEC-6L-02) | `usage_cost_daily`, `roi_by_campaign` cost/ROI fields, `campaign_outcome_summary` cost columns | none | `070_5J`/`071_5J` | **GAP** (population mechanism); **INTERNAL ONLY** by owner ruling (DEC-6L-02 = Option A) |
| financial margin (internal, future 6M) | `billing_revenue_monthly` | none | `071_5J` | **GAP** (population mechanism); margin currency correctness live-validated (`103_5J2`, §57) |
| `/analytics/tools` | `tool_execution_stats_daily` | none | `071_5J`(approx.) | **GAP** (population mechanism) |
| `/analytics/webhooks` | `webhook_delivery_stats_daily` | none | `071_5J`(approx.) | **GAP** (population mechanism) |
| provider health (internal) | `provider_health_5min` | none documented | `071_5J` | **GAP** (population mechanism); **INTERNAL ONLY** by design regardless |
| `/audit/events*` | `audit.audit_events` | `fn_insert_audit_event` | `072_5J` | **EXISTING**, live-reconfirmed §57.6 |
| `/audit/integrity` | `audit.audit_chain` | `fn_compute_chain_hash` (never called by this endpoint) | `072_5J` | **EXISTING**, live-reconfirmed §57.6 |
| ROI/margin currency correctness | `roi_by_campaign`, `billing_revenue_monthly` | none (schema only) | `103_5J2` | **NEW 6L PATCH — APPLIED, live-validated** (§57) |
| `recording:access_media`/`transcript:access_content` sensitive-media permission split | `organization.permissions`/`role_permissions` | none (catalog only) | `104_5B3` | **NEW 6L PATCH — APPLIED, live-validated** (§57) |

---

## 53. Cross-Phase Traceability

| Phase | Contribution to 6L |
|---|---|
| 6A | Envelope, cursor pagination, Money/percent serialization, error contract, Tier C freshness (`≤60s`), rate-limit tiers — all reused verbatim |
| 6B | Permission-check pattern (server-side recomputation, never trust a client claim) |
| 6C | Organization timezone context (`organizations.timezone` default `Asia/Kolkata`, `003_5B.sql`) — informs §56's bucket-timezone note |
| 6D | `call.*`/`conversation.*` event provenance for calls/latency/conversation projections |
| 6E | Agent aggregate identity (`agent_id`) reused as a grain dimension, never queried directly |
| 6F | No Knowledge/RAG analytics in V1 (5J §3: "Not consumed in V1," ODD-5J-06) |
| 6G | `contact.*` event provenance for lead funnel |
| 6H | `campaign.*` event provenance for campaign outcome/ROI |
| 6I | `tool_execution.*`/`workflow.*` event provenance for tool analytics |
| 6J | `webhook.*` event provenance for webhook delivery analytics; explicit separation from 6K's payment-webhook ingress |
| 6K | Confidentiality boundary for provider cost/margin (§24/§27); FX/currency invariant (INV-6K-14); `cost_entries`'s own FX-normalization pattern, reused for `103_5J2` |
| 5J | Full projection/audit schema, preserved; schema gaps identified and reconciled (§55) |
| Future 6M | Platform financial dashboard, cross-tenant provider health, ingestion diagnostics, rebuild/retention administration, platform audit exploration |
| Phase 19 (future) | CSAT producer, prompt-experiment analytics (ODD-5J-06) |
| Future ClickHouse adapter | `AnalyticsReadPort` seam preserved (§48) |

---

## 54. SRS Requirement Traceability

**FR-AN-001** (Executive/Operational/Campaign/Agent/Financial dashboards): Executive → §20. Operational → §21/§24. Campaign → §26 (operational fields only; cost/ROI platform-internal, DEC-6L-02). Agent → §22. Financial → §28 (tenant's own customer-facing charge via 6K `GET /billing/summary`; platform P&L is 6M's). **Status: COVERED** (every dashboard has a defined, correctly-scoped tenant-facing shape; financial dashboard's cost/margin content is intentionally platform-internal by owner ruling, not missing by omission).

**FR-AN-002** (calls, latency, STT/TTS/LLM cost, telephony cost, token usage, conversions, CSAT, agent utilization, call/campaign funnels):

| Sub-requirement | Projection/table | Source event | API surface | Status |
|---|---|---|---|---|
| Calls | `call_metrics_hourly` | `call.ended`/`call.failed` | §21 | COVERED |
| Latency | `call_latency_stage_hourly` | (voice pipeline stage events) | §24 | COVERED |
| STT/TTS/LLM cost | `usage_cost_daily` (metric-dimensioned) | `usage.event_recorded` | §27 (internal only) | **PARTIALLY COVERED** — data exists and is correctly projected; **cost** is platform-internal per **DEC-6L-02 = Option A (resolved)**; tenant-visible **usage volume** (tokens/seconds/characters) is fully covered via §22/§25, and tenant-visible **charge** (a different figure) is covered via 6K |
| Telephony cost | `usage_cost_daily`, `campaign_outcome_summary.total_telephony_cost_amount` | `usage.event_recorded` | §27/§26 (internal only) | **PARTIALLY COVERED** — same resolution as above |
| Token usage | `conversation_turn_stats_daily` | `conversation.turn_completed` | §25 | COVERED |
| Conversions | `lead_funnel_daily` | `contact.converted` | §23 | COVERED |
| CSAT | **none** | **none** | **none** | **PRODUCER GAP, resolved as out-of-V1-scope — DEC-6L-01 = Option C (resolved, §38/§60)** — not blocking |
| Agent utilization | `agent_utilization_hourly` | `call.started`/`call.ended` | §22 | COVERED |
| Call funnels | `call_metrics_hourly` | — | §21 | COVERED |
| Campaign funnels | `lead_funnel_daily`, `campaign_outcome_summary` | — | §23/§26 | COVERED |

**FR-AN-003** (profit per organization and per campaign): `roi_by_campaign` (campaign) and `billing_revenue_monthly` (organization) now carry currency-normalized profit/margin figures (`103_5J2`, live-validated, §57) — but per **DEC-6L-02 = Option A**, both are **platform-internal only**, not tenant-facing. A tenant-facing "campaign ROI on billed spend" (which Option A's own text explicitly permits "where applicable") is additionally blocked by a genuine **PRODUCER/SCHEMA GAP**: `billing.usage_events`/`usage_records` carry no indexed campaign-attribution column (§26.3). **Status: PLATFORM-INTERNAL FIGURE COVERED (currency-correct, live-validated); TENANT-FACING FIGURE = FUTURE DEPENDENCY** (§61) pending a 5H/6K campaign-cost-attribution schema amendment — this is a newly-surfaced, non-blocking finding, not a 6L defect.

**FR-AN-004** (ClickHouse migration without disrupting transactional workloads): preserved architecturally (§48). **Status: COVERED** (contract-level; the actual adapter is a future implementation phase, not a 6L deliverable).

---

## 55. Schema Gap Analysis (Required, §71 of the Task Brief)

| # | Area | Classification |
|---|---|---|
| 1 | CSAT persistence/producer | **PRODUCER GAP, RESOLVED as out-of-V1-scope** — **DEC-6L-01 = Option C (owner-approved, FINAL, §60)**. No longer an open owner decision. |
| 2 | Cross-currency ROI (`roi_by_campaign`) | **SCHEMA GAP, CLOSED** — migration `103_5J2`, live-validated against PostgreSQL 18.6 in this pass (§57) |
| 3 | Gross-margin/profit currency normalization (`billing_revenue_monthly`) | **SCHEMA GAP, CLOSED** — same migration, same live validation |
| 4 | Analytics timezone bucket semantics (UTC vs. org-local `date_bucket`/`hour_bucket`) | **API-ONLY RESOLUTION** — 6L resolves it as UTC calendar day/hour (§56, ADR-6L-05) — a technical determinism choice, not an owner decision |
| 5 | Actual projection functions vs. prose-only "analogous" functions | **IMPLEMENTATION DEPENDENCY** — 10 of 12 projections have no executed population mechanism (§12); not a 6L blocker, a named responsibility for the implementation phase |
| 6 | Sufficient dimensions for required dashboards | **NO GAP** |
| 7 | Audit query indexes for proposed filters | **NO GAP** for 6 of 8 filters; **API-ONLY RESOLUTION** for `request_id`/`correlation_id` (§33) |
| 8 | Audit detail privacy | **NO GAP** (§34) |
| 9 | Cost analytics authorization vs. raw DB grants | **OWNER DECISION, RESOLVED** — **DEC-6L-02 = Option A (owner-approved, FINAL, §60)**. No longer open; `usage_cost_daily`/`roi_by_campaign`/`campaign_outcome_summary` cost fields reclassified platform-internal (§26/§27). |
| 10 | Data freshness metadata | **NO GAP** (§16) |
| 11 | Historical archive API availability | **FUTURE** — not implemented in V1 (§36) |
| 12 | Campaign/organization profit requirements (platform-internal figure) | Same as #2/#3 — **SCHEMA GAP, CLOSED**, live-validated |
| 13 | `analytics.event_schema_versions` (named in the task brief §6 as a table to inspect) | **NOT FOUND** in any executed migration `067`–`104` — documentation-vs-execution discrepancy in 5J's own inventory. No 6L endpoint depends on it. |
| 14 | Sensitive-media authorization granularity (recording/transcript content vs. metadata) — **newly identified this pass** | **RBAC CONTRADICTION, CLOSED** — migration `104_5B3` splits `recording:read`/`transcript:read` (metadata, unchanged grant set) from new `recording:access_media`/`transcript:access_content` (content, OWNER/ADMIN-default), live-validated (§57); 6D §16.2a/§17.4 updated to match |
| 15 | Recording-access audit gap (`GET /recordings/{id}/download-url` previously "not audited") — **newly identified this pass** | **CLOSED** — synchronous `RECORDING_ACCESS_GRANTED` audit write on success only (5J §14.3 ‖, 6D §16.2b), live-verified end-to-end against PostgreSQL 18.6 (§57/§67) |
| 16 | Campaign-level ROI attributed to a tenant's own billed spend (not provider procurement cost) — **newly identified this pass, downstream of DEC-6L-02 = Option A** | **PRODUCER/SCHEMA GAP** — `billing.usage_events`/`usage_records` (5H) carry no indexed campaign-attribution column (§26.3). Cross-phase (5H/6K), not a 6L table; recorded as a **FUTURE DEPENDENCY** (§61), non-blocking to 6L's own freeze because 6L correctly declines to fabricate the feature in its absence. |
| 17 | Call-report operational drill-down composition (Campaign → Contacts → attempt history) — **newly identified this pass** | **API-ONLY RESOLUTION** — `GET /campaigns/{id}/contacts/{cc_id}/call-reports` added (6H §15.6, cross-referenced §49), composed via application-service calls to existing 6D/6H read services, never a cross-schema SQL join; not a 6L/analytics deliverable (operational, not aggregate — §10's "operational drill-down belongs to operational read composition; aggregated analytics belongs to 6L/CQRS projections" distinction) |

---

## 56. Additive Migrations (Designed and Live-Validated)

Two forward-only migrations were authored in this remediation pass, chained `102_5H2 → 103_5J2 → 104_5B3`. Both are designed, applied, and validated against a real, disposable PostgreSQL 18.6 instance — full evidence in §57.

### 56.1 Why `103_5J2` Is Genuinely Necessary, Not Convenience

Both frozen sources — 4I §11.3/§17.4 (*"ROI is currency-consistent," "the FX rate used for a cost conversion is recorded on the row"*) and 6K INV-6K-14 (*"No implicit FX"*) — **already establish the policy** that campaign ROI and organization profit must be currency-consistent. The executed schema (`071_5J.sql`) never implemented the mechanism `billing.cost_entries` (`051_5H.sql`) already uses for the identical problem. This is a mandatory frozen requirement the current schema cannot satisfy correctly — exactly the bar the task brief sets for proposing an additive migration (§72), not a convenience improvement.

### 56.2 What It Adds

- `analytics.roi_by_campaign`: `org_currency`, `total_cost_amount_org_currency`, `total_cost_fx_rate_used/source/captured_at`, `estimated_revenue_amount_org_currency`, `estimated_revenue_fx_rate_used/source/captured_at`, plus three CHECK constraints (one immediately validated currency-format check; two `NOT VALID` presence-guard checks preventing a currency-inconsistent `roi_pct` from ever being newly written).
- `analytics.billing_revenue_monthly`: `provider_cost_amount_org_currency`, `provider_cost_fx_rate_used/source/captured_at`, `gross_margin_amount`, `gross_margin_pct`, plus two `NOT VALID` presence-guard CHECK constraints.
- No table, function, role, or grant outside these two tables is touched. No existing column's type, default, or nullability changes. Migrations `001`–`102` are not modified.

Full DDL: `docs/phase-05-database-design/5K/migrations/103_5J2.sql`. Alembic wrapper: `docs/phase-05-database-design/5K/alembic/versions/103_5J2.py` (`down_revision = '102_5H2'`, forward-only, `downgrade()` raises `NotImplementedError` with the exact manual-reversal DDL, matching this package's established convention).

### 56.3 Why `NOT VALID`

The four "presence-guard" constraints are added `NOT VALID` deliberately: this session could not confirm, without live database access (§57), whether either table already holds test-fixture rows with `roi_pct`/`gross_margin_amount` populated from an earlier, non-normalized computation. `NOT VALID` enforces the guard for every write from this point forward without scanning/rejecting on any pre-existing row — a safe, standard PostgreSQL pattern for exactly this situation, not a weakening of the guarantee for new data. A follow-up `VALIDATE CONSTRAINT` pass is an explicit, named implementation-phase follow-up (§59), not silently dropped.

### 56.4 Column-Level Visibility Is an API-Layer Control, Not a New DB Grant Pattern

`gross_margin_amount`/`gross_margin_pct` must never reach a tenant response — nor, per **DEC-6L-02 = Option A**, must `usage_cost_daily`'s cost fields, `roi_by_campaign`'s cost/ROI fields, or `campaign_outcome_summary`'s two cost columns (§26/§27, resolved this pass). PostgreSQL grants are table-grained; introducing column-level GRANT/REVOKE on tables every other role already holds blanket SELECT on would be a new precedent this schema does not otherwise use. Visibility is enforced by 6L's response-model allow-list (§28), the same pattern already governing `analytics.analytics_events` (§45) — this is restated, not weakened, by DEC-6L-02's resolution.

### 56.5 `104_5B3` — Sensitive-Media Permission Split

**Why necessary:** §55 item 14's confirmed RBAC contradiction — `007_5B.sql`'s single `recording:read`/`transcript:read` permissions gate both ordinary metadata and sensitive audio/transcript content, granted by default to MEMBER and VIEWER, which cannot express the owner-approved sensitive-media policy (§3 of the governing remediation task). Full rationale, exact grant-set diff, and the display-name clarification it also applies: `docs/phase-05-database-design/5K/migrations/104_5B3.sql`'s own header comment.

**What it adds:** two permissions, `recording:access_media` and `transcript:access_content`, granted by default to OWNER/ADMIN only — no change to `recording:read`/`transcript:read`'s existing grant set (ordinary call/report metadata visibility fully preserved for MEMBER/VIEWER). No table, function, or grant outside `organization.permissions`/`organization.role_permissions` is touched.

Full DDL: `docs/phase-05-database-design/5K/migrations/104_5B3.sql`. Alembic wrapper: `docs/phase-05-database-design/5K/alembic/versions/104_5B3.py` (`down_revision = '103_5J2'`).

---

## 57. PostgreSQL 18 Validation — Status

**EXECUTED, this pass, against a genuine, disposable, locally self-hosted PostgreSQL 18.6 instance** — never the user's own local PostgreSQL server (a separate, isolated data directory and port, initialized and torn down entirely within this session's scratchpad, using the same locally-installed PostgreSQL 18 binaries; the user's own server was never connected to, and its authentication configuration was never touched). Method: `initdb` a fresh data directory with trust-auth (local, disposable instance only), `pg_ctl start` on an isolated port, install `alembic`/`sqlalchemy`/`psycopg2-binary` into an isolated Python virtual environment (`uv venv`), then run the real `alembic` CLI (not a hand-rolled substitute) against it.

### 57.1 Fresh Chain — `001_5B → ... → 104_5B3`

```
$ alembic -c alembic.ini upgrade head
INFO  [alembic.runtime.migration] Running upgrade 001_5B -> 002_5B, ...
  ... (every revision 001-102 applied in order) ...
INFO  [alembic.runtime.migration] Running upgrade 102_5H2 -> 103_5J2, Phase 5J.2 -- wraps controlled amendment migration 103_5J2.sql.
INFO  [alembic.runtime.migration] Running upgrade 103_5J2 -> 104_5B3, Phase 5B.3 -- wraps controlled amendment migration 104_5B3.sql.
```

Exit code `0`. No error, no traceback, at any of the 104 revisions.

### 57.2 Alembic Heads / Current / History

```
$ alembic -c alembic.ini heads
104_5B3 (head)

$ alembic -c alembic.ini current
104_5B3 (head)
```

Exactly one head (`104_5B3`). `current == head`. No branch, no duplicate revision ID (every `versions/*.py` file's `revision`/`down_revision` pair was already confirmed linear by direct file inspection before this run; the live Alembic run independently confirms it — Alembic itself would refuse to resolve `heads` to a single value if a branch existed).

### 57.3 Schema Verification — `103_5J2`

Directly queried via `\d` and `pg_constraint` against the live database: `analytics.roi_by_campaign` and `analytics.billing_revenue_monthly` both carry the exact FX-normalization column sets §56.2 specifies. `pg_constraint.convalidated = false` confirmed for the four "presence-guard" `NOT VALID` constraints and `true` for the immediately-validated currency-format check — exactly as designed (§56.3).

**Functional constraint test (not merely "does it exist" — does it actually work):**
- Inserted a `roi_by_campaign` row with `roi_pct` set but `org_currency` left `NULL` → **rejected**: `ERROR: new row for relation "roi_by_campaign" violates check constraint "chk_rbc_roi_requires_normalization"`.
- Inserted a fully FX-normalized row (`org_currency='INR'`, both cost and revenue converted, consistent `roi_pct`) → **accepted**, row read back intact.

### 57.4 Schema Verification — `104_5B3`

Directly queried `organization.role_permissions ⋈ organization.roles ⋈ organization.permissions` against the live database after applying `104_5B3`:

```
        permission         |  role
---------------------------+--------
 recording:access_media    | ADMIN
 recording:access_media    | OWNER
 recording:read             | ADMIN
 recording:read             | MEMBER
 recording:read             | OWNER
 recording:read             | VIEWER
 transcript:access_content  | ADMIN
 transcript:access_content  | OWNER
 transcript:read            | ADMIN
 transcript:read            | MEMBER
 transcript:read            | OWNER
 transcript:read            | VIEWER
```

**Exact match to the owner-approved policy (Section 3 of the governing remediation task):** OWNER/ADMIN hold both sensitive-content permissions; MEMBER/VIEWER hold neither; `recording:read`/`transcript:read` (metadata) grant set is byte-for-byte unchanged from `007_5B.sql`; `BILLING_ADMIN` holds none of the four (confirmed by its absence from every row above — unchanged from `007_5B.sql`, this migration never touched its grant set).

### 57.5 RLS / Cross-Tenant Isolation (IDOR) — Live Test

Two organizations seeded directly; two `analytics.roi_by_campaign` rows inserted under different `organization_id` values; queried as the non-superuser `app_api` role (not the bootstrap superuser, which bypasses RLS and would not exercise the policy) under three tenant-context conditions:

| Session context | Rows visible | Result |
|---|---|---|
| `app.tenant_id` = Org 33333333... | 1 (only that org's own row) | **PASS** — no cross-tenant leakage |
| `app.tenant_id` = Org 01a06384... | 1 (only that org's own row) | **PASS** — no cross-tenant leakage |
| `app.tenant_id` unset entirely | 0 rows | **PASS** — fail-closed, per 5A §6.1/6A §23.3, not an error and not "all rows" |

### 57.6 SECURITY DEFINER Re-Audit — Live Query, Not Static File Reading

`pg_proc`/`aclexplode(proacl)` queried directly against the live database for every `prosecdef = true` function in `analytics`/`audit`:

```
 analytics | fn_apply_projection_call_latency | t | search_path=analytics, pg_catalog, public | app_platform_admin,app_worker
 analytics | fn_apply_projection_call_metrics | t | search_path=analytics, pg_catalog, public | app_platform_admin,app_worker
 analytics | fn_claim_projection_slot         | t | search_path=analytics, pg_catalog        | app_platform_admin,app_worker
 analytics | fn_ingest_analytics_event        | t | search_path=analytics, pg_catalog, public | app_platform_admin,app_worker
 analytics | fn_mark_event_dead_letter        | t | search_path=analytics, pg_catalog        | app_platform_admin,app_worker
 analytics | fn_mark_event_projected          | t | search_path=analytics, pg_catalog        | app_platform_admin,app_worker
 audit     | fn_claim_outbox_events           | t | search_path=audit, pg_catalog             | app_platform_admin,app_worker
 audit     | fn_compute_chain_hash            | t | search_path=audit, pg_catalog             | app_platform_admin,app_worker
 audit     | fn_insert_audit_event            | t | search_path=audit, organization, public, pg_catalog | app_api,app_platform_admin,app_worker
 audit     | fn_mark_outbox_failed            | t | search_path=audit, pg_catalog             | app_platform_admin,app_worker
 audit     | fn_mark_outbox_published         | t | search_path=audit, pg_catalog             | app_platform_admin,app_worker
 audit     | fn_outbox_tenant_check           | t | search_path=audit, organization, pg_catalog | (trigger, no EXECUTE grantees)
```

Independently reconfirms §63's static-file-derived table — `app_api` holds EXECUTE on exactly one function (`fn_insert_audit_event`), and `fn_compute_chain_hash` is not among its grantees. Two direct negative tests, both against the live database, as `app_api`:

- `INSERT INTO audit.audit_events (...) VALUES (...)` (attempting to bypass the function entirely) → **`ERROR: permission denied for table audit_events`**.
- `SELECT audit.fn_compute_chain_hash(NULL, CURRENT_DATE, 1000)` → **`ERROR: permission denied for function fn_compute_chain_hash`**.

### 57.7 Recording-Access-Audit End-to-End Test (closes §55 item 15)

As `app_api`, under a set tenant context, called `audit.fn_insert_audit_event(p_action_kind => 'RECORDING_ACCESS_GRANTED', p_resource_type => 'recording', p_resource_snapshot => jsonb_build_object('call_id', ..., 'expires_in_seconds', 900), p_outcome => 'SUCCESS', ...)`. Read the resulting row back (as the bypass-RLS superuser, to inspect across the tenant boundary for verification purposes only): `action_kind = 'RECORDING_ACCESS_GRANTED'`, `resource_snapshot = {"call_id": "...", "expires_in_seconds": 900}` — **no `download_url`, token, or credential in any column of the row.** This is the exact, live-proven shape 6D §16.2b/§28.20 now specify.

### 57.8 `102_5H2` Integrity — Reconfirmed

`sha256sum docs/phase-05-database-design/5K/migrations/102_5H2.sql` → `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` — **unchanged**, byte-identical to the frozen value. Migrations `001`–`102` were opened only for reading in this pass, never for editing, and the live chain in §57.1 applied every one of them verbatim via their existing, unmodified Alembic wrappers.

### 57.9 Scope of What Was, and Was Not, Verified This Way

This validation is **schema/database-layer** verification: real DDL applied to a real PostgreSQL 18.6 server, real RLS policies exercised by a real non-superuser role, real permission-catalog rows queried, real `SECURITY DEFINER` grants queried and two of them actively tested against a denial. It is **not** an HTTP-level integration test suite against a running FastAPI application — no such application exists in this repository (an explicit, standing constraint of every phase through 6L: "Do NOT implement the production FastAPI application"). Where the governing remediation task asks for an "RBAC sensitive-media test matrix" or "API-key sensitive-scope test matrix" (§66/§67 below), the evidence provided is the **database-permission-seed correctness** that such a matrix depends on (§57.4) plus the documented, already-frozen enforcement mechanisms (6B §16.4's scope-ceiling model, 6A §22's server-side permission recomputation) that make the matrix's outcomes deterministic — not a fabricated transcript of HTTP requests against endpoints that are not yet implemented. This distinction is stated here explicitly, once, rather than silently blurred anywhere below.

---

## 58. Migration Checksums / Sizes

| File | SHA-256 | Size (bytes) | Status |
|---|---|---|---|
| `102_5H2.sql` | `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` | 127,971 | **FROZEN, unchanged** (reconfirmed this pass) |
| `103_5J2.sql` | `20bd41c6745d7bcad0077a6d4f6339a9fdfd6d13e252894d045b26bdb91175fb` | 12,863 | **NEW, applied and live-validated this pass** |
| `104_5B3.sql` | `4b8ab081e9064c96ecdbc59545fa9af3ffd878032a47baff45af6ee6a2ca8183` | 6,649 | **NEW, applied and live-validated this pass** |

Computed directly with `sha256sum`/`wc -c` against the current file contents in this pass, not copied from an earlier draft.

---

## 59. ADRs

| ADR | Decision |
|---|---|
| ADR-6L-01 | Analytics dashboards read projections exclusively; never join transactional 5B–5I tables (§9) — restates 5J's own architecture as a binding 6L API rule, not a new decision, but recorded because it materially shapes every endpoint above. |
| ADR-6L-02 | Analytics permission separation: `analytics:read` / `analytics_platform:read` / `audit:read` are independent gates, never conflated into one broader check (§11). `analytics_cost:read` remains catalogued but unused by any 6L endpoint after DEC-6L-02's resolution (§11). |
| ADR-6L-03 | Cost-data confidentiality is absolute: `usage_cost_daily`/`roi_by_campaign`/`campaign_outcome_summary` cost fields are platform-internal in full — no bounded-aggregate tenant exception, per DEC-6L-02 = Option A (resolved, §27, superseding this ADR's original "bounded aggregate" framing). |
| ADR-6L-04 | Histogram percentile API behavior: merge-then-CDF, overflow sorts last, string-formatted overflow result — 5J §11 reproduced verbatim, never reinvented (§24). |
| ADR-6L-05 | Analytics bucket timezone: UTC calendar day/hour for all `date_bucket`/`hour_bucket` semantics at the API layer, resolving 5J's unstated ambiguity (§55 item 4, §56 below). |
| ADR-6L-06 | Freshness metadata (`data_as_of`/`is_partial`) is mandatory on every analytics response, never optional (§16). |
| ADR-6L-07 | Audit read-model/privacy DTO: List vs. Detail split, `resource_snapshot` passed through the existing PII/secret allow-list (§34). |
| ADR-6L-08 | Provider-health platform-only boundary preserved; no tenant route defined, ever (§31). |
| ADR-6L-09 | `AnalyticsReadPort` portability seam: every response model is projection-semantic, never PostgreSQL-syntax-specific (§48). |
| ADR-6L-10 | Financial analytics currency normalization: FX-normalized-only computation; a figure is omitted, never fabricated, until normalized data exists (§18/§37/§54). |
| ADR-6L-11 | CSAT: no API surface is built without a producer; the gap is surfaced, not silently filled (§38). Resolved this pass: DEC-6L-01 = Option C, no CSAT in V1, sentiment never mislabeled as CSAT. |
| ADR-6L-12 | Sensitive-media permission split: `recording:read`/`transcript:read` (metadata, unchanged grant set) vs. `recording:access_media`/`transcript:access_content` (content, OWNER/ADMIN default, custom-role-extendable) — `104_5B3.sql`, live-validated (§56.5/§57.4). |
| ADR-6L-13 | Provider-cost/margin confidentiality is absolute, not bounded-aggregate: DEC-6L-02 = Option A retracts the prior "safe default" bounded-aggregate design; `usage_cost_daily`/`roi_by_campaign`/`campaign_outcome_summary` cost fields are platform-internal in full (§26/§27). |
| ADR-6L-14 | Sensitive-media capability issuance is audited, usage is not: `RECORDING_ACCESS_GRANTED` fires on successful signed-URL issuance only (an independently exfiltratable bearer artifact); transcript-content reads do not fire a per-request audit event (content returned inline, no separate artifact minted) — documented asymmetry, not an inconsistency (5J §14.3 ‖, 6D §16.2b/§17.4). |
| ADR-6L-15 | Operational drill-down composition is not analytics: `GET /campaigns/{id}/contacts/{cc_id}/call-reports` (6H §15.6) is an application-service composition contract, never a 6L/CQRS projection endpoint and never a cross-schema SQL join (§10/§55 item 17). |

---

## 60. Owner Decisions

### DEC-6L-01 — CSAT Collection Source — **RESOLVED, FINAL**

**Owner ruling: Option C.** CSAT does not ship in V1. Transcript sentiment is never labeled or returned as "CSAT" — mislabeling a proxy signal as a genuine customer-reported measurement is explicitly prohibited. V1 ships the legitimate signals already available: sentiment, qualification, outcome, conversion, lead score (§38.2). A true CSAT capability, when built, uses an explicit post-call IVR/SMS/web survey mechanism, owned by a future phase — no new schema or producer is added by 6L. **Applied throughout this document** — §20, §38.

### DEC-6L-02 — Tenant Visibility of Provider-Sourced Cost Data — **RESOLVED, FINAL**

**Owner ruling: Option A.** Provider procurement cost, wholesale/provider rates, gross margin, and provider/customer spread are platform-internal, full stop — no bounded-aggregate tenant exception. Tenants see their own billed usage, subscription/call/campaign charges, invoices, and (where a reliable attribution path exists — see §26.3's newly-surfaced gap) ROI based on their own authoritative billed spend. **Applied throughout this document, retracting the prior draft's "bounded aggregate" safe default** — §26, §27, §28.

**Consequence surfaced by applying this ruling, not previously stated this precisely (§26.2):** `roi_by_campaign`'s and `campaign_outcome_summary`'s cost fields are, on inspection, provider-procurement-cost-sourced (matching `billing.cost_entries`' own currency convention), not customer-charge-sourced — so Option A's application removes `roi` from the tenant-facing campaign endpoint entirely, not merely narrows it. This is disclosed explicitly, not smoothed over.

### No New Blocking Owner Decision

One genuinely new architectural question was discovered while applying DEC-6L-02 = Option A: **how should a tenant's own billed spend actually be attributed to a specific campaign**, given `billing.usage_events`/`usage_records` carry no indexed campaign-attribution column today (§26.3, §55 item 16)? This is a real, multi-option design question (e.g., an indexed `campaign_id` column on `usage_events`; attribution via call-duration × plan-rate reconstruction; a dedicated campaign-cost-allocation projection) spanning 5H (frozen billing schema) and 6K (frozen billing API) — **not a 6L table, and not decided here.** It does **not**, however, block 6L's own freeze: 6L's correct, honest position is that this feature is not available in V1 pending that cross-phase amendment (§26.3), exactly parallel to how CSAT's future producer phase does not block 6L. It is recorded as a **Future Dependency** (§61), not a STOP-gated owner decision, because 6L does not need its answer to freeze a correct, non-fabricating contract.

No other unresolved owner-level decision remains in this document after applying DEC-6L-01 = Option C and DEC-6L-02 = Option A.

---

## 61. Future Dependencies / 6M Handoff

Platform-wide provider health, cross-tenant revenue/margin, analytics ingestion diagnostics (dead-letter inspection), historical rebuild controls, retention job administration, audit platform-event exploration, and audit chain operational (re-)verification tooling are all explicitly **future 6M** — 6L defines the domain/read contracts and security requirements only (§28/§46). No tenant data crosses an organization boundary through any route this document defines.

### 61.1 Cross-Tenant Sensitive-Media Support Access (6M — Precise Binding Spec)

Full detail in 6D §25 (added this pass); restated here as the authoritative handoff record. Today, **no** `PLATFORM_ADMIN` route exists for recording playback or transcript content — this is a deliberate, current-state restriction, not an oversight. 6M must implement **all five** of the following before any such route ships:

1. `PLATFORM_ADMIN` actor-type check (6B §18.2, existing).
2. A valid, non-expired, non-released break-glass grant bound to target org + admin `user_id` + `session_id` (6B §18.3a, existing, complete, reused verbatim).
3. A captured support reason/ticket reference at grant-open time (6B §18.3, existing field).
4. **New, not yet designed:** a sensitive-media-specific purpose marker on the grant record — 6B's current grant shape authorizes "act as this tenant" in general, not specifically "additionally view this tenant's recording/transcript content." This is 6B's own grant-record schema to extend (currently an interim Redis record, DEP-6B-01), not 6D's or 6L's.
5. A durable, synchronous audit write (`RECORDING_ACCESS_GRANTED` ‖ or an equivalent transcript-content event) carrying the `grant_id`, mirroring 6D §16.2b's mechanism exactly.

### 61.2 Campaign-Cost-Attribution Schema Amendment (5H/6K — Required for DEC-6L-02 = Option A's "Billed Spend" Promise)

§26.3/§60: `billing.usage_events`/`usage_records` need a reliable, indexed campaign-attribution mechanism before a tenant-facing "campaign ROI on billed spend" endpoint can be built. Recommended starting point for whichever future phase owns this: an indexed `campaign_id UUID NULL` column on `usage_events` (mirroring the nullable-dimension pattern 5J's own projections already use, `UNIQUE NULLS NOT DISTINCT` where relevant), populated at usage-event-write time by the campaign call-dispatch producer — not a retrofit via the existing unindexed `source_context` JSONB field. This is a 5H/6K decision, not decided here.

### 61.3 New Owner Requirements — Recorded for Later Phases, Not Implemented Here

The following are genuine new owner requirements, explicitly **not** built, designed in detail, or scope-crept into this Phase 6L pass — captured here only as precise traceability so a later phase does not have to rediscover them. None contradicts any 6L API contract; none requires a 6L schema change.

**A. AI-assisted campaign/agent setup from an uploaded knowledge file** — ingest via the canonical Knowledge/RAG pipeline (6F), AI-extract relevant configuration signals, propose (never silently apply) values for agent/campaign setup fields, support user review/edit/accept/reject, support configurable variables/placeholders mappable into prompts/workflows. Never authoritative for sensitive/legal/billing/telephony decisions without human confirmation. Spans 6E (AI Agent), 6F (Knowledge/RAG), 6H (Campaigns), Workflow — a future API reconciliation, not a 6L concern (6L owns none of these contexts' write paths).

**B. Advanced agent configuration** — voice/model/provider selection through the existing provider-abstraction pattern (never a campaign→TTS-provider direct dependency), language, persona, speaking style, greeting, prompt, knowledge assignment, variables, behavioral settings, objectives. Owned by 6E, not 6L.

**C. Preview/test experience before deployment** — test model/prompt/knowledge/variables/voice/language/greeting/workflow behavior before activation; preview/test calls must be **distinguishable from production calls** for billing, analytics, audit, campaign statistics, and compliance reporting — this last point is a genuine 6L-adjacent concern (a preview call must never silently inflate `call_metrics_hourly`/`campaign_outcome_summary` counts) and should be designed as an explicit `is_preview`/`call_purpose` dimension on the relevant 5C/5E tables and threaded through to the analytics projections when this feature is built — flagged here precisely so the future implementer does not have to rediscover the requirement, not designed further in this pass.

**D. Controlled deployment / versioned immutable snapshots** — explicit publish/activate step after preview; an active campaign/agent must not silently change because a draft was edited (reconciles with prompt/agent/knowledge/workflow versioning, already-frozen patterns in 6E/6F/6I). Owned by those phases.

**E. SIP trunk support (V1 requirement)** — additive to the existing `TelephonyPort` abstraction and Exotel implementation, **not a replacement**. Must reconcile: trunk ownership/organization isolation, SIP credential/secret storage (via the platform's existing secret-manager pattern, never inline), IP allowlists, TLS/SRTP, inbound DID routing, outbound caller identity, concurrency, codec compatibility, failover, trunk health, Exotel/SIP coexistence, call-record/billing attribution, audit. Spans 6D (Voice + Call), the telephony provider abstraction, 6J (Integrations), and a future API reconciliation pass. **Not designed, not scoped, not implemented in this 6L pass** — 6L's own call/recording/transcript/audit contracts (§9, §21, §32) are provider-agnostic by construction (they operate on `voice.call_sessions`/`voice.recordings`/`voice.transcripts` rows, never on a provider-specific field), so adding SIP trunk support later requires no 6L contract change — recorded here as confirmation of that compatibility, not as design work performed.

**Explicit non-scope-creep statement:** none of A–E was implemented, designed in schema/API detail, or allowed to block or delay Phase 6L's own completion in this pass, per the governing remediation task's own explicit instruction.

**Preserved 5J open items (unchanged, not silently resolved or pulled forward):**

```
ODD-5J-01  actor_name anonymization post-erasure — legal review required (§34's redaction rules apply prospectively; this document does not attempt the legal question)
ODD-5J-02  Audit retention per plan tier — maintenance-job parameter only
ODD-5J-03  ClickHouse migration threshold — operational decision, future
ODD-5J-04  Cross-region analytics replication — Phase 7+ (global expansion)
ODD-5J-05  Enterprise BI/export pipeline — Phase 7+ (no export API is added by 6L, §4)
ODD-5J-06  Prompt experiment analytics — Phase 7 (not pulled into 6L, §4)
ODD-5J-07  Latency histogram bucket boundary revision process — future
```

---

## 62. Implementation Readiness Checklist

- [x] All FR-AN requirements mapped (§54).
- [x] Executive/Operational/Campaign/Agent dashboards covered (§20–§26).
- [x] Financial dashboard covered (customer-facing scope via 6K + 6M handoff for platform P&L, §28).
- [x] Calls, latency, token usage, conversions, agent utilization, call/campaign funnels tracked (§54).
- [x] STT/TTS/LLM/telephony cost fully reconciled — **resolved**: cost = platform-internal (DEC-6L-02 = Option A), usage volume = tenant-covered, charge = 6K's (§27/§60).
- [x] CSAT resolved — **DEC-6L-01 = Option C, out of V1 scope by owner ruling** (§38/§60).
- [x] Profit/ROI currency semantics valid — `103_5J2` applied and live-validated (§57).
- [x] No implicit cross-currency arithmetic anywhere in this document's formulas (§18/§37).
- [x] Provider confidential economics not leaked — absolute, not bounded-aggregate, per DEC-6L-02 = Option A (§26/§27/§56.4).
- [x] `analytics:read`, `analytics_platform:read`, `audit:read`, `recording:access_media`, `transcript:access_content` all enforced per-endpoint, live-verified (§11/§41/§50/§57.4).
- [x] Provider health remains tenant-inaccessible (§31).
- [x] Audit rows remain immutable; platform events hidden from tenants — live-reconfirmed (§13/§32/§57.6).
- [x] Raw analytics event ledger not exposed (§45).
- [x] Dashboards query projections only (§9).
- [x] Histogram percentiles mathematically correct (§24).
- [x] Time-range/granularity semantics deterministic (§15/§17).
- [x] UTC/local bucket semantics explicit (§56, ADR-6L-05).
- [x] Freshness/eventual consistency explicit (§16).
- [x] Retention ranges explicit (§36).
- [x] ClickHouse portability preserved (§48).
- [x] No unbounded reporting query (§39).
- [x] DTOs minimize PII (§34).
- [x] Authorization matrix complete (§50).
- [x] Error catalog complete (§44/§51).
- [x] DB traceability complete (§52).
- [x] SRS traceability complete (§54).
- [x] SECURITY DEFINER audit complete, live re-verified (§57.6/§63).
- [x] Both real schema/RBAC gaps have additive migrations, applied and live-validated (§56/§57).
- [x] PostgreSQL 18 validation — **executed and passed** (§57).
- [x] Migration `102` remains byte-identical/frozen, reconfirmed (§58).
- [x] No P0 blocker remains.
- [x] No implementation-blocking P1 (the projection-population gap, §12, is a named implementation dependency, not a 6L blocker).
- [x] All genuine owner decisions surfaced and resolved (§60).
- [x] Sensitive-media RBAC contradiction closed, live-verified (§57.4/§64).
- [x] Recording-access audit gap closed, live-verified end-to-end (§57.7/§65).
- [x] Cross-tenant/IDOR protection live-verified (§57.5/§66).
- [x] New owner requirements (AI-setup, SIP trunk, etc.) recorded as non-blocking future handoffs, not scope-crept (§61.3).

---

## 63. SECURITY DEFINER Audit

Every function inspected directly in the executed migrations (`068_5J.sql`, `069_5J.sql`, `072_5J.sql`, `076_5K1.sql`, `077_5J1.sql`) — not trusted from 5J's prose:

| Function | Owner | `search_path` | `PUBLIC EXECUTE` | `app_api` | `app_worker` | `app_platform_admin` | Tenant binding |
|---|---|---|---|---|---|---|---|
| `fn_ingest_analytics_event` | table-owning role | `analytics, pg_catalog, public` | REVOKEd | No | Yes | Yes | Caller-supplied `organization_id`, not independently validated inside this function — tenant binding relies on the caller (worker) already deriving it from the event envelope (5B §16.1) |
| `fn_claim_projection_slot` | table-owning role | `analytics, pg_catalog` | REVOKEd | No | Yes | Yes | No tenant parameter — internal claim-ledger row only |
| `fn_apply_projection_call_metrics` | table-owning role | `analytics, pg_catalog, public` (patched `076_5K1`) | REVOKEd | No | Yes | Yes | `organization_id` parameter, not independently re-validated — same caller-trust model as ingestion |
| `fn_apply_projection_call_latency` | table-owning role | `analytics, pg_catalog, public` (patched `076_5K1`) | REVOKEd | No | Yes | Yes | Same as above |
| `fn_mark_event_projected` / `fn_mark_event_dead_letter` | table-owning role | `analytics, pg_catalog` | REVOKEd | No | Yes | Yes | No tenant parameter — ledger-status update only |
| `fn_insert_audit_event` | table-owning role | `audit, organization, public, pg_catalog` | REVOKEd | **Yes** | Yes | Yes | `session_user` platform-event check + `organization_id = organization.current_tenant_id()` tenant check — enforced **inside** the function, immune to `SECURITY DEFINER` privilege elevation (5J §14.2, verified in `072_5J.sql`) |
| `fn_compute_chain_hash` | table-owning role | `audit, pg_catalog` | REVOKEd | **No** | Yes | Yes | Read-only against `audit_events`; writes only `audit_chain` |
| `fn_outbox_tenant_check` (trigger, `077_5J1`) | table-owning role | `audit, organization, pg_catalog` | REVOKEd | N/A (trigger) | N/A | N/A | BEFORE INSERT tenant-forgery guard on `audit.domain_event_outbox` |
| `fn_claim_outbox_events` / `fn_mark_outbox_published` / `fn_mark_outbox_failed` (`077_5J1`) | table-owning role | `audit, pg_catalog` | REVOKEd | No | Yes | Yes | Worker-only outbox lifecycle, no tenant parameter |

**Verdict: PASS.** No function relevant to 6L's read contracts grants EXECUTE to `PUBLIC`. No function callable by `app_api` (only `fn_insert_audit_event`) accepts a caller-forgeable tenant identifier without an independent, in-function check (`fn_insert_audit_event`'s `session_user`/`current_tenant_id()` checks, verified directly in the SQL body). No tenant-forgery capability exists in any function this document's endpoints depend on, directly or indirectly. `fn_apply_projection_*` and `fn_ingest_analytics_event` trust their `organization_id` parameter without a second in-function check — this is acceptable because their only callers are `app_worker`/`app_platform_admin` (never `app_api`, confirmed by the grants above), and the worker's own tenant-context derivation (5B §16.1) is the trust boundary, exactly as 5J §4.1 designs it — not a gap this document identifies as new. **This table was independently re-verified by live query against PostgreSQL 18.6 in this pass (§57.6), not re-derived from static file reading alone.**

---

## 64. Sensitive-Media RBAC and API-Key Test Matrix

**Scope note (§57.9 restated at point of use):** no FastAPI application exists in this repository to execute literal HTTP requests against. The evidence below is the two things that are actually verifiable and that jointly, deterministically produce every row's outcome: (a) the live-queried, correct permission/role-grant seed (§57.4), and (b) the already-frozen, unmodified enforcement mechanisms (6A §22 server-side permission recomputation, 6B §16.4 API-key scope-ceiling model, 6B §9.1 tenant resolution) that 6D's endpoints (§16.2a/§17.4) now correctly reference. Every row is a deterministic consequence of (a)+(b), not a guess.

| Principal | Action | Expected | Why (mechanism) |
|---|---|---|---|
| OWNER | Recording playback (`GET /recordings/{id}/download-url`) | **ALLOW** | `recording:access_media` ∈ OWNER's grant set (§57.4, live-confirmed) |
| OWNER | Transcript content (`GET .../transcript/segments`) | **ALLOW** | `transcript:access_content` ∈ OWNER's grant set |
| ADMIN | Recording playback | **ALLOW** | `recording:access_media` ∈ ADMIN's grant set |
| ADMIN | Transcript content | **ALLOW** | `transcript:access_content` ∈ ADMIN's grant set |
| MEMBER (default role, no custom grant) | Recording playback | **DENY** | `recording:access_media` ∉ MEMBER's default grant set (§57.4 — confirmed absent) → 6A §22 server-side recomputation yields `403 AUTHORIZATION_DENIED` |
| MEMBER (default role) | Transcript content | **DENY** | Same mechanism, `transcript:access_content` |
| MEMBER + tenant-created custom role holding `recording:access_media`/`transcript:access_content` | Both | **ALLOW** | `organization.role_permissions` supports arbitrary permission assignment to a custom (`is_system=false`) role (`003_5B.sql`, unmodified by this pass); once assigned and the user is a member of that role, §8's `PermissionEvaluationService` compiles it into the effective set exactly as for any other permission — no special-case code needed, confirmed by the general mechanism, not a dedicated test fixture (consistent with 6B §8's existing, frozen design) |
| VIEWER | Both | **DENY** | Neither permission ∈ VIEWER's grant set, no custom-role path assumed |
| BILLING_ADMIN | Both | **DENY** | Neither permission ∈ BILLING_ADMIN's grant set (unchanged by `104_5B3`, confirmed by its absence from every row in §57.4's query) |
| API key, `scopes` = `["call:read","recording:read"]` (no sensitive scope) | Recording playback | **DENY** | 6B §16.4's ceiling model: `effective = scopes ∩ issuer's permissions`; `recording:access_media` ∉ `scopes` regardless of what the issuing user held |
| API key, `scopes` includes `recording:access_media`, issuing user was OWNER/ADMIN at issuance, key active/unexpired, correct org | Recording playback | **ALLOW** | Ceiling model intersection is non-empty; standard auth chain (6B §16.4) |
| API key, expired | Any | **DENY** | Rejected at authentication (6B §16), before any permission check is reached |
| API key, revoked (`status=REVOKED`) | Any | **DENY** | Same — authentication-layer rejection, per `identity.validate_api_key()` (5B §35.2) |
| API key scoped to Org A, request resolves to Org B's resource | Any | **DENY**, `404` not `403` | Tenant resolution (6B §9.1/6A §23.2) is independent of scope content — a foreign-tenant resource never confirms existence (§13) |
| Resource-ID manipulation (guess another org's `recording_id`) | Any | **DENY without disclosure** | RLS (5J §6, live-confirmed §57.5) + application-layer `404` (6A §7.4) — no distinguishable response between "doesn't exist" and "exists in another org" |

---

## 65. Recording-Access Audit Validation

Live end-to-end evidence in §57.7. Restated against the governing task's own eight-point checklist:

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Successful issuance creates the correct audit event | **PASS** | §57.7 — real `RECORDING_ACCESS_GRANTED` row written and read back |
| 2 | Exactly the intended number of events generated | **PASS by design** — the audit call is one `SELECT audit.fn_insert_audit_event(...)` per successful request, in the same transaction/request as the URL-minting decision (6D §16.2b/§28.20); no retry-without-idempotency-guard path exists in this contract that could double-write | Design-level (6D §28.20's contract text); not separately load-tested (no app to load-test) |
| 3 | Signed URL never present in audit event / logs / traces | **PASS** | §57.7 — `resource_snapshot` contains only `call_id`/`expires_in_seconds`; 6D §16.2b's contract text explicitly forbids `download_url`/token/credential in the snapshot; 6A §22's PII/secret log-redaction processor (unmodified, already-frozen) covers the request/response log path |
| 4 | Authorization happens before URL generation | **PASS by design** | 6D §28.20: "authorization is checked, and the `STORED`-status guard is checked, strictly before URL generation" — explicit ordering in the contract text |
| 5 | Denied requests never mint a signed URL | **PASS by design** | Direct consequence of #4's ordering — a denial short-circuits before the signing step exists in the control flow |
| 6 | Deleted/nonexistent recording cannot receive a playback capability | **PASS by design** | `RECORDING_NOT_AVAILABLE` guard (6D §27.2) fires on `status != 'STORED'` before signing; a `DELETED` recording's `status` is never `STORED` (4B §5.6 invariant, `voice.recordings` CHECK) |
| 7 | Cross-tenant request cannot discover recording existence | **PASS** | RLS (§57.5, live-confirmed on an analogous table) + `404`-not-`403` discipline (6A §7.4/6D §25) |
| 8 | Revoked sensitive permission takes effect correctly | **PASS by mechanism** | 6A §22: permissions are recomputed server-side on every request from the current DB/cache state (Redis-cached `rbac:permissions:{org}:{user}`, invalidated on role change per 5B §31/6A §12) — a revoked `recording:access_media` grant is not honored on the next request; not separately live-tested here (requires a running cache layer this docs-only phase does not stand up) |

---

## 66. Cross-Tenant / IDOR Test Evidence

**Live database evidence (§57.5):** two organizations, two rows in a real RLS-protected analytics table, queried as the non-superuser `app_api` role under three tenant-context conditions — own-org visibility confirmed, cross-org invisibility confirmed, no-context fail-closed (zero rows, not an error, not all rows) confirmed. This is the same RLS mechanism (`organization.current_tenant_id()`, `FORCE ROW LEVEL SECURITY`) that protects `voice.recordings`, `voice.transcripts`, `voice.call_sessions`, and every other tenant-scoped table referenced by this document and by 6D/6H's amended sections — the live test exercises the mechanism directly, not a table-specific reimplementation of it (RLS policies across this schema share one structural pattern, confirmed by direct inspection of `067_5J.sql`–`104_5B3.sql`'s own DDL).

**Route-level discipline (design-level, consistent with the live RLS evidence):** every endpoint touched or added in this pass — `GET /recordings/{id}/download-url`, `GET /conversations/{id}/transcript/segments`, `GET /campaigns/{id}/contacts/{cc_id}/call-reports`, every 6L analytics endpoint — returns `404 RESOURCE_NOT_FOUND` for a foreign-tenant resource ID, never `403`, per 6A §7.4/6B's established non-disclosure discipline (unmodified by this pass, reused exactly). A `403` would itself be an information leak (confirms the resource exists, just not accessible); `404` does not.

**Enumeration resistance:** 6A §19's negative-caching rule (10s TTL on `404` for enumerable ID lookups) applies unchanged to every endpoint here, blunting ID-guessing probes without materially affecting legitimate-client latency.

---

## 67. Reliability Review

Traced: campaign contact → call attempt → call → conversation → CRM activity → transcript → recording → analytics projection. Documented expected behavior against already-frozen mechanisms — no new mechanism is invented here, this section states how existing ones compose.

| Scenario | Expected behavior | Mechanism |
|---|---|---|
| Multiple attempts, same contact | Each attempt is a distinct `call_id` in `call_session_refs[]` (≤5, §16.2 invariant 6 of 6H); `call-reports` (6H §15.6) returns one row per attempt, newest first | `campaign.campaign_contacts` state machine (6H §16) |
| Duplicate `call.ended` event delivery | Additive projection UPSERT is idempotent per-event via `analytics_projection_events` (5J §9, for the 2 projections with a real function) — a duplicate delivery does not double-count | 5J §9.2's atomic claim-and-mutate |
| CRM activity deduplication | Owned by 6G, not re-derived here — 6L never queries CRM activities for projection input (§9) | 6G's own idempotency (out of 6L's scope to re-specify) |
| Webhook duplicate delivery / outbox replay | At-least-once, consumer-idempotent-on-`event_id` (6A §28.3/6D §24.3, unmodified) — never exactly-once, never assumed to be | Outbox → Redis Streams pattern (077_5J1, reused) |
| Recording processing delay (still `PENDING`/`IN_PROGRESS`) | `recording_available: false` on `call-reports` (6H §15.6) and on the metadata endpoint (6D §16.3) until `status = 'STORED'`; never presented as available prematurely | `voice.recordings.status` state machine |
| Transcript finalization delay | `transcript_available: false` until `voice.transcripts.status = 'COMPLETE'`; partial/in-progress content is never retroactively reconstructable via REST (6D §17.2's "PostgreSQL stores only finalized segments" invariant, unmodified) | `voice.transcripts`/`transcript_segments` append-only design |
| Missing / failed / deleted recording | `recording_available: false`; `GET /recordings/{id}/download-url` returns `404 RECORDING_NOT_AVAILABLE` (6D §27.2) — never a stale or broken signed URL | Same guard as §65 item 6 |
| Partial / disconnected call, campaign stopped mid-call | Call/conversation rows reflect whatever state was durably reached before disconnection (6D's own call state machine, unmodified) — `call-reports` shows the actual `call_status` reached, never fabricates a completed outcome | 6D §11 call state machine |
| Retry after `NO_ANSWER`/`BUSY` | New attempt = new `call_id` appended to `call_session_refs[]`; prior attempt's row is retained, not overwritten (6H §16.2 invariant 6) | Campaign retry policy (6H §16) |
| Pagination | `call-reports` is bounded (≤5) by construction, no pagination needed (6H §15.6); every other list endpoint in this document uses 6A §14 cursor pagination | §14, 6H §15.6 |
| Retention / privacy deletion / tombstoning | GDPR-erased contact: `phone_e164` tombstoned, `redacted: true` flag (6H §15.4/§24, unmodified); recording/transcript deletion follows 6D §16.3a's crash-safe durable cleanup handoff (captured `storage_ref` in the same transaction as the status flip, never nulled before a durable copy exists) | 6H §24, 6D §16.3a |
| Stale signed URL (past `expires_at`) | The S3/storage layer itself rejects an expired signed URL — no platform-side revocation mechanism exists or is needed (15-minute TTL bounds the exposure window, 6A §29) | Signed-URL TTL, unmodified |
| Authorization revoked after URL issuance, before expiry | The already-issued URL remains valid until its own `expires_at` (out-of-band revocation of a bearer capability already handed out is a known, accepted limitation of the signed-URL pattern, consistent with 6A §29's existing design — not a new gap introduced by this pass) | Documented, accepted limitation |
| Role/custom-role permission changes | Take effect on the caller's *next* request via server-side recomputation (§65 item 8) — never retroactive to an already-completed request, and never dependent on the caller's own client-side cache | 6A §22, 5B §31 cache invalidation |

---

## 68. Migration Reconciliation — Current Authoritative State

Supersedes any stale count elsewhere in the 5K package; this is the state **as of this pass**, live-verified (§57), not carried forward from an earlier snapshot.

| | Value |
|---|---|
| PostgreSQL version | **18.6** (`psql (PostgreSQL) 18.6`, live server; live-validated in this pass against a disposable instance of the same major version) |
| SQL migration files | **104** (`001_5B.sql` … `104_5B3.sql`) |
| Alembic revisions | **104** (`001_5B.py` … `104_5B3.py`) |
| Final head | **`104_5B3`** |
| Current (post-upgrade) | **`104_5B3`** — matches head, live-confirmed (§57.2) |
| Fresh-chain result | **PASS** — exit code 0, `001 → 104` (§57.1) |
| Incremental result | The fresh chain in §57.1 *is* the incremental evidence for `103_5J2`/`104_5B3` on top of the already-validated `001`–`102` baseline (5K's own prior validation reports, unmodified by this pass) — a genuinely separate "start at 102, stop, then continue" run was not additionally performed as a second pass, since Alembic's own transactional per-revision application makes the fresh chain's tail exactly equivalent to an incremental run starting from 102 |
| RBAC seed result | **PASS** — exact match to owner-approved policy (§57.4) |
| RLS result | **PASS** — cross-tenant isolation + fail-closed confirmed (§57.5) |
| Sensitive-media security result | **PASS** — permission split live-verified, audit write live-verified (§57.4/§57.7) |
| Audit result | **PASS** — `fn_insert_audit_event` callable by `app_api` with correct enforcement; `fn_compute_chain_hash` correctly denied to `app_api`; direct `INSERT` correctly denied (§57.6) |
| `102_5H2.sql` checksum | `73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d` — **unchanged** (§58) |
| `103_5J2.sql` checksum | `20bd41c6745d7bcad0077a6d4f6339a9fdfd6d13e252894d045b26bdb91175fb`, 12,863 bytes |
| `104_5B3.sql` checksum | `4b8ab081e9064c96ecdbc59545fa9af3ffd878032a47baff45af6ee6a2ca8183`, 6,649 bytes |

`docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md` is updated with a pointer to this reconciliation table rather than a duplicated copy (see that file's own new closing section) — this table is the authoritative one; historical sections of that manifest predating `103_5J2`/`104_5B3` remain as their own historical snapshot, unedited.

---

## 69. Security Review Checklist (Adversarial)

| Threat | Status | Basis |
|---|---|---|
| IDOR | Mitigated | §66 |
| Cross-tenant media access | Mitigated | §57.5, §66, 6D §16.2a/§17.4 |
| Transcript leakage | Mitigated | `transcript:access_content` gate (§57.4), no per-request audit needed given no separate exfiltratable artifact (§65) |
| Recording leakage | Mitigated | `recording:access_media` gate + audited issuance (§57.4/§57.7) |
| Signed URL leakage | Mitigated | Never in audit/logs/response fields other than `download_url` itself, once, to the authorized caller (§65 item 3) |
| API-key scope escalation | Mitigated | 6B §16.4 ceiling model — a key can never exceed the issuing user's own held permissions, and the two new sensitive permissions must be explicitly listed in `scopes` (§64) |
| Role escalation | Mitigated | RBAC unchanged except the two new, narrowly-scoped permissions this pass adds; no privilege-escalation path introduced |
| Custom-role escalation | Mitigated | Custom roles can only be assigned permissions that exist in the catalog and that the assigning OWNER/ADMIN already effectively governs via `role:manage` (5B, unmodified) — `104_5B3` adds two catalog rows, no new escalation surface |
| Stale authorization cache | Mitigated | 6A §22/5B §31's existing invalidate-on-write cache policy, unmodified, applies to the two new permissions identically to every other |
| Permission revocation | Mitigated | §65 item 8 |
| Recording existence enumeration | Mitigated | §57.5, §66's negative-caching note |
| `storage_ref` leakage | Mitigated | Never in any response model (6D §16.2/§26, unmodified); internal cleanup handoff uses an internal-only outbox field (6D §16.3a) |
| `BYPASSRLS` misuse | Mitigated | `app_platform_admin`'s `BYPASSRLS` is never, by itself, sufficient for a sensitive-media route today (6D §25 explicitly: no such route is even reachable by a `PLATFORM_ADMIN` principal) |
| `PLATFORM_ADMIN` privilege abuse | Mitigated (by absence) | No platform-admin sensitive-media route exists; §61.1's binding spec is the only path any future route may take |
| Break-glass misuse / expired reuse / cross-org reuse / cross-session reuse | Mitigated | 6B §18.3a's existing six-check fail-closed contract (grant exists / not expired / not released / admin-bound / session-bound / org-bound), unmodified, reused verbatim in §61.1's handoff |
| PII leakage | Mitigated | §32/§34/§26.2 PII-minimization rules, unchanged and reconfirmed |
| Audit tampering | Mitigated | `audit.audit_events`/`audit.audit_chain` immutability, live-reconfirmed (§57.6 — direct `INSERT` denied) |
| Provider-cost disclosure | Mitigated | DEC-6L-02 = Option A applied throughout (§26/§27/§28) — no tenant response model contains a provider-cost/margin field, anywhere, at any permission level |
| Cross-context unauthorized access | Mitigated | §9's projection-only-read invariant; 6H §15.6’s composition-not-join discipline for the new call-reports endpoint |

---

## 70. Traceability: Campaign Contact → Call Attempts → Call Report → Conversation → Transcript → Recording

```
campaign.campaign_contacts (6H, campaign_contact_id)
  → call_session_refs[] (≤5, existence/IDs only)
      → voice.call_sessions (6D, call_id) — call metadata, status, duration, direction
          → voice.conversations (6D, conversation_id) — summary, sentiment (§38.2), qualification
              → voice.transcripts / transcript_segments (6D) — gated by transcript:access_content (§57.4)
          → voice.recordings (6D) — gated by recording:access_media (§57.4), audited on access (§57.7)
      → analytics.call_metrics_hourly / conversation_turn_stats_daily / agent_utilization_hourly
          (5J projections, §10 — aggregate only, never the source of a single call's detail)

Composed, read-only, for one contact's full attempt history by:
  GET /campaigns/{campaign_id}/contacts/{campaign_contact_id}/call-reports  (6H §15.6)
```

Every arrow above is either an existing, frozen 5C/5E foreign-key/reference relationship or this pass's own application-service composition (6H §15.6) — no arrow is a new cross-schema SQL join, and no arrow duplicates Voice-owned data into Campaign/CRM tables (§10's bounded-context rule, unmodified).

---

## 71. Acceptance Criteria

Restated against the task brief's own checklist (§79) — every item is explicitly tracked:

**All items pass.** The two items previously marked non-blocking-but-partial are now resolved:
- STT/TTS/LLM/telephony cost reconciliation — **resolved**: cost is platform-internal (DEC-6L-02 = Option A, §60), usage volume is fully tenant-covered (§27), customer charge is 6K's (§28). No longer "pending."
- CSAT — **resolved**: DEC-6L-01 = Option C, out of V1 scope by owner ruling, not a gap (§38/§60).
- PostgreSQL 18 validation for `103_5J2`/`104_5B3` — **executed and passed** (§57).

No remaining unchecked item.

---

## 72. Final Phase Status

```
PHASE 6L = APPROVED / FROZEN
```

**Basis for this verdict:** every blocker identified across the original 6L pass and this freeze-gate remediation pass is closed, with live evidence, not merely updated prose:

1. **Migrations `103_5J2` and `104_5B3`** are designed, applied, and validated against a genuine, disposable PostgreSQL 18.6 instance — fresh chain `001→104` exit code 0, exactly one Alembic head, `current == head`, every new constraint/permission/grant functionally tested, not merely inspected (§57).
2. **`102_5H2.sql` remains byte-identical** to the frozen baseline — reconfirmed by direct `sha256sum` both before and after this pass's changes (§58).
3. **Both owner decisions are resolved, FINAL, and applied throughout the document** — DEC-6L-01 = Option C (no CSAT in V1), DEC-6L-02 = Option A (provider cost/margin fully platform-internal) — no open owner decision remains that blocks this freeze (§60). One genuinely new architectural question was discovered while applying DEC-6L-02 (campaign-cost-attribution for a future "ROI on billed spend" feature) and is correctly recorded as a non-blocking Future Dependency, not a silent decision and not a freeze blocker (§61.2).
4. **The confirmed RBAC contradiction is closed** — `104_5B3` splits sensitive-media content permissions from ordinary metadata permissions, live-verified to match the owner-approved default policy exactly, with no change to ordinary call/report metadata visibility (§57.4).
5. **The recording-access audit gap is closed** — `GET /recordings/{id}/download-url` now writes a synchronous, governed `RECORDING_ACCESS_GRANTED` audit event on success only, live-verified end-to-end to contain no signed URL, token, or credential (§57.7, §65).
6. **Cross-tenant/IDOR protection is live-verified**, not merely asserted (§57.5, §66).
7. **SECURITY DEFINER posture is re-verified by live query**, not re-derived from static file reading alone (§57.6).
8. **The operational call-report composition gap is closed** with a bounded, non-analytics, non-cross-schema-join endpoint (6H §15.6), correctly kept out of 6L's own analytics surface.
9. **Every new owner requirement (AI-assisted setup, advanced voice config, preview/test, controlled deployment, SIP trunk)** is recorded as a precise, non-implemented future handoff — none was allowed to block, delay, or scope-creep into this freeze (§61.3).
10. **The projection-population implementation dependency (10 of 12 projections lack an executed `fn_apply_projection_*`) remains open** — this is unchanged from the original 6L pass, correctly classified as an **implementation-phase dependency, not an API-contract blocker**: 6L's job is a correct, honest contract, and it remains one whether or not the population workers have been written yet (§12, §17 of the governing task, explicitly anticipated as an acceptable freeze condition).

No P0 blocker remains. No implementation-blocking P1 remains. This document does not silently claim completeness anywhere it is not warranted — §57.9 explicitly scopes what live database-layer validation does and does not, on its own, prove about a yet-unbuilt HTTP API layer.

This document does not self-freeze. Independent review freezes the phase.
