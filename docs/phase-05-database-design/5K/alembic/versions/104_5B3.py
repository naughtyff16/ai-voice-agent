"""Phase 5B.3 -- wraps controlled amendment migration 104_5B3.sql.

This revision does not define schema itself. It executes the frozen,
canonical SQL file 5K/migrations/104_5B3.sql verbatim via
op.get_bind().exec_driver_sql() (through _frozen_sql.run_frozen_sql, the
shared helper every 5K revision wrapper uses). Do not add DDL here.

104_5B3 is a controlled, additive amendment on top of the validated
001-103 baseline, driven by the Phase 6L freeze-gate remediation pass's
owner-approved sensitive-media policy and the confirmed RBAC
contradiction it identifies: 007_5B.sql's single recording:read /
transcript:read permissions gate both ordinary call/report metadata
AND sensitive recording playback / transcript content, granted by
default to OWNER, ADMIN, MEMBER, and VIEWER alike -- which cannot
express the approved policy (MEMBER/VIEWER = no sensitive content by
default; OWNER/ADMIN = yes; MEMBER only via an explicit custom-role
grant). This revision adds two new permissions --
recording:access_media and transcript:access_content -- granted by
default to OWNER/ADMIN only, without touching recording:read's or
transcript:read's existing grant set (ordinary metadata visibility is
fully preserved for MEMBER/VIEWER, per the governing policy's explicit
instruction not to remove it). Full rationale in the SQL file's own
header comment and in docs/phase-06-api-design/6L-Analytics-Audit-APIs.md.

VALIDATION STATUS: applied and verified against a disposable, locally
self-hosted PostgreSQL 18.6 instance in the authoring session (isolated
data directory and port, never the user's own local PostgreSQL server)
-- fresh chain 001_5B -> ... -> 103_5J2 -> 104_5B3 exit code 0, exactly
one Alembic head (104_5B3), current == head, and the new permission
rows / role_permissions grants confirmed present with the exact grant
set this file's own header specifies (no grant to MEMBER, VIEWER, or
BILLING_ADMIN). See docs/phase-06-api-design/6L-Analytics-Audit-APIs.md
for the full validation evidence and command output.

Revision ID: 104_5B3
Revises: '103_5J2'
"""
from __future__ import annotations

from typing import Sequence, Union

from _frozen_sql import run_frozen_sql

revision: str = '104_5B3'
down_revision: Union[str, None] = '103_5J2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SQL_FILE = '104_5B3.sql'


def upgrade() -> None:
    run_frozen_sql(SQL_FILE)


def downgrade() -> None:
    raise NotImplementedError(
        "Migration 104_5B3 is part of the frozen, forward-only 5K SQL "
        "package (same forward-only policy as every revision since "
        "001_5B). No rollback DDL is authored here; restore from a "
        "database backup taken before this revision if needed. "
        "(Low-risk manual reversal: DELETE FROM organization.role_"
        "permissions WHERE permission_id IN (SELECT id FROM "
        "organization.permissions WHERE name IN ('recording:access_media', "
        "'transcript:access_content')); DELETE FROM organization.permissions "
        "WHERE name IN ('recording:access_media', 'transcript:access_content'); "
        "UPDATE organization.permissions SET display_name = 'Access "
        "Recordings' WHERE name = 'recording:read'; UPDATE organization."
        "permissions SET display_name = 'View Transcripts' WHERE name = "
        "'transcript:read' -- but this reintroduces the confirmed RBAC "
        "contradiction this revision closes (MEMBER/VIEWER would again "
        "have no way to be excluded from sensitive recording playback / "
        "transcript content by default); not recommended.)"
    )
