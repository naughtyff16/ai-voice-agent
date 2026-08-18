-- =================================================================
-- Migration 074 (Phase 5J): grants finalization
-- down_revision: 073_5J
-- Transaction: yes
-- Source: 5J §17 Migration 074
-- Key actions:
--   1. Broad SELECT grant to app_readonly for all analytics tables
--   2. REVOKE SELECT on provider_health_5min from app_readonly + app_api
--      (reaffirms denial after the broad grant; defense-in-depth)
--   3. Broad four-privilege grant to app_platform_admin for analytics
--   4. SELECT-only for app_platform_admin on audit schema
--      (audit_events and audit_chain retain SELECT-only per migration 072)
-- =================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA audit     TO app_readonly;

-- Reaffirm provider_health_5min denial after the broad grant above.
-- The broad GRANT SELECT ON ALL TABLES cannot silently reopen access
-- to this platform-internal table for app_readonly or app_api.
REVOKE SELECT ON analytics.provider_health_5min FROM app_readonly, app_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA analytics TO app_platform_admin;

-- audit schema: SELECT-only for app_platform_admin (intentional; not the
-- broad four-privilege grant). audit_events and audit_chain remain write-protected
-- for every role as established in migration 072.
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO app_platform_admin;
