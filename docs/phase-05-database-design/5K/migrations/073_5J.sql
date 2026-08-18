-- =================================================================
-- Migration 073 (Phase 5J): analytics.event_schema_versions
-- down_revision: 072_5J
-- Transaction: yes
-- Source: 5J §17 Migration 073
-- =================================================================

CREATE TABLE analytics.event_schema_versions (
  id            UUID        NOT NULL DEFAULT gen_uuid_v7(),
  event_type    TEXT        NOT NULL,
  event_version TEXT        NOT NULL,
  status        TEXT        NOT NULL DEFAULT 'ACTIVE',
  introduced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deprecated_at TIMESTAMPTZ NULL,
  notes         TEXT        NULL,
  CONSTRAINT pk_esv          PRIMARY KEY (id),
  CONSTRAINT uq_esv_type_ver UNIQUE (event_type, event_version),
  CONSTRAINT chk_esv_status  CHECK (status IN ('ACTIVE','DEPRECATED','RETIRED'))
);

GRANT SELECT ON analytics.event_schema_versions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON analytics.event_schema_versions TO app_platform_admin;
