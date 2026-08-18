-- =================================================================
-- Migration 072 (Phase 5J): audit.audit_events (immutable),
--   audit.audit_chain, fn_insert_audit_event(), fn_compute_chain_hash()
-- down_revision: 071_5J
-- Transaction: yes (requires pgcrypto; installed in migration 001)
-- Source: 5J §17 Migration 072
-- Corrections applied (5K §10.12):
--   - fn_insert_audit_event: calls gen_uuid_v7() → search_path includes public
--     (SET search_path = audit, organization, public, pg_catalog)
--   - fn_compute_chain_hash: does NOT call gen_uuid_v7()
--     (SET search_path = audit, pg_catalog)
--   - session_user authorization logic preserved exactly as source specifies:
--     session_user (not current_user) is correct inside SECURITY DEFINER
-- =================================================================

-- audit.audit_events — truly immutable; no INSERT/UPDATE/DELETE for any role
CREATE TABLE audit.audit_events (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NULL,
  actor_type        TEXT        NOT NULL,
  actor_ref         UUID        NULL,
  actor_name        TEXT        NULL,
  action_kind       TEXT        NOT NULL,
  resource_type     TEXT        NOT NULL,
  resource_id       UUID        NULL,
  outcome           TEXT        NOT NULL,
  failure_reason    TEXT        NULL,
  ip_address        INET        NULL,
  user_agent        TEXT        NULL,
  session_id        TEXT        NULL,
  request_id        UUID        NULL,
  correlation_id    UUID        NULL,
  resource_snapshot JSONB       NULL,
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- NO chain_hash column — by design (§15)
  CONSTRAINT pk_audit_events           PRIMARY KEY (id, occurred_at),
  CONSTRAINT chk_ae_actor_type         CHECK (actor_type IN ('USER','API_KEY','SYSTEM','WORKER','PLUGIN','PLATFORM_ADMIN','INTEGRATION')),
  CONSTRAINT chk_ae_outcome            CHECK (outcome IN ('SUCCESS','FAILURE','PARTIAL')),
  CONSTRAINT chk_ae_action_kind        CHECK (length(action_kind) BETWEEN 1 AND 200),
  CONSTRAINT chk_ae_resource_type      CHECK (length(resource_type) BETWEEN 1 AND 200),
  CONSTRAINT chk_ae_failure_reason_len CHECK (failure_reason IS NULL OR length(failure_reason) <= 1000),
  CONSTRAINT chk_ae_user_agent_len     CHECK (user_agent IS NULL OR length(user_agent) <= 500),
  CONSTRAINT chk_ae_snapshot_size      CHECK (resource_snapshot IS NULL OR length(resource_snapshot::TEXT) <= 4096)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE audit.audit_events_y2026m08 PARTITION OF audit.audit_events FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE audit.audit_events_y2026m09 PARTITION OF audit.audit_events FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit.audit_events_y2026m10 PARTITION OF audit.audit_events FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE audit.audit_events_default   PARTITION OF audit.audit_events DEFAULT;

CREATE INDEX idx_audit_occurred_at ON audit.audit_events USING BRIN (occurred_at);
CREATE INDEX idx_audit_org_occurred ON audit.audit_events (organization_id, occurred_at DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX idx_audit_actor       ON audit.audit_events (actor_ref, occurred_at DESC) WHERE actor_ref IS NOT NULL;
CREATE INDEX idx_audit_resource    ON audit.audit_events (organization_id, resource_type, resource_id, occurred_at DESC) WHERE resource_id IS NOT NULL;
CREATE INDEX idx_audit_action      ON audit.audit_events (organization_id, action_kind, occurred_at DESC);

-- REVOKE ALL from every role including app_platform_admin; SELECT only re-granted below.
-- INSERT is NEVER granted to any role — fn_insert_audit_event() writes as its owning role.
REVOKE ALL ON audit.audit_events FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT SELECT ON audit.audit_events TO app_api, app_readonly, app_worker, app_platform_admin;

ALTER TABLE audit.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.audit_events FORCE ROW LEVEL SECURITY;
-- Tenant roles see only their own org rows; NULL-org (platform) rows excluded.
-- app_platform_admin has BYPASSRLS and sees all rows via SELECT.
CREATE POLICY rls_audit_tenant_select ON audit.audit_events
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

-- audit.audit_chain
CREATE TABLE audit.audit_chain (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NULL,
  date_bucket     DATE        NOT NULL,
  event_count     INTEGER     NOT NULL,
  chain_hash      CHAR(64)    NOT NULL,
  previous_hash   CHAR(64)    NULL,
  batch_size      INTEGER     NOT NULL DEFAULT 1000,
  computed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_audit_chain          PRIMARY KEY (id),
  CONSTRAINT uq_audit_chain_org_date UNIQUE NULLS NOT DISTINCT (organization_id, date_bucket)
);
CREATE INDEX idx_audit_chain_org_date ON audit.audit_chain (organization_id, date_bucket DESC);
REVOKE ALL ON audit.audit_chain FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT SELECT ON audit.audit_chain TO app_api, app_readonly, app_worker, app_platform_admin;
ALTER TABLE audit.audit_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.audit_chain FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_audit_chain_tenant ON audit.audit_chain
  FOR SELECT
  USING (organization_id = organization.current_tenant_id());

-- SECURITY DEFINER: sole audit insertion path
-- search_path includes public because body calls gen_uuid_v7() (5K §10.12)
-- Uses session_user (not current_user) for platform-event authorization:
--   inside SECURITY DEFINER, current_user resolves to the function's owning role,
--   defeating the caller-identity check. session_user is immune to SECURITY DEFINER
--   privilege elevation and correctly identifies the authenticated session role.
CREATE OR REPLACE FUNCTION audit.fn_insert_audit_event(
  p_organization_id   UUID,
  p_actor_type        TEXT,
  p_actor_ref         UUID,
  p_actor_name        TEXT,
  p_action_kind       TEXT,
  p_resource_type     TEXT,
  p_resource_id       UUID,
  p_outcome           TEXT,
  p_failure_reason    TEXT,
  p_ip_address        INET,
  p_user_agent        TEXT,
  p_session_id        TEXT,
  p_request_id        UUID,
  p_correlation_id    UUID,
  p_resource_snapshot JSONB,
  p_is_platform_event BOOLEAN DEFAULT FALSE
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, organization, public, pg_catalog
AS $$
DECLARE
  v_id UUID := gen_uuid_v7();
BEGIN
  IF p_action_kind IS NULL OR length(p_action_kind) < 1 THEN
    RAISE EXCEPTION 'audit: action_kind is required';
  END IF;
  IF p_outcome NOT IN ('SUCCESS','FAILURE','PARTIAL') THEN
    RAISE EXCEPTION 'audit: invalid outcome %', p_outcome;
  END IF;
  IF p_actor_type NOT IN ('USER','API_KEY','SYSTEM','WORKER','PLUGIN','PLATFORM_ADMIN','INTEGRATION') THEN
    RAISE EXCEPTION 'audit: invalid actor_type %', p_actor_type;
  END IF;

  IF p_is_platform_event THEN
    -- session_user is the authenticated session role; unaffected by SECURITY DEFINER.
    -- current_user would resolve to the function owner — wrong for this check.
    IF session_user NOT IN ('app_worker', 'app_platform_admin') THEN
      RAISE EXCEPTION 'audit: caller % is not authorized to create platform audit events', session_user;
    END IF;
    IF p_organization_id IS NOT NULL THEN
      RAISE EXCEPTION 'audit: platform events must have NULL organization_id';
    END IF;
  ELSE
    IF p_organization_id IS NULL THEN
      RAISE EXCEPTION 'audit: tenant audit events must have a non-NULL organization_id';
    END IF;
    IF p_organization_id <> organization.current_tenant_id() THEN
      RAISE EXCEPTION 'audit: organization_id % does not match current tenant context', p_organization_id;
    END IF;
  END IF;

  INSERT INTO audit.audit_events (
    id, organization_id, actor_type, actor_ref, actor_name,
    action_kind, resource_type, resource_id, outcome, failure_reason,
    ip_address, user_agent, session_id, request_id, correlation_id,
    resource_snapshot
  ) VALUES (
    v_id, p_organization_id, p_actor_type, p_actor_ref,
    LEFT(COALESCE(p_actor_name, ''), 200),
    p_action_kind, p_resource_type, p_resource_id, p_outcome,
    LEFT(COALESCE(p_failure_reason, ''), 1000),
    p_ip_address,
    LEFT(COALESCE(p_user_agent, ''), 500),
    p_session_id, p_request_id, p_correlation_id,
    p_resource_snapshot
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_insert_audit_event(UUID,TEXT,UUID,TEXT,TEXT,TEXT,UUID,TEXT,TEXT,INET,TEXT,TEXT,UUID,UUID,JSONB,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_insert_audit_event(UUID,TEXT,UUID,TEXT,TEXT,TEXT,UUID,TEXT,TEXT,INET,TEXT,TEXT,UUID,UUID,JSONB,BOOLEAN)
  TO app_api, app_worker, app_platform_admin;

-- SECURITY DEFINER: batched hash chain computation
-- Does NOT call gen_uuid_v7() → search_path = audit, pg_catalog (no public needed)
-- Uses pgcrypto digest() — installed in migration 001
CREATE OR REPLACE FUNCTION audit.fn_compute_chain_hash(
  p_organization_id UUID,
  p_date            DATE,
  p_batch_size      INTEGER DEFAULT 1000
) RETURNS CHAR(64)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, pg_catalog
AS $$
DECLARE
  v_prev_hash    CHAR(64);
  v_running_hash TEXT;
  v_event_count  INTEGER := 0;
  v_batch_count  INTEGER;
  v_batch_data   TEXT;
  v_new_hash     CHAR(64);
BEGIN
  SELECT chain_hash INTO v_prev_hash
  FROM audit.audit_chain
  WHERE organization_id IS NOT DISTINCT FROM p_organization_id
    AND date_bucket = p_date - INTERVAL '1 day';

  v_running_hash := COALESCE(v_prev_hash, 'GENESIS');

  SELECT COUNT(*) INTO v_event_count
  FROM audit.audit_events
  WHERE organization_id IS NOT DISTINCT FROM p_organization_id
    AND occurred_at >= p_date
    AND occurred_at <  p_date + INTERVAL '1 day';

  IF v_event_count = 0 THEN RETURN NULL; END IF;

  v_batch_count := CEIL(v_event_count::NUMERIC / p_batch_size);

  FOR i IN 0..(v_batch_count - 1) LOOP
    SELECT STRING_AGG(
             id::TEXT || '|' || occurred_at::TEXT || '|' || action_kind || '|' || outcome,
             chr(30) ORDER BY occurred_at, id)
    INTO v_batch_data
    FROM (
      SELECT id, occurred_at, action_kind, outcome
      FROM audit.audit_events
      WHERE organization_id IS NOT DISTINCT FROM p_organization_id
        AND occurred_at >= p_date
        AND occurred_at <  p_date + INTERVAL '1 day'
      ORDER BY occurred_at, id
      LIMIT p_batch_size OFFSET (i * p_batch_size)
    ) batch;

    v_running_hash := encode(
      digest(v_running_hash || '|BATCH' || i::TEXT || '|' || COALESCE(v_batch_data, ''), 'sha256'),
      'hex'
    );
  END LOOP;

  v_new_hash := v_running_hash;

  INSERT INTO audit.audit_chain
    (organization_id, date_bucket, event_count, chain_hash, previous_hash, batch_size)
  VALUES
    (p_organization_id, p_date, v_event_count, v_new_hash, v_prev_hash, p_batch_size)
  ON CONFLICT (organization_id, date_bucket)
  DO UPDATE SET
    chain_hash    = EXCLUDED.chain_hash,
    event_count   = EXCLUDED.event_count,
    previous_hash = EXCLUDED.previous_hash,
    batch_size    = EXCLUDED.batch_size,
    computed_at   = NOW();

  RETURN v_new_hash;
END;
$$;
REVOKE ALL ON FUNCTION audit.fn_compute_chain_hash(UUID, DATE, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.fn_compute_chain_hash(UUID, DATE, INTEGER)
  TO app_worker, app_platform_admin;
