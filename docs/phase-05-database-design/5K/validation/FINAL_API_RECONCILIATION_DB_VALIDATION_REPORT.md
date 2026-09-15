# Final API Reconciliation — DB Remediation Validation Report (migration `110_5C2`)

**Date:** 2026-09-14
**Pass:** FINAL API RECONCILIATION — Final DB-Conformant Closure Pass
**Owner decision in force:** `FAR-OD-01` = **OPTION B** (hard, synchronous, server-authoritative
`ACTIVE_AGENTS` commercial-quota admission). The owner decision is unchanged by this pass; only
its *implementation mechanism* changed.
**Defect closed:** `FAR-P1-01` (reclassified from `FAR-P3-02`) and `DB-BLOCKER-FINAL-API-001`.
**Dependency closed:** `DEP-6E-20`.
**Status of this document:** canonical validation record for migration `110_5C2`. It does not
supersede any Phase 6M document; Phase 6M is not reopened.

---

## 1. Why a DB remediation was required

The design that entered this pass implemented Option B by having the **API/service layer**
execute `SELECT pg_advisory_xact_lock(hashtext('agent_quota:' || org_id))` inside its own
request transaction, then count Agents and decide admission in application code.

Frozen **6A §17.3** permits the API tier no application-level locking of its own: locking is
legitimate only where it is already **encapsulated inside a Phase-5 `SECURITY DEFINER`
function**, or via the existing Campaign Redis `SETNX` mechanism. An API-layer
`pg_advisory_xact_lock` is neither. This is a direct conflict with a frozen architectural rule,
not a documentation nit — which is why it was reclassified from `FAR-P3-02` (P3) to
**`FAR-P1-01` (P1)**.

6A was **not** weakened, reworded or reinterpreted to legalise the previous design. 6A §17.3
stands exactly as frozen, and the implementation was moved to satisfy it.

### Why "the primitive already exists" was not an acceptable answer

`voice.agents` previously granted raw `INSERT` to `app_api`, `app_worker` and
`app_platform_admin`. Any quota check performed above that grant is **advisory**: a caller
holding raw `INSERT` can create an Agent without ever consulting it. An existing enforcement
*primitive* is not an existing *compliant enforcement path*. `DB-BLOCKER-FINAL-API-001` was
raised on exactly that distinction, and the required invariant is:

> Agent creation — via **both** `POST /api/v1/agents` and
> `POST /api/v1/agents/{agent_id}/clone` — must be subject to a hard, synchronous,
> server-authoritative `ACTIVE_AGENTS` admission decision that is concurrency-safe and
> **structurally unbypassable**.

---

## 2. What migration `110_5C2` does

One additive migration, created under the authorisation granted for this closure pass only.
Migrations `001`–`109` are untouched; no `111` exists.

| # | Object | Kind | Purpose |
|---|---|---|---|
| 1 | `voice.fn_assert_agent_quota_admission(UUID)` | `plpgsql`, **SECURITY INVOKER**, owner-only, **no `GRANT` to any role** | Derives the tenant server-side, takes the transaction-scoped advisory lock **internally**, resolves `billing.quota_configs`, counts the canonical ACTIVE_AGENTS set, raises `53400` at the limit |
| 2 | `voice.fn_create_agent(UUID, UUID, TEXT, TEXT)` | **SECURITY DEFINER**, `GRANT EXECUTE TO app_api` | Sole create path; calls (1), then inserts exactly one `DRAFT` Agent |
| 3 | `voice.fn_clone_agent(UUID, UUID, UUID, UUID)` | **SECURITY DEFINER**, `GRANT EXECUTE TO app_api` | Sole clone path; validates source ownership, calls (1), then inserts exactly one `DRAFT` Agent |
| 4 | `REVOKE INSERT ON voice.agents FROM app_api, app_worker, app_platform_admin` | privilege | Closes the raw-INSERT bypass |
| 5 | `COMMENT ON TABLE voice.agents` | documentation | Records that INSERT is available exclusively through (2) and (3) |

This reproduces, object for object, the pattern already frozen in the Phase-5 corpus at
`041_5G.sql` (`workflow.fn_start_workflow_execution` — invariant check + internal
`pg_advisory_xact_lock` + `REVOKE INSERT` from all app roles). It is not a new architectural
idea; it is the project's existing guarded-function idiom applied to the Agent quota.

### Deliberately **not** done

- **No `AgentVersion` is created during Agent creation.** `AgentVersion` creation remains
  publish-only. Proven live: `voice.agent_versions` did not grow across any create or clone.
- **No change to the counted predicate.** It remains
  `organization_id = <current org> AND status IN ('DRAFT','PUBLISHED') AND deleted_at IS NULL`
  — `DEPRECATED` does not consume a slot. No source contradiction was found, so no
  OWNER DECISION REQUIRED was raised.
- **No new API error code.** The `53400` raise maps onto 6K's existing canonical
  `QUOTA_EXCEEDED`; `P0002` maps onto the existing non-disclosing 404.
- **No audit event, domain event or outbox row is emitted by the migration.** The existing 5B
  audit function and 5B transactional outbox remain the only mechanisms. No second event
  mechanism was introduced.
- **No RLS weakening**, no new `BYPASSRLS`, no `PUBLIC` `EXECUTE`, no public DTO expansion.

### Hardening properties (§6), all verified against the live catalog

Explicit `SET search_path = voice, billing, organization, public, pg_catalog` on all three
functions; cross-schema references schema-qualified; org context derived from
`organization.current_tenant_id()` and cross-checked against the argument; cross-tenant source
Agent and source version references rejected; ids from the existing `public.gen_uuid_v7()`
pattern; **no client-supplied `hard_limit`, `current_count` or plan limit is accepted or
trusted** — the limit is read server-side from `billing.quota_configs` inside the lock;
admission fails **before** the INSERT; `pg_advisory_xact_lock` is transaction-scoped so
rollback atomicity and automatic lock release are preserved.

---

## 3. Validation performed

Real PostgreSQL **18.6** (`pgvector/pgvector:pg18` — the pgvector image is required because
`034_5F.sql` creates the `vector` extension). Two **disposable** containers, both destroyed at
the end of the pass. Alembic 1.19.1 / SQLAlchemy 2.0.52 / psycopg2 2.9.12.

| Requirement | Result | Evidence |
|---|---|---|
| §12 fresh `001 → 110` | **PASS** — exit 0, 114 log lines, 0 errors, `current` = `110_5C2 (head)` | `FAR_DB_01` §2 |
| §12 incremental `109 → 110` | **PASS** — exit 0 as one discrete step | `FAR_DB_01` §3 |
| §12 exactly one head | **PASS** — `alembic heads` → `110_5C2 (head)` | `FAR_DB_01` §1 |
| §13 A — ≥2 slots, 2 concurrent creates | **PASS** — 2 simultaneously blocked waiters, both succeed, 0 rejections | `FAR_DB_02` |
| §13 B — exactly 1 slot, 2 concurrent creates | **PASS** — exactly one winner, exactly one `53400` | `FAR_DB_02` |
| §13 C — at limit | **PASS** — rejected, count unchanged | `FAR_DB_02` |
| §13 D — admitted then rollback | **PASS** — 0 rows committed, 0 locks held, slot reusable | `FAR_DB_02` |
| §13 E — clone at boundary, concurrent | **PASS** — exactly one winner, 0 `agent_versions` written | `FAR_DB_02` |
| §13 F — NULL / absent hard limit | **PASS** — unlimited, no rejection | `FAR_DB_02` |
| §13 G — cross-tenant / no tenant context | **PASS** — rejected; cross-tenant and nonexistent sources are byte-identical | `FAR_DB_02` |
| §13 H — raw INSERT as every runtime role | **PASS** — denied for all 8 roles, 0 rows committed | `FAR_DB_03` Part 2 |
| §13 I — publish `DRAFT→PUBLISHED` | **PASS** — count-neutral | `FAR_DB_02` |
| §13 J — deprecate | **PASS** — frees exactly one slot | `FAR_DB_02` |
| §14 `PUBLIC` cannot execute | **PASS** — `has_function_privilege('public', …)` = `f` ×3 | `FAR_DB_03` Part 1 §2 |
| §14 only intended roles can execute | **PASS** — only `app_api`, and on the two endpoint functions only | `FAR_DB_03` Part 1 §3 |
| §14 6E SELECT/UPDATE still functional | **PASS** | `FAR_DB_03` Part 1 §7 |
| §14 no new `app_platform_admin` write bypass | **PASS** — it *lost* INSERT and gained nothing | `FAR_DB_03` Part 1 §4 |
| §14 RLS intact, no accidental `BYPASSRLS` | **PASS** — enabled + forced, policy unchanged, 0 new grants | `FAR_DB_03` Part 1 §5–6 |
| §15 audit/outbox atomicity | **PASS** — 1/1/1 on commit, nothing on rollback, nothing on rejection | `FAR_DB_02` |
| §30 `001`–`109` byte-identical | **PASS** — 218 files, 0 differences | `FAR_DB_01` §4 |

**Concurrency was not simulated.** A controller session held the guarded function's own advisory
key while two worker processes were confirmed, via `pg_locks`, to be *simultaneously blocked
inside the function* before the key was released. The `FAR_DB_02` header documents the harness
in full. Across repeated runs the clone-boundary winner alternated between the two workers,
while the outcome (exactly one winner) never did.

---

## 4. Privilege outcome by role (actual, post-`110`)

| Role | `voice.agents` INSERT | `fn_create_agent` / `fn_clone_agent` EXECUTE | `fn_assert_agent_quota_admission` EXECUTE |
|---|---|---|---|
| `app_api` | ❌ revoked | ✅ granted | ❌ |
| `app_worker` | ❌ revoked | ❌ | ❌ |
| `app_platform_admin` | ❌ revoked | ❌ | ❌ |
| `app_readonly` | ❌ | ❌ | ❌ |
| `app_migration` | ❌ | ❌ | ❌ |
| `app_voice_reconciler` | ❌ | ❌ | ❌ |
| `app_billing_reconciler` | ❌ (no `voice` schema access) | ❌ | ❌ |
| `app_billing_webhook_ingress` | ❌ (no `voice` schema access) | ❌ | ❌ |
| `PUBLIC` | ❌ | ❌ | ❌ |

**No role retains raw `INSERT` on `voice.agents`.** The directive's fallback — "if any role must
retain raw INSERT, document exactly why and prove that it cannot bypass the quota invariant" —
therefore does not apply to any role; the stronger outcome was achievable and was taken.

`app_migration` and `app_platform_admin` hold `BYPASSRLS`. `BYPASSRLS` skips *row-level
policies*, not *table-level ACLs*, so the `REVOKE INSERT` binds them too — demonstrated live,
not assumed (`FAR_DB_03` Part 2).

---

## 5. Migration identity and history integrity

| Item | Value |
|---|---|
| Migration id | `110_5C2` |
| `down_revision` | `109_5B7` |
| New project head | `110_5C2` (exactly one head) |
| SQL file | `docs/phase-05-database-design/5K/migrations/110_5C2.sql` |
| SQL sha256 | `3b76d83515942f6e2193667e7c376e26cd1102bfb7926d080dda297e693d776c` |
| SQL size | 15,044 bytes |
| Alembic file | `docs/phase-05-database-design/5K/alembic/versions/110_5C2.py` |
| Alembic sha256 | `735366afb9141c9f31cb3b8ad05da10d63544f278890667a68431456bbf871d5` |
| Alembic size | 5,810 bytes |
| Downgrade policy | forward-only — `downgrade()` raises `NotImplementedError`, matching the repository's existing policy. No destructive downgrade was invented; reversing `110` would reopen the raw-INSERT bypass. |

**Historical head `109_5B7`, reconfirmed unchanged:**

| File | sha256 |
|---|---|
| `109_5B7.sql` | `a761239d7e63e3d2d982f4dbf7291b81711a24dc051c2577bc44ff46052b0cf3` |
| `109_5B7.py` | `d60f497b9c6c494e051b86d2f086211c77aef8e6b46bc390321e179e83fb9602` |

Both match the values carried in the Phase-6M freeze record byte for byte.

### Head ownership (§29)

- `109_5B7` **remains** the frozen **Phase 6M** head as a matter of project history. Phase 6M is
  **not reopened**; no Phase 6M document or migration changed in this pass.
- `110_5C2` is the **new project head**, owned by the **Final API Reconciliation** pass
  (`FAR-P1-01` / `DB-BLOCKER-FINAL-API-001` / `DEP-6E-20` closure) — **not** by Phase 6M.
- `6M_FINAL_VALIDATION_REPORT.md` states that no `110` was created or planned. That statement
  remains correct **within its own scope**: Phase 6M created no `110`. Migration `110_5C2` was
  authored by a later, separately authorised pass. That document is deliberately left unedited.

---

## 6. Architectural classification (§28)

| Dimension | Changed? | What changed |
|---|---|---|
| **Product behaviour** | No | Option B (hard synchronous Agent-count quota) was already owner-approved as `FAR-OD-01`. The user-visible outcome — a `QUOTA_EXCEEDED` rejection at the limit — is unchanged. |
| **API architecture** | **Yes** | The API/service/repository layer no longer executes `SELECT pg_advisory_xact_lock(...)`. Agent create and clone now call a Phase-5 guarded function. This **restores** compliance with frozen 6A §17.3 rather than departing from it. |
| **DB architecture** | **Yes — additive** | Three new functions and one privilege narrowing. No table, column, index, constraint, RLS policy or domain model was redesigned, dropped or altered. |

`Architecture Changed? = NO` would be an incorrect characterisation of this remediation and is
not claimed anywhere in this pass.

---

## 7. Evidence index

| File | Contents |
|---|---|
| `FAR_DB_01_migration_and_integrity.txt` | Fresh + incremental PG18 legs, single-head proof, `001`–`109` byte-identity, all hashes |
| `FAR_DB_02_quota_concurrency_battery.txt` | Concurrency harness description; §13 A–G, I, J; clone functional behaviour; §15 atomicity |
| `FAR_DB_03_privilege_rls_bypass_battery.txt` | `pg_proc` / ACL / RLS / `BYPASSRLS` inspection; §13 H raw-INSERT battery across all 8 roles |

One report, three evidence files. No per-statement execution logs were generated.

---

## 8. Conclusion

`FAR-P1-01` is **CLOSED BY MIGRATION 110**. `DB-BLOCKER-FINAL-API-001` is **RESOLVED BY
MIGRATION 110**. Option B is enforced synchronously, server-authoritatively, concurrency-safely
and unbypassably at the database boundary, and 6A §17.3 is satisfied **without an exception** —
the API layer acquires no lock of its own. No deferred DB work remains for this item; it is not
carried as future debt.

This report records validation only. It does not declare the Final API Reconciliation approved
or frozen.
