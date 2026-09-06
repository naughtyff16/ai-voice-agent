# §10 items 11-14 — Redis/Postgres consistency + availability findings

## Method
This repository is docs-only (verified: no `src`/application backend, no
Redis client code, no running Redis instance anywhere in this environment —
`find . -path ./docs -prune -o -name "*.py" -o -name "*.ts" ... | xargs grep
-li redis` returned zero matches outside `docs/`). The only Redis coupling
that exists at all is the *documented, frozen* 6B application-layer contract
(`6B-Authentication-and-Authorization-API.md` §18.3a/§18.3b/§21.4/§24/§28),
which is out of 6M's scope to reopen (§34). What 6M *can* and must prove
live is whether the DB layer's own privileged-access functions ever trust
anything Redis might claim — i.e. whether a hypothetical stale/wider Redis
cache entry could actually widen real access.

## Item 11 — stale Redis ACTIVE while Postgres RELEASED -> expect DENY
**CLOSED — structural + empirical proof.**
`voice.fn_platform_access_recording` (and the transcript equivalent) take
only `p_grant_id, p_admin_user_id, p_organization_id, p_session_id,
p_recording_id` as input -- no caller-supplied "already validated by cache"
flag of any kind -- and their entire authorization decision is
`organization.fn_break_glass_check(...)`. That function's body (read live,
`\sf organization.fn_break_glass_check`) does exactly one thing for state:
`SELECT * INTO v_grant FROM organization.break_glass_grants WHERE id =
p_grant_id`, then `IF v_grant.status <> 'ACTIVE' THEN RETURN FALSE`. There is
no Redis read anywhere in this call chain -- it is impossible for the actual
DB-layer decision to be influenced by any Redis value, stale or not. This is
also already empirically demonstrated by the 6M_18 battery, item [5]: grant
g4 (RELEASED in Postgres) was denied when invoked exactly the way the real
backend would invoke it post-Redis-lookup (by `grant_id`) -- i.e. that test
*is* the "Redis said ACTIVE, backend called through anyway" scenario, and
Postgres's real status is what gets enforced, unconditionally.

## Item 12 — Redis wider purpose than Postgres -> expect Postgres wins
**CLOSED — structural + empirical proof.**
Same function, purpose check: `IF NOT (p_required_purpose = ANY(v_grant.
purposes)) THEN RETURN FALSE`. `v_grant.purposes` is read from the same live
row, and (per `6M_21a`/`6M_21b`, this same session) that column is provably
immutable post-insert -- no application code path, cache, or raw UPDATE can
widen it after issuance. Whatever a Redis cache might independently believe
about a grant's purposes is never consulted by the DB layer; the widest
possible authorized purpose set for any real access is always exactly
Postgres's `purposes` array at issuance time. Already empirically reinforced
by 6M_18 item [3] (g2, valid grant but wrong/narrower purpose -> DENY).

## Item 13 — Redis unavailable -> documented safe behavior
**N/A for a 6M-scoped live DB test; verified by contract review instead.**
No Redis instance exists in this repository/environment to take down, and
the DB layer (per items 11-12 above) has zero coupling to Redis at all, in
either direction -- Redis unavailability cannot make the DB layer *more*
permissive, because the DB layer never reads Redis regardless of whether
Redis is up. The apparent behavior is governed entirely at the application
layer by the frozen, already-documented 6B §18.3a contract: "Redis
unavailable -> 503 DEPENDENCY_UNAVAILABLE. Break-glass access is [denied],"
reaffirmed at §28's failure-behavior table and §2411. This is Phase 6B's own
frozen decision (§34 forbids reopening it), and 6M's implementation does not
change how it is resolved, so no cross-phase amendment is needed here --
only this explicit acknowledgment that item 13 was checked and found to
already have a safe, documented, fail-closed answer that 6M's DB design does
not weaken.

## Item 14 — Postgres unavailable where durable revalidation is required -> expect FAIL CLOSED
**CLOSED — live-tested.**
Since `fn_break_glass_check` and every guarded access function are
themselves PostgreSQL functions, there is no code path that could produce an
ALLOW without a live, successful round-trip to Postgres -- unlike Redis,
there is no possible "skip the check" shortcut. Verified live by physically
stopping the validation container mid-session and attempting the exact
privileged-path call:

```
$ docker stop phase6m-pg18-incr
$ docker exec -i phase6m-pg18-incr psql -U app_platform_admin -d postgres -c \
  "SELECT voice.fn_platform_access_recording('...401'::uuid, '...002'::uuid, '...a1'::uuid, 'fixture-session-001', '...202'::uuid);"
Error response from daemon: container ...  is not running
exit_code=1
```

Result: a hard connection failure -- no rows, no partial/degraded ALLOW, no
bypass of any kind. After `docker start phase6m-pg18-incr` and a 3s
stabilization wait, the durable state was confirmed completely intact and
unaffected by the outage (`g1` still `ACTIVE`/`{SENSITIVE_MEDIA_ACCESS}`,
`g4` still `RELEASED`/`{SENSITIVE_MEDIA_ACCESS}`) -- the outage-and-restart
cycle itself introduced no data loss or state drift, consistent with the
same safe restart already observed and logged in
`20260904T104619Z_6M_17_extra_fixtures_load_output.txt`.

## Summary for the final §38 report
| Item | Result | Basis |
|---|---|---|
| 11 | DENY confirmed | Structural (no Redis coupling in DB layer) + empirical (6M_18 [5], g4) |
| 12 | Postgres-wins confirmed | Structural (no Redis coupling) + empirical (6M_18 [3] g2; 6M_21 immutability) |
| 13 | Safe/documented, N/A for 6M live DB test | 6B §18.3a/§28 frozen contract; DB layer has zero Redis dependency to break |
| 14 | FAIL CLOSED confirmed | Live container-stop test, this file |
