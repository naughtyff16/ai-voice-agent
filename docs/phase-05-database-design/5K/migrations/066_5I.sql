-- Migration 066 (Phase 5I): grants finalization
-- down_revision: 065_5I
GRANT SELECT ON ALL TABLES IN SCHEMA integrations TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA webhooks     TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA plugins      TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA integrations TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA webhooks     TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA plugins      TO app_platform_admin;
