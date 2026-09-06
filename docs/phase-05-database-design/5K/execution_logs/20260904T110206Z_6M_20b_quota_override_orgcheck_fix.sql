CREATE OR REPLACE FUNCTION billing.fn_platform_set_quota_override(
  p_organization_id UUID,
  p_admin_user_id   UUID,
  p_metric          TEXT,
  p_soft_limit      NUMERIC,
  p_hard_limit      NUMERIC,
  p_reason          TEXT,
  p_expires_at      TIMESTAMPTZ DEFAULT NULL,
  p_unit_label      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = billing, organization, pg_catalog
AS $$
DECLARE
  v_id UUID;
  v_unit_label TEXT;
BEGIN
  IF NOT organization.is_platform_admin() THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: caller is not authorized.';
  END IF;
  IF p_metric NOT IN (
      'CALL_MINUTES','CALL_COUNT','SMS_COUNT','WHATSAPP_MESSAGE_COUNT',
      'STORAGE_GB','API_REQUEST_COUNT','WORKFLOW_EXECUTION_COUNT',
      'AGENT_COUNT','SEAT_COUNT','KNOWLEDGE_BASE_DOCUMENT_COUNT',
      'INTEGRATION_COUNT','CONCURRENT_CALL_COUNT','LLM_TOKEN_COUNT',
      'RECORDING_STORAGE_GB','WEBHOOK_DELIVERY_COUNT'
    ) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: metric % is not a recognized usage dimension.', p_metric;
  END IF;
  IF p_soft_limit IS NULL OR p_soft_limit <= 0 OR p_hard_limit IS NULL OR p_hard_limit <= 0 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: soft_limit and hard_limit must both be positive.';
  END IF;
  IF p_hard_limit < p_soft_limit THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: hard_limit must be >= soft_limit.';
  END IF;
  IF p_reason IS NULL OR length(p_reason) NOT BETWEEN 10 AND 2000 THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: p_reason must be between 10 and 2000 characters.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM organization.organizations WHERE id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'fn_platform_set_quota_override: organization % not found.', p_organization_id;
  END IF;

  v_unit_label := COALESCE(p_unit_label, CASE p_metric
    WHEN 'CALL_MINUTES' THEN 'minutes'
    WHEN 'STORAGE_GB' THEN 'GB'
    WHEN 'RECORDING_STORAGE_GB' THEN 'GB'
    WHEN 'LLM_TOKEN_COUNT' THEN 'tokens'
    ELSE 'count'
  END);

  INSERT INTO billing.quota_configs (
    organization_id, metric, soft_limit, hard_limit, override_reason,
    effective_from, expires_at, updated_by, unit_label
  ) VALUES (
    p_organization_id, p_metric, p_soft_limit, p_hard_limit, p_reason,
    NOW(), p_expires_at, p_admin_user_id, v_unit_label
  )
  ON CONFLICT ON CONSTRAINT uq_qc_org_metric DO UPDATE
  SET soft_limit = EXCLUDED.soft_limit,
      hard_limit = EXCLUDED.hard_limit,
      override_reason = EXCLUDED.override_reason,
      effective_from = EXCLUDED.effective_from,
      expires_at = EXCLUDED.expires_at,
      updated_by = EXCLUDED.updated_by,
      unit_label = EXCLUDED.unit_label
  RETURNING id INTO v_id;

  PERFORM set_config('app.tenant_id', p_organization_id::text, true);
  PERFORM audit.fn_insert_audit_event(
    p_organization_id, 'PLATFORM_ADMIN', p_admin_user_id, NULL,
    'QUOTA_OVERRIDE_SET', 'QUOTA_CONFIG', v_id, 'SUCCESS', NULL,
    NULL, NULL, NULL, NULL, NULL,
    jsonb_build_object(
      'metric', p_metric, 'soft_limit', p_soft_limit, 'hard_limit', p_hard_limit,
      'reason', p_reason, 'expires_at', p_expires_at, 'unit_label', v_unit_label
    ),
    FALSE
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) FROM app_api;
GRANT EXECUTE ON FUNCTION billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT) TO app_platform_admin;
