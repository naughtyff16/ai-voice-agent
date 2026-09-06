# Migrations 105_5B4 / 106_5H3 — Validation Report (Phase 6M, Admin/Platform Control-Plane APIs)

**Date:** 2026-09-03 (live validation pass, post fail-open security fix).
**Scope:** validation of `105_5B4.sql` (organization suspend/reactivate,
break-glass grant/check/release) and `106_5H3.sql` (quota-override lifecycle,
guarded refund saga, and a critical `organization.is_platform_admin()`
fail-open fix discovered during this pass), authored to support
`docs/phase-06-api-design/6M-Admin-Platform-APIs.md`.

## 0. Validation method

Two genuine, disposable, locally self-hosted PostgreSQL 18 (`pgvector/pgvector:pg18`)
Docker containers — `phase6m-pg18-fresh` (port 55433, db `phase6m_fresh`) and
`phase6m-pg18-incr` (port 55434, db `phase6m_incr`) — separate from any
shared/production database. Both were rebuilt from scratch (`docker rm -f` +
recreate) specifically to re-validate from a clean state after the security
fix below was added, so every result in this report reflects the final,
post-fix bytes of `106_5H3.sql`. Raw evidence lives under
`../execution_logs/`, files prefixed `20260903T01` (initial pre-fix pass,
where the bug was discovered) through `20260903T02` (post-fix re-validation),
plus the durable, reusable scripts `6M_pre105_fixture_insert.sql`,
`6M_final_adversarial_security_battery.sql`, `6M_race_a.sql`, `6M_race_b.sql`.

---

## 1. Critical finding: fail-open authorization bug (discovered, fixed, re-validated this pass)

**Discovery.** Live adversarial testing (battery TEST 7: "an unauthenticated
caller — session never touches `app.is_platform_admin` — must be REJECTED by
`fn_platform_suspend_organization`") unexpectedly returned `SUSPENDED` instead
of raising `caller is not authorized`. Evidence:
`20260903T014000Z_6M_08_adversarial_security_battery.txt` /
`20260903T014500Z_6M_09_adversarial_security_battery_part2.txt`
(pre-fix) and `20260903T023500Z_6M_17_final_adversarial_security_battery.txt`
(pre-fix, confirming reproducibility on a rebuilt fixture set).

**Root cause.** `001_5B.sql`'s `organization.is_platform_admin()` is:
```sql
SELECT current_setting('app.is_platform_admin', true) = 'true'
```
`current_setting(name, missing_ok=>true)` returns SQL NULL — not `'false'`,
not empty string — for a custom GUC that has never been `SET`/`RESET` in the
session. `NULL = 'true'` evaluates to NULL, and PL/pgSQL's
`IF NOT <NULL-valued expression> THEN ...` treats that as false, silently
**skipping** the guard's own `RAISE EXCEPTION`. Confirmed via
`pg_get_functiondef`/`\sf` that this exact pattern (`IF NOT
organization.is_platform_admin() THEN RAISE ...`) is used, without exception,
in every platform-admin-gated function that existed at the time:
`fn_platform_suspend_organization`, `fn_platform_reactivate_organization`,
`fn_break_glass_grant` (`087_5B1.sql`/`105_5B4.sql`), plus 6M's own
`fn_platform_set_quota_override`, `fn_platform_reserve_refund`,
`fn_platform_settle_refund`, `fn_platform_fail_refund` (`106_5H3.sql`); and
`fn_break_glass_check` uses the same NULL-as-skip failure mode with
`RETURN FALSE` in place of `RAISE`. RLS policies using
`USING (organization.is_platform_admin())` (e.g. `087_5B1.sql:83`) are **not**
subject to this failure mode — a NULL qualifier in an RLS `USING` clause
excludes the row (fails closed), unlike PL/pgSQL's `IF NOT` (fails open).

**Fix.** `001_5B.sql` is frozen and may never be edited. `106_5H3.sql` (an
open, editable Phase 6M migration) reissues the function via
`CREATE OR REPLACE FUNCTION organization.is_platform_admin()`, wrapping the
comparison in `COALESCE`:
```sql
SELECT COALESCE(current_setting('app.is_platform_admin', true), 'false') = 'true'
```
PL/pgSQL resolves function calls by name/schema at execution time, so this
single redefinition transparently closes the gap for every existing and
future caller — including the still-frozen `087_5B1.sql` functions and the
`break_glass_grants` RLS policy — without touching or re-checksumming
`001_5B.sql`.

**Post-fix re-validation (this report's live evidence):**
- `\sf organization.is_platform_admin()` on `phase6m-pg18-incr` confirms the
  `COALESCE` body is active (`20260903T024500Z_6M_19`).
- A fresh session that never touches `app.is_platform_admin` now returns
  proper `f`, not NULL (`20260903T024500Z_6M_19`).
- Full 28-test adversarial battery re-run: TEST 7 now correctly raises
  `fn_platform_suspend_organization: caller is not authorized.`; every other
  test (1-6, 8-28) passes identically to the pre-fix run — a line-by-line
  `ERROR` sweep confirms zero regressions (`20260903T025000Z_6M_20`).
- TEST 27R (true-concurrency double-refund race, §4 below) re-run
  post-fix and still passes, confirming the fix touched only the
  authorization guard, not the `FOR UPDATE` locking logic
  (`20260903T025500Z_6M_21`).

---

## 2. Fresh-chain validation

`phase6m-pg18-fresh`, empty at start: `alembic upgrade head` (`001_5B →
106_5H3`), exit code 0. `alembic current`/`heads` both `106_5H3 (head)`.
Evidence: `20260903T024000Z_6M_18`.

## 3. Independent incremental-chain validation, with pre-105 fixtures

`phase6m-pg18-incr`: `alembic upgrade 104_5B3` → pre-105 fixture rows
inserted directly against `104_5B3` state (`6M_pre105_fixture_insert.sql`: 2
users, 1 organization, 1 billing account, 1 invoice, 1 payment attempt, 1
refund, 1 quota config, 1 break-glass grant — see fixture-ID scheme below) →
`alembic upgrade head` (`104_5B3 → 105_5B4 → 106_5H3`, exit 0, **with the
legacy fixture rows already present**) → all 8 fixture categories confirmed
present, `break_glass_grants.purposes` correctly backfilled to
`{SUPPORT_GENERAL}` by `106_5H3.sql`. Evidence: `20260903T024500Z_6M_19`.

**Fixture ID scheme:** `11111111-...`/`22222222-...` (owner/admin users),
`33333333-...` (organization), `44444444-...` (billing account),
`55555555-...` (invoice), `66666666-...` (payment attempt, 1000.0000 INR
SUCCEEDED), `77777777-...` (refund, 200.0000 INR SUCCEEDED), `88888888-...`
(quota config, `CALL_MINUTES`), `99999999-...` (break-glass grant).

## 4. Adversarial security battery (28 sequential tests + 1 true-concurrency race)

Full battery script: `6M_final_adversarial_security_battery.sql`. Post-fix
run: `20260903T025000Z_6M_20`. Highlights:

| # | Test | Result |
|---|---|---|
| 1-6 | `app_platform_admin` cannot raw-INSERT/UPDATE/DELETE `organizations`/`billing.refunds`/`billing.payment_attempts`/`billing.quota_configs` | PASS (permission denied) |
| 7 | Unauthenticated caller rejected by `fn_platform_suspend_organization` | **PASS post-fix** (was FAIL pre-fix — the bug) |
| 8-12 | Suspend/reactivate lifecycle incl. idempotency and terminal-state (`CANCELLED`) rejection | PASS |
| 13R-19R | Break-glass purpose scoping: correct purpose passes, wrong purpose denied, wildcard/superuser purposes (`*`, `ALL_ACCESS`, `SUPER_ADMIN`, mixed-array wildcard) rejected at issuance, `purposes` immutable post-insert | PASS |
| 20R | `fn_break_glass_check` rejects (returns FALSE, not error) when caller lacks `is_platform_admin` GUC | PASS |
| 21R-23R | Quota override: out-of-allow-list metric rejected, valid metric accepted with auto-derived `unit_label`, idempotent upsert | PASS |
| 24-26 | Refund reserve rejects over-balance amount, reserve+settle succeeds, settle is idempotent | PASS |
| 27P | Fail on already-SUCCEEDED refund rejected (terminal state) | PASS |
| 27R | True-concurrency double-refund race (`6M_race_a.sql`/`6M_race_b.sql`, run concurrently via backgrounded `psql`) — two 400.00 INR reserves against a 700.00 INR remaining balance | PASS — exactly one succeeded (`PENDING`), the other correctly rejected with `REFUND_AMOUNT_EXCEEDED`; evidence `20260903T025500Z_6M_21` |
| 28 | Reserve then fail (idempotent), settle-after-fail rejected (terminal state) | PASS |

## 5. Checksums

```
102_5H2.sql  73b9f7aed921ccc373cc634372ac7ac75c0490872d55af21116c3ff182445b3d  127,971 bytes  (unchanged, frozen)
103_5J2.sql  fba53d7ecc09b345335ea4aea600ca2ffbb288aed42775ff986dcabf8e8dfb87   13,907 bytes  (unchanged, frozen)
104_5B3.sql  4b8ab081e9064c96ecdbc59545fa9af3ffd878032a47baff45af6ee6a2ca8183    6,649 bytes  (unchanged, frozen)
105_5B4.sql  a16262285c3a4f1d290817940a8ed28e6c4ad6348f6ec2cc19f21ce2eb779a57   15,898 bytes  (final)
106_5H3.sql  d589017d89d329f123f990faedb823574ce9f109b3600d6104b98447d50f2ac0   21,430 bytes  (final, post security fix)
```
102-104 confirmed byte-identical to the checksums recorded before Phase 6M
began (`20260903T000000Z_6L_13_final_checksums_and_sizes.txt`). Evidence:
`20260903T030000Z_6M_22_post_fix_final_checksums_and_sizes.txt`.

## 6. Conclusion

Every check in this report is **PASS** against the final, post-fix bytes of
`105_5B4.sql`/`106_5H3.sql`. The one genuine defect found during this phase's
own adversarial validation — the `is_platform_admin()` fail-open NULL bug —
was root-caused, fixed without touching any frozen migration, and
re-validated from a clean rebuild with zero regressions across the full
security battery and the true-concurrency refund race. This report does not
itself declare Phase 6M frozen; see
`docs/phase-06-api-design/6M-Admin-Platform-APIs.md` for the authoritative
phase-status statement.
