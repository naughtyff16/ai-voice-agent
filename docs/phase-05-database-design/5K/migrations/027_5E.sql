-- =================================================================
-- Migration 027 (Phase 5E): Campaign schema grant and functions
-- down_revision: 026_5D
-- Transaction: yes
-- Source: 5E §14.1
-- =================================================================
GRANT USAGE ON SCHEMA campaign TO app_api, app_worker, app_readonly, app_platform_admin;
