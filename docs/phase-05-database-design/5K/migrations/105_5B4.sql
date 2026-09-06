-- =================================================================
-- Migration 105 (Phase 5B.4): break-glass purpose authorization +
-- guarded platform-admin organization lifecycle transitions
-- down_revision: 104_5B3
-- Transaction: yes
-- Source: Phase 6M Admin/Platform Control-Plane API design
--
-- Two independent, additive changes, both forward-only extensions of
-- already-frozen persistence (087_5B1, 003_5B/008_5B). Neither migration
-- 001-104 is edited.
--
-- (1) Sensitive-media purpose authorization (6M Block 1 §10-11, Block 2
--     candidate shape "B"). A durable break-glass grant (087_5B1) proves
--     an admin has an active, org-bound, session-bound, time-boxed
--     support session — it does NOT by itself prove *what* that support
--     session is for. §10's blocker requires a second, composed check
--     before any recording/transcript content is served: the grant must
--     also carry a machine-enforceable, allow-listed, immutable-after-
--     creation set of purposes, and the caller must present the specific
--     purpose it needs (e.g. SENSITIVE_MEDIA_ACCESS) for that to succeed.
--     `purposes` is bounded, CHECK-constrained against a fixed allow-list,
--     defended against the forbidden '*' wildcard pattern at the DB layer
--     (belt-and-suspenders on top of the CHECK's own allow-list), and
--     folded into the existing `prevent_bgg_immutable_field_mutation`
--     trigger so it can never be widened after issuance. `justification`
--     (087_5B1) remains free-text evidence only; `purposes` is the actual
--     authorization signal.
--
--     fn_break_glass_grant gains a 6-arg overload carrying p_purposes;
--     the original 5-arg signature is preserved byte-for-byte (087_5B1
--     is not edited) so any caller still invoking it implicitly grants
--     ARRAY['SUPPORT_GENERAL'] only — never SENSITIVE_MEDIA_ACCESS by
--     default, satisfying "no privilege widening" without breaking the
--     original signature's callers.
--
--     fn_break_glass_check() is new: a single boolean-only SECURITY
--     DEFINER function implementing the full six-check runtime contract
--     from 087_5B1/6B §18.3 (grant exists, not released, not expired,
--     admin matches, org matches, session matches) *plus* the purpose
--     check, so application code has one fail-closed call instead of
--     re-deriving the six checks per caller. It returns TRUE/FALSE only
--     — never grant contents — so it cannot itself become a data leak.
--
-- (2) Guarded platform-admin organization suspend/reactivate. 6C §7.6
--     (ADR-6C-02) confirms no SECURITY DEFINER guarded transition
--     function exists anywhere in 5B for organization.organizations —
--     6C's own OWNER self-service suspend uses a raw atomic
--     UPDATE...WHERE status='ACTIVE' RETURNING (CAS), which is
--     appropriate there because the caller (app_api, tenant OWNER) is
--     already scoped to its own org by RLS. Platform Admin has no such
--     natural scoping (BYPASSRLS, cross-tenant by design), so the same
--     raw-CAS shape run over app_platform_admin's broad grant would BE
--     the "Platform Admin = database superuser" anti-pattern 6M Block 1
--     explicitly forbids. fn_platform_suspend_organization /
--     fn_platform_reactivate_organization are SECURITY DEFINER, require
--     organization.is_platform_admin(), require a bounded non-empty
--     reason, use the same function-internal `SELECT ... FOR UPDATE`
--     single-row-lock pattern already proven in 087_5B1's
--     fn_break_glass_release (this is *not* API-layer locking — it is
--     locking performed inside a guarded DB function, 6A's sanctioned
--     exception), enforce the frozen chk_orgs_status transition matrix
--     (ACTIVE<->SUSPENDED only; CANCELLED remains terminal in both
--     directions, matching 6C §7.1/§7.4's "reactivation only reverses a
--     valid suspension, not a terminal state"), and are idempotent
--     (re-suspending an already-SUSPENDED org, or re-activating an
--     already-ACTIVE org, is a successful no-op, not an error). Neither
--     function calls audit.fn_insert_audit_event() internally — 087_5B1's
--     own functions establish the precedent that the guarded state
--     transition and the synchronous audit write (5J §14.5) are two
--     separate calls made by the application layer, not fused inside the
--     DB function; 6M's document records this as the audited call
--     sequence.
--
--     app_platform_admin's raw INSERT/UPDATE/DELETE on
--     organization.organizations (granted in 008_5B.sql, unedited here)
--     is REVOKEd in this migration — SELECT is retained for read-side
--     support views. This does not affect app_api's own INSERT/UPDATE
--     grants (003_5B.sql), which remain in force for 6C's tenant-facing,
--     RLS-scoped, already-frozen self-service org endpoints. Because
--     SECURITY DEFINER functions execute with the privileges of their
--     owning role (not the caller's), stripping app_platform_admin's raw
--     DML does not impair fn_platform_suspend_organization /
--     fn_platform_reactivate_organization; it closes off the only other
--     path (a hand-rolled raw UPDATE/DELETE issued by the REST layer
--     itself) that would otherwise let "Platform Admin" mean "database
--     superuser" for this table, per 6M Block 1's explicit invariant.
-- =================================================================

-- -----------------------------------------------------------------
-- (1) Break-glass purpose authorization
-- -----------------------------------------------------------------

ALTER TABLE organization.break_glass_grants
  ADD COLUMN purposes TEXT[] NOT NULL DEFAULT ARRAY['SUPPORT_GENERAL'];

COMMENT ON COLUMN organization.break_glass_grants.purposes IS
  'Allow-listed, immutable-after-creation set of purposes this grant authorizes (6M §11, Block 2 shape B). Authorization signal — justification is evidence text only, never authorization.';

ALTER TABLE organization.break_glass_grants
  ADD CONSTRAINT chk_bgg_purposes_nonempty
    CHECK (array_length(purposes, 1) IS NOT NULL AND array_length(purposes, 1) BETWEEN 1 AND 5);

ALTER TABLE organization.break_glass_grants
  ADD CONSTRAINT chk_bgg_purposes_allowed
    CHECK (purposes <@ ARRAY[
      'SUPPORT_GENERAL',
      'SUPPORT_BILLING',
      'SUPPORT_ORG_LIFECYCLE',
      'SUPPORT_QUOTA',
      'SENSITIVE_MEDIA_ACCESS',
      'SUPPORT_SECURITY_INCIDENT'
    ]::TEXT[]);

-- Belt-and-suspenders: forbidden wildcard/superuser-shaped values can
-- never enter this column even if the allow-list above is ever edited
-- carelessly in a future migration.
ALTER TABLE organization.break_glass_grants
  ADD CONSTRAINT chk_bgg_purposes_no_wildcard
    CHECK (NOT ('*' = ANY(purposes))
       AND NOT ('ALL' = ANY(purposes))
       AND NOT ('ALL_ACCESS' = ANY(purposes))
       AND NOT ('SUPER_ADMIN' = ANY(purposes)));

-- Extend (CREATE OR REPLACE, not edit-in-place) the existing 087_5B1
-- immutability trigger so purposes is covered by the same
-- identity/terms-are-frozen-after-issuance rule as the original columns.
CREATE OR REPLACE FUNCTION organization.prevent_bgg_immutable_field_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.organization_id IS DISTINCT FROM NEW.organization_id OR
     OLD.admin_user_id   IS DISTINCT FROM NEW.admin_user_id OR
     OLD.justification   IS DISTINCT FROM NEW.justification OR
     OLD.session_id       IS DISTINCT FROM NEW.session_id OR
     OLD.issued_at        IS DISTINCT FROM NEW.issued_at OR
     OLD.expires_at       IS DISTINCT FROM NEW.expires_at OR
     OLD.purposes          IS DISTINCT FROM NEW.purposes THEN
    RAISE EXCEPTION 'break_glass_grants identity/terms fields (including purposes) are immutable. grant_id: %', OLD.id;
  END IF;
  IF OLD.status = 'RELEASED' THEN
    RAISE EXCEPTION 'break_glass_grants % is already RELEASED (terminal state).', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

-- New 6-arg overload. The original 5-arg organization.fn_break_glass_grant
-- (087_5B1) is untouched, so every existing caller keeps issuing
-- SUPPORT_GENERAL-only grants by default.
CREATE OR REPLACE FUNCTION organization.fn_break_glass_grant(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_justification   TEXT,
  p_ttl_seconds     INTEGER,
  p_session_id      TEXT,
  p_purposes        TEXT[]
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
    RAISE EXCEPTION 'fn_break_glass_grant: p_ttl_seconds % out of the conservative technical bound [60, 86400] seconds.', p_ttl_seconds;
  END IF;

  IF p_purposes IS NULL OR array_length(p_purposes, 1) IS NULL THEN
    RAISE EXCEPTION 'fn_break_glass_grant: at least one purpose is required.';
  END IF;

  IF NOT (p_purposes <@ ARRAY[
      'SUPPORT_GENERAL','SUPPORT_BILLING','SUPPORT_ORG_LIFECYCLE',
      'SUPPORT_QUOTA','SENSITIVE_MEDIA_ACCESS','SUPPORT_SECURITY_INCIDENT'
    ]::TEXT[]) THEN
    RAISE EXCEPTION 'fn_break_glass_grant: purposes % contains a value outside the allow-list.', p_purposes;
  END IF;

  INSERT INTO organization.break_glass_grants (
    organization_id, admin_user_id, justification, session_id, expires_at, purposes
  ) VALUES (
    p_organization_id, p_admin_user_id, p_justification, p_session_id,
    NOW() + make_interval(secs => p_ttl_seconds), p_purposes
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_grant(UUID, UUID, TEXT, INTEGER, TEXT, TEXT[]) TO app_api, app_platform_admin;

-- Boolean-only composed runtime check: the full six-check break-glass
-- contract plus the purpose check, in one fail-closed call.
CREATE OR REPLACE FUNCTION organization.fn_break_glass_check(
  p_grant_id         UUID,
  p_admin_user_id    UUID,
  p_organization_id  UUID,
  p_session_id       TEXT,
  p_required_purpose TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_grant organization.break_glass_grants%ROWTYPE;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RETURN FALSE;
  END IF;

  IF p_grant_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT * INTO v_grant
  FROM organization.break_glass_grants
  WHERE id = p_grant_id;

  IF NOT FOUND THEN
    RETURN FALSE;                                    -- check 1: grant exists
  END IF;

  IF v_grant.status <> 'ACTIVE' THEN
    RETURN FALSE;                                    -- check 2: not released
  END IF;

  IF v_grant.expires_at <= NOW() THEN
    RETURN FALSE;                                    -- check 3: not expired
  END IF;

  IF v_grant.admin_user_id IS DISTINCT FROM p_admin_user_id THEN
    RETURN FALSE;                                    -- check 4: admin matches
  END IF;

  IF v_grant.organization_id IS DISTINCT FROM p_organization_id THEN
    RETURN FALSE;                                    -- check 5: org matches
  END IF;

  IF v_grant.session_id IS DISTINCT FROM p_session_id THEN
    RETURN FALSE;                                    -- check 6: session matches
  END IF;

  IF p_required_purpose IS NULL OR length(p_required_purpose) < 1 THEN
    RETURN FALSE;
  END IF;

  IF NOT (p_required_purpose = ANY(v_grant.purposes)) THEN
    RETURN FALSE;                                    -- purpose authorization (6M §10-11)
  END IF;

  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_break_glass_check(UUID, UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.fn_break_glass_check(UUID, UUID, UUID, TEXT, TEXT) TO app_api, app_platform_admin;

-- -----------------------------------------------------------------
-- (2) Guarded platform-admin organization suspend / reactivate
-- -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION organization.fn_platform_suspend_organization(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_reason          TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: caller is not authorized.';
  END IF;

  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: p_admin_user_id is required.';
  END IF;

  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: p_reason must be between 10 and 2000 characters.';
  END IF;

  SELECT status INTO v_status
  FROM organization.organizations
  WHERE id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: organization % not found.', p_organization_id;
  END IF;

  IF v_status = 'SUSPENDED' THEN
    RETURN v_status;                                 -- idempotent no-op
  END IF;

  IF v_status = 'CANCELLED' THEN
    RAISE EXCEPTION 'fn_platform_suspend_organization: organization % is CANCELLED (terminal state) and cannot be suspended.', p_organization_id;
  END IF;

  UPDATE organization.organizations
  SET status = 'SUSPENDED', updated_at = NOW()
  WHERE id = p_organization_id;

  RETURN 'SUSPENDED';
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_platform_suspend_organization(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.fn_platform_suspend_organization(UUID, UUID, TEXT) TO app_api, app_platform_admin;

CREATE OR REPLACE FUNCTION organization.fn_platform_reactivate_organization(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_reason          TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = organization, pg_catalog
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: caller is not authorized.';
  END IF;

  IF p_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: p_admin_user_id is required.';
  END IF;

  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: p_reason must be between 10 and 2000 characters.';
  END IF;

  SELECT status INTO v_status
  FROM organization.organizations
  WHERE id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: organization % not found.', p_organization_id;
  END IF;

  IF v_status = 'ACTIVE' THEN
    RETURN v_status;                                 -- idempotent no-op
  END IF;

  IF v_status = 'CANCELLED' THEN
    RAISE EXCEPTION 'fn_platform_reactivate_organization: organization % is CANCELLED (terminal state) and cannot be reactivated.', p_organization_id;
  END IF;

  UPDATE organization.organizations
  SET status = 'ACTIVE', updated_at = NOW()
  WHERE id = p_organization_id;

  RETURN 'ACTIVE';
END;
$$;
REVOKE ALL ON FUNCTION organization.fn_platform_reactivate_organization(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.fn_platform_reactivate_organization(UUID, UUID, TEXT) TO app_api, app_platform_admin;

-- Close off the raw-DML path: mutation now flows only through the two
-- guarded functions above (or 6C's already-frozen, RLS-scoped app_api
-- path, which is unaffected). SELECT is retained for platform-admin
-- read-side support views (org directory/support detail, 6M §14-15).
REVOKE INSERT, UPDATE, DELETE ON organization.organizations FROM app_platform_admin;
