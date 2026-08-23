-- =================================================================
-- Migration 087 (Phase 5B.1): durable break-glass grant persistence
-- down_revision: 086_5H1
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, DEP-6B-01
--
-- No durable table exists anywhere in 5B or any later migration
-- (confirmed by repo-wide search) — break-glass grant/release actions
-- are already durably audited (BREAK_GLASS_GRANTED/RELEASED, 5J §14.3),
-- but the live lifecycle state of a grant (is it still active, when
-- does it expire) has only ever existed in an interim Redis TTL key
-- (6B §18.3/§24). Columns mirror that interim record's own field shape,
-- as cited in 6B: admin_user_id, session_id, organization_id,
-- expires_at, a released flag.
--
-- status only ever holds ACTIVE/RELEASED — EXPIRED is computed at read
-- time from expires_at < NOW(), exactly the pattern already established
-- for crm.contact_suppressions (5D), not invented here.
--
-- No app role gets any direct DML grant on this table — INSERT only via
-- fn_break_glass_grant(), the ACTIVE->RELEASED transition only via
-- fn_break_glass_release(), both requiring organization.is_platform_admin()
-- (the same session-GUC-based platform-admin check used elsewhere in
-- this schema for RLS platform-admin exceptions — not a DB-role check,
-- since app_api serves both tenant and platform-admin traffic). RLS
-- restricts even SELECT to platform-admin sessions; tenant-facing
-- visibility of break-glass access into their own org is a separate,
-- undecided product question and is not built here.
--
-- Redis remains the fast-path cache; this table is the durable source
-- of truth a reconciliation job can fall back to after cache loss.
-- =================================================================

CREATE TABLE organization.break_glass_grants (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID        NOT NULL,
  admin_user_id     UUID        NOT NULL,
  justification     TEXT        NOT NULL,
  session_id        TEXT        NULL,
  issued_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMPTZ NOT NULL,
  status            TEXT        NOT NULL DEFAULT 'ACTIVE',
  released_at       TIMESTAMPTZ NULL,
  released_by       UUID        NULL,

  CONSTRAINT pk_break_glass_grants        PRIMARY KEY (id),
  CONSTRAINT chk_bgg_status                CHECK (status IN ('ACTIVE','RELEASED')),
  CONSTRAINT chk_bgg_justification_len     CHECK (length(justification) BETWEEN 10 AND 2000),
  CONSTRAINT chk_bgg_expires_after_issued  CHECK (expires_at > issued_at),
  CONSTRAINT chk_bgg_released_consistency  CHECK ((status = 'RELEASED') = (released_at IS NOT NULL))
);
COMMENT ON COLUMN organization.break_glass_grants.admin_user_id IS 'logical ref: identity.users.id — granting platform admin (no cross-schema FK, 5A convention)';
COMMENT ON COLUMN organization.break_glass_grants.released_by   IS 'logical ref: identity.users.id';
COMMENT ON COLUMN organization.break_glass_grants.session_id    IS 'Correlates with the interim Redis grant record (6B §18.3), where present.';

CREATE INDEX idx_bgg_org_active ON organization.break_glass_grants (organization_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_bgg_admin      ON organization.break_glass_grants (admin_user_id, issued_at DESC);
CREATE INDEX idx_bgg_expires    ON organization.break_glass_grants (expires_at) WHERE status = 'ACTIVE';

CREATE OR REPLACE FUNCTION organization.prevent_bgg_immutable_field_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id OR
     OLD.admin_user_id   IS DISTINCT FROM NEW.admin_user_id OR
     OLD.justification   IS DISTINCT FROM NEW.justification OR
     OLD.session_id       IS DISTINCT FROM NEW.session_id OR
     OLD.issued_at        IS DISTINCT FROM NEW.issued_at OR
     OLD.expires_at       IS DISTINCT FROM NEW.expires_at THEN
    RAISE EXCEPTION 'break_glass_grants identity/terms fields are immutable. grant_id: %', OLD.id;
  END IF;
  IF OLD.status = 'RELEASED' THEN
    RAISE EXCEPTION 'break_glass_grants % is already RELEASED (terminal state).', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_bgg_immutable_fields BEFORE UPDATE ON organization.break_glass_grants
  FOR EACH ROW EXECUTE FUNCTION organization.prevent_bgg_immutable_field_mutation();

ALTER TABLE organization.break_glass_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.break_glass_grants FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_bgg_platform_admin_only ON organization.break_glass_grants
  FOR ALL USING (organization.is_platform_admin());

REVOKE ALL ON organization.break_glass_grants FROM app_api, app_worker, app_readonly, app_platform_admin;
GRANT SELECT ON organization.break_glass_grants TO app_api, app_worker, app_readonly, app_platform_admin;

CREATE OR REPLACE FUNCTION organization.fn_break_glass_grant(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_justification   TEXT,
  p_ttl_seconds     INTEGER,
  p_session_id      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, public, pg_catalog
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_break_glass_grant: caller is not authorized to grant break-glass access.';
  END IF;

  IF p_ttl_seconds NOT BETWEEN 60 AND 86400 THEN
    RAISE EXCEPTION 'fn_break_glass_grant: p_ttl_seconds % out of the conservative technical bound [60, 86400] seconds. The exact operational TTL policy is owned by 6B/product, not asserted here.', p_ttl_seconds;
  END IF;

  INSERT INTO organization.break_glass_grants (
    organization_id, admin_user_id, justification, session_id, expires_at
  ) VALUES (
    p_organization_id, p_admin_user_id, p_justification, p_session_id,
    NOW() + make_interval(secs => p_ttl_seconds)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT) TO app_api, app_platform_admin;

CREATE OR REPLACE FUNCTION organization.fn_break_glass_release(
  p_grant_id    UUID,
  p_released_by UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_break_glass_release: caller is not authorized to release break-glass grants.';
  END IF;

  SELECT status INTO v_status
  FROM organization.break_glass_grants
  WHERE id = p_grant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_break_glass_release: grant % not found.', p_grant_id;
  END IF;

  IF v_status = 'RELEASED' THEN
    RETURN; -- idempotent no-op
  END IF;

  UPDATE organization.break_glass_grants
  SET status = 'RELEASED', released_at = NOW(), released_by = p_released_by
  WHERE id = p_grant_id;
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_release(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_release(UUID, UUID) TO app_api, app_platform_admin;
