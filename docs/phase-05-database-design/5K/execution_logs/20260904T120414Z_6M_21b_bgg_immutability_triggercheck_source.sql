-- Run as postgres (superuser/table owner -- the only principal in this
-- schema holding UPDATE on organization.break_glass_grants). This proves
-- layer 2: even a principal that DOES have raw UPDATE rights is blocked by
-- trg_bgg_immutable_fields from mutating or widening purposes (§10 items
-- 9-10), and from making ANY further change once a grant is RELEASED
-- (terminal state). This models the internal path a SECURITY DEFINER
-- function (owned by postgres) would take -- proving the DB-level guard
-- holds independent of which principal or code path attempts the write.
\set ON_ERROR_STOP off

\echo '=== [I4] pre-state: g1 purposes/status ==='
SELECT id, status, purposes FROM organization.break_glass_grants
WHERE id = 'f0000000-0000-4000-8000-000000000401';

\echo '=== [I5] item 10: widen g1 purposes (append SUPPORT_BILLING to existing SENSITIVE_MEDIA_ACCESS) -> expect exception ==='
UPDATE organization.break_glass_grants
SET purposes = ARRAY['SENSITIVE_MEDIA_ACCESS','SUPPORT_BILLING']
WHERE id = 'f0000000-0000-4000-8000-000000000401';

\echo '=== [I6] item 9: mutate g1 purposes to a wholly different single purpose -> expect exception ==='
UPDATE organization.break_glass_grants
SET purposes = ARRAY['SUPPORT_BILLING']
WHERE id = 'f0000000-0000-4000-8000-000000000401';

\echo '=== [I7] control: an UPDATE that does NOT touch any protected field (e.g. a no-op status re-set to its current value) -> expect ALLOW (proves trigger is scoped to protected fields, not a table-wide freeze) ==='
UPDATE organization.break_glass_grants
SET status = status
WHERE id = 'f0000000-0000-4000-8000-000000000401';

\echo '=== [I8] additional control: g4 is already RELEASED (terminal). Attempt ANY update at all, even to a non-listed field -> expect exception (terminal-state guard, second IF in the trigger) ==='
UPDATE organization.break_glass_grants
SET status = 'RELEASED'
WHERE id = 'f0000000-0000-4000-8000-000000000404';

\echo '=== [I9] post-attempt state: g1 and g4 unchanged by any of the rejected attempts ==='
SELECT id, status, purposes FROM organization.break_glass_grants
WHERE id IN ('f0000000-0000-4000-8000-000000000401','f0000000-0000-4000-8000-000000000404')
ORDER BY id;
