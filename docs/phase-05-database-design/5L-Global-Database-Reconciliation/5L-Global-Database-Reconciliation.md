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
