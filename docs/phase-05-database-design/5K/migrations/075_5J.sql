-- =================================================================
-- Migration 075 (Phase 5J): seed analytics.event_schema_versions
-- down_revision: 074_5J
-- Transaction: yes
-- Source: 5J §17 Migration 075
-- Idempotent: ON CONFLICT (event_type, event_version) DO NOTHING
-- =================================================================

INSERT INTO analytics.event_schema_versions (event_type, event_version, status) VALUES
  ('call.ended',                       '1', 'ACTIVE'),
  ('call.failed',                      '1', 'ACTIVE'),
  ('call.started',                     '1', 'ACTIVE'),
  ('conversation.turn_completed',      '1', 'ACTIVE'),
  ('conversation.completed',           '1', 'ACTIVE'),
  ('contact.qualified',                '1', 'ACTIVE'),
  ('contact.converted',                '1', 'ACTIVE'),
  ('contact.lead_status_changed',      '1', 'ACTIVE'),
  ('appointment.booked',               '1', 'ACTIVE'),
  ('campaign.contact.call_attempted',  '1', 'ACTIVE'),
  ('campaign.contact.qualified',       '1', 'ACTIVE'),
  ('campaign.completed',               '1', 'ACTIVE'),
  ('campaign.outcome_computed',        '1', 'ACTIVE'),
  ('usage.event_recorded',             '1', 'ACTIVE'),
  ('invoice.payment_succeeded',        '1', 'ACTIVE'),
  ('invoice.generated',                '1', 'ACTIVE'),
  ('tool_execution.succeeded',         '1', 'ACTIVE'),
  ('tool_execution.failed',            '1', 'ACTIVE'),
  ('webhook.delivery_succeeded',       '1', 'ACTIVE'),
  ('webhook.delivery_failed',          '1', 'ACTIVE'),
  ('webhook.delivery_dead_lettered',   '1', 'ACTIVE'),
  ('provider.failed',                  '1', 'ACTIVE'),
  ('provider.failover_triggered',      '1', 'ACTIVE'),
  ('provider.circuit_opened',          '1', 'ACTIVE'),
  ('provider.circuit_closed',          '1', 'ACTIVE')
ON CONFLICT (event_type, event_version) DO NOTHING;
