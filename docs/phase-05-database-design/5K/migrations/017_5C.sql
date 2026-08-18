-- =================================================================
-- Migration 017 (Phase 5C): Voice seed data — built-in tool definitions
-- down_revision: 016_5C
-- Transaction: yes
-- Source: 5C §16.9
-- =================================================================

INSERT INTO voice.tool_definitions (id, organization_id, tool_name, description, input_schema, output_schema, is_builtin, timeout_ms, requires_confirmation, max_retries_on_timeout, is_active, created_by)
VALUES
  ('018d0000-0000-7000-b000-000000000001'::UUID, NULL, 'createLead',
   'Creates or updates a CRM contact from information gathered during the call. Use when the caller provides their name, phone, or email.',
   '{"type":"object","properties":{"full_name":{"type":"string"},"phone_e164":{"type":"string"},"email":{"type":"string"}},"required":[]}'::JSONB,
   '{"type":"object","properties":{"contact_id":{"type":"string"},"created":{"type":"boolean"}}}'::JSONB,
   TRUE, 8000, FALSE, 1, TRUE, NULL),
  ('018d0000-0000-7000-b000-000000000002'::UUID, NULL, 'bookAppointment',
   'Books an appointment in the calendar system. Use when the caller confirms a specific date, time, and appointment type.',
   '{"type":"object","properties":{"appointment_type":{"type":"string"},"scheduled_at":{"type":"string","format":"date-time"},"notes":{"type":"string"}},"required":["appointment_type","scheduled_at"]}'::JSONB,
   '{"type":"object","properties":{"appointment_id":{"type":"string"},"confirmed_at":{"type":"string"}}}'::JSONB,
   TRUE, 10000, FALSE, 1, TRUE, NULL),
  ('018d0000-0000-7000-b000-000000000003'::UUID, NULL, 'createTask',
   'Creates a follow-up task for the sales team. Use when a callback or follow-up action is needed.',
   '{"type":"object","properties":{"task_title":{"type":"string"},"due_at":{"type":"string","format":"date-time"},"priority":{"type":"string","enum":["LOW","MEDIUM","HIGH"]}},"required":["task_title"]}'::JSONB,
   '{"type":"object","properties":{"task_id":{"type":"string"}}}'::JSONB,
   TRUE, 6000, FALSE, 1, TRUE, NULL),
  ('018d0000-0000-7000-b000-000000000004'::UUID, NULL, 'lookupKnowledge',
   'Searches the organization knowledge base for relevant information. Use when the caller asks a question that may be in the knowledge base.',
   '{"type":"object","properties":{"query":{"type":"string"},"knowledge_base_ids":{"type":"array","items":{"type":"string"}}},"required":["query"]}'::JSONB,
   '{"type":"object","properties":{"results":{"type":"array"},"total":{"type":"integer"}}}'::JSONB,
   TRUE, 5000, FALSE, 1, TRUE, NULL),
  ('018d0000-0000-7000-b000-000000000005'::UUID, NULL, 'suppressContact',
   'Marks a contact as Do Not Call and removes them from active campaign queues. Use ONLY when the caller explicitly requests not to be called again.',
   '{"type":"object","properties":{"reason":{"type":"string"}},"required":[]}'::JSONB,
   '{"type":"object","properties":{"suppressed":{"type":"boolean"}}}'::JSONB,
   TRUE, 5000, FALSE, 0, TRUE, NULL)
ON CONFLICT (tool_name) WHERE organization_id IS NULL DO NOTHING;
