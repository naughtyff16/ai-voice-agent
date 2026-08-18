-- Migration 065 (Phase 5I): plugin_installations, plugin_executions, all plugin SECURITY DEFINER functions
-- down_revision: 064_5I
CREATE TABLE plugins.plugin_installations (
  id                   UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID        NOT NULL,
  plugin_id            UUID        NOT NULL REFERENCES plugins.plugins(id) ON DELETE RESTRICT,
  plugin_version_id    UUID        NOT NULL REFERENCES plugins.plugin_versions(id) ON DELETE RESTRICT,
  status               TEXT        NOT NULL DEFAULT 'INSTALLED',
  configuration        JSONB       NOT NULL DEFAULT '{}',
  credential_ref       TEXT        NULL,
  enabled_capabilities TEXT[]      NOT NULL DEFAULT '{}',
  rate_limit_override  INTEGER     NULL,
  installed_by_ref     UUID        NULL,
  installed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  activated_at         TIMESTAMPTZ NULL,
  suspended_at         TIMESTAMPTZ NULL,
  uninstalled_at       TIMESTAMPTZ NULL,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_plugin_installations PRIMARY KEY (id),
  CONSTRAINT chk_pi_status           CHECK (status IN ('INSTALLED','ACTIVE','SUSPENDED','UNINSTALLED')),
  CONSTRAINT chk_pi_credential_ref   CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%'),
  CONSTRAINT chk_pi_rate_limit       CHECK (rate_limit_override IS NULL OR rate_limit_override > 0),
  CONSTRAINT chk_pi_uninstalled      CHECK ((status = 'UNINSTALLED' AND uninstalled_at IS NOT NULL) OR status <> 'UNINSTALLED')
);
CREATE UNIQUE INDEX uq_pi_org_plugin_active ON plugins.plugin_installations (organization_id, plugin_id) WHERE status NOT IN ('UNINSTALLED');
CREATE INDEX idx_pi_org_status ON plugins.plugin_installations (organization_id, status);
CREATE INDEX idx_pi_version    ON plugins.plugin_installations (plugin_version_id);

CREATE OR REPLACE FUNCTION plugins.fn_pi_version_immutable()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF NEW.plugin_version_id <> OLD.plugin_version_id THEN
    IF current_setting('plugins.upgrade_in_progress', TRUE) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'plugins: plugin_version_id is immutable; use fn_upgrade_plugin() to change the version';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_pi_version_immutable() FROM PUBLIC;
CREATE TRIGGER trg_pi_version_immutable BEFORE UPDATE ON plugins.plugin_installations FOR EACH ROW EXECUTE FUNCTION plugins.fn_pi_version_immutable();

CREATE OR REPLACE FUNCTION plugins.fn_pi_terminal_guard()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF OLD.status = 'UNINSTALLED' AND NEW.status <> 'UNINSTALLED' THEN
    RAISE EXCEPTION 'plugins: installation % is UNINSTALLED (terminal)', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_pi_terminal_guard() FROM PUBLIC;
CREATE TRIGGER trg_pi_terminal_guard BEFORE UPDATE ON plugins.plugin_installations FOR EACH ROW EXECUTE FUNCTION plugins.fn_pi_terminal_guard();
CREATE TRIGGER trg_pi_updated_at     BEFORE UPDATE ON plugins.plugin_installations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE plugins.plugin_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE plugins.plugin_installations FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pi_tenant ON plugins.plugin_installations FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
REVOKE INSERT, UPDATE, DELETE ON plugins.plugin_installations FROM app_api, app_worker;
GRANT SELECT ON plugins.plugin_installations TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON plugins.plugin_installations TO app_platform_admin;

CREATE OR REPLACE FUNCTION plugins.fn_create_plugin_installation(p_organization_id UUID, p_plugin_id UUID, p_plugin_version_id UUID, p_configuration JSONB DEFAULT '{}', p_credential_ref TEXT DEFAULT NULL, p_installed_by_ref UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE v_plugin_status TEXT; v_version_status TEXT; v_version_plugin UUID; v_new_id UUID;
BEGIN
  SELECT pv.status, pv.plugin_id, pl.status INTO v_version_status, v_version_plugin, v_plugin_status
  FROM plugins.plugin_versions pv JOIN plugins.plugins pl ON pl.id = pv.plugin_id WHERE pv.id = p_plugin_version_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plugins: plugin version % not found', p_plugin_version_id; END IF;
  IF v_version_plugin <> p_plugin_id THEN RAISE EXCEPTION 'plugins: version % does not belong to plugin %', p_plugin_version_id, p_plugin_id; END IF;
  IF v_plugin_status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: plugin % is not APPROVED (status=%)', p_plugin_id, v_plugin_status; END IF;
  IF v_version_status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: version % is not APPROVED (status=%)', p_plugin_version_id, v_version_status; END IF;
  IF p_credential_ref IS NOT NULL AND p_credential_ref NOT LIKE 'secret_manager://%' THEN RAISE EXCEPTION 'plugins: credential_ref must be a secret_manager:// reference'; END IF;
  INSERT INTO plugins.plugin_installations (organization_id, plugin_id, plugin_version_id, configuration, credential_ref, installed_by_ref)
  VALUES (p_organization_id, p_plugin_id, p_plugin_version_id, p_configuration, p_credential_ref, p_installed_by_ref) RETURNING id INTO v_new_id;
  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_create_plugin_installation(UUID, UUID, UUID, JSONB, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_create_plugin_installation(UUID, UUID, UUID, JSONB, TEXT, UUID) TO app_api, app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION plugins.fn_activate_plugin(p_organization_id UUID, p_installation_id UUID, p_enabled_capabilities TEXT[])
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE v_inst RECORD; v_manifest_caps TEXT[]; v_cap TEXT;
BEGIN
  SELECT pi.status, pi.plugin_version_id, pv.status AS version_status, pl.status AS plugin_status, pv.manifest INTO v_inst
  FROM plugins.plugin_installations pi JOIN plugins.plugin_versions pv ON pv.id = pi.plugin_version_id JOIN plugins.plugins pl ON pl.id = pi.plugin_id
  WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plugins: installation not found for this organization'; END IF;
  IF v_inst.status NOT IN ('INSTALLED','SUSPENDED') THEN RAISE EXCEPTION 'plugins: cannot activate from status %', v_inst.status; END IF;
  IF v_inst.plugin_status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: plugin is not APPROVED'; END IF;
  IF v_inst.version_status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: plugin version is not APPROVED (status=%)', v_inst.version_status; END IF;
  SELECT ARRAY(SELECT jsonb_array_elements_text(v_inst.manifest -> 'capabilities')) INTO v_manifest_caps;
  FOREACH v_cap IN ARRAY p_enabled_capabilities LOOP
    IF NOT (v_cap = ANY(v_manifest_caps)) THEN RAISE EXCEPTION 'plugins: capability % is not in the plugin version manifest', v_cap; END IF;
  END LOOP;
  UPDATE plugins.plugin_installations SET status = 'ACTIVE', enabled_capabilities = p_enabled_capabilities, activated_at = COALESCE(activated_at, NOW()), updated_at = NOW() WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_activate_plugin(UUID, UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_activate_plugin(UUID, UUID, TEXT[]) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION plugins.fn_uninstall_plugin(p_organization_id UUID, p_installation_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM plugins.plugin_installations WHERE id = p_installation_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plugins: installation not found'; END IF;
  IF v_status = 'UNINSTALLED' THEN RETURN; END IF;
  UPDATE plugins.plugin_installations SET status = 'UNINSTALLED', uninstalled_at = NOW(), updated_at = NOW() WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_uninstall_plugin(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_uninstall_plugin(UUID, UUID) TO app_worker, app_platform_admin;

CREATE OR REPLACE FUNCTION plugins.fn_upgrade_plugin(p_organization_id UUID, p_installation_id UUID, p_new_version_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE v_inst RECORD; v_new_ver RECORD;
BEGIN
  SELECT pi.status, pi.plugin_id, pi.plugin_version_id INTO v_inst FROM plugins.plugin_installations pi WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plugins: installation not found for this organization'; END IF;
  IF v_inst.status = 'UNINSTALLED' THEN RAISE EXCEPTION 'plugins: cannot upgrade UNINSTALLED installation'; END IF;
  SELECT pv.plugin_id, pv.status INTO v_new_ver FROM plugins.plugin_versions pv WHERE pv.id = p_new_version_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plugins: new version % not found', p_new_version_id; END IF;
  IF v_new_ver.plugin_id <> v_inst.plugin_id THEN RAISE EXCEPTION 'plugins: version % does not belong to the same plugin', p_new_version_id; END IF;
  IF v_new_ver.status <> 'APPROVED' THEN RAISE EXCEPTION 'plugins: new version % is not APPROVED (status=%)', p_new_version_id, v_new_ver.status; END IF;
  IF p_new_version_id = v_inst.plugin_version_id THEN RETURN; END IF;
  PERFORM set_config('plugins.upgrade_in_progress', 'true', TRUE);
  UPDATE plugins.plugin_installations SET plugin_version_id = p_new_version_id, enabled_capabilities = '{}', status = 'INSTALLED', updated_at = NOW() WHERE id = p_installation_id;
  PERFORM set_config('plugins.upgrade_in_progress', 'false', TRUE);
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_upgrade_plugin(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_upgrade_plugin(UUID, UUID, UUID) TO app_worker, app_platform_admin;

CREATE TABLE plugins.plugin_executions (
  id                     UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID        NOT NULL,
  plugin_installation_id UUID        NOT NULL REFERENCES plugins.plugin_installations(id) ON DELETE RESTRICT,
  plugin_version_id      UUID        NOT NULL REFERENCES plugins.plugin_versions(id) ON DELETE RESTRICT,
  capability             TEXT        NOT NULL,
  endpoint               TEXT        NOT NULL,
  status                 TEXT        NOT NULL DEFAULT 'PENDING',
  input_preview          TEXT        NULL,
  input_ref              TEXT        NULL,
  output_preview         TEXT        NULL,
  output_ref             TEXT        NULL,
  http_status_code       INTEGER     NULL,
  failure_reason         TEXT        NULL,
  correlation_id         UUID        NULL,
  idempotency_key        TEXT        NULL,
  started_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at           TIMESTAMPTZ NULL,
  CONSTRAINT pk_plugin_executions      PRIMARY KEY (id),
  CONSTRAINT chk_pe_status             CHECK (status IN ('PENDING','RUNNING','SUCCEEDED','FAILED','TIMED_OUT')),
  CONSTRAINT chk_pe_capability         CHECK (length(capability) BETWEEN 1 AND 100),
  CONSTRAINT chk_pe_endpoint           CHECK (length(endpoint) BETWEEN 1 AND 500),
  CONSTRAINT chk_pe_failure_reason_len CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000)
);
CREATE INDEX idx_pe_installation ON plugins.plugin_executions (plugin_installation_id, started_at DESC);
CREATE INDEX idx_pe_org_status   ON plugins.plugin_executions (organization_id, status);
CREATE INDEX idx_pe_correlation  ON plugins.plugin_executions (correlation_id) WHERE correlation_id IS NOT NULL;
REVOKE UPDATE, DELETE ON plugins.plugin_executions FROM app_api;
GRANT SELECT, INSERT ON plugins.plugin_executions TO app_api;
GRANT SELECT, INSERT, UPDATE ON plugins.plugin_executions TO app_worker;
GRANT SELECT ON plugins.plugin_executions TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON plugins.plugin_executions TO app_platform_admin;
ALTER TABLE plugins.plugin_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE plugins.plugin_executions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pe_tenant ON plugins.plugin_executions FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
