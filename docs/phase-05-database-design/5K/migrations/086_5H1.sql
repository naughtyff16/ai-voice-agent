-- =================================================================
-- Migration 086 (Phase 5H.1): billing.fn_create_billing_adjustment()
-- down_revision: 085_5D1
-- Transaction: yes
-- Source: Phase 5L Global Database Reconciliation, Section 10
--
-- 5H-Billing-Usage-Schema.md's own review already names this: app_worker
-- currently has direct INSERT on billing_adjustments (056_5H.sql);
-- "for full financial control parity, a SECURITY DEFINER
-- fn_create_billing_adjustment is recommended." Implemented now —
-- narrow financial-control parity, not a blocker being manufactured
-- into one. app_platform_admin's existing full-CRUD grant (058_5H.sql)
-- is untouched; only app_worker's direct-INSERT path is narrowed.
-- =================================================================

CREATE OR REPLACE FUNCTION billing.fn_create_billing_adjustment(
  p_organization_id UUID,
  p_invoice_id      UUID,
  p_adjustment_type TEXT,
  p_description     TEXT,
  p_amount_amount   NUMERIC(18,4),
  p_amount_currency CHAR(3),
  p_created_by_ref  TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, public, pg_catalog
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM billing.billing_accounts WHERE organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_create_billing_adjustment: no billing account for organization %.', p_organization_id;
  END IF;

  IF p_adjustment_type NOT IN ('CREDIT_NOTE','DEBIT_NOTE','MANUAL_CORRECTION','WRITE_OFF') THEN
    RAISE EXCEPTION 'fn_create_billing_adjustment: invalid adjustment_type %.', p_adjustment_type;
  END IF;

  IF p_invoice_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM billing.invoices WHERE id = p_invoice_id AND organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_create_billing_adjustment: invoice % does not belong to organization %.', p_invoice_id, p_organization_id;
  END IF;

  INSERT INTO billing.billing_adjustments (
    organization_id, invoice_id, adjustment_type, description,
    amount_amount, amount_currency, created_by_ref
  ) VALUES (
    p_organization_id, p_invoice_id, p_adjustment_type, p_description,
    p_amount_amount, p_amount_currency, p_created_by_ref
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_create_billing_adjustment(UUID, UUID, TEXT, TEXT, NUMERIC, CHAR, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.fn_create_billing_adjustment(UUID, UUID, TEXT, TEXT, NUMERIC, CHAR, TEXT) TO app_worker, app_platform_admin;

REVOKE INSERT ON billing.billing_adjustments FROM app_worker;
