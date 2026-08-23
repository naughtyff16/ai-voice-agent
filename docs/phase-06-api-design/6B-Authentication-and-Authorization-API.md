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
| Revision 2 | Final Security + Contract Correction Pass — 2026-08-22 (same day, second pass). Applied the binding CENTRAL INTERNAL TOKEN ISSUER decision (replacing the per-deployable self-signing model, §17, ADR-6B-11); fixed the refresh-token rotation race with row-level locking (`SELECT ... FOR UPDATE`, §13, ADR-6B-01 revised); made forced access-token revocation a global check on every access-token validation path, not an admin-route-only check (§7, §12.4, §19, ADR-6B-02 revised); fully specified the MFA challenge token as a restricted JWT (§11.4, §15.3); designed an explicit multi-organization login-continuation flow replacing the undefined `requires_organization_selection` dead end (§9.3, new endpoint `POST /api/v1/auth/organization/select`, §11.5); fully specified break-glass runtime authorization (`X-Break-Glass-Grant` header, per-request grant validation, §18.3); expanded every one of the (now 36) endpoints to a concrete, non-templated contract (§21); reconciled 6A-vs-6B status codes (notably the `IDEMPOTENCY_KEY_REUSE_MISMATCH` status, which was wrongly listed as `422` in the prior pass — 6A §7.4/§16 is `409`, now corrected); corrected the access-token hot-path performance claim now that a forced-revocation denylist check runs on every validation (§27); no Phase 5/5K/6A modification, no 6C work, no architectural redesign beyond what this pass's blockers required. Status remains multi-dimensional (§38) — see this pass's exact status line before treating any part of 6B as frozen. **NOTE: Revision 2's refresh-token fix (`SELECT ... FOR UPDATE`) was itself found to violate frozen 6A §17.3 and was replaced in Revision 3 below — do not read this row as 6B's current design for that mechanism.** |
| Revision 3 | Final Technical Correction Pass — 2026-08-22 (same day, third pass). Fixed three remaining blockers found by strict review: **(1)** removed the API-layer `SELECT ... FOR UPDATE` from refresh-token rotation — it conflicted with frozen 6A §17.3's rule against API-layer application locking — and replaced it with an atomic, conditional `UPDATE ... WHERE ... RETURNING` (CAS) statement providing the identical concurrency guarantee via Postgres's own row-level MVCC, with no application-level lock of any kind (§13.2, ADR-6B-01 revised again); applied the same CAS correction to platform-admin revoke-all (§21.36) and the new password-reset global-revocation flow (§13.5), since both had the same locking pattern. **(2)** Made MFA challenge consumption atomic — replaced the prior check-then-write shape with a single Redis `SET auth:consumed_mfa_challenge:{jti} 1 NX EX <ttl>` claim, evaluated after TOTP validation and strictly before session creation, closing a race where two concurrent verify calls with the same correct code could both create a session (§11.4, §15.3, §21.18). **(3)** Made password-reset-confirm globally revoke access, not just sessions — every currently-known access-token `jti` across the user's active sessions is now denylisted atomically alongside session revocation, closing the up-to-15-minute residual-access window a routine-logout-shaped reset previously left open; a refresh racing the reset is resolved by the same CAS pattern as (1), and Redis unavailability during the denylisting step fails the endpoint closed rather than reporting the security reset as complete (§13.5, §21.11). No Phase 5/5K/6A modification, no 6C work, no new architecture beyond correcting these three blockers to comply with frozen 6A and to close the two remaining atomicity races. See §38 for this pass's exact status line and the full 6A-compliance re-check. |
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
| User access token (JWT) | `Authorization: Bearer <jwt>` | Signature (RS256, platform user-facing key), `exp`/`nbf`/`iss`/`aud`, `token_use=access`, **then** the forced-revocation denylist check (§12.4) — applied on **every** validation of this credential type, not a special-route-only check |
| API key | `Authorization: Bearer vxa_<prefix><secret>` (or `X-Api-Key`) | `identity.validate_api_key()` SECURITY DEFINER lookup by SHA-256(full key) |
| Internal service token (JWT) | `Authorization: Bearer <jwt>` on `/api/internal/v1/*` only | Signature (RS256, central-internal-issuer public key — §17), `token_use=internal`. **Not** subject to the user-access-token denylist (§12.4) — internal tokens have no separately-defined revocation mechanism in this document; their exposure window is bounded by the 5-minute TTL alone (§17.2). |
| MFA challenge token (JWT) | `Authorization: Bearer <jwt>` (or request body field, implementation's choice) | Signature (user-facing key), `token_use=mfa_challenge`, `aud` restricted to the MFA-verification audience, plus the not-yet-consumed check (§11.4, §15.3). **Accepted only** at `POST /api/v1/auth/mfa/verify` — rejected as an invalid credential everywhere else, including every ordinary `/api/v1/*` route, every `/api/internal/v1/*` route, and every WebSocket handshake. |
| Login-continuation token (JWT) | `Authorization: Bearer <jwt>` (or request body field) | Signature (user-facing key), `token_use=login_continuation`, `aud` restricted to the org-selection audience (§11.5). **Accepted only** at `POST /api/v1/auth/organization/select` — rejected everywhere else. |
| WebSocket connect credential | Query param `?token=` or `Sec-WebSocket-Protocol` subprotocol (per ADR-6A-05) | Same validators as the access token or API key, applied at `CONNECTING → AUTHENTICATED` transition — including the forced-revocation denylist check for access tokens (§19.3). |

A request presenting no credential to a protected route fails with `401 AUTHENTICATION_REQUIRED` before any business logic or DB call. A request presenting a syntactically valid but expired/invalid/wrong-type/wrong-`token_use`/revoked credential fails with `401` (specific `code`, §22) — never a `200` and never a silent anonymous fallback.

**Restricted-purpose tokens (MFA challenge, login-continuation) are validated by a dedicated branch of this same middleware stage, not a separate pipeline** — they still run through signature/`exp`/`nbf`/`iss`/`aud` verification, but their `aud`/`token_use` values are scoped so tightly that no route other than their one designated endpoint will accept them (§11.4, §11.5, §15). This is the same "no validator accepts a token of the wrong type" invariant (§5.5) applied to two additional, narrower token types.

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
        JWT path: from the token's `organization_id` claim (set at login/refresh/org-selection time — §9.3)
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
- **Switching organizations issues a new JWT** (5B-implied session-per-org-context model, consistent with 6A §23.2) — a single access token is scoped to exactly one `organization_id` for its lifetime; there is no multi-org token. For a user authenticating fresh with more than one active membership, which organization that first JWT is scoped to is resolved through the explicit continuation flow in §9.3, never guessed and never taken from an unauthenticated client-supplied value.
- **Cross-tenant resource access returns `404`, never `403`.** Confirming that a resource exists in another tenant is itself a disclosure (6A §22) — a `Membership`, `Role`, or `ApiKey` row outside the caller's `organization_id` is indistinguishable, from the response, from one that doesn't exist.
- **Platform-admin exception:** an authenticated `PLATFORM_ADMIN` actor may cross tenant boundaries only via the break-glass mechanism (§17.3), which explicitly sets `TenantContext` to the target tenant for a bounded, audited window — it does not bypass tenant resolution, it exercises it under a distinct, logged authorization path.
- **Service-to-service tenant context:** an internal-JWT-authenticated request carries `on_behalf_of_organization_id` only when the operation is genuinely tenant-scoped (e.g., a Worker processing a specific org's job); platform-scoped internal calls (health checks, cross-tenant maintenance jobs) carry no tenant claim and must not be routed through any org-scoped endpoint.
- **Tenant-aware caching:** every cache key this document defines is namespaced by `organization_id` (`rbac:permissions:{org}:{user}`, `rbac:role:{org}:{role_id}`) — no cache key is ever constructed without a tenant segment for tenant-scoped data (3A §11.2, "no call site can construct an unnamespaced key").
- **Tenant-aware logging:** every structured log line and audit event this document emits carries `organization_id` (nullable only for genuinely platform-scoped events, §22) and `request_id`.
- **Fail-closed guarantee (6A §23.3):** if tenant context is somehow unset when a handler runs, that is a `401`/`500` at the middleware boundary — never a silent, empty-result `200`.

### 9.3 Multi-Organization Login Continuation (fixes the prior undefined `requires_organization_selection` dead end)

**Problem being corrected:** the prior draft's login contract set `requires_organization_selection: true` for a user with more than one active membership, but defined no mechanism for the client to actually complete organization selection — and, left undefined, the obvious naive fix ("let the client just POST an `organization_id` after password verification") would let an unauthenticated-for-that-org client assert an arbitrary tenant, which is exactly the client-supplied-`organization_id` trust violation §9.2 forbids. This section closes that gap with an explicit continuation mechanism.

**Flow:**

```
POST /api/v1/auth/login (email + password)
    ↓
primary authentication succeeds (password verified, user ACTIVE)
    ↓
server loads the user's ACTIVE memberships in ACTIVE organizations
    ↓
exactly one allowed membership?
    ├── yes → treat as already "selected" (no client round trip needed) → proceed to MFA check (below)
    └── no  → issue a short-lived login_continuation_token (§11.5) whose claims embed the
              exact set of allowed (organization_id, membership_id) pairs computed just now,
              server-side, from real membership rows — never from client input
              → respond 200 {
                    "requires_organization_selection": true,
                    "continuation_token": "<jwt>",
                    "allowed_organizations": [{"organization_id": "...", "organization_name": "..."}, ...],
                    "expires_in": 300
                  }
              → client renders the allowed_organizations list, user picks one
              ↓
              POST /api/v1/auth/organization/select { "organization_id": "...", "continuation_token": "..." }
              ↓
              server re-validates: continuation_token signature/exp/token_use/aud;
                                    organization_id ∈ token's embedded allowed set (§21 — else 403 ORGANIZATION_SELECTION_INVALID,
                                    never a signal about organizations outside that set, including whether they exist);
                                    membership row is (still) ACTIVE; organization row is (still) ACTIVE
                                    (both re-checked against current DB state, not just the token's snapshot,
                                    since the window between login and selection can be minutes)
              ↓
              (continues into the same MFA check as the single-membership path, below)
    ↓
MFA check (organization_id is now resolved, either implicitly or via §9.3's flow)
    ├── mfa_enabled → issue mfa_challenge_token (§11.4), organization_id claim populated
    │                 (safe to populate — org is already resolved at this point) →
    │                 client completes POST /api/v1/auth/mfa/verify
    └── mfa disabled → create session (§13), issue access + refresh tokens directly
```

**Ordering rationale (task-required justification):** `primary authentication → organization selection → MFA → session/token issuance`.

1. **Primary auth first** — nothing downstream can be evaluated (which memberships, whether MFA is required for this actor) without knowing *who* is authenticating.
2. **Organization selection before MFA** — `identity.users.mfa_enabled` is a per-user flag today (5B — MFA is not currently modeled as per-membership/per-organization), so which MFA state applies is already user-level and doesn't itself require org resolution; but the **MFA challenge token's `organization_id` claim** (§11.4) must be populated with the already-resolved organization so that the token issued after MFA success can go straight to session creation without a second round of ambiguity. Resolving org before MFA means the MFA challenge is issued once, correctly scoped, rather than needing a second "which org, again" step after MFA succeeds. It also means a suspended-membership or suspended-organization case is caught by §9.3's re-validation *before* spending an MFA round trip on a login that couldn't succeed anyway.
3. **MFA before session/token issuance** — no access or refresh token, and no `identity.sessions` row, is ever created before MFA succeeds for an MFA-enabled user (matches §15.3 and the original design intent) — the MFA challenge token itself carries no session-granting power (§11.4).
4. **Session and token issuance last** — this is the point where `identity.sessions` gains a row and the caller receives real, usable credentials; everything before this point is deliberately non-authorizing (continuation and challenge tokens authorize nothing beyond their own one designated next step, §11.4–§11.5).

**Security properties this flow provides (mirrors §9.2's server-derived-tenant principle applied to login):**
- The client never supplies an `organization_id` that the server has not already independently verified as one of *that authenticated user's own* active memberships — `allowed_organizations`/the continuation token's embedded set is server-computed from real `organization.memberships` rows, never client-asserted.
- A membership or organization that becomes `SUSPENDED`/`REMOVED`/`CANCELLED` between the login call and the organization-select call is caught at organization-select time by the live re-validation, not silently allowed through on a stale snapshot.
- The continuation token cannot access any normal API resource (§7, restricted `token_use`) and cannot be refreshed (no refresh-token semantics apply to it).
- Response to an out-of-membership `organization_id` at the select step is `403 ORGANIZATION_SELECTION_INVALID` with no detail distinguishing "not a member" from "organization doesn't exist" from "membership suspended" — the same non-disclosure discipline §9.2/§22 already apply to ordinary cross-tenant references (§22).

Full endpoint contracts: `POST /api/v1/auth/login` (§21.1), `POST /api/v1/auth/organization/select` (§21.6). JWT claims: §11.5. Error codes: §22. Threat-model coverage: §29. Tests: §32.

---

## 10. Token Architecture

Six distinct credential types (four durable/session-bearing types below, plus two narrow-purpose ephemeral JWTs specified in §10.1–§10.2). None is a substitute for another; no validator accepts a token of the wrong `token_use`/type.

| | Access Token | Refresh Token | Internal Service Token | API Key |
|---|---|---|---|---|
| Format | JWT (RS256) | Opaque, `{session_id}.{secret}` (ADR-6B-01) | JWT (RS256, central-issuer key) | `vxa_<prefix><secret>` |
| Purpose | Authorize API/WS calls | Obtain a new access token | Authorize internal (`/api/internal/v1/*`) calls | Authorize programmatic/partner API calls |
| Issuer (`iss`) | `https://auth.platform/user` | n/a (opaque) | `https://auth.platform/internal-issuer` | n/a |
| Audience (`aud`) | `platform-api` | n/a | `platform-internal-api` | n/a |
| Subject | `user_id` | n/a — session identified by embedded `session_id` | `service_id`, asserted by the **central internal token issuer** after it authenticates the calling workload — never chosen by the caller (§17.2) | resolved via DB lookup, not embedded |
| Signing key | User-facing RS256 keypair | n/a (HMAC-verified server secret material, not a JWT) | **Separate** internal RS256 keypair, owned exclusively by the **central internal token issuer** (§17.2, ADR-6B-11) — Worker, Voice Gateway, and Core API hold only the corresponding public verification key/JWKS, never the private key | n/a — SHA-256 hash comparison |
| Lifetime | 15 minutes (6A §22 baseline, applied here) | 30 days, sliding via rotation (§12) | 5 minutes (design decision — short-lived per ADR-6A-09, unchanged by centralizing the issuer) | Optional `expires_at`, default none (org-controlled) |
| Rotation | Not rotated — reissued on refresh | Rotated on every use, via an atomic conditional `UPDATE` (CAS), no API-layer lock (§13.2) | Reissued per outbound internal call **by requesting a fresh token from the central issuer**, not by the calling service signing its own (§17.2) — not persisted by the caller | Manual — revoke + reissue only, no in-place rotation (5B: `KeyHash` immutable) |
| Revocation | Individually revocable **only** via the admin-triggered forced-revocation denylist, which is now checked on **every** validation of this token type, not an admin-route-only check (§12.4, ADR-6B-02); routine logout remains session-scoped only (§12.5) and does not itself denylist the outstanding access token | `identity.sessions.status = REVOKED` | Not revocable individually — short TTL is the control; a compromised *issuer* signing key is rotated (§17.2) invalidating all outstanding internal tokens; a compromised *calling service's* workload credential cannot be used to mint tokens for another `service_id` (§17.2) and is revoked at the workload-identity layer, not the token layer | `identity.api_keys.status = REVOKED` |
| Storage (client) | Memory / short-lived, never `localStorage` recommended | `httpOnly` cookie (web) or secure storage (mobile/CLI) — never exposed to JS | Held only by the internal SDK, in memory, for its 5-minute lifetime — never the private signing key, which never leaves the central issuer | Held by the integrating system, never logged |
| Replay protection | `exp` + `jti`, denylist-checked on every use (§12.4) | Reuse/rotation detection via atomic conditional `UPDATE` (CAS), no API-layer lock (§13.2) | `exp` (5 min) + `jti`; internal-only network path bounds exposure further | `LastUsedAt` monitored, no built-in replay window (bearer-style, mitigated by TLS + IP/rate monitoring, §24) |
| Failure/audit behavior | `401`, specific `code` per §22 (expired / revoked / malformed each distinguished) | `401`, session revoked + audit on reuse detection | `401`, distinct internal-auth-failure log, **never** falls back to user-JWT validation | `401`, `INVALID_API_KEY` |

Signing algorithm decision (RS256 for both user-facing and internal JWTs, asymmetric, JWKS-distributable) is recorded as **ADR-6B-04** — Phase 1–5 does not specify an algorithm; this document supplies the decision since Worker and Voice Gateway (3A, separate deployables) need to verify tokens without holding a shared symmetric secret.

### 10.1 MFA Challenge Token

A short-lived, narrowly-scoped JWT issued after primary authentication (and, where applicable, organization selection, §9.3) succeeds for an MFA-enabled user. It authorizes exactly one thing: a single call to `POST /api/v1/auth/mfa/verify`. It is not a session credential, not a bearer of API access, and not refreshable. Full claim table: §11.4. Full behavioral contract (TTL, consumption, rate limiting, replay): §15.3.

### 10.2 Login-Continuation Token

A short-lived, narrowly-scoped JWT issued after primary authentication succeeds for a user with more than one active organization membership. It authorizes exactly one thing: a single call to `POST /api/v1/auth/organization/select`, and only for an `organization_id` within the exact allowed-membership set embedded in its own claims at issuance. Full claim table: §11.5. Full behavioral contract: §9.3.

### 10.3 Central Internal Token Issuer — Summary Pointer

Per the binding user decision for this correction pass, internal service tokens are no longer minted by each internal deployable holding its own private signing key. A single, trusted **central internal token issuer** owns the private signing capability; Worker, Voice Gateway, and Core API (and any future internal caller) receive and verify tokens using only its published public verification material (JWKS). This does **not** change anything in the "Internal Service Token" column above (format, claims, lifetime, audience are unchanged from the original ADR-6A-09 baseline) — it changes **who is allowed to hold the private key and mint the token**. Full contract: §17.2. ADR: ADR-6B-11 (§36).

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

`iss=https://auth.platform/internal-issuer`, `aud=platform-internal-api`, `exp` (now+5min), `iat`, `nbf`, `jti`, `sub`/`service_id` (the identity the **central internal token issuer** authenticated the caller as — §17.2; the caller cannot request a different value), `on_behalf_of_organization_id` (optional, present only when the issuer's policy authorizes that specific service to act on behalf of a tenant for that call), `token_use=internal`. Mirrors ADR-6A-09's claim set exactly — no claim invented beyond what 6A already specified; only the **issuance path** changes (ADR-6B-11, §17.2), not the claims.

### 11.3 Stale-permission handling (explicit, per task requirement)

| Scenario | Token still says | Server behavior |
|---|---|---|
| Role's permission set changed | Old `role` name, unchanged | `role` claim ignored for authz; `rbac:permissions:{org}:{user}` cache invalidated synchronously on `role.permissions_updated` (§23) — next request re-resolves current permissions from DB |
| User's role assignment changed | Old `role` name | Same — permission cache invalidated on `ROLE_ASSIGNED`; token's `role` claim becomes cosmetically stale until next refresh, but grants nothing itself |
| Membership revoked/suspended | Token still unexpired | `PermissionEvaluationService` step 1 (§8) — `membership.status != 'ACTIVE'` — denies on next request regardless of token validity |
| Organization suspended | Token still unexpired | Step 2 (§8) — denies on next request |
| Access token itself force-revoked (admin/break-glass-triggered) | n/a | The denylist entry is written **only** by an admin-forced-revocation action (ADR-6B-02), but the denylist **check** now runs on **every** validation of every access token, on every route type (§12.4) — not a special-route-only check. A force-revoked `jti` is rejected globally, immediately, for the remainder of its natural lifetime. |
| Access token outstanding after routine logout (not force-revoked) | n/a | No denylist entry is written by routine logout (§12.5) — the token remains cryptographically valid and passes the denylist check (nothing to find) until its own `exp`, per the documented, bounded 15-minute trade-off (§12.4). |

The distinction the task asks for: **`role` is token-derived and advisory only; every `permissions` check is must-check-server-state, resolved fresh (subject to a 5-minute cache) on every request.**

### 11.4 MFA Challenge Token

**Design chosen (per task requirement, one design only): a short-lived, restricted JWT** — not opaque server-side state — because every other ephemeral credential in this document (access, internal, and now login-continuation) is already a signed JWT verified by the same middleware stage (§7), and a JWT lets `POST /api/v1/auth/mfa/verify` validate the challenge with the same signature/`exp`/`nbf`/`aud`/`token_use` machinery already built for every other token type, rather than adding a second, opaque-token validation path.

| Claim | Required | Source | Notes |
|---|---|---|---|
| `iss` | Yes | Fixed | `https://auth.platform/user` (same issuer as the access token — this is still a user-facing credential) |
| `sub` | Yes | `identity.users.id` | The user who passed primary authentication |
| `aud` | Yes | Fixed | `platform-mfa-verify` — a dedicated, isolated audience distinct from `platform-api`; no ordinary resource-server validator ever accepts this audience |
| `iat` | Yes | Now | |
| `nbf` | Yes | Now | |
| `exp` | Yes | Now + 5 minutes | Design target, justified: long enough for a user to retrieve a TOTP code from an authenticator app, short enough to bound the exposure of a captured challenge token to a single-digit number of minutes |
| `jti` | Yes | New UUIDv7 per issuance | The single-use handle — recorded in the consumed-challenge denylist on successful verification (§15.3) so replay of an already-consumed challenge fails even though the JWT itself remains signature-valid until `exp` |
| `token_use` | Yes | Fixed | `mfa_challenge` — rejected by every validator that isn't `POST /api/v1/auth/mfa/verify` |
| `auth_stage` | Yes | Fixed at issuance | `primary_verified` — records that password/OAuth succeeded but MFA has not; not itself used for any authorization decision, present for audit/log clarity only |
| `organization_id` | Conditional | Resolved membership (§9.3) | Present **only** once organization selection has already safely completed (single-membership user, or a user who has just completed `POST /api/v1/auth/organization/select`) — never populated with a guessed or default organization. This is what lets the post-MFA-success token issuance (§9.3) go straight to session creation without a second selection round trip. |
| `membership_id` | Conditional | Same as `organization_id` | Present under the same condition |

**Rules (all task-mandated, restated as this document's binding contract):**
- Accepted **only** by `POST /api/v1/auth/mfa/verify` (§7, §21) — rejected as an invalid credential by every `/api/v1/*` resource route, every `/api/internal/v1/*` route, and every WebSocket handshake (wrong `aud`/`token_use`, same rejection path as any other wrong-type token, §5.5).
- Cannot authorize normal `/api/v1` resources, `/api/internal/v1/*`, or WebSocket connections — it carries no `role`, no `permissions`, and no session-granting claim.
- Cannot be refreshed — there is no refresh-token semantics for this token type; a client whose challenge expires must re-authenticate from `POST /api/v1/auth/login` (or `.../organization/select`) to obtain a new one.
- Cannot be exchanged for real tokens except through a **successful** call to `POST /api/v1/auth/mfa/verify` with a correct TOTP code.
- Repeated failed verification attempts against the same challenge (or the same user) are rate-limited: 5 attempts / 15 minutes per user (§23, unchanged from the prior design) — this is a lockout of the *verification step*, not the account.
- The challenge expires at its own `exp` (5 minutes) regardless of attempt count remaining.
- **Consumption is atomic, not check-then-write (corrected this pass — closes a verify-time race).** A **successful** TOTP verification does **not** proceed to session/token issuance until the server has atomically **claimed** the challenge's `jti` via a single Redis `SET auth:consumed_mfa_challenge:{jti} 1 NX EX <remaining_ttl>` — full contract in §15.3. The prior "check whether consumed, then write after success" shape allowed two concurrent requests presenting the same challenge (with the same correct TOTP code, which is valid for the whole 30–60s time-step window) to both observe "not yet consumed" and both proceed to create a session. `SET ... NX` makes the claim itself the single point of truth: only the request whose `SET NX` actually sets the key (the first to reach Redis) may proceed; every other request — concurrent or a later replay — observes the key already present and is rejected `401 MFA_CHALLENGE_CONSUMED`, even though the JWT signature itself is still valid until `exp`.
- No access or refresh token, and no `identity.sessions` row, is created before MFA verification succeeds **and** the atomic `SET NX` claim is won (§9.3, §15.3).

### 11.5 Login-Continuation Token

| Claim | Required | Source | Notes |
|---|---|---|---|
| `iss` | Yes | Fixed | `https://auth.platform/user` |
| `sub` | Yes | `identity.users.id` | |
| `aud` | Yes | Fixed | `platform-org-select` — a dedicated, isolated audience, distinct from both `platform-api` and `platform-mfa-verify` |
| `iat` / `nbf` | Yes | Now | |
| `exp` | Yes | Now + 5 minutes | Design target — long enough to render a selection UI and let the user click, short enough to bound exposure |
| `jti` | Yes | New UUIDv7 | Not individually consumption-tracked (see rationale below) |
| `token_use` | Yes | Fixed | `login_continuation` |
| `allowed_memberships` | Yes | Computed server-side at login time from real, current `organization.memberships` rows (§9.3) | Array of `{organization_id, membership_id}` — this **is** the enforcement mechanism that prevents arbitrary organization injection: `POST /api/v1/auth/organization/select` accepts only an `organization_id` present in this exact embedded set, cross-checked again against live membership/organization status at redemption time (§9.3) |

**Rules:**
- Accepted **only** by `POST /api/v1/auth/organization/select` — rejected everywhere else (wrong `aud`/`token_use`).
- Restricted purpose only — cannot access any normal API resource.
- Prevents arbitrary organization injection by construction: the set of organizations selectable through this token is fixed at issuance to the caller's own real memberships, and every selection is still re-validated live (status re-checked, not just claim-trusted) at redemption (§9.3).
- Expires quickly (5 minutes); cannot be refreshed.
- **Not** single-use/consumption-tracked, unlike the MFA challenge token: re-submitting the same continuation token to select a different allowed organization within its short TTL is accepted — it re-derives from the same already-completed primary authentication event and the same server-verified membership set, so it grants nothing beyond what a single successful password check already established. This is a deliberate scope decision (the task's explicit single-use/replay requirements are stated for the MFA challenge token, not this one) and is called out here rather than silently applied without comment.

---

## 12. Access Token Lifecycle

```
Login/Refresh → Issue (§11.1) → Use (every request: signature/claim verify + forced-revocation denylist check, §12.2) → Expire (15 min) → Refresh (§13) → Revoke (session-scoped or forced, §12.4) → Logout (§12.5)
```

### 12.1 Issue

On successful login (§14, §9.3) or successful refresh (§13), the server mints a new access token bound to the session's current `organization_id`/`role`/`membership_id`.

### 12.2 Use — corrected: no longer a zero-I/O happy path

**Prior claim, now corrected (per this pass's blocker):** the prior draft stated access-token verification has no DB or Redis round-trip on the happy path. That claim is **no longer true** once forced revocation is required to be checked globally (§12.4) rather than only on admin-triggered routes — and this document does not restate a "zero I/O" claim it knows to be false.

**Corrected verification sequence, applied identically on every `/api/v1/*` request, every WebSocket handshake (§19), and every other access-token validation path:**

```
1. Signature verification (RS256 public key)
2. exp / nbf / iss / aud / token_use validation
3. Forced-revocation denylist check: Redis GET auth:revoked_jti:{jti}
     found  → 401 TOKEN_REVOKED (§22) — reject, regardless of signature validity
     absent → continue
4. Proceed to tenant resolution / authorization (§9)
```

**What is still true:** step 1–2 remain pure-CPU, no I/O. **What changed:** step 3 is a mandatory Redis round-trip on every access-token-authenticated request — Redis is now a hard runtime dependency of access-token authentication, not only of the permission-cache path (§8). This is stated plainly in the latency budget (§27) and the failure/resilience table (§28) rather than left as a stale "stateless" claim anywhere in this document.

**Safe optimization applied (does not weaken the guarantee):** where a single request already needs a Redis round-trip for the permission-cache lookup (§8, cache-hit case), the denylist check is issued as part of the **same** Redis pipeline/`MGET` batch rather than a second sequential round-trip — this reduces added latency without skipping the check for any token. No token type ever bypasses step 3; there is no "trusted" access token that skips the denylist check, and no batching optimization is allowed to turn into a probabilistic or eventually-consistent check (e.g., no Bloom filter, no local negative cache with a propagation-delay window) — those would reintroduce exactly the unsafe shortcut this correction pass forbids.

**Redis unavailable at step 3:** per this document's own Architectural Principle #3 (§5.3 — "every failure of a dependency the authz pipeline needs fails the request closed, never open"), a Redis outage at the forced-revocation check fails the request `503 DEPENDENCY_UNAVAILABLE`, `retryable: true` — **not** a silent pass-through. This is the same fail-closed rule 6B already committed to for the permission-cache/DB dependency (§28); it is now applied consistently to the denylist check rather than carved out as an exception. Concretely: **Redis down now means every `/api/v1/*` request and every WebSocket handshake fails closed**, not just permission-dependent ones — this is a genuine, disclosed availability trade-off of adding a global forced-revocation guarantee with no Phase 5 schema change available to back it with a DB-level fallback (Hard Stop — no new table). It is deliberately not "fail open" because a false negative here (a force-revoked token being accepted) is the exact defect this correction pass exists to close. Redis HA/replication (already assumed for the permission cache, §8/§24) is the mitigation for this expanded blast radius, not a weakened check.

### 12.3 Expire

At `exp`, the token is rejected (`401 TOKEN_EXPIRED`) by signature verification alone — no state to clean up. (This check still runs before the denylist check, §12.2 — an already-expired token doesn't need a Redis round-trip to be rejected.)

### 12.4 Revoke — forced revocation is now a global check, and whether logout invalidates an outstanding access token

**Explicit answer (required by task §9, unchanged by this pass): routine logout does not retroactively invalidate an outstanding access token.** Logout (§12.5) and explicit self-service session revocation (§13.4) mark the `identity.sessions` row `REVOKED`, which prevents any **future refresh** using that session — but the access token already issued for that session remains cryptographically valid, and is accepted until its own natural expiry, **unless** it has also been force-revoked via the mechanism below. This is an explicit, bounded trade-off (worst case exposure window = 15 minutes for routine logout), not an overlooked flaw, and it is the reason the access-token TTL is kept short rather than the more common 30–60 minutes seen elsewhere.

**Forced revocation — corrected (this pass's blocker):** the prior draft's `auth:revoked_jti:{jti}` denylist existed but was checked **only** on routes reachable from a platform-admin-forced-revocation trigger path, which does **not** actually revoke the token globally — any other route would still accept it. This is fixed: **the denylist check is now step 3 of every access-token validation (§12.2), on every `/api/v1/*` route, every WebSocket handshake (§19), and any other public access-token validation path this document defines, with no exception.** A force-revoked token is rejected everywhere, for the remainder of its natural lifetime, from the moment the denylist entry is written.

The write side of the mechanism is unchanged: `auth:revoked_jti:{jti}` set with TTL = the token's remaining lifetime (or, where the exact remaining lifetime is not cheaply computable — e.g. a revoke-all across many sessions, §13.4/§21 — the full 15-minute maximum access-token TTL is used as a safe upper bound; over-retention by a few minutes is harmless, under-retention is not, so the ceiling is always used when in doubt). This is still a pure API/cache-layer addition — no Phase 5 schema change — recorded as **ADR-6B-02 (revised this pass)**.

**Who writes a denylist entry:** platform-admin forced logout (§13.4, §21), password-reset-confirm's global revocation step (§13.5 — written as a separate, best-effort step *after* the durable database revocation commits, not as part of the same atomic operation), a released/expired break-glass grant's session-revocation side effects where applicable, and any future admin-triggered revocation action. Routine logout and routine session self-revocation (§13.4) do **not** write a denylist entry — they remain session-scoped only, consistent with the explicit answer above; the two mechanisms (session revocation vs. token denylisting) are deliberately kept distinct rather than merged, since merging them would mean every logout pays the same global-check cost analysis but with no additional security benefit (a routine logout's own access token was never suspected of compromise).

**Internal-service tokens are explicitly out of scope for this denylist** (per task instruction): `token_use=internal` credentials are not checked against `auth:revoked_jti:{jti}` and are not subject to user-token revocation logic — internal tokens have no separately-defined revocation mechanism in this document; their sole exposure control is the 5-minute TTL (§10, §17.2). If a future phase needs internal-token forced revocation, that is a new, separately-specified mechanism, not an extension of this one.

**Multiple active sessions — explicit analysis (task-required):** a user may hold several concurrent `ACTIVE` `identity.sessions` rows (§12.6), each with its own `access_token_jti` reflecting the **most recently issued** access token for that session. Platform-admin revoke-all (`POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all`, §21) denylists the `access_token_jti` currently on file for **every** `ACTIVE` session belonging to that user, then marks all of those sessions `REVOKED`. **Corrected this pass:** both steps are performed via the same atomic, conditional `UPDATE ... WHERE status = 'ACTIVE' ... RETURNING access_token_jti` pattern as §13.2/§13.5 — **not** `SELECT ... FOR UPDATE` (a prior pass's draft used a row lock here; that is retired for the same frozen-6A-§17.3 reason §13.2 documents) — so a refresh racing the revoke-all cannot silently escape it: whichever atomic statement (the revoke-all's per-session `UPDATE` or a racing refresh's own rotation `UPDATE`, §13.2) commits second either observes `status != 'ACTIVE'` and fails, or is the value the other side's `RETURNING` clause captures — the same two-outcomes-only analysis as §13.5.

**Documented limitation (task-required, not silently omitted):** `identity.sessions` stores exactly **one** `access_token_jti` per row — the current one — not a history of every access token ever issued for that session. This is sufficient for revoke-all's guarantee **as long as the atomic conditional `UPDATE` captures the true current value at the moment of revocation** (which it does, since `RETURNING` reflects the row exactly as written by that same statement, not a value read earlier by a separate statement) — but it does mean the platform has no record of, and cannot retroactively denylist, an access token that was already superseded by an earlier refresh before revoke-all ran (that token is already unusable anyway, since only the current session state accepts refresh, and the superseded token was never separately tracked). This is not a gap in revoke-all's correctness for the *current* token per session; it is a statement of exactly what "current" means given the frozen schema's single-column design, made explicit here rather than assumed.

### 12.5 Logout

`POST /api/v1/auth/logout` sets the caller's own `identity.sessions.status = REVOKED`. Audit: `USER_LOGOUT` (existing 5J action_kind). Does not affect other sessions belonging to the same user (§13). Does **not** write a forced-revocation denylist entry (§12.4) — this is routine logout, not forced revocation; the caller's own outstanding access token remains valid until its natural `exp`, per §12.4's explicit, bounded trade-off.

### 12.6 Concurrent sessions

Not limited by this document — a user may hold multiple `ACTIVE` sessions (multiple devices) simultaneously; each is an independent `identity.sessions` row with its own refresh-token hash and `access_token_jti`. No maximum-concurrent-session cap exists in Phase 1–5; none is invented here (a rate-limit-style cap could be added later as a configurable policy, not a hard architectural decision this document needs to make).

---

## 13. Refresh Token Lifecycle

### 13.1 Format and the reuse-detection problem (ADR-6B-01)

`identity.sessions` has exactly **one** `refresh_token_hash` column per row — there is no token-family/history table in the frozen 5B schema. A naive "hash the presented token, look it up" design cannot distinguish "this token was already rotated out (possible theft)" from "this token never existed" once its hash has been overwritten by rotation — both look identical: no row found.

**Decision (ADR-6B-01):** the refresh token is structured as `{session_id}.{secret}`, where `session_id` is `identity.sessions.id` in cleartext and `secret` is a 256-bit random value. The server:
1. Parses `session_id` from the presented token (no DB hit yet).
2. Attempts the atomic conditional rotation described in §13.2 directly — there is no separate "look up, then decide" step; the lookup and the state-check are folded into the single `UPDATE ... WHERE ...` statement's `WHERE` clause.
3. If that atomic statement affects zero rows, a **separate, unlocked** read distinguishes: no row / wrong status / expired / hash mismatch (§13.2).
4. **Match** (the atomic `UPDATE` affected exactly one row) → rotation already happened as part of that same statement (§13.2).
   **Mismatch** (found, active, unexpired, but stored hash differs from presented) → the session exists but this specific token value is not the current one — i.e., an already-rotated-out (superseded) token was replayed. This **is** distinguishable from "unknown token" precisely because the session was found by ID. Treated as **reuse/theft** (§13.3).

This is a pure API-layer/token-format design decision — it requires no Phase 5 schema change, and is recorded as ADR-6B-01 rather than silently assumed.

### 13.2 Rotation — corrected: atomic conditional UPDATE (CAS), no API-layer `SELECT ... FOR UPDATE` (ADR-6B-01, revised this pass — 6A-compliance correction)

**Problem being corrected, in two layers:**
1. The original draft's conceptual flow (read old hash → compare → update) allowed two concurrent requests presenting the *same* refresh token to both read the same `refresh_token_hash` before either had written its rotation, both match, and both rotate — producing two valid successor token pairs from one presented token.
2. A prior correction pass closed that race using an **API-layer `SELECT ... FOR UPDATE`** — but this conflicts with frozen **6A §17.3 ("Locking and Retries")**, which states plainly: *"The API layer never takes its own application-level locks beyond what Phase 5's `SECURITY DEFINER` functions already do ... or what the Campaign Execution context already does via Redis `SETNX` ... introducing a second, API-layer locking scheme would create two sources of truth for 'who owns this row right now.'"* `identity.sessions` has no `SECURITY DEFINER` guarded-transition function for refresh rotation in the frozen 5B schema — so an ad hoc `SELECT ... FOR UPDATE` issued directly by 6B's own API-layer code is exactly the "second, API-layer locking scheme" 6A forbids, not an instance of the Phase-5-sanctioned pattern. **This is corrected here.**

**Corrected contract — single atomic statement, no explicit row lock acquired by API code, no read-then-write gap:**

```
new_secret := random(256 bits)
new_jti    := uuidv7()
new_hash   := sha256(new_secret)

UPDATE identity.sessions
SET
    refresh_token_hash = :new_hash,
    access_token_jti   = :new_jti,
    last_seen_at        = now()
WHERE id = :session_id
  AND status = 'ACTIVE'
  AND expires_at >= now()
  AND refresh_token_hash = :presented_hash
RETURNING id, access_token_jti, refresh_token_hash;

-- rows affected = 1  →  THIS request rotated the session. Return the new access_token
--                       (built from the returned access_token_jti) + new refresh_token
--                       ({session_id}.{new_secret}). No further branching needed.
--
-- rows affected = 0  →  perform a plain (unlocked) follow-up SELECT to distinguish why:
--     no row with that id                          → 401 INVALID_REFRESH_TOKEN
--     status != 'ACTIVE'                            → 401 INVALID_REFRESH_TOKEN
--     expires_at < now()                            → 401 INVALID_REFRESH_TOKEN
--     row exists, ACTIVE, unexpired, but
--       refresh_token_hash != :presented_hash        → 401 REFRESH_TOKEN_REUSE_DETECTED
--                                                       (§13.3 — revoke the session as a
--                                                        second statement, see below)
```

**Why this closes the race without any application-level lock:** the `WHERE` clause's `refresh_token_hash = :presented_hash` condition and the `SET refresh_token_hash = :new_hash` write are evaluated by Postgres as one atomic statement. Postgres's own MVCC/row-visibility machinery — not API code — guarantees that of two concurrent `UPDATE` statements racing against the same row with the same `WHERE` predicate, at most one can match and commit; the loser's `WHERE` clause re-evaluates against the row as it exists *after* the winner's commit (or is blocked briefly by Postgres's own internal row-version conflict handling, invisible to and uncontrolled by API code) and therefore fails to match (because `refresh_token_hash` has already changed). This is precisely the same "compare-and-swap inside a single statement" property 6A's own ADR-6A-08 already relies on for optimistic concurrency elsewhere (§17.2 of 6A) — 6B does not invent a new concurrency primitive, it applies the one 6A already sanctions.
- If the first request's `UPDATE` commits, the row's `refresh_token_hash` is now the **new** hash. The second request's `UPDATE` (same presented, now-stale hash) matches zero rows — its follow-up read finds the session `ACTIVE`/unexpired with a **different** current hash, which is exactly the reuse/replay condition (§13.3): the session is revoked (a second, single-row, unconditional `UPDATE ... SET status = 'REVOKED' WHERE id = :session_id` — itself also just an ordinary atomic statement, no lock acquired).
- If the first request instead was itself a reuse attempt (already-superseded token) and lost the race to revoke first, the second request's follow-up read simply finds `status != 'ACTIVE'` and returns `401 INVALID_REFRESH_TOKEN` — also correct.
- **No interleaving exists in which both requests' `UPDATE` statements affect a row each with the rotation write** — Postgres's own row-level MVCC guarantees this without any `SELECT ... FOR UPDATE`, `LOCK TABLE`, advisory lock, or other application-level locking primitive appearing anywhere in 6B's own code. No second source of truth for "who owns this row" is introduced — the single `UPDATE`'s own atomicity **is** the only mechanism, and it is provided entirely by Postgres, not by 6B.

**Requirements satisfied (task-mandated, restated as verified guarantees of the design above):**
- Exactly one successful rotation per presented (still-current) refresh token — enforced by the atomic conditional `UPDATE`'s own row-affected count, not by an API-layer lock.
- Concurrent same-token refresh cannot produce two valid successor token pairs — the second request's `UPDATE` affects zero rows and is routed to the reuse/invalid branch, never both to success.
- **No `SELECT ... FOR UPDATE` or any other API-layer locking construct appears anywhere in this design** — corrected per frozen 6A §17.3.
- No Phase 5 schema change, no new table/column — `identity.sessions`' existing columns are sufficient.
- **DB cost is minimal and unchanged from the latency budget already committed to (§27):** one atomic `UPDATE` (with an optional follow-up unlocked `SELECT` only on the zero-rows-affected path) — no lock held across any external I/O, no lock held at all in the success path.
- Retry behavior is explicitly defined in §13.2a below — no automatic API-layer retry of a rotating `POST`.
- **Explicit 6A-compliance statement:** this design introduces no application-level lock of any kind; it relies exclusively on a single atomic, conditional SQL statement whose all-or-nothing semantics are provided by Postgres itself — the same class of mechanism 6A's own ADR-6A-08 and §17.3 already endorse (guarded conditional writes, not apply-side locking). No second source of truth for row ownership is created, satisfying 6A §17.3 by construction rather than by exception.

### 13.2a Concurrency test requirement and retry semantics

**Tests (§32 restates this as an explicit minimum test):** two genuinely concurrent HTTP requests presenting the identical refresh token against a running instance (not two sequential requests in a unit test that never actually overlap) must produce: exactly one `200` with a new access+refresh pair, and exactly one `401 REFRESH_TOKEN_REUSE_DETECTED` (or, in the rare true-simultaneous-start case, Postgres's own internal commit ordering — not any API-layer construct — decides which `UPDATE` lands first; the guarantee is about the *outcome*, one winner, one loser, never two winners, not about which physical request wins, and **no `SELECT ... FOR UPDATE` code path exists to test the absence of** — this is itself asserted, §32).

**Retry behavior — explicitly defined (task-mandated):**
- **No automatic API-layer retry of the rotating `POST /api/v1/auth/token/refresh` exists anywhere in this stack.** 6A's own retry rule (§16/§21, restated in 6B §22) already forbids auto-retrying a non-idempotent POST without an Idempotency-Key round trip, and this endpoint deliberately carries **no** Idempotency-Key support (§21) — because idempotency-key replay-of-a-successful-call semantics (6A §16 — "same key ⇒ return the original result") would be actively wrong here: it would mean a legitimate second presentation of an already-rotated-out token returns the *original* rotation's tokens again, silently defeating rotation. Refresh is therefore designed to be **non-retryable by construction**, not merely "retryable but discouraged."
- A client-side retry of what the client believes was a failed/timed-out request, using the **same** (now possibly-already-rotated) refresh token, is indistinguishable at the server from an attacker replaying a captured token — and is deliberately treated identically (§13.3, §13.6) rather than special-cased, per the accepted trade-off documented in §13.6.

### 13.3 Reuse/replay detection and response

On a hash mismatch against a found, active, unexpired session — detected via the atomic `UPDATE`'s zero-rows-affected result followed by the unlocked distinguishing read (§13.2), **not** inside any locked transaction: immediately issue a second, ordinary, unconditional single-row `UPDATE identity.sessions SET status = 'REVOKED' WHERE id = :session_id` (hard-revoke, not just deny this request), and respond `401 REFRESH_TOKEN_REUSE_DETECTED`. This forces the legitimate user to re-authenticate, closing the window regardless of which of the two holders (attacker or legitimate client racing a rotation, or a legitimate client retrying after a lost response, §13.6) is which — the standard rotation-family compromise response. **This second `UPDATE` is, like the rotation `UPDATE` itself, an ordinary atomic statement with no API-layer lock acquired** — a small window between the failed conditional `UPDATE` and this revoke `UPDATE` is inherent to the CAS approach (as opposed to holding a lock across both), but is inconsequential here: the only thing that can happen in that window is another request also failing to match the (already-rotated-or-already-being-revoked) row, which itself either revokes redundantly (idempotent — the row is already becoming `REVOKED`) or observes the row already `REVOKED` and returns `401 INVALID_REFRESH_TOKEN`. No sequence of events in this window can produce a second valid successor token pair, which is the actual guarantee this section exists to provide.

**Audit gap, explicitly documented (ADR-6B-06):** 5J's `action_kind` vocabulary has no `SESSION_REVOKED` or `TOKEN_REFRESH_REUSE_DETECTED` value (confirmed absent by direct inspection of the CHECK constraint and the full enumerated list in 5J §14.3). Per this document's hard boundary (§2), Phase 5 is not modified to add one. **Interim mitigation:** reuse-detection events are emitted as structured application logs and a dedicated Prometheus counter (`auth_refresh_reuse_detected_total`, §26) rather than into `audit.audit_events`, with the gap and a recommendation to extend the 5J vocabulary in a future migration recorded as an open item (§36).

### 13.6 Lost-response trade-off (task-required — network-failure behavior, not to be silently ignored)

**Scenario:** the server successfully rotates the refresh token and commits (§13.2), but the response is lost in transit (client timeout, connection reset, proxy hiccup) before the client receives the new token pair. The client, believing the call failed, retries using the **old** (now-superseded) refresh token. The server correctly identifies this as a hash mismatch against an active session and — per §13.3 — treats it as reuse, hard-revoking the session. The legitimate client is force-logged-out by its own retry of a call that, in fact, already succeeded server-side.

**Decision: (A) strict reuse-detection behavior — accepted security trade-off.** This document does not weaken §13.2/§13.3's guarantee to accommodate this case. Reasoning:
- A **bounded grace strategy** (e.g., accepting the immediately-prior refresh token's hash for a short window after rotation, so a lost-response retry still succeeds) would require persisting at least the *previous* `refresh_token_hash` (or an equivalent short history) somewhere — `identity.sessions` has exactly one `refresh_token_hash` column in the frozen 5B schema (§13.1), and this document's hard boundary forbids adding a token-history table or column to close this gap (Hard Stop, §2/§17 of the task). No safe grace strategy is possible within the frozen schema without reintroducing exactly the "was this the previous legitimate token or a stolen one" ambiguity ADR-6B-01 was designed to eliminate — a short grace window is indistinguishable, at the protocol level, from a short window in which a stolen-and-already-used token would also be silently accepted.
- Given the frozen-schema constraint, choosing (B) would mean inventing an unsafe shortcut (a time-boxed exception to reuse detection with no way to verify *why* the old token is being presented again) — precisely what this correction pass forbids elsewhere (§12.2's "no unsafe shortcut" instruction for the denylist optimization applies with equal force here).
- The residual impact is bounded and recoverable: the affected client is forced to re-authenticate via `POST /api/v1/auth/login` (and, if applicable, §9.3's organization-selection/MFA flow) — an inconvenience, not a security incident, and not silently different from any other forced-logout UX the client must already handle (§13.3, §21).

**Client-side mitigation (implementation guidance, not an API contract change):** a well-behaved client SDK should treat "request sent, response not received" for this specific endpoint as ambiguous and prefer prompting re-authentication over blindly retrying with the same token — but that is a client behavior recommendation, not a server-side relaxation of §13.2/§13.3, and this document does not make server behavior depend on trusting client-declared "this is a retry" signals (which an attacker could also send).

### 13.4 Session-scoped revocation, forced logout, password reset implications

- **User revokes one other session:** `DELETE /api/v1/sessions/{session_id}` — same `status=REVOKED` update, scoped to sessions owned by the caller's own `user_id` (authorization rule: a user cannot revoke another user's session; an org admin does **not** automatically gain this ability — no such elevation exists in Membership/Role modeling, 4A confirms Session is not a Membership-scoped concept).
- **Platform-admin forced logout:** `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all` (§20) — revokes every `ACTIVE` session for a user; requires `PlatformAdminOnly` (§17), always audited (`ORG`-independent platform action).
- **Password reset:** on successful `POST /api/v1/auth/password/reset/confirm`, **all** existing sessions for that user are durably revoked in the same database transaction as the password change, and the server then attempts to globally denylist every currently-known access-token `jti` for those sessions as a **separate, best-effort step performed after that transaction commits** (§13.5 — corrected this pass to stop implying PostgreSQL+Redis act as one atomic unit) — a deliberate design decision recorded here, not found explicitly in Phase 1–5 but directly implied by `NFR-SEC-008` (OWASP-ASVS alignment) and not in tension with any frozen schema. The database-durable part of this guarantee (password changed, sessions revoked, refresh capability gone) is unconditional; the immediate-global-access-token-rejection part depends on the Redis write succeeding, and is not always achievable crash-safely with the frozen schema (§13.5, DEP-6B-08).
- **Suspicious activity:** beyond reuse detection (§13.3), no automated anomaly-detection mechanism (impossible-travel, new-device challenge) exists in Phase 1–5; not invented here (§36).

### 13.5 Password reset — durable session revocation, plus best-effort global access-token denylisting (corrected this pass — removes a false cross-system atomicity claim)

**Problem being corrected (this pass):** a prior draft of this section described the database session-revocation step and the Redis access-token-denylist step as if they were part of one all-or-nothing operation, and further claimed that a later retry of an already-consumed reset token could always "resume" any unfinished Redis work. **Neither claim is true of this platform's actual architecture.** PostgreSQL and Redis are two independent systems with no shared transaction coordinator between them (no two-phase commit, no distributed transaction manager is specified anywhere in Phase 1–5 or 6A, and this document does not invent one). A statement committed in PostgreSQL and a key written to Redis cannot be made to succeed or fail together as a single unit. This section restates the design so it claims exactly what the architecture can actually guarantee — no more.

**The underlying security objective is unchanged and remains required:** a password reset must (a) durably end the ability to obtain new access tokens for that user, and (b) make a best-effort attempt to immediately invalidate every access token already outstanding at reset time, rather than waiting out their natural 15-minute lifetime. What changes here is **only** the honesty of what is claimed about step (b)'s reliability — the mechanism itself (denylisting known current `jti`s, §12.4) is unchanged.

**A. Durable database security state (PostgreSQL) — one transaction, this is the source of truth:**

```
BEGIN;

1. Validate the reset token (§13.1-style single-use/hash/expiry check against
   identity.password_reset_tokens); mark it consumed.
2. UPDATE identity.users SET password_hash = :new_hash,
                              password_changed_at = now()
   WHERE id = :user_id;
3. For every row of identity.sessions WHERE user_id = :user_id
                                        AND status = 'ACTIVE':
     UPDATE identity.sessions
     SET status = 'REVOKED'
     WHERE id = :session_id AND status = 'ACTIVE'
     RETURNING access_token_jti;
     -- conditional, CAS-consistent with §13.2's no-API-layer-locking rule
     -- (unchanged from the prior pass — see the concurrency note below);
     -- the RETURNING clause is what captures each session's current
     -- access_token_jti, atomically, as part of this same statement

COMMIT;
```

**Once this transaction commits, the following are unconditionally, durably true** — regardless of anything that happens afterward: the password is changed; every session that was `ACTIVE` at the time of the reset is now `REVOKED`; no refresh token bound to any of those sessions can succeed again (§13.2 — a racing refresh's own conditional `UPDATE` will observe `status != 'ACTIVE'` and fail). This is the durable database security state, and it is what `password_reset_completed`/`session_revocation_completed` (§21.11) actually report.

**B. Runtime access-token revocation state (Redis) — a separate, best-effort step performed AFTER the transaction above has committed:**

```
-- only reached after COMMIT above has succeeded --
for each access_token_jti captured by step 3's RETURNING clause:
    SET auth:revoked_jti:{jti} <marker> EX <15-minute maximum ceiling>
    -- same ceiling-TTL rule as §12.4/§21.36; exact remaining lifetime
    -- is not cheaply known without decoding, so the ceiling is always used
```

**This is explicitly NOT one atomic operation with step A.** The database commit in A has already happened, irreversibly, by the time B begins. B can succeed fully, succeed partially (some `jti`s denylisted, others not, e.g. a connection drop mid-loop), or fail entirely — and none of those outcomes changes what A already committed. **The document does not use, and must not be read as implying, wording such as** *"atomically across DB and Redis,"* *"guaranteed all-or-nothing across PostgreSQL and Redis,"* *"the reset can always resume from the consumed token,"* **or** *"no crash window exists"* — none of these describe a mechanism this architecture actually provides.

**Case-by-case outcome (task-required, stated exactly, not summarized away):**

| Case | What happened | Result |
|---|---|---|
| **A — DB commit succeeds, Redis denylisting succeeds** | Both steps completed | Password changed; sessions revoked; refresh tokens unusable; **every known current access-token `jti` is immediately rejected on every access-token validation path (§12.4)** — the full intended security outcome is achieved. |
| **B — DB commit fails** | Step A's transaction rolled back (bad token, DB error, etc.) | Password reset fails outright — no password change, no session change, nothing to denylist. `400`/`409`/`503` per the specific cause (§22); no partial state exists to report. |
| **C — DB commit succeeds, then Redis denylisting fails (fully or partially)** | Step A committed; step B did not complete for one or more sessions | Password **is already changed**; sessions **are durably revoked**; refresh tokens **cannot be used** — none of this is undone. But some already-issued access tokens for the affected sessions **may remain usable until their own natural ≤15-minute expiry**, because the corresponding `auth:revoked_jti:{jti}` entry was never written. **The endpoint response must not claim that immediate global access-token revocation succeeded when it did not** (§21.11's response shape and error behavior make this distinction explicit). |

**No fabricated resumability:** a client that retries `POST /api/v1/auth/password/reset/confirm` with the same (now-already-consumed) reset token after a Case C failure is **not** promised — anywhere in this document — a mechanism that resumes the unfinished Redis work from durable state. The frozen 5B schema stores no `password_reset_revocation_pending`, `revocation_delivery_status`, `security_reset_status`, `revocation_outbox`, or equivalent field, and this document does not add one (Hard Stop). §21.11 defines the actual, honest retry-observable behavior (the reset token is already consumed, so a literal retry with the same token fails token-validation — it does not silently re-run step B) rather than implying a resume capability that does not exist.

**Concurrency with an in-flight refresh — unchanged from the prior pass, restated for context:** a refresh request racing the durable transaction (step A) for the *same* session cannot escape revocation, and this part of the design is unaffected by this correction — it is a pure PostgreSQL-side CAS guarantee (§13.2), not something that depends on Redis at all:
- **Reset wins the race:** the session-revoking `UPDATE` (step A.3) commits first, capturing and (in step B) denylisting the pre-refresh `jti`. The racing refresh's own conditional `UPDATE` (§13.2) then matches zero rows and fails `401 INVALID_REFRESH_TOKEN`.
- **Refresh wins the race:** the refresh's `UPDATE` (§13.2) commits first, rotating to a new `refresh_token_hash`/`access_token_jti` while `status` is still `ACTIVE`. Step A.3's own `RETURNING`-bearing conditional `UPDATE` then captures the **already-rotated**, current `access_token_jti` — the new one the refresh just minted — which step B then attempts to denylist. The new token is still caught by step A's durable capture; whether it is *also* denylisted in Redis is governed by the same Case A/B/C analysis above, not by anything new introduced by the race.
- **No `SELECT ... FOR UPDATE` or other API-layer lock is used anywhere in this coordination** — consistent with §13.2's 6A-compliance correction; this correction pass changes nothing about that.

**Redis unavailable during step B (task-required, fail-closed at the response level, not at the DB level):** the endpoint does **not** report an unqualified `200 { "status": "ok" }` when step B could not be completed — it returns `503 DEPENDENCY_UNAVAILABLE` (6A's frozen error envelope, §22) whose `error.details` accurately distinguishes what actually completed (conceptually: `password_reset_completed: true`, `session_revocation_completed: true`, `access_token_revocation_completed: false`) **without** exposing which `jti`s, token values, Redis key names, or internal implementation detail were involved. The password change and session revocation are **not** rolled back to "match" the Redis failure — they already durably happened in step A, and rolling them back would itself be a security regression (it would mean a legitimate password-reset request that later hit a transient Redis blip loses its already-achieved protection). The response is honest about the *partial* nature of the outcome rather than either (a) falsely claiming full success or (b) discarding the durable progress already made.

**Frozen-schema limitation preserved (task-required, not silently dropped):** `identity.sessions` still stores only **one** current `access_token_jti` per session (§12.4's documented limitation, unchanged) — only the currently-known `jti` per session can ever be captured/denylisted this way, and this section adds no mechanism to go further. This is the same limitation already accepted for platform-admin forced revoke-all (§21.36), now also applied to password-reset.

**Future dependency, not solved here:** genuinely crash-safe coordination between the durable database revocation (step A) and the Redis denylist population (step B) — such that a Case C partial failure could be durably tracked and later reconciled/retried without inventing an unsafe shortcut — is recorded as **DEP-6B-08** (§36.3). It is explicitly not designed, chosen, or implemented in this document; see §36.3 for the possible future mechanisms listed only as non-selected examples.

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

**Authorization rule (explicit, per task requirement):** a user cannot revoke another user's session under any circumstance via these endpoints. An org admin/owner does not gain session-control over other members through their Role — no code path in this document grants it, since `identity.sessions` carries no `organization_id` and Membership/Role never reference it. The only cross-user session control is the platform-admin forced-logout endpoint (§13.4, §21), which is a distinct, explicitly audited elevated action, not an RBAC permission any org-level role holds, and which — unlike these owner-scoped session endpoints — also writes forced-revocation denylist entries so the affected access tokens are rejected globally, not merely blocked from future refresh (§12.4).

**Self-revocation (`DELETE /api/v1/sessions/{session_id}`, `DELETE /api/v1/sessions`) does not denylist the outstanding access token**, consistent with §12.4/§12.5's routine-logout behavior — only the platform-admin-forced path does. This is a deliberate, documented asymmetry: self-revocation is a "stop trusting this device for future refresh" action, not an emergency global-revocation action.

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

`identity.users.mfa_enabled` (boolean) and `mfa_secret_ref` (opaque `secret_manager://` pointer; the column comment itself names the mechanism as **TOTP**, 5B). Endpoints: `POST /api/v1/auth/mfa/enroll` (generates a TOTP secret, stores its reference, returns a provisioning URI/QR payload — **the raw secret is returned exactly once**, mirroring the API-key one-time-reveal pattern, §16.6), `POST /api/v1/auth/mfa/verify` (§21 — two distinct calling contexts, disambiguated by which credential is presented, never by a client-supplied flag: (a) an **access-token**-authenticated call, used to confirm enrollment — sets `mfa_enabled=true` on first successful verification; (b) an **`mfa_challenge_token`**-authenticated call (§10.1, §11.4), used as the login step-up required after password/OAuth for a user with `mfa_enabled=true` — see the full challenge-token contract below), `DELETE /api/v1/auth/mfa` (disable, requires password re-entry).

**MFA challenge token — the credential the prior draft introduced but did not define (corrected this pass).** Full JWT claims: §11.4. Full design rationale (why a JWT, not opaque server-side state): §10.1. Summary of the behavioral contract, restated here in context:
- Issued by `POST /api/v1/auth/login` (or `POST /api/v1/auth/organization/select` for a multi-org user, §9.3) in place of real tokens, whenever `mfa_enabled=true` for the authenticating user and primary authentication (and, if applicable, organization selection) has already succeeded.
- 5-minute TTL (design target, justified in §11.4); `token_use=mfa_challenge`; `aud=platform-mfa-verify` — a dedicated audience no ordinary resource-server validator accepts.
- Accepted **only** by `POST /api/v1/auth/mfa/verify`; rejected as an invalid credential everywhere else (§7).
- Cannot authorize normal `/api/v1` resources, cannot authorize `/api/internal/v1/*`, cannot authorize a WebSocket connection — it carries no session, role, or permission claim, only `sub`, the resolved `organization_id`/`membership_id` (§9.3), and `auth_stage=primary_verified`.
- Cannot be refreshed — expiry means re-authenticating from `POST /api/v1/auth/login`.
- Cannot be exchanged for real tokens except through a successful `POST /api/v1/auth/mfa/verify` call presenting a correct TOTP code.
- Repeated failed TOTP attempts against it are rate-limited (5/15min/user, §23, lockout-style — locks the verification step, not the account).
- The challenge expires at its own `exp` regardless of remaining attempts.
- **Consumption is an atomic Redis claim, not a check-then-write (corrected this pass, §11.4, §21.18):** `SET auth:consumed_mfa_challenge:{jti} 1 NX EX <remaining_ttl>` — only the request whose `SET NX` succeeds may proceed to session creation and token issuance; any other request (concurrent, or a later replay) fails `401 MFA_CHALLENGE_CONSUMED` (§22) because the key already exists. This closes a race the prior check-then-write shape did not: two concurrent verify calls presenting the same challenge and the same (TOTP-window-valid) code could otherwise both observe "not yet consumed" and both create a session.

  **Required ordering (task-mandated, binding):**
  ```
  1. Validate challenge JWT (signature)
  2. Validate exp / aud / token_use
  3. Validate TOTP code
  4. Atomically claim the challenge jti: SET auth:consumed_mfa_challenge:{jti} 1 NX EX <ttl>
  5. Claim succeeded  → create session, issue access + refresh tokens
  6. Claim already existed → 401 MFA_CHALLENGE_CONSUMED (no session created)
  ```
  TOTP is validated **before** the atomic claim so that a wrong code never consumes a challenge the user could still legitimately retry (consistent with the 5/15min lockout being a code-attempt limiter, not a single-shot gate) — only a **correct** code reaches the claim step, and once claimed, no second correct-code presentation (replay, or a genuine race) can also succeed.
  **Documented failure trade-off (task-required, not silently accepted without comment):** if the `SET NX` claim succeeds but session creation subsequently fails (DB error, etc.), the challenge remains consumed and the user must restart authentication from `POST /api/v1/auth/login`. This is accepted rather than "unclaiming" the jti on failure, because: duplicate session/token issuance (the alternative failure mode if the claim were reversible mid-flight and a retry raced a slow first attempt) is a worse outcome than an inconvenienced re-login; the challenge is short-lived (≤5 minutes) so the cost of restarting is bounded; and restart-login is a fully recoverable, ordinary user action, not a security incident.
  **Redis unavailable at the claim step (task-required, fail-closed):** `503 DEPENDENCY_UNAVAILABLE` — MFA login completion fails closed; no session is created and no tokens are issued. This is not weakened to "proceed without the claim," since doing so would silently reopen the exact race this correction closes.
- No access token, no refresh token, and no `identity.sessions` row exists before the TOTP check succeeds **and** the atomic claim is won (§9.3).

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

Applies ADR-6A-09's claim set, audience, and token shape exactly — **no redecision of ADR-6A-09 itself**. What this correction pass changes is narrower and additive: **who is allowed to hold the private signing key and mint the token**, per the binding user decision for this pass (CENTRAL INTERNAL TOKEN ISSUER, recorded as ADR-6B-11, §36). ADR-6A-09 already left this specific question open at the "each service could plausibly sign its own" level of detail; ADR-6B-11 closes it.

### 17.1 Principal and trust model

- **Principal:** a named internal service (`service_id` claim), not a DB row — Worker, Voice Gateway, and any future internal caller of Core API. **No `ServiceAccount` table is created** — per the Hard Stop for this pass and per 4A's confirmation that no such aggregate exists in the domain model (§6).
- **Token:** short-lived (5 min, §10) RS256 JWT, signed with a key **separate** from the user-facing keypair, verified by the **same** auth middleware entry point but routed to a distinct validator by `token_use=internal`.
- **Trust model:** the **central internal token issuer** — a single, trusted internal platform capability, not a public endpoint and not a Membership/Role/tenant-scoped concept — owns the private signing capability exclusively. Every resource/API service that verifies internal tokens (Core API, and any future internal HTTP consumer) receives **only** the issuer's public verification material (JWKS) — never the private key. This is the same asymmetric-signing pattern already used for the user-facing keypair (ADR-6B-04), applied to a second, now-centralized keypair.

### 17.2 Central Internal Token Issuer — full contract (ADR-6B-11)

**What changes vs. the prior draft, explicitly:** the prior draft stated "each internal deployable holds its own signing capability... and mints its own token per outbound call" (3F §7.2 secret store, per-deployable). That model is **replaced** by this pass's binding decision: internal services **no longer** hold a private signing key at all. Every occurrence of "mints its own token" for an internal service in this document refers to the corrected flow below, not the retired per-deployable model.

**Corrected flow:**

```
Internal service workload (Worker | Voice Gateway | Core API | future internal caller)
    ↓
authenticates its own workload/service identity to the issuer
    (trusted workload identity / deployment credential / infrastructure identity —
     e.g. the platform's existing deployment/infrastructure-identity mechanism, 3F;
     this document does not invent a new Phase 5 credential store for this —
     it is an infrastructure-identity concern, not a database concern)
    ↓
central internal token issuer
    - verifies the calling workload's identity via the trusted mechanism above
    - determines the service_id that identity is authorized to assert
      (the caller cannot request/choose an arbitrary service_id — §17.2's
      "caller authentication" rule below)
    - determines whether an on_behalf_of_organization_id is permitted for
      this service_id + operation, per issuer-side policy — never per
      caller assertion
    - signs a new short-lived (5 min) internal JWT with its own private key
    ↓
short-lived internal JWT (claims: §11.2 — iss, aud, sub/service_id, iat, nbf,
                                    exp, jti, token_use=internal,
                                    on_behalf_of_organization_id optional)
    ↓
POST /api/internal/v1/*  (verified by the resource/API service using only
                          the issuer's public JWKS — §17.3)
```

**Issuer trust model:**
- The central issuer owns the private signing key exclusively; it is never distributed to Worker, Voice Gateway, or Core API.
- Validators (every internal-token-verifying service) hold only the issuer's public verification key/JWKS — the same JWKS-distribution mechanism already specified for the user-facing keypair (§24), now serving a second, issuer-owned key set.
- Key rotation is supported: the issuer can rotate its signing key on the existing 180-day policy (3F §7.2, unchanged cadence) by publishing the new public key to the JWKS endpoint ahead of cutover, exactly as the user-facing keypair already does — no new rotation mechanism is invented, only the ownership of the *private* half is now concentrated in one place instead of one-per-deployable.

**Caller authentication (how a workload proves *its own* identity to the issuer, without a new Phase 5 table):**
- The calling service authenticates to the issuer through a trusted workload/deployment identity mechanism — e.g., the platform's existing infrastructure-level service identity (mTLS client identity, a platform-issued deployment credential, or an equivalent infra-layer identity already established for that deployable, 3F). This document does **not** invent a Phase 5 service-account table to back this — caller authentication is an infrastructure-identity concern the issuer resolves at its own layer, the same way `3F §7.2`'s per-deployable secret store already was an infra-layer concern before this pass, just now consumed by the issuer instead of by each deployable directly.
- **The caller cannot assert an arbitrary `service_id`.** The issuer derives `service_id` from the authenticated workload identity via its own internal mapping/policy (workload identity → allowed `service_id`), never from a field the caller supplies in its request to the issuer. A compromised Worker workload identity can, at most, obtain tokens asserting `service_id=worker` — it cannot request `service_id=voice-gateway` or any other identity, because the issuer's mapping is keyed by the *authenticated* workload identity, not by caller-supplied input.
- **The caller cannot assert an arbitrary tenant.** `on_behalf_of_organization_id` is included in an issued token only when the issuer's own policy authorizes that specific `service_id` to act on behalf of tenant-scoped data for that class of operation — this is issuer-side policy, not a value the calling service can simply request and receive.

**Issued claims:** exactly the set already specified in ADR-6A-09 and restated at §11.2 — `iss`, `aud`, `sub`/`service_id`, `iat`, `nbf`, `exp`, `jti`, `token_use=internal`, `on_behalf_of_organization_id` (optional, policy-controlled). No claim is added or removed by centralizing issuance.

**Security properties (task-mandated, restated as this contract's guarantees):**
- A caller cannot assert an arbitrary `service_id` (above).
- A caller cannot assert an arbitrary tenant (above).
- Issuer policy — not caller input — determines allowed tenant delegation.
- Tokens remain short-lived (5 minutes, unchanged from ADR-6A-09).
- The private signing key never leaves the issuer — Worker, Voice Gateway, and Core API never hold it, only its public counterpart.
- Key rotation is supported without invalidating already-issued, still-live tokens (JWKS-based, same mechanism as the user-facing keypair, §24).
- A compromised individual service (Worker or Voice Gateway) cannot mint tokens for another service's `service_id` — it has no signing capability at all; at most, its own trusted-workload-identity credential could be used to request more tokens *for itself* from the issuer, which is a narrower blast radius than the prior per-deployable-signing-key model (where a compromised deployable's private key could forge a token for *any* `service_id`, since the key itself carried no caller-identity binding).

**Failure behavior:**
- **Issuer unavailable → new internal token issuance fails closed.** A calling service that cannot reach the issuer (or whose workload-identity authentication to the issuer fails) simply does not obtain a new internal token — it cannot fall back to minting its own, because it has no signing capability. The calling service's own outbound call fails/retries per its own resilience policy (not a 6B concern beyond stating this bound); there is no fallback to user tokens or API keys for internal-to-internal calls (below).
- **Already-issued, still-valid tokens remain verifiable** by resource/API services for their own remaining 5-minute lifetime even during an issuer outage, because verification only needs the cached public JWKS, not a live call to the issuer (§24) — an issuer outage stops new issuance, it does not retroactively invalidate tokens issued moments before the outage began.
- **No fallback to user tokens or API keys.** An internal caller that cannot obtain a fresh internal token never substitutes a user-facing credential or an API key to reach `/api/internal/v1/*` — no such fallback path exists in the auth middleware (§7, §17.3), and none is added here.
- This is not a public endpoint inventory item (§20) — it is described here as an internal platform capability per the task's own framing, not as a 36th public/internal-API-surface endpoint with its own rate limit/OpenAPI entry. It is not reachable by tenant/user clients, is not documented in the public OpenAPI surface (§33), and is not subject to the public rate-limit/quota system (6A §23, restated §17.1).

### 17.3 Trust boundary / routing (unchanged from the prior draft's substance)

- `/api/internal/v1/*` routes accept **only** internal tokens minted by the central issuer; `/api/v1/*` routes accept **only** user/API-key credentials (plus the two narrowly-restricted ephemeral tokens, §7). Neither validator falls back to the other — an internal JWT presented at a public route is rejected exactly as any other invalid credential, and vice versa (§29 threat model, confused-deputy mitigation).
- **On-behalf-of:** `on_behalf_of_organization_id`, optional, present only for genuinely tenant-scoped internal calls, per issuer policy (§17.2, §9.2).

### 17.4 Threat-model-specific notes

- **Confused deputy:** an internal token presented at a public `/api/v1/*` route, or a user/API-key credential presented at `/api/internal/v1/*`, is rejected by the strict `token_use`/audience separation with no fallback validator (§7, §17.3) — covered in full in the threat model (§29).
- **Central-issuer compromise** is now the single highest-consequence internal-auth failure mode (concentrating what was previously N independent per-deployable keys into one): compromise of the issuer's private key would allow forging tokens for any `service_id`. This is mitigated the same way user-facing-keypair compromise already is — key rotation policy (180 days, or faster on detected compromise), short (5-minute) token TTL bounding the blast radius of any single forged token, and the issuer being a narrowly-scoped internal capability (not internet-reachable, not a tenant-facing surface) rather than a broadly-exposed service. This trade-off (concentrated risk, smaller overall attack surface, no per-deployable key sprawl) is the explicit reason ADR-6B-11 chose centralization — see §29 for the full threat-model entry.

### 17.5 Audit

Internal-authenticated writes to `audit.audit_events` use `actor_type='WORKER'` (or `'SYSTEM'`/`'INTEGRATION'`/`'PLUGIN'` as appropriate — 5J's full 7-value CHECK constraint: `USER, API_KEY, SYSTEM, WORKER, PLUGIN, PLATFORM_ADMIN, INTEGRATION`). `fn_insert_audit_event` additionally **enforces at the DB level** that only sessions authenticated as `app_worker` or `app_platform_admin` may write a platform-scoped (`organization_id IS NULL`) audit event — a second, independent enforcement point beyond the API-layer check. Central-issuer issuance failures (workload-identity authentication rejected, issuer unavailable) are observable via structured logs and a dedicated metric (§26) — this is operational telemetry, not a durable `audit.audit_events` row, since minting an internal token is not itself one of 5J's audited action kinds and this document does not add one (§25, hard boundary).

**Failure behavior (restated for the ordinary per-call validation path, distinct from issuer-side issuance failure above):** invalid/expired/wrong-`token_use` internal token presented to a resource/API service → `401`, logged with `service_id` (if parseable) but never processed as a fallback anonymous or public-user request.

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

### 18.3a Break-glass runtime authorization (corrected this pass — how every subsequent elevated request proves the grant)

**Problem being corrected:** §18.3/§21.4 fully specify how a grant is *obtained* and *released*, but the prior draft did not specify how an admin's **subsequent** requests — the actual cross-tenant reads/actions performed under an open grant — prove they are covered by that grant. Without this, `TenantContext` could not be safely set to the target tenant for a *specific* elevated request; this section closes that gap.

**Mechanism — a dedicated header carries the grant identity on every elevated request:**

```
X-Break-Glass-Grant: <grant_id>
```

(Named to match this document's existing custom-header style, e.g. `X-Api-Key`, `X-Platform-Signature` in 6A §21 — no `X-`-avoidance convention exists elsewhere in this platform's API to deviate from.)

**Per-request validation contract — run for every request an authenticated platform admin makes to a tenant-scoped route while intending to act under break-glass:**

```
1. Authenticate platform admin (§7, §18.1) — ordinary access-token validation,
   including the forced-revocation denylist check (§12.4). This step alone
   proves identity, not elevated tenant access (§18.2).
2. Require PlatformAdminOnly (§18.2) — actor-type check.
3. Read X-Break-Glass-Grant from the request.
     missing → 403 BREAK_GLASS_GRANT_INVALID (§22) — an ordinary platform-admin
               JWT by itself is never sufficient for tenant-scoped data (§18.3a
               invariant, restated from §31's existing authorization-matrix row).
4. Load the grant's live state from Redis (platform_admin:break_glass:{grant_id},
   §18.3/§24 — the interim, non-durable mechanism; durable persistence is
   DEP-6B-01, §36.3, and does not block this runtime contract).
     Redis unavailable → 503 DEPENDENCY_UNAVAILABLE. Break-glass access is
     DENIED, never allowed, when the grant store cannot be consulted — this
     is fail-closed by construction (§5.3), not a special case invented for
     this section.
5. Verify, in order, failing closed at the first mismatch:
     a. grant exists (Redis key present)                    → else 403 BREAK_GLASS_GRANT_INVALID
     b. grant not expired (now < expires_at)                 → else 403 BREAK_GLASS_GRANT_INVALID
     c. grant not released (release flag not set)            → else 403 BREAK_GLASS_GRANT_INVALID
     d. grant.admin_user_id == authenticated admin's user_id → else 403 BREAK_GLASS_GRANT_INVALID
     e. grant.session_id == current admin session_id         → else 403 BREAK_GLASS_GRANT_INVALID
        (session-binding — a grant is bound to the admin session that opened
        it, §18.3a below; a stolen/replayed access token from a *different*
        session cannot ride an existing grant even if steps a–d all pass)
     f. grant.organization_id == the requested target tenant → else 403 BREAK_GLASS_GRANT_INVALID
        (the path/resource's own organization_id, resolved the same way any
        tenant-scoped route resolves it — §9.1 — never a client-asserted value)
   All six failure branches return the **same** generic code and message —
   deliberately not distinguished in the response body (§22's safe-error-
   behavior rule, applied here exactly as it already is for INVALID_CREDENTIALS,
   §21): an attacker probing with a guessed/expired/foreign grant_id learns
   nothing about which check failed. Full detail (which check failed) is
   available only in the structured log/audit trail, never the API response.
6. Only after all six checks pass: TenantContext.set(grant.organization_id) —
   never before, and never implicitly from the admin's own JWT alone (step 1
   is authentication, not tenant authorization; steps 2–5 are what actually
   authorizes the cross-tenant context switch).
7. Process the request under the target tenant's context, RLS included (§9,
   unchanged — break-glass does not bypass RLS, it is the API-layer path that
   is allowed to set TenantContext to a tenant other than the admin's own,
   which for a PLATFORM_ADMIN actor has no ordinary-membership tenant anyway).
8. Include grant_id in the audit metadata/correlation for the elevated action
   performed (§25) — every action taken under an open grant is attributable to
   that specific grant_id, not merely to "some platform admin, some time."
```

**Fail-closed summary (task-mandated, restated as this contract's guarantees):**

| Condition | Result |
|---|---|
| Redis unavailable | `503 DEPENDENCY_UNAVAILABLE` — break-glass access denied, never allowed |
| Missing `X-Break-Glass-Grant` header on an elevated request | `403 BREAK_GLASS_GRANT_INVALID` |
| Grant does not exist | `403 BREAK_GLASS_GRANT_INVALID` |
| Grant expired | `403 BREAK_GLASS_GRANT_INVALID` |
| Grant released | `403 BREAK_GLASS_GRANT_INVALID` |
| Grant is for Org A, request targets Org B | `403 BREAK_GLASS_GRANT_INVALID` — a grant never authorizes any tenant but the one it names |
| Grant was opened by Admin A, request authenticated as Admin B | `403 BREAK_GLASS_GRANT_INVALID` — one admin can never use another admin's grant |
| Grant was opened under session S1, request authenticated under session S2 (same admin, different session) | `403 BREAK_GLASS_GRANT_INVALID` — session-bound, not merely admin-bound |
| Ordinary platform-admin JWT, no grant at all, against a tenant-scoped route | `403 AUTHORIZATION_DENIED` (§31's existing row — platform-admin status alone never satisfies ordinary tenant RBAC; this is the *no-grant* case, distinct from the *invalid-grant* case above only in that no `X-Break-Glass-Grant` header was even presented as an attempt) |
| Automatic TTL expiry mid-use | Enforced by check 5b on every subsequent request — no separate sweep/cron is required for correctness, since every request re-checks `expires_at` live; a background reaper may still exist operationally to clean up expired Redis keys, but is not load-bearing for the security guarantee |
| Explicit release mid-use | Enforced immediately by check 5c — the very next request under that `grant_id` is denied, with no propagation delay (single Redis read, not a cached/eventually-consistent flag) |

**No implicit target-org switching, no permanent cross-tenant context:** `TenantContext` is set to the target tenant **only** for the lifetime of a single request that presents a valid `X-Break-Glass-Grant` header passing all six checks — it is not "sticky" on the admin's session or connection. A subsequent request without the header (or with a different/invalid one) is evaluated as an ordinary platform-admin request against whatever tenant context it would otherwise resolve to (i.e., none, for a platform admin with no ordinary membership) — never as an inherited continuation of a prior grant.

**Multiple simultaneous grants (task-required decision):** an admin **may** hold multiple simultaneous grants, provided each is separately identified by its own `grant_id` (e.g., investigating two different tenants' tickets concurrently). Each individual request must select **exactly one** grant via the header — there is no mechanism for a request to implicitly combine or fall back across multiple held grants, and no connection/request may inherit a previously-used grant implicitly (every request re-presents the header and is re-validated from scratch, step 3–6 above, with no per-connection "remembered" grant state). This keeps the audit trail for every elevated action attributable to one specific grant, never an ambiguous "one of the admin's several open grants."

**Durable grant persistence remains a future Phase 5.x dependency (DEP-6B-01, §36.3), unchanged by this section** — this section fully specifies **runtime authorization** using the same interim Redis-backed grant record already described in §18.3/§21.4/§24, adding only the fields runtime validation needs (`admin_user_id`, `session_id`, `organization_id`, `expires_at`, a released flag) to that existing Redis record shape — no new storage technology, no Phase 5 table, no schema change.

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

Credential transport (browsers cannot set arbitrary headers on the WS handshake): `?token=<access_token>` query param, or `Sec-WebSocket-Protocol` subprotocol header — same access-token or API-key validators as REST (§7), applied at `CONNECTING → AUTHENTICATED`, **including the forced-revocation denylist check (§12.4)** — a force-revoked access token is rejected at handshake exactly as it would be on any `/api/v1/*` route, not only on REST. Tenant resolution identical to REST (§9). Every connection is bound to exactly one `organization_id` for its lifetime — no cross-tenant multiplexing on one socket (6A §27.4).

### 19.3 Mid-connection concerns

- **Token expiry mid-connection:** since the access token is short-lived (15 min) and a WS connection may live longer, the connection is held authenticated for its own session lifetime once `AUTHENTICATED` (no per-message re-verification) but is force-closed (`CLOSING → CLOSED`, code indicating re-auth required) at the earlier of (a) the access token's `exp`, or (b) session revocation or forced-token-revocation detected via the heartbeat/presence-key mechanism (6A §27) — the presence key itself is tagged with the session's revocation status **and** re-checks the connection's `jti` against `auth:revoked_jti:{jti}` on write, so both a revoked session and a force-revoked access token close their associated sockets within one heartbeat interval, not left open indefinitely. This is the corrected behavior for this pass: forced revocation is no longer a REST-only check that leaves an already-open WS connection unaffected.
- **Revoked credentials (routine session revocation):** handled the same way — a revoked session closes its associated WS connections at the next heartbeat check.
- **Reconnect:** client responsibility (exponential backoff+jitter, 6A §27), re-authenticates from `CONNECTING` again with a valid (possibly refreshed), non-denylisted access token.
- **Disconnect:** subscription-scoped channels re-verify RBAC permission on subscribe, not only at connect (6A §27.4) — a permission revoked mid-connection blocks the *next* subscribe/resubscribe, though (consistent with §19.3's no-per-message-reverification design) does not itself force-close an already-bound subscription mid-stream; this is the same bounded-exposure trade-off as §12.4, inherited from 6A rather than newly introduced here.
- **Rate limiting / connection limits:** 5 concurrent connections per source, NGINX-enforced (6A §27, unchanged); connection-*attempt* rate limiting (distinct from concurrent-connection count) is defined in §21.

---

## 20. Endpoint Inventory

**36 REST endpoints** (35 in the prior draft + 1 — `POST /api/v1/auth/organization/select`, added this pass to close the multi-organization login gap, §9.3), grouped by capability. **Every one of the 36 is fully expanded in §21** with concrete values for every field of the shared template (§21.0) — none is left as "apply the template" only, correcting this pass's blocker on that point. The central internal token issuer (§17.2) is **not** counted here — per the task's own framing, it is an internal platform capability, not a public/internal-API-surface endpoint with its own inventory row, rate limit, or OpenAPI entry.

### 20.1 Authentication (14)

| # | Method & Path | Purpose | Auth | Actor | Tenant scope | Permission | Rate limit | Latency tier (6A) |
|---|---|---|---|---|---|---|---|---|
| 1 | `POST /api/v1/auth/register` | Create a `PENDING_VERIFICATION` user | None | — | None | — | 5/hour/IP | Standard |
| 2 | `POST /api/v1/auth/login` | Password login → session + tokens, or a continuation/challenge token (§9.3) | None (credentials in body) | — | Resolved from membership post-auth, or deferred to org-selection (§9.3) | — | 5/15min per email, 20/15min per IP | Standard |
| 3 | `POST /api/v1/auth/organization/select` | Consume a login-continuation token, select one allowed organization (§9.3) | Login-continuation token (body) | USER (mid-login) | Target org, validated against the token's embedded allowed set + live status | — | 10/15min per continuation-token subject | Fast |
| 4 | `POST /api/v1/auth/logout` | Revoke current session | Access token | USER | Own session | — | 60/hour | Fast |
| 5 | `POST /api/v1/auth/token/refresh` | Rotate refresh → new access+refresh, via atomic conditional UPDATE, no API-layer lock (§13.2) | Refresh token (body/cookie) | USER | Own session | — | 30/hour/session | Fast |
| 6 | `POST /api/v1/auth/email/verify` | Consume verification token | Token (body) | — | — | — | 10/hour/IP | Standard |
| 7 | `POST /api/v1/auth/email/verify/resend` | Resend verification email | Access token or unauth+email | USER | Self | — | 3/hour/email | Standard |
| 8 | `POST /api/v1/auth/password/reset` | Request reset (always 200) | None | — | — | — | 3/hour/email, 10/hour/IP | Standard |
| 9 | `POST /api/v1/auth/password/reset/confirm` | Consume token, set new password, revoke all sessions | Token (body) | — | — | — | 10/hour/IP | Standard |
| 10 | `POST /api/v1/auth/password/change` | Change password (current required) | Access token | USER | Self | — | 10/hour/user | Standard |
| 11 | `POST /api/v1/auth/invitations/accept` | Consume invitation token, activate Membership, issue session | Token (body) | — | Target org (from token) | — | 10/hour/IP | Standard |
| 12 | `GET /api/v1/auth/oauth/{provider}/authorize` | Redirect to IdP | None | — | — | — | 20/hour/IP | Fast |
| 13 | `GET /api/v1/auth/oauth/{provider}/callback` | Exchange code, upsert identity, issue session | None (code in query) | — | Resolved post-exchange | — | 20/hour/IP | Standard |
| 14 | `DELETE /api/v1/auth/oauth/{provider}` | Unlink | Access token | USER | Self | — | 10/hour/user | Standard |

### 20.2 MFA (3)

| # | Method & Path | Purpose | Auth | Rate limit | Latency tier |
|---|---|---|---|---|---|
| 15 | `POST /api/v1/auth/mfa/enroll` | Generate TOTP secret, return provisioning URI once | Access token | 5/hour/user | Standard |
| 16 | `POST /api/v1/auth/mfa/verify` | Verify TOTP code (enrollment confirm via access token, or login step-up via `mfa_challenge_token`, §11.4) | Access token **or** `mfa_challenge_token` (mutually exclusive per call) | 5/15min/user (lockout-style) | Fast |
| 17 | `DELETE /api/v1/auth/mfa` | Disable MFA (password required) | Access token | 5/hour/user | Standard |

### 20.3 Identity Context (1)

| # | Method & Path | Purpose | Auth | Rate limit | Latency tier |
|---|---|---|---|---|---|
| 18 | `GET /api/v1/auth/me` | Return current `AuthenticationContext` | Access token or API key | 300/min/user | Fast |

### 20.4 Sessions (4)

| # | Method & Path | Purpose | Auth | Rate limit | Latency tier |
|---|---|---|---|---|---|
| 19 | `GET /api/v1/sessions` | List own sessions (cursor-paginated) | Access token | 60/hour | Standard |
| 20 | `GET /api/v1/sessions/me` | Get session behind current token | Access token | 300/min | Fast |
| 21 | `DELETE /api/v1/sessions/{session_id}` | Revoke one owned session | Access token | 60/hour | Fast |
| 22 | `DELETE /api/v1/sessions` | Revoke all except current | Access token | 20/hour | Standard |

### 20.5 API Keys (4)

| # | Method & Path | Purpose | Auth | Permission | Rate limit | Latency tier |
|---|---|---|---|---|---|---|
| 23 | `POST /api/v1/organizations/{organization_id}/api-keys` | Create (raw key returned once) | Access token | `api_key:manage` | 10/day/org | Standard |
| 24 | `GET /api/v1/organizations/{organization_id}/api-keys` | List (metadata only) | Access token or API key | `api_key:read` | 60/hour | Standard |
| 25 | `GET /api/v1/organizations/{organization_id}/api-keys/{api_key_id}` | Get metadata | Access token or API key | `api_key:read` | 120/hour | Fast |
| 26 | `DELETE /api/v1/organizations/{organization_id}/api-keys/{api_key_id}` | Revoke | Access token | `api_key:manage` | 30/hour/org | Fast |

### 20.6 Authorization / RBAC Catalog (7)

| # | Method & Path | Purpose | Auth | Permission | Rate limit | Latency tier |
|---|---|---|---|---|---|---|
| 27 | `GET /api/v1/permissions` | Platform-wide permission catalog | Access token or API key | — (read-only, no tenant scope) | 60/min | Fast |
| 28 | `GET /api/v1/organizations/{organization_id}/roles` | List roles (system + custom) visible to org | Access token or API key | `role:read` | 60/min | Fast |
| 29 | `POST /api/v1/organizations/{organization_id}/roles` | Create custom role | Access token | `role:manage` | 20/hour/org | Standard |
| 30 | `GET /api/v1/organizations/{organization_id}/roles/{role_id}` | Get role detail | Access token or API key | `role:read` | 120/hour | Fast |
| 31 | `PATCH /api/v1/organizations/{organization_id}/roles/{role_id}` | Update custom role's permission set (blocked if `is_system`) | Access token | `role:manage` | 30/hour/org | Standard |
| 32 | `DELETE /api/v1/organizations/{organization_id}/roles/{role_id}` | Delete custom role (blocked if `is_system` or in use) | Access token | `role:manage` | 20/hour/org | Standard |
| 33 | `POST /api/v1/auth/authorize/check` | Explicit permission-check (exposes the `CheckPermission` OHS) | Access token or internal token | — (self-check only) | 300/min | Fast |

### 20.7 Platform Admin (3)

| # | Method & Path | Purpose | Auth | Permission | Rate limit | Latency tier |
|---|---|---|---|---|---|---|
| 34 | `POST /api/v1/platform-admin/organizations/{organization_id}/break-glass` | Grant time-boxed cross-tenant access | Access token | `PlatformAdminOnly` | 20/day/admin | Standard |
| 35 | `POST /api/v1/platform-admin/break-glass/{grant_id}/release` | Release grant early | Access token | `PlatformAdminOnly` | 20/day/admin | Fast |
| 36 | `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all` | Force-logout a user (all sessions, denylist every known current jti — §12.4) | Access token | `PlatformAdminOnly` | 50/day/admin | Standard |

All rate-limit figures are **configurable defaults**, not benchmarked production numbers (§23, per task's anti-fabrication rule).

**Header note applying to every tenant-scoped endpoint above when the caller is a `PLATFORM_ADMIN` acting under break-glass:** `X-Break-Glass-Grant: <grant_id>` (§18.3a) is required in addition to whatever this table lists as that endpoint's own headers — it is a cross-cutting header, not restated per-row in this inventory table, and its absence/invalidity produces `403 BREAK_GLASS_GRANT_INVALID` (§22) before the endpoint's own handler runs.

---

## 21. Endpoint Contracts

### 21.0 Shared template (applies to every endpoint in §20)

Every endpoint's contract instantiates: Purpose, Method & Path, Authentication, Authorization, Actor, Tenant Context, Path Params, Query Params, Headers, Request Schema, Validation, Response (status + schema), Errors, Rate Limit, Idempotency, Latency, Database, Cache, Audit, Security, Observability, Side Effects, and Concurrency/Consistency notes where applicable — using 6A's envelope (`{data, meta}` success / `{error}` failure), 6A's error object shape, and 6A's `request_id`/correlation propagation throughout. **Every one of the 36 endpoints below instantiates this template with concrete values** — this pass corrects the prior draft's reliance on "apply the template" for all but a handful of endpoints. Where a field is genuinely not applicable to a given endpoint (e.g., no path parameters on a fixed-path POST), it is stated as such explicitly rather than omitted silently.

**Rules that apply identically to every endpoint below and are not repeated per-row:** every response uses 6A's `{data, meta}`/`{error}` envelope (§22); every `request_id` is propagated per 6A §26; every rate-limit figure is a configurable default, not a benchmark (§23); every latency figure is a TARGET, not a MEASURED number (§27); every audit write not marked synchronous goes through the normal async pipeline (§25); every endpoint that is `PLATFORM_ADMIN`-only additionally requires `X-Break-Glass-Grant` validation (§18.3a) whenever it operates against a tenant other than none (i.e., whenever it is invoked as a break-glass action rather than a platform-scoped action) — restated per-endpoint below only where it actually applies.

---

### 21.1 `POST /api/v1/auth/login`

- **Purpose:** Primary authentication — exchange email+password for either (a) a session (access + refresh tokens), (b) an MFA challenge, or (c) an organization-selection continuation, per §9.3's ordering.
- **Authentication:** None (this endpoint establishes it).
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller, becomes `USER` on success.
- **Tenant Context:** None at request time — resolved from the user's memberships after credential verification (§9.3); never guessed, never client-supplied.
- **Path/Query Params:** None.
- **Headers:** Standard (`Content-Type: application/json`); no auth header.
- **Request Schema:** `{ "email": "user@example.com", "password": "••••••••" }`.
- **Validation:** `email` well-formed (Pydantic), `password` non-empty, both required; unknown fields rejected (6A strict-schema rule).
- **Response `200` — one of three shapes, per §9.3:**
  - **(a) Direct success** (single active membership, MFA disabled):
    ```json
    { "data": { "access_token": "eyJhbGciOiJSUzI1NiIs...", "refresh_token": "018f2c9e-....7f8a9b0c1d2e",
                "token_type": "Bearer", "expires_in": 900,
                "organization_id": "018f2c9e-3a1b-7d4f-ad2b-2b3c4d5e6f7a" },
      "meta": { "request_id": "01930000-0000-7000-8000-000000000000" } }
    ```
  - **(b) Organization selection required** (§9.3, more than one active membership):
    ```json
    { "data": { "requires_organization_selection": true,
                "continuation_token": "eyJhbGciOiJSUzI1NiIs...",
                "allowed_organizations": [
                  {"organization_id": "018f2c9e-3a1b-...", "organization_name": "Acme Inc"},
                  {"organization_id": "018f2c9e-4b2c-...", "organization_name": "Beta LLC"}
                ],
                "expires_in": 300 },
      "meta": { "request_id": "..." } }
    ```
  - **(c) MFA challenge required** (single membership, `mfa_enabled=true` — organization already resolved internally, §9.3):
    ```json
    { "data": { "mfa_required": true, "mfa_challenge_token": "eyJhbGciOiJSUzI1NiIs...", "expires_in": 300 },
      "meta": { "request_id": "..." } }
    ```
- **Errors:** `401 INVALID_CREDENTIALS` (generic — covers both wrong password and non-existent email, never distinguished, §22); `403 ACCOUNT_SUSPENDED` (only after successful credential check); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 5/15min per email (post-normalization), 20/15min per IP — composite, not IP-only (§23).
- **Idempotency:** N/A — not a mutating resource-creation call in the 6A idempotency-key sense; safe to retry on genuine failure since password verification has no side effect other than lockout-counter updates, which are themselves monotonic and safe to re-increment on a true retry of a genuinely-failed attempt.
- **Latency:** Standard tier (p50 <150ms / p99 <500ms target, §27) — dominated by Argon2id verification cost, deliberately expensive.
- **Database:** `identity.users` (read), `organization.memberships` (read, to resolve allowed organizations); `identity.sessions` (insert) **only** on shape (a) — shapes (b)/(c) create no session row (§9.3).
- **Cache:** None on the write path; permission cache is warmed lazily on first authorized request, not at login.
- **Audit:** `USER_LOGIN` (success, shape (a)) / `USER_LOGIN_FAILED` (failure) — both existing 5J `action_kind` values. Shapes (b)/(c) are intermediate steps, not yet a completed login — logged via metrics (§26), not yet `USER_LOGIN` until the flow actually completes (§9.3).
- **Security:** Argon2id timing is inherently near-constant regardless of match/mismatch; failure response is identical for "no such user" and "wrong password"; `failed_login_count`/`last_failed_login_at` updated on `identity.users` for lockout accounting (§23).
- **Observability:** `auth_login_attempts_total{result}`, latency histogram.
- **Side Effects:** Session row created only on shape (a); no side effect on shapes (b)/(c) beyond the ephemeral, stateless JWTs issued (no Redis/DB write for either ephemeral token type, §11.4–§11.5).
- **Concurrency/Consistency:** None required — a stateless read-mostly path; two concurrent logins for the same user are independent and each produces its own session (§12.6).

### 21.2 `POST /api/v1/auth/token/refresh`

- **Purpose:** Rotate a refresh token for a new access+refresh pair via an atomic conditional `UPDATE` (CAS), with no API-layer lock (§13.2).
- **Authentication:** Refresh token only (no access token required — it may already be expired).
- **Authorization:** N/A (session-identity check only).
- **Actor:** `USER` (identified via the session, not a separate credential check).
- **Tenant Context:** Own session's `organization_id` — unchanged by refresh.
- **Path/Query Params:** None.
- **Headers:** Standard.
- **Request Schema:** `{ "refresh_token": "<session_id>.<secret>" }`.
- **Validation:** `refresh_token` non-empty, parses into a well-formed `{session_id}.{secret}` pair (§13.1) — malformed shape is itself a `401 INVALID_REFRESH_TOKEN`, not a `400`, to avoid distinguishing malformed-syntax from wrong-value at the response level.
- **Response `200`:** `{ "data": { "access_token": "...", "refresh_token": "<session_id>.<new_secret>", "token_type": "Bearer", "expires_in": 900 }, "meta": {...} }`.
- **Errors:** `401 INVALID_REFRESH_TOKEN` (not found / expired / wrong status); `401 REFRESH_TOKEN_REUSE_DETECTED` (hash mismatch against a found active session — §13.3, session force-revoked as a side effect); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 30/hour per session.
- **Idempotency:** Explicitly **not** idempotent and carries **no** `Idempotency-Key` support (§13.2a) — each successful call rotates the token; a retry of a successful rotation with the now-superseded token triggers reuse detection (§13.3, §13.6) by design.
- **Latency:** Fast tier (<10ms/<40ms target, §27) — single atomic conditional `UPDATE` by PK, no Argon2id cost, no API-layer lock acquired (§13.2).
- **Database:** `identity.sessions` — one atomic `UPDATE ... WHERE id = :session_id AND status = 'ACTIVE' AND expires_at >= now() AND refresh_token_hash = :presented_hash RETURNING ... ` (§13.2, corrected this pass from a prior `SELECT ... FOR UPDATE` design — no API-layer lock, per frozen 6A §17.3); a follow-up unlocked `SELECT` only on the zero-rows-affected path to distinguish the specific error.
- **Cache:** None.
- **Audit:** Reuse detection → structured log + metric only (§13.3 gap, ADR-6B-06); routine rotation is not separately audited beyond metrics (high-frequency, low-security-value event by itself).
- **Security:** See §13.1–§13.3, §13.6.
- **Observability:** `auth_token_refresh_total`, `auth_token_refresh_failures_total`, `auth_refresh_reuse_detected_total`.
- **Side Effects:** `identity.sessions.refresh_token_hash`/`access_token_jti`/`last_seen_at` updated on success; `status=REVOKED` on reuse detection.
- **Concurrency/Consistency:** **Exactly one of N concurrent requests presenting the same refresh token succeeds; all others fail as reuse or as invalid**, guaranteed by the atomic conditional `UPDATE`'s own row-affected semantics (§13.2) — no API-layer lock is involved; this is the corrected guarantee this pass's blocker required, verified by the concurrency test in §32.

### 21.3 `POST /api/v1/auth/authorize/check`

- **Purpose:** Expose the `CheckPermission` OHS (4A) directly, primarily for internal/frontend UI-gating use (e.g., "should I show this button").
- **Authentication:** Access token or internal service token.
- **Authorization:** Self-check only — a caller may only ask about its own resolved `AuthenticationContext`; no "check permission for another user" capability exists here.
- **Actor:** `USER`, `API_KEY`, or internal `SERVICE` principal.
- **Tenant Context:** Caller's own resolved `organization_id` (JWT claim or API-key lookup, §9).
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** `{ "permission": "campaign:write" }`.
- **Validation:** `permission` must match the `resource:action` catalog format (§8, §16.2); a syntactically-valid but non-catalog string is `400 VALIDATION_ERROR`, not a silent `allowed:false`.
- **Response `200`:** `{ "data": { "allowed": true } }` — deliberately `200` even when `allowed: false` (a query about authorization, not the authorized action itself).
- **Errors:** `401` (no valid credential); `400 VALIDATION_ERROR` (permission string not in the catalog).
- **Rate Limit:** 300/min/user.
- **Idempotency:** N/A — GET-shaped query semantics despite the POST verb (chosen because the permission string is more naturally a body than a query string per 6A's own convention for structured non-CRUD queries); side-effect-free, safe to retry freely.
- **Latency:** Fast tier (<5ms/<20ms cache-hit, §27) — cache-hit path only touches Redis.
- **Database:** DB fallback only on cache miss (§8, §23).
- **Cache:** `rbac:permissions:{organization_id}:{user_id}`.
- **Audit:** Not audited individually (read-only query; the actual gated action, when performed, is what gets audited).
- **Security:** Never reveals another actor's permissions; never reveals the full role→permission matrix (that's `GET .../roles/{role_id}`, permission-gated separately).
- **Observability:** `auth_authorization_denied_total{permission}` (on `allowed:false` only).
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A — pure read.

### 21.4 `POST /api/v1/platform-admin/organizations/{organization_id}/break-glass`

- **Purpose:** Grant a time-boxed, audited, cross-tenant access window (§18.3).
- **Authentication:** Access token, actor must be `PLATFORM_ADMIN`.
- **Authorization:** `PlatformAdminOnly` — actor-type check, not an RBAC permission. **This endpoint itself does not require `X-Break-Glass-Grant`** — it is the endpoint that *creates* a grant, not an action performed under one (§18.3a's header requirement applies to subsequent tenant-scoped requests, not to this one).
- **Actor:** `PLATFORM_ADMIN`.
- **Tenant Context:** The *target* `organization_id` is the path parameter — explicitly cross-tenant by design, the one class of endpoint where that is intentional and audited rather than denied.
- **Path Params:** `organization_id` (UUID, target tenant).
- **Query Params:** None.
- **Headers:** Standard bearer auth; optional `Idempotency-Key` (below).
- **Request Schema:** `{ "justification": "Investigating billing dispute #4471, ticket JIRA-2291", "duration_minutes": 60 }`.
- **Validation:** `justification` required, minimum length enforced (non-trivial free text); `duration_minutes` required, bounded (e.g. 5–240, configurable default, not benchmarked, §23).
- **Response `201`:** `{ "data": { "grant_id": "...", "organization_id": "...", "admin_user_id": "...", "session_id": "...", "expires_at": "..." } }` — `admin_user_id`/`session_id` are included so the client (an admin console) can display which identity/session the grant is bound to (§18.3a).
- **Errors:** `401`; `403 AUTHORIZATION_DENIED` (not a platform admin); `400 VALIDATION_ERROR` (missing/too-short justification, or `duration_minutes` outside allowed bound); `404 RESOURCE_NOT_FOUND` (target org doesn't exist — the one place a platform-admin-facing 404 is *not* concealing tenant existence from a peer, since the actor is platform-scoped by definition); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 20/day/admin.
- **Idempotency:** `Idempotency-Key` supported (6A standard) — a retried grant request with the same key returns the original grant, not a second one.
- **Latency:** Standard tier (<50ms/<150ms target, §27) — includes the synchronous audit write.
- **Database:** No durable grant-lifecycle table exists (Phase 5 gap, DEP-6B-01, §36.3) — grant state is Redis-resident only (`platform_admin:break_glass:{grant_id}`, §18.3a/§24), now storing `admin_user_id`, `session_id`, `organization_id`, `expires_at`, and a released flag (§18.3a). `audit.audit_events` (insert, synchronous).
- **Cache:** Writes the Redis grant record above, TTL = `duration_minutes`.
- **Audit:** `BREAK_GLASS_GRANTED`, written **synchronously** (§18.3) — the one exception to async audit in this document.
- **Security:** Grant is bound to the issuing admin's `user_id` **and** current `session_id` at creation (§18.3a) — a later request under a different session of the same admin cannot use it.
- **Observability:** dedicated grant-issuance counter (§26).
- **Side Effects:** Creates the Redis grant record; writes the synchronous audit event.
- **Concurrency/Consistency:** An admin may hold multiple simultaneous grants, each independently identified by `grant_id` (§18.3a) — this endpoint does not enforce a single-active-grant-per-admin limit.

---

### 21.5 `POST /api/v1/auth/register`

- **Purpose:** Create a new `PENDING_VERIFICATION` user.
- **Authentication:** None.
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller, becomes `USER` (`PENDING_VERIFICATION`) on success.
- **Tenant Context:** None — registration is not itself membership creation (org invitation/creation is out of scope here, §3.2).
- **Path/Query Params:** None.
- **Headers:** Standard.
- **Request Schema:** `{ "email": "user@example.com", "password": "••••••••", "display_name": "Jane Doe" }` (exact optional-field set per `identity.users`' actual nullable columns — no field invented beyond 5B).
- **Validation:** `email` well-formed and not already registered (`409 STATE_CONFLICT` — not `400`, since the request is well-formed but conflicts with existing state; response does **not** distinguish "already registered" wording that would leak account existence beyond what registration inherently requires the caller to learn, since the caller supplied the email themselves); `password` meets minimum complexity policy (length-based, Argon2id-appropriate — no fabricated complexity rule beyond what 5B implies).
- **Response `201`:** `{ "data": { "user_id": "...", "email": "...", "status": "PENDING_VERIFICATION" }, "meta": {...} }` — no token issued; email verification is a separate step (§21.8).
- **Errors:** `400 VALIDATION_ERROR`; `409 STATE_CONFLICT` (email already registered); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 5/hour/IP.
- **Idempotency:** Not `Idempotency-Key`-bearing; a retried identical registration for an already-existing email is caught by the `409` above, which is itself the effective duplicate-submission guard for a `POST`-create endpoint without an idempotency key.
- **Latency:** Standard tier — Argon2id hashing cost on the password.
- **Database:** `identity.users` (insert).
- **Cache:** None.
- **Audit:** `USER_REGISTERED` (5J).
- **Security:** Password never logged; Argon2id hash only persisted.
- **Observability:** `auth_registration_total{result}`.
- **Side Effects:** Triggers an email-verification send (out-of-band, not itself an API call this document specifies beyond the token issuance in `identity.password_reset_tokens`, §15.4).
- **Concurrency/Consistency:** Unique constraint on `email` is the actual race-safety mechanism for two simultaneous registrations of the same address — the second fails `409` at the DB constraint, not a pre-check-then-insert race.

### 21.6 `POST /api/v1/auth/organization/select`

- **Purpose:** Consume a login-continuation token and select one organization from the caller's own allowed set (§9.3).
- **Authentication:** Login-continuation token (§11.5) — **not** an access token; presented in the request body (or `Authorization: Bearer`, implementation's choice, §7).
- **Authorization:** N/A as an RBAC check — the authorization here **is** the token's embedded allowed-membership set plus live re-validation (§9.3).
- **Actor:** `USER`, mid-login (no session yet).
- **Tenant Context:** The selected `organization_id`, validated against the token's embedded set and live membership/organization status — never trusted from the request body alone.
- **Path/Query Params:** None.
- **Headers:** Standard; continuation token via `Authorization: Bearer` or body field (implementation's choice, consistent across the codebase).
- **Request Schema:** `{ "organization_id": "018f2c9e-3a1b-...", "continuation_token": "eyJhbGciOiJSUzI1NiIs..." }`.
- **Validation:** `organization_id` well-formed UUID; `continuation_token` well-formed JWT, `token_use=login_continuation`, `aud=platform-org-select`, unexpired.
- **Response `200` — one of two shapes, per §9.3:**
  - Direct success (MFA disabled): same access/refresh-token shape as §21.1(a).
  - MFA required: same `mfa_required`/`mfa_challenge_token` shape as §21.1(c), now with `organization_id` resolved into the challenge token (§11.4).
- **Errors:** `401` (continuation token expired/malformed/wrong `token_use`/`aud`); `403 ORGANIZATION_SELECTION_INVALID` (`organization_id` not in the token's allowed set, or membership/organization no longer `ACTIVE` — a single generic code, no detail distinguishing which sub-case, §9.3/§22); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 10/15min per continuation-token subject.
- **Idempotency:** Not consumption-tracked (§11.5) — re-submission within the token's TTL is accepted, re-validated fresh each time; not `Idempotency-Key`-bearing (this is a selection, not a resource creation, in 6A's idempotency-key sense).
- **Latency:** Fast tier — signature verification plus one membership/organization status read, no Argon2id cost.
- **Database:** `organization.memberships` (read, live status re-check), `organization.organizations` (read, live status re-check), `identity.sessions` (insert, only on direct-success shape).
- **Cache:** None.
- **Audit:** Not separately audited as its own `action_kind` (no 5J value exists for "organization selected mid-login" and this document does not add one, §25) — folded into the eventual `USER_LOGIN` audit event once the flow completes, with the selected `organization_id` as that event's `organization_id`.
- **Security:** `403 ORGANIZATION_SELECTION_INVALID` never distinguishes "not a member," "organization doesn't exist," or "membership suspended" (§9.3) — the same non-disclosure discipline as ordinary cross-tenant references.
- **Observability:** `auth_organization_select_total{result}`.
- **Side Effects:** Session row created only on the direct-success shape.
- **Concurrency/Consistency:** N/A beyond the live re-validation already specified — no row-lock is needed since this endpoint doesn't rotate any shared secret.

### 21.7 `POST /api/v1/auth/logout`

- **Purpose:** Revoke the caller's own current session.
- **Authentication:** Access token.
- **Authorization:** N/A (self-scoped).
- **Actor:** `USER`.
- **Tenant Context:** Caller's own session's `organization_id` (not otherwise used).
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** N/A.
- **Response `204`:** No content.
- **Errors:** `401` (invalid/expired/revoked access token — including the forced-revocation denylist check, §12.4).
- **Rate Limit:** 60/hour.
- **Idempotency:** Naturally idempotent — revoking an already-`REVOKED` session is a no-op success, not an error.
- **Latency:** Fast tier — single-row update.
- **Database:** `identity.sessions` (update `status=REVOKED`).
- **Cache:** None.
- **Audit:** `USER_LOGOUT` (5J).
- **Security:** Does **not** write a forced-revocation denylist entry (§12.4/§12.5) — the caller's own outstanding access token remains valid until its natural `exp`, the documented, bounded trade-off.
- **Observability:** `auth_session_revocations_total{trigger="self"}`.
- **Side Effects:** Session marked `REVOKED`; no effect on the caller's other sessions.
- **Concurrency/Consistency:** N/A.

### 21.8 `POST /api/v1/auth/email/verify`

- **Purpose:** Consume an email-verification token, set `email_verified_at`, may transition `PENDING_VERIFICATION → ACTIVE`.
- **Authentication:** None (token itself is the credential, §15.4).
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller acting on behalf of the token's subject.
- **Tenant Context:** None.
- **Path/Query Params:** None.
- **Headers:** Standard.
- **Request Schema:** `{ "token": "<opaque verification token>" }`.
- **Validation:** Token well-formed; hashed match against `identity.password_reset_tokens` (`purpose=EMAIL_VERIFICATION`), unexpired, unused.
- **Response `200`:** `{ "data": { "status": "ACTIVE" } }`.
- **Errors:** `401 INVALID_REFRESH_TOKEN`-style generic invalid-token code (reusing the same "not found/expired/used" non-disclosure shape as password reset, §22 — specific catalog code: `400 VALIDATION_ERROR` if malformed, `409 STATE_CONFLICT` if already consumed).
- **Rate Limit:** 10/hour/IP.
- **Idempotency:** Re-submitting an already-consumed token is `409 STATE_CONFLICT`, not a silent `200` — single-use tokens (`identity.password_reset_tokens`) are marked consumed on first use.
- **Latency:** Standard tier.
- **Database:** `identity.password_reset_tokens` (read + mark consumed), `identity.users` (update `email_verified_at`, possibly `status`).
- **Cache:** None.
- **Audit:** `USER_EMAIL_VERIFIED` (5J).
- **Security:** No account-existence disclosure beyond what the token itself already proves possession of.
- **Observability:** `auth_email_verify_total{result}`.
- **Side Effects:** May transition user `status`.
- **Concurrency/Consistency:** Token's single-use constraint (unique consumed-flag/row) prevents two concurrent verifications of the same token from both succeeding — the second sees the row already marked consumed.

### 21.9 `POST /api/v1/auth/email/verify/resend`

- **Purpose:** Resend a verification email.
- **Authentication:** Access token, or unauthenticated + email in body (mirrors password-reset's non-disclosure shape).
- **Authorization:** Self-scoped only when authenticated.
- **Actor:** `USER` or unauthenticated caller.
- **Tenant Context:** None.
- **Path/Query Params:** None.
- **Headers:** Standard; optional bearer auth.
- **Request Schema:** `{ "email": "user@example.com" }` (unauthenticated) or empty body (authenticated — self).
- **Validation:** `email` well-formed if present.
- **Response `200`:** `{ "data": { "sent": true } }` — always this shape regardless of whether the email exists, mirroring password-reset's account-existence non-disclosure (§19/§22).
- **Errors:** `400 VALIDATION_ERROR`; `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 3/hour/email.
- **Idempotency:** Naturally idempotent in effect (always `200`); each call invalidates the prior unconsumed verification token and issues a new one, per `identity.password_reset_tokens`'s single-active-token-per-purpose convention.
- **Latency:** Standard tier.
- **Database:** `identity.users` (read), `identity.password_reset_tokens` (insert, invalidate prior).
- **Cache:** None.
- **Audit:** Not separately audited (a resend of an existing capability, not a new security event category).
- **Security:** Never confirms/denies account existence in the response.
- **Observability:** `auth_email_verify_resend_total`.
- **Side Effects:** New token issued, prior invalidated.
- **Concurrency/Consistency:** N/A.

### 21.10 `POST /api/v1/auth/password/reset`

- **Purpose:** Request a password reset (always `200`, never confirms account existence).
- **Authentication:** None.
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller.
- **Tenant Context:** None.
- **Path/Query Params:** None.
- **Headers:** Standard.
- **Request Schema:** `{ "email": "user@example.com" }`.
- **Validation:** `email` well-formed.
- **Response `200`:** `{ "data": { "sent": true } }` — always, regardless of whether the email exists (§19).
- **Errors:** `400 VALIDATION_ERROR`; `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 3/hour/email, 10/hour/IP.
- **Idempotency:** Effectively idempotent (always `200`); each call issues a fresh single-use token, invalidating any prior unconsumed one.
- **Latency:** Standard tier.
- **Database:** `identity.users` (read), `identity.password_reset_tokens` (insert, `purpose=PASSWORD_RESET`).
- **Cache:** None.
- **Audit:** Not separately audited at request time (only the *confirm* step, §21.11, is a completed security event).
- **Security:** Account-existence non-disclosure is the primary security property of this endpoint.
- **Observability:** `auth_password_reset_request_total`.
- **Side Effects:** New reset token issued (out-of-band email send).
- **Concurrency/Consistency:** N/A.

### 21.11 `POST /api/v1/auth/password/reset/confirm`

- **Purpose:** Consume a reset token, set a new password, durably revoke all existing sessions for that user in one database transaction, then make a **best-effort, separate** attempt to globally denylist every currently-known access-token `jti` for that user (§13.5, corrected this pass — the two are no longer described as one atomic operation).
- **Authentication:** Token (body) — the credential.
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller acting on behalf of the token's subject.
- **Tenant Context:** None.
- **Path/Query Params:** None.
- **Headers:** Standard.
- **Request Schema:** `{ "token": "...", "new_password": "••••••••" }`.
- **Validation:** Token well-formed, hashed match, unexpired, unused; `new_password` meets complexity policy.
- **Response `200` (Case A, §13.5 — both the durable transaction and the Redis denylisting succeeded):**
  ```json
  { "data": {
      "password_reset_completed": true,
      "session_revocation_completed": true,
      "access_token_revocation_completed": true,
      "sessions_revoked": 3
    } }
  ```
- **Response `503 DEPENDENCY_UNAVAILABLE` (Case C, §13.5 — the database transaction committed, but Redis denylisting did not fully complete):** returned using 6A's frozen error envelope (§22, §24 of 6A) — `error.code = DEPENDENCY_UNAVAILABLE`, `error.retryable = false` for this specific case (retrying does **not** re-run the already-committed database step, and does not resume the Redis step — a retry only re-validates the now-already-consumed token, per §13.5), and `error.details` conceptually shaped as:
  ```json
  { "error": {
      "code": "DEPENDENCY_UNAVAILABLE",
      "message": "Password and session reset completed; immediate access-token revocation is incomplete.",
      "details": {
        "password_reset_completed": true,
        "session_revocation_completed": true,
        "access_token_revocation_completed": false
      },
      "request_id": "...",
      "retryable": false
    } }
  ```
  This detail block never includes `jti` values, token material, Redis key names, session IDs, or any other internal implementation detail (§22's never-exposed rule, unchanged) — only the three boolean completion flags a caller/operator needs to know not to treat the account as fully secured yet.
- **Errors:** Generic invalid-token code (`400`/`409`, §22, non-disclosure — covers Case B, §13.5: the database transaction itself failed or the token was invalid/expired/already consumed, so nothing changed); `400 VALIDATION_ERROR` (weak password); `503 DEPENDENCY_UNAVAILABLE` (Case C, above).
- **Rate Limit:** 10/hour/IP.
- **Idempotency:** Re-submission of an already-consumed reset token is `409 STATE_CONFLICT` — **this is unconditional**, including after a prior Case C `503`: the endpoint does **not** promise, and does not implement, resuming unfinished Redis denylisting from a re-presented, already-consumed token (§13.5 — no `password_reset_revocation_pending`/`revocation_delivery_status`/`revocation_outbox` or equivalent durable marker exists to make such a resume safe, and none is invented). A caller that hits Case C and wants a fresh attempt at the denylist step must obtain a new reset token and go through the flow again — which durably re-revokes sessions (harmless, already revoked) and retries the Redis step from scratch.
- **Latency:** Standard tier — Argon2id hashing cost on the new password, plus one database transaction (N atomic session-revoke statements) followed by up to N Redis denylist writes (N = caller's active session count, normally small) as a distinct, subsequent step.
- **Database:** `identity.password_reset_tokens` (read + mark consumed), `identity.users` (update `password_hash`, `password_changed_at`), `identity.sessions` (per-row atomic conditional `UPDATE ... WHERE status='ACTIVE' ... RETURNING access_token_jti`, §13.5 — not a row lock, an ordinary CAS statement per session) — **all inside one transaction, committed before any Redis write is attempted**.
- **Cache:** Writes `auth:revoked_jti:{jti}`, TTL = full 15-minute maximum, **after** the database transaction above has committed — a separate step, not part of that transaction (§13.5, §24).
- **Audit:** `USER_PASSWORD_CHANGED` (5J) — written once the database transaction commits, regardless of the subsequent Redis outcome (the durable security-relevant fact — password changed, sessions revoked — is what this audit event records).
- **Security:** Sessions are durably revoked as part of the same database transaction as the password change — this part is unconditional and cannot be undone by a later Redis failure. Global access-token denylisting is a best-effort step attempted immediately after that commit; when it does not fully succeed (Case C, §13.5), the response honestly reports `access_token_revocation_completed: false` rather than claiming the full security outcome was achieved. This is not a weakening of the security requirement — it is an accurate statement of what a PostgreSQL-plus-Redis architecture with no cross-system transaction coordinator and no Phase-5 durable delivery-tracking mechanism can actually guarantee (DEP-6B-08, §36.3).
- **Observability:** `auth_password_reset_confirm_total{result}` (result includes a distinct value for Case C, e.g. `"partial_revocation"`, distinct from `"success"` and `"failed"`), `auth_session_revocations_total{trigger="password-reset"}`.
- **Side Effects:** Password changed; every session for the user set `REVOKED` (both unconditional once the transaction commits); every known current access-token `jti` denylisted globally **when the subsequent Redis step succeeds** — not guaranteed jointly with the above.
- **Concurrency/Consistency:** Reset token's single-use constraint prevents double-consumption of the password change itself. Session revocation-and-jti-capture uses the same atomic-conditional-`UPDATE`-with-`RETURNING` pattern as refresh rotation (§13.2) — **no `SELECT ... FOR UPDATE` or other API-layer lock**, consistent with frozen 6A §17.3. A refresh racing this flow for the same session cannot escape the *durable* revocation (§13.5's ordering analysis: whichever side's atomic `UPDATE` commits second either fails outright or is the value the other side captures — never both succeeding independently); whether a token produced by that race is *also* denylisted in Redis is governed by the same Case A/B/C analysis as any other session's `jti`, not by anything specific to the race.

### 21.12 `POST /api/v1/auth/password/change`

- **Purpose:** Change password (current password required).
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A (user-global, not tenant-scoped).
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** `{ "current_password": "••••••••", "new_password": "••••••••" }`.
- **Validation:** `current_password` must verify against stored hash; `new_password` meets complexity policy and is not identical to `current_password`.
- **Response `200`:** `{ "data": { "status": "ok" } }`.
- **Errors:** `401 INVALID_CREDENTIALS` (wrong current password); `400 VALIDATION_ERROR` (weak/identical new password).
- **Rate Limit:** 10/hour/user.
- **Idempotency:** Not idempotent in a meaningful sense (each call changes state if it succeeds); no `Idempotency-Key` needed since a retried identical call with the same current/new password pair is naturally safe to re-attempt (same effect either way).
- **Latency:** Standard tier — Argon2id cost twice (verify current, hash new).
- **Database:** `identity.users` (read + update).
- **Cache:** None.
- **Audit:** `USER_PASSWORD_CHANGED` (5J).
- **Security:** Does **not** revoke other sessions by default (distinct from the forced-reset-confirm path, §13.4) — a deliberate, narrower scope decision consistent with "user knowingly changed their own password while already authenticated" being a lower-risk event than a password-reset-token-based recovery.
- **Observability:** `auth_password_change_total{result}`.
- **Side Effects:** `password_hash`/`password_changed_at` updated.
- **Concurrency/Consistency:** N/A.

### 21.13 `POST /api/v1/auth/invitations/accept`

- **Purpose:** Consume an invitation token, activate the associated Membership, and issue a session.
- **Authentication:** Token (body).
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller acting on behalf of the invited user.
- **Tenant Context:** Target org, resolved from the token — never client-supplied.
- **Path/Query Params:** None.
- **Headers:** Standard.
- **Request Schema:** `{ "token": "...", "password": "••••••••" }` (password set only if the invited identity has no existing `password_hash` — new-user invitation path; omitted for an existing user accepting into an additional org).
- **Validation:** Token well-formed, hashed match against `identity.password_reset_tokens` (`purpose=INVITATION`), unexpired, unused; target Membership row still `PENDING`/inactive as expected.
- **Response `200`:** Same access/refresh-token shape as §21.1(a) — organization is already resolved (the invitation's own org), no selection step needed even if the user has other memberships elsewhere.
- **Errors:** Generic invalid-token code (§22); `409 STATE_CONFLICT` (already accepted).
- **Rate Limit:** 10/hour/IP.
- **Idempotency:** Re-submission of an already-consumed invitation is `409 STATE_CONFLICT`.
- **Latency:** Standard tier.
- **Database:** `identity.password_reset_tokens` (read + consume), `organization.memberships` (activate), `identity.users` (create or read), `identity.sessions` (insert).
- **Cache:** None.
- **Audit:** `MEMBER_JOINED` (5J).
- **Security:** Token is the sole proof of authorization to join — no separate email confirmation loop invented here beyond what 5B's token table already provides.
- **Observability:** `auth_invitation_accept_total{result}`.
- **Side Effects:** Membership activated; session created.
- **Concurrency/Consistency:** Token single-use constraint prevents double-acceptance.

### 21.14 `GET /api/v1/auth/oauth/{provider}/authorize`

- **Purpose:** Redirect to the IdP's authorization endpoint (generic shape only, ADR-6B-07).
- **Authentication:** None.
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller.
- **Tenant Context:** None.
- **Path Params:** `provider` (string, from a configured allow-list — an unconfigured provider is `404 RESOURCE_NOT_FOUND`, not a 500).
- **Query Params:** Implementation-defined `redirect_uri`/`state` per standard OAuth2 authorization-code flow — provider-specific detail deferred (ADR-6B-07).
- **Headers:** Standard.
- **Request Schema:** N/A (GET).
- **Validation:** `provider` must be in the configured allow-list.
- **Response `302`:** Redirect to the IdP.
- **Errors:** `404 RESOURCE_NOT_FOUND` (unconfigured provider); `429 RATE_LIMIT_EXCEEDED`.
- **Rate Limit:** 20/hour/IP.
- **Idempotency:** N/A (GET, safe/idempotent by HTTP semantics).
- **Latency:** Fast tier — no DB/Redis I/O, just a redirect.
- **Database:** None.
- **Cache:** None.
- **Audit:** Not audited (no security-decision made yet).
- **Security:** `state` parameter is the CSRF mitigation for the OAuth2 flow itself (standard practice, not further specified here since provider integration is deferred).
- **Observability:** `auth_oauth_authorize_total{provider}`.
- **Side Effects:** None server-side beyond the redirect.
- **Concurrency/Consistency:** N/A.

### 21.15 `GET /api/v1/auth/oauth/{provider}/callback`

- **Purpose:** Exchange the authorization code, upsert `identity.oauth_identities`, issue a session.
- **Authentication:** None (the code itself, exchanged server-side with the IdP, is the credential).
- **Authorization:** N/A.
- **Actor:** Unauthenticated caller becoming `USER` on success.
- **Tenant Context:** Resolved post-exchange, same §9.3 flow as password login (an OAuth-authenticated user with multiple memberships also goes through organization selection).
- **Path Params:** `provider`.
- **Query Params:** `code`, `state` (standard OAuth2).
- **Headers:** Standard.
- **Request Schema:** N/A (GET, params in query).
- **Validation:** `state` matches the value issued at `.../authorize`; `code` exchanges successfully with the IdP.
- **Response:** Same three-shape contract as §21.1 (direct success / organization selection / MFA challenge), since this is just a different primary-authentication method feeding the same post-authentication flow (§9.3).
- **Errors:** `401 INVALID_CREDENTIALS`-equivalent (code exchange failed / `state` mismatch); `403 ACCOUNT_SUSPENDED`.
- **Rate Limit:** 20/hour/IP.
- **Idempotency:** N/A — a `code` is single-use by OAuth2 protocol design; a retried callback with the same code fails at the IdP's own exchange step, not this document's concern beyond passing that failure through as `401`.
- **Latency:** Standard tier — dominated by the IdP round trip, not by this platform's own DB/CPU cost.
- **Database:** `identity.oauth_identities` (upsert), `identity.users` (read/create), `organization.memberships` (read), `identity.sessions` (insert, on direct-success shape).
- **Cache:** None.
- **Audit:** `USER_LOGIN` (5J) on completion, mirroring password login.
- **Security:** No raw OAuth token ever persisted (`credential_ref` only, §6).
- **Observability:** `auth_oauth_callback_total{provider,result}`.
- **Side Effects:** Same as password login's completion path.
- **Concurrency/Consistency:** N/A beyond the IdP's own code single-use guarantee.

### 21.16 `DELETE /api/v1/auth/oauth/{provider}`

- **Purpose:** Unlink an OAuth identity.
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A (user-global).
- **Path Params:** `provider`.
- **Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** Must not be the user's only auth method (blocked with `409 STATE_CONFLICT` if `password_hash IS NULL` and this is the last linked identity, §15.2).
- **Response `204`:** No content.
- **Errors:** `404 RESOURCE_NOT_FOUND` (no such linked identity); `409 STATE_CONFLICT` (would leave the user with no auth method).
- **Rate Limit:** 10/hour/user.
- **Idempotency:** Naturally idempotent (unlinking an already-unlinked provider is `404`, treated as the safe/expected outcome of a retry).
- **Latency:** Standard tier.
- **Database:** `identity.oauth_identities` (update `status=UNLINKED`).
- **Cache:** None.
- **Audit:** `OAUTH_UNLINKED` (5J).
- **Security:** The "last auth method" guard prevents account lockout.
- **Observability:** `auth_oauth_unlink_total{provider,result}`.
- **Side Effects:** Identity unlinked.
- **Concurrency/Consistency:** N/A.

---

### 21.17 `POST /api/v1/auth/mfa/enroll`

- **Purpose:** Generate a TOTP secret and return a one-time provisioning URI/QR payload.
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A (user-global — MFA is per-user, not per-membership, §9.3).
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** `mfa_enabled` must currently be `false` (re-enrolling while already enabled is `409 STATE_CONFLICT` — disable first, §21.19).
- **Response `200`:** `{ "data": { "provisioning_uri": "otpauth://totp/...", "secret": "BASE32SECRET..." } }` — **the raw secret is returned exactly once**, mirroring the API-key one-time-reveal pattern (§16.6); never retrievable again.
- **Errors:** `409 STATE_CONFLICT` (already enabled).
- **Rate Limit:** 5/hour/user.
- **Idempotency:** Not `Idempotency-Key`-bearing; each call generates a fresh secret (invalidating any prior unconfirmed enrollment) — repeated calls before confirmation are safe, just wasteful.
- **Latency:** Standard tier.
- **Database:** `identity.users` (write `mfa_secret_ref`, `mfa_enabled` still `false` until confirmed via §21.18).
- **Cache:** None.
- **Audit:** Not separately audited at the enroll step (only the confirming verify, §21.18, flips `mfa_enabled` and is audited then).
- **Security:** Raw secret never logged, never persisted in Postgres — only `mfa_secret_ref` (`secret_manager://...`, §6) is stored; the raw value exists only in this single response body.
- **Observability:** `auth_mfa_enroll_total`.
- **Side Effects:** `mfa_secret_ref` set (pending confirmation).
- **Concurrency/Consistency:** N/A.

### 21.18 `POST /api/v1/auth/mfa/verify`

- **Purpose:** Two distinct calling contexts (§15.3): (a) confirm TOTP enrollment (sets `mfa_enabled=true`); (b) login step-up, consuming an `mfa_challenge_token` (§11.4).
- **Authentication:** Access token (context (a)) **or** `mfa_challenge_token` (context (b)) — mutually exclusive per call, disambiguated by which credential type is presented, never by a client-supplied flag.
- **Authorization:** Self-scoped in both contexts.
- **Actor:** `USER`.
- **Tenant Context:** N/A for (a); resolved from the challenge token's `organization_id` claim for (b) (§9.3, §11.4).
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth (either credential type).
- **Request Schema:** `{ "code": "123456" }`.
- **Validation:** `code` is a 6-digit TOTP value, verified against the user's `mfa_secret_ref` within the standard TOTP time-step window.
- **Response `200` — context (a):** `{ "data": { "mfa_enabled": true } }`. **Response `200` — context (b):** same access/refresh-token shape as §21.1(a)/§21.6 (session now created).
- **Errors:** `401 MFA_INVALID_CODE` (wrong code); `401 MFA_CHALLENGE_EXPIRED` (challenge token past `exp`, context (b) only); `401 MFA_CHALLENGE_CONSUMED` (challenge already claimed — by this request losing the atomic `SET NX` race, or by prior replay, context (b) only, §11.4, §15.3); `429 RATE_LIMIT_EXCEEDED` (lockout-style); `503 DEPENDENCY_UNAVAILABLE` (Redis unavailable at the atomic-claim step, context (b) only — MFA login completion fails closed, §15.3).
- **Rate Limit:** 5/15min/user — locks the verification step, not the account (§23).
- **Idempotency:** Context (a) is naturally idempotent on repeated correct codes within the TOTP window (each just re-confirms); context (b) is explicitly **not** replayable after success — the challenge is atomically claimed (§11.4, §15.3) and a second presentation of the same challenge (concurrent or later) fails `401 MFA_CHALLENGE_CONSUMED` regardless of code correctness.
- **Latency:** Fast tier — TOTP verification is cheap CPU, no Argon2id cost; context (b) additionally does one atomic Redis `SET NX` (the claim) and, only if the claim succeeds, one session insert.
- **Database:** `identity.users` (read `mfa_secret_ref`; write `mfa_enabled=true` on first confirmation, context (a)); `identity.sessions` (insert, context (b), only after the claim succeeds).
- **Cache:** `auth:consumed_mfa_challenge:{jti}` — **atomic `SET ... NX EX <remaining_ttl>` claim, context (b) only, evaluated strictly after TOTP validation and strictly before session creation (§11.4, §15.3, corrected this pass from a prior check-then-write shape)**.
- **Audit:** `USER_MFA_ENABLED` (context (a), first confirmation, 5J); `USER_LOGIN` (context (b), completion of login, 5J — written only after the claim succeeds and the session is actually created).
- **Security:** Rate-limited per user regardless of context; TOTP secret never logged; a consumed-challenge replay is rejected even though the JWT itself remains signature-valid until `exp` (§11.4); **the claim step is atomic, so no two concurrent requests can both pass TOTP validation and both proceed to session creation for the same challenge (§11.4, §15.3)**.
- **Observability:** `auth_mfa_verify_total{result,context}`.
- **Side Effects:** Context (a): `mfa_enabled` flips to `true`. Context (b): challenge atomically claimed (Redis `SET NX`), then — and only then — session created.
- **Concurrency/Consistency:** Context (b)'s consumption is a single atomic Redis `SET auth:consumed_mfa_challenge:{jti} 1 NX EX <ttl>` — this, not a separate check-then-write pair, is what prevents two concurrent presentations of the same successfully-verified challenge from both completing login: exactly one `SET NX` can succeed for a given `jti`, and only that one request proceeds to create a session and issue tokens; every other concurrent or subsequent request observes the key already present and is rejected `401 MFA_CHALLENGE_CONSUMED`, never a race in which two sessions are created for the same challenge.

### 21.19 `DELETE /api/v1/auth/mfa`

- **Purpose:** Disable MFA (requires password re-entry).
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A.
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** `{ "password": "••••••••" }`.
- **Validation:** Password must verify against stored hash.
- **Response `204`:** No content.
- **Errors:** `401 INVALID_CREDENTIALS` (wrong password); `409 STATE_CONFLICT` (already disabled).
- **Rate Limit:** 5/hour/user.
- **Idempotency:** Disabling an already-disabled MFA is `409 STATE_CONFLICT`, not a silent success — deliberate, so a client can distinguish "nothing to do" from "action taken."
- **Latency:** Standard tier — Argon2id verification cost.
- **Database:** `identity.users` (write `mfa_enabled=false`, clear `mfa_secret_ref`).
- **Cache:** None.
- **Audit:** `USER_MFA_DISABLED` (5J).
- **Security:** Password re-entry prevents a hijacked-but-still-logged-in session from silently disabling MFA without re-proving the password.
- **Observability:** `auth_mfa_disable_total{result}`.
- **Side Effects:** MFA disabled.
- **Concurrency/Consistency:** N/A.

---

### 21.20 `GET /api/v1/auth/me`

- **Purpose:** Return the current `AuthenticationContext` (§6.1).
- **Authentication:** Access token or API key.
- **Authorization:** Self-scoped (returns only the caller's own context).
- **Actor:** `USER` or `API_KEY`.
- **Tenant Context:** Caller's own resolved `organization_id`.
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** N/A.
- **Response `200`:** The `AuthenticationContext` shape from §6.1 (minus `token_id`, which is internal-only, never returned in an API response).
- **Errors:** `401` (invalid/expired/revoked credential, including the denylist check, §12.4).
- **Rate Limit:** 300/min/user.
- **Idempotency:** N/A (GET).
- **Latency:** Fast tier — cache-hit permission resolution.
- **Database:** DB fallback only on permission-cache miss.
- **Cache:** `rbac:permissions:{organization_id}:{user_id}`.
- **Audit:** Not audited (a read-only self-query).
- **Security:** Never returns another actor's context; never returns raw token material.
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

---

### 21.21 `GET /api/v1/sessions`

- **Purpose:** List the caller's own sessions, cursor-paginated (6A standard).
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A (sessions are not tenant-scoped, §14).
- **Path Params:** None. **Query Params:** `cursor`, `limit` (6A pagination standard).
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** `limit` bounded per 6A's pagination rules.
- **Response `200`:** `{ "data": [ {"id": "...", "device_label": "...", "ip_address": "...", "created_at": "...", "last_seen_at": "...", "expires_at": "...", "status": "ACTIVE"}, ... ], "meta": {"cursor": "...", "request_id": "..."} }` — never includes `refresh_token_hash`/`access_token_jti` (§14).
- **Errors:** `401`.
- **Rate Limit:** 60/hour.
- **Idempotency:** N/A (GET).
- **Latency:** Standard tier.
- **Database:** `identity.sessions` (read, `WHERE user_id = :id`, cursor-paginated).
- **Cache:** None.
- **Audit:** Not audited (read-only).
- **Security:** Owner-scoped query only — no path exists to list another user's sessions here (§14).
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.22 `GET /api/v1/sessions/me`

- **Purpose:** Get the session record behind the current access token.
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A.
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** N/A.
- **Response `200`:** Single session object, same shape as one row of §21.21.
- **Errors:** `401`.
- **Rate Limit:** 300/min.
- **Idempotency:** N/A (GET).
- **Latency:** Fast tier — PK lookup via `session_id` claim.
- **Database:** `identity.sessions` (read by PK).
- **Cache:** None.
- **Audit:** Not audited.
- **Security:** Same owner-scoping as §21.21.
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.23 `DELETE /api/v1/sessions/{session_id}`

- **Purpose:** Revoke one owned session.
- **Authentication:** Access token.
- **Authorization:** Owner-scoped — a user cannot revoke another user's session (§14).
- **Actor:** `USER`.
- **Tenant Context:** N/A.
- **Path Params:** `session_id`.
- **Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** `session_id` must belong to the caller's own `user_id` — otherwise `404 RESOURCE_NOT_FOUND` (never `403`, since a foreign session_id is indistinguishable from a nonexistent one to this caller, §14/§22 non-disclosure discipline extended here even though this isn't a tenant boundary, because the same "don't confirm existence of something you don't own" principle applies).
- **Response `204`:** No content.
- **Errors:** `404 RESOURCE_NOT_FOUND` (not found, or belongs to another user).
- **Rate Limit:** 60/hour.
- **Idempotency:** Naturally idempotent — revoking an already-`REVOKED` session is a no-op success.
- **Latency:** Fast tier.
- **Database:** `identity.sessions` (update, `WHERE id = :id AND user_id = :caller_id`).
- **Cache:** None.
- **Audit:** Not separately audited with its own `action_kind` (5J gap, §25 Tier 2, ADR-6B-06) — telemetry-only interim signal.
- **Security:** Does not denylist the access token for that session (routine revocation, §12.4).
- **Observability:** `auth_session_revocations_total{trigger="self"}`.
- **Side Effects:** Session marked `REVOKED`.
- **Concurrency/Consistency:** N/A.

### 21.24 `DELETE /api/v1/sessions`

- **Purpose:** Revoke all of the caller's own sessions except the current one ("log out other devices").
- **Authentication:** Access token.
- **Authorization:** Self-scoped.
- **Actor:** `USER`.
- **Tenant Context:** N/A.
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** N/A.
- **Response `200`:** `{ "data": { "revoked_count": 3 } }`.
- **Errors:** `401`.
- **Rate Limit:** 20/hour.
- **Idempotency:** Naturally idempotent (repeated calls just revoke zero additional sessions once none remain).
- **Latency:** Standard tier — bulk update, bounded by the user's own (small) session count.
- **Database:** `identity.sessions` (bulk update, `WHERE user_id = :caller_id AND id != :current_session_id AND status='ACTIVE'`).
- **Cache:** None.
- **Audit:** Not separately audited with its own `action_kind` (same Tier 2 gap as §21.23).
- **Security:** Does not denylist those sessions' access tokens (routine revocation, distinct from platform-admin forced revoke-all, §12.4, §21.36).
- **Observability:** `auth_session_revocations_total{trigger="self"}`.
- **Side Effects:** All other sessions marked `REVOKED`.
- **Concurrency/Consistency:** A plain bulk `UPDATE` — no row-lock coordination with concurrent refreshes is required here since routine self-revocation doesn't need the denylist-write guarantee that platform-admin revoke-all does (§12.4, §21.36); a session mid-refresh when this runs either completes its own already-in-flight rotation (harmless — it's still the same user revoking their own device) or is revoked, either outcome acceptable for this non-emergency action.

---

### 21.25 `POST /api/v1/organizations/{organization_id}/api-keys`

- **Purpose:** Create an API key (raw key returned once).
- **Authentication:** Access token.
- **Authorization:** `api_key:manage`.
- **Actor:** `USER`.
- **Tenant Context:** `organization_id` (path, server-verified against the caller's own membership, §9).
- **Path Params:** `organization_id`. **Query Params:** None.
- **Headers:** Standard bearer auth; optional `Idempotency-Key`.
- **Request Schema:** `{ "name": "CI integration key", "scopes": ["contact:read", "contact:write"], "expires_at": null }`.
- **Validation:** `scopes` must be a subset of the issuing user's own current permissions (§16.4, least-privilege) — a requested scope the issuer doesn't hold is `403 AUTHORIZATION_DENIED`, not silently dropped.
- **Response `201`:** `{ "data": { "id": "...", "key": "vxa_a1b2c3d4...<secret>", "key_prefix": "a1b2c3d4", "scopes": [...], "expires_at": null, "created_at": "..." } }` — `key` present only in this one response (§16.5).
- **Errors:** `403 AUTHORIZATION_DENIED` (missing `api_key:manage`, or requested scope exceeds issuer's own permissions); `400 VALIDATION_ERROR`.
- **Rate Limit:** 10/day/org.
- **Idempotency:** `Idempotency-Key` supported (6A standard) — a retried creation with the same key returns the original key's metadata, **not** the raw secret again (the raw secret is genuinely one-time, even across idempotent retries — the retry response omits `key` and instead signals "already created, raw value was only shown once").
- **Latency:** Standard tier.
- **Database:** `identity.api_keys` (insert).
- **Cache:** None.
- **Audit:** `API_KEY_CREATED` (5J).
- **Security:** Scopes are a ceiling at issuance time only (§16.4) — later permission changes to the issuing user do not retroactively narrow or widen an already-issued key's scopes (the key's own `scopes` array is what's evaluated going forward, not the issuer's current permissions).
- **Observability:** `auth_api_key_usage_total{organization_id}` (creation event).
- **Side Effects:** New `identity.api_keys` row.
- **Concurrency/Consistency:** N/A.

### 21.26 `GET /api/v1/organizations/{organization_id}/api-keys`

- **Purpose:** List API keys (metadata only).
- **Authentication:** Access token or API key.
- **Authorization:** `api_key:read`.
- **Actor:** `USER` or `API_KEY`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`. **Query Params:** `cursor`, `limit`.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** N/A.
- **Response `200`:** `{ "data": [ {"id": "...", "key_prefix": "...", "name": "...", "scopes": [...], "status": "ACTIVE", "expires_at": null, "last_used_at": "...", "created_at": "..."}, ... ] }` — raw key never included (§16.5).
- **Errors:** `403 AUTHORIZATION_DENIED`.
- **Rate Limit:** 60/hour.
- **Idempotency:** N/A (GET).
- **Latency:** Standard tier.
- **Database:** `identity.api_keys` (read, RLS-scoped).
- **Cache:** None.
- **Audit:** Not audited (read-only).
- **Security:** RLS-scoped to the caller's own `organization_id` — cross-tenant listing is architecturally impossible, not merely permission-checked.
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.27 `GET /api/v1/organizations/{organization_id}/api-keys/{api_key_id}`

- **Purpose:** Get one API key's metadata.
- **Authentication:** Access token or API key.
- **Authorization:** `api_key:read`.
- **Actor:** `USER` or `API_KEY`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`, `api_key_id`.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** `api_key_id` must belong to `organization_id` — cross-tenant reference is `404`, never `403` (§9.2).
- **Response `200`:** Single key metadata object, same shape as one row of §21.26.
- **Errors:** `403 AUTHORIZATION_DENIED` (missing `api_key:read`); `404 RESOURCE_NOT_FOUND` (wrong org, or doesn't exist — indistinguishable, §9.2).
- **Rate Limit:** 120/hour.
- **Idempotency:** N/A (GET).
- **Latency:** Fast tier — PK lookup.
- **Database:** `identity.api_keys` (read by PK, RLS-scoped).
- **Cache:** None.
- **Audit:** Not audited.
- **Security:** Same cross-tenant non-disclosure as every other resource read (§9.2).
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.28 `DELETE /api/v1/organizations/{organization_id}/api-keys/{api_key_id}`

- **Purpose:** Revoke an API key.
- **Authentication:** Access token.
- **Authorization:** `api_key:manage`.
- **Actor:** `USER`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`, `api_key_id`.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** `api_key_id` must belong to `organization_id` (§9.2, `404` otherwise).
- **Response `204`:** No content.
- **Errors:** `403 AUTHORIZATION_DENIED`; `404 RESOURCE_NOT_FOUND`.
- **Rate Limit:** 30/hour/org.
- **Idempotency:** Naturally idempotent — revoking an already-`REVOKED` key is a no-op success.
- **Latency:** Fast tier.
- **Database:** `identity.api_keys` (update `status=REVOKED`).
- **Cache:** None.
- **Audit:** `API_KEY_REVOKED` (5J).
- **Security:** No in-place rotation (§16.3) — this is the only mutation path, paired with a fresh `POST` to reissue.
- **Observability:** `auth_api_key_usage_total{organization_id}` (revocation event).
- **Side Effects:** Key immediately unusable for future requests (checked at `identity.validate_api_key()`, §16.4) — in-flight requests already past the auth-check boundary are not retroactively terminated (bounded by request duration, not a residual-validity window in the token sense, since API keys are DB-checked per request, not stateless).
- **Concurrency/Consistency:** N/A.

---

### 21.29 `GET /api/v1/permissions`

- **Purpose:** Return the platform-wide permission catalog.
- **Authentication:** Access token or API key.
- **Authorization:** None beyond authentication — read-only, no tenant scope, not sensitive (§16.2, the catalog is platform reference data).
- **Actor:** `USER` or `API_KEY`.
- **Tenant Context:** None.
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** N/A.
- **Response `200`:** `{ "data": [ {"key": "contact:read", "description": "..."}, ... ] }` — all 64 seeded permissions (§16.2).
- **Errors:** `401`.
- **Rate Limit:** 60/min.
- **Idempotency:** N/A (GET).
- **Latency:** Fast tier — small, effectively-static reference table, cacheable at the HTTP layer via standard caching headers (6A §10.3) if desired; no per-request Redis dependency introduced by this document beyond that.
- **Database:** `organization.permissions` (read).
- **Cache:** None Redis-side (small enough to not need it); HTTP-layer caching per 6A is an implementation option, not a requirement this document imposes.
- **Audit:** Not audited (read-only reference data).
- **Security:** No tenant-specific information ever included.
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.30 `GET /api/v1/organizations/{organization_id}/roles`

- **Purpose:** List roles (system + custom) visible to the org.
- **Authentication:** Access token or API key.
- **Authorization:** `role:read`.
- **Actor:** `USER` or `API_KEY`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`. **Query Params:** `cursor`, `limit`.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** N/A.
- **Response `200`:** `{ "data": [ {"id": "...", "name": "ADMIN", "is_system": true, "organization_id": null}, {"id": "...", "name": "Custom Support Role", "is_system": false, "organization_id": "..."}, ... ] }`.
- **Errors:** `403 AUTHORIZATION_DENIED`.
- **Rate Limit:** 60/min.
- **Idempotency:** N/A (GET).
- **Latency:** Fast tier.
- **Database:** `organization.roles` (read — system roles `organization_id IS NULL` plus this org's custom roles, §6).
- **Cache:** `rbac:role:{organization_id}:{role_id}` (per-role detail cache, not the list itself).
- **Audit:** Not audited.
- **Security:** System roles from every org are visible (they are platform-shared reference data, `organization_id IS NULL`, §6) — only custom roles are tenant-scoped and RLS-filtered.
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.31 `POST /api/v1/organizations/{organization_id}/roles`

- **Purpose:** Create a custom role.
- **Authentication:** Access token.
- **Authorization:** `role:manage`.
- **Actor:** `USER`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`.
- **Headers:** Standard bearer auth; optional `Idempotency-Key`.
- **Request Schema:** `{ "name": "Support Lead", "permissions": ["contact:read", "contact:write"] }`.
- **Validation:** `permissions` must all exist in the platform catalog (§16.2) — an unrecognized permission string is `400 VALIDATION_ERROR`; `name` unique within the org.
- **Response `201`:** `{ "data": { "id": "...", "name": "...", "is_system": false, "permissions": [...] } }`.
- **Errors:** `403 AUTHORIZATION_DENIED`; `400 VALIDATION_ERROR`; `409 STATE_CONFLICT` (duplicate name).
- **Rate Limit:** 20/hour/org.
- **Idempotency:** `Idempotency-Key` supported (6A standard).
- **Latency:** Standard tier.
- **Database:** `organization.roles` (insert), `organization.role_permissions` (insert).
- **Cache:** Invalidates `rbac:role:{organization_id}:*` for this org's list views (§24 — new role, no existing cache entry to invalidate for it specifically, but list-shaped caches if any would need refresh — this document specifies no list-level cache today, §24, so no invalidation gap exists).
- **Audit:** `ROLE_ASSIGNED` (closest existing 5J value, §25 — semantically adequate per the prior pass's decision, not a gap).
- **Security:** Cannot create a role with `is_system=true` (server-controlled field, not client-settable).
- **Observability:** Standard latency histogram.
- **Side Effects:** New role + permission-set rows.
- **Concurrency/Consistency:** Unique constraint on `(organization_id, name)` is the race-safety mechanism for two concurrent creates of the same name.

### 21.32 `GET /api/v1/organizations/{organization_id}/roles/{role_id}`

- **Purpose:** Get role detail (full permission set).
- **Authentication:** Access token or API key.
- **Authorization:** `role:read`.
- **Actor:** `USER` or `API_KEY`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`, `role_id`.
- **Headers:** Standard bearer auth.
- **Request Schema:** N/A (GET).
- **Validation:** `role_id` must be visible to `organization_id` (system role, or this org's own custom role) — otherwise `404` (§9.2).
- **Response `200`:** `{ "data": { "id": "...", "name": "...", "is_system": bool, "permissions": [...] } }`.
- **Errors:** `403 AUTHORIZATION_DENIED`; `404 RESOURCE_NOT_FOUND`.
- **Rate Limit:** 120/hour.
- **Idempotency:** N/A (GET).
- **Latency:** Fast tier — cache-hit path.
- **Database:** DB fallback only on cache miss.
- **Cache:** `rbac:role:{organization_id}:{role_id}`, 5-min TTL (§24).
- **Audit:** Not audited.
- **Security:** This is the one place the full role→permission matrix is exposed — permission-gated (`role:read`), never exposed via `authorize/check` (§21.3).
- **Observability:** Standard latency histogram.
- **Side Effects:** None.
- **Concurrency/Consistency:** N/A.

### 21.33 `PATCH /api/v1/organizations/{organization_id}/roles/{role_id}`

- **Purpose:** Update a custom role's permission set (blocked if `is_system`).
- **Authentication:** Access token.
- **Authorization:** `role:manage`.
- **Actor:** `USER`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`, `role_id`.
- **Headers:** Standard bearer auth; `If-Match` ETag optional (6A weak-ETag concurrency, ADR-6A-08).
- **Request Schema:** `{ "permissions": ["contact:read", "contact:write", "campaign:read"] }`.
- **Validation:** `is_system=true` roles reject any mutation (`409 STATE_CONFLICT`, `trg_protect_system_roles`, §31); `permissions` values must exist in the catalog.
- **Response `200`:** Updated role object, same shape as §21.32.
- **Errors:** `403 AUTHORIZATION_DENIED`; `404 RESOURCE_NOT_FOUND` (wrong org); `409 STATE_CONFLICT` (`is_system=true`); `412 PRECONDITION_FAILED` (`If-Match` mismatch, if supplied).
- **Rate Limit:** 30/hour/org.
- **Idempotency:** `PATCH` is naturally idempotent (same input → same result, 6A §7.3) — no separate `Idempotency-Key` needed.
- **Latency:** Standard tier.
- **Database:** `organization.role_permissions` (replace set), `organization.roles` (touch `updated_at`).
- **Cache:** `rbac:role:{organization_id}:{role_id}` invalidated; `rbac:permissions:{organization_id}:{user_id}` invalidated for **every** member holding this role (§8, §23, synchronous invalidation on `role.permissions_updated`).
- **Audit:** `PERMISSION_CHANGED` (5J).
- **Security:** System-role protection enforced at the DB trigger layer (`trg_protect_system_roles`) as well as the API layer — defense in depth (§30).
- **Observability:** Standard latency histogram.
- **Side Effects:** Every member holding this role gets a re-resolved permission set on their next request.
- **Concurrency/Consistency:** Weak-`updated_at`-ETag concurrency (ADR-6A-08) for two concurrent edits of the same role; the DB trigger guard is the authoritative system-role protection regardless of ETag use.

### 21.34 `DELETE /api/v1/organizations/{organization_id}/roles/{role_id}`

- **Purpose:** Delete a custom role (blocked if `is_system` or in use).
- **Authentication:** Access token.
- **Authorization:** `role:manage`.
- **Actor:** `USER`.
- **Tenant Context:** `organization_id` (path).
- **Path Params:** `organization_id`, `role_id`.
- **Headers:** Standard bearer auth.
- **Request Schema:** Empty body.
- **Validation:** `is_system=true` → `409 STATE_CONFLICT`; role currently assigned to any active Membership → `409 STATE_CONFLICT` (`current_state: "IN_USE"` detail).
- **Response `204`:** No content.
- **Errors:** `403 AUTHORIZATION_DENIED`; `404 RESOURCE_NOT_FOUND`; `409 STATE_CONFLICT`.
- **Rate Limit:** 20/hour/org.
- **Idempotency:** Naturally idempotent for the "already deleted" case (`404` on retry, treated as the expected outcome).
- **Latency:** Standard tier.
- **Database:** `organization.roles` (delete), guarded by the in-use check above.
- **Cache:** `rbac:role:{organization_id}:{role_id}` invalidated.
- **Audit:** `PERMISSION_CHANGED` (5J, closest existing value for a role-catalog mutation).
- **Security:** In-use guard prevents orphaning an active Membership's `role_id` FK.
- **Observability:** Standard latency histogram.
- **Side Effects:** Role removed from the catalog.
- **Concurrency/Consistency:** The in-use check and the delete should be evaluated inside one transaction (read-then-delete) to avoid a race where a Membership is assigned this role between the check and the delete — a straightforward `DELETE ... WHERE id = :role_id AND NOT EXISTS (SELECT 1 FROM organization.memberships WHERE role_id = :role_id)` pattern (or equivalent FK constraint violation caught and mapped to `409`) closes this without needing an explicit application-level lock.

---

### 21.35 `POST /api/v1/platform-admin/break-glass/{grant_id}/release`

- **Purpose:** Release a break-glass grant early (§18.3/§18.3a).
- **Authentication:** Access token, actor must be `PLATFORM_ADMIN`.
- **Authorization:** `PlatformAdminOnly`, **and** the releasing admin must be the grant's own `admin_user_id`/`session_id` (§18.3a) — an admin cannot release another admin's grant.
- **Actor:** `PLATFORM_ADMIN`.
- **Tenant Context:** The grant's own `organization_id` (informational — release itself is not a tenant-scoped data operation).
- **Path Params:** `grant_id`.
- **Headers:** Standard bearer auth. (No `X-Break-Glass-Grant` header needed here — `grant_id` is the path parameter itself; this endpoint is about the grant, not an action performed *under* it.)
- **Request Schema:** Empty body.
- **Validation:** Grant must exist, not already released, and be bound to the calling admin's `user_id`/`session_id` (§18.3a) — otherwise a single generic `403 BREAK_GLASS_GRANT_INVALID` (no detail on which check failed, same non-disclosure rule as §18.3a's runtime checks).
- **Response `200`:** `{ "data": { "grant_id": "...", "released_at": "..." } }`.
- **Errors:** `403 BREAK_GLASS_GRANT_INVALID` (not found / already released / wrong admin/session); `503 DEPENDENCY_UNAVAILABLE` (Redis unreachable — release itself fails closed too, rather than silently no-op'ing).
- **Rate Limit:** 20/day/admin.
- **Idempotency:** Naturally idempotent in intent, but explicitly **not** silently successful on a second release — releasing an already-released grant is `403 BREAK_GLASS_GRANT_INVALID` (consistent with the generic-failure non-disclosure rule, not specially carved out as a `200` no-op, since the grant no longer belongs to an "active" state this admin can act on).
- **Latency:** Fast tier.
- **Database:** None (Redis-only state, §18.3).
- **Cache:** Sets the released flag on `platform_admin:break_glass:{grant_id}` (§18.3a) — takes effect immediately for the very next request presenting that `grant_id` (§18.3a, no propagation delay).
- **Audit:** `BREAK_GLASS_RELEASED`, written **synchronously** (§18.3).
- **Security:** Immediate effect — no cached/stale "still active" window (§18.3a).
- **Observability:** Dedicated release counter (§26).
- **Side Effects:** Grant marked released; every subsequent request presenting this `grant_id` is denied (§18.3a).
- **Concurrency/Consistency:** A release racing an in-flight elevated request under the same grant does not retroactively invalidate a request whose validation (§18.3a step 5) already completed before the release write landed — this is the same bounded, request-scoped window every other credential check in this document already accepts (§12.2's denylist check has the identical shape: a check that already passed is not retroactively undone mid-request).

### 21.36 `POST /api/v1/platform-admin/users/{user_id}/sessions/revoke-all`

- **Purpose:** Force-logout a user — revoke every `ACTIVE` session and globally denylist every currently-known access-token `jti` for that user (§12.4).
- **Authentication:** Access token, actor must be `PLATFORM_ADMIN`.
- **Authorization:** `PlatformAdminOnly`. **Not** a break-glass action in the tenant-data-access sense (§18.3a) — this endpoint acts on a `User`, which is not itself tenant-scoped (§6) — so no `X-Break-Glass-Grant` header is required here, only the platform-admin actor-type check.
- **Actor:** `PLATFORM_ADMIN`.
- **Tenant Context:** N/A (`identity.users`/`identity.sessions` are not tenant-scoped, §14).
- **Path Params:** `user_id`.
- **Headers:** Standard bearer auth.
- **Request Schema:** `{ "reason": "Compromised-account report, ticket JIRA-2299" }` (justification field, mirroring break-glass's own justification requirement for an elevated, cross-user action).
- **Validation:** `reason` required, minimum length enforced.
- **Response `200`:** `{ "data": { "user_id": "...", "revoked_session_count": 3, "denylisted_jti_count": 3 } }`.
- **Errors:** `403 AUTHORIZATION_DENIED` (not a platform admin); `404 RESOURCE_NOT_FOUND` (no such user); `400 VALIDATION_ERROR` (missing reason); `503 DEPENDENCY_UNAVAILABLE` (Redis unreachable — see below).
- **Rate Limit:** 50/day/admin.
- **Idempotency:** Naturally idempotent — a repeated call against a user with no remaining `ACTIVE` sessions returns `revoked_session_count: 0` successfully, not an error.
- **Latency:** Standard tier (<50ms/<150ms target-equivalent to the break-glass grant tier, §27) — bounded by the number of `ACTIVE` sessions for one user, normally small (§12.6).
- **Database:** `identity.sessions` — for each `ACTIVE` session belonging to `user_id` (enumerated by an ordinary unlocked `SELECT id FROM identity.sessions WHERE user_id = :user_id AND status = 'ACTIVE'`), an atomic conditional `UPDATE identity.sessions SET status = 'REVOKED' WHERE id = :session_id AND status = 'ACTIVE' RETURNING access_token_jti` — **corrected this pass from a prior `SELECT ... FOR UPDATE` design; no API-layer lock, per frozen 6A §17.3, consistent with §13.2/§13.5's pattern.**
- **Cache:** Writes `auth:revoked_jti:{jti}` for every session whose conditional `UPDATE` actually affected a row, using the `access_token_jti` that same statement's `RETURNING` clause reported (i.e., whatever was current at the exact moment of revocation, not a value read earlier) — TTL = full 15-minute access-token maximum, since exact remaining lifetime per session isn't cheaply known without decoding (§12.4's safe-ceiling rule).
- **Audit:** A genuinely unmappable 5J `action_kind` gap (§25 Tier 2, ADR-6B-06) — "platform-admin forced logout of a specific user" has no matching value (using `USER_LOGOUT` would misrepresent who performed the action). Telemetry-only interim signal (§26) until the future Phase 5.x audit-vocabulary extension (DEP-6B-02, §36.3).
- **Security:** **This is the endpoint that actually closes this pass's forced-revocation blocker for the multi-session case** — every session's `access_token_jti`, captured atomically at the moment its own conditional `UPDATE` commits, is denylisted, and the denylist check now runs on every subsequent access-token validation everywhere (§12.4), not merely on future refresh attempts. Documented limitation: only the *current* `jti` per session is known/denylistable (§12.4) — an already-superseded prior token for that session was never separately tracked and is not independently re-denylisted (it is already unusable for refresh regardless).
- **Observability:** `auth_session_revocations_total{trigger="platform-admin"}`.
- **Side Effects:** Every `ACTIVE` session for the user marked `REVOKED`; every known current `access_token_jti` denylisted globally.
- **Concurrency/Consistency:** A refresh racing this operation for the same session cannot escape revocation — the same two-outcomes analysis as §13.5: whichever of the two atomic conditional `UPDATE`s (this endpoint's per-session revoke, or a racing refresh's rotation, §13.2) commits second either observes `status != 'ACTIVE'` and fails, or is the value the other side's `RETURNING` clause captures. No `SELECT ... FOR UPDATE` or other row lock is used.

---

## 22. Error Catalog

Uses 6A's frozen error envelope (§4, verbatim shape) exclusively — no second error format introduced.

**Correction this pass (§8 of the task, 6A-vs-6B status-code reconciliation):** the prior draft listed `IDEMPOTENCY_KEY_REUSE_MISMATCH` under HTTP `422`. **This was wrong** — 6A §7.4/§16 binds this exact code to `409 Conflict` ("Idempotency-Key payload mismatch"), not `422`. 6B does not get to silently redefine a 6A-standard status code; this is fixed below, and no other 6A status-code binding was found altered anywhere else in this document (§38.1's reconciliation pass, restated).

| HTTP | `code` | Used for | Never reveals |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | Malformed request body, inconsistent client-supplied `organization_id` | — |
| 401 | `AUTHENTICATION_REQUIRED` | No credential presented on a protected route | — |
| 401 | `INVALID_CREDENTIALS` | Login: wrong password or unknown email | Which of the two it was |
| 401 | `TOKEN_EXPIRED` | Access token past `exp` | — |
| 401 | `TOKEN_REVOKED` | Access token's `jti` found in the forced-revocation denylist (§12.4) — checked on **every** access-token validation path, not an admin-route-only code | Whether the revocation was self-triggered, admin-triggered, or break-glass-triggered — the caller only learns the token no longer works |
| 401 | `INVALID_REFRESH_TOKEN` | Refresh token not found / wrong status / expired | Whether the token ever existed |
| 401 | `REFRESH_TOKEN_REUSE_DETECTED` | Hash mismatch against a found active session, detected via the atomic conditional `UPDATE`'s zero-rows-affected result (§13.2–§13.3) — no API-layer lock involved | — |
| 401 | `INVALID_API_KEY` | API key hash not found / revoked / expired | — |
| 401 | `MFA_REQUIRED` | Login succeeded on password, MFA step pending | — |
| 401 | `MFA_INVALID_CODE` | Wrong TOTP code, presented against either an access token (enrollment confirm) or an `mfa_challenge_token` (login step-up) | — |
| 401 | `MFA_CHALLENGE_EXPIRED` | `mfa_challenge_token` presented past its own `exp` (§11.4) | — |
| 401 | `MFA_CHALLENGE_CONSUMED` | `mfa_challenge_token` already used successfully once — replay of a consumed challenge (§11.4) | — |
| 403 | `AUTHORIZATION_DENIED` | Authenticated, permission check failed (§8, §17); also the "ordinary platform-admin JWT alone, no break-glass grant, against tenant-scoped data" case (§18.3a, §31) | Internal permission-structure detail, other actors' roles |
| 403 | `ACCOUNT_SUSPENDED` | User/Membership/Organization not `ACTIVE` (post-credential-check only) | — |
| 403 | `ORGANIZATION_SELECTION_INVALID` | `organization_id` not in the login-continuation token's allowed set, or membership/organization no longer `ACTIVE` at selection time (§9.3, §21.6) | Which of "not a member," "org doesn't exist," or "suspended" it was |
| 403 | `BREAK_GLASS_GRANT_INVALID` | Any break-glass runtime-authorization failure: missing header, grant not found, expired, released, wrong org, wrong admin, wrong session (§18.3a) | Which of the six specific checks failed |
| 404 | `RESOURCE_NOT_FOUND` | Cross-tenant resource reference (§9.2) — deliberately used **instead of 403** for tenant-boundary cases | Cross-tenant existence |
| 409 | `STATE_CONFLICT` | e.g., accepting an already-accepted invitation, disabling MFA that's already disabled, deleting an in-use role | — |
| 409 | `IDEMPOTENCY_KEY_REUSE_MISMATCH` | An `Idempotency-Key`-bearing request retried with a materially different body (6A §7.4/§16 — corrected from the prior draft's erroneous `422`, this pass) | — |
| 429 | `RATE_LIMIT_EXCEEDED` | Any §21/§23 limit breached | — |
| 503 | `DEPENDENCY_UNAVAILABLE` | Redis/DB unavailable at a point this document requires fail-closed behavior (§28) — now including the forced-revocation denylist check on every access-token validation (§12.4) and the break-glass grant-validation Redis lookup (§18.3a) | Stack traces, internal service names, `credential_ref`/`signing_secret_ref` values, SQL text |
| 5xx | `INTERNAL_ERROR` | Unhandled failure (§28) | Same as above |

**Internal token issuer failures fail closed (§17.2):** a workload that cannot authenticate to the central internal token issuer, or whose issuer is unreachable, simply does not receive a new internal token — there is no user-facing HTTP status for this (it is not a public endpoint, §17.2, §20), and no fallback credential is substituted (§17.2).

Never returned as `200` on failure — every branch above returns its stated non-2xx status; there is no endpoint in this document that reports failure inside a `200` body.

---

## 23. Rate Limiting and Abuse Protection

All limits below are **configurable defaults**, not benchmarked production numbers, per this document's anti-fabrication rule (§2).

| Concern | Key | Default |
|---|---|---|
| Login | `email` (post-normalization) + `IP` composite, never IP-only | 5/15min per email, 20/15min per IP |
| Failed-login lockout | `identity.users.failed_login_count` | Soft lockout after 10 consecutive failures, auto-clears on next success or after 1 hour |
| Organization selection (§9.3, §21.6) | continuation-token subject | 10/15min |
| Registration | IP | 5/hour |
| Password reset request | email + IP | 3/hour per email, 10/hour per IP |
| Refresh | session | 30/hour |
| MFA verify (enrollment confirm **and** login-challenge step-up, §21.18) | user | 5/15min (lockout-style — 5 wrong codes locks the MFA step for 15 min, not the account) |
| API key creation | org | 10/day |
| Session list/revoke ops | user | 60/hour (list), 20/hour (revoke-all) |
| Role create/update/delete | org | 20–30/hour |
| Break-glass grant / release | admin | 20/day each (§21.4, §21.35) |
| Platform-admin forced session revoke-all | admin | 50/day (§21.36) |
| WS connection attempts | source | 20/min (attempt rate) on top of the existing 5-concurrent cap (6A §27) |

**§13's explicit answer to 6A's R-8 (auth-endpoint abuse step-up):** confirmed, via the dedicated research pass, that **no CAPTCHA, adaptive-MFA-challenge, or bot-detection mechanism is specified anywhere in Phase 1–5**. This document does not fabricate one. **Decision (ADR-6B-03):** the interim, fully-grounded control is the composite identity+IP rate limiting and soft-lockout counters above, which *are* directly supported by existing schema (`identity.users.failed_login_count`/`last_failed_login_at`) and `NFR-SEC-007`. A CAPTCHA/adaptive-step-up layer is recorded as an explicit open item (§36) for a future phase, not designed here — this closes R-8 with a documented decision rather than leaving it silently unaddressed.

---

## 24. Caching

| Cache key | Contents | TTL | Invalidated on |
|---|---|---|---|
| `rbac:permissions:{organization_id}:{user_id}` | Compiled permission set for the membership | 5 min | `role_changed`, `role.permissions_updated` (invalidates all members holding that role), `custom_permission_granted/revoked` (not applicable — no such mechanism exists, ADR-6B-05), `apikey.revoked`, membership status change |
| `rbac:role:{organization_id}:{role_id}` | Role's permission list (used to serve §20.6 role-detail reads) | 5 min | Role update/delete |
| JWKS (public verification keys) | User-facing keypair's public half, **plus** the central internal token issuer's public half (§17.2, ADR-6B-11) — two independent key sets, one JWKS-distribution mechanism | Long-lived, refreshed on rotation (90-day user-facing / 180-day internal-issuer, per 3F §7.2) | Key rotation event |
| `auth:revoked_jti:{jti}` | Forced-revocation denylist entries — written by admin-triggered forced-revocation actions **and** by password-reset-confirm's best-effort post-commit denylisting step (§13.5, §21.11), and **read on every access-token validation, on every route type** (§12.4, corrected in an earlier pass — no longer an admin-route-only check). **This specific key is security-critical runtime enforcement state, not merely a performance optimization** — see the corrected framing below this table. | = token's remaining lifetime, or the full 15-minute maximum where exact remaining lifetime isn't cheaply known (e.g. revoke-all, §12.4/§21.36; password-reset, §13.5) | Self-expiring |
| `auth:consumed_mfa_challenge:{jti}` | MFA challenge single-use/consumption tracking (§11.4, §15.3) — **claimed atomically via `SET ... NX EX <ttl>` (corrected this pass — not a separate check-then-write) as the gate before session creation** in `POST /api/v1/auth/mfa/verify`'s login-step-up context; every concurrent/subsequent presentation of the same `jti` observes the key already present | = challenge token's remaining lifetime at consumption time | Self-expiring |
| `platform_admin:break_glass:{grant_id}` | Interim, non-durable grant state, now storing the fields runtime authorization needs (§18.3a): `admin_user_id`, `session_id`, `organization_id`, `expires_at`, a released flag — Redis TTL only, not audit-grade persistence (§18.3, §18.3a, §21.4 — flagged as a future Phase 5.x dependency, §36.3 item 1) | = `duration_minutes` | Release (flag set) or TTL expiry |

**Never cached:** individual authorization *decisions* per specific request (only the underlying compiled permission set is cached, evaluated fresh against the requested permission every time); raw credentials in any form; refresh-token or API-key hashes are read from DB directly, never cached (their lookup is already `O(1)` and caching a security-sensitive credential-verification path adds risk disproportionate to the latency saved).

**Redis wording, corrected this pass — no longer a blanket "disposable performance cache" claim.** The prior framing ("Redis is process-state/performance cache, never the audit or system of record — every Redis-backed entry is disposable") is not accurate for every key in the table above, and this document does not restate it. The precise statement is:

- **Redis is never the durable business/audit system of record.** No Redis key above is, or substitutes for, a durable record that a login, role change, or break-glass grant *occurred* — that durable record is `audit.audit_events` (§25) where a matching `action_kind` exists, or is an explicitly flagged future dependency where it does not. This part of the prior statement remains true and unchanged.
- **However, `auth:revoked_jti:{jti}` (and, by the same reasoning, `auth:consumed_mfa_challenge:{jti}`) is security-critical *runtime enforcement* state, not merely a disposable performance optimization.** Whether a specific access token is currently rejected, or whether a specific MFA challenge has already been consumed, depends on this key existing at read time — losing it does not just "degrade performance," it can change a security-relevant authorization outcome (a should-be-revoked token silently passing, or a should-be-single-use challenge being usable twice). This is exactly why this document's own fail-closed rule already treats Redis unavailability at these two specific checks as `503 DEPENDENCY_UNAVAILABLE` rather than a silent pass-through (§12.2, §28) — that rule is unchanged by this correction; this correction only fixes the *prose that described why*, which previously undersold these two keys' importance.
- **`platform_admin:break_glass:{grant_id}` remains correctly described as an operational-convenience/interim mechanism** (§18.3, §18.3a) — losing it degrades the ability to locate/release an active grant and, per §18.3a's own fail-closed rule, denies further use of that grant rather than silently allowing it; it is not "merely disposable" either, though its blast radius (an already-scoped, time-boxed platform-admin action) differs from the two keys above.
- **What Redis unavailability does *not* change:** the platform continues to follow the fail-closed rules already defined for every request-time authentication/authorization check that depends on Redis (§28) — a Redis outage denies rather than silently permits. What Redis unavailability *can* affect, specifically for password-reset (§13.5), is whether a **previously-intended** denylist write for an *already-completed* durable revocation gets delivered at all — and that specific gap, not the request-time fail-closed behavior, is what DEP-6B-08 (§36.3) tracks. **Previously-undelivered denylist entries from a completed password reset cannot be reconstructed crash-safely without that future reconciliation mechanism** — this document does not claim otherwise, and does not fabricate one now.

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
| MFA verified (login step-up completion, §11.4, §21.18 context (b)) | `USER_LOGIN` (the completed login this step was gating — not a separate event; the MFA step itself is a credential-exchange detail, not a distinct audited action) | `USER` | Resolved org |
| Break-glass grant/release, **and every elevated action performed under an open grant** | `BREAK_GLASS_GRANTED` / `BREAK_GLASS_RELEASED` for the grant lifecycle itself; every other audited action performed while `TenantContext` is set under a grant carries `grant_id` in its own `resource`/correlation metadata (§18.3a step 8) so the elevated action is attributable to the specific grant, not merely to "some platform admin, some time" | `PLATFORM_ADMIN` | Target org (synchronous write for grant/release, §18.3) |
| Internal-service authenticated action | `actor_type='WORKER'`/`'SYSTEM'`/`'INTEGRATION'`/`'PLUGIN'` as appropriate | matches caller | Per `on_behalf_of_organization_id`, or `NULL` |

**Tier 2 — Required audit semantics with no matching 5J `action_kind` today → future Phase 5.x audit-vocabulary extension (ADR-6B-06, §36.3 item 2):**

| This document's action | Current 5J mapping | Status |
|---|---|---|
| Platform-admin forced logout of a specific user (§21.36) | Closest existing value is `USER_LOGOUT`, but actor/target semantics differ (admin acting on another user, not the user acting on themself) — using it would misrepresent who performed the action | **Genuinely unmappable — requires new `action_kind`** |
| Session revoked (self-service, e.g. "log out this device") | No matching `action_kind` exists | **Genuinely unmappable — requires new `action_kind`** |
| Refresh-token reuse detected (`TOKEN_REFRESH_REUSE_DETECTED`) | No matching `action_kind` exists | **Genuinely unmappable — requires new `action_kind`** |
| Access-token forced revocation (denylist write itself, distinct from the revoke-all/forced-logout action that triggers it) | No matching `action_kind` exists | **Genuinely unmappable — requires new `action_kind`** |
| Organization selected mid-login (§9.3, §21.6) | No matching `action_kind` exists (folded into the eventual `USER_LOGIN` event once the flow completes, §21.6) | Not independently gapped — covered by the completed login's Tier 1 event; called out here only for completeness, not counted as an additional Tier 2 item |
| Central internal token issuer issuance failure (workload-identity rejected, issuer unreachable, §17.2) | No matching `action_kind` exists, and minting an internal token is not itself one of 5J's audited action kinds even in the successful case | **Not a Tier 2 gap in the FR-AUTH-004 sense** — this was never a durably-audited event category in this document's design (internal-token issuance is an infrastructure/operational concern, not a user-facing security decision); observable via structured logs and a dedicated metric (§17.5, §26) as operational telemetry only |

Per this document's hard boundary, Phase 5 is **not** modified here to add these `action_kind` values, no migration is written, and this document does not pretend an existing value is an adequate substitute. Until the Phase 5.x extension lands, the genuinely-unmappable events above are observable only via structured application logs and Prometheus counters (§26) — **that telemetry is a supporting, best-effort signal, not a durable audit record**, and does not satisfy FR-AUTH-004 for these event kinds (§35). This is the one place in 6B's audit design that is API-design-complete (the requirement to audit these events is specified) but implementation-dependent on an upstream Phase 5.x change. **No new Phase 5 `action_kind` values are invented or assumed anywhere in this document** — the count of genuinely-unmappable Tier 2 items grew from 3 to 4 this pass (adding forced-revocation-denylist-write) strictly because this pass introduced the global forced-revocation check itself; it does not reflect a newly-discovered pre-existing gap.

Audit structure (5J, unchanged): `actor{type, ref, name}`, `action_kind`, `resource{type, id}`, `outcome ∈ {SUCCESS, FAILURE, PARTIAL}`, `ip_address`, `user_agent`, `session_id`, `request_id`, `correlation_id`, `occurred_at`. Write-once — no role, including platform admin, has `UPDATE`/`DELETE` on `audit.audit_events` (5J §26, confirmed).

---

## 26. Observability

**Structured logs, metrics, and traces below are supporting telemetry — operational visibility, debugging, and alerting signals. They are not a substitute for, or equivalent to, the durable audit record defined in §25.** A metric counter can tell an operator that refresh-reuse events are occurring; it cannot answer "did user X's session get revoked, by whom, when, attributably" the way a durable `audit.audit_events` row can. Where §25 flags an event as lacking a durable `action_kind` today, the telemetry below is the best-effort interim signal for that event — not a claim that the event is durably audited.

Metrics (Prometheus, `platform_`-prefixed convention per 6A §25, `auth_` sub-namespace here):

- `auth_login_attempts_total{result}`, `auth_login_failures_total{reason}`
- `auth_organization_select_total{result}` (§9.3, §21.6 — new this pass)
- `auth_token_refresh_total{result}`, `auth_token_refresh_failures_total{reason}`
- `auth_refresh_reuse_detected_total`
- `auth_authorization_denied_total{permission}`
- `auth_api_key_usage_total{organization_id}`
- `auth_session_revocations_total{trigger}` (self / password-reset / platform-admin / reuse-detected)
- `auth_token_revoked_checks_total{result}` (denylist check outcome on every access-token validation — new this pass, §12.4)
- `auth_websocket_auth_failures_total`
- `auth_mfa_verify_total{result,context}` (enrollment-confirm vs. login-step-up, §21.18)
- `auth_mfa_challenge_expired_total`, `auth_mfa_challenge_consumed_replay_total` (new this pass, §11.4)
- `auth_break_glass_grant_validation_total{result}` (per-request runtime authorization outcome — new this pass, §18.3a)
- `auth_internal_token_issuance_total{result}` (central issuer issuance outcome, operational telemetry only — new this pass, §17.2/§17.5)
- p50/p95/p99 latency histograms per endpoint (§27)

Correlation: every log line and metric label carries `request_id` (6A entry-middleware assigned), and where applicable `actor_id`/`organization_id`/`trace_id` (OpenTelemetry span per request, per 6A §25).

**Never logged, under any circumstance:** raw passwords, raw access/refresh tokens, raw API keys, raw TOTP secrets, JWT signing key material, `mfa_secret_ref`/`credential_ref` values (the reference itself is safe to log; the secret it points to is never fetched into a log line). Enforced by the same PII-redacting `structlog` processor 6A already mandates platform-wide (strips `phone_number|email|token|password|secret`) — this document adds no exception to that filter.

---

## 27. Performance and Latency

Per 6A's latency tiers (Fast / Standard / Async), reasoned per stage rather than benchmarked (no load-test data exists yet — marked TARGET, not MEASURED):

| Stage | Budget (p50 / p99, TARGET) | Dominant cost |
|---|---|---|
| Access-token verification, **corrected this pass** | <4ms / <15ms | RS256 signature check (no I/O) **+ one mandatory Redis GET for the forced-revocation denylist check** (§12.2, §12.4) — no longer zero-I/O; the added ~2–7ms reflects one Redis round trip, batched with the permission-cache lookup via pipeline/`MGET` where both are needed in the same request (§12.2) |
| Permission check, cache hit | <5ms / <20ms | Redis round-trip (may share a pipeline with the denylist check above, §12.2) |
| Permission check, cache miss | <25ms / <80ms | DB read (Membership⋈Role⋈Organization) |
| Login (Argon2id) | <150ms / <500ms | Deliberately expensive hashing — a floor, not a bug |
| Refresh (rotation, atomic conditional UPDATE) | <10ms / <40ms | Single atomic `UPDATE ... WHERE ... RETURNING` — no API-layer lock acquired; Postgres's own row-level MVCC serializes concurrent writers on the same row at negligible added cost, §13.2 |
| API-key validation | <15ms / <50ms | `validate_api_key()` SECURITY DEFINER call, pre-tenant-context |
| WS handshake auth | <20ms / <70ms | Same as access-token/API-key path (including the denylist check) plus connection setup |
| MFA challenge verify (login step-up) | <10ms / <35ms | TOTP check (CPU) + one Redis write (consume challenge `jti`) + session insert |
| Organization selection | <10ms / <35ms | Continuation-token verify + membership/organization live-status read |
| Break-glass grant | <50ms / <150ms | Includes synchronous audit write (§18.3) |
| Break-glass runtime authorization (per elevated request, §18.3a) | <5ms / <20ms | One Redis read of the grant record, same order of magnitude as the permission-cache lookup |

**Resilience of the authz path under dependency failure — corrected this pass (task-required explanation):** the prior draft claimed the hot path (access-token verification) has **zero** runtime dependency on Redis or DB. **That claim is no longer accurate** now that the forced-revocation denylist check runs on every access-token validation (§12.2, §12.4) — this document does not restate it. Redis is now a hard runtime dependency of **access-token authentication itself**, not only of the permission-check path: a Redis outage means every `/api/v1/*` request and every WebSocket handshake fails `503 DEPENDENCY_UNAVAILABLE` (§12.2, §28), not merely a degraded-to-DB-fallback permission check. This is a genuine, disclosed availability trade-off of closing the global forced-revocation gap with no new Phase 5 table available to back it with a DB-level fallback — mitigated by Redis HA/replication (already assumed for the permission cache), not by weakening the check. Signing-key-service (and, per ADR-6B-11, the central internal token issuer) unavailability still affects only key **rotation**/new-token **issuance**, not verification of already-cached public keys (§17.2, §24), so a transient outage there does not stop request authentication the way a Redis outage now does.

---

## 28. Failure and Resilience

Fail-closed wherever security requires it (§5.3):

| Dependency down | Behavior |
|---|---|
| Redis — **forced-revocation denylist check (§12.4), now on every access-token validation** | **Corrected this pass:** `503 DEPENDENCY_UNAVAILABLE`, `retryable: true` — fails closed for **every** `/api/v1/*` request and every WebSocket handshake, not only permission-dependent ones. There is no DB fallback for this specific check (no Phase 5 table exists to fall back to, Hard Stop) — the prior draft's implicit assumption that Redis-down only ever degraded the permission-check path no longer holds once forced revocation is a global, every-request check. Never "assume not revoked." |
| Redis (permission cache, distinct from the row above) | DB fallback (§27); if DB also unavailable, see below — never "assume allowed" |
| Redis — break-glass grant validation (§18.3a) | `503 DEPENDENCY_UNAVAILABLE` — break-glass access is **denied**, never allowed, when the grant store cannot be consulted (§18.3a) |
| Redis — MFA-challenge atomic consumption claim (`SET NX`, §11.4, §15.3, §21.18) | `503 DEPENDENCY_UNAVAILABLE` — MFA login completion fails closed; no session is created and no tokens are issued, since the atomic claim (not a separate check) is the only mechanism preventing two concurrent verifications of the same challenge from both succeeding |
| Redis — password-reset best-effort access-token denylisting, attempted *after* the durable DB transaction has already committed (§13.5, §21.11 — corrected this pass, no cross-system atomicity claimed) | The already-committed password change and session revocation are **not** rolled back or hidden. The endpoint returns `503 DEPENDENCY_UNAVAILABLE` with `error.details` accurately reporting `password_reset_completed: true`, `session_revocation_completed: true`, `access_token_revocation_completed: false` — it does not claim immediate global access-token revocation succeeded when it did not, and it does not promise that a retry of the (now-consumed) reset token will resume the unfinished Redis work (§13.5, DEP-6B-08). |
| DB | `503 DEPENDENCY_UNAVAILABLE`, `retryable: true` — no request reaches authorization evaluation without the ability to resolve current Membership/Role/Organization state |
| Signing-key service / JWKS unavailable (user-facing keypair) | New token *issuance* fails (`503`); *verification* of already-cached public keys continues to work until cache staleness exceeds the rotation window (§24) |
| Central internal token issuer unavailable (§17.2) | New internal token *issuance* fails closed — the calling service simply cannot obtain a fresh internal token, and does **not** fall back to a user token or API key; *verification* of already-issued, still-valid internal tokens continues to work via the cached public JWKS, unaffected by the issuer's own availability |
| Permission cache down (Redis) | See row 2 |
| Audit pipeline down (async) | Request still completes (audit is fire-and-forget except break-glass, §18.3) — but this is a monitored condition (`audit pipeline lag` alert), not silently ignored; break-glass, being synchronous, instead **fails the grant request** if the DB write itself fails, since that action's audit-or-it-didn't-happen guarantee is stronger by design |
| Clock skew | `nbf`/`exp` validation allows a small, explicit leeway window (30s) consistent with standard JWT practice; beyond that, tokens are rejected rather than accepted with unbounded skew tolerance |
| Token verification failure (malformed, wrong key, wrong `token_use`, revoked) | `401`, generic `code`, no detail on *why* verification failed beyond the `code` itself |
| Internal token expiry mid-call | `401 AUTHENTICATION_REQUIRED` on the internal route — calling service's SDK is responsible for requesting a fresh token from the central issuer before the 5-minute TTL lapses (§17.2), not this document's concern beyond specifying the TTL |
| Org suspended mid-session | Access token remains signature-valid but every authorization check now denies at `PermissionEvaluationService` step 2 (§8) — effectively read/write-locked out without needing token-level revocation |
| Break-glass grant expired/released mid-use | Enforced live on every subsequent request under that `grant_id` (§18.3a) — no propagation delay, no reliance on a background sweep for correctness |

---

## 29. Threat Model

| Threat | Attack surface | Mitigation | Detection | Residual risk |
|---|---|---|---|---|
| Credential stuffing | `/auth/login` | Composite email+IP rate limit, Argon2id cost, soft lockout | `auth_login_failures_total` spike alerting | Distributed low-and-slow attempts under per-IP threshold (CAPTCHA/step-up not implemented — ADR-6B-03) |
| Brute force (password) | `/auth/login` | Same as above | Same | Same |
| Phishing | Outside API surface | N/A (client/UX concern) | — | Not mitigated by this document |
| Access-token theft (XSS) | Client storage | Documented recommendation: never `localStorage`; short (15-min) TTL bounds exposure | — | Client-implementation-dependent, outside API control |
| Refresh-token theft | Client storage / transport | `httpOnly` cookie recommendation, rotation via atomic conditional UPDATE (no API-layer lock), reuse detection (§13) | `auth_refresh_reuse_detected_total` | Theft before first use of a rotated-out token is undetectable by design (the schema constraint, ADR-6B-01); a lost-response retry by the legitimate client is indistinguishable from theft and is force-logged-out (§13.6, accepted trade-off) |
| **Concurrent refresh race (corrected this pass)** | Two simultaneous requests presenting the same refresh token | Atomic, conditional `UPDATE ... WHERE refresh_token_hash = :presented_hash ... RETURNING` — no API-layer lock; Postgres's own row-level MVCC guarantees at most one of the two concurrent statements matches and writes — exactly one rotates, the other is treated as reuse (§13.2) | Same reuse-detection telemetry as the row above | None identified — this was the actual blocker this pass closed; no residual race remains, and no `SELECT ... FOR UPDATE`/API-layer lock is used, per frozen 6A §17.3 |
| Token replay | Network capture | TLS mandatory (`NFR-SEC-001`), short access-token TTL, `jti` denylist **checked on every access-token validation path, not only admin-triggered routes (corrected this pass, §12.4)** | `auth_token_revoked_checks_total` | Replay within the 15-min TTL window on a captured, unrevoked token — but a *force-revoked* token no longer has any surviving acceptance path, closing the prior draft's gap where only admin-reachable routes checked the denylist |
| Refresh reuse | Stolen rotated-out token | §13.3 — session hard-revoked on detection via an ordinary atomic `UPDATE`, no API-layer lock | Metric + structured log (audit gap, ADR-6B-06) | Legitimate user also logged out (accepted trade-off) |
| JWT forgery | Signature attack | RS256 asymmetric signing, private key never leaves signing service (user-facing) or the central internal token issuer (internal, §17.2, ADR-6B-11) | — | Signing-key compromise (mitigated by 180-day rotation, 3F §7.2) |
| Signing-key compromise (user-facing keypair) | Secret store breach | Rotation policy (90 days), separate key from the internal-issuer keypair limits blast radius | — | Window between compromise and rotation/detection |
| **Central internal token issuer compromise (new this pass, ADR-6B-11)** | Issuer's private-key store breach | Rotation policy (180 days, faster on detected compromise), short (5-min) token TTL bounds blast radius, issuer is a narrowly-scoped internal capability (not internet-reachable, not tenant-facing) | — | Concentrated risk vs. the retired per-deployable-signing-key model: compromise of the single issuer key can forge tokens for any `service_id`, whereas a compromised individual deployable's key (prior model) could only forge for that one service — but the retired model also meant N independent keys, each an equally-catastrophic single point of failure for its own `service_id`, with no caller-identity binding at all. This pass's trade-off (fewer, better-protected keys; smaller overall key-sprawl attack surface) is the explicit reason ADR-6B-11 was adopted. |
| **Compromised individual internal service workload (Worker/Voice Gateway)** | Workload identity credential theft | Central issuer maps workload identity → `service_id`; a compromised workload's own identity can, at most, obtain more tokens *for itself* — it has no signing capability and cannot request a different `service_id` (§17.2) | Issuer-side workload-authentication logs | Narrower than the retired per-deployable-key model, where a stolen signing key could forge tokens for *any* `service_id` |
| API-key leakage/replay | Client-side storage, logs, git commits | One-time reveal, prefix-only display thereafter, SHA-256 hash at rest, `last_used_at`/`last_used_ip` for anomaly review | Manual/analytics review of `last_used_ip` drift (no automated anomaly detection built) | No automated leaked-key detection (e.g., no GitHub secret-scanning integration specified) |
| Session hijacking | Stolen access token | Same as token theft above | — | Same |
| CSRF | N/A for Bearer-token `/api/v1` (6A §22, reaffirmed) | No ambient-cookie auth for the primary API surface | — | If a browser refresh-token cookie is introduced, `SameSite=Strict`+`httpOnly` is mandatory (6A carries this requirement forward) |
| XSS token theft | Client-side | See access-token-theft row | — | Same |
| WS hijacking | Connection takeover | Same credential/tenant binding as REST; heartbeat-based revocation check (§19.3) | — | Bounded by heartbeat interval |
| Tenant escape | Cross-org access attempt | Server-derived `organization_id` only (§9), RLS as independent second layer, `404` not `403` on cross-tenant refs | `auth_authorization_denied_total` | None identified beyond RLS/API-layer defense-in-depth already covering this |
| Privilege escalation | Role/permission manipulation | `role_permissions` RLS policy `FOR ALL USING(is_system=FALSE)` blocks modifying system-role permissions; `role:manage` gated | — | None beyond standard RBAC-bypass-via-bug class, mitigated by tests (§32) |
| Confused deputy | Internal token, MFA challenge token, or login-continuation token accepted on the wrong route | Strict `token_use`/audience separation, no fallback validator, for **all six** credential types this document now defines (§7, §17.3) | Internal-auth-failure logs distinct from public-auth-failure logs | None identified |
| Service-token abuse | Compromised internal signing key — **see the two dedicated rows above (central-issuer compromise, compromised individual workload) for the corrected, more precise breakdown this pass introduced** | Short TTL (5 min) bounds blast radius; central-issuer-owned rotation policy (§17.2) | — | See the two rows above |
| Org-ID tampering | Client-supplied `organization_id` in body/query | Never trusted for authz — cross-checked only, `400` on mismatch (§9.2) | — | None identified |
| **Arbitrary organization injection at login (closed this pass, §9.3)** | `POST /api/v1/auth/organization/select` | Continuation token's embedded allowed-membership set (server-computed at login) + live re-validation at redemption (§9.3, §11.5) | `auth_organization_select_total{result}` | None identified — the naive "let the client just POST an org_id" design this section exists to forbid was never implemented |
| **MFA challenge token misuse (closed this pass, §11.4)** | `mfa_challenge_token` presented at a normal resource route, replayed after consumption, or brute-forced | Restricted `aud`/`token_use`, **atomic `SET NX` single-use claim (corrected this pass — closes a concurrent-verify race a prior check-then-write shape left open, §11.4/§15.3)**, 5/15min rate limit on verification attempts (§11.4, §23) | `auth_mfa_verify_total`, `auth_mfa_challenge_consumed_replay_total` | Brute-forcing the 6-digit TOTP code within the lockout window before it triggers — bounded by the existing rate limit, same residual class as any TOTP implementation |
| **Concurrent MFA verification race (corrected this pass, §11.4, §15.3, §21.18)** | Two requests presenting the same challenge and the same (TOTP-window-valid) correct code, near-simultaneously | Atomic Redis `SET auth:consumed_mfa_challenge:{jti} 1 NX EX <ttl>` — only the request whose `SET NX` succeeds proceeds to session creation; the other observes the key already present | `auth_mfa_verify_total{result="consumed"}` | None identified — Redis's own `SET NX` atomicity guarantees exactly one winner; a Redis outage at this step fails the login closed (`503`), never silently races open |
| **Password-reset residual-access-token window (mitigated, not eliminated — corrected this pass, §13.5, §21.11)** | Attacker holds a still-valid access token at the moment the legitimate user resets a compromised password | Every currently-known `access_token_jti` across all of the user's active sessions is durably captured in the same database transaction that revokes sessions and changes the password, then a best-effort attempt globally denylists each one in Redis immediately afterward (checked on every access-token validation, §12.4) — refresh capability is unconditionally gone the instant the transaction commits, regardless of the Redis outcome | `auth_session_revocations_total{trigger="password-reset"}`, `auth_password_reset_confirm_total{result="partial_revocation"}` | **Two distinct residual risks, not one:** (1) the same frozen-schema limitation as revoke-all (§12.4, §13.5) — only the *currently-known* `jti` per session can be denylisted; an already-superseded prior token was never separately tracked (already unusable for refresh regardless); (2) **new, honestly disclosed this pass:** if the Redis denylist write fails or is only partially completed after the database transaction already committed (Case C, §13.5), an already-issued access token can remain usable for up to its own natural ≤15-minute expiry — this is not "closed," it is bounded and disclosed, and is explicitly tracked as DEP-6B-08 (§36.3) pending a future crash-safe reconciliation mechanism |
| **Break-glass grant misuse (closed this pass, §18.3a)** | Stolen/replayed platform-admin credential attempting to reuse a grant, or an admin attempting cross-org/cross-admin/cross-session grant use | Six-check runtime validation (grant exists/unexpired/unreleased/admin-bound/session-bound/org-bound), fail-closed on Redis unavailability, generic error with no distinguishing detail (§18.3a) | `auth_break_glass_grant_validation_total{result}`, `grant_id`-correlated audit entries for every elevated action (§18.3a step 8, §25) | A stolen admin access token used **within the same session** while a grant is open could still use that grant — this is not a new gap introduced by this design, it is the same "stolen valid credential" risk every session-bound credential in this document already carries (§29's access-token-theft row), not something break-glass-specific hardening can additionally close without also solving general session-theft |
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
15. **(New this pass.)** A force-revoked access token is rejected on **every** access-token validation path — every `/api/v1/*` route, every WebSocket handshake, and any other public access-token validation path — not merely on routes specifically reachable from an admin-revocation trigger (§12.2, §12.4).
16. **(Revised this pass.)** Refresh-token rotation guarantees exactly one successful rotation per presented, still-current refresh token; concurrent presentation of the same token can never yield two valid successor token pairs — enforced by an atomic, conditional `UPDATE ... RETURNING` (CAS), **with no API-layer lock of any kind** (§13.2).
17. **(New this pass.)** No access or refresh token, and no `identity.sessions` row, is ever created for an MFA-enabled user before MFA verification succeeds — the MFA challenge token itself carries no session-granting power (§9.3, §11.4).
18. **(New this pass.)** No client-supplied `organization_id` is ever accepted as authoritative during login/organization-selection — only organizations within the caller's own server-computed, continuation-token-embedded allowed set, re-validated live at redemption, can be selected (§9.3, §11.5).
19. **(New this pass.)** An ordinary platform-admin JWT, by itself, is never sufficient to access tenant-scoped data — a valid, live-validated `X-Break-Glass-Grant` bound to the same admin, the same session, and the requested organization is required for every such access, and Redis unavailability at that check denies access rather than allowing it (§18.3a).
20. **(New this pass.)** No internal service can mint a token asserting a `service_id` other than its own authenticated workload identity, and no internal service ever holds the private key capable of minting an internal token for any `service_id` — only the central internal token issuer does (§17.2, ADR-6B-11).
21. **(New this pass.)** The API layer never takes its own application-level lock (`SELECT ... FOR UPDATE`, `LOCK TABLE`, advisory lock, or equivalent) to coordinate concurrent access to `identity.sessions` — every such coordination (refresh rotation, password-reset global revocation, platform-admin revoke-all) is achieved exclusively through atomic, conditional `UPDATE ... WHERE <current-state predicate> ... RETURNING` statements, consistent with frozen 6A §17.3 (§13.2, §13.5, §21.36).
22. **(New this pass.)** An MFA challenge can be consumed by at most one request, ever — enforced by a single atomic Redis `SET ... NX` claim evaluated strictly after TOTP validation and strictly before session creation, not by a separate check-then-write pair (§11.4, §15.3).
23. **(Revised this pass — removes a false cross-system-atomicity claim.)** A successful password reset **durably and unconditionally** revokes every active session and ends refresh capability in the same database transaction as the password change; it additionally makes a **best-effort** attempt, immediately after that transaction commits, to globally denylist every currently-known access-token `jti` for that user. The endpoint never reports `access_token_revocation_completed: true` unless that denylisting step actually succeeded, and never implies that PostgreSQL and Redis committed as one atomic unit or that a retry of an already-consumed reset token can resume unfinished denylisting work (§13.5, §21.11, DEP-6B-08).

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
| `PLATFORM_ADMIN` | `GET /organizations/{any}/roles` (ordinary tenant-scoped **read**, no `X-Break-Glass-Grant` presented) | `PlatformAdminOnly` alone is not enough | `403 AUTHORIZATION_DENIED` — this row restates the row above for a read, not only a write, closing any ambiguity about whether the ordinary-JWT-insufficiency rule applies only to mutations (§18.3a) |
| `PLATFORM_ADMIN` with a **valid** `X-Break-Glass-Grant` for Org A | `GET /organizations/{A}/roles` | Six-check grant validation passes (§18.3a) | `200` — this is break-glass working as designed, not a bypass |
| `PLATFORM_ADMIN` with a grant for Org A | `GET /organizations/{B}/roles` (wrong org) | Grant/org mismatch (§18.3a check f) | `403 BREAK_GLASS_GRANT_INVALID` |
| `PLATFORM_ADMIN` B, presenting Admin A's `grant_id` | Any tenant-scoped route under that grant | Grant/admin mismatch (§18.3a check d) | `403 BREAK_GLASS_GRANT_INVALID` |
| `PLATFORM_ADMIN` A, different session than the one that opened the grant | Any tenant-scoped route under that grant | Grant/session mismatch (§18.3a check e) | `403 BREAK_GLASS_GRANT_INVALID` |
| `PLATFORM_ADMIN` with an expired or released grant | Any tenant-scoped route under that grant | Expiry/release check (§18.3a checks b/c) | `403 BREAK_GLASS_GRANT_INVALID` |
| MFA challenge token (§11.4) | Any `/api/v1/*` route other than `POST /auth/mfa/verify` | Wrong `aud`/`token_use` | `401` — rejected exactly as any other wrong-type credential (§7) |
| Login-continuation token (§11.5) | Any `/api/v1/*` route other than `POST /auth/organization/select` | Wrong `aud`/`token_use` | `401` |
| `USER` | `POST /auth/organization/select` with an `organization_id` outside the continuation token's allowed set | Server-side allowed-set check (§9.3) | `403 ORGANIZATION_SELECTION_INVALID` |
| Force-revoked access token (any actor type it was issued to) | Any `/api/v1/*` route, or any WebSocket handshake | Denylist check (§12.2, §12.4) | `401 TOKEN_REVOKED` — globally, not only on admin-triggered routes (this pass's corrected guarantee) |

---

## 32. Test Strategy

- **Unit:** `PermissionEvaluationService` (§8) — all four branches; refresh-token hash-match/mismatch/not-found branching (§13.1); TOTP verification.
- **Integration:** full login→refresh→logout lifecycle against a real (test) DB; RLS-scoped queries under `SET LOCAL app.tenant_id`.
- **Contract:** every endpoint in §20/§21 against its fully-expanded contract (status codes, envelope shape, error `code` values, request/response schema) — **every one of the 36 endpoints' request/response validates against its intended OpenAPI schema**, not only the previously-detailed subset.
- **Security / authz-matrix:** every row of §31, executed as an automated table-driven suite.
- **Tenant-isolation:** User A (org 1) cannot access org 2's roles/api-keys/sessions — asserts `404`, not `403`, and asserts the response body contains no signal distinguishing "doesn't exist" from "exists in another tenant."
- **Rate-limit:** login/refresh/reset endpoints hit their configured ceiling and return `429`, not silently degrade or 500.
- **Token-lifecycle:** access token accepted until `exp`, rejected after; refresh token rejected once its session is `REVOKED`.
- **Replay:** a captured, valid, unexpired access token replayed after **routine** logout is still accepted (§12.4's documented, bounded trade-off) — asserted as *expected* behavior for that specific case, not a bug — with a companion test proving the **forced**-revocation denylist path rejects the same token on **any** route once denylisted (below), not only via `PlatformAdminOnly` revoke-all's own trigger route.
- **WebSocket-auth:** connection with expired token rejected at handshake; connection whose session is revoked mid-stream is closed within one heartbeat interval (§19.3); connection with a force-revoked `jti` is rejected at handshake and, if already open, closed within one heartbeat interval (new this pass, §19.3).
- **API-key:** revoked key rejected; expired key rejected; key with narrower `scopes` than the requested permission rejected (§16.4).
- **Failure-injection:** Redis unavailable at the **permission-cache** path → DB-fallback exercised and asserted correct; Redis unavailable at the **forced-revocation denylist**, **MFA-challenge-consumption**, or **break-glass-grant-validation** path → `503`, asserted as denied, never a silent allow (new this pass — these three did not previously have their own fail-closed test); DB unavailable → `503`, never a silent allow.
- **Performance:** p50/p95/p99 assertions against §27's TARGET budgets under a defined load profile (to be executed once implementation exists — this document specifies the test, not its result).

**REFRESH CAS (revised this pass — replaces "REFRESH CONCURRENCY," same test intent, corrected mechanism, §13.2):**
- Two genuinely parallel HTTP requests presenting the same refresh token against a running instance → exactly one `200` with a new access+refresh pair, exactly one `401 REFRESH_TOKEN_REUSE_DETECTED` (or `401 INVALID_REFRESH_TOKEN` if the losing request instead observes the winner's already-completed revoke, §13.2/§13.5's ordering analysis) — **never two `200`s, never two successor token pairs**.
- Assert no two valid successor token pairs are ever issued from one presented token, across repeated trials (flakiness in a race-condition fix must be caught by running this many times, not once).
- **Assert no `SELECT ... FOR UPDATE` (or any other API-layer lock) code path exists** in the refresh implementation — a static-analysis/code-review gate, not only a runtime behavioral test, since 6A-compliance is a design property as much as a behavioral one (§13.2).

**FORCED TOKEN REVOCATION (new this pass, §12.4):**
- A force-revoked access token is rejected on an **unrelated normal API endpoint** (not the endpoint that triggered the revocation) — e.g., revoke via `PlatformAdminOnly` revoke-all, then assert the same token is rejected on `GET /api/v1/auth/me`.
- The same force-revoked token is rejected on **WebSocket authentication** (handshake attempt with the denylisted token).
- `revoke-all` denylists **every** currently-known `access_token_jti` across **all** of a user's `ACTIVE` sessions, not just one — assert with a user holding 3+ concurrent sessions.

**MFA (revised this pass, §11.4, §15.3, §21.18):**
- `mfa_challenge_token` cannot access any normal `/api/v1/*` resource route (assert `401` on a representative sample, not just one route).
- Expired challenge (past its 5-minute `exp`) is rejected.
- Consumed challenge (already used for a successful verification) is rejected on replay, even though signature-valid.
- Wrong audience/`token_use` (e.g., an ordinary access token presented where a challenge is expected, or vice versa) is rejected.
- Excessive failed TOTP attempts against the same challenge/user are rate-limited (5/15min lockout).
- **Two genuinely concurrent `POST /api/v1/auth/mfa/verify` requests presenting the same challenge and the same correct TOTP code** → exactly one atomic `SET NX` claim succeeds, exactly one session/access+refresh-token pair is issued, and the other request receives `401 MFA_CHALLENGE_CONSUMED` — never two sessions created for the same challenge.
- **Redis unavailable at the atomic-claim step** → the verify call fails `503 DEPENDENCY_UNAVAILABLE`; no session is created and no tokens are issued (asserted explicitly, not inferred).

**PASSWORD RESET (revised this pass — corrected to test the honest DB-then-Redis separation, §13.5, §21.11; no test in this group may assume PostgreSQL and Redis provide one atomic transaction):**
1. **DB transaction fails** (bad/expired/already-consumed token, or an injected DB error) → no password change, no session-status change, nothing committed; the endpoint reports failure (`400`/`409`/`503` per §22) and no partial durable state exists to assert against.
2. **DB commits, Redis succeeds (Case A, §13.5)** → password changed; every previously-`ACTIVE` session transitions to `REVOKED`; every one of those sessions' current `access_token_jti` values is captured (via the transaction's own `RETURNING`) and globally denylisted; response reports all three completion flags `true`.
3. **DB commits, Redis partially or fully fails (Case C, §13.5)** → password is still changed and sessions are still `REVOKED` (asserted directly against the database, independent of the Redis outcome); the endpoint does **not** report `access_token_revocation_completed: true`; the returned error/response uses 6A's frozen envelope shape (§22); the response body is asserted to contain no `jti`, token value, session ID, or other internal implementation detail — only the three boolean completion flags.
4. **Old refresh token, presented after the DB transaction has committed** → rejected `401 INVALID_REFRESH_TOKEN` because the session is durably `REVOKED` (§13.2's CAS observes `status != 'ACTIVE'`) — this holds regardless of whether the Redis step in test 2/3 succeeded or failed, since refresh rejection depends only on database state.
5. **Old access token whose `jti` was successfully denylisted (Case A outcome)** → rejected immediately on an unrelated normal API route (e.g., `GET /api/v1/auth/me`) and on a WebSocket handshake attempt (§12.4, §19.3).
6. **Old access token whose denylist delivery was missed due to a Redis failure (Case C outcome)** → this token is asserted to remain **accepted** on an unrelated normal API route until its own natural ≤15-minute expiry (the honest, documented residual exposure, §13.5) — the test explicitly asserts this as the *expected*, disclosed behavior for this case, not a defect, and is explicitly tied to DEP-6B-08 (§36.3) in the test's own documentation/comments so the residual exposure is never later mistaken for an unnoticed regression.
7. **Meta-requirement for this entire test group:** no test in this group asserts, relies on, or is written as if PostgreSQL commit and Redis denylist population happen as a single atomic transaction — each test explicitly drives or asserts the DB step and the Redis step as separable events, including forcing a DB-commits-then-Redis-fails ordering to exercise Case C directly (e.g., via a fault-injection point between step A and step B, §13.5).

**MULTI-ORG LOGIN (new this pass, §9.3, §21.6):**
- User cannot select an organization outside the continuation token's allowed memberships — assert `403 ORGANIZATION_SELECTION_INVALID`, no distinguishing detail in the response.
- Membership suspended between password success and organization selection → denied at selection time (live re-validation, not the stale token snapshot).
- Organization suspended between the same two steps → denied at selection time.
- MFA ordering is correct: organization selection always completes (or is not needed) before an MFA challenge is issued; no MFA challenge token is ever issued with an unresolved `organization_id`.

**BREAK-GLASS (new this pass, §18.3a):**
- No `X-Break-Glass-Grant` header on a tenant-scoped request from a `PLATFORM_ADMIN` → denied (`403 AUTHORIZATION_DENIED`, not silently allowed).
- Wrong/nonexistent `grant_id` → denied (`403 BREAK_GLASS_GRANT_INVALID`).
- Expired grant → denied.
- Released grant → denied, immediately (no propagation delay).
- Grant for Org A used against Org B → denied.
- Grant used by a different admin, or the same admin under a different session, than the one that opened it → denied.
- Redis unavailable at grant-validation time → `503`, denied, never allowed.
- An ordinary `PLATFORM_ADMIN` access token with **no** grant at all cannot access tenant data (already covered in §31's matrix, restated here as an explicit test).
- Every elevated action performed under a valid grant carries that `grant_id` in its audit correlation metadata (§18.3a step 8, §25).

**CENTRAL INTERNAL ISSUER (new this pass, §17.2):**
- Worker's authenticated workload identity cannot obtain a token asserting `service_id=voice-gateway` (or any `service_id` other than its own) from the issuer.
- A calling service cannot inject an arbitrary `on_behalf_of_organization_id` the issuer's policy hasn't authorized for it.
- A user-facing access token is rejected at the issuer's own workload-authentication step and at any `/api/internal/v1/*` route (never accepted as a substitute for an internal token).
- An internal JWT is rejected at any public `/api/v1/*` route.
- Internal token expiry (5 min) is enforced — a token used 1 second past `exp` is rejected.
- Central-issuer key rotation is verified: tokens signed with the pre-rotation key remain verifiable via cached JWKS until the rotation window elapses; tokens signed with the new key are accepted once published.

**Minimum explicit tests (task-mandated, all included above or listed for completeness):** User A cannot access Org B's resources (✓ tenant-isolation); no-permission user gets `403` (✓ authz-matrix); unauthenticated gets `401` (✓ contract); expired token rejected (✓ token-lifecycle); revoked session cannot refresh (✓ token-lifecycle); refresh reuse detected (✓ refresh concurrency/replay); revoked membership loses access (✓ unit, `PermissionEvaluationService` step 1); suspended org blocked (✓ unit, step 2); platform-admin ops audited (✓ security, break-glass synchronous-audit assertion, and break-glass runtime-authorization tests above); internal service JWT cannot authenticate as public user and vice versa (✓ contract, §17 row in §31, and central-internal-issuer tests above).

---

## 33. OpenAPI Readiness

Per 6A's approach (ADR-6A-06 — FastAPI-generated OpenAPI + vendor extension fields, no separate hand-maintained spec), this document supplies the semantics FastAPI's generator needs, not a hand-written spec:

- **Reusable schemas:** `AuthenticationContext` (§6.1), `Session`, `ApiKey` (create-response vs. list/get-response variants — the former includes the one-time raw key, the latter never does), `Role`, `Permission`, `ErrorResponse` (6A's frozen shape), `LoginResponse` (three-shape discriminated union per §9.3/§21.1 — direct success / organization-selection-required / MFA-challenge-required), `BreakGlassGrant` (§21.4/§21.35).
- **Security schemes:** `BearerAuth` (JWT, user-facing access token), `ApiKeyAuth` (`Authorization: Bearer vxa_...` or `X-Api-Key`), `InternalBearerAuth` (JWT, internal-only, restricted to `/api/internal/v1/*` paths in the generated spec via a distinct security requirement — verified against the central internal token issuer's public JWKS, §17.2), `MfaChallengeAuth` (JWT, restricted to `POST /auth/mfa/verify` only, §11.4), `LoginContinuationAuth` (JWT, restricted to `POST /auth/organization/select` only, §11.5) — **two new security schemes this pass**, closing the gap where the prior draft referenced `mfa_challenge_token` without a corresponding declared scheme.
- **Auth flows:** OAuth2 authorization-code flow shape declared for `/auth/oauth/{provider}/*` (§15.2), with provider-specific `authorizationUrl`/`tokenUrl` left as implementation-time configuration, consistent with ADR-6B-07's deferral.
- **Authz metadata:** each endpoint's required permission (§20 tables) is expressible as a vendor extension (`x-required-permission`) for tooling/doc-generation purposes, mirroring 6A's existing vendor-extension pattern; break-glass-protected tenant-scoped endpoints additionally carry `x-requires-break-glass-header: X-Break-Glass-Grant` when invoked by a `PLATFORM_ADMIN` actor (§18.3a).
- **Header parameter:** `X-Break-Glass-Grant` declared as a reusable OpenAPI header parameter component, referenced by every tenant-scoped route rather than redefined per-route (§18.3a, §20).
- No application code is included in this document — schemas and semantics only.
- **Status: OpenAPI-ready for all 36 endpoints** (§20, §21) — the prior draft's "OpenAPI-ready" claim covered only the previously-detailed subset; this pass extends the same semantics to every endpoint, closing that gap.

---

## 34. Implementation Readiness

**Reading this table:** "6B API status" is always about design/contract completeness (is the endpoint, schema, and behavior fully specified?). "Implementation status" is about whether it can be built *today* against the frozen Phase 5 schema without further upstream work. A row can be **DESIGN COMPLETE / CONTRACT COMPLETE** while its implementation status is **IMPLEMENTATION DEPENDENCY** or **BLOCKED** — that is not a contradiction, it is the point of splitting the columns (§4-equivalent correction, see §38).

| Area | Decision | Current Phase 5 support | 6B API status | Implementation status | Dependency | Notes |
|---|---|---|---|---|---|---|
| Authentication (password) | Argon2id, generic failure messaging | Full (`identity.users`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §15/§21 |
| Authorization | RBAC + permission-evaluation pipeline, deny-by-default | Full (5B roles/permissions tables) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §8, §9.1 |
| Tenant isolation | Server-derived `organization_id`, RLS as independent layer | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §9 |
| JWT | RS256, separate user-facing/internal keypairs, JWKS-distributed | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | JWKS distribution mechanism (operational, not schema) | §10–§11, ADR-6B-04 |
| **Refresh-token concurrency (corrected this pass)** | Atomic conditional `UPDATE ... RETURNING` (CAS) closes the concurrent-rotation race with **no API-layer lock**, per frozen 6A §17.3 (a prior draft's `SELECT ... FOR UPDATE` is retired); lost-response trade-off explicitly accepted (strict reuse detection, §13.6) | Full (`identity.sessions`, no schema change needed) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §13.2, §13.2a, §13.6, ADR-6B-01 (revised) |
| Refresh tokens (format/lifecycle, general) | `{session_id}.{secret}` rotating opaque, reuse detection | Full (`identity.sessions`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §13, ADR-6B-01 |
| Sessions | `identity.sessions` CRUD-style API | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §14 |
| API keys | `vxa_` format, scope-as-ceiling | Full (`identity.api_keys`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §16 |
| **Access-token forced revocation (corrected this pass)** | Denylist check now runs on every access-token validation path (§12.2, §12.4), not an admin-route-only check; Redis becomes a hard dependency of access-token auth itself | Full (Redis-only, no Phase 5 schema change) | CONTRACT COMPLETE | IMPLEMENTATION READY | Redis HA sized for the expanded blast radius (operational, not schema — availability of Redis now gates all access-token auth, §27/§28) | §12.2, §12.4, §19.3, ADR-6B-02 (revised) |
| Internal service authentication (claims/audience/lifetime) | Per ADR-6A-09, claims unchanged | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | JWKS for the (now centrally-issued) internal keypair (operational) | §17.1, §17.3 |
| **Central internal token issuer (new this pass)** | Single trusted issuer owns the private signing key; callers authenticate via trusted workload identity; no `ServiceAccount` table | No Phase 5 change required (infrastructure-identity concern, not a DB concern) | CONTRACT COMPLETE | IMPLEMENTATION DEPENDENCY (the issuer itself — a new internal platform capability — must be built; this is an infrastructure/deployment dependency, not a Phase 5 one) | Issuer service build-out + workload-identity mechanism wiring (infrastructure, not Phase 5) | §17.2, ADR-6B-11 |
| WebSocket authentication | Per ADR-6A-05, applied unchanged, now including the forced-revocation denylist check at handshake and heartbeat (§19.3) | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | Heartbeat/presence-key revocation check, now extended to cover denylisted `jti`s too | §19 |
| Platform admin (base authz) | DB-role + GUC mechanism (`app_platform_admin`, `is_platform_admin()`) | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §18.1–18.2 |
| **Break-glass runtime authorization (new this pass)** | `X-Break-Glass-Grant` header + six-check per-request validation (existence/expiry/release/admin/session/org), fail-closed on Redis unavailability, multiple-simultaneous-grants policy | Full (Redis-only, no Phase 5 schema change) | CONTRACT COMPLETE / SECURITY MODEL COMPLETE | IMPLEMENTATION READY (the runtime-authorization contract itself needs no durable table — it is fully specified against the same interim Redis mechanism, §18.3a) | None for runtime authorization itself (distinct from the row below) | §18.3a |
| **Break-glass durable persistence** | Grant/release *action* audit is full (5J); *live lifecycle state* has no durable table | **Grant-lifecycle persistence: none** — no durable Phase 5 table | CONTRACT COMPLETE (interim mechanism fully specified) | IMPLEMENTATION DEPENDENCY (durable grant-lifecycle persistence only) | Durable break-glass grant persistence — future Phase 5.x (DEP-6B-01, §36.3 item 1) | §18.3, §21.4, §24 |
| **Audit-vocabulary extension** | Reuses 5J's `audit.audit_events` exclusively; two-tier semantics | Full for 12 of 16 event categories (§25 Tier 1); **no matching `action_kind`** for 4 (§25 Tier 2 — grew from 3 to 4 this pass by adding the forced-revocation-denylist-write event, a direct consequence of this pass's own new global-revocation design, not a newly-discovered pre-existing gap) | CONTRACT COMPLETE (audit requirement specified for every event, including the 4) | DESIGN COMPLETE for Tier 1; IMPLEMENTATION DEPENDENCY for Tier 2 (`SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout, forced-revocation-denylist-write) | Authentication audit-vocabulary extension — future Phase 5.x (DEP-6B-02, §36.3 item 2) | §25, ADR-6B-06 |
| **MFA challenge credential** | Short-lived restricted JWT (`token_use=mfa_challenge`), single-use via an **atomic Redis `SET NX` claim (corrected this pass from a check-then-write shape)**, dedicated audience | Full (Redis-only, no Phase 5 schema change) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §10.1, §11.4, §15.3, §21.18 |
| **Password-reset — durable session/password revocation** | On successful reset: change password and revoke all sessions in one database transaction, via the same atomic-conditional-`UPDATE` (CAS) pattern as refresh rotation — no API-layer lock | Full (`identity.sessions`/`identity.users`, no Phase 5 schema change) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §13.5, §21.11 |
| **Password-reset — immediate global access-token revocation (corrected this pass — split from the row above)** | Best-effort Redis denylisting of every captured `jti`, attempted after the durable transaction commits; honestly reported as incomplete when it fails (Case C, §13.5) | Redis-only, no Phase 5 schema change — but **no crash-safe coordination exists between the DB commit and the Redis write** | CONTRACT COMPLETE (the best-effort contract, its honest failure reporting, and the residual-risk disclosure are fully specified) | IMPLEMENTATION DEPENDENCY (crash-safe/guaranteed-delivery immediate revocation specifically; the best-effort version above is implementable today exactly as specified) | Durable forced-revocation delivery/reconciliation — future dependency (DEP-6B-08, §36.3) | §13.5, §21.11, §28, §29 |
| MFA (enrollment/disable, base TOTP) | TOTP enroll/verify/disable | Full (`identity.users.mfa_enabled`/`mfa_secret_ref`) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §15.3 |
| MFA recovery | Intentionally deferred (ADR-6B-10) — current interim mechanism is platform-admin-assisted, out-of-band recovery only | No recovery-codes/backup table in 5B | Interim mechanism CONTRACT COMPLETE (generic platform-admin-assisted flow, §18); **robust self-service recovery NOT DESIGNED** | DEFERRED BY DESIGN — not a defect, a scoped-out decision for this phase | Robust MFA recovery mechanism — future security requirement (§36.3 item 3) | §15.3, ADR-6B-10 |
| **Multi-org organization-selection flow (new this pass)** | Login-continuation token (§11.5) + `POST /auth/organization/select` (§21.6), explicit ordering (primary auth → org select → MFA → session/token issuance, §9.3) | Full (`organization.memberships`/`.organizations`, no schema change) | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §9.3, §11.5, §21.6 |
| OAuth/OIDC | Generic authorization-code flow shape only | `identity.oauth_identities` table exists; no IdP integration | CONTRACT COMPLETE (generic shape) | BLOCKED — IdP-specific configuration is Phase 8 scope | IdP selection/config, Phase 8 (§36.3 item 4) | §15.2, ADR-6B-07 |
| Phone verification | Not designed | `phone_e164`/`phone_verified_at` columns exist, no OTP-delivery mechanism | NOT DESIGNED | BLOCKED — mechanism/provider undefined upstream | OTP mechanism/provider — future phase (§36.3 item 5) | §15.5, ADR-6B-09 |
| Rate limiting | Composite identity+IP defaults, soft lockout | Full (`identity.users.failed_login_count` etc.) | CONTRACT COMPLETE | IMPLEMENTATION READY (defaults provisional, not load-tested) | Load-test validation of defaults | §23 |
| Observability | Metrics/logging/tracing per §26 | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §26 |
| Performance | Latency budgets, TARGET not MEASURED — corrected this pass to no longer claim zero-I/O access-token verification | — | DESIGN COMPLETE | IMPLEMENTATION READY (targets, not yet measured) | Load testing to convert TARGET → MEASURED | §27 |
| Error handling | 6A envelope, no new shape; `IDEMPOTENCY_KEY_REUSE_MISMATCH` status corrected from `422` to `409` this pass to match 6A | Full | CONTRACT COMPLETE | IMPLEMENTATION READY | None | §22 |
| **Complete endpoint/OpenAPI contracts (corrected this pass)** | All 36 endpoints fully expanded (§21), not just a security-critical subset; two new security schemes declared (§33) | — | CONTRACT COMPLETE (36/36 endpoints) | IMPLEMENTATION READY | None | §20, §21, §33 |
| Testing | Strategy defined, expanded this pass with concurrency/forced-revocation/MFA/multi-org/break-glass/central-issuer test categories (§32) | — | DESIGN COMPLETE | IMPLEMENTATION READY | Test-environment DB with RLS enabled; a test harness capable of issuing genuinely concurrent requests (for the refresh-concurrency test, §13.2a) | §32 |
| Custom permissions (per-membership) | Not implemented (ADR-6B-05) | No such column in frozen 5B `organization.memberships` | NOT DESIGNED | BLOCKED — out of this document's authority | Phase 5 schema change if ever prioritized (not in §36.3 — not currently requested) | ADR-6B-05 |
| Abuse step-up (CAPTCHA) | Deferred, rate-limiting is interim control | None | DEFERRED BY DESIGN | DEFERRED — no provider selected | CAPTCHA/adaptive-challenge provider — future phase (§36.3 item 6) | §23, ADR-6B-03 |

**Roll-up (feeds §4/§38's status model):** every row above is either IMPLEMENTATION READY or has its non-readiness traced to a named, upstream Phase 5.x/Phase 8/infrastructure dependency in §36.3 or explicitly in this table (the central issuer's own build-out) — no row is "Blocked" for an undisclosed or unexplained reason. Every one of this pass's six blockers now has its own explicit row, distinguishing DESIGN/CONTRACT status from IMPLEMENTATION status from its DEPENDENCY, per the task's requirement.

---

## 35. Traceability

**Status vocabulary used below:** `PASS` (fully supported end-to-end today, no caveat), `DESIGN COMPLETE` (API/contract fully specified; implementation may still depend on operational, not schema, work), `IMPLEMENTATION DEPENDENCY` (design complete, but a concrete upstream Phase 5.x item blocks full implementation), `PARTIAL` (some sub-cases pass, others do not — sub-cases enumerated in Notes), `BLOCKED BY PHASE 5.x` (cannot be implemented without a future Phase 5 schema/data change this document does not make).

| Requirement | Architecture | Domain (4A) | Phase 5 capability | API (this doc) | Permission | Business rule | DB interaction | Audit event | Status |
|---|---|---|---|---|---|---|---|---|---|
| `FR-AUTH-001` (JWT + OAuth2 SSO) | HLA §7.9 | `User` aggregate | `identity.users`, `identity.oauth_identities` | §20.1 (login, oauth/*) | — | Generic-failure, no enumeration | `identity.users` read/insert | `USER_LOGIN`/`USER_LOGIN_FAILED` | PASS |
| `FR-AUTH-002` (RBAC, platform roles + custom) | HLA §7.9 | `Role` aggregate, `PermissionEvaluationService` | `organization.roles`, `.permissions`, `.role_permissions` | §20.6 | `role:read`/`role:manage` | System roles immutable (`trg_protect_system_roles`) | `organization.roles` CRUD | `ROLE_ASSIGNED`/`PERMISSION_CHANGED` | PASS (custom per-membership permissions out of scope, ADR-6B-05 — not part of this requirement's approved scope) |
| `FR-AUTH-003` (scoped API keys) | HLA §7.9 | `ApiKey` aggregate | `identity.api_keys` | §20.5 | `api_key:read`/`api_key:manage` | Scopes ⊆ issuer permissions at issuance | `identity.api_keys` CRUD | `API_KEY_CREATED`/`API_KEY_REVOKED` | PASS |
| `FR-AUTH-004` (audit every authn/authz decision) | — | `AuditEvent` aggregate | `audit.audit_events` | §25 (cross-cutting) | — | Write-once, no UPDATE/DELETE role | `fn_insert_audit_event()` | Tier 1 (12 event categories): full coverage. Tier 2 (`SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout, **forced-revocation-denylist-write — added this pass**): no durable `action_kind`, telemetry-only today | **PARTIAL** — DESIGN COMPLETE (the requirement to audit every event, including all 4 Tier-2 kinds, is specified); IMPLEMENTATION DEPENDENCY for the 4 Tier-2 event kinds pending the audit-vocabulary extension (DEP-6B-02, §36.3 item 2). Not PASS: a durable audit record does not yet exist for those 4 kinds. The Tier-2 count grew from 3 to 4 this pass strictly because this pass introduced the global forced-revocation check itself (§12.4) — not a newly-discovered pre-existing gap. |
| `FR-AUTH-005` (MFA for admin roles) | — | `MfaConfig` (deferred in DDD) | `identity.users.mfa_enabled/mfa_secret_ref` | §20.2, §21.18 | — | Recovery: intentionally deferred (ADR-6B-10), not a gap in the base requirement; login step-up now fully specified via the MFA challenge token (§11.4, new this pass) | `identity.users` update | `USER_MFA_ENABLED`/`USER_MFA_DISABLED` | PASS for core TOTP enrollment/verification and login step-up. MFA *recovery* is a separate, explicitly deferred concern (§36.3 item 3), tracked there rather than counted against this requirement. |
| `FR-TEN-001..003` (tenant isolation, org-scoped admin) | HLA §7.9, 3A §11 | `Organization`/`Membership` aggregates | RLS on `organization.*`/`identity.api_keys` | §9 (cross-cutting), §9.3 (multi-org login, new this pass) | — | Server-derived `organization_id` | `SET LOCAL app.tenant_id` | — | PASS |
| `FR-TEN-004` (platform super admin, audited cross-tenant) | 3A §11.3 break-glass | Platform Admin (DDR-4A-005) | `app_platform_admin` DB role, `is_platform_admin()` | §18, §21.4, §21.35, **§18.3a (runtime authorization, new this pass)** | `PlatformAdminOnly` + valid `X-Break-Glass-Grant` for every elevated request (§18.3a) | Time-boxed, justified, synchronous audit; every elevated request now cryptographically/procedurally proves its grant, not only the initial grant/release calls | Grant-lifecycle persistence — no durable Phase 5 table (§18.3, §21.4); **runtime authorization itself needs no durable table and is IMPLEMENTATION READY today (§18.3a)** | `BREAK_GLASS_GRANTED`/`RELEASED` (this part: PASS — durable and synchronous today) | **IMPLEMENTATION DEPENDENCY** — API design, authorization (including the now-fully-specified per-request runtime check, §18.3a), and grant/release audit are DESIGN COMPLETE and implementable today; only the durable grant-lifecycle persistence table remains a future Phase 5.x dependency (§36.3 item 1). Not BLOCKED: the requirement is implementable end-to-end using the interim mechanism, just not yet with durable grant-state persistence. |
| `NFR-SEC-003` (RBAC/tenant isolation at all layers) | HLA §7.9 | — | RLS + `PermissionEvaluationService` | §8, §9 | — | Deny-by-default | — | — | PASS |
| `NFR-SEC-007` (rate limiting per tenant/API key) | SRS §4 | — | — | §23 | — | Composite identity+IP | — | — | PASS (defaults provisional, not load-tested — does not affect design-completeness status) |
| `NFR-SEC-008` (OWASP ASVS alignment) | SRS §4 | — | — | §19, §22 (no enumeration) | — | — | — | — | PASS |

Source does not define a formal requirement ID for: session management, refresh-token rotation/reuse-detection design, internal-service auth mechanics beyond ADR-6A-09, or WebSocket connection-auth mechanics beyond ADR-6A-05 — these are grounded directly in 6A's architecture decisions and the 5B/5J schema rather than a numbered SRS requirement, and are cited as such throughout §7–§19 rather than against a fabricated requirement ID. All are PASS by the same standard applied above.

---

## 36. ADRs and Open Questions

| ID | Title | Decision | Status |
|---|---|---|---|
| ADR-6B-01 | Refresh token format for session-bound reuse detection | `{session_id}.{secret}`, enabling reuse detection despite the single-hash-column schema, with no Phase 5 change. **Revised (twice):** an intermediate pass closed the concurrent-refresh race with an API-layer `SELECT ... FOR UPDATE` row-level lock (§13.2), which itself violated frozen 6A §17.3's rule against API-layer application locking; **this pass replaces that lock with an atomic, conditional `UPDATE ... WHERE ... RETURNING` (CAS) statement (§13.2)** — the same race-closure guarantee, provided entirely by Postgres's own row-level MVCC, with no application-level lock of any kind. A strict-reuse-detection stance on lost-response retries remains an explicit, accepted trade-off (§13.6) | Decided (revised this pass — 6A-compliance correction) |
| ADR-6B-02 | Access-token statelessness vs. forced-revocation denylist | Stateless signature+claim verification for the normal path; narrow Redis denylist for admin-forced/break-glass-triggered revocation. **Revised this pass:** the denylist check now runs on **every** access-token validation path (§12.2, §12.4), not only admin-triggered routes — the prior scoping did not actually achieve global revocation, which this revision corrects. Access-token verification is consequently no longer zero-I/O; Redis unavailability at this check fails closed (§12.2, §27, §28) | Decided (revised this pass) |
| ADR-6B-03 | Auth-endpoint abuse step-up (closes 6A's R-8) | CAPTCHA/adaptive-challenge deferred to a future phase (no provider/mechanism specified in Phase 1–5); composite identity+IP rate limiting + soft lockout is the interim, fully-grounded control | Decided (interim) |
| ADR-6B-04 | JWT signing algorithm | RS256 (asymmetric), separate keypairs for user-facing vs internal tokens, JWKS-distributed | Decided |
| ADR-6B-05 | Membership `CustomPermissions` (4A's `OQ-4A-04`) | Not implemented — `organization.memberships` has no such column in the frozen 5B schema; RBAC in this document is role-only, no per-membership permission override designed | Decided (resolves upstream open question by confirming it was never built) |
| ADR-6B-06 | Audit vocabulary gap for session-revocation/refresh/forced-revocation events | `SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout, and (**added this pass**) forced-revocation-denylist-write are not in 5J's `action_kind` CHECK constraint; interim mitigation via structured logs + metrics; recommend a future 5J-extension migration | Decided (interim), **open dependency on Phase 5** |
| ADR-6B-07 | OAuth2/SSO protocol specifics | Generic authorization-code flow shape only; IdP selection, OIDC-vs-SAML, and claim mapping deferred to Phase 8 per 3E's own explicit deferral | Decided (deferred scope) |
| ADR-6B-08 | System role set — DDD (9 roles) vs. DB (5 roles) discrepancy | Phase 5B's frozen 5-role seed DDL (`OWNER, ADMIN, MEMBER, BILLING_ADMIN, VIEWER`) is authoritative; Phase 4A/4H's 9-role narrative is superseded/aspirational and is not used anywhere in this document's authorization matrix or endpoint design | Decided |
| ADR-6B-09 | Phone verification | Not designed — `phone_e164`/`phone_verified_at` columns exist, no OTP-delivery mechanism specified anywhere in Phase 1–5 | Decided (documented limitation) |
| ADR-6B-10 | MFA recovery | **Intentionally deferred, not merely undesigned.** Current TOTP MFA design (§15.3) is kept unchanged; no recovery-codes or backup table is added to Phase 5. The retained interim mechanism is platform-admin-assisted, out-of-band recovery (generic flow, §18). A robust, self-service recovery mechanism is a named future security requirement (§36.3 item 3) — future candidate mechanisms are listed there as non-exhaustive examples only, none selected by this document | Decided (deferred scope, ADR text intentionally does not choose a future mechanism) |
| **ADR-6B-11** | **Central internal token issuer — refinement of ADR-6A-09 (new this pass)** | Internal service tokens are issued exclusively by a single, trusted **central internal token issuer** that owns the private signing key; Worker, Voice Gateway, and Core API hold only the issuer's public JWKS, never the private key. Callers authenticate to the issuer via a trusted workload/deployment identity mechanism (no new Phase 5 `ServiceAccount` table). This does not redecide ADR-6A-09's claim set, audience, algorithm, or lifetime — it closes the narrower question ADR-6A-09 left implicit (each deployable holding its own signing key was this document's own prior-pass assumption, not something ADR-6A-09 itself mandated) | Decided — binding for this pass, applies ADR-6A-09's substance unchanged |

No ADR was created for trivial implementation details (e.g., exact JSON field naming, exact HTTP verb choice for a CRUD op) — only for genuine architectural gaps or upstream-conflicting decisions, per this document's own instruction not to over-produce ADRs.

### 36.3 Future / Upstream Dependencies Register

This register is the single authoritative list of everything 6B's design depends on that is **not yet built**. Its purpose is the opposite of a hidden-requirements list: every item here is explicitly named so that none of them can silently become a blocker to *this document's* architecture, contract, or security-model approval (§4, §38). A dependency being listed here means "6B's design accounts for this and names it," not "6B is incomplete until this exists."

| ID | Description | Why needed | Current status | Required phase | Requires Phase 5.x? | Blocks 6B architecture? | Blocks 6B implementation? |
|---|---|---|---|---|---|---|---|
| DEP-6B-01 | Durable break-glass grant-lifecycle persistence (target org, justification, TTL, granting admin, active/released state) | Break-glass grant/release *actions* are already durably audited (`BREAK_GLASS_GRANTED`/`RELEASED`, 5J); but the *live lifecycle state* of a grant (is it still active, remaining TTL) has no durable table — only an interim Redis TTL key (§18.3, §24) | **RESOLVED (Phase 5L, 2026-08-24)** — `organization.break_glass_grants` (migration `087_5B1.sql`) now provides durable grant-state persistence; Redis remains the fast-path cache. See `5B-Identity-Organization-Multitenancy-Security.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. ~~API contract complete (§18.3, §21.4); interim Redis mechanism specified; no durable table exists~~ | Future Phase 5.x | Yes | **No** | Yes — for durable grant-state persistence only; the API, authz, and action-audit are implementable today without it |
| DEP-6B-02 | Authentication audit-vocabulary extension: `SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout, **forced-revocation-denylist-write (added this pass)** `action_kind` values | 5J's `action_kind` CHECK constraint has no matching value for these 4 event kinds; using an unrelated existing value would misrepresent the event (§25 Tier 2) | **RESOLVED (Phase 5L, 2026-08-24)** — doc-only governance amendment; all 4 values added to `5J-Analytics-Audit-Schema.md` §14.3 (`§` marker). No SQL migration required (`action_kind` has no enum constraint). ~~Audit requirement specified (§25); telemetry-only interim signal (§26); no schema change made~~ | Future Phase 5.x | Yes | No | Yes — for these 4 event kinds only; all other audit events are fully supported today |
| DEP-6B-03 | Robust, self-service MFA recovery mechanism | Current interim mechanism (platform-admin-assisted, out-of-band) does not scale and is not self-service; a durable design requires a Phase 5 schema decision (e.g., a recovery-codes table) this document's authority does not extend to | Intentionally deferred (ADR-6B-10, §15.3); example future mechanisms listed, none selected | Future phase (Phase 5.x schema + 6B.x or 6C API work) | Yes (for most candidate mechanisms) | No | No — current interim mechanism is implementable today; this is a future security *enhancement*, not a blocker to today's design |
| DEP-6B-04 | OAuth2/OIDC provider-specific implementation (IdP selection, OIDC vs. SAML, claim mapping) | This document specifies only the generic authorization-code flow shape (§15.2); IdP integration is explicitly Phase 8 scope per 3E | Generic shape DESIGN COMPLETE; provider integration not designed | Phase 8 | No (Phase 8 work, not Phase 5) | No | Yes — for actual OAuth login with a real IdP; generic flow contract is complete today |
| DEP-6B-05 | Phone verification mechanism/provider (OTP delivery) | `phone_e164`/`phone_verified_at` columns exist in 5B, but no OTP-delivery mechanism or provider is specified anywhere in Phase 1–5 (§15.5, ADR-6B-09) | Not designed | Future phase | Possibly (provider integration, not necessarily schema) | No | Yes — phone verification cannot be implemented until a mechanism/provider is chosen |
| DEP-6B-06 | CAPTCHA / adaptive-challenge step-up for auth-endpoint abuse | Closes 6A's R-8 only via an interim control today (composite identity+IP rate limiting + soft lockout, ADR-6B-03); no CAPTCHA/bot-detection mechanism exists in Phase 1–5 | Deferred by design; interim control fully implementable today | Future phase | No | No | No — interim control is sufficient and implementable today; this is a future hardening option, not a current blocker |
| **DEP-6B-07** | **Central internal token issuer build-out (new this pass)** | ADR-6B-11 specifies the issuer's contract fully (§17.2), but the issuer is a new internal platform capability — a service that must actually be built and wired to a trusted workload-identity mechanism — not something the frozen Phase 5 schema or 6A's prior architecture already provides | Contract fully specified (§17.2); no schema change needed; **infrastructure/deployment build-out required** | Infrastructure/deployment work, not a Phase 5.x or Phase 8 item | **No** — this is an infrastructure dependency, not a Phase 5 schema dependency | No | Yes — internal service-to-service calls cannot use the corrected central-issuer model until the issuer itself exists; this does not block 6B's *design* approval, only the *implementation* of the internal-auth path |
| **DEP-6B-08** | **Durable forced-revocation delivery / reconciliation (new this pass)** | Password-reset-confirm's global access-token denylisting (§13.5, §21.11) is a best-effort step performed in Redis *after* the durable database transaction (password change + session revocation) has already committed — there is no cross-system transaction coordinator between PostgreSQL and Redis, and the frozen 5B schema has no `password_reset_revocation_pending`/`revocation_delivery_status`/`revocation_outbox`-equivalent durable field to track undelivered denylist entries for crash-safe retry. If the Redis step fails or is only partially completed (Case C, §13.5), some already-issued access tokens for the affected sessions can remain usable until their own natural ≤15-minute expiry, and this cannot currently be reconstructed/retried crash-safely. **Possible future implementation mechanisms are listed here only as non-exhaustive examples for a later phase to evaluate — none is selected or committed to by this document:** a transactional outbox, a durable revocation-job table, a reconciliation worker that periodically re-derives and re-delivers missing denylist entries from `identity.sessions`' own `REVOKED` rows, or a persistent security-event delivery mechanism. Choosing among these requires a Phase 5 schema decision this document's authority does not extend to. | **RESOLVED (Phase 5L, 2026-08-24)** — the existing `audit.domain_event_outbox` (migration `077_5J1.sql`) is reused, no new table added; the password-reset-confirm transaction now durably enqueues an `identity.forced_revocation_required` outbox event (payload: `user_id`, `session_ids[]`, `access_token_jti[]`, `reason` — JTIs only, never raw tokens) in the same transaction as the password change and session revocation, giving crash-safe retry and an observable terminal `FAILED` state. See `5B-Identity-Organization-Multitenancy-Security.md`'s Phase 5L amendment and `5L-Global-Database-Reconciliation.md`. ~~Best-effort mechanism fully specified and honestly documented (§13.5, §21.11); durable crash-safe delivery/reconciliation not designed or chosen here~~ | Future Phase 5.x (for any durable-tracking candidate) + accompanying 6B.x/6C API work | Yes (for every candidate mechanism listed) | **No** — does not block 6B's architecture, API contract, or security-design completeness; the best-effort contract and its honest Case A/B/C behavior are already fully specified | **Yes** — specifically for *crash-safe, guaranteed* immediate access-token revocation on password reset; does **not** block the already-complete best-effort design, and does **not** block ordinary refresh-capability revocation (which is unconditional and database-durable, §13.5) |

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
- [x] Token architecture: all six types (four durable/session-bearing + two narrow-purpose ephemeral JWTs added this pass) fully specified with purpose/issuer/audience/claims/algorithm/lifetime/rotation/revocation/storage/transport/replay/failure/audit (§10–§11).
- [x] Access token lifecycle fully defined, including the explicit logout-vs-token-validity answer, **corrected this pass so forced revocation is a global check rather than an admin-route-only one** (§12.2, §12.4).
- [x] Refresh token security: rotation, reuse detection, revocation, session binding all defined, with the schema-constraint limitation explicitly documented rather than papered over, **and the concurrent-refresh race closed via an atomic conditional `UPDATE` (CAS) — corrected in this pass from an earlier `SELECT ... FOR UPDATE` design that conflicted with frozen 6A §17.3** (§13, ADR-6B-01).
- [x] Session management: list/revoke one/all, authorization boundary (no cross-user revocation without platform-admin elevation) defined; revoke-all's forced-token-denylisting behavior and its documented current-jti-only limitation stated explicitly (§14, §12.4, §21.36).
- [x] Login flows limited to actually-supported methods (password, OAuth2-shape, MFA) — no fabricated OAuth/passkey/social detail beyond what 5B's schema grounds; **multi-organization login continuation and the MFA challenge token fully specified this pass** (§9.3, §15).
- [x] Account security: enumeration avoidance, lockout, rate limiting defined; abuse-step-up gap (6A's R-8) explicitly closed via ADR-6B-03 rather than left open (§23).
- [x] API keys: full lifecycle, format, hashing, one-time reveal, scope-as-ceiling chain defined without breaking tenant isolation (§16).
- [x] Internal service auth: applies 6A's ADR-6A-09 claim set/audience/lifetime unchanged; **issuance model corrected this pass to a central internal token issuer (ADR-6B-11) per the binding user decision — no Phase 5 `ServiceAccount` table created** — strictly separated from user auth bidirectionally (§17).
- [x] Authorization model: RBAC + permission evaluation pipeline + tenant membership + platform-level permissions, using only real roles/permissions from 5B (§8, §16, §31) — no invented permission strings.
- [x] Deterministic, fail-closed authz evaluation pipeline defined, with explicit behavior for every listed degraded-state scenario (§9.1, §28).
- [x] Platform admin: authz, tenant-boundary behavior, audit (including the one synchronous-audit exception), no silent bypass; **runtime authorization for every elevated request under an open grant fully specified this pass** (§18, §18.3a).
- [x] WebSocket auth: applies ADR-6A-05 without redeciding it; connection lifecycle, token transport, mid-connection expiry/revocation (**now including forced-token-revocation, §19.3**), rate/connection limits defined; voice-call WS explicitly out of scope (§19).
- [x] Error contract: reuses 6A's frozen shape exactly; no account-existence, password-validity-detail, internal-permission-structure, or credential-material leakage; **`IDEMPOTENCY_KEY_REUSE_MISMATCH`'s status corrected this pass from an erroneous `422` to 6A's actual `409`** (§22).
- [x] Exact HTTP status per endpoint/error branch defined; no blanket 200-on-failure anywhere (§20–§22).
- [x] Latency/performance budgets reasoned per stage, explicitly marked TARGET not MEASURED, with resilience-under-degradation explained; **the access-token-verification "zero I/O" claim retracted and replaced with an accurate, disclosed Redis dependency this pass** (§27).
- [x] Caching: explicit cacheable/non-cacheable list, tenant-aware keys, explicit invalidation triggers; **new entries added this pass for MFA-challenge consumption tracking and the expanded break-glass grant record** (§24).
- [x] Rate limiting: identity/IP-composite (not IP-only) for every auth-sensitive endpoint, values marked configurable defaults; **organization-selection and break-glass runtime limits added this pass** (§23).
- [x] Audit strategy reuses 5J's existing vocabulary; every genuine vocabulary gap documented explicitly rather than misusing an unrelated `action_kind`, **including the forced-revocation-denylist-write event this pass's own design introduced** (§25, ADR-6B-06).
- [x] Endpoint inventory (**36 endpoints — 35 + `POST /api/v1/auth/organization/select`, added this pass**) determined from the actual repo/schema, not copied from generic SaaS assumptions (§20).
- [x] **Consistent endpoint contract template applied, and — corrected this pass — every one of the 36 endpoints is fully instantiated with concrete values; none is left as "apply the template only"** (§21).
- [x] Realistic, syntactically valid, tenant-safe, security-safe JSON examples aligned with 6A's envelope; no password/secret/signing-key values ever shown in an example (§21).
- [x] Threat model covers all task-listed threat categories in Threat→Surface→Mitigation→Detection→Residual-risk format, **with new rows this pass for the concurrent-refresh race (closed), central-issuer compromise, MFA-challenge misuse, organization-injection, and break-glass-grant misuse** (§29).
- [x] Failure/resilience covers all task-listed dependency-failure scenarios, fail-closed where security requires it, **including the newly-mandatory-for-every-request Redis denylist/MFA-consumption/break-glass-grant checks this pass introduced** (§28).
- [x] Observability: all task-named metrics present plus latency histograms, correlation fields, and the never-logged list, **extended this pass with organization-selection, forced-revocation-check, MFA-challenge, break-glass-runtime, and internal-issuer metrics** (§26).
- [x] OpenAPI readiness: reusable schemas, security schemes (**two new schemes this pass for the MFA challenge and login-continuation tokens**), auth flows, authz metadata identified; no application code included; **status corrected to cover all 36 endpoints, not a subset** (§33).
- [x] Implementation readiness matrix covers all task-named areas, statuses honestly marked using the DESIGN COMPLETE / CONTRACT COMPLETE / IMPLEMENTATION READY / IMPLEMENTATION DEPENDENCY / BLOCKED / DEFERRED vocabulary — no row silently blocked without a named dependency; **rebuilt this pass with explicit new rows for refresh-token concurrency, forced revocation, MFA challenge credential, multi-org flow, central internal issuer, break-glass runtime authorization (split from durable persistence), audit-vocabulary extension, and complete endpoint/OpenAPI contracts** (§34).
- [x] Test strategy covers every task-listed test category, including all explicitly-mandated minimum tests, **plus REFRESH CAS (renamed/corrected this pass to test the lock-free CAS mechanism), FORCED TOKEN REVOCATION, MFA (extended this pass with the concurrent-claim race test), MULTI-ORG LOGIN, BREAK-GLASS, CENTRAL INTERNAL ISSUER, PASSWORD RESET (new this pass), and FULL CONTRACT categories** (§32).
- [x] Authorization matrix uses only real actors/roles from 5B, covering platform admin, every system role, API key, internal service, and unauthenticated, **plus new rows this pass for break-glass runtime authorization outcomes and the two new restricted-purpose token types** (§31).
- [x] **Twenty-three security invariants stated** (twenty from the prior pass, with #16 revised this pass to describe the CAS mechanism, plus three new this pass covering no-API-layer-locking, MFA atomic-claim exactly-once, and password-reset global revocation), each traceable to a concrete mechanism defined earlier in this document (§30).
- [x] Performance budget follows TARGET/MEASURED/UNKNOWN discipline — no fabricated benchmark numbers; **access-token verification's latency figure and I/O characterization corrected this pass to reflect the mandatory denylist check** (§27).
- [x] Every unresolvable architectural gap recorded as an ADR-6B-xx (**11 total, unchanged by the most recent (fourth) pass** — no new ADR was needed for the password-reset distributed-consistency correction, since it corrects wording/honesty rather than introducing a new architectural decision) or an explicit future dependency (§36.3, **now 8 items — DEP-6B-08 added by the most recent pass** for durable forced-revocation delivery/reconciliation, the one genuine new upstream dependency this specific correction surfaced), not silently resolved.
- [x] Traceability chain (Requirement→Architecture→Domain→Phase 5→API→Permission→Rule→DB→Audit→Status) completed for every `FR-AUTH-*`/`FR-TEN-*` requirement, with an explicit Status column using PASS/DESIGN COMPLETE/IMPLEMENTATION DEPENDENCY/PARTIAL/BLOCKED BY PHASE 5.x, **updated this pass for the 4-item Tier-2 audit count and the fully-specified break-glass runtime authorization** (§35).
- [x] Final consistency audit performed (§38.1, this pass) — no contradictions, duplicate endpoint definitions, inconsistent status/token/claim/role/permission names, tenant-isolation bypasses, conflicting WS/internal-JWT semantics, references to nonexistent Phase 5 objects, stale TBD/review-required/zero-I/O/stateless language outside what this pass corrected, or fabricated performance numbers found.
- [x] **This correction pass's (prior-pass) user decisions remain applied exactly:** break-glass retained (not redesigned, not removed) with durable persistence identified as a future Phase 5.x dependency, not invented and not silently assumed (§18.3, §36.3 item 1) — **this pass adds runtime authorization on top, without altering that prior decision** (§18.3a).
- [x] **This pass's binding user decision applied exactly:** internal service tokens are issued exclusively by a central internal token issuer; no internal deployable holds a private signing key; no Phase 5 `ServiceAccount` table was created (§17.2, ADR-6B-11).
- [x] MFA recovery is explicitly labeled **intentionally deferred** (not "not designed," not silently absent) — current temporary model (platform-admin-assisted, out-of-band) stated as retained interim mechanism, not a placeholder; no recovery-codes table added to Phase 5; future mechanisms listed only as non-selected examples (§15.3, ADR-6B-10, §36.3 item 3) — **unchanged and re-verified this pass, not touched by any of this pass's blockers**.
- [x] Audit extension intentionally deferred — Phase 5's frozen audit architecture (5J) is unmodified; no migration created; no `action_kind` added; the (now 4, grew from 3 this pass for the reason stated in §25) genuinely unmappable events are named individually rather than papered over (§25, §36.3 item 2).
- [x] AUDIT RECORD != LOG != METRIC is enforced throughout — §25/§26 explicitly state that structured logs and Prometheus metrics are supporting telemetry, not a substitute for a durable `audit.audit_events` row.
- [x] `FR-AUTH-004` no longer reads as an unqualified PASS — it is marked PARTIAL with the Tier 1 (durably audited) / Tier 2 (telemetry-only, pending extension, now 4 items) split stated explicitly (§35).
- [x] `FR-TEN-004` reflects the break-glass action-audit-vs-grant-persistence distinction **and now also reflects the fully-specified runtime-authorization check** rather than a single undifferentiated "gap" note (§35).
- [x] Implementation Readiness matrix (§34) rebuilt with the mandated row set **including this pass's nine new/split rows** (refresh-token concurrency, access-token forced revocation, central internal token issuer, break-glass runtime authorization split from break-glass durable persistence, audit-vocabulary extension, MFA challenge credential, multi-org organization-selection flow, complete endpoint/OpenAPI contracts) alongside the prior pass's full row set, using the same Area/Decision/Current Phase 5 support/6B API status/Implementation status/Dependency/Notes columns.
- [x] Future/Upstream Dependencies Register (§36.3) — **now 8 items** (DEP-6B-07 for the central issuer's own infrastructure build-out, and DEP-6B-08, added by the most recent pass, for durable forced-revocation delivery/reconciliation between PostgreSQL and Redis) — with ID/Description/Why needed/Current status/Required phase/Requires Phase 5.x?/Blocks architecture?/Blocks implementation? — no dependency is a hidden requirement for 6B architecture approval (every "Blocks 6B architecture?" cell is explicitly No).
- [x] §4-equivalent status contradiction resolved: Architecture, API Contracts, Security Model, Authorization Model, and Traceability are each independently marked COMPLETE; only Implementation Readiness is marked CONDITIONAL, and only where a named upstream Phase 5.x/infrastructure dependency exists (§38.3).
- [x] No redesign of 6B's architecture performed beyond what this pass's six blockers required; no Phase 6C content introduced; no Phase 5, 5K, or 6A content modified during this correction pass (verified again in §38.4).
- [x] **Every one of this pass's 15 required update targets addressed:** token architecture, threat model, internal-service authentication, failure/resilience, OpenAPI/security-scheme notes, ADRs, implementation-readiness matrix, test strategy, security invariants, §13 refresh lifecycle, endpoint contracts, performance notes, concurrency tests, token lifecycle, authentication middleware, session revocation, platform-admin forced logout, WebSocket auth, caching, credential/token architecture, JWT claims, login/MFA-verify endpoints, error catalog, rate limiting, sequence/ordering description, multi-organization login flow, platform-admin security, break-glass endpoint contracts, tenant-context rules, request middleware, authorization matrix, audit semantics, and the full endpoint contract set — cross-checked section by section during this pass, not asserted in the abstract.

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
- **Break-glass terminology:** consistent everywhere it appears (§9.2, §17.4, §18.3, §18.3a, §21.4, §21.35, §24, §29–§31, §34–§36) — the canonical flow (Platform Admin → target org → justification → strong auth → authorization → time-boxed grant → target tenant context → audited elevated operations → automatic expiry/explicit release) and the action-audit-vs-grant-persistence distinction are stated identically in every section that touches it; the new runtime-authorization contract (§18.3a) is additive to this flow, not a redefinition of it — grant *creation*/*release* semantics are unchanged, only *use* of an already-open grant is newly and fully specified.
- **Audit terminology:** searched for every occurrence of audit/`audit_events`/`SESSION_REVOKED`/`TOKEN_REFRESH_REUSE_DETECTED`/admin-forced-logout/security event/authentication event/authorization event (§18.3, §21.4, §25, §26, §34, §35, §36.3) — no sentence claims "every authentication/authorization decision is durably recorded" without the Tier 1/Tier 2 qualification found in §25; the Tier 2 count is stated consistently as 4 (not 3) everywhere it is cited after this pass (§25, §34, §35, §36.3, §37).

### 38.1a This pass's literal-term consistency sweep (task-mandated, §15 of the correction-pass instructions)

A direct search was run across the full document for every term the correction-pass instructions named, before any status change was finalized:

| Term searched | Finding |
|---|---|
| `zero I/O` / "no DB or Redis round-trip" | Retracted at its one prior location (§12.2) and replaced with the corrected, disclosed Redis dependency; every other appearance of "zero I/O"/"stateless" in the document either states the correction explicitly (§27, §28, ADR-6B-02) or refers to a genuinely still-stateless, unrelated mechanism (e.g., §21.1's login being a stateless read-mostly path, §21.28's API-key-is-DB-checked-not-stateless clarification) — no stale contradiction remains. |
| `stateless` | Same as above — every remaining use is either accurate in its own local context or explicitly flagged as corrected. |
| `revoked_jti` | `auth:revoked_jti:{jti}` is now described consistently as checked on **every** access-token validation (§7, §10, §11.3, §12.2, §12.4, §19.3, §22, §24, §27, §28, §29, §30, ADR-6B-02) — no remaining sentence limits this check to admin-triggered routes only. |
| `mfa_challenge` / `mfa_challenge_token` | Fully defined (§10.1, §11.4) and consistently restricted to `POST /api/v1/auth/mfa/verify` everywhere it is referenced (§7, §9.3, §15.3, §21.1, §21.6, §21.18, §22, §23, §29, §31, §32, §33). |
| `requires_organization_selection` | Retained as a response field name (§21.1, §9.3) but now paired everywhere it appears with the continuation-token/`allowed_organizations` mechanism that actually resolves it (§9.3, §11.5, §21.6) — no longer a dead end. |
| `organization/select` | `POST /api/v1/auth/organization/select` is consistently named and path-identical everywhere it is referenced (§9.3, §20.1, §21.6, §22, §23, §32). |
| `break_glass` / `grant_id` | Consistent throughout, including the new runtime-authorization fields (`admin_user_id`, `session_id`, `organization_id`, `expires_at`, released flag) added to the same Redis record shape everywhere it is described (§18.3, §18.3a, §21.4, §21.35, §24). |
| `internal signing` / "mints its own" | The retired per-deployable model is referenced only in explicitly-labeled "prior draft"/"replaced"/"corrected" language (§10.3, §17.2 opening paragraph, ADR-6B-11) — no remaining sentence describes it as the current design. |
| `API CONTRACT COMPLETE` / `OpenAPI ready` | Both now explicitly scoped to "all 36 endpoints" wherever asserted (§33, §38.3) — not carried forward as a stale claim about a partial subset. |
| `FOR UPDATE` | **This pass removes it as an active design element.** Every remaining occurrence of the string is either (a) inside this same sweep table naming the term to search for, or (b) explanatory prose stating that a *prior* pass used `SELECT ... FOR UPDATE` and that this pass *replaced* it with an atomic conditional `UPDATE ... RETURNING` (CAS) — for refresh rotation (§13.2), platform-admin revoke-all (§21.36), and password-reset global revocation (§13.5) alike. No sentence in the document asserts `SELECT ... FOR UPDATE` as 6B's current design anywhere after this pass. |
| `CAS` / `compare-and-swap` | Now the *only* concurrency mechanism 6B's own API-layer code uses for session-row mutation — refresh rotation (§13.2), password-reset global revocation (§13.5), and platform-admin revoke-all (§21.36) all use the identical `UPDATE ... WHERE <current-state predicate> ... RETURNING ...` shape. No API-layer lock (`SELECT ... FOR UPDATE`, `LOCK TABLE`, advisory lock) exists anywhere in 6B after this pass — verified consistent with frozen 6A §17.3. |
| `refresh` | §13's full lifecycle (format, rotation, reuse detection, concurrency, retry semantics) is internally consistent end-to-end; every description of refresh rotation now uses the atomic conditional `UPDATE` (CAS), not the retired row-lock design. |
| `REVIEW REQUIRED` / `TBD` / `BLOCKED` / `PARTIAL` | Every remaining occurrence is a deliberate, labeled status (§34's `BLOCKED` rows for Phase 8/phone-verification/custom-permissions; §35's `PARTIAL` for `FR-AUTH-004`'s Tier 1/Tier 2 split) — none is a stale, unresolved placeholder contradicting this pass's completed items. |

No stale statement contradicting this pass's final architecture was found outstanding after this sweep.

### 38.1b This pass's (third pass) literal-term consistency sweep — the three new blockers

A second, targeted sweep was run for the specific terms this pass's task named, before finalizing status:

| Term searched | Finding |
|---|---|
| `SELECT FOR UPDATE` / `FOR UPDATE` | Fully retired as 6B's active design — see the updated §38.1a rows above (now reflecting this pass's removal, not the prior pass's introduction). No sentence anywhere in the document asserts an API-layer `SELECT ... FOR UPDATE` as current behavior. |
| `CAS` / `compare-and-swap` | Consistently the sole concurrency mechanism for `identity.sessions` mutation across all three sites that need it (refresh rotation §13.2, password-reset global revocation §13.5, platform-admin revoke-all §21.36) — same `UPDATE ... WHERE <predicate> ... RETURNING` shape at every site. |
| `refresh_token_hash` | Used consistently as the CAS predicate/write target in §13.1/§13.2/§13.5/§21.2/§21.11 — no remaining reference to it being read under a row lock. |
| `REFRESH_TOKEN_REUSE_DETECTED` | Consistently triggered by the atomic `UPDATE`'s zero-rows-affected path followed by an unlocked distinguishing read (§13.2, §13.3, §21.2, §22, §29, §31) — no remaining reference to detection "inside a locked transaction." |
| `consumed_mfa_challenge` | Consistently described as an atomic `SET ... NX EX` claim, not a check-then-write pair, everywhere it appears (§11.4, §15.3, §21.18, §24, §28, §29, §32, §34, §38.1a). |
| `SET NX` | Used consistently for exactly one mechanism — the MFA-challenge-consumption claim (§11.4, §15.3, §21.18) — with the required ordering (validate JWT → validate exp/aud/token_use → validate TOTP → atomic claim → session creation only on success) stated identically wherever the flow is described. |
| `MFA_CHALLENGE_CONSUMED` | Consistently the error returned when the atomic claim already exists (this request lost the race, or is a later replay) — never described as resulting from a separate, pre-claim "check" step (§11.4, §15.3, §21.18, §22, §29, §32). |
| `password/reset/confirm` | `POST /api/v1/auth/password/reset/confirm`'s contract (§21.11) consistently describes global access-token denylisting alongside session revocation everywhere it is cross-referenced (§13.4, §13.5, §22, §28, §29, §30, §32, §34) — no remaining sentence describes password reset as leaving old access tokens valid for their natural lifetime. |
| `revoked_jti` | Now written by three call sites — platform-admin forced revoke-all (§21.36), password-reset global revocation (§13.5, §21.11), and (unchanged from the second pass) any future admin-triggered revocation action — and read on every access-token validation (§12.2, §12.4) — stated consistently everywhere. |
| `TOKEN_REVOKED` | Unchanged in meaning from the second pass — the response code for a denylisted `jti` found at validation time (§22) — now additionally reachable via the password-reset write path, consistent with every other reference. |
| `zero I/O` / `stateless` | No new occurrences introduced by this pass's three fixes; the second pass's corrections (§12.2, §27, §28) remain accurate and are not contradicted by the CAS/atomic-claim mechanisms this pass adds (an atomic `UPDATE`/`SET NX` is not "stateless," and no sentence claims it is). |
| `APPROVED` / `FROZEN` | Confirmed to appear only in §38.3's status block and its own explanatory prose — no other section pre-empts or contradicts the status this pass concludes with. |
| `REVIEW REQUIRED` / `BLOCKED` / `PARTIAL` | Re-confirmed unchanged from the §38.1a sweep — no new stale occurrence introduced by this pass's edits. |

No stale statement contradicting this pass's three corrections was found outstanding after this sweep.

### 38.1c 6A compliance re-check (task-mandated, §5 of the correction-pass instructions)

| 6A rule | Re-checked against | Result |
|---|---|---|
| No API-layer locking beyond Phase-5-sanctioned mechanisms (6A §17.3) | Refresh rotation (§13.2), password-reset global revocation (§13.5), platform-admin revoke-all (§21.36) | **Compliant.** All three now use atomic conditional `UPDATE ... RETURNING` (CAS) statements exclusively — no `SELECT ... FOR UPDATE`, `LOCK TABLE`, or advisory lock appears anywhere in 6B's own API-layer design. The MFA-challenge claim uses Redis `SET ... NX`, which is the exact mechanism 6A §17.3 itself names as an approved precedent (5E ADR-5E-012). |
| Idempotency-Key / status-code rules (6A §7.4, §16) | `IDEMPOTENCY_KEY_REUSE_MISMATCH` = `409` (§22, fixed in the prior pass); refresh and MFA-verify remain explicitly non-`Idempotency-Key`-bearing, unchanged by this pass | **Compliant.** No change made this pass to any 6A-defined status code. |
| Error envelope (6A §24) | Every error introduced or touched this pass (`MFA_CHALLENGE_CONSUMED`, `REFRESH_TOKEN_REUSE_DETECTED`, `TOKEN_REVOKED`, `DEPENDENCY_UNAVAILABLE`) uses the unchanged `{error: {code, message, details, request_id, retryable}}` shape (§22) | **Compliant.** No new error envelope or shape introduced. |
| Latency tiers (6A §12/§27) | Refresh remains Fast tier (§27); MFA verify remains Fast tier; password-reset-confirm remains Standard tier — none of this pass's fixes added an I/O round trip beyond what was already budgeted (the atomic `UPDATE`/`SET NX` replace, not add to, the operations already accounted for) | **Compliant.** No latency tier reclassified. |
| API versioning (6A §6) | No endpoint path, version prefix, or versioning rule touched by this pass | **Compliant.** Unaffected. |
| Tenant-resolution rules (6A §23, 6B §9) | Password-reset and MFA fixes operate on `identity.users`/`identity.sessions`, which are not tenant-scoped (§14); refresh rotation does not touch `organization_id` resolution | **Compliant.** No tenant-resolution rule touched. |
| No new Phase 5 schema assumptions | Refresh CAS, MFA atomic claim, and password-reset global revocation all operate on columns/tables already in the frozen 5B schema (`identity.sessions.refresh_token_hash`/`access_token_jti`/`status`, `identity.users.password_hash`) plus Redis-only state (`auth:revoked_jti:{jti}`, `auth:consumed_mfa_challenge:{jti}`) — no column, table, or `action_kind` was added | **Compliant.** |
| No hidden override of 6A | Every correction in this pass is justified by an explicit citation to the specific frozen-6A section it brings 6B into line with (§17.3 for locking; no other 6A rule was found in conflict) — none is a silent, unstated deviation | **Compliant.** |

**No conflict with frozen 6A remains identified.**

### 38.2 Remaining genuine dependencies (not blockers to freezing this document's design — recorded as forward dependencies, full detail in §36.3)

1. **Durable break-glass grant-lifecycle persistence** (DEP-6B-01, §18.3/§18.3a/§21.4/§36.3) — the API contract, the now-fully-specified runtime authorization model, and grant/release action-audit are complete and implementable today; only the durable *lifecycle-state* table is a future Phase 5.x item.
2. **Authentication audit-vocabulary extension** (DEP-6B-02, §25/§36.3) — `SESSION_REVOKED`, `TOKEN_REFRESH_REUSE_DETECTED`, admin-forced-logout, and (new this pass) forced-revocation-denylist-write have no matching 5J `action_kind`; the audit *requirement* is fully specified, its durable persistence for these 4 kinds is a future Phase 5.x item.
3. **Robust, self-service MFA recovery** (DEP-6B-03, §15.3/§36.3) — intentionally deferred; current interim platform-admin-assisted mechanism is implementable today; a self-service mechanism is a future security requirement, not chosen here. Unaffected by this pass's blockers.
4. **OAuth2/OIDC provider-specific implementation** (DEP-6B-04, §15.2/§36.3) — Phase 8 scope, per 3E's own explicit deferral, not a 6B gap.
5. **Phone verification mechanism/provider** (DEP-6B-05, §15.5/§36.3) — undefined anywhere upstream of this document; not designed here.
6. **CAPTCHA/adaptive-challenge step-up** (DEP-6B-06, §23/§36.3) — deferred by design; rate limiting is a sufficient, fully-implementable interim control.
7. **Central internal token issuer build-out** (DEP-6B-07, §17.2/§36.3) — the issuer's contract is fully specified; the issuer itself is an infrastructure/deployment build-out, not a Phase 5.x item, and does not block this document's own design completeness.
8. **Durable forced-revocation delivery/reconciliation** (DEP-6B-08, §13.5/§21.11/§36.3, new — added by this correction) — password-reset's global access-token denylisting is a best-effort step performed in Redis after the durable database transaction commits; crash-safe, guaranteed delivery of every denylist entry (surviving a Redis failure between the DB commit and the Redis write) requires a future durable-tracking mechanism this document's authority does not extend to designing. The best-effort mechanism itself, and its honest Case A/B/C behavior, are fully specified today (§13.5) — only the crash-safe upgrade is deferred.

None of these eight items block this document's own architectural, contractual, or security-model completeness — each is a forward-looking dependency on a *future* phase, a *future* Phase 5.x extension, or infrastructure build-out, individually named with an explicit "blocks implementation? / blocks architecture?" answer in §36.3, rather than silently assumed away or vaguely gestured at.

### 38.3 Status

**This correction (fourth pass) fixed exactly one issue: password-reset-confirm's false claim of cross-system atomicity between PostgreSQL and Redis.** No other blocker from any prior pass was reopened.

| # | Issue (this pass) | Resolved? | Where |
|---|---|---|---|
| 1 | Password-reset-confirm implied PostgreSQL commit and Redis denylist population are one atomic/all-or-nothing operation, and implied a consumed reset token could always resume unfinished denylist work | ✅ Yes — §13.5 rewritten to separate (A) the durable database transaction (password change + session revocation, unconditional once committed) from (B) a best-effort, subsequent Redis denylisting step with no resumability claim | §13.5, §21.11 |

No residual wording claiming cross-system atomicity, guaranteed retry-resume, or "no crash window" was found anywhere in the document after this correction (§38.1d sweep, below). The security objective itself (durable session revocation + best-effort immediate access-token denylisting) is unchanged and remains fully specified — only the previously-overclaimed reliability of the Redis half was corrected.

### 38.1d Fourth-pass literal-term consistency sweep (this correction's own scope)

| Term/phrase searched | Finding |
|---|---|
| "atomically across DB and Redis" / "atomic ... with the password change" | No longer appears — §13.5/§21.11 now explicitly separate step A (database transaction, atomic within PostgreSQL only) from step B (Redis, a distinct, subsequent, best-effort step). |
| "guaranteed all-or-nothing across PostgreSQL and Redis" | No sentence in the document makes this claim; §13.5 explicitly states the opposite. |
| "the reset can always resume from the consumed token" / resumable retry | Explicitly disclaimed — §13.5 and §21.11 both state that a retry with an already-consumed token does not resume unfinished Redis work, and that no durable resume-marker exists or is invented. |
| "no crash window exists" | Not present; §13.5's Case C is the explicit statement that a crash/failure window between step A and step B does exist and is disclosed, not hidden. |
| `password_reset_revocation_pending` / `revocation_delivery_status` / `security_reset_status` / `revocation_outbox` | None of these fields was added — confirmed absent from every section touched this pass (§13.5, §21.11, §36.3's DEP-6B-08 description explicitly lists these as examples of what was *not* added). |
| "Redis is ... disposable" / blanket performance-cache framing | Corrected in §24 — `auth:revoked_jti:{jti}` and `auth:consumed_mfa_challenge:{jti}` are now described as security-critical runtime enforcement state, distinct from the (still-accurate) statement that Redis is never the durable audit/business system of record. |
| `sessions_revoked` / `access_tokens_denylisted` response fields (prior wording) | Replaced with the three explicit boolean completion flags (`password_reset_completed`, `session_revocation_completed`, `access_token_revocation_completed`) everywhere the response shape is shown (§21.11) — no stale reference to the old field names remains. |

No stale statement contradicting this pass's correction was found outstanding after this sweep.

**Full blocker history (context only — all prior-pass blockers remain resolved and were not reopened by this correction):**

| # | Blocker (established in an earlier pass) | Status |
|---|---|---|
| 1 | Central internal token issuer (binding user decision) | ✅ Resolved, unaffected by this correction — §10.3, §17.2, ADR-6B-11 |
| 2 | Forced access-token revocation, global not admin-route-only | ✅ Resolved, unaffected — §7, §12.2, §12.4, §19.3 |
| 3 | MFA challenge token undefined / consumption atomicity | ✅ Resolved, unaffected — §10.1, §11.4, §15.3, §21.18 |
| 4 | Multi-organization login flow undefined | ✅ Resolved, unaffected — §9.3, §11.5, §21.6 |
| 5 | Break-glass runtime authorization incomplete | ✅ Resolved, unaffected — §18.3a |
| 6 | Refresh-token concurrency race / 6A-compliant CAS | ✅ Resolved, unaffected — §13.2, §13.2a, §21.2 |
| 7 | Password reset must globally revoke known current access tokens | ✅ Resolved in an earlier pass; **this pass corrects the mechanism's honesty (no false atomicity claim), not the underlying security objective** — §13.5, §21.11, DEP-6B-08 |

Per this document's final-approval rule: approval is **not** granted merely because edits are complete — it is granted here because the specific false claim was located and removed everywhere it appeared (§38.1d), the security objective was re-verified as still fully and honestly specified (§13.5's Case A/B/C table), and the one genuine new dependency this correction surfaced (DEP-6B-08) was recorded rather than papered over.

```
PHASE 6B ARCHITECTURE:                       COMPLETE
PHASE 6B API CONTRACT:                       COMPLETE   (36/36 endpoints fully expanded, §20–§21; endpoint count unchanged by this correction)
PHASE 6B SECURITY / AUTHORIZATION DESIGN:    COMPLETE   (all 7 established blockers remain resolved; the password-reset distributed-consistency issue is corrected — no false atomicity claim remains, residual risk honestly documented)
PHASE 6B IMPLEMENTATION READINESS:           CONDITIONAL — UPSTREAM DEPENDENCIES REMAIN
                                              (DEP-6B-01 break-glass grant persistence,
                                               DEP-6B-02 audit vocabulary extension (4 items),
                                               DEP-6B-07 central internal token issuer build-out,
                                               DEP-6B-08 durable forced-revocation delivery/reconciliation (new) —
                                               see §36.3 for the full 8-item register;
                                               none of the eight blocks architecture/contract/security-design completeness;
                                               DEP-6B-08 specifically blocks claiming crash-safe immediate
                                               access-token revocation on password reset, and affects full
                                               implementation readiness of that one recovery flow, per this
                                               correction's own instruction)

PHASE 6B: APPROVED / FROZEN
    ARCHITECTURE, API CONTRACT, AND SECURITY/AUTHORIZATION DESIGN — ALL THREE INTERNALLY COMPLETE
    AND CONSISTENT AS OF THIS FOURTH, TARGETED CORRECTION, WITH NO REMAINING FALSE CROSS-SYSTEM-
    ATOMICITY CLAIM AND NO CONFLICT AGAINST FROZEN 6A. IMPLEMENTATION READINESS REMAINS CONDITIONAL
    ON THE NAMED FORWARD DEPENDENCIES ABOVE, NONE OF WHICH REQUIRED REDESIGNING ANY OTHER PART OF 6B.
```

"APPROVED/FROZEN" means the 6B **design** (architecture, API contracts, security and authorization model, traceability) is frozen and will not be redesigned absent a new explicit decision — it does **not** mean every upstream dependency named in §36.3 is already implemented, and it does **not** mean password-reset's immediate access-token revocation is crash-safe today (it is honestly disclosed as best-effort, pending DEP-6B-08).

**Explicitly confirmed for this correction:**
- No Phase 5 content was modified. No migration was created. No new Phase 5 table, column, or `action_kind` was added — specifically, no `password_reset_revocation_pending`/`revocation_delivery_status`/`security_reset_status`/`revocation_outbox`-equivalent field was added, as required.
- No Phase 5K content was modified.
- No 6A content was modified.
- No Phase 6C work was started or designed.
- No FastAPI code, backend source files, or database table redesigns were produced.
- Refresh-token CAS (§13.2), MFA challenge atomicity (§11.4/§15.3/§21.18), the central internal token issuer (§17.2), break-glass (§18.3/§18.3a), RBAC (§8/§16), and tenant isolation (§9) were **not** changed by this correction — verified by this pass touching only §13.4/§13.5, §21.11, §24, §28, §29, §30, §32, §34, §36.3, §37, §38.
- The endpoint inventory remains 36 endpoints — no endpoint was added, removed, or renumbered by this correction.
- The only new dependency this correction surfaced is DEP-6B-08, recorded exactly as required: does not block architecture/API-contract/security-design completeness; does block claiming crash-safe immediate access-token revocation; does affect full implementation readiness of the password-reset security-recovery flow specifically.

This document fully specifies the Authentication and Authorization API within the boundaries of Phase 1–5 and 6A's frozen architecture, resolves every discrepancy it found between DDD-layer and DB-layer sources explicitly (ADR-6B-08), closes 6A's named open item R-8 with a documented decision (ADR-6B-03), closes this pass's three mandatory blockers with concrete, verified corrections consistent with frozen 6A (table above), and records every genuine gap it could not close on its own authority as an explicit, individually-tracked forward dependency (§36.3, §38.2) rather than a fabricated resolution or a silently dropped caveat.
