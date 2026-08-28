# Campaign Identity Table Privilege Validation Report

**Date:** 2026-08-28 (Phase 6H Final Blocker Remediation pass, Blocker B)
**Scope:** live proof, on PostgreSQL 16.10, that `app_worker` can no longer
directly `INSERT` into `campaign.campaign_contact_identities`, and that the
guarded path (`campaign.fn_enqueue_contact()`) is unaffected. Full raw
transcript:
`execution_logs/20260828T143000Z_69_privilege_and_dispatch_state_machine_tests.txt`.

## The defect

Before this pass, `098_5E1.sql` granted `SELECT, INSERT` on
`campaign.campaign_contact_identities` directly to `app_worker`. Because
this table's `PRIMARY KEY (campaign_id, contact_id)` is the *entire*
uniqueness guarantee `fn_enqueue_contact()` relies on (the table exists
specifically because `campaign_contacts` is partitioned by `imported_at`
and cannot enforce this uniqueness itself), a caller with direct `INSERT`
could create an identity row with no corresponding `campaign_contacts` row
— an orphan that would permanently block every future legitimate
`fn_enqueue_contact()` call for that `(campaign_id, contact_id)` pair (its
`ON CONFLICT DO NOTHING` would always lose to the orphan, which has no
`campaign_contacts` row to report back as the "winner").

## The fix, proven live

`INSERT` was removed from `app_worker`'s grant; only `SELECT` remains
(alongside `app_api`/`app_readonly`, also read-only). `campaign.
fn_enqueue_contact()` is `SECURITY DEFINER`, owned by the migration-running
role, which already holds full privileges on every object it creates
independent of any `GRANT` statement — so removing the direct grant does not
touch the guarded function's own ability to write.

### Test 1 — direct INSERT as app_worker: DENIED

```sql
SET ROLE app_worker;
INSERT INTO campaign.campaign_contact_identities (...) VALUES (...);
```
```
ERROR:  permission denied for table campaign_contact_identities
```

### Test 2 — the guarded function still succeeds for app_worker

```sql
SET ROLE app_worker;
SELECT * FROM campaign.fn_enqueue_contact(<org A>, <campaign A>, <contact 1>, '+911234500002', 5, false, 'PENDING');
```
```
         campaign_contact_id          |           imported_at            | is_new
--------------------------------------+----------------------------------+--------
 01a048cf-5c67-7b76-a40d-0d1a908ba749 | 2026-08-28 20:09:04.292461+05:30 | t
```

### Test 3 — duplicate enqueue via the guarded function is still idempotent

Same call repeated: `is_new=f`, identical `campaign_contact_id` and
`imported_at` — no duplicate, no orphan, exactly the same behavior as before
this privilege change.

### Test 4 — the pre-existing cross-tenant ownership guard is unaffected

```sql
SET ROLE app_worker;
SELECT * FROM campaign.fn_enqueue_contact(<org B>, <campaign A (belongs to org A)>, <contact>, ...);
```
```
ERROR:  fn_enqueue_contact: campaign 00000000-...-a5 not found for organization 00000000-...-b1
```

This confirms the privilege change is additive-only: it closes the
direct-INSERT bypass without weakening (or being weakened by) the
tenant-ownership check fixed in the prior remediation pass.

## Final grant matrix (verified directly, not asserted)

```
      grantee       | table_schema |         table_name          |                          privs
--------------------+--------------+-----------------------------+---------------------------------------------------------
 app_api            | campaign     | campaign_contact_identities | SELECT
 app_platform_admin | campaign     | campaign_contact_identities | DELETE,INSERT,SELECT,UPDATE
 app_readonly       | campaign     | campaign_contact_identities | SELECT
 app_worker         | campaign     | campaign_contact_identities | SELECT
 postgres           | campaign     | campaign_contact_identities | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
```

No role except `app_platform_admin` (an explicit, documented operator-only
escape hatch, unchanged by this pass) and the table owner holds `INSERT`,
`UPDATE`, or `DELETE`.
