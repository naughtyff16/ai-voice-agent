-- Migration 057 (Phase 5H): SECURITY DEFINER invoice lifecycle functions
-- down_revision: 056_5H
-- Correction: all four functions get SET search_path = billing, pg_catalog (5K §10.7)

CREATE OR REPLACE FUNCTION billing.fn_finalize_invoice(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_fiscal_year     INTEGER,
  p_prefix          TEXT DEFAULT 'INV'
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE v_inv_number TEXT; v_current_status TEXT;
BEGIN
  SELECT status INTO v_current_status FROM billing.invoices
  WHERE id = p_invoice_id AND organization_id = p_organization_id FOR UPDATE;
  IF v_current_status IS NULL THEN RAISE EXCEPTION 'billing: invoice not found'; END IF;
  IF v_current_status <> 'DRAFT' THEN RAISE EXCEPTION 'billing: can only finalize a DRAFT invoice; current status = %', v_current_status; END IF;
  v_inv_number := billing.fn_allocate_invoice_number(p_organization_id, p_fiscal_year, p_prefix);
  UPDATE billing.invoices SET status = 'OPEN', invoice_number = v_inv_number, issue_date = CURRENT_DATE, updated_at = NOW() WHERE id = p_invoice_id;
  RETURN v_inv_number;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_finalize_invoice(UUID, UUID, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_finalize_invoice(UUID, UUID, INTEGER, TEXT) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_mark_invoice_paid(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_payment_amount  NUMERIC(18,4),
  p_currency        CHAR(3)
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM billing.invoices WHERE id = p_invoice_id AND organization_id = p_organization_id FOR UPDATE;
  IF v_status <> 'OPEN' THEN RAISE EXCEPTION 'billing: can only mark OPEN invoice as PAID; current = %', v_status; END IF;
  UPDATE billing.invoices SET status = 'PAID', paid_at = NOW(), amount_paid_amount = p_payment_amount, amount_paid_currency = p_currency, updated_at = NOW() WHERE id = p_invoice_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_mark_invoice_paid(UUID, UUID, NUMERIC, CHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_mark_invoice_paid(UUID, UUID, NUMERIC, CHAR) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_void_invoice(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_reason          TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM billing.invoices WHERE id = p_invoice_id AND organization_id = p_organization_id FOR UPDATE;
  IF v_status NOT IN ('DRAFT','OPEN') THEN RAISE EXCEPTION 'billing: can only void DRAFT or OPEN invoices; current = %', v_status; END IF;
  UPDATE billing.invoices SET status = 'VOID', voided_at = NOW(), void_reason = p_reason, updated_at = NOW() WHERE id = p_invoice_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_void_invoice(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_void_invoice(UUID, UUID, TEXT) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION billing.fn_update_payment_status(
  p_organization_id         UUID,
  p_payment_attempt_id      UUID,
  p_new_status              TEXT,
  p_provider_webhook_event_id TEXT DEFAULT NULL,
  p_failure_code            TEXT DEFAULT NULL,
  p_failure_message         TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, pg_catalog
AS $$
DECLARE
  v_current_status TEXT;
  v_allowed_transitions TEXT[][] := ARRAY[
    ARRAY['INITIATED','PENDING'], ARRAY['INITIATED','SUCCEEDED'],
    ARRAY['INITIATED','FAILED'],  ARRAY['INITIATED','CANCELLED'],
    ARRAY['PENDING','SUCCEEDED'], ARRAY['PENDING','FAILED'],
    ARRAY['PENDING','CANCELLED']];
  v_transition TEXT[];
  v_valid BOOLEAN := FALSE;
BEGIN
  IF p_new_status NOT IN ('INITIATED','PENDING','SUCCEEDED','FAILED','CANCELLED') THEN
    RAISE EXCEPTION 'billing: invalid payment status %', p_new_status;
  END IF;
  SELECT status INTO v_current_status FROM billing.payment_attempts
  WHERE id = p_payment_attempt_id AND organization_id = p_organization_id FOR UPDATE;
  IF v_current_status IS NULL THEN RAISE EXCEPTION 'billing: payment_attempt not found'; END IF;
  IF v_current_status IN ('SUCCEEDED','FAILED','CANCELLED') THEN
    IF v_current_status = p_new_status THEN RETURN; END IF;
    RAISE EXCEPTION 'billing: payment_attempt % is in terminal state % — cannot transition to %', p_payment_attempt_id, v_current_status, p_new_status;
  END IF;
  FOREACH v_transition SLICE 1 IN ARRAY v_allowed_transitions LOOP
    IF v_transition[1] = v_current_status AND v_transition[2] = p_new_status THEN v_valid := TRUE; EXIT; END IF;
  END LOOP;
  IF NOT v_valid THEN
    RAISE EXCEPTION 'billing: transition % → % is not allowed for payment_attempt %', v_current_status, p_new_status, p_payment_attempt_id;
  END IF;
  UPDATE billing.payment_attempts
  SET status = p_new_status,
      provider_webhook_event_id = COALESCE(p_provider_webhook_event_id, provider_webhook_event_id),
      failure_code    = CASE WHEN p_new_status = 'FAILED' THEN p_failure_code ELSE failure_code END,
      failure_message = CASE WHEN p_new_status = 'FAILED' THEN p_failure_message ELSE failure_message END,
      completed_at    = CASE WHEN p_new_status IN ('SUCCEEDED','FAILED','CANCELLED') THEN NOW() ELSE completed_at END
  WHERE id = p_payment_attempt_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_update_payment_status(UUID, UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_update_payment_status(UUID, UUID, TEXT, TEXT, TEXT, TEXT) TO app_worker, app_platform_admin;
