
-- =================================================================
-- Migration 033 (Phase 5E): Campaign grants finalization
-- down_revision: 032_5E
-- Transaction: yes
-- Source: 5E §14.7
-- =================================================================
GRANT SELECT ON campaign.campaigns         TO app_readonly;
GRANT SELECT ON campaign.contact_lists     TO app_readonly;
GRANT SELECT ON campaign.csv_import_jobs   TO app_readonly;
GRANT SELECT ON campaign.campaign_contacts TO app_readonly;
GRANT SELECT ON campaign.call_jobs         TO app_readonly;
GRANT SELECT ON campaign.campaign_outcomes TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA campaign TO app_platform_admin;

