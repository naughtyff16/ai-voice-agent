-- =================================================================
-- Migration 005 (Phase 5B): RLS verification — identity schema
-- down_revision: 004_5B
-- Transaction: yes
-- Source: 5K §4.1 — verification-only migration
-- Purpose: Asserts that identity.api_keys RLS policy created in
--          migration 002 is present. No CREATE POLICY. No DDL.
-- =================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies
    WHERE schemaname = 'identity'
      AND tablename  = 'api_keys'
      AND policyname = 'rls_api_keys_tenant'
  ) THEN
    RAISE EXCEPTION
      'Migration 005 precondition FAILED: '
      'policy rls_api_keys_tenant on identity.api_keys not found. '
      'Ensure migration 002 completed successfully before running 005.';
  END IF;
END
$$;
