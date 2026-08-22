# 6B — Authentication and Authorization API

## 1. Document Control

| Field | Value |
|---|---|
| Document ID | 6B |
| Title | Authentication and Authorization API |
| Phase | 6 — API Design |
| Depends on (frozen, upstream) | Phase 1 SRS, Phase 2 HLA, Phase 3 LLD (3A–3F), Phase 4 DDD (4A, 4H, 4I), Phase 5 DB Design (5A–5J), Phase 5K Migration & Validation, **6A — API Architecture and Standards** |
| Status | See §38 — Final Approval Status (multi-dimension status model: architecture / API contract / security design / implementation readiness are tracked separately, not collapsed into one label) |
| Author | karthi (karthimadan2003@gmail.com) |
| Date | 2026-08-21 |
| Revision | Final Correction and Pre-Closure Pass — 2026-08-22. Applied explicit user decisions on break-glass retention, MFA recovery deferral, and audit-extension deferral; corrected the design-completeness-vs-implementation-readiness status contradiction; added a Future/Upstream Dependencies register (§36.3); rebuilt §34's implementation-readiness matrix; no architectural redesign performed. |
| Path note | The originating task specification named the target path as `docs/phase-06-api-design/Phase-06-API-Design/6B-Authentication-and-Authorization-API.md`. A repo-wide inventory (`find docs -type f -name "*.md"`) confirmed every other phase document — including 6A — lives flat inside its phase folder, with no `Phase-06-API-Design/` subfolder anywhere in the repository. This document is therefore written to the flat path `docs/phase-06-api-design/6B-Authentication-and-Authorization-API.md`, matching 6A's location and the repo-wide convention. This is a deliberate path-normalization decision, not a silent deviation, and is recorded here per this task's own "identify conflicts explicitly" principle. |
| Hard boundary | This document designs **only** the Authentication and Authorization API. It does not modify Phase 5 (frozen), does not modify 6A (frozen), and does not begin 6C or any business-domain API (Voice, Calls, AI Agents, Knowledge, CRM, Leads, Campaigns, Workflow, Integrations, Webhooks, Billing, Analytics). |

---

## 2. Purpose

This document defines the complete external and internal API surface for **authentication** (establishing who a caller is) and **authorization** (determining what an authenticated caller may do), for the ai-voice-agent platform. It covers:

- User authentication (registration, login, logout, credential and email/phone verification, password reset, MFA)
- Token issuance and lifecycle (access token, refresh token, internal service token)
- Session management (list, revoke, forced logout)
- API key issuance and lifecycle (organization-scoped, programmatic access)
- OAuth2 SSO account linking (login-flow shape only — protocol/IdP specifics deferred, see ADR-6B-07)
- RBAC authorization model, permission evaluation pipeline, and role catalog management
- Multi-tenant identity resolution and cross-tenant isolation at the API layer
- Platform-admin authenticated/authorized access, including break-glass cross-tenant access
- Internal service-to-service authentication (per ADR-6A-09, applied here, not redecided)
- WebSocket connection authentication (per ADR-6A-05, applied here, not redecided)
- Security-sensitive error behavior, rate limiting, audit events, and observability for all of the above

Every capability defined here is traced to an approved architecture artifact (Phase 1–5, or 6A). Where the approved architecture does not yet define a capability that a SaaS platform commonly has (CAPTCHA, adaptive step-up, SAML/OIDC IdP specifics, phone OTP, session device fingerprinting, MFA backup codes), this document does **not** invent one — it documents the gap explicitly, either as a new ADR-6B-xx or as a stated limitation, per §36.

---

## 3. Scope

### 3.1 In scope

Authentication, token lifecycle, session management, API keys, internal service auth, RBAC authorization evaluation, role/permission catalog (read + custom-role definition), tenant isolation at the API layer, platform-admin authenticated access and break-glass, WebSocket connection authentication, and all audit/observability/rate-limiting/error-handling concerns for the above.

### 3.2 Explicitly out of scope

- **Organization/membership management** (inviting a user into an org, listing an org's members, changing a member's role assignment, removing a member, team management) — these mutate `organization.memberships` / `organization.teams`, which is the **Organization** bounded context (4A), not Identity or Authorization. They belong to an Organization Management API design, not this document. The one exception is **invitation acceptance** (`POST /api/v1/auth/invitations/accept`), which is retained here because it is a credential/token-redemption flow that creates a session — mechanically identical to email verification and password reset, and reuses the same `identity.password_reset_tokens` table (5B §22, `purpose='INVITATION'`).
- **Role catalog membership assignment** — assigning a `role_id` to a `Membership` row is an Organization-context mutation (out of scope here). Defining what a role *is* (its permission set) is Authorization-context and **is** in scope (§15, §20).
- All business-domain APIs: Voice, Calls, AI Agents, Knowledge, CRM, Leads, Campaigns, Workflow, Integrations, Webhooks, Billing, Analytics. None are designed, referenced as endpoints, or altered here.
- Any change to Phase 5 DB objects, RLS policies, migrations, or bounded-context boundaries. Where a requirement in this document appears to need one, it is called out explicitly (§36) rather than actioned.
- Any change to 6A's frozen API standards (envelope, versioning, error contract shape, pagination, idempotency, latency tiers, OpenAPI generation approach). This document consumes 6A's standards; it does not amend them.
- Phase 6C or any other Phase 6 sub-phase.

---

## 4. Governing Documents

| Document | Role for this document |
|---|---|
| Phase 1 SRS | `FR-AUTH-001..005`, `FR-TEN-001..005`, `NFR-SEC-001..008`, `NFR-PERF-001..002`, `NFR-COMPAT-001` — see §31 traceability |
| Phase 2 HLA | Container-level AuthN/AuthZ statement (§7.9); explicitly defers "detailed RBAC matrix, token lifecycle, MFA flows, threat model" to a later phase (HLA §8, Next Steps) — **this document is that later phase for the token/RBAC/MFA/threat-model portions** |
| Phase 3A Platform Architecture | `TenantContext` primitive, tenant-resolution middleware pattern, break-glass mechanics, illustrative `identity_access` module (explicitly marked illustrative, not authoritative for token/claims detail) |
| Phase 3B Voice Platform | Confirms Voice Gateway WS auth is call-setup-payload-based, not JWT-based — out of scope here (§18.4) |
| Phase 3E Platform Services | RBAC/Audit/API-key module structure; explicitly defers "OAuth2/SSO flow design" and "full RBAC permission string catalogue" to Phase 6 — **this document supplies the permission catalogue by citing 5B's authoritative seed data (§8), and defines the OAuth2 flow shape while deferring protocol specifics (ADR-6B-07)** |
| Phase 3F Deployment Internals | Secret rotation policy for JWT signing keys (90 days) and internal-service HMAC/signing keys (180 days) — binding inputs to §10 |
| Phase 4A Core Domains (DDD) | `User`, `ApiKey`, `Organization`, `Membership`, `Role` aggregates; `PermissionEvaluationService`; `CheckPermission` OHS; platform-admin/break-glass modeling; explicitly confirms no `Session`, `OAuthIdentity`, or `ServiceAccount` aggregate exists in the domain model |
| Phase 4H/4I | Final bounded-context naming; system-role list (**superseded here — see ADR-6B-08**); compliance/audit `ActionKind` additions |
| Phase 5B Identity/Organization/Multitenancy/Security | **Authoritative, frozen DB schema** for `identity.*` and `organization.*` — the primary grounding source for this entire document (§6–§17) |
| Phase 5J Analytics/Audit Schema | **Authoritative, frozen** audit event schema, `action_kind` vocabulary, write-path function (`fn_insert_audit_event`) — grounding for §22 |
| Phase 5K Migration & Validation | Confirms 5B/5J migrated without drift; APPROVED/FROZEN/PRODUCTION BASELINE |
| **6A — API Architecture and Standards** | **Binding constitution.** Supplies: response envelope, error contract shape, versioning, pagination, idempotency, latency tiers, WebSocket standard (ADR-6A-05), internal service auth decision (ADR-6A-09), multi-tenant request-context chain (§23), security architecture baseline (§22 — 15-min access token, `vxa_` API key prefix, RLS as independent tenant-isolation layer), and the explicitly-named open item this document is required to close: R-8, auth-endpoint abuse step-up. |

**Noted inconsistency (not silently corrected):** 5B §30 attributes the audit-event schema to "Phase 5I"; the audit schema is actually built in the document self-titled Phase 5J (confirmed by 5J's own header and final-status section). This is a cross-reference typo in 5B's prose, not a schema conflict — flagged here per this document's own anti-silent-resolution rule, no action taken against frozen Phase 5 content.

**Noted inconsistency (resolved, see ADR-6B-08):** Phase 4A/4H's DDD narrative describes 9 system roles; Phase 5B's frozen seed DDL defines 5. The DB-frozen set is authoritative for this document.

---

## 5. Architectural Principles

1. **Authentication answers "who"; authorization answers "what."** They are evaluated as distinct pipeline stages (§9) and never conflated — a valid, unexpired token proves identity, never entitlement.
2. **Tenant identity is always server-derived, never client-supplied.** `organization_id` for authorization purposes comes only from a verified JWT claim or an `identity.api_keys` lookup (6A §23.2) — a client-supplied `organization_id` in a request body/query string is, at most, cross-checked for a `400`/`409` malformed-request report, never trusted for access decisions.
3. **Deny by default, fail closed.** Every authorization branch that cannot positively resolve to `ALLOWED` resolves to `DENIED`. Every failure of a dependency the authz pipeline needs (Redis, DB, signing-key service) fails the request closed, never open (§28).
4. **API authorization and Postgres RLS are independent, non-substitutable layers.** RLS (5A §16, 5B §16.4) is the last line of defense inside the database; API-layer authorization is defense-in-depth in front of it. Neither layer is designed to be sufficient alone, and this document does not weaken, bypass, or duplicate-as-a-replacement-for RLS.
5. **No token type is reused for a purpose it wasn't issued for.** Access, refresh, internal-service, and API-key credentials are structurally and semantically distinct (§10) and are rejected by every validator that isn't the one they were minted for.
6. **Minimum necessary claims.** Tokens carry identity and coarse authorization hints (role name) for cheap routing; they never carry a resolved permission set. Permission resolution is always re-evaluated server-side, per request, against current DB/cache state (§8, §16) — a stale token cannot grant stale access.
7. **No fabrication.** Where Phase 1–5 does not define a mechanism this document would otherwise need (CAPTCHA, phone OTP, MFA backup codes, IdP-specific SSO protocol, session device fingerprinting, a `SESSION_REVOKED` audit event type), this document says so explicitly (§36) rather than inventing schema, endpoints, or claims to paper over the gap.

---

## 6. Identity Model

Strictly derived from the frozen Phase 5 schema (5B) and the DDD aggregates that motivate it (4A). No entity below exists that isn't already in Phase 5.

| Concept | Backing Phase 5 object | Notes |
|---|---|---|
| **User** | `identity.users` | Global identity, not tenant-scoped itself. `status ∈ {PENDING_VERIFICATION, ACTIVE, SUSPENDED, DELETED}`. |
| **Organization** | `organization.organizations` | Tenant root. `status ∈ {ACTIVE, SUSPENDED, CANCELLED}`. Not RLS-protected (it *is* the RLS root — 5B §16.4). |
| **Membership** | `organization.memberships` | Join of User↔Organization, exactly one `role_id` per active membership (single-role model, not multi-role — see §16). `status ∈ {ACTIVE, SUSPENDED, REMOVED}`. Partial-unique on `(organization_id, user_id) WHERE status='ACTIVE'` — a removed user can be re-invited (new row). |
| **Role** | `organization.roles` | `organization_id IS NULL` ⇒ system role (5 seeded, §16); non-null ⇒ tenant-owned custom role. |
| **Permission** | `organization.permissions` | Platform-owned reference data, `resource:action` string format, 64 seeded (§16.2), not tenant-scoped, no RLS. |
| **Session** | `identity.sessions` | Backs refresh-token lifecycle and "list/revoke my sessions." Not modeled as a domain aggregate in 4A, but exists as a first-class table in 5B — this document treats it as authoritative (§13). |
| **API Key** | `identity.api_keys` | Organization-owned, not user-owned (`organization_id` FK; `created_by` records the issuing user). RLS-protected. |
| **OAuth Identity** | `identity.oauth_identities` | Links a `User` to an external IdP subject. `credential_ref` only (`secret_manager://...`) — no raw OAuth token ever persisted in Postgres. |
| **Service Principal** | Not a table — an unregistered principal type authenticated purely by internal-JWT signature (`service_id` claim), per ADR-6A-09. No `ServiceAccount` DB row exists or is needed. |
| **Platform Admin** | `organization.is_platform_admin()` session GUC + `app_platform_admin` DB role (BYPASSRLS) | Not a Membership role — a distinct actor type, per 4A DDR-4A-005 and 5B's DB-role mechanism (§17). |

### 6.1 `AuthenticationContext`

The server-side, request-scoped construct built by auth middleware after token/API-key validation. This is **not** the JWT payload verbatim — it is resolved and, where noted, augmented from cache/DB on every request.

```json
{
  "subject": "018f2c9e-2b0a-7c3e-9c1a-1a2b3c4d5e6f",
  "actor_type": "USER",
  "organization_id": "018f2c9e-3a1b-7d4f-ad2b-2b3c4d5e6f7a",
  "membership_id": "018f2c9e-4b2c-7e5a-be3c-3c4d5e6f7a8b",
  "role": "ADMIN",
  "permissions": ["contact:read", "contact:write", "campaign:read", "campaign:write"],
  "session_id": "018f2c9e-5c3d-7f6b-cf4d-4d5e6f7a8b9c",
  "auth_method": "PASSWORD",
  "token_id": "018f2c9e-6d4e-7a7c-df5e-5e6f7a8b9c0d",
  "request_id": "01930000-0000-7000-8000-000000000000"
}
```

Field notes:
- `subject`: `user_id` for `USER`, `api_key_id` for `API_KEY`, `service_id` for internal service principals.
- `role`: **singular**, not an array — `organization.memberships.role_id` is a single FK, confirming a one-role-per-membership model in the frozen schema (not multi-role). Sourced from the token's `role` claim but never trusted alone for authorization (see §16.4).
- `permissions`: resolved server-side per request from the `rbac:permissions:{organization_id}:{user_id}` Redis cache (5-min TTL, DB fallback on miss) — **never** taken from the token. Absent entirely for `SERVICE`/internal-JWT principals (internal routes use `service_id`/allow-list authorization, not RBAC permissions — §17).
- `auth_method` ∈ `{PASSWORD, OAUTH_<PROVIDER>, API_KEY, INTERNAL_SERVICE, PLATFORM_ADMIN}`.
- `token_id`: the token's `jti` — used for audit correlation and (for admin-forced revocation only) denylist lookups (§12.4).

---

## 7. Authentication Architecture

Authentication is a single middleware stage that runs before any handler, and before `TenantContext.set()` (3A §11.1). It accepts exactly one credential per request from a closed set:

| Credential | Header | Validated by |
|---|---|---|
| User access token (JWT) | `Authorization: Bearer <jwt>` | Signature (RS256, platform user-facing key), `exp`/`nbf`/`iss`/`aud`, `token_use=access` |
| API key | `Authorization: Bearer vxa_<prefix><secret>` (or `X-Api-Key`) | `identity.validate_api_key()` SECURITY DEFINER lookup by SHA-256(full key) |
| Internal service token (JWT) | `Authorization: Bearer <jwt>` on `/api/internal/v1/*` only | Signature (RS256, separate internal signing key), `token_use=internal` |
| WebSocket connect credential | Query param `?token=` or `Sec-WebSocket-Protocol` subprotocol (per ADR-6A-05) | Same validators as the access token or API key, applied at `CONNECTING → AUTHENTICATED` transition |

A request presenting no credential to a protected route fails with `401 AUTHENTICATION_REQUIRED` before any business logic or DB call. A request presenting a syntactically valid but expired/invalid/wrong-type credential fails with `401` (specific `code`, §22) — never a `200` and never a silent anonymous fallback.

Authentication never queries `organization.*` tables directly for a JWT-authenticated request — the organization is a **claim**, not a lookup (§9). It is looked up only for the API-key path, where `identity.validate_api_key()` is deliberately the one function permitted to resolve tenant identity before `TenantContext` exists (ADR-5B-005, referenced by 6A §23.2).

---

## 8. Authorization Architecture

Authorization is RBAC, evaluated fresh on every request after tenant resolution, never trusted from the token. Reused directly from 4A's `PermissionEvaluationService`, adapted to the frozen 5B schema (single role per membership, no `CustomPermissions` column — see ADR-6B-05):

```
evaluate(membership, role, organization, permission) -> ALLOWED | DENIED

1. membership.status != 'ACTIVE'      -> DENIED
2. organization.status != 'ACTIVE'    -> DENIED
3. permission ∈ role.permissions      -> ALLOWED
4. else                               -> DENIED
```

This is a pure function — no per-membership override step exists in the frozen schema (4A's `CustomPermissions` concept was DDD-aspirational only; `organization.memberships` has no such column — ADR-6B-05). The full evaluation pipeline, including where this function sits, is §16.

Authorization decisions are **never cached beyond the compiled-permission-set cache** (`rbac:permissions:{org}:{user}`, 5-min TTL) — no endpoint-level "was this exact request allowed" cache exists, and role/membership/org-state changes invalidate that cache immediately and explicitly (§23).

---

## 9. Tenant Isolation

### 9.1 Resolution chain (applies 6A §23 to this document's endpoints)

```
Request
  → Authenticate (§7)
  → Resolve organization_id
        JWT path: from the token's `organization_id` claim (set at login/refresh/org-switch time)
        API-key path: from identity.api_keys.organization_id (via validate_api_key())
        Internal path: from `on_behalf_of_organization_id` claim, if present; else no tenant context (platform-scoped call)
  → TenantContext.set(organization_id)               [3A §11.1 — raises if unset, never silently proceeds]
  → SET LOCAL app.tenant_id = '<organization_id>'     [start of DB transaction, 3A §11.2]
  → Resolve Membership (organization_id, user_id) — RLS now scopes this lookup
  → Resolve Role (membership.role_id)
  → Resolve compiled Permissions (Redis cache, §8)
  → Evaluate requested permission
  → Allow / Deny
```

### 9.2 Rules

- A client-supplied `organization_id` (body, query param, path segment on an org-scoped route) is **cross-checked**, never trusted: if it disagrees with the resolved tenant context, the request fails `400 VALIDATION_ERROR` (malformed/inconsistent request) — it is never silently substituted, and it is never used to widen access.
- **Switching organizations issues a new JWT** (5B-implied session-per-org-context model, consistent with 6A §23.2) — a single access token is scoped to exactly one `organization_id` for its lifetime; there is no multi-org token.
- **Cross-tenant resource access returns `404`, never `403`.** Confirming that a resource exists in another tenant is itself a disclosure (6A §22) — a `Membership`, `Role`, or `ApiKey` row outside the caller's `organization_id` is indistinguishable, from the response, from one that doesn't exist.
- **Platform-admin exception:** an authenticated `PLATFORM_ADMIN` actor may cross tenant boundaries only via the break-glass mechanism (§17.3), which explicitly sets `TenantContext` to the target tenant for a bounded, audited window — it does not bypass tenant resolution, it exercises it under a distinct, logged authorization path.
- **Service-to-service tenant context:** an internal-JWT-authenticated request carries `on_behalf_of_organization_id` only when the operation is genuinely tenant-scoped (e.g., a Worker processing a specific org's job); platform-scoped internal calls (health checks, cross-tenant maintenance jobs) carry no tenant claim and must not be routed through any org-scoped endpoint.
- **Tenant-aware caching:** every cache key this document defines is namespaced by `organization_id` (`rbac:permissions:{org}:{user}`, `rbac:role:{org}:{role_id}`) — no cache key is ever constructed without a tenant segment for tenant-scoped data (3A §11.2, "no call site can construct an unnamespaced key").
- **Tenant-aware logging:** every structured log line and audit event this document emits carries `organization_id` (nullable only for genuinely platform-scoped events, §22) and `request_id`.
- **Fail-closed guarantee (6A §23.3):** if tenant context is somehow unset when a handler runs, that is a `401`/`500` at the middleware boundary — never a silent, empty-result `200`.

---

## 10. Token Architecture

Four distinct credential types. None is a substitute for another; no validator accepts a token of the wrong `token_use`/type.

| | Access Token | Refresh Token | Internal Service Token | API Key |
|---|---|---|---|---|
| Format | JWT (RS256) | Opaque, `{session_id}.{secret}` (ADR-6B-01) | JWT (RS256, separate key) | `vxa_<prefix><secret>` |
| Purpose | Authorize API/WS calls | Obtain a new access token | Authorize internal (`/api/internal/v1/*`) calls | Authorize programmatic/partner API calls |
| Issuer (`iss`) | `https://auth.platform/user` | n/a (opaque) | `https://auth.platform/internal` | n/a |
| Audience (`aud`) | `platform-api` | n/a | `platform-internal-api` | n/a |
| Subject | `user_id` | n/a — session identified by embedded `session_id` | `service_id` | resolved via DB lookup, not embedded |
| Signing key | User-facing RS256 keypair | n/a (HMAC-verified server secret material, not a JWT) | **Separate** internal RS256 keypair (ADR-6A-09) | n/a — SHA-256 hash comparison |
| Lifetime | 15 minutes (6A §22 baseline, applied here) | 30 days, sliding via rotation (§12) | 5 minutes (design decision — short-lived per ADR-6A-09) | Optional `expires_at`, default none (org-controlled) |
| Rotation | Not rotated — reissued on refresh | Rotated on every use (§12.2) | Reissued per internal call by the calling service's SDK, not persisted | Manual — revoke + reissue only, no in-place rotation (5B: `KeyHash` immutable) |
| Revocation | Not individually revocable (stateless) — session revocation blocks further refresh; forced-revocation denylist for admin-triggered cases only (ADR-6B-02) | `identity.sessions.status = REVOKED` | Not revocable individually — short TTL is the control; compromised signing key is rotated (180-day policy, 3F §7.2) invalidating all outstanding | `identity.api_keys.status = REVOKED` |
| Storage (client) | Memory / short-lived, never `localStorage` recommended | `httpOnly` cookie (web) or secure storage (mobile/CLI) — never exposed to JS | Held only by the internal SDK, never client-facing | Held by the integrating system, never logged |
| Replay protection | `exp` + `jti` (denylist only for forced-revocation path) | Reuse/rotation detection (§12.2) | `exp` (5 min) + `jti`; internal-only network path bounds exposure further | `LastUsedAt` monitored, no built-in replay window (bearer-style, mitigated by TLS + IP/rate monitoring, §24) |
| Failure/audit behavior | `401`, `AUTH_FAILURE` (§22) | `401`, session revoked + audit on reuse detection | `401`, distinct internal-auth-failure log, **never** falls back to user-JWT validation | `401`, `API_KEY_AUTH_FAILURE` |

Signing algorithm decision (RS256 for both user-facing and internal JWTs, asymmetric, JWKS-distributable) is recorded as **ADR-6B-04** — Phase 1–5 does not specify an algorithm; this document supplies the decision since Worker and Voice Gateway (3A, separate deployables) need to verify tokens without holding a shared symmetric secret.

---

## 11. JWT Claims

### 11.1 Access token (user-facing)

| Claim | Required | Source | Notes |
|---|---|---|---|
| `iss` | Yes | Fixed | `https://auth.platform/user` |
| `sub` | Yes | `identity.users.id` | |
| `aud` | Yes | Fixed | `platform-api` |
| `exp` | Yes | Now + 15 min | |
| `iat` | Yes | Now | |
| `nbf` | Yes | Now | |
| `jti` | Yes | New UUIDv7 per issuance | Stored in `identity.sessions.access_token_jti` for the *current* access token of a session (informational — not looked up per request, §12.4) |
| `organization_id` | Yes | `organization.memberships.organization_id` at login/refresh/org-switch | |
| `membership_id` | Yes | `organization.memberships.id` | |
| `role` | Yes | `organization.roles.name` via `membership.role_id` | Coarse hint only — never authoritative (§8) |
| `actor_type` | Yes | Fixed `USER` | Matches 5J `actor_type` CHECK vocabulary |
| `session_id` | Yes | `identity.sessions.id` | For audit correlation |
| `auth_method` | Yes | Set at login | `PASSWORD` \| `OAUTH_<PROVIDER>` |
| `token_use` | Yes | Fixed | `access` — rejects any token minted for another purpose |

No permission array, no full role-permission expansion, no email/PII beyond `sub` — minimum necessary claims (§5.6).

### 11.2 Internal service token

`iss=https://auth.platform/internal`, `aud=platform-internal-api`, `exp` (now+5min), `iat`, `nbf`, `jti`, `service_id`, `on_behalf_of_organization_id` (optional), `token_use=internal`. Mirrors ADR-6A-09 exactly — no claim invented beyond what 6A already specified.

### 11.3 Stale-permission handling (explicit, per task requirement)

| Scenario | Token still says | Server behavior |
|---|---|---|
| Role's permission set changed | Old `role` name, unchanged | `role` claim ignored for authz; `rbac:permissions:{org}:{user}` cache invalidated synchronously on `role.permissions_updated` (§23) — next request re-resolves current permissions from DB |
| User's role assignment changed | Old `role` name | Same — permission cache invalidated on `ROLE_ASSIGNED`; token's `role` claim becomes cosmetically stale until next refresh, but grants nothing itself |
| Membership revoked/suspended | Token still unexpired | `PermissionEvaluationService` step 1 (§8) — `membership.status != 'ACTIVE'` — denies on next request regardless of token validity |
| Organization suspended | Token still unexpired | Step 2 (§8) — denies on next request |
| Access token itself revoked (forced logout) | n/a | Denylist check only for admin-forced revocation (ADR-6B-02); routine logout does not retroactively invalidate an outstanding access token (§12.4) |

The distinction the task asks for: **`role` is token-derived and advisory only; every `permissions` check is must-check-server-state, resolved fresh (subject to a 5-minute cache) on every request.**

---

## 12. Access Token Lifecycle

```
Login/Refresh → Issue (§11.1) → Use (every request, stateless verify) → Expire (15 min) → Refresh (§13) → Revoke (session-scoped, §12.4) → Logout (§12.5)
```

### 12.1 Issue

On successful login (§14) or successful refresh (§13), the server mints a new access token bound to the session's current `organization_id`/`role`/`membership_id`.

### 12.2 Use

Stateless verification: signature (RS256 public key), `exp`/`nbf`/`iss`/`aud`/`token_use`. No DB or Redis round-trip on the happy path — this is deliberate (6A latency budget, §27) and is the reason access tokens are short-lived (15 min) rather than long-lived-and-revocable.

### 12.3 Expire

At `exp`, the token is rejected (`401 TOKEN_EXPIRED`) by signature verification alone — no state to clean up.

### 12.4 Revoke — and whether logout invalidates an outstanding access token

**Explicit answer (required by task §9): No.** Logout (§12.5) and explicit session revocation (§13.4) mark the `identity.sessions` row `REVOKED`, which prevents any **future refresh** using that session — but the access token already issued for that session remains cryptographically valid, and is accepted by any resource server that only checks signature + `exp`, until its own natural expiry. This is an explicit, bounded trade-off (worst case exposure window = 15 minutes), not an overlooked flaw, and it is the reason the access-token TTL is kept short rather than the more common 30–60 minutes seen elsewhere.

For the one class of event where a 15-minute residual-validity window is unacceptable — **platform-admin-forced logout** (compromised account, break-glass response) — this document adds a narrow, explicitly-scoped **Redis denylist**: `auth:revoked_jti:{jti}` set with TTL = token's remaining lifetime, checked **only** on routes reachable from a platform-admin-forced-revocation trigger path (not on the normal per-request hot path, preserving the stateless-verification latency budget for ordinary traffic). This is a pure API/cache-layer addition — no Phase 5 schema change — recorded as **ADR-6B-02**.

### 12.5 Logout

`POST /api/v1/auth/logout` sets the caller's own `identity.sessions.status = REVOKED`. Audit: `USER_LOGOUT` (existing 5J action_kind). Does not affect other sessions belonging to the same user (§13).

### 12.6 Concurrent sessions

Not limited by this document — a user may hold multiple `ACTIVE` sessions (multiple devices) simultaneously; each is an independent `identity.sessions` row with its own refresh-token hash and `access_token_jti`. No maximum-concurrent-session cap exists in Phase 1–5; none is invented here (a rate-limit-style cap could be added later as a configurable policy, not a hard architectural decision this document needs to make).

---

## 13. Refresh Token Lifecycle

### 13.1 Format and the reuse-detection problem (ADR-6B-01)

`identity.sessions` has exactly **one** `refresh_token_hash` column per row — there is no token-family/history table in the frozen 5B schema. A naive "hash the presented token, look it up" design cannot distinguish "this token was already rotated out (possible theft)" from "this token never existed" once its hash has been overwritten by rotation — both look identical: no row found.

**Decision (ADR-6B-01):** the refresh token is structured as `{session_id}.{secret}`, where `session_id` is `identity.sessions.id` in cleartext and `secret` is a 256-bit random value. The server:
1. Parses `session_id` from the presented token (no DB hit yet).
2. Looks up the session row **by primary key** (`O(1)`, not by hash).
3. If no row, or `status != 'ACTIVE'`, or `expires_at < now()` → generic `401 INVALID_REFRESH_TOKEN`.
4. If found and active: compares `SHA-256(presented token)` to the stored `refresh_token_hash`.
   - **Match** → valid, proceed to rotation (§13.2).
   - **Mismatch** → the session exists but this specific token value is not the current one — i.e., an already-rotated-out (superseded) token was replayed. This **is** distinguishable from "unknown token" precisely because the session was found by ID. Treated as **reuse/theft** (§13.3).

This is a pure API-layer/token-format design decision — it requires no Phase 5 schema change, and is recorded as ADR-6B-01 rather than silently assumed.

### 13.2 Rotation

On every successful refresh: generate a new `secret`, compute its hash, `UPDATE identity.sessions SET refresh_token_hash = <new hash>, access_token_jti = <new jti>, last_seen_at = now()`. The `session_id` (and therefore the token's own identity) does not change — only the secret portion rotates. Return a new access token + a new refresh token (same `session_id`, new `secret`).

### 13.3 Reuse/replay detection and response

On a hash mismatch against a found, active session (§13.1 step 4): immediately set that session's `status = REVOKED` (hard-revoke, not just deny this request), and respond `401 REFRESH_TOKEN_REUSE_DETECTED`. This forces the legitimate user to re-authenticate, closing the window regardless of which of the two holders (attacker or legitimate client racing a rotation) is which — the standard rotation-family compromise response.

**Audit gap, explicitly documented (ADR-6B-06):** 5J's `action_kind` vocabulary has no `SESSION_REVOKED` or `TOKEN_REFRESH_REUSE_DETECTED` value (confirmed absent by direct inspection of the CHECK constraint and the full enumerated list in 5J §14.3). Per this document's hard boundary (§2), Phase 5 is not modified to add one. **Interim mitigation:** reuse-detection events are emitted as structured application logs and a dedicated Prometheus counter (`auth_refresh_reuse_detected_total`, §26) rather than into `audit.audit_events`, with the gap and a recommendation to extend the 5J vocabulary in a future migration recorded as an open item (§36).

### 13.4 Session-scoped revocation, forced logout, password reset implications

- **User revokes one other session:** `DELETE /api/v1/sessions/{session_id}` — same `status=REVOKED` update, scoped to sessions owned by the caller's own `user_id` (authorization rule: a user cannot revoke another user's session; an org admin does **not** automatically gain this ability — no such elevation exists in Membership/Role modeling, 4A confirms Session is not a Membership-scoped concept).
- **Platform-admin forced logout:** `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all` (§20) — revokes every `ACTIVE` session for a user; requires `PlatformAdminOnly` (§17), always audited (`ORG`-independent platform action).
- **Password reset:** on successful `POST /api/v1/auth/password/reset/confirm`, **all** existing sessions for that user are revoked as a side effect (standard "changing your password logs you out everywhere" behavior) — a deliberate design decision recorded here, not found explicitly in Phase 1–5 but directly implied by `NFR-SEC-008` (OWASP-ASVS alignment) and not in tension with any frozen schema.
- **Suspicious activity:** beyond reuse detection (§13.3), no automated anomaly-detection mechanism (impossible-travel, new-device challenge) exists in Phase 1–5; not invented here (§36).

---

## 14. Session Management

Backed by `identity.sessions` (5B), not RLS-protected (sessions belong to a `user_id`, which is not itself tenant-scoped — a user may hold sessions with different `organization_id` claims across separate login/org-switch events; only the JWT issued from a session is org-scoped, §9.2).

| Field | Exposed to owner? |
|---|---|
| `id` | Yes |
| `device_label` | Yes (user-set at login, not fingerprinted — no device-fingerprinting mechanism exists in 5B; `user_agent_hash` is stored hashed, not raw, and is **not** exposed via API — §22 PII rules) |
| `ip_address` | Yes, tagged `pii:network` (5B) — displayed to the owner only, never to another actor |
| `created_at`, `last_seen_at`, `expires_at` | Yes |
| `status` | Yes |
| `refresh_token_hash`, `access_token_jti` | **Never** exposed via any API response |

Endpoints: `GET /api/v1/sessions` (list, paginated per 6A cursor standard), `GET /api/v1/sessions/me` (the session the current access token belongs to, highlighted), `DELETE /api/v1/sessions/{session_id}` (revoke one, owner-only), `DELETE /api/v1/sessions` (revoke all except current — "log out other devices").

**Authorization rule (explicit, per task requirement):** a user cannot revoke another user's session under any circumstance via these endpoints. An org admin/owner does not gain session-control over other members through their Role — no code path in this document grants it, since `identity.sessions` carries no `organization_id` and Membership/Role never reference it. The only cross-user session control is the platform-admin forced-logout endpoint (§13.4, §17), which is a distinct, explicitly audited elevated action, not an RBAC permission any org-level role holds.

---

## 15. Authentication Methods

Only methods with a grounding in Phase 1–5 are designed. No social login beyond generically-shaped OAuth2, no passkeys/WebAuthn, no SMS OTP.

### 15.1 Password (primary method)

`identity.users.password_hash` (Argon2id, 5B §21), `password_changed_at`. Registration → `PENDING_VERIFICATION` until `email_verified_at` is set. Login requires `status = ACTIVE` (or, per product decision, `PENDING_VERIFICATION` with reduced scope — **not specified in Phase 1–5; this document requires full `ACTIVE` status for login, treating email verification as a hard gate**, consistent with `FR-AUTH-004`'s audit-everything posture and avoiding an unspecified "partial access" state).

### 15.2 OAuth2 SSO (per `FR-AUTH-001`)

`identity.oauth_identities` exists and grounds the *linking* data model (provider, `provider_subject`, `credential_ref` — no raw token stored). This document defines the generic authorization-code redirect shape:

```
GET  /api/v1/auth/oauth/{provider}/authorize   → 302 redirect to IdP
GET  /api/v1/auth/oauth/{provider}/callback    → exchanges code, upserts oauth_identities row, issues session
DELETE /api/v1/auth/oauth/{provider}           → unlink (sets status=UNLINKED), blocked if it is the user's only auth method and password_hash is NULL
```

**Explicitly deferred (ADR-6B-07):** which IdPs are supported, OIDC-vs-SAML, discovery-document handling, and claim-mapping rules are **not** specified anywhere in Phase 1–5 (3E §19 explicitly names this as deferred to "Phase 8"). This document defines only the endpoint shape and the DB interaction; provider-specific configuration is an implementation-time input, not an API-design decision this document can make without fabricating IdP choices.

### 15.3 MFA (per `FR-AUTH-005`, admin roles)

`identity.users.mfa_enabled` (boolean) and `mfa_secret_ref` (opaque `secret_manager://` pointer; the column comment itself names the mechanism as **TOTP**, 5B). Endpoints: `POST /api/v1/auth/mfa/enroll` (generates a TOTP secret, stores its reference, returns a provisioning URI/QR payload — **the raw secret is returned exactly once**, mirroring the API-key one-time-reveal pattern, §16.6), `POST /api/v1/auth/mfa/verify` (challenge-response, sets `mfa_enabled=true` on first successful verification, and is required as a second step after password on every subsequent login for that user), `DELETE /api/v1/auth/mfa` (disable, requires password re-entry).

**MFA recovery is intentionally deferred (ADR-6B-10).** This is a deliberate scope decision for this phase, not an oversight: no backup/recovery-codes table exists in 5B, and this document does not invent one, add a new MFA-recovery table, or modify Phase 5 to create one. The **current, temporary model** for this phase: losing the TOTP device with no backup code means account recovery requires an out-of-band, platform-admin-assisted flow (covered generically by §18's platform-admin authenticated-access model) — not a self-service endpoint. This is the retained interim mechanism, not a placeholder for something already built.

A robust, self-service MFA recovery mechanism is recorded as a **future security requirement** (§36.3, item 3), not designed or chosen here. Possible future mechanisms — listed only as non-exhaustive examples for a later phase to evaluate, none selected or committed to by this document — include: one-time recovery codes issued at enrollment, a verified secondary recovery channel (e.g., backup email/SMS), a stronger structured admin-assisted recovery workflow with its own audit trail, or passkey/hardware-backed recovery (WebAuthn). Choosing among these requires a Phase 5 schema decision this document's authority does not extend to.

### 15.4 Email verification / password reset / invitation acceptance

All three reuse `identity.password_reset_tokens` (`purpose ∈ {EMAIL_VERIFICATION, PASSWORD_RESET, INVITATION}`, 5B §22) — single-use, hashed at rest, `expires_at` enforced:

```
POST /api/v1/auth/email/verify                (token → sets email_verified_at, may transition PENDING_VERIFICATION → ACTIVE)
POST /api/v1/auth/email/verify/resend
POST /api/v1/auth/password/reset               (request — always 200, never confirms account existence, §19)
POST /api/v1/auth/password/reset/confirm        (token + new password → revokes all sessions, §13.4)
POST /api/v1/auth/password/change               (authenticated, current password required)
POST /api/v1/auth/invitations/accept            (token → activates the associated Membership, issues a session)
```

### 15.5 Phone verification — explicit gap

`identity.users.phone_e164` and `phone_verified_at` exist as columns, but **no OTP-delivery mechanism, no OTP table, and no phone-verification token flow exists anywhere in Phase 1–5** (confirmed absent by the 5B/5J research pass). This document does **not** design a phone-verification endpoint — recorded as **ADR-6B-09**, an explicit limitation, not an oversight.

---

## 16. API Key Architecture

### 16.1 Model

`identity.api_keys` — organization-owned (not user-owned), `created_by` records the issuing user, `scopes TEXT[]` (a subset of the issuer's permissions **at issuance time**, least-privilege — mirrors 4A's `ApiKeyPermissionsMustBeSubset` policy even though the DDD's `ApiKey` aggregate shape differs slightly from 5B's flatter column set; 5B is authoritative). RLS-protected (`rls_api_keys_tenant`).

### 16.2 Format

`vxa_<8-char-prefix><secret>` — `key_prefix` (exactly 8 chars, `CHECK length=8`) stored **plaintext** for display (`vxa_a1b2c3d4…`), full key hashed SHA-256 into `key_hash` (unique-indexed), raw key **never** persisted or returned again after creation.

### 16.3 Lifecycle

```
POST   /api/v1/organizations/{organization_id}/api-keys        → create, raw key returned once
GET    /api/v1/organizations/{organization_id}/api-keys        → list (prefix + metadata only)
GET    /api/v1/organizations/{organization_id}/api-keys/{id}   → metadata only
DELETE /api/v1/organizations/{organization_id}/api-keys/{id}   → revoke (status=REVOKED)
```

**No rotation endpoint** — 5B's `key_hash` is immutable by design (no UPDATE path is modeled); "rotation" is create-new + revoke-old, matching 4A's explicit invariant ("rotation = revoke + reissue, no in-place rotation").

### 16.4 Auth chain

`Authorization: Bearer vxa_...` → `identity.validate_api_key(SHA-256(key))` (SECURITY DEFINER, runs *before* `TenantContext` exists) → returns `(api_key_id, organization_id, scopes, status)` → `TenantContext.set(organization_id)` → scopes are treated as a **ceiling**, not a grant: the effective permission set for the request is `scopes ∩ (permissions the issuing user held at issuance)`, evaluated the same way as §8's `PermissionEvaluationService`, substituting the key's `scopes` array for a role's permission set. This preserves tenant isolation identically to the JWT path — an API key can never grant access outside its own `organization_id`.

### 16.5 Never returned after creation

The raw key value. Only `key_prefix`, `name`, `scopes`, `status`, `expires_at`, `last_used_at`, `created_at` are ever returned by list/get.

---

## 17. Internal Service Authentication

Applies ADR-6A-09 exactly — no redecision here.

- **Principal:** a named internal service (`service_id` claim), not a DB row — Worker, Voice Gateway, and any future internal caller of Core API.
- **Token:** short-lived (5 min, §10) RS256 JWT, signed with a key **separate** from the user-facing keypair, verified by the **same** auth middleware entry point but routed to a distinct validator by `token_use=internal`.
- **Issuance mechanism (explicit, since Phase 1–5 doesn't specify one):** there is no public HTTP endpoint that mints internal tokens on request. Each internal deployable holds its own signing capability (via the secret store, 3F §7.2, 180-day rotation) and mints its own token per outbound call through a shared internal-auth SDK/library — consistent with "verified by signature, not DB lookup, entirely within the API layer" (6A §23.4). This document does not invent a `/token` issuance endpoint, since doing so would imply a central token-minting service not described anywhere upstream.
- **Trust boundary:** `/api/internal/v1/*` routes accept **only** internal tokens; `/api/v1/*` routes accept **only** user/API-key credentials. Neither validator falls back to the other — an internal JWT presented at a public route is rejected exactly as any other invalid credential, and vice versa (§30 threat model, confused-deputy mitigation).
- **On-behalf-of:** `on_behalf_of_organization_id`, optional, present only for genuinely tenant-scoped internal calls (§9.2).
- **Audit:** internal-authenticated writes to `audit.audit_events` use `actor_type='WORKER'` (or `'SYSTEM'`/`'INTEGRATION'`/`'PLUGIN'` as appropriate — 5J's full 7-value CHECK constraint: `USER, API_KEY, SYSTEM, WORKER, PLUGIN, PLATFORM_ADMIN, INTEGRATION`). `fn_insert_audit_event` additionally **enforces at the DB level** that only sessions authenticated as `app_worker` or `app_platform_admin` may write a platform-scoped (`organization_id IS NULL`) audit event — a second, independent enforcement point beyond the API-layer check.
- **Failure behavior:** invalid/expired internal token → `401`, logged with `service_id` (if parseable) but never processed as a fallback anonymous or public-user request.

---

## 18. Platform Admin Security

### 18.1 Authentication and actor modeling

Not a Membership role (4A DDR-4A-005 confirmed, and 5B has no `PLATFORM_ADMIN` value in `organization.roles`). Modeled at the DB-connection level: `organization.is_platform_admin()` reads session GUC `app.is_platform_admin`, and the dedicated `app_platform_admin` Postgres role carries `BYPASSRLS`. The API layer authenticates a platform-admin human the same way as any user (password/OAuth2/MFA — MFA is **required**, not optional, for this actor class per the spirit of `FR-AUTH-005`), then, only after a distinct, separately-authorized elevation check, opens the DB connection under `app_platform_admin` and sets the session GUC — this is never automatic from a JWT `role` claim alone.

### 18.2 Authorization

`PlatformAdminOnly` policy (4A) gates every platform-admin-only endpoint listed here (§20). No RBAC permission string grants this — it is an actor-type check, not a permission check, evaluated as a distinct branch before the normal §8 pipeline runs.

### 18.3 Break-glass (not "impersonation" — 4A's ubiquitous-language table explicitly forbids that term)

**Retained in this phase, by explicit decision.** Break-glass cross-tenant access is a required capability of the platform-admin security model and stays in 6B's architecture. The canonical flow, applied consistently everywhere break-glass is described in this document (§9.2, §17.4 threat model, §21.4, §24, §29–§31, §34):

```
Platform Admin
  → Explicit target organization (path parameter, never inferred)
  → Explicit justification (required field, min length enforced)
  → Strong authentication (password/OAuth2 + mandatory MFA, §18.1)
  → Authorization (PlatformAdminOnly actor-type check, §18.2)
  → Time-boxed break-glass grant (bounded TTL, e.g. 1 hour default — configurable, not benchmarked)
  → TenantContext set to the target tenant for the grant's duration
  → Audited elevated operations (every action performed under the grant is attributable to the admin and the grant_id)
  → Automatic expiry (TTL lapse) or explicit release (early, admin-initiated)
```

```
POST /api/v1/platform-admin/organizations/{organization_id}/break-glass
     → grants the above; returns grant_id + expires_at
POST /api/v1/platform-admin/break-glass/{grant_id}/release
     → early release, or automatic at TTL expiry
```

**Two distinct things, not to be conflated:**
1. **The audit record of the grant/release action itself** — `BREAK_GLASS_GRANTED` / `BREAK_GLASS_RELEASED` are existing 5J `action_kind` values (§25). Writing these two audit events is written **synchronously** to `audit.audit_events` (not through the normal async audit pipeline) — this mirrors 4A's explicit risk-mitigation rationale ("audit not lost if async pipeline down") for exactly this one action class, and is the single documented exception to this document's otherwise-async audit posture (§22). This part is fully supported by the frozen Phase 5 schema today — no gap here.
2. **The grant's own lifecycle state** (which grants are currently active, their remaining TTL, enabling release-by-`grant_id`) — this has **no durable Phase 5 table**. It is API-contract-complete (§21.4) but only backed today by an interim, non-durable Redis record (`platform_admin:break_glass:{grant_id}`, §24). Redis here is temporary process state for enforcing the TTL and locating a grant to release, not an audit-grade or durable persistence layer — if Redis is lost, the *fact* that grants were opened and closed remains in `audit.audit_events` (item 1 above), but the *live* "is this grant still active" state does not survive independently of Redis. Durable grant-lifecycle persistence is tracked as an **upstream/future Phase 5.x dependency** (§36.3, item 1), not invented here and not assumed to already exist.

This distinction is the basis for §4's completeness-vs-readiness split: the break-glass **API design and security model are complete**; break-glass **durable implementation is conditional** on the future Phase 5.x grant table.

### 18.4 Explicitly not modeled

**Impersonation of an org-level user session** is not supported — 4A's `OQ-4A-02` ("Should a Platform Admin be able to impersonate an org-level session?") is open and unresolved upstream; this document does not resolve it and does not design an impersonation endpoint. Only read-oriented break-glass access and the forced-session-revocation action (§13.4) are in scope here.

---

## 19. WebSocket Authentication

Applies ADR-6A-05 exactly. This document does not redecide raw-WebSocket-vs-Socket.IO — that ambiguity (flagged as open in 3A Review Note 2 and 3B, and reflected in `TECH_STACK.md` listing Socket.IO under Frontend only) is treated as **already resolved upstream by 6A**: the backend is raw FastAPI WebSockets for every realtime channel platform-wide; any frontend Socket.IO client must speak to it as a plain WebSocket. That is a frontend-integration note, not a 6B decision, and is out of scope for further action here.

### 19.1 Scope

This section defines the **connection-authentication contract** that applies to every `/ws/v1/*` channel. It does not define or own any specific business channel (notifications, dashboards, etc. — those are business-domain concerns for a future phase) and it explicitly excludes the Voice Gateway's own call-audio WebSocket protocol, which is call-setup-payload-authenticated per 3B, not JWT-authenticated, and is owned by the Voice Pipeline domain.

### 19.2 Handshake

```
CONNECTING → AUTHENTICATED → BOUND → STREAMING → CLOSING → CLOSED     (6A §27, reused verbatim)
```

Credential transport (browsers cannot set arbitrary headers on the WS handshake): `?token=<access_token>` query param, or `Sec-WebSocket-Protocol` subprotocol header — same access-token or API-key validators as REST (§7), applied at `CONNECTING → AUTHENTICATED`. Tenant resolution identical to REST (§9). Every connection is bound to exactly one `organization_id` for its lifetime — no cross-tenant multiplexing on one socket (6A §27.4).

### 19.3 Mid-connection concerns

- **Token expiry mid-connection:** since the access token is short-lived (15 min) and a WS connection may live longer, the connection is held authenticated for its own session lifetime once `AUTHENTICATED` (no per-message re-verification) but is force-closed (`CLOSING → CLOSED`, code indicating re-auth required) at the earlier of (a) the access token's `exp`, or (b) session revocation detected via the heartbeat/presence-key mechanism (6A §27) — the presence key itself is tagged with the session's revocation status on write, so a revoked session's sockets are closed within one heartbeat interval, not left open indefinitely.
- **Revoked credentials:** handled the same way — a revoked session closes its associated WS connections at the next heartbeat check.
- **Reconnect:** client responsibility (exponential backoff+jitter, 6A §27), re-authenticates from `CONNECTING` again with a valid (possibly refreshed) access token.
- **Disconnect:** subscription-scoped channels re-verify RBAC permission on subscribe, not only at connect (6A §27.4) — a permission revoked mid-connection blocks the *next* subscribe/resubscribe, though (consistent with §19.3's no-per-message-reverification design) does not itself force-close an already-bound subscription mid-stream; this is the same bounded-exposure trade-off as §12.4, inherited from 6A rather than newly introduced here.
- **Rate limiting / connection limits:** 5 concurrent connections per source, NGINX-enforced (6A §27, unchanged); connection-*attempt* rate limiting (distinct from concurrent-connection count) is defined in §21.

---

## 20. Endpoint Inventory

35 REST endpoints, grouped by capability. Full per-endpoint contracts for the security-critical subset follow in §21; the remainder follow the same template (§21.0) and are fully specified by this table plus §21.0's shared rules — reading them as "apply the template" is deliberate scoping, not an omission, given the size of a fully-expanded 35-endpoint contract set.

### 20.1 Authentication (13)

| # | Method & Path | Purpose | Auth | Actor | Tenant scope | Permission | Rate limit | Latency tier (6A) |
|---|---|---|---|---|---|---|---|---|
| 1 | `POST /api/v1/auth/register` | Create a `PENDING_VERIFICATION` user | None | — | None | — | 5/hour/IP | Standard |
| 2 | `POST /api/v1/auth/login` | Password login → session + tokens | None (credentials in body) | — | Resolved from membership post-auth | — | 5/15min per email, 20/15min per IP | Standard |
| 3 | `POST /api/v1/auth/logout` | Revoke current session | Access token | USER | Own session | — | 60/hour | Fast |
| 4 | `POST /api/v1/auth/token/refresh` | Rotate refresh → new access+refresh | Refresh token (body/cookie) | USER | Own session | — | 30/hour/session | Fast |
| 5 | `POST /api/v1/auth/email/verify` | Consume verification token | Token (body) | — | — | — | 10/hour/IP | Standard |
| 6 | `POST /api/v1/auth/email/verify/resend` | Resend verification email | Access token or unauth+email | USER | Self | — | 3/hour/email | Standard |
| 7 | `POST /api/v1/auth/password/reset` | Request reset (always 200) | None | — | — | — | 3/hour/email, 10/hour/IP | Standard |
| 8 | `POST /api/v1/auth/password/reset/confirm` | Consume token, set new password, revoke all sessions | Token (body) | — | — | — | 10/hour/IP | Standard |
| 9 | `POST /api/v1/auth/password/change` | Change password (current required) | Access token | USER | Self | — | 10/hour/user | Standard |
| 10 | `POST /api/v1/auth/invitations/accept` | Consume invitation token, activate Membership, issue session | Token (body) | — | Target org (from token) | — | 10/hour/IP | Standard |
| 11 | `GET /api/v1/auth/oauth/{provider}/authorize` | Redirect to IdP | None | — | — | — | 20/hour/IP | Fast |
| 12 | `GET /api/v1/auth/oauth/{provider}/callback` | Exchange code, upsert identity, issue session | None (code in query) | — | Resolved post-exchange | — | 20/hour/IP | Standard |
| 13 | `DELETE /api/v1/auth/oauth/{provider}` | Unlink | Access token | USER | Self | — | 10/hour/user | Standard |

### 20.2 MFA (3)

| # | Method & Path | Purpose | Auth | Rate limit | Latency tier |
|---|---|---|---|---|---|
| 14 | `POST /api/v1/auth/mfa/enroll` | Generate TOTP secret, return provisioning URI once | Access token | 5/hour/user | Standard |
| 15 | `POST /api/v1/auth/mfa/verify` | Verify TOTP code (enrollment confirm, or per-login step-up) | Access token or partial-login state | 5/15min/user (lockout-style) | Fast |
| 16 | `DELETE /api/v1/auth/mfa` | Disable MFA (password required) | Access token | 5/hour/user | Standard |

### 20.3 Identity Context (1)

| # | Method & Path | Purpose | Auth | Rate limit | Latency tier |
|---|---|---|---|---|---|
| 17 | `GET /api/v1/auth/me` | Return current `AuthenticationContext` | Access token or API key | 300/min/user | Fast |

### 20.4 Sessions (4)

| # | Method & Path | Purpose | Auth | Rate limit | Latency tier |
|---|---|---|---|---|---|
| 18 | `GET /api/v1/sessions` | List own sessions (cursor-paginated) | Access token | 60/hour | Standard |
| 19 | `GET /api/v1/sessions/me` | Get session behind current token | Access token | 300/min | Fast |
| 20 | `DELETE /api/v1/sessions/{session_id}` | Revoke one owned session | Access token | 60/hour | Fast |
| 21 | `DELETE /api/v1/sessions` | Revoke all except current | Access token | 20/hour | Standard |

### 20.5 API Keys (4)

| # | Method & Path | Purpose | Auth | Permission | Rate limit | Latency tier |
|---|---|---|---|---|---|---|
| 22 | `POST /api/v1/organizations/{organization_id}/api-keys` | Create (raw key returned once) | Access token | `api_key:manage` | 10/day/org | Standard |
| 23 | `GET /api/v1/organizations/{organization_id}/api-keys` | List (metadata only) | Access token or API key | `api_key:read` | 60/hour | Standard |
| 24 | `GET /api/v1/organizations/{organization_id}/api-keys/{api_key_id}` | Get metadata | Access token or API key | `api_key:read` | 120/hour | Fast |
| 25 | `DELETE /api/v1/organizations/{organization_id}/api-keys/{api_key_id}` | Revoke | Access token | `api_key:manage` | 30/hour/org | Fast |

### 20.6 Authorization / RBAC Catalog (7)

| # | Method & Path | Purpose | Auth | Permission | Rate limit | Latency tier |
|---|---|---|---|---|---|---|
| 26 | `GET /api/v1/permissions` | Platform-wide permission catalog | Access token or API key | — (read-only, no tenant scope) | 60/min | Fast |
| 27 | `GET /api/v1/organizations/{organization_id}/roles` | List roles (system + custom) visible to org | Access token or API key | `role:read` | 60/min | Fast |
| 28 | `POST /api/v1/organizations/{organization_id}/roles` | Create custom role | Access token | `role:manage` | 20/hour/org | Standard |
| 29 | `GET /api/v1/organizations/{organization_id}/roles/{role_id}` | Get role detail | Access token or API key | `role:read` | 120/hour | Fast |
| 30 | `PATCH /api/v1/organizations/{organization_id}/roles/{role_id}` | Update custom role's permission set (blocked if `is_system`) | Access token | `role:manage` | 30/hour/org | Standard |
| 31 | `DELETE /api/v1/organizations/{organization_id}/roles/{role_id}` | Delete custom role (blocked if `is_system` or in use) | Access token | `role:manage` | 20/hour/org | Standard |
| 32 | `POST /api/v1/auth/authorize/check` | Explicit permission-check (exposes the `CheckPermission` OHS) | Access token or internal token | — (self-check only) | 300/min | Fast |

### 20.7 Platform Admin (3)

| # | Method & Path | Purpose | Auth | Permission | Rate limit | Latency tier |
|---|---|---|---|---|---|---|
| 33 | `POST /api/v1/platform-admin/organizations/{organization_id}/break-glass` | Grant time-boxed cross-tenant access | Access token | `PlatformAdminOnly` | 20/day/admin | Standard |
| 34 | `POST /api/v1/platform-admin/break-glass/{grant_id}/release` | Release grant early | Access token | `PlatformAdminOnly` | 20/day/admin | Fast |
| 35 | `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all` | Force-logout a user (all sessions) | Access token | `PlatformAdminOnly` | 50/day/admin | Standard |

All rate-limit figures are **configurable defaults**, not benchmarked production numbers (§23, per task's anti-fabrication rule).

---

## 21. Endpoint Contracts

### 21.0 Shared template (applies to every endpoint in §20)

Every endpoint's contract has: Purpose, Authentication, Authorization, Tenant Context, Request, Response, Errors, Rate Limit, Idempotency, Latency, Database, Cache, Audit, Security, Observability — using 6A's envelope (`{data, meta}` success / `{error}` failure), 6A's error object shape, and 6A's `request_id`/correlation propagation throughout. Detailed contracts below for the security-critical subset; all others follow this template directly from the §20 table plus the general rules in §7–§19.

### 21.1 `POST /api/v1/auth/login`

- **Purpose:** Exchange email+password for a session (access + refresh tokens).
- **Authentication:** None (this endpoint establishes it).
- **Authorization:** N/A.
- **Tenant Context:** None at request time — resolved from the user's memberships after credential verification; if the user belongs to more than one active organization, the response includes an organization-selection step (`requires_organization_selection: true`) rather than guessing.
- **Request:**
  ```json
  { "email": "user@example.com", "password": "••••••••" }
  ```
- **Response `200`:**
  ```json
  {
    "data": {
      "access_token": "eyJhbGciOiJSUzI1NiIs...",
      "refresh_token": "018f2c9e-....7f8a9b0c1d2e",
      "token_type": "Bearer",
      "expires_in": 900,
      "organization_id": "018f2c9e-3a1b-7d4f-ad2b-2b3c4d5e6f7a",
      "mfa_required": false
    },
    "meta": { "request_id": "01930000-0000-7000-8000-000000000000" }
  }
  ```
  If `mfa_enabled=true` on the user: `200` with `mfa_required: true` and a short-lived, scope-limited `mfa_challenge_token` in place of the real tokens — the real tokens are issued only after `POST /api/v1/auth/mfa/verify` succeeds.
- **Errors:** `401 INVALID_CREDENTIALS` (generic — covers both wrong password and non-existent email, never distinguished, §19); `403 ACCOUNT_SUSPENDED` (only after successful credential check, since this doesn't leak existence beyond what login inherently must); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 5/15min per email (post-normalization), 20/15min per IP — composite, not IP-only (§23).
- **Idempotency:** N/A (not a mutating resource-creation call in the 6A idempotency-key sense).
- **Latency:** Standard tier (p50 <150ms / p99 <500ms target, §27) — dominated by Argon2id verification cost, deliberately expensive.
- **Database:** `identity.users` (read), `identity.sessions` (insert), `organization.memberships` (read, to resolve `organization_id`/`role`).
- **Cache:** None on the write path; permission cache is warmed lazily on first authorized request, not at login.
- **Audit:** `USER_LOGIN` (success) / `USER_LOGIN_FAILED` (failure) — both existing 5J `action_kind` values.
- **Security:** Argon2id timing is inherently near-constant regardless of match/mismatch; failure response is identical for "no such user" and "wrong password"; `failed_login_count`/`last_failed_login_at` updated on `identity.users` for lockout accounting (§24).
- **Observability:** `auth_login_attempts_total{result}`, latency histogram.

### 21.2 `POST /api/v1/auth/token/refresh`

- **Purpose:** Rotate a refresh token for a new access+refresh pair (§13).
- **Authentication:** Refresh token only (no access token required — it may already be expired).
- **Authorization:** N/A (session-identity check only).
- **Request:** `{ "refresh_token": "<session_id>.<secret>" }`
- **Response `200`:** new `access_token`, `refresh_token`, `expires_in`.
- **Errors:** `401 INVALID_REFRESH_TOKEN` (not found / expired / wrong status); `401 REFRESH_TOKEN_REUSE_DETECTED` (hash mismatch against a found active session — §13.3, session force-revoked as a side effect of this response); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 30/hour per session.
- **Idempotency:** Explicitly **not** idempotent — each successful call rotates the token; a client that erroneously retries a *successful* rotation with the now-superseded token triggers reuse detection (§13.3) by design, which is the correct, intended behavior, not a bug to special-case away.
- **Latency:** Fast tier — single indexed PK lookup, no Argon2id cost.
- **Database:** `identity.sessions` (read by PK + update).
- **Cache:** None.
- **Audit:** Reuse detection → structured log + metric only (§13.3 gap, ADR-6B-06); routine rotation is not separately audited beyond metrics (high-frequency, low-security-value event by itself).
- **Security:** See §13.1–§13.3.
- **Observability:** `auth_token_refresh_total`, `auth_token_refresh_failures_total`, `auth_refresh_reuse_detected_total`.

### 21.3 `POST /api/v1/auth/authorize/check`

- **Purpose:** Expose the `CheckPermission` OHS (4A) directly, primarily for internal/frontend UI-gating use (e.g., "should I show this button").
- **Authentication:** Access token or internal service token.
- **Authorization:** Self-check only — a caller may only ask about its own resolved `AuthenticationContext`; no "check permission for another user" capability exists here (that would itself need to be permission-gated and isn't grounded in any upstream requirement).
- **Request:** `{ "permission": "campaign:write" }`
- **Response `200`:** `{ "data": { "allowed": true } }` — deliberately returns `200` with a boolean body even when `allowed: false` (this is a *query* about authorization, not the authorized action itself, so it does not itself return `403`).
- **Errors:** `401` (no valid credential); `400 VALIDATION_ERROR` (permission string not in the catalog).
- **Rate Limit:** 300/min/user.
- **Latency:** Fast tier — cache-hit path only touches Redis.
- **Database:** DB fallback only on cache miss (§8, §23).
- **Cache:** `rbac:permissions:{organization_id}:{user_id}`.
- **Audit:** Not audited individually (a read-only query, not a state-changing or security-decision action in itself — the actual gated action, when performed, is what gets audited).
- **Security:** Never reveals another actor's permissions; never reveals the full role→permission matrix (that's `GET /api/v1/organizations/{organization_id}/roles/{role_id}`, permission-gated separately).

### 21.4 `POST /api/v1/platform-admin/organizations/{organization_id}/break-glass`

- **Purpose:** Grant a time-boxed, audited, cross-tenant access window (§18.3).
- **Authentication:** Access token, actor must be `PLATFORM_ADMIN`.
- **Authorization:** `PlatformAdminOnly` — actor-type check, not an RBAC permission.
- **Tenant Context:** The *target* `organization_id` is the path parameter — explicitly cross-tenant by design, the one endpoint in this document where that is intentional and audited rather than denied.
- **Request:** `{ "justification": "Investigating billing dispute #4471, ticket JIRA-2291", "duration_minutes": 60 }`
- **Response `201`:** `{ "data": { "grant_id": "...", "organization_id": "...", "expires_at": "..." } }`
- **Errors:** `401`; `403 AUTHORIZATION_DENIED` (not a platform admin); `400 VALIDATION_ERROR` (missing/too-short justification, or `duration_minutes` outside allowed bound); `404 RESOURCE_NOT_FOUND` (target org doesn't exist — this is the one place a platform-admin-facing 404 is *not* concealing tenant existence from a tenant peer, since the actor is platform-scoped by definition).
- **Rate Limit:** 20/day/admin.
- **Idempotency:** `Idempotency-Key` supported (6A standard) — a retried grant request with the same key returns the original grant, not a second one.
- **Latency:** Standard tier.
- **Database:** New break-glass grant table is **not** designed here — no such table exists in frozen 5B/5J. **This is a genuine Phase 5 gap** (§36, recorded as a dependency, not silently worked around): grant state (active grants, their TTL, their justification text) needs persistent storage this document cannot invent into Phase 5. Until such a table exists, this endpoint's grant/release state is specified at the API-contract level only, backed by a Redis-resident grant record (`platform_admin:break_glass:{grant_id}`, TTL = `duration_minutes`) as an interim, non-durable mechanism — explicitly weaker than a DB-backed audit-grade record, and flagged as such.
- **Audit:** Synchronous write (§18.3) — the one exception to async audit in this entire document.
- **Security:** Every break-glass grant and release is independently auditable; no silent bypass.

---

## 22. Error Catalog

Uses 6A's frozen error envelope (§4, verbatim shape) exclusively — no second error format introduced.

| HTTP | `code` | Used for | Never reveals |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | Malformed request body, inconsistent client-supplied `organization_id` | — |
| 401 | `AUTHENTICATION_REQUIRED` | No credential presented on a protected route | — |
| 401 | `INVALID_CREDENTIALS` | Login: wrong password or unknown email | Which of the two it was |
| 401 | `TOKEN_EXPIRED` | Access token past `exp` | — |
| 401 | `INVALID_REFRESH_TOKEN` | Refresh token not found / wrong status / expired | Whether the token ever existed |
| 401 | `REFRESH_TOKEN_REUSE_DETECTED` | Hash mismatch against a found active session (§13.3) | — |
| 401 | `INVALID_API_KEY` | API key hash not found / revoked / expired | — |
| 401 | `MFA_REQUIRED` | Login succeeded on password, MFA step pending | — |
| 401 | `MFA_INVALID_CODE` | Wrong TOTP code | — |
| 403 | `AUTHORIZATION_DENIED` | Authenticated, permission check failed (§8, §17) | Internal permission-structure detail, other actors' roles |
| 403 | `ACCOUNT_SUSPENDED` | User/Membership/Organization not `ACTIVE` (post-credential-check only) | — |
| 404 | `RESOURCE_NOT_FOUND` | Cross-tenant resource reference (§9.2) — deliberately used **instead of 403** for tenant-boundary cases | Cross-tenant existence |
| 409 | `STATE_CONFLICT` | e.g., accepting an already-accepted invitation, disabling MFA that's already disabled | — |
| 422 | `IDEMPOTENCY_KEY_REUSE_MISMATCH` | Break-glass grant retried with same key, different body (6A standard) | — |
| 429 | `RATE_LIMIT_EXCEEDED` | Any §21/§23 limit breached | — |
| 5xx | `DEPENDENCY_UNAVAILABLE` / `INTERNAL_ERROR` | Redis/DB/signing-key failures (§28) | Stack traces, internal service names, `credential_ref`/`signing_secret_ref` values, SQL text |

Never returned as `200` on failure — every branch above returns its stated non-2xx status; there is no endpoint in this document that reports failure inside a `200` body.

---

## 23. Rate Limiting and Abuse Protection

All limits below are **configurable defaults**, not benchmarked production numbers, per this document's anti-fabrication rule (§2).

| Concern | Key | Default |
|---|---|---|
| Login | `email` (post-normalization) + `IP` composite, never IP-only | 5/15min per email, 20/15min per IP |
| Failed-login lockout | `identity.users.failed_login_count` | Soft lockout after 10 consecutive failures, auto-clears on next success or after 1 hour |
| Registration | IP | 5/hour |
| Password reset request | email + IP | 3/hour per email, 10/hour per IP |
| Refresh | session | 30/hour |
| MFA verify | user | 5/15min (lockout-style — 5 wrong codes locks the MFA step for 15 min, not the account) |
| API key creation | org | 10/day |
| Session list/revoke ops | user | 60/hour (list), 20/hour (revoke-all) |
| Role create/update/delete | org | 20–30/hour |
| WS connection attempts | source | 20/min (attempt rate) on top of the existing 5-concurrent cap (6A §27) |

**§13's explicit answer to 6A's R-8 (auth-endpoint abuse step-up):** confirmed, via the dedicated research pass, that **no CAPTCHA, adaptive-MFA-challenge, or bot-detection mechanism is specified anywhere in Phase 1–5**. This document does not fabricate one. **Decision (ADR-6B-03):** the interim, fully-grounded control is the composite identity+IP rate limiting and soft-lockout counters above, which *are* directly supported by existing schema (`identity.users.failed_login_count`/`last_failed_login_at`) and `NFR-SEC-007`. A CAPTCHA/adaptive-step-up layer is recorded as an explicit open item (§36) for a future phase, not designed here — this closes R-8 with a documented decision rather than leaving it silently unaddressed.

---

## 24. Caching

| Cache key | Contents | TTL | Invalidated on |
|---|---|---|---|
| `rbac:permissions:{organization_id}:{user_id}` | Compiled permission set for the membership | 5 min | `role_changed`, `role.permissions_updated` (invalidates all members holding that role), `custom_permission_granted/revoked` (not applicable — no such mechanism exists, ADR-6B-05), `apikey.revoked`, membership status change |
| `rbac:role:{organization_id}:{role_id}` | Role's permission list (used to serve §20.6 role-detail reads) | 5 min | Role update/delete |
| JWKS (public verification keys) | Both user-facing and internal signing keypairs' public halves | Long-lived, refreshed on rotation (90-day / 180-day per 3F §7.2) | Key rotation event |
| `auth:revoked_jti:{jti}` | Forced-revocation denylist entries only (§12.4) | = token's remaining lifetime | Self-expiring |
| `platform_admin:break_glass:{grant_id}` | Interim, non-durable grant state — Redis TTL only, not audit-grade persistence (§18.3, §21.4 — flagged as a future Phase 5.x dependency, §36.3 item 1) | = `duration_minutes` | Release or TTL expiry |

**Never cached:** individual authorization *decisions* per specific request (only the underlying compiled permission set is cached, evaluated fresh against the requested permission every time); raw credentials in any form; refresh-token or API-key hashes are read from DB directly, never cached (their lookup is already `O(1)` and caching a security-sensitive credential-verification path adds risk disproportionate to the latency saved).

**Redis is process-state/performance cache, never the audit or system of record.** Every Redis-backed entry above (including `platform_admin:break_glass:{grant_id}`) is disposable: losing it degrades performance or, for the break-glass key specifically, degrades an operational convenience (locating an active grant to release, enforcing TTL), but it is never the durable record that a login, revocation, or break-glass grant occurred — that durable record is `audit.audit_events` (§25) where a matching `action_kind` exists, or is an explicitly flagged future dependency where it does not.

---

## 25. Audit Events

**AUDIT RECORD != LOG != METRIC.** This section defines the audit semantics 6B *requires*, then states separately what the frozen 5J schema *currently persists*, and what remains a *future extension*. The three are not interchangeable, and this section does not let a log line or a counter stand in for a missing durable audit row.

Reuses 5J's existing `audit.audit_events` schema and `fn_insert_audit_event()` write path exclusively — no second audit system introduced, per this document's hard boundary. No migration is created and no `action_kind` is added to Phase 5 by this document.

**Tier 1 — Required audit semantics → current Phase 5 persistence (fully supported today):**

| This document's action | `action_kind` (5J) | `actor_type` | `organization_id` |
|---|---|---|---|
| Login success/failure | `USER_LOGIN` / `USER_LOGIN_FAILED` | `USER` | Resolved org, or `NULL` if pre-org-resolution |
| Logout | `USER_LOGOUT` | `USER` | Session's org |
| Registration | `USER_REGISTERED` | `USER` | `NULL` (pre-membership) |
| Email verified | `USER_EMAIL_VERIFIED` | `USER` | `NULL` |
| Password changed | `USER_PASSWORD_CHANGED` | `USER` | Caller's org context if present, else `NULL` |
| MFA enabled/disabled | `USER_MFA_ENABLED` / `USER_MFA_DISABLED` | `USER` | — |
| OAuth link/unlink | `OAUTH_LINKED` / `OAUTH_UNLINKED` | `USER` | — |
| API key created/revoked | `API_KEY_CREATED` / `API_KEY_REVOKED` | `USER` | Org |
| Invitation accepted | `MEMBER_JOINED` | `USER` | Org |
| Role created/updated/deleted, custom permission-set change | `ROLE_ASSIGNED` / `PERMISSION_CHANGED` (closest existing values — semantically adequate, not a gap) | `USER` | Org |
| Break-glass grant/release | `BREAK_GLASS_GRANTED` / `BREAK_GLASS_RELEASED` | `PLATFORM_ADMIN` | Target org (synchronous write, §18.3) |
| Internal-service authenticated action | `actor_type='WORKER'`/`'SYSTEM'`/`'INTEGRATION'`/`'PLUGIN'` as appropriate | matches caller | Per `on_behalf_of_organization_id`, or `NULL` |

**Tier 2 — Required audit semantics with no matching 5J `action_kind` today → future Phase 5.x audit-vocabulary extension (ADR-6B-06, §36.3 item 2):**

| This document's action | Current 5J mapping | Status |
|---|---|---|
| Platform-admin forced logout of a specific user | Closest existing value is `USER_LOGOUT`, but actor/target semantics differ (admin acting on another user, not the user acting on themself) — using it would misrepresent who performed the action | **Genuinely unmappable — requires new `action_kind`** |
| Session revoked (self-service, e.g. "log out this device") | No matching `action_kind` exists | **Genuinely unmappable — requires new `action_kind`** |
| Refresh-token reuse detected (`TOKEN_REFRESH_REUSE_DETECTED`) | No matching `action_kind` exists | **Genuinely unmappable — requires new `action_kind`** |

Per this document's hard boundary, Phase 5 is **not** modified here to add these three `action_kind` values, no migration is written, and this document does not pretend an existing value is an adequate substitute. Until the Phase 5.x extension lands, these three events are observable only via structured application logs and Prometheus counters (§26) — **that telemetry is a supporting, best-effort signal, not a durable audit record**, and does not satisfy FR-AUTH-004 for these three event kinds (§35). This is the one place in 6B's audit design that is API-design-complete (the requirement to audit these events is specified) but implementation-dependent on an upstream Phase 5.x change.

Audit structure (5J, unchanged): `actor{type, ref, name}`, `action_kind`, `resource{type, id}`, `outcome ∈ {SUCCESS, FAILURE, PARTIAL}`, `ip_address`, `user_agent`, `session_id`, `request_id`, `correlation_id`, `occurred_at`. Write-once — no role, including platform admin, has `UPDATE`/`DELETE` on `audit.audit_events` (5J §26, confirmed).

---

## 26. Observability

**Structured logs, metrics, and traces below are supporting telemetry — operational visibility, debugging, and alerting signals. They are not a substitute for, or equivalent to, the durable audit record defined in §25.** A metric counter can tell an operator that refresh-reuse events are occurring; it cannot answer "did user X's session get revoked, by whom, when, attributably" the way a durable `audit.audit_events` row can. Where §25 flags an event as lacking a durable `action_kind` today, the telemetry below is the best-effort interim signal for that event — not a claim that the event is durably audited.

Metrics (Prometheus, `platform_`-prefixed convention per 6A §25, `auth_` sub-namespace here):

- `auth_login_attempts_total{result}`, `auth_login_failures_total{reason}`
- `auth_token_refresh_total{result}`, `auth_token_refresh_failures_total{reason}`
- `auth_refresh_reuse_detected_total`
- `auth_authorization_denied_total{permission}`
- `auth_api_key_usage_total{organization_id}`
- `auth_session_revocations_total{trigger}` (self / password-reset / platform-admin / reuse-detected)
- `auth_websocket_auth_failures_total`
- `auth_mfa_verify_total{result}`
- p50/p95/p99 latency histograms per endpoint (§27)

Correlation: every log line and metric label carries `request_id` (6A entry-middleware assigned), and where applicable `actor_id`/`organization_id`/`trace_id` (OpenTelemetry span per request, per 6A §25).

**Never logged, under any circumstance:** raw passwords, raw access/refresh tokens, raw API keys, raw TOTP secrets, JWT signing key material, `mfa_secret_ref`/`credential_ref` values (the reference itself is safe to log; the secret it points to is never fetched into a log line). Enforced by the same PII-redacting `structlog` processor 6A already mandates platform-wide (strips `phone_number|email|token|password|secret`) — this document adds no exception to that filter.

---

## 27. Performance and Latency

Per 6A's latency tiers (Fast / Standard / Async), reasoned per stage rather than benchmarked (no load-test data exists yet — marked TARGET, not MEASURED):

| Stage | Budget (p50 / p99, TARGET) | Dominant cost |
|---|---|---|
| Access-token verification (stateless) | <2ms / <8ms | RS256 signature check only, no I/O |
| Permission check, cache hit | <5ms / <20ms | Redis round-trip |
| Permission check, cache miss | <25ms / <80ms | DB read (Membership⋈Role⋈Organization) |
| Login (Argon2id) | <150ms / <500ms | Deliberately expensive hashing — a floor, not a bug |
| Refresh (rotation) | <10ms / <40ms | Single PK lookup + update |
| API-key validation | <15ms / <50ms | `validate_api_key()` SECURITY DEFINER call, pre-tenant-context |
| WS handshake auth | <20ms / <70ms | Same as access-token/API-key path plus connection setup |
| Break-glass grant | <50ms / <150ms | Includes synchronous audit write (§18.3) |

**Resilience of the authz path under dependency failure** (task-required explanation): the hot path (stateless access-token verification) has **zero** runtime dependency on Redis or DB — it fails or succeeds on signature+`exp` alone, which is precisely why access tokens are stateless. The permission-check path depends on Redis with a DB fallback; a Redis outage degrades every request to the DB-fallback cost (§27 row 3) rather than failing outright, and a simultaneous DB outage triggers §28's fail-closed behavior rather than silently granting access. Signing-key‑service unavailability affects only key **rotation**, not verification (public keys are cached/distributed via JWKS, §24), so a transient signing-service outage does not stop request authentication.

---

## 28. Failure and Resilience

Fail-closed wherever security requires it (§5.3):

| Dependency down | Behavior |
|---|---|
| Redis (permission cache) | DB fallback (§27); if DB also unavailable, see below — never "assume allowed" |
| DB | `503 DEPENDENCY_UNAVAILABLE`, `retryable: true` — no request reaches authorization evaluation without the ability to resolve current Membership/Role/Organization state |
| Signing-key service / JWKS unavailable | New token *issuance* fails (`503`); *verification* of already-cached public keys continues to work until cache staleness exceeds the rotation window (§24) |
| Permission cache down (Redis) | See row 1 |
| Audit pipeline down (async) | Request still completes (audit is fire-and-forget except break-glass, §18.3) — but this is a monitored condition (`audit pipeline lag` alert), not silently ignored; break-glass, being synchronous, instead **fails the grant request** if the DB write itself fails, since that action's audit-or-it-didn't-happen guarantee is stronger by design |
| Clock skew | `nbf`/`exp` validation allows a small, explicit leeway window (30s) consistent with standard JWT practice; beyond that, tokens are rejected rather than accepted with unbounded skew tolerance |
| Token verification failure (malformed, wrong key, wrong `token_use`) | `401`, generic `code`, no detail on *why* verification failed beyond the `code` itself |
| Internal token expiry mid-call | `401 AUTHENTICATION_REQUIRED` on the internal route — calling service's SDK is responsible for reissuing before the 5-minute TTL lapses, not this document's concern beyond specifying the TTL |
| Org suspended mid-session | Access token remains signature-valid but every authorization check now denies at `PermissionEvaluationService` step 2 (§8) — effectively read/write-locked out without needing token-level revocation |

---

## 29. Threat Model

| Threat | Attack surface | Mitigation | Detection | Residual risk |
|---|---|---|---|---|
| Credential stuffing | `/auth/login` | Composite email+IP rate limit, Argon2id cost, soft lockout | `auth_login_failures_total` spike alerting | Distributed low-and-slow attempts under per-IP threshold (CAPTCHA/step-up not implemented — ADR-6B-03) |
| Brute force (password) | `/auth/login` | Same as above | Same | Same |
| Phishing | Outside API surface | N/A (client/UX concern) | — | Not mitigated by this document |
| Access-token theft (XSS) | Client storage | Documented recommendation: never `localStorage`; short (15-min) TTL bounds exposure | — | Client-implementation-dependent, outside API control |
| Refresh-token theft | Client storage / transport | `httpOnly` cookie recommendation, rotation, reuse detection (§13) | `auth_refresh_reuse_detected_total` | Theft before first use of a rotated-out token is undetectable by design (the schema constraint, ADR-6B-01) |
| Token replay | Network capture | TLS mandatory (`NFR-SEC-001`), short access-token TTL, `jti` denylist for forced-revocation cases | — | Replay within the 15-min TTL window on a captured, unrevoked token |
| Refresh reuse | Stolen rotated-out token | §13.3 — session hard-revoked on detection | Metric + structured log (audit gap, ADR-6B-06) | Legitimate user also logged out (accepted trade-off) |
| JWT forgery | Signature attack | RS256 asymmetric signing, private key never leaves signing service | — | Signing-key compromise (mitigated by 180-day rotation, 3F §7.2) |
| Signing-key compromise | Secret store breach | Rotation policy (90/180 days), separate keys per token type (user vs internal) limit blast radius | — | Window between compromise and rotation/detection |
| API-key leakage/replay | Client-side storage, logs, git commits | One-time reveal, prefix-only display thereafter, SHA-256 hash at rest, `last_used_at`/`last_used_ip` for anomaly review | Manual/analytics review of `last_used_ip` drift (no automated anomaly detection built) | No automated leaked-key detection (e.g., no GitHub secret-scanning integration specified) |
| Session hijacking | Stolen access token | Same as token theft above | — | Same |
| CSRF | N/A for Bearer-token `/api/v1` (6A §22, reaffirmed) | No ambient-cookie auth for the primary API surface | — | If a browser refresh-token cookie is introduced, `SameSite=Strict`+`httpOnly` is mandatory (6A carries this requirement forward) |
| XSS token theft | Client-side | See access-token-theft row | — | Same |
| WS hijacking | Connection takeover | Same credential/tenant binding as REST; heartbeat-based revocation check (§19.3) | — | Bounded by heartbeat interval |
| Tenant escape | Cross-org access attempt | Server-derived `organization_id` only (§9), RLS as independent second layer, `404` not `403` on cross-tenant refs | `auth_authorization_denied_total` | None identified beyond RLS/API-layer defense-in-depth already covering this |
| Privilege escalation | Role/permission manipulation | `role_permissions` RLS policy `FOR ALL USING(is_system=FALSE)` blocks modifying system-role permissions; `role:manage` gated | — | None beyond standard RBAC-bypass-via-bug class, mitigated by tests (§32) |
| Confused deputy | Internal token accepted on public route or vice versa | Strict `token_use`/audience separation, no fallback validator (§17) | Internal-auth-failure logs distinct from public-auth-failure logs | None identified |
| Service-token abuse | Compromised internal signing key | Short TTL (5 min) bounds blast radius; rotation policy | — | Same window-of-compromise limitation as user-JWT signing key |
| Org-ID tampering | Client-supplied `organization_id` in body/query | Never trusted for authz — cross-checked only, `400` on mismatch (§9.2) | — | None identified |
| Timing/enumeration | Login, password reset | Generic error messages, constant-shape responses (§19, §22) | — | Argon2id itself has a small timing difference for "user not found" (skip-hash short-circuit) vs "wrong password" (full hash) — **documented residual risk**, not eliminated, since always-hashing a random salt for non-existent users trades this off against added average-case latency; not resolved further here |
| Rate-limit bypass | Distributed IPs, API-key rotation | Composite identity+IP limiting reduces but does not eliminate | — | Same as credential-stuffing residual risk |

---

## 30. Security Invariants

1. No unauthenticated access to any protected route — verified before any handler runs.
2. Authentication success never implies authorization — every state-changing or data-returning operation re-evaluates permissions (§8).
3. `organization_id` for authorization purposes is always server-derived, never accepted from a client-supplied value (§9.2).
4. Cross-tenant access is always denied, and denial is disclosed as `404`, never `403` or any signal that confirms cross-tenant existence.
5. Authorization fails closed on every ambiguous or degraded-dependency state (§28).
6. Expired credentials (access token, refresh token, API key, internal token) cannot authenticate.
7. Revoked credentials cannot be used to obtain a new credential (a revoked session cannot refresh — §13.1).
8. API-key and refresh-token secrets are never stored in plaintext (SHA-256 hash only).
9. Raw tokens, raw API keys, and raw passwords are never written to any log line (§26).
10. Internal-service credentials cannot authenticate as a public user, and public-user credentials cannot authenticate as an internal service (§17, bidirectional, no fallback validator).
11. Every platform-admin elevated action is individually auditable (§18, §25) — no silent bypass exists for any break-glass or forced-revocation action.
12. Security-sensitive endpoints (login, password reset, MFA verify, refresh, API-key creation) are rate-limited by identity and/or IP, never left unbounded (§23).
13. Database-layer RLS remains an independent tenant-isolation boundary — this document's API-layer authorization is defense-in-depth in front of it, not a substitute (§5.4).
14. A stale `role` claim in an already-issued token cannot grant access beyond what the current, server-resolved permission set allows (§11.3).

---

## 31. Authorization Matrix

Roles are the 5 frozen system roles from 5B (§16); no invented role appears. `system` marks actor types that are not Memberships at all.

| Actor | Resource/Action | Required | Expected result |
|---|---|---|---|
| Unauthenticated | Any `/api/v1/*` protected route | — | `401 AUTHENTICATION_REQUIRED` |
| `VIEWER` (own org) | `GET /organizations/{own}/api-keys` | `api_key:read` | `200` |
| `VIEWER` (own org) | `POST /organizations/{own}/api-keys` | `api_key:manage` | `403 AUTHORIZATION_DENIED` (VIEWER lacks `api_key:manage`) |
| `MEMBER` (own org) | `GET /organizations/{own}/roles` | `role:read` | `200` |
| `MEMBER` (own org) | `POST /organizations/{own}/roles` | `role:manage` | `403` (MEMBER lacks `role:manage`) |
| `ADMIN` (own org) | `POST /organizations/{own}/roles` | `role:manage` | `201` |
| `ADMIN` (own org) | `PATCH /organizations/{other-org}/roles/{id}` | `role:manage`, tenant match | `404 RESOURCE_NOT_FOUND` (cross-tenant, not 403) |
| `OWNER` (own org) | `DELETE /organizations/{own}/roles/{system-role-id}` | `role:manage` + `is_system=false` guard | `409 STATE_CONFLICT` (system roles are protected, `trg_protect_system_roles`) |
| `BILLING_ADMIN` (own org) | `GET /organizations/{own}/api-keys` | `api_key:read` | `403` unless BILLING_ADMIN's seeded permission set includes `api_key:read` (per 5B §33.4 matrix — BILLING_ADMIN's set is billing/invoice-scoped, not `api_key:*`) |
| Any Membership actor, any role | `GET /sessions` for another user's `session_id` | — | `404` (owner-scoped lookup never matches another user's row) |
| API Key (`scopes=['contact:read']`) | `GET /organizations/{own}/roles` | `role:read` not in `scopes` | `403` (scope ceiling enforced, §16.4) |
| Internal service (`service_id=worker`) | `/api/v1/*` (public route) | n/a | `401` — internal token rejected on public routes (§17) |
| User access token | `/api/internal/v1/*` | n/a | `401` — user token rejected on internal routes (§17) |
| `PLATFORM_ADMIN` | `POST /platform-admin/organizations/{any}/break-glass` | `PlatformAdminOnly` | `201` (any org, by design) |
| `ADMIN` (own org, not platform admin) | `POST /platform-admin/organizations/{any}/break-glass` | `PlatformAdminOnly` | `403` — actor-type check, no RBAC permission can satisfy it |
| `PLATFORM_ADMIN` | `POST /organizations/{any}/api-keys` (ordinary tenant-scoped route) | Membership+role required | `403` — platform-admin status alone does not satisfy ordinary tenant RBAC; a platform admin acting on tenant data must go through break-glass (§18.3), not bypass RBAC silently |

---

## 32. Test Strategy

- **Unit:** `PermissionEvaluationService` (§8) — all four branches; refresh-token hash-match/mismatch/not-found branching (§13.1); TOTP verification.
- **Integration:** full login→refresh→logout lifecycle against a real (test) DB; RLS-scoped queries under `SET LOCAL app.tenant_id`.
- **Contract:** every endpoint in §20 against its §21.0 template (status codes, envelope shape, error `code` values).
- **Security / authz-matrix:** every row of §31, executed as an automated table-driven suite.
- **Tenant-isolation:** User A (org 1) cannot access org 2's roles/api-keys/sessions — asserts `404`, not `403`, and asserts the response body contains no signal distinguishing "doesn't exist" from "exists in another tenant."
- **Concurrency:** two simultaneous refresh calls with the same refresh token — exactly one succeeds, the other triggers reuse detection (§13.3), not a race that grants both.
- **Rate-limit:** login/refresh/reset endpoints hit their configured ceiling and return `429`, not silently degrade or 500.
- **Token-lifecycle:** access token accepted until `exp`, rejected after; refresh token rejected once its session is `REVOKED`.
- **Replay:** a captured, valid, unexpired access token replayed after logout is still accepted (§12.4's documented trade-off) — asserted as *expected* behavior, not a bug, with a companion test proving the forced-revocation denylist path *does* reject it when triggered via `PlatformAdminOnly` revoke-all.
- **WebSocket-auth:** connection with expired token rejected at handshake; connection whose session is revoked mid-stream is closed within one heartbeat interval (§19.3).
- **API-key:** revoked key rejected; expired key rejected; key with narrower `scopes` than the requested permission rejected (§16.4).
- **Failure-injection:** Redis unavailable → DB-fallback path exercised and asserted correct; DB unavailable → `503`, never a silent allow.
- **Performance:** p50/p95/p99 assertions against §27's TARGET budgets under a defined load profile (to be executed once implementation exists — this document specifies the test, not its result).

**Minimum explicit tests (task-mandated, all included above or listed for completeness):** User A cannot access Org B's resources (✓ tenant-isolation); no-permission user gets `403` (✓ authz-matrix); unauthenticated gets `401` (✓ contract); expired token rejected (✓ token-lifecycle); revoked session cannot refresh (✓ token-lifecycle); refresh reuse detected (✓ concurrency/replay); revoked membership loses access (✓ unit, `PermissionEvaluationService` step 1); suspended org blocked (✓ unit, step 2); platform-admin ops audited (✓ security, break-glass synchronous-audit assertion); internal service JWT cannot authenticate as public user and vice versa (✓ contract, §17 row in §31).

---

## 33. OpenAPI Readiness

Per 6A's approach (ADR-6A-06 — FastAPI-generated OpenAPI + vendor extension fields, no separate hand-maintained spec), this document supplies the semantics FastAPI's generator needs, not a hand-written spec:

- **Reusable schemas:** `AuthenticationContext` (§6.1), `Session`, `ApiKey` (create-response vs. list/get-response variants — the former includes the one-time raw key, the latter never does), `Role`, `Permission`, `ErrorResponse` (6A's frozen shape).
- **Security schemes:** `BearerAuth` (JWT, user-facing), `ApiKeyAuth` (`Authorization: Bearer vxa_...` or `X-Api-Key`), `InternalBearerAuth` (JWT, internal-only, restricted to `/api/internal/v1/*` paths in the generated spec via a distinct security requirement).
- **Auth flows:** OAuth2 authorization-code flow shape declared for `/auth/oauth/{provider}/*` (§15.2), with provider-specific `authorizationUrl`/`tokenUrl` left as implementation-time configuration, consistent with ADR-6B-07's deferral.
- **Authz metadata:** each endpoint's required permission (§20 tables) is expressible as a vendor extension (`x-required-permission`) for tooling/doc-generation purposes, mirroring 6A's existing vendor-extension pattern.
- No application code is included in this document — schemas and semantics only.

---

## 34. Implementation Readiness

**Reading this table:** "6B API status" is always about design/contract completeness (is the endpoint, schema, and behavior fully specified?). "Implementation status" is about whether it can be built *today* against the frozen Phase 5 schema without further upstream work. A row can be **DESIGN COMPLETE / CONTRACT COMPLETE** while its implementation status is **IMPLEMENTATION DEPENDENCY** or **BLOCKED** — that is not a contradiction, it is the point of splitting the columns (§4-equivalent correction, see §38).

| Area | Decision | Current Phase 5 support | 6B API status | Implementation status | Dependency | Notes |
|---|---|---|---|---|---|---|
| Authentication (password) | Argon2id, generic failure messaging | Full (`identity.users`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §15/§21 |
| Authorization | RBAC + permission-evaluation pipeline, deny-by-default | Full (5B roles/permissions tables) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §8, §9.1 |
| Tenant isolation | Server-derived `organization_id`, RLS as independent layer | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §9 |
| JWT | RS256, separate user-facing/internal keypairs, JWKS-distributed | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | JWKS distribution mechanism (operational, not schema) | §10–§11, ADR-6B-04 |
| Refresh tokens | `{session_id}.{secret}` rotating opaque, reuse detection | Full (`identity.sessions`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §13, ADR-6B-01 |
| Sessions | `identity.sessions` CRUD-style API | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §14 |
| API keys | `vxa_` format, scope-as-ceiling | Full (`identity.api_keys`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §16 |
| Internal service authentication | Per ADR-6A-09, applied unchanged | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | JWKS for internal keypair (operational) | §17 |
| WebSocket authentication | Per ADR-6A-05, applied unchanged | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | Heartbeat/presence-key revocation check | §19 |
| Platform admin (base authz) | DB-role + GUC mechanism (`app_platform_admin`, `is_platform_admin()`) | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §18.1–18.2 |
| Break-glass | Retained by explicit decision; canonical flow in §18.3 | **Action audit: full** (`BREAK_GLASS_GRANTED`/`RELEASED` exist in 5J). **Grant-lifecycle persistence: none** — no durable Phase 5 table | CONTRACT COMPLETE / SECURITY MODEL COMPLETE | IMPLEMENTATION DEPENDENCY (grant-lifecycle persistence only; the API contract, authz check, and grant/release audit are implementable today against the interim Redis mechanism) | Durable break-glass grant persistence — future Phase 5.x (§36.3 item 1) | §18.3, §21.4, §24 |
| Audit | Reuses 5J's `audit.audit_events` exclusively; two-tier semantics | Full for 12 of 15 event categories (§25 Tier 1); **no matching `action_kind`** for 3 (§25 Tier 2) | CONTRACT COMPLETE (audit requirement specified for every event, including the 3) | DESIGN COMPLETE for Tier 1; IMPLEMENTATION DEPENDENCY for Tier 2 (`SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout) | Authentication audit-vocabulary extension — future Phase 5.x (§36.3 item 2) | §25, ADR-6B-06 |
| MFA | TOTP enroll/verify/disable | Full (`identity.users.mfa_enabled`/`mfa_secret_ref`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §15.3 |
| MFA recovery | Intentionally deferred (ADR-6B-10) — current interim mechanism is platform-admin-assisted, out-of-band recovery only | No recovery-codes/backup table in 5B | Interim mechanism CONTRACT COMPLETE (generic platform-admin-assisted flow, §18); **robust self-service recovery NOT DESIGNED** | DEFERRED BY DESIGN — not a defect, a scoped-out decision for this phase | Robust MFA recovery mechanism — future security requirement (§36.3 item 3) | §15.3, ADR-6B-10 |
| OAuth/OIDC | Generic authorization-code flow shape only | `identity.oauth_identities` table exists; no IdP integration | CONTRACT COMPLETE (generic shape) | BLOCKED — IdP-specific configuration is Phase 8 scope | IdP selection/config, Phase 8 (§36.3 item 4) | §15.2, ADR-6B-07 |
| Phone verification | Not designed | `phone_e164`/`phone_verified_at` columns exist, no OTP-delivery mechanism | NOT DESIGNED | BLOCKED — mechanism/provider undefined upstream | OTP mechanism/provider — future phase (§36.3 item 5) | §15.5, ADR-6B-09 |
| Rate limiting | Composite identity+IP defaults, soft lockout | Full (`identity.users.failed_login_count` etc.) | CONTRACT COMPLETE | IMPLEMENTATION READY (defaults provisional, not load-tested) | Load-test validation of defaults | §23 |
| Observability | Metrics/logging/tracing per §26 | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §26 |
| Performance | Latency budgets, TARGET not MEASURED | — | DESIGN COMPLETE | IMPLEMENTATION READY (targets, not yet measured) | Load testing to convert TARGET → MEASURED | §27 |
| Error handling | 6A envelope, no new shape | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §22 |
| OpenAPI | FastAPI-generated per 6A, reusable schemas defined | — | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §33 |
| Testing | Strategy defined, 10 minimum tests specified | — | DESIGN COMPLETE | IMPLEMENTATION READY | Test-environment DB with RLS enabled | §32 |
| Custom permissions (per-membership) | Not implemented (ADR-6B-05) | No such column in frozen 5B `organization.memberships` | NOT DESIGNED | BLOCKED — out of this document's authority | Phase 5 schema change if ever prioritized (not in §36.3 — not currently requested) | ADR-6B-05 |
| Abuse step-up (CAPTCHA) | Deferred, rate-limiting is interim control | None | DEFERRED BY DESIGN | DEFERRED — no provider selected | CAPTCHA/adaptive-challenge provider — future phase (§36.3 item 6) | §23, ADR-6B-03 |

**Roll-up (feeds §4/§38's status model):** every row above is either IMPLEMENTATION READY or has its non-readiness traced to a named, upstream Phase 5.x/Phase 8 dependency in §36.3 — no row is "Blocked" for an undisclosed or unexplained reason.

---

## 35. Traceability

**Status vocabulary used below:** `PASS` (fully supported end-to-end today, no caveat), `DESIGN COMPLETE` (API/contract fully specified; implementation may still depend on operational, not schema, work), `IMPLEMENTATION DEPENDENCY` (design complete, but a concrete upstream Phase 5.x item blocks full implementation), `PARTIAL` (some sub-cases pass, others do not — sub-cases enumerated in Notes), `BLOCKED BY PHASE 5.x` (cannot be implemented without a future Phase 5 schema/data change this document does not make).

| Requirement | Architecture | Domain (4A) | Phase 5 capability | API (this doc) | Permission | Business rule | DB interaction | Audit event | Status |
|---|---|---|---|---|---|---|---|---|---|
| `FR-AUTH-001` (JWT + OAuth2 SSO) | HLA §7.9 | `User` aggregate | `identity.users`, `identity.oauth_identities` | §20.1 (login, oauth/*) | — | Generic-failure, no enumeration | `identity.users` read/insert | `USER_LOGIN`/`USER_LOGIN_FAILED` | PASS |
| `FR-AUTH-002` (RBAC, platform roles + custom) | HLA §7.9 | `Role` aggregate, `PermissionEvaluationService` | `organization.roles`, `.permissions`, `.role_permissions` | §20.6 | `role:read`/`role:manage` | System roles immutable (`trg_protect_system_roles`) | `organization.roles` CRUD | `ROLE_ASSIGNED`/`PERMISSION_CHANGED` | PASS (custom per-membership permissions out of scope, ADR-6B-05 — not part of this requirement's approved scope) |
| `FR-AUTH-003` (scoped API keys) | HLA §7.9 | `ApiKey` aggregate | `identity.api_keys` | §20.5 | `api_key:read`/`api_key:manage` | Scopes ⊆ issuer permissions at issuance | `identity.api_keys` CRUD | `API_KEY_CREATED`/`API_KEY_REVOKED` | PASS |
| `FR-AUTH-004` (audit every authn/authz decision) | — | `AuditEvent` aggregate | `audit.audit_events` | §25 (cross-cutting) | — | Write-once, no UPDATE/DELETE role | `fn_insert_audit_event()` | Tier 1 (12 event categories): full coverage. Tier 2 (`SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout): no durable `action_kind`, telemetry-only today | **PARTIAL** — DESIGN COMPLETE (the requirement to audit every event, including the 3 Tier-2 kinds, is specified); IMPLEMENTATION DEPENDENCY for the 3 Tier-2 event kinds pending the audit-vocabulary extension (§36.3 item 2). Not PASS: a durable audit record does not yet exist for those 3 kinds. |
| `FR-AUTH-005` (MFA for admin roles) | — | `MfaConfig` (deferred in DDD) | `identity.users.mfa_enabled/mfa_secret_ref` | §20.2 | — | Recovery: intentionally deferred (ADR-6B-10), not a gap in the base requirement | `identity.users` update | `USER_MFA_ENABLED`/`USER_MFA_DISABLED` | PASS for core TOTP enrollment/verification. MFA *recovery* is a separate, explicitly deferred concern (§36.3 item 3), tracked there rather than counted against this requirement. |
| `FR-TEN-001..003` (tenant isolation, org-scoped admin) | HLA §7.9, 3A §11 | `Organization`/`Membership` aggregates | RLS on `organization.*`/`identity.api_keys` | §9 (cross-cutting) | — | Server-derived `organization_id` | `SET LOCAL app.tenant_id` | — | PASS |
| `FR-TEN-004` (platform super admin, audited cross-tenant) | 3A §11.3 break-glass | Platform Admin (DDR-4A-005) | `app_platform_admin` DB role, `is_platform_admin()` | §18, §21.4 | `PlatformAdminOnly` | Time-boxed, justified, synchronous audit | Grant-lifecycle persistence — no durable Phase 5 table (§18.3, §21.4) | `BREAK_GLASS_GRANTED`/`RELEASED` (this part: PASS — durable and synchronous today) | **IMPLEMENTATION DEPENDENCY** — API design, authorization, and grant/release audit are DESIGN COMPLETE and implementable today; the durable grant-lifecycle persistence table is a future Phase 5.x dependency (§36.3 item 1). Not BLOCKED: the requirement is implementable end-to-end using the interim mechanism, just not yet with durable grant-state persistence. |
| `NFR-SEC-003` (RBAC/tenant isolation at all layers) | HLA §7.9 | — | RLS + `PermissionEvaluationService` | §8, §9 | — | Deny-by-default | — | — | PASS |
| `NFR-SEC-007` (rate limiting per tenant/API key) | SRS §4 | — | — | §23 | — | Composite identity+IP | — | — | PASS (defaults provisional, not load-tested — does not affect design-completeness status) |
| `NFR-SEC-008` (OWASP ASVS alignment) | SRS §4 | — | — | §19, §22 (no enumeration) | — | — | — | — | PASS |

Source does not define a formal requirement ID for: session management, refresh-token rotation/reuse-detection design, internal-service auth mechanics beyond ADR-6A-09, or WebSocket connection-auth mechanics beyond ADR-6A-05 — these are grounded directly in 6A's architecture decisions and the 5B/5J schema rather than a numbered SRS requirement, and are cited as such throughout §7–§19 rather than against a fabricated requirement ID. All are PASS by the same standard applied above.

---

## 36. ADRs and Open Questions

| ID | Title | Decision | Status |
|---|---|---|---|
| ADR-6B-01 | Refresh token format for session-bound reuse detection | `{session_id}.{secret}`, enabling reuse detection despite the single-hash-column schema, with no Phase 5 change | Decided |
| ADR-6B-02 | Access-token statelessness vs. forced-revocation denylist | Stateless for the normal path (bounded 15-min exposure); narrow Redis denylist only for admin-forced/break-glass-triggered revocation | Decided |
| ADR-6B-03 | Auth-endpoint abuse step-up (closes 6A's R-8) | CAPTCHA/adaptive-challenge deferred to a future phase (no provider/mechanism specified in Phase 1–5); composite identity+IP rate limiting + soft lockout is the interim, fully-grounded control | Decided (interim) |
| ADR-6B-04 | JWT signing algorithm | RS256 (asymmetric), separate keypairs for user-facing vs internal tokens, JWKS-distributed | Decided |
| ADR-6B-05 | Membership `CustomPermissions` (4A's `OQ-4A-04`) | Not implemented — `organization.memberships` has no such column in the frozen 5B schema; RBAC in this document is role-only, no per-membership permission override designed | Decided (resolves upstream open question by confirming it was never built) |
| ADR-6B-06 | Audit vocabulary gap for session-revocation/refresh events | `SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED` not in 5J's `action_kind` CHECK constraint; interim mitigation via structured logs + metrics; recommend a future 5J-extension migration | Decided (interim), **open dependency on Phase 5** |
| ADR-6B-07 | OAuth2/SSO protocol specifics | Generic authorization-code flow shape only; IdP selection, OIDC-vs-SAML, and claim mapping deferred to Phase 8 per 3E's own explicit deferral | Decided (deferred scope) |
| ADR-6B-08 | System role set — DDD (9 roles) vs. DB (5 roles) discrepancy | Phase 5B's frozen 5-role seed DDL (`OWNER, ADMIN, MEMBER, BILLING_ADMIN, VIEWER`) is authoritative; Phase 4A/4H's 9-role narrative is superseded/aspirational and is not used anywhere in this document's authorization matrix or endpoint design | Decided |
| ADR-6B-09 | Phone verification | Not designed — `phone_e164`/`phone_verified_at` columns exist, no OTP-delivery mechanism specified anywhere in Phase 1–5 | Decided (documented limitation) |
| ADR-6B-10 | MFA recovery | **Intentionally deferred, not merely undesigned.** Current TOTP MFA design (§15.3) is kept unchanged; no recovery-codes or backup table is added to Phase 5. The retained interim mechanism is platform-admin-assisted, out-of-band recovery (generic flow, §18). A robust, self-service recovery mechanism is a named future security requirement (§36.3 item 3) — future candidate mechanisms are listed there as non-exhaustive examples only, none selected by this document | Decided (deferred scope, ADR text intentionally does not choose a future mechanism) |

No ADR was created for trivial implementation details (e.g., exact JSON field naming, exact HTTP verb choice for a CRUD op) — only for genuine architectural gaps or upstream-conflicting decisions, per this document's own instruction not to over-produce ADRs.

### 36.3 Future / Upstream Dependencies Register

This register is the single authoritative list of everything 6B's design depends on that is **not yet built**. Its purpose is the opposite of a hidden-requirements list: every item here is explicitly named so that none of them can silently become a blocker to *this document's* architecture, contract, or security-model approval (§4, §38). A dependency being listed here means "6B's design accounts for this and names it," not "6B is incomplete until this exists."

| ID | Description | Why needed | Current status | Required phase | Requires Phase 5.x? | Blocks 6B architecture? | Blocks 6B implementation? |
|---|---|---|---|---|---|---|---|
| DEP-6B-01 | Durable break-glass grant-lifecycle persistence (target org, justification, TTL, granting admin, active/released state) | Break-glass grant/release *actions* are already durably audited (`BREAK_GLASS_GRANTED`/`RELEASED`, 5J); but the *live lifecycle state* of a grant (is it still active, remaining TTL) has no durable table — only an interim Redis TTL key (§18.3, §24) | API contract complete (§18.3, §21.4); interim Redis mechanism specified; no durable table exists | Future Phase 5.x | Yes | **No** | Yes — for durable grant-state persistence only; the API, authz, and action-audit are implementable today without it |
| DEP-6B-02 | Authentication audit-vocabulary extension: `SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout `action_kind` values | 5J's `action_kind` CHECK constraint has no matching value for these 3 event kinds; using an unrelated existing value would misrepresent the event (§25 Tier 2) | Audit requirement specified (§25); telemetry-only interim signal (§26); no schema change made | Future Phase 5.x | Yes | No | Yes — for these 3 event kinds only; all other audit events are fully supported today |
| DEP-6B-03 | Robust, self-service MFA recovery mechanism | Current interim mechanism (platform-admin-assisted, out-of-band) does not scale and is not self-service; a durable design requires a Phase 5 schema decision (e.g., a recovery-codes table) this document's authority does not extend to | Intentionally deferred (ADR-6B-10, §15.3); example future mechanisms listed, none selected | Future phase (Phase 5.x schema + 6B.x or 6C API work) | Yes (for most candidate mechanisms) | No | No — current interim mechanism is implementable today; this is a future security *enhancement*, not a blocker to today's design |
| DEP-6B-04 | OAuth2/OIDC provider-specific implementation (IdP selection, OIDC vs. SAML, claim mapping) | This document specifies only the generic authorization-code flow shape (§15.2); IdP integration is explicitly Phase 8 scope per 3E | Generic shape DESIGN COMPLETE; provider integration not designed | Phase 8 | No (Phase 8 work, not Phase 5) | No | Yes — for actual OAuth login with a real IdP; generic flow contract is complete today |
| DEP-6B-05 | Phone verification mechanism/provider (OTP delivery) | `phone_e164`/`phone_verified_at` columns exist in 5B, but no OTP-delivery mechanism or provider is specified anywhere in Phase 1–5 (§15.5, ADR-6B-09) | Not designed | Future phase | Possibly (provider integration, not necessarily schema) | No | Yes — phone verification cannot be implemented until a mechanism/provider is chosen |
| DEP-6B-06 | CAPTCHA / adaptive-challenge step-up for auth-endpoint abuse | Closes 6A's R-8 only via an interim control today (composite identity+IP rate limiting + soft lockout, ADR-6B-03); no CAPTCHA/bot-detection mechanism exists in Phase 1–5 | Deferred by design; interim control fully implementable today | Future phase | No | No | No — interim control is sufficient and implementable today; this is a future hardening option, not a current blocker |

**Reading the last two columns:** "Blocks 6B architecture?" is **No** for every item — none of these dependencies invalidate or block approval of 6B's architecture, API contracts, or security model, because each is explicitly named, scoped, and has an interim treatment (or, for DEP-6B-04/05, an explicit "not yet possible" status that doesn't contradict anything else in this document). "Blocks 6B implementation?" is **Yes** only for the specific implementation slice each item covers — never for 6B's overall implementation-readiness as a blanket label (see §4/§38's status model).

---

## 37. Acceptance Checklist

- [x] Full review scope covered: authentication, token lifecycle, sessions, credentials/MFA, API keys, internal/service auth, RBAC/authorization, tenant isolation, membership-adjacent boundary (invitation acceptance only), platform-admin authz, audit/security events, failure handling, rate limiting, revocation, expiry, error behavior, WebSocket authz.
- [x] No Phase 5 DB objects, RLS policies, or migrations modified.
- [x] No 6A content modified — consumed as a frozen constitution only.
- [x] No business-domain APIs (Voice/Calls/AI Agents/Knowledge/CRM/Leads/Campaigns/Workflow/Integrations/Webhooks/Billing/Analytics) designed or referenced.
- [x] No Phase 6C or other Phase 6 sub-phase content included.
- [x] Identity model strictly derived from approved Phase 1–5 architecture (§6) — no invented DB entities.
- [x] Multi-tenancy: server-derived `organization_id`, tenant resolution, membership validation, cross-tenant denial (404), platform-admin exception, service-to-service tenant context all defined (§9).
- [x] Token architecture: all four types fully specified with purpose/issuer/audience/claims/algorithm/lifetime/rotation/revocation/storage/transport/replay/failure/audit (§10–§11).
- [x] Access token lifecycle fully defined, including the explicit logout-vs-stateless-token-validity answer (§12.4).
- [x] Refresh token security: rotation, reuse detection, revocation, session binding all defined, with the schema-constraint limitation explicitly documented rather than papered over (§13, ADR-6B-01).
- [x] Session management: list/revoke one/all, authorization boundary (no cross-user revocation without platform-admin elevation) defined (§14).
- [x] Login flows limited to actually-supported methods (password, OAuth2-shape, MFA) — no fabricated OAuth/passkey/social detail beyond what 5B's schema grounds (§15).
- [x] Account security: enumeration avoidance, lockout, rate limiting defined; abuse-step-up gap (6A's R-8) explicitly closed via ADR-6B-03 rather than left open (§23).
- [x] API keys: full lifecycle, format, hashing, one-time reveal, scope-as-ceiling chain defined without breaking tenant isolation (§16).
- [x] Internal service auth: uses 6A's ADR-6A-09 exactly, no redecision, strictly separated from user auth bidirectionally (§17).
- [x] Authorization model: RBAC + permission evaluation pipeline + tenant membership + platform-level permissions, using only real roles/permissions from 5B (§8, §16, §31) — no invented permission strings.
- [x] Deterministic, fail-closed authz evaluation pipeline defined, with explicit behavior for every listed degraded-state scenario (§9.1, §28).
- [x] Platform admin: authz, tenant-boundary behavior, audit (including the one synchronous-audit exception), no silent bypass (§18).
- [x] WebSocket auth: applies ADR-6A-05 without redeciding it; connection lifecycle, token transport, mid-connection expiry/revocation, rate/connection limits defined; voice-call WS explicitly out of scope (§19).
- [x] Error contract: reuses 6A's frozen shape exactly; no account-existence, password-validity-detail, internal-permission-structure, or credential-material leakage (§22).
- [x] Exact HTTP status per endpoint/error branch defined; no blanket 200-on-failure anywhere (§20–§22).
- [x] Latency/performance budgets reasoned per stage, explicitly marked TARGET not MEASURED, with resilience-under-degradation explained (§27).
- [x] Caching: explicit cacheable/non-cacheable list, tenant-aware keys, explicit invalidation triggers (§24).
- [x] Rate limiting: identity/IP-composite (not IP-only) for every auth-sensitive endpoint, values marked configurable defaults (§23).
- [x] Audit strategy reuses 5J's existing vocabulary; every genuine vocabulary gap documented explicitly rather than misusing an unrelated `action_kind` (§25, ADR-6B-06).
- [x] Endpoint inventory (35 endpoints) determined from the actual repo/schema, not copied from generic SaaS assumptions (§20).
- [x] Consistent endpoint contract template applied; full detail given for the security-critical subset, template applied to the remainder with the scoping choice stated explicitly (§21).
- [x] Realistic, syntactically valid, tenant-safe, security-safe JSON examples aligned with 6A's envelope; no password/secret/signing-key values ever shown in an example (§21).
- [x] Threat model covers all task-listed threat categories in Threat→Surface→Mitigation→Detection→Residual-risk format (§29).
- [x] Failure/resilience covers all task-listed dependency-failure scenarios, fail-closed where security requires it (§28).
- [x] Observability: all nine task-named metrics present plus latency histograms, correlation fields, and the never-logged list (§26).
- [x] OpenAPI readiness: reusable schemas, security schemes, auth flows, authz metadata identified; no application code included (§33).
- [x] Implementation readiness matrix covers all task-named areas, statuses honestly marked using the DESIGN COMPLETE / CONTRACT COMPLETE / IMPLEMENTATION READY / IMPLEMENTATION DEPENDENCY / BLOCKED / DEFERRED vocabulary — no row silently blocked without a named dependency (§34).
- [x] Test strategy covers every task-listed test category, including all ten explicitly-mandated minimum tests (§32).
- [x] Authorization matrix uses only real actors/roles from 5B, covering platform admin, every system role, API key, internal service, and unauthenticated (§31).
- [x] Fourteen security invariants stated, each traceable to a concrete mechanism defined earlier in this document (§30).
- [x] Performance budget follows TARGET/MEASURED/UNKNOWN discipline — no fabricated benchmark numbers (§27).
- [x] Every unresolvable architectural gap recorded as an ADR-6B-xx (10 total) or an explicit future dependency (§36.3), not silently resolved.
- [x] Traceability chain (Requirement→Architecture→Domain→Phase 5→API→Permission→Rule→DB→Audit→Status) completed for every `FR-AUTH-*`/`FR-TEN-*` requirement, with an explicit Status column using PASS/DESIGN COMPLETE/IMPLEMENTATION DEPENDENCY/PARTIAL/BLOCKED BY PHASE 5.x (§35).
- [x] Final consistency audit performed (§38) — no contradictions, duplicate endpoint definitions, inconsistent status/token/claim/role/permission names, tenant-isolation bypasses, conflicting WS/internal-JWT semantics, references to nonexistent Phase 5 objects, stale TBD/review-required language outside the explicitly-flagged gaps, or fabricated performance numbers found.
- [x] **This correction pass's user decisions applied exactly:** break-glass retained (not redesigned, not removed) with durable persistence identified as a future Phase 5.x dependency, not invented and not silently assumed (§18.3, §36.3 item 1).
- [x] MFA recovery is explicitly labeled **intentionally deferred** (not "not designed," not silently absent) — current temporary model (platform-admin-assisted, out-of-band) stated as retained interim mechanism, not a placeholder; no recovery-codes table added to Phase 5; future mechanisms listed only as non-selected examples (§15.3, ADR-6B-10, §36.3 item 3).
- [x] Audit extension intentionally deferred — Phase 5's frozen audit architecture (5J) is unmodified; no migration created; no `action_kind` added; the 3 genuinely unmappable events are named individually rather than papered over (§25, §36.3 item 2).
- [x] AUDIT RECORD != LOG != METRIC is enforced throughout — §25/§26 explicitly state that structured logs and Prometheus metrics are supporting telemetry, not a substitute for a durable `audit.audit_events` row.
- [x] `FR-AUTH-004` no longer reads as an unqualified PASS — it is marked PARTIAL with the Tier 1 (durably audited) / Tier 2 (telemetry-only, pending extension) split stated explicitly (§35).
- [x] `FR-TEN-004` reflects the break-glass action-audit-vs-grant-persistence distinction rather than a single undifferentiated "gap" note (§35).
- [x] Implementation Readiness matrix (§34) rebuilt with the mandated row set (Authentication, Authorization, Tenant isolation, JWT, Refresh tokens, Sessions, API keys, Internal service authentication, WebSocket authentication, Platform admin, Break-glass, Audit, MFA, MFA recovery, OAuth/OIDC, Phone verification, Rate limiting, Observability, Performance, Error handling, OpenAPI, Testing) and mandated columns (Area, Decision, Current Phase 5 support, 6B API status, Implementation status, Dependency, Notes), with Break-glass and MFA recovery split into their own rows rather than merged into Platform admin/MFA.
- [x] Future/Upstream Dependencies Register (§36.3) created, covering all 6 required items with ID/Description/Why needed/Current status/Required phase/Requires Phase 5.x?/Blocks architecture?/Blocks implementation? — no dependency is a hidden requirement for 6B architecture approval (every "Blocks 6B architecture?" cell is explicitly No).
- [x] §4-equivalent status contradiction resolved: Architecture, API Contracts, Security Model, Authorization Model, and Traceability are each independently marked COMPLETE; only Implementation Readiness is marked CONDITIONAL, and only where a named upstream Phase 5.x dependency exists (§38.3).
- [x] No redesign of 6B's architecture performed; no Phase 6C content introduced; no Phase 5, 5K, or 6A content modified during this correction pass (verified again in §38.4).

---

## 38. Final Approval Status

**This section replaces the prior single-label status with a multi-dimension model.** The prior version's blanket "APPROVED/FROZEN" alongside per-area "Partial"/"Blocked" readiness notes was a genuine internal contradiction — a single label cannot honestly represent both "the design is done" and "some capabilities cannot be built yet." §38.3 below resolves it by tracking five dimensions independently, per this correction pass's explicit instruction: **design/contract/security-model completeness is not the same claim as implementation readiness.**

### 38.1 Final consistency audit (performed before declaring status)

- **Endpoint definitions:** no path is defined twice with conflicting contracts; the §20 inventory and §21 detailed contracts agree on method/path/auth/permission for every overlapping entry.
- **Status codes:** consistent throughout (`401` vs `403` vs `404` usage matches the stated rules in §9.2/§22 everywhere it appears, including the authorization matrix rows in §31).
- **Token/claim names:** `role` (singular) is used consistently everywhere a token/claims table or `AuthenticationContext` example appears (§6.1, §11.1) — no stray `roles` array reintroduced anywhere else in the document.
- **Role/permission names:** every role referenced (`OWNER, ADMIN, MEMBER, BILLING_ADMIN, VIEWER`) and every permission string referenced (`role:read`, `role:manage`, `api_key:read`, `api_key:manage`, etc.) matches 5B's frozen seed data (§16, §31); the superseded 9-role DDD list does not appear anywhere outside §4's and ADR-6B-08's explicit discussion of the discrepancy itself.
- **WS/internal-JWT semantics:** §17 and §19 do not contradict each other or 6A — internal JWTs are never described as valid on `/ws/v1/*` or `/api/v1/*`, and user JWTs are never described as valid on `/api/internal/v1/*`, anywhere in the document.
- **References to Phase 5 objects:** every table/function/column cited (`identity.users`, `identity.sessions`, `identity.api_keys`, `identity.oauth_identities`, `identity.password_reset_tokens`, `organization.organizations`, `.memberships`, `.roles`, `.permissions`, `.role_permissions`, `audit.audit_events`, `audit.fn_insert_audit_event`, `organization.current_tenant_id()`, `organization.is_platform_admin()`, `identity.validate_api_key()`) was directly confirmed present in the 5B/5J research pass — none is invented. No new Phase 5 table, column, or `action_kind` was added during this correction pass.
- **No stale "REVIEW REQUIRED"/TBD language** remains outside the explicitly-scoped items in §36.3's Future/Upstream Dependencies Register and the documented limitations in §15.5 (phone OTP) — each is a deliberate, labeled deferral, not an unresolved placeholder. Where the prior draft used self-contradictory labels ("Ready with interim log-based mitigation," "Ready (scoped)"), §34 now uses the precise DESIGN COMPLETE / IMPLEMENTATION DEPENDENCY / DEFERRED vocabulary instead.
- **No fabricated performance numbers:** every latency figure in §27 is labeled TARGET; every rate-limit figure in §23 is labeled a configurable default.
- **Endpoint examples vs. schemas, authz examples vs. the authz matrix, token claims vs. token architecture, security rules vs. threat model:** cross-checked — §21's examples use the exact claim/field names defined in §6.1/§11; §31's matrix rows use the exact permission strings and status-code rules defined in §8/§9.2/§22; §29's threat mitigations cite the exact mechanisms defined in §12–§19, not new ones invented for the threat model alone.
- **Break-glass terminology:** consistent everywhere it appears (§9.2, §17.4, §18.3, §21.4, §24, §29–§31, §34–§36) — the canonical flow (Platform Admin → target org → justification → strong auth → authorization → time-boxed grant → target tenant context → audited elevated operations → automatic expiry/explicit release) and the action-audit-vs-grant-persistence distinction are stated identically in every section that touches it.
- **Audit terminology:** searched for every occurrence of audit/`audit_events`/`SESSION_REVOKED`/`TOKEN_REFRESH_REUSE_DETECTED`/admin-forced-logout/security event/authentication event/authorization event (§18.3, §21.4, §25, §26, §34, §35, §36.3) — no sentence claims "every authentication/authorization decision is durably recorded" without the Tier 1/Tier 2 qualification found in §25.

### 38.2 Remaining genuine dependencies (not blockers to freezing this document's design — recorded as forward dependencies, full detail in §36.3)

1. **Durable break-glass grant-lifecycle persistence** (DEP-6B-01, §18.3/§21.4/§36.3) — the API contract, authorization model, and grant/release action-audit are complete and implementable today; only the durable *lifecycle-state* table is a future Phase 5.x item.
2. **Authentication audit-vocabulary extension** (DEP-6B-02, §25/§36.3) — `SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, and admin-forced-logout have no matching 5J `action_kind`; the audit *requirement* is fully specified, its durable persistence for these 3 kinds is a future Phase 5.x item.
3. **Robust, self-service MFA recovery** (DEP-6B-03, §15.3/§36.3) — intentionally deferred; current interim platform-admin-assisted mechanism is implementable today; a self-service mechanism is a future security requirement, not chosen here.
4. **OAuth2/OIDC provider-specific implementation** (DEP-6B-04, §15.2/§36.3) — Phase 8 scope, per 3E's own explicit deferral, not a 6B gap.
5. **Phone verification mechanism/provider** (DEP-6B-05, §15.5/§36.3) — undefined anywhere upstream of this document; not designed here.
6. **CAPTCHA/adaptive-challenge step-up** (DEP-6B-06, §23/§36.3) — deferred by design; rate limiting is a sufficient, fully-implementable interim control.

None of these six items block this document's own architectural, contractual, or security-model completeness — each is a forward-looking dependency on a *future* phase or a *future* Phase 5.x extension, individually named with an explicit "blocks implementation? / blocks architecture?" answer in §36.3, rather than silently assumed away or vaguely gestured at.

### 38.3 Status

```
PHASE 6B ARCHITECTURE:                       COMPLETE
PHASE 6B API CONTRACT:                       COMPLETE
PHASE 6B SECURITY / AUTHORIZATION DESIGN:    COMPLETE
PHASE 6B IMPLEMENTATION READINESS:           CONDITIONAL — UPSTREAM PHASE 5.x DEPENDENCIES REMAIN
                                              (DEP-6B-01 break-glass grant persistence,
                                               DEP-6B-02 audit vocabulary extension —
                                               see §36.3 for the full register)

PHASE 6B: APPROVED / FROZEN
    ONLY THE ARCHITECTURE AND API CONTRACT THEMSELVES — BOTH INTERNALLY COMPLETE
    AND CONSISTENT AS OF THIS CORRECTION PASS.
```

"APPROVED/FROZEN" means the 6B **design** (architecture, API contracts, security and authorization model, traceability) is frozen and will not be redesigned absent a new explicit decision — it does **not** mean every upstream dependency named in §36.3 is already implemented, and it does **not** mean every endpoint can be deployed to production today without the two Phase 5.x items above.

**Explicitly confirmed for this correction pass:**
- No Phase 5 content was modified. No migration was created. No new Phase 5 table, column, or `action_kind` was added.
- No Phase 5K content was modified.
- No 6A content was modified.
- No Phase 6C work was started or designed.
- This document was corrected and validated, not redesigned — every change in this pass resolves a terminology/consistency/status-labeling issue or adds the required future-dependency disclosure; no endpoint, token design, role, permission, or security mechanism from the original 6B design was altered in substance.

This document fully specifies the Authentication and Authorization API within the boundaries of Phase 1–5 and 6A's frozen architecture, resolves every discrepancy it found between DDD-layer and DB-layer sources explicitly (ADR-6B-08), closes 6A's named open item R-8 with a documented decision (ADR-6B-03), and records every genuine gap it could not close on its own authority as an explicit, individually-tracked forward dependency (§36.3, §38.2) rather than a fabricated resolution or a silently dropped caveat.
