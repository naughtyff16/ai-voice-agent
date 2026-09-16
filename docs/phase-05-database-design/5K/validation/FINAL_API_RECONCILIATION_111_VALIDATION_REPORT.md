# FINAL API RECONCILIATION — MIGRATION 111_5H4 VALIDATION REPORT

**Subject:** `111_5H4` — temporary platform-admin quota overrides with baseline fallback
**Owner decision implemented:** FAR-OD-02 = **Option B** (true temporary overrides, base quota stays live)
**Engine:** PostgreSQL 18.6 (Debian 18.6-1.pgdg12+2), `pgvector/pgvector:pg18`
**Date of validation run:** 2026-09-15
**Status:** validation complete — see [§9 Acceptance gate](#9-acceptance-gate)

> This report does **not** declare the migration approved or frozen. It records what was
> executed, what the output showed, and what remains outside the guarantee.

---

## 1. What this pass was for

Two defects were carried into this pass as **proven**, not as reviewer assertions. Both were
re-proven programmatically against a live database rather than taken from a summary.

| ID | Defect | Status after 111 |
|----|--------|------------------|
| **FAR-P1-04** | `107_5B5` replaced `billing.fn_platform_set_quota_override(...)` using a metric vocabulary incompatible with the canonical 5H §11.1 / 6K vocabulary (`ACTIVE_AGENTS` vs `AGENT_COUNT`). | **Closed** — see §3 |
| **FAR-P1-05** | `billing.quota_configs` carries one `UNIQUE (organization_id, metric)` row. The 107-era override **overwrote** that row, so when the override expired the only effective `hard_limit` disappeared and the resolver fell through to “not found → unlimited”. A fail-open. | **Closed** — see §4 |

Both are P1 fail-open or vocabulary-divergence defects on the billing enforcement path, which is
why they gated the reconciliation rather than being deferred.

## 2. What 111_5H4 does

| Object | Action | Purpose |
|--------|--------|---------|
| `billing.quota_overrides` | **CREATE** (additive) | The temporary-override layer. `billing.quota_configs` is **not** overloaded and keeps every 106-era column. |
| `billing.fn_is_canonical_usage_metric(text)` | CREATE | The single source of the canonical 15-metric vocabulary; backs `chk_qo_metric_canonical`. |
| `billing.fn_platform_set_quota_override(...)` | CREATE OR REPLACE | The only write path. SECURITY DEFINER, `app_platform_admin`-only EXECUTE. |
| `billing.fn_resolve_effective_quota(uuid, text)` | CREATE | The read path: active override **else** current base. SECURITY INVOKER, so RLS and tenant context apply to the caller. |
| `voice.fn_assert_agent_quota_admission(uuid)` | CREATE OR REPLACE | ACTIVE_AGENTS admission now reads the **effective** quota through the resolver. |
| `billing.quota_configs` override columns | COMMENT only | Marked `LEGACY (111_5H4)`; not dropped, not read by the resolver. |

Migration `110_5C2` was **not** amended. No migration `112` exists. `down_revision = '110_5C2'`.

## 3. FAR-P1-04 — vocabulary divergence (closed)

Proven by **set arithmetic against the live function**, not by inspection:

```
legacy_107_size = 15 | canonical_5h_size = 15 | intersection = 2
legacy_only = 13     | canonical_absent_from_107 = 13
```

Only `CALL_MINUTES` and `STORAGE_GB` were common to both vocabularies. Thirteen of the fifteen
canonical metrics were unreachable through the 107-era function.

All 15 canonical metrics are accepted; 0 missing. `AGENT_COUNT` evaluates **false** and
`ACTIVE_AGENTS` **true** — the legacy name was **not** silently aliased, as directed. A legacy
metric is refused at two independent layers:

- function layer → `P0001 … metric AGENT_COUNT is outside the canonical 5H §11.1 usage-dimension vocabulary.`
- table layer → `23514 / chk_qo_metric_canonical`

Evidence: `FAR_111_02_override_resolver_battery.txt`, Battery A.

## 4. FAR-P1-05 — fail-open on expiry (closed)

The defining case, from Battery B:

| Step | Base (`quota_configs`) | Override | Effective | Source |
|------|------------------------|----------|-----------|--------|
| B1 baseline | 1000 | — | 1000 | `BASE` |
| B2 override active | **1000, unchanged** (B3) | 2000 | 2000 | `PLATFORM_OVERRIDE` |
| B4 base raised while override active | **1200** | 2000 | 2000 | `PLATFORM_OVERRIDE` |
| B5 after expiry | 1200 | expired | **1200** | `BASE` |

On expiry the effective quota falls back to the **current** baseline — not to unlimited (the
FAR-P1-05 defect), and not to the stale historical 1000 (which would be production-data fiction).
The base row was never overwritten and was never copied into the override.

B11 additionally shows that a legacy `quota_configs.expires_at` lying in the past does **not**
erase the baseline: the resolver deliberately ignores that column, which is recorded verbatim in
the column comment.

Evidence: `FAR_111_02_override_resolver_battery.txt`, Battery B.

## 5. FAR-OD-02 — the normative contract as implemented

1. **Two layers.** A commercial/base quota (`billing.quota_configs`) and a temporary
   platform-admin override (`billing.quota_overrides`). They are separate rows in separate tables.
2. **The override never overwrites the base.** Setting, superseding or expiring an override makes
   no change to `quota_configs`.
3. **Resolution order.** Active, non-superseded override → else the **current** base row → else no
   row. “No row” is not “unlimited”: it is the absence of a configured quota, and callers must
   treat it as such.
4. **`expires_at = NULL` means permanent**, not expired.
5. **Expiry is read-time**, evaluated against `NOW()`. No sweeper job, no background state change.
   `NOW()` is `transaction_timestamp()`, so an effective quota is stable within a transaction and
   an expiry becomes visible to the **next** transaction.
6. **Unlimited is `hard_limit IS NULL`** on the effective result, and that is exactly what
   `overage_allowed` reports.
7. **Supersession is atomic.** The previous current row is superseded and the new row inserted
   under one advisory lock in one transaction. Superseded overrides never reactivate.
8. **The audit record is written in the same transaction** as the override row.

## 6. Validation coverage

All ten batteries ran against live disposable databases. Every line quoted in the evidence files
is captured output.

| Battery | Subject | Where |
|---------|---------|-------|
| **A** | Canonical vocabulary; legacy-vocabulary set arithmetic (FAR-P1-04) | `FAR_111_02` |
| **B** | Baseline/override resolution, all 8 required cases + extras (FAR-OD-02, FAR-P1-05) | `FAR_111_02` |
| **C** | Supersession atomicity; partial-unique-index structural proof | `FAR_111_02` |
| **D** | Admin mutation function: refusals, validations, NULL and fractional limits, unit labels | `FAR_111_02` |
| **E** | ACTIVE_AGENTS admission end to end; non-destructive lowering; 110 invariants | `FAR_111_03` |
| **F** | Fractional `NUMERIC(18,4)` limits | `FAR_111_02` |
| **G** | Concurrency: admission race and simultaneous override writes | `FAR_111_03` |
| **H** | `created_by` non-member / cross-tenant / NULL negatives | `FAR_111_03` |
| **I** | Platform Admin GET read model: ACTIVE / EXPIRED / SUPERSEDED | `FAR_111_03` |
| **J** | Tenant effective-quota contract; RLS isolation both directions | `FAR_111_03` |

### Migration integrity

- Fresh chain `base → 111_5H4` and incremental chain `base → 110_5C2 → 111_5H4` both reach head
  `111_5H4`.
- `diff objects_fresh.txt objects_incr.txt` produced **no output** — the two catalogs are
  identical, 113 lines each.
- Evidence: `FAR_111_01_migration_integrity.txt`.

### Security posture (summary; full ACL/RLS dump in `FAR_111_03` Part 1)

- Exactly **one** SECURITY DEFINER function (the admin mutation path); every other routine is
  SECURITY INVOKER with an explicit `search_path` terminating in `pg_catalog`.
- `app_api` holds **no** EXECUTE on `fn_platform_set_quota_override` — the 107-era grant is gone.
- `app_api`, `app_worker` and `app_readonly` resolve effective quota with **no** admin privilege.
- No application role holds INSERT/UPDATE/DELETE on `billing.quota_overrides`; RLS is **FORCED**.
- **No new BYPASSRLS.** The inventory is `app_migration`, `app_platform_admin`, `postgres` —
  unchanged, and all pre-existing.

### Scope of the security claim

> Under normal SQL execution with the defined triggers/functions/ACLs enabled, the tested runtime
> principals and tested privileged session cannot bypass the application invariant; deliberate
> superuser DDL/trigger-disabling actions are outside the application guarantee.

## 7. The lower-limit contract (quota below current usage)

When the effective limit drops below current usage — by expiry, by supersession, or by a
deliberately lower override — the database **closes admission only**:

- New `ACTIVE_AGENTS` admissions are refused with `53400`.
- **Zero** Agents were deleted, deprecated or soft-deleted (`auto_deprecated=0`,
  `soft_deleted_rows=0`).
- An existing Agent could still transition `DRAFT → PUBLISHED` while the tenant was over limit.
- The state is recoverable: a new override re-opens admission without touching customer data.

The database never destroys, deprecates or mutates customer Agents or phone numbers to make a
quota true. Reconciling usage down to a lower limit is a product/commercial decision surfaced
through the API, not a database side effect.

## 8. Caveats and disclosed limitations

1. **Harness time travel.** The EXPIRED state was produced by a superuser shifting an override
   window into the past. No application path can create such a row: the admin function rejects a
   past `p_expires_at`, and `chk_qo_expires_after_start` rejects backdating `expires_at` alone
   (a rejection captured verbatim in `FAR_111_03` E.6). Real expiry by wall-clock passage was not
   waited out; it is inferred from the read-time comparison the resolver actually evaluates.
2. **`CREATE OR REPLACE` revalidation caveat.** `chk_qo_metric_canonical` calls
   `fn_is_canonical_usage_metric`. PostgreSQL does **not** revalidate existing rows when a function
   backing a CHECK is replaced. Any future narrowing of the vocabulary must be accompanied by an
   explicit revalidation of `billing.quota_overrides`, not by replacing the function alone.
3. **Unit-label reconciliation.** `KNOWLEDGE_RETRIEVALS` derives `queries` (not `retrievals`) and
   `STORAGE_GB` derives `GB-months` (not `GB`), matching the 106-era reconciliation recorded at
   `111_5H4.sql:535-537`. An explicitly supplied label wins over the derived one.
4. **Harness expectation error, not an engine defect.** Step E.6b printed `FAIL`. The step ran
   inside a single `psql` `DO` block; an exception raised by an earlier probe in the same block had
   already rolled back the agent the step was trying to re-create. The engine behaved correctly and
   the transcript is retained rather than removed.
5. **Fixture planting used superuser.** Batteries A, B and C plant rows directly in
   `billing.quota_configs` / `billing.quota_overrides`, which no application principal may do.
   Superuser is used only to create starting conditions, never to make a result come out right.
   The runtime-principal proofs are Batteries D, E, H and J.
6. **No application code was written or executed.** These are database guarantees the API layer
   must surface, not replace. Nothing here measures performance, capacity or index efficiency.

## 9. Acceptance gate

| Check | Result |
|-------|--------|
| Migrations `001`–`110` unmodified | ✅ `git status` clean for those paths |
| Exactly one new migration, `111_5H4` | ✅ |
| No migration `112` | ✅ |
| `.sql` migration count | ✅ 111 |
| Alembic revision count | ✅ 111 |
| Alembic heads | ✅ exactly one — `111_5H4` |
| `down_revision` | ✅ `110_5C2` |
| Fresh and incremental chains converge | ✅ identical object dumps |
| `110_5C2` amended? | ✅ no |
| New BYPASSRLS roles | ✅ none |
| Audit write inside the override transaction | ✅ K.10c–K.10e |
| Legacy metric aliasing | ✅ none |
| `hard_limit` nullable (unlimited) | ✅ not over-restricted |
| Integer-only limits imposed | ✅ no — `NUMERIC(18,4)` |
| Tenant consumers require admin privilege | ✅ no |
| Customer resources mutated on limit lowering | ✅ none |
| Open P0 / P1 / P2 / P3 | ✅ 0 / 0 / 0 / 0 |
| Unresolved owner decisions | ✅ 0 |
| Open database blockers | ✅ 0 |
| `__pycache__` / `*.pyc` / `*.pyo` in repository | ✅ none |
| Temporary validation scripts in repository | ✅ none — scratchpad is outside the repository |

### Artifact checksums

| File | SHA-256 | Size |
|------|---------|------|
| `5K/migrations/111_5H4.sql` | `5fe2bc96431236d637dbe2558c0c78d13ab17b7cce647aac3e61db2ac2f4c048` | 44,726 B |
| `5K/alembic/versions/111_5H4.py` | `78b3fda47b22e9e5ef55b66ce4815a415578351a5e786f6977355cdd067e70ea` | 9,227 B |

### Evidence files

- `FAR_111_01_migration_integrity.txt` — fresh/incremental chains, head, object-dump equality
- `FAR_111_02_override_resolver_battery.txt` — Batteries A, B, C, D, F
- `FAR_111_03_security_integration_battery.txt` — Batteries E, G, H, I, J; catalog/ACL/RLS; audit atomicity

### Disposable validation infrastructure — final state

Both disposable containers built for this pass were destroyed **after** every transcript quoted above had been captured and written into the four evidence artifacts. Nothing was discarded that is not reproduced in the evidence files.

```text
$ docker rm -f far_fresh far_incr
far_fresh
far_incr

$ docker ps -a --format '{{.Names}}' | grep -E '^far_(fresh|incr)$' || echo "none"
none
```

No FAR validation container remains on the host. The two throwaway databases went with their containers: `far_v2` (container `far_fresh`, host port 55441, the fresh `001 → 111_5H4` leg and Batteries A–J) and `far_i2` (container `far_incr`, host port 55442, the incremental `… → 110_5C2 → 111_5H4` leg and the object-dump comparison). Both were disposable by construction, were created empty for this pass, and held no project or customer data at any point.

**No unrelated container was stopped, removed or otherwise touched.** The removal named exactly the two FAR containers. The six unrelated containers running on this host (`freellmapi-freellmapi-1`, `learnhouse-nginx-…`, `learnhouse-ssr-fwd-…`, `learnhouse-app-…`, `learnhouse-db-…`, `learnhouse-redis-…`) and the long-exited `charming_rosalind` were never addressed by any command in this pass and remain exactly as they were.

**Repository hygiene at close.** No validation script, harness, helper or temporary SQL file was left inside the repository — the harness lives in the session scratchpad, outside the repository tree. A repository-wide sweep for `__pycache__`, `*.pyc` and `*.pyo` returns nothing. The evidence produced by the two containers survives only as the transcripts in `FAR_111_01_migration_integrity.txt`, `FAR_111_02_override_resolver_battery.txt`, `FAR_111_03_security_integration_battery.txt` and this report, which is the intended end state: the transcripts, not the containers, are the deliverable.
