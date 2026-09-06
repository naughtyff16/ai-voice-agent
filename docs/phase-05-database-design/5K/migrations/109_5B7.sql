-- =====================================================================
-- Migration 109 (Phase 5B.7) -- Phase 6M Admin Platform API guarded
-- DB-layer closure: Platform Admin manual-credit / billing-adjustment /
-- plan-catalog / CPA / tax guarded commands, safe identity support
-- views + guarded forced-session-revocation, and webhook-delivery DML
-- narrowing.
--
-- down_revision = '108_5B6'. Forward-only, additive. Does NOT edit
-- 001-108 (frozen). This is the final migration of the Phase 6M
-- closure pass -- no 110 follows to repair this file; any defect found
-- during validation is fixed in place here before freeze.
--
-- Source: docs/phase-06-api-design/6M-Admin-Platform-APIs.md
--   Sections 57, 58, 62, 63, 64, 65 (65.1-65.7).
-- Cross-referenced: docs/phase-05-database-design/5J-Analytics-Audit-
--   Schema.md Section 14.3/14.5 (audit.fn_insert_audit_event contract).
--
-- Problem being closed: prior to this migration, app_platform_admin
-- (the human Platform Admin operator role, distinct from app_worker's
-- automated/system principal) held direct table-level INSERT/UPDATE/
-- DELETE on multiple financial and identity tables, and direct EXECUTE
-- on several worker-facing SECURITY DEFINER functions that accept a
-- caller-supplied created_by_ref / actor identity with no server-side
-- authorization check, no input validation beyond the underlying
-- table's own CHECK constraints, and no atomic audit trail. Every
-- mutation surface a human Platform Admin operator can legitimately
-- reach must instead go through a purpose-built SECURITY DEFINER
-- wrapper that: (1) re-verifies organization.is_platform_admin() as
-- its first statement, (2) performs real input validation against the
-- actual schema (not invented columns/enum values), (3) derives the
-- audit actor / created_by_ref server-side rather than trusting a
-- client-supplied value, and (4) writes an immutable audit.audit_events
-- row via audit.fn_insert_audit_event() in the SAME local transaction
-- as its mutation. Direct table/function grants that bypass this
-- wrapper are then revoked from app_platform_admin; app_worker's own
-- direct grants (used by the automated billing/CPA engines) are left
-- untouched throughout this migration.
--
-- Every new function below follows the exact template already
-- established by 107_5B5.sql's fn_break_glass_grant/fn_break_glass_
-- release and fn_platform_set_quota_override:
--   IF NOT organization.is_platform_admin() THEN RAISE EXCEPTION ...
--   -- validation --
--   -- mutation (direct INSERT/UPDATE, or delegation to an existing
--   --   underlying function) --
--   PERFORM set_config('app.tenant_id', p_organization_id::text, true);
--     -- only for tenant-scoped mutations; global-catalog functions
--     -- (Plan/PlanVersion/PlanPrice/Tax) omit this and instead pass
--     -- p_organization_id = NULL / p_is_platform_event = TRUE to the
--     -- audit call, per audit.fn_insert_audit_event's own branching
--     -- (072_5J.sql): platform events require session_user IN
--     -- ('app_worker','app_platform_admin') AND organization_id IS
--     -- NULL; tenant events require organization_id = current tenant.
--   PERFORM audit.fn_insert_audit_event(...);
--   RETURN ...;
--   REVOKE ALL ... FROM PUBLIC; REVOKE EXECUTE ... FROM app_api;
--   GRANT EXECUTE ... TO app_platform_admin;
--
-- No table 001-108 DDL shape changes; no column added/removed on any
-- existing table. audit.audit_events.action_kind/resource_type are
-- open TEXT columns with only length CHECKs (072_5J.sql) -- the 14 new
-- action_kind literals introduced below require no enum/CHECK
-- migration.
-- =====================================================================


-- =====================================================================
-- PART A -- Platform Admin manual credit (6M section 65.1)
-- =====================================================================

CREATE OR REPLACE FUNCTION billing.fn_platform_apply_credit(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_credit_type     TEXT,
  p_amount          NUMERIC(18,4),
  p_reason          TEXT,
  p_expires_at      TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_billing_account_id UUID;
  v_currency            CHAR(3);
  v_credit_id           UUID;
  v_created_by_ref      TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_apply_credit: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_apply_credit: admin_user % not found.', p_admin_user_id;
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'fn_platform_apply_credit: amount must be positive.';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_apply_credit: reason is required.';
  END IF;

  IF p_credit_type NOT IN ('PROMOTIONAL','MANUAL','REFUND_CREDIT','PRORATION_CREDIT') THEN
    RAISE EXCEPTION 'fn_platform_apply_credit: credit_type % is not recognized.', p_credit_type;
  END IF;

  -- Freeze-gate remediation (P1 #2): currency is NEVER accepted from
  -- the caller -- it is derived server-side from the billing account's
  -- own credit_balance_currency, the same column
  -- fn_billing_apply_credit's ledger bookkeeping is itself keyed to.
  -- This removes any possibility of a client-supplied currency
  -- mismatch/override.
  SELECT id, credit_balance_currency INTO v_billing_account_id, v_currency
  FROM billing.billing_accounts
  WHERE organization_id = p_organization_id;

  IF v_billing_account_id IS NULL THEN
    RAISE EXCEPTION 'fn_platform_apply_credit: no billing account for organization %.', p_organization_id;
  END IF;

  -- created_by_ref is derived server-side from the trust-checked caller
  -- identity -- the client never authors this field.
  v_created_by_ref := 'platform_admin:' || p_admin_user_id::text;

  v_credit_id := billing.fn_billing_apply_credit(
    p_organization_id, v_billing_account_id, p_credit_type, p_amount,
    v_currency, p_reason, p_expires_at, v_created_by_ref
  );

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_CREDIT_APPLIED', 'credit_ledger_entry', v_credit_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'credit_type', p_credit_type, 'amount', p_amount, 'currency', v_currency,
      'reason', p_reason, 'expires_at', p_expires_at,
      'billing_account_id', v_billing_account_id
    ),
    FALSE
  );

  RETURN v_credit_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_apply_credit(UUID, UUID, TEXT, NUMERIC, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_apply_credit(UUID, UUID, TEXT, NUMERIC, TEXT, TIMESTAMPTZ) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_apply_credit(UUID, UUID, TEXT, NUMERIC, TEXT, TIMESTAMPTZ) TO app_platform_admin;

-- This wrapper is now the only Platform-Admin-reachable path to
-- fn_billing_apply_credit; app_worker's own direct EXECUTE (used by the
-- automated billing engine's credit-issuance paths, e.g. proration/
-- refund credits) is unaffected.
REVOKE EXECUTE ON FUNCTION billing.fn_billing_apply_credit(UUID, UUID, TEXT, NUMERIC, CHAR, TEXT, TIMESTAMPTZ, TEXT) FROM app_platform_admin;

-- billing.credits / billing.credit_ledger_entries: app_platform_admin's
-- direct INSERT/UPDATE/DELETE bypassed the guarded wrapper above and
-- fn_billing_apply_credit's own ledger bookkeeping; narrow to SELECT
-- (read access for support/investigation is retained).
REVOKE INSERT, UPDATE, DELETE ON billing.credits              FROM app_platform_admin;
REVOKE INSERT, UPDATE, DELETE ON billing.credit_ledger_entries FROM app_platform_admin;


-- =====================================================================
-- PART B -- Platform Admin billing adjustment (6M section 65.2)
-- =====================================================================

-- Freeze-gate remediation (P1 #3): p_amount_currency is REMOVED from this
-- wrapper's client-facing signature. Currency is derived server-side:
-- when the adjustment is bound to an invoice (p_invoice_id IS NOT NULL),
-- the invoice's own billing.invoices.currency is authoritative; otherwise
-- the organization's billing.billing_accounts.currency (base/operating
-- currency, distinct from the credit-ledger-specific
-- credit_balance_currency used by fn_platform_apply_credit) applies. The
-- derived value is still passed positionally to the frozen
-- fn_create_billing_adjustment (086_5H1.sql), which cannot be altered
-- and still requires a currency argument.
--
-- Sign semantics (canonical, made explicit here since no frozen source
-- states otherwise): p_amount_amount is always non-negative; the
-- adjustment_type itself (CREDIT_NOTE/DEBIT_NOTE/MANUAL_CORRECTION/
-- WRITE_OFF) carries the direction of the adjustment. This wrapper
-- rejects negative or zero amounts outright.
CREATE OR REPLACE FUNCTION billing.fn_platform_create_billing_adjustment(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_adjustment_type TEXT,
  p_description     TEXT,
  p_amount_amount   NUMERIC(18,4),
  p_invoice_id      UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id              UUID;
  v_created_by_ref  TEXT;
  v_currency        CHAR(3);
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_billing_adjustment: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_billing_adjustment: admin_user % not found.', p_admin_user_id;
  END IF;

  IF p_adjustment_type NOT IN ('CREDIT_NOTE','DEBIT_NOTE','MANUAL_CORRECTION','WRITE_OFF') THEN
    RAISE EXCEPTION 'fn_platform_create_billing_adjustment: invalid adjustment_type %.', p_adjustment_type;
  END IF;

  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_billing_adjustment: description is required.';
  END IF;

  IF p_amount_amount IS NULL OR p_amount_amount <= 0 THEN
    RAISE EXCEPTION 'fn_platform_create_billing_adjustment: amount must be positive; adjustment_type carries direction.';
  END IF;

  IF p_invoice_id IS NOT NULL THEN
    SELECT currency INTO v_currency
    FROM billing.invoices
    WHERE id = p_invoice_id AND organization_id = p_organization_id;

    IF v_currency IS NULL THEN
      RAISE EXCEPTION 'fn_platform_create_billing_adjustment: invoice % not found for organization %.', p_invoice_id, p_organization_id;
    END IF;
  ELSE
    SELECT currency INTO v_currency
    FROM billing.billing_accounts
    WHERE organization_id = p_organization_id;

    IF v_currency IS NULL THEN
      RAISE EXCEPTION 'fn_platform_create_billing_adjustment: no billing account for organization %.', p_organization_id;
    END IF;
  END IF;

  -- created_by_ref is derived server-side; cross-org invoice validation
  -- and billing-account-exists validation are both also enforced by
  -- the underlying fn_create_billing_adjustment (086_5H1.sql) and are
  -- not solely relied upon here.
  v_created_by_ref := 'platform_admin:' || p_admin_user_id::text;

  v_id := billing.fn_create_billing_adjustment(
    p_organization_id, p_invoice_id, p_adjustment_type, p_description,
    p_amount_amount, v_currency, v_created_by_ref
  );

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_BILLING_ADJUSTMENT_CREATED', 'billing_adjustment', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'adjustment_type', p_adjustment_type, 'description', p_description,
      'amount', p_amount_amount, 'currency', v_currency,
      'invoice_id', p_invoice_id
    ),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_billing_adjustment(UUID, UUID, TEXT, TEXT, NUMERIC, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_billing_adjustment(UUID, UUID, TEXT, TEXT, NUMERIC, UUID) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_billing_adjustment(UUID, UUID, TEXT, TEXT, NUMERIC, UUID) TO app_platform_admin;

REVOKE EXECUTE ON FUNCTION billing.fn_create_billing_adjustment(UUID, UUID, TEXT, TEXT, NUMERIC, CHAR, TEXT) FROM app_platform_admin;

REVOKE INSERT, UPDATE, DELETE ON billing.billing_adjustments FROM app_platform_admin;


-- =====================================================================
-- PART C -- Plan / PlanVersion / PlanPrice guarded commands
-- (6M section 65.3). Global catalog data -- not tenant-scoped, so
-- these are platform events (organization_id = NULL,
-- p_is_platform_event = TRUE) rather than tenant audit events.
-- =====================================================================

CREATE OR REPLACE FUNCTION billing.fn_platform_create_plan(
  p_admin_user_id UUID,
  p_name          TEXT,
  p_description   TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_plan: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_plan: admin_user % not found.', p_admin_user_id;
  END IF;

  IF p_name IS NULL OR length(p_name) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'fn_platform_create_plan: name must be between 1 and 100 characters.';
  END IF;

  INSERT INTO billing.plans (name, description)
  VALUES (p_name, p_description)
  RETURNING id INTO v_id;

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_PLAN_CREATED', 'plan', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('name', p_name, 'description', p_description),
    TRUE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_plan(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_plan(UUID, TEXT, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_plan(UUID, TEXT, TEXT) TO app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_create_plan_version(
  p_admin_user_id      UUID,
  p_plan_id            UUID,
  p_billing_cycle      TEXT,
  p_base_price_amount  NUMERIC(18,4),
  p_base_price_currency CHAR(3),
  p_effective_from     DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id             UUID;
  v_next_version   INTEGER;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: admin_user % not found.', p_admin_user_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM billing.plans WHERE id = p_plan_id) THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: plan % not found.', p_plan_id;
  END IF;

  IF p_billing_cycle NOT IN ('MONTHLY','ANNUAL') THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: billing_cycle % is not recognized.', p_billing_cycle;
  END IF;

  IF p_base_price_amount IS NULL OR p_base_price_amount < 0 THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: base_price_amount must be non-negative.';
  END IF;

  IF p_base_price_currency IS NULL OR p_base_price_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: currency % is not a valid ISO-4217 code.', p_base_price_currency;
  END IF;

  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION 'fn_platform_create_plan_version: effective_from is required.';
  END IF;

  SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_next_version
  FROM billing.plan_versions
  WHERE plan_id = p_plan_id;

  INSERT INTO billing.plan_versions (
    plan_id, version_number, billing_cycle, base_price_amount,
    base_price_currency, is_published, effective_from
  ) VALUES (
    p_plan_id, v_next_version, p_billing_cycle, p_base_price_amount,
    p_base_price_currency, FALSE, p_effective_from
  )
  RETURNING id INTO v_id;

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_PLAN_VERSION_CREATED', 'plan_version', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'plan_id', p_plan_id, 'version_number', v_next_version,
      'billing_cycle', p_billing_cycle, 'base_price_amount', p_base_price_amount,
      'base_price_currency', p_base_price_currency, 'effective_from', p_effective_from
    ),
    TRUE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_plan_version(UUID, UUID, TEXT, NUMERIC, CHAR, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_plan_version(UUID, UUID, TEXT, NUMERIC, CHAR, DATE) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_plan_version(UUID, UUID, TEXT, NUMERIC, CHAR, DATE) TO app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_publish_plan_version(
  p_admin_user_id   UUID,
  p_plan_version_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_is_published BOOLEAN;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_publish_plan_version: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_publish_plan_version: admin_user % not found.', p_admin_user_id;
  END IF;

  SELECT is_published INTO v_is_published
  FROM billing.plan_versions
  WHERE id = p_plan_version_id;

  IF v_is_published IS NULL THEN
    RAISE EXCEPTION 'fn_platform_publish_plan_version: plan_version % not found.', p_plan_version_id;
  END IF;

  IF v_is_published THEN
    RAISE EXCEPTION 'fn_platform_publish_plan_version: plan_version % is already published.', p_plan_version_id;
  END IF;

  UPDATE billing.plan_versions
  SET is_published = TRUE
  WHERE id = p_plan_version_id;

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_PLAN_VERSION_PUBLISHED', 'plan_version', p_plan_version_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('plan_version_id', p_plan_version_id),
    TRUE
  );
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_publish_plan_version(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_publish_plan_version(UUID, UUID) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_publish_plan_version(UUID, UUID) TO app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_create_plan_price(
  p_admin_user_id        UUID,
  p_plan_version_id      UUID,
  p_metric               TEXT,
  p_unit_label           TEXT,
  p_included_quantity    NUMERIC(18,4),
  p_overage_rate_amount  NUMERIC(18,4) DEFAULT NULL,
  p_overage_rate_currency CHAR(3)      DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id           UUID;
  v_is_published BOOLEAN;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: admin_user % not found.', p_admin_user_id;
  END IF;

  SELECT is_published INTO v_is_published
  FROM billing.plan_versions
  WHERE id = p_plan_version_id;

  IF v_is_published IS NULL THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: plan_version % not found.', p_plan_version_id;
  END IF;

  IF v_is_published THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: plan_version % is already published and immutable.', p_plan_version_id;
  END IF;

  IF p_metric IS NULL OR length(trim(p_metric)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: metric is required.';
  END IF;

  IF p_unit_label IS NULL OR length(trim(p_unit_label)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: unit_label is required.';
  END IF;

  IF p_included_quantity IS NULL OR p_included_quantity < 0 THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: included_quantity must be non-negative.';
  END IF;

  IF (p_overage_rate_amount IS NULL) <> (p_overage_rate_currency IS NULL) THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: overage_rate_amount and overage_rate_currency must both be set or both be NULL.';
  END IF;

  IF p_overage_rate_amount IS NOT NULL AND p_overage_rate_amount < 0 THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: overage_rate_amount must be non-negative.';
  END IF;

  IF p_overage_rate_currency IS NOT NULL AND p_overage_rate_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'fn_platform_create_plan_price: overage_rate_currency % is not a valid ISO-4217 code.', p_overage_rate_currency;
  END IF;

  INSERT INTO billing.plan_prices (
    plan_version_id, metric, unit_label, included_quantity,
    overage_rate_amount, overage_rate_currency
  ) VALUES (
    p_plan_version_id, p_metric, p_unit_label, p_included_quantity,
    p_overage_rate_amount, p_overage_rate_currency
  )
  RETURNING id INTO v_id;

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_PLAN_PRICE_CREATED', 'plan_price', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'plan_version_id', p_plan_version_id, 'metric', p_metric,
      'unit_label', p_unit_label, 'included_quantity', p_included_quantity,
      'overage_rate_amount', p_overage_rate_amount,
      'overage_rate_currency', p_overage_rate_currency
    ),
    TRUE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_plan_price(UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, CHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_plan_price(UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, CHAR) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_plan_price(UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, CHAR) TO app_platform_admin;

-- Freeze-gate remediation (P1 #4): plans could be created/versioned/
-- priced but never taken out of the active catalog -- there was no
-- guarded path to stop a plan from being sold going forward. This
-- command never deletes the plan (or its versions/prices); it only
-- flips billing.plans.is_active to FALSE. Idempotent: deactivating an
-- already-inactive plan succeeds silently and still records an audit
-- event (no raw UPDATE path exists for app_platform_admin, so this is
-- the only way to flip the flag either way).
CREATE OR REPLACE FUNCTION billing.fn_platform_deactivate_plan(
  p_admin_user_id UUID,
  p_plan_id       UUID,
  p_reason        TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_newly_deactivated BOOLEAN;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_deactivate_plan: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_deactivate_plan: admin_user % not found.', p_admin_user_id;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_deactivate_plan: reason is required.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM billing.plans WHERE id = p_plan_id) THEN
    RAISE EXCEPTION 'fn_platform_deactivate_plan: plan % not found.', p_plan_id;
  END IF;

  UPDATE billing.plans
  SET is_active = FALSE
  WHERE id = p_plan_id AND is_active = TRUE
  RETURNING TRUE INTO v_newly_deactivated;

  v_newly_deactivated := COALESCE(v_newly_deactivated, FALSE);

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_PLAN_DEACTIVATED', 'plan', p_plan_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'plan_id', p_plan_id, 'reason', p_reason, 'newly_deactivated', v_newly_deactivated
    ),
    TRUE
  );
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_deactivate_plan(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_deactivate_plan(UUID, UUID, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_deactivate_plan(UUID, UUID, TEXT) TO app_platform_admin;

-- app_platform_admin no longer needs direct write access to the plan
-- catalog tables -- all writes now go through the five guarded
-- commands above. SELECT is retained (support/investigation reads).
REVOKE INSERT, UPDATE ON billing.plans         FROM app_platform_admin;
REVOKE INSERT, UPDATE ON billing.plan_versions FROM app_platform_admin;
REVOKE INSERT, UPDATE ON billing.plan_prices   FROM app_platform_admin;


-- =====================================================================
-- PART D -- Commercial Pricing Agreement thin wrappers (6M section
-- 65.4). The underlying 102_5H2.sql functions do not call
-- audit.fn_insert_audit_event() themselves (that is the calling
-- application service's job for the app_worker path) -- these wrappers
-- supply their own atomic audit write, in the same transaction as the
-- delegated call.
-- =====================================================================

CREATE OR REPLACE FUNCTION billing.fn_platform_create_commercial_pricing_agreement(
  p_organization_id     UUID,
  p_admin_user_id       UUID,
  p_base_plan_id        UUID,
  p_contract_reference  TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id              UUID;
  v_created_by_ref  TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_commercial_pricing_agreement: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_commercial_pricing_agreement: admin_user % not found.', p_admin_user_id;
  END IF;

  v_created_by_ref := 'platform_admin:' || p_admin_user_id::text;

  v_id := billing.fn_create_commercial_pricing_agreement(
    p_organization_id, p_base_plan_id, p_contract_reference, v_created_by_ref
  );

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_CPA_CREATED', 'commercial_pricing_agreement', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('base_plan_id', p_base_plan_id, 'contract_reference', p_contract_reference),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_commercial_pricing_agreement(UUID, UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_commercial_pricing_agreement(UUID, UUID, UUID, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_commercial_pricing_agreement(UUID, UUID, UUID, TEXT) TO app_platform_admin;

REVOKE EXECUTE ON FUNCTION billing.fn_create_commercial_pricing_agreement(UUID, UUID, TEXT, TEXT) FROM app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_create_commercial_pricing_agreement_version(
  p_organization_id              UUID,
  p_admin_user_id                UUID,
  p_agreement_id                 UUID,
  p_base_plan_version_id         UUID,
  p_currency                     CHAR(3),
  p_base_price_override_amount   NUMERIC(18,4),
  p_base_price_override_currency CHAR(3),
  p_effective_from               DATE,
  p_effective_to                 DATE,
  p_contract_reference           TEXT,
  p_reason                       TEXT,
  p_approved_by_ref              TEXT,
  p_metrics                      JSONB DEFAULT '[]'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id              UUID;
  v_created_by_ref  TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_commercial_pricing_agreement_version: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_commercial_pricing_agreement_version: admin_user % not found.', p_admin_user_id;
  END IF;

  v_created_by_ref := 'platform_admin:' || p_admin_user_id::text;

  v_id := billing.fn_create_commercial_pricing_agreement_version(
    p_organization_id, p_agreement_id, p_base_plan_version_id, p_currency,
    p_base_price_override_amount, p_base_price_override_currency,
    p_effective_from, p_effective_to, p_contract_reference, p_reason,
    v_created_by_ref, p_approved_by_ref, p_metrics
  );

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_CPA_VERSION_CREATED', 'commercial_pricing_agreement_version', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'agreement_id', p_agreement_id, 'base_plan_version_id', p_base_plan_version_id,
      'currency', p_currency, 'base_price_override_amount', p_base_price_override_amount,
      'base_price_override_currency', p_base_price_override_currency,
      'effective_from', p_effective_from, 'effective_to', p_effective_to,
      'contract_reference', p_contract_reference, 'reason', p_reason,
      'approved_by_ref', p_approved_by_ref
    ),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_commercial_pricing_agreement_version(
  UUID, UUID, UUID, UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_commercial_pricing_agreement_version(
  UUID, UUID, UUID, UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, JSONB) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_commercial_pricing_agreement_version(
  UUID, UUID, UUID, UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, JSONB) TO app_platform_admin;

REVOKE EXECUTE ON FUNCTION billing.fn_create_commercial_pricing_agreement_version(
  UUID, UUID, UUID, CHAR, NUMERIC, CHAR, DATE, DATE, TEXT, TEXT, TEXT, TEXT, JSONB) FROM app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_activate_commercial_pricing_agreement_version(
  p_organization_id      UUID,
  p_admin_user_id        UUID,
  p_agreement_version_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_activate_commercial_pricing_agreement_version: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_activate_commercial_pricing_agreement_version: admin_user % not found.', p_admin_user_id;
  END IF;

  PERFORM billing.fn_activate_commercial_pricing_agreement_version(p_organization_id, p_agreement_version_id);

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_CPA_VERSION_ACTIVATED', 'commercial_pricing_agreement_version', p_agreement_version_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('agreement_version_id', p_agreement_version_id),
    FALSE
  );
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_activate_commercial_pricing_agreement_version(UUID, UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_activate_commercial_pricing_agreement_version(UUID, UUID, UUID) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_activate_commercial_pricing_agreement_version(UUID, UUID, UUID) TO app_platform_admin;

REVOKE EXECUTE ON FUNCTION billing.fn_activate_commercial_pricing_agreement_version(UUID, UUID) FROM app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_expire_commercial_pricing_agreement_version(
  p_organization_id      UUID,
  p_admin_user_id        UUID,
  p_agreement_version_id UUID,
  p_reason               TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_expire_commercial_pricing_agreement_version: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_expire_commercial_pricing_agreement_version: admin_user % not found.', p_admin_user_id;
  END IF;

  -- Freeze-gate remediation (P1 #6): reason is required for an expire
  -- action (matches the contract correction in 6M §63) -- the
  -- underlying frozen fn_expire_commercial_pricing_agreement_version
  -- does not itself enforce this, so it is enforced here.
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_expire_commercial_pricing_agreement_version: reason is required.';
  END IF;

  PERFORM billing.fn_expire_commercial_pricing_agreement_version(p_organization_id, p_agreement_version_id, p_reason);

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_CPA_VERSION_EXPIRED', 'commercial_pricing_agreement_version', p_agreement_version_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('agreement_version_id', p_agreement_version_id, 'reason', p_reason),
    FALSE
  );
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_expire_commercial_pricing_agreement_version(UUID, UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_expire_commercial_pricing_agreement_version(UUID, UUID, UUID, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_expire_commercial_pricing_agreement_version(UUID, UUID, UUID, TEXT) TO app_platform_admin;

REVOKE EXECUTE ON FUNCTION billing.fn_expire_commercial_pricing_agreement_version(UUID, UUID, TEXT) FROM app_platform_admin;


-- =====================================================================
-- PART E -- Tax guarded commands (6M section 65.5). Global catalog
-- data -- platform events, same as Part C.
-- =====================================================================

CREATE OR REPLACE FUNCTION billing.fn_platform_create_tax_category(
  p_admin_user_id UUID,
  p_code          TEXT,
  p_description   TEXT,
  p_regime        TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_tax_category: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_tax_category: admin_user % not found.', p_admin_user_id;
  END IF;

  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_tax_category: code is required.';
  END IF;

  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_tax_category: description is required.';
  END IF;

  IF p_regime IS NULL OR length(trim(p_regime)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_tax_category: regime is required.';
  END IF;

  INSERT INTO billing.tax_categories (code, description, regime)
  VALUES (p_code, p_description, p_regime)
  RETURNING id INTO v_id;

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_TAX_CATEGORY_CREATED', 'tax_category', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object('code', p_code, 'description', p_description, 'regime', p_regime),
    TRUE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_tax_category(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_tax_category(UUID, TEXT, TEXT, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_tax_category(UUID, TEXT, TEXT, TEXT) TO app_platform_admin;


CREATE OR REPLACE FUNCTION billing.fn_platform_create_tax_rule(
  p_admin_user_id          UUID,
  p_regime                 TEXT,
  p_tax_category_id        UUID,
  p_supplier_jurisdiction  TEXT,
  p_recipient_jurisdiction TEXT,
  p_components             JSONB,
  p_effective_from         DATE,
  p_effective_to           DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, identity, organization, pg_catalog
AS $$
DECLARE
  v_id        UUID;
  v_component JSONB;
  v_rate      TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: admin_user % not found.', p_admin_user_id;
  END IF;

  IF p_regime IS NULL OR length(trim(p_regime)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: regime is required.';
  END IF;

  IF p_tax_category_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM billing.tax_categories WHERE id = p_tax_category_id
  ) THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: tax_category % not found.', p_tax_category_id;
  END IF;

  IF p_supplier_jurisdiction IS NULL OR length(trim(p_supplier_jurisdiction)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: supplier_jurisdiction is required.';
  END IF;

  -- Freeze-gate remediation (P1 #5): components must be a non-empty
  -- JSON array of objects, each with a non-empty "name" and a numeric
  -- "rate" in [0,1]. Any other shape (non-array, empty array, non-object
  -- element, missing/blank name, non-numeric rate, or rate outside
  -- [0,1]) is rejected outright -- a malformed tax component is a
  -- silent revenue-correctness defect, not a soft validation warning.
  IF p_components IS NULL OR jsonb_typeof(p_components) <> 'array' THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: components must be a JSON array.';
  END IF;

  IF jsonb_array_length(p_components) = 0 THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: components must not be empty.';
  END IF;

  FOR v_component IN SELECT * FROM jsonb_array_elements(p_components)
  LOOP
    IF jsonb_typeof(v_component) <> 'object' THEN
      RAISE EXCEPTION 'fn_platform_create_tax_rule: each component must be a JSON object.';
    END IF;

    IF NOT (v_component ? 'name')
       OR jsonb_typeof(v_component -> 'name') <> 'string'
       OR length(trim(v_component ->> 'name')) = 0 THEN
      RAISE EXCEPTION 'fn_platform_create_tax_rule: each component must have a non-empty name.';
    END IF;

    IF NOT (v_component ? 'rate') OR jsonb_typeof(v_component -> 'rate') <> 'number' THEN
      RAISE EXCEPTION 'fn_platform_create_tax_rule: each component must have a numeric rate.';
    END IF;

    v_rate := v_component ->> 'rate';
    IF v_rate::NUMERIC < 0 OR v_rate::NUMERIC > 1 THEN
      RAISE EXCEPTION 'fn_platform_create_tax_rule: component rate % must be between 0 and 1.', v_rate;
    END IF;
  END LOOP;

  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: effective_from is required.';
  END IF;

  IF p_effective_to IS NOT NULL AND p_effective_to <= p_effective_from THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: effective_to must be after effective_from.';
  END IF;

  -- Freeze-gate remediation (P1 #5): the overlap-detection grain was
  -- missing tax_category_id -- two rules for the same regime/
  -- jurisdiction pair but different tax categories are NOT a conflict
  -- and must both be allowed to exist; only a true same-category
  -- overlap is rejected.
  IF EXISTS (
    SELECT 1 FROM billing.tax_rules
    WHERE regime = p_regime
      AND tax_category_id IS NOT DISTINCT FROM p_tax_category_id
      AND supplier_jurisdiction = p_supplier_jurisdiction
      AND recipient_jurisdiction IS NOT DISTINCT FROM p_recipient_jurisdiction
      AND effective_from <= COALESCE(p_effective_to, 'infinity'::date)
      AND COALESCE(effective_to, 'infinity'::date) >= p_effective_from
  ) THEN
    RAISE EXCEPTION 'fn_platform_create_tax_rule: an overlapping tax rule already exists for regime %, tax_category %, supplier_jurisdiction %.', p_regime, p_tax_category_id, p_supplier_jurisdiction;
  END IF;

  INSERT INTO billing.tax_rules (
    regime, tax_category_id, supplier_jurisdiction, recipient_jurisdiction,
    components, effective_from, effective_to
  ) VALUES (
    p_regime, p_tax_category_id, p_supplier_jurisdiction, p_recipient_jurisdiction,
    p_components, p_effective_from, p_effective_to
  )
  RETURNING id INTO v_id;

  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_TAX_RULE_CREATED', 'tax_rule', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'regime', p_regime, 'tax_category_id', p_tax_category_id,
      'supplier_jurisdiction', p_supplier_jurisdiction,
      'recipient_jurisdiction', p_recipient_jurisdiction,
      'effective_from', p_effective_from, 'effective_to', p_effective_to
    ),
    TRUE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_create_tax_rule(UUID, TEXT, UUID, TEXT, TEXT, JSONB, DATE, DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_create_tax_rule(UUID, TEXT, UUID, TEXT, TEXT, JSONB, DATE, DATE) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_create_tax_rule(UUID, TEXT, UUID, TEXT, TEXT, JSONB, DATE, DATE) TO app_platform_admin;

-- Retain SELECT only; all writes now go through the two guarded
-- commands above.
REVOKE INSERT, UPDATE, DELETE ON billing.tax_categories FROM app_platform_admin;
REVOKE INSERT, UPDATE          ON billing.tax_rules      FROM app_platform_admin;


-- =====================================================================
-- PART F -- Identity safe-support boundary (6M section 65.6).
--
-- identity.users/sessions/api_keys currently grant app_platform_admin
-- full SELECT/INSERT/UPDATE/DELETE (008_5B.sql). That is revoked below
-- and replaced with SELECT on three column-restricted views that
-- exclude password_hash/mfa_secret_ref (users), refresh_token_hash/
-- access_token_jti (sessions), and key_hash (api_keys) -- the same
-- "column-restricted GRANT SELECT" pattern 107_5B5.sql/108_5B6.sql
-- already apply to sensitive voice content. Note: app_platform_admin
-- carries BYPASSRLS (confirmed live during this pass's re-
-- verification, see 108_5B6.sql's header) so identity.api_keys' RLS
-- policy does not itself restrict this role -- table/column ACL
-- narrowing is the only real control here, exactly as it was for
-- voice.transcript_segments.
-- =====================================================================

CREATE OR REPLACE VIEW identity.v_platform_safe_users AS
SELECT
  id, email, email_normalized, display_name, phone_e164,
  phone_verified_at, email_verified_at, password_changed_at, status,
  last_login_at, failed_login_count, last_failed_login_at,
  mfa_enabled, deleted_at, created_at, updated_at
FROM identity.users;
GRANT SELECT ON identity.v_platform_safe_users TO app_platform_admin;

CREATE OR REPLACE VIEW identity.v_platform_safe_sessions AS
SELECT
  id, user_id, status, created_at, expires_at, revoked_at,
  last_seen_at, device_label, ip_address, user_agent_hash
FROM identity.sessions;
GRANT SELECT ON identity.v_platform_safe_sessions TO app_platform_admin;

CREATE OR REPLACE VIEW identity.v_platform_safe_api_keys AS
SELECT
  id, organization_id, created_by, name, key_prefix, scopes, status,
  expires_at, last_used_at, last_used_ip, revoked_at, revoked_by,
  created_at, updated_at
FROM identity.api_keys;
GRANT SELECT ON identity.v_platform_safe_api_keys TO app_platform_admin;


-- fn_platform_revoke_all_sessions: DB-transaction-only guarded command
-- matching 6B's frozen forced-session-revocation contract. Performs
-- the atomic conditional CAS-UPDATE + id/jti capture + audit write,
-- AND (freeze-gate remediation, P1 #1) durably enqueues exactly one
-- audit.domain_event_outbox row -- event_type
-- 'identity.forced_revocation_required' -- in the SAME transaction,
-- resolving DEP-6B-08 (durable forced-revocation delivery) per 5B's
-- Phase 5L amendment / 5L-Global-Database-Reconciliation.md item 22:
-- "Reuse audit.domain_event_outbox (no new table)". This function
-- still does NOT touch Redis itself and does NOT claim atomicity with
-- the Redis denylist -- delivery/publish of the enqueued outbox event
-- remains a separate, crash-safe-retryable, post-commit publisher-
-- worker step (Case A/B/C semantics unchanged; only the durability of
-- the *handoff* to that worker is what changes here). identity.
-- sessions carries no organization_id column, so this is a platform
-- event (organization_id = NULL, p_is_platform_event = TRUE), matching
-- Parts C/E above; the outbox row's own organization_id is likewise
-- NULL (a platform-scoped event, not tenant-scoped) so
-- fn_outbox_tenant_check() (077_5J1.sql) passes it through unchecked.
CREATE OR REPLACE FUNCTION identity.fn_platform_revoke_all_sessions(
  p_admin_user_id UUID,
  p_user_id       UUID,
  p_reason        TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = identity, audit, organization, pg_catalog
AS $$
DECLARE
  v_revoked_ids      UUID[];
  v_revoked_jtis     TEXT[];
  v_count            INTEGER;
  v_outbox_event_id  UUID;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_revoke_all_sessions: caller is not authorized.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_admin_user_id) THEN
    RAISE EXCEPTION 'fn_platform_revoke_all_sessions: admin_user % not found.', p_admin_user_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM identity.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'fn_platform_revoke_all_sessions: user % not found.', p_user_id;
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'fn_platform_revoke_all_sessions: reason is required.';
  END IF;

  -- Atomic conditional (CAS) update, no row lock -- same pattern 6B's
  -- own forced-session-revocation path already uses. 0 rows revoked is
  -- valid/idempotent (the user may simply have no active sessions),
  -- and in that case NO outbox event is written -- there is nothing
  -- for the denylist publisher to act on, and a repeat call against an
  -- already-fully-revoked user must stay a true no-op.
  WITH revoked AS (
    UPDATE identity.sessions
    SET status = 'REVOKED', revoked_at = NOW()
    WHERE user_id = p_user_id AND status = 'ACTIVE'
    RETURNING id, access_token_jti
  )
  SELECT array_agg(id),
         array_agg(access_token_jti) FILTER (WHERE access_token_jti IS NOT NULL),
         count(*)
  INTO v_revoked_ids, v_revoked_jtis, v_count
  FROM revoked;

  v_count := COALESCE(v_count, 0);

  IF v_count > 0 THEN
    INSERT INTO audit.domain_event_outbox (
      event_type, organization_id, aggregate_type, aggregate_id, payload
    ) VALUES (
      'identity.forced_revocation_required', NULL, 'user', p_user_id,
      jsonb_build_object(
        'user_id', p_user_id,
        'session_ids', to_jsonb(v_revoked_ids),
        'access_token_jti', to_jsonb(COALESCE(v_revoked_jtis, ARRAY[]::TEXT[])),
        'reason', p_reason
      )
    )
    RETURNING id INTO v_outbox_event_id;
  END IF;

  -- resource_snapshot deliberately excludes the raw access_token_jti
  -- array (freeze-gate remediation, P1 #1) -- the durable, retryable
  -- copy of that array lives only in the outbox payload above, not in
  -- the immutable audit trail; the audit row instead carries the
  -- outbox event's own id as a correlation identifier.
  PERFORM audit.fn_insert_audit_event(
    NULL, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'PLATFORM_SESSIONS_REVOKED', 'user', p_user_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'user_id', p_user_id,
      'revoked_session_count', v_count,
      'reason', p_reason,
      'outbox_event_id', v_outbox_event_id
    ),
    TRUE
  );

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION identity.fn_platform_revoke_all_sessions(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION identity.fn_platform_revoke_all_sessions(UUID, UUID, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION identity.fn_platform_revoke_all_sessions(UUID, UUID, TEXT) TO app_platform_admin;

-- Full direct-grant revocation -- mirrors 107_5B5.sql's REVOKE ALL
-- precedent for the voice schema. app_platform_admin's only remaining
-- paths to identity data are the three safe views above and this
-- guarded revocation command; app_api/app_worker's own direct grants
-- (008_5B.sql/002_5B.sql) are unaffected.
REVOKE ALL ON identity.users     FROM app_platform_admin;
REVOKE ALL ON identity.sessions  FROM app_platform_admin;
REVOKE ALL ON identity.api_keys  FROM app_platform_admin;


-- =====================================================================
-- PART G -- webhooks.webhook_deliveries DML narrowing (6M section
-- 65.7). No new function. Reuses 108_5B6.sql's exact two-DO-block
-- pg_inherits-walking pattern (remediation loop + self-verifying
-- assertion loop), applied to the parent AND every existing child
-- partition, with NO column restriction (only INSERT/UPDATE/DELETE
-- revoked; SELECT retained in full -- unlike the voice.
-- transcript_segments precedent, webhook delivery metadata carries no
-- equivalent sensitive-content column). app_worker is unaffected: its
-- writes go through SECURITY DEFINER functions that bypass table ACLs.
-- =====================================================================

REVOKE INSERT, UPDATE, DELETE ON webhooks.webhook_deliveries FROM app_platform_admin;

DO $$
DECLARE
  v_partition regclass;
BEGIN
  FOR v_partition IN
    SELECT c.oid::regclass
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'webhooks.webhook_deliveries'::regclass
  LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON %s FROM app_platform_admin', v_partition);
  END LOOP;
END
$$;

-- Defensive verification: assert every child partition (and the
-- parent) now reports no INSERT/UPDATE/DELETE for app_platform_admin,
-- while SELECT remains -- raises if any partition is left
-- over-privileged, so this migration fails loudly rather than
-- silently leaving the gap open on a future re-run against a
-- differently-shaped database.
DO $$
DECLARE
  v_partition regclass;
BEGIN
  IF has_table_privilege('app_platform_admin', 'webhooks.webhook_deliveries', 'INSERT')
     OR has_table_privilege('app_platform_admin', 'webhooks.webhook_deliveries', 'UPDATE')
     OR has_table_privilege('app_platform_admin', 'webhooks.webhook_deliveries', 'DELETE')
  THEN
    RAISE EXCEPTION 'migration 109_5B7: webhooks.webhook_deliveries still reports INSERT/UPDATE/DELETE for app_platform_admin after remediation.';
  END IF;
  IF NOT has_table_privilege('app_platform_admin', 'webhooks.webhook_deliveries', 'SELECT') THEN
    RAISE EXCEPTION 'migration 109_5B7: webhooks.webhook_deliveries unexpectedly lost SELECT for app_platform_admin.';
  END IF;

  FOR v_partition IN
    SELECT c.oid::regclass
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    WHERE i.inhparent = 'webhooks.webhook_deliveries'::regclass
  LOOP
    IF has_table_privilege('app_platform_admin', v_partition, 'INSERT')
       OR has_table_privilege('app_platform_admin', v_partition, 'UPDATE')
       OR has_table_privilege('app_platform_admin', v_partition, 'DELETE')
    THEN
      RAISE EXCEPTION
        'migration 109_5B7: partition % still reports INSERT/UPDATE/DELETE for app_platform_admin after remediation.', v_partition;
    END IF;
    IF NOT has_table_privilege('app_platform_admin', v_partition, 'SELECT') THEN
      RAISE EXCEPTION
        'migration 109_5B7: partition % unexpectedly lost SELECT for app_platform_admin.', v_partition;
    END IF;
  END LOOP;
END
$$;

-- Operational-runbook requirement (restated from 108_5B6.sql): any
-- future migration that adds a new webhooks.webhook_deliveries
-- partition MUST apply this same REVOKE INSERT/UPDATE/DELETE (SELECT
-- retained) to the new partition in the SAME migration --
-- ALTER DEFAULT PRIVILEGES does not apply to partition attachment.
