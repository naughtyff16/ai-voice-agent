"""Phase 5B.6 -- wraps controlled hardening migration 108_5B6.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/108_5B6.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

108_5B6 is a forward, additive migration closing finding F-26-1,
surfaced during the Phase 6M STRICT FINAL REMEDIATION review's live
re-verification of 107_5B5.sql's sensitive-voice-content hardening.

107_5B5.sql's REVOKE ALL ON voice.transcript_segments FROM
app_platform_admin + column-restricted GRANT SELECT (excluding `text`)
was applied only to the PARENT relation name of a RANGE (created_at)
partitioned table. PostgreSQL does not propagate a parent-level REVOKE/
GRANT to already-existing child partitions -- each partition carries its
own independent ACL, and voice.transcript_segments' five partitions
(014_5C.sql) still held their original, unrestricted DELETE, INSERT,
SELECT, UPDATE grant to app_platform_admin from 018_5C.sql's blanket
schema-wide grant. Live-confirmed: `SELECT text FROM voice.
transcript_segments` (parent) correctly denies app_platform_admin, but
`SELECT text FROM voice.transcript_segments_2026_09` (naming a child
partition directly) succeeded with no permission error -- a live,
unremediated bypass of Phase 6M's P0 requirement that PLATFORM_ADMIN
identity/BYPASSRLS alone must not be sufficient to read transcript
content outside purpose-bound break-glass.

This is the same class of defect already fixed twice before in this
package against a different partitioned table (workflow.
workflow_executions) -- see 076_5K1.sql's FIX 2 and 100_5G1.sql's
defensive per-partition pg_inherits loop. 108_5B6.sql applies the
identical technique: walks pg_inherits for voice.transcript_segments's
current child partitions and applies the same REVOKE ALL + column-
restricted GRANT SELECT 107_5B5.sql already applies to the parent, then
asserts (via has_table_privilege/has_column_privilege) that no
partition is left over-privileged, raising if so.

The other four tables 107_5B5.sql hardened (voice.recordings, voice.
transcripts, voice.conversations, voice.turns) are confirmed NOT
partitioned -- this migration touches voice.transcript_segments only.
voice.fn_platform_access_transcript (107_5B5.sql) is unchanged and
remains the sole guarded path to segment text content.

Nothing here reopens Phase 6L's frozen decisions, changes the tenant-
facing transcript:read/access_content permission model, or touches any
table/function/role outside voice.transcript_segments's partitions.

Revision ID: 108_5B6
Revises: 107_5B5
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '108_5B6'
down_revision: Union[str, None] = '107_5B5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '108_5B6.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 108_5B6 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Manual reversal would require re-issuing GRANT SELECT, "
        "INSERT, UPDATE, DELETE ON voice.transcript_segments_2026_09, "
        "voice.transcript_segments_2026_10, voice.transcript_segments_"
        "2026_11, voice.transcript_segments_2026_12, voice."
        "transcript_segments_default TO app_platform_admin for each "
        "existing partition -- this recreates finding F-26-1, the "
        "child-partition sensitive-content bypass this migration "
        "closes, and is NOT recommended outside of restoring a "
        "pre-108 backup.)"
    )
