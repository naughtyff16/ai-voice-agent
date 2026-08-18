-- Migration 059 (Phase 5I): integrations, webhooks, plugins schemas
-- down_revision: 058_5H
CREATE SCHEMA IF NOT EXISTS integrations;
CREATE SCHEMA IF NOT EXISTS webhooks;
CREATE SCHEMA IF NOT EXISTS plugins;
GRANT USAGE ON SCHEMA integrations TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA webhooks     TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA plugins      TO app_api, app_worker, app_readonly, app_platform_admin;
