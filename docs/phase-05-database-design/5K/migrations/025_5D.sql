
-- =================================================================
-- Migration 025 (Phase 5D): CRM grants finalization
-- down_revision: 024_5D
-- Transaction: yes
-- Source: 5D §14.7
-- =================================================================
GRANT SELECT ON crm.contacts              TO app_readonly;
GRANT SELECT ON crm.companies             TO app_readonly;
GRANT SELECT ON crm.deals                 TO app_readonly;
GRANT SELECT ON crm.pipelines             TO app_readonly;
GRANT SELECT ON crm.activities            TO app_readonly;
GRANT SELECT ON crm.tasks                 TO app_readonly;
GRANT SELECT ON crm.notes                 TO app_readonly;
GRANT SELECT ON crm.appointments          TO app_readonly;
GRANT SELECT ON crm.lead_score_records    TO app_readonly;
GRANT SELECT ON crm.crm_field_definitions TO app_readonly;
GRANT SELECT ON crm.consent_records       TO app_readonly;
GRANT SELECT ON crm.contact_suppressions  TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA crm TO app_platform_admin;

