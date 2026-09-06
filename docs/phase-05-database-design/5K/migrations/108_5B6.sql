-- =====================================================================
-- Migration 108 (Phase 5B.6) -- closes finding F-26-1: app_platform_admin
-- child-partition grant bypass on voice.transcript_segments.
--
-- Forward-only, additive. Does NOT edit 001-107 (frozen). down_revision
-- = '107_5B5'.
--
-- Root cause (same class of defect already fixed twice before in this
-- package -- see 076_5K1.sql's FIX 2 and 100_5G1.sql's defensive
-- per-partition loop, both against workflow.workflow_executions):
-- PostgreSQL checks table privileges against the EXACT relation named
-- in a query. A GRANT/REVOKE issued against a partitioned PARENT
-- table's name does NOT propagate to that table's already-existing
-- CHILD partitions -- each partition is a separate physical relation
-- with its own independent ACL.
--
-- 107_5B5.sql's sensitive-voice-content hardening ((C) in its own
-- header) issued:
--   REVOKE ALL ON voice.transcript_segments FROM app_platform_admin;
--   GRANT SELECT (<metadata columns, excluding text>) ON
--     voice.transcript_segments TO app_platform_admin;
-- against the PARENT relation name only. voice.transcript_segments is
-- RANGE (created_at) partitioned (014_5C.sql) with five physical child
-- partitions (transcript_segments_2026_09/_10/_11/_12/_default). Those
-- five partitions never had 018_5C.sql's original blanket `GRANT
-- SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA voice TO
-- app_platform_admin` revoked from them individually -- 107_5B5.sql's
-- REVOKE/GRANT pair, naming only the parent, left every partition's own
-- unrestricted DELETE, INSERT, SELECT, UPDATE grant to app_platform_
-- admin fully intact.
--
-- Live-confirmed (6M §26/§29 re-verification, this pass): as
-- app_platform_admin, `SELECT text FROM voice.transcript_segments`
-- correctly fails with `permission denied for table
-- transcript_segments` (the parent-level hardening works as intended),
-- but `SELECT text FROM voice.transcript_segments_2026_09` -- naming a
-- child partition directly -- succeeds with no permission error, and a
-- DELETE against the same partition (`DELETE FROM voice.
-- transcript_segments_2026_09 WHERE false`) also succeeds. This is a
-- live, unremediated violation of Phase 6M's P0 sensitive-content
-- requirement: PLATFORM_ADMIN identity/BYPASSRLS alone must not be
-- sufficient to read recording/transcript content outside purpose-
-- bound break-glass. The other four tables 107_5B5.sql hardened
-- (voice.recordings, voice.transcripts, voice.conversations,
-- voice.turns) are confirmed NOT partitioned -- this defect is specific
-- to voice.transcript_segments.
--
-- Fix: defensively walk pg_inherits for every existing child partition
-- of voice.transcript_segments and apply the identical REVOKE ALL +
-- column-restricted GRANT SELECT that 107_5B5.sql already applies to
-- the parent, so parent and children present an identical restricted
-- surface. voice.fn_platform_access_transcript (107_5B5.sql) remains
-- the sole guarded path to segment text content; this migration does
-- not touch that function.
--
-- Future partitions: this schema's transcript_segments partitions are
-- created ahead of time by an explicit DO block (014_5C.sql, four
-- months at a time) rather than by an automated pg_partman-style
-- maintenance job -- there is no scheduled/triggered partition-creation
-- routine anywhere in this migration package to hook a default-
-- privilege fix into. Any future migration that runs 014_5C.sql's same
-- "CREATE TABLE voice.<name> PARTITION OF voice.transcript_segments
-- FOR VALUES ..." pattern to add new future-dated partitions MUST
-- immediately apply this same REVOKE ALL + column-restricted GRANT
-- SELECT to the new partition in the SAME migration, exactly as it
-- must already GRANT SELECT, INSERT to app_api/app_worker per
-- 014_5C.sql's own pattern -- ALTER DEFAULT PRIVILEGES does not apply
-- to partition attachment, and PostgreSQL provides no native
-- "partitions inherit parent ACL forever" mode. This requirement is
-- restated in docs/phase-06-api-design/6M-Admin-Platform-APIs.md's
-- operational runbook section so it is not silently missed the next
-- time a partition is added.
-- =====================================================================

DO $$
DECLARE
  v_partition regclass;
BEGIN
  FOR v_partition IN
    SELECT c.oid::regclass
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'voice.transcript_segments'::regclass
  LOOP
    EXECUTE format('REVOKE ALL ON %s FROM app_platform_admin', v_partition);
    EXECUTE format(
      'GRANT SELECT (id, created_at, organization_id, transcript_id, '
      'conversation_id, call_id, sequence_number, speaker, is_partial, '
      'start_ms, end_ms, confidence, language, stt_provider_id, '
      'provider_segment_id) ON %s TO app_platform_admin',
      v_partition
    );
  END LOOP;
END
$$;

-- Defensive verification: assert every child partition's ACL for
-- app_platform_admin now excludes table-level SELECT/INSERT/UPDATE/
-- DELETE (only the column-restricted SELECT above should remain, which
-- has_table_privilege reports as table-level SELECT only when EVERY
-- column is covered -- it is not, since `text` is excluded -- so this
-- must report false for the unqualified privilege check). Raises if
-- any partition is left over-privileged, so this migration fails loudly
-- rather than silently leaving the gap open on a future re-run against
-- a differently-shaped database.
DO $$
DECLARE
  v_partition regclass;
BEGIN
  FOR v_partition IN
    SELECT c.oid::regclass
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'voice.transcript_segments'::regclass
  LOOP
    IF has_table_privilege('app_platform_admin', v_partition, 'SELECT')
       OR has_table_privilege('app_platform_admin', v_partition, 'INSERT')
       OR has_table_privilege('app_platform_admin', v_partition, 'UPDATE')
       OR has_table_privilege('app_platform_admin', v_partition, 'DELETE')
    THEN
      RAISE EXCEPTION
        'migration 108_5B6: partition % still reports a table-level '
        'privilege for app_platform_admin after remediation -- F-26-1 '
        'is not closed', v_partition;
    END IF;
    IF NOT has_column_privilege(
      'app_platform_admin', v_partition, 'sequence_number', 'SELECT'
    ) THEN
      RAISE EXCEPTION
        'migration 108_5B6: partition % unexpectedly lost metadata '
        'SELECT for app_platform_admin', v_partition;
    END IF;
    IF has_column_privilege('app_platform_admin', v_partition, 'text', 'SELECT') THEN
      RAISE EXCEPTION
        'migration 108_5B6: partition % still grants column-level '
        'SELECT on text to app_platform_admin -- content bypass not '
        'closed', v_partition;
    END IF;
  END LOOP;
END
$$;
