-- =================================================================
-- Migration 016 (Phase 5C): RLS verification and app_readonly grants
-- down_revision: 015_5C
-- Transaction: yes
-- Source: 5C §16.8
-- =================================================================

GRANT SELECT ON voice.call_sessions        TO app_readonly;
GRANT SELECT ON voice.conversations        TO app_readonly;
GRANT SELECT ON voice.turns                TO app_readonly;
GRANT SELECT ON voice.recordings           TO app_readonly;
GRANT SELECT ON voice.transcripts          TO app_readonly;
GRANT SELECT ON voice.transcript_segments  TO app_readonly;
GRANT SELECT ON voice.agents               TO app_readonly;
GRANT SELECT ON voice.agent_versions       TO app_readonly;
GRANT SELECT ON voice.tool_definitions     TO app_readonly;
GRANT SELECT ON voice.tool_executions      TO app_readonly;
GRANT SELECT ON voice.provider_configs     TO app_readonly;
GRANT SELECT ON voice.tenant_phone_numbers TO app_readonly;
GRANT SELECT ON voice.language_evaluation_records TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA voice TO app_platform_admin;
