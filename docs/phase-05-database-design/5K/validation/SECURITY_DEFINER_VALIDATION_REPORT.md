# SECURITY DEFINER Validation Report — 098_5E1 / 099_5C1 (Final Blocker Remediation)

**Date:** 2026-08-28. **Database:** PostgreSQL 16.10 (`voice_agent_pg16_fresh`,
this pass's own fresh-DB validation target). Full raw transcript:
`execution_logs/20260828T143000Z_69_privilege_and_dispatch_state_machine_tests.txt`.

## Query used

```sql
SELECT n.nspname, p.proname, p.prosecdef,
       (SELECT array_agg(x) FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%') AS search_path_setting
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('voice','campaign') AND p.proname LIKE 'fn_%'
ORDER BY n.nspname, p.proname;
```

## Result (11 functions, all from 098_5E1/099_5C1)

| Schema | Function | `prosecdef` | `search_path` |
|---|---|---|---|
| campaign | `fn_enqueue_contact` | t | `campaign, organization, pg_catalog` |
| campaign | `fn_new_uuid_v7` | t | `public, pg_catalog` |
| campaign | `fn_reserve_dispatch` | t | `campaign, organization, pg_catalog` |
| voice | `fn_begin_provider_submission` | t | `voice, pg_catalog` |
| voice | `fn_claim_dispatch_for_provider_submission` | t | `voice, pg_catalog` |
| voice | `fn_initiate_outbound_call_idempotent` | t | `voice, organization, pg_catalog` |
| voice | `fn_new_uuid_v7` | t | `public, pg_catalog` |
| voice | `fn_reconcile_dispatch_outcome` | t | `voice, pg_catalog` |
| voice | `fn_record_dispatch_ambiguous` | t | `voice, pg_catalog` |
| voice | `fn_record_dispatch_confirmed` | t | `voice, pg_catalog` |
| voice | `fn_record_dispatch_failed` | t | `voice, pg_catalog` |

`prosecdef = t` (SECURITY DEFINER) on every one, as intended — every write
path into `campaign.campaign_contact_identities` and
`voice.call_dispatch_keys` must run with the migration-owner's privileges,
since no other role holds direct write access (Blockers B/C).

`public` appears in `search_path` **only** for the two `fn_new_uuid_v7()`
bridge functions, exactly as designed — every tenant/security-sensitive
function keeps a minimal `search_path` with no ambient `public` schema
resolution.

## PUBLIC EXECUTE check

```sql
SELECT n.nspname, p.proname, has_function_privilege('public', p.oid, 'EXECUTE')
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('voice','campaign') AND p.proname LIKE 'fn_%';
```

All 11 rows: `public_can_execute = f`. `REVOKE ALL ... FROM PUBLIC` followed
by an explicit, minimal `GRANT EXECUTE` per function is confirmed live, not
merely present in the SQL source.

## Function count reconciliation

`SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='voice' AND p.proname LIKE 'fn_%'` → **8**. This corrects the
stale "five new voice.fn_* functions" reference that existed in
`099_5C1.py`'s `downgrade()` docstring before this pass (already undercounting
the pre-remediation six; this pass added two more — `fn_begin_provider_submission`
and `fn_reconcile_dispatch_outcome` — for a genuine total of eight). Every
reference to this count across `099_5C1.py`, `6D-Voice-Call-Agent-APIs.md`,
and `6H-Campaign-APIs.md` was corrected to match this directly-queried
number, not asserted from memory.

## No dynamic SQL

None of the 11 functions use `EXECUTE`-format dynamic SQL anywhere in their
bodies (confirmed by direct source inspection of `098_5E1.sql`/`099_5C1.sql`
— every statement is a literal, static `SELECT`/`INSERT`/`UPDATE`). No
function accepts a table or column name as a parameter.
