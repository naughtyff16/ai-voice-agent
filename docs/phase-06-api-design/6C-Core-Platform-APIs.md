# 6C — Core Platform APIs

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6C

---

## 1. Document Control

| Field | Value |
|---|---|
| Document ID | 6C |
| Title | Core Platform APIs |
| Phase | 6 — API Design |
| Depends on (frozen, upstream) | Phase 1 SRS, Phase 2 HLA, Phase 3 LLD (3A, 3E), Phase 4 DDD (4A, 4G, 4H, 4I), Phase 5 DB Design (5A, 5B, 5J), Phase 5K Migration & Validation, **6A — API Architecture and Standards**, **6B — Authentication and Authorization API** |
| Status | See §31 — Final Status (multi-dimension model, consistent with 6B's precedent). **APPROVED/FROZEN as of Revision 7** — the six dependencies that previously blocked conditions 5 and 6 of §31.1 (DEP-6C-07/10/11/14/15/16) were resolved by a controlled Phase 5.x dependency-closure package (migration `077_5J1`, a governance amendment to 5J §14.3), and DEP-6C-16's live-database execution/concurrency/security gap — the one condition Revision 6 had left as a disclosed, non-blocking residual — is now closed with actual live PostgreSQL execution evidence (Revision 7); see the Revision 7 row below and §31/§31.2 for the full, condition-by-condition re-evaluation. |
| Author | karthi (karthimadan2003@gmail.com) |
| Date | 2026-08-22 |
| Revision 1 | Targeted Correction Pass — 2026-08-23. Resolved the pre-acceptance-membership security blocker (pending invitations now use `status='SUSPENDED'`, not `'ACTIVE'`, closing unauthorized-access risk without any 6B/5B change, §9.6); corrected the invitation-token↔membership linkage claim (accept is safe; resend's invalidation guarantee is not implementable with the frozen schema and is now honestly marked blocked, §9.2/§9.4, DEP-6C-12); corrected the organization-creation transaction to respect frozen `FORCE ROW LEVEL SECURITY`/`WITH CHECK` policies (§7.7, no RLS bypass); corrected the team-membership-uniqueness claim (a DB-level partial unique index already exists, §10.2); corrected membership role-assignment authorization to the catalog's actual intended permission (`role:manage`, per 5B §37.6, §8.4). Final status revised from APPROVED/FROZEN to REVIEW REQUIRED. No Phase 5/6A/6B modification; no 6D work. |
| Revision 2 | Targeted Final Correction Pass — 2026-08-23 (same day, second pass). Fixed a stale invitation-list predicate the first pass missed (§9.4, §15.17, §8.1a's new canonical state table); redesigned invitation creation as idempotent-by-`(org, user, role)` to close a partial-failure stranding gap (ADR-6C-08, §9.3.2, Blocker 2); retracted a false deterministic-concurrency claim for invitation creation and replaced it with the actual, `uq_memberships_active`-contained guarantee (§9.3.2 point 5, §25, DEP-6C-13, Blocker 3); re-audited every state-changing endpoint against 6A §22's binding (not discretionary) rule, reclassifying three previously-mislabeled "deliberate non-gap" mutations as genuine dependencies and correctly auditing compliance-policy draft creation (§19, DEP-6C-14/15, Blocker 4); retracted an unauthorized extension of 6A §35's transaction-boundary exception list (`CompliancePolicy` is a separate aggregate and was wrongly included in the atomic Organization+Membership transaction) and redesigned both organization creation and compliance-policy activation as two-transaction, honestly-reported flows with documented recovery paths (§7.7, §12.2, Blocker 5); reconciled a real conflict between 4A's 7-day and 5B's generic 1-hour invitation-expiry values (§9.2a, ADR-6C-07); reconciled `400`-vs-`422` usage against 6A §7.4's exact definitions (§18, Cleanup 1); corrected the dependency-register count (11 → 15, Cleanup 2); rebuilt §31's final-status determination as an explicit 8-condition evaluation rather than a single named blocker (Cleanup 3). Final status remains REVIEW REQUIRED, now naming all five audit-gap dependencies as the exact blockers (DEP-6C-07/10/11/14/15), not a single "sole reason." No Phase 5/6A/6B modification; no 6D work; no unrelated 6C area redesigned. |
| Revision 3 | Final Targeted Correction Pass — 2026-08-23 (same day, third pass). **Blocker 1:** the second pass's fix for organization-creation `CompliancePolicy` seeding (a second, synchronous transaction in the same request handler) was itself insufficient against 6A §35's actual rule ("synchronous response must never wait for downstream effects") — corrected to a genuinely event-driven design using the platform's existing, frozen transactional-outbox + Redis Streams event bus (3A §6.3): TXN1 (Organization + owner Membership + outbox write) commits and `201` is returned immediately; `CompliancePolicy` seeding happens later, in a separate asynchronous consumer transaction; the retracted `compliance_policy_seeded` response field is removed entirely (§7.7, §15.1). **Blocker 2:** the same correction applied to compliance-policy activation's `organizations.compliance_policy_id` convenience-pointer update — now consumed from the already-existing `compliance.policy_activated` event rather than a synchronous second transaction (§12.2). **Consistency Fix 1:** §9.7's summary corrected to name DEP-6C-12 and DEP-6C-13 as two independently-tracked open items, neither "the one" remaining invitation item. **Consistency Fix 2:** §22's stale "3 inserts in one transaction" performance claim corrected to reflect the single-transaction, two-insert-plus-outbox reality, with async `CompliancePolicy` seeding correctly excluded from synchronous latency. **Consistency Fix 3:** §15.1's stale "`SET LOCAL` at the start of TXN1" wording corrected — tenant context can only be set after the `organizations` INSERT returns an id. **Consistency Fix 4:** "Tier 1"/"Tier 2" audit terminology normalized to Category A/B/C throughout §19, §23, §26, §30, avoiding confusion with 6A's unrelated latency-tier vocabulary; the `x-audit-status` OpenAPI extension value changed from `"telemetry-only"` to `"implementation-dependency"` so it cannot read as compliant behavior. **Consistency Fix 5:** §30's threat-model checklist item corrected — §9.6 is resolved, not an open finding; DEP-6C-12/13 both named explicitly. **Consistency Fix 6:** DEP-6C-12's "Affects" dimension corrected to remove "auditability" (no audit requirement depends on it) and instead name revocation/invalidation-strength and token-lifecycle integrity. Added an explicit note (§19) that Phase 5K's `action_kind` column being unconstrained `TEXT` does not itself authorize inventing new vocabulary — 5J's documented list remains the sole governance boundary. No dependency added or removed this pass (the event-bus mechanism used was already upstream-frozen, not invented). Final status remains REVIEW REQUIRED, same five blocking dependencies, condition 6 now verified as genuinely satisfied (not merely "moved to a second transaction"). No Phase 5/6A/6B modification; no 6D work; no unrelated 6C area redesigned. |
| Revision 4 | Final Targeted Correction Pass — 2026-08-23 (same day, fourth pass). **Revision 3's "no dependency added" and "condition 6 genuinely satisfied" claims are corrected — not reverted architecturally, but corrected for an unverified assumption.** An independent review found, and this pass confirmed by direct search of every Phase 5 document and the entire 5K migrations/manifest directory, that **no concrete Postgres transactional-outbox relation exists anywhere in the frozen schema.** Redis Streams (event bus) and the transactional-outbox pattern remain correctly approved, frozen architecture (Phase 2, 3A §6.3, 4A §5.1) — Revision 3's event-driven design (request transaction contains only `Organization`+`Membership`; `CompliancePolicy`/pointer updates are consumer-only) is **retained exactly as designed, not reverted to synchronous cross-aggregate transactions.** What is corrected: the fabricated `INSERT INTO <platform outbox table>` line is removed and replaced with an explicit, commented-out placeholder plus prose stating this step is IMPLEMENTATION DEPENDENCY; **DEP-6C-16 is added** (§27) to name the missing durable-persistence backing precisely; §7.7 and §12.2 now clearly separate the REQUEST TRANSACTION (synchronous, fully implementable today) from the ASYNC CONSUMER TRANSACTION (architecturally correct, blocked end-to-end pending DEP-6C-16); §31's condition 6 is split into "architectural design SATISFIED" and "implementation NOT YET SATISFIED." Also this pass: normalized inconsistent "zero or two" vs. "zero/one/two" pending-row wording under invitation-creation concurrency to one consistent statement (§9.3.2, §25); retracted an overstated compliance-pointer-staleness bound ("cannot drift more than one activation behind") and replaced it with the honest rule that the pointer is non-authoritative and may remain arbitrarily stale while its consumer is unhealthy (§12.2, §25). Dependency register grows from 15 to 16 total records (15 open + 1 resolved). Final status remains REVIEW REQUIRED; blocking dependencies now DEP-6C-07/10/11/14/15/16 (DEP-6C-12/13 remain disclosed, non-blocking residuals, risk classification unchanged). No Phase 5/6A/6B modification; no 6D work; no unrelated 6C area redesigned. |
| Revision 5 | Minimal Final Consistency Cleanup — 2026-08-23 (same day, fifth pass). Two remaining inconsistencies fixed, no architecture change. **(1) §22 stale outbox count:** a Revision-3 sentence still counted a durable outbox `INSERT` as part of `POST /organizations`'s *current* synchronous work, contradicting Revision 4's own finding that no such relation exists (DEP-6C-16). Corrected to distinguish the **current implementable path** (two inserts: `organizations`, `memberships` — no outbox insert, since DEP-6C-16 is unresolved) from the **target path** once DEP-6C-16 lands (the same two inserts plus a third, durable outbox insert, still within one 6A-§35-authorized transaction). **(2) Compliance-policy cache invalidation incorrectly tied to event delivery:** §20's Domain Events table and §21's Caching table both stated the `compliance.policy_activated` *event* triggers the `compliance_policy:{org_id}` cache invalidation — this would have made cache correctness depend on DEP-6C-16, which is unresolved. Corrected throughout §12.2, §20, §21, and §25's test strategy: cache invalidation is a **synchronous** step inside the activation endpoint's own request handler (commit the authoritative `compliance_policies` status transition → synchronously `DEL compliance_policy:{org_id}` → return `200`), entirely independent of event delivery or DEP-6C-16; the event remains responsible only for the separate, non-authoritative `organizations.compliance_policy_id` pointer update, which does remain blocked/eventual under DEP-6C-16. New test assertions added (§25) proving cache invalidation succeeds even with the event consumer entirely absent, while the pointer correctly remains stale in that same scenario. Final status unchanged: REVIEW REQUIRED, same six blocking dependencies (DEP-6C-07/10/11/14/15/16). No Phase 5/6A/6B modification; no 6D work; no architecture redesigned; dependency register unchanged except for cross-references. |
| Revision 6 | **Phase 5.x Dependency-Closure Package — 2026-08-23 (same day, sixth pass). Controlled amendment to Phase 5, authorized explicitly for this pass only (every prior pass was Phase-5-frozen).** Resolves all six blocking dependencies via two Phase 5.x artifacts, neither a 6C-authored redesign: **(A) Audit vocabulary (DEP-6C-07/10/11/14/15) — governance-only, no SQL.** `audit.audit_events.action_kind` is `TEXT` with only a length `CHECK` (`chk_ae_action_kind`, migration `072_5J.sql`), not an enum or lookup table — verified directly, not assumed, before concluding no migration was needed. Ten new canonical values were added to `5J-Analytics-Audit-Schema.md` §14.3's governed vocabulary list, named to match the existing style exactly (verb-past-tense, mirroring sibling values already in each category — e.g. `MEMBER_REACTIVATED` mirrors `ORGANIZATION_REACTIVATED`; `DATA_SUBJECT_REQUEST_VERIFYING`/`_ON_HOLD` match `data_subject_requests.status`'s own value spelling exactly): `ORGANIZATION_CANCELLED`, `MEMBER_REACTIVATED`, `TEAM_CREATED`, `TEAM_UPDATED`, `TEAM_ARCHIVED`, `TEAM_MEMBER_ADDED`, `TEAM_MEMBER_REMOVED`, `DATA_SUBJECT_REQUEST_VERIFYING`, `DATA_SUBJECT_REQUEST_ON_HOLD`, `USER_PROFILE_UPDATED`. **(B) Transactional outbox (DEP-6C-16) — new migration `077_5J1.sql`** (Alembic revision `077_5J1`, `down_revision=076_5K1`), adding `audit.domain_event_outbox` (16 typed columns, 8 `CHECK` constraints, 4 partial/covering indexes, no RLS by design — same documented no-RLS precedent as `identity.sessions`/`identity.password_reset_tokens`, 5B §16.3, with tenant-forgery on `INSERT` instead guarded by a structural `BEFORE INSERT` trigger) plus three `SECURITY DEFINER` functions (`fn_claim_outbox_events` — `SELECT ... FOR UPDATE SKIP LOCKED`, worker-internal only, mirroring `webhooks.fn_claim_delivery`; `fn_mark_outbox_published`; `fn_mark_outbox_failed` — retry-with-backoff plus terminal `FAILED` on exhaustion). At-least-once delivery only, by design (never exactly-once) — consumers remain required to be idempotent, unchanged from every prior pass's own stated discipline. §7.7's and §12.2's commented-out placeholder `INSERT`s are replaced with real, executable SQL against this table; the two unblocked flows (`organization.created` → `CompliancePolicy` seeding, `compliance.policy_activated` → pointer update) are **not** redesigned — same event names, same payload shapes, same consumer-only write pattern as every prior pass. Compliance-policy cache invalidation **remains synchronous** (§12.2, §21, unchanged by this pass, per the explicit constraint carried forward from Revision 5). Sections updated: §1, §7.7, §12.2, §15.1/§15.7/§15.12/§15.20–§15.27/§15.34/§15.35/§15.39, §19, §20, §22, §25, §26, §27, §29, §30, §31. **No endpoint contract redesigned** — every change either replaces a placeholder/gap disclosure with a resolved-dependency statement, or corrects an audit/event field that referenced the now-resolved gap; no request/response shape, status code, or permission mapping changed. **Validation:** `5K/validation/077_5J1_VALIDATION_REPORT.md` — 13/13 static/structural checks PASS; live execution against a running PostgreSQL instance was **not** performed in this session (no functional `psql`/Python/Alembic runtime available) and is disclosed as a residual, non-blocking operational step, not concealed (§27, §29, §31.2). Final status changes from REVIEW REQUIRED to **APPROVED/FROZEN** — see §31/§31.2 for the full re-evaluation against both the original 8-condition gate and the governing task's own 13-point closure-package gate. No 6A modification. No 6B modification. No 6D work. Phase 5 modification is limited exactly to the controlled amendment described above (5J §14.3 vocabulary list, one new migration in the already-established 5K package) — no other Phase 5 document, table, column, or function touched. |
| Revision 7 | **Live-Validation Closure Pass — 2026-08-23 (same day, seventh pass). No redesign; closes exactly the one residual Revision 6 itself disclosed as non-blocking-but-open: DEP-6C-16's live-database execution/concurrency/security gap.** Revision 6 marked `PHASE 6C — APPROVED/FROZEN` on the strength of `077_5J1_VALIDATION_REPORT.md`'s 13/13 **static/structural** checks alone, with live PostgreSQL execution explicitly named as not performed. This pass supplies that live evidence: a genuinely fresh database (local PostgreSQL 18; the prior Docker-based 5K/5K.1 workflow was unavailable, no Docker engine in this environment) was walked through the full `001_5B→077_5J1` chain (single head, exit code 0); `audit.domain_event_outbox`'s live column/constraint/index inventory was verified exactly (correcting two static-report miscounts along the way — 17 columns not 16, 7 `CHECK` constraints + 1 `PRIMARY KEY` not "8 `CHECK`"); all four `SECURITY DEFINER` functions were confirmed to have explicit, safe `search_path`s with no regression; `app_api`/`app_worker`/`app_readonly` grant boundaries were exercised live via `SET ROLE` (no `BYPASSRLS` workaround); the atomic domain+outbox invariant was proven with real `COMMIT`/`ROLLBACK` transactions, not reasoned about; both DEP-6C-16 event flows (`organization.created`, `compliance.policy_activated`) were inserted and claimed live; a **genuine two-connection concurrency race** against `fn_claim_outbox_events` (overlapping, not sequential, transactions) confirmed 0 double-claims across 20 rows; wrong-worker publish rejection, retry/failure, max-attempts→terminal `FAILED`, and stale-claim recovery (with a fresh-claim negative control) were all live-tested; a full security/Alembic regression pass confirmed no regression from 077. **No defect was found — `077_5J1.sql`/`077_5J1.py` are unmodified; SHA-256 unchanged, reconfirmed against `MIGRATION_MANIFEST.md`.** Full raw evidence: `5K/execution_logs/README.md`'s "Fifth batch" section (files `51`-`62`, prefix `20260823T061055Z`); `5K/validation/077_5J1_VALIDATION_REPORT.md` (rewritten in place, static version preserved in its own revision history); `5K/EXECUTION_REPORT.md` §13. §31.1 condition 6 and §31.2 conditions 3/7 (and the summary line) are updated to state LIVE VERIFIED instead of "disclosed residual"; DEP-6C-16 changes from RESOLVED (design/schema level) to **RESOLVED — LIVE VERIFIED**; DEP-6C-07/10/11/14/15 remain RESOLVED (governance-only, unaffected — no SQL was ever needed for them, confirmed again this pass). DEP-6C-12/13 are unchanged — not touched by this pass, remain exactly the disclosed, non-blocking residual classification Revision 2/3 gave them. Final status: **PHASE 6C — APPROVED/FROZEN**, now genuinely earned against the governing task's stricter live-validation gate rather than asserted on static evidence alone. No Phase 5/6A/6B modification beyond the validation-report/manifest/execution-report documentation updates named above (no new SQL, no schema redesign). No 6D work. No endpoint contract, request/response shape, status code, or permission mapping changed. |
| Hard boundary | This document designs **only** the Core Platform APIs: Organizations, Memberships/Invitations, Teams, Organization Compliance Configuration, Data Subject Requests, and User Profile. It does not modify Phase 5 (frozen), 6A (frozen), or 6B (frozen). It does not begin 6D or any business-domain API (Voice, AI Agent, Knowledge/RAG, CRM, Campaigns, Workflow, Integrations, Billing, Analytics, Admin). |

---

## 2. Purpose

6C defines the APIs for the platform's **core platform** bounded contexts — the cross-cutting, tenant-facing resources every dashboard and every later business-domain API depends on: organization identity/profile/lifecycle, membership and invitation lifecycle, teams, organization-level compliance/localization configuration, data-subject-request processing, and the authenticated user's own editable profile. It consumes 6A's constitution and 6B's authentication/authorization/RBAC surface without reopening either.

---

## 3. Scope

### 3.1 In scope
Organization CRUD and lifecycle (create, read, update, suspend, cancel); organization membership listing and lifecycle (role assignment, suspend, reactivate, remove, self-leave, ownership transfer); invitation creation/listing/resend/cancel (the organization-management half of the flow whose acceptance half is owned by 6B); teams and team membership; organization compliance-policy configuration (versioned) and data-subject-request processing (both frozen `organization` schema aggregates per 4I); the authenticated user's own editable profile and organization list.

### 3.2 Explicitly out of scope
- Everything 6B already owns: authentication, tokens/sessions, API keys, RBAC role/permission catalog management, invitation *acceptance*, platform-admin/break-glass, WebSocket/internal-service auth. 6C does not redesign or restate these — it consumes them as fixed dependencies.
- All later business-domain APIs: Voice, Calls, AI Agents, Knowledge/RAG, CRM/Leads, Campaigns, Workflow, Integrations/Webhooks/Plugins, Billing/Usage/Quotas, Analytics, Audit-log browsing, and any Admin Control Plane beyond what 6B already owns.
- Any change to Phase 5, 6A, or 6B.

---

## 4. Governing Documents

| Document | Role for this document |
|---|---|
| Phase 1 SRS | `FR-TEN-001..005` (multi-tenancy/org management), `NFR-PERF-001/002`, `NFR-SEC-003/004` — §33 traceability |
| Phase 4A Core Domains (DDD) | `Organization` aggregate (with embedded `Teams`), `Membership` aggregate, invariants, commands, events — the primary domain grounding for §7–§11 |
| Phase 4I India-First Decision Closure | `CompliancePolicy` and `DataSubjectRequest` as Organization-context aggregates, explicitly mapped to "Core API" ownership (§4I row 2) — the primary grounding for §12–§13 |
| Phase 4G Analytics/Cross-Domain Context Map | Cross-aggregate consistency/eventual-consistency lag targets (reused from 6A §35, not restated) |
| Phase 5B Identity/Organization/Multitenancy/Security | **Authoritative, frozen DB schema** for `organization.*` (organizations, memberships, teams, team_memberships, roles, permissions, compliance_policies, data_subject_requests) and the referenced `identity.*` tables — the primary grounding source for every endpoint's DB interaction (§7–§14) |
| Phase 5J Analytics/Audit Schema | Frozen `action_kind` vocabulary (§14.3) and `fn_insert_audit_event()` write path — grounding for §19 |
| **6A — API Architecture and Standards** | **Binding constitution.** Supplies envelope, error contract, versioning, pagination, idempotency, concurrency mechanism, latency tiers, transaction-boundary exceptions (§35 — "Create Organization + owner Membership" and "Transfer Ownership" are named there verbatim), and file/media pattern. |
| **6B — Authentication and Authorization API** | **Binding, consumed unmodified.** Supplies `AuthenticationContext`, the RBAC permission catalog (§16–§17 of 6B; §17 of 5B), tenant-resolution chain, the invitation-*acceptance* endpoint (`POST /api/v1/auth/invitations/accept`) this document's invitation-*creation* flow must feed correctly, and the multi-organization login-continuation flow whose membership-selection behavior this document's invitation design was verified against and is now designed to work correctly with, unmodified (see §9.6 — a genuine cross-document finding, resolved this pass without any 6B change). |

---

## 5. Source Reconciliation

For every candidate resource, ownership is derived — never assumed — from the chain: Phase 4 bounded context → Phase 5 schema → 6A standard → 6B boundary → 6C decision.

| Resource | DDD owner (Phase 4) | Phase 5 schema | Tenant scope | 6B dependency | 6C decision |
|---|---|---|---|---|---|
| Organization | `Organization` aggregate (4A §5.1) | `organization.organizations` | Root of hierarchy, no RLS on itself (5B §16.4) | Tenant resolution derives `organization_id` from JWT/API-key (6B §9) | **OWNED — CRUD + lifecycle** |
| Localization/settings fields | `Organization.Settings`/`LocalizationProfile` VO (4A §5.1; 4I ADR-INDIA-020) | Typed columns on `organizations` (5B §9.6, §23.1 — no separate table by design) | Same as Organization | — | **OWNED — via Organization PATCH, typed allow-list, not a separate resource** (matches 5B's own no-separate-table rationale) |
| Membership | `Membership` aggregate (4A §5.2) | `organization.memberships` | RLS (5B §16.4) | 6B resolves the caller's own membership for authz; does not manage others' | **OWNED — list/get/role-assign/suspend/reactivate/remove/leave** |
| Ownership transfer | `TransferOwnership` (co-owned command, 4A §5.1/§5.2/§6.1) | Two `memberships` rows, one transaction | RLS | — | **OWNED** — named verbatim as a same-transaction exception in 6A §35 |
| Invitation (creation side) | `InviteUser`/`RevokeInvitation` commands (4A §5.2) | `identity.password_reset_tokens` (`purpose=INVITATION`) + `organization.memberships` (pending row) | Cross-schema; org-scoped in effect | **Acceptance is 6B's** (`POST /api/v1/auth/invitations/accept`, 6B §3.2, §21.13) | **OWNED — creation/list/resend/cancel only.** Acceptance is not re-designed here. |
| Team | Entity **embedded in** `Organization` aggregate, not an independent aggregate (4A §5.1: `"Teams (list[Team] — embedded, bounded, < ~100 per org)"`) | `organization.teams`, `organization.team_memberships` | RLS (5B §16.4) | — | **OWNED — full CRUD + membership**, gated by `organization:update` (interim mapping — see §17 dependency) |
| CompliancePolicy | Separate aggregate, **Organization bounded context** (4I §7.2, §9.1 table row 2: "Organization ... Core API") | `organization.compliance_policies` | RLS | — | **OWNED — read + versioned create/activate** |
| DataSubjectRequest | Separate aggregate, **Organization bounded context**, explicitly mapped to "Core API" (4I §9.1 row 2, §639) | `organization.data_subject_requests` | RLS | — | **OWNED — create/list/get/verify/hold/complete/reject** |
| User (profile fields only) | `User` aggregate, **Identity context**, platform-global (4A §5.3) | `identity.users` | No RLS (platform-owned) | 6B owns `/auth/me` (authentication context) and all credential/MFA/email-verification mutations | **OWNED (narrow slice only) — `GET/PATCH /users/me` for `display_name`/`phone_e164`, plus `GET /users/me/organizations`.** Credentials, MFA, email, sessions remain 6B's. |
| User preferences (timezone/locale/default-org) | Not modeled — 4A defines no `UserPreferences` aggregate; **ADR-5B-006 explicitly confirms no `user_preferences` table exists** | None | — | — | **NOT OWNED — not designed.** No column exists to back it; inventing one would violate the Hard Stop. Flagged as a future dependency (§27), not fabricated. |
| Quota / plan-tier limits | `Quota` aggregate, embedded in Organization (4A §5.1, §5.7) | Not in 5B — plan-tier/quota enforcement is a Billing/Usage concern (4F) | — | — | **DEFERRED to a future Billing/Usage API phase** — explicitly out of the task's candidate list and materially about billing, not core-platform identity |
| Feature flags | Separate bounded context, own aggregate (4A §4.5, §5.6) | Not covered by 5B | — | — | **DEFERRED** — its own bounded context with its own aggregate; not in the task's candidate resource list |
| Shared reference data (locales/timezones/countries) | — | No platform reference table exists in 5B; validation is application-layer whitelist (5B §23.2) | — | — | **REFERENCED, not exposed as a distinct resource** — validated inline on Organization PATCH against the same static whitelists 5B already specifies; no `/api/v1/locales` catalog endpoint is invented since no upstream source-of-truth table exists |
| File/media primitives | 6A §29 defines the generic signed-URL *pattern*, not a shared table | No generic `media`/`attachments` table in `organization`/`identity` schema | — | — | **DEFERRED as a shared resource.** `organizations.logo_url` is the only 6C-owned field touching media; it reuses 6A §29's pattern scoped to the Organization resource (§11.5), not a new platform-wide file API. |
| Async job / status | 6A §18.3: `/api/v1/jobs/{job_id}` projects from an existing domain table; it does not create one | No Organization/Membership/Team/Compliance/DSR operation in 5B is modeled as an async job — every 6C mutation is a short, synchronous transaction | — | — | **NOT APPLICABLE — every 6C endpoint is synchronous (Tier A).** No job resource is introduced. |
| Audit-log browsing (`audit.audit_events` query API) | `AuditEvent` aggregate, its own bounded context (4A §4.4) | `audit.audit_events` (5J) | — | 6B writes to it; does not expose a browse API | **DEFERRED** — explicitly named out-of-scope by the task brief (§2) |
| Platform-admin org management (suspend/reactivate any org, cross-tenant listing) | Platform Admin actor (4A DDR-4A-005) | `app_platform_admin` DB role | — | 6B owns `PlatformAdminOnly`/break-glass mechanics | **DEFERRED** — belongs to a future Admin Control Plane API (`FR-ADM-001`), which 6B explicitly did not build beyond break-glass and forced-logout |

---

## 6. Resource Ownership Matrix (Summary)

| Resource | 6C owns? | Bounded context | Phase 5 backing | Later phase owner | Notes |
|---|---|---|---|---|---|
| Organization (profile/lifecycle/settings) | **OWNED** | Organization | `organizations` | — | §7 |
| Membership (list/role/suspend/remove/leave/transfer) | **OWNED** | Organization | `memberships` | — | §8–§9 |
| Invitation (creation side) | **OWNED** | Organization | `memberships` + `identity.password_reset_tokens` | 6B (acceptance) | §10 |
| Team + team membership | **OWNED** | Organization (embedded) | `teams`, `team_memberships` | — | §11 |
| Compliance Policy | **OWNED** | Organization | `compliance_policies` | Voice/Campaign/CRM *consume* it read-only in later phases | §12 |
| Data Subject Request | **OWNED** | Organization | `data_subject_requests` | Later phases execute the underlying erasure/export against their own schemas | §13 |
| User profile (`display_name`, `phone_e164`) | **OWNED (narrow)** | Identity (slice) | `identity.users` | 6B (credentials, email, MFA, sessions) | §14 |
| User's own organization list | **OWNED** | Organization (query) | `memberships` | — | §14.3 |
| User preferences (timezone/locale/default-org) | **REFERENCED, not designed** | — | None | Future Phase 5.x | §27 DEP-6C-05 |
| Quota / plan tier | **DEFERRED** | Organization (embedded per DDD) | Not in 5B | Billing/Usage phase | §5 |
| Feature flags | **DEFERRED** | Feature Flag (own context) | Not in 5B | Future phase | §5 |
| Shared reference data catalog | **DEFERRED (not exposed)** | — | None | — | §5 |
| File/media shared primitive | **DEFERRED** | — | None (organization logo reuses 6A §29 pattern locally) | — | §5 |
| Async job/status resource | **NOT APPLICABLE** | — | — | — | §5 |
| Audit-log browsing | **DEFERRED** | Audit (own context) | `audit.audit_events` | Future Audit API phase | §5 |
| Voice/AI Agent/Knowledge/CRM/Campaign/Workflow/Integrations/Billing/Analytics/Admin | **DEFERRED** | Respective contexts | Respective schemas | 6D–6M | Task Hard Stop |

---

## 7. Organization Design

### 7.1 Aggregate and Invariants

Grounded in 4A §5.1 and 5B §9.6/§22. Frozen DB truth is authoritative wherever it differs from the DDD narrative (see §7.5).

- **Status machine (5B-frozen):** `ACTIVE | SUSPENDED | CANCELLED` (`chk_orgs_status`). 4A's narrative names `DELETED` instead of `CANCELLED` — a naming discrepancy resolved the same way 6B resolved its own DDD-vs-DB conflicts (ADR-6B-08 precedent): **the frozen DB value (`CANCELLED`) is authoritative**; this document uses it exclusively.
- **Legal transitions:** `ACTIVE → SUSPENDED`, `SUSPENDED → ACTIVE`, `ACTIVE → CANCELLED`, `SUSPENDED → CANCELLED` (4A §5.1 invariant 3, restated with the DB-authoritative terminal name). `CANCELLED` is terminal — no further transition (invariant 4).
- **Owner constraint:** exactly one `ACTIVE` membership with role `OWNER` at all times (5B §22.2). Enforced at the application layer via an atomic conditional statement (§16), since 5B enforces only "one active membership per user," not "exactly one OWNER" — that composite invariant is 6C's to guard.
- **Immutable fields:** `id`, `slug` is mutable (subject to global uniqueness, 4A §5.1 business rule) but its own change is a distinct, audited action; `currency` is **write-once**, enforced by a `BEFORE UPDATE` DB trigger (5B §9.6) — 6C's PATCH schema must reject any client-supplied `currency` change with `422 VALIDATION_ERROR`, not merely rely on the trigger to fail the transaction, so the caller gets an honest error rather than a generic 500.
- **`country_code`** has no column default (5B §24) — required at creation, immutable in practice (no update path is designed here; changing a tenant's country has tax/compliance consequences outside 6C's authority and is not exposed).

### 7.2 Editable Profile / Settings Fields (typed allow-list — never a generic JSON bag)

Per the task's explicit prohibition on an unrestricted settings PATCH (§14 of the task brief), the following is the **complete** allow-list for `PATCH /api/v1/organizations/{organization_id}`. Every field not listed is either immutable or owned by a different, unbuilt subsystem (billing profile, tax profile) and is rejected by Pydantic's `extra="forbid"` (6A §22) if supplied.

| Field | Type | Validation | Server authority | Cache invalidated |
|---|---|---|---|---|
| `name` | string, 2–100 chars | 4A §5.1 `OrganizationName` VO bounds | Client | — |
| `slug` | string, 3–63 chars, `[a-z0-9-]` | Global uniqueness (5B §9.6) — `409 STATE_CONFLICT` on collision | Client, server-validated | — |
| `legal_name` | string, nullable | — | Client | — |
| `timezone` | IANA TZ string | `zoneinfo.ZoneInfo()` parse (5B §23.2) | Client | `localization:{org_id}` (5B §31) |
| `locale` | BCP 47 | `babel.Locale.parse()` (5B §23.2) | Client | `localization:{org_id}` |
| `primary_language` | BCP 47 | Must be a member of `supported_languages` (5B §23.2) | Client | `localization:{org_id}` |
| `supported_languages` | BCP 47 array | Each element valid BCP 47 | Client | `localization:{org_id}` |
| `phone_country` | ISO 3166-1 alpha-2 | Whitelist | Client | `localization:{org_id}` |
| `fiscal_year_start_month` | integer 1–12 | — | Client | `localization:{org_id}` |
| `website` | URL string, nullable | HTTPS-only if present | Client | — |
| `logo_url` | string, nullable, server-set only | Never client-writable directly — set only via the upload-complete flow (§11.5) | **Server** | — |

**Never editable via this endpoint:** `id`, `owner_user_id` (only via §9.5 ownership transfer), `status` (only via §7.4 action endpoints), `country_code`, `currency` (write-once), `region_ref`/`data_residency_profile` (contractual, not self-service — no permission exists for it either; flagged §27), `compliance_policy_id`/`tax_profile_id`/`billing_account_id` (system-set logical references).

### 7.3 CRUD Endpoints

`POST /api/v1/organizations` (create), `GET /api/v1/organizations/{organization_id}` (read), `PATCH /api/v1/organizations/{organization_id}` (update, allow-list above). Full contracts: §15.1–§15.3.

### 7.4 Lifecycle (Command) Endpoints

Per 6A §8.3, status transitions with business-rule guards use action endpoints, not a generic `PATCH {"status": ...}`:

```
POST /api/v1/organizations/{organization_id}/suspend
POST /api/v1/organizations/{organization_id}/cancel
```

**No `DELETE /api/v1/organizations/{organization_id}`** — organizations are a terminal-status resource (6A §7.6); `DELETE` returns `405 Method Not Allowed`, directing callers to `POST .../cancel`.

**Reactivation is deliberately not designed here.** The frozen permission catalog (5B §17.1) defines `organization:suspend` and `organization:delete` but **no `organization:reactivate`/`organization:activate` permission**, and 4A's own `SuspendOrganization` command names its issuer as `"Platform Admin or system process"` (4A §10.1) — not the tenant OWNER — even though 5B's frozen role-permission matrix grants `organization:suspend` to `OWNER` (5B §17.2). This is a genuine, documented conflict between the DDD narrative and the frozen permission matrix (§7.5 below); this document does not silently pick a side beyond what the frozen matrix actually grants. Because no tenant-facing permission for reactivation exists in either source, **reactivation is out of 6C's scope** and is deferred to a future Admin Control Plane API (consistent with 6B's own precedent of leaving `PLATFORM_ADMIN`-only capabilities to be built as needed) — see DEP-6C-01, §27.

### 7.5 Documented Upstream Conflict — Self-Service Suspend vs. DDD Narrative

**Finding (not silently resolved):** 4A §10.1's `SuspendOrganization` command comment states the issuer is "Platform Admin or system process," implying tenant self-suspension was never intended. However, 5B §17.2's frozen role-permission matrix explicitly grants `organization:suspend` to the `OWNER` role — a real, tenant-facing, seeded permission. Per this document's own precedent (6B ADR-6B-08: the DB-frozen artifact wins over an aspirational DDD narrative), **this document treats the frozen permission matrix as authoritative** and designs `POST /api/v1/organizations/{organization_id}/suspend` as an `OWNER`-only, tenant-self-service action (e.g., "pause the account temporarily"). This is recorded as **ADR-6C-01** (§28) rather than silently picking one source over the other without comment.

### 7.6 Reconciled Concurrency Mechanism (no bespoke `SECURITY DEFINER` function exists)

Unlike Voice/Campaign/Webhook schemas (5C/5E/5I), **5B defines no `SECURITY DEFINER` guarded-transition function for organization or membership status changes** — the frozen schema relies on `CHECK` constraints and partial unique indexes only. 6A §17.2 expects action endpoints to "call the corresponding guarded DB function"; where none exists, this document applies the identical solution 6B already used for an analogous gap (refresh-token rotation, ADR-6B-01/§13.2): an **atomic, conditional `UPDATE ... WHERE ... RETURNING`** issued directly by the application layer, with **no** `SELECT ... FOR UPDATE` or other API-layer lock (6A §17.3 compliance). This is recorded as **ADR-6C-02** (§28) and is the concurrency mechanism for every guarded transition in this document (organization status, membership status/role, team archive, compliance-policy activation, DSR status).

```sql
UPDATE organization.organizations
SET status = 'SUSPENDED', updated_at = now()
WHERE id = :organization_id AND status = 'ACTIVE'
RETURNING id, status;
-- 0 rows affected → 409 STATE_CONFLICT, error.details.current_state = <re-read value>
```

### 7.7 Organization Creation Transaction — RLS-Correct AND Genuinely Event-Driven (corrected this pass — Blocker 1)

**Three corrections layered here:**

**(1) RLS correctness (retained).** `organization.memberships` carries `ENABLE + FORCE ROW LEVEL SECURITY` (5B §16.4) with `WITH CHECK` on `INSERT`, never bypassed; ordinary `app_api` role throughout, no `BYPASSRLS`.

**(2) Transaction-boundary correction (retained from the prior pass).** Only `Organization` + owner `Membership` — 6A §35's exact named exception — are written atomically. `CompliancePolicy` is a confirmed separate aggregate (4I §7.2, §9.1) and is not named in that exception list.

**(3) Genuinely event-driven CompliancePolicy seeding (corrected THIS pass — Blocker 1).** The prior pass's fix was insufficient: it moved the `compliance_policies` insert into a *second transaction*, but that second transaction still ran **synchronously, in the same request handler, before the HTTP response was returned**. This still violated 6A §35's actual rule, which is stronger than "a different transaction": *"an API endpoint's synchronous response must never wait for these downstream effects to complete."* The prior draft's `compliance_policy_seeded: true|false` response field is **retracted** for the same reason: if the response cannot honestly know a downstream asynchronous outcome at response time, it must not report on it.

**Corrected shape — the synchronous boundary ends at the request transaction's commit; everything else is genuinely event-driven, using the platform's approved architecture-layer mechanism (Redis Streams event bus + transactional-outbox reliability pattern — both approved at Phase 2/3A level, 3A §6.3, `eventbus/publisher.py`/`outbox.py`/`consumer.py`).** **DEP-6C-16 is RESOLVED this pass (Revision 6, controlled Phase 5.x amendment).** A concrete Postgres transactional-outbox relation, `audit.domain_event_outbox`, now exists — added by migration `077_5J1.sql` (Alembic revision `077_5J1`, `down_revision=076_5K1`; `5K/MIGRATION_MANIFEST.md` row 077; `5K/validation/077_5J1_VALIDATION_REPORT.md`) — placed inside the already-frozen `audit` schema (5A §1's "prefer an existing schema; the bar for a new one is high," satisfied by reuse rather than a new schema), carrying no RLS by design (same documented precedent as `identity.sessions`/`identity.password_reset_tokens`, 5B §16.3 — not a `BYPASSRLS` workaround; tenant-forgery on `INSERT` is instead guarded structurally by a `BEFORE INSERT` trigger). This section's SQL below is now real, executable SQL against that relation, not a commented-out placeholder.

**REQUEST TRANSACTION (synchronous — the only 6A-§35-authorized aggregate pair):**

```sql
BEGIN;

INSERT INTO organization.organizations (id, name, slug, status, owner_user_id, country_code, currency, ...)
VALUES (gen_uuid_v7(), :name, :slug, 'ACTIVE', :caller_user_id, :country_code, :currency, ...)
RETURNING id;
-- organizations carries no RLS (5B §16.4 — tenant root; RLS cannot predicate on itself).

SET LOCAL app.tenant_id = '<the id just returned by the INSERT above>';
-- This can only happen AFTER the organizations INSERT returns an id — it
-- cannot be "at the start of the transaction." Canonical sequence: INSERT
-- organizations RETURNING id → SET LOCAL → INSERT memberships →
-- INSERT the durable outbox event → COMMIT.

INSERT INTO organization.memberships (id, organization_id, user_id, role_id, status, accepted_at, ...)
VALUES (gen_uuid_v7(), :new_org_id, :caller_user_id, :owner_role_id, 'ACTIVE', now(), ...);
-- Passes rls_memberships_tenant's WITH CHECK.

-- DURABLE OUTBOX EVENT INSERT — DEP-6C-16 RESOLVED this pass (Revision 6):
-- audit.domain_event_outbox now exists (migration 077_5J1). This is real,
-- executable SQL, not a placeholder. No RLS applies to this table (5B
-- §16.3-precedent design, migration 077_5J1 header comment); the ordinary
-- app_api role performs this INSERT in the same transaction as the two
-- inserts above — no BYPASSRLS, no separate privilege.
INSERT INTO audit.domain_event_outbox (event_type, organization_id, aggregate_type, aggregate_id, payload)
VALUES ('organization.created', :new_org_id, 'organization', :new_org_id,
        jsonb_build_object('organization_id', :new_org_id, 'owner_user_id', :caller_user_id, 'slug', :slug));
-- audit.fn_outbox_tenant_check() (a BEFORE INSERT trigger) passes here
-- because app.tenant_id (just SET LOCAL above) equals the organization_id
-- being inserted.

COMMIT;  -- Organization + owner Membership + the outbox event row are all
         -- durable together, in one transaction. RETURN 201 HERE.
         -- Nothing about CompliancePolicy is awaited, checked, or reported
         -- by this response — the outbox row being durable is not the same
         -- as CompliancePolicy having been seeded; the response still never
         -- waits on the consumer (6A §35 compliance is unaffected either
         -- way, per the ADR-6C precedent established in earlier passes).
```

**ASYNC CONSUMER TRANSACTION (fully asynchronous — a distinct process/worker, never inline in the request handler):**

```sql
-- Triggered once the platform's existing outbox-publisher worker (3A
-- eventbus/publisher.py) claims this row via audit.fn_claim_outbox_events(),
-- relays it to the organization.created Redis Streams topic, and confirms
-- the publish via audit.fn_mark_outbox_published() — at-least-once delivery
-- only (never exactly-once); this consumer transaction's own INSERT below
-- is required to be idempotent regardless (point 4, below), independent of
-- how many times the outbox row is (re)claimed or (re)published.
BEGIN;
SET LOCAL app.tenant_id = '<organization_id from the event payload — trusted
                            because it originates from an already-committed,
                            durable event, never from client input>';
INSERT INTO organization.compliance_policies (id, organization_id, status, ...)
VALUES (gen_uuid_v7(), :organization_id, 'ACTIVE', ... India-first defaults per 5B §25.1 ...);
-- Passes rls_compliance_policies_tenant's WITH CHECK.
COMMIT;
```

**Architectural design vs. implementation readiness — the required distinction, stated precisely:**
- **Architecturally, this design is COMPLETE and correct against 6A §35:** the request transaction contains only the 6A-§35-authorized `Organization` + `Membership` pair (now joined by the same-transaction outbox insert, which is not a second aggregate — it is infrastructure bookkeeping, not a domain write); `CompliancePolicy` is written exclusively by an asynchronous consumer, never inline in the request handler.
- **The durable-outbox-INSERT step is DESIGN COMPLETE, schema-backed, and LIVE VERIFIED — DEP-6C-16 RESOLVED (Revision 7).** `audit.domain_event_outbox` (migration `077_5J1.sql`) is a concrete, committed Postgres relation with the exact columns this flow needs (§20). Migration `077_5J1` has been authored, structurally validated, and — as of Revision 7 — **executed against a genuinely fresh PostgreSQL 18 database**, with the atomic domain+outbox invariant, both event flows, concurrency, and security grants all confirmed live (`5K/validation/077_5J1_VALIDATION_REPORT.md`, `5K/execution_logs/README.md`'s "Fifth batch"). No residual remains for this dependency.

**Sequence, restated with DEP-6C-16 resolved:**

1. Request transaction commits — `organizations`, `memberships`, and the `audit.domain_event_outbox` row are all durable together. `201` is returned to the caller **at this point**, with no field describing `CompliancePolicy` state (the outbox row being durable is not the same as `CompliancePolicy` having been seeded — the response still never waits on the consumer).
2. The platform's existing outbox-publisher worker (3A `eventbus/publisher.py`) claims the row via `audit.fn_claim_outbox_events()` (`SELECT ... FOR UPDATE SKIP LOCKED`, safe against double-claiming by concurrent worker instances) and relays it to the `organization.created` Redis Streams topic, then confirms via `audit.fn_mark_outbox_published()`.
3. A Compliance-context consumer (via the existing consumer-group mechanism, 3A `consumer.py`) receives `organization.created` and creates the initial `CompliancePolicy` row (India-first defaults, 5B §25.1) in its own transaction (the ASYNC CONSUMER TRANSACTION above).
4. **Idempotency (required — Redis Streams consumer groups, and this outbox's own publisher semantics, are at-least-once, never exactly-once):** the consumer's insert is safely repeatable — either a pre-check ("does an `ACTIVE`/`DRAFT` policy already exist for this `organization_id`? skip if so") or reliance on 5B §9.13's own partial unique index (`UNIQUE (organization_id) WHERE status = 'ACTIVE'`) to reject a duplicate `ACTIVE` insert, caught and treated as already-done.
5. **Retry on processing/publish failure:** `audit.fn_mark_outbox_failed()` reverts a `CLAIMED` row to `PENDING` with backoff (or to terminal `FAILED` once `max_attempts` is exhausted); a worker that crashes mid-claim without calling either completion function is opportunistically reclaimed by the next `fn_claim_outbox_events()` scan once its claim exceeds the timeout — no bespoke retry policy is invented in this document beyond citing that this mechanism now exists (full detail: migration `077_5J1.sql`, `5K/MIGRATION_MANIFEST.md`).
6. **Until the consumer succeeds**, `GET /organizations/{id}/compliance-policy` (§15.28) correctly returns `404` — a real, expected transient state, not an error condition.
7. **Enforcement consumers must fail closed:** any future phase (Voice/Campaign) gating an operation on `CompliancePolicy` must treat "no `ACTIVE` policy found" as a hard stop, never a permissive default.

**Failure mode, restated now that the outbox exists:** because the outbox row commits in the **same transaction** as `organizations`/`memberships`, a process crash between the request transaction's commit and the publisher's later claim/publish no longer loses the `organization.created` signal — the row survives the crash, durably, in `audit.domain_event_outbox`, and is claimed on the publisher's next scan. The residual risk is narrower than before: an *unclaimed or unpublished-forever* row (e.g., every publisher instance down for an extended period) is not silently lost either — it remains queryable via `idx_outbox_status`/`idx_outbox_claim` — but the practical effect (a delayed `CompliancePolicy`) is the same class of eventual-consistency lag every other event in §20 already accepts, not a crash-safety gap.

**Indicative processing-lag target (TARGET, not measured, 6A §11 discipline):** organization → seeded compliance policy, <5s — by analogy to 4G §12's tightest comparable eventual-consistency target (`call.ended → CRM Activity <5s`); 4G does not itself name this event pair, so this is a 6C-owned design choice, not a claim of prior specification.

**Recovery path — fully implementable today, independent of the publisher's operational health:** the `OWNER`/`ADMIN` may complete seeding manually via the already-designed `POST /organizations/{id}/compliance-policy` (create a `DRAFT`) followed by `POST .../{policy_id}/activate` (§15.29–§15.30) at any time — this path depends on no event mechanism at all, so it fully covers any period where the automated path is degraded, not merely ordinary event latency.

**Idempotency-Key:** because the response never carries any `CompliancePolicy`-derived field, a same-key retry of `POST /organizations` (6A §16) simply replays the original `201` with no staleness concern.

**Why the newly-created organization's own ID is safe to use as tenant context:** the `organizations` row committed by the request transaction is durable and not visible to any other session until commit (Postgres `READ COMMITTED`); no concurrent session can race to claim or observe this `organization_id` before that transaction either commits or rolls back. The async consumer transaction reuses the same `organization_id` from the event payload, which by the time the consumer runs is already durably committed — this is what makes trusting it, rather than re-deriving it from client input, safe.

**DB role:** ordinary `app_api` for the request transaction (including the outbox insert — `app_api` holds `INSERT` on `audit.domain_event_outbox`, migration `077_5J1.sql`), `app_worker` for the publisher's claim/publish/fail calls, and ordinary `app_api` again for the async consumer's own transaction — no `BYPASSRLS` anywhere in this flow.

---

## 8. Membership Design

### 8.1 Status Model (frozen) and the Invited/Accepted Gap

`organization.memberships.status ∈ {ACTIVE, SUSPENDED, REMOVED}` (`chk_memberships_status`, 5B §9.7) — **only three values.** 4A §5.2's DDD narrative defines a fourth value, `INVITED`, that **the frozen DDL never implemented**. Unlike the org-status naming difference (§7.1, a same-concept rename), this is a genuine **missing state**. §9.3 (revised this pass) resolves this **without fabricating a new enum value**: a pending invitation is represented as `status='SUSPENDED', accepted_at=NULL` — reusing the existing `SUSPENDED` value as the pending-placeholder state, disambiguated from a genuine (post-acceptance) suspension purely by `accepted_at`. This specific representation was chosen because it is the only one of the frozen enum's three values under which a pending invitation is **automatically excluded** from every one of 6B's existing access-granting queries — closing a real security gap without any upstream change (§9.6).

### 8.1a Canonical Membership State Table (binding — every query, endpoint, and test in this document is checked against this table)

| Logical state | DB `status` | `accepted_at` | Meaning | Grants tenant access? |
|---|---|---|---|---|
| Pending invitation | `SUSPENDED` | `NULL` | Invited, not yet accepted | **No** |
| Active member | `ACTIVE` | non-null | Ordinary, current organization access | **Yes** |
| Suspended accepted member | `SUSPENDED` | non-null | Was active, access denied until legitimate reactivation | **No** |
| Removed member/invitation | `REMOVED` | any historical value | Terminal — no further transition (5B ADR-5B-004) | **No** |

No other `(status, accepted_at)` combination is legal under this document's design. In particular, `status='ACTIVE' AND accepted_at IS NULL` must never occur — it was the retracted, insecure design from a prior draft (§9.6) and is not a state any endpoint or query in this document produces or expects. This table is the single source of truth every other section's predicates must match; the consistency sweep performed this pass (§9.4, §15.8, §15.17) verified every occurrence against it.

### 8.2 Invariants (from 4A §5.2, reconciled against the 3-value frozen enum)

1. One `ACTIVE` membership per `(organization_id, user_id)` (`uq_memberships_active`, partial unique index, 5B §9.7).
2. A `REMOVED` membership is immutable — no reactivation of a removed row; re-invitation creates a new row (5B ADR-5B-004).
3. Exactly one `ACTIVE` membership may hold the `OWNER` role per organization at a time (application-layer invariant, §7.1) — the last OWNER cannot be suspended or removed without a prior ownership transfer.
4. A `SUSPENDED` membership retains its `role_id` (role is not cleared on suspension) — reactivation restores the same role, no re-invitation needed. **Reactivation is valid only for a genuinely-suspended row (`accepted_at IS NOT NULL`)** — a `SUSPENDED` row with `accepted_at IS NULL` is a *pending invitation* (§9.3), not a suspended member, and `POST .../reactivate` must reject it (§15.12) rather than silently activating an invitation the invitee never accepted.
5. `CustomPermissions` (4A §5.2's per-membership additive-grant concept) **does not exist** in the frozen schema (confirmed by 6B ADR-6B-05) — 6C does not design `GrantCustomPermission`/`RevokeCustomPermission` endpoints; role is the sole authority unit.

### 8.3 Endpoints

```
GET    /api/v1/organizations/{organization_id}/members
GET    /api/v1/organizations/{organization_id}/members/{member_id}
POST   /api/v1/organizations/{organization_id}/members/{member_id}/role
POST   /api/v1/organizations/{organization_id}/members/{member_id}/suspend
POST   /api/v1/organizations/{organization_id}/members/{member_id}/reactivate
POST   /api/v1/organizations/{organization_id}/members/{member_id}/remove
POST   /api/v1/organizations/{organization_id}/members/me/leave
POST   /api/v1/organizations/{organization_id}/ownership/transfer
```

`{member_id}` is the `Membership.id`, never `user_id` — matches 5B's own PK and avoids leaking whether a given `user_id` exists on the platform at all (cross-tenant enumeration, §24).

### 8.4 Role Assignment — Guard Rules and Authorization (corrected this pass)

`POST .../members/{member_id}/role` is a command endpoint (6A §8.3), not `PATCH {"role_id": ...}` — role changes touching `OWNER` have invariants a bare field write cannot safely express.

**Authorization — corrected:** gated by **`role:manage`**, not `member:invite`. A prior draft of this document mapped role assignment to `member:invite` as an "interim, no dedicated permission exists" workaround; that reasoning was wrong. 5B §37.6 (Privilege Escalation Prevention) explicitly states the frozen design's own intended control for this exact scenario: *"User grants themselves OWNER → `role:manage` permission required + server validates the assigning user has higher/equal role."* `role:manage` is a real, seeded permission (5B §17.1/§17.2, §32.3) — held by `OWNER` and `ADMIN` only, the same actor set the retracted interim mapping happened to also restrict to, so no seeded grantee changes as a result of this correction; only the permission *string* checked at authorization time changes.

- Rejects (`409 ROLE_CHANGE_NOT_ALLOWED`) if `new_role_id` resolves to `OWNER` — assigning ownership is exclusively `POST .../ownership/transfer` (§8.5), because only that endpoint enforces the "exactly one OWNER" swap atomically.
- Rejects (`409 ROLE_CHANGE_NOT_ALLOWED`) if the target membership's *current* role is `OWNER` — the sole OWNER cannot be demoted through this endpoint; ownership must be transferred first.
- **Hierarchy check (5B §37.6's own stated control, applied here):** beyond the two structural guards above, the use case additionally validates that the assigning caller's own role is of equal-or-higher authority than the role being assigned — the exact mechanism 5B §37.6 names generally for privilege-escalation prevention. Since 5B defines no explicit ordinal ranking beyond `OWNER` (checked separately above) and only `OWNER`/`ADMIN` hold `role:manage` at all (5B §17.2), this reduces in practice to: `ADMIN` may assign any non-`OWNER` role; `OWNER` may assign any role including reassigning `ADMIN`. A finer-grained ordinal hierarchy (e.g., preventing one `ADMIN` from granting `ADMIN` to another membership) is not separately encoded anywhere in 5B and is not fabricated here.
- Otherwise: atomic conditional `UPDATE organization.memberships SET role_id = :new_role_id WHERE id = :member_id AND organization_id = :org_id AND status = 'ACTIVE' RETURNING id` (§7.6 CAS pattern).

### 8.5 Ownership Transfer

`POST /api/v1/organizations/{organization_id}/ownership/transfer` — named verbatim in 6A §35 as one of the platform's few approved same-transaction, cross-aggregate atomicity exceptions ("Transfer Ownership (two Memberships)"). Request: `{"target_member_id": "..."}`. Guard: the caller **must be** the current OWNER membership (identity-bound, not merely permission-bound — 4A §10.1's `TransferOwnership` command shape); target must be an `ACTIVE` membership in the same org. Both role reassignments happen in one transaction:

```sql
BEGIN;
UPDATE organization.memberships SET role_id = :admin_role_id
  WHERE id = :current_owner_member_id AND status = 'ACTIVE' AND role_id = :owner_role_id
  RETURNING id;
UPDATE organization.memberships SET role_id = :owner_role_id
  WHERE id = :target_member_id AND organization_id = :org_id AND status = 'ACTIVE'
  RETURNING id;
COMMIT;
-- either UPDATE affecting 0 rows aborts the transaction → 409 STATE_CONFLICT
```

No API-layer lock — both statements' `WHERE`-clause CAS conditions provide the atomicity guarantee within the single transaction (6A §17.3-compliant, same reasoning as §7.6/§13.2 of 6B).

### 8.6 Suspend / Reactivate / Remove / Leave

- **Suspend** (`POST .../suspend`): guarded — cannot suspend the sole `ACTIVE OWNER` membership (§8.2 invariant 3), enforced by the same CAS-with-`NOT EXISTS`-guard pattern shown in §16.2.
- **Reactivate** (`POST .../reactivate`): `SUSPENDED → ACTIVE`, guarded by `WHERE status = 'SUSPENDED' AND accepted_at IS NOT NULL` — the `accepted_at IS NOT NULL` clause is load-bearing, not decorative: it is what prevents this endpoint from being used to bypass invitation acceptance by directly activating a still-pending (`accepted_at IS NULL`) row without the invitee ever presenting a valid token (§9.3, §15.12).
- **Remove** (`POST .../remove`, admin-initiated): same last-owner guard as suspend; sets `status='REMOVED', removed_at=now(), removed_by=:actor`.
- **Leave** (`POST .../members/me/leave`, self-initiated): identical state transition to Remove, but `removed_by = caller's own user_id` and no `member:remove` permission is required (self-scoped, mirrors 6B's session self-revocation precedent, §14 of 6B) — still subject to the last-owner guard (an OWNER must transfer ownership before leaving, per 4A's business rule).
- 5J's audit vocabulary provides only one `MEMBER_REMOVED` action_kind for both Remove and Leave — this is treated as **adequate**, not a gap: `actor_ref` (the admin vs. the departing user themself) already differentiates the two cases in the audit record, matching how 6B accepted an analogous single-action-kind-for-two-actors mapping elsewhere (6B §25 Tier 1).

---

## 9. Invitation Design — the Boundary With 6B

### 9.1 Restated Boundary

6B owns exactly one invitation endpoint: `POST /api/v1/auth/invitations/accept` (6B §21.13) — token redemption, membership activation, session issuance. Everything upstream of that (who can invite, what role, duplicate/expiry/resend/cancel handling) is 6C's, per 6B's own explicit scope carve-out (6B §3.2).

### 9.2 Two Frozen-Schema Gaps — One Closed by Design, One Genuinely Open

Two frozen facts, read together, leave two **distinct** gaps this document must reconcile — they require different treatment and must not be conflated:

**Gap A — no pre-acceptance status value (closed in §9.3, no upstream change needed).** `organization.memberships.status` has no `INVITED`/`PENDING` value (§8.1) — yet the table carries `invited_at`, `invited_by`, `accepted_at` columns clearly intended to represent a pre-acceptance state, and 5B's own reference query for listing members (5B §35.5, `ORDER BY m.accepted_at ASC NULLS LAST`) is written as if rows with `accepted_at IS NULL` legitimately coexist under some status value. §9.3 closes this by using `status='SUSPENDED', accepted_at=NULL` as the pending-placeholder representation — a value already excluded by every one of 6B's frozen access-granting checks (§9.6), requiring no upstream change.

**Gap B — no durable link between an invitation token and the membership it belongs to (NOT closed — a genuine, disclosed dependency; §9.3.1, §9.4, DEP-6C-12).** `identity.password_reset_tokens` (the table 6B's invitation-accept flow reads, `purpose='INVITATION'`) has **no `organization_id`, `role_id`, `membership_id`, or `invitation_id` column** — only `id`, `user_id`, `token_hash`, `created_at`, `expires_at`, `used_at`, `purpose`. A raw token presented by a client can be made to carry a `membership_id` prefix (§9.3), which solves lookup **at acceptance time**, when the server has the raw token. It does **not** solve lookup **at resend/cancel time**, when the server has only a `membership_id` (from the URL path) and must find "the" `password_reset_tokens` row for that specific invitation among possibly several rows sharing the same `user_id` and `purpose='INVITATION'` (one user invited to several organizations) — the server cannot do this from durable state alone, because no column ties a `password_reset_tokens` row back to a specific membership. This is a genuine implementation/storage gap, not merely a documentation gap; §9.3/§9.4 state precisely what is and is not implementable because of it.

Neither gap is a defect in 6B (invitation *creation* was explicitly out of 6B's scope) or in 5B (5B never claimed to fully specify the invitation *creation* mechanism). Both are genuine seams between frozen documents that 6C, as the owner of invitation creation, must close or honestly disclose — **without modifying either.**

### 9.2a Invitation Token Expiry — Reconciled Contract (High-Priority Consistency Fix, this pass)

**Conflict identified between two frozen sources, neither a hard DB `CHECK` constraint:**

- **4A §5.2** (DDD business rule, invitation-specific): *"Invitations expire after 7 days (configurable via Feature Flag per organization)."*
- **5B §9.3** (frozen schema documentation for `identity.password_reset_tokens.expires_at`, the shared table backing `PASSWORD_RESET`/`EMAIL_VERIFICATION`/`INVITATION` alike): *"`created_at + 1 hour`"* — stated generically for the column, matching the table's own `purpose` column `DEFAULT 'PASSWORD_RESET'`, with no purpose-specific carve-out written for `INVITATION`.

**Neither value is DB-enforced.** 5B's own rationale for this column states plainly: *"`expires_at` is enforced at the application layer on redemption"* — the column is `TIMESTAMPTZ NOT NULL` with no `CHECK` or computed default tying it to `created_at`; the application chooses and writes the value at `INSERT` time. 5B's "1 hour" is therefore read as a **documented design intent for the column's typical (password-reset-oriented) use**, not a structural constraint an `INVITATION`-purpose choice would violate.

**Reconciliation (ADR-6C-07, §28):** this document retains **7 days** as the `INVITATION`-purpose expiry, because (a) 4A's rule is purpose-specific and product-grounded (an emailed invitation, unlike an in-session password reset, is realistically not opened within an hour), (b) 5B's "1 hour" note reads as describing the column's `PASSWORD_RESET`-default use case rather than a considered decision about `INVITATION`'s different UX, and (c) 5B explicitly delegates the actual duration to the application layer, leaving room for a purpose-specific value without contradicting any enforced schema fact. **The "configurable via Feature Flag per organization" half of 4A's rule is NOT implemented** — Feature Flags are their own bounded context, explicitly deferred out of 6C's scope (§5) — so 7 days is a **fixed** default here, not per-org-configurable; this is a disclosed simplification, not a silent drop of the DDD rule. This value is used consistently in §9.3 (creation), §9.4 (resend's natural-expiry backstop), and §24 (threat model).

### 9.3 Reconciled Design (ADR-6C-03, revised — §28)

**Membership row created at invite time, using `SUSPENDED` (not `ACTIVE`) as the pending-placeholder status — a corrected design.** A prior draft of this document used `status='ACTIVE'` at invite time; that was a genuine security defect (an invited-but-unaccepted existing user could pass 6B's own frozen access checks before ever accepting) and is retracted — see §9.6 for the full analysis.

```
POST /organizations/{org}/invitations
  → validate inviter's member:invite permission (5B §17.2 — OWNER/ADMIN only)
  → validate role_id is not OWNER (ownership is never granted by invitation, only by §8.5 transfer)
  → resolve invitee by normalized email:
       existing identity.users row found → use its user_id
       not found → create identity.users row: status='PENDING_VERIFICATION',
                    email set, password_hash=NULL, email_verified_at=NULL
                    (idempotent on retry — see §9.3.2 point 1)
  → duplicate/idempotent check against this specific (organization_id, user_id)
    pair (application-layer — full decision table and residual race in §9.3.2):
       existing row: status='ACTIVE' (real member)
                                                          → 409 MEMBER_ALREADY_EXISTS
       existing row: status='SUSPENDED' AND accepted_at IS NOT NULL (real suspended member)
                                                          → 409 MEMBER_ALREADY_EXISTS
       existing row: status='SUSPENDED' AND accepted_at IS NULL (pending),
       SAME role_id requested
                                                          → IDEMPOTENT RE-INVITE (§9.3.2 point 2):
                                                            reuse the existing membership_id,
                                                            mint a fresh password_reset_tokens
                                                            row, return 200 (not 201)
       existing row: status='SUSPENDED' AND accepted_at IS NULL (pending),
       DIFFERENT role_id requested
                                                          → 409 INVITATION_ALREADY_PENDING
                                                            (ambiguous intent — cancel §9.4
                                                            first, or resend §9.4 to keep the
                                                            same role)
       no existing row for this (org, user) pair          → proceed to insert, below
  → [fresh-invite path only] INSERT organization.memberships (
       status='SUSPENDED'   -- the pending-placeholder value, per §8.1a — NOT 'ACTIVE' (§9.6)
       accepted_at=NULL     -- the pending signal
       invited_by, invited_at=now(), role_id
    )
  → INSERT identity.password_reset_tokens (user_id, purpose='INVITATION',
       token_hash = SHA256(raw_token), expires_at = now() + 7 days per §9.2a's
       reconciled invitation-expiry contract)
  → raw_token is constructed as "{membership_id}.{secret}" — mirrors 6B ADR-6B-01's
       refresh-token format exactly (cleartext ID prefix + random secret), giving
       the ACCEPT flow (which possesses the raw token, §9.3.1) a concrete way to
       resolve WHICH membership row it targets, without any Phase 5 schema change
  → email delivery is out of scope here (notification concern, FR-NOTIF-001, later phase)
  → audit MEMBER_INVITED (both the fresh-invite and idempotent-re-invite paths, §19)
```

Full failure-mode review (retry safety, partial-failure recovery, the residual concurrency race, and why it does not threaten unauthorized access): **§9.3.2**.

**9.3.1 — Accept flow (owned by 6B, using 6C's token-construction guidance; unchanged in mechanism from the prior draft):**

```
1. Parse membership_id from the presented raw token's cleartext prefix.
2. Load organization.memberships WHERE id = membership_id
     — must have status = 'SUSPENDED' AND accepted_at IS NULL (the pending-placeholder
       state, §8.1a) — anything else (already ACTIVE, REMOVED, or a genuinely-suspended
       row with accepted_at IS NOT NULL) fails this step: "target Membership row still
       PENDING/inactive as expected" (6B §21.13's own language).
3. Look up identity.password_reset_tokens WHERE user_id = membership.user_id
     AND purpose='INVITATION' AND used_at IS NULL AND expires_at > now(),
     verify SHA-256(presented_token) = token_hash.
4. On match (atomic conditional UPDATE, §7.6 CAS — WHERE status='SUSPENDED'
     AND accepted_at IS NULL — no API-layer lock): membership.status='ACTIVE',
     membership.accepted_at=now(); token.used_at=now(); create session.
     — If this UPDATE instead raises a unique_violation on uq_memberships_active
       (possible only under the duplicate-pending-row race, §9.3.2 point 5,
       DEP-6C-13): the invitee already holds an ACTIVE membership in this org via
       a different, duplicate invitation accepted first — map this to
       409 STATE_CONFLICT ("already a member"), not a raw 500. This is the accept
       flow's own defined recovery for that specific race, made possible by the
       already-frozen uq_memberships_active index without any schema change.
```

Step 2's membership-state guard is what actually authorizes acceptance — not solely the token's cryptographic validity — and this is what makes §9.7's cancel-vs-accept race (scenario E) resolve safely by construction, independent of Gap B (§9.2).

### 9.3.2 Failure-Mode Review — Invitation Creation (Blockers 2 & 3, this pass)

Applying the standard failure-mode questions to every step of §9.3's flow:

1. **What if the `identity.users` insert (new-user path) commits and the `organization.memberships` insert fails?** The user row is left `PENDING_VERIFICATION` with no memberships anywhere. **Retry is safe and self-healing:** a subsequent call re-resolves the invitee by email, finds the existing `PENDING_VERIFICATION` user with no memberships, and proceeds directly — no duplicate user row, no error.
2. **What if the `organization.memberships` insert commits and the `identity.password_reset_tokens` insert fails?** This is Blocker 2's named scenario: a `SUSPENDED`/`accepted_at IS NULL` membership exists with **no usable token** — previously a dead end, since a naive retry hit `409 INVITATION_ALREADY_PENDING` with no path forward. **Corrected this pass:** the duplicate-check logic (§9.3) now recognizes a pending row for the same `(org, user)` **with the same requested `role_id`** as an **idempotent re-invite**, not a conflict — it reuses the existing `membership_id` and mints a fresh token, returning `200`. A retry (automatic or manual) of the *original* request with the *same parameters* always converges to a working invitation, never a stranded one. A retry with a **different** `role_id` instead surfaces `409 INVITATION_ALREADY_PENDING`, directing the caller to cancel (§9.4) first — this is a deliberate, narrow exception so a client cannot silently change a pending invitation's role via a bare retry.
3. **Can retry detect the partially-completed state?** Yes — the duplicate check's lookup on `(organization_id, user_id)` finds the pending row regardless of whether the token insert ever succeeded; the retry does not need to know *why* the prior attempt didn't fully complete.
4. **Can the operation become permanently stranded?** **No**, for sequential retries (points 1–3) — every partial-failure state self-heals via a repeated call to the same endpoint (or, equivalently, `POST .../resend` once the pending row is visible via `GET .../invitations`, §15.17/§9.4). A narrower exception remains for the concurrent case (point 5).
5. **Can concurrent requests produce duplicate logical resources?** **Yes.** No DB constraint covers `(organization_id, user_id) WHERE status='SUSPENDED' AND accepted_at IS NULL` (the partial unique index `uq_memberships_active` covers only `status='ACTIVE'`, §8.2 invariant 1) — two genuinely concurrent `POST .../invitations` calls for the same `(org, email, role)` can both observe "no existing row" in the same race window and both `INSERT`, producing **two** pending rows for the same `(organization_id, user_id)` pair. **This document does not claim a deterministic single-winner-plus-409 outcome for this race** (§25's tests reflect this honestly, corrected this pass). **Why this does not threaten unauthorized access:** 5B's existing `uq_memberships_active` partial unique index (`WHERE status='ACTIVE'`) — a real, already-frozen, already-enforced constraint — guarantees **at most one** of the duplicate pending rows can ever successfully transition to `ACTIVE`. Whichever `membership_id`'s token is accepted first succeeds (§9.3.1 step 4); the second, duplicate `membership_id`'s token later raises a `unique_violation`, mapped to a clean `409 STATE_CONFLICT` (§9.3.1 step 4, revised above) rather than a raw error. **The worst outcome is a data-hygiene nuisance (two invitation emails, one link ends in a clean 409) — never a double grant, never unauthorized access, and never two `ACTIVE` memberships for the same `(org, user)` pair.** Tracked as **DEP-6C-13** (§27) — logically distinct from Gap B/DEP-6C-12 (that gap is about identifying *which* token belongs to a membership at resend/cancel time; this gap is about *preventing duplicate pending rows from being created at all* — a different missing DB capability, hence a separate dependency entry rather than conflating two materially different problems).
6. **Is there a DB constraint protecting the invariant?** Partially: `uq_memberships_active` protects the *acceptance*-time invariant; no constraint protects the *pending-creation*-time invariant — this asymmetry is exactly DEP-6C-13.
7. **Is the residual documented honestly?** Yes — here, and in §25's corrected test claims.
8. **Is the claimed test behavior actually enforceable?** Yes, after §25's correction this pass — the suite asserts only what the CAS/unique-index mechanics actually guarantee.

This is additive clarification of an underspecified mechanism 6B deliberately left to its downstream owner (6B §3.2) — not a modification of 6B's endpoint contract, request/response shape, or status codes, all of which are unchanged.

### 9.4 Invitation Management Endpoints

```
POST   /api/v1/organizations/{organization_id}/invitations          (create, per §9.3)
GET    /api/v1/organizations/{organization_id}/invitations           (list pending — status='SUSPENDED' AND accepted_at IS NULL, per §8.1a)
POST   /api/v1/organizations/{organization_id}/invitations/{membership_id}/resend
POST   /api/v1/organizations/{organization_id}/invitations/{membership_id}/cancel
```

- **Cancel — fully implementable today, no dependency.** Atomic conditional `UPDATE organization.memberships SET status='REMOVED', removed_at=now(), removed_by=:canceller WHERE id=:membership_id AND status='SUSPENDED' AND accepted_at IS NULL RETURNING id` (§7.6 CAS). **Cancellation's safety does not depend on identifying or invalidating any `password_reset_tokens` row** — a prior draft of this document incorrectly claimed the "associated token row" is marked used; that claim is removed. It is unnecessary: once the membership row leaves the pending state, §9.3.1 step 2 rejects *any* subsequent accept attempt for that `membership_id`, regardless of which token (or how many) were ever issued for it and regardless of whether their `token_hash` rows remain technically un-expired and unused in the database. Reuses `MEMBER_REMOVED` audit action (adequate — canceling an unaccepted invitation and removing a member are the same terminal row-outcome).
- **Resend — DESIGN CONTRACT COMPLETE, CURRENT IMPLEMENTABILITY BLOCKED on Gap B (DEP-6C-12).** The endpoint inserts a fresh `password_reset_tokens` row (new secret, new `token_hash`, new `expires_at`) for `membership.user_id`, so the invitee always has a working link. The required security invariant — *"after resend, exactly one invitation token for that invitation may remain valid"* — **cannot be reliably guaranteed with the frozen schema** whenever the same user has more than one concurrent pending invitation (to different organizations): `identity.password_reset_tokens` has no column identifying which row belongs to which membership/invitation, so the resend use case has no durable-state way to find and invalidate specifically the *prior* token for *this* membership without risking invalidating a *different* organization's still-valid pending invitation instead. **This document does not fabricate an invalidation algorithm to paper over this.** The old token row is left as-is; it remains cryptographically valid until its own natural `expires_at` (7 days, per §9.2a's reconciled contract) unless a future Phase 5.x change (§27, DEP-6C-12) adds the missing linkage. **Bounded residual risk, stated precisely:** an old, un-invalidated token can only be used to accept the *same* invitation (same organization, same role) that the legitimate resend was reissuing — it cannot grant anything beyond what the inviting admin already intended to grant to that specific invitee; the risk is "an intercepting party could race the legitimate invitee to accept first," not privilege escalation or cross-tenant access. Natural token expiry (7 days) is the only backstop until DEP-6C-12 is resolved.
- **Removed-user reinvite:** a `REMOVED` membership row does not block a new `POST .../invitations` call — no unique index constrains `REMOVED` rows (5B ADR-5B-004), so a fresh invite simply inserts a new membership row (new `id`), and any token tied to the old, now-`REMOVED` `membership_id` already fails §9.3.1 step 2 permanently (§9.7 scenario G).

### 9.5 Rate Limiting and Enumeration Privacy

Mirrors 6B's own discipline: `POST .../invitations` does not reveal whether the invitee email already has a platform account (the create flow behaves identically either way from the caller's perspective — `201` in both cases); rate limit 20/hour/org (configurable default, not benchmarked). `GET .../invitations` never exposes another organization's pending invitations (RLS + 404 cross-tenant, §24).

### 9.6 Pre-Acceptance Authorization — RESOLVED This Pass (was a Security Blocker)

**Original finding (prior draft of this document):** an earlier design created the pending-invitation membership row with `status='ACTIVE', accepted_at=NULL`. 6B's multi-organization login-continuation flow (6B §9.3) computes a user's "allowed organizations" via `organization.get_user_organization_ids()` (5B §16.2), whose query is exactly `SELECT organization_id FROM organization.memberships WHERE user_id = $1 AND status = 'ACTIVE'` — it does not filter `accepted_at`. Under the `status='ACTIVE'` pending-placeholder design, an **existing platform user** invited into an *additional* organization would appear in that query's result set — and would pass 6B's `PermissionEvaluationService` step 1 (`membership.status != 'ACTIVE' → DENIED`) — the moment `POST /organizations/{org}/invitations` committed, **before ever completing acceptance.** This was a genuine security blocker, correctly requiring escalation rather than silent documentation.

**Resolution (this pass, no upstream 6B/5B change required):** §9.3 now creates the pending-placeholder row with **`status='SUSPENDED'`** instead of `'ACTIVE'`, disambiguated from a genuinely-suspended (post-acceptance) member purely by `accepted_at IS NULL`. This closes the vulnerability **using only the frozen 3-value enum and 6B's own, unmodified, frozen logic**:

- `organization.get_user_organization_ids()` (5B §16.2) filters `status = 'ACTIVE'` — a `SUSPENDED` pending row is excluded. **Verified against the actual frozen query, not assumed.**
- 6B's `PermissionEvaluationService` step 1 (6B §8): `membership.status != 'ACTIVE' → DENIED` — a `SUSPENDED` pending row fails this check identically to a real suspension. **Verified against the actual frozen pseudocode.**
- 6B's login-continuation flow (6B §9.3): "server loads the user's `ACTIVE` memberships in `ACTIVE` organizations" — a `SUSPENDED` pending row is excluded.

**No path exists, under this corrected design, for an unaccepted invitation to grant tenant access.** This is a schema-free fix — it changes only which of the three *existing* frozen enum values 6C's own invitation-creation use case writes; it fabricates no new status value (`INVITED` is still not used, consistent with the explicit prohibition on doing so) and requires no amendment to 6B or 5B.

**Trade-off introduced by this fix, disclosed:** a pending invitation now shares the `SUSPENDED` DB value with a genuinely-suspended (previously-active) member. This is fully disambiguated everywhere 6C itself renders membership state — via `accepted_at IS NULL` — see §8.1 invariant 4, §8.6, §15.8, §15.12, and §15.40's `membership_status` derivation. §15.12 (`reactivate`) carries a load-bearing guard (`accepted_at IS NOT NULL`) specifically to prevent this shared representation from becoming a *new* access-control bypass (an admin directly "reactivating" a pending invitation instead of the invitee completing token-based acceptance) — see §8.2 invariant 4.

**What remains open (tracked separately, not this section's concern):** the *token-linkage* gap (§9.2 Gap B, DEP-6C-12) affecting resend's ability to invalidate a superseded token. That gap does not permit unauthorized tenant access — it only means an old, valid-but-unnecessary invitation token to *the same, already-intended* organization/role may outlive a resend. It is tracked in §9.7/§27 and is **not** a reason to withhold this section's resolution.

### 9.7 Invitation Atomicity / Multi-Org Scenario Review

| Scenario | Requirement | Outcome under the corrected design |
|---|---|---|
| **A.** Existing user invited to Org B before acceptance | MUST NOT gain authorization to Org B | **CLOSED** (§9.6) — the pending row is `status='SUSPENDED'`, excluded from every 6B access-granting query |
| **B.** Same user has pending invitations to Org A and Org B | Each invitation independently identifiable | **CLOSED for acceptance** — each is its own `membership_id`, and the ACCEPT flow (§9.3.1) resolves the correct one from the client-supplied raw token's cleartext prefix, never from ambiguous server-side state. **NOT closed for server-initiated lookup** (resend starting only from `membership_id`, with no raw token) — cancel doesn't need token lookup at all (§9.4) so B holds fully for cancel; resend's *token-invalidation* guarantee is the part affected by Gap B (DEP-6C-12) |
| **C.** Resend Org A invite | Old Org A token must become unusable; Org B invitation unaffected | **PARTIAL** — Org B is unaffected (✅, separate row, separate token row, nothing in resend touches another membership_id). Old Org A token becoming unusable is **BLOCKED** by DEP-6C-12 (§9.4) |
| **D.** Cancel Org A invite | Org A token becomes unusable; Org B invitation unaffected | **CLOSED** — Org A: the membership-state guard (§9.3.1 step 2) rejects acceptance the instant the row leaves the pending state, independent of any token row's own validity (§9.4). Org B: unaffected (separate row) |
| **E.** Cancel vs. accept race | Exactly one terminal outcome | **CLOSED** — both operations are atomic conditional `UPDATE`s sharing the identical `WHERE status='SUSPENDED' AND accepted_at IS NULL` precondition on the same row (§7.6 CAS); Postgres MVCC guarantees exactly one commits, the other observes the row already in its terminal state and fails (`409`) |
| **F.** Resend vs. accept race | Cannot leave two valid invitation tokens granting *separate* outcomes | **CLOSED for the security-relevant property** — resend never touches the membership row (§9.4), so it cannot race accept for row ownership; once accepted (`accepted_at` set), §9.3.1 step 2 rejects every subsequent presentation of *any* token for that `membership_id`, old or new. **The narrower, non-security-relevant nuance** — a technically-still-valid old token hash may continue to exist in the table post-resend — is the same, already-disclosed Gap B limitation (DEP-6C-12), not a double-acceptance risk |
| **G.** Removed user re-invited | Fresh invitation does not revive old tokens | **CLOSED** — re-invitation always creates a **new** `membership_id` (the old, `REMOVED` row is immutable, 5B ADR-5B-004); any token tied to the old `membership_id` fails §9.3.1 step 2 permanently, since that row can never return to the pending state |

**Summary — corrected this pass (two open items, not one):** the security-critical properties (A, D, E, F's access-control core, G) are fully closed by the corrected design with no upstream dependency. **Two, not one, genuinely open items remain, and neither is "the" sole remaining invitation item:**
- **DEP-6C-12** (Gap B — scenario C, and the narrower half of B/F): `identity.password_reset_tokens` has no durable link from a token to the membership/invitation it belongs to, so `resend` cannot reliably invalidate a superseded token when the invitee holds more than one concurrent pending invitation (§9.2, §9.4).
- **DEP-6C-13** (scenario B's other half, §9.3.2 point 5): no DB constraint prevents two concurrent `POST .../invitations` calls from both inserting a pending row for the same `(organization_id, user_id)` pair.

**Neither DEP-6C-12 nor DEP-6C-13 permits unauthorized tenant access** — both are bounded by the frozen `uq_memberships_active` partial unique index, which guarantees at most one membership per `(organization_id, user_id)` pair can ever reach `ACTIVE` regardless of how many pending rows or valid tokens exist (§9.3.1 step 4). DEP-6C-12 weakens a defense-in-depth revocation guarantee for an already-intended grant; DEP-6C-13 is a data-hygiene/duplicate-email nuisance. Both are tracked independently in §27, not merged or singled out as the one remaining item.

---

## 10. Team Design

### 10.1 Grounding and the Permission Gap

Teams are an **embedded entity of the `Organization` aggregate**, not an independent aggregate (4A §5.1: `"Teams (list[Team] — embedded, bounded, < ~100 per org) ... Team.MemberRefs — references, not embedded Memberships"`) — display/grouping only, no independent permission grants (4A ubiquitous language, §1; OQ-4A-05 confirms Teams are designed display-only for this phase). Backed by `organization.teams` and `organization.team_memberships` (5B §9.8–§9.9, both RLS-enabled).

**Genuine permission-vocabulary gap:** the frozen permission catalog (5B §17.1) has **no `team:*` permission** at all. Per this document's own instruction not to invent a permission silently, this is flagged as **DEP-6C-03** (§27). **Interim, grounded mapping (not fabricated):** because Teams are structurally embedded in the Organization aggregate and DDD's own transaction-boundary note states *"all mutations to the Organization aggregate (including nested ... Teams) are committed in a single database transaction"* (4A §5.1), team mutations are gated by the existing `organization:update` permission — the same permission that governs every other Organization-aggregate-internal mutation. This is recorded as **ADR-6C-04** (§28).

### 10.2 Invariants

- A Team belongs to exactly one organization (`teams.organization_id`, FK).
- Team member must be an `ACTIVE` org member at add-time — enforced by an application-layer check (no cross-table FK from `team_memberships.user_id` to `memberships`, since `team_memberships.user_id` is a logical reference to `identity.users.id`, not to a specific `Membership` row; 5B §9.9).
- A member whose org `Membership` becomes `SUSPENDED`/`REMOVED` is **not** automatically removed from teams by any DB trigger (none exists) — `GET .../teams/{team_id}/members` responses flag such entries with a `membership_status` field so UI can visually distinguish a "stale" team member, and any *new* addition is blocked at the org-membership-status check; a background reconciliation job is not designed here (no Phase 5 job table backs it — see §5, Async job row).
- **Duplicate team membership is prevented by a database-level partial unique index** — `uq_team_memberships_active ON organization.team_memberships (team_id, user_id) WHERE removed_at IS NULL` (5B §13/§33.3, confirmed present in the frozen DDL) — this is the authoritative race-protection mechanism, not an application-layer pre-check. A prior draft of this document incorrectly claimed no such constraint exists and accepted a TOCTOU race as a documented residual risk; that claim is retracted. `POST .../teams/{team_id}/members` maps the resulting `unique_violation` to `409 TEAM_MEMBER_ALREADY_EXISTS` (§18) rather than a generic `500`.
- Archiving a team (`status='ARCHIVED'`) does not cascade-delete `team_memberships` rows — they remain for historical record; `GET .../teams` excludes archived teams by default (`?include_archived=true` to see them).

### 10.3 Endpoints

```
GET    /api/v1/organizations/{organization_id}/teams
POST   /api/v1/organizations/{organization_id}/teams
GET    /api/v1/organizations/{organization_id}/teams/{team_id}
PATCH  /api/v1/organizations/{organization_id}/teams/{team_id}
POST   /api/v1/organizations/{organization_id}/teams/{team_id}/archive
GET    /api/v1/organizations/{organization_id}/teams/{team_id}/members
POST   /api/v1/organizations/{organization_id}/teams/{team_id}/members
DELETE /api/v1/organizations/{organization_id}/teams/{team_id}/members/{user_id}
```

`archive` is an action endpoint (guarded terminal transition, no legal reversal designed — matches 6A §7.6's terminal-status-resource guidance); no `DELETE /teams/{team_id}` is exposed.

---

## 11. User Profile Design

### 11.1 Boundary vs. `GET /api/v1/auth/me`

6B's `/auth/me` (6B §21.20) returns the **`AuthenticationContext`** — subject, role, permissions, session/token metadata (6B §6.1). It is a security/authentication artifact, cached-permission-bearing, and reflects the *currently selected organization*. 6C's `/users/me` is a **different resource entirely**: the platform-global, editable `identity.users` profile row, independent of which organization is currently selected. Neither substitutes for the other; both may be called on the same page load for different purposes.

### 11.2 Editable Fields (narrow, grounded exactly in 5B §9.1)

| Field | Editable via 6C? | Rationale |
|---|---|---|
| `display_name` | **Yes** (`PATCH`) | Ordinary profile field, no security implication |
| `phone_e164` | **Yes** (`PATCH`) — clears `phone_verified_at` on change | No OTP mechanism exists (6B ADR-6B-09) to re-verify; setting it unverified is honest, not a workaround |
| `email` | **No** | Authentication identifier; email-change/re-verification is a credential-adjacent concern 6B's hard boundary already claims (6B §3.1) but did not build an endpoint for — flagged as **DEP-6C-06** (§27), not designed here |
| `password_hash`, `mfa_*`, `failed_login_count`, `last_login_at`, sessions | **Never** | 6B's exclusive domain; structurally absent from every 6C response model (mass-assignment/overposting defense, 6A §22) |
| Timezone/locale preference | **N/A — does not exist** | ADR-5B-006 confirms no `user_preferences` table; not fabricated (§5, §27 DEP-6C-05) |

### 11.3 Endpoints

```
GET   /api/v1/users/me
PATCH /api/v1/users/me
GET   /api/v1/users/me/organizations
```

`GET /users/me/organizations` lists the caller's real `ACTIVE` memberships (5B §35.3 query pattern, reused read-only, `WHERE status='ACTIVE'`) — under the corrected design (§9.6), this query **no longer** includes pending invitations at all, since those now carry `status='SUSPENDED'` and are correctly excluded, exactly like 6B's own login-continuation query. This endpoint's list therefore only ever contains organizations the caller genuinely has access to. A "my pending invitations" inbox view (surfacing invitations addressed *to* the caller, distinct from 6C's own org-admin-facing `GET .../invitations` list of *outgoing* invitations, §9.4) is not designed here — not fabricated. The `membership_status` field on this response is retained for forward compatibility and currently always reports `"ACTIVE"` for every row returned.

### 11.4 File/Media Note — Organization Logo

`organizations.logo_url` (§7.2) is set exclusively via the 6A §29 signed-URL pattern, scoped to this one field — not a new platform-wide media API (§5):

```
POST /api/v1/organizations/{organization_id}/logo/upload-url   → { upload_url, expires_at }
POST /api/v1/organizations/{organization_id}/logo/complete     → validates, sets logo_url server-side
```

Included in the endpoint count (§15) as two of the Organization group's endpoints; full contracts §15.4–§15.5.

---

## 12. Compliance Policy Design

### 12.1 Grounding

`CompliancePolicy` — Organization-context aggregate (4I §7.2, §9.1 row 2), backed by `organization.compliance_policies` (5B §9.13, RLS-enabled). Versioned; only one `status='ACTIVE'` policy per org at a time (partial unique index, 5B §9.13). Governs outbound-call consent/recording/calling-window rules **consumed, read-only, by later Voice/Campaign/CRM phases** — 6C owns the configuration surface, not the enforcement logic (which belongs to those future domains).

### 12.2 Endpoints

```
GET  /api/v1/organizations/{organization_id}/compliance-policy              (current ACTIVE policy)
POST /api/v1/organizations/{organization_id}/compliance-policy              (create a new DRAFT version)
POST /api/v1/organizations/{organization_id}/compliance-policy/{policy_id}/activate
```

- `POST .../compliance-policy` creates a `status='DRAFT'` row (never directly `ACTIVE`) with `version = previous_max_version + 1` — typed fields matching 5B §9.13's own columns exactly (`require_consent_for_outbound`, `required_consent_purposes`, `recording_policy`, `calling_windows`, `holiday_calendar_ref`, `allowed_phone_types`, `max_attempts_per_contact`, `attempt_window_days`, `block_on_policy_failure`, `retention_profile`) — **not** a generic JSON bag; every field is individually typed and validated against the enumerated value sets 5B documents (e.g., `recording_policy ∈ {DISABLED, ENABLED, REQUIRES_CONSENT, REQUIRES_DISCLOSURE}`).
- `POST .../{policy_id}/activate` is the guarded transition (corrected this pass — Blocker 2: `CompliancePolicy` and `Organization` are separate aggregates per 4I §7.2, and 6A §35 authorizes no same-transaction exception for this pair; a prior draft's "TXN2" for the pointer update was still a second, synchronous transaction run in the same request, which does not satisfy 6A §35's actual rule any more than §7.7's original mistake did, §7.7):
  1. **The one synchronous, single-aggregate REQUEST TRANSACTION (`CompliancePolicy` only):** the target `DRAFT` row transitions to `ACTIVE`, and the previously `ACTIVE` policy (if any) transitions to `ARCHIVED` — both rows belong to the same table/aggregate (`organization.compliance_policies`), a legitimate single-aggregate transaction (not a cross-aggregate exception), guarded by the §7.6 CAS pattern. **The `compliance.policy_activated` outbox write within this same transaction is now real, executable SQL — DEP-6C-16 RESOLVED (Revision 6):**
     ```sql
     INSERT INTO audit.domain_event_outbox (event_type, organization_id, aggregate_type, aggregate_id, payload)
     VALUES ('compliance.policy_activated', :organization_id, 'compliance_policy', :policy_id,
             jsonb_build_object('organization_id', :organization_id, 'policy_id', :policy_id, 'version', :version));
     ```
     written in the same transaction as the `compliance_policies` status transitions above, against `audit.domain_event_outbox` (migration `077_5J1.sql`, §7.7). The endpoint's response (`200`) is returned once the `CompliancePolicy` state transition (and this same-transaction outbox insert) commits — this is the complete, authoritative outcome, since the response never depended on the pointer update (point 2) in the first place. **Cache invalidation is synchronous, part of this same request handler, and does not depend on event delivery (unchanged from Revision 5, carried forward through this pass per the explicit constraint that it must never move to the consumer):** immediately after the request transaction commits, the handler synchronously issues `DEL compliance_policy:{organization_id}` (5B §31, 6A §19's write-then-invalidate discipline) before returning `200` — this is ordinary request-time cache invalidation, not consumed from `compliance.policy_activated` or any other event. Canonical sequence: **commit the authoritative `compliance_policies` status transition (+ outbox insert) → synchronously invalidate `compliance_policy:{org_id}` → return `200`.**
  2. **`organizations.compliance_policy_id` is updated asynchronously, event-driven, never synchronously in this request — the ASYNC CONSUMER TRANSACTION:** the `compliance.policy_activated` event (already named in §20, reused here rather than inventing a second event) is relayed via the now-concrete `audit.domain_event_outbox` → `audit.fn_claim_outbox_events()`/`fn_mark_outbox_published()` publisher path (§7.7), then consumed by an Organization-context handler that updates the denormalized pointer in its own transaction (`SET LOCAL app.tenant_id = <organization_id from the event payload>`). This field is a **display/convenience denormalization only** — the authoritative source of truth for "which policy is active" is `organization.compliance_policies.status = 'ACTIVE'` (enforced by 5B §9.13's own partial unique index, `UNIQUE (organization_id) WHERE status = 'ACTIVE'`), which the request transaction above alone already establishes correctly, independent of the pointer. `GET /organizations/{id}/compliance-policy` (§15.28) queries by `status='ACTIVE'` directly, **not** via `organizations.compliance_policy_id` — so the pointer consumer's failure, delay, or temporary absence affects only the freshness of the convenience field on the `Organization` resource (§15.2), never correctness of any read in this document. **Staleness:** a prior draft claimed "the pointer cannot drift more than one activation behind"; that claim remains **retracted** — if the consumer or its infrastructure is unhealthy for a period, the pointer can remain stale for as long as that period lasts, not bounded to "one activation" (the now-durable outbox row means the event itself is never lost — §7.7 — but consumer *processing* health is a separate, ordinary operational concern the outbox's existence does not itself guarantee). The canonical rule, stated precisely instead:
- `organization.compliance_policies.status = 'ACTIVE'` is the **sole authoritative** source of truth for which policy is active — never the pointer.
- `organizations.compliance_policy_id` is **non-authoritative convenience data only**, exposed on the `Organization` resource (§15.2) for display/UX convenience, never used by any read or enforcement path in this document.
- The consumer's update is idempotent (an unconditional `UPDATE organizations SET compliance_policy_id = :new_id WHERE id = :org_id`, safely re-appliable on redelivery) — so **every successfully-processed activation event overwrites the pointer with the value that was current at that event's processing time**; a later activation's own event, once successfully consumed, supersedes whatever the pointer currently holds, regardless of how many prior updates were missed.
- **No read or enforcement path may ever depend on pointer freshness** — this is binding, not merely descriptive: `GET /organizations/{id}/compliance-policy` (§15.28) and any future enforcement consumer must query `compliance_policies.status='ACTIVE'` directly, never dereference the pointer for a correctness-sensitive decision.
- Repair happens via the platform's existing consumer-group retry/redelivery semantics (3A §6.3) once infrastructure is healthy, and via each subsequent activation's own event — not via a dedicated recovery endpoint, since no correctness-sensitive read depends on the pointer being current in the first place.
- **Audit — corrected this pass (Blocker 4, 6A §22's binding rule):** both draft creation and activation are durably audited via `COMPLIANCE_POLICY_UPDATED` (5J §14.3) — 5J provides no finer split between "a draft version was created" and "a version was activated," and reusing the one available, semantically-adequate action for both (the same discipline 6B applied elsewhere, e.g. reusing `ROLE_ASSIGNED` for role-catalog mutations) is a correction of a prior draft's now-retracted choice to leave draft creation unaudited entirely — under 6A §22's unconditional wording, "low-stakes" is not itself a valid reason to skip a durable audit record for a state-changing endpoint. The audit `resource_snapshot` (5B §30's allow-list) includes a `policy_status` field (`"DRAFT"` vs. `"ACTIVE"`) so the two event instances remain distinguishable despite sharing one `action_kind`. Activation's own request handler synchronously invalidates the `compliance_policy:{org_id}` Redis cache (see point 1, above) — this is independent of, and does not wait on, the async consumer transaction's eventual `organizations.compliance_policy_id` pointer update (point 2), which has no cache-correctness implication of its own.

Permission: `compliance:read` / `compliance:manage` (5B §17.1 — exact existing permission strings, `OWNER`/`ADMIN` only per the matrix).

---

## 13. Data Subject Request Design

### 13.1 Grounding

`DataSubjectRequest` — Organization-context aggregate, explicitly named as "Core API"-owned (4I §9.1 row 2, §639). Backed by `organization.data_subject_requests` (5B §9.14, RLS-enabled). Tracks *workflow state only*; the actual erasure/export mechanics execute against each owning schema in later phases (5B §27 — explicitly out of 6C's mechanical scope, though the *request record itself* is 6C's).

### 13.2 Workflow States (5B §27, reused verbatim)

```
RECEIVED → VERIFYING → IN_PROGRESS → COMPLETED
                    ↘ REJECTED
              ↓
           ON_HOLD (legal hold; manual review required)
```

### 13.3 Endpoints

```
POST /api/v1/organizations/{organization_id}/data-subject-requests
GET  /api/v1/organizations/{organization_id}/data-subject-requests
GET  /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}
POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/verify
POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/hold
POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/complete
POST /api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/reject
```

- `POST .../data-subject-requests` requires `subject_contact_id` OR `subject_email` OR `subject_phone_e164` (5B ADR-5B-007 — mirrored exactly as request-body validation, `422` if none present).
- **`verify`/`hold` — RESOLVED this pass (Revision 6), previously reclassified as a genuine gap (Blocker 4).** A prior draft classified these as "deliberate telemetry-only, not a gap"; that was corrected to a genuine, tracked audit-vocabulary gap (DEP-6C-14) once 6A §22's binding rule was applied strictly. **This pass closes it**: `DATA_SUBJECT_REQUEST_VERIFYING`/`DATA_SUBJECT_REQUEST_ON_HOLD` were added to 5J §14.3's governed vocabulary by the controlled Phase 5.x amendment, named to match `data_subject_requests.status`'s own `VERIFYING`/`ON_HOLD` values exactly (the same naming convention already used by the pre-existing `..._RECEIVED`/`..._COMPLETED`/`..._REJECTED` triplet) — no reuse of `DATA_SUBJECT_REQUEST_RECEIVED` was needed, avoiding the misrepresentation the original gap analysis correctly flagged. `NFR-SEC-004`/6A §22 compliance is now **fully met** for both transitions.
- `complete`/`reject` map to `DATA_SUBJECT_REQUEST_COMPLETED`/`DATA_SUBJECT_REQUEST_REJECTED` (5J §14.3 — exact matches); `create` maps to `DATA_SUBJECT_REQUEST_RECEIVED` (exact match). No audit-vocabulary gap exists for this resource.
- Permission: `data_subject:manage` (5B §17.1) gates **every** operation including read/list — the catalog defines no separate `data_subject:read`; this is a deliberate coarse grant already present in the frozen catalog, not an invented restriction (`OWNER`/`ADMIN` only per the matrix — the most sensitive resource in 6C's surface, per 4I §1261: "highest sensitivity; access restricted to a dedicated permission").
- `export_storage_ref` (5B §9.14) is populated by a future phase's export mechanism (not built here — no generic export-job resource exists yet, §5) and, when present, is exposed only as a short-TTL signed download URL per 6A §29 — never inlined.

---

## 14. Data Exposure / PII Matrix

| Endpoint group | Field | Classification | Notes |
|---|---|---|---|
| Organization | `name`, `slug`, `timezone`, `locale`, `website`, `logo_url` | `VISIBLE_TO_ORG_MEMBER` | Non-sensitive profile data |
| Organization | `legal_name`, `region_ref`, `data_residency_profile` | `VISIBLE_TO_ORG_ADMIN` | Business/contractual detail, not every member's concern |
| Organization | `owner_user_id`, `compliance_policy_id`, `tax_profile_id`, `billing_account_id` | `VISIBLE_TO_ORG_ADMIN` | Internal linkage, not raw secrets, but not a VIEWER's business |
| Members | `display_name`, `role`, `status` | `VISIBLE_TO_ORG_MEMBER` | Needed for collaboration UI |
| Members | `email` | `VISIBLE_TO_ORG_ADMIN` | `pii:email` (5B §28) — matches the frozen role-permission matrix, where only OWNER/ADMIN have `member:invite`/`member:remove`; VIEWER/MEMBER see `member:read` only, and this document restricts email specifically to ADMIN+ rather than exposing it to every member by default (least privilege, per the task's explicit instruction not to auto-expose email to every member) |
| Members | `invited_by`, `invited_at`, `accepted_at`, `removed_by`, `removed_at` | `VISIBLE_TO_ORG_ADMIN` | Membership-lifecycle audit-adjacent detail |
| Teams | all fields | `VISIBLE_TO_ORG_MEMBER` | Display/grouping only, no sensitivity |
| Compliance Policy | all fields | `VISIBLE_TO_ORG_ADMIN` | Gated by `compliance:read`, which only ADMIN/OWNER hold |
| Data Subject Request | `subject_email`, `subject_phone_e164` | `PLATFORM_ONLY`-adjacent — `VISIBLE_TO_ORG_ADMIN` only, and only because `data_subject:manage` is ADMIN/OWNER-only | `pii:email`/`pii:phone` (5B §28); highest sensitivity in this document's surface (4I §1261) |
| User Profile | `display_name`, `phone_e164` | `PUBLIC_TO_SELF` (own `/users/me`); `display_name` also `VISIBLE_TO_ORG_MEMBER` via the members list | — |
| User Profile | `email` | `PUBLIC_TO_SELF`; `VISIBLE_TO_ORG_ADMIN` via members list only | Not exposed to ordinary members (above) |
| — | `password_hash`, `mfa_secret_ref`, `refresh_token_hash`, `access_token_jti`, `key_hash`, `token_hash` | `NEVER_EXPOSE` | Structurally absent from every 6C response model (6A §22, mass-assignment/output-filtering discipline) |

---

## 15. Endpoint Contracts

### 15.0 Shared Template

Every endpoint below instantiates: Purpose, Method & Path, API surface, Authentication, Authorization, Actor, Tenant Scope, Path/Query Params, Headers, Request Schema, Validation, Response, Errors, Rate Limit, Idempotency, Latency, Database, Cache, RLS, Audit, Domain Event, Observability, Side Effects, Concurrency, Security — using 6A's `{data, meta}`/`{error}` envelope, error object shape, and `request_id` propagation throughout (6A §10, §24, §25). Every rate limit is a **configurable default**, not a benchmark. Every latency figure is a **TARGET**, not a MEASURED number. Tenant scope for every endpoint below (unless stated otherwise) is: `organization_id` resolved from the caller's JWT/API-key per 6B §9 — the path's `{organization_id}` is cross-checked against it and a mismatch yields `404 RESOURCE_NOT_FOUND` (never `403`, per 6B §9.2/§22 non-disclosure discipline, applied identically here).

---

### 15.1 `POST /api/v1/organizations`

- **Purpose:** Create a new organization with the caller as its first `OWNER`.
- **API surface:** Public.
- **Authentication:** Access token (6B). **No API key** — an API key is org-scoped and cannot exist before the org does.
- **Authorization:** No RBAC permission — gated only by "caller is an authenticated, `ACTIVE` user" (there is no organization context yet to check a permission against).
- **Actor:** `USER`.
- **Tenant Scope:** None (pre-tenant operation — this is the one 6C endpoint that creates tenant context rather than consuming it).
- **Path/Query Params:** None.
- **Headers:** Standard bearer auth; `Idempotency-Key` **required** (creating a duplicate organization from a retried request has real consequences).
- **Request Schema:** `{ "name": "...", "slug": "...", "country_code": "IN", "currency": "INR", "timezone": "Asia/Kolkata", "locale": "en-IN", "phone_country": "IN", "primary_language": "en-IN", "supported_languages": ["en-IN","ta-IN"] }` — `country_code`/`currency` required (5B §24, no column default, explicit-is-better-than-implicit); the rest default per 5B §24's India-first values if omitted.
- **Validation:** `slug` global uniqueness (`409 STATE_CONFLICT`); `country_code`/`currency` whitelist (`422`, corrected this pass — Cleanup 1); `timezone`/`locale` per 5B §23.2 (`422`).
- **Response `201`:** `{ "data": { "id", "name", "slug", "status": "ACTIVE", "owner_user_id": "<caller>", ...profile fields } }`, `Location` header set. The prior draft's `compliance_policy_seeded: true|false` field is **removed and stays removed** — the response is returned once the request transaction (org + owner membership + outbox event, §7.7) commits, before `CompliancePolicy` seeding has necessarily even been attempted (it is architecturally, and now also durably, asynchronous, §7.7); a field the response cannot honestly know the value of at response time must not exist.
- **Errors:** `400 VALIDATION_ERROR` (malformed request body); `422 VALIDATION_ERROR` (invalid `country_code`/`currency`/`timezone`/`locale` value — well-formed request, semantically invalid, per 6A §7.4, corrected this pass); `409 STATE_CONFLICT` (slug collision).
- **Rate Limit:** 5/day/user (configurable default).
- **Idempotency:** Required, per 6A §16. **Simplified this pass:** since the response no longer carries any `CompliancePolicy`-derived field, a same-key retry simply replays the original `201` with no staleness concern (the prior pass's disclosed limitation here no longer applies).
- **Latency:** Standard (Tier A) — a single short request transaction (three single-row inserts: two aggregate rows plus the outbox event row, §22); `CompliancePolicy` seeding is fully asynchronous and contributes **zero** latency to this endpoint's response — the response was never made to wait on it (§7.7).
- **Database:** **Request transaction only (6A-§35-authorized atomic pair, plus the same-transaction outbox insert):** `organization.organizations` (insert), `organization.memberships` (insert, `role_id=OWNER`), `audit.domain_event_outbox` (insert, `event_type='organization.created'` — DEP-6C-16 RESOLVED, migration `077_5J1.sql`, §7.7). `organization.compliance_policies` is **never** written by this endpoint's own request handler under any circumstance — it is written later, in its own async consumer transaction, once the event is relayed (§7.7).
- **Cache:** None (nothing to invalidate for a brand-new org).
- **RLS:** `organizations` has no self-referential RLS (5B §16.4 — tenant root). `memberships` **is** `ENABLE + FORCE ROW LEVEL SECURITY` with `WITH CHECK` on `INSERT` (5B §16.4) — never bypassed. `audit.domain_event_outbox` carries **no** RLS (by design, migration `077_5J1.sql` header comment — same precedent as `identity.sessions`, 5B §16.3); tenant-forgery on its `INSERT` is instead guarded structurally by `audit.fn_outbox_tenant_check()` (a `BEFORE INSERT` trigger). `app.tenant_id` is `SET LOCAL`-established **immediately after the `organizations` INSERT returns its `id`**, within the request transaction — a prior draft said this happens "at the start of the transaction," which is impossible since the id does not exist until that INSERT returns (§7.7). The async consumer transaction independently `SET LOCAL`s the same `organization_id` (taken from the event payload) at the start of its own transaction.
- **Audit:** `ORGANIZATION_CREATED` (5J §14.3, exact match), synchronous, written on the request transaction's commit.
- **Domain Event:** `organization.created` — durably persisted via `audit.domain_event_outbox` in the same transaction as the two domain inserts above (DEP-6C-16 RESOLVED), then relayed to Redis Streams (3A §6.3) by the platform's existing outbox-publisher worker via `audit.fn_claim_outbox_events()`/`fn_mark_outbox_published()` — at-least-once delivery, never exactly-once; the Compliance-context consumer's own insert remains required to be idempotent (§7.7 point 4) regardless. No webhook — internal event only, per 6A §28.3's three-mechanism distinction.
- **Observability:** `org_created_total`; `compliance_policy_seed_consumer_failures_total` (owned by the Compliance-context consumer — tracks event-processing failures that would otherwise only surface via the manual-recovery path, §7.7).
- **Side Effects:** Owner membership created (request transaction, guaranteed, synchronous). Default compliance policy created — architecturally and now durably event-driven (§7.7); the manual recovery path (§7.7) remains available for any period the automated path is degraded. Never a side effect of this endpoint's own request transaction, regardless.
- **Concurrency:** N/A (creation, nothing to race against except the slug-uniqueness constraint, DB-enforced). The asynchronous consumer's own idempotency (§7.7 point 4) is what protects against duplicate/replayed event delivery — not a concern of this endpoint's own request handler.
- **Security:** `country_code`/`currency` are never defaulted silently server-side beyond what 5B §24 already documents as the *application's* India-first fallback — the endpoint requires them explicitly in the request rather than relying on a column `DEFAULT`, consistent with 5B's own stated rationale (a missing value is a logic error, not a fallback situation).

### 15.2 `GET /api/v1/organizations/{organization_id}`

- **Purpose:** Retrieve the current organization's profile.
- **API surface:** Public. **Authentication:** Access token or API key. **Authorization:** `organization:read` (all 5 roles hold it, 5B §17.2). **Actor:** `USER` or `API_KEY`. **Tenant Scope:** Path `organization_id`, cross-checked.
- **Path Params:** `organization_id`. **Query Params:** None. **Headers:** Standard.
- **Request Schema:** N/A. **Validation:** N/A.
- **Response `200`:** Full profile object (§7.2 fields + `id`, `status`, `owner_user_id`, `country_code`, `currency`, `created_at`, `updated_at`). `ETag` header present (weak, `hash(id, updated_at)`, per 6A ADR-6A-08).
- **Errors:** `401`; `404` (cross-tenant or nonexistent — indistinguishable).
- **Rate Limit:** 300/min/user. **Idempotency:** N/A (GET). **Latency:** Fast (Tier A, cache-hit path where the `localization:{org_id}` cache is warm for the localization subset; the full profile read still goes to DB — see Cache row).
- **Database:** `organization.organizations`, single `WHERE id = $1` lookup (no RLS applies to this table itself, 5B §16.4 — the API layer's own ownership check via the resolved membership is the defense here, consistent with 6A §22's IDOR discipline).
- **Cache:** `localization:{org_id}` (5B §31, 15-min TTL) covers only the localization subset of fields; the full-resource read is not cached beyond HTTP `ETag`/conditional-GET.
- **RLS:** N/A (organizations table). **Audit:** Not audited (read). **Domain Event:** None.
- **Observability:** Standard latency histogram.
- **Side Effects:** None. **Concurrency:** N/A. **Security:** Response model strips `compliance_policy_id`/`tax_profile_id`/`billing_account_id` for actors below `organization:update`... actually these are visible per §14's `VISIBLE_TO_ORG_ADMIN` classification — enforced by a second, narrower response model for non-admin roles (field-level redaction, not a second endpoint).

### 15.3 `PATCH /api/v1/organizations/{organization_id}`

- **Purpose:** Update organization profile/settings fields (§7.2 allow-list).
- **API surface:** Public. **Authentication:** Access token. **Authorization:** `organization:update` (OWNER/ADMIN only, 5B §17.2). **Actor:** `USER`. **Tenant Scope:** Path `organization_id`, cross-checked.
- **Path Params:** `organization_id`. **Headers:** `If-Match` (ETag, optional but recommended, 6A ADR-6A-08).
- **Request Schema:** Any subset of §7.2's allow-list; `extra="forbid"` rejects any other field including `currency`/`country_code`/`status`/`owner_user_id` with `422 VALIDATION_ERROR` (not merely relying on the DB trigger for `currency`).
- **Validation:** Per-field, §7.2. `slug` uniqueness → `409 STATE_CONFLICT`.
- **Response `200`:** Updated profile object. **Errors:** `400` (malformed body); `422` (forbidden-field or invalid-value mutation attempt, corrected this pass — Cleanup 1); `403`; `404`; `409` (slug collision); `412` (`If-Match` mismatch).
- **Rate Limit:** 30/hour/org. **Idempotency:** Naturally idempotent (PATCH, 6A §7.3) — no `Idempotency-Key`. **Latency:** Standard.
- **Database:** `organization.organizations` (update, single-row).
- **Cache:** `localization:{org_id}` invalidated on any localization-field change; `compliance_policy:{org_id}` unaffected.
- **RLS:** N/A. **Audit:** `ORGANIZATION_UPDATED` (exact match), payload = `changed_fields` list only (no PII, matches 5B §30's documented allow-list).
- **Domain Event:** `organization.updated` (internal; consumed by future Voice/Campaign phases needing fresh localization/timezone context — eventual, per 4G §12 lag targets reused from 6A §35).
- **Observability:** Standard. **Side Effects:** None beyond the row update. **Concurrency:** Weak ETag (6A ADR-6A-08) — two admins editing simultaneously: second write's `If-Match` fails `412`, forcing a re-read.
- **Security:** `currency` change attempt returns `422` before ever reaching the DB trigger — an honest client-facing error, not a generic `500` from a caught trigger exception.

### 15.4 `POST /api/v1/organizations/{organization_id}/logo/upload-url`

- **Purpose:** Obtain a presigned upload URL for the organization's logo image.
- **API surface:** Public. **Authentication:** Access token. **Authorization:** `organization:update`. **Actor:** `USER`. **Tenant Scope:** Path, cross-checked.
- **Request Schema:** `{ "content_type": "image/png", "max_size_bytes": 2097152 }` (2MB ceiling, configurable). **Validation:** `content_type ∈ {image/png, image/jpeg, image/webp}`.
- **Response `200`:** `{ "upload_url": "...", "expires_at": "<now+15min>" }` — reuses 6A §29's pattern exactly (S3 presigned PUT, 15-min expiry).
- **Errors:** `400`; `403`. **Rate Limit:** 10/hour/org. **Idempotency:** N/A (no durable state change yet). **Latency:** Fast.
- **Database:** None yet (no row created — `logo_url` is set only on `complete`, §15.5). **Cache:** None. **Audit:** Not audited (no state change). **Security:** Content-type/size enforced by the S3 policy embedded in the URL, not client honesty (6A §29).

### 15.5 `POST /api/v1/organizations/{organization_id}/logo/complete`

- **Purpose:** Finalize a logo upload, setting `logo_url` server-side.
- **API surface:** Public. **Authentication:** Access token. **Authorization:** `organization:update`. **Actor:** `USER`. **Tenant Scope:** Path, cross-checked.
- **Response `200`:** `{ "logo_url": "https://..." }`. **Errors:** `400` (magic-number content-type mismatch); `404` (no pending upload).
- **Rate Limit:** 10/hour/org. **Latency:** Standard (magic-number re-verification, 6A §29). **Database:** `organization.organizations` (update `logo_url`). **Audit:** `ORGANIZATION_UPDATED` (`changed_fields: ["logo_url"]`). **Security:** Actual bytes' magic number re-verified server-side before `logo_url` is set — matches 6A §29's malware/content-type re-verification step exactly (no dedicated scan job exists for this narrow, low-risk field; a full scan pipeline is not warranted for a small logo image and is not designed here).

### 15.6 `POST /api/v1/organizations/{organization_id}/suspend`

- **Purpose:** Self-service temporary suspension of the organization (§7.5, ADR-6C-01).
- **API surface:** Public. **Authentication:** Access token. **Authorization:** `organization:suspend` (OWNER only, 5B §17.2 — the frozen matrix's actual grant, not ADMIN). **Actor:** `USER`. **Tenant Scope:** Path, cross-checked.
- **Request Schema:** `{ "reason": "..." }` (min length enforced, mirrors 6B's break-glass justification pattern for a consequential action). **Validation:** Current status must be `ACTIVE`.
- **Response `200`:** Updated org object, `status: "SUSPENDED"`. **Errors:** `403`; `404`; `409 STATE_CONFLICT` (not currently `ACTIVE`).
- **Rate Limit:** 5/day/org. **Idempotency:** Naturally idempotent via the `409` on retry (no `Idempotency-Key`). **Latency:** Standard.
- **Database:** `organization.organizations` — atomic conditional `UPDATE ... WHERE status='ACTIVE' RETURNING *` (§7.6 CAS). **Cache:** `localization:{org_id}` and `compliance_policy:{org_id}` invalidated (org-suspended state should not be served stale). **Audit:** `ORGANIZATION_SUSPENDED` (exact match), synchronous. **Domain Event:** `organization.suspended`.
- **Security:** A suspended org's members cannot authenticate into it going forward per 4A's business rule (§7.1) — enforced by 6B's own `PermissionEvaluationService` step 2 (organization.status != 'ACTIVE' → DENIED, 6B §8), not re-implemented here; 6C only flips the status.
- **Concurrency:** CAS, no lock.

### 15.7 `POST /api/v1/organizations/{organization_id}/cancel`

- **Purpose:** Terminal, self-service closure of the organization.
- **API surface:** Public. **Authentication:** Access token. **Authorization:** `organization:delete` (OWNER only, 5B §17.2). **Actor:** `USER`. **Tenant Scope:** Path, cross-checked.
- **Request Schema:** `{ "reason": "...", "confirm_slug": "<must equal the org's current slug>" }` — a lightweight "type the slug to confirm" guard for an irreversible action, matching the seriousness 6A §7.6 assigns to terminal-status resources.
- **Validation:** `confirm_slug` must match exactly (`422 VALIDATION_ERROR` otherwise — well-formed request, semantically invalid value, per 6A §7.4, corrected this pass — Cleanup 1); current status must be `ACTIVE` or `SUSPENDED` (both legal per 4A §5.1 invariant 3).
- **Response `200`:** Updated org object, `status: "CANCELLED"`. **Errors:** `422` (confirm_slug mismatch); `403`; `404`; `409 STATE_CONFLICT` (already `CANCELLED`).
- **Rate Limit:** 3/day/org. **Idempotency:** Naturally idempotent via `409` on retry. **Latency:** Standard.
- **Database:** Atomic conditional `UPDATE ... WHERE status IN ('ACTIVE','SUSPENDED') RETURNING *`. **Cache:** Full invalidation of every org-scoped cache key. **Audit:** `ORGANIZATION_CANCELLED` (5J §14.3 — added by the Revision 6 controlled Phase 5.x amendment; **DEP-6C-07 RESOLVED**, §27) — Category A, exact match, durable, synchronous. **Domain Event:** `organization.cancelled`.
- **Side Effects:** Downstream billing/subscription closure is **not** performed by this endpoint (Billing is a later phase, out of scope) — this is disclosed, not silently assumed to cascade; flagged as **DEP-6C-08** (§27).
- **Security:** `DELETE /api/v1/organizations/{organization_id}` returns `405 Method Not Allowed` (6A §7.6) directing callers here.
- **Concurrency:** CAS, no lock.

### 15.8 `GET /api/v1/organizations/{organization_id}/members`

- **Purpose:** List organization members (including pending invitations).
- **API surface:** Public. **Authentication:** Access token or API key. **Authorization:** `member:read` (all roles, 5B §17.2). **Actor:** `USER`/`API_KEY`. **Tenant Scope:** Path, cross-checked.
- **Query Params:** `cursor`, `limit` (default 25, max 100, 6A §14.3); `status` filter (`active`|`pending`|`suspended`, allow-listed, 6A §15).
- **Response `200`:** `{ "data": [ { "id", "user_id", "display_name", "email" (ADMIN+ only, §14), "role", "status", "invited_at", "accepted_at", "membership_status": "ACTIVE"|"PENDING_ACCEPTANCE"|"SUSPENDED" }, ... ], "meta": { "pagination": {...} } }`. `membership_status` is **derived**, not a raw DB column, per §8.1a's canonical state table: `status='ACTIVE'` → `"ACTIVE"`; `status='SUSPENDED' AND accepted_at IS NULL` → `"PENDING_ACCEPTANCE"`; `status='SUSPENDED' AND accepted_at IS NOT NULL` → `"SUSPENDED"` (corrected this pass — a prior draft derived `"PENDING_ACCEPTANCE"` from `status='ACTIVE' AND accepted_at IS NULL`, which was part of the now-retracted, insecure design; see §9.6).
- **Errors:** `401`; `403`; `422` (invalid filter/sort field). **Rate Limit:** 60/min. **Latency:** Fast (indexed, `idx_memberships_user_active`-adjacent tenant-first index per 5B §15.6).
- **Database:** `organization.memberships JOIN identity.users JOIN organization.roles` — mirrors 5B §35.5's exact reference query, extended with cursor pagination (6A §14) in place of the reference query's simple `ORDER BY`. **Cache:** None (membership lists are too write-frequent to cache safely; RBAC's own 5-min permission cache is unaffected). **RLS:** `rls_memberships_tenant` (5B §16.4) scopes the join automatically. **Audit:** Not audited (read).
- **Security:** `email` field present only when the caller holds `member:invite` or `member:remove` (i.e., ADMIN/OWNER) — a second, narrower response model for MEMBER/VIEWER/BILLING_ADMIN (§14).
- **Concurrency:** N/A.

### 15.9 `GET /api/v1/organizations/{organization_id}/members/{member_id}`

Same authorization/tenant/response shape as §15.8, single-resource form. **Errors add:** `404` (member not in this org — cross-tenant, or nonexistent, indistinguishable). **Latency:** Fast. **Rate Limit:** 120/hour.

### 15.10 `POST /api/v1/organizations/{organization_id}/members/{member_id}/role`

- **Purpose:** Reassign a member's role (§8.4 guards). **API surface:** Public. **Authentication:** Access token. **Authorization:** `role:manage` (corrected this pass — 5B §37.6 names this permission explicitly as the frozen design's own privilege-escalation control for role assignment; a prior draft's `member:invite` mapping and its DEP-6C-09 entry are retracted for this endpoint, §27). **Actor:** `USER`. **Tenant Scope:** Path, cross-checked.
- **Request Schema:** `{ "role_id": "..." }`. **Validation:** §8.4's two guard rules.
- **Response `200`:** Updated member object. **Errors:** `403`; `404`; `409 ROLE_CHANGE_NOT_ALLOWED` (OWNER-involving attempt); `409 STATE_CONFLICT` (membership not `ACTIVE`).
- **Rate Limit:** 30/hour/org. **Idempotency:** Naturally idempotent (same input → same result). **Latency:** Standard.
- **Database:** Atomic conditional `UPDATE organization.memberships` (§8.4). **Cache:** `rbac:permissions:{org_id}:{user_id}` invalidated synchronously for the affected user (6B §23/§8 — cross-referencing 6B's own cache-invalidation contract, not re-implementing it). **Audit:** `MEMBER_ROLE_CHANGED` (exact match, payload `old_role`/`new_role`). **Domain Event:** `member.role_changed`.
- **Security:** Cannot self-elevate — the caller cannot assign a role to their own membership beyond what their current permission already allows to grant (ordinary RBAC evaluation applies to the target as much as the actor). **Concurrency:** CAS.

### 15.11 `POST /api/v1/organizations/{organization_id}/members/{member_id}/suspend`

- **Purpose:** Suspend a member's access without removing them. **Authorization:** `member:suspend` (OWNER/ADMIN, exact match). **Request:** `{ "reason": "..." }`.
- **Validation/Guard:** Last-active-OWNER protection (§16.2 pattern). **Response `200`.** **Errors:** `403`; `404`; `409 LAST_OWNER_PROTECTED`; `409 STATE_CONFLICT`.
- **Rate Limit:** 30/hour/org. **Database:** CAS `UPDATE ... SET status='SUSPENDED'`. **Cache:** RBAC permission cache invalidated for the affected user. **Audit:** `MEMBER_SUSPENDED` (exact match). **Domain Event:** `member.suspended`. **Concurrency:** CAS.

### 15.12 `POST /api/v1/organizations/{organization_id}/members/{member_id}/reactivate`

- **Purpose:** Restore a genuinely-suspended member — never a pending invitation (see the guard below). **Authorization:** `member:suspend` (unchanged by this pass's corrections — reactivation remains the natural inverse of suspend and reuses its permission; §27 DEP-6C-09 now covers only this narrower interim mapping, after the role-assignment retraction).
- **Validation/Guard (corrected this pass — security-critical):** `WHERE status='SUSPENDED' AND accepted_at IS NOT NULL`. The `accepted_at IS NOT NULL` clause is **load-bearing**: under the corrected invitation design (§9.3, §9.6), a pending invitation also has `status='SUSPENDED'` (with `accepted_at IS NULL`) — without this clause, this endpoint could be misused to directly activate a still-pending invitation, granting the invitee organization access without them ever presenting a valid invitation token, bypassing §9.3.1's entire acceptance flow. A request targeting a pending (`accepted_at IS NULL`) row is rejected `409 STATE_CONFLICT` with `error.details.current_state = "PENDING_ACCEPTANCE"`, distinct from the ordinary `409` for a non-`SUSPENDED` row.
- **Response `200`.** **Errors:** `403`; `404`; `409 STATE_CONFLICT` (not suspended, or is a pending invitation).
- **Rate Limit:** 30/hour/org. **Database:** CAS `UPDATE ... SET status='ACTIVE' WHERE status='SUSPENDED' AND accepted_at IS NOT NULL`. **Audit:** `MEMBER_REACTIVATED` (5J §14.3 — added by the Revision 6 controlled Phase 5.x amendment; **DEP-6C-10 RESOLVED**, §27) — Category A, exact match, durable, synchronous. **Domain Event:** `member.reactivated`.

### 15.13 `POST /api/v1/organizations/{organization_id}/members/{member_id}/remove`

- **Purpose:** Admin-initiated permanent removal. **Authorization:** `member:remove` (exact match, OWNER/ADMIN). **Guard:** last-active-OWNER protection (§16.2).
- **Response `204`.** **Errors:** `403`; `404`; `409 LAST_OWNER_PROTECTED`; `409 STATE_CONFLICT`.
- **Rate Limit:** 30/hour/org. **Database:** CAS `UPDATE ... SET status='REMOVED', removed_at=now(), removed_by=:actor`. **Cache:** RBAC cache invalidated for the removed user; their outstanding sessions are **not** force-revoked by this endpoint (that is 6B's `PlatformAdminOnly` revoke-all mechanism, out of 6C's authority — flagged as an observed, disclosed interaction gap rather than silently assumed to cascade: a removed member's existing access token remains valid for its natural ≤15-minute lifetime, same bounded trade-off 6B already accepts elsewhere, 6B §12.4). **Audit:** `MEMBER_REMOVED` (exact match). **Domain Event:** `member.removed`.

### 15.14 `POST /api/v1/organizations/{organization_id}/members/me/leave`

- **Purpose:** Self-initiated departure (§8.6). **Authorization:** None beyond an `ACTIVE` membership (self-scoped). **Guard:** last-active-OWNER protection — an OWNER must transfer ownership first (`409 LAST_OWNER_PROTECTED`, message directs to `POST .../ownership/transfer`).
- **Response `204`.** **Errors:** `409 LAST_OWNER_PROTECTED`; `409 STATE_CONFLICT`. **Rate Limit:** 10/day/user. **Database/Cache:** Same as §15.13, `removed_by = caller`. **Audit:** `MEMBER_REMOVED` (actor differentiates, §8.6). **Domain Event:** `member.left`.

### 15.15 `POST /api/v1/organizations/{organization_id}/ownership/transfer`

Full mechanism: §8.5. **Authorization:** `organization:update` **and** the caller's own membership must currently hold `OWNER` (identity-bound invariant, not permission-string-expressible alone). **Request:** `{ "target_member_id": "..." }`. **Response `200`:** both updated member objects. **Errors:** `403` (not the current OWNER); `404`; `409 STATE_CONFLICT` (target not `ACTIVE`). **Rate Limit:** 3/day/org (deliberately conservative — highest-consequence membership action). **Idempotency:** `Idempotency-Key` supported (irreversible, real-world consequence). **Latency:** Standard. **Database:** Two-row same-transaction CAS (§8.5). **Cache:** RBAC permission caches invalidated for both affected users. **Audit:** `MEMBER_ROLE_CHANGED` × 2 (adequate mapping, §5). **Domain Event:** `ownership.transferred`.

### 15.16 `POST /api/v1/organizations/{organization_id}/invitations`

Full mechanism: §9.3, failure-mode review §9.3.2. **Authorization:** `member:invite` (exact match). **Request:** `{ "email": "...", "role_id": "..." }`. **Validation:** `role_id` not `OWNER`; email format. **Response `201`** (fresh invite — new membership row created) **or `200`** (idempotent re-invite — an existing pending row for this `(org, user)` with the same `role_id` was found and reissued a fresh token, §9.3.2 point 2): `{ "member_id", "email", "role", "invited_at", "expires_at" }` (never the raw token — it is delivered out-of-band via email, a notification concern outside this document). **Errors:** `403`; `409 MEMBER_ALREADY_EXISTS`; `409 INVITATION_ALREADY_PENDING` (only when a pending row exists with a **different** `role_id` than requested, §9.3). **Rate Limit:** 20/hour/org. **Idempotency:** `Idempotency-Key` supported (6A §16) **in addition to** the endpoint's own same-parameters idempotent-re-invite behavior (§9.3.2) — the `Idempotency-Key` mechanism protects a byte-identical retried request from being reprocessed at all; the `(org, user, role)`-based re-invite logic separately protects a *new* request carrying the same intent after the original attempt's outcome was never observed by the client. **Latency:** Standard. **Database:** §9.3's multi-step sequence (not single-transaction across `identity.users` + `organization.memberships` + `identity.password_reset_tokens` — each insert is its own short transaction in sequence, since 6A §35's approved same-transaction exception list does not name this combination). **Partial-failure recovery:** fully self-healing for sequential retries (§9.3.2 points 1–3); a narrow, disclosed concurrent-duplicate-pending-row race remains for genuinely simultaneous requests (§9.3.2 point 5, DEP-6C-13) — contained, not a security gap, by `uq_memberships_active` at acceptance time. **Audit:** `MEMBER_INVITED` (both the `201` and `200` paths). **Domain Event:** `member.invited`.

### 15.17 `GET /api/v1/organizations/{organization_id}/invitations`

List pending (`status='SUSPENDED' AND accepted_at IS NULL`, per §8.1a — corrected this pass; a prior draft incorrectly wrote `status='ACTIVE'` here) memberships. **Authorization:** `member:invite` (only inviters see the pending list — narrower than `member:read`, a deliberate choice since a pending invitee's email is otherwise-restricted PII per §14). **Response:** cursor-paginated list, same shape as §15.16's creation response per row. **Rate Limit:** 60/min.

### 15.18 `POST /api/v1/organizations/{organization_id}/invitations/{membership_id}/resend`

§9.4. **Authorization:** `member:invite`. **Design contract:** issues a fresh, working invitation token for the given `membership_id`. **Current implementability:** the accompanying "old token becomes unusable" guarantee is **BLOCKED** by Gap B / **DEP-6C-12** (§9.2, §9.4, §27) whenever the invitee has another concurrent pending invitation — this document does not claim the guarantee holds unconditionally. **Errors:** `404` (not pending); `409 STATE_CONFLICT` (already accepted). **Rate Limit:** 5/hour per invitation (distinct from the org-wide invite-creation limit, preventing email-bombing a single invitee). **Idempotency:** Not required (each call intentionally issues a fresh token). **Audit:** `MEMBER_INVITED`.

### 15.19 `POST /api/v1/organizations/{organization_id}/invitations/{membership_id}/cancel`

§9.4. **Authorization:** `member:invite`. **Fully implementable today — no dependency** (§9.4: safety comes from the membership-state guard, §9.3.1 step 2, not from locating/invalidating a `password_reset_tokens` row). **Response `204`.** **Errors:** `404`; `409 STATE_CONFLICT` (already accepted). **Rate Limit:** 30/hour/org. **Audit:** `MEMBER_REMOVED`.

### 15.20–15.27 Teams (8 endpoints)

All gated by `organization:update` (§10.1, ADR-6C-04) except reads, which use `organization:read` (broader — matches the read/write asymmetry pattern already established for `role:read`/`role:manage` in 6B §20.6).

| # | Endpoint | Auth | Request | Response | Errors | Audit | Notes |
|---|---|---|---|---|---|---|---|
| 15.20 | `GET .../teams` | `organization:read` | — | Paginated list, `status` filter (active/archived) | `401`/`403` | none (read) | Fast tier |
| 15.21 | `POST .../teams` | `organization:update` | `{"name","description"}` | `201`, team object | `403`/`409` (dup name) | `TEAM_CREATED` (5J §14.3, Revision 6 amendment) | `Idempotency-Key` supported |
| 15.22 | `GET .../teams/{team_id}` | `organization:read` | — | `200`, team object | `404` | none | Fast |
| 15.23 | `PATCH .../teams/{team_id}` | `organization:update` | `{"name"?,"description"?}` | `200` | `403`/`404`/`412` | `TEAM_UPDATED` (5J §14.3, Revision 6 amendment) | Weak ETag concurrency |
| 15.24 | `POST .../teams/{team_id}/archive` | `organization:update` | — | `200`, `status:"ARCHIVED"` | `403`/`404`/`409` | `TEAM_ARCHIVED` (5J §14.3, Revision 6 amendment) | CAS transition |
| 15.25 | `GET .../teams/{team_id}/members` | `organization:read` | — | list, each with `membership_status` flag (§10.2) | `404` | none | Fast |
| 15.26 | `POST .../teams/{team_id}/members` | `organization:update` | `{"user_id"}` | `201` | `403`/`404`/`409 TEAM_MEMBER_ALREADY_EXISTS`/`409` (target not `ACTIVE` org member) | `TEAM_MEMBER_ADDED` (5J §14.3, Revision 6 amendment) | Guard §10.2 |
| 15.27 | `DELETE .../teams/{team_id}/members/{user_id}` | `organization:update` | — | `204` | `403`/`404 TEAM_MEMBER_NOT_FOUND` | `TEAM_MEMBER_REMOVED` (5J §14.3, Revision 6 amendment) | — |

**DEP-6C-11 RESOLVED (Revision 6, §27):** every team-mutation row above now has an exact-match `action_kind` — `TEAM_CREATED`/`TEAM_UPDATED`/`TEAM_ARCHIVED`/`TEAM_MEMBER_ADDED`/`TEAM_MEMBER_REMOVED` — added to 5J §14.3's governed vocabulary by the controlled Phase 5.x amendment (no `TEAM_*` value existed at all prior to this pass, previously the single largest audit gap this document surfaced). Category A, durable, synchronous — no telemetry-only interim remains for team mutations.

### 15.28–15.30 Compliance Policy (3 endpoints)

Full mechanism §12. All gated `compliance:read`/`compliance:manage` (exact matches).

| # | Endpoint | Response | Errors | Audit |
|---|---|---|---|---|
| 15.28 | `GET .../compliance-policy` | `200`, current `ACTIVE` policy, full typed shape (§12.2) | `404` (no policy yet — a real, possible state while the asynchronous seeding consumer has not yet run or failed to process the `organization.created` event, §7.7; not merely defensive, corrected this pass) | none (read) |
| 15.29 | `POST .../compliance-policy` | `201`, `status:"DRAFT"`, `version: N+1` | `403`/`422` | `COMPLIANCE_POLICY_UPDATED` (adequate reuse, corrected this pass — §12.2) |
| 15.30 | `POST .../compliance-policy/{policy_id}/activate` | `200`, `status:"ACTIVE"` | `403`/`404`/`409` (not `DRAFT`) | `COMPLIANCE_POLICY_UPDATED` |

Idempotency-Key supported on `POST .../compliance-policy` (creating a policy version). Latency Standard for both mutations, Fast for the read.

### 15.31–15.37 Data Subject Requests (7 endpoints)

Full mechanism §13. All gated `data_subject:manage` (exact match, including reads — §13.3).

| # | Endpoint | Response | Errors | Audit |
|---|---|---|---|---|
| 15.31 | `POST .../data-subject-requests` | `201` | `422` (no subject identifier, ADR-5B-007) | `DATA_SUBJECT_REQUEST_RECEIVED` |
| 15.32 | `GET .../data-subject-requests` | paginated list | — | none |
| 15.33 | `GET .../data-subject-requests/{request_id}` | `200` | `404` | none |
| 15.34 | `POST .../{request_id}/verify` | `200`, `status:"VERIFYING"` or `"IN_PROGRESS"` | `409` | `DATA_SUBJECT_REQUEST_VERIFYING` (5J §14.3, Revision 6 amendment — **DEP-6C-14 RESOLVED**, §13.3, §27) |
| 15.35 | `POST .../{request_id}/hold` | `200`, `status:"ON_HOLD"` | `409` | `DATA_SUBJECT_REQUEST_ON_HOLD` (5J §14.3, Revision 6 amendment — **DEP-6C-14 RESOLVED**, §13.3, §27) |
| 15.36 | `POST .../{request_id}/complete` | `200`, `status:"COMPLETED"` | `409` | `DATA_SUBJECT_REQUEST_COMPLETED` |
| 15.37 | `POST .../{request_id}/reject` | `200`, `status:"REJECTED"`, requires `rejection_reason` | `409`/`422` | `DATA_SUBJECT_REQUEST_REJECTED` |

All CAS-guarded transitions (§7.6). Idempotency-Key supported on `POST .../data-subject-requests` (creation). Rate limit: 20/day/org across all DSR mutation endpoints combined (a low-volume, high-sensitivity workflow).

### 15.38 `GET /api/v1/users/me`

- **Purpose:** Return the caller's own editable profile. **Authorization:** None beyond authentication (self-scoped, mirrors 6B `/auth/me`). **Response `200`:** `{ "id", "email", "display_name", "phone_e164", "phone_verified_at", "email_verified_at", "status", "created_at" }` — never `password_hash`/`mfa_secret_ref`/etc. (§11.2). **Rate Limit:** 300/min. **Latency:** Fast. **Database:** `identity.users WHERE id = $subject` (no RLS, platform-owned). **Audit:** Not audited (read).

### 15.39 `PATCH /api/v1/users/me`

- **Purpose:** Update `display_name`/`phone_e164` (§11.2). **Request:** `{"display_name"?, "phone_e164"?}`, `extra="forbid"`. **Validation:** `phone_e164` E.164 format (6A §7.5). **Response `200`.** **Errors:** `400` (malformed body); `422` (invalid `phone_e164` format — well-formed request, semantically invalid value, per 6A §7.4, corrected this pass). **Rate Limit:** 20/hour. **Idempotency:** Naturally idempotent (PATCH). **Latency:** Standard. **Database:** `identity.users` update; `phone_e164` change also clears `phone_verified_at`. **Audit:** `USER_PROFILE_UPDATED` (5J §14.3, added by the Revision 6 controlled Phase 5.x amendment — **DEP-6C-15 RESOLVED**, §27) — Category A, exact match, durable, synchronous. **Concurrency:** Weak ETag.

### 15.40 `GET /api/v1/users/me/organizations`

§11.3. **Response `200`:** `{ "data": [ {"organization_id","organization_name","role","membership_status"}, ... ] }` (no pagination — bounded by realistic per-user org count). **Rate Limit:** 300/min. **Latency:** Fast (5B §35.3 query pattern). **Database:** `organization.memberships JOIN organization.organizations JOIN organization.roles WHERE user_id=$subject AND status='ACTIVE'`. **Security note:** inherits the §9.6 finding — documented in the response shape via `membership_status`, not silently hidden.

### 15.41 `GET /api/internal/v1/organizations/{organization_id}`

- **Purpose:** Lightweight internal lookup of core org fields for a worker/internal service that needs org context without a direct DB round-trip through its own repository layer (e.g., a future Voice/Campaign worker resolving timezone/currency/status before placing a call). **API surface:** Internal (`/api/internal/v1/`, 6A §8.5, never in public OpenAPI). **Authentication:** Internal service token (6B §17, central-issuer-minted). **Authorization:** `on_behalf_of_organization_id` claim must equal the path `organization_id` (6B §9.2's rule, applied here). **Actor:** `SERVICE`. **Tenant Scope:** Path, cross-checked against the token claim, not client-supplied.
- **Response `200`:** `{ "id", "status", "currency", "timezone", "region_ref", "data_residency_profile" }` — a deliberately narrow field set, not the full profile. **Errors:** `401` (wrong token type, per 6B §17.3's strict routing); `404`.
- **Rate Limit:** High fixed internal ceiling, not tenant-quota-governed (6A §20). **Latency:** Fast. **Database:** Same table as §15.2, no RLS. **Cache:** Internal callers may rely on the same `localization:{org_id}` key. **Audit:** Not audited (internal read). **Security:** Never exposed through public OpenAPI (6A §8.5); no fallback to a user/API-key credential (6B §17.3).

### 15.42 `GET /api/internal/v1/organizations/{organization_id}/compliance-policy`

- **Purpose:** Internal, synchronous read of the active compliance policy for call-time/campaign-time enforcement gating (consumed by future Voice/Campaign phases — 4I's own stated grounding for why this aggregate exists: "Recording policy per `CompliancePolicy`," 4I row 11). **API surface:** Internal. **Authentication/Authorization/Tenant Scope:** Identical pattern to §15.41.
- **Response `200`:** Full typed policy shape (§12.2), read-only. **Errors:** `401`; `404`. **Rate Limit:** High internal ceiling. **Latency:** Fast (cache-hit path, `compliance_policy:{org_id}`, 5B §31). **Cache:** `compliance_policy:{org_id}`, 15-min TTL, invalidated on activation (§15.30). **Audit:** Not audited.

---

## 16. Pagination, Filtering, Sorting, Concurrency, Idempotency (Cross-Cutting)

### 16.1 Pagination/Filtering/Sorting

Every list endpoint (§15.8, §15.17, §15.20, §15.25, §15.32) uses 6A §14's cursor pagination exactly — default 25, max 100, opaque HMAC-signed cursor, `(indexed_sort_column, id)` ordering. Allowed filters are an explicit allow-list per endpoint (documented in each contract above); no arbitrary `?filter[...]` expression language is accepted (6A §15). No list endpoint in this document is large/high-volume enough to require full-text/semantic search (6A §15's search rule is not exercised here — the closest candidate, member listing, is bounded by realistic org size and served by simple filters only).

### 16.2 Last-Owner-Protection Query Pattern (referenced by §8.6, §15.11, §15.13, §15.14)

```sql
UPDATE organization.memberships
SET status = 'REMOVED', removed_at = now(), removed_by = :actor_user_id
WHERE id = :member_id
  AND organization_id = :org_id
  AND status = 'ACTIVE'
  AND NOT (
    role_id = (SELECT id FROM organization.roles WHERE name = 'OWNER' AND organization_id IS NULL)
    AND (
      SELECT count(*) FROM organization.memberships m2
      JOIN organization.roles r2 ON r2.id = m2.role_id
      WHERE m2.organization_id = :org_id AND m2.status = 'ACTIVE' AND r2.name = 'OWNER'
    ) <= 1
  )
RETURNING id;
-- 0 rows: distinguish "not found/wrong org/wrong status" (404/409 STATE_CONFLICT)
--         from "would violate last-owner invariant" (409 LAST_OWNER_PROTECTED)
--         via an unlocked follow-up SELECT, mirroring 6B §13.2's exact zero-rows-affected pattern
```

Applied identically (with `SET status='SUSPENDED'`) for §15.11.

### 16.3 Idempotency Summary

| Endpoint class | Idempotency-Key |
|---|---|
| Organization create, cancel, ownership transfer, invitation create, team create, DSR create | **Required/supported** — real-world consequence on duplicate (6A §16.1) |
| Action endpoints routed through a guarded CAS transition (suspend/reactivate/remove/role-assign/archive/activate) | **Not required** — naturally safe via `409 STATE_CONFLICT` on retry (6A §17.2's action-endpoint guarantee) |
| PATCH endpoints | **Not required** — PATCH is natively idempotent (6A §7.3) |
| GET/list endpoints | N/A (safe methods) |

### 16.4 Concurrency Summary

Every guarded transition in this document uses the atomic conditional `UPDATE ... WHERE ... RETURNING` (CAS) pattern (§7.6, ADR-6C-02) — **no `SELECT ... FOR UPDATE` or other API-layer lock appears anywhere in this design**, consistent with frozen 6A §17.3 and directly modeled on 6B's own corrected refresh-token design (6B §13.2). Free-form field edits (Organization PATCH, Team PATCH, User Profile PATCH) use weak `updated_at`-derived ETags (6A ADR-6A-08).

---

## 17. Authorization Matrix

| Actor | Endpoint | Required | Expected result |
|---|---|---|---|
| Unauthenticated | Any `/api/v1/organizations/*` | — | `401 AUTHENTICATION_REQUIRED` |
| Authenticated `ACTIVE` user, no org yet | `POST /organizations` | Authentication only | `201` |
| `VIEWER` (own org) | `GET /organizations/{own}` | `organization:read` | `200` |
| `VIEWER` (own org) | `PATCH /organizations/{own}` | `organization:update` | `403` (VIEWER lacks it) |
| `MEMBER` (own org) | `GET /organizations/{own}/members` | `member:read` | `200` |
| `MEMBER` (own org) | `POST /organizations/{own}/invitations` | `member:invite` | `403` (MEMBER lacks it) |
| `ADMIN` (own org) | `POST /organizations/{own}/invitations` | `member:invite` | `201` |
| `ADMIN` (own org) | `POST /organizations/{own}/members/{id}/role` (assign a non-`OWNER` role) | `role:manage` | `200` (corrected this pass — previously checked against `member:invite`, §8.4) |
| `MEMBER` (own org) | `POST /organizations/{own}/members/{id}/role` | `role:manage` | `403` (MEMBER lacks it) |
| `ADMIN` (own org) | `GET /organizations/{other-org}/members` | tenant match | `404` (cross-tenant, not `403`) |
| `OWNER` (own org) | `POST /organizations/{own}/members/{self}/remove`-equivalent (via `/leave`) while sole OWNER | last-owner guard | `409 LAST_OWNER_PROTECTED` |
| `ADMIN` (own org) | `POST /organizations/{own}/ownership/transfer` | Must be current `OWNER` | `403` (identity-bound, ADMIN is not the owner) |
| `BILLING_ADMIN` (own org) | `GET /organizations/{own}/compliance-policy` | `compliance:read` | `403` (BILLING_ADMIN's seeded set per 5B §17.2 does not include `compliance:*`) |
| Any actor | `GET /organizations/{own}/data-subject-requests` without `data_subject:manage` | `data_subject:manage` | `403` (only OWNER/ADMIN hold it) |
| API Key (`scopes=['member:read']`) | `POST /organizations/{own}/members/{id}/suspend` | `member:suspend` not in `scopes` | `403` (scope-ceiling, 6B §16.4) |
| `PLATFORM_ADMIN`, no break-glass grant | Any `/organizations/{any}/*` tenant-scoped route | Ordinary tenant RBAC | `403` (platform-admin status alone never satisfies tenant RBAC, 6B §18.3a/§31 — restated here unmodified) |
| `PLATFORM_ADMIN` with a **valid** `X-Break-Glass-Grant` for Org A | `GET /organizations/{A}/members` | Six-check grant validation (6B §18.3a) passes | `200` — 6C endpoints are ordinary tenant-scoped routes and are reachable under break-glass exactly like any other, with no 6C-specific exception |
| Internal service (`service_id=worker`) | `/api/v1/organizations/*` (public route) | n/a | `401` (internal token rejected on public routes, 6B §17) |
| User access token | `/api/internal/v1/organizations/*` | n/a | `401` (user token rejected on internal routes, 6B §17) |

---

## 18. Error Catalog (6C-specific codes, extending 6A's envelope and 6B's established families)

| HTTP | `code` | Used for | Existence concealed? |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | Malformed request (unparseable JSON, invalid query parameter) — 6A §7.4's strict definition | — |
| 422 | `VALIDATION_ERROR` | Well-formed but semantically invalid: forbidden-field mutation attempts (`currency`/`country_code`/`status`/`owner_user_id`), invalid field-value formats (`timezone`/`locale`/`phone_e164`), `confirm_slug` mismatch, DSR missing-subject-identifier (ADR-5B-007) — 6A §7.4's strict definition, corrected this pass (Cleanup 1: a prior draft inconsistently used `400` for several of these) | — |
| 403 | `AUTHORIZATION_DENIED` | Permission check failed | Internal permission structure |
| 404 | `RESOURCE_NOT_FOUND` | Cross-tenant reference (org, member, team, policy, DSR) | Cross-tenant existence |
| 409 | `STATE_CONFLICT` | Generic guarded-transition rejection (`error.details.current_state`) | — |
| 409 | `MEMBER_ALREADY_EXISTS` | Invite target already an accepted, active member | — |
| 409 | `INVITATION_ALREADY_PENDING` | Invite target already has an unaccepted invitation in this org | — |
| 409 | `ROLE_CHANGE_NOT_ALLOWED` | Attempted role change touching `OWNER` outside the transfer endpoint | Which specific guard fired |
| 409 | `LAST_OWNER_PROTECTED` | Suspend/remove/leave would leave the org with zero active OWNERs | — |
| 409 | `TEAM_MEMBER_ALREADY_EXISTS` | Duplicate team-membership add | — |
| 404 | `TEAM_MEMBER_NOT_FOUND` | Remove of a non-existent team membership | — |
| 409 | `IDEMPOTENCY_KEY_REUSE_MISMATCH` | 6A/6B-standard, `409` (not `422`) | — |
| 429 | `RATE_LIMIT_EXCEEDED` | Any §15/§18 limit breached | — |
| 503 | `DEPENDENCY_UNAVAILABLE` | Redis/DB unavailable at a fail-closed point (RBAC cache invalidation on role change, §15.10) | Stack traces, internals |
| 5xx | `INTERNAL_ERROR` | Unhandled failure | Same |

`RESOURCE_VERSION_CONFLICT` from the task's illustrative list is not separately introduced — 6A's existing `412 PRECONDITION_FAILED` (weak-ETag mismatch) already covers this exactly (6A §17.2); inventing a second code for the same condition would contradict 6A's own error-family discipline (§24.2).

---

## 19. Audit Coverage

**6A §22's audit rule is binding, not advisory:** *"Every state-changing endpoint maps to a documented `action_kind`... and triggers an `audit.audit_events` write."* This document does not treat a mutation as exempt from that rule merely because it seems low-stakes — a prior draft classified several genuinely-gapped mutations (compliance-policy draft creation, DSR `verify`/`hold`, user-profile edits) as "deliberate, not a gap," an unjustified carve-out from 6A's unconditional wording. **Corrected in an earlier pass (Blocker 4):** every state-changing 6C endpoint is classified strictly as **A** (exact `action_kind` match), **B** (adequate, documented reuse of an existing `action_kind`), or **C** (genuine gap — no `action_kind` can honestly represent the event; tracked as a dependency, telemetry-only in the interim). **Telemetry never counts as satisfying 6A's audit requirement** — it was disclosed, honest interim visibility for Category-C gaps only, never presented as equivalent to a durable `audit.audit_events` row. **Revision 6 (this pass) closes every remaining Category-C gap** via a controlled Phase 5.x governance amendment to 5J §14.3 (no SQL migration — `action_kind` is `TEXT` with only a length `CHECK`, not an enum, so the amendment is a pure vocabulary/governance addition, verified directly against `072_5J.sql`'s `chk_ae_action_kind` definition, not assumed) — **there is no longer a Category C for this document.**

**Category A — exact `action_kind` match:** organization create/update/suspend/**cancel** (`ORGANIZATION_CREATED`/`UPDATED`/`SUSPENDED`/**`CANCELLED`†**), member invite/role-change/suspend/remove/**reactivate** (`MEMBER_INVITED`/`MEMBER_ROLE_CHANGED`/`MEMBER_SUSPENDED`/`MEMBER_REMOVED`/**`MEMBER_REACTIVATED`†**), all three terminal DSR transitions plus **the two intermediate transitions** (`DATA_SUBJECT_REQUEST_RECEIVED`/`COMPLETED`/`REJECTED`/**`VERIFYING`†**/**`ON_HOLD`†**), **every team mutation** (`TEAM_CREATED`†/`TEAM_UPDATED`†/`TEAM_ARCHIVED`†/`TEAM_MEMBER_ADDED`†/`TEAM_MEMBER_REMOVED`†), **user-profile edits** (`USER_PROFILE_UPDATED`†). († = added to 5J §14.3's governed vocabulary by the Revision 6 controlled Phase 5.x amendment; see §27 DEP-6C-07/10/11/14/15, all RESOLVED.)

**Category B — adequate, documented reuse:** member self-leave (`MEMBER_REMOVED`, actor differentiates), invitation resend/idempotent-re-invite (`MEMBER_INVITED`), invitation cancel (`MEMBER_REMOVED`), ownership transfer (`MEMBER_ROLE_CHANGED` ×2), organization-logo completion (`ORGANIZATION_UPDATED`), compliance-policy draft creation and activation, both `COMPLIANCE_POLICY_UPDATED` (§12.2).

**Category C — none remaining.** Every mutation this document's earlier passes identified as a genuine audit-vocabulary gap (organization cancellation, member reactivation, every team mutation, DSR `verify`/`hold`, user-profile edits) now has an exact-match, governed `action_kind` (table above). No interim telemetry-only mapping remains anywhere in this document's endpoint surface.

**How this was closed without silently inventing a string (the governing discipline, unchanged; only the outcome changed this pass):** Phase 5K's implementation confirms `audit.audit_events.action_kind` is `TEXT` with only a length/basic-validity check (`chk_ae_action_kind`), not a database `ENUM` — the column could, mechanically, always have stored any string 6C chose to write. **That was never the governing constraint.** 5J §14.3's documented vocabulary is the architecture's actual governance boundary for what `action_kind` values mean and are permitted to exist; a value the database would physically accept but 5J never defined was not a legitimate `action_kind` under this platform's design discipline, any more than a client being able to send an extra JSON field means the API should accept it (6A §22's mass-assignment discipline, applied by analogy). This document did not unilaterally invent `ORGANIZATION_CANCELLED`, `MEMBER_REACTIVATED`, any `TEAM_*` value, or any DSR-intermediate/user-profile value — each of the ten new values was instead added through an explicit, controlled Phase 5.x governance amendment to `5J-Analytics-Audit-Schema.md` §14.3 itself (see §27, DEP-6C-07/10/11/14/15), named to match 5J's own existing naming style exactly (verb-past-tense; `DATA_SUBJECT_REQUEST_VERIFYING`/`_ON_HOLD` mirror `data_subject_requests.status`'s own spelling; `MEMBER_REACTIVATED` mirrors the existing `ORGANIZATION_REACTIVATED` verb) — a genuine upstream governance decision, not a 6C string choice made unilaterally.

**Reads are never audited** (org/member/team/policy/DSR/profile `GET`s) — unaffected by 6A §22's rule, which is scoped to state-changing endpoints. Organization logo `upload-url` (§15.4) is likewise not audited — it creates no durable state (no row is written until `complete`, §15.5).

**Honest compliance statement:** `NFR-SEC-004`/6A §22's audit requirement is **now fully satisfied** for every state-changing endpoint in this document's surface — Category A and B alike — following the Revision 6 vocabulary amendment. This closes what was previously the largest reason this document's overall status remained REVIEW REQUIRED (§26, §31).

---

## 20. Domain Events

| Event | Producer | Payload | Delivery |
|---|---|---|---|
| `organization.created` | This document | `organization_id`, `owner_user_id`, `slug` | Internal event bus only (6A §6/§28.3) — no webhook. **Consumed by this document's own Compliance-context seeding logic (§7.7) — durably persisted in `audit.domain_event_outbox` (migration `077_5J1.sql`) in the same transaction as the triggering `Organization`/`Membership` insert (DEP-6C-16 RESOLVED), then relayed to Redis Streams by the existing publisher via `audit.fn_claim_outbox_events()`/`fn_mark_outbox_published()` — at-least-once delivery.** |
| `organization.updated` | This document | `organization_id`, `changed_fields` | Internal — not currently consumed by any 6C logic requiring durability |
| `organization.suspended` / `organization.cancelled` | This document | `organization_id`, `reason` | Internal |
| `member.invited` / `member.role_changed` / `member.suspended` / `member.reactivated` / `member.removed` / `member.left` | This document | `organization_id`, `member_id`, `actor_id` | Internal |
| `ownership.transferred` | This document | `organization_id`, `previous_owner_member_id`, `new_owner_member_id` | Internal |
| `team.created` / `team.updated` / `team.archived` / `team.member_added` / `team.member_removed` | This document | `organization_id`, `team_id` | Internal |
| `compliance.policy_activated` | This document | `organization_id`, `policy_id`, `version` | Internal — the trigger for the `organizations.compliance_policy_id` convenience-pointer update (§12.2) only; **durably persisted in `audit.domain_event_outbox` in the same transaction as the `compliance_policies` status transition (DEP-6C-16 RESOLVED, §12.2).** The `compliance_policy:{org_id}` cache invalidation named in 5B §31 is **NOT** triggered by this event — it is a synchronous step inside the activation endpoint's own request handler (§12.2, §21) and does not depend on this event's delivery at all. |
| `data_subject_request.*` | This document | `organization_id`, `request_id`, `request_type` | Internal |

Every event uses 6A §27.3's generic JSON envelope (`event_id`, `event_type`, `version`, `timestamp`, `organization_id`, `resource_id`, `sequence`, `payload`) where delivered over the WebSocket/internal-bus path; none of these are outbound tenant webhooks (6J's future domain, not this document's — 6A §28.3's three-mechanism distinction applies unchanged). `audit.domain_event_outbox`'s own columns (`event_type`, `organization_id`, `aggregate_type`, `aggregate_id`, `payload`) map directly onto this envelope's fields (`event_id`/`sequence`/`timestamp` are the outbox row's own `id`/insertion-order/`occurred_at`).

**Distinguishing "the event type is architecturally defined" from "the event is durably, crash-safely deliverable" (the same distinction an earlier pass introduced — now resolved for the two rows it applied to):** every row in this table is architecturally sound — the event names, payloads, and internal-vs-webhook classification are all DESIGN COMPLETE. `organization.created` and `compliance.policy_activated` are the only two rows whose consumer correctness depends on durable delivery (§7.7, §12.2) — and for exactly those two, durable delivery is now schema-backed via `audit.domain_event_outbox` (DEP-6C-16 RESOLVED). The other events in this table remain emitted for future consumption (e.g., later phases' notification/analytics needs) without any 6C-owned logic currently depending on their durability; nothing prevents them from using the same outbox relation once such a consumer is designed, but this document does not fabricate that design here.

---

## 21. Caching

| Cache key | Contents | TTL | Invalidated on | Fail-open/closed |
|---|---|---|---|---|
| `localization:{org_id}` | Localization subset of org profile (5B §31) | 15 min | `organization.updated` (localization fields) | Fail-open (non-security-sensitive; a stale timezone for 15 min is a UX nit, not a breach) |
| `compliance_policy:{org_id}` | Active compliance policy (5B §31) | 15 min | **Synchronous `DEL` inside `POST .../compliance-policy/{policy_id}/activate`'s own request handler (§12.2) — NOT the `compliance.policy_activated` event.** Cache correctness must not, and does not, depend on event delivery — this remains true unconditionally, independent of DEP-6C-16's now-resolved status (§27); the event remains responsible only for the separate, non-authoritative `organizations.compliance_policy_id` pointer update (§12.2, §20). | **Fail-closed for enforcement consumers** (future Voice/Campaign call-time gating must treat a cache-read failure as "fetch from DB or refuse to place the call," never "assume permissive defaults") — this document specifies the cache contract; the fail-closed *enforcement* behavior is binding guidance for whichever future phase consumes §15.42, not implemented here |
| `rbac:permissions:{org_id}:{user_id}` | Not owned by 6C — invalidated *by* 6C's role/suspend/remove/transfer endpoints, per 6B's existing contract (6B §23/§8) | 5 min (6B) | Referenced, not redefined | Per 6B |

No new cache namespace is introduced beyond what 5B §31 already names; 6C's job is to invalidate correctly on write, not to define new cache architecture (6A §19's existing tenant-namespaced-key discipline applies unchanged).

---

## 22. Performance

All figures TARGET, not MEASURED (6A §11 discipline). Every 6C **endpoint's own client-observed latency** is Tier A (Interactive) per 6A's tier definitions — no endpoint's synchronous response path has an external-provider dependency, and none waits on a downstream cross-aggregate effect (6A §35; matches §7.7/§12.2's genuinely event-driven design, Blockers 1–2). CRUD/list endpoints target 6A's Tier A p99 (300ms); action/transition endpoints likewise, since the CAS pattern (§16.4) is a single indexed statement, not a multi-step orchestration. No endpoint in this document is a candidate for Tier B (no external side effect like telephony) or Tier C (no heavy aggregation — member/team lists are bounded by realistic per-org scale, well under the volumes 6A §13 flags as partition-scale). **`POST /organizations` (§15.1) — DEP-6C-16 RESOLVED this pass (Revision 6):** the request transaction now performs exactly **three** single-row inserts — `organization.organizations`, `organization.memberships`, `audit.domain_event_outbox` (§7.7, migration `077_5J1.sql`) — all within the one 6A-§35-authorized transaction, still contributing negligible latency (three single indexed inserts, not an external call), comfortably within 6A §12's per-layer database budget (100–150ms of the 300ms ceiling). `CompliancePolicy` seeding itself never contributes synchronous latency — it remains architecturally consumer-only (§7.7), regardless of the outbox's own existence.

**Asynchronous, event-driven side effects — a clarification of §5's "Async job / status: NOT APPLICABLE" row:** that row remains accurate for the *client-facing API contract* — no 6C endpoint returns `202` + a job resource, and no `/jobs`-shaped polling endpoint is introduced (6A §18.3's pattern is genuinely not used anywhere in this document). It does **not** mean no processing in this document's scope is asynchronous: `CompliancePolicy` seeding (§7.7) and the `compliance_policy_id` pointer update (§12.2) are both internal, event-driven, backend-only asynchronous effects with no client-visible job/polling surface — a materially different thing from the async-job pattern §5's row was scoping out. This distinction is stated explicitly here rather than left as an apparent contradiction between §5 and §7.7/§12.2.

---

## 23. OpenAPI Readiness

Per 6A's ADR-6A-06 (FastAPI-generated OpenAPI + vendor extensions) and 6B's precedent:

- **Reusable schemas:** `Organization`, `OrganizationUpdate` (the §7.2 allow-list, exactly), `Member`, `MemberListItem` (email-redacted variant), `MembershipStatus` enum, `MemberInviteRequest`, `MemberRoleChangeRequest`, `Team`, `TeamCreate`, `TeamUpdate`, `TeamMember`, `CompliancePolicy`, `CompliancePolicyCreate`, `DataSubjectRequest`, `DataSubjectRequestCreate`, `UserProfile`, `UserProfileUpdate`, pagination metadata and error schemas reused unmodified from 6A/6B.
- **Security schemes:** `BearerAuth`, `ApiKeyAuth` (both reused from 6B, unmodified), `InternalBearerAuth` (reused from 6B, restricted to `/api/internal/v1/organizations/*` in the generated spec).
- **Vendor extensions:** `x-latency-tier`, `x-permission-required`, `x-audit-action-kind` (every state-changing endpoint, §19 — as of Revision 6, this now applies to the entire endpoint surface, since no Category C endpoint remains). The `x-audit-status: "implementation-dependency"` extension value (used through Revision 5 for Category C endpoints, mirroring 6A §32.2's mechanism without its exact prior vocabulary) is **retired, not merely unused** — every endpoint that previously carried it now carries `x-audit-action-kind` with a real, governed value instead.
- **Status:** OpenAPI-ready for all 42 endpoints listed in §15 (§25 gives the exact count).

---

## 24. Threat Model

| Threat | Surface | Mitigation | Detection | Residual risk |
|---|---|---|---|---|
| IDOR / cross-tenant access | Any `{organization_id}`/`{member_id}`/`{team_id}` path param | RLS (5B §16.4) + API-layer tenant cross-check (§15.0) + `404` non-disclosure | Tenant-isolation test suite (§26) | None known |
| Privilege escalation via role assignment | `POST .../members/{id}/role` | OWNER-role assignment blocked outside `/ownership/transfer`; sole-OWNER demotion blocked (§8.4) | Authz-matrix test suite | None known |
| Last-owner removal (org left ownerless) | Suspend/remove/leave | CAS guard with `NOT EXISTS` last-owner check (§16.2) | Dedicated test (§26) | None known |
| Invitation hijacking / replay | `POST /auth/invitations/accept` (6B), fed by 6C's token | `{membership_id}.{secret}` format (§9.3) — secret is 256-bit random, membership-state-guarded (§9.3.1 step 2), 7-day expiry (§9.2a, reconciled) | 6B's existing token-validation telemetry | Token delivery (email) is out of this document's authority. **Additionally:** a resend does not reliably invalidate a prior, still-valid token for the same invitation (Gap B, DEP-6C-12) — an intercepting party holding the old token can race the legitimate invitee to accept the *same, already-intended* grant; this cannot escalate beyond that one grant (§9.4) |
| Invitation enumeration | `POST .../invitations` | Response is `201`/`200` regardless of whether the invitee already had an account (§9.5) | — | None known |
| Stranded invitation after partial creation failure (new this pass — Blocker 2) | `POST .../invitations` (token insert fails after membership insert succeeds) | Idempotent re-invite: a retry with the same `(org, user, role)` reuses the pending `membership_id` and mints a fresh token rather than dead-ending on `409` (§9.3.2 points 1–3) | — | None known — fully self-healing for sequential retries |
| Concurrent duplicate pending invitations (new this pass — Blocker 3) | `POST .../invitations`, two genuinely simultaneous calls | No DB constraint prevents two pending rows for the same `(org, user)`; contained at acceptance time by the frozen `uq_memberships_active` index — at most one can ever become `ACTIVE` (§9.3.2 point 5) | Duplicate-invite metric (interim) | Data-hygiene nuisance (two emails, one clean `409` on second accept attempt) — never unauthorized access, never a double grant — tracked as **DEP-6C-13** |
| Pre-acceptance unauthorized tenant access via login-continuation | `organization.get_user_organization_ids()` / login flow (6B, frozen) | **CLOSED this pass** — pending invitations use `status='SUSPENDED'`, already excluded by every one of 6B's frozen access-granting queries, verified directly against the frozen query/pseudocode (§9.6) | Scenario-A test (§25) | None known — closed without requiring a 6B/5B change |
| Team membership spoofing | `POST .../teams/{id}/members` | Target must be an `ACTIVE` org member at add-time (§10.2); duplicate-add is DB-enforced (`uq_team_memberships_active` partial unique index, 5B §13 — corrected this pass, no longer an application-layer TOCTOU mitigation) | — | None known |
| Mass assignment / overposting | Any PATCH/POST body | `extra="forbid"` Pydantic schemas (6A §22); `status`/`owner_user_id`/`currency`/`country_code` structurally absent from `OrganizationUpdate` | Contract tests | None known |
| Hidden-field updates via team/DSR create | `POST .../teams`, `.../data-subject-requests` | Typed allow-list request schemas, no generic JSON body accepted anywhere in this document | Contract tests | None known |
| Stale-role permissions after role change | `POST .../members/{id}/role` | Synchronous `rbac:permissions:{org}:{user}` invalidation (§15.10, reusing 6B's existing contract) | — | Bounded by 6B's existing 5-min TTL fallback |
| Suspended-org/member continued access | Org/member suspend | Enforced by 6B's `PermissionEvaluationService` steps 1–2 (6B §8), unchanged by 6C | 6B's own test suite | None new introduced |
| Pagination abuse | Any list endpoint | Server-enforced max page size 100 (6A §14.3) | — | None known |
| Search/filter injection | N/A — no free-text search exposed anywhere in this document (§16.1) | Allow-listed filters only, parameterized (6A §15) | — | None known |
| Cache poisoning | `localization:{org_id}`, `compliance_policy:{org_id}` | Tenant-namespaced keys, write-then-invalidate (not TTL-only) for compliance policy | — | None known |
| Race conditions / duplicate commands | Every guarded transition | CAS pattern, no API-layer lock (§16.4) | Concurrency test suite (§26) | None known |
| SSRF | None — no endpoint in this document accepts an arbitrary URL (`website` is stored, not fetched server-side) | N/A | — | None |
| File-upload threats | Organization logo (§15.4–§15.5) | 6A §29's full pattern: presigned URL, content-type allowlist, size ceiling, magic-number re-verification | — | No malware-scan pipeline for this specific low-risk field (deliberate, disclosed, §15.5) |
| Compromised admin issuing bulk destructive actions | Cancel/remove/team-archive | Rate limits (§15 per-endpoint), `confirm_slug` guard on cancel (§15.7) | Audit trail (§19) | Standard admin-compromise risk, not specific to this document |

---

## 25. Test Strategy

- **Contract:** every one of the 42 endpoints (§15) validated against its full contract — status codes, envelope shape, error `code` values, request/response schema (mirrors 6B §32's discipline exactly).
- **Authorization:** every row of §17 as an automated table-driven suite, including the `PLATFORM_ADMIN`-with-and-without-break-glass-grant rows (reusing 6B's own break-glass test harness, not reinventing it).
- **Multitenancy:** org A's members/teams/policy/DSR are unreachable via org B's context — asserts `404`, never `403`, with no distinguishing signal (mirrors 6B §32's tenant-isolation test exactly).
- **Membership:** invite → accept (cross-document, exercised against 6B's real accept endpoint in integration) → role-change guards (OWNER-involving rejections) → suspend/reactivate → remove → last-owner protection under concurrent removal attempts (two simultaneous `remove` calls on the two remaining non-owner members of a 2-member org, one of whom is being promoted — race asserted to leave exactly one OWNER, never zero).
- **Team:** same-org-membership-only add; duplicate add; removed-org-member's stale team entries surfaced correctly via `membership_status`; cross-tenant add rejected.
- **Concurrency:** simultaneous role-change requests on the same membership (CAS, exactly one wins); simultaneous suspend attempts on the sole OWNER (both must fail `LAST_OWNER_PROTECTED`, zero must succeed); simultaneous organization-cancel calls (exactly one succeeds). **Simultaneous invitation-creation for the same email — corrected this pass (Blocker 3):** a prior draft asserted a deterministic "one succeeds, one gets `INVITATION_ALREADY_PENDING`" outcome; this contradicted §9.3.2 point 5's own documented race (no DB constraint covers pending-row creation) and is retracted. The actual, enforceable assertions are (normalized this pass — a prior draft stated this range inconsistently in two places): (a) **the number of pending rows resulting from two genuinely concurrent calls is not deterministic and is never asserted as a fixed count** — one or two pending `SUSPENDED`/`accepted_at IS NULL` rows may exist afterward, depending on whether the second call's duplicate-check observed the first call's row before its own insert; (b) **the one invariant that IS enforceable and IS asserted:** at most **one** membership for a given `(organization_id, user_id)` pair can ever transition to `ACTIVE`, because `uq_memberships_active` (5B §9.7) protects `(organization_id, user_id) WHERE status='ACTIVE'` — if two pending rows exist, the second acceptance attempt is asserted to fail `409 STATE_CONFLICT` via the `unique_violation`-on-`uq_memberships_active` path (§9.3.1 step 4), never a `500`, never a second `ACTIVE` membership; (c) a **sequential** retry (not concurrent) with the same `(org, user, role)` after a prior attempt is asserted to hit the idempotent-re-invite path (`200`, not `409`), per §9.3.2 point 2.
- **Security:** mass-assignment probes against every PATCH/POST body (attempt to set `status`/`owner_user_id`/`currency` directly — asserted rejected at the schema layer, `422`, never silently ignored-and-succeeded); client-supplied `organization_id` mismatch in path vs. token (`404`, not `403`); DSR/compliance-policy access by a role lacking the specific permission (`403`, including `BILLING_ADMIN` explicitly, since it is the role most likely to be mistakenly over-granted).
- **Invitation-specific (§9.7 scenarios A–G, new to this document, not inherited from 6B):** (A) an existing user invited to a second org does not appear in their own `GET /users/me/organizations` or in 6B's login-continuation "allowed organizations" set until they actually accept; (B) two simultaneous pending invitations for the same user to two different orgs both individually and correctly acceptable via their own `{membership_id}.{secret}` token, with no cross-contamination; (C) resend issues a working new token — explicitly **not** asserted to invalidate the old one (Gap B, DEP-6C-12) — while confirming the old token still resolves only to the *same* org/role and never to a different org's pending invitation; (D) cancel renders the membership permanently un-acceptable regardless of any token's own remaining validity, asserted **without** relying on any token being marked used; (E) concurrent cancel-vs-accept produces exactly one terminal outcome, never both; (F) concurrent resend-vs-accept never produces two distinct sessions/memberships from one invitation; (G) re-inviting a previously-removed user creates a new `membership_id`, and any stale token tied to the old, removed row is confirmed permanently rejected. **Reactivate-vs-pending-invitation guard:** `POST .../members/{id}/reactivate` against a row with `accepted_at IS NULL` is asserted rejected `409`, never silently activating an unaccepted invitation (§8.2, §15.12).
- **Invitation creation partial-failure / stranding (new this pass — Blocker 2, §9.3.2):** (i) inject a failure between the membership insert and the token insert, then retry the identical request — asserted to return `200` with a working new token, never a dead-end `409`; (ii) retry with a **different** `role_id` against the same pending invitee — asserted `409 INVITATION_ALREADY_PENDING`; (iii) inject a failure between the `identity.users` insert and the membership insert (new-user path), then retry — asserted to reuse the existing `PENDING_VERIFICATION` user row, no duplicate.
- **Invitation creation concurrency (new this pass — Blocker 3, §9.3.2 point 5):** fire two genuinely parallel `POST .../invitations` calls for the same `(org, email, role)` — assert the actual enforceable outcome only, worded identically to §25's Concurrency bullet above (one or two pending rows may result, not asserted as a fixed count; **at most one** can ever reach `ACTIVE`, enforced by `uq_memberships_active`; the second acceptance attempt against a duplicate-pending scenario is asserted `409 STATE_CONFLICT`, never `500`, never a second `ACTIVE` row) — no test in this group asserts a deterministic single-`409`-on-create outcome.
- **Audit assertion discipline (Blocker 4; DEP-6C-07/10/11/14/15 RESOLVED this pass, Revision 6):** for every state-changing 6C endpoint, the test suite asserts the documented `action_kind` was written to `audit.audit_events` — this now applies uniformly across the entire endpoint surface (Category A and B), since no Category C endpoint remains (§19). No endpoint's test asserts interim telemetry as a substitute for a durable audit write any longer.
- **Transaction-boundary / event-driven tests (§7.7, §12.2) — DEP-6C-16 RESOLVED — LIVE VERIFIED (Revision 7): the outbox-dependent tests below have been executed live against a real database (`077_5J1` applied via a genuinely fresh `alembic upgrade head` run) — atomic domain+outbox COMMIT/ROLLBACK, both event flows' insert+claim, a real two-connection concurrency race, wrong-worker rejection, retry/failure, max-attempts, and stale-claim recovery all passed (§27, `5K/validation/077_5J1_VALIDATION_REPORT.md`, `5K/execution_logs/README.md`'s "Fifth batch"):**
  - **Testable today (unaffected by DEP-6C-16 either way):** (i) `POST /organizations` — assert the response is returned (`201`, org and owner membership durably queryable) **before** any `CompliancePolicy` row can possibly exist yet — the response must never be observed waiting on `CompliancePolicy` seeding; assert the response body carries **no** `CompliancePolicy`-derived field at all. (ii) `GET .../compliance-policy` immediately after organization creation is asserted `404` (a real, expected state, not an error). (iii) the manual recovery path (`POST .../compliance-policy` + `.../activate`) is asserted to succeed independently of any event mechanism at all. (iv) `POST .../compliance-policy/{id}/activate` — assert the response (`200`) reflects only `compliance_policies.status='ACTIVE'`, never waiting on the `organizations.compliance_policy_id` pointer; assert `GET .../compliance-policy` (which queries by `status`, not the pointer) returns the correct policy regardless of the pointer's value. **(iv-a) cache invalidation, asserted independent of event delivery (§12.2, §21):** after a successful activation call, assert the `compliance_policy:{org_id}` Redis key was synchronously invalidated (deleted or absent) **before** the `200` response was returned, and assert a subsequent `GET .../compliance-policy` reflects the newly-activated policy, not a stale cached value — this assertion must pass identically whether or not the `compliance.policy_activated` event was ever delivered (simulate the event consumer as entirely absent/disabled in this specific test to prove the independence). (iv-b) separately, and explicitly **not** conflated with (iv-a): `organizations.compliance_policy_id` (the convenience pointer, distinct from the cache) is asserted to remain at its **pre-activation** value when the event consumer does not run — this is the expected, disclosed staleness (§12.2), not a test failure. (v) static/code-review assertion: no code path in either endpoint's own request-handling transaction includes a `CompliancePolicy` write (for org creation) or an `organizations` write (for policy activation) — both are reachable only from an asynchronous consumer, never inline in the synchronous request path.
  - **Now specifiable against the concrete schema (previously blocked pending DEP-6C-16):** (vi) assert `POST /organizations`'s request transaction, on commit, leaves exactly one `audit.domain_event_outbox` row with `event_type='organization.created'`, `status='PENDING'`; assert a rolled-back request transaction (e.g., a simulated failure after the `memberships` insert) leaves **zero** rows in any of `organizations`/`memberships`/`domain_event_outbox` — proving same-transaction atomicity (§077_5J1_VALIDATION_REPORT.md §8-9). (vii) two concurrent calls to `audit.fn_claim_outbox_events()` against one `PENDING` row are asserted to yield exactly one claimant, the other zero rows — the same class of assertion already proven for the structurally identical `webhooks.fn_claim_delivery` (`FINAL_5K_VALIDATION_REPORT.md` §3 row 5), now to be independently re-verified for this new function. (viii) `audit.fn_mark_outbox_failed()` on an exhausted-`attempt_count` row is asserted to leave `status='FAILED'`, never silently retried forever; a stuck `CLAIMED` row past `p_claim_timeout_seconds` is asserted reclaimable by a subsequent `fn_claim_outbox_events()` call. (ix) the `compliance.policy_activated` flow's equivalent same-transaction/atomicity/claim assertions, mirroring (vi)-(viii). These tests are named here as **executable specifications**, required to actually be run against a live database as part of this migration's own deployment validation (tracked in `5K/validation/077_5J1_VALIDATION_REPORT.md`, not fabricated here as already-passing results).
- **Performance:** p50/p95/p99 assertions against §22's TARGET budgets under a defined load profile (test specified, result not fabricated, per 6A/6B's shared discipline).

---

## 26. Traceability

**Status vocabulary reused from 6B §35:** `PASS`, `DESIGN COMPLETE`, `IMPLEMENTATION DEPENDENCY`, `PARTIAL`, `BLOCKED BY PHASE 5.x`.

| Requirement | Domain (4A/4I) | Phase 5 capability | API (this doc) | Permission | DB interaction | Audit event | Status |
|---|---|---|---|---|---|---|---|
| `FR-TEN-001` (unlimited, isolated orgs) | `Organization` aggregate | `organizations`, no self-RLS by design | §15.1–§15.7 | `organization:*` | `organizations` CRUD | `ORGANIZATION_CREATED`/`UPDATED`/`SUSPENDED`/`CANCELLED` (full coverage, DEP-6C-07 RESOLVED Revision 6) | PASS |
| `FR-TEN-003` (Org Admins manage users/roles/settings within their tenant) | `Membership` aggregate | `memberships`, RLS | §15.8–§15.19 | `member:*` | `memberships` CRUD | Category A/B fully covered including reactivation (`MEMBER_REACTIVATED`, DEP-6C-10 RESOLVED Revision 6) | PASS |
| `NFR-SEC-003` (RBAC/tenant isolation at all layers) | — | RLS + `PermissionEvaluationService` (6B, reused) | §17 (cross-cutting) | — | — | — | PASS |
| `NFR-SEC-004` / 6A §22 (every state-changing endpoint audited) | — | `audit.audit_events` (5J) | §19 | — | `fn_insert_audit_event()` | Category A/B (exact match or adequate reuse): full coverage of every state-changing endpoint in this document's surface — no Category C remains (DEP-6C-07/10/11/14/15 all RESOLVED, Revision 6, via a controlled Phase 5.x governance amendment to 5J §14.3) | **PASS — FULLY 6A-§22-COMPLIANT** (was PARTIAL through Revision 5; closed this pass) |
| `NFR-PERF-002` (API p99 < 300ms) | — | — | §22 | — | — | — | PASS (TARGET, not measured) |
| Teams (no dedicated SRS FR — grounded directly in 4A §5.1's embedded-entity design) | `Organization` aggregate (embedded) | `teams`, `team_memberships`, RLS | §15.20–§15.27 | `organization:update` (interim, DEP-6C-03) | CRUD | `TEAM_CREATED`/`UPDATED`/`ARCHIVED`/`MEMBER_ADDED`/`MEMBER_REMOVED` (full coverage, DEP-6C-11 RESOLVED Revision 6) | **PASS for audit; permission-vocabulary interim mapping (DEP-6C-03) remains disclosed, non-blocking** |
| Compliance configuration (grounded in 4I §7.2/§9.1, not a numbered SRS FR — closest is `NFR-COMPLY-001`) | `CompliancePolicy` aggregate | `compliance_policies`, RLS | §15.28–§15.30 | `compliance:*` | CRUD + activation CAS | `COMPLIANCE_POLICY_UPDATED` | PASS |
| Data subject rights (grounded in 4I §9.1/§1261, closest SRS anchor is `NFR-SEC-005`/`NFR-COMPLY-001`) | `DataSubjectRequest` aggregate | `data_subject_requests`, RLS, ADR-5B-007 | §15.31–§15.37 | `data_subject:manage` | CRUD + CAS transitions | `DATA_SUBJECT_REQUEST_RECEIVED`/`COMPLETED`/`REJECTED` | PASS |

---

## 27. Future / Upstream Dependencies Register

**Revised across six correction passes.** Pass 1: DEP-6C-02 (pre-acceptance authorization) marked **RESOLVED** (§9.6). DEP-6C-04 narrowed — 5B already has `uq_team_memberships_active` (§10.2). DEP-6C-09 narrowed — the role-assignment half retracted (`role:manage` is correct, §8.4). DEP-6C-12 added (invitation-token↔membership durable-linkage gap, §9.2). Pass 2: **DEP-6C-13** added (concurrent duplicate-pending-invitation race, §9.3.2), **DEP-6C-14**/**DEP-6C-15** added (DSR `verify`/`hold` and user-profile-edit audit gaps, §19). Pass 3: no dependency added — organization-creation's `CompliancePolicy` seeding and activation's `organizations.compliance_policy_id` pointer update were redesigned as genuinely event-driven (§7.7, §12.2, Blockers 1–2), at the time believed to require no new dependency. Pass 4: An independent review verified — by direct search of every Phase 5 document and the 5K migration manifest/directory — that **no concrete Postgres transactional-outbox table exists anywhere in the frozen schema**, even though Redis Streams (the event bus) and the transactional-outbox pattern are both approved, frozen architecture (Phase 2, 3A §6.3, 4A §5.1). Pattern approval is not table existence. **DEP-6C-16 is added** to name this precisely. This pass also normalizes the invitation-concurrency wording (a prior draft stated the possible pending-row count inconsistently in two places, §9.3.2/§25) and retracts an overstated compliance-pointer-staleness bound (§12.2). Pass 5: minimal consistency cleanup, no register change. **Pass 6 (Revision 6, this pass) — a controlled Phase 5.x dependency-closure package resolves six items in one coordinated amendment:** DEP-6C-07/10/11/14/15 (audit-vocabulary gaps) are resolved by a governance-only amendment to `5J-Analytics-Audit-Schema.md` §14.3 (ten new canonical `action_kind` values; no SQL migration required — verified directly that `chk_ae_action_kind` is a length check, not an enum). DEP-6C-16 (transactional-outbox persistence) is resolved by a new migration, `077_5J1.sql` (`audit.domain_event_outbox` + three `SECURITY DEFINER` claim/publish/fail functions), added after and on top of the validated 001-076 baseline, changing no existing Phase 5 object. Full detail, rationale, and the honest residual (live-database execution of `077_5J1` has not occurred in this session) are in each row below and in `5K/validation/077_5J1_VALIDATION_REPORT.md`. **This register now contains 16 total dependency records: 7 resolved (DEP-6C-02, -07, -10, -11, -14, -15, -16) + 9 open (DEP-6C-01, -03, -04, -05, -06, -08, -09, -12, -13).** Materially different problems are kept in separate entries — DEP-6C-12 (which token belongs to which membership) and DEP-6C-13 (whether a duplicate pending row can be created at all) remain open, logically distinct, non-blocking residuals, unaffected by this pass.

| ID | Description | Why needed | Current status | Required phase | Requires Phase 5.x? | Blocks 6C architecture? | Blocks 6C implementation? |
|---|---|---|---|---|---|---|---|
| DEP-6C-01 | Organization reactivation mechanism (no tenant-facing permission exists; DDD names Platform Admin as issuer) | 5B's frozen matrix has no `organization:reactivate`; a suspended org currently has no designed path back to `ACTIVE` | Explicitly deferred (§7.4) | Future Admin Control Plane API | Possibly (a permission-catalog addition) | **No** | Yes — for self-service or admin-triggered reactivation specifically; suspend/cancel are implementable today |
| **DEP-6C-02 — RESOLVED this pass** | ~~6B's `get_user_organization_ids()` / login-continuation query does not filter `accepted_at`~~ | Previously: an invited-but-not-accepted existing user could appear as having org access before completing acceptance | **CLOSED** — §9.3/§9.6's corrected design (pending invitations use `status='SUSPENDED'`) removes the vulnerability using only the frozen 3-value enum; 6B's `get_user_organization_ids()`, `PermissionEvaluationService` step 1, and login-continuation flow are all unmodified and now correctly exclude pending rows without any upstream change | N/A — resolved | N/A | N/A | **No** |
| DEP-6C-03 | No `team:*` permission exists in the frozen catalog | Team CRUD reuses `organization:update` as an interim, grounded mapping (§10.1) | Interim mapping specified and implementable today | Future Phase 5.x permission-catalog seed addition | Yes (new seed rows, no structural change) | **No** | No — the interim mapping is fully functional today |
| **DEP-6C-04 — narrowed this pass** | ~~No `UNIQUE (team_id, user_id)` constraint on `team_memberships`~~ **retracted — the index already exists (`uq_team_memberships_active`, 5B §13/§33.3, §10.2).** Remaining scope: no cascading membership-status reconciliation for teams (stale entries after org-membership suspension/removal are not auto-cleaned) | Stale team entries for suspended/removed org members are cosmetic/display-only issues, surfaced via the `membership_status` flag (§10.2), not an access-control gap | Documented residual, UI-level mitigation implementable today | Future Phase 5.x (a reconciliation job, if ever built) | Yes, for an automated reconciliation job specifically | **No** | No — functional today with the disclosed, cosmetic residual |
| DEP-6C-05 | No `user_preferences` table (ADR-5B-006 confirms) | User-level timezone/locale/default-org preference cannot be exposed — not fabricated | Not designed, per Hard Stop | Future Phase 5.x | Yes | **No** | N/A — no such feature exists to block |
| DEP-6C-06 | Email-change endpoint not designed (credential-adjacent, arguably 6B's territory but not built there either) | A user cannot currently change their own login email via any Phase 6 document | Explicitly named gap, not silently dropped | Future 6B revision or Phase 8 | No (Phase 5B already has the `email`/`email_normalized` columns) | **No** | Yes — for this specific capability only |
| **DEP-6C-07 — RESOLVED (Revision 6)** | ~~No `ORGANIZATION_CANCELLED` `action_kind`~~ **`ORGANIZATION_CANCELLED` added to `5J-Analytics-Audit-Schema.md` §14.3's governed vocabulary** | Organization cancellation (§15.7) now has a durable, exact-match audit mapping | **RESOLVED** — governance-only amendment, no SQL migration (`chk_ae_action_kind` is a length check, not an enum; verified directly against `072_5J.sql`) | N/A — resolved this pass | Yes (documentation/governance only) | **No** | **No** — §15.7 now writes `ORGANIZATION_CANCELLED` synchronously, Category A |
| DEP-6C-08 | Organization cancellation does not cascade into billing/subscription closure | Billing is a later phase; this document does not fabricate a cross-phase cascade | Disclosed, not designed | Future Billing/Usage phase | No | **No** | Yes — for a complete self-service closure flow; the status-transition itself is implementable today |
| **DEP-6C-09 — narrowed this pass** | ~~No `member:role_assign`/`member:manage`/`member:reactivate` permission exists~~ **the role-assignment half is retracted — role assignment now correctly uses the existing, seeded `role:manage` permission (5B §37.6), not an invented interim mapping (§8.4).** Remaining scope: no dedicated `member:reactivate` permission | Member reactivation (§15.12) reuses `member:suspend` as an interim, grounded mapping (suspend/reactivate are a natural pair) | Interim mapping specified and implementable today | Future Phase 5.x permission-catalog seed addition | Yes (new seed row, no structural change) | **No** | No — the interim mapping is fully functional and safe today (guarded by the `accepted_at IS NOT NULL` check, §15.12) |
| **DEP-6C-10 — RESOLVED (Revision 6)** | ~~No `MEMBER_REACTIVATED` `action_kind`~~ **`MEMBER_REACTIVATED` added to 5J §14.3 (mirrors the existing `ORGANIZATION_REACTIVATED` verb)** | Member reactivation (§15.12) now has a durable, exact-match audit mapping | **RESOLVED** — governance-only amendment, no SQL migration | N/A — resolved this pass | Yes (documentation/governance only) | **No** | **No** — §15.12 now writes `MEMBER_REACTIVATED` synchronously, Category A |
| **DEP-6C-11 — RESOLVED (Revision 6)** | ~~No `TEAM_*` `action_kind` values exist at all~~ **`TEAM_CREATED`/`TEAM_UPDATED`/`TEAM_ARCHIVED`/`TEAM_MEMBER_ADDED`/`TEAM_MEMBER_REMOVED` added to 5J §14.3 — the largest single audit gap this document found, now fully closed** | Every team mutation (create/update/archive/member-add/member-remove) now has a durable, exact-match audit mapping (§19) | **RESOLVED** — governance-only amendment, no SQL migration | N/A — resolved this pass | Yes (documentation/governance only) | **No** | **No** — §15.20–§15.27 now write the five team `action_kind` values synchronously, Category A |
| **DEP-6C-12 — SECURITY-ADJACENT** | `identity.password_reset_tokens` has no `membership_id`/`organization_id`/`role_id`/`invitation_id` column — the server cannot, from durable state alone, identify which token row belongs to which pending invitation when a user holds more than one concurrent pending invitation (§9.2 Gap B) | Blocks a fully-safe `resend` implementation of the stated invariant "after resend, exactly one invitation token for that invitation may remain valid" (§9.4); does **not** block `cancel` (safe via the membership-state guard alone, §9.4) or `accept` (safe via the client-supplied raw token's cleartext `membership_id` prefix, §9.3.1) | Design contract specified (§9.4); current implementability explicitly marked BLOCKED for the resend-invalidation guarantee only; bounded, disclosed residual risk in the interim (§9.4, §24) | Future Phase 5.x schema addition (example only, not chosen: a `membership_id` column on `password_reset_tokens`, or a dedicated invitation table) | Yes | **No** — does not permit unauthorized tenant access (§9.6 already closes that); the residual risk is narrower (old-token-still-works for an already-intended grant) | **Yes** — specifically for the resend-invalidation guarantee; every other invitation operation is fully implementable today. **Affects: revocation/invalidation strength and security-adjacent token-lifecycle integrity — corrected this pass (was inaccurately labeled "auditability/data-integrity only"; no audit requirement actually depends on this dependency, so "auditability" is removed).** |
| **DEP-6C-13 — new this pass (Blocker 3)** | No DB constraint covers `(organization_id, user_id) WHERE status='SUSPENDED' AND accepted_at IS NULL` — two genuinely concurrent `POST .../invitations` calls for the same `(org, user)` can both insert a pending row (§9.3.2 point 5) | The application-layer duplicate check is a `SELECT`-then-branch, not atomic; no unique index protects the pending-creation-time invariant (only the `ACTIVE`-time invariant is protected, by `uq_memberships_active`) | Contained, not a security gap: at most one duplicate pending row can ever reach `ACTIVE` (5B's existing `uq_memberships_active` index); the second acceptance attempt is mapped to a clean `409 STATE_CONFLICT` (§9.3.1 step 4). Tests corrected this pass to assert only the enforceable outcome (§25) | Future Phase 5.x schema addition (example only: a partial unique index on `(organization_id, user_id) WHERE status='SUSPENDED' AND accepted_at IS NULL`) | Yes | **No** | No — fully functional today with the disclosed, contained residual. **Affects: data-integrity/UX dimension only (duplicate emails), not security.** |
| **DEP-6C-14 — RESOLVED (Revision 6)** | ~~No 5J `action_kind` adequately represents DSR `verify`/`hold` transitions~~ **`DATA_SUBJECT_REQUEST_VERIFYING`/`DATA_SUBJECT_REQUEST_ON_HOLD` added to 5J §14.3, named to match `data_subject_requests.status`'s own values exactly** | These are genuinely state-changing (mutate `data_subject_requests.status`) and 6A §22 requires durable audit for every state-changing endpoint | **RESOLVED** — governance-only amendment, no SQL migration; no reuse of `DATA_SUBJECT_REQUEST_RECEIVED` was needed | N/A — resolved this pass | Yes (documentation/governance only) | **No** | **No** — §15.34/§15.35 now write exact-match `action_kind` values synchronously, Category A. **Affects: auditability/compliance dimension (`NFR-SEC-004`) — now satisfied.** |
| **DEP-6C-15 — RESOLVED (Revision 6)** | ~~No 5J `action_kind` adequately represents a user-profile-field edit~~ **`USER_PROFILE_UPDATED` added to 5J §14.3** | `PATCH /users/me` is genuinely state-changing (mutates `identity.users`); 6A §22 requires durable audit for every state-changing endpoint | **RESOLVED** — governance-only amendment, no SQL migration | N/A — resolved this pass | Yes (documentation/governance only) | **No** | **No** — §15.39 now writes `USER_PROFILE_UPDATED` synchronously, Category A. **Affects: auditability/compliance dimension (`NFR-SEC-004`) — now satisfied.** |
| **DEP-6C-16 — RESOLVED — LIVE VERIFIED (Revision 7)** | ~~No concrete, durable Postgres transactional-outbox relation exists anywhere in the frozen Phase 5 schema~~ **`audit.domain_event_outbox` added by migration `077_5J1.sql`** (Alembic revision `077_5J1`, `down_revision=076_5K1`) — a concrete relation with **17** typed columns, **7** `CHECK` constraints + 1 `PRIMARY KEY`, 4 indexes, no RLS by design (5B §16.3 precedent), plus `audit.fn_claim_outbox_events()` (`SELECT ... FOR UPDATE SKIP LOCKED`), `audit.fn_mark_outbox_published()`, `audit.fn_mark_outbox_failed()`. Redis Streams (Phase 2) and the transactional-outbox *pattern* (Phase 2/3A, 3A §6.3) remain approved, frozen architecture, now backed by an actual table | Previously blocked crash-safe, durable delivery of `organization.created` (→ `CompliancePolicy` seeding, §7.7) and `compliance.policy_activated` (→ `organizations.compliance_policy_id` pointer update, §12.2); both flows now write real, uncommented `INSERT`s into this relation in the same transaction as their domain mutation | **RESOLVED — LIVE VERIFIED (Revision 7)** — migration authored, structurally validated, committed to the 5K migration package (`MIGRATION_MANIFEST.md` row 077), and **executed against a genuinely fresh PostgreSQL 18 database**: single-head Alembic upgrade (001→077), exact live column/constraint/index/function inventory, `SECURITY DEFINER`/`search_path` hardening, `app_api`/`app_worker`/`app_readonly` grant boundaries, atomic domain+outbox COMMIT/ROLLBACK, both event flows' insert+claim, a genuine two-connection concurrency race (0 double-claims/20 rows), wrong-worker rejection, retry/failure, max-attempts→FAILED, stale-claim recovery, and a full security/Alembic regression pass — all PASS (`5K/validation/077_5J1_VALIDATION_REPORT.md`, `5K/execution_logs/README.md`'s "Fifth batch"). No residual remains | Delivered and live-verified this pass — no further work required for DEP-6C-16 | Yes — delivered | **No** — both request-transaction designs already conformed to 6A §35 independent of this dependency; that remains true now that it is resolved | **No** — the outbox relation and its claim/publish/fail functions exist, are structurally correct, and are live-verified; §7.7/§12.2 write real SQL against it. **Affects: implementation/infrastructure-completeness dimension — fully resolved, live-execution proof complete, no longer a disclosed residual.** |

**Reading the last two columns:** identical convention to 6B §36.3 — "Blocks 6C architecture?" is **No** for every item, including all six resolved. "Blocks 6C implementation?" was **Yes** for DEP-6C-07/10/11/14/15/16 through Revision 5; **all six became No as of Revision 6's schema/governance closure, and DEP-6C-16 specifically is now additionally LIVE VERIFIED as of Revision 7**, closing the one residual Revision 6 had left disclosed-but-open. DEP-6C-07/10/11/14/15 previously collectively caused condition 5 of §31's final-approval rule ("all mandatory 6A audit requirements are satisfiable") to fail; DEP-6C-16 was the exact blocking reason condition 6's *implementation* half was not realizable end-to-end, and its live-execution/concurrency/security half is what condition 6 required before this document could honestly claim APPROVED/FROZEN under the governing task's stricter gate. **Both conditions are now satisfied with live evidence (§31, §31.2)** — this is what allows this document's overall status to be APPROVED/FROZEN. DEP-6C-12/13 remain open, disclosed, contained, non-approval-blocking residuals, unaffected by this pass — they do not themselves permit unauthorized access or invalidate any design decision, and neither requires a further Phase 5.x change to keep this document's status at APPROVED/FROZEN.

---

## 28. Architecture Decision Records

| ID | Decision | Alternatives considered | Rationale | Status |
|---|---|---|---|---|
| ADR-6C-01 | Organization self-suspend is `OWNER`-only, tenant-facing (not Platform-Admin-only as 4A's DDD narrative implies) | Platform-admin-only suspend (matching 4A's command comment literally); no self-service suspend at all | The frozen 5B role-permission matrix is the authoritative artifact per this project's own established precedent (6B ADR-6B-08); it grants `organization:suspend` to OWNER, a real, seeded, tenant-facing permission the DDD narrative's aspirational comment does not override | Decided |
| ADR-6C-02 | Guarded state transitions (org status, membership status/role, team archive, compliance-policy activation, DSR status) use an atomic conditional `UPDATE ... RETURNING` (CAS), no API-layer lock, in the absence of a bespoke Phase-5 `SECURITY DEFINER` function | Add new `SECURITY DEFINER` functions (rejected — modifies frozen Phase 5); use `SELECT ... FOR UPDATE` (rejected — violates frozen 6A §17.3, exactly the mistake 6B's own ADR-6B-01 had to correct) | Directly reuses the same class of mechanism 6B already established and 6A §17.3/ADR-6A-08 already sanctions; requires no Phase 5 change | Decided |
| ADR-6C-03 (revised this pass) | Invitations are represented by an early-created `organization.memberships` row using **`status='SUSPENDED'`** (not `'ACTIVE'` — corrected, §9.6) with `accepted_at=NULL` as the pending signal, plus an `identity.password_reset_tokens` row (`purpose='INVITATION'`), with the raw token structured as `{membership_id}.{secret}` for client-side (accept-time) lookup only | `status='ACTIVE'` at invite time (the original draft's choice — **retracted**: verified to let an invited-but-unaccepted existing user pass 6B's own frozen `get_user_organization_ids()`/`PermissionEvaluationService` checks, a real security defect); a dedicated `organization.invitations` table (rejected — modifies frozen Phase 5); a fabricated `INVITED` enum value (rejected — explicitly forbidden, and unnecessary once `SUSPENDED` was verified to work); one pending invitation per user platform-wide (considered, rejected as unnecessarily restrictive) | `SUSPENDED` is the only one of the frozen schema's three status values that both (a) is disambiguable from a real accepted state via `accepted_at`, and (b) is independently verified, against 6B's actual frozen queries, to be already excluded from every access-granting check (§9.6) — closing a genuine security gap with zero upstream change. The `{membership_id}.{secret}` token format is retained from the original design and remains sufficient for the accept flow (§9.3.1), but is now explicitly documented as **not** sufficient for server-initiated resend/cancel lookup (§9.2 Gap B, DEP-6C-12) — a limitation this ADR no longer glosses over | Decided (revised — see also ADR-6C-05) |
| ADR-6C-04 | Team mutations are gated by `organization:update` (no dedicated `team:*` permission exists) | Invent a new `team:manage` permission string (rejected — violates the explicit instruction not to invent permissions silently); gate by `member:invite` (rejected — semantically wrong, teams are not membership) | Teams are structurally embedded in the Organization aggregate per 4A §5.1's own transaction-boundary language; `organization:update` is the existing permission governing every other Organization-aggregate-internal mutation | Decided (interim — DEP-6C-03) |
| ADR-6C-05 (new this pass) | Member reactivation (`POST .../members/{id}/reactivate`) requires `accepted_at IS NOT NULL` in addition to `status='SUSPENDED'` | No guard beyond `status='SUSPENDED'` (the original design — **retracted**: would let this endpoint be used to bypass invitation-token acceptance entirely, since pending invitations now also carry `status='SUSPENDED'` under ADR-6C-03's corrected design) | A direct, necessary consequence of reusing `SUSPENDED` as the invitation pending-placeholder value (ADR-6C-03) — without this guard, ADR-6C-03's fix would introduce a *new* access-control bypass exactly where it closed the original one | Decided |
| ADR-6C-06 (new this pass) | Membership role assignment (`POST .../members/{id}/role`) is gated by `role:manage`, not `member:invite` | `member:invite` (the original draft's interim mapping — **retracted**: 5B §37.6 explicitly names `role:manage` as the frozen design's own intended control for exactly this scenario, so no interim/invented mapping was ever needed) | 5B §37.6's "Privilege Escalation Prevention" table is dispositive: `role:manage` is a real, seeded permission (5B §17.1/§17.2) already held by the correct actor set (`OWNER`/`ADMIN`); using it is a correction of a prior misreading of the frozen catalog, not a new architectural decision | Decided |
| ADR-6C-07 (new this pass) | Invitation token expiry (`INVITATION` purpose) is **7 days**, fixed, not per-org-configurable | 5B's generic "`created_at + 1 hour`" design note for `password_reset_tokens.expires_at` (considered and rejected as the `INVITATION`-specific value — read as `PASSWORD_RESET`-oriented, since 5B explicitly delegates the actual duration to the application layer and the column carries no `CHECK` tying it to `created_at`); 4A's full "configurable via Feature Flag per organization" rule (rejected as implemented — Feature Flags are deferred out of 6C's scope, §5) | 4A's business rule is purpose-specific and product-grounded (an emailed invitation is not realistically opened within an hour, unlike an in-session password reset); 5B does not structurally forbid a purpose-specific value; retaining 7 days as a fixed default is a disclosed simplification of 4A's rule, not a silent drop of it | Decided (§9.2a) |
| ADR-6C-08 (new this pass) | Invitation creation is **idempotent by `(organization_id, user_id, role_id)`** for a still-pending invitee — a repeated create with the same parameters reuses the existing `membership_id` and mints a fresh token (`200`), rather than failing `409` | Bare `409 INVITATION_ALREADY_PENDING` on every duplicate-pending hit (the original design — **retracted**: this was Blocker 2's named dead end, since a retry after a token-insert failure had no path forward); a distributed transaction across `identity.users`/`organization.memberships`/`identity.password_reset_tokens` (rejected — 6A forbids inventing distributed-transaction machinery, and no infrastructure exists for it) | Closes the partial-failure stranding gap using only existing schema/endpoints — the same effect as calling `resend`, reached automatically by a natural retry of `create`, with no new table, column, or job infrastructure. A **different** `role_id` on retry still surfaces `409`, preserving the code's meaning for genuinely ambiguous intent | Decided (§9.3, §9.3.2) |

No ADR was created for trivial implementation choices (exact JSON field names, exact rate-limit numbers) — only for genuine architectural gaps this document had to close, matching 6A/6B's own restraint.

---

## 29. Implementation Readiness Matrix

| Area | Design status | Contract status | Phase 5 backing | Authz backing | Implementation status | Dependency | Notes |
|---|---|---|---|---|---|---|---|
| Organization CRUD | COMPLETE | COMPLETE | Full | Full | READY — creation's request transaction (Org + owner Membership + outbox event) is fully implementable, conforms to 6A §35, and now writes into a concrete relation (`audit.domain_event_outbox`, migration `077_5J1.sql`, DEP-6C-16 RESOLVED); `CompliancePolicy` seeding is architecturally and now durably event-driven; manual recovery path remains available for any consumer-health degradation | None (live-database execution of `077_5J1` is complete and LIVE VERIFIED — Revision 7, §31.2) | §7, §15.1–§15.3 |
| Organization lifecycle (suspend/cancel) | COMPLETE | COMPLETE | Full | Full | READY (suspend and cancel alike — `ORGANIZATION_CANCELLED` now exists, DEP-6C-07 RESOLVED) | None | §7.4, §15.6–§15.7 |
| Organization reactivation | DEFERRED | DEFERRED | N/A | Missing permission | BLOCKED (not designed) | DEP-6C-01 | §7.4 |
| Membership listing/role/suspend/reactivate/remove/leave | COMPLETE | COMPLETE | Full | Full (`role:manage` for role-assign; interim mapping remains only for reactivate permission) | READY (audit fully covered — `MEMBER_REACTIVATED` now exists, DEP-6C-10 RESOLVED) | DEP-6C-09 (reactivate permission only — unaffected by this pass) | §8, §15.8–§15.14 |
| Ownership transfer | COMPLETE | COMPLETE | Full | Full (identity-bound) | READY | None | §8.5, §15.15 |
| Invitation creation/list/cancel | COMPLETE | COMPLETE | Full, via the reconciled ADR-6C-03 (revised) + ADR-6C-08 (idempotent re-invite) mechanism | Full | READY — including self-healing partial-failure retry (§9.3.2) | DEP-6C-13 (narrow, contained concurrent-duplicate race, non-blocking — unaffected by this pass) | §9, §15.16, §15.17, §15.19 |
| Invitation resend | COMPLETE | CONTRACT COMPLETE | Full for token issuance; missing linkage for token invalidation | Full | **IMPLEMENTATION DEPENDENCY** — the endpoint works, but its stated "old token invalidated" guarantee does not hold when the invitee has another concurrent pending invitation | DEP-6C-12 (unaffected by this pass) | §9.4, §15.18 |
| Teams + team membership | COMPLETE | COMPLETE | Full — including DB-enforced duplicate-membership protection (`uq_team_memberships_active`) | Interim (`organization:update`) | READY — audit fully covered (`TEAM_CREATED`/`UPDATED`/`ARCHIVED`/`MEMBER_ADDED`/`MEMBER_REMOVED` now exist, DEP-6C-11 RESOLVED) | DEP-6C-03 (permission-vocabulary interim mapping — unaffected by this pass) | §10, §15.20–§15.27 |
| Compliance policy | COMPLETE | COMPLETE | Full — activation's request transaction is fully implementable, conforms to 6A §35; the `organizations.compliance_policy_id` convenience-pointer update now writes into a concrete relation (DEP-6C-16 RESOLVED) | Full | READY | None (live-database execution of `077_5J1` is complete and LIVE VERIFIED — Revision 7, §31.2) | §12, §15.28–§15.30 |
| Data subject requests | COMPLETE | COMPLETE | Full | Full | READY — including verify/hold (`DATA_SUBJECT_REQUEST_VERIFYING`/`_ON_HOLD` now exist, DEP-6C-14 RESOLVED) | None | §13, §15.31–§15.37 |
| User profile | COMPLETE | COMPLETE | Full (narrow slice) | N/A (self-scoped) | READY — including profile-edit audit (`USER_PROFILE_UPDATED` now exists, DEP-6C-15 RESOLVED) | DEP-6C-05 (preferences, not built — unaffected), DEP-6C-06 (email change, not built — unaffected) | §11, §15.38–§15.40 |
| Internal org/compliance reads | COMPLETE | COMPLETE | Full | Full | READY | None | §15.41–§15.42 |
| Audit (all endpoints — Category A/B, Category C now empty) | COMPLETE | COMPLETE | Full — every state-changing endpoint in this document's surface has an exact-match or adequately-reused `action_kind`, including the ten values added by the Revision 6 governance amendment | — | READY | None | §19 |
| Events | COMPLETE | COMPLETE | Internal bus only, no webhook | — | READY | None | §20 |
| OpenAPI | COMPLETE | COMPLETE | — | — | READY | None | §23 |
| Testing | COMPLETE (strategy) | — | — | — | READY | None | §25 |
| Observability | COMPLETE | COMPLETE | — | — | READY | None | (cross-cutting, reuses 6A §25/6B §26 patterns) |
| Caching | COMPLETE | COMPLETE | Full (5B §31) | — | READY | None | §21 |
| Performance | COMPLETE (TARGET) | — | — | — | READY | None | §22 |

---

## 30. Acceptance Checklist

- [x] All 6C-owned resources reconciled with frozen DDD (§5–§6), including the two aggregates (`CompliancePolicy`, `DataSubjectRequest`) 4I explicitly names "Core API"-owned.
- [x] Every resource mapped to frozen Phase 5 schema; no invented tables/columns (§5–§14).
- [x] No business-domain API leaked from later phases (§3.2, §5's DEFERRED rows).
- [x] Organization lifecycle fully specified, including the documented DDD-vs-DB-matrix conflict (§7.5) and the deliberately-deferred reactivation gap (§7.4, DEP-6C-01).
- [x] Membership lifecycle fully specified, including last-owner protection (§16.2) and the interim permission mappings (§17, DEP-6C-09) disclosed rather than silently invented.
- [x] Invitation lifecycle fully specified — the pre-acceptance authorization security gap (originally §9.6/DEP-6C-02) is **RESOLVED this pass** via a schema-free redesign (ADR-6C-03 revised, §9.3/§9.6), not merely disclosed; the narrower token-linkage gap affecting resend's invalidation guarantee (Gap B, DEP-6C-12) remains open and is honestly marked BLOCKED for that specific guarantee, not silently assumed to work (§9.4, §9.7).
- [x] Organization-creation transaction is RLS-correct — `FORCE ROW LEVEL SECURITY`/`WITH CHECK` on `memberships`/`compliance_policies` is not bypassed; `SET LOCAL app.tenant_id` is established from the newly-created organization's own ID before either dependent insert runs, under the ordinary `app_api` role, with no `BYPASSRLS` shortcut (§7.7, corrected this pass).
- [x] Team duplicate-membership protection correctly attributed to the frozen DB-level partial unique index (`uq_team_memberships_active`), not an invented application-layer TOCTOU mitigation (§10.2, corrected this pass).
- [x] Membership role assignment correctly gated by the frozen catalog's actual intended control (`role:manage`, per 5B §37.6), not an invented interim mapping (§8.4, corrected this pass).
- [x] Team lifecycle fully specified since teams are upstream-grounded (4A §5.1, embedded entity) — permission-vocabulary and audit-vocabulary gaps disclosed (DEP-6C-03/04/11), not fabricated around.
- [x] User profile boundary vs. `/auth/me` stated explicitly (§11.1); no credential/session/MFA field ever appears in a 6C response model.
- [x] Settings typed and allowlisted (§7.2) — no generic JSON settings bag.
- [x] Tenant context never client-trusted (§15.0, applied to every endpoint).
- [x] Cross-tenant behavior consistent (`404`, never `403`, throughout).
- [x] RLS remains independent defense-in-depth (§7.6, §16.4 note; API-layer checks never described as a substitute).
- [x] Permissions use the frozen catalog only — every place an exact permission does not exist is flagged as a dependency (§17, §27), never invented silently.
- [x] Owner/last-owner invariants addressed with a concrete, tested query pattern (§16.2).
- [x] State transitions use command/action endpoints where 6A §8.3 requires it, PATCH reserved for genuinely free-form fields (§7.2 vs. §7.4).
- [x] Every one of the 42 endpoints fully contracted per §15.0's template — none left as "apply the template only."
- [x] Pagination/filter/sort allow-listed per 6A §14–§15 (§16.1).
- [x] Idempotency decided per mutating endpoint (§16.3).
- [x] Concurrency strategy specified and 6A-§17.3-compliant — no API-layer lock anywhere (§16.4, ADR-6C-02).
- [x] No prohibited API-layer locking introduced.
- [x] Audit mapped honestly — Category A/B/C split stated explicitly (§19); Category C is now empty as of Revision 6, closed by a controlled Phase 5.x governance amendment to 5J §14.3 (ten new `action_kind` values), not by silently inventing vocabulary — every value's addition is recorded in `5J-Analytics-Audit-Schema.md` §14.3's own footnote, not merely asserted here.
- [x] Events mapped, internal-vs-webhook distinction preserved per 6A §28.3 (§20).
- [x] PII exposure matrix complete (§14), least-privilege applied to member email visibility rather than auto-exposing it to every member.
- [x] Rate limits defined as configurable defaults (§15 per-endpoint).
- [x] Latency figures labeled TARGET (§22).
- [x] OpenAPI schemas complete (§23).
- [x] Threat model complete, including every currently disclosed residual (§24): the pre-acceptance-authorization finding at §9.6 is **RESOLVED**, not an open finding (a prior checklist wording incorrectly implied it remained unresolved — corrected this pass); the invitation-token-invalidation gap (DEP-6C-12) and the concurrent-duplicate-pending-invitation race (DEP-6C-13) remain genuinely open and are both listed as distinct rows, neither described as "the one" remaining item (§9.7).
- [x] Test strategy complete, including invitation-specific tests not inherited from 6B (§25).
- [x] Traceability complete (§26).
- [x] Dependency register complete — **16 items (9 open + 7 resolved), up from 11 across six correction passes** — every "blocks 6C architecture" cell honestly `No`; as of Revision 6, every "blocks 6C implementation" cell that previously read `Yes` for DEP-6C-07/10/11/14/15/16 now reads `No` (§27, §31).
- [x] Verified, not assumed: the Revision 6 Phase 5.x dependency-closure package's own claims were checked against the actual committed artifacts before being reported resolved — `chk_ae_action_kind` re-confirmed as a length check (not an enum) before concluding no SQL migration was needed for the audit-vocabulary half; `audit.domain_event_outbox`'s existence, column list, constraints, indexes, and grants re-confirmed by direct inspection and checksum reconciliation against `MIGRATION_MANIFEST.md` before concluding DEP-6C-16 resolved (§7.7, §12.2, §27, `5K/validation/077_5J1_VALIDATION_REPORT.md`) — not fabricated as already solved because an architecture-layer pattern was previously approved.
- [x] Invitation-concurrency wording normalized — a prior draft stated the possible pending-row count under concurrency inconsistently in two places; both now read identically and assert only the actual enforceable invariant (`uq_memberships_active` bounds activation, not creation) (§9.3.2, §24, §25).
- [x] Compliance-pointer staleness claim corrected — the retracted "cannot drift more than one activation behind" bound is replaced with the honest rule that `compliance_policies.status='ACTIVE'` is sole authoritative and the pointer may remain arbitrarily stale while its consumer is unhealthy, with no read/enforcement path ever depending on its freshness (§12.2).
- [x] Invitation-list/predicate consistency swept end-to-end (§9.4, §15.8, §15.17) against the canonical membership state table (§8.1a) — no remaining occurrence of the retracted `status='ACTIVE' AND accepted_at IS NULL` pending representation.
- [x] Invitation-creation partial-failure recovery specified and self-healing for sequential retries; the narrower concurrent-duplicate race honestly disclosed, not claimed away (§9.3.2, DEP-6C-13, Blockers 2 & 3).
- [x] Invitation-token expiry conflict (4A's 7 days vs. 5B's generic 1-hour note) explicitly reconciled, not silently picked (§9.2a, ADR-6C-07).
- [x] Organization-creation and compliance-policy-activation cross-aggregate effects are now **genuinely event-driven**, per 6A §35's actual rule ("synchronous response must never wait for downstream effects") — corrected this pass (Blocker 1, Blocker 2): a prior pass's fix (a second, synchronous transaction in the same request) was itself insufficient and is retracted; `CompliancePolicy` seeding and the `organizations.compliance_policy_id` pointer update are both now relayed via the platform's existing transactional-outbox + Redis Streams mechanism (3A §6.3), with the response returned once the sole 6A-§35-authorized synchronous transaction commits, and documented, fully-implementable-today manual recovery paths for both (§7.7, §12.2).
- [x] Every state-changing endpoint re-audited against 6A §22's binding (not discretionary) rule; three mutations previously mislabeled "deliberate non-gap" are now correctly tracked as genuine dependencies (DEP-6C-14, DEP-6C-15) and compliance-policy draft creation is now correctly audited (Blocker 4).
- [x] `400` vs. `422` usage reconciled against 6A §7.4's exact definitions throughout §7, §15, §18 (Cleanup 1).
- [x] **Phase 5 modification limited exactly to the explicitly-authorized Revision 6 controlled amendment** — one new migration (`077_5J1.sql`, additive only, no existing 001-076 object altered) and one governance-only vocabulary addition to `5J-Analytics-Audit-Schema.md` §14.3 (no SQL); no other Phase 5 document, table, column, function, or RLS policy touched. Every prior pass (Revisions 1-5) made no Phase 5 modification at all — this is the one explicitly-authorized exception, scoped and disclosed, not a general reopening of Phase 5.
- [x] No 6A modification.
- [x] No 6B modification — the invitation-token-format clarification (§9.3) is additive to an area 6B explicitly deferred, not a redefinition of any 6B endpoint contract, status code, or claim.
- [x] No 6D+ work.
- [x] No hidden TBD blocking core behavior — every open item is a named, scoped dependency with an interim, working mechanism, exactly matching the discipline 6B itself established.

---

## 31. Final Status

**PHASE 6C ARCHITECTURE:** COMPLETE

**PHASE 6C API CONTRACT:** COMPLETE for every endpoint except one specific, narrow guarantee: `POST .../invitations/{membership_id}/resend`'s "old token becomes unusable" property is **CONTRACT COMPLETE / IMPLEMENTATION BLOCKED** (DEP-6C-12) — the endpoint itself, its request/response shape, and every other endpoint in this document are fully specified and implementable.

**PHASE 6C SECURITY / TENANT DESIGN:** The pre-acceptance unauthorized-access blocker is **RESOLVED** — verified directly against 6B's actual frozen queries and pseudocode (§9.6). No path exists, under the corrected design, for an unaccepted invitation to grant tenant access (§9.7 scenario A). The remaining invitation-related residuals (DEP-6C-12 token-invalidation, DEP-6C-13 concurrent-duplicate-pending-row race) are both verified, not merely asserted, to be non-access-granting (§9.3.1 step 4's `uq_memberships_active` containment, §9.3.2 point 5).

**PHASE 6C TRACEABILITY:** COMPLETE

**PHASE 6C IMPLEMENTATION READINESS:** CONDITIONAL — every capability is READY except: organization reactivation (not designed, DEP-6C-01), the resend token-invalidation guarantee (DEP-6C-12), the narrow concurrent-duplicate-pending-invitation race (DEP-6C-13), an email-change endpoint (DEP-6C-06), and user preferences (DEP-6C-05, not backed by any schema) — none of these five is a condition of this document's own final-approval rule (§31.1), and none is newly affected by this pass. **Durable audit for all five previously-gapped event categories (DEP-6C-07/10/11/14/15) are RESOLVED, and crash-safe, automated `CompliancePolicy` seeding/pointer propagation (DEP-6C-16) is RESOLVED — LIVE VERIFIED, as of Revision 7** — see §31.2 for the full closure-package evaluation, now backed by live PostgreSQL execution evidence rather than static/structural review alone.

### 31.1 Final-Approval Rule — Evaluated Condition by Condition (re-evaluated this pass, Revision 7)

| # | Condition | Status | Basis |
|---|---|---|---|
| 1 | No unaccepted invitation can grant tenant access | **SATISFIED** | §9.6 — verified against 6B's actual frozen queries/pseudocode |
| 2 | Invitation creation cannot leave an unrecoverable stranded state | **SATISFIED** | §9.3.2 points 1–4 — self-healing for all sequential-retry failure modes via ADR-6C-08's idempotent re-invite |
| 3 | Invitation concurrency guarantees stated in this document are actually enforceable | **SATISFIED** | §9.3.2 point 5, §25 — the deterministic-`409` claim was retracted; only the CAS/unique-index-backed containment guarantee is now claimed, and it is real |
| 4 | Resend guarantees implementable or explicitly removed/re-scoped | **SATISFIED (re-scoped)** | §9.4 — the invalidation guarantee is explicitly marked BLOCKED (DEP-6C-12) rather than falsely claimed |
| 5 | All mandatory 6A audit requirements are satisfiable | **SATISFIED (Revision 6)** | §19 — the five `action_kind` vocabulary gaps (DEP-6C-07/10/11/14/15) are resolved by the controlled Phase 5.x governance amendment to `5J-Analytics-Audit-Schema.md` §14.3 (ten new canonical values, no SQL migration — verified `chk_ae_action_kind` is a length check, not an enum). Every state-changing 6C endpoint now maps to an exact-match or adequately-reused `action_kind`; 6A §22's rule is satisfied without exception |
| 6 | Cross-aggregate transaction boundaries conform to frozen 6A | **SATISFIED — architecture, implementation, AND live evidence (Revision 7)** | §7.7, §12.2 — the **architecture** was already verified against 6A §35's actual rule in an earlier pass: `Organization` + owner `Membership` is the **only** synchronous cross-aggregate atomic exception used during organization creation; `CompliancePolicy` is written exclusively by an asynchronous consumer. The durable-outbox-INSERT step is schema-backed: migration `077_5J1.sql` adds `audit.domain_event_outbox`, and §7.7/§12.2 contain real, executable SQL against it, in the same transaction as each flow's domain mutation. **As of Revision 7, this is LIVE VERIFIED, not merely schema-backed:** the migration was executed against a genuinely fresh PostgreSQL 18 database (single head `077_5J1`, exit code 0); the atomic domain+outbox invariant was proven with real `COMMIT`/`ROLLBACK` transactions (both rows present/absent as expected, not reasoned about); both event flows were inserted and claimed live; a genuine two-connection concurrency race against `fn_claim_outbox_events` confirmed 0 double-claims across 20 rows; publish/retry/max-attempts/stale-claim-recovery semantics were all live-tested — see `5K/validation/077_5J1_VALIDATION_REPORT.md` and `5K/execution_logs/README.md`'s "Fifth batch" (files `51`-`62`) for full raw evidence |
| 7 | No endpoint contract contradicts the canonical invitation-state model | **SATISFIED** | §8.1a's table is matched by every predicate in §9.3, §9.4, §15.8, §15.17 — unaffected by this pass |
| 8 | No unresolved blocker remains | **SATISFIED (Revision 7)** | Direct consequence of conditions 5 and 6 now both being satisfied, condition 6 now with live evidence rather than a disclosed residual; DEP-6C-12/13 remain open but were never conditions of this rule and are unaffected by this pass |

**All eight conditions are now satisfied.** Conditions 1–4 and 7 were already satisfied through Revision 5. Condition 5 is satisfied by the controlled Phase 5.x governance amendment to 5J §14.3 — a genuine upstream governance decision, explicitly authorized for this one pass, not a unilateral 6C vocabulary invention. Condition 6 is satisfied at the architecture, implementation, **and now live-execution** level: migration `077_5J1.sql` was applied to a genuinely fresh PostgreSQL database and its table/constraints/indexes/functions/grants/concurrency behavior were all confirmed live, closing the residual Revision 6 had left disclosed-but-open. Condition 8 follows directly.

**PHASE 6C OVERALL: APPROVED/FROZEN**

### 31.2 Phase 5.x Dependency-Closure Package — Governing-Task Approval Gate (evaluated explicitly, not assumed)

The task authorizing this pass set an additional, more granular gate before this document may be marked APPROVED/FROZEN: **do not report a dependency as resolved merely because documentation was changed — a dependency is resolved only if the required backing implementation/governance now actually exists in the repository.** Each condition is evaluated against that literal test, individually:

| # | Condition | Status | Evidence |
|---|---|---|---|
| 1 | Audit mappings exist and endpoints can durably write | **TRUE** | `5J-Analytics-Audit-Schema.md` §14.3 amended with ten governed values; `audit.audit_events.action_kind` (`TEXT` + length `CHECK` only, migration `072_5J.sql`) already physically accepts them — no SQL migration needed and none was fabricated as needed |
| 2 | Concrete outbox exists | **TRUE** | `audit.domain_event_outbox`, migration `077_5J1.sql`, committed to `5K/migrations/`, referenced in `MIGRATION_MANIFEST.md` row 077 |
| 3 | Both event flows insertable atomically | **TRUE — LIVE VERIFIED (Revision 7)** | §7.7/§12.2 contain real SQL inserting the outbox row in the same transaction as each flow's domain mutation; **live-tested** with real `BEGIN`/`INSERT`×2/`COMMIT` and `BEGIN`/`INSERT`×2/`ROLLBACK` transactions against `organization.organizations` + `audit.domain_event_outbox` — both rows present after commit, both absent after rollback, verified by direct query, not schema-level reasoning alone; both `organization.created` and `compliance.policy_activated` inserted and successfully claimed. See `077_5J1_VALIDATION_REPORT.md` (LIVE DB VALIDATION section) and `execution_logs/..._56_...txt`/`_57_...txt` |
| 4 | Publisher semantics implementation-ready | **TRUE** | `fn_claim_outbox_events`/`fn_mark_outbox_published`/`fn_mark_outbox_failed` fully defined, at-least-once only (never exactly-once claimed), mirroring the already-proven `webhooks.fn_claim_delivery` pattern |
| 5 | Alembic accurately reflects migration | **TRUE** | `077_5J1.py`, `down_revision='076_5K1'`, no branching, wraps the frozen `.sql` verbatim via `run_frozen_sql()` — same pattern as every other revision |
| 6 | Manifest/checksums updated correctly | **TRUE** | `MIGRATION_MANIFEST.md` row 077; checksum/size re-verified via `sha256sum`/`wc -c` against the actual committed file in this pass, not merely copied from when the file was authored |
| 7 | Validation artifacts exist | **TRUE — LIVE VERIFIED (Revision 7)** | `5K/validation/077_5J1_VALIDATION_REPORT.md` — rewritten in place: **18/18 checks PASS with live PostgreSQL execution evidence** (static-only 13/13 predecessor preserved in the report's own revision history), backed by `5K/execution_logs/README.md`'s "Fifth batch" (files `51`-`62`) and `5K/EXECUTION_REPORT.md` §13 |
| 8 | No 6A §35 contradiction | **TRUE** | §7.7/§12.2 unchanged in their transaction-boundary shape from the already-verified Revision 3/4/5 design — only the outbox placeholder became real SQL |
| 9 | No reintroduction of invitation/security issues already solved | **TRUE** | §9.6 (pre-acceptance authorization), §9.3.1 step 2 (reactivate guard), §8.4 (`role:manage`) — none touched this pass |
| 10 | 6A untouched | **TRUE** | No edit made to any 6A document this pass |
| 11 | 6B untouched | **TRUE** | No edit made to any 6B document this pass |
| 12 | 6D not started | **TRUE** | No 6D document created or referenced as designed this pass |

**All twelve conditions are TRUE, and as of Revision 7 condition 3's former residual is closed with live evidence rather than disclosed as open.** Revision 6 had correctly and honestly disclosed that no live-database execution had been performed — that disclosure was accurate at the time and is preserved in the revision history above, not erased. This pass (Revision 7) supplies exactly that missing evidence: the atomicity/rollback claims are now backed by real executed `COMMIT`/`ROLLBACK` transactions against a genuinely fresh PostgreSQL 18 database, not schema-level reasoning alone, and are further reinforced by a live two-connection concurrency race (0 double-claims across 20 rows), live security/grant tests via `SET ROLE`, and a live regression pass confirming no security/Alembic regression from migration 077. Full raw evidence: `5K/execution_logs/README.md`'s "Fifth batch" section (files `51`-`62`, prefix `20260823T061055Z`).

**Exact status of each originally-blocking dependency:** DEP-6C-07 **RESOLVED**. DEP-6C-10 **RESOLVED**. DEP-6C-11 **RESOLVED**. DEP-6C-14 **RESOLVED**. DEP-6C-15 **RESOLVED**. DEP-6C-16 **RESOLVED — LIVE VERIFIED** (Revision 7 — no longer merely design/schema level; live execution, concurrency, and security validation are now complete and evidenced). **Remaining open, non-blocking dependencies, unaffected by this pass:** DEP-6C-01 (org reactivation, deferred), DEP-6C-03 (team permission interim mapping), DEP-6C-04 (team-membership reconciliation job, cosmetic), DEP-6C-05 (user preferences, not backed by schema), DEP-6C-06 (email-change endpoint), DEP-6C-08 (billing cascade on cancellation), DEP-6C-09 (reactivate-permission half only), DEP-6C-12 (resend token-invalidation guarantee), DEP-6C-13 (concurrent-duplicate-pending-invitation race). None of these nine was ever a condition of §31.1's eight-condition gate or this section's twelve-condition gate, and none is newly affected by this pass — DEP-6C-12 and DEP-6C-13 in particular retain exactly their prior, non-approval-blocking residual classification, untouched by this pass's schema/live-validation work.

**Confirmed:** 6A was not modified. 6B was not modified. 6D work was not begun. No 6C endpoint contract was redesigned — every change in this pass either replaced a disclosed-residual statement with live-verified evidence, or corrected an audit/event field that referenced the now-fully-resolved gap. No new SQL was written; `077_5J1.sql` was validated exactly as committed and found to need no defect fix.

---

**STOP — Phase 6C Revision 7 (live-validation closure pass) complete. Phase 6C status: APPROVED/FROZEN — architecture, implementation, and live database/concurrency/security evidence all confirmed. Phase 6D not started.**
