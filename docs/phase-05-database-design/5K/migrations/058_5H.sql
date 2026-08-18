-- Migration 058 (Phase 5H): billing grants finalization
-- down_revision: 057_5H
GRANT SELECT ON ALL TABLES IN SCHEMA billing TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA billing TO app_platform_admin;
