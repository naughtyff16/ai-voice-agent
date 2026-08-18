-- =================================================================
-- Migration 001 (Phase 5B): Extensions, schemas, roles, core functions
-- down_revision: None (root)
-- Transaction: yes
-- Corrections applied:
--   - Roles created with no password literal (5K §10.1)
--   - get_user_organization_ids() NOT created here (depends on
--     organization.memberships which does not exist until 003)
-- =================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS organization;
CREATE SCHEMA IF NOT EXISTS voice;
CREATE SCHEMA IF NOT EXISTS crm;
CREATE SCHEMA IF NOT EXISTS campaign;
CREATE SCHEMA IF NOT EXISTS knowledge;
CREATE SCHEMA IF NOT EXISTS workflow;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS integrations;
CREATE SCHEMA IF NOT EXISTS webhooks;
CREATE SCHEMA IF NOT EXISTS plugins;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

-- Application roles — no password literal; set via secrets manager post-migration
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_api') THEN
    CREATE ROLE app_api LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_worker') THEN
    CREATE ROLE app_worker LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_readonly') THEN
    CREATE ROLE app_readonly LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_migration') THEN
    CREATE ROLE app_migration LOGIN BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_platform_admin') THEN
    CREATE ROLE app_platform_admin LOGIN BYPASSRLS;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA identity     TO app_api, app_worker, app_platform_admin;
GRANT USAGE ON SCHEMA organization TO app_api, app_worker, app_readonly, app_platform_admin;

-- UUIDv7 generation (DB-side fallback; application layer generates before insert)
CREATE OR REPLACE FUNCTION gen_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_millis  BIGINT := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
  v_rand    BYTEA  := gen_random_bytes(10);
BEGIN
  RETURN (
    lpad(to_hex(v_millis), 12, '0') ||
    '7' ||
    lpad(to_hex(get_byte(v_rand,0) * 256 + get_byte(v_rand,1)), 3, '0') ||
    '-' ||
    lpad(to_hex((get_byte(v_rand,2) & 63) | 128), 2, '0') ||
    lpad(to_hex(get_byte(v_rand,3)), 2, '0') ||
    '-' ||
    encode(substring(v_rand FROM 4 FOR 6), 'hex')
  )::UUID;
END;
$$;

-- Auto-update updated_at trigger function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- RLS context functions
CREATE OR REPLACE FUNCTION organization.current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::UUID
$$;

CREATE OR REPLACE FUNCTION organization.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT current_setting('app.is_platform_admin', true) = 'true'
$$;
