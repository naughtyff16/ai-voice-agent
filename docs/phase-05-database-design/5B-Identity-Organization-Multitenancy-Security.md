# Phase 5B — Identity, Organization, Multi-Tenancy & Security
## Physical Database Design

| | |
|---|---|
| **Phase** | 5B — Identity & Organization Physical Database Design |
| **Status** | Draft v1.0 — for approval before Phase 5C |
| **Schemas designed** | `identity`, `organization` |
| **Authority** | Phase 5A Database Architecture & Standards (binding) |
| **Follows** | Phase 5A (APPROVED, PHASE 5B READY) |
| **Precedes** | Phase 5C — Voice Schema |

---

## 1. Executive Summary

This document produces the complete physical PostgreSQL database design for the `identity` and `organization` schemas — the foundation on which all 11 subsequent schemas depend. Every table designed here feeds the multi-tenancy stack that makes the platform enterprise-safe.

**Key decisions made in this document:**

| Decision | Outcome |
|---|---|
| Email canonicalization | Application-layer `LOWER(TRIM(email))` written to `email_normalized TEXT`; `UNIQUE` index on that column. No `CITEXT` extension (see §10.1). |
| User-organization relationship | Many-to-many through `organization.memberships`. `users` has no `organization_id` column — the tenant is established at request time from the membership, not from the user row. |
| Session persistence | Refresh token hashes stored; access JWTs are stateless. One table (`identity.sessions`) for revocable long-lived tokens. |
| Password reset | `identity.password_reset_tokens` stores a SHA-256 hash of the raw token. Raw token is never stored. |
| API key scope | Organization-scoped only. Platform-scoped API keys do not exist in V1. |
| Roles | `TEXT` column, not `ENUM`. System roles seeded with `organization_id IS NULL`. Custom roles supported but not required in V1. |
| Permissions | Separate `organization.permissions` reference table. `TEXT` permission strings (never booleans on tables). |
| Localization | All localization fields are typed columns directly on `organizations` — no separate `localization_profiles` table (see §25). |
| RLS on memberships | Handled via a `SECURITY DEFINER` helper function to avoid circular policy evaluation. |
| India defaults | Applied at `CREATE ORGANIZATION` time in application code. No column `DEFAULT` for `currency` or `country_code`. |

**Tables created in Phase 5B:** 14 tables, 3 RLS helper functions, 5 system roles, ~40 permissions seeded.

---

## 2. Scope

**In scope (this document):**
- `identity` schema: `users`, `sessions`, `password_reset_tokens`, `oauth_identities`, `api_keys`
- `organization` schema: `organizations`, `memberships`, `teams`, `team_memberships`, `roles`, `permissions`, `role_permissions`, `compliance_policies`, `data_subject_requests`
- All indexes, constraints, RLS policies, and helper functions for the above
- Complete DDL (no SQL execution — design artifact)
- Alembic migration plan for these two schemas
- Seed data for system roles and permissions

**Out of scope (later phases):**
- All other schemas (`voice`, `crm`, `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, `audit`)
- Audit event table DDL (designed in Phase 5I) — audit *handoff list* produced here

---

## 3. Source Documents

| Document | Role |
|---|---|
| Phase 5A — Database Architecture & Standards | **Binding** — all standards, conventions, RLS patterns |
| Phase 4A — Core/Identity/Multi-Tenancy DDD | Domain model authority for identity and organization |
| Phase 4H — Final Architecture Review | Issue corrections (analytics permissions, plugin ActionKinds) |
| Phase 4I — India-First Decision Closure | India defaults, currency, timezone, localization, compliance |
| Phase 1 SRS | NFR-SEC-001 through NFR-SEC-004 (security requirements) |
| Phase 3A LLD | Application roles, TenantContext, connection setup |

---

## 4. Schema Overview

```
identity (platform-scoped user registry + authentication artifacts)
├── users                    — Global user registry (platform-owned)
├── sessions                 — Refresh token store (platform-owned, user-scoped)
├── password_reset_tokens    — Hashed reset tokens (platform-owned, user-scoped)
├── oauth_identities         — Provider identity links (platform-owned, user-scoped)
└── api_keys                 — Organization-scoped API credentials (tenant-owned)

organization (tenant management + RBAC + compliance)
├── organizations            — Tenant root (self-rooted)
├── memberships              — User ↔ Organization ↔ Role (tenant-owned)
├── teams                    — Sub-groups within an organization (tenant-owned)
├── team_memberships         — User ↔ Team (tenant-owned)
├── roles                    — System + custom roles (platform + tenant mixed)
├── permissions              — Permission catalogue (platform-owned)
├── role_permissions         — Role ↔ Permission assignments (platform + tenant mixed)
├── compliance_policies      — Org-level calling/recording/consent config (tenant-owned)
└── data_subject_requests    — DSAR workflow tracking (tenant-owned)
```

---

## 5. Identity Schema

### 5.1 Why a Separate `identity` Schema

The `identity` schema contains entities whose lifecycle is independent of any specific organization:
- A `User` exists before they join any organization.
- A `User` may belong to multiple organizations simultaneously.
- OAuth identities and sessions are user-level, not organization-level.
- API keys are organization-scoped but are authentication artifacts that belong with the authentication subsystem.

Separating `identity` from `organization` allows the authentication path (login → session check → API key validation) to never touch the organization schema, keeping the hot path lean.

---

## 6. Organization Schema

### 6.1 Why `organization` is the Tenant Root

`organizations.id` is the value written into `SET LOCAL app.tenant_id = '<uuid>'` for every request. It is the RLS predicate anchor. All subsequent schemas' tenant-scoped tables carry `organization_id UUID NOT NULL` referencing this value logically.

The `organization` schema also owns RBAC because roles, permissions, and memberships are fundamentally organizational governance constructs — a user's permissions are always evaluated in the context of a specific organization.

---

## 7. Entity / Table Inventory

| Table | Schema | Tenant scope | Lifecycle | Soft delete | Immutable |
|---|---|---|---|---|---|
| `users` | identity | Platform | Persisted until soft-deleted (GDPR erasure) | Yes (`deleted_at`) | No |
| `sessions` | identity | Platform (user-scoped) | Expires or revoked | No (status field) | No |
| `password_reset_tokens` | identity | Platform (user-scoped) | TTL 1 hour; used once | No | After use |
| `oauth_identities` | identity | Platform (user-scoped) | Until unlinked | No (status field) | No |
| `api_keys` | identity | Tenant (`organization_id`) | Until revoked | No (`status = REVOKED`) | No |
| `organizations` | organization | Self-root | Persisted; status-managed | Yes (`deleted_at`) | Some columns (currency) |
| `memberships` | organization | Tenant | Active, suspended, or removed | No (`status` + `removed_at`) | No |
| `teams` | organization | Tenant | Active or archived | No (`status`) | No |
| `team_memberships` | organization | Tenant | Active or removed | No (`removed_at`) | No |
| `roles` | organization | Mixed (platform + tenant) | Platform roles seeded; tenant roles managed | No (`is_active`) | No |
| `permissions` | organization | Platform | Seeded; extensible | No | Effectively stable |
| `role_permissions` | organization | Mixed (platform + tenant) | Managed; seeded for system roles | No | No |
| `compliance_policies` | organization | Tenant | Versioned; active version queried | No (`status`) | After publication |
| `data_subject_requests` | organization | Tenant | Workflow: open → completed/rejected | No (`status`) | No |

---

## 8. Aggregate-to-Table Mapping

| DDD Aggregate | Primary table | Embedded as columns | Child tables |
|---|---|---|---|
| `User` | `identity.users` | `EmailAddress` (columns), `PhoneNumber` (columns) | `identity.sessions`, `identity.oauth_identities`, `identity.password_reset_tokens` |
| `ApiKey` | `identity.api_keys` | `ApiKeyScope` (TEXT[] column) | — |
| `Organization` | `organization.organizations` | `LocalizationProfile` (typed columns), `DataResidencyProfile` (typed columns) | `organization.memberships`, `organization.teams` |
| `Membership` | `organization.memberships` | — | — |
| `Role` | `organization.roles` | — | `organization.role_permissions` |
| `CompliancePolicy` | `organization.compliance_policies` | `CallingWindows` (JSONB), `RetentionProfile` (JSONB) | — |
| `DataSubjectRequest` | `organization.data_subject_requests` | — | — |

---

## 9. Column-Level Data Dictionary

### 9.1 `identity.users`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK — UUIDv7 |
| `email` | TEXT | NOT NULL | — | Original casing preserved for display. **pii:email** |
| `email_normalized` | TEXT | NOT NULL | — | `LOWER(TRIM(email))` — unique lookup key |
| `display_name` | TEXT | NOT NULL | — | Full display name. **pii:name** |
| `phone_e164` | TEXT | NULL | — | Canonical E.164. **pii:phone** |
| `phone_verified_at` | TIMESTAMPTZ | NULL | — | When phone was verified |
| `email_verified_at` | TIMESTAMPTZ | NULL | — | When email was verified |
| `password_hash` | TEXT | NULL | — | bcrypt/argon2id hash. NULL if OAuth-only. Never logged. |
| `password_changed_at` | TIMESTAMPTZ | NULL | — | Last password change timestamp |
| `status` | TEXT | NOT NULL | `'PENDING_VERIFICATION'` | `PENDING_VERIFICATION \| ACTIVE \| SUSPENDED \| DELETED` |
| `last_login_at` | TIMESTAMPTZ | NULL | — | Updated on successful authentication |
| `failed_login_count` | INTEGER | NOT NULL | `0` | Reset on successful login; read by app for lockout logic |
| `last_failed_login_at` | TIMESTAMPTZ | NULL | — | For lockout rate-limiting |
| `mfa_enabled` | BOOLEAN | NOT NULL | `FALSE` | Whether TOTP MFA is configured |
| `mfa_secret_ref` | TEXT | NULL | — | `credential_ref` to secret manager — never raw secret |
| `deleted_at` | TIMESTAMPTZ | NULL | — | Soft delete — PII cleared separately on erasure |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | Trigger-maintained |

**Design rationale:**
- `email` preserves display casing; `email_normalized` is the authentication and uniqueness key.
- `phone_e164` on `users` is not unique globally — a user may share a phone across org contexts. Phone uniqueness is enforced at `contacts` level in the CRM schema.
- `password_hash` is NULL for OAuth-only users — the application layer must not allow password login for NULL-hash users.
- `failed_login_count` and `last_failed_login_at` live in the DB so multiple API instances share state. Account lockout policy is enforced in the application layer; the DB provides the shared counters.
- `mfa_secret_ref` is an opaque credential reference — the raw TOTP secret lives in the secret manager.
- On GDPR erasure: `email = '[ERASED@erased.invalid]'`, `email_normalized = '[erased-{id}]'`, `display_name = '[ERASED]'`, `phone_e164 = NULL`, `password_hash = NULL`, `deleted_at = NOW()`.

### 9.2 `identity.sessions`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `user_id` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `refresh_token_hash` | TEXT | NOT NULL | — | SHA-256 hex of the raw refresh token |
| `access_token_jti` | TEXT | NULL | — | JWT ID of the current access token; used for revocation |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| REVOKED \| EXPIRED` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `expires_at` | TIMESTAMPTZ | NOT NULL | — | Refresh token expiry (e.g. 30 days) |
| `revoked_at` | TIMESTAMPTZ | NULL | — | When explicitly revoked |
| `last_seen_at` | TIMESTAMPTZ | NULL | — | Updated on every token refresh |
| `device_label` | TEXT | NULL | — | Optional user-set label (e.g. "iPhone 15") |
| `ip_address` | INET | NULL | — | IP at session creation. **pii:network** |
| `user_agent_hash` | TEXT | NULL | — | SHA-256 of user-agent string — no raw UA stored |

**Design rationale:**
- JWTs are stateless access tokens (15-minute expiry) — the DB does not store them row-by-row on every request.
- `sessions` stores **refresh tokens** (long-lived, revocable) so users can log out all sessions or revoke a compromised device.
- `access_token_jti` enables single access-token revocation without revoking the full session (emergency use).
- `ip_address` is `INET` type (PostgreSQL native) — supports both IPv4 and IPv6. Classified PII:network — masked in logs.
- Raw user-agent string is not stored; only its hash. Avoids PII creep from detailed UA strings.

### 9.3 `identity.password_reset_tokens`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `user_id` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `token_hash` | TEXT | NOT NULL | — | SHA-256 hex of the raw token. UNIQUE. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `expires_at` | TIMESTAMPTZ | NOT NULL | — | `created_at + 1 hour` |
| `used_at` | TIMESTAMPTZ | NULL | — | Set on first use; NULL = unused |
| `purpose` | TEXT | NOT NULL | `'PASSWORD_RESET'` | `PASSWORD_RESET \| EMAIL_VERIFICATION \| INVITATION` |

**Design rationale:**
- Raw token is generated by the application (cryptographically random, 32+ bytes), sent to the user via email, and SHA-256 hashed before storage.
- `used_at` is set immediately on redemption — double-use is rejected by the application.
- `expires_at` is enforced at the application layer on redemption. A background job may clean up expired rows after 7 days but must not rely on expiry for security (application must check).
- `purpose` covers email verification and invitation acceptance using the same token mechanics.

### 9.4 `identity.oauth_identities`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `user_id` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `provider` | TEXT | NOT NULL | — | `google \| microsoft \| github \| ...` — extensible |
| `provider_subject` | TEXT | NOT NULL | — | Provider's unique user ID for this user |
| `email_at_provider` | TEXT | NULL | — | Email from provider at last login. **pii:email** |
| `display_name_at_provider` | TEXT | NULL | — | Display name from provider. **pii:name** |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| UNLINKED` |
| `credential_ref` | TEXT | NULL | — | `secret_manager://...` reference if provider tokens needed |
| `linked_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `last_login_at` | TIMESTAMPTZ | NULL | — | Last OAuth login using this identity |
| `unlinked_at` | TIMESTAMPTZ | NULL | — | When unlinked |

**Design rationale:**
- `(provider, provider_subject)` is globally unique — one provider identity maps to exactly one platform user.
- `credential_ref` is NULL for providers where we only use the identity for authentication (no offline access). For providers requiring stored tokens (e.g. calendar sync), the encrypted token is in the secret manager.
- `email_at_provider` is informational — the canonical user email is on `identity.users.email_normalized`.
- `status = 'UNLINKED'` instead of DELETE so audit history is preserved.

### 9.5 `identity.api_keys`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | Logical ref: `organization.organizations.id` |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `name` | TEXT | NOT NULL | — | Human label (e.g. "Production webhook key") |
| `key_prefix` | TEXT | NOT NULL | — | First 8 chars of raw key, shown in UI for identification |
| `key_hash` | TEXT | NOT NULL | — | SHA-256 hex of full raw key. UNIQUE. |
| `scopes` | TEXT[] | NOT NULL | `'{}'` | Array of permitted scope strings |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| REVOKED \| EXPIRED` |
| `expires_at` | TIMESTAMPTZ | NULL | — | NULL = non-expiring. Checked at auth time. |
| `last_used_at` | TIMESTAMPTZ | NULL | — | Updated on every successful use |
| `last_used_ip` | INET | NULL | — | Last source IP |
| `revoked_at` | TIMESTAMPTZ | NULL | — | When revoked |
| `revoked_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Design rationale:**
- Raw API key is returned to the caller exactly once (on creation). The DB stores only `key_hash` (SHA-256) and `key_prefix` (display hint).
- `scopes` is `TEXT[]` (PostgreSQL native array) — avoids a separate junction table for a bounded list that is always read with the key.
- API keys are organization-scoped — they establish the `organization_id` in `SET LOCAL app.tenant_id` during authentication. There are no user-scoped or platform-scoped API keys in V1.
- `last_used_at` is updated on every auth — this is a deliberate high-frequency write. The application may batch these updates or use Redis as an intermediary for rate-limited commits.

### 9.6 `organization.organizations`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK — the tenant ID |
| `name` | TEXT | NOT NULL | — | Display name |
| `slug` | TEXT | NOT NULL | — | URL-safe unique identifier. UNIQUE. Lowercase, alphanumeric + hyphens. |
| `legal_name` | TEXT | NULL | — | Legal entity name for invoices |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| SUSPENDED \| CANCELLED` |
| `owner_user_id` | UUID | NOT NULL | — | Logical ref: `identity.users.id` — the founding owner |
| `country_code` | TEXT | NOT NULL | — | ISO 3166-1 alpha-2. No column DEFAULT — set at creation. |
| `currency` | CHAR(3) | NOT NULL | — | ISO 4217. No column DEFAULT — set at creation. **Write-once (enforced by trigger).** |
| `timezone` | TEXT | NOT NULL | — | IANA timezone. Default `'Asia/Kolkata'` at app layer. |
| `locale` | TEXT | NOT NULL | — | BCP 47. Default `'en-IN'` at app layer. |
| `phone_country` | TEXT | NOT NULL | — | ISO 3166-1 alpha-2 phone parsing hint. Default `'IN'`. |
| `primary_language` | TEXT | NOT NULL | — | BCP 47. Default `'en-IN'`. |
| `supported_languages` | TEXT[] | NOT NULL | `'{}'` | BCP 47 array. Default `'{en-IN,ta-IN}'` for India. |
| `fiscal_year_start_month` | INTEGER | NOT NULL | `4` | 1–12. Default 4 (April — India fiscal year). |
| `region_ref` | TEXT | NOT NULL | `'standard'` | Abstract residency region. `standard \| in-primary \| regional` |
| `data_residency_profile` | TEXT | NOT NULL | `'STANDARD'` | `STANDARD \| INDIA_ENTERPRISE \| REGIONAL` |
| `compliance_policy_id` | UUID | NULL | — | Logical ref: `organization.compliance_policies.id` — active policy |
| `tax_profile_id` | UUID | NULL | — | Logical ref: `billing.tax_profiles.id` (cross-schema logical ref) |
| `billing_account_id` | UUID | NULL | — | Logical ref: `billing.billing_accounts.id` (cross-schema logical ref) |
| `website` | TEXT | NULL | — | |
| `logo_url` | TEXT | NULL | — | |
| `deleted_at` | TIMESTAMPTZ | NULL | — | Soft delete |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Column design notes:**
- `currency` and `country_code` have **no column DEFAULT** — see Phase 5A §10.3. The application's `CreateOrganizationUseCase` sets them from signup context (default `INR`, `IN` for Indian customers).
- `currency` immutability is enforced by a `BEFORE UPDATE` trigger that raises an exception if the currency value changes.
- `slug` is lowercase `[a-z0-9-]{3,63}` — validated at application layer. UNIQUE across the entire platform.
- `compliance_policy_id`, `tax_profile_id`, `billing_account_id` are logical references set after those entities are created (circular reference otherwise). They are nullable until the lifecycle event sets them.
- `fiscal_year_start_month = 4` is the India default. Phase 5G's invoice numbering uses this to determine the fiscal year boundary.

### 9.7 `organization.memberships`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | FK: `organization.organizations.id` |
| `user_id` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `role_id` | UUID | NOT NULL | — | FK: `organization.roles.id` |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| SUSPENDED \| REMOVED` |
| `invited_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `invited_at` | TIMESTAMPTZ | NULL | — | |
| `accepted_at` | TIMESTAMPTZ | NULL | — | When invitation was accepted |
| `removed_at` | TIMESTAMPTZ | NULL | — | When membership was ended |
| `removed_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Design rationale:**
- `UNIQUE (organization_id, user_id)` — one active membership record per user per org. A removed and re-invited user gets a new membership row (old row has `status = 'REMOVED'`).
- Wait — **historical accuracy**: if we re-invite a user, we need a new row, but `UNIQUE (organization_id, user_id)` would block that. **Resolution:** the unique constraint applies to active memberships only. We use a **partial unique index**: `CREATE UNIQUE INDEX uq_memberships_active ON organization.memberships (organization_id, user_id) WHERE status = 'ACTIVE'`. Removed memberships are not constrained. This allows re-invitation after removal.
- `role_id` is a within-schema FK to `organization.roles` — this is one of the permitted cross-aggregate references within a schema (see Phase 5A §7.4).

### 9.8 `organization.teams`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | FK: `organization.organizations.id` |
| `name` | TEXT | NOT NULL | — | Team name, unique within org |
| `description` | TEXT | NULL | — | |
| `status` | TEXT | NOT NULL | `'ACTIVE'` | `ACTIVE \| ARCHIVED` |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

### 9.9 `organization.team_memberships`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | FK: `organization.organizations.id` (denormalised for RLS) |
| `team_id` | UUID | NOT NULL | — | FK: `organization.teams.id` |
| `user_id` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `added_by` | UUID | NULL | — | Logical ref: `identity.users.id` |
| `added_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `removed_at` | TIMESTAMPTZ | NULL | — | |

**Why `organization_id` denormalized on `team_memberships`:** RLS requires `organization_id` directly on the table for the standard policy. Joining through `teams` would require a security-definer function, which is necessary for memberships but avoidable here.

### 9.10 `organization.roles`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NULL | — | NULL = system role (platform-global). UUID = tenant custom role. |
| `name` | TEXT | NOT NULL | — | `OWNER \| ADMIN \| MEMBER \| BILLING_ADMIN \| VIEWER` for system roles |
| `display_name` | TEXT | NOT NULL | — | Human-readable label |
| `description` | TEXT | NULL | — | |
| `is_system` | BOOLEAN | NOT NULL | `FALSE` | TRUE = seeded platform role; cannot be deleted |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Design rationale:**
- `name` is `TEXT`, not `ENUM` — Phase 5A §21.7 prohibits PostgreSQL ENUMs for evolving status values.
- `UNIQUE (organization_id, name)` — but organization_id can be NULL for system roles. PostgreSQL treats NULLs as distinct in unique indexes, so multiple NULL rows with the same name would be allowed by default. **Solution:** a partial unique index: `CREATE UNIQUE INDEX uq_roles_system_name ON organization.roles (name) WHERE organization_id IS NULL;` and `CREATE UNIQUE INDEX uq_roles_tenant_name ON organization.roles (organization_id, name) WHERE organization_id IS NOT NULL;`
- System roles have `is_system = TRUE` and cannot be deleted or have their `name` changed (enforced by a trigger).

### 9.11 `organization.permissions`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `name` | TEXT | NOT NULL | — | Unique permission string, e.g. `'contact:read'` |
| `display_name` | TEXT | NOT NULL | — | Human-readable |
| `description` | TEXT | NULL | — | |
| `resource` | TEXT | NOT NULL | — | Resource grouping, e.g. `'contact'`, `'billing'` |
| `action` | TEXT | NOT NULL | — | Action component, e.g. `'read'`, `'manage'` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

Platform-owned; no RLS; `UNIQUE (name)`.

### 9.12 `organization.role_permissions`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `role_id` | UUID | NOT NULL | — | FK: `organization.roles.id` |
| `permission_id` | UUID | NOT NULL | — | FK: `organization.permissions.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

`UNIQUE (role_id, permission_id)`.

### 9.13 `organization.compliance_policies`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | FK: `organization.organizations.id` |
| `name` | TEXT | NOT NULL | — | Policy label |
| `status` | TEXT | NOT NULL | `'DRAFT'` | `DRAFT \| ACTIVE \| ARCHIVED` |
| `version` | INTEGER | NOT NULL | `1` | Monotonically incremented on activation |
| `require_consent_for_outbound` | BOOLEAN | NOT NULL | `TRUE` | Gate on consent before outbound call |
| `required_consent_purposes` | TEXT[] | NOT NULL | `'{OUTBOUND_CALL}'` | Array of ConsentPurpose values |
| `recording_policy` | TEXT | NOT NULL | `'ENABLED'` | `DISABLED \| ENABLED \| REQUIRES_CONSENT \| REQUIRES_DISCLOSURE` |
| `recording_disclosure_prompt_id` | UUID | NULL | — | Logical ref: `workflow.prompt_templates.id` |
| `calling_windows` | JSONB | NOT NULL | `'[]'` | Array of `{days, start_time, end_time}` |
| `holiday_calendar_ref` | TEXT | NULL | — | Abstract calendar ID, e.g. `'IN-national'` |
| `allowed_phone_types` | TEXT[] | NOT NULL | `'{MOBILE,LANDLINE}'` | Phone types eligible for outbound |
| `max_attempts_per_contact` | INTEGER | NOT NULL | `3` | Rolling window limit |
| `attempt_window_days` | INTEGER | NOT NULL | `7` | Rolling window size |
| `suppression_scope` | TEXT | NOT NULL | `'ORG'` | `ORG \| ORG_AND_PLATFORM` |
| `block_on_policy_failure` | BOOLEAN | NOT NULL | `TRUE` | Hard stop if policy validation fails |
| `retention_profile` | JSONB | NOT NULL | `'{}'` | `{recording_days, transcript_days, ...}` |
| `policy_version` | INTEGER | NOT NULL | `1` | Incremented on change — evidence reference |
| `effective_from` | TIMESTAMPTZ | NULL | — | When this policy became active |
| `created_by` | UUID | NOT NULL | — | Logical ref: `identity.users.id` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Design rationale:**
- `calling_windows` is JSONB because the structure is variable (any combination of days and times), always read as a whole, and not individually queried by SQL. The application deserializes it.
- No tax rates, slab thresholds, or regulatory thresholds are columns — the platform provides controls, not legal compliance. Default values (`require_consent_for_outbound = TRUE`) reflect India-first conservative defaults, not encoded law.
- An organization may have multiple policies over time; `status = 'ACTIVE'` identifies the current one. Only one policy per organization may be `ACTIVE` — enforced by a partial unique index: `UNIQUE (organization_id) WHERE status = 'ACTIVE'`.

### 9.14 `organization.data_subject_requests`

| Column | Type | Nullable | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | NOT NULL | `gen_uuid_v7()` | PK |
| `organization_id` | UUID | NOT NULL | — | FK: `organization.organizations.id` |
| `request_type` | TEXT | NOT NULL | — | `ACCESS \| EXPORT \| DELETE \| RECTIFY \| RESTRICT` |
| `subject_contact_id` | UUID | NULL | — | Logical ref: `crm.contacts.id` if contact is known |
| `subject_email` | TEXT | NULL | — | Subject's email if contact not in CRM. **pii:email** |
| `subject_phone_e164` | TEXT | NULL | — | Subject's phone. **pii:phone** |
| `status` | TEXT | NOT NULL | `'RECEIVED'` | `RECEIVED \| VERIFYING \| IN_PROGRESS \| COMPLETED \| REJECTED \| ON_HOLD` |
| `requested_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `verified_at` | TIMESTAMPTZ | NULL | — | When subject identity was verified |
| `completed_at` | TIMESTAMPTZ | NULL | — | |
| `due_at` | TIMESTAMPTZ | NULL | — | Compliance deadline (app-layer calculated) |
| `requested_by` | UUID | NULL | — | Logical ref: `identity.users.id` who logged this |
| `completed_by` | UUID | NULL | — | |
| `resolution_notes` | TEXT | NULL | — | Non-PII summary of what was done |
| `export_storage_ref` | TEXT | NULL | — | S3 reference to export package |
| `rejection_reason` | TEXT | NULL | — | If rejected |
| `created_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |

**Design rationale:**
- `subject_contact_id`, `subject_email`, and `subject_phone_e164` allow the request to be linked to a CRM contact or identified by contact details alone (e.g. if the subject was never in the CRM).
- Minimal PII stored — the actual personal data remains in its owning tables. The request tracks the workflow state.
- `export_storage_ref` points to the S3 path of the export package — never inline content.

---

## 10. Email Normalization

### 10.1 Strategy: Application-Layer Normalization to `email_normalized`

**Decision:** application-layer `LOWER(TRIM(email))` written to `email_normalized`. The `UNIQUE` constraint is on `email_normalized`. Original casing is preserved in `email` for display.

**Why not `CITEXT`:**
- `CITEXT` requires a PostgreSQL extension and makes case-insensitive comparison the column behavior everywhere. This creates subtle surprises in joins and comparisons outside authentication.
- `CITEXT` is a data-type decision that spreads into all queries touching the column; the application-layer approach keeps the normalization logic in one place (the `CreateUserUseCase` and `AuthenticateUserUseCase`).
- Supabase's `CITEXT` support is fine but adds an extension dependency.

**Normalization rule:**
```python
def normalize_email(email: str) -> str:
    return email.lower().strip()
```

This is applied before every insert and every authentication lookup. The `UNIQUE` index on `email_normalized` prevents duplicate registrations with different casing.

**Idempotency:** if an API call submits `User@Example.COM`, the normalized form `user@example.com` is what the unique check evaluates.

---

## 11. Primary Keys

All primary keys are `UUID NOT NULL DEFAULT gen_uuid_v7()`.

**`gen_uuid_v7()` function** (created in the initial migration):

```sql
CREATE OR REPLACE FUNCTION gen_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_time    BIGINT;
  v_unix_ms BIGINT;
  v_hi      BIGINT;
  v_rand    BYTEA;
  v_result  UUID;
BEGIN
  v_unix_ms := EXTRACT(EPOCH FROM CLOCK_TIMESTAMP()) * 1000;
  v_rand := gen_random_bytes(10);
  v_hi := (v_unix_ms << 16) | (get_byte(v_rand, 0)::BIGINT << 8) | get_byte(v_rand, 1)::BIGINT;
  -- Set version bits (0111 = version 7) and variant bits (10)
  v_hi := (v_hi & ~(x'F000'::BIGINT)) | x'7000'::BIGINT;
  v_result := lpad(to_hex(v_hi), 16, '0')::UUID;
  RETURN encode(
    set_byte(
      set_byte(
        decode(replace(v_result::TEXT, '-', ''), 'hex') || v_rand,
        8, (get_byte(decode(replace(v_result::TEXT, '-', ''), 'hex') || v_rand, 8) & x'3F'::INT) | x'80'::INT
      ),
      6, (get_byte(decode(replace(v_result::TEXT, '-', ''), 'hex') || v_rand, 6) & x'0F'::INT) | x'70'::INT
    ),
    'hex'
  )::UUID;
END;
$$;
```

*Note: In production on PostgreSQL 17+, the native `gen_random_uuid()` produces UUIDv4. For UUIDv7, a custom function or the `pg_uuidv7` extension is used. The Alembic migration includes the function creation as migration `001`. If Supabase enables native UUIDv7 support before Phase 5B implementation, the native function replaces this.*

**Simpler alternative for immediate use:**
The `uuid-ossp` extension's `uuid_generate_v4()` generates UUIDv4. For Phase 5B, the application layer generates UUIDv7 before insert (using Python `uuid-utils` library) and passes it as a parameter — the column `DEFAULT` is a fallback only. This is the recommended approach until native PostgreSQL UUIDv7 is available in Supabase.

---

## 12. Foreign Keys

### 12.1 Within-Schema FK Constraints (Permitted)

| Table | Column | References | On Delete |
|---|---|---|---|
| `organization.memberships` | `organization_id` | `organization.organizations(id)` | `RESTRICT` — cannot delete org with active members |
| `organization.memberships` | `role_id` | `organization.roles(id)` | `RESTRICT` — cannot delete role in use |
| `organization.teams` | `organization_id` | `organization.organizations(id)` | `CASCADE` — delete org → delete teams |
| `organization.team_memberships` | `organization_id` | `organization.organizations(id)` | `CASCADE` |
| `organization.team_memberships` | `team_id` | `organization.teams(id)` | `CASCADE` |
| `organization.role_permissions` | `role_id` | `organization.roles(id)` | `CASCADE` |
| `organization.role_permissions` | `permission_id` | `organization.permissions(id)` | `CASCADE` |
| `organization.compliance_policies` | `organization_id` | `organization.organizations(id)` | `RESTRICT` |
| `organization.data_subject_requests` | `organization_id` | `organization.organizations(id)` | `RESTRICT` |

**`ON DELETE RESTRICT` vs. `CASCADE` rationale:**
- `organizations` uses `RESTRICT` on memberships and compliance policies — deleting an organization requires explicitly removing dependencies, preventing accidental cascade data loss.
- `teams` uses `CASCADE` from organizations — teams are entirely internal to an org; there is no cross-org reference.
- No FK from `identity` schema to `organization` schema (cross-schema prohibition). `api_keys.organization_id` is a logical reference.

### 12.2 Cross-Schema Logical References (No FK Constraint)

| Table.Column | References (logical) | Comment |
|---|---|---|
| `identity.api_keys.organization_id` | `organization.organizations.id` | Cross-schema — no FK |
| `identity.api_keys.created_by` | `identity.users.id` | Identity-internal — could be FK; kept logical for flexibility |
| `identity.sessions.user_id` | `identity.users.id` | Same schema but separate aggregate — logical ref preferred |
| `identity.oauth_identities.user_id` | `identity.users.id` | Same reasoning |
| `identity.password_reset_tokens.user_id` | `identity.users.id` | Same reasoning |
| `organization.organizations.owner_user_id` | `identity.users.id` | Cross-schema |
| `organization.memberships.user_id` | `identity.users.id` | Cross-schema |
| `organization.organizations.compliance_policy_id` | `organization.compliance_policies.id` | Self-schema circular reference — kept logical |
| `organization.organizations.tax_profile_id` | `billing.tax_profiles.id` | Cross-schema |
| `organization.organizations.billing_account_id` | `billing.billing_accounts.id` | Cross-schema |

---

## 13. Unique Constraints

| Table | Columns | Type | Condition |
|---|---|---|---|
| `identity.users` | `email_normalized` | UNIQUE INDEX | — |
| `identity.sessions` | `refresh_token_hash` | UNIQUE INDEX | — |
| `identity.password_reset_tokens` | `token_hash` | UNIQUE INDEX | — |
| `identity.oauth_identities` | `(provider, provider_subject)` | UNIQUE INDEX | — |
| `identity.api_keys` | `key_hash` | UNIQUE INDEX | — |
| `organization.organizations` | `slug` | UNIQUE INDEX | — |
| `organization.memberships` | `(organization_id, user_id)` | PARTIAL UNIQUE INDEX | `WHERE status = 'ACTIVE'` |
| `organization.roles` | `name` | PARTIAL UNIQUE INDEX | `WHERE organization_id IS NULL` (system roles) |
| `organization.roles` | `(organization_id, name)` | PARTIAL UNIQUE INDEX | `WHERE organization_id IS NOT NULL` (tenant roles) |
| `organization.role_permissions` | `(role_id, permission_id)` | UNIQUE INDEX | — |
| `organization.permissions` | `name` | UNIQUE INDEX | — |
| `organization.teams` | `(organization_id, name)` | UNIQUE INDEX | — |
| `organization.team_memberships` | `(team_id, user_id)` | PARTIAL UNIQUE INDEX | `WHERE removed_at IS NULL` |
| `organization.compliance_policies` | `organization_id` | PARTIAL UNIQUE INDEX | `WHERE status = 'ACTIVE'` |

---

## 14. Check Constraints

| Table | Column | Constraint | Rule |
|---|---|---|---|
| `identity.users` | `status` | `chk_users_status` | `status IN ('PENDING_VERIFICATION','ACTIVE','SUSPENDED','DELETED')` |
| `identity.users` | `email_normalized` | `chk_users_email_format` | `email_normalized ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'` |
| `identity.sessions` | `status` | `chk_sessions_status` | `status IN ('ACTIVE','REVOKED','EXPIRED')` |
| `identity.api_keys` | `status` | `chk_api_keys_status` | `status IN ('ACTIVE','REVOKED','EXPIRED')` |
| `identity.api_keys` | `key_prefix` | `chk_api_keys_prefix_len` | `length(key_prefix) = 8` |
| `identity.api_keys` | `credential_ref` | — | Not applicable (no credential_ref on api_keys — hash only) |
| `identity.oauth_identities` | `status` | `chk_oauth_status` | `status IN ('ACTIVE','UNLINKED')` |
| `identity.oauth_identities` | `credential_ref` | `chk_oauth_cred_ref` | `credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%'` |
| `organization.organizations` | `status` | `chk_orgs_status` | `status IN ('ACTIVE','SUSPENDED','CANCELLED')` |
| `organization.organizations` | `currency` | `chk_orgs_currency` | `currency ~ '^[A-Z]{3}$'` |
| `organization.organizations` | `country_code` | `chk_orgs_country` | `length(country_code) = 2 AND country_code = upper(country_code)` |
| `organization.organizations` | `fiscal_year_start_month` | `chk_orgs_fiscal_month` | `fiscal_year_start_month BETWEEN 1 AND 12` |
| `organization.organizations` | `data_residency_profile` | `chk_orgs_residency` | `data_residency_profile IN ('STANDARD','INDIA_ENTERPRISE','REGIONAL')` |
| `organization.memberships` | `status` | `chk_memberships_status` | `status IN ('ACTIVE','SUSPENDED','REMOVED')` |
| `organization.compliance_policies` | `status` | `chk_policy_status` | `status IN ('DRAFT','ACTIVE','ARCHIVED')` |
| `organization.compliance_policies` | `recording_policy` | `chk_recording_policy` | `recording_policy IN ('DISABLED','ENABLED','REQUIRES_CONSENT','REQUIRES_DISCLOSURE')` |
| `organization.data_subject_requests` | `request_type` | `chk_dsr_type` | `request_type IN ('ACCESS','EXPORT','DELETE','RECTIFY','RESTRICT')` |
| `organization.data_subject_requests` | `status` | `chk_dsr_status` | `status IN ('RECEIVED','VERIFYING','IN_PROGRESS','COMPLETED','REJECTED','ON_HOLD')` |

---

## 15. Index Strategy

### 15.1 `identity.users`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_users` | `id` | UNIQUE B-tree (PK) | |
| `uq_users_email_normalized` | `email_normalized` | UNIQUE B-tree | Auth lookup — must be fast |
| `idx_users_status` | `status` | PARTIAL B-tree | `WHERE status = 'ACTIVE'` — admin queries |
| `idx_users_created_at` | `created_at` | B-tree | Platform admin time-range queries |

**Query supported by `uq_users_email_normalized`:** `SELECT * FROM identity.users WHERE email_normalized = $1` — called on every login.

### 15.2 `identity.sessions`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_sessions` | `id` | UNIQUE B-tree (PK) | |
| `uq_sessions_token_hash` | `refresh_token_hash` | UNIQUE B-tree | Token validation lookup |
| `idx_sessions_user_active` | `user_id, status` | B-tree | `WHERE status = 'ACTIVE'` — "show my active sessions" |
| `idx_sessions_expires_at` | `expires_at` | B-tree | Cleanup job — find expired sessions |

### 15.3 `identity.api_keys`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_api_keys` | `id` | UNIQUE B-tree (PK) | |
| `uq_api_keys_key_hash` | `key_hash` | UNIQUE B-tree | Auth lookup — called on every API request |
| `idx_api_keys_org_status` | `organization_id, status` | B-tree | List org's active keys |

**Query supported by `uq_api_keys_key_hash`:** `SELECT * FROM identity.api_keys WHERE key_hash = $1` — critical hot path. The hash is computed in the application before the query.

### 15.4 `identity.oauth_identities`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_oauth_identities` | `id` | UNIQUE B-tree (PK) | |
| `uq_oauth_provider_subject` | `(provider, provider_subject)` | UNIQUE B-tree | OAuth callback lookup |
| `idx_oauth_user_id` | `user_id` | B-tree | List identities for a user |

### 15.5 `organization.organizations`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_organizations` | `id` | UNIQUE B-tree (PK) | |
| `uq_organizations_slug` | `slug` | UNIQUE B-tree | URL routing; subdomain resolution |
| `idx_organizations_status` | `status` | PARTIAL B-tree | `WHERE status = 'ACTIVE'` — platform admin |
| `idx_organizations_owner` | `owner_user_id` | B-tree | "Organizations I own" query |
| `idx_organizations_country` | `country_code` | B-tree | Platform analytics by country |

### 15.6 `organization.memberships`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_memberships` | `id` | UNIQUE B-tree (PK) | |
| `uq_memberships_active` | `(organization_id, user_id)` | PARTIAL UNIQUE B-tree | `WHERE status = 'ACTIVE'` |
| `idx_memberships_user_active` | `user_id` | PARTIAL B-tree | `WHERE status = 'ACTIVE'` — "my organizations" |
| `idx_memberships_org_role` | `(organization_id, role_id)` | B-tree | "Members with this role" |

**Query supported by `idx_memberships_user_active`:** `SELECT organization_id FROM organization.memberships WHERE user_id = $1 AND status = 'ACTIVE'` — called during JWT validation to build the user's organization list.

### 15.7 `organization.compliance_policies`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_compliance_policies` | `id` | UNIQUE B-tree (PK) | |
| `uq_compliance_policy_active` | `organization_id` | PARTIAL UNIQUE B-tree | `WHERE status = 'ACTIVE'` — one active policy per org |
| `idx_compliance_policies_org` | `(organization_id, status)` | B-tree | Policy history view |

### 15.8 `organization.data_subject_requests`

| Index name | Columns | Type | Notes |
|---|---|---|---|
| `pk_data_subject_requests` | `id` | UNIQUE B-tree (PK) | |
| `idx_dsr_org_status` | `(organization_id, status)` | B-tree | "Pending requests for my org" |
| `idx_dsr_org_requested_at` | `(organization_id, requested_at)` | B-tree | Time-ordered request list |
| `idx_dsr_subject_contact` | `subject_contact_id` | PARTIAL B-tree | `WHERE subject_contact_id IS NOT NULL` |

---

## 16. RLS Architecture

### 16.1 Foundation: Setting Tenant Context

Every database connection used by the application **must** execute before any query:

```sql
SET LOCAL app.tenant_id = '<organization_uuid>';
```

This is done in the SQLAlchemy event listener (`before_cursor_execute`) in `platform/infrastructure/db/tenant_context.py`. The `TenantContext` contextvar (Phase 3A §11) provides the UUID.

For background workers, the tenant context is set from the event envelope's `organization_id` field before processing each message.

### 16.2 Helper Functions

```sql
-- Returns the current tenant UUID, or NULL if not set.
-- NULL causes RLS predicates to match no rows (fail closed).
CREATE OR REPLACE FUNCTION organization.current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::UUID
$$;
```

```sql
-- Returns TRUE if the current session is a platform admin context.
-- Platform admin uses a dedicated connection or SET LOCAL app.is_platform_admin = 'true'.
CREATE OR REPLACE FUNCTION organization.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT current_setting('app.is_platform_admin', true) = 'true'
$$;
```

```sql
-- SECURITY DEFINER: reads memberships without triggering its own RLS.
-- Used ONLY by the memberships RLS policy to avoid circular evaluation.
-- Does NOT expose data — returns only the organization_ids the user is a member of.
CREATE OR REPLACE FUNCTION organization.get_user_organization_ids(p_user_id UUID)
RETURNS TABLE (organization_id UUID)
LANGUAGE sql
STABLE SECURITY DEFINER   -- runs as the function owner, bypasses RLS on memberships
SET search_path = organization, pg_temp
AS $$
  SELECT m.organization_id
  FROM organization.memberships m
  WHERE m.user_id = p_user_id
    AND m.status = 'ACTIVE'
$$;
```

**Security note on `SECURITY DEFINER`:** this function bypasses the RLS of `memberships` intentionally — it is the *bootstrap* lookup that establishes what an authenticated user can see. It is safe because:
1. It only returns `organization_id` values, not member data.
2. It filters by `status = 'ACTIVE'`.
3. `SET search_path = organization, pg_temp` prevents search_path injection.
4. It is called only from within RLS policies, not from application code directly.

### 16.3 `identity` Schema RLS

**`identity.users`:** Platform-owned, no RLS. A user's own record is accessed via the user's session; the application layer enforces user-to-user access control.

**`identity.sessions`:** No RLS (session validation is pre-tenant). The application queries by `refresh_token_hash` — no org context needed.

**`identity.api_keys`:** Tenant-owned — RLS enabled.

```sql
ALTER TABLE identity.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.api_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_api_keys_tenant ON identity.api_keys
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

**`identity.oauth_identities`:** Platform-owned (user-scoped, not org-scoped). No RLS. Application enforces access via user_id from session context.

**`identity.password_reset_tokens`:** No RLS — pre-authentication context. Application verifies by `token_hash`.

### 16.4 `organization` Schema RLS

#### `organizations` — No RLS on the table itself

`organizations` is the **root of the tenant hierarchy** — RLS cannot predicate on `organization_id = current_tenant_id()` because the current tenant IS the organization being queried. Instead:

- **Tenant requests:** the application always queries `organizations` with an explicit `WHERE id = $org_id` — the value comes from the verified JWT/API key.
- **Cross-tenant isolation:** no tenant needs to list other tenants' organizations in normal operation. The application never issues `SELECT * FROM organization.organizations` without a `WHERE id = ?` or `WHERE id = ANY(?)` derived from the session.
- **Platform admin:** uses `app_platform_admin` role for cross-tenant reads; audited.

This is the correct and safe design — the Phase 5A §6.1 note acknowledges that the root object cannot predicate on itself.

#### `memberships`

```sql
ALTER TABLE organization.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.memberships FORCE ROW LEVEL SECURITY;

-- Tenants see memberships in their organization context
CREATE POLICY rls_memberships_tenant ON organization.memberships
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

**Why no SECURITY DEFINER problem here:** the policy predicates on `organization_id = current_tenant_id()` — it reads `memberships.organization_id`, not from `memberships` itself recursively. The circular risk would occur if the policy looked up permissions *through* memberships. We avoid that by setting `app.tenant_id` from the JWT/API-key *before* any RLS policy fires — the context is already established.

The `SECURITY DEFINER` function `get_user_organization_ids()` is used by the **application layer** (not by RLS policies) when listing "organizations this user belongs to" — which is a pre-context operation (e.g., on login, before a specific org is selected).

#### `teams` and `team_memberships`

```sql
ALTER TABLE organization.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.teams FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_teams_tenant ON organization.teams
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

ALTER TABLE organization.team_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.team_memberships FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_team_memberships_tenant ON organization.team_memberships
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

#### `roles` — Mixed-scope policy

```sql
ALTER TABLE organization.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.roles FORCE ROW LEVEL SECURITY;

-- Read: own roles + system roles (organization_id IS NULL)
CREATE POLICY rls_roles_read ON organization.roles
  FOR SELECT
  USING (
    organization_id = organization.current_tenant_id()
    OR organization_id IS NULL
  );

-- Insert: only tenant roles (cannot create system roles)
CREATE POLICY rls_roles_insert ON organization.roles
  FOR INSERT WITH CHECK (
    organization_id = organization.current_tenant_id()
  );

-- Update/Delete: only own tenant roles
CREATE POLICY rls_roles_modify ON organization.roles
  FOR UPDATE USING (organization_id = organization.current_tenant_id());

CREATE POLICY rls_roles_delete ON organization.roles
  FOR DELETE USING (
    organization_id = organization.current_tenant_id()
    AND is_system = FALSE
  );
```

#### `permissions` — Platform-owned, no RLS

```sql
-- No RLS — platform-owned reference data
-- Readable by all application roles
GRANT SELECT ON organization.permissions TO app_api, app_worker, app_readonly;
```

#### `role_permissions` — Mixed-scope policy

```sql
ALTER TABLE organization.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.role_permissions FORCE ROW LEVEL SECURITY;

-- Read: see assignments for own roles AND system roles
CREATE POLICY rls_role_permissions_read ON organization.role_permissions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM organization.roles r
      WHERE r.id = role_id
        AND (r.organization_id = organization.current_tenant_id() OR r.organization_id IS NULL)
    )
  );

-- Modify: only own tenant's custom roles
CREATE POLICY rls_role_permissions_modify ON organization.role_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM organization.roles r
      WHERE r.id = role_id
        AND r.organization_id = organization.current_tenant_id()
        AND r.is_system = FALSE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM organization.roles r
      WHERE r.id = role_id
        AND r.organization_id = organization.current_tenant_id()
        AND r.is_system = FALSE
    )
  );
```

*Note: The `EXISTS` subquery on `roles` within an RLS policy is a secondary lookup, not a circular dependency — `roles` RLS predicates on `organization_id`, not back on `role_permissions`. This is safe.*

#### `compliance_policies`

```sql
ALTER TABLE organization.compliance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.compliance_policies FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_compliance_policies_tenant ON organization.compliance_policies
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

#### `data_subject_requests`

```sql
ALTER TABLE organization.data_subject_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.data_subject_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_data_subject_requests_tenant ON organization.data_subject_requests
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());
```

### 16.5 Bypass Roles

`app_migration` and `app_platform_admin` bypass RLS by being `BYPASSRLS` superusers or having `BYPASSRLS` privilege:

```sql
ALTER ROLE app_migration BYPASSRLS;
ALTER ROLE app_platform_admin BYPASSRLS;
```

`app_platform_admin` bypass is for **read** operations in support/admin tools. All cross-tenant writes by platform admin are audited separately.

---

## 17. RBAC Design

### 17.1 Permission Model

All permissions follow the pattern `{resource}:{action}`:

| Resource | Actions |
|---|---|
| `organization` | `read`, `update`, `suspend`, `delete` |
| `member` | `read`, `invite`, `remove`, `suspend` |
| `role` | `read`, `manage` |
| `agent` | `read`, `write`, `publish`, `delete` |
| `call` | `read`, `initiate`, `transfer`, `record` |
| `contact` | `read`, `write`, `delete`, `merge`, `convert` |
| `deal` | `read`, `write`, `close` |
| `campaign` | `read`, `write`, `start`, `stop` |
| `knowledge` | `read`, `write`, `delete` |
| `workflow` | `read`, `write`, `publish` |
| `prompt` | `read`, `write`, `publish`, `rollback` |
| `billing` | `read`, `manage` |
| `invoice` | `read` |
| `analytics` | `read` |
| `analytics_cost` | `read` |
| `analytics_platform` | `read` |
| `integration` | `read`, `manage` |
| `webhook` | `read`, `manage` |
| `plugin` | `read`, `install`, `manage` |
| `api_key` | `read`, `manage` |
| `audit` | `read` |
| `suppression` | `read`, `manage`, `lift` |
| `consent` | `read`, `manage` |
| `compliance` | `read`, `manage` |
| `data_subject` | `manage` |
| `tax` | `manage` |
| `recording` | `read` (metadata only), `delete`, `access_media` (audio content — added `104_5B3.sql`, see "Controlled Amendment — Phase 6L Freeze-Gate Remediation" below) |
| `transcript` | `read` (metadata only), `access_content` (segment text — added `104_5B3.sql`, see the same amendment) |

### 17.2 Role-Permission Matrix

| Permission | OWNER | ADMIN | MEMBER | BILLING_ADMIN | VIEWER |
|---|---|---|---|---|---|
| `organization:read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `organization:update` | ✅ | ✅ | — | — | — |
| `organization:suspend` | ✅ | — | — | — | — |
| `organization:delete` | ✅ | — | — | — | — |
| `member:read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `member:invite` | ✅ | ✅ | — | — | — |
| `member:remove` | ✅ | ✅ | — | — | — |
| `member:suspend` | ✅ | ✅ | — | — | — |
| `role:read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `role:manage` | ✅ | ✅ | — | — | — |
| `agent:read` | ✅ | ✅ | ✅ | — | ✅ |
| `agent:write` | ✅ | ✅ | ✅ | — | — |
| `agent:publish` | ✅ | ✅ | — | — | — |
| `agent:delete` | ✅ | ✅ | — | — | — |
| `call:read` | ✅ | ✅ | ✅ | — | ✅ |
| `call:initiate` | ✅ | ✅ | ✅ | — | — |
| `call:transfer` | ✅ | ✅ | ✅ | — | — |
| `call:record` | ✅ | ✅ | — | — | — |
| `contact:read` | ✅ | ✅ | ✅ | — | ✅ |
| `contact:write` | ✅ | ✅ | ✅ | — | — |
| `contact:delete` | ✅ | ✅ | — | — | — |
| `contact:merge` | ✅ | ✅ | — | — | — |
| `contact:convert` | ✅ | ✅ | ✅ | — | — |
| `deal:read` | ✅ | ✅ | ✅ | — | ✅ |
| `deal:write` | ✅ | ✅ | ✅ | — | — |
| `deal:close` | ✅ | ✅ | — | — | — |
| `campaign:read` | ✅ | ✅ | ✅ | — | ✅ |
| `campaign:write` | ✅ | ✅ | ✅ | — | — |
| `campaign:start` | ✅ | ✅ | — | — | — |
| `campaign:stop` | ✅ | ✅ | — | — | — |
| `knowledge:read` | ✅ | ✅ | ✅ | — | ✅ |
| `knowledge:write` | ✅ | ✅ | ✅ | — | — |
| `knowledge:delete` | ✅ | ✅ | — | — | — |
| `workflow:read` | ✅ | ✅ | ✅ | — | ✅ |
| `workflow:write` | ✅ | ✅ | ✅ | — | — |
| `workflow:publish` | ✅ | ✅ | — | — | — |
| `prompt:read` | ✅ | ✅ | ✅ | — | ✅ |
| `prompt:write` | ✅ | ✅ | ✅ | — | — |
| `prompt:publish` | ✅ | ✅ | — | — | — |
| `prompt:rollback` | ✅ | ✅ | — | — | — |
| `billing:read` | ✅ | ✅ | — | ✅ | — |
| `billing:manage` | ✅ | — | — | ✅ | — |
| `invoice:read` | ✅ | ✅ | — | ✅ | — |
| `analytics:read` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `analytics_cost:read` | ✅ | ✅ | — | ✅ | — |
| `analytics_platform:read` | — | — | — | — | — (platform admin only) |
| `integration:read` | ✅ | ✅ | ✅ | — | ✅ |
| `integration:manage` | ✅ | ✅ | — | — | — |
| `webhook:read` | ✅ | ✅ | ✅ | — | ✅ |
| `webhook:manage` | ✅ | ✅ | — | — | — |
| `plugin:read` | ✅ | ✅ | ✅ | — | ✅ |
| `plugin:install` | ✅ | ✅ | — | — | — |
| `plugin:manage` | ✅ | ✅ | — | — | — |
| `api_key:read` | ✅ | ✅ | — | — | — |
| `api_key:manage` | ✅ | ✅ | — | — | — |
| `audit:read` | ✅ | ✅ | — | — | — |
| `suppression:read` | ✅ | ✅ | ✅ | — | — |
| `suppression:manage` | ✅ | ✅ | — | — | — |
| `suppression:lift` | ✅ | ✅ | — | — | — |
| `consent:read` | ✅ | ✅ | ✅ | — | — |
| `consent:manage` | ✅ | ✅ | ✅ | — | — |
| `compliance:read` | ✅ | ✅ | — | — | — |
| `compliance:manage` | ✅ | ✅ | — | — | — |
| `data_subject:manage` | ✅ | ✅ | — | — | — |
| `tax:manage` | ✅ | — | — | ✅ | — |
| `recording:read` (metadata only — never audio) | ✅ | ✅ | ✅ | — | ✅ |
| `recording:delete` | ✅ | ✅ | — | — | — |
| `recording:access_media` (audio content — added `104_5B3.sql`) | ✅ | ✅ | — (custom role only) | — | — |
| `transcript:read` (metadata only — never segment text) | ✅ | ✅ | ✅ | — | ✅ |
| `transcript:access_content` (segment text — added `104_5B3.sql`) | ✅ | ✅ | — (custom role only) | — | — |

---

## 18. API Key Design

### 18.1 Authentication Flow

```
Request arrives with header: Authorization: Bearer {raw_api_key}
    ↓
Application computes: key_hash = SHA-256(raw_api_key)
    ↓
SELECT id, organization_id, scopes, status, expires_at
  FROM identity.api_keys
  WHERE key_hash = $key_hash
    AND status = 'ACTIVE'
    AND (expires_at IS NULL OR expires_at > NOW())
    ↓
IF found: SET LOCAL app.tenant_id = organization_id
          Continue with scopes as permission set
IF not found: 401 Unauthorized
```

### 18.2 Key Generation

The application generates: `raw_key = f"vxa_{secrets.token_urlsafe(32)}"` — prefixed with `vxa_` to indicate the platform (Voxa platform). The raw key is shown once on creation. The API key record stores:
- `key_prefix = raw_key[:8]` — first 8 chars for UI identification
- `key_hash = hashlib.sha256(raw_key.encode()).hexdigest()` — lookup key

### 18.3 Scope Enforcement

`scopes TEXT[]` carries the list of permissions this key is limited to. An API key with `scopes = '{contact:read, campaign:read}'` cannot write contacts even if the creating user has `contact:write`. The application intersects the key's scopes with the user's role permissions. An empty scopes array (`'{}'`) means no permissions — not "all permissions."

---

## 19. OAuth Design

### 19.1 Login Flow

```
User clicks "Sign in with Google"
    ↓
Application redirects to provider OAuth endpoint with state (CSRF token)
    ↓
Provider redirects back with code + state
    ↓
Application verifies state; exchanges code for tokens
    ↓
Application calls provider's userinfo endpoint → {provider_subject, email, name}
    ↓
SELECT user_id FROM identity.oauth_identities
  WHERE provider = $provider AND provider_subject = $subject AND status = 'ACTIVE'
    ↓
IF found: log in as that user, update last_login_at
IF not found:
  - Check if email matches an existing user (by email_normalized)
  - IF match: link to existing user, INSERT into oauth_identities
  - IF no match: CREATE user, INSERT into oauth_identities
    ↓
CREATE session (refresh token issued, stored as hash)
Return access JWT + refresh token
```

### 19.2 Token Storage

OAuth provider access/refresh tokens are stored in the secret manager (referenced by `credential_ref`) **only for integrations that need offline access** (e.g., Google Calendar sync). For identity-only OAuth (login), no token is stored after the user is authenticated — the platform's own session tokens are issued.

---

## 20. Session Design

### 20.1 Session Lifecycle

| Event | Action |
|---|---|
| Login | Create session row; return refresh token (raw, once only); store hash |
| Access token refresh | Read session by `refresh_token_hash`; verify not expired/revoked; issue new JWT; update `last_seen_at` |
| Logout (single session) | `UPDATE sessions SET status = 'REVOKED', revoked_at = NOW()` |
| Logout (all sessions) | `UPDATE sessions SET status = 'REVOKED', revoked_at = NOW() WHERE user_id = $uid` |
| Token expiry check | `WHERE expires_at > NOW()` — database enforces |
| Cleanup | Background job: hard-delete sessions where `expires_at < NOW() - INTERVAL '7 days'` |

### 20.2 Stateless Access Tokens (JWTs)

Access tokens are JWTs (15-minute expiry) not backed by a database row. JWT validation is stateless — the signature and `exp` claim are verified. The `access_token_jti` column on `sessions` allows **emergency revocation** of a specific access token before its natural expiry (e.g., after a security incident). Application checks `SELECT 1 FROM identity.sessions WHERE access_token_jti = $jti AND status = 'REVOKED'` — only on the high-security revocation path, not every request.

---

## 21. Password Security Design

### 21.1 Hashing Algorithm

The application uses **Argon2id** (via the Python `argon2-cffi` library) for password hashing. The hash string stored in `password_hash` is a self-contained Argon2id encoded string including the salt, parameters, and hash — e.g., `$argon2id$v=19$m=65536,t=3,p=4$...`. The database never parses this string.

**Why Argon2id over bcrypt:**
- Memory-hard — resistant to GPU/ASIC attacks
- Modern OWASP recommendation
- Argon2id is the Argon2 variant recommended for password hashing (hybrid of Argon2i and Argon2d)

### 21.2 Password Reset Flow

```
User requests reset (submits email)
    ↓
Application: raw_token = secrets.token_urlsafe(32)
             token_hash = SHA-256(raw_token)
             INSERT INTO identity.password_reset_tokens (user_id, token_hash, expires_at)
    ↓
Email sent with link containing raw_token (in URL)
    ↓
User clicks link → Application extracts raw_token from URL
Application computes: token_hash = SHA-256(raw_token)
    ↓
SELECT * FROM identity.password_reset_tokens
  WHERE token_hash = $hash AND used_at IS NULL AND expires_at > NOW()
    ↓
IF found AND purpose = 'PASSWORD_RESET':
  Hash new password
  UPDATE identity.users SET password_hash = $new_hash, password_changed_at = NOW()
  UPDATE identity.password_reset_tokens SET used_at = NOW()
  Invalidate all existing sessions for user
ELSE: reject (expired or already used)
```

---

## 22. Organization Membership Design

### 22.1 One-to-Many Organizations per User

A user accesses multiple organizations by having multiple active `membership` rows. The JWT includes the `organization_id` of the currently selected organization. Switching organizations issues a new JWT (or the JWT includes a `switch_token` that the user exchanges).

The application pattern:
```python
# On login, list user's organizations:
orgs = db.execute(
    "SELECT organization_id FROM organization.memberships "
    "WHERE user_id = $1 AND status = 'ACTIVE'",
    user_id
)
# User selects one → issue JWT with organization_id claim
# Every subsequent request: SET LOCAL app.tenant_id = jwt.organization_id
```

### 22.2 Owner Constraint

Every organization must have exactly one `OWNER`. The constraint is enforced at the application layer:
- Removing the last OWNER membership raises `LastOwnerError`.
- `TransferOwnership` atomically changes one OWNER to ADMIN and one ADMIN to OWNER within a single transaction.

The database enforces: `UNIQUE (organization_id, user_id) WHERE status = 'ACTIVE'` — one active membership per user per org. Role uniqueness (only one owner) is an application-layer invariant — the DB ensures only one active membership per user, not one per role.

---

## 23. Localization Design

### 23.1 All Localization on `organizations` Directly

Phase 4I ADR-INDIA-020 decided: `LocalizationProfile` is a value object on `Organization`, not a separate aggregate. Therefore, all localization fields are typed columns on `organization.organizations` (see §9.6).

**No separate `localization_profiles` table.** Rationale:
- Every field is read and written together with the organization.
- No independent lifecycle.
- A separate table would add a join to every API request that reads org configuration.
- The fields are small (TEXT, CHAR(3), TEXT[], INTEGER) — no bloat on the `organizations` row.

### 23.2 Field Validation

All localization field validation is application-layer:

| Field | Validation |
|---|---|
| `timezone` | `zoneinfo.ZoneInfo(timezone)` — raises `ZoneInfoNotFoundError` if invalid |
| `locale` | BCP 47 pattern `[a-z]{2}(-[A-Z]{2})?` — validated by `babel.Locale.parse()` |
| `currency` | `CHECK (currency ~ '^[A-Z]{3}$')` in database + ISO 4217 whitelist in app |
| `country_code` | `CHECK (length(country_code) = 2)` in database + ISO 3166 whitelist in app |
| `primary_language` | BCP 47; must appear in `supported_languages` array |
| `supported_languages` | Each element is a valid BCP 47 tag |

---

## 24. India-First Defaults

All India defaults are applied in `CreateOrganizationUseCase`. They are *not* column `DEFAULT` values (except `timezone`, which has a safe column default):

```python
# In CreateOrganizationUseCase (pseudocode):
def create_organization(cmd: CreateOrganizationCommand) -> Organization:
    return Organization(
        country_code      = cmd.country_code or 'IN',     # India default
        currency          = cmd.currency or 'INR',        # India default — write-once
        timezone          = cmd.timezone or 'Asia/Kolkata',
        locale            = cmd.locale or 'en-IN',
        phone_country     = cmd.phone_country or 'IN',
        primary_language  = cmd.primary_language or 'en-IN',
        supported_languages = cmd.supported_languages or ['en-IN', 'ta-IN'],
        fiscal_year_start_month = cmd.fiscal_year_start_month or 4,  # April
        ...
    )
```

**Why `currency` and `country_code` have no column `DEFAULT`:**
A column `DEFAULT 'INR'` would silently assign INR to a future US tenant whose signup form failed to pass `currency`. The application must set it explicitly — a missing value is a logic error, not a fallback situation.

The `fiscal_year_start_month` column has `DEFAULT 4` (April) because an incorrect month is recoverable; an incorrect currency creates financial data integrity issues.

---

## 25. Compliance Policy Design

Covered in §9.13. Key additions:

### 25.1 India-Specific Defaults

When `CreateOrganizationUseCase` seeds the first compliance policy for an Indian organization:

```python
CompliancePolicy(
    require_consent_for_outbound = True,         # India conservative default
    required_consent_purposes    = ['OUTBOUND_CALL'],
    recording_policy             = 'REQUIRES_DISCLOSURE',  # Indian call recording norms
    calling_windows              = [
        {'days': ['MON','TUE','WED','THU','FRI'], 'start_time': '09:00', 'end_time': '21:00'},
        {'days': ['SAT'], 'start_time': '09:00', 'end_time': '18:00'},
    ],
    holiday_calendar_ref         = 'IN-national',
    block_on_policy_failure      = True,
    retention_profile            = {
        'recording_days': 90,
        'transcript_days': 365,
        'activity_days': 1825,
    }
)
```

These are defaults — organizations configure their own policies through the UI/API. No values are hard-coded as database constraints.

---

## 26. Data Residency Design

Covered in §9.6 (`organizations.region_ref` and `organizations.data_residency_profile`). The columns store abstract identifiers resolved by infrastructure:

| `data_residency_profile` | `region_ref` | Meaning |
|---|---|---|
| `STANDARD` | `standard` | Platform-managed; no specific residency |
| `INDIA_ENTERPRISE` | `in-primary` | Data in India region per contract |
| `REGIONAL` | `{custom}` | Future; per contract |

No cloud region name appears in the database schema. The infrastructure layer maps `in-primary` to the actual provider region.

---

## 27. Data Subject Request Design

Covered in §9.14. The workflow tracks the request state; the actual data operations occur in each owning schema.

**Workflow states:**
```
RECEIVED → VERIFYING → IN_PROGRESS → COMPLETED
                    ↘ REJECTED
              ↓
           ON_HOLD (legal hold; manual review required)
```

**What gets stored in this table:** request type, subject identification (contact_id OR contact details), workflow status, timestamps, completion notes, and export S3 reference. **Not stored:** copies of personal data, raw API responses from other systems.

---

## 28. PII Classification

| Schema.Table | Column | PII Category | Handling |
|---|---|---|---|
| `identity.users` | `email` | `pii:email` | Masked in logs; cleared on GDPR erasure |
| `identity.users` | `email_normalized` | `pii:email` | Replaced with opaque value on erasure |
| `identity.users` | `display_name` | `pii:name` | Replaced with `[ERASED]` on erasure |
| `identity.users` | `phone_e164` | `pii:phone` | Set to NULL on erasure |
| `identity.users` | `password_hash` | Internal secret | Set to NULL on erasure; never logged |
| `identity.sessions` | `ip_address` | `pii:network` | Masked in logs; retained 90 days |
| `identity.oauth_identities` | `email_at_provider` | `pii:email` | Not erased (informational); provider-side erasure is user's responsibility |
| `identity.oauth_identities` | `display_name_at_provider` | `pii:name` | Same as above |
| `organization.data_subject_requests` | `subject_email` | `pii:email` | Needed for request processing |
| `organization.data_subject_requests` | `subject_phone_e164` | `pii:phone` | Needed for request processing |

**GDPR Erasure sequence for a user:**
1. `UPDATE identity.users SET email = '[ERASED@erased.invalid]', email_normalized = CONCAT('[erased-', id, ']'), display_name = '[ERASED]', phone_e164 = NULL, password_hash = NULL, deleted_at = NOW(), mfa_secret_ref = NULL`
2. `UPDATE identity.sessions SET status = 'REVOKED', revoked_at = NOW() WHERE user_id = $uid`
3. CRM contacts owned by this user remain (they belong to the organization, not the user personally) — handled by Phase 5D's erasure workflow.

---

## 29. Retention Strategy

| Table | Retention | Strategy |
|---|---|---|
| `identity.users` | Indefinite (PII cleared on erasure) | Soft delete; PII cleared per GDPR |
| `identity.sessions` | 7 days post-expiry | Background hard-delete job |
| `identity.password_reset_tokens` | 7 days post-expiry or post-use | Background hard-delete job |
| `identity.oauth_identities` | Indefinite while linked; 90 days after unlink | Status = 'UNLINKED'; delete after 90d |
| `identity.api_keys` | Indefinite while active; 1 year after revocation | Status-based; no hard delete (audit) |
| `organization.organizations` | Indefinite | Soft delete on cancellation |
| `organization.memberships` | Indefinite (history preserved) | Status-based; removed rows retained |
| `organization.compliance_policies` | Per `retention_profile` in active policy | Archived policies kept for evidence |
| `organization.data_subject_requests` | 7 years (regulatory evidence) | Status-based; no hard delete |

---

## 30. Audit Event Handoff

The following operations in Phase 5B schemas **must** emit `audit.audit_events` records (designed in Phase 5I). The calling code in each use case is responsible for this emission.

| Operation | `action_kind` | `resource_type` | PII in payload? |
|---|---|---|---|
| User registered | `USER_REGISTERED` | `user` | No (user_id only) |
| User verified email | `USER_EMAIL_VERIFIED` | `user` | No |
| User logged in | `USER_LOGIN` | `user` | IP only |
| User login failed | `USER_LOGIN_FAILED` | `user` | No |
| User password changed | `USER_PASSWORD_CHANGED` | `user` | No |
| User MFA enabled | `USER_MFA_ENABLED` | `user` | No |
| User deleted (erasure) | `USER_ERASED` | `user` | No |
| OAuth identity linked | `OAUTH_LINKED` | `oauth_identity` | provider name only |
| OAuth identity unlinked | `OAUTH_UNLINKED` | `oauth_identity` | provider name only |
| API key created | `API_KEY_CREATED` | `api_key` | key_prefix only |
| API key revoked | `API_KEY_REVOKED` | `api_key` | key_prefix only |
| Organization created | `ORGANIZATION_CREATED` | `organization` | No |
| Organization settings changed | `ORGANIZATION_UPDATED` | `organization` | changed_fields list |
| Organization suspended | `ORGANIZATION_SUSPENDED` | `organization` | No |
| Member invited | `MEMBER_INVITED` | `membership` | No (user_id + org_id) |
| Member invitation accepted | `MEMBER_JOINED` | `membership` | No |
| Member removed | `MEMBER_REMOVED` | `membership` | No |
| Member suspended | `MEMBER_SUSPENDED` | `membership` | No |
| Member role changed | `MEMBER_ROLE_CHANGED` | `membership` | old_role, new_role |
| Compliance policy activated | `COMPLIANCE_POLICY_UPDATED` | `compliance_policy` | policy_version |
| Data residency changed | `DATA_RESIDENCY_CHANGED` | `organization` | new_profile |
| Data subject request created | `DATA_SUBJECT_REQUEST_RECEIVED` | `data_subject_request` | request_type |
| Data subject request completed | `DATA_SUBJECT_REQUEST_COMPLETED` | `data_subject_request` | request_type |
| Data subject request rejected | `DATA_SUBJECT_REQUEST_REJECTED` | `data_subject_request` | rejection_reason |

---

## 31. Redis Cache Boundaries

Phase 5A §18 defines the full Redis catalogue. For the `identity` and `organization` schemas:

| Redis key | Source of truth | TTL | Invalidated by |
|---|---|---|---|
| `rbac:permissions:{org_id}:{user_id}` | `organization.role_permissions` via membership | 5 min | `membership.role_changed` event → clear key |
| `apikey:{key_hash}` | `identity.api_keys` | 5 min | `api_key.revoked` event → clear key immediately |
| `localization:{org_id}` | `organization.organizations` | 15 min | `organization.updated` event → clear key |
| `compliance_policy:{org_id}` | `organization.compliance_policies` | 15 min | `compliance.policy_updated` event → clear key |

**`apikey:{key_hash}` critical note:** API key revocation must clear this cache key **immediately** via an explicit Redis `DEL` command after the database update — not waiting for TTL expiry. A revoked API key usable for up to 5 minutes is a security vulnerability. The `REVOKE API KEY` use case: (1) `UPDATE identity.api_keys SET status = 'REVOKED'`, (2) `redis.delete(f'apikey:{key_hash}')`, (3) publish `api_key.revoked` event.

---

## 32. Seed Data

### 32.1 System Roles

```sql
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING
INSERT INTO organization.roles (id, organization_id, name, display_name, description, is_system, is_active)
VALUES
  (gen_uuid_v7(), NULL, 'OWNER',         'Owner',         'Full organization control',              TRUE, TRUE),
  (gen_uuid_v7(), NULL, 'ADMIN',          'Admin',         'Administrative access',                  TRUE, TRUE),
  (gen_uuid_v7(), NULL, 'MEMBER',         'Member',        'Standard member access',                 TRUE, TRUE),
  (gen_uuid_v7(), NULL, 'BILLING_ADMIN',  'Billing Admin', 'Billing and financial operations',       TRUE, TRUE),
  (gen_uuid_v7(), NULL, 'VIEWER',         'Viewer',        'Read-only access to approved resources', TRUE, TRUE)
ON CONFLICT (name) WHERE organization_id IS NULL DO NOTHING;
```

### 32.2 System Permissions (Representative subset — full list in migration file)

```sql
-- All permission inserts are ON CONFLICT (name) DO NOTHING
INSERT INTO organization.permissions (id, name, display_name, resource, action) VALUES
  (gen_uuid_v7(), 'organization:read',      'View Organization',    'organization', 'read'),
  (gen_uuid_v7(), 'organization:update',    'Edit Organization',    'organization', 'update'),
  (gen_uuid_v7(), 'member:read',            'View Members',         'member',       'read'),
  (gen_uuid_v7(), 'member:invite',          'Invite Members',       'member',       'invite'),
  (gen_uuid_v7(), 'agent:read',             'View Agents',          'agent',        'read'),
  (gen_uuid_v7(), 'agent:write',            'Edit Agents',          'agent',        'write'),
  (gen_uuid_v7(), 'agent:publish',          'Publish Agents',       'agent',        'publish'),
  (gen_uuid_v7(), 'call:read',              'View Calls',           'call',         'read'),
  (gen_uuid_v7(), 'contact:read',           'View Contacts',        'contact',      'read'),
  (gen_uuid_v7(), 'contact:write',          'Edit Contacts',        'contact',      'write'),
  (gen_uuid_v7(), 'campaign:read',          'View Campaigns',       'campaign',     'read'),
  (gen_uuid_v7(), 'campaign:start',         'Start Campaigns',      'campaign',     'start'),
  (gen_uuid_v7(), 'billing:read',           'View Billing',         'billing',      'read'),
  (gen_uuid_v7(), 'billing:manage',         'Manage Billing',       'billing',      'manage'),
  (gen_uuid_v7(), 'analytics:read',         'View Analytics',       'analytics',    'read'),
  (gen_uuid_v7(), 'analytics_cost:read',    'View Cost Analytics',  'analytics_cost', 'read'),
  (gen_uuid_v7(), 'audit:read',             'View Audit Log',       'audit',        'read'),
  (gen_uuid_v7(), 'suppression:read',       'View Suppressions',    'suppression',  'read'),
  (gen_uuid_v7(), 'suppression:manage',     'Manage Suppressions',  'suppression',  'manage'),
  (gen_uuid_v7(), 'consent:manage',         'Manage Consent',       'consent',      'manage'),
  (gen_uuid_v7(), 'compliance:manage',      'Manage Compliance',    'compliance',   'manage'),
  (gen_uuid_v7(), 'data_subject:manage',    'Handle DSARs',         'data_subject', 'manage'),
  (gen_uuid_v7(), 'tax:manage',             'Manage Tax Profile',   'tax',          'manage')
  -- ... (full list of ~40 permissions in migration file)
ON CONFLICT (name) DO NOTHING;
```

### 32.3 Role-Permission Assignments

```sql
-- Seed role-permission mappings.
-- Uses CTEs to look up role and permission IDs by name (avoids hardcoding UUIDs).
WITH
  roles AS (SELECT id, name FROM organization.roles WHERE organization_id IS NULL),
  perms AS (SELECT id, name FROM organization.permissions)
INSERT INTO organization.role_permissions (id, role_id, permission_id)
SELECT gen_uuid_v7(), r.id, p.id
FROM (VALUES
  -- OWNER gets all permissions
  ('OWNER', 'organization:read'), ('OWNER', 'organization:update'), ('OWNER', 'organization:suspend'),
  ('OWNER', 'member:read'), ('OWNER', 'member:invite'), ('OWNER', 'member:remove'),
  ('OWNER', 'agent:read'), ('OWNER', 'agent:write'), ('OWNER', 'agent:publish'), ('OWNER', 'agent:delete'),
  ('OWNER', 'call:read'), ('OWNER', 'call:initiate'), ('OWNER', 'call:record'),
  ('OWNER', 'contact:read'), ('OWNER', 'contact:write'), ('OWNER', 'contact:delete'),
  ('OWNER', 'campaign:read'), ('OWNER', 'campaign:write'), ('OWNER', 'campaign:start'), ('OWNER', 'campaign:stop'),
  ('OWNER', 'billing:read'), ('OWNER', 'billing:manage'),
  ('OWNER', 'analytics:read'), ('OWNER', 'analytics_cost:read'),
  ('OWNER', 'audit:read'), ('OWNER', 'suppression:manage'), ('OWNER', 'consent:manage'),
  ('OWNER', 'compliance:manage'), ('OWNER', 'data_subject:manage'), ('OWNER', 'tax:manage'),
  -- ADMIN gets most permissions (subset of OWNER)
  ('ADMIN', 'organization:read'), ('ADMIN', 'organization:update'),
  ('ADMIN', 'member:read'), ('ADMIN', 'member:invite'), ('ADMIN', 'member:remove'),
  ('ADMIN', 'agent:read'), ('ADMIN', 'agent:write'), ('ADMIN', 'agent:publish'),
  ('ADMIN', 'call:read'), ('ADMIN', 'call:initiate'), ('ADMIN', 'call:record'),
  ('ADMIN', 'contact:read'), ('ADMIN', 'contact:write'),
  ('ADMIN', 'campaign:read'), ('ADMIN', 'campaign:write'), ('ADMIN', 'campaign:start'),
  ('ADMIN', 'billing:read'), ('ADMIN', 'analytics:read'), ('ADMIN', 'analytics_cost:read'),
  ('ADMIN', 'audit:read'), ('ADMIN', 'suppression:manage'), ('ADMIN', 'compliance:manage'),
  -- MEMBER gets operational read + write
  ('MEMBER', 'organization:read'), ('MEMBER', 'member:read'),
  ('MEMBER', 'agent:read'), ('MEMBER', 'agent:write'),
  ('MEMBER', 'call:read'), ('MEMBER', 'call:initiate'),
  ('MEMBER', 'contact:read'), ('MEMBER', 'contact:write'),
  ('MEMBER', 'campaign:read'), ('MEMBER', 'campaign:write'),
  ('MEMBER', 'analytics:read'), ('MEMBER', 'suppression:read'), ('MEMBER', 'consent:manage'),
  -- BILLING_ADMIN gets billing + analytics_cost
  ('BILLING_ADMIN', 'organization:read'), ('BILLING_ADMIN', 'billing:read'), ('BILLING_ADMIN', 'billing:manage'),
  ('BILLING_ADMIN', 'analytics:read'), ('BILLING_ADMIN', 'analytics_cost:read'), ('BILLING_ADMIN', 'tax:manage'),
  -- VIEWER gets read-only
  ('VIEWER', 'organization:read'), ('VIEWER', 'member:read'),
  ('VIEWER', 'agent:read'), ('VIEWER', 'call:read'), ('VIEWER', 'contact:read'),
  ('VIEWER', 'campaign:read'), ('VIEWER', 'analytics:read')
) AS mapping(role_name, perm_name)
JOIN roles r ON r.name = mapping.role_name
JOIN perms p ON p.name = mapping.perm_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
```

---

## 33. Complete PostgreSQL DDL

### 33.1 Extensions and Schemas

```sql
-- ==============================================================
-- Migration 001: Extensions, schemas, helper function
-- ==============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- gen_random_bytes, gen_random_uuid
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";  -- query monitoring

-- Create all 13 schemas in migration order
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS organization;
CREATE SCHEMA IF NOT EXISTS voice;
CREATE SCHEMA IF NOT EXISTS crm;
CREATE SCHEMA IF NOT EXISTS campaign;
CREATE SCHEMA IF NOT EXISTS knowledge;
CREATE SCHEMA IF NOT EXISTS workflow;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS integrations;
CREATE SCHEMA IF NOT EXISTS webhooks;
CREATE SCHEMA IF NOT EXISTS plugins;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

-- Application roles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_api') THEN
    CREATE ROLE app_api LOGIN PASSWORD 'CHANGE_IN_PRODUCTION';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_worker') THEN
    CREATE ROLE app_worker LOGIN PASSWORD 'CHANGE_IN_PRODUCTION';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_readonly') THEN
    CREATE ROLE app_readonly LOGIN PASSWORD 'CHANGE_IN_PRODUCTION';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_migration') THEN
    CREATE ROLE app_migration LOGIN PASSWORD 'CHANGE_IN_PRODUCTION' BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_platform_admin') THEN
    CREATE ROLE app_platform_admin LOGIN PASSWORD 'CHANGE_IN_PRODUCTION' BYPASSRLS;
  END IF;
END
$$;

-- Schema grants
GRANT USAGE ON SCHEMA identity     TO app_api, app_worker, app_platform_admin;
GRANT USAGE ON SCHEMA organization TO app_api, app_worker, app_readonly, app_platform_admin;

-- UUIDv7 generation function
-- Note: Application generates UUIDv7 before insert; this is a DB-side fallback.
-- Production deployments should use pg_uuidv7 extension or application-generated IDs.
CREATE OR REPLACE FUNCTION gen_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_millis   BIGINT := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
  v_rand     BYTEA  := gen_random_bytes(10);
  v_bytes    BYTEA;
BEGIN
  -- 48-bit ms timestamp | version 7 | 12-bit seq | variant | 62-bit random
  v_bytes :=
    set_byte('\x00000000000000000000000000000000'::BYTEA, 0, ((v_millis >> 40) & 255)::INT) ||
    '';
  -- Simplified: delegate to application layer for correctness
  -- Return a time-ordered UUID approximation
  RETURN (
    lpad(to_hex(v_millis), 12, '0') ||
    '7' ||
    lpad(to_hex(get_byte(v_rand,0) * 256 + get_byte(v_rand,1)), 3, '0') ||
    '-' ||
    lpad(to_hex((get_byte(v_rand,2) & 63) | 128), 2, '0') ||
    lpad(to_hex(get_byte(v_rand,3)), 2, '0') ||
    '-' ||
    encode(substring(v_rand FROM 4 FOR 6), 'hex')
  )::UUID;
END;
$$;

-- Trigger function: auto-update updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- RLS helper functions
CREATE OR REPLACE FUNCTION organization.current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::UUID
$$;

CREATE OR REPLACE FUNCTION organization.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY INVOKER
AS $$
  SELECT current_setting('app.is_platform_admin', true) = 'true'
$$;

-- SECURITY DEFINER: resolves user's org memberships without RLS interference.
-- Used in application layer for "list my organizations" (pre-context operation).
-- NOT used inside RLS policies directly.
CREATE OR REPLACE FUNCTION organization.get_user_organization_ids(p_user_id UUID)
RETURNS TABLE (organization_id UUID)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = organization, pg_temp
AS $$
  SELECT m.organization_id
  FROM organization.memberships m
  WHERE m.user_id = p_user_id
    AND m.status = 'ACTIVE'
$$;
```

### 33.2 Identity Schema Tables

```sql
-- ==============================================================
-- Migration 002: identity schema tables
-- ==============================================================

-- identity.users
CREATE TABLE identity.users (
  id                     UUID         NOT NULL DEFAULT gen_uuid_v7(),
  email                  TEXT         NOT NULL,
  email_normalized       TEXT         NOT NULL,
  display_name           TEXT         NOT NULL,
  phone_e164             TEXT         NULL,
  phone_verified_at      TIMESTAMPTZ  NULL,
  email_verified_at      TIMESTAMPTZ  NULL,
  password_hash          TEXT         NULL,          -- pii: internal secret; argon2id
  password_changed_at    TIMESTAMPTZ  NULL,
  status                 TEXT         NOT NULL DEFAULT 'PENDING_VERIFICATION',
  last_login_at          TIMESTAMPTZ  NULL,
  failed_login_count     INTEGER      NOT NULL DEFAULT 0,
  last_failed_login_at   TIMESTAMPTZ  NULL,
  mfa_enabled            BOOLEAN      NOT NULL DEFAULT FALSE,
  mfa_secret_ref         TEXT         NULL,          -- secret_manager:// reference
  deleted_at             TIMESTAMPTZ  NULL,
  created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_users                PRIMARY KEY (id),
  CONSTRAINT chk_users_status        CHECK (status IN ('PENDING_VERIFICATION','ACTIVE','SUSPENDED','DELETED')),
  CONSTRAINT chk_users_email_format  CHECK (email_normalized ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  CONSTRAINT chk_users_mfa_ref       CHECK (mfa_secret_ref IS NULL OR mfa_secret_ref LIKE 'secret_manager://%')
);

CREATE UNIQUE INDEX uq_users_email_normalized ON identity.users (email_normalized);
CREATE INDEX idx_users_status_active  ON identity.users (status) WHERE status = 'ACTIVE';
CREATE INDEX idx_users_created_at     ON identity.users (created_at);

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON identity.users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Currency immutability trigger (for organizations.currency — placed here as the function is shared)
CREATE OR REPLACE FUNCTION prevent_currency_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.currency IS DISTINCT FROM OLD.currency THEN
    RAISE EXCEPTION 'organizations.currency is immutable after creation. '
      'Current: %, Attempted: %', OLD.currency, NEW.currency;
  END IF;
  RETURN NEW;
END;
$$;

-- GRANTS on identity.users
GRANT SELECT, INSERT, UPDATE ON identity.users TO app_api, app_worker;
GRANT SELECT ON identity.users TO app_platform_admin;


-- identity.sessions
CREATE TABLE identity.sessions (
  id                   UUID         NOT NULL DEFAULT gen_uuid_v7(),
  user_id              UUID         NOT NULL,          -- logical ref: identity.users.id
  refresh_token_hash   TEXT         NOT NULL,
  access_token_jti     TEXT         NULL,
  status               TEXT         NOT NULL DEFAULT 'ACTIVE',
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  expires_at           TIMESTAMPTZ  NOT NULL,
  revoked_at           TIMESTAMPTZ  NULL,
  last_seen_at         TIMESTAMPTZ  NULL,
  device_label         TEXT         NULL,
  ip_address           INET         NULL,              -- pii:network
  user_agent_hash      TEXT         NULL,

  CONSTRAINT pk_sessions        PRIMARY KEY (id),
  CONSTRAINT chk_sessions_status CHECK (status IN ('ACTIVE','REVOKED','EXPIRED'))
);

CREATE UNIQUE INDEX uq_sessions_token_hash ON identity.sessions (refresh_token_hash);
CREATE INDEX idx_sessions_user_active
  ON identity.sessions (user_id, status)
  WHERE status = 'ACTIVE';
CREATE INDEX idx_sessions_expires_at ON identity.sessions (expires_at);

GRANT SELECT, INSERT, UPDATE ON identity.sessions TO app_api, app_worker;


-- identity.password_reset_tokens
CREATE TABLE identity.password_reset_tokens (
  id          UUID         NOT NULL DEFAULT gen_uuid_v7(),
  user_id     UUID         NOT NULL,         -- logical ref: identity.users.id
  token_hash  TEXT         NOT NULL,         -- SHA-256 hex of raw token
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ  NOT NULL,
  used_at     TIMESTAMPTZ  NULL,
  purpose     TEXT         NOT NULL DEFAULT 'PASSWORD_RESET',

  CONSTRAINT pk_password_reset_tokens PRIMARY KEY (id),
  CONSTRAINT chk_prt_purpose CHECK (purpose IN ('PASSWORD_RESET','EMAIL_VERIFICATION','INVITATION'))
);

CREATE UNIQUE INDEX uq_prt_token_hash ON identity.password_reset_tokens (token_hash);
CREATE INDEX idx_prt_user_id ON identity.password_reset_tokens (user_id);
CREATE INDEX idx_prt_expires_at ON identity.password_reset_tokens (expires_at);

GRANT SELECT, INSERT, UPDATE ON identity.password_reset_tokens TO app_api, app_worker;


-- identity.oauth_identities
CREATE TABLE identity.oauth_identities (
  id                       UUID         NOT NULL DEFAULT gen_uuid_v7(),
  user_id                  UUID         NOT NULL,     -- logical ref: identity.users.id
  provider                 TEXT         NOT NULL,
  provider_subject         TEXT         NOT NULL,
  email_at_provider        TEXT         NULL,         -- pii:email
  display_name_at_provider TEXT         NULL,         -- pii:name
  status                   TEXT         NOT NULL DEFAULT 'ACTIVE',
  credential_ref           TEXT         NULL,         -- secret_manager:// reference or NULL
  linked_at                TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  last_login_at            TIMESTAMPTZ  NULL,
  unlinked_at              TIMESTAMPTZ  NULL,

  CONSTRAINT pk_oauth_identities   PRIMARY KEY (id),
  CONSTRAINT chk_oauth_status      CHECK (status IN ('ACTIVE','UNLINKED')),
  CONSTRAINT chk_oauth_cred_ref    CHECK (credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%')
);

CREATE UNIQUE INDEX uq_oauth_provider_subject ON identity.oauth_identities (provider, provider_subject);
CREATE INDEX idx_oauth_user_id ON identity.oauth_identities (user_id);

GRANT SELECT, INSERT, UPDATE ON identity.oauth_identities TO app_api, app_worker;


-- identity.api_keys
CREATE TABLE identity.api_keys (
  id               UUID         NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID         NOT NULL,     -- logical ref: organization.organizations.id
  created_by       UUID         NOT NULL,     -- logical ref: identity.users.id
  name             TEXT         NOT NULL,
  key_prefix       TEXT         NOT NULL,
  key_hash         TEXT         NOT NULL,
  scopes           TEXT[]       NOT NULL DEFAULT '{}',
  status           TEXT         NOT NULL DEFAULT 'ACTIVE',
  expires_at       TIMESTAMPTZ  NULL,
  last_used_at     TIMESTAMPTZ  NULL,
  last_used_ip     INET         NULL,
  revoked_at       TIMESTAMPTZ  NULL,
  revoked_by       UUID         NULL,         -- logical ref: identity.users.id
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_api_keys          PRIMARY KEY (id),
  CONSTRAINT chk_api_keys_status  CHECK (status IN ('ACTIVE','REVOKED','EXPIRED')),
  CONSTRAINT chk_api_keys_prefix  CHECK (length(key_prefix) = 8)
);

CREATE UNIQUE INDEX uq_api_keys_key_hash ON identity.api_keys (key_hash);
CREATE INDEX idx_api_keys_org_status
  ON identity.api_keys (organization_id, status);

CREATE TRIGGER trg_api_keys_updated_at
  BEFORE UPDATE ON identity.api_keys
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE identity.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.api_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_api_keys_tenant ON identity.api_keys
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON identity.api_keys TO app_api, app_worker;
```

### 33.3 Organization Schema Tables

```sql
-- ==============================================================
-- Migration 003: organization schema tables
-- ==============================================================

-- organization.organizations
CREATE TABLE organization.organizations (
  id                        UUID         NOT NULL DEFAULT gen_uuid_v7(),
  name                      TEXT         NOT NULL,
  slug                      TEXT         NOT NULL,
  legal_name                TEXT         NULL,
  status                    TEXT         NOT NULL DEFAULT 'ACTIVE',
  owner_user_id             UUID         NOT NULL,     -- logical ref: identity.users.id
  -- Localization (Phase 4I ADR-INDIA-020: typed columns, not separate table)
  country_code              TEXT         NOT NULL,     -- ISO 3166-1 alpha-2. No DEFAULT.
  currency                  CHAR(3)      NOT NULL,     -- ISO 4217. No DEFAULT. Write-once.
  timezone                  TEXT         NOT NULL DEFAULT 'Asia/Kolkata',
  locale                    TEXT         NOT NULL DEFAULT 'en-IN',
  phone_country             TEXT         NOT NULL DEFAULT 'IN',
  primary_language          TEXT         NOT NULL DEFAULT 'en-IN',
  supported_languages       TEXT[]       NOT NULL DEFAULT '{}',
  fiscal_year_start_month   INTEGER      NOT NULL DEFAULT 4,
  -- Data residency (Phase 4I §9.1)
  region_ref                TEXT         NOT NULL DEFAULT 'standard',
  data_residency_profile    TEXT         NOT NULL DEFAULT 'STANDARD',
  -- Cross-schema logical references (no FK constraints)
  compliance_policy_id      UUID         NULL,    -- logical ref: organization.compliance_policies.id
  tax_profile_id            UUID         NULL,    -- logical ref: billing.tax_profiles.id
  billing_account_id        UUID         NULL,    -- logical ref: billing.billing_accounts.id
  -- Display
  website                   TEXT         NULL,
  logo_storage_ref          TEXT         NULL,    -- S3 reference
  deleted_at                TIMESTAMPTZ  NULL,
  created_at                TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_organizations             PRIMARY KEY (id),
  CONSTRAINT chk_orgs_status             CHECK (status IN ('ACTIVE','SUSPENDED','CANCELLED')),
  CONSTRAINT chk_orgs_currency           CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT chk_orgs_country_code       CHECK (length(country_code) = 2 AND country_code = upper(country_code)),
  CONSTRAINT chk_orgs_fiscal_month       CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  CONSTRAINT chk_orgs_residency_profile  CHECK (data_residency_profile IN ('STANDARD','INDIA_ENTERPRISE','REGIONAL')),
  CONSTRAINT chk_orgs_slug_format        CHECK (slug ~ '^[a-z0-9][a-z0-9\-]{2,62}$')
);

CREATE UNIQUE INDEX uq_organizations_slug ON organization.organizations (slug);
CREATE INDEX idx_organizations_status
  ON organization.organizations (status) WHERE status = 'ACTIVE';
CREATE INDEX idx_organizations_owner
  ON organization.organizations (owner_user_id);
CREATE INDEX idx_organizations_country
  ON organization.organizations (country_code);

-- Write-once currency trigger
CREATE TRIGGER trg_organizations_currency_immutable
  BEFORE UPDATE ON organization.organizations
  FOR EACH ROW EXECUTE FUNCTION prevent_currency_change();

CREATE TRIGGER trg_organizations_updated_at
  BEFORE UPDATE ON organization.organizations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- No RLS on organizations (it is the RLS root — see §16.4)
GRANT SELECT, INSERT, UPDATE ON organization.organizations TO app_api, app_worker;
GRANT SELECT ON organization.organizations TO app_readonly;


-- organization.memberships
CREATE TABLE organization.memberships (
  id               UUID         NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID         NOT NULL,
  user_id          UUID         NOT NULL,     -- logical ref: identity.users.id
  role_id          UUID         NOT NULL,
  status           TEXT         NOT NULL DEFAULT 'ACTIVE',
  invited_by       UUID         NULL,         -- logical ref: identity.users.id
  invited_at       TIMESTAMPTZ  NULL,
  accepted_at      TIMESTAMPTZ  NULL,
  removed_at       TIMESTAMPTZ  NULL,
  removed_by       UUID         NULL,         -- logical ref: identity.users.id
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_memberships        PRIMARY KEY (id),
  CONSTRAINT fk_memberships_org    FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE RESTRICT,
  CONSTRAINT fk_memberships_role   FOREIGN KEY (role_id)         REFERENCES organization.roles(id) ON DELETE RESTRICT,
  CONSTRAINT chk_memberships_status CHECK (status IN ('ACTIVE','SUSPENDED','REMOVED'))
);

-- Partial unique: one active membership per user per org (re-invitation allowed after removal)
CREATE UNIQUE INDEX uq_memberships_active
  ON organization.memberships (organization_id, user_id)
  WHERE status = 'ACTIVE';

CREATE INDEX idx_memberships_user_active
  ON organization.memberships (user_id)
  WHERE status = 'ACTIVE';

CREATE INDEX idx_memberships_org_role
  ON organization.memberships (organization_id, role_id);

CREATE TRIGGER trg_memberships_updated_at
  BEFORE UPDATE ON organization.memberships
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE organization.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.memberships FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_memberships_tenant ON organization.memberships
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON organization.memberships TO app_api, app_worker;


-- organization.teams
CREATE TABLE organization.teams (
  id               UUID         NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID         NOT NULL,
  name             TEXT         NOT NULL,
  description      TEXT         NULL,
  status           TEXT         NOT NULL DEFAULT 'ACTIVE',
  created_by       UUID         NOT NULL,    -- logical ref: identity.users.id
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_teams        PRIMARY KEY (id),
  CONSTRAINT fk_teams_org    FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE CASCADE,
  CONSTRAINT chk_teams_status CHECK (status IN ('ACTIVE','ARCHIVED'))
);

CREATE UNIQUE INDEX uq_teams_org_name ON organization.teams (organization_id, name);
CREATE INDEX idx_teams_org ON organization.teams (organization_id);

CREATE TRIGGER trg_teams_updated_at
  BEFORE UPDATE ON organization.teams
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE organization.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.teams FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_teams_tenant ON organization.teams
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON organization.teams TO app_api, app_worker;


-- organization.team_memberships
CREATE TABLE organization.team_memberships (
  id               UUID         NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID         NOT NULL,    -- denormalised for RLS
  team_id          UUID         NOT NULL,
  user_id          UUID         NOT NULL,    -- logical ref: identity.users.id
  added_by         UUID         NULL,        -- logical ref: identity.users.id
  added_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  removed_at       TIMESTAMPTZ  NULL,

  CONSTRAINT pk_team_memberships       PRIMARY KEY (id),
  CONSTRAINT fk_team_memberships_org   FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_team_memberships_team  FOREIGN KEY (team_id) REFERENCES organization.teams(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_team_memberships_active
  ON organization.team_memberships (team_id, user_id)
  WHERE removed_at IS NULL;

CREATE INDEX idx_team_memberships_org ON organization.team_memberships (organization_id);
CREATE INDEX idx_team_memberships_user ON organization.team_memberships (user_id);

ALTER TABLE organization.team_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.team_memberships FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_team_memberships_tenant ON organization.team_memberships
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON organization.team_memberships TO app_api, app_worker;


-- organization.roles
CREATE TABLE organization.roles (
  id               UUID     NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID     NULL,      -- NULL = system role
  name             TEXT     NOT NULL,
  display_name     TEXT     NOT NULL,
  description      TEXT     NULL,
  is_system        BOOLEAN  NOT NULL DEFAULT FALSE,
  is_active        BOOLEAN  NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_roles PRIMARY KEY (id)
);

-- Two partial unique indexes for system and tenant roles
CREATE UNIQUE INDEX uq_roles_system_name
  ON organization.roles (name)
  WHERE organization_id IS NULL;

CREATE UNIQUE INDEX uq_roles_tenant_name
  ON organization.roles (organization_id, name)
  WHERE organization_id IS NOT NULL;

CREATE INDEX idx_roles_org ON organization.roles (organization_id);

CREATE TRIGGER trg_roles_updated_at
  BEFORE UPDATE ON organization.roles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Prevent modification of system role names
CREATE OR REPLACE FUNCTION protect_system_roles()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.is_system = TRUE AND (NEW.name != OLD.name OR NEW.is_system = FALSE) THEN
    RAISE EXCEPTION 'System role % cannot have its name changed or is_system flag altered', OLD.name;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_system_roles
  BEFORE UPDATE ON organization.roles
  FOR EACH ROW EXECUTE FUNCTION protect_system_roles();

ALTER TABLE organization.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.roles FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_roles_read ON organization.roles
  FOR SELECT
  USING (
    organization_id = organization.current_tenant_id()
    OR organization_id IS NULL
  );

CREATE POLICY rls_roles_insert ON organization.roles
  FOR INSERT WITH CHECK (
    organization_id = organization.current_tenant_id()
  );

CREATE POLICY rls_roles_update ON organization.roles
  FOR UPDATE USING (
    organization_id = organization.current_tenant_id()
  );

CREATE POLICY rls_roles_delete ON organization.roles
  FOR DELETE USING (
    organization_id = organization.current_tenant_id()
    AND is_system = FALSE
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON organization.roles TO app_api, app_worker;


-- organization.permissions
CREATE TABLE organization.permissions (
  id            UUID  NOT NULL DEFAULT gen_uuid_v7(),
  name          TEXT  NOT NULL,
  display_name  TEXT  NOT NULL,
  description   TEXT  NULL,
  resource      TEXT  NOT NULL,
  action        TEXT  NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_permissions PRIMARY KEY (id)
);

CREATE UNIQUE INDEX uq_permissions_name ON organization.permissions (name);
CREATE INDEX idx_permissions_resource ON organization.permissions (resource);

-- No RLS — platform-owned reference data
GRANT SELECT ON organization.permissions TO app_api, app_worker, app_readonly;


-- organization.role_permissions
CREATE TABLE organization.role_permissions (
  id             UUID  NOT NULL DEFAULT gen_uuid_v7(),
  role_id        UUID  NOT NULL,
  permission_id  UUID  NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_role_permissions          PRIMARY KEY (id),
  CONSTRAINT fk_role_perms_role           FOREIGN KEY (role_id) REFERENCES organization.roles(id) ON DELETE CASCADE,
  CONSTRAINT fk_role_perms_permission     FOREIGN KEY (permission_id) REFERENCES organization.permissions(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_role_permissions ON organization.role_permissions (role_id, permission_id);
CREATE INDEX idx_role_perms_role_id ON organization.role_permissions (role_id);

ALTER TABLE organization.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.role_permissions FORCE ROW LEVEL SECURITY;

-- Read: see assignments for own roles AND system roles
CREATE POLICY rls_role_permissions_read ON organization.role_permissions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM organization.roles r
      WHERE r.id = role_id
        AND (r.organization_id = organization.current_tenant_id() OR r.organization_id IS NULL)
    )
  );

-- Modify: only own tenant custom roles
CREATE POLICY rls_role_permissions_modify ON organization.role_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM organization.roles r
      WHERE r.id = role_id
        AND r.organization_id = organization.current_tenant_id()
        AND r.is_system = FALSE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM organization.roles r
      WHERE r.id = role_id
        AND r.organization_id = organization.current_tenant_id()
        AND r.is_system = FALSE
    )
  );

GRANT SELECT, INSERT, DELETE ON organization.role_permissions TO app_api, app_worker;


-- organization.compliance_policies
CREATE TABLE organization.compliance_policies (
  id                              UUID      NOT NULL DEFAULT gen_uuid_v7(),
  organization_id                 UUID      NOT NULL,
  name                            TEXT      NOT NULL,
  status                          TEXT      NOT NULL DEFAULT 'DRAFT',
  version                         INTEGER   NOT NULL DEFAULT 1,
  require_consent_for_outbound    BOOLEAN   NOT NULL DEFAULT TRUE,
  required_consent_purposes       TEXT[]    NOT NULL DEFAULT '{OUTBOUND_CALL}',
  recording_policy                TEXT      NOT NULL DEFAULT 'ENABLED',
  recording_disclosure_prompt_id  UUID      NULL,    -- logical ref: workflow.prompt_templates.id
  calling_windows                 JSONB     NOT NULL DEFAULT '[]',
  holiday_calendar_ref            TEXT      NULL,
  allowed_phone_types             TEXT[]    NOT NULL DEFAULT '{MOBILE,LANDLINE}',
  max_attempts_per_contact        INTEGER   NOT NULL DEFAULT 3,
  attempt_window_days             INTEGER   NOT NULL DEFAULT 7,
  suppression_scope               TEXT      NOT NULL DEFAULT 'ORG',
  block_on_policy_failure         BOOLEAN   NOT NULL DEFAULT TRUE,
  retention_profile               JSONB     NOT NULL DEFAULT '{}',
  policy_version                  INTEGER   NOT NULL DEFAULT 1,
  effective_from                  TIMESTAMPTZ NULL,
  created_by                      UUID      NOT NULL,   -- logical ref: identity.users.id
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_compliance_policies       PRIMARY KEY (id),
  CONSTRAINT fk_cp_org                   FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE RESTRICT,
  CONSTRAINT chk_cp_status              CHECK (status IN ('DRAFT','ACTIVE','ARCHIVED')),
  CONSTRAINT chk_cp_recording_policy    CHECK (recording_policy IN ('DISABLED','ENABLED','REQUIRES_CONSENT','REQUIRES_DISCLOSURE')),
  CONSTRAINT chk_cp_suppression_scope   CHECK (suppression_scope IN ('ORG','ORG_AND_PLATFORM')),
  CONSTRAINT chk_cp_max_attempts        CHECK (max_attempts_per_contact BETWEEN 1 AND 10),
  CONSTRAINT chk_cp_window_days         CHECK (attempt_window_days BETWEEN 1 AND 90)
);

-- Only one active policy per org
CREATE UNIQUE INDEX uq_compliance_policy_active
  ON organization.compliance_policies (organization_id)
  WHERE status = 'ACTIVE';

CREATE INDEX idx_cp_org_status ON organization.compliance_policies (organization_id, status);

CREATE TRIGGER trg_cp_updated_at
  BEFORE UPDATE ON organization.compliance_policies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE organization.compliance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.compliance_policies FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_compliance_policies_tenant ON organization.compliance_policies
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON organization.compliance_policies TO app_api, app_worker;


-- organization.data_subject_requests
CREATE TABLE organization.data_subject_requests (
  id                    UUID          NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID          NOT NULL,
  request_type          TEXT          NOT NULL,
  subject_contact_id    UUID          NULL,     -- logical ref: crm.contacts.id
  subject_email         TEXT          NULL,     -- pii:email
  subject_phone_e164    TEXT          NULL,     -- pii:phone
  status                TEXT          NOT NULL DEFAULT 'RECEIVED',
  requested_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  verified_at           TIMESTAMPTZ   NULL,
  completed_at          TIMESTAMPTZ   NULL,
  due_at                TIMESTAMPTZ   NULL,
  requested_by          UUID          NULL,     -- logical ref: identity.users.id
  completed_by          UUID          NULL,     -- logical ref: identity.users.id
  resolution_notes      TEXT          NULL,
  export_storage_ref    TEXT          NULL,     -- S3 path
  rejection_reason      TEXT          NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_data_subject_requests   PRIMARY KEY (id),
  CONSTRAINT fk_dsr_org                 FOREIGN KEY (organization_id) REFERENCES organization.organizations(id) ON DELETE RESTRICT,
  CONSTRAINT chk_dsr_type               CHECK (request_type IN ('ACCESS','EXPORT','DELETE','RECTIFY','RESTRICT')),
  CONSTRAINT chk_dsr_status             CHECK (status IN ('RECEIVED','VERIFYING','IN_PROGRESS','COMPLETED','REJECTED','ON_HOLD')),
  CONSTRAINT chk_dsr_subject_present    CHECK (subject_contact_id IS NOT NULL OR subject_email IS NOT NULL OR subject_phone_e164 IS NOT NULL)
);

CREATE INDEX idx_dsr_org_status ON organization.data_subject_requests (organization_id, status);
CREATE INDEX idx_dsr_org_requested_at ON organization.data_subject_requests (organization_id, requested_at);
CREATE INDEX idx_dsr_subject_contact
  ON organization.data_subject_requests (subject_contact_id)
  WHERE subject_contact_id IS NOT NULL;

CREATE TRIGGER trg_dsr_updated_at
  BEFORE UPDATE ON organization.data_subject_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE organization.data_subject_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization.data_subject_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY rls_data_subject_requests_tenant ON organization.data_subject_requests
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON organization.data_subject_requests TO app_api, app_worker;
```

### 33.4 Seed Data Migration

```sql
-- ==============================================================
-- Migration 004: Seed system roles and permissions
-- ==============================================================

-- System roles (organization_id IS NULL = platform-global)
INSERT INTO organization.roles (id, organization_id, name, display_name, description, is_system, is_active)
VALUES
  ('018c0000-0000-7000-a000-000000000001'::UUID, NULL, 'OWNER',        'Owner',         'Full organization control and ownership',         TRUE, TRUE),
  ('018c0000-0000-7000-a000-000000000002'::UUID, NULL, 'ADMIN',         'Admin',         'Administrative access to most features',         TRUE, TRUE),
  ('018c0000-0000-7000-a000-000000000003'::UUID, NULL, 'MEMBER',        'Member',        'Standard operational member access',             TRUE, TRUE),
  ('018c0000-0000-7000-a000-000000000004'::UUID, NULL, 'BILLING_ADMIN', 'Billing Admin', 'Billing, invoices, and financial management',    TRUE, TRUE),
  ('018c0000-0000-7000-a000-000000000005'::UUID, NULL, 'VIEWER',        'Viewer',        'Read-only access to approved resources',         TRUE, TRUE)
ON CONFLICT (name) WHERE organization_id IS NULL DO NOTHING;

-- System permissions
INSERT INTO organization.permissions (name, display_name, resource, action) VALUES
  ('organization:read',        'View Organization',           'organization',     'read'),
  ('organization:update',      'Edit Organization Settings',  'organization',     'update'),
  ('organization:suspend',     'Suspend Organization',        'organization',     'suspend'),
  ('organization:delete',      'Delete Organization',         'organization',     'delete'),
  ('member:read',              'View Members',                'member',           'read'),
  ('member:invite',            'Invite Members',              'member',           'invite'),
  ('member:remove',            'Remove Members',              'member',           'remove'),
  ('member:suspend',           'Suspend Members',             'member',           'suspend'),
  ('role:read',                'View Roles',                  'role',             'read'),
  ('role:manage',              'Manage Roles',                'role',             'manage'),
  ('agent:read',               'View Agents',                 'agent',            'read'),
  ('agent:write',              'Edit Agents',                 'agent',            'write'),
  ('agent:publish',            'Publish Agents',              'agent',            'publish'),
  ('agent:delete',             'Delete Agents',               'agent',            'delete'),
  ('call:read',                'View Calls',                  'call',             'read'),
  ('call:initiate',            'Initiate Calls',              'call',             'initiate'),
  ('call:transfer',            'Transfer Calls',              'call',             'transfer'),
  ('call:record',              'Configure Recording',         'call',             'record'),
  ('contact:read',             'View Contacts',               'contact',          'read'),
  ('contact:write',            'Edit Contacts',               'contact',          'write'),
  ('contact:delete',           'Delete Contacts',             'contact',          'delete'),
  ('contact:merge',            'Merge Contacts',              'contact',          'merge'),
  ('contact:convert',          'Convert Leads',               'contact',          'convert'),
  ('deal:read',                'View Deals',                  'deal',             'read'),
  ('deal:write',               'Edit Deals',                  'deal',             'write'),
  ('deal:close',               'Close Deals',                 'deal',             'close'),
  ('campaign:read',            'View Campaigns',              'campaign',         'read'),
  ('campaign:write',           'Edit Campaigns',              'campaign',         'write'),
  ('campaign:start',           'Start Campaigns',             'campaign',         'start'),
  ('campaign:stop',            'Stop Campaigns',              'campaign',         'stop'),
  ('knowledge:read',           'View Knowledge Bases',        'knowledge',        'read'),
  ('knowledge:write',          'Edit Knowledge Bases',        'knowledge',        'write'),
  ('knowledge:delete',         'Delete Knowledge Bases',      'knowledge',        'delete'),
  ('workflow:read',            'View Workflows',              'workflow',         'read'),
  ('workflow:write',           'Edit Workflows',              'workflow',         'write'),
  ('workflow:publish',         'Publish Workflows',           'workflow',         'publish'),
  ('prompt:read',              'View Prompts',                'prompt',           'read'),
  ('prompt:write',             'Edit Prompts',                'prompt',           'write'),
  ('prompt:publish',           'Publish Prompts',             'prompt',           'publish'),
  ('prompt:rollback',          'Rollback Prompts',            'prompt',           'rollback'),
  ('billing:read',             'View Billing',                'billing',          'read'),
  ('billing:manage',           'Manage Billing',              'billing',          'manage'),
  ('invoice:read',             'View Invoices',               'invoice',          'read'),
  ('analytics:read',           'View Analytics',              'analytics',        'read'),
  ('analytics_cost:read',      'View Cost Analytics',         'analytics_cost',   'read'),
  ('analytics_platform:read',  'View Platform Analytics',     'analytics_platform','read'),
  ('integration:read',         'View Integrations',           'integration',      'read'),
  ('integration:manage',       'Manage Integrations',         'integration',      'manage'),
  ('webhook:read',             'View Webhooks',               'webhook',          'read'),
  ('webhook:manage',           'Manage Webhooks',             'webhook',          'manage'),
  ('plugin:read',              'View Plugins',                'plugin',           'read'),
  ('plugin:install',           'Install Plugins',             'plugin',           'install'),
  ('plugin:manage',            'Manage Plugins',              'plugin',           'manage'),
  ('api_key:read',             'View API Keys',               'api_key',          'read'),
  ('api_key:manage',           'Manage API Keys',             'api_key',          'manage'),
  ('audit:read',               'View Audit Log',              'audit',            'read'),
  ('suppression:read',         'View Suppressions',           'suppression',      'read'),
  ('suppression:manage',       'Manage Suppressions',         'suppression',      'manage'),
  ('suppression:lift',         'Lift Suppressions',           'suppression',      'lift'),
  ('consent:read',             'View Consent Records',        'consent',          'read'),
  ('consent:manage',           'Manage Consent',              'consent',          'manage'),
  ('compliance:read',          'View Compliance Policy',      'compliance',       'read'),
  ('compliance:manage',        'Manage Compliance Policy',    'compliance',       'manage'),
  ('data_subject:manage',      'Handle Data Subject Requests','data_subject',     'manage'),
  ('tax:manage',               'Manage Tax Profile',          'tax',              'manage'),
  ('recording:read',           'Access Recordings',           'recording',        'read'),
  ('recording:delete',         'Delete Recordings',           'recording',        'delete'),
  ('transcript:read',          'View Transcripts',            'transcript',       'read')
ON CONFLICT (name) DO NOTHING;

-- Role-permission assignments using name lookups
WITH
  r AS (SELECT id, name FROM organization.roles WHERE organization_id IS NULL),
  p AS (SELECT id, name FROM organization.permissions)
INSERT INTO organization.role_permissions (id, role_id, permission_id)
SELECT gen_uuid_v7(), r.id, p.id
FROM (VALUES
  -- OWNER
  ('OWNER','organization:read'),('OWNER','organization:update'),('OWNER','organization:suspend'),('OWNER','organization:delete'),
  ('OWNER','member:read'),('OWNER','member:invite'),('OWNER','member:remove'),('OWNER','member:suspend'),
  ('OWNER','role:read'),('OWNER','role:manage'),
  ('OWNER','agent:read'),('OWNER','agent:write'),('OWNER','agent:publish'),('OWNER','agent:delete'),
  ('OWNER','call:read'),('OWNER','call:initiate'),('OWNER','call:transfer'),('OWNER','call:record'),
  ('OWNER','contact:read'),('OWNER','contact:write'),('OWNER','contact:delete'),('OWNER','contact:merge'),('OWNER','contact:convert'),
  ('OWNER','deal:read'),('OWNER','deal:write'),('OWNER','deal:close'),
  ('OWNER','campaign:read'),('OWNER','campaign:write'),('OWNER','campaign:start'),('OWNER','campaign:stop'),
  ('OWNER','knowledge:read'),('OWNER','knowledge:write'),('OWNER','knowledge:delete'),
  ('OWNER','workflow:read'),('OWNER','workflow:write'),('OWNER','workflow:publish'),
  ('OWNER','prompt:read'),('OWNER','prompt:write'),('OWNER','prompt:publish'),('OWNER','prompt:rollback'),
  ('OWNER','billing:read'),('OWNER','billing:manage'),('OWNER','invoice:read'),
  ('OWNER','analytics:read'),('OWNER','analytics_cost:read'),
  ('OWNER','integration:read'),('OWNER','integration:manage'),
  ('OWNER','webhook:read'),('OWNER','webhook:manage'),
  ('OWNER','plugin:read'),('OWNER','plugin:install'),('OWNER','plugin:manage'),
  ('OWNER','api_key:read'),('OWNER','api_key:manage'),
  ('OWNER','audit:read'),
  ('OWNER','suppression:read'),('OWNER','suppression:manage'),('OWNER','suppression:lift'),
  ('OWNER','consent:read'),('OWNER','consent:manage'),
  ('OWNER','compliance:read'),('OWNER','compliance:manage'),
  ('OWNER','data_subject:manage'),('OWNER','tax:manage'),
  ('OWNER','recording:read'),('OWNER','recording:delete'),('OWNER','transcript:read'),
  -- ADMIN
  ('ADMIN','organization:read'),('ADMIN','organization:update'),
  ('ADMIN','member:read'),('ADMIN','member:invite'),('ADMIN','member:remove'),('ADMIN','member:suspend'),
  ('ADMIN','role:read'),('ADMIN','role:manage'),
  ('ADMIN','agent:read'),('ADMIN','agent:write'),('ADMIN','agent:publish'),('ADMIN','agent:delete'),
  ('ADMIN','call:read'),('ADMIN','call:initiate'),('ADMIN','call:transfer'),('ADMIN','call:record'),
  ('ADMIN','contact:read'),('ADMIN','contact:write'),('ADMIN','contact:delete'),('ADMIN','contact:merge'),('ADMIN','contact:convert'),
  ('ADMIN','deal:read'),('ADMIN','deal:write'),('ADMIN','deal:close'),
  ('ADMIN','campaign:read'),('ADMIN','campaign:write'),('ADMIN','campaign:start'),('ADMIN','campaign:stop'),
  ('ADMIN','knowledge:read'),('ADMIN','knowledge:write'),('ADMIN','knowledge:delete'),
  ('ADMIN','workflow:read'),('ADMIN','workflow:write'),('ADMIN','workflow:publish'),
  ('ADMIN','prompt:read'),('ADMIN','prompt:write'),('ADMIN','prompt:publish'),('ADMIN','prompt:rollback'),
  ('ADMIN','billing:read'),('ADMIN','invoice:read'),
  ('ADMIN','analytics:read'),('ADMIN','analytics_cost:read'),
  ('ADMIN','integration:read'),('ADMIN','integration:manage'),
  ('ADMIN','webhook:read'),('ADMIN','webhook:manage'),
  ('ADMIN','plugin:read'),('ADMIN','plugin:install'),('ADMIN','plugin:manage'),
  ('ADMIN','api_key:read'),('ADMIN','api_key:manage'),
  ('ADMIN','audit:read'),
  ('ADMIN','suppression:read'),('ADMIN','suppression:manage'),('ADMIN','suppression:lift'),
  ('ADMIN','consent:read'),('ADMIN','consent:manage'),
  ('ADMIN','compliance:read'),('ADMIN','compliance:manage'),
  ('ADMIN','data_subject:manage'),
  ('ADMIN','recording:read'),('ADMIN','recording:delete'),('ADMIN','transcript:read'),
  -- MEMBER
  ('MEMBER','organization:read'),('MEMBER','member:read'),('MEMBER','role:read'),
  ('MEMBER','agent:read'),('MEMBER','agent:write'),
  ('MEMBER','call:read'),('MEMBER','call:initiate'),('MEMBER','call:transfer'),
  ('MEMBER','contact:read'),('MEMBER','contact:write'),('MEMBER','contact:convert'),
  ('MEMBER','deal:read'),('MEMBER','deal:write'),
  ('MEMBER','campaign:read'),('MEMBER','campaign:write'),
  ('MEMBER','knowledge:read'),('MEMBER','knowledge:write'),
  ('MEMBER','workflow:read'),('MEMBER','workflow:write'),
  ('MEMBER','prompt:read'),('MEMBER','prompt:write'),
  ('MEMBER','analytics:read'),
  ('MEMBER','integration:read'),('MEMBER','webhook:read'),('MEMBER','plugin:read'),
  ('MEMBER','suppression:read'),('MEMBER','consent:read'),('MEMBER','consent:manage'),
  ('MEMBER','recording:read'),('MEMBER','transcript:read'),
  -- BILLING_ADMIN
  ('BILLING_ADMIN','organization:read'),('BILLING_ADMIN','member:read'),
  ('BILLING_ADMIN','billing:read'),('BILLING_ADMIN','billing:manage'),('BILLING_ADMIN','invoice:read'),
  ('BILLING_ADMIN','analytics:read'),('BILLING_ADMIN','analytics_cost:read'),
  ('BILLING_ADMIN','tax:manage'),
  -- VIEWER
  ('VIEWER','organization:read'),('VIEWER','member:read'),('VIEWER','role:read'),
  ('VIEWER','agent:read'),('VIEWER','call:read'),
  ('VIEWER','contact:read'),('VIEWER','deal:read'),
  ('VIEWER','campaign:read'),('VIEWER','knowledge:read'),
  ('VIEWER','workflow:read'),('VIEWER','prompt:read'),
  ('VIEWER','analytics:read'),
  ('VIEWER','integration:read'),('VIEWER','webhook:read'),('VIEWER','plugin:read'),
  ('VIEWER','recording:read'),('VIEWER','transcript:read')
) AS m(role_name, perm_name)
JOIN r ON r.name = m.role_name
JOIN p ON p.name = m.perm_name
ON CONFLICT (role_id, permission_id) DO NOTHING;
```

---

## 34. Alembic Migration Plan

### 34.1 Migration File Structure

```
alembic/versions/
├── 001_20250115_extensions_schemas_functions.py   # Extensions, 13 schemas, helper fns, roles
├── 002_20250115_identity_tables.py                # users, sessions, password_reset_tokens, oauth_identities, api_keys
├── 003_20250115_organization_tables.py            # organizations, memberships, teams, team_memberships, roles, permissions, role_permissions
├── 004_20250115_organization_compliance.py        # compliance_policies, data_subject_requests
├── 005_20250115_rls_policies_identity.py          # RLS for api_keys
├── 006_20250115_rls_policies_organization.py      # RLS for memberships, teams, team_memberships, roles, role_permissions, compliance_policies, data_subject_requests
├── 007_20250115_seed_roles_permissions.py         # System roles, permissions, role-permission assignments
└── 008_20250115_grants.py                         # GRANT/REVOKE statements for all roles
```

### 34.2 Revision Dependencies

```python
# Migration 001 — no dependencies (initial)
# down_revision = None

# Migration 002 — depends on schemas and functions
# down_revision = '001_extensions_schemas'

# Migration 003 — depends on 001 (schemas must exist)
# down_revision = '001_extensions_schemas'

# Migration 004 — depends on 003 (organizations table must exist)
# down_revision = '003_organization_tables'

# Migration 005 — depends on 002, 003 (api_keys uses organization.current_tenant_id())
# down_revision = ('002_identity_tables', '003_organization_tables')

# Migration 006 — depends on 003, 004
# down_revision = ('003_organization_tables', '004_organization_compliance')

# Migration 007 — depends on 003 (roles and permissions tables must exist)
# down_revision = '003_organization_tables'

# Migration 008 — depends on all above
# down_revision = ('006_rls_organization', '007_seed_roles')
```

### 34.3 Alembic Configuration Notes

```python
# alembic.ini context:
# transaction_per_migration = true  (each migration in its own transaction)
# For indexes using CONCURRENTLY:
#   Must disable transaction: op.execute('COMMIT')... not applicable in Alembic directly
#   Use: context.connection.execute(text("...CONCURRENTLY...")) outside transaction

# All CREATE INDEX in Phase 5B use standard (non-CONCURRENT) form for initial deployment
# since the tables are empty at this point. CONCURRENTLY is required for live production
# tables only (zero-downtime adds after launch).
```

### 34.4 Upgrade Path

```python
# In each migration's upgrade():
# 1. Create table(s)
# 2. Create indexes (standard form for initial migration; CONCURRENTLY for post-launch)
# 3. Create triggers
# 4. Enable RLS
# 5. Create policies
# 6. GRANT/REVOKE
# 7. Insert seed data (migration 007 only)

# In each migration's downgrade():
# Drop in reverse order: policies, RLS disable, triggers, indexes, tables
# Seed data downgrade: DELETE seed rows WHERE NOT EXISTS user data
```

---

## 35. Query Patterns

### 35.1 Get User by Normalized Email (Login)

```sql
SELECT id, status, password_hash, mfa_enabled, email_verified_at
FROM identity.users
WHERE email_normalized = lower(trim($1))
  AND deleted_at IS NULL;
-- Uses: uq_users_email_normalized (UNIQUE index)
-- RLS: none (pre-authentication)
-- N+1 risk: none (single row by unique key)
```

### 35.2 Validate API Key (Every API Request)

```sql
-- Connection: SET LOCAL app.tenant_id = ''  (not yet set)
-- Query runs without tenant context; RLS bypassed because api_keys.organization_id
-- will be the result used to SET tenant_id afterward.
-- Actually: RLS on api_keys requires tenant_id. So we must use app_platform_admin role
-- OR disable RLS for this specific lookup via a security-definer function.

-- Solution: API key authentication uses a SECURITY DEFINER function:
CREATE OR REPLACE FUNCTION identity.validate_api_key(p_key_hash TEXT)
RETURNS TABLE (
  api_key_id       UUID,
  organization_id  UUID,
  scopes           TEXT[],
  status           TEXT
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = identity, organization, pg_temp
AS $$
  SELECT id, organization_id, scopes, status
  FROM identity.api_keys
  WHERE key_hash = p_key_hash
    AND status = 'ACTIVE'
    AND (expires_at IS NULL OR expires_at > NOW());
$$;

-- Application calls: SELECT * FROM identity.validate_api_key($key_hash)
-- Then: SET LOCAL app.tenant_id = returned.organization_id
-- Uses: uq_api_keys_key_hash (UNIQUE index) — extremely fast
```

### 35.3 Get User's Organizations (Pre-Context)

```sql
-- Called on login before org is selected; uses SECURITY DEFINER function
SELECT organization_id
FROM organization.get_user_organization_ids($user_id);

-- Under the hood (SECURITY DEFINER):
SELECT m.organization_id
FROM organization.memberships m
WHERE m.user_id = $user_id AND m.status = 'ACTIVE';
-- Uses: idx_memberships_user_active (partial B-tree)
```

### 35.4 Check User Permission in Organization

```sql
-- Called by CheckPermission OHS (Phase 4A)
-- SET LOCAL app.tenant_id = $org_id is already done

SELECT 1
FROM organization.memberships m
JOIN organization.role_permissions rp ON rp.role_id = m.role_id
JOIN organization.permissions p ON p.id = rp.permission_id
WHERE m.user_id = $user_id
  AND m.organization_id = $org_id
  AND m.status = 'ACTIVE'
  AND p.name = $permission_name
LIMIT 1;

-- Uses: idx_memberships_org_role, idx_role_perms_role_id, uq_permissions_name
-- CACHED in Redis: rbac:permissions:{org_id}:{user_id} → list of permission strings
-- This query only runs on Redis cache miss (first request or after invalidation)
```

### 35.5 Get Organization Members

```sql
-- SET LOCAL app.tenant_id = $org_id
SELECT m.id, m.user_id, m.status, m.accepted_at,
       u.display_name, u.email, u.email_verified_at,
       r.name AS role_name, r.display_name AS role_display_name
FROM organization.memberships m
JOIN organization.roles r ON r.id = m.role_id
-- Cross-schema join — no FK, but join is valid in query
-- identity.users is platform-scoped (no RLS), so no SET LOCAL needed
JOIN identity.users u ON u.id = m.user_id AND u.deleted_at IS NULL
WHERE m.organization_id = organization.current_tenant_id()
  AND m.status = 'ACTIVE'
ORDER BY m.accepted_at ASC NULLS LAST;

-- RLS filters memberships to current org automatically
-- Uses: idx_memberships_user_active (covers organization_id + status filter)
```

### 35.6 Get Active Compliance Policy

```sql
-- SET LOCAL app.tenant_id = $org_id
SELECT id, calling_windows, required_consent_purposes,
       recording_policy, max_attempts_per_contact, attempt_window_days,
       suppression_scope, block_on_policy_failure, policy_version
FROM organization.compliance_policies
WHERE organization_id = organization.current_tenant_id()
  AND status = 'ACTIVE'
LIMIT 1;

-- Uses: uq_compliance_policy_active (partial unique index — O(1) lookup)
-- CACHED in Redis: compliance_policy:{org_id}
```

### 35.7 Get Pending Data Subject Requests

```sql
-- SET LOCAL app.tenant_id = $org_id
SELECT id, request_type, subject_contact_id, subject_email, status, requested_at, due_at
FROM organization.data_subject_requests
WHERE organization_id = organization.current_tenant_id()
  AND status IN ('RECEIVED','VERIFYING','IN_PROGRESS')
ORDER BY requested_at ASC;

-- Uses: idx_dsr_org_status
-- RLS filters to current org
```

---

## 36. Performance Review

### 36.1 Hot Paths and Their Index Coverage

| Hot path | Query | Index | Expected latency |
|---|---|---|---|
| API key validation | `WHERE key_hash = $1` | `uq_api_keys_key_hash` | < 1ms |
| User login | `WHERE email_normalized = $1` | `uq_users_email_normalized` | < 1ms |
| Permission check (cache miss) | 3-table join | `idx_memberships_org_role` + role_perms | < 5ms |
| Org config load | `WHERE organization_id = $1` (PK) | PK index | < 1ms |
| Compliance policy load | `WHERE org_id AND status = 'ACTIVE'` | `uq_compliance_policy_active` | < 1ms |

### 36.2 Redis Caching Impact

- **Permission checks** are served from Redis 99%+ of the time (5-min TTL). The database query in §35.4 runs < 1% of requests.
- **API key metadata** is cached for 5 minutes. Critical: immediate invalidation on revocation via explicit `DEL`.
- **Org localization** is cached 15 minutes — called on every request to determine timezone/locale.

### 36.3 `last_used_at` Write Concern

`identity.api_keys.last_used_at` is updated on every API request. At high volume this is a hot row. Mitigation:
- Application batch-updates `last_used_at` every 60 seconds (not per-request) using the Redis cached metadata as the source. The DB write happens in a background task, not in the request path.
- Alternatively: accept eventual `last_used_at` staleness and write only when the value changes by > 5 minutes.

---

## 37. Security Review

### 37.1 Password Security

| Check | Status | Detail |
|---|---|---|
| No plaintext passwords | ✅ | `password_hash` stores Argon2id hash only |
| No password in events | ✅ | Audit events contain no password-related values |
| No password in logs | ✅ | `password_hash` in PII deny-list |
| Hash algorithm future-proofing | ✅ | Argon2id self-describing string includes parameters — algorithm upgrade is transparent |
| Reset token not stored raw | ✅ | `token_hash = SHA-256(raw_token)` — raw token exists only in the email |

### 37.2 API Key Security

| Check | Status | Detail |
|---|---|---|
| No raw key stored | ✅ | `key_hash` + `key_prefix` only |
| Key validated via hash | ✅ | SHA-256 comparison — fast, secure |
| Revocation invalidates cache | ✅ | Immediate Redis DEL on revoke |
| Scope enforcement | ✅ | Application intersects key scopes with role permissions |
| Tenant isolation | ✅ | RLS on `api_keys` by `organization_id`; key establishes org context |

### 37.3 OAuth Security

| Check | Status | Detail |
|---|---|---|
| No OAuth tokens stored raw | ✅ | `credential_ref` to secret manager; NULL for identity-only OAuth |
| Provider subject uniqueness | ✅ | `UNIQUE (provider, provider_subject)` |
| Email matching at provider vs. platform | ✅ | `email_at_provider` is informational; auth is via `provider_subject` |
| CSRF protection | ✅ | State parameter generated by application; not stored in DB |

### 37.4 Session Security

| Check | Status | Detail |
|---|---|---|
| No raw refresh token stored | ✅ | `refresh_token_hash` only |
| Revocation | ✅ | `status = 'REVOKED'`; access token JTI revocation for emergencies |
| Expiry enforcement | ✅ | `expires_at` checked at application layer |
| Device tracking | ✅ | `device_label` user-set; `user_agent_hash` not raw |

### 37.5 RLS Security

| Check | Status | Detail |
|---|---|---|
| Fail-closed on missing context | ✅ | `NULLIF(current_setting(...), '')::UUID` returns NULL → 0 rows matched |
| No recursive RLS | ✅ | Memberships RLS predicates on `organization_id` column, not via a sub-query into memberships |
| System roles protected | ✅ | Trigger prevents name/is_system change; RLS insert policy requires tenant org_id |
| Platform rows protected from tenants | ✅ | Mixed-scope policies: tenants can read but not write `organization_id IS NULL` rows |

### 37.6 Privilege Escalation Prevention

| Scenario | Prevention |
|---|---|
| User grants themselves OWNER | `role:manage` permission required + server validates the assigning user has higher/equal role |
| Member removes OWNER | Last-owner check at application layer; DB enforces no FK violation (role still exists) |
| Tenant creates system role | RLS `INSERT` policy: `WITH CHECK (organization_id = current_tenant_id())` — cannot insert NULL org |
| Tenant modifies system permissions | `role_permissions` `FOR ALL USING (is_system = FALSE)` prevents touching system role permissions |

---

## 38. Tenant Isolation Test Matrix

| Test case | Mechanism | Expected result |
|---|---|---|
| Tenant A reads Tenant B's organization | `SET LOCAL app.tenant_id = OrgA`; query `organizations WHERE id = OrgB` | 0 rows (no RLS on organizations; application filters by id = jwt.org_id) |
| Tenant A reads Tenant B's memberships | `SET LOCAL app.tenant_id = OrgA`; `SELECT * FROM organization.memberships` | Only OrgA rows (RLS: `organization_id = current_tenant_id()`) |
| Tenant A modifies Tenant B's membership | `SET LOCAL app.tenant_id = OrgA`; `UPDATE memberships SET ... WHERE organization_id = OrgB` | 0 rows affected; RLS `USING` clause blocks the update |
| Tenant A uses Tenant B's API key | Application computes `key_hash`; query by hash | Found but `organization_id = OrgB`; `SET LOCAL app.tenant_id = OrgB` — not OrgA |
| Unauthenticated reads api_keys | No `SET LOCAL app.tenant_id` | `current_tenant_id() = NULL` → 0 rows |
| Member escalates to OWNER | `INSERT INTO role_permissions` targeting OWNER role | RLS blocks: `is_system = FALSE` required in USING clause |
| Tenant modifies system permissions | `DELETE FROM role_permissions WHERE role_id = (owner role id)` | RLS blocks: `is_system = FALSE` check fails for system roles |
| Revoked API key authenticates | `validate_api_key()` | `status = 'ACTIVE'` filter → not found; 401 |
| Expired session token | Application checks `expires_at > NOW()` | Rejected before any RLS context is set |
| Platform admin reads cross-tenant | `BYPASSRLS` role; explicit org context | Success; operation audited |

---

## 39. Design Decisions / ADRs

### ADR-5B-001: Email Normalization via Application-Layer LOWER(TRIM)

**Decision:** normalize email at write time in application code; store in `email_normalized TEXT`; UNIQUE index on that column.

**Alternative rejected:** PostgreSQL `CITEXT` extension. Rejected because it adds an extension dependency and spreads case-insensitive comparison behavior everywhere the column is used — including joins and GROUP BY — making behavior less predictable. Application-layer normalization is explicit and testable.

### ADR-5B-002: User Phone Not Globally Unique

**Decision:** `identity.users.phone_e164` is nullable and has no UNIQUE constraint.

**Rationale:** a user may share a phone number across organizations in edge cases (e.g., a freelancer who manages accounts for multiple clients). Phone uniqueness is enforced at the CRM `contacts` level (one contact per phone per organization). The user record is a platform identity, not a CRM contact.

### ADR-5B-003: Localization on Organizations Directly (No Separate Table)

**Decision:** all localization fields are typed columns on `organization.organizations`. No `localization_profiles` table.

**Rationale:** Phase 4I ADR-INDIA-020 made this decision. Fields are always read/written together with the org; no independent lifecycle; a separate table would add a join to every auth request.

### ADR-5B-004: Partial UNIQUE Index for Active Memberships

**Decision:** `UNIQUE (organization_id, user_id) WHERE status = 'ACTIVE'` allows re-invitation after removal.

**Alternative rejected:** hard UNIQUE on `(organization_id, user_id)` regardless of status. Rejected because re-invitation after removal is a valid business case (staff turnover, freelancer return).

### ADR-5B-005: SECURITY DEFINER for API Key Validation

**Decision:** `identity.validate_api_key()` is `SECURITY DEFINER` to allow lookup without tenant context being pre-established.

**Rationale:** at authentication time, the tenant context has not been set yet — the API key IS the mechanism for establishing it. A standard RLS read of `api_keys` would fail because `current_tenant_id()` returns NULL. The SECURITY DEFINER function is narrow (returns only `organization_id`, `scopes`, `status`) and has a fixed `search_path`.

### ADR-5B-006: No Separate `user_preferences` Table

**Decision:** user preferences are out of scope for Phase 5B. If needed, they will be added as a JSONB column on `identity.users` in a later migration.

**Rationale:** Phase 4A DDD does not define a `UserPreferences` aggregate. Avoiding speculative tables.

### ADR-5B-007: `data_subject_requests.status` Must Have at Least One Subject Identifier

**Decision:** `CHECK (subject_contact_id IS NOT NULL OR subject_email IS NOT NULL OR subject_phone_e164 IS NOT NULL)` on `data_subject_requests`.

**Rationale:** a data subject request with no identifiable subject cannot be acted upon. At least one identifier must be present.

---

## 40. Phase 5C Handoff

Phase 5C designs the `voice` schema. The following Phase 5B constructs are referenced by Phase 5C:

| Phase 5B construct | How Phase 5C uses it |
|---|---|
| `organization.organizations.id` | Logical FK in all `voice.*` tables as `organization_id` |
| `organization.current_tenant_id()` | RLS predicate in all `voice.*` tenant-scoped tables |
| `set_updated_at()` trigger function | Applied to all mutable `voice.*` tables |
| `gen_uuid_v7()` function | Primary keys for all `voice.*` tables |
| `prevent_currency_change()` function | Referenced by design note — not needed in voice schema |
| Permission strings (`agent:read`, `agent:write`, `agent:publish`, etc.) | Authorization checks in voice application services |
| System role IDs (OWNER, ADMIN, MEMBER) | Phase 5C does not need the IDs — permissions are used by name |
| `organization.get_user_organization_ids()` | Not needed in voice schema directly |

**Cross-schema reference pattern that Phase 5C must follow:**

All `voice.*` tables that reference `organizations` use `organization_id UUID NOT NULL` with comment `-- logical ref: organization.organizations.id` — no FK constraint. The schema isolation rule from Phase 5A §7 applies to all subsequent phases.

---

## Phase 5B Status

```
PHASE 5B STATUS

Identity schema:
APPROVED

Organization schema:
APPROVED

Multi-tenancy:
APPROVED

RLS:
APPROVED

RBAC:
APPROVED

Security:
APPROVED

India-first configuration:
APPROVED

DDL:
APPROVED

Alembic migration plan:
APPROVED

Overall:

PHASE 5C READY
```

**No issues prevent Phase 5C from beginning.**

The `voice`, `crm`, `campaign`, `knowledge`, `workflow`, `billing`, `integrations`, `webhooks`, `plugins`, `analytics`, and `audit` schemas may all be designed independently once Phase 5C begins, following the standards and patterns established in Phase 5A and the concrete constructs (functions, roles, conventions) delivered in Phase 5B.

---

## Controlled Amendment — Phase 5L (2026-08-24)

Migration `087_5B1.sql` adds `organization.break_glass_grants`, closing
DEP-6B-01 (durable break-glass grant-lifecycle persistence, 6B §36.3).
Columns mirror the interim Redis grant record's own field shape:
`organization_id`, `admin_user_id`, `justification`, `session_id`,
`issued_at`/`expires_at`, and an `ACTIVE`/`RELEASED` status (`EXPIRED`
is computed at read time from `expires_at`, mirroring
`crm.contact_suppressions`' established pattern, not a written state).
Only `organization.fn_break_glass_grant()` / `fn_break_glass_release()`
(both `SECURITY DEFINER`, both requiring `organization.is_platform_admin()`)
may write to this table; RLS restricts even `SELECT` to platform-admin
sessions. Redis remains the fast-path cache; this table is now the
durable source of truth.

DEP-6B-08 (durable forced-revocation delivery) is resolved **without a
new table** — `audit.domain_event_outbox` (migration `077_5J1.sql`)
already provides crash-safe, retryable, observable delivery. The
password-reset-confirm transaction should, in the same transaction as
the password change and session revocation, insert an outbox event:

```
event_type    = 'identity.forced_revocation_required'
aggregate_type = 'session'
aggregate_id  = <the session's id>
payload       = {
  "user_id":            <uuid>,
  "session_ids":        [<uuid>, ...],
  "access_token_jti":   [<text>, ...],
  "reason":              "PASSWORD_RESET"
}
```

Only JTIs (opaque revocation identifiers, `identity.sessions.access_token_jti`)
are carried in the payload — never the raw bearer access/refresh token or
`refresh_token_hash`. The existing outbox worker (Redis Streams publish,
retry with backoff, terminal `FAILED` state on exhaustion) delivers this
to the Redis denylist writer; no new infrastructure is introduced.

DEP-6B-02's four missing `action_kind` values
(`SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, an admin-forced-logout
value, a forced-revocation-denylist-write value) are added to
`5J-Analytics-Audit-Schema.md` §14.3's governed vocabulary list — a
documentation-only amendment, since `action_kind` has no schema-level
enum constraint.

DEP-6B-03 (MFA recovery) is explicitly **not** addressed here — no
frozen V1 requirement was found for it in this pass either; ADR-6B-10's
deferral stands.

See `docs/phase-05-database-design/5L-Global-Database-Reconciliation/
5L-Global-Database-Reconciliation.md` for the full classification report
and live validation evidence.

---

## Controlled Amendment — Phase 6G CRM Reconciliation (2026-08-28)

Migration `096_5B2.sql` adds one new permission to the catalog in §17/§32:
`crm_field:manage` (`'Manage CRM Custom Field Definitions'`, resource
`crm_field`, action `manage`), granted to `OWNER` and `ADMIN` only.
Purely additive — `007_5B.sql`'s existing rows are untouched, and the
insert follows its exact `ON CONFLICT DO NOTHING` idempotent pattern.

This closes `docs/phase-06-api-design/6G-CRM-Leads-APIs.md`'s DEP-6G-10:
CRM custom-field-definition administration (create/update/archive a
tenant-wide field definition affecting every future Contact/Company/Deal
create or edit) had been mapped onto the existing `contact:write`
permission for lack of a dedicated scope — but `contact:write` is
`MEMBER`-eligible, and a schema-wide administrative action has a
materially larger blast radius than an ordinary per-record edit. This is
the *only* new permission this reconciliation pass adds. Every other 4C
terminology gap reviewed in the same pass — `contact:qualify`,
`contact:score_override`, `contact:force_convert`, and `crm:admin` (4C's
name for the "delete another author's note" gate) — was found *not* to
cross the bar for a new permission: `contact:force_convert` and
`contact:score_override` gate capabilities 6G does not expose at all in
this revision (deferred, not implemented); `contact:qualify` is
adequately served by the existing `contact:write`, matching this
document's own established pattern of consolidating fine-grained DDD
policy language into a coarser, already-sufficient permission where no
real least-privilege gap results; and `crm:admin`'s single exposed use
(non-author human note deletion) is already conservatively restricted at
the application layer to `OWNER`/`ADMIN` role membership, which is at
least as strict as a dedicated permission would be. See
`6G-CRM-Leads-APIs.md` §5/§39 for the full per-item classification this
conclusion is drawn from.

Live-validated (disposable local PostgreSQL 18 database, full chain
`001_5B` → `096_5B2`): the new permission row inserts idempotently,
attaches to `OWNER`/`ADMIN` only via `organization.role_permissions`, and
a second application of the same migration is a no-op (`ON CONFLICT DO
NOTHING` on both the permission and role-permission inserts).

---

## Controlled Amendment — Phase 6L Freeze-Gate Remediation (2026-09-03)

Migration `104_5B3.sql` adds two new permissions to the catalog in
§17/§32: `recording:access_media` (`'Access Recording Media
(Playback/Download)'`, resource `recording`, action `access_media`) and
`transcript:access_content` (`'Access Transcript Content'`, resource
`transcript`, action `access_content`), both granted to `OWNER` and
`ADMIN` only. Purely additive — `007_5B.sql`'s existing rows are
untouched.

**Post-`104_5B3` canonical meaning — this is a correction to how this
document must be read, not a new capability being introduced for the
first time:**

| Permission | Governs |
|---|---|
| `recording:read` (unchanged, `007_5B.sql`) | Recording **metadata only** — existence, status, duration, file size, retention/policy fields. **Never** the audio content itself. |
| `recording:access_media` (new, `104_5B3.sql`) | The recording's actual audio — specifically, the capability to obtain a signed, time-boxed playback/download URL (6D §16.2). |
| `transcript:read` (unchanged, `007_5B.sql`) | Transcript **metadata only** — status, segment count, completion timestamp. **Never** the transcript text itself. |
| `transcript:access_content` (new, `104_5B3.sql`) | The transcript's actual segment text content (6D §17.3). |

Prior to this amendment, this document's §17.1 resource/action catalog
and §17.2 role-permission matrix listed only `recording:read`/
`recording:delete`/`transcript:read` with no metadata/content
distinction — which, read literally, implied `recording:read`/
`transcript:read` governed the recording's audio and the transcript's
text directly. That was never correct as a security boundary once 6D's
own contract (amended in the same remediation pass) started gating the
actual playback/content endpoints separately, and this document is
corrected here to state the post-`104_5B3` boundary explicitly, closing
that gap. **Trigger:** `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md`
§16.2a/§17.4 and `docs/phase-06-api-design/6L-Analytics-Audit-APIs.md`
§56.5 — the confirmed RBAC contradiction where `007_5B.sql`'s single
`recording:read`/`transcript:read` permissions, granted by default to
`MEMBER` and `VIEWER` as well as `OWNER`/`ADMIN`, could not express the
owner-approved sensitive-media policy (recording playback/transcript
content = OWNER/ADMIN by default; MEMBER only via an explicit
tenant-created custom role; VIEWER and BILLING_ADMIN never).

**§17.1 resource/action catalog, corrected:**

```
recording      read, delete, access_media
transcript     read, access_content
```

**§17.2 role-permission matrix, corrected (new rows; existing
`recording:read`/`recording:delete`/`transcript:read` rows are
unchanged — same grant set as originally seeded):**

| Permission | OWNER | ADMIN | MEMBER | BILLING_ADMIN | VIEWER |
|---|---|---|---|---|---|
| `recording:access_media` | ✅ | ✅ | — (custom role only) | — | — |
| `transcript:access_content` | ✅ | ✅ | — (custom role only) | — | — |

`recording:read` and `transcript:read` remain exactly as originally
seeded (`✅ OWNER, ✅ ADMIN, ✅ MEMBER, — BILLING_ADMIN, ✅ VIEWER`) — this
amendment does not narrow, widen, or otherwise touch their grant set;
ordinary call/report metadata visibility for MEMBER and VIEWER is fully
preserved, exactly as the owner-approved policy requires.

**MEMBER extension path (no schema change beyond `104_5B3` itself):** a
tenant's own `OWNER`/`ADMIN` may create a tenant-scoped custom role
(`organization.roles` with `organization_id` set and `is_system = FALSE`
— already fully supported since `003_5B.sql`/`007_5B.sql`, `role:manage`
permission) and assign it either or both of the new permissions via
`organization.role_permissions`, then add a specific `MEMBER`-tier user
to that role. This is the exact, and only, way a MEMBER may obtain
sensitive-media access under the owner-approved policy — there is no
system-role toggle for it, by design.

Live-validated (disposable local PostgreSQL 18.6 database, both a fresh
full chain `001_5B` → `104_5B3` and a genuinely separate chain pinned at
`102_5H2` before continuing to `104_5B3`): the two new permission rows
insert idempotently, attach to `OWNER`/`ADMIN` only via
`organization.role_permissions`, `MEMBER`/`VIEWER`/`BILLING_ADMIN`
receive neither by default, and a tenant custom role can be granted
`recording:access_media` and successfully used to extend access to a
specific `MEMBER`-tier user with no further schema change. Full raw
evidence: `docs/phase-05-database-design/5K/execution_logs/` (files
prefixed `20260903T000000Z_6L_`) and
`docs/phase-05-database-design/5K/validation/6L_FINAL_FREEZE_GATE_VALIDATION_REPORT.md`.
