-- Migration 064 (Phase 5I): plugins.plugins and plugins.plugin_versions
-- down_revision: 063_5I
CREATE TABLE plugins.plugins (
  id                UUID        NOT NULL DEFAULT gen_uuid_v7(),
  developer_org_id  UUID        NOT NULL,
  slug              TEXT        NOT NULL,
  name              TEXT        NOT NULL,
  description       TEXT        NULL,
  status            TEXT        NOT NULL DEFAULT 'PENDING_REVIEW',
  documentation_url TEXT        NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_plugins      PRIMARY KEY (id),
  CONSTRAINT uq_plugin_slug  UNIQUE (slug),
  CONSTRAINT chk_plug_slug   CHECK (slug ~ '^[a-z][a-z0-9_-]{0,98}[a-z0-9]$'),
  CONSTRAINT chk_plug_status CHECK (status IN ('PENDING_REVIEW','APPROVED','REJECTED')),
  CONSTRAINT chk_plug_name   CHECK (length(name) BETWEEN 1 AND 100)
);
CREATE OR REPLACE FUNCTION plugins.fn_plug_slug_immutable()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF NEW.slug <> OLD.slug THEN RAISE EXCEPTION 'plugins.slug is immutable'; END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_plug_slug_immutable() FROM PUBLIC;
CREATE TRIGGER trg_plug_slug_immutable BEFORE UPDATE ON plugins.plugins FOR EACH ROW EXECUTE FUNCTION plugins.fn_plug_slug_immutable();
CREATE TRIGGER trg_plug_updated_at     BEFORE UPDATE ON plugins.plugins FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_pl_status ON plugins.plugins (status);
GRANT SELECT ON plugins.plugins TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON plugins.plugins TO app_platform_admin;

CREATE TABLE plugins.plugin_versions (
  id               UUID        NOT NULL DEFAULT gen_uuid_v7(),
  plugin_id        UUID        NOT NULL REFERENCES plugins.plugins(id) ON DELETE RESTRICT,
  semver           TEXT        NOT NULL,
  manifest         JSONB       NOT NULL,
  status           TEXT        NOT NULL DEFAULT 'PENDING_REVIEW',
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at      TIMESTAMPTZ NULL,
  approved_by_ref  UUID        NULL,
  rejected_at      TIMESTAMPTZ NULL,
  rejection_reason TEXT        NULL,
  deprecated_at    TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_plugin_versions     PRIMARY KEY (id),
  CONSTRAINT uq_pv_plugin_semver    UNIQUE (plugin_id, semver),
  CONSTRAINT chk_pv_status          CHECK (status IN ('PENDING_REVIEW','APPROVED','REJECTED','DEPRECATED')),
  CONSTRAINT chk_pv_semver          CHECK (semver ~ '^\d+\.\d+\.\d+'),
  CONSTRAINT chk_pv_manifest_object CHECK (jsonb_typeof(manifest) = 'object'),
  CONSTRAINT chk_pv_approved_has_at CHECK ((status = 'APPROVED' AND approved_at IS NOT NULL) OR status <> 'APPROVED')
);
CREATE OR REPLACE FUNCTION plugins.fn_pv_manifest_immutable()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF OLD.approved_at IS NOT NULL AND NEW.manifest <> OLD.manifest THEN
    RAISE EXCEPTION 'plugins: plugin_version manifest is immutable after approval';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_pv_manifest_immutable() FROM PUBLIC;
CREATE TRIGGER trg_pv_manifest_immutable BEFORE UPDATE ON plugins.plugin_versions FOR EACH ROW EXECUTE FUNCTION plugins.fn_pv_manifest_immutable();
CREATE INDEX idx_pv_plugin   ON plugins.plugin_versions (plugin_id, semver);
CREATE INDEX idx_pv_approved ON plugins.plugin_versions (plugin_id) WHERE status = 'APPROVED';
GRANT SELECT ON plugins.plugin_versions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON plugins.plugin_versions TO app_platform_admin;
