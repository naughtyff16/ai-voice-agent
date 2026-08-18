-- Migration 067 (Phase 5J): analytics and audit schemas
-- down_revision: 066_5I
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;
GRANT USAGE ON SCHEMA analytics TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA audit     TO app_api, app_worker, app_readonly, app_platform_admin;
