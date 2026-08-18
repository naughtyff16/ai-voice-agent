-- =================================================================
-- Migration 046 (Phase 5G): workflow/prompt/memory grants finalization
-- down_revision: 045_5G
-- Transaction: yes
-- Source: 5G §16.5
-- =================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA workflow TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA prompt   TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA memory   TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA workflow TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA prompt   TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA memory   TO app_platform_admin;
