-- =================================================================
-- Migration 018 (Phase 5C): Voice grants finalization
-- down_revision: 017_5C
-- Transaction: yes
-- Source: 5C §16.9 (grants finalization placeholder)
-- =================================================================

-- Final cross-cutting grant verification pass for voice schema
-- Ensure app_platform_admin has full access (idempotent re-grant)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA voice TO app_platform_admin;

-- Confirm USAGE grants are present
GRANT USAGE ON SCHEMA voice TO app_api, app_worker, app_readonly, app_platform_admin;
