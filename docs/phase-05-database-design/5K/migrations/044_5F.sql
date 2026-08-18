-- =================================================================
-- Migration 044 (Phase 5F): knowledge grants finalization
-- down_revision: 043_5F
-- Transaction: yes
-- Source: 5F §14 Migration 044
-- =================================================================

GRANT SELECT ON knowledge.knowledge_bases    TO app_readonly;
GRANT SELECT ON knowledge.documents          TO app_readonly;
GRANT SELECT ON knowledge.document_versions  TO app_readonly;
GRANT SELECT ON knowledge.ingestion_jobs     TO app_readonly;
GRANT SELECT ON knowledge.document_chunks    TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA knowledge TO app_platform_admin;
