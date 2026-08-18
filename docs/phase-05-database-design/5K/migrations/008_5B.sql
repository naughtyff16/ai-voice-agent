-- =================================================================
-- Migration 008 (Phase 5B): Grants finalization
-- down_revision: 007_5B
-- Transaction: yes
-- Source: 5B §34.1 (grants finalization pass)
-- =================================================================

-- app_readonly: SELECT on all 5B tables
GRANT SELECT ON identity.users                  TO app_readonly;
GRANT SELECT ON identity.sessions               TO app_readonly;
GRANT SELECT ON identity.password_reset_tokens  TO app_readonly;
GRANT SELECT ON identity.oauth_identities       TO app_readonly;
GRANT SELECT ON identity.api_keys               TO app_readonly;
GRANT SELECT ON organization.organizations      TO app_readonly;
GRANT SELECT ON organization.memberships        TO app_readonly;
GRANT SELECT ON organization.teams              TO app_readonly;
GRANT SELECT ON organization.team_memberships   TO app_readonly;
GRANT SELECT ON organization.roles              TO app_readonly;
GRANT SELECT ON organization.permissions        TO app_readonly;
GRANT SELECT ON organization.role_permissions   TO app_readonly;
GRANT SELECT ON organization.compliance_policies       TO app_readonly;
GRANT SELECT ON organization.data_subject_requests     TO app_readonly;

-- app_platform_admin: full access
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.users                 TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.sessions              TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.password_reset_tokens TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.oauth_identities      TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.api_keys              TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.organizations     TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.memberships       TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.teams             TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.team_memberships  TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.roles             TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.permissions       TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.role_permissions  TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.compliance_policies      TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.data_subject_requests    TO app_platform_admin;
