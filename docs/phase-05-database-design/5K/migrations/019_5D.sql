-- =================================================================
-- Migration 019 (Phase 5D): CRM schema functions
-- down_revision: 018_5C
-- Transaction: yes
-- Source: 5D §14.1
-- =================================================================

GRANT USAGE ON SCHEMA crm TO app_api, app_worker, app_readonly, app_platform_admin;

CREATE OR REPLACE FUNCTION crm.prevent_ai_note_body_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.note_source IN ('AI_SUMMARY','AI_INTERACTION') AND OLD.body IS DISTINCT FROM NEW.body THEN
    RAISE EXCEPTION 'AI-generated note body is immutable (DDR-4C-003). note_id=%, source=%', OLD.id, OLD.note_source;
  END IF;
  RETURN NEW;
END;
$$;
