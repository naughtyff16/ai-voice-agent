# Phase 5L — Global Database Reconciliation

**Date:** 2026-08-24
**Scope:** Controlled reopening of the database baseline to resolve the six
Phase 6F blocking dependencies (DEP-6F-01, 02, 09, 14, 15, 16), re-evaluate
Phase 6B's four database-adjacent dependencies against the *current*
schema (not the schema as it stood when 6B was written), and perform a
global Category A/B/C/D readiness sweep across CRM suppression, billing,
workflow/prompt, analytics/audit governance, and forward-compatibility for
6G-6M. Phase 6G API design does **not** begin as part of this pass, and
this document does not itself declare Phase 6F frozen — that verdict
belongs to the independent review the task authorizing this pass calls
for.

All ten new migrations (`078_5F1.sql` through `087_5B1.sql`) are
forward-only, live-executed, and captured in
`execution_logs/` (25 timestamped files, prefix `20260823T204549Z`). No
migration `001`-`077` was edited.

---

## A. Baseline

| # | Item | Value |
|---|---|---|
| 1 | Old SQL head (before this pass) | `077_5J1.sql` (77 files) |
| 2 | Old Alembic head | `077_5J1` |
| 3 | New SQL head | `087_5B1.sql` (87 files) |
| 4 | New Alembic head | `087_5B1` |
| 5 | Single-head result | Confirmed both before and after — `alembic heads` returned exactly one row at every checkpoint (see `execution_logs/20260823T204549Z_01_fresh_db_upgrade_001_to_087.txt`, `..._04_existing_db_upgrade_077_to_087.txt`) |

Additional baseline facts confirmed live (not assumed) before any DDL was
written:

- `down_revision` chain: single linear chain, `001_5B` (root) through
  `077_5J1`, no branch points.
- Migration checksum/manifest mechanism: SHA-256 + byte size per file,
  tracked in `5K/MIGRATION_MANIFEST.md`.
- Current schema count: 16. Table count (excluding extension-owned
  objects): 198. Function count (same basis): 70. SECURITY DEFINER
  function count: 47. Trigger count: 106. Index count: 826. RLS-enabled
  table count: 91. Policy count: 103. (All reconfirmed live against a
  database freshly upgraded to `077_5J1` — see
  `execution_logs/20260823T204549Z_03_structural_counts_baseline_077.txt`;
  these figures match the independently-produced `077_5J1_VALIDATION_REPORT.md`
  aggregate counts for index/trigger/RLS, corroborating both.)
- Existing SECURITY DEFINER functions and the roles/privilege model
  (`app_api`, `app_worker`, `app_readonly`, `app_migration`,
  `app_platform_admin`) match `5A-Database-Architecture-and-Standards.md`
  §1.3/§26 exactly; no drift found.
- `audit.audit_events.action_kind` is `TEXT CHECK (length BETWEEN 1 AND 200)`
  — not an enum, not a lookup table. Confirmed by inspecting migration
  `072_5J.sql` directly.
- `audit.domain_event_outbox` (migration `077_5J1.sql`) is a generic,
  already-hardened transactional outbox (claim/publish/fail,
  `SKIP LOCKED`, CAS-guarded) with no wiring to `identity.sessions` or
  password-reset revocation.

## B. Global audit

| # | Item | Count |
|---|---|---|
| 6 | Total candidate DB findings reviewed | 31 |
| 7 | Category A | 12 |
| 8 | Category B | 3 |
| 9 | Category C | 11 |
| 10 | Category D | 5 |

Full classification table (Section 23 of the authorizing task):

| Finding | Source | Current physical state | Risk | Cat. | Proposed action | DB migration? | Doc amendment? | Product/legal decision? |
|---|---|---|---|---|---|---|---|---|
| DEP-6F-16 publish/delete race | 6F §28 Race #9 | `fn_docver_publish()` has no `documents.status` check | Integrity — revives deleted documents | A | Add guard to `fn_docver_publish()` | Yes (078) | Yes (5F, 6F) | No |
| `documents.current_version_id` bypass | Discovered this pass, adjacent to DEP-6F-16 | Plain table `UPDATE` grant, no column restriction, no FK | Integrity — bypasses the publish/rollback/erase gate entirely | B | Column-level lockdown | Yes (078) | Yes (5F) | No |
| DEP-6F-09 no FAILED path | 6F §39 | No SECURITY DEFINER path to `FAILED` | Blocks reprocess flow structurally | A | `fn_docver_mark_failed()` | Yes (080) | Yes (5F, 6F) | No |
| DEP-6F-01 versioning/rollback | 6F §39, SRS FR-RAG-004 | No rollback mechanism for Documents | Named SRS requirement structurally unimplementable | A | `fn_docver_rollback()`, document-level interpretation per DDD evidence | Yes (079) | Yes (5F, 6F) | No (resolved from DDD evidence, not guessed) |
| DEP-6F-14 KB-wide dedup | 6F §39, DDD 4E inv. 1 | `uq_dv_content_hash` scoped to `document_id`, not KB | DDD invariant physically false | A | `knowledge_base_id` column + KB-scoped unique index | Yes (082) | Yes (5F, 6F) | No |
| DEP-6F-15 GDPR erase | 6F §39/§23.4 | No erasure function; `DELETE .../documents/{id}` fully blocked | GDPR path structurally missing | A | `fn_docver_gdpr_erase()`, `fn_document_gdpr_delete()` | Yes (081) | Yes (5F, 6F) | No |
| DEP-6F-02 real reindex | 6F §39/§22 | No dual-generation representation | Named capability withdrawn from V1 surface | A | Derived chunk/index generations, 4 functions | Yes (083) | Yes (5F, 6F) | No |
| Multilingual FTS | 5F §19 carry-forward, task §8 | `to_tsvector('english', ...)` hard-coded | Mis-tokenizes Tamil/Telugu/Hindi silently | A | `content_language` column, language-aware trigger | Yes (084) | Yes (5F) | No |
| Suppression ACTIVE uniqueness | 5D §own carry-forward | No DB-level uniqueness; race-prone app check | Compliance state (DNC/opt-out) not fail-safe | A | Partial unique index, `NULLS NOT DISTINCT` | Yes (085) | Yes (5D) | No |
| Billing adjustment privilege | 5H §32 own review | `app_worker` direct INSERT | Financial-control parity gap | B | `fn_create_billing_adjustment()` | Yes (086) | Yes (5H) | No |
| DEP-6B-01 durable break-glass | 6B §36.3 | Interim Redis-only state, no durable table | Privileged cross-tenant access has no durable audit trail of *live* state | A | `organization.break_glass_grants` + 2 functions | Yes (087) | Yes (5B, 6B) | No |
| DEP-6B-08 forced-revocation delivery | 6B §36.3 | Best-effort Redis write, no crash-safe retry | Undelivered denylist entries unrecoverable | A | Reuse `audit.domain_event_outbox` (no new table) | **No** | Yes (5B, 6B) | No |
| DEP-6B-02 auth audit vocabulary | 6B §25/§36.3 | 4 event kinds have no governed `action_kind` | Governance gap only — column is unconstrained TEXT | D (doc-only) | Add 4 values to 5J §14.3 vocabulary | No | Yes (5J) | No |
| DEP-6F-03 vocabulary (7 values) | 6F §30.2 | 7 event kinds have no governed `action_kind` | Governance gap only | D (doc-only) | Add 7 values to 5J §14.3 vocabulary | No | Yes (5J) | No |
| New-function audit vocabulary (5 values) | This pass | Rollback/mark-failed/GDPR-erase/reindex events have no governed `action_kind` | Governance gap only | D (doc-only) | Add 5 values to 5J §14.3 vocabulary | No | Yes (5J) | No |
| DEP-6B-03 MFA recovery | 6B §36.3, ADR-6B-10 | No recovery-codes table or equivalent | Not a V1-mandated capability | C — defer | None | No | No | Yes (mechanism choice is product-owned) |
| Prompt-version pinning (ADR-5G-010) | 5G §28 carry-forward | `graph_json` stores `PromptId`, not `PromptVersionId` | No frozen "deterministic replay" requirement found anywhere | C — defer | None | No | No | Yes (5G's own Phase 9 target) |
| Workflow partition maintenance | 5G §28 carry-forward | App/ops concern | None DB-structural | D — no change | None | No | No | No |
| CustomerMemory conflict resolution | 5G §28 carry-forward | Application-layer logic (4E §8.1 inv. 3) | None DB-structural | D — no change | None | No | No | No |
| `campaign_runs` (recurring campaigns) | 5E carry-forward, task §11 | Not modeled | Recurring semantics not yet frozen | C — defer | None | No | No | Yes (6H) |
| DNC dispatch-proof logging | 5E carry-forward, task §11 | Not modeled | Retention policy not legally mandated yet | C — defer | None | No | No | Yes (legal/6H) |
| `(campaign_id, contact_id)` uniqueness | Task §11 | Not enforced | No genuine V1 concurrency guarantee identified requiring it now | C — defer | None | No | No | Possibly (6H) |
| Webhook topic-versioning | 5I, task §12 | Not modeled | Future feature semantics, not yet designed | C — defer | None | No | No | Yes (6J) |
| Plugin developer KYC | 5I, task §12 | Not modeled | No frozen V1 requirement | C — defer | None | No | No | Yes (6J) |
| Integrations/webhooks security review | 5I, task §12 | Claiming, idempotency, signing, replay protection, tenant isolation | Reviewed for defects | D — no change | None (no defect found) | No | No | No |
| Custom/cloned voice tables | 5C, task §6 | Not modeled | Explicitly future/V2 | C — defer | None | No | No | No |
| Future multi-model vector schemas | 5F §19 carry-forward | `vector(1536)` single-model | Future extension, no current requirement | C — defer | None | No | No | No |
| `tool_executions` storage_ref / partition-key lookup / deterministic chunk UUID / Redis fragment cleanup | 5C carry-forwards | Application/implementation concerns | No approved API/runtime requirement forces a schema change now | D — no change | None | No | No | No |
| 6G-6M forward-compatibility | Task §14 | Existing 5D-5J schemas reviewed against known bounded contexts | See Section I below | Mixed (mostly D) | None speculative | No | No | Per-phase (see Section I) |
| Analytics/audit governed-vocabulary consolidation | Task §13 | `domain_event_outbox` already generic; no second outbox needed | Reviewed, no duplicate infrastructure created | D — no change | None (infrastructure already correct) | No | No | No |
| SECURITY DEFINER master audit (all 58 functions post-087) | Task §17 | See Section J | Verified clean | D — no change | None (all compliant) | No | No | No |

## C. Changes implemented

**11. Every migration created:** `078_5F1.sql`, `079_5F2.sql`,
`080_5F3.sql`, `081_5F4.sql`, `082_5F5.sql`, `083_5F6.sql`, `084_5F7.sql`,
`085_5D1.sql`, `086_5H1.sql`, `087_5B1.sql` (plus one same-named
`.py` Alembic wrapper each, in `5K/alembic/versions/`, following the
`run_frozen_sql()` template exactly).

**12. Table added:** `organization.break_glass_grants` (087).

**13. Columns added:**
- `knowledge.document_versions.knowledge_base_id` (082)
- `knowledge.document_chunks.index_generation` (083)
- `knowledge.documents.content_language`, `knowledge.document_chunks.content_language` (084)

**14. Indexes/constraints added:**
- `fk_dv_kb` FK, `uq_dv_content_hash_kb` (replacing `uq_dv_content_hash`,
  dropped), `idx_dv_kb_status` (082)
- `chk_dc_index_generation`, widened `uq_chunk_position`,
  `idx_dc_kb_generation` (083)
- `chk_doc_content_language`, `chk_dc_content_language` (084)
- `uq_sup_active` (`NULLS NOT DISTINCT`) on `crm.contact_suppressions` (085)
- `pk_break_glass_grants`, `idx_bgg_org_active`, `idx_bgg_admin`,
  `idx_bgg_expires`, plus 5 `CHECK` constraints on
  `organization.break_glass_grants` (087)

**15. Functions added (12):**
`knowledge.fn_docver_rollback` (079), `knowledge.fn_docver_mark_failed`
(080), `knowledge.fn_docver_gdpr_erase`, `knowledge.fn_document_gdpr_delete`
(081), `knowledge.fn_dv_derive_kb_id` (082, trigger function),
`knowledge.fn_kb_reindex_begin`, `fn_kb_reindex_complete`,
`fn_kb_reindex_fail`, `fn_kb_reindex_cleanup_old_generations` (083),
`billing.fn_create_billing_adjustment` (086),
`organization.fn_break_glass_grant`, `organization.fn_break_glass_release`
(087).

**16. Functions modified (`CREATE OR REPLACE`, signature/grants
unchanged):** `knowledge.fn_docver_publish` (078, added the
`documents.status <> 'DELETED'` guard),
`knowledge.prevent_docver_immutable_field_mutation` (082, extended to
also protect `knowledge_base_id`), `knowledge.update_chunk_tsvector`
(084, language-aware).

**17. Grants changed:**
- `knowledge.documents`: table-level `UPDATE` revoked from `app_api`,
  `app_worker`; re-granted at column level for every column except
  `current_version_id` (078).
- `billing.billing_adjustments`: `INSERT` revoked from `app_worker`,
  replaced by `EXECUTE` on `fn_create_billing_adjustment` (086).
- All 12 new functions: `REVOKE ALL ... FROM PUBLIC` + narrow
  `GRANT EXECUTE` to specific roles only (see Section J for the full
  per-function grant table, live-queried).
- `organization.break_glass_grants`: no app role has any direct
  INSERT/UPDATE/DELETE; `SELECT` granted to all four (gated by RLS).

**18. RLS changes:** `organization.break_glass_grants` — `ENABLE`/`FORCE`
ROW LEVEL SECURITY, single policy `rls_bgg_platform_admin_only FOR ALL
USING (organization.is_platform_admin())` (087). No existing RLS policy
on any pre-existing table was altered.

**19. Trigger changes:** `trg_dv_derive_kb_id` (082, new, `BEFORE INSERT`
on `document_versions`), `trg_bgg_immutable_fields` (087, new, `BEFORE
UPDATE` on `break_glass_grants`). `trg_dc_tsvector` and `trg_dv_immutable_fields`
keep their existing bindings — only the underlying function bodies changed
(items 16 above).

**20. Data backfill:** `document_versions.knowledge_base_id` backfilled
from the parent `documents` row for any pre-existing rows (082) —
preflight duplicate-check `DO` block ran first and would have raised
(not silently resolved) had any conflict existed; none did in the
validated environment. No other backfill was required (all other new
columns have safe defaults: `index_generation` defaults to `1`,
`content_language` defaults to `'en'`).

## D. 6B

**21. Break-glass decision:** Category A — implemented.
`organization.break_glass_grants` (087) provides durable persistence for
grant target org, granting admin, justification, issued/expires/released
timestamps, and active/released state (EXPIRED computed at read time,
mirroring `contact_suppressions`' established pattern). Redis remains the
fast-path cache; the table is the durable source of truth a
reconciliation job can fall back to.

**22. DEP-6B-08 decision:** Category A — implemented via
infrastructure reuse, **not** a new table.

**23. Does migration 077's outbox close it:** Yes. The documented event
contract (added to 5B/6B, see amendments below):
`event_type='identity.forced_revocation_required'`,
`aggregate_type='session'`, `aggregate_id`=session id,
`payload={user_id, session_ids[], access_token_jti[], reason}`. JTIs only
— never the raw bearer access/refresh token or `refresh_token_hash`. The
password-reset transaction now has a crash-safe, retryable, observable
(`PENDING`→`CLAIMED`→`PUBLISHED`/`FAILED`) durable write in the same
transaction as the password change and session revocation.

**24. Authentication audit governance decision:** Doc-only amendment.
`action_kind` has no schema-level enum; the 4 named values
(`SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, an admin-forced-logout
value, a forced-revocation-denylist-write value) are added to 5J §14.3's
governed vocabulary list. Zero SQL.

**25. MFA recovery decision:** Category C — deferred, unchanged from
6B's own ADR-6B-10. No frozen V1 mandate found in SRS or 4E DDD; multiple
materially different schemas remain possible (recovery codes vs. other
mechanisms); explicitly product-owned.

## E. CRM/Compliance

**26. Active suppression uniqueness decision:** Category A —
implemented. `uq_sup_active` partial unique index (`organization_id,
phone_e164, scope, channel`) `WHERE status='ACTIVE'`, `NULLS NOT
DISTINCT` (085). Live-proven: exact-duplicate rejection, a genuine
two-process concurrent-insert race (one succeeded, one failed with a real
`unique_violation` — not simulated sequentially), lift-then-reinsert
success, and cross-scope (ORG vs. PLATFORM) independence preserved.

## F. Knowledge/RAG

**27. DEP-6F-01:** Resolved — Interpretation A (document-level historical
rollback), grounded in DDD evidence (Prompt Management's existing
`rollback(environment, target_version)` pointer-swap pattern; Knowledge/RAG
has no `KnowledgeBaseVersion` aggregate). `fn_docver_rollback()` (079).

**28. DEP-6F-02:** Resolved — derived chunk/index generations.
`document_chunks.index_generation` + 4 lifecycle functions (083). Old
generation remains queryable throughout a rebuild; atomic cutover;
failed rebuild preserves the old generation; concurrent double-begin
prevented (advisory lock + row lock, live two-session race test passed).

**29. DEP-6F-09:** Resolved — `fn_docver_mark_failed()` (080), `PENDING`
→`FAILED` only, idempotent, terminal-state rejection for all other
source states.

**30. DEP-6F-14:** Resolved — `document_versions.knowledge_base_id`
(server-derived, anti-spoofing trigger, FK-enforced) +
`uq_dv_content_hash_kb` replacing the document-scoped
`uq_dv_content_hash` (082). Live-proven: same-KB cross-document
duplicate rejected, cross-KB identical hash allowed, client-supplied
`knowledge_base_id` value silently overridden by the server-derived one.

**31. DEP-6F-15:** Resolved — `fn_docver_gdpr_erase()` (per-version,
idempotent) + `fn_document_gdpr_delete()` (per-document orchestration,
matches 6F §23.4's 4-step contract for steps 1-3) (081).

**32. DEP-6F-16:** Resolved — `fn_docver_publish()` guard against
`documents.status='DELETED'` (078), plus a newly-discovered adjacent gap
closed in the same migration: `documents.current_version_id` (INV-12,
the "publication gate") had a plain table-level `UPDATE` grant with no
column restriction, letting `app_api`/`app_worker` bypass
`fn_docver_publish()`/`fn_docver_rollback()` entirely via a direct
`UPDATE`. Closed via column-level privilege lockdown (Category B
hardening, `REVOKE`+targeted `GRANT UPDATE(...)`).

**33. Multilingual FTS decision:** Resolved — `content_language`
column (`en`/`ta`/`te`/`hi`) on `documents` and `document_chunks`,
language-aware `update_chunk_tsvector()` (`english` config for `en`,
`simple` for `ta`/`te`/`hi` and code-mixed content) (084). Live-proven
across English (stemmed match confirmed), Tamil, Telugu, Hindi, and
Tamil-English code-mixed content — every language produced a non-empty,
correctly-tokenized `tsvector_content`; no keyword loss/corruption in any
case.

## G. Workflow

**34. Prompt-version pinning decision:** Category C — deferred. No
"deterministic replay" requirement found anywhere in frozen SRS or 4E
DDD (confirmed by direct search); 5G's own document already carries this
to Phase 9. Not touched.

## H. Billing

**35. Billing-adjustment privilege decision:** Category B —
implemented. `billing.fn_create_billing_adjustment()` (086), `app_worker`'s
direct `INSERT` on `billing_adjustments` revoked and replaced with
`EXECUTE`. Live-proven: direct-INSERT denial, function-mediated success,
cross-tenant `invoice_id` rejection, invalid `adjustment_type` rejection.
`app_platform_admin`'s existing full-CRUD grant is untouched.

## I. Future phase readiness

| # | Phase | Status |
|---|---|---|
| 36 | 6G CRM + Leads | READY WITH CURRENT SCHEMA — `crm.contacts`/`deals`/`activities`/`tasks`/`notes`/`lead_score_records` already support the bounded context; `contact_suppressions` now has DB-level uniqueness (085) strengthening any 6G suppression endpoints. No blocker found. |
| 37 | 6H Campaign | KNOWN DEFERRED ITEM — recurring-campaign semantics (`campaign_runs`), `(campaign_id, contact_id)` uniqueness, and DNC dispatch-proof retention are explicitly unresolved product/legal questions; 5E's existing tables (`campaigns`, `campaign_targets`, etc.) are otherwise structurally sound. Not a current blocker. |
| 38 | 6I Workflow | KNOWN DEFERRED ITEM — prompt-version pinning (ADR-5G-010) remains an open design question for deterministic replay, but is explicitly not required by any frozen SRS/DDD text found. `workflow_executions`/`prompt_versions`/`memory` schemas are otherwise ready. |
| 39 | 6J Integrations/Webhooks/Plugins | KNOWN DEFERRED ITEM — webhook topic-versioning and plugin KYC are undesigned future features; existing claiming/idempotency/signing/replay/tenant-isolation mechanisms were reviewed for security defects and none was found. |
| 40 | 6K Billing + Usage | READY WITH CURRENT SCHEMA — `billing_adjustments` now has financial-control parity (086); `usage_events`/`invoices`/`payment_attempts`/`credits` schemas unchanged and already validated in Phase 5K/6C. |
| 41 | 6L Analytics + Audit | READY WITH CURRENT SCHEMA — `audit.domain_event_outbox` (077) already provides generic reliable event delivery; no second outbox created this pass; governed-vocabulary additions are doc-only and require no API-blocking schema work. |
| 42 | 6M Admin/Platform | READY WITH CURRENT SCHEMA — `organization.break_glass_grants` (087) gives 6M's platform-admin operations a durable, auditable, narrowly-scoped privileged-access mechanism to build on. |

## J. Security

**43. RLS tests:** Live-executed. `organization.break_glass_grants`:
non-platform-admin session sees 0 rows (`..._22_dep6b01_breakglass_rls_tenant_blind.txt`);
platform-admin session sees the row it created
(`..._21_dep6b01_breakglass_admin_lifecycle.txt`). Pre-existing RLS
unregressed: Org A cannot see Org B's suppressions or knowledge bases
(`..._24_regression_slice.txt`).

**44. Cross-tenant tests:** `fn_create_billing_adjustment` rejects an
`invoice_id` belonging to a different organization
(`..._19_dep5h_billing_function_and_crosstenant.txt`);
`fn_dv_derive_kb_id` re-validates document/tenant ownership independent
of RLS (`..._11_dep6f14_kb_dedup.txt`, test T4).

**45. SECURITY DEFINER tests:** All 12 new functions confirmed live:
`prosecdef=true`, explicit non-empty `search_path` on every one, owner
`postgres` (the migration-running role in this validation; `app_migration`
in a real deployment, both privilege-equivalent) —
`..._25_security_definer_public_execute_audit.txt`.

**46. PUBLIC EXECUTE audit:** All 12 new functions' `proacl` inspected
live — no empty-grantee (PUBLIC) entry on any of them; each has exactly
the roles explicitly `GRANT EXECUTE`-ed in its migration and no others
(same file as #45).

**47. Privilege-escalation tests:** Column-level lockdown proven —
`app_api` denied direct `UPDATE` of `documents.current_version_id`
(`..._07_dep6f16_column_privilege.txt`) while retaining `UPDATE` on
every other column of that table; `app_worker` denied direct `INSERT`
on `billing_adjustments` (`..._18_dep5h_billing_direct_insert_denied.txt`);
no app role has any direct DML grant on `break_glass_grants`
(`..._20_dep6b01_breakglass_nonadmin_denied.txt`, test T2).

**48. Admin-misuse tests:** A non-platform-admin `app_api` session is
denied both `fn_break_glass_grant` and any direct table write
(`..._20_...txt`); the immutable-fields trigger rejects reverting a
`RELEASED` grant back to `ACTIVE` even attempted as the superuser
connection directly on the table, independent of role grants
(`..._22_...txt`, final block) — proving the terminal-state guarantee
does not rely solely on privilege grants.

**49. AI/untrusted-input DB safety tests:** A chunk `content` value
containing SQL-injection-shaped text (`DROP TABLE ...`), a quote,
comment syntax, and an HTML/script fragment was inserted, stored
verbatim as inert text, correctly tokenized by the (unmodified-in-logic,
newly language-aware) FTS trigger without error, and left
`knowledge.documents` completely unaffected
(`..._23_ai_untrusted_input_safety.txt`).

**50. GDPR tests:** `fn_docver_gdpr_erase()` deletes chunks and erases
`storage_ref`/`content_hash` to `'ERASED'`, transitions to
`GDPR_ERASED`, is idempotent on re-call; `fn_document_gdpr_delete()`
erases every non-erased version of a document and correctly tombstones
the document row (`status='DELETED'`, `current_version_id=NULL`,
`original_filename=NULL`, `deleted_at` set) —
`..._10_dep6f15_gdpr_erase.txt`.

**51. Audit immutability tests:** No change was made to
`audit.audit_events`/`audit.audit_chain`/`audit.domain_event_outbox` in
this pass; the regression slice reconfirms `app_readonly` is still
denied direct `INSERT` on `audit.audit_events`
(`..._24_regression_slice.txt`).

## K. Validation

**52. Existing DB upgrade:** PASS — a database pinned at `077_5J1` was
upgraded forward to `087_5B1`, exit code 0, single head confirmed
(`..._04_existing_db_upgrade_077_to_087.txt`).

**53. Fresh DB upgrade:** PASS — an empty database was upgraded
`001`→`087` in one run, exit code 0, single head confirmed
(`..._01_fresh_db_upgrade_001_to_087.txt`).

**54. Manifest/checksum:** PASS — SHA-256 + byte size computed for all
10 new files and recorded in `5K/MIGRATION_MANIFEST.md`'s Phase 5L
amendment section.

**55. Regression suite:** PASS (representative slice, not the full ~50
original checks) — `app_readonly` INSERT-on-`audit_events` still denied;
cross-tenant RLS still isolates Org A/Org B on `knowledge_bases` and
`contact_suppressions` (`..._24_regression_slice.txt`).

**56. Concurrency suite:** PASS — two genuinely concurrent OS-level
`psql` sessions raced `fn_kb_reindex_begin()` on the same KB (one blocked
on the row/advisory lock, then correctly rejected once the winner
committed — `..._13_dep6f02_reindex_concurrency.txt`) and raced an
identical suppression INSERT (one succeeded, one failed with a real
`unique_violation` — `..._17_dep5d_suppression_true_concurrency.txt`).

Validation environment: local PostgreSQL 18 (`postgresql-x64-18`
service), `pgvector 0.8.6`, Python 3.13 venv with `alembic 1.19.1` /
`sqlalchemy 2.0.52` / `psycopg2 2.9.12`. Two disposable databases
(`voice_agent_recon_validate`, `voice_agent_recon_baseline077`) were
created and dropped; the pre-existing `voice_agent_5j1_validate` database
and the pre-existing `app_api`/`app_worker`/`app_readonly`/
`app_migration`/`app_platform_admin` roles (left over from earlier Phase
5K/6B work on this same local instance) were left untouched except for
temporary passwords set on the four login-capable app roles for
privilege testing, reset to `NULL` at the end of this pass — the
instance is back to its pre-session state.

## L. Final status

Six of six required DEP-6F blockers resolved, live-validated. DEP-6B-01
and DEP-6B-08 resolved, live-validated (the latter via infrastructure
reuse, no new table). DEP-6B-02/6F-03 vocabulary gaps closed via
documentation-only amendment. Suppression and billing hardening
implemented and live-validated. Multilingual FTS implemented and
live-validated across five language/mixed-language cases. All identified
Category C/D items recorded above with explicit rationale, none
implemented speculatively. Every new SECURITY DEFINER function passes
the search_path/PUBLIC-EXECUTE audit. Single Alembic head maintained
throughout. Both required upgrade paths (fresh-DB and existing-DB) pass
with real execution evidence.

**GLOBAL DATABASE RECONCILIATION COMPLETE — READY TO RETURN TO PHASE 6F
FREEZE REVIEW**

---

# Phase 5L.1 — Post-Reconciliation Correction (2026-08-24)

An independent review of migrations `078_5F1`-`087_5B1` found five
defects/gaps in the cross-feature interactions between the six new
Knowledge/RAG lifecycle mechanisms (publish, rollback, mark-failed, GDPR
erase, and — especially — the new reindex-generation machinery), plus
one multilingual query-consistency gap. This addendum documents the
fixes: four new migrations (`088_5F8`-`091_5F11`), all live-validated,
including one defect self-found and fixed *during* this sub-pass's own
adversarial testing (see item 1 below).

Baseline for this sub-pass: SQL/Alembic head `087_5B1` -> new head
`091_5F11`. Both upgrade paths (fresh-DB 001-091, existing-DB
087-091) pass with real execution evidence
(`execution_logs/20260823T212453Z_26_...txt`).

## 1. Reindex-fail active-generation forgery (Blocker)

**Root cause**: `fn_kb_reindex_fail()` (083_5F6.sql) deleted
`WHERE index_generation = p_failed_generation` without proving
`p_failed_generation` was actually the pending build generation. A
caller passing the current serving generation could delete it.

**Fix** (`088_5F8.sql`): a new `knowledge.kb_reindex_jobs` table is the
authoritative record of which generation is pending for a KB.
`fn_kb_reindex_fail()` now requires `p_failed_generation = index_version + 1`
and a matching `BUILDING` job row, both checked under the same
`FOR UPDATE` row lock used for the KB status check.

**Self-found regression, fixed in the same migration**: initial testing
of the "retry after failure" path hit a table-wide
`UNIQUE(knowledge_base_id, generation)` constraint — a failed attempt at
generation N permanently blocked any future attempt at generation N,
since `fn_kb_reindex_begin()` always recomputes N = `index_version + 1`
(unchanged by a failed attempt). Fixed with a partial unique index
(`uq_krj_kb_generation_active`) excluding `FAILED` rows, before this
migration was reported as validated.

**Live adversarial evidence** (`execution_logs/..._28_reindex_fail_adversarial_tests.txt`):
- A (valid pending generation) -> succeeds, only pending-generation rows removed, job marked `FAILED`, KB reverts to `ACTIVE`.
- B (current serving generation) -> rejected, zero rows removed.
- C (older/never-existed generation, `0`) -> rejected.
- D (future, `pending+1`) -> rejected.
- E (cross-tenant org) -> rejected (`not found or not owned by tenant`).
- KB state and pending-generation row count independently confirmed unchanged after every rejected attempt.
- A second reindex attempt at the same generation number, after the first failed, now succeeds (proves the self-found regression is closed).

## 2. Reindex-complete false-positive completeness (Blocker)

**Root cause**: `fn_kb_reindex_complete()` (083_5F6.sql) only checked
"at least one chunk row exists" for the new generation — a rebuild that
produced 1 chunk out of 100 required documents would pass.

**Fix** (`088_5F8.sql`): a new `knowledge.kb_reindex_job_manifest` table,
populated once by `fn_kb_reindex_begin()`, snapshots every currently
`READY`, non-deleted document's current version and its already-durable
`document_versions.chunk_count` at begin-time. `fn_kb_reindex_complete()`
now requires, for every manifest entry whose document is still not
deleted and whose version is still `READY` at completion time (entries
made irrelevant by a concurrent delete/GDPR-erase/republish are
correctly excluded, matching the task's own guidance), that the new
generation has exactly `expected_chunk_count` chunks for that
version — not merely at least one. A document ingested after the
snapshot is out of this job's scope by design (picked up by the next
reindex).

**Live evidence** (`execution_logs/..._29_reindex_completeness_proof.txt`):
manifest for a 2-document KB correctly recorded expected counts of 3 and
2; a build that fully rebuilt one document but only 1-of-3 chunks for
the other was rejected with "1 of 2 manifested document version(s) are
missing or incomplete", KB remained `REINDEXING` at the old
`index_version`; supplying the missing chunks then allowed
`fn_kb_reindex_complete()` to succeed and cut over.

## 3-4. Rollback vs. reindex-cleanup coherence (Blocker)

**Root cause**: `fn_kb_reindex_cleanup_old_generations()` (083_5F6.sql)
deleted every chunk row with `index_generation < index_version`
unconditionally. A `SUPERSEDED` (rollback-eligible) document version's
chunks are normally never rebuilt into a newer generation (reindex only
rebuilds currently-published content, per the new manifest) — so its
sole surviving copy could be deleted by cleanup, after which
`fn_docver_rollback()` would succeed at the SQL layer but reactivate a
version with zero searchable content.

**Options considered and rejected** (documented in `089_5F9.sql`'s
header): (A) rebuild every rollback-eligible historical version on
every reindex — correctness-preserving but unboundedly expensive and
ungrounded in any frozen requirement; (B) make rollback an async,
worker-driven rebuild-then-cutover operation mirroring reindex — adds an
entire second async lifecycle for what 4E models as Prompt Management's
synchronous pointer-swap, with no DDD basis for gating Knowledge
rollback behind an external re-embedding step.

**Chosen — Option D** (`089_5F9.sql`): cleanup deletes an old-generation
chunk row for a given `document_version_id` only if a strictly newer
generation copy already exists for that same version (a true,
redundant duplicate), or the version has since become
`GDPR_ERASED`/`FAILED` (nothing left to protect). A `SUPERSEDED`
version's sole chunk copy is therefore preserved for as long as it
remains rollback-eligible, regardless of how many reindexes have run
since — a disclosed, deliberate storage/retention trade-off in favor of
the correctness guarantee, not a new unbounded-growth problem beyond
what `document_versions`' own indefinite history retention already
implies.

**Unified retrieval contract** (documented, not DB-enforced — restated
in the 5F/6F amendments): a chunk is eligible for retrieval when
`document_version_id = documents.current_version_id AND index_generation
<= knowledge_bases.index_version`. This single predicate hides
not-yet-cut-over new-generation rows during a rebuild (their generation
number exceeds `index_version` until cutover) and correctly finds a
rollback-reactivated version regardless of how far behind its generation
number is (it can never exceed the current `index_version`, since it was
created at or before it).

**Live evidence — the mandatory 17-step end-to-end lifecycle test**
(`execution_logs/..._27_e2e_lifecycle_integration_test.txt`), every
step PASS, including the critical proof point: after publish V1 ->
publish V2 -> begin reindex -> build generation 2 -> verify V2's old
generation still serves mid-build (invariant 3) -> atomic cutover ->
cleanup (V2's old-gen duplicate removed, V1's `SUPERSEDED` chunks
untouched/protected) -> rollback to V1 -> V1 retrieves its original 2
chunks successfully -> GDPR-delete -> zero chunks remain -> publish and
rollback on the deleted document both rejected.

## 5. Document<->DocumentVersion knowledge_base_id drift (Blocker)

**Root cause**: `document_versions.knowledge_base_id` (082_5F5.sql) is
server-derived and immutable, on the assumption
`documents.knowledge_base_id` itself never changes after a version
exists. But `078_5F1.sql` had re-granted `app_api`/`app_worker`
column-level `UPDATE` on every `documents` column except
`current_version_id` — including `knowledge_base_id`, `organization_id`,
`source_type`, `created_by`, `created_at`. Nothing stopped an ordinary
`UPDATE` from moving a document between KBs (or tenants) after its
versions existed, silently invalidating 082's guarantee, the KB-wide
dedup scope, reindex ownership, and retrieval scoping.

**Checked against 4E before fixing**: the Document aggregate's command
list (`UploadDocument, StartIngestion, MarkChunked, MarkEmbedded,
MarkIndexed, MarkFailed, ReprocessDocument, ArchiveDocument,
DeleteDocument`) has no move/transfer command — moving a document
between KBs is not a supported capability, so locking the column is a
correctness fix, not a capability removal.

**Fix** (`090_5F10.sql`): `documents` `UPDATE` narrowed to exactly
`title, original_filename, status, metadata, deleted_at, updated_at`.
`knowledge_base_id`, `organization_id`, `source_type`, `created_by`,
`created_at` (identity/ownership/audit-origin) are now locked, alongside
`current_version_id` (already locked since `078_5F1.sql`).

**Live evidence** (`execution_logs/..._30_kb_drift_lockdown.txt`):
`app_api` and `app_worker` both denied a direct `UPDATE` moving a
document's `knowledge_base_id`; `app_api` also denied mutating
`organization_id`; ordinary `title`/`status` mutation still succeeds;
`documents.knowledge_base_id` and `document_versions.knowledge_base_id`
independently confirmed to still agree.

## 6. Multilingual query consistency — QP-09 (Major)

**Root cause**: `084_5F7.sql` made tsvector storage language-aware
(`english` for `en`, `simple` for `ta`/`te`/`hi`), but the documented
retrieval query pattern still ran a single
`plainto_tsquery('english', ...)` unconditionally — inconsistent with
`simple`-indexed content (English stemming applied to a query term that
must match an unstemmed stored token).

**Fix**: a documented query-contract correction (no DDL can enforce a
query shape) — the query builder runs the same raw user input text
through both regconfigs already established by storage
(`plainto_tsquery('english', text)` for the `en` branch,
`plainto_tsquery('simple', text)` for the `ta`/`te`/`hi` branch),
OR-combined by `content_language`. No per-query language detection
(AI-derived or otherwise) is used or needed — deterministic, closed over
the same 4-language allow-list storage already uses. `091_5F11.sql`
adds the supporting index (`knowledge_base_id, content_language`).

**Live decisive evidence** (`execution_logs/..._31_qp09_multilingual_query_consistency.txt`):
a chunk stored under `simple` (content_language='ta') containing the
literal unstemmed token `returns` — the corrected two-branch query finds
it (1 row); the same query using only the old single-branch
`english`-only pattern returns 0 rows (English-side stemming turns the
query term into `return`, which cannot match the stored literal
`returns`) — a genuine, decisive counter-example proving the old pattern
was broken, not merely a theoretical concern. English stemmed-match,
Tamil/Telugu/Hindi exact-token match, and code-mixed English-word match
were also independently verified correct.

## 7. Break-glass actor attribution (Security review, no DB change)

Reviewed whether `fn_break_glass_grant()`/`fn_break_glass_release()`'s
`p_admin_user_id`/`p_released_by` parameters can be validated
server-side against a trusted authenticated identity. Confirmed: this
schema has no session-GUC-based "current authenticated user id" function
anywhere (only `organization.current_tenant_id()` and
`organization.is_platform_admin()` exist) — no other function in the
entire schema (including `crm.lift_suppression()`'s `p_lifted_by_ref`)
validates actor identity this way either; it is the established,
existing trust model, not a gap unique to break-glass. No fake identity
source was invented. This is recorded as a disclosed application-layer
dependency: the API layer must bind these parameters to the actually
authenticated platform-admin principal (e.g. from verified JWT claims)
before calling these functions. Non-platform-admin denial (both at the
function's `is_platform_admin()` check and at the RLS-guarded `SELECT`)
remains verified from the Phase 5L pass and was not affected by this
sub-pass.

## Phase 5L.1 — Security re-audit

Repo-wide live scan: zero `SECURITY DEFINER` functions with a
missing/unsafe `search_path` (all 58, across the entire schema, not
just this sub-pass's functions). `PUBLIC` `EXECUTE` audit clean on all
11 functions touched this sub-pass (`fn_docver_publish`,
`fn_docver_rollback`, `fn_docver_mark_failed`, `fn_docver_gdpr_erase`,
`fn_document_gdpr_delete`, `fn_kb_reindex_begin/complete/fail/
cleanup_old_generations`, `fn_break_glass_grant`, `fn_break_glass_release`)
— see `execution_logs/..._32_security_definer_reaudit.txt`.

## Phase 5L.1 — Final status

All five independent-review defects are fixed and live-validated,
including one additional defect self-found during this sub-pass's own
adversarial testing and closed before being reported. The mandatory
17-step end-to-end lifecycle test passes in full, with the critical
rollback-after-reindex-and-cleanup proof point (step 14) confirmed live.
Both required upgrade paths pass. Security re-audit clean.

**PHASE 5L.1 COMPLETE — PHASE 6F APPROVED/FROZEN CANDIDATE**

---

# Phase 5L.2 — Final Knowledge/RAG Retrieval Coherence Pass (2026-08-24)

A final independent freeze review found two remaining technical
coherence issues on top of Phase 5L.1's fixes, plus stale contradictory
text in the 6F document. One new migration (`092_5F12.sql`) and a
documented query-contract correction (no DDL needed, verified via
`EXPLAIN ANALYZE`) close the two technical issues; the 6F document
itself received a full internal-consistency pass (not a regeneration).

Baseline: SQL/Alembic head `091_5F11` -> new head `092_5F12`. Both
upgrade paths pass with real execution evidence
(`execution_logs/20260823T215109Z_*`).

## 1. Effective-generation retrieval (Blocker)

**Root cause**: the Phase 5L.1 retrieval predicate,
`document_version_id = documents.current_version_id AND index_generation
<= knowledge_bases.index_version`, is satisfied by *every* generation
`<= index_version` for a version, not just one. Between a successful
cutover (`index_version` advanced) and the next, separate
`fn_kb_reindex_cleanup_old_generations()` call, a current version can
have chunks at both the old and the new generation, both matching the
predicate — duplicate hits, duplicate citations, distorted ranking.

**Fix (query-contract only, no new table/column)**: retrieval must pick
exactly one generation per current version — the highest one
`<= index_version` that actually has chunks for that version. Implemented
as a `NOT EXISTS` anti-join (mirroring the exact pattern
`fn_kb_reindex_cleanup_old_generations()` already uses, migration
`089_5F9.sql`, for full auditability/consistency):

```sql
... AND dc.document_version_id = d.current_version_id
    AND dc.index_generation <= kb.index_version
    AND NOT EXISTS (
      SELECT 1 FROM knowledge.document_chunks newer
      WHERE newer.document_version_id = dc.document_version_id
        AND newer.index_generation > dc.index_generation
        AND newer.index_generation <= kb.index_version
    )
```

**Index decision**: no new index. `EXPLAIN (ANALYZE, BUFFERS)` on this
exact shape shows the anti-join using the existing
`idx_dc_version_generation` index (`089_5F9.sql`) via an **index-only
scan**, total execution time 0.617ms
(`execution_logs/..._37_explain_effective_generation_query.txt`). Adding
a redundant index was considered and rejected — the existing one already
covers `(document_version_id, index_generation)` exactly as needed.

**Live evidence — mandatory pre-cleanup test** (`execution_logs/..._34_effective_generation_precleanup_test.txt`):
after publish -> reindex -> build generation 2 -> complete (cutover)
**without running cleanup**, 4 raw chunk rows are confirmed physically
present (2 at generation 1, 2 at generation 2) for the one current
version. Both a vector-style query (`ORDER BY embedding <=> ...`) and an
FTS-style query (the QP-09 two-branch language pattern) against the
corrected predicate return **exactly 2 rows, generation 2 only** — no
duplicates, identical semantics on both legs. Running cleanup afterward
leaves the result set semantically unchanged (still exactly those same 2
rows).

## 2. Applied identically to QP-08 and QP-09

The same predicate (verbatim) was used for both the vector-style and
FTS-style queries in the test above — there is no possibility of the two
legs disagreeing on which generation to search, by construction (one
documented predicate, not two independently-maintained ones). The
QP-09 multilingual two-branch language strategy from Phase 5L.1
(`english` for `en`, `simple` for `ta`/`te`/`hi`) is unchanged and
composes with the new generation predicate as a simple `AND`.

## 3. Rollback-fallback generation test (Blocker, proves compatibility with 089's cleanup model)

**Live evidence** (`execution_logs/..._35_rollback_fallback_generation_test.txt`):
a document was published (V1), reindexed once (V1's chunks rebuilt into
generation 2), then a new version (V2) was published and *that* was
reindexed again (generation 3) and cleaned up. At this point the KB's
`index_version` is 3, but V1's only surviving chunks live at generation
2 (never rebuilt a second time, and protected from cleanup by
`089_5F9.sql`'s rule). Rolling back to V1: the effective-generation
query correctly resolves to **generation 2** (not 1, not 3) for both
vector and FTS legs, with correct citation fields
(`document_version_id`, `chunk_index`) — a stronger proof than the
task's literal example (which assumed a version only ever has
generation-1 chunks), since it demonstrates the rule generalizes to
"whatever generation is actually available," not merely "the oldest."

## 4. Reindex manifest predicate correction (Major)

**Root cause**: `088_5F8.sql`'s manifest population
(`fn_kb_reindex_begin`) and completion-relevance check
(`fn_kb_reindex_complete`) both used `d.status <> 'DELETED'` to decide
which documents must be present/proven in a rebuild. That's broader than
6F's actual retrieval-eligibility rule — `ArchivedDocumentNotQueryable`
(4E §10, 6F §23.3/§23.5) excludes `ARCHIVED` documents from search, so
only `status = 'READY'` is truly searchable. Under the old predicate, an
`ARCHIVED` document was still *required* by the manifest, which would
have wrongly rejected a worker that correctly skipped rebuilding
non-searchable content.

**Fix** (`092_5F12.sql`): both predicates tightened to `d.status =
'READY'`. `dv.status = 'READY'` (already present, unaffected) continues
to correctly exclude a version superseded/GDPR-erased during rebuild.

**Live evidence — scenarios A-E** (`execution_logs/..._36_manifest_archive_delete_supersede_scenarios.txt`):
- **A** (document already `ARCHIVED` before `begin`): confirmed absent from the manifest.
- **B/C/D fixtures** (three documents `READY` at `begin`): confirmed present in the manifest.
- **E** (cross-tenant document, different org/KB): confirmed absent.
- Document **B** archived, **C** GDPR-deleted, and **D**'s version superseded by a republish — all *during* the rebuild, with no generation-N chunks ever built for any of them. `fn_kb_reindex_complete()` was queried directly and confirmed: of the 4 manifest entries, exactly 3 (the archived/deleted/superseded ones) were correctly excluded from "still relevant," leaving only the one genuinely-current document requiring completion — which the function correctly still blocked on until its chunks were supplied, then succeeded. This proves the fix neither under- nor over-excludes.

## Phase 5L.2 — Security/regression re-audit

Both modified functions (`fn_kb_reindex_begin`, `fn_kb_reindex_complete`)
retain `prosecdef=true`, explicit `search_path`, and no `PUBLIC` EXECUTE
grant. Repo-wide scan (all functions, post-092): zero missing
`search_path`. RLS/cross-tenant isolation and `app_worker`'s EXECUTE
privilege on both functions reconfirmed unregressed
(`execution_logs/..._38_security_rls_privilege_regression.txt`).

## Phase 5L.2 — 6F document consistency pass

The 6F document received a full internal-consistency pass (not a
regeneration): the effective-generation retrieval rule replaces every
mention of the insufficient `index_generation <= index_version` rule as
the *final* search predicate; the reindex manifest predicate correction
is documented; stale "BLOCKING"/"no supporting function exists" wording
still present after Phase 5L.1's own edits is corrected; §44's old
"Controlled Reconciliation Required" work list is converted to a closure
record; the top-of-document status banner is updated from "APPROVED /
FROZEN CANDIDATE" to **"APPROVED / FROZEN"**. See 6F's own Phase 5L.2
correction notice (§1.1b) for the itemized list of what changed.

## Phase 5L.2 — Final status

Both remaining technical coherence issues are fixed and live-validated,
including the mandatory pre-cleanup no-duplicates test (both legs), the
rollback-fallback generation test (a stronger case than literally
specified), and all five archive/delete/supersede/cross-tenant manifest
scenarios. No redundant index was added — the existing one was proven
sufficient via `EXPLAIN ANALYZE`. Security/RLS/privilege regression
checks clean. Both upgrade paths pass. 6F's document-level consistency
pass is complete.

**PHASE 5L.2 COMPLETE — PHASE 6F READY FOR FINAL INDEPENDENT FREEZE APPROVAL**
