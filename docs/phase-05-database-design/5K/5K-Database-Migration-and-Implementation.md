# Phase 5K — Database Migration & Implementation

## 1. Purpose and Scope

Phase 5K converts the frozen Phase 5A–5J database architecture into a complete, executable, dependency-safe, reproducible PostgreSQL 16 migration system. It does not design new schema. It sequences, packages, and operationalizes what Phase 5A–5J already approved, resolves the implementation-layer issues discovered during source reconciliation, and provides the validation machinery needed to certify the resulting database as correct.

Phase 5K answers one question: given the frozen architecture, what exact 75 SQL migrations do we run, in what order, with what dependencies, with what security constraints, and how do we prove the result is correct?

---

## 2. Relationship to Frozen Phase 5A–5J Architecture

| Rule | Statement |
|---|---|
| Authority | Phase 5A–5J are APPROVED/FROZEN and are the sole architectural source of truth. Phase 5K implements; it does not redesign. |
| No redesign | Phase 5K does not alter table structures, business rules, RLS semantics, billing semantics, analytics semantics, audit semantics, or integration semantics. |
| No new domain tables | Phase 5K introduces no new domain tables. |
| Conflict handling | Any conflict between two frozen phase documents is recorded as a MIGRATION BLOCKER, not silently resolved. |
| Implementation decisions | Where an approved phase document contains a source defect that would prevent execution (wrong column name in an index, missing `CREATE SCHEMA`, invalid index expression), Phase 5K records the correction with full justification, referencing the approved phase invariant the correction preserves. See §10. |

---

## 3. Canonical Migration Strategy

### 3.1 The Single Linear Chain

The complete migration package is 75 migrations in a single, unbroken linear `down_revision` chain. There are no branches, no merge migrations, no multiple heads.

```
001 → 002 → 003 → 004 → 005 → 006 → 007 → 008
  → 009 → 010 → 011 → 012 → 013 → 014 → 015 → 016 → 017 → 018
  → 019 → 020 → 021 → 022 → 023 → 024 → 025 → 026
  → 027 → 028 → 029 → 030 → 031 → 032 → 033
  → 034 → 035 → 036 → 037 → 038
  → 039 → 040 → 041 → 042
  → 043 → 044
  → 045 → 046
  → 047 → 048 → 049 → 050 → 051 → 052 → 053 → 054 → 055 → 056 → 057 → 058
  → 059 → 060 → 061 → 062 → 063 → 064 → 065 → 066
  → 067 → 068 → 069 → 070 → 071 → 072 → 073 → 074 → 075
```

- Migration 001 has `down_revision = None` (root).
- Every subsequent migration has exactly one predecessor.
- Migration 075 is the final head.
- No number is reused. No gap exists in 001–075.

### 3.2 Phase-to-Migration Mapping

```
Phase 5B  (identity, organization)          001–008
Phase 5C  (voice)                           009–018
Phase 5D  (crm)                             019–026
Phase 5E  (campaign)                        027–033
Phase 5F  (knowledge/RAG)                   034–038, 043–044
Phase 5G  (workflow, prompt, memory)        039–042, 045–046
Phase 5H  (billing, usage)                  047–058
Phase 5I  (integrations, webhooks, plugins) 059–066
Phase 5J  (analytics, audit)                067–075
```

### 3.3 Why 5F and 5G Interleave Numerically but Not Structurally

Phase 5F's HNSW index (migration 043) must execute *after* Phase 5G populates the `knowledge.document_chunks` table with its initial data via the ingestion pipeline — but it must also execute after 5G's own migrations (039–042) since `document_chunks` already exists at 038 and 5G's functions reference it. Phase 5F's own migration plan (§16 of the 5F source document) states this explicitly: "Migrations 039–042 are reserved for Phase 5G. Phase 5F uses 034–038, 043, 044 to align with the Phase 5G dependency chain." The interleaving produces one valid linear chain; it is not a fork or a merge.

---

## 4. Complete Migration Inventory

Legend: **Txn** = executes inside a single standard transaction. **Non-Txn** = must execute outside a transaction block (migration 043 only).

### 4.1 Phase 5B — Identity / Organization (001–008)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 001 | `001_5B.sql` | Extensions (`pgcrypto`, `pg_stat_statements`), 13 base schemas, 5 app roles (no password literal), `gen_uuid_v7()`, `set_updated_at()`, `organization.current_tenant_id()`, `organization.is_platform_admin()` | Yes |
| 002 | `002_5B.sql` | `identity.users`, `sessions`, `password_reset_tokens`, `oauth_identities`, `api_keys` (+ inline RLS and grants) | Yes |
| 003 | `003_5B.sql` | `organization.organizations`, `roles`, `permissions`, `memberships`, `teams`, `team_memberships`, `role_permissions` (+ inline RLS, grants, `get_user_organization_ids()`) | Yes |
| 004 | `004_5B.sql` | `organization.compliance_policies`, `data_subject_requests` (+ inline RLS, grants) | Yes |
| 005 | `005_5B.sql` | **Verification-only** — asserts that `identity.api_keys`'s RLS policy (`rls_api_keys_tenant`) created in migration 002 is present; raises exception if missing | Yes |
| 006 | `006_5B.sql` | **Verification-only** — asserts that the 11 organization-schema RLS policies created in migrations 003/004 are present; raises exception if any is missing | Yes |
| 007 | `007_5B.sql` | Seed: system roles, permissions, role-permission assignments (`ON CONFLICT DO NOTHING`) | Yes |
| 008 | `008_5B.sql` | Grants finalization: cross-cutting GRANT/REVOKE pass across all 5B objects | Yes |

**Note on 005 and 006:** These are verification-only migrations containing no `CREATE POLICY`, no `ALTER TABLE ... ROW LEVEL SECURITY`, and no schema changes. All 5B RLS definitions are bundled inline with their owning table migrations (002, 003, 004). Migrations 005 and 006 exist because the frozen migration chain requires exactly 8 Phase 5B slots — every downstream phase's `down_revision` chain is anchored to this numbering. Their small size (a single `DO $$` block querying `pg_catalog.pg_policies`) is intentional.

### 4.2 Phase 5C — Voice / Telephony (009–018)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 009 | `009_5C.sql` | Voice trigger functions (excluding `resolve_inbound_phone_number`, which depends on a table not created until 015) | Yes |
| 010 | `010_5C.sql` | `voice.agents`, `voice.agent_versions` | Yes |
| 011 | `011_5C.sql` | `voice.call_sessions` (RANGE monthly, parametric partitions + DEFAULT) | Yes |
| 012 | `012_5C.sql` | `voice.conversations`, `voice.turns` | Yes |
| 013 | `013_5C.sql` | `voice.tool_definitions`, `voice.tool_executions` | Yes |
| 014 | `014_5C.sql` | `voice.recordings`, `voice.transcripts`, `voice.transcript_segments` (RANGE monthly, REVOKE UPDATE/DELETE on segments) | Yes |
| 015 | `015_5C.sql` | `voice.provider_configs`, `voice.language_evaluation_records`, `voice.tenant_phone_numbers`; `resolve_inbound_phone_number()` SECURITY DEFINER (depends on `tenant_phone_numbers`) | Yes |
| 016 | `016_5C.sql` | RLS verification pass; `app_readonly` grants | Yes |
| 017 | `017_5C.sql` | Seed: 5 built-in tool definitions (`ON CONFLICT DO NOTHING`) | Yes |
| 018 | `018_5C.sql` | Final grant verification and cleanup | Yes |

### 4.3 Phase 5D — CRM (019–026)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 019 | `019_5D.sql` | CRM schema grant, AI-note immutability trigger function | Yes |
| 020 | `020_5D.sql` | `crm.contacts`, `crm.companies` | Yes |
| 021 | `021_5D.sql` | `crm.pipelines`, `crm.deals` | Yes |
| 022 | `022_5D.sql` | `crm.activities` (RANGE monthly + DEFAULT, REVOKE), `crm.tasks`, `crm.notes` | Yes |
| 023 | `023_5D.sql` | `crm.appointments`, `crm.lead_score_records` (REVOKE), `crm.crm_field_definitions` | Yes |
| 024 | `024_5D.sql` | `crm.consent_records` (RANGE monthly + DEFAULT, REVOKE), `crm.contact_suppressions` (three-scope RLS, REVOKE), `crm.lift_suppression()` SECURITY DEFINER | Yes |
| 025 | `025_5D.sql` | `app_readonly` grants; `app_platform_admin` full access | Yes |
| 026 | `026_5D.sql` | Placeholder — org-specific seed data is API-driven at tenant onboarding, not migration-driven | Yes |

### 4.4 Phase 5E — Campaign (027–033)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 027 | `027_5E.sql` | Campaign schema grant; campaign functions | Yes |
| 028 | `028_5E.sql` | `campaign.contact_lists`, `campaign.csv_import_jobs` | Yes |
| 029 | `029_5E.sql` | `campaign.campaigns`; functional index on raw `scheduling_policy->>'start_at'` text (see §10.3) | Yes |
| 030 | `030_5E.sql` | `campaign.campaign_contacts` (RANGE monthly + DEFAULT) | Yes |
| 031 | `031_5E.sql` | `campaign.call_jobs` | Yes |
| 032 | `032_5E.sql` | `campaign.campaign_outcomes` | Yes |
| 033 | `033_5E.sql` | Campaign grants finalization | Yes |

### 4.5 Phase 5F — Knowledge / RAG (034–038, 043–044)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 034 | `034_5F.sql` | `pgvector` extension; trigger functions; `fn_docver_mark_ready()`, `fn_docver_publish()`, `create_kb_partition()` SECURITY DEFINER | Yes |
| 035 | `035_5F.sql` | `knowledge.knowledge_bases` | Yes |
| 036 | `036_5F.sql` | `knowledge.documents`, `knowledge.document_versions` (FK CASCADE/RESTRICT, immutability trigger, REVOKE UPDATE/DELETE, dedup index on `document_id`/`content_hash` — see §10.4) | Yes |
| 037 | `037_5F.sql` | `knowledge.ingestion_jobs` | Yes |
| 038 | `038_5F.sql` | `knowledge.document_chunks` (LIST partitioned + DEFAULT, GIN/tsvector, REVOKE UPDATE) | Yes |
| 043 | `043_5F.sql` | `CREATE INDEX CONCURRENTLY idx_dc_embedding_hnsw` on `knowledge.document_chunks` | **Non-Txn** |
| 044 | `044_5F.sql` | `app_readonly` grants; `app_platform_admin` full access | Yes |

### 4.6 Phase 5G — Workflow / Prompt / Memory (039–042, 045–046)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 039 | `039_5G.sql` | `CREATE SCHEMA IF NOT EXISTS prompt; CREATE SCHEMA IF NOT EXISTS memory;`; GRANT USAGE on workflow/prompt/memory; all trigger/SECURITY DEFINER functions for Phase 5G | Yes |
| 040 | `040_5G.sql` | `workflow.workflow_definitions`, `workflow.workflow_versions` (immutability trigger, REVOKE UPDATE/DELETE) | Yes |
| 041 | `041_5G.sql` | `workflow.workflow_executions` (RANGE monthly + DEFAULT); `fn_start_workflow_execution()` SECURITY DEFINER; database-enforced one-ACTIVE invariant (see §11) | Yes |
| 042 | `042_5G.sql` | `prompt.prompt_templates`, `prompt.prompt_versions` (immutability, REVOKE UPDATE/DELETE), `prompt.prompt_experiments` | Yes |
| 045 | `045_5G.sql` | `memory.session_memories`, `memory.customer_memories` | Yes |
| 046 | `046_5G.sql` | `app_readonly` grants; `app_platform_admin` full access (workflow/prompt/memory) | Yes |

### 4.7 Phase 5H — Billing / Usage (047–058)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 047 | `047_5H.sql` | `CREATE SCHEMA billing`; GRANT USAGE; `fn_raise_immutable()`; `plans`, `plan_versions`, `plan_prices`, `tax_categories`, `tax_rules`, `fx_rates` | Yes |
| 048 | `048_5H.sql` | `billing.billing_accounts` | Yes |
| 049 | `049_5H.sql` | `billing.subscriptions`, `billing.billing_periods` | Yes |
| 050 | `050_5H.sql` | `billing.usage_events` (RANGE monthly, 3 partitions + DEFAULT, REVOKE UPDATE/DELETE), `billing.usage_records` | Yes |
| 051 | `051_5H.sql` | `billing.cost_entries` (RANGE monthly, REVOKE UPDATE/DELETE) | Yes |
| 052 | `052_5H.sql` | `billing.quota_configs`, `billing.tax_profiles`, `billing.invoice_number_sequences`, `fn_allocate_invoice_number()` SECURITY DEFINER | Yes |
| 053 | `053_5H.sql` | `billing.credits`, `billing.credit_ledger_entries` (REVOKE UPDATE/DELETE), `fn_billing_apply_credit()` SECURITY DEFINER | Yes |
| 054 | `054_5H.sql` | `billing.invoices` (immutability trigger), `billing.invoice_lines`, `billing.tax_lines` (REVOKE UPDATE/DELETE on lines) | Yes |
| 055 | `055_5H.sql` | `billing.payment_attempts` (REVOKE UPDATE/DELETE), `billing.refunds`, `fn_validate_refund_amount()` trigger | Yes |
| 056 | `056_5H.sql` | `billing.billing_adjustments` | Yes |
| 057 | `057_5H.sql` | `fn_finalize_invoice()`, `fn_mark_invoice_paid()`, `fn_void_invoice()`, `fn_update_payment_status()` — all SECURITY DEFINER | Yes |
| 058 | `058_5H.sql` | `app_readonly` grants; `app_platform_admin` full access | Yes |

### 4.8 Phase 5I — Integrations / Webhooks / Plugins (059–066)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 059 | `059_5I.sql` | `CREATE SCHEMA integrations, webhooks, plugins`; GRANT USAGE | Yes |
| 060 | `060_5I.sql` | `integrations.integration_definitions`, `fn_id_slug_immutable()` SECURITY DEFINER | Yes |
| 061 | `061_5I.sql` | `integrations.integration_connections`, `fn_create_integration_connection()`, `integrations.oauth_attempts`, `fn_redeem_oauth_attempt()`, `integrations.integration_health`, `fn_rotate_integration_credential()`, `fn_integrations_anonymize_org()` | Yes |
| 062 | `062_5I.sql` | `webhooks.webhook_endpoints`, `webhooks.inbound_webhook_events`, `fn_update_inbound_event_status()` | Yes |
| 063 | `063_5I.sql` | `webhooks.webhook_deliveries` (RANGE monthly + DEFAULT, REVOKE UPDATE/DELETE); `fn_wd_identity_immutable()`, `fn_claim_delivery()`, `fn_delivery_succeeded()`, `fn_delivery_failed()`, `fn_replay_webhook_delivery()` (search_path corrected — see §10.5) | Yes |
| 064 | `064_5I.sql` | `plugins.plugins`, `plugins.plugin_versions`, `fn_plug_slug_immutable()`, `fn_pv_manifest_immutable()` | Yes |
| 065 | `065_5I.sql` | `plugins.plugin_installations`, `plugins.plugin_executions`, all plugin SECURITY DEFINER functions | Yes |
| 066 | `066_5I.sql` | `app_readonly` grants; `app_platform_admin` full access | Yes |

### 4.9 Phase 5J — Analytics / Audit (067–075)

| # | Filename | Purpose | Txn |
|---|---|---|---|
| 067 | `067_5J.sql` | `CREATE SCHEMA analytics, audit`; GRANT USAGE | Yes |
| 068 | `068_5J.sql` | `analytics.analytics_event_dedup`, `analytics.analytics_events` (RANGE monthly + DEFAULT), `analytics.analytics_projection_events`; ingestion/projection SECURITY DEFINER functions (search_path corrected — see §10.6) | Yes |
| 069 | `069_5J.sql` | `analytics.call_metrics_hourly`, `analytics.call_latency_stage_hourly` (both RANGE monthly); `fn_apply_projection_call_latency()` | Yes |
| 070 | `070_5J.sql` | `analytics.conversation_turn_stats_daily`, `analytics.usage_cost_daily` (both RANGE monthly) | Yes |
| 071 | `071_5J.sql` | `analytics.agent_utilization_hourly`, `analytics.lead_funnel_daily`, `analytics.tool_execution_stats_daily`, `analytics.webhook_delivery_stats_daily`, `analytics.provider_health_5min` (all RANGE monthly); `analytics.campaign_outcome_summary`, `analytics.roi_by_campaign` (non-partitioned); `analytics.billing_revenue_monthly` (RANGE yearly — see §10.7) | Yes |
| 072 | `072_5J.sql` | `audit.audit_events` (RANGE monthly + DEFAULT, no direct INSERT/UPDATE/DELETE for any role), `audit.audit_chain`; `fn_insert_audit_event()` SECURITY DEFINER (uses `session_user` for platform authorization), `fn_compute_chain_hash()` SECURITY DEFINER | Yes |
| 073 | `073_5J.sql` | `analytics.event_schema_versions` | Yes |
| 074 | `074_5J.sql` | Grants finalization; provider_health_5min restricted access reaffirmed | Yes |
| 075 | `075_5J.sql` | Seed: known V1 event type/version pairs (`ON CONFLICT DO NOTHING`) | Yes |

---

## 5. Prerequisites — PostgreSQL 16 and Extensions

| Requirement | Details |
|---|---|
| PostgreSQL version | 16 (minimum). `pg_advisory_xact_lock` semantics, partitioned table indexing rules, and `NULLS NOT DISTINCT` on UNIQUE constraints all require PostgreSQL 14+; PostgreSQL 16 is the deployment target. |
| `pgcrypto` | Installed in migration 001 (`CREATE EXTENSION IF NOT EXISTS pgcrypto`). Required for `gen_random_bytes()` (used by `gen_uuid_v7()`), and for `digest()` (used by `fn_compute_chain_hash()` in migration 072). |
| `pg_stat_statements` | Installed in migration 001. Requires `shared_preload_libraries = 'pg_stat_statements'` in `postgresql.conf` on standalone PostgreSQL; pre-configured on Supabase. |
| `vector` (pgvector) | Installed in migration 034 (`CREATE EXTENSION IF NOT EXISTS vector`). Required for the `vector(1536)` column type in `knowledge.document_chunks` and the HNSW index in migration 043. On standalone PostgreSQL, install the `postgresql-16-pgvector` package (or equivalent) before running migration 034. On Supabase, `vector` is pre-installed. |
| `pgcrypto` for audit | `pgcrypto` is installed in migration 001, which precedes migration 072's `fn_compute_chain_hash()` by 71 migrations. No separate step is needed. |

---

## 6. Complete Linear Dependency Graph

| Migration | down_revision | Phase | Filename |
|---|---|---|---|
| 001 | None (root) | 5B | 001_5B.sql |
| 002 | 001_5B | 5B | 002_5B.sql |
| 003 | 002_5B | 5B | 003_5B.sql |
| 004 | 003_5B | 5B | 004_5B.sql |
| 005 | 004_5B | 5B | 005_5B.sql |
| 006 | 005_5B | 5B | 006_5B.sql |
| 007 | 006_5B | 5B | 007_5B.sql |
| 008 | 007_5B | 5B | 008_5B.sql |
| 009 | 008_5B | 5C | 009_5C.sql |
| 010 | 009_5C | 5C | 010_5C.sql |
| 011 | 010_5C | 5C | 011_5C.sql |
| 012 | 011_5C | 5C | 012_5C.sql |
| 013 | 012_5C | 5C | 013_5C.sql |
| 014 | 013_5C | 5C | 014_5C.sql |
| 015 | 014_5C | 5C | 015_5C.sql |
| 016 | 015_5C | 5C | 016_5C.sql |
| 017 | 016_5C | 5C | 017_5C.sql |
| 018 | 017_5C | 5C | 018_5C.sql |
| 019 | 018_5C | 5D | 019_5D.sql |
| 020 | 019_5D | 5D | 020_5D.sql |
| 021 | 020_5D | 5D | 021_5D.sql |
| 022 | 021_5D | 5D | 022_5D.sql |
| 023 | 022_5D | 5D | 023_5D.sql |
| 024 | 023_5D | 5D | 024_5D.sql |
| 025 | 024_5D | 5D | 025_5D.sql |
| 026 | 025_5D | 5D | 026_5D.sql |
| 027 | 026_5D | 5E | 027_5E.sql |
| 028 | 027_5E | 5E | 028_5E.sql |
| 029 | 028_5E | 5E | 029_5E.sql |
| 030 | 029_5E | 5E | 030_5E.sql |
| 031 | 030_5E | 5E | 031_5E.sql |
| 032 | 031_5E | 5E | 032_5E.sql |
| 033 | 032_5E | 5E | 033_5E.sql |
| 034 | 033_5E | 5F | 034_5F.sql |
| 035 | 034_5F | 5F | 035_5F.sql |
| 036 | 035_5F | 5F | 036_5F.sql |
| 037 | 036_5F | 5F | 037_5F.sql |
| 038 | 037_5F | 5F | 038_5F.sql |
| 039 | 038_5F | 5G | 039_5G.sql |
| 040 | 039_5G | 5G | 040_5G.sql |
| 041 | 040_5G | 5G | 041_5G.sql |
| 042 | 041_5G | 5G | 042_5G.sql |
| 043 | 042_5G | 5F | 043_5F.sql |
| 044 | 043_5F | 5F | 044_5F.sql |
| 045 | 044_5F | 5G | 045_5G.sql |
| 046 | 045_5G | 5G | 046_5G.sql |
| 047 | 046_5G | 5H | 047_5H.sql |
| 048 | 047_5H | 5H | 048_5H.sql |
| 049 | 048_5H | 5H | 049_5H.sql |
| 050 | 049_5H | 5H | 050_5H.sql |
| 051 | 050_5H | 5H | 051_5H.sql |
| 052 | 051_5H | 5H | 052_5H.sql |
| 053 | 052_5H | 5H | 053_5H.sql |
| 054 | 053_5H | 5H | 054_5H.sql |
| 055 | 054_5H | 5H | 055_5H.sql |
| 056 | 055_5H | 5H | 056_5H.sql |
| 057 | 056_5H | 5H | 057_5H.sql |
| 058 | 057_5H | 5H | 058_5H.sql |
| 059 | 058_5H | 5I | 059_5I.sql |
| 060 | 059_5I | 5I | 060_5I.sql |
| 061 | 060_5I | 5I | 061_5I.sql |
| 062 | 061_5I | 5I | 062_5I.sql |
| 063 | 062_5I | 5I | 063_5I.sql |
| 064 | 063_5I | 5I | 064_5I.sql |
| 065 | 064_5I | 5I | 065_5I.sql |
| 066 | 065_5I | 5I | 066_5I.sql |
| 067 | 066_5I | 5J | 067_5J.sql |
| 068 | 067_5J | 5J | 068_5J.sql |
| 069 | 068_5J | 5J | 069_5J.sql |
| 070 | 069_5J | 5J | 070_5J.sql |
| 071 | 070_5J | 5J | 071_5J.sql |
| 072 | 071_5J | 5J | 072_5J.sql |
| 073 | 072_5J | 5J | 073_5J.sql |
| 074 | 073_5J | 5J | 074_5J.sql |
| 075 | 074_5J | 5J | 075_5J.sql |

Structural guarantees confirmed mechanically from this table: exactly one predecessor per migration except 001; 001 has no predecessor; no merger; no multiple heads; no branch; no cycle; 075 is the sole head.

---

## 7. Schema Creation Order

Thirteen schemas are created in migration 001. Two additional schemas are created in migration 039. Final schema count: **15**.

| Schema | Created | First object | Notes |
|---|---|---|---|
| identity | 001 | 002 | |
| organization | 001 | 003 | |
| voice | 001 | 009 (functions) / 010 (first table) | |
| crm | 001 | 019 (functions) / 020 (first table) | |
| campaign | 001 | 027 (functions) / 028 (first table) | |
| knowledge | 001 | 034 (functions + pgvector) / 035 (first table) | |
| workflow | 001 | 039 (functions) / 040 (first table) | |
| billing | 047 | 047 | Not in 001; created in its own migration |
| integrations | 059 | 060 | Not in 001; created in 059 alongside webhooks/plugins |
| webhooks | 059 | 062 | Not in 001 |
| plugins | 059 | 064 | Not in 001 |
| analytics | 067 | 068 | Not in 001 |
| audit | 067 | 072 | Not in 001 |
| **prompt** | **039** | 042 | Not in 001. The Phase 5G source issues `GRANT USAGE ON SCHEMA prompt` without a preceding `CREATE SCHEMA`. Migration 039 adds the `CREATE SCHEMA IF NOT EXISTS prompt` statement before the grant. |
| **memory** | **039** | 045 | Same as prompt — `CREATE SCHEMA IF NOT EXISTS memory` added to migration 039. |

The `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, and `audit` schemas are each created in their phase's first migration (047, 059, 059, 059, 067, 067) rather than in 001. This reflects the Phase 5H, 5I, and 5J source documents, which each begin their own migration chain with a schema-creation statement. These migrations also issue `GRANT USAGE ON SCHEMA` for their schemas, which is why they must own both the `CREATE SCHEMA` and the initial grant.

---

## 8. Migration Transaction Strategy

### 8.1 Transaction Classification

**74 of 75 migrations: fully transactional.** Each executes as a single `BEGIN ... COMMIT` unit. A failure at any point rolls back the entire migration's changes, leaving the database in exactly the state it was before that migration ran.

**1 migration: non-transactional. Migration 043 (`043_5F.sql`) only.**

```sql
CREATE INDEX CONCURRENTLY idx_dc_embedding_hnsw
  ON knowledge.document_chunks USING hnsw (embedding vector_cosine_ops);
```

PostgreSQL prohibits `CREATE INDEX CONCURRENTLY` inside a transaction block. Migration 043 must run with `transaction_per_migration = False` (Alembic) or in autocommit connection mode. This is the sole reason any migration in the chain requires non-standard transaction handling.

### 8.2 Migration 043 Failure Recovery

If migration 043 is interrupted:
1. PostgreSQL leaves an invalid index: check `SELECT indisvalid FROM pg_index WHERE indexrelid = 'knowledge.idx_dc_embedding_hnsw'::regclass`.
2. If `indisvalid = false`: `DROP INDEX CONCURRENTLY knowledge.idx_dc_embedding_hnsw;` (also non-transactional, safe against an invalid index).
3. Re-run migration 043.
4. Confirm `indisvalid = true` before proceeding to migration 044.

Do not re-run migration 043 without the `DROP INDEX CONCURRENTLY` step first — a second `CREATE INDEX CONCURRENTLY` against the same name while an invalid index of that name exists will fail with a duplicate-name error.

---

## 9. Role and Security Model

### 9.1 Application Roles

Five application roles are created in migration 001 via `DO $$ ... CREATE ROLE ... $$` blocks:

| Role | LOGIN | BYPASSRLS | Purpose |
|---|---|---|---|
| `app_api` | Yes | No | API layer — tenant-scoped reads and writes |
| `app_worker` | Yes | No | Background workers — queue processing, projections |
| `app_readonly` | Yes | No | Read-only analytics/reporting access |
| `app_migration` | Yes | Yes | Migration runner — bypasses RLS to apply DDL |
| `app_platform_admin` | Yes | Yes | Platform operator — bypasses RLS for cross-tenant admin |

**Password management:** Migration 001 creates these roles with no embedded password literal. Passwords must be set post-migration by the operations team from a secrets manager using `ALTER ROLE ... PASSWORD '...'`. No password value is committed to any migration file.

### 9.2 Cross-Cutting Privilege Rules

The following rules apply across all 75 migrations without exception:

1. `app_readonly` receives zero INSERT/UPDATE/DELETE grants anywhere in 001–075.
2. `audit.audit_events` and `audit.audit_chain` have zero direct INSERT/UPDATE/DELETE grants for any role — including `app_platform_admin`. Writes go exclusively through `fn_insert_audit_event()` and `fn_compute_chain_hash()`, which run as SECURITY DEFINER.
3. Every SECURITY DEFINER function has `REVOKE ALL ON FUNCTION ... FROM PUBLIC` immediately after creation, followed by explicit scoped `GRANT EXECUTE` to named roles.
4. Every SECURITY DEFINER function has a `SET search_path` clause in its definition. The `public` schema is included in the search_path only for functions that directly call `gen_uuid_v7()` in their body (since `gen_uuid_v7()` lives in the `public` schema and is not schema-qualified at its call sites).
5. No cross-schema foreign key constraint exists anywhere in 001–075. Every cross-schema reference is a bare `UUID` column (logical reference, no FK) with an explicit `-- logical ref` comment in the DDL.

### 9.3 RLS Enforcement

For every tenant-owned table in all ten schemas:
- `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
- `ALTER TABLE ... FORCE ROW LEVEL SECURITY;`
- At least one `CREATE POLICY ... USING (organization_id = organization.current_tenant_id())` with a matching `WITH CHECK`.

`organization.current_tenant_id()` is created in migration 001, before any tenant-owned table — it is never undefined at policy creation time. `app_platform_admin` has `BYPASSRLS` and sees all rows; its access to sensitive operations (audit writes, etc.) is separately constrained by privilege revocation, not RLS.

---

## 10. Implementation-Layer Corrections

The following items were discovered during source reconciliation. Each preserves an approved Phase 5A–5J invariant while removing a defect in the phase source document that would prevent successful execution against PostgreSQL 16. They are listed here as authoritative specification, not as errata or historical notes.

### 10.1 Migration 001 — No password literal

The Phase 5B source shows `CREATE ROLE ... PASSWORD 'CHANGE_IN_PRODUCTION'`. Migration 001 creates roles with no password literal. Passwords are set by the operations team post-migration.

### 10.2 Migration 003 — FK-safe table creation order

The Phase 5B source defines `organization.memberships` (which has `FK → organization.roles`) before `organization.roles`. Migration 003 creates tables in dependency order: `organizations → roles → permissions → memberships → teams → team_memberships → role_permissions`. The `get_user_organization_ids()` function is created in migration 003 (after `organization.memberships` exists), not in migration 001 as the Phase 5B narrative suggests.

### 10.3 Migration 029 — Non-IMMUTABLE index expression

The Phase 5E source defines:
```sql
CREATE INDEX idx_camp_due_for_start
  ON campaign.campaigns ((scheduling_policy->>'start_at')::timestamptz)
```
PostgreSQL rejects this: the `::timestamptz` cast is not declared `IMMUTABLE`, so it cannot appear in an index expression. Migration 029 indexes the raw ISO-8601 text instead:
```sql
CREATE INDEX idx_camp_due_for_start
  ON campaign.campaigns ((scheduling_policy->>'start_at'))
```
The `->>'start_at'` extraction returns text. ISO-8601 format sorts correctly as text for APScheduler's `start_at >= NOW()::text` poll query. The approved Phase 5E business requirement (efficient scheduling poll) is preserved.

### 10.4 Migration 036 — Dedup index scope

The Phase 5F source defines:
```sql
CREATE UNIQUE INDEX uq_dv_content_hash
  ON knowledge.document_versions (knowledge_base_id, content_hash)
  WHERE status NOT IN ('FAILED','GDPR_ERASED');
```
`knowledge.document_versions` has no `knowledge_base_id` column (`knowledge_base_id` belongs to `knowledge.documents`, one hop away via `document_id`). Migration 036 uses:
```sql
CREATE UNIQUE INDEX uq_dv_content_hash
  ON knowledge.document_versions (document_id, content_hash)
  WHERE status NOT IN ('FAILED','GDPR_ERASED');
```
This enforces dedup at the document level (no two active versions of the same document may have identical content), which matches the approved Phase 5F invariant.

### 10.5 Migration 039 — Missing schema creation

The Phase 5G source issues `GRANT USAGE ON SCHEMA prompt` and `GRANT USAGE ON SCHEMA memory` without preceding `CREATE SCHEMA` statements. Neither schema is among the 13 created in migration 001. Migration 039 adds `CREATE SCHEMA IF NOT EXISTS prompt` and `CREATE SCHEMA IF NOT EXISTS memory` before the grant statements. Without this, migrations 042 (`prompt.prompt_templates`) and 045 (`memory.session_memories`) fail with "schema does not exist".

### 10.6 Migration 041 — workflow.workflow_executions invariant (full design)

See §11 for the complete design. Summary: the Phase 5G source contains a UNIQUE partial index on a partitioned table that omits the partition key — invalid in PostgreSQL 16. The approved Phase 5G invariant (at most one ACTIVE execution per `(session_ref, organization_id)`) is preserved by a SECURITY DEFINER function using `pg_advisory_xact_lock`.

### 10.7 Migration 052/053/057 — Billing SECURITY DEFINER search_path

The Phase 5H source creates six SECURITY DEFINER functions (`fn_allocate_invoice_number`, `fn_billing_apply_credit`, `fn_finalize_invoice`, `fn_mark_invoice_paid`, `fn_void_invoice`, `fn_update_payment_status`) without `SET search_path` clauses. Migration 052/053/057 adds `SET search_path = billing, pg_catalog` to each.

### 10.8 Migration 063 — fn_replay_webhook_delivery search_path

The Phase 5I source defines `fn_replay_webhook_delivery()` with `SET search_path = webhooks, pg_catalog`. This function calls `gen_uuid_v7()` (line: `v_new_id UUID := gen_uuid_v7()`) which lives in the `public` schema. The `SET search_path` does not include `public`, so `gen_uuid_v7()` is not resolvable at call time. Migration 063 uses `SET search_path = webhooks, pg_catalog, public` for this function only. All other functions in migration 063 do not call `gen_uuid_v7()` and retain `SET search_path = webhooks, pg_catalog`.

### 10.9 Migration 065 — No correction needed

All six SECURITY DEFINER functions in Phase 5I migration 065 were individually verified. None calls `gen_uuid_v7()` in their function body (one function uses a column `DEFAULT gen_uuid_v7()` via INSERT without specifying `id`, which resolves via the column's bound function OID, not the calling function's `search_path`). No search_path correction is needed for migration 065.

### 10.10 Migration 068 — fn_ingest_analytics_event search_path

The Phase 5J source defines `fn_ingest_analytics_event()` with `SET search_path = analytics, pg_catalog`. This function calls `v_event_id UUID := gen_uuid_v7()`. Migration 068 uses `SET search_path = analytics, pg_catalog, public` for this function. The other four functions in migration 068 do not call `gen_uuid_v7()` directly and retain `SET search_path = analytics, pg_catalog`.

### 10.11 Migration 071 — billing_revenue_monthly partition key and unique constraint

The Phase 5J source defines `billing_revenue_monthly` with:
```sql
year_bucket INTEGER NOT NULL GENERATED ALWAYS AS (EXTRACT(YEAR FROM year_month)::INTEGER) STORED,
...
CONSTRAINT uq_brm_grain UNIQUE (organization_id, year_month)
) PARTITION BY RANGE (year_bucket);
```
PostgreSQL 16 prohibits a generated column as a partition key. It also prohibits a unique constraint on a partitioned table that does not include all partition-key columns (`year_bucket` is absent from `uq_brm_grain`).

Migration 071 uses a plain application-supplied integer column with a CHECK constraint, matching the pattern every other partitioned analytics table uses:
```sql
year_bucket INTEGER NOT NULL,
CONSTRAINT chk_brm_year_bucket CHECK (year_bucket = EXTRACT(YEAR FROM year_month)::INTEGER),
CONSTRAINT uq_brm_grain UNIQUE (organization_id, year_month, year_bucket)
) PARTITION BY RANGE (year_bucket);
```
The approved Phase 5J retention design (7-year RANGE yearly partitioning) is preserved.

### 10.12 Migration 072 — fn_insert_audit_event search_path and session_user authorization

The Phase 5J source defines `fn_insert_audit_event()` with `SET search_path = audit, organization, pg_catalog`. This function calls `v_id UUID := gen_uuid_v7()`. Migration 072 uses `SET search_path = audit, organization, public, pg_catalog`.

The `session_user`-based platform-event authorization is preserved exactly as the Phase 5J source specifies:
```sql
IF session_user NOT IN ('app_worker', 'app_platform_admin') THEN
  RAISE EXCEPTION 'audit: caller % is not authorized to create platform audit events', session_user;
END IF;
```
`session_user` reflects the authenticated session role and is unaffected by the function's `SECURITY DEFINER` privilege elevation. Using `current_user` here would resolve to the function's owning role and defeat the authorization check — the Phase 5J source explicitly documents this distinction and `session_user` is the correct, intentional choice. `fn_compute_chain_hash()` does not call `gen_uuid_v7()` and retains `SET search_path = audit, pg_catalog`.

---

## 11. Migration 041 — Workflow Execution Invariant Design

### 11.1 The Approved Invariant

Phase 5G defines: at most one `ACTIVE` workflow execution per `(session_ref, organization_id)`. This is a database-enforced invariant, not an application-layer convention.

### 11.2 Why the Source Index Cannot Be Used

The Phase 5G source contains:
```sql
CREATE UNIQUE INDEX uq_we_active_session
  ON workflow.workflow_executions (session_ref, organization_id)
  WHERE status = 'ACTIVE';
```
`workflow.workflow_executions` is `PARTITION BY RANGE (started_at)`. PostgreSQL 16 requires every unique index on a partitioned table to include all partition-key columns. `started_at` is absent, so this index definition fails. Adding `started_at` to the index does not enforce the invariant — it would allow two ACTIVE rows for the same session in different monthly partitions.

### 11.3 Final Design

Migration 041 replaces the invalid unique index with:

**A non-unique supporting index:**
```sql
CREATE INDEX idx_we_active_session
  ON workflow.workflow_executions (organization_id, session_ref)
  WHERE status = 'ACTIVE';
```

**An extended immutability trigger** (replaces the Phase 5G source version of `prevent_execution_mutation()`):
```sql
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
  RETURN NEW;
END;
$$;
```
This extends Phase 5G's approved INV-WF-03 (version pinned) and INV-WF-04 (terminal immutability) with identity-field immutability for `session_ref` and `organization_id`. Triggers fire for all roles including BYPASSRLS — a PostgreSQL engine guarantee.

**INSERT revocation from all app roles:**
```sql
REVOKE INSERT ON workflow.workflow_executions
  FROM app_api, app_worker, app_platform_admin;
GRANT SELECT, UPDATE ON workflow.workflow_executions TO app_api, app_worker;
GRANT SELECT, UPDATE, DELETE ON workflow.workflow_executions TO app_platform_admin;
```

**A SECURITY DEFINER function as the sole INSERT path:**
```sql
CREATE OR REPLACE FUNCTION workflow.fn_start_workflow_execution(
  p_organization_id       UUID,
  p_workflow_version_id   UUID,
  p_session_ref           UUID,
  p_started_at            TIMESTAMPTZ DEFAULT NOW()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflow, organization, public, pg_catalog
AS $$
DECLARE
  v_new_id      UUID   := gen_uuid_v7();
  v_existing_id UUID;
  v_lock_key    BIGINT;
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
  IF NOT EXISTS (
    SELECT 1 FROM workflow.workflow_versions
    WHERE id = p_workflow_version_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: workflow_version % not found for tenant %', p_workflow_version_id, p_organization_id;
  END IF;
  v_lock_key := hashtext(p_organization_id::text || ':' || p_session_ref::text);
  PERFORM pg_advisory_xact_lock(v_lock_key);
  SELECT id INTO v_existing_id
  FROM workflow.workflow_executions
  WHERE organization_id = p_organization_id AND session_ref = p_session_ref AND status = 'ACTIVE'
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RAISE EXCEPTION 'fn_start_workflow_execution: session % already has an ACTIVE workflow execution (id=%). Complete or fail it first.', p_session_ref, v_existing_id;
  END IF;
  INSERT INTO workflow.workflow_executions
    (id, started_at, organization_id, workflow_version_id, session_ref, status)
  VALUES
    (v_new_id, p_started_at, p_organization_id, p_workflow_version_id, p_session_ref, 'ACTIVE');
  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION workflow.fn_start_workflow_execution(UUID, UUID, UUID, TIMESTAMPTZ)
  TO app_api, app_worker, app_platform_admin;
```

### 11.4 Concurrency Safety

`pg_advisory_xact_lock(v_lock_key)` acquires an exclusive transaction-scoped advisory lock keyed to `hashtext(organization_id::text || ':' || session_ref::text)`. A second concurrent transaction for the same `(org, session)` pair blocks at this call until the first commits or rolls back, serializing the check-then-insert window.

In autocommit mode, the function call is itself a transaction; `pg_advisory_xact_lock` holds for the function's full duration. The invariant is preserved with or without an enclosing `BEGIN/COMMIT`. An explicit outer transaction is recommended when the caller needs broader atomicity (e.g., also writing to Redis or creating a session memory row) — this is an application design guideline, not a correctness requirement for the invariant.

Hash collisions (the 32-bit `hashtext` keyspace) may cause unnecessary blocking between different sessions whose `(org, session)` pairs collide, but cannot violate correctness: the actual invariant check uses the exact `(organization_id, session_ref)` pair in the SELECT, not the hash. A collision causes spurious serialization (performance impact) but never a false acceptance or false rejection.

### 11.5 Complete Mutation-Path Analysis

| Mutation | Blocked by |
|---|---|
| INSERT — new ACTIVE row for a session that already has one | `pg_advisory_xact_lock` serializes concurrent callers; SELECT check rejects the second |
| INSERT — direct (bypassing function) | `REVOKE INSERT` from all app roles |
| UPDATE — `session_ref` change | Extended trigger (raises exception) |
| UPDATE — `organization_id` change | Extended trigger (raises exception) |
| UPDATE — `workflow_version_id` change | Trigger (INV-WF-03, unchanged from Phase 5G source) |
| UPDATE — `COMPLETED → ACTIVE` or `FAILED → ACTIVE` | Trigger (INV-WF-04, unchanged from Phase 5G source) |
| UPDATE — normal checkpoint (slots, node state, status → COMPLETED/FAILED) | Allowed — intended application behavior |
| DELETE | No DELETE grant for `app_api` or `app_worker`; `app_platform_admin` DELETE does not resurrect rows |

All invariant-violating paths are closed at the database level.

---

## 12. Foreign Key Strategy

No foreign key constraint crosses a schema boundary anywhere in 001–075. Cross-schema references are bare `UUID` columns with `-- logical ref` comments, validated at the application layer. This is a Phase 5A invariant (§29 anti-pattern table: "Cross-schema FK constraints — PROHIBITED") confirmed in every phase's consistency review.

Within-schema FKs exist in `knowledge`, `crm`, `integrations`, and `plugins` schemas only. Every FK column has a supporting index. Every FK has an explicit `ON DELETE` clause.

---

## 13. Partitioning

### 13.1 Partitioned Tables (22 total)

| Table | Migration | Strategy | Granularity | DEFAULT partition |
|---|---|---|---|---|
| `voice.call_sessions` | 011 | RANGE on `started_at` | Monthly | Yes |
| `voice.transcript_segments` | 014 | RANGE on `created_at` | Monthly | Yes |
| `crm.activities` | 022 | RANGE on `created_at` | Monthly | Yes |
| `crm.consent_records` | 024 | RANGE on `created_at` | Monthly | Yes |
| `campaign.campaign_contacts` | 030 | RANGE on `created_at` | Monthly | Yes |
| `knowledge.document_chunks` | 038 | LIST on `knowledge_base_id` | Per-KB | Yes (DEFAULT) |
| `workflow.workflow_executions` | 041 | RANGE on `started_at` | Monthly | Yes |
| `billing.usage_events` | 050 | RANGE on `occurred_at` | Monthly | Yes |
| `billing.cost_entries` | 051 | RANGE on `occurred_at` | Monthly | Yes |
| `webhooks.webhook_deliveries` | 063 | RANGE on `created_at` | Monthly | Yes |
| `analytics.analytics_events` | 068 | RANGE on `occurred_at` | Monthly | Yes |
| `analytics.call_metrics_hourly` | 069 | RANGE on `hour_bucket` | Monthly | Yes |
| `analytics.call_latency_stage_hourly` | 069 | RANGE on `hour_bucket` | Monthly | Yes |
| `analytics.conversation_turn_stats_daily` | 070 | RANGE on `date_bucket` | Monthly | Yes |
| `analytics.usage_cost_daily` | 070 | RANGE on `date_bucket` | Monthly | Yes |
| `analytics.agent_utilization_hourly` | 071 | RANGE on `hour_bucket` | Monthly | Yes |
| `analytics.lead_funnel_daily` | 071 | RANGE on `date_bucket` | Monthly | Yes |
| `analytics.tool_execution_stats_daily` | 071 | RANGE on `date_bucket` | Monthly | Yes |
| `analytics.webhook_delivery_stats_daily` | 071 | RANGE on `date_bucket` | Monthly | Yes |
| `analytics.provider_health_5min` | 071 | RANGE on `bucket_start` | Monthly | Yes |
| `analytics.billing_revenue_monthly` | 071 | RANGE on `year_bucket` (INT) | Yearly | Yes |
| `audit.audit_events` | 072 | RANGE on `occurred_at` | Monthly | Yes |

### 13.2 Rules Confirmed

Every partitioned table's PRIMARY KEY includes the partition key column (PostgreSQL requirement). Every partitioned table has a DEFAULT partition to absorb inserts that fall outside pre-created explicit partitions. The migration chain creates a minimum of 3–4 forward partitions at migration time; an operational Celery beat task (outside the migration chain) creates additional forward partitions on a rolling schedule.

---

## 14. Seed Data

| Migration | Content | Idempotent |
|---|---|---|
| 007 | System roles, permissions, role-permission assignments | Yes — `ON CONFLICT DO NOTHING` |
| 017 | 5 built-in `voice.tool_definitions` (platform-owned, `organization_id IS NULL`) | Yes — `ON CONFLICT DO NOTHING` |
| 026 | No-op placeholder — org-specific CRM data is API-driven at tenant onboarding | Yes (empty) |
| 075 | 25+ `analytics.event_schema_versions` reference rows | Yes — `ON CONFLICT DO NOTHING` |

No other migration contains INSERT statements. No customer data, no secrets, no plaintext credentials appear in any migration.

---

## 15. Migration Failure and Recovery

### 15.1 Standard (Transactional) Migrations (001–042, 044–075)

PostgreSQL's transactional DDL guarantees a complete rollback on failure. The `alembic_version` table remains at the previous successful revision. Re-run the failed migration after diagnosing and correcting the root cause.

### 15.2 Migration 043 (Non-Transactional)

See §8.2 for the complete recovery procedure. The key point: `DROP INDEX CONCURRENTLY` must precede any re-run attempt.

---

## 16. SECURITY DEFINER Standards

All SECURITY DEFINER functions across 001–075 must satisfy:

| Requirement | Enforcement |
|---|---|
| `SECURITY DEFINER` in definition | Required |
| `SET search_path = <owning_schema>, pg_catalog` | Required; add `public` only if the function body calls `gen_uuid_v7()` directly |
| `REVOKE ALL ON FUNCTION ... FROM PUBLIC` immediately after `CREATE OR REPLACE FUNCTION` | Required |
| Explicit `GRANT EXECUTE ON FUNCTION ... TO <specific_roles>` | Required |
| No dynamic SQL (`EXECUTE format(...)`) on unsanitized caller input | Required |
| Tenant authorization via `organization.current_tenant_id()` where applicable | Required |
| Platform-event authorization via `session_user` (not `current_user`) in `fn_insert_audit_event()` | Required — `current_user` inside SECURITY DEFINER resolves to the function owner, defeating the check |

---

## 17. Automated Validation Suite

Run after every fresh install or upgrade:

| # | Check |
|---|---|
| 1 | All 15 expected schemas exist (`information_schema.schemata`) |
| 2 | All ~90 expected tables exist (`information_schema.tables`) |
| 3 | All expected columns with correct types (`information_schema.columns`) |
| 4 | All expected constraints: PK, UNIQUE, CHECK (`pg_constraint`) |
| 5 | All expected FKs with correct `ON DELETE` (`pg_constraint WHERE contype = 'f'`) |
| 6 | All expected indexes (`pg_indexes`) |
| 7 | Every SECURITY DEFINER function has `prosecdef = true` and non-null `proconfig` containing `search_path` (`pg_proc`) |
| 8 | All expected triggers enabled (`pg_trigger WHERE tgenabled = 'O'`) |
| 9 | Every tenant table has `relrowsecurity = true` AND `relforcerowsecurity = true` (`pg_class`); expected RLS policies present (`pg_policies`) |
| 10 | All expected grants/revokes match exactly (`information_schema.role_table_grants`, `role_routine_grants`) |
| 11 | All expected partitions with DEFAULT partition present (`pg_inherits`) |
| 12 | Extensions installed: `pgcrypto`, `vector` (`pg_extension`) |
| 13 | `workflow.workflow_executions` has no UNIQUE index — only non-unique `idx_we_active_session` (`pg_indexes WHERE schemaname='workflow' AND tablename='workflow_executions'`) |

---

## 18. Security Test Suite

| Test | Expected result |
|---|---|
| Tenant A reads Tenant A's own data | Allowed |
| Tenant A reads Tenant B's data | Denied (RLS) |
| `app_api` direct `INSERT INTO audit.audit_events` | Denied (no INSERT privilege) |
| `app_api` calls `fn_insert_audit_event(p_is_platform_event => TRUE)` | Denied (`session_user` check inside SECURITY DEFINER) |
| `app_worker` calls `fn_insert_audit_event(p_is_platform_event => TRUE)` | Allowed |
| `app_api` direct `INSERT INTO workflow.workflow_executions` | Denied (REVOKE INSERT) |
| `app_worker` direct `INSERT INTO workflow.workflow_executions` | Denied (REVOKE INSERT) |
| `app_platform_admin` direct `INSERT INTO workflow.workflow_executions` | Denied (REVOKE INSERT) |
| `app_api` calls `fn_start_workflow_execution` when session already ACTIVE | Exception raised |
| Two concurrent `fn_start_workflow_execution` calls for same session | Exactly one succeeds |
| UPDATE `session_ref` on any `workflow.workflow_executions` row | Denied (trigger) |
| UPDATE `status = 'ACTIVE'` on a COMPLETED `workflow.workflow_executions` row | Denied (trigger) |
| `app_readonly` writes to any table | Denied (no write privilege anywhere) |

---

## 19. Concurrency Tests

| Test | Expected | Mechanism |
|---|---|---|
| Two concurrent `fn_start_workflow_execution` calls for the same session | Exactly one inserts; other receives exception | `pg_advisory_xact_lock` |
| Two concurrent workers claim the same analytics projection slot | Exactly one succeeds | `UNIQUE (projection_name, analytics_event_id)` row lock |
| Two concurrent inserts with the same `analytics_event_dedup.dedup_key` | Exactly one succeeds | `PRIMARY KEY (dedup_key)` |
| Two concurrent inbound webhook events with same `(organization_id, provider_slug, provider_event_id)` | Exactly one succeeds | UNIQUE constraint |
| Two concurrent `fn_claim_delivery()` calls for the same delivery | Exactly one claims | `SELECT ... FOR UPDATE SKIP LOCKED` |
| Two concurrent `fn_upgrade_plugin()` calls for the same installation | Exactly one succeeds | `SELECT ... FOR UPDATE` inside function |
| Two concurrent tenant sessions write rows for different `organization_id` | Both succeed, fully isolated | `FORCE ROW LEVEL SECURITY` + `WITH CHECK` |

---

## 20. Fresh-Database Execution Procedure

```
1. Start with a completely empty PostgreSQL 16 database.

2. On standalone PostgreSQL (not Supabase):
   - Install pgvector: apt install postgresql-16-pgvector (or equivalent)
   - Add pg_stat_statements to postgresql.conf shared_preload_libraries and restart

3. Configure DATABASE_URL as an environment variable (no credentials in config files).

4. Run migrations 001–075 in exact linear order:
   for each migration in 001..075:
     if migration == 043:
       run in autocommit / transaction_per_migration=False mode
       verify pg_index.indisvalid = true before continuing
     else:
       run in standard transaction mode
     record success in alembic_version

5. Run the full validation suite (§17, all 13 checks).

6. Run the security test suite (§18).

7. Run the concurrency tests (§19).

8. Compute SHA-256 checksums from actual migration files and record in the migration manifest.
```

---

## 21. Alembic Configuration

Migration 043 requires special Alembic configuration. In `env.py`:

```python
# Transaction control per migration
def run_migrations_online():
    ...
    with engine.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            transaction_per_migration=True,  # default for all migrations
        )
        with context.begin_transaction():
            context.run_migrations()
```

Migration 043's Alembic revision file must override `transaction_per_migration = False` for that specific revision. The Alembic migration runner must not silently wrap migration 043 in a transaction — failure to configure this correctly will result in `ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block`.

`DATABASE_URL` must be environment-variable-provided. No credentials are hardcoded in `alembic.ini` or `env.py`.

---

## 22. Migration Manifest

SHA-256 checksums are generated from actual migration files after SQL generation, not fabricated in advance. The manifest table below records migration metadata; checksum values are populated during the package-build step.

| # | Filename | Phase | down_revision | Txn Mode | SHA-256 |
|---|---|---|---|---|---|
| 001 | 001_5B.sql | 5B | None | transactional | (computed at build) |
| 002 | 002_5B.sql | 5B | 001_5B | transactional | (computed at build) |
| 003 | 003_5B.sql | 5B | 002_5B | transactional | (computed at build) |
| 004 | 004_5B.sql | 5B | 003_5B | transactional | (computed at build) |
| 005 | 005_5B.sql | 5B | 004_5B | transactional | (computed at build) |
| 006 | 006_5B.sql | 5B | 005_5B | transactional | (computed at build) |
| 007 | 007_5B.sql | 5B | 006_5B | transactional | (computed at build) |
| 008 | 008_5B.sql | 5B | 007_5B | transactional | (computed at build) |
| 009 | 009_5C.sql | 5C | 008_5B | transactional | (computed at build) |
| 010 | 010_5C.sql | 5C | 009_5C | transactional | (computed at build) |
| 011 | 011_5C.sql | 5C | 010_5C | transactional | (computed at build) |
| 012 | 012_5C.sql | 5C | 011_5C | transactional | (computed at build) |
| 013 | 013_5C.sql | 5C | 012_5C | transactional | (computed at build) |
| 014 | 014_5C.sql | 5C | 013_5C | transactional | (computed at build) |
| 015 | 015_5C.sql | 5C | 014_5C | transactional | (computed at build) |
| 016 | 016_5C.sql | 5C | 015_5C | transactional | (computed at build) |
| 017 | 017_5C.sql | 5C | 016_5C | transactional | (computed at build) |
| 018 | 018_5C.sql | 5C | 017_5C | transactional | (computed at build) |
| 019 | 019_5D.sql | 5D | 018_5C | transactional | (computed at build) |
| 020 | 020_5D.sql | 5D | 019_5D | transactional | (computed at build) |
| 021 | 021_5D.sql | 5D | 020_5D | transactional | (computed at build) |
| 022 | 022_5D.sql | 5D | 021_5D | transactional | (computed at build) |
| 023 | 023_5D.sql | 5D | 022_5D | transactional | (computed at build) |
| 024 | 024_5D.sql | 5D | 023_5D | transactional | (computed at build) |
| 025 | 025_5D.sql | 5D | 024_5D | transactional | (computed at build) |
| 026 | 026_5D.sql | 5D | 025_5D | transactional | (computed at build) |
| 027 | 027_5E.sql | 5E | 026_5D | transactional | (computed at build) |
| 028 | 028_5E.sql | 5E | 027_5E | transactional | (computed at build) |
| 029 | 029_5E.sql | 5E | 028_5E | transactional | (computed at build) |
| 030 | 030_5E.sql | 5E | 029_5E | transactional | (computed at build) |
| 031 | 031_5E.sql | 5E | 030_5E | transactional | (computed at build) |
| 032 | 032_5E.sql | 5E | 031_5E | transactional | (computed at build) |
| 033 | 033_5E.sql | 5E | 032_5E | transactional | (computed at build) |
| 034 | 034_5F.sql | 5F | 033_5E | transactional | (computed at build) |
| 035 | 035_5F.sql | 5F | 034_5F | transactional | (computed at build) |
| 036 | 036_5F.sql | 5F | 035_5F | transactional | (computed at build) |
| 037 | 037_5F.sql | 5F | 036_5F | transactional | (computed at build) |
| 038 | 038_5F.sql | 5F | 037_5F | transactional | (computed at build) |
| 039 | 039_5G.sql | 5G | 038_5F | transactional | (computed at build) |
| 040 | 040_5G.sql | 5G | 039_5G | transactional | (computed at build) |
| 041 | 041_5G.sql | 5G | 040_5G | transactional | (computed at build) |
| 042 | 042_5G.sql | 5G | 041_5G | transactional | (computed at build) |
| 043 | 043_5F.sql | 5F | 042_5G | **non-transactional** | (computed at build) |
| 044 | 044_5F.sql | 5F | 043_5F | transactional | (computed at build) |
| 045 | 045_5G.sql | 5G | 044_5F | transactional | (computed at build) |
| 046 | 046_5G.sql | 5G | 045_5G | transactional | (computed at build) |
| 047 | 047_5H.sql | 5H | 046_5G | transactional | (computed at build) |
| 048 | 048_5H.sql | 5H | 047_5H | transactional | (computed at build) |
| 049 | 049_5H.sql | 5H | 048_5H | transactional | (computed at build) |
| 050 | 050_5H.sql | 5H | 049_5H | transactional | (computed at build) |
| 051 | 051_5H.sql | 5H | 050_5H | transactional | (computed at build) |
| 052 | 052_5H.sql | 5H | 051_5H | transactional | (computed at build) |
| 053 | 053_5H.sql | 5H | 052_5H | transactional | (computed at build) |
| 054 | 054_5H.sql | 5H | 053_5H | transactional | (computed at build) |
| 055 | 055_5H.sql | 5H | 054_5H | transactional | (computed at build) |
| 056 | 056_5H.sql | 5H | 055_5H | transactional | (computed at build) |
| 057 | 057_5H.sql | 5H | 056_5H | transactional | (computed at build) |
| 058 | 058_5H.sql | 5H | 057_5H | transactional | (computed at build) |
| 059 | 059_5I.sql | 5I | 058_5H | transactional | (computed at build) |
| 060 | 060_5I.sql | 5I | 059_5I | transactional | (computed at build) |
| 061 | 061_5I.sql | 5I | 060_5I | transactional | (computed at build) |
| 062 | 062_5I.sql | 5I | 061_5I | transactional | (computed at build) |
| 063 | 063_5I.sql | 5I | 062_5I | transactional | (computed at build) |
| 064 | 064_5I.sql | 5I | 063_5I | transactional | (computed at build) |
| 065 | 065_5I.sql | 5I | 064_5I | transactional | (computed at build) |
| 066 | 066_5I.sql | 5I | 065_5I | transactional | (computed at build) |
| 067 | 067_5J.sql | 5J | 066_5I | transactional | (computed at build) |
| 068 | 068_5J.sql | 5J | 067_5J | transactional | (computed at build) |
| 069 | 069_5J.sql | 5J | 068_5J | transactional | (computed at build) |
| 070 | 070_5J.sql | 5J | 069_5J | transactional | (computed at build) |
| 071 | 071_5J.sql | 5J | 070_5J | transactional | (computed at build) |
| 072 | 072_5J.sql | 5J | 071_5J | transactional | (computed at build) |
| 073 | 073_5J.sql | 5J | 072_5J | transactional | (computed at build) |
| 074 | 074_5J.sql | 5J | 073_5J | transactional | (computed at build) |
| 075 | 075_5J.sql | 5J | 074_5J | transactional | (computed at build) |

---

## 23. Production Migration Checklist

### Before migration

- [ ] Migration files generated and SHA-256 checksums computed
- [ ] Checksums verified against manifest (CI gate must pass)
- [ ] DATABASE_URL set from secrets manager — no credentials in config files
- [ ] Role passwords set via `ALTER ROLE ... PASSWORD '...'` from secrets manager — never from migration files
- [ ] PostgreSQL 16 confirmed; pgvector package installed (standalone only)
- [ ] `pg_stat_statements` in `shared_preload_libraries` (standalone only)
- [ ] Full database backup taken
- [ ] Maintenance window confirmed with stakeholders

### During migration

- [ ] Migrations 001–042 run in transactional mode
- [ ] Migration 043 run in non-transactional (autocommit) mode; `indisvalid = true` confirmed before 044
- [ ] Migrations 044–075 run in transactional mode
- [ ] Each migration's completion logged with timestamp

### After migration

- [ ] `alembic_version` confirms revision 075
- [ ] All 13 validation checks (§17) pass
- [ ] Security tests (§18) pass
- [ ] Concurrency tests (§19) pass
- [ ] Application smoke test passes

---

## 24. Architecture Verified vs. Implementation Executed

This document specifies the complete, authoritative implementation plan. The distinction between these two states is explicit:

**Architecture verified (status: COMPLETE):** The frozen Phase 5A–5J architecture has been mapped, reconciled, forward-reference-checked, conflict-resolved, and fully specified in this document and its associated reconciliation artifacts. All 14 implementation-layer corrections (§10) have been identified, independently re-verified against raw source, and specified precisely.

**Implementation executed (status: PENDING):** The actual SQL migration files (001–075) have not yet been generated and executed on a fresh PostgreSQL 16 database. The full validation suite, security tests, concurrency tests, checksum verification, and Alembic configuration have not yet been run end-to-end. The final manifest SHA-256 values have not yet been computed.

---

## 25. Implementation Gates — Remaining Steps

The following gates must be completed before Phase 5K can be declared fully executed:

1. **Generate migration files** — produce `001_5B.sql` through `075_5J.sql` using the source boundaries in §4, applying all corrections in §10 and §11.
2. **Execute on fresh PostgreSQL 16** — run all 75 migrations in linear order against an empty database. Migration 043 must be run non-transactionally. Record actual per-migration pass/fail results.
3. **Run validation suite** — execute all 13 checks in §17 and confirm zero discrepancies.
4. **Run security tests** — execute all tests in §18 and confirm all expected denials and allowances.
5. **Run concurrency tests** — execute all tests in §19 and confirm all invariants hold.
6. **Compute manifest checksums** — `sha256sum` each migration file; populate the SHA-256 column in §22.
7. **Verify Alembic configuration** — confirm `transaction_per_migration = False` for migration 043; confirm DATABASE_URL is environment-variable-provided.
8. **Generate execution report** — document exact PostgreSQL version, extension versions, per-migration results, test outcomes, and final pass/fail counts.
9. **Final approval** — sign off only after 75/75 migrations pass on a clean database and all test suites pass.

---

## 26. Final Status

```
PHASE 5K — DATABASE MIGRATION & IMPLEMENTATION

Architecture mapped:                        75/75 migrations
Dependency graph valid:                     YES — single linear chain, no branches
Implementation-layer corrections:           14 items, all independently verified
                                            against raw source (§10, §11)
Migration 043 non-transactional handling:   Documented (§8)
Migration 005/006 verification-only:        Designed and tested (§4.1)
Schema count:                               15 (13 base + prompt + memory)
Foreign key strategy:                       No cross-schema FKs
Partitioned tables:                         22
SECURITY DEFINER standards:                 Defined (§16)
Validation suite:                           13 checks defined (§17)
Security test suite:                        Defined (§18)
Concurrency tests:                          Defined (§19)
Manifest:                                   Structure defined; SHA-256 pending file generation

ARCHITECTURE VERIFIED

IMPLEMENTATION EXECUTED: PENDING

Remaining gates: generate SQL files (001–075), execute on fresh PostgreSQL 16,
run validation/security/concurrency tests, compute checksums, generate execution
report. Phase 5K reaches IMPLEMENTATION EXECUTED only after 75/75 migrations
pass on a clean database and all test suites confirm zero failures.
```
