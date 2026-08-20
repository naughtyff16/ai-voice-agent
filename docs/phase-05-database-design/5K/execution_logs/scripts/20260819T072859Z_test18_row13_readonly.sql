SELECT session_user;
INSERT INTO audit.audit_events (organization_id, actor_type, action_kind, outcome) VALUES ('00000000-0000-0000-0000-00000000aaaa', 'USER', 'test.readonly', 'SUCCESS');
