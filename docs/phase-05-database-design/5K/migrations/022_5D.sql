-- =================================================================
-- Migration 022 (Phase 5D): crm.activities (partitioned), crm.tasks, crm.notes
-- down_revision: 021_5D
-- Transaction: yes
-- Source: 5D §14.4
-- =================================================================

CREATE TABLE crm.activities (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  occurred_at     TIMESTAMPTZ NOT NULL,
  organization_id UUID        NOT NULL,
  activity_type   TEXT        NOT NULL,
  subject_type    TEXT        NOT NULL,
  subject_id      UUID        NOT NULL,
  actor_type      TEXT        NOT NULL,
  actor_ref       UUID        NULL,
  actor_name      TEXT        NULL,
  summary         TEXT        NULL,
  payload         JSONB       NOT NULL DEFAULT '{}',
  call_ref        UUID        NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_activities        PRIMARY KEY (id, occurred_at),
  CONSTRAINT chk_act_type         CHECK (activity_type IN ('CALL','EMAIL','SMS','WHATSAPP','MEETING','NOTE','TASK_COMPLETED','STAGE_CHANGE','SCORE_CHANGE','QUALIFICATION_CHANGE','AI_INTERACTION','CAMPAIGN_CONTACT')),
  CONSTRAINT chk_act_subject_type CHECK (subject_type IN ('CONTACT','DEAL','COMPANY')),
  CONSTRAINT chk_act_actor_type   CHECK (actor_type IN ('HUMAN','AI_AGENT','SYSTEM')),
  CONSTRAINT chk_act_summary_len  CHECK (summary IS NULL OR length(summary) <= 1000)
) PARTITION BY RANGE (occurred_at);

COMMENT ON COLUMN crm.activities.actor_name IS 'pii:name — captured at activity creation time';
CREATE INDEX idx_act_subject ON crm.activities (organization_id, subject_type, subject_id, occurred_at DESC);
CREATE INDEX idx_act_type    ON crm.activities (organization_id, activity_type, occurred_at DESC);
CREATE INDEX idx_act_call_ref ON crm.activities (call_ref) WHERE call_ref IS NOT NULL;
CREATE INDEX idx_act_org_time_brin ON crm.activities USING BRIN (organization_id, occurred_at);
ALTER TABLE crm.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.activities FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_activities_read   ON crm.activities FOR SELECT USING (organization_id = organization.current_tenant_id());
CREATE POLICY rls_activities_insert ON crm.activities FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT ON crm.activities TO app_api, app_worker;
REVOKE UPDATE, DELETE ON crm.activities FROM app_api, app_worker;

DO $$
DECLARE v_start DATE; v_end DATE; v_name TEXT; v_month DATE;
BEGIN
  v_month := date_trunc('month', CURRENT_DATE);
  FOR i IN 0..3 LOOP
    v_start := v_month + (i || ' months')::INTERVAL;
    v_end   := v_start + '1 month'::INTERVAL;
    v_name  := 'activities_' || to_char(v_start, 'YYYY_MM');
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='crm' AND c.relname=v_name) THEN
      EXECUTE format('CREATE TABLE crm.%I PARTITION OF crm.activities FOR VALUES FROM (%L) TO (%L)', v_name, v_start, v_end);
    END IF;
  END LOOP;
END $$;
CREATE TABLE crm.activities_default PARTITION OF crm.activities DEFAULT;

CREATE TABLE crm.tasks (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  title           TEXT        NOT NULL,
  subject_type    TEXT        NOT NULL,
  subject_id      UUID        NOT NULL,
  assigned_to     UUID        NULL,
  due_at          TIMESTAMPTZ NOT NULL,
  priority        TEXT        NOT NULL DEFAULT 'MEDIUM',
  status          TEXT        NOT NULL DEFAULT 'OPEN',
  created_by      UUID        NULL,
  created_by_type TEXT        NOT NULL DEFAULT 'HUMAN',
  completed_at    TIMESTAMPTZ NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_tasks               PRIMARY KEY (id),
  CONSTRAINT chk_tasks_subject_type CHECK (subject_type IN ('CONTACT','DEAL','COMPANY')),
  CONSTRAINT chk_tasks_priority     CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT')),
  CONSTRAINT chk_tasks_status       CHECK (status IN ('OPEN','COMPLETED','CANCELLED')),
  CONSTRAINT chk_tasks_creator_type CHECK (created_by_type IN ('HUMAN','AI_AGENT','SYSTEM')),
  CONSTRAINT chk_tasks_title_len    CHECK (length(title) BETWEEN 1 AND 200)
);
CREATE INDEX idx_tasks_subject    ON crm.tasks (organization_id, subject_type, subject_id);
CREATE INDEX idx_tasks_assigned   ON crm.tasks (organization_id, assigned_to, status) WHERE status = 'OPEN';
CREATE INDEX idx_tasks_due        ON crm.tasks (organization_id, due_at) WHERE status = 'OPEN';
CREATE INDEX idx_tasks_org_status ON crm.tasks (organization_id, status);
CREATE TRIGGER trg_tasks_updated_at BEFORE UPDATE ON crm.tasks FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE crm.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.tasks FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_tasks_tenant ON crm.tasks FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON crm.tasks TO app_api, app_worker;

CREATE TABLE crm.notes (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  subject_type    TEXT        NOT NULL,
  subject_id      UUID        NOT NULL,
  body            TEXT        NOT NULL DEFAULT '',
  author_ref      UUID        NULL,
  author_type     TEXT        NOT NULL DEFAULT 'HUMAN',
  note_source     TEXT        NOT NULL DEFAULT 'HUMAN',
  pinned_at       TIMESTAMPTZ NULL,
  deleted_at      TIMESTAMPTZ NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_notes               PRIMARY KEY (id),
  CONSTRAINT chk_notes_subject_type CHECK (subject_type IN ('CONTACT','DEAL','COMPANY')),
  CONSTRAINT chk_notes_source       CHECK (note_source IN ('HUMAN','AI_SUMMARY','AI_INTERACTION','SYSTEM')),
  CONSTRAINT chk_notes_author_type  CHECK (author_type IN ('HUMAN','AI_AGENT','SYSTEM')),
  CONSTRAINT chk_notes_body_len     CHECK (length(body) <= 10000)
);
COMMENT ON COLUMN crm.notes.body IS 'pii:voice — AI_SUMMARY/AI_INTERACTION notes contain voice-derived content';
CREATE INDEX idx_notes_subject ON crm.notes (organization_id, subject_type, subject_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_notes_pinned  ON crm.notes (organization_id, subject_type, subject_id) WHERE pinned_at IS NOT NULL AND deleted_at IS NULL;
CREATE TRIGGER trg_notes_updated_at BEFORE UPDATE ON crm.notes FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ai_note_immutable BEFORE UPDATE ON crm.notes FOR EACH ROW EXECUTE FUNCTION crm.prevent_ai_note_body_mutation();
ALTER TABLE crm.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.notes FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_notes_tenant ON crm.notes FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE, DELETE ON crm.notes TO app_api, app_worker;
