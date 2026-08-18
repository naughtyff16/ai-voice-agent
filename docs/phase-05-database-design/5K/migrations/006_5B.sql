-- =================================================================
-- Migration 006 (Phase 5B): RLS verification — organization schema
-- down_revision: 005_5B
-- Transaction: yes
-- Source: 5K §4.1 — verification-only migration
-- Purpose: Asserts 11 organization-schema RLS policies created in
--          migrations 003/004 are present. No CREATE POLICY. No DDL.
-- =================================================================

DO $$
DECLARE
  v_missing TEXT := '';
  v_pol     RECORD;
  v_expected CONSTANT TEXT[][] := ARRAY[
    ARRAY['organization', 'memberships',           'rls_memberships_tenant'],
    ARRAY['organization', 'teams',                 'rls_teams_tenant'],
    ARRAY['organization', 'team_memberships',      'rls_team_memberships_tenant'],
    ARRAY['organization', 'roles',                 'rls_roles_read'],
    ARRAY['organization', 'roles',                 'rls_roles_insert'],
    ARRAY['organization', 'roles',                 'rls_roles_update'],
    ARRAY['organization', 'roles',                 'rls_roles_delete'],
    ARRAY['organization', 'role_permissions',      'rls_role_permissions_read'],
    ARRAY['organization', 'role_permissions',      'rls_role_permissions_modify'],
    ARRAY['organization', 'compliance_policies',   'rls_compliance_policies_tenant'],
    ARRAY['organization', 'data_subject_requests', 'rls_data_subject_requests_tenant']
  ];
BEGIN
  FOR v_pol IN
    SELECT v_expected[i][1] AS sch,
           v_expected[i][2] AS tbl,
           v_expected[i][3] AS pol
    FROM generate_subscripts(v_expected, 1) i
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policies
      WHERE schemaname = v_pol.sch
        AND tablename  = v_pol.tbl
        AND policyname = v_pol.pol
    ) THEN
      v_missing := v_missing
                || v_pol.sch || '.' || v_pol.tbl || '.' || v_pol.pol || ' ';
    END IF;
  END LOOP;

  IF v_missing <> '' THEN
    RAISE EXCEPTION
      'Migration 006 precondition FAILED: missing RLS policies: %. '
      'Ensure migrations 003 and 004 completed successfully before running 006.',
      rtrim(v_missing);
  END IF;
END
$$;
