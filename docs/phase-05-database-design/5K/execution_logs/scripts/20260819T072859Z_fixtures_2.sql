BEGIN;

INSERT INTO webhooks.webhook_endpoints (id, organization_id, display_name, target_url, signing_secret_ref, topics, status)
VALUES ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000aaaa', 'Test Endpoint', 'https://example.com/hook', 'secret_manager://wh1', ARRAY['call.completed'], 'ACTIVE');

INSERT INTO webhooks.webhook_deliveries (id, organization_id, webhook_endpoint_id, event_type, event_id, payload_json, payload_hash, status, next_attempt_at, created_at)
VALUES ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000aaaa', 'a0000000-0000-0000-0000-000000000001', 'call.completed', gen_uuid_v7(), '{"a":1}', 'hash1', 'PENDING', now(), now());

INSERT INTO plugins.plugins (id, developer_org_id, slug, name, status)
VALUES ('a0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000aaaa', 'test-plugin', 'Test Plugin', 'APPROVED');

INSERT INTO plugins.plugin_versions (id, plugin_id, semver, manifest, status, approved_at)
VALUES
  ('a0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000003', '1.0.0', '{}', 'APPROVED', now()),
  ('a0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000003', '2.0.0', '{}', 'APPROVED', now());

INSERT INTO plugins.plugin_installations (id, organization_id, plugin_id, plugin_version_id, status)
VALUES ('a0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000aaaa', 'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000004', 'ACTIVE');

COMMIT;
