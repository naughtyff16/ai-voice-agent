-- =================================================================
-- Migration 003 (Phase 5B): organization schema tables
-- down_revision: 002_5B
-- Transaction: yes
-- Source: 5B §33.3
-- Corrections applied:
--   - Table creation order: organizations → roles → permissions →
--     memberships → teams → team_memberships → role_permissions
--     (5K §10.2: memberships has FK→roles; raw source had wrong order)
--   - get_user_organization_ids() added here (needs memberships)
-- =================================================================

-- organization.organizations (RLS root — no policy)
CREATE TABLE organization.organizations (
  id                      UUID        NOT NULL DEFAULT gen_uuid_v7(),
  name                    TEXT        NOT NULL,
  slug                    TEXT        NOT NULL,
  legal_name              TEXT        NULL,
  status                  TEXT        NOT NULL DEFAULT 'ACTIVE',
  owner_user_id           UUID        NOT NULL,
  country_code            TEXT        NOT NULL,
  currency                CHAR(3)     NOT NULL,
  timezone                TEXT        NOT NULL DEFAULT 'Asia/Kolkata',
  locale                  TEXT        NOT NULL DEFAULT 'en-IN',
  phone_country           TEXT        NOT NULL DEFAULT 'IN',
  primary_language        TEXT        NOT NULL DEFAULT 'en-IN',
  supported_languages     TEXT[]      NOT NULL DEFAULT '{}',
  fiscal_year_start_month INTEGER     NOT NULL DEFAULT 4,
  region_ref              TEXT        NOT NULL DEFAULT 'standard',
  data_residency_profile  TEXT        NOT NULL DEFAULT 'STANDARD',
  compliance_policy_id    UUID        NULL,
  tax_profile_id          UUID        NULL,
  billing_account_id      UUID        NULL,
  website                 TEXT        NULL,
  logo_storage_ref        TEXT        NULL,
  deleted_at              TIMESTAMPTZ NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_organizations            PRIMARY KEY (id),
  CONSTRAINT chk_orgs_status            CHECK (status IN ('ACTIVE','SUSPENDED','CANCELLED')),
  CONSTRAINT chk_orgs_currency          CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_orgs_country_code      CHECK (length(country_code) = 2 AND country_code = upper(country_code)),
  CONSTRAINT chk_orgs_fiscal_month      CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  CONSTRAINT chk_orgs_residency_profile CHECK (data_residency_profile IN ('STANDARD','INDIA_ENTERPRISE','REGIONAL')),
  CONSTRAINT chk_orgs_slug_format       CHECK (slug ~ '^[a-z0-9][a-z0-9\-]{2,62}$')
);
CREATE UNIQUE INDEX uq_organizations_slug  ON organization.organizations (slug);
CREATE INDEX idx_organizations_status ON organization.organizations (status) WHERE status = 'ACTIVE';
CREATE INDEX idx_organizations_owner  ON organization.organizations (owner_user_id);
CREATE INDEX idx_organizations_country ON organization.organizations (country_code);
CREATE TRIGGER trg_organizations_currency_immutable BEFORE UPDATE ON organization.organizations FOR EACH ROW EXECUTE FUNCTION prevent_currency_change();
CREATE TRIGGER trg_organizations_updated_at BEFORE UPDATE ON organization.organizations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
GRANT SELECT, INSERT, UPDATE ON organization.organizations TO app_api, app_worker;
GRANT SELECT ON organization.organizations TO app_readonly;

-- organization.roles (must exist before memberships FK)
CREATE TABLE organization.roles (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NULL,
  name            TEXT        NOT NULL,
  display_name    TEXT        NOT NULL,
  description     TEXT        NULL,
  is_system       BOOLEAN     NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_roles PRIMARY KEY (id)
);
CREATE UNIQUE INDEX uq_roles_system_name ON organization.roles (name) WHERE organization_id IS NULL;
CREATE UNIQUE INDEX uq_roles_tenant_name ON organization.roles (organization_id, name) WHERE organization_id IS NOT NULL;
CREATE INDEX idx_roles_org ON organization.roles (organization_id);
CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON organization.roles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION protect_system_roles()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_system = TRUE AND (NEW.name != OLD.name OR NEW.is_system = FALSE) THEN
    RAISE EXCEPTION 'System role % cannot have its name changed or is_system flag altered', OLD.name;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_protect_system_roles BEFORE UPDATE ON organization.roles FOR EACH ROW EXECUTE FUNCTION protect_system_roles();
ALTER TABLE organization.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.roles FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_roles_read ON organization.roles FOR SELECT USING (organization_id = organization.current_tenant_id() OR organization_id IS NULL);
CREATE POLICY rls_roles_insert ON organization.roles FOR INSERT WITH CHECK (organization_id = organization.current_tenant_id());
CREATE POLICY rls_roles_update ON organization.roles FOR UPDATE USING (organization_id = organization.current_tenant_id());
CREATE POLICY rls_roles_delete ON organization.roles FOR DELETE USING (organization_id = organization.current_tenant_id() AND is_system = FALSE);
GRANT SELECT, INSERT, UPDATE, DELETE ON organization.roles TO app_api, app_worker;

-- organization.permissions (no RLS — platform-owned reference data)
CREATE TABLE organization.permissions (
  id           UUID        NOT NULL DEFAULT gen_uuid_v7(),
  name         TEXT        NOT NULL,
  display_name TEXT        NOT NULL,
  description  TEXT        NULL,
  resource     TEXT        NOT NULL,
  action       TEXT        NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_permissions PRIMARY KEY (id)
);
CREATE UNIQUE INDEX uq_permissions_name ON organization.permissions (name);
CREATE INDEX idx_permissions_resource ON organization.permissions (resource);
GRANT SELECT ON organization.permissions TO app_api, app_worker, app_readonly;

-- organization.memberships (FK → organizations + roles — both now exist)
CREATE TABLE organization.memberships (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  user_id         UUID        NOT NULL,
  role_id         UUID        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'ACTIVE',
  invited_by      UUID        NULL,
  invited_at      TIMESTAMPTZ NULL,
  accepted_at     TIMESTAMPTZ NULL,
  removed_at      TIMESTAMPTZ NULL,
  removed_by      UUID        NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_memberships        PRIMARY KEY (id),
  CONSTRAINT fk_memberships_org    FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE RESTRICT,
  CONSTRAINT fk_memberships_role   FOREIGN KEY (role_id) REFERENCES organization.roles(id) ON DELETE RESTRICT,
  CONSTRAINT chk_memberships_status CHECK (status IN ('ACTIVE','SUSPENDED','REMOVED'))
);
CREATE UNIQUE INDEX uq_memberships_active ON organization.memberships (organization_id, user_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_memberships_user_active ON organization.memberships (user_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_memberships_org_role ON organization.memberships (organization_id, role_id);
CREATE TRIGGER trg_memberships_updated_at BEFORE UPDATE ON organization.memberships FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE organization.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.memberships FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_memberships_tenant ON organization.memberships FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON organization.memberships TO app_api, app_worker;

-- organization.teams
CREATE TABLE organization.teams (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  name            TEXT        NOT NULL,
  description     TEXT        NULL,
  status          TEXT        NOT NULL DEFAULT 'ACTIVE',
  created_by      UUID        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_teams     PRIMARY KEY (id),
  CONSTRAINT fk_teams_org FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE CASCADE,
  CONSTRAINT chk_teams_status CHECK (status IN ('ACTIVE','ARCHIVED'))
);
CREATE UNIQUE INDEX uq_teams_org_name ON organization.teams (organization_id, name);
CREATE INDEX idx_teams_org ON organization.teams (organization_id);
CREATE TRIGGER trg_teams_updated_at BEFORE UPDATE ON organization.teams FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE organization.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.teams FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_teams_tenant ON organization.teams FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON organization.teams TO app_api, app_worker;

-- organization.team_memberships
CREATE TABLE organization.team_memberships (
  id              UUID        NOT NULL DEFAULT gen_uuid_v7(),
  organization_id UUID        NOT NULL,
  team_id         UUID        NOT NULL,
  user_id         UUID        NOT NULL,
  added_by        UUID        NULL,
  added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  removed_at      TIMESTAMPTZ NULL,

  CONSTRAINT pk_team_memberships      PRIMARY KEY (id),
  CONSTRAINT fk_team_memberships_org  FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_team_memberships_team FOREIGN KEY (team_id) REFERENCES organization.teams(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX uq_team_memberships_active ON organization.team_memberships (team_id, user_id) WHERE removed_at IS NULL;
CREATE INDEX idx_team_memberships_org  ON organization.team_memberships (organization_id);
CREATE INDEX idx_team_memberships_user ON organization.team_memberships (user_id);
ALTER TABLE organization.team_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.team_memberships FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_team_memberships_tenant ON organization.team_memberships FOR ALL USING (organization_id = organization.current_tenant_id()) WITH CHECK (organization_id = organization.current_tenant_id());
GRANT SELECT, INSERT, UPDATE ON organization.team_memberships TO app_api, app_worker;

-- organization.role_permissions
CREATE TABLE organization.role_permissions (
  id            UUID        NOT NULL DEFAULT gen_uuid_v7(),
  role_id       UUID        NOT NULL,
  permission_id UUID        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_role_permissions      PRIMARY KEY (id),
  CONSTRAINT fk_role_perms_role       FOREIGN KEY (role_id) REFERENCES organization.roles(id) ON DELETE CASCADE,
  CONSTRAINT fk_role_perms_permission FOREIGN KEY (permission_id) REFERENCES organization.permissions(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX uq_role_permissions ON organization.role_permissions (role_id, permission_id);
CREATE INDEX idx_role_perms_role_id ON organization.role_permissions (role_id);
ALTER TABLE organization.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.role_permissions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_role_permissions_read ON organization.role_permissions FOR SELECT
  USING (EXISTS (SELECT 1 FROM organization.roles r WHERE r.id = role_id AND (r.organization_id = organization.current_tenant_id() OR r.organization_id IS NULL)));
CREATE POLICY rls_role_permissions_modify ON organization.role_permissions FOR ALL
  USING (EXISTS (SELECT 1 FROM organization.roles r WHERE r.id = role_id AND r.organization_id = organization.current_tenant_id() AND r.is_system = FALSE))
  WITH CHECK (EXISTS (SELECT 1 FROM organization.roles r WHERE r.id = role_id AND r.organization_id = organization.current_tenant_id() AND r.is_system = FALSE));
GRANT SELECT, INSERT, DELETE ON organization.role_permissions TO app_api, app_worker;

-- get_user_organization_ids() — moved here (needs memberships table)
CREATE OR REPLACE FUNCTION organization.get_user_organization_ids(p_user_id UUID)
RETURNS TABLE (organization_id UUID)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = organization, pg_temp
AS $$
  SELECT m.organization_id
  FROM organization.memberships m
  WHERE m.user_id = p_user_id AND m.status = 'ACTIVE'
$$;
REVOKE ALL ON FUNCTION organization.get_user_organization_ids(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION organization.get_user_organization_ids(UUID) TO app_api, app_worker, app_platform_admin;
