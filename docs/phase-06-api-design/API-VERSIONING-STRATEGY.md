# API Versioning Strategy

This document is the Phase-6 closure artifact that fixes, for every API surface of the platform, how a proposed change is classified, which version axis it moves, in what order it is rolled out, how each axis retires a predecessor (the public REST deprecation/sunset lifecycle applies to AX-A only), and which changes are prohibited without a source amendment. It is a reconciliation of frozen sources plus the resolved owner decisions AVS-OD-01..AVS-OD-11; it is not an implementation, and it creates no route, schema, OpenAPI document, SDK, dispatcher or migration.

## 0. Document Control / Source Baseline

### 0.1 Control

| Field | Value |
|---|---|
| Document | `docs/phase-06-api-design/API-VERSIONING-STRATEGY.md` |
| Phase | Phase 6 — API Design (closure artifact: API Versioning Strategy) |
| Status | Candidate for independent re-review |
| Baseline HEAD | `9192b48393ca9496dccd1dc794adefb0ded73a1d` |
| Owner decisions | 11/11 RESOLVED (AVS-OD-01..AVS-OD-11, §38) |
| Frozen-source amendments | 0 |
| Current majors | public REST `v1`; internal REST `v1`; WebSocket `v1` |
| Route baseline | 369 REST/internal/callback routes + 4 WebSocket routes (AMI) |
| Migration baseline | 112 SQL / 112 Alembic; root `001_5B`; sole head `112_5H5`; linear; no `113` |
| Normative keywords | MUST, MUST NOT, SHOULD, SHOULD NOT, MAY carry their RFC 2119 meaning |

### 0.2 Source Baseline

Hash-gated sources MUST match the SHA-256 below at review time; a mismatch invalidates this document's citations. Unhashed sources are informative only and bind no rule on their own.

| Key | Path | SHA-256 | Gate |
|---|---|---|---|
| 6A | `docs/phase-06-api-design/6A-API-Architecture-and-Standards.md` | `a13e295f8041627751bf0648d4c2b37aa665a096bb79ab758243b1bac69971ab` | hash-gated |
| 6B | `docs/phase-06-api-design/6B-Authentication-and-Authorization-API.md` | `f8b43a258fee15824fcc6323ac0bcd612ca1cfa4d9278095fc899b776bac6cfe` | hash-gated |
| 6C | `docs/phase-06-api-design/6C-Core-Platform-APIs.md` | `269b5978a72d5526d2a6ce5a332b6bbf2ba87b6d584a8e8d4b11c1836e26813c` | hash-gated |
| 6D | `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md` | `0971c372de32bd58f01521a3f493b7458b5fd103c9ac28f5a6ff95cd5dfafd42` | hash-gated |
| 6E | `docs/phase-06-api-design/6E-AI-Agent-APIs.md` | `6c9b500ac2afac65cf8b5c9f237170a72f29d4c468c4991f169c5f52145241bf` | hash-gated |
| 6F | `docs/phase-06-api-design/6F-Knowledge-RAG-APIs.md` | `8a38ce1f4f3def3b819c0bb3588d66f24d2be2757a5a2f3811a9d3a6a0d7a7f2` | hash-gated |
| 6G | `docs/phase-06-api-design/6G-CRM-Leads-APIs.md` | `907ca4165290932bc631c0d416bbe3b477a4bad0df8f1c22853ffc5189e56211` | hash-gated |
| 6H | `docs/phase-06-api-design/6H-Campaign-APIs.md` | `9639498818c48e1a6b9ecbf34312cf94e509929a89fb111f5b4320b695e28c18` | hash-gated |
| 6I | `docs/phase-06-api-design/6I-Workflow-APIs.md` | `00023a92b86230849fa6ff3ba076350a6e94037feba049ed377603bfdd792dbe` | hash-gated |
| 6J | `docs/phase-06-api-design/6J-Integrations-Webhooks-Plugins-APIs.md` | `adebb15b6f132816b2adfef5d3b62c93de18f31fbbd5885cafd05fc3640782a9` | hash-gated |
| 6K | `docs/phase-06-api-design/6K-Billing-Usage-APIs.md` | `db4df2883cdeafb41035176a5c8a5199088044ea00626a52e036fd862fa0d675` | hash-gated |
| 6L | `docs/phase-06-api-design/6L-Analytics-Audit-APIs.md` | `b268460c4fc954ce2d833415f058201afec7f8c74420d1d9ac7804d6c6ce96e9` | hash-gated |
| 6M | `docs/phase-06-api-design/6M-Admin-Platform-APIs.md` | `88684f96527fd7ceb14ab88ac5fcc5458d531f993625ddf1b7140ac7ad7dd0f8` | hash-gated |
| FAR | `docs/phase-06-api-design/FINAL-API-RECONCILIATION.md` | `5853982e7209d84f097405c6ad149f180013d6351645db3aaa7297553addbc3f` | hash-gated |
| AMI | `docs/phase-06-api-design/API-MASTER-INDEX.md` | `cb033a2f334aee1563d05e6db535b9d1a17038cf163ff4ea6925313cf9756c38` | hash-gated |
| AAM | `docs/phase-06-api-design/API-AUTHORIZATION-MATRIX.md` | `f61d2d742a3193803c36cf7b9b9f78ce974da35fac94c61ce238b334dfd94843` | hash-gated |
| AEC | `docs/phase-06-api-design/API-ERROR-CATALOG.md` | `2505acda65a07d98247bb2cbd5d3e28421bbf6cc75f7cfd0fff1ba07d7f65c7a` | hash-gated |
| SRS | `docs/phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` | `ee8a25c315a6a383e38d0a3c4674c2246240620325a84ddeb1e7d768a821a28b` | hash-gated |
| AP | `docs/product/ARCHITECTURE_PRINCIPLES.md` | `92b5e9153ec89eae9882f53c9792fd4f46cbc351ed0668e0fa0a7e0afb869af6` | hash-gated |
| 4F | `docs/phase-04-domain-driven-design/4F-Billing-Usage-Integrations.md` | `f759647c29bdaf7f0e7d2f824c5c1b2e15d516be1ae345539d2a20b2d4362638` | hash-gated |
| 5A | `docs/phase-05-database-design/5A-Database-Architecture-and-Standards.md` | `26f443c5f826aa7f3aba57482ccf7d8cd149b58d77aaac426d99d499fd7dd782` | hash-gated |
| HLA | `docs/phase-02-high-level-architecture/HIGH_LEVEL_ARCHITECTURE.md` | `2fa9df45348cdd3f4da4644fae5f0f1b9d08784cd18670e1508d931b64f1c4de` | unhashed (informative) |
| 3A | `docs/phase-03-low-level-design/3A-Platform-Architecture.md` | `c4173ccaf4db5c8eec0fd2d80ea04fb8e79a4833becc087c09fd528d0011ff91` | unhashed (informative) |

### 0.3 Evidence Register

Every citation of the form `<Key> L<line>` in this document resolves to exactly one row below; the anchor text is a verbatim substring of that source line.

| EV ID | Source | Line | Anchor text |
|---|---|---|---|
| EV-001 | 6A | 115 | `/api/v1/{resource}` — tenant/user-facing REST resources |
| EV-002 | 6A | 116 | `/api/internal/v1/{...}` — internal service-to-service endpoints |
| EV-003 | 6A | 117 | `/health/live`, `/health/ready` — unversioned, unauthenticated, infra-only |
| EV-004 | 6A | 118 | WebSocket endpoints are not under `/api/v1` |
| EV-005 | 6A | 143 | `If-Match` ETag mismatch |
| EV-006 | 6A | 169 | DELETE is either disallowed (410/405) |
| EV-007 | 6A | 288 | `ETag` on single-resource GETs |
| EV-008 | 6A | 289 | `Cache-Control: private, no-store` by default on all tenant-scoped responses |
| EV-009 | 6A | 290 | is permitted **only** on platform-global, non-tenant-scoped reference endpoints |
| EV-010 | 6A | 387 | Cursor pagination is the default |
| EV-011 | 6A | 397 | opaque, HMAC-signed, base64url-encoded token |
| EV-012 | 6A | 403 | Default page size |
| EV-013 | 6A | 404 | Maximum page size |
| EV-014 | 6A | 405 | orders by `(indexed_sort_column, id)` |
| EV-015 | 6A | 406 | `created_at DESC` unless the resource documents otherwise |
| EV-016 | 6A | 415 | A field not on the allow-list returns 422, not a silent no-op |
| EV-017 | 6A | 416 | Multi-field sort is capped at 2 fields. |
| EV-018 | 6A | 418 | At most 10 filter parameters combined |
| EV-019 | 6A | 437 | `(organization_id, principal_id, endpoint, Idempotency-Key)` |
| EV-020 | 6A | 438 | `idempotency:{org_id}:{endpoint}:{key}` |
| EV-021 | 6A | 439 | 24 hours |
| EV-022 | 6A | 440 | SHA-256 of the normalized |
| EV-023 | 6A | 442 | IDEMPOTENCY_KEY_REUSE_MISMATCH |
| EV-024 | 6A | 445 | GET (and other safe methods) never require or accept an Idempotency-Key |
| EV-025 | 6A | 460 | `PATCH` requires `If-Match` |
| EV-026 | 6A | 461 | client submits `If-Match` on the follow-up `PATCH` |
| EV-027 | 6A | 535 | 60 req/min |
| EV-028 | 6A | 537 | Default 300 req/min per organization |
| EV-029 | 6A | 542 | High fixed ceiling, separate bucket |
| EV-030 | 6A | 544 | `Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` |
| EV-031 | 6A | 576 | Enforced primarily by PostgreSQL RLS via `SET LOCAL app.tenant_id` |
| EV-032 | 6A | 577 | unknown fields rejected (`extra="forbid"`) |
| EV-033 | 6A | 579 | The API never returns a raw secret after initial issuance |
| EV-034 | 6A | 581 | Signed/presigned media URL handling |
| EV-035 | 6A | 627 | short-lived, platform-signed internal JWT |
| EV-036 | 6A | 653 | Clients branch on this, never on `message`. |
| EV-037 | 6A | 665 | SQL error text, stack traces |
| EV-038 | 6A | 716 | JWT (query param or subprotocol header at connect time |
| EV-039 | 6A | 718 | No mid-stream resume for dropped voice call audio |
| EV-040 | 6A | 719 | 5 concurrent per source |
| EV-041 | 6A | 723 | Voice's WS protocol uses raw binary/control frames with no generic envelope |
| EV-042 | 6A | 742 | Event schema version, independent of the API's `/v1` URL versioning |
| EV-043 | 6A | 776 | verified instead by the provider's own signature scheme |
| EV-044 | 6A | 778 | Three Distinct Mechanisms |
| EV-045 | 6A | 822 | a new major version is created only for breaking changes |
| EV-046 | 6A | 823 | Event schema (`version` field, §27.3) versions independently of the URL path |
| EV-047 | 6A | 824 | No minor/patch version in the URL |
| EV-048 | 6A | 832 | Breaking (requires new major version) |
| EV-049 | 6A | 834 | Removing a response field |
| EV-050 | 6A | 835 | Changing a field's type or shape |
| EV-051 | 6A | 836 | Changing an enum's semantics (not just adding a new value) |
| EV-052 | 6A | 837 | Making an optional request field required |
| EV-053 | 6A | 838 | Changing an endpoint's authorization requirement to be stricter |
| EV-054 | 6A | 839 | Changing what a 200 response means for existing callers |
| EV-055 | 6A | 840 | Changing pagination default page size |
| EV-056 | 6A | 844 | `deprecated: true` + `Sunset` HTTP header on every response from the deprecated version |
| EV-057 | 6A | 845 | minimum 6 months (indicative default |
| EV-058 | 6A | 846 | returns 410 Gone after the compatibility period, with a `Link` header pointing to the migration guide |
| EV-059 | 6A | 848 | treat an unrecognized value as "unknown, do not crash" |
| EV-060 | 6A | 860 | there is no separately hand-maintained OpenAPI file |
| EV-061 | 6A | 870 | A CI lint script verifies every non-internal route carries the required `x-*` fields before merge |
| EV-062 | 6B | 1515 | `GET /api/v1/auth/oauth/{provider}/callback` |
| EV-063 | 6D | 529 | Raw binary (audio) + JSON control frames |
| EV-064 | 6D | 541 | `Sec-WebSocket-Protocol: bearer.<jwt>` |
| EV-065 | 6D | 543 | connection close with code 4404 |
| EV-066 | 6D | 581 | Per-connection |
| EV-067 | 6D | 582 | Stable per (call_id, subscription) |
| EV-068 | 6D | 613 | server closes with 4408 |
| EV-069 | 6D | 614 | resume IS supported |
| EV-070 | 6E | 28 | AgentVersion immutability (DDR-4B-003) |
| EV-071 | 6I | 15 | `WorkflowVersion` |
| EV-072 | 6I | 363 | (PromptId, not PromptVersionId) |
| EV-073 | 6I | 591 | `PromptVersion` is resolved **live** |
| EV-074 | 6I | 892 | JWT via query param/subprotocol at connect |
| EV-075 | 6I | 893 | `workflow:read`, re-verified on subscribe |
| EV-076 | 6K | 51 | Plan / PlanVersion / PlanPrice |
| EV-077 | 6K | 52 | Commercial Pricing Agreement |
| EV-078 | 6K | 2249 | `POST /api/v1/billing/payment-providers/{provider_slug}/webhook` |
| EV-079 | 6J | 93 | An immutable-once-approved manifest version of a Plugin |
| EV-080 | 6J | 481 | `410 OAUTH_STATE_EXPIRED` |
| EV-081 | 6J | 720 | Schema version |
| EV-082 | 6J | 722 | `call.started` |
| EV-083 | 6J | 723 | `call.completed` |
| EV-084 | 6J | 724 | `call.failed` |
| EV-085 | 6J | 725 | `call.transferred` |
| EV-086 | 6J | 726 | `lead.created` |
| EV-087 | 6J | 727 | `lead.qualified` |
| EV-088 | 6J | 728 | `lead.disqualified` |
| EV-089 | 6J | 729 | `deal.created` |
| EV-090 | 6J | 730 | `deal.won` |
| EV-091 | 6J | 731 | `deal.lost` |
| EV-092 | 6J | 732 | `appointment.booked` |
| EV-093 | 6J | 733 | `campaign.started` |
| EV-094 | 6J | 734 | `campaign.completed` |
| EV-095 | 6J | 735 | `campaign.contact.qualified` |
| EV-096 | 6J | 736 | `invoice.created` |
| EV-097 | 6J | 737 | `invoice.paid` |
| EV-098 | 6J | 738 | `payment.failed` |
| EV-099 | 6J | 739 | `usage.threshold_reached` |
| EV-100 | 6J | 740 | `subscription.changed` |
| EV-101 | 6J | 781 | Starts at `1` for every topic in §19.1's table |
| EV-102 | 6J | 799 | **Algorithm:** HMAC-SHA256 |
| EV-103 | 6J | 805 | `v1={hex_signature}` |
| EV-104 | 6J | 809 | The envelope `version` (schema version, not API version) |
| EV-105 | 6J | 811 | Dual-signature rotation grace |
| EV-106 | 6J | 814 | X-Platform-Signature: v1={hex_signature_current} |
| EV-107 | 6J | 815 | X-Platform-Signature-Previous: v1={hex_signature_previous} |
| EV-108 | 6J | 823 | `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")` over the **raw, unparsed** request body bytes |
| EV-109 | 6J | 832 | default 3600 = 1 hour |
| EV-110 | 6J | 1009 | one signing algorithm across the whole platform, not two |
| EV-111 | 6J | 1047 | "min_platform_version": "1.0.0" |
| EV-112 | 6J | 1059 | Compatibility gate (§29) |
| EV-113 | 6J | 1061 | a manifest change after approval requires a **new version**, never an in-place edit |
| EV-114 | 6J | 1193 | requires submitting a **new** `PluginVersion` |
| EV-115 | 6J | 1197 | existing installations pinned to it continue running unaffected |
| EV-116 | 6J | 1201 | against the platform's own current API version |
| EV-117 | 6J | 1207 | resets `enabled_capabilities` to `{}` |
| EV-118 | 6J | 1445 | `PLUGIN_VERSION_INCOMPATIBLE` |
| EV-119 | 6J | 1634 | an existing topic string is never removed or repurposed |
| EV-120 | 6J | 2005 | 5-minute replay window |
| EV-121 | 6J | 2106 | a consumer that only checks `X-Platform-Signature` is unaffected |
| EV-122 | FAR | 2545 | begin after independent review |
| EV-123 | AMI | 13 | On any conflict, the owning source section cited in each row prevails |
| EV-124 | AMI | 231 | no /api/v1 prefix |
| EV-125 | AAM | 71 | Error-catalogue and versioning documents |
| EV-126 | AAM | 79 | When two sources disagree, the higher-ranked source wins. |
| EV-127 | AAM | 142 | `token_use=internal` |
| EV-128 | AAM | 371 | an allow-listed `service_id` |
| EV-129 | AAM | 587 | Platform Admin and Break-Glass |
| EV-130 | AAM | 632 | Internal-Service Routes (4) |
| EV-131 | AAM | 648 | Callback / Provider Trust Boundary (5) |
| EV-132 | AAM | 662 | Sensitive Media |
| EV-133 | AAM | 1247 | fail closed |
| EV-134 | AEC | 84 | ACTIVE_PUBLIC_REST_ERROR |
| EV-135 | AEC | 85 | ACTIVE_PLATFORM_ADMIN_ERROR |
| EV-136 | AEC | 86 | ACTIVE_INTERNAL_API_ERROR |
| EV-137 | AEC | 87 | CALLBACK_FAILURE |
| EV-138 | AEC | 99 | active A+B+C+D = 132 |
| EV-139 | AEC | 121 | IDEMPOTENCY_KEY_REUSE_MISMATCH |
| EV-140 | AEC | 166 | PLUGIN_VERSION_INCOMPATIBLE |
| EV-141 | AEC | 171 | QUOTA_EXCEEDED |
| EV-142 | AEC | 172 | RATE_LIMIT_EXCEEDED |
| EV-143 | AEC | 466 | Gone (OAuth state expired only) |
| EV-144 | SRS | 279 | NFR-COMPAT-001 |
| EV-145 | SRS | 290 | Versioned (`/v1/...`) |
| EV-146 | AP | 74 | Everything should expose versioned APIs. |
| EV-147 | AP | 125 | Avoid breaking APIs. |
| EV-148 | AP | 127 | Use versioning. |
| EV-149 | 4F | 863 | the signing algorithm and header format are part of the Published Language |
| EV-150 | 4F | 893 | Old topic subscriptions continue to deliver on the old schema. |
| EV-151 | 5A | 1301 | Enum / Reference Data Strategy |
| EV-152 | 5A | 1362 | Migration Principles |
| EV-153 | 5A | 1367 | **Backward compatible** |
| EV-154 | 5A | 1369 | **Non-destructive by default** |
| EV-155 | 5A | 1370 | **No data backfill in migration** |
| EV-156 | 5A | 1374 | Expand/Contract Pattern for Breaking Changes |
| EV-157 | 5A | 1377 | **Expand:** add the new column |
| EV-158 | 5A | 1378 | **Deploy application** that stops reading the old column |
| EV-159 | 5A | 1379 | **Contract:** `DROP COLUMN` after all application instances no longer reference it. |
| EV-160 | 5A | 1383 | Large Table Migrations |
| EV-161 | 5A | 1390 | Zero-Downtime Deployment Rule |
| EV-162 | 5A | 1392 | The migration runs before the new application version deploys. |
| EV-163 | 5A | 1395 | Renaming a column |
| EV-164 | 5A | 1396 | Changing a column's type in a way that breaks existing queries |
| EV-165 | 5A | 1397 | Making a nullable column NOT NULL without a default |
| EV-166 | HLA | 23 | modular monolith of bounded-context modules |
| EV-167 | 3A | 196 | modular monolith, few deployables |
| EV-168 | 3A | 442 | chose a modular monolith over microservices |
| EV-169 | 6J | 2539 | Method + canonical path + timestamp + body |
| EV-170 | 6K | 1923 | V1: platform-protection quota only, never priced |
| EV-171 | 6K | 1924 | V1: quota/entitlement gate only, not metered |
| EV-172 | 6K | 2035 | ## 25. Quotas |
| EV-173 | 6K | 2046 | ### 25.2 Quota Enforcement — Hot Path |
| EV-174 | 6K | 3625 | the only V1 capacity metric |
| EV-175 | 6M | 155 | ## 18. Quota Overrides |
| EV-176 | 6M | 251 | Set a per-org quota override |

## 1. Purpose / Scope

### 1.1 Purpose

Different readers applying this strategy to the same proposed change MUST reach the same one of the following five outcomes:

| Outcome | Meaning | Matrix classifications |
|---|---|---|
| O-1 Compatible inside the current major | Ships inside the existing major/topic/scheme | NON-BREAKING; NON-BREAKING (SECURITY REVIEW REQUIRED); OPERATIONAL; CONDITIONAL when its NO condition holds. Never assigned to a change that needs a frozen-source amendment |
| O-2 Requires staged rollout | Ships inside the current major only in the §18/§27 order | CONDITIONAL |
| O-3 Requires deprecation | Moves an interface through the retirement path of its own axis: §28/§29 on AX-A only; the AVS-OD-04 caller-confirmed sequence on AX-B (§27.3); AX-A-derived re-evaluation on AX-I | LIFECYCLE |
| O-4 Requires a successor major/topic/scheme | MUST NOT ship in place | BREAKING; CONDITIONAL when its YES condition holds |
| O-5 Prohibited without a source amendment | No version action authorizes it; a row MAY record the compatibility impact it would have after a future owning-source amendment without authorizing it now | PROHIBITED |

### 1.2 In Scope

- Public REST (`/api/v1`), platform-admin REST, internal REST (`/api/internal/v1`), provider/OAuth callbacks, WebSocket (`/ws/v1`), WebSocket event schemas, webhook topics/payloads/envelope, webhook signature scheme, plugin `min_platform_version`, idempotency, pagination, errors, authentication/authorization, rate limits.
- The compatibility matrix (§17), rollout ordering (§18, §27), per-axis retirement (§27.3–§27.5) and the AX-A lifecycle (§28, §29), security invariants (§34), anti-patterns (§35), owner decisions (§38), coverage (§39) and freeze gates (§41).

### 1.3 Out of Scope — This Phase MUST NOT

- MUST NOT create `/api/v2`, `/api/internal/v2` or `/ws/v2` routes; all three are NOT CREATED.
- MUST NOT duplicate V1 routers or copy V1 routes.
- MUST NOT add V2 Pydantic models or invent V2 schemas.
- MUST NOT create a V2 OpenAPI document or any committed OpenAPI/Swagger artifact.
- MUST NOT create V2 webhook schemas or successor topics.
- MUST NOT generate migration `113` or change any migration.
- MUST NOT create an SDK.
- MUST NOT implement a version dispatcher.
- MUST NOT mark V1 deprecated, choose a real sunset date, or start migrating clients. V1 is not deprecated.
- MUST NOT create an actual V1-to-V2 migration guide (only the §30 template).

Future introduction of a successor is documented as procedure only; every successor path shown in this document is HYPOTHETICAL.

## 2. Authority / Source Precedence

When two sources disagree, the higher-ranked source wins (AAM L79). An index is corrected, never the owning source (AMI L13). This document ranks below every source it cites and amends none of them.

| Rank | Authority | Governs in this strategy | Anchor |
|---|---|---|---|
| 1 | 6A — API architecture and standards | Path prefixes, versioning policy, compatibility table, deprecation signals, error-envelope rules, pagination, idempotency, rate-limit headers | 6A L115, 6A L822, 6A L832, 6A L844 |
| 2 | Owning domain contracts 6B–6M | Webhooks, signatures, topics, plugins (6J); WebSocket protocols (6D, 6I); callbacks (6B, 6J, 6K) | 6J L781, 6J L805, 6D L529 |
| 3 | AMI — API Master Index | Route inventory: 369 REST/internal/callback routes + 4 WebSocket routes | AMI L13 |
| 4 | AAM and AEC | Authorization outcomes (AAM); error codes and catalog counts (AEC) | AAM L79, AEC L99 |
| 5 | FAR — Final API Reconciliation | Phase-6 closure sequencing | FAR L2545 |
| 6 | 5A, 4F, SRS, AP | Expand/contract (5A); topic/signature Published Language (4F); versioning requirement (SRS, AP) | 5A L1374, 4F L863, SRS L290, AP L127 |
| 7 | HLA, 3A (unhashed, informative) | Runtime topology context (modular monolith) | HLA L23, 3A L442 |
| 8 | AVS-OD-01..AVS-OD-11 (§38) | Close gaps where the sources above are silent or ambiguous; override no explicit frozen text | §38 |

Conflict rule: an explicit frozen-source requirement that is stronger than an owner-decision floor prevails (recorded in §37). Where no source and no owner decision settles a question, the item is a blocker, not an opinion; §42 records zero such blockers.

## 3. Terminology

| Term | Definition |
|---|---|
| API major | The integer `N` in `/api/vN`, `/api/internal/vN` or `/ws/vN`. It is the only API version signal (6J L1201). |
| Current major | `v1` on each of AX-A, AX-B and AX-C. |
| Successor major | `N+1` on one axis. Every successor path named in this document is HYPOTHETICAL and NOT CREATED. |
| Version axis | An independently advancing version carrier, registered in §4 (AX-A..AX-L). |
| Breaking change | A change to contracted request/response/protocol behavior for which any §17.1 behavioral question answers YES. Explicitly configured operational values covered by CM-RL-01 and CM-RL-02 are outside this contract-diff test while their wire contract and enforcement semantics remain unchanged (§17.1). |
| BREAKING | Matrix class: requires a successor major/topic/scheme; MUST NOT ship in place. |
| NON-BREAKING | Matrix class: ships inside the current major; consumers tolerate it. Never assigned to a change whose implementation requires a frozen-source amendment (that change is PROHIBITED pending owning-source amendment). |
| NON-BREAKING (SECURITY REVIEW REQUIRED) | Matrix class (NSRR): ships inside the current major only after a recorded security review. |
| CONDITIONAL | Matrix class: a deterministic NO/YES condition decides; the NO branch still requires server-first rollout. |
| OPERATIONAL | Matrix class: no API-version action; outside the §17.1 contract-diff test. Either a numeric request-rate or abuse-protection threshold change with an unchanged signalling contract (AVS-OD-10), or a quota value (plan, agreement or per-organization override, including `ACTIVE_AGENTS` and `CONCURRENT_CALLS`) governed by 6K §25 and 6M §18, which is not an API version. It never covers a change to pricing, billing calculation, admission, authority, enforcement, wire shape or error contract (CM-RL-05). |
| LIFECYCLE | Matrix class: a retirement-path state transition on its own axis, not a contract change — §28/§29 on AX-A; the AVS-OD-04 caller-confirmed sequence on AX-B (§27.3); AX-A-derived re-evaluation on AX-I. |
| PROHIBITED | Matrix class: no major, topic or scheme authorizes it; a source amendment is required. A PROHIBITED row MAY record, as a future compatibility note, the impact the change would have after that amendment; the note never authorizes implementation. |
| Server-first rollout | The §18 five-step order under `extra="forbid"`. |
| Tolerant reader | A consumer that ignores unknown response fields and treats an unrecognized enum value as unknown without failing (6A L848). |
| Schema version | Per-topic webhook payload version; carried in envelope `version` and `X-Platform-Webhook-Version` (6J L809). |
| Successor topic | A topic string `X.vN` (N ≥ 2) carrying a breaking payload for topic `X`. |
| Signature scheme | The `v1=` label and algorithm in `X-Platform-Signature` (6J L805); not an API major. |
| Deprecation | AX-A only: formal announcement after successor GA; signals `deprecated: true` + `Sunset` (6A L844). No other axis uses these signals (§28 scope). |
| Compatibility period | AX-A only: time between deprecation announcement and sunset; minimum six months (AVS-OD-02). |
| Sunset | AX-A only: end of the compatibility period; once the AEC prerequisite is satisfied (AVS-OD-01), the retired public major returns all four sunset signals: 410 Gone + the registered sunset error envelope/code + `Link` to the migration guide + the `Sunset` header (6A L846, AVS-OD-01). |
| Caller confirmation | AX-B: recorded confirmation that an authorized `service_id` caller is deployed against the successor internal major (AVS-OD-04). |
| Provider cutover | AX-G: recorded confirmation that the provider has moved to the successor callback registration (AVS-OD-05). |
| HYPOTHETICAL | Marks an illustrative path, topic or scheme that does not exist and is NOT CREATED. |
| FUTURE REQUIRED WORK | A prerequisite that MUST be completed by a later, separately governed change before a named action; not performed here. |

## 4. Version Axis Registry

| Axis | Carrier | Current value | Is API version? | Coupled to | Rule section |
|---|---|---|---|---|---|
| AX-A | Public REST incl. platform-admin: `/api/v{major}` | `v1` | YES | none | §7, §8 |
| AX-B | Internal REST: `/api/internal/v{major}` | `v1` | YES | none | §9, §27.3 |
| AX-C | WebSocket: `/ws/v{major}` | `v1` | YES | none | §10, §27.4 |
| AX-D | WebSocket event `version` field | 1 per event type | NO | AX-C (breaking only, AVS-OD-11) | §11 |
| AX-E | Webhook topic `X.vN` / envelope `version` / `X-Platform-Webhook-Version` | 1 (all 19 topics) | NO | none | §12, §27.5 |
| AX-F | Webhook signature scheme `v1=` in `X-Platform-Signature` | `v1=` | NO | none | §13, §27.5 |
| AX-G | Provider/OAuth callbacks (provider-native contracts) | per provider | NO | none | §14, §27.5 |
| AX-H | `PluginVersion` SemVer | per PluginVersion | NO | none | §15 |
| AX-I | Plugin `min_platform_version` (MAJOR evaluated) | `1.0.0` example | NO | AX-A (read-only, AVS-OD-06) | §15 |
| AX-J | Resource versions (Agent/Workflow/Prompt/Plan versions) | per resource | NO | none | §16 |
| AX-K | Alembic revision | `112_5H5` | NO | none | §26 |
| AX-L | Signing-secret rotation | per endpoint | NO | none | §13 |

Axis rules:

| Rule ID | Rule | Source |
|---|---|---|
| AX-R01 | AX-A, AX-B and AX-C MUST advance independently; a successor on one axis MUST NOT force a successor on another. | AVS-OD-03 |
| AX-R02 | HYPOTHETICAL combined state (NOT CREATED): `/api/v2` + `/api/internal/v1` + `/ws/v1` is a valid configuration. | AVS-OD-03 |
| AX-R03 | Only AX-A, AX-B and AX-C are API versions. AX-D..AX-L MUST NOT be read as, or used to select, an API major. | 6J L1201, 6J L781, 6A L742 |
| AX-R04 | The only coupling from AX-D to AX-C is that a breaking WebSocket event change requires a new WebSocket major. | AVS-OD-11 |
| AX-R05 | AX-I reads AX-A (which AX-A public majors are served and not in the §29 SUNSET state); it MUST NOT drive AX-A. | AVS-OD-06 |
| AX-R06 | No axis uses minor or patch numbers in a URL. | 6A L824 |

## 5. Current V1 Contract Baseline

| Item | Current value | State | Source |
|---|---|---|---|
| Public REST major (AX-A) | `/api/v1` — 360 PUBLIC routes (318 tenant/user + 42 platform-admin) | ACTIVE | 6A L115 |
| Internal REST major (AX-B) | `/api/internal/v1` — 4 INTERNAL routes | ACTIVE | 6A L116 |
| WebSocket major (AX-C) | `/ws/v1` — 4 WebSocket routes | ACTIVE | 6A L118 |
| WebSocket event schema (AX-D) | event `version` independent of URL | ACTIVE | 6A L742 |
| Webhook topics (AX-E) | 19 topics, each at schema version 1; no successor topic exists | ACTIVE | 6J L720, 6J L781 |
| Webhook signature (AX-F) | HMAC-SHA256, `X-Platform-Signature: v1={hex_signature}` | ACTIVE | 6J L799, 6J L805 |
| Callbacks (AX-G) | 5 CALLBACK routes, provider-native verification | ACTIVE | AAM L648 |
| Plugin baseline (AX-I) | `min_platform_version` example `1.0.0` | ACTIVE | 6J L1047 |
| Database head (AX-K) | `112_5H5` (112 SQL / 112 Alembic) | baseline | 5A L1362 |
| Error catalog | Total 421 tokens; active A+B+C+D = 132; the sunset error code is not registered (FUTURE REQUIRED WORK, §29) | baseline | AEC L99 |
| Deprecation state | No major is deprecated; V1 is not deprecated; no sunset date exists | none | 6A L845 |
| Successor majors | None; `/api/v2`, `/api/internal/v2`, `/ws/v2` are NOT CREATED | none | 6A L822 |

### 5.1 Webhook Topic Registry

| Topic | Schema version | Successor topic | Source |
|---|---|---|---|
| `call.started` | 1 | none | 6J L722 |
| `call.completed` | 1 | none | 6J L723 |
| `call.failed` | 1 | none | 6J L724 |
| `call.transferred` | 1 | none | 6J L725 |
| `lead.created` | 1 | none | 6J L726 |
| `lead.qualified` | 1 | none | 6J L727 |
| `lead.disqualified` | 1 | none | 6J L728 |
| `deal.created` | 1 | none | 6J L729 |
| `deal.won` | 1 | none | 6J L730 |
| `deal.lost` | 1 | none | 6J L731 |
| `appointment.booked` | 1 | none | 6J L732 |
| `campaign.started` | 1 | none | 6J L733 |
| `campaign.completed` | 1 | none | 6J L734 |
| `campaign.contact.qualified` | 1 | none | 6J L735 |
| `invoice.created` | 1 | none | 6J L736 |
| `invoice.paid` | 1 | none | 6J L737 |
| `payment.failed` | 1 | none | 6J L738 |
| `usage.threshold_reached` | 1 | none | 6J L739 |
| `subscription.changed` | 1 | none | 6J L740 |

## 6. Route / Surface Version Profiles

### 6.1 Profile Definitions

| Profile | Surface | Count | Path form | Governing axis | Lifecycle rule |
|---|---|---|---|---|---|
| PUBLIC_REST_V1 | PUBLIC | 318 | `/api/v1/...` excluding `/api/v1/platform-admin/` | AX-A | §7, §28 |
| PLATFORM_ADMIN_REST_V1 | PUBLIC | 42 | `/api/v1/platform-admin/...` | AX-A | §8, §28 |
| INTERNAL_REST_V1 | INTERNAL | 4 | `/api/internal/v1/...` | AX-B | §9, §27.3 (AVS-OD-04) |
| CALLBACK_BROWSER_OAUTH | CALLBACK | 2 | `/api/v1/.../callback` (browser redirect) | AX-G | §14, §27.5 (AVS-OD-05) |
| CALLBACK_VOICE_PROVIDER | CALLBACK | 1 | `/webhooks/voice/{provider_slug}/events` (unversioned) | AX-G | §14, §27.5 (AVS-OD-05) |
| CALLBACK_INTEGRATION_PROVIDER | CALLBACK | 1 | `/api/v1/integrations/providers/.../callbacks/...` | AX-G | §14, §27.5 (AVS-OD-05) |
| CALLBACK_PAYMENT_PROVIDER | CALLBACK | 1 | `/api/v1/billing/payment-providers/.../webhook` | AX-G | §14, §27.5 (AVS-OD-05) |
| WS_MEDIA_V1 | WS | 1 | `/ws/v1/voice/media/{session_id}` | AX-C | §10, §27.4; retirement BLOCKED (WSP-13) |
| WS_EVENTS_V1 | WS | 3 | `/ws/v1/...` event streams | AX-C (+AX-D) | §10, §11, §27.4; retirement BLOCKED (WSP-13) |

### 6.2 REST / Internal / Callback Route Classification (369)

| # | AMI ID | Method | Path | Surface | Profile | Governing axis |
|---|---|---|---|---|---|---|
| 1 | AMI-6A-001 | GET | `/api/v1/jobs/{job_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 2 | AMI-6B-001 | POST | `/api/v1/auth/register` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 3 | AMI-6B-002 | POST | `/api/v1/auth/login` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 4 | AMI-6B-003 | POST | `/api/v1/auth/organization/select` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 5 | AMI-6B-004 | POST | `/api/v1/auth/logout` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 6 | AMI-6B-005 | POST | `/api/v1/auth/token/refresh` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 7 | AMI-6B-006 | POST | `/api/v1/auth/email/verify` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 8 | AMI-6B-007 | POST | `/api/v1/auth/email/verify/resend` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 9 | AMI-6B-008 | POST | `/api/v1/auth/password/reset` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 10 | AMI-6B-009 | POST | `/api/v1/auth/password/reset/confirm` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 11 | AMI-6B-010 | POST | `/api/v1/auth/password/change` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 12 | AMI-6B-011 | POST | `/api/v1/auth/invitations/accept` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 13 | AMI-6B-012 | GET | `/api/v1/auth/oauth/{provider}/authorize` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 14 | AMI-6B-013 | GET | `/api/v1/auth/oauth/{provider}/callback` | CALLBACK | CALLBACK_BROWSER_OAUTH | AX-G |
| 15 | AMI-6B-014 | DELETE | `/api/v1/auth/oauth/{provider}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 16 | AMI-6B-015 | POST | `/api/v1/auth/mfa/enroll` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 17 | AMI-6B-016 | POST | `/api/v1/auth/mfa/verify` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 18 | AMI-6B-017 | DELETE | `/api/v1/auth/mfa` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 19 | AMI-6B-018 | GET | `/api/v1/auth/me` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 20 | AMI-6B-019 | GET | `/api/v1/sessions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 21 | AMI-6B-020 | GET | `/api/v1/sessions/me` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 22 | AMI-6B-021 | DELETE | `/api/v1/sessions/{session_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 23 | AMI-6B-022 | DELETE | `/api/v1/sessions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 24 | AMI-6B-023 | POST | `/api/v1/organizations/{organization_id}/api-keys` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 25 | AMI-6B-024 | GET | `/api/v1/organizations/{organization_id}/api-keys` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 26 | AMI-6B-025 | GET | `/api/v1/organizations/{organization_id}/api-keys/{api_key_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 27 | AMI-6B-026 | DELETE | `/api/v1/organizations/{organization_id}/api-keys/{api_key_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 28 | AMI-6B-027 | GET | `/api/v1/permissions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 29 | AMI-6B-028 | GET | `/api/v1/organizations/{organization_id}/roles` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 30 | AMI-6B-029 | POST | `/api/v1/organizations/{organization_id}/roles` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 31 | AMI-6B-030 | GET | `/api/v1/organizations/{organization_id}/roles/{role_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 32 | AMI-6B-031 | PATCH | `/api/v1/organizations/{organization_id}/roles/{role_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 33 | AMI-6B-032 | DELETE | `/api/v1/organizations/{organization_id}/roles/{role_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 34 | AMI-6B-033 | POST | `/api/v1/auth/authorize/check` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 35 | AMI-6B-034 | POST | `/api/v1/platform-admin/organizations/{organization_id}/break-glass` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 36 | AMI-6B-035 | POST | `/api/v1/platform-admin/break-glass/{grant_id}/release` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 37 | AMI-6B-036 | POST | `/api/v1/platform-admin/users/{user_id}/sessions/revoke-all` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 38 | AMI-6C-001 | POST | `/api/v1/organizations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 39 | AMI-6C-002 | GET | `/api/v1/organizations/{organization_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 40 | AMI-6C-003 | PATCH | `/api/v1/organizations/{organization_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 41 | AMI-6C-004 | POST | `/api/v1/organizations/{organization_id}/logo/upload-url` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 42 | AMI-6C-005 | POST | `/api/v1/organizations/{organization_id}/logo/complete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 43 | AMI-6C-006 | POST | `/api/v1/organizations/{organization_id}/suspend` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 44 | AMI-6C-007 | POST | `/api/v1/organizations/{organization_id}/cancel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 45 | AMI-6C-008 | GET | `/api/v1/organizations/{organization_id}/members` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 46 | AMI-6C-009 | GET | `/api/v1/organizations/{organization_id}/members/{member_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 47 | AMI-6C-010 | POST | `/api/v1/organizations/{organization_id}/members/{member_id}/role` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 48 | AMI-6C-011 | POST | `/api/v1/organizations/{organization_id}/members/{member_id}/suspend` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 49 | AMI-6C-012 | POST | `/api/v1/organizations/{organization_id}/members/{member_id}/reactivate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 50 | AMI-6C-013 | POST | `/api/v1/organizations/{organization_id}/members/{member_id}/remove` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 51 | AMI-6C-014 | POST | `/api/v1/organizations/{organization_id}/members/me/leave` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 52 | AMI-6C-015 | POST | `/api/v1/organizations/{organization_id}/ownership/transfer` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 53 | AMI-6C-016 | POST | `/api/v1/organizations/{organization_id}/invitations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 54 | AMI-6C-017 | GET | `/api/v1/organizations/{organization_id}/invitations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 55 | AMI-6C-018 | POST | `/api/v1/organizations/{organization_id}/invitations/{membership_id}/resend` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 56 | AMI-6C-019 | POST | `/api/v1/organizations/{organization_id}/invitations/{membership_id}/cancel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 57 | AMI-6C-020 | GET | `/api/v1/organizations/{organization_id}/teams` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 58 | AMI-6C-021 | POST | `/api/v1/organizations/{organization_id}/teams` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 59 | AMI-6C-022 | GET | `/api/v1/organizations/{organization_id}/teams/{team_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 60 | AMI-6C-023 | PATCH | `/api/v1/organizations/{organization_id}/teams/{team_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 61 | AMI-6C-024 | POST | `/api/v1/organizations/{organization_id}/teams/{team_id}/archive` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 62 | AMI-6C-025 | GET | `/api/v1/organizations/{organization_id}/teams/{team_id}/members` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 63 | AMI-6C-026 | POST | `/api/v1/organizations/{organization_id}/teams/{team_id}/members` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 64 | AMI-6C-027 | DELETE | `/api/v1/organizations/{organization_id}/teams/{team_id}/members/{user_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 65 | AMI-6C-028 | GET | `/api/v1/organizations/{organization_id}/compliance-policy` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 66 | AMI-6C-029 | POST | `/api/v1/organizations/{organization_id}/compliance-policy` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 67 | AMI-6C-030 | POST | `/api/v1/organizations/{organization_id}/compliance-policy/{policy_id}/activate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 68 | AMI-6C-031 | POST | `/api/v1/organizations/{organization_id}/data-subject-requests` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 69 | AMI-6C-032 | GET | `/api/v1/organizations/{organization_id}/data-subject-requests` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 70 | AMI-6C-033 | GET | `/api/v1/organizations/{organization_id}/data-subject-requests/{request_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 71 | AMI-6C-034 | POST | `/api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/verify` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 72 | AMI-6C-035 | POST | `/api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/hold` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 73 | AMI-6C-036 | POST | `/api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/complete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 74 | AMI-6C-037 | POST | `/api/v1/organizations/{organization_id}/data-subject-requests/{request_id}/reject` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 75 | AMI-6C-038 | GET | `/api/v1/users/me` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 76 | AMI-6C-039 | PATCH | `/api/v1/users/me` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 77 | AMI-6C-040 | GET | `/api/v1/users/me/organizations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 78 | AMI-6C-041 | GET | `/api/internal/v1/organizations/{organization_id}` | INTERNAL | INTERNAL_REST_V1 | AX-B |
| 79 | AMI-6C-042 | GET | `/api/internal/v1/organizations/{organization_id}/compliance-policy` | INTERNAL | INTERNAL_REST_V1 | AX-B |
| 80 | AMI-6D-001 | POST | `/api/v1/calls` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 81 | AMI-6D-002 | GET | `/api/v1/calls` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 82 | AMI-6D-003 | GET | `/api/v1/calls/{call_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 83 | AMI-6D-004 | POST | `/api/v1/calls/{call_id}/terminate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 84 | AMI-6D-005 | POST | `/api/v1/calls/{call_id}/transfer` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 85 | AMI-6D-006 | POST | `/api/v1/calls/{call_id}/hold` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 86 | AMI-6D-007 | POST | `/api/v1/calls/{call_id}/resume` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 87 | AMI-6D-008 | GET | `/api/v1/conversations/{conversation_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 88 | AMI-6D-009 | GET | `/api/v1/conversations/{conversation_id}/turns` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 89 | AMI-6D-010 | GET | `/api/v1/calls/{call_id}/recording` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 90 | AMI-6D-011 | GET | `/api/v1/recordings/{recording_id}/download-url` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 91 | AMI-6D-012 | POST | `/api/v1/recordings/{recording_id}/delete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 92 | AMI-6D-013 | GET | `/api/v1/conversations/{conversation_id}/transcript` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 93 | AMI-6D-014 | GET | `/api/v1/conversations/{conversation_id}/transcript/segments` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 94 | AMI-6D-015 | GET | `/api/v1/conversations/{conversation_id}/tool-executions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 95 | AMI-6D-016 | GET | `/api/v1/tool-executions/{execution_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 96 | AMI-6D-017 | GET | `/api/v1/phone-numbers` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 97 | AMI-6D-018 | GET | `/api/v1/phone-numbers/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 98 | AMI-6D-019 | POST | `/api/v1/phone-numbers/{id}/assign-agent` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 99 | AMI-6D-020 | GET | `/api/internal/v1/calls/{call_id}` | INTERNAL | INTERNAL_REST_V1 | AX-B |
| 100 | AMI-6D-021 | POST | `/webhooks/voice/{provider_slug}/events` | CALLBACK | CALLBACK_VOICE_PROVIDER | AX-G |
| 101 | AMI-6E-001 | POST | `/api/v1/agents` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 102 | AMI-6E-002 | GET | `/api/v1/agents` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 103 | AMI-6E-003 | GET | `/api/v1/agents/{agent_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 104 | AMI-6E-004 | PATCH | `/api/v1/agents/{agent_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 105 | AMI-6E-005 | POST | `/api/v1/agents/{agent_id}/publish` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 106 | AMI-6E-006 | POST | `/api/v1/agents/{agent_id}/deprecate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 107 | AMI-6E-007 | POST | `/api/v1/agents/{agent_id}/clone` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 108 | AMI-6E-008 | GET | `/api/v1/agents/{agent_id}/versions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 109 | AMI-6E-009 | GET | `/api/v1/agents/{agent_id}/versions/{version_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 110 | AMI-6E-010 | GET | `/api/v1/tools` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 111 | AMI-6E-011 | POST | `/api/v1/tools` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 112 | AMI-6E-012 | GET | `/api/v1/tools/{tool_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 113 | AMI-6E-013 | PATCH | `/api/v1/tools/{tool_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 114 | AMI-6E-014 | POST | `/api/v1/tools/{tool_id}/deactivate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 115 | AMI-6E-015 | GET | `/api/v1/provider-health` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 116 | AMI-6E-016 | GET | `/api/v1/language-evaluations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 117 | AMI-6E-017 | GET | `/api/internal/v1/agents/{agent_id}/versions/{version_id}` | INTERNAL | INTERNAL_REST_V1 | AX-B |
| 118 | AMI-6F-001 | POST | `/api/v1/knowledge-bases` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 119 | AMI-6F-002 | GET | `/api/v1/knowledge-bases` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 120 | AMI-6F-003 | GET | `/api/v1/knowledge-bases/{kb_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 121 | AMI-6F-004 | PATCH | `/api/v1/knowledge-bases/{kb_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 122 | AMI-6F-005 | POST | `/api/v1/knowledge-bases/{kb_id}/archive` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 123 | AMI-6F-006 | POST | `/api/v1/knowledge-bases/{kb_id}/reindex` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 124 | AMI-6F-007 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/upload-url` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 125 | AMI-6F-008 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/complete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 126 | AMI-6F-009 | POST | `/api/v1/knowledge-bases/{kb_id}/documents` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 127 | AMI-6F-010 | GET | `/api/v1/knowledge-bases/{kb_id}/documents` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 128 | AMI-6F-011 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 129 | AMI-6F-012 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/reprocess` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 130 | AMI-6F-013 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/archive` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 131 | AMI-6F-014 | DELETE | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 132 | AMI-6F-015 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 133 | AMI-6F-016 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 134 | AMI-6F-017 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/publish` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 135 | AMI-6F-018 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 136 | AMI-6F-019 | GET | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/ingestion-jobs/{job_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 137 | AMI-6F-020 | GET | `/api/v1/knowledge/search` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 138 | AMI-6F-021 | POST | `/api/v1/knowledge-bases/{kb_id}/documents/{document_id}/versions/{version_id}/rollback` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 139 | AMI-6G-001 | POST | `/api/v1/contacts` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 140 | AMI-6G-002 | GET | `/api/v1/contacts` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 141 | AMI-6G-003 | GET | `/api/v1/contacts/{contact_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 142 | AMI-6G-004 | PATCH | `/api/v1/contacts/{contact_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 143 | AMI-6G-005 | POST | `/api/v1/contacts/{contact_id}/lead-status` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 144 | AMI-6G-006 | POST | `/api/v1/contacts/{contact_id}/qualify` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 145 | AMI-6G-007 | POST | `/api/v1/contacts/{contact_id}/convert` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 146 | AMI-6G-008 | POST | `/api/v1/contacts/{contact_id}/owner` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 147 | AMI-6G-009 | POST | `/api/v1/contacts/{contact_id}/tags` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 148 | AMI-6G-010 | DELETE | `/api/v1/contacts/{contact_id}/tags/{tag}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 149 | AMI-6G-011 | POST | `/api/v1/contacts/{contact_id}/merge` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 150 | AMI-6G-012 | DELETE | `/api/v1/contacts/{contact_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 151 | AMI-6G-013 | POST | `/api/v1/contacts/{contact_id}/suppress` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 152 | AMI-6G-014 | GET | `/api/v1/contacts/{contact_id}/deals` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 153 | AMI-6G-015 | GET | `/api/v1/contacts/{contact_id}/activities` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 154 | AMI-6G-016 | GET | `/api/v1/contacts/{contact_id}/tasks` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 155 | AMI-6G-017 | GET | `/api/v1/contacts/{contact_id}/notes` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 156 | AMI-6G-018 | GET | `/api/v1/contacts/{contact_id}/appointments` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 157 | AMI-6G-019 | GET | `/api/v1/contacts/{contact_id}/score` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 158 | AMI-6G-020 | GET | `/api/v1/contacts/{contact_id}/score-history` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 159 | AMI-6G-021 | GET | `/api/v1/contacts/{contact_id}/consent` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 160 | AMI-6G-022 | GET | `/api/v1/contacts/{contact_id}/consent/history` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 161 | AMI-6G-023 | POST | `/api/v1/contacts/{contact_id}/consent` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 162 | AMI-6G-024 | POST | `/api/v1/companies` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 163 | AMI-6G-025 | GET | `/api/v1/companies` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 164 | AMI-6G-026 | GET | `/api/v1/companies/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 165 | AMI-6G-027 | PATCH | `/api/v1/companies/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 166 | AMI-6G-028 | POST | `/api/v1/companies/{id}/owner` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 167 | AMI-6G-029 | POST | `/api/v1/deals` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 168 | AMI-6G-030 | GET | `/api/v1/deals` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 169 | AMI-6G-031 | GET | `/api/v1/deals/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 170 | AMI-6G-032 | PATCH | `/api/v1/deals/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 171 | AMI-6G-033 | POST | `/api/v1/deals/{id}/stage` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 172 | AMI-6G-034 | POST | `/api/v1/deals/{id}/win` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 173 | AMI-6G-035 | POST | `/api/v1/deals/{id}/lose` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 174 | AMI-6G-036 | POST | `/api/v1/deals/{id}/abandon` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 175 | AMI-6G-037 | POST | `/api/v1/deals/{id}/owner` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 176 | AMI-6G-038 | POST | `/api/v1/pipelines` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 177 | AMI-6G-039 | GET | `/api/v1/pipelines` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 178 | AMI-6G-040 | GET | `/api/v1/pipelines/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 179 | AMI-6G-041 | PATCH | `/api/v1/pipelines/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 180 | AMI-6G-042 | POST | `/api/v1/pipelines/{id}/default` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 181 | AMI-6G-043 | GET | `/api/v1/pipelines/{id}/board` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 182 | AMI-6G-044 | POST | `/api/v1/activities` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 183 | AMI-6G-045 | GET | `/api/v1/activities/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 184 | AMI-6G-046 | GET | `/api/v1/deals/{id}/activities` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 185 | AMI-6G-047 | GET | `/api/v1/companies/{id}/activities` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 186 | AMI-6G-048 | POST | `/api/v1/tasks` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 187 | AMI-6G-049 | GET | `/api/v1/tasks` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 188 | AMI-6G-050 | GET | `/api/v1/tasks/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 189 | AMI-6G-051 | PATCH | `/api/v1/tasks/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 190 | AMI-6G-052 | POST | `/api/v1/tasks/{id}/complete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 191 | AMI-6G-053 | POST | `/api/v1/tasks/{id}/cancel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 192 | AMI-6G-054 | GET | `/api/v1/me/tasks` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 193 | AMI-6G-055 | POST | `/api/v1/notes` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 194 | AMI-6G-056 | GET | `/api/v1/notes/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 195 | AMI-6G-057 | GET | `/api/v1/deals/{id}/notes` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 196 | AMI-6G-058 | GET | `/api/v1/companies/{id}/notes` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 197 | AMI-6G-059 | POST | `/api/v1/notes/{id}/pin` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 198 | AMI-6G-060 | POST | `/api/v1/notes/{id}/unpin` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 199 | AMI-6G-061 | DELETE | `/api/v1/notes/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 200 | AMI-6G-062 | POST | `/api/v1/appointments` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 201 | AMI-6G-063 | GET | `/api/v1/appointments` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 202 | AMI-6G-064 | GET | `/api/v1/appointments/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 203 | AMI-6G-065 | POST | `/api/v1/appointments/{id}/confirm` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 204 | AMI-6G-066 | POST | `/api/v1/appointments/{id}/reschedule` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 205 | AMI-6G-067 | POST | `/api/v1/appointments/{id}/cancel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 206 | AMI-6G-068 | POST | `/api/v1/appointments/{id}/complete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 207 | AMI-6G-069 | POST | `/api/v1/appointments/{id}/no-show` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 208 | AMI-6G-070 | POST | `/api/v1/crm-field-definitions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 209 | AMI-6G-071 | GET | `/api/v1/crm-field-definitions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 210 | AMI-6G-072 | PATCH | `/api/v1/crm-field-definitions/{field_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 211 | AMI-6G-073 | POST | `/api/v1/crm-field-definitions/{field_id}/archive` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 212 | AMI-6G-074 | GET | `/api/v1/suppressions/check` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 213 | AMI-6G-075 | POST | `/api/v1/suppressions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 214 | AMI-6G-076 | GET | `/api/v1/suppressions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 215 | AMI-6G-077 | GET | `/api/v1/suppressions/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 216 | AMI-6G-078 | POST | `/api/v1/suppressions/{id}/lift` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 217 | AMI-6H-001 | POST | `/api/v1/campaigns` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 218 | AMI-6H-002 | GET | `/api/v1/campaigns` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 219 | AMI-6H-003 | GET | `/api/v1/campaigns/{campaign_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 220 | AMI-6H-004 | PATCH | `/api/v1/campaigns/{campaign_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 221 | AMI-6H-005 | POST | `/api/v1/campaigns/{campaign_id}/contact-list` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 222 | AMI-6H-006 | POST | `/api/v1/campaigns/{campaign_id}/schedule` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 223 | AMI-6H-007 | POST | `/api/v1/campaigns/{campaign_id}/start` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 224 | AMI-6H-008 | POST | `/api/v1/campaigns/{campaign_id}/pause` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 225 | AMI-6H-009 | POST | `/api/v1/campaigns/{campaign_id}/resume` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 226 | AMI-6H-010 | POST | `/api/v1/campaigns/{campaign_id}/stop` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 227 | AMI-6H-011 | POST | `/api/v1/campaigns/{campaign_id}/cancel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 228 | AMI-6H-012 | GET | `/api/v1/campaigns/{campaign_id}/progress` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 229 | AMI-6H-013 | GET | `/api/v1/campaigns/{campaign_id}/outcome` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 230 | AMI-6H-014 | POST | `/api/v1/contact-lists` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 231 | AMI-6H-015 | GET | `/api/v1/contact-lists` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 232 | AMI-6H-016 | GET | `/api/v1/contact-lists/{contact_list_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 233 | AMI-6H-017 | POST | `/api/v1/contact-lists/{contact_list_id}/imports/upload-url` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 234 | AMI-6H-018 | POST | `/api/v1/contact-lists/{contact_list_id}/imports/{import_job_id}/complete` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 235 | AMI-6H-019 | GET | `/api/v1/imports/{import_job_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 236 | AMI-6H-020 | GET | `/api/v1/imports` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 237 | AMI-6H-021 | GET | `/api/v1/campaigns/{campaign_id}/contacts` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 238 | AMI-6H-022 | GET | `/api/v1/campaigns/{campaign_id}/contacts/{campaign_contact_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 239 | AMI-6H-023 | GET | `/api/v1/campaigns/{campaign_id}/call-jobs` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 240 | AMI-6H-024 | GET | `/api/v1/campaigns/{campaign_id}/call-jobs/{job_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 241 | AMI-6H-025 | GET | `/api/v1/campaigns/{campaign_id}/contacts/{campaign_contact_id}/call-reports` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 242 | AMI-6I-001 | POST | `/api/v1/workflows` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 243 | AMI-6I-002 | GET | `/api/v1/workflows` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 244 | AMI-6I-003 | GET | `/api/v1/workflows/{workflow_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 245 | AMI-6I-004 | PATCH | `/api/v1/workflows/{workflow_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 246 | AMI-6I-005 | PUT | `/api/v1/workflows/{workflow_id}/draft` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 247 | AMI-6I-006 | POST | `/api/v1/workflows/{workflow_id}/validate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 248 | AMI-6I-007 | POST | `/api/v1/workflows/{workflow_id}/publish` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 249 | AMI-6I-008 | POST | `/api/v1/workflows/{workflow_id}/archive` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 250 | AMI-6I-009 | GET | `/api/v1/workflows/{workflow_id}/versions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 251 | AMI-6I-010 | GET | `/api/v1/workflows/{workflow_id}/versions/{version_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 252 | AMI-6I-011 | GET | `/api/v1/workflow-executions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 253 | AMI-6I-012 | GET | `/api/v1/workflow-executions/{execution_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 254 | AMI-6J-001 | GET | `/api/v1/integration-definitions` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 255 | AMI-6J-002 | GET | `/api/v1/integration-definitions/{definition_key}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 256 | AMI-6J-003 | GET | `/api/v1/integrations/connections` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 257 | AMI-6J-004 | POST | `/api/v1/integrations/connections` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 258 | AMI-6J-005 | GET | `/api/v1/integrations/connections/{connection_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 259 | AMI-6J-006 | PATCH | `/api/v1/integrations/connections/{connection_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 260 | AMI-6J-007 | POST | `/api/v1/integrations/connections/{connection_id}/disconnect` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 261 | AMI-6J-008 | POST | `/api/v1/integrations/connections/{connection_id}/reauthorize` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 262 | AMI-6J-009 | POST | `/api/v1/integrations/connections/{connection_id}/test` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 263 | AMI-6J-010 | POST | `/api/v1/integrations/connections/{connection_id}/oauth/authorize` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 264 | AMI-6J-011 | GET | `/api/v1/integrations/oauth/{definition_key}/callback` | CALLBACK | CALLBACK_BROWSER_OAUTH | AX-G |
| 265 | AMI-6J-012 | GET | `/api/v1/integrations/connections/{connection_id}/health` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 266 | AMI-6J-013 | POST | `/api/v1/integrations/connections/{connection_id}/sync` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 267 | AMI-6J-014 | POST | `/api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` | CALLBACK | CALLBACK_INTEGRATION_PROVIDER | AX-G |
| 268 | AMI-6J-015 | GET | `/api/v1/inbound-webhook-events` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 269 | AMI-6J-016 | GET | `/api/v1/inbound-webhook-events/{id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 270 | AMI-6J-017 | GET | `/api/v1/webhook-endpoints` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 271 | AMI-6J-018 | POST | `/api/v1/webhook-endpoints` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 272 | AMI-6J-019 | GET | `/api/v1/webhook-endpoints/{webhook_endpoint_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 273 | AMI-6J-020 | PATCH | `/api/v1/webhook-endpoints/{webhook_endpoint_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 274 | AMI-6J-021 | DELETE | `/api/v1/webhook-endpoints/{webhook_endpoint_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 275 | AMI-6J-022 | POST | `/api/v1/webhook-endpoints/{webhook_endpoint_id}/enable` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 276 | AMI-6J-023 | POST | `/api/v1/webhook-endpoints/{webhook_endpoint_id}/disable` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 277 | AMI-6J-024 | POST | `/api/v1/webhook-endpoints/{webhook_endpoint_id}/rotate-secret` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 278 | AMI-6J-025 | POST | `/api/v1/webhook-endpoints/{webhook_endpoint_id}/test` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 279 | AMI-6J-026 | GET | `/api/v1/webhook-deliveries` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 280 | AMI-6J-027 | GET | `/api/v1/webhook-deliveries/{delivery_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 281 | AMI-6J-028 | POST | `/api/v1/webhook-deliveries/{delivery_id}/replay` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 282 | AMI-6J-029 | GET | `/api/v1/plugins` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 283 | AMI-6J-030 | GET | `/api/v1/plugins/{plugin_key}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 284 | AMI-6J-031 | GET | `/api/v1/plugin-installations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 285 | AMI-6J-032 | POST | `/api/v1/plugin-installations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 286 | AMI-6J-033 | GET | `/api/v1/plugin-installations/{installation_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 287 | AMI-6J-034 | PATCH | `/api/v1/plugin-installations/{installation_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 288 | AMI-6J-035 | POST | `/api/v1/plugin-installations/{installation_id}/rotate-credential` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 289 | AMI-6J-036 | POST | `/api/v1/plugin-installations/{installation_id}/activate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 290 | AMI-6J-037 | POST | `/api/v1/plugin-installations/{installation_id}/suspend` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 291 | AMI-6J-038 | POST | `/api/v1/plugin-installations/{installation_id}/reactivate` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 292 | AMI-6J-039 | POST | `/api/v1/plugin-installations/{installation_id}/upgrade` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 293 | AMI-6J-040 | DELETE | `/api/v1/plugin-installations/{installation_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 294 | AMI-6K-001 | GET | `/api/v1/billing/account` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 295 | AMI-6K-002 | PATCH | `/api/v1/billing/account` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 296 | AMI-6K-003 | GET | `/api/v1/billing/plans` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 297 | AMI-6K-004 | GET | `/api/v1/billing/plans/{plan_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 298 | AMI-6K-005 | GET | `/api/v1/billing/subscription` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 299 | AMI-6K-006 | POST | `/api/v1/billing/subscription` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 300 | AMI-6K-007 | POST | `/api/v1/billing/subscription/change-plan` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 301 | AMI-6K-008 | POST | `/api/v1/billing/subscription/cancel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 302 | AMI-6K-009 | GET | `/api/v1/billing/periods` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 303 | AMI-6K-010 | GET | `/api/v1/billing/periods/{period_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 304 | AMI-6K-011 | GET | `/api/v1/billing/usage` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 305 | AMI-6K-012 | GET | `/api/v1/billing/usage/summary` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 306 | AMI-6K-013 | GET | `/api/v1/billing/quotas` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 307 | AMI-6K-014 | GET | `/api/v1/billing/invoices` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 308 | AMI-6K-015 | GET | `/api/v1/billing/invoices/{invoice_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 309 | AMI-6K-016 | POST | `/api/v1/billing/invoices/{invoice_id}/payment-intent` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 310 | AMI-6K-017 | GET | `/api/v1/billing/payments` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 311 | AMI-6K-018 | GET | `/api/v1/billing/payments/{payment_attempt_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 312 | AMI-6K-019 | GET | `/api/v1/billing/refunds` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 313 | AMI-6K-020 | GET | `/api/v1/billing/refunds/{refund_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 314 | AMI-6K-021 | GET | `/api/v1/billing/credits` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 315 | AMI-6K-022 | GET | `/api/v1/billing/summary` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 316 | AMI-6K-023 | POST | `/api/v1/billing/payment-providers/{provider_slug}/webhook` | CALLBACK | CALLBACK_PAYMENT_PROVIDER | AX-G |
| 317 | AMI-6L-001 | GET | `/api/v1/analytics/overview` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 318 | AMI-6L-002 | GET | `/api/v1/analytics/calls` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 319 | AMI-6L-003 | GET | `/api/v1/analytics/calls/latency` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 320 | AMI-6L-004 | GET | `/api/v1/analytics/agents` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 321 | AMI-6L-005 | GET | `/api/v1/analytics/agents/{agent_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 322 | AMI-6L-006 | GET | `/api/v1/analytics/leads/funnel` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 323 | AMI-6L-007 | GET | `/api/v1/analytics/campaigns` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 324 | AMI-6L-008 | GET | `/api/v1/analytics/campaigns/{campaign_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 325 | AMI-6L-009 | GET | `/api/v1/analytics/conversations` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 326 | AMI-6L-010 | GET | `/api/v1/analytics/tools` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 327 | AMI-6L-011 | GET | `/api/v1/analytics/webhooks` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 328 | AMI-6L-012 | GET | `/api/v1/audit/events` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 329 | AMI-6L-013 | GET | `/api/v1/audit/events/{event_id}` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 330 | AMI-6L-014 | GET | `/api/v1/audit/integrity` | PUBLIC | PUBLIC_REST_V1 | AX-A |
| 331 | AMI-6M-001 | GET | `/api/v1/platform-admin/organizations` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 332 | AMI-6M-002 | GET | `/api/v1/platform-admin/organizations/{organization_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 333 | AMI-6M-003 | POST | `/api/v1/platform-admin/organizations/{organization_id}/suspend` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 334 | AMI-6M-004 | POST | `/api/v1/platform-admin/organizations/{organization_id}/reactivate` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 335 | AMI-6M-005 | GET | `/api/v1/platform-admin/organizations/{organization_id}/quota-overrides` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 336 | AMI-6M-006 | POST | `/api/v1/platform-admin/organizations/{organization_id}/quota-overrides` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 337 | AMI-6M-007 | GET | `/api/v1/platform-admin/break-glass` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 338 | AMI-6M-008 | POST | `/api/v1/platform-admin/recordings/{recording_id}/access` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 339 | AMI-6M-009 | POST | `/api/v1/platform-admin/transcripts/{transcript_id}/access` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 340 | AMI-6M-010 | POST | `/api/v1/platform-admin/organizations/{organization_id}/refunds` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 341 | AMI-6M-011 | POST | `/api/v1/platform-admin/organizations/{organization_id}/credits` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 342 | AMI-6M-012 | POST | `/api/v1/platform-admin/organizations/{organization_id}/billing-adjustments` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 343 | AMI-6M-013 | GET | `/api/v1/platform-admin/organizations/{organization_id}/payment-attempts` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 344 | AMI-6M-014 | GET | `/api/v1/platform-admin/plans` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 345 | AMI-6M-015 | GET | `/api/v1/platform-admin/plans/{plan_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 346 | AMI-6M-016 | POST | `/api/v1/platform-admin/plans` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 347 | AMI-6M-017 | POST | `/api/v1/platform-admin/plans/{plan_id}/versions` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 348 | AMI-6M-018 | POST | `/api/v1/platform-admin/plans/{plan_id}/versions/{version_id}/publish` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 349 | AMI-6M-019 | POST | `/api/v1/platform-admin/plans/{plan_id}/versions/{version_id}/prices` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 350 | AMI-6M-020 | POST | `/api/v1/platform-admin/plans/{plan_id}/deactivate` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 351 | AMI-6M-021 | GET | `/api/v1/platform-admin/commercial-pricing-agreements` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 352 | AMI-6M-022 | GET | `/api/v1/platform-admin/commercial-pricing-agreements/{agreement_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 353 | AMI-6M-023 | POST | `/api/v1/platform-admin/commercial-pricing-agreements` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 354 | AMI-6M-024 | POST | `/api/v1/platform-admin/commercial-pricing-agreements/{agreement_id}/versions` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 355 | AMI-6M-025 | POST | `/api/v1/platform-admin/commercial-pricing-agreements/{agreement_id}/versions/{version_id}/activate` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 356 | AMI-6M-026 | POST | `/api/v1/platform-admin/commercial-pricing-agreements/{agreement_id}/versions/{version_id}/expire` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 357 | AMI-6M-027 | GET | `/api/v1/platform-admin/tax-categories` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 358 | AMI-6M-028 | GET | `/api/v1/platform-admin/tax-rules` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 359 | AMI-6M-029 | POST | `/api/v1/platform-admin/tax-categories` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 360 | AMI-6M-030 | POST | `/api/v1/platform-admin/tax-rules` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 361 | AMI-6M-031 | GET | `/api/v1/platform-admin/analytics/financial` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 362 | AMI-6M-032 | GET | `/api/v1/platform-admin/audit/events` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 363 | AMI-6M-033 | GET | `/api/v1/platform-admin/provider-health` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 364 | AMI-6M-034 | GET | `/api/v1/platform-admin/webhooks/failed` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 365 | AMI-6M-035 | GET | `/api/v1/platform-admin/webhooks/dead-letter` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 366 | AMI-6M-036 | GET | `/api/v1/platform-admin/workflow-executions/{workflow_execution_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 367 | AMI-6M-037 | GET | `/api/v1/platform-admin/users/{user_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 368 | AMI-6M-038 | GET | `/api/v1/platform-admin/sessions/{session_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |
| 369 | AMI-6M-039 | GET | `/api/v1/platform-admin/api-keys/{api_key_id}` | PUBLIC | PLATFORM_ADMIN_REST_V1 | AX-A |

### 6.3 WebSocket Route Classification (4)

| # | AMI ID | Path | Profile | Governing axis |
|---|---|---|---|---|
| 1 | AMI-WS-6D-001 | `/ws/v1/voice/media/{session_id}` | WS_MEDIA_V1 | AX-C |
| 2 | AMI-WS-6D-002 | `/ws/v1/voice/calls/{call_id}` | WS_EVENTS_V1 | AX-C |
| 3 | AMI-WS-6D-003 | `/ws/v1/voice/calls/stream` | WS_EVENTS_V1 | AX-C |
| 4 | AMI-WS-6I-001 | `/ws/v1/workflow-executions/{execution_id}` | WS_EVENTS_V1 | AX-C |

### 6.4 Count Reconciliation

| Measure | Count |
|---|---|
| PUBLIC_REST_V1 | 318 |
| PLATFORM_ADMIN_REST_V1 | 42 |
| PUBLIC total | 360 |
| INTERNAL_REST_V1 | 4 |
| CALLBACK (all profiles) | 5 |
| REST/internal/callback total | 369 |
| AAM rows with identical AMI IDs | 369 |
| WebSocket routes | 4 |
| Unclassified (orphan) routes | 0 |

### 6.5 Unversioned Exceptions

Exactly the rows below are unversioned by source. They MUST NOT be classified as missing-version defects, and no other exemption exists.

| Exception | Why unversioned | Governing rule | Source |
|---|---|---|---|
| `/health/live` | Infra-only liveness probe; unauthenticated; not an AMI route | Not an API contract; not on any axis | 6A L117 |
| `/health/ready` | Infra-only readiness probe; unauthenticated; not an AMI route | Not an API contract; not on any axis | 6A L117 |
| `/webhooks/voice/{provider_slug}/events` (AMI-6D-021) | Provider-facing callback; path fixed by provider registration | AX-G; AVS-OD-05 | AMI L231 |

## 7. Public REST Versioning

| Rule ID | Rule | Source |
|---|---|---|
| PR-01 | Public REST routes MUST carry the major in the URL path as `/api/v{major}`; the current and only major is `v1`. | 6A L115, 6A L824 |
| PR-02 | A minor or patch number MUST NOT appear in any REST URL. | 6A L824 |
| PR-03 | The major MUST NOT be selected by request header, query parameter or `Accept-Version`; the URL path is the only selector. | 6J L1201, SRS L290 |
| PR-04 | A change classified BREAKING in §17 MUST NOT ship inside `/api/v1`; it requires a successor public major. | 6A L822, 6A L832 |
| PR-05 | A change classified NON-BREAKING or OPERATIONAL ships inside the current major. | 6A L834 |
| PR-06 | A CONDITIONAL change ships inside the current major only when its NO condition holds and the §18 server-first order is followed. | 6A L577, 6A L837 |
| PR-07 | Releasing a successor major MUST NOT retire the predecessor; retirement follows §28 and §29 only. | 6A L845, AVS-OD-02 |
| PR-08 | Structured error properties (`error.code`, HTTP status, `retryable`, `details`) are the machine contract; `message` is not a contract. | 6A L653 |
| PR-09 | On AX-A, deprecation signals are exactly `deprecated: true` in generated OpenAPI plus the `Sunset` header on every response of the deprecated major; sunset is 410 Gone + the registered sunset error envelope/code + `Link` to the migration guide + the `Sunset` header (AVS-OD-01 Option C), once the AEC prerequisite is satisfied. | 6A L844, 6A L846, AVS-OD-01 |
| PR-10 | The platform exposes versioned APIs and avoids breaking them. | SRS L279, AP L74, AP L125, AP L127 |

## 8. Platform-Admin REST Versioning

| Rule ID | Rule | Source |
|---|---|---|
| PA-01 | The 42 routes under `/api/v1/platform-admin/` are PUBLIC-surface routes on AX-A and follow the public REST lifecycle (§7, §28, §29). | AAM L587 |
| PA-02 | No separate platform-admin major exists; a breaking platform-admin change requires the successor public major. | 6A L822 |
| PA-03 | Platform-admin and break-glass controls MUST NOT be weakened by any version transition. | AAM L587 |
| PA-04 | Platform-admin errors use the platform-admin envelope class and follow §20. | AEC L85 |

## 9. Internal REST Versioning

| Rule ID | Rule | Source |
|---|---|---|
| IN-01 | Internal routes carry `/api/internal/v{major}`; the current major is `v1` with 4 routes. | 6A L116, AAM L632 |
| IN-02 | AX-B advances independently of AX-A and AX-C. | AVS-OD-03 |
| IN-03 | The §28/§29 public lifecycle does not apply to internal majors: no six-month floor, no `Sunset` header, no public OpenAPI deprecation, no 410 and no published sunset date. Retirement follows §27.3 only. | AVS-OD-04 |
| IN-04 | The producer ships compatibility first: the serving module deploys support for a new shape before any caller depends on it; expand/contract applies. | AVS-OD-04, 5A L1374 |
| IN-05 | A breaking internal change requires a successor internal major `/api/internal/v{n+1}` (HYPOTHETICAL). The old internal major stays served until every authorized caller is confirmed deployed against the successor; removal is deployment-coordinated. | AVS-OD-04 |
| IN-06 | The `service_id` allowlist, internal JWT authentication and fail-closed behavior are unchanged across internal majors. | AAM L371, AAM L142, 6A L627, AAM L1247 |
| IN-07 | Internal errors use the internal error class and follow §20. | AEC L86 |

## 10. WebSocket Protocol Versioning

A breaking WebSocket event-schema change requires a new WebSocket major such as `/ws/v2`. Event-level `version` advancement within `/ws/v1` is limited to compatible/additive evolution and must not be used to deliver a breaking representation to existing `/ws/v1` clients. (`/ws/v2` is HYPOTHETICAL and NOT CREATED.)

| Rule ID | Rule | Source |
|---|---|---|
| WSP-01 | WebSocket endpoints live under `/ws/v{major}`, not under `/api/v1`; the current major is `v1` with 4 routes. | 6A L118 |
| WSP-02 | AX-C advances independently of AX-A and AX-B. | AVS-OD-03 |
| WSP-03 | A breaking WebSocket event-schema change MUST be delivered only on a new WebSocket major. | AVS-OD-11 |
| WSP-04 | The binary audio contract (raw binary audio plus JSON control frames, no generic envelope) is part of the `/ws/v1` contract; any incompatible change to it requires a new WebSocket major. | 6D L529, 6A L723 |
| WSP-05 | The connect-time authentication handshake is part of the contract; changing it is breaking. | 6A L716, 6D L541, 6I L892 |
| WSP-06 | Close codes 4404 and 4408 are part of the contract. | 6D L543, 6D L613 |
| WSP-07 | Resume semantics are part of the contract: no mid-stream resume for voice audio; event-stream resume is supported. | 6A L718, 6D L614 |
| WSP-08 | Per-connection sequence semantics and stable per-subscription identity are part of the contract. | 6D L581, 6D L582 |
| WSP-09 | Subscribe-time authorization re-verification MUST be preserved on every WebSocket major. | 6I L893 |
| WSP-10 | No N−1/N dual-emit and no connection-time version negotiation; the URL path selects the WebSocket major. | AVS-OD-11 |
| WSP-11 | The per-source concurrent-connection limit is an OPERATIONAL number. | 6A L719, AVS-OD-10 |
| WSP-12 | No new WebSocket major is created in this phase. | AVS-OD-11 |
| WSP-13 | The WebSocket deprecation/removal mechanism is FUTURE REQUIRED WORK: the frozen sources define no WebSocket carrier for deprecation or retirement signalling, and the REST signals (`deprecated: true`, the `Sunset` header, 410 + the REST error envelope) are not a WebSocket mechanism. A successor `/ws/v{major}` MAY coexist with `/ws/v1`, but no WebSocket major deprecation or removal may be announced or executed until that mechanism is specified by a separately governed change (CM-LC-11). | AVS-OD-11, 6A L844 |

## 11. Event Schema Versioning

The event `version` field versions independently of the URL path (6A L742, 6A L823), bounded by AVS-OD-11 (§10).

### 11.1 Allowed within `/ws/v1` (event `version` MAY advance)

- ES-A1 additive event fields where existing clients remain valid;
- ES-A2 compatible event additions;
- ES-A3 compatible event-type additions where clients are already required to tolerate events they do not subscribe to or process;
- ES-A4 other non-breaking evolution supported by the frozen source.

### 11.2 Not allowed within `/ws/v1`

- ES-N1 changing required fields incompatibly;
- ES-N2 removing required fields;
- ES-N3 incompatible type changes;
- ES-N4 semantic changes that invalidate V1 consumers;
- ES-N5 a replacement breaking schema under a new event `version`.

Each ES-N item requires a new WebSocket major (§10, CM-WS-02).

## 12. Webhook Topic / Payload Versioning

| Rule ID | Rule | Source |
|---|---|---|
| WHR-01 | A bare topic string is schema version 1; a topic string `X.vN` is schema version N of topic `X`. | AVS-OD-07, 6J L781 |
| WHR-02 | Envelope `version` equals the schema version; `X-Platform-Webhook-Version` equals the envelope `version`. | 6J L809, AVS-OD-07 |
| WHR-03 | Schema version is not the REST major and MUST NOT be derived from it. | 6J L781 |
| WHR-04 | Additive payload changes require no new schema version. | 6J L1634, AVS-OD-07 |
| WHR-05 | A breaking payload change requires a successor topic; the existing topic MUST NOT change shape. | 4F L893, AVS-OD-07 |
| WHR-06 | Predecessor and successor topics MAY be delivered side by side; old topic subscriptions continue to deliver on the old schema. | 4F L893 |
| WHR-07 | An existing topic string is never removed or repurposed; predecessor-topic removal or retirement is PROHIBITED (CM-WH-04). A successor topic is additive: predecessor subscribers keep receiving the predecessor schema, and migration to the successor topic is optional with no deadline. | 6J L1634, AVS-OD-07 |
| WHR-08 | No subscription-model or database change is made for topic versioning. | AVS-OD-07 |
| WHR-09 | Current state: 19 topics, all at schema version 1 (§5.1). | 6J L720 |

## 13. Webhook Signature-Scheme Versioning

| Rule ID | Rule | Source |
|---|---|---|
| SG-01 | The webhook signature is `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")` computed over the raw, unparsed request body bytes, sent as `X-Platform-Signature: v1={hex_signature}` together with `X-Platform-Timestamp`. Verifiers MUST recompute over the raw body, compare with constant-time comparison and enforce the 5-minute replay window. | 6J L799, 6J L805, 6J L823, 6J L2005 |
| SG-02 | The `v1=` label names the signature scheme; it is not the REST major and MUST NOT be conflated with `/api/v1`. | 6J L805 |
| SG-03 | The `v1=` syntax of `X-Platform-Signature` MUST NOT be altered, and that header MUST NOT carry multiple incompatible values. | AVS-OD-08 |
| SG-04 | A successor signature scheme is PROHIBITED pending owning-source amendment (6J L1009 one algorithm; 4F L863 Published Language); it MUST NOT be built or emitted now, and no amendment is made by this document (CM-WH-12). Future compatibility note: if the owning source is later amended to authorize a successor signature scheme, introducing that successor in a separate additional header while continuing `X-Platform-Signature: v1=` unchanged is additive/non-breaking for existing v1-only verifiers. | AVS-OD-08, 6J L2106, 6J L1009, 4F L863 |
| SG-05 | Retirement of the legacy `X-Platform-Signature`/`v1=` header is FUTURE REQUIRED WORK and PROHIBITED pending a separately governed decision (CM-WH-11). The AX-A lifecycle does not apply to it: it has no retirement date, no `deprecated: true`, no `Sunset` header and no 410. | AVS-OD-08 |
| SG-06 | Only the algorithm (HMAC-SHA256) and the header family (`X-Platform-Signature: v1=` plus `X-Platform-Timestamp`) are shared platform-wide; they are Published Language. The canonical signing inputs differ: webhook `ts={X-Platform-Timestamp}.{raw_request_body}` (6J L823); plugin callout `ts={unix_timestamp}.{method}.{canonical_request_path}.{raw_body}` (6J L1009, 6J L2539). A successor scheme is PROHIBITED pending owning-source amendment; if later authorized it applies to both, each with its own canonical input. | 4F L863, 6J L823, 6J L1009, 6J L2539 |
| SG-07 | Secret rotation (dual-signature grace with `X-Platform-Signature-Previous`) is AX-L and is OPERATIONAL, not a scheme change. | 6J L811, 6J L814, 6J L815, 6J L832 |
| SG-08 | No DB field, migration, selector or successor scheme is created now. | AVS-OD-08 |
| SG-09 | In-place mutation is PROHIBITED even with a new REST major: the algorithm behind `v1=`, the `v1=` syntax and `X-Platform-Signature` semantics MUST NOT change, and successor values MUST NOT be placed in `X-Platform-Signature` (CM-WH-07). The signature scheme is AX-F and never follows a REST major. | AVS-OD-08, 6J L805, 6J L1009, 4F L863 |

## 14. Provider / OAuth Callback Versioning

| Rule ID | Rule | Source |
|---|---|---|
| CBR-01 | Callbacks are verified by the provider's own signature scheme or OAuth state, not by platform authentication; their contracts are provider-native (AX-G). | 6A L776, AAM L648 |
| CBR-02 | Public-major sunset does not retire callbacks: callback retirement follows only the CBR-03 sequence and is independent of the lifecycle state of any REST major. A `/api/v1` segment in a callback path does not permit a 410 or a removal before provider cutover is confirmed. | AVS-OD-05 |
| CBR-03 | Callback migration MUST follow, in order: (1) register/configure the successor with the provider; (2) accept old and new; (3) verify signatures/state on both; (4) confirm provider cutover; (5) remove the old. | AVS-OD-05 |
| CBR-04 | Provider-native contracts stay distinct from the public error-envelope lifecycle and from outbound webhooks (three distinct mechanisms). | AVS-OD-05, AEC L87, 6A L778 |
| CBR-05 | No callback path is renamed in this phase. | AVS-OD-05 |
| CBR-06 | `410 OAUTH_STATE_EXPIRED` on OAuth callbacks is an OAuth-state outcome and is not the sunset contract. | 6J L481, AEC L466 |

| AMI ID | Method | Path | Profile | Verification | Lifecycle |
|---|---|---|---|---|---|
| AMI-6B-013 | GET | `/api/v1/auth/oauth/{provider}/callback` | CALLBACK_BROWSER_OAUTH | OAuth state | AVS-OD-05 sequence; independent of REST-major lifecycle |
| AMI-6D-021 | POST | `/webhooks/voice/{provider_slug}/events` | CALLBACK_VOICE_PROVIDER | provider signature | AVS-OD-05 sequence; independent of REST-major lifecycle |
| AMI-6J-011 | GET | `/api/v1/integrations/oauth/{definition_key}/callback` | CALLBACK_BROWSER_OAUTH | OAuth state | AVS-OD-05 sequence; independent of REST-major lifecycle |
| AMI-6J-014 | POST | `/api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` | CALLBACK_INTEGRATION_PROVIDER | provider signature | AVS-OD-05 sequence; independent of REST-major lifecycle |
| AMI-6K-023 | POST | `/api/v1/billing/payment-providers/{provider_slug}/webhook` | CALLBACK_PAYMENT_PROVIDER | provider signature | AVS-OD-05 sequence; independent of REST-major lifecycle |

Anchors: 6B L1515 (auth OAuth callback), 6K L2249 (payment-provider webhook), AMI L231 (voice provider callback).

## 15. Plugin SemVer / min_platform_version

| Rule ID | Rule | Source |
|---|---|---|
| PL-01 | `PluginVersion` carries its own SemVer (AX-H); an approved manifest is immutable and changes require a new version, never an in-place edit. | 6J L93, 6J L1061, 6J L1193 |
| PL-02 | `min_platform_version` stays SemVer-shaped. Only MAJOR is evaluated; MINOR and PATCH are retained but MUST NOT be evaluated. | AVS-OD-06, 6J L1047 |
| PL-03 | A plugin is compatible when at least one served, non-sunset AX-A public major satisfies its MAJOR. `1.0.0` stays compatible while V1 is supported. | AVS-OD-06, 6J L1201 |
| PL-04 | The check runs at install and upgrade time against the platform's current public majors; incompatibility returns `PLUGIN_VERSION_INCOMPATIBLE`. | 6J L1059, 6J L1445, AEC L166 |
| PL-05 | No 6J amendment is made and no platform SemVer is invented; the URL-path major is the only formal platform version signal. | AVS-OD-06, 6J L1201 |
| PL-06 | Existing installations pinned to a deprecated PluginVersion continue running; a PluginVersion change resets `enabled_capabilities`. | 6J L1197, 6J L1207 |

## 16. Resource Versions That Are NOT API Versions

| Resource version | Axis | Meaning | Relation to API major | Source |
|---|---|---|---|---|
| AgentVersion | AX-J | Immutable agent configuration snapshot | None — MUST NOT select or imply an API major | 6E L28 |
| WorkflowVersion | AX-J | Workflow definition version | None | 6I L15 |
| PromptVersion | AX-J | Resolved live by PromptId | None | 6I L363, 6I L591 |
| Plan / PlanVersion / PlanPrice | AX-J | Commercial catalog versions | None | 6K L51, 6K L52 |
| PluginVersion | AX-H | Plugin manifest SemVer | None | 6J L93 |
| Alembic revision | AX-K | Database schema revision | None | 5A L1362 |
| Webhook schema version | AX-E | Topic payload version | None | 6J L781 |
| Signature scheme `v1=` | AX-F | Signature label | None | 6J L805 |
| ETag | none | Optimistic-concurrency token | None | 6A L288 |

## 17. Breaking / Non-Breaking Compatibility Matrix

### 17.1 Behavioral Test

Scope (normative): Q1–Q10 apply to changes in the contracted request/response/protocol behavior. Explicitly configured operational values covered by CM-RL-01 and CM-RL-02 are outside this contract-diff test while their wire contract and enforcement semantics remain unchanged.

Within that scope, a change is breaking when any question below answers YES for any existing consumer of the current major. The matrix rows record the deciding question.

| Q | Question |
|---|---|
| Q1 | Would a request valid under V1 become invalid? |
| Q2 | Would a successful V1 operation become an error? |
| Q3 | Would the same request produce materially different business meaning? |
| Q4 | Would a conforming V1 parser fail? |
| Q5 | Would a previously accepted credential/principal become denied? |
| Q6 | Would a documented field/code/status disappear or change meaning? |
| Q7 | Would cross-tenant/security behavior observably change? |
| Q8 | Could a retry that was safe before now duplicate a real-world action? |
| Q9 | Would an existing webhook subscriber silently receive incompatible meaning? |
| Q10 | Would an existing WS consumer need a different parser/framing contract? |

| Change | Classification | Row |
|---|---|---|
| Numeric request-rate or abuse-protection threshold change, 429 contract unchanged | OPERATIONAL (outside the contract-diff test) | CM-RL-01 |
| Quota VALUE change through 6K §25 / 6M §18 | No API-version action (outside the contract-diff test) | CM-RL-02 |
| Change to 429 status, `RATE_LIMIT_EXCEEDED` or `Retry-After`/`X-RateLimit-*` semantics | BREAKING | CM-RL-03 |
| Quota wire shape or error-contract change | Classified by §17.1 Q1–Q10 | CM-RL-05, CM-SEC-12 |
| Admission, authority, billing, pricing or enforcement semantics | Not protected by AVS-OD-10; classified by its own row | CM-RL-05 |
| Bypassing rate limiting or quota enforcement | PROHIBITED | CM-RL-04 |

### 17.2 Classification Vocabulary

| Classification | Breaking? | Outcome (§1.1) |
|---|---|---|
| BREAKING | YES | O-4 |
| NON-BREAKING | NO | O-1 |
| NON-BREAKING (SECURITY REVIEW REQUIRED) | NO | O-1 after security review |
| CONDITIONAL | CONDITIONAL | O-2 (NO branch) or O-4 (YES branch) |
| OPERATIONAL | NO | O-1 |
| LIFECYCLE | LIFECYCLE | O-3 |
| PROHIBITED | PROHIBITED | O-5 |

Every CONDITIONAL row states a deterministic `NO when` and `YES when` condition. "Always" means the classification holds for every instance of the change.

### 17.3 Matrix

| CM ID | Group | Change | Breaking? | Deterministic condition | Classification | Axis | Version action / successor | Rollout order | Deprecation behavior | Client obligation | Server obligation | Security requirement | Reason | Operational requirement | Required compatibility test | Source |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CM-REQ-01 | Request | Add optional request field with a safe default | CONDITIONAL | NO when omission yields exactly the V1 behavior and every instance accepts the field before any client sends it; YES when omission changes V1 behavior | CONDITIONAL | Route axis (AX-A/AX-B) | CONDITIONAL — SERVER-FIRST: none when NO; successor major when YES | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1 NO only in server-first order: under `extra="forbid"` an old instance rejects the field | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L577, 6A L837 |
| CM-REQ-02 | Request | Add optional request field without a safe default (omission changes behavior) | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L837 |
| CM-REQ-03 | Request | Add required request field | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES: V1-valid requests become invalid | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L837 |
| CM-REQ-04 | Request | Remove request field | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES under `extra="forbid"` | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L577, 6A L835 |
| CM-REQ-05 | Request | Rename request field | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-REQ-06 | Request | Request-field type or shape change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-REQ-07 | Request | Request enum expansion (new accepted value) | CONDITIONAL | NO when existing values keep their meaning and every instance accepts the value before clients send it; YES when an existing value changes meaning | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1/Q3 NO in server-first order | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L836 |
| CM-REQ-08 | Request | Request enum removal/restriction | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L836 |
| CM-REQ-09 | Request | Request validation tightening | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L837 |
| CM-REQ-10 | Request | Request validation loosening | CONDITIONAL | NO when every previously valid request keeps the same outcome and meaning; YES when a previously rejected input now changes the meaning of an existing request | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1 NO; Q3 decides | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L832 |
| CM-REQ-11 | Request | Change the default applied when a field is omitted | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L839 |
| CM-REQ-12 | Request | New required request header (including `Idempotency-Key` or `If-Match`) | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L460, 6A L837 |
| CM-REQ-13 | Request | New optional request header with semantic effect | CONDITIONAL | NO when absence yields exactly the V1 behavior; YES when absence changes behavior | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1/Q3 decide | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L837 |
| CM-REQ-14 | Request | Request content-type change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-NUL-01 | Nullability | Request field newly accepts `null` | CONDITIONAL | NO when `null` has no prior meaning and every instance accepts it before clients send it; YES when `null` changes the meaning of an existing request | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1 NO in server-first order | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L835 |
| CM-NUL-02 | Nullability | Request field newly rejects `null` | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-NUL-03 | Nullability | Response field may newly be `null` | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-NUL-04 | Nullability | Response field newly guaranteed non-null | CONDITIONAL | NO when `null` had no documented meaning; YES when `null` had a documented meaning | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Not order-sensitive (response-only) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT rely on the new guarantee on older instances | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q6 decides | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L835 |
| CM-RQD-01 | Requiredness | Request field optional → required | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L837 |
| CM-RQD-02 | Requiredness | Request field required → optional | CONDITIONAL | NO when the default applied on omission equals a value V1 clients could already send; YES when omission creates a new meaning | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q3 decides | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L837 |
| CM-RQD-03 | Requiredness | Response field may become absent | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4/Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L834 |
| CM-RQD-04 | Requiredness | Response field becomes always present | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q4 NO | Standard deploy | Existing-major contract test passes unchanged | 6A L834 |
| CM-RES-01 | Response | Add optional response field | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q4 NO: tolerant reader | Standard deploy | Existing-major contract test passes unchanged | 6A L834 |
| CM-RES-02 | Response | Remove response field | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L834 |
| CM-RES-03 | Response | Rename response field | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4/Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L834 |
| CM-RES-04 | Response | Response-field type or shape change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-RES-05 | Response | Response enum expansion (new value) | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | NON-BREAKING (TOLERANT READER): clients treat an unrecognized value as unknown | Standard deploy | Existing-major contract test passes unchanged | 6A L836, 6A L848 |
| CM-RES-06 | Response | Response enum value removal | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L836 |
| CM-RES-07 | Response | Change the meaning of an existing enum value in place | PROHIBITED | Always inside an existing major; a successor major MAY introduce a new value instead | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q3/Q6 YES; §35 AN-20 | Reviewer MUST reject | Review check and negative test prove absence | 6A L836 |
| CM-RES-08 | Response | Change what a 200 response means | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L839 |
| CM-RES-09 | Response | Success status-code change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L839 |
| CM-RES-10 | Response | Remove `ETag` from single-resource GET | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6/Q8 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L288, 6A L460 |
| CM-RES-11 | Response | Relax `Cache-Control: private, no-store` on tenant-scoped responses | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L289, 6A L290 |
| CM-RES-12 | Response | Add response header | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q4 NO | Standard deploy | Existing-major contract test passes unchanged | 6J L2106 |
| CM-RTE-01 | Route | Add endpoint | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | No existing request changes | Standard deploy | Existing-major contract test passes unchanged | 6A L835 |
| CM-RTE-02 | Route | Add HTTP method to an existing resource | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | No existing request changes | Standard deploy | Existing-major contract test passes unchanged | 6A L839 |
| CM-RTE-03 | Route | Change HTTP method of an operation | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L832 |
| CM-RTE-04 | Route | Change route path | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L832 |
| CM-RTE-05 | Route | Rename route parameter | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q8 YES: changes the idempotency route template (§23) | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L437, AVS-OD-09 |
| CM-RTE-06 | Route | Route-parameter type change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L835 |
| CM-RTE-07 | Route | Route-parameter semantics change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L839 |
| CM-RTE-08 | Route | Endpoint removal | YES | Always; only by omission from a successor major — AX-A: after the predecessor's §29 sunset; AX-B: after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED; removal only by omission from the successor — AX-A: the predecessor keeps the endpoint until its §29 sunset; AX-B: the predecessor keeps the endpoint until every authorized `service_id` caller is confirmed on the successor | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q2/Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L846, AVS-OD-04 |
| CM-RTE-09 | Route | Change query-parameter semantics | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L839 |
| CM-RTE-10 | Route | Add optional query parameter | CONDITIONAL | NO when absence yields exactly the V1 behavior; YES when absence changes behavior | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1 NO in server-first order: an old instance rejects an unknown allow-listed parameter with 422 | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L415 |
| CM-PAG-01 | Pagination | Default page size change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L840, 6A L403 |
| CM-PAG-02 | Pagination | Raise maximum page size or sort/filter caps | CONDITIONAL | NO when every instance accepts the higher value before clients send it; YES when a V1 request changes result meaning | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1 NO in server-first order; over-maximum behavior is not specified by the source | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L404, 6A L416, 6A L418 |
| CM-PAG-03 | Pagination | Lower maximum page size or sort/filter caps | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L404, 6A L416, 6A L418 |
| CM-PAG-04 | Pagination | Default sort change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L405, 6A L406 |
| CM-PAG-05 | Pagination | Add filter/sort field to the allow-list | CONDITIONAL | NO when every instance accepts the field before clients send it; YES when an existing field's meaning changes | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | 6A L840 lists it non-breaking; an old instance returns 422, so server-first order applies | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L840, 6A L415 |
| CM-PAG-06 | Pagination | Remove filter/sort field from the allow-list | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L415 |
| CM-PAG-07 | Pagination | Filtering behavior change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q3 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L415 |
| CM-PAG-08 | Pagination | Cursor encoding change | CONDITIONAL | NO when every instance decodes both old and new cursors before any instance issues new cursors; YES when an issued cursor stops decoding | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18): dual decode everywhere, then new encode | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q2 decides; cursors are opaque | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L387, 6A L397 |
| CM-PAG-09 | Pagination | Pagination style or pagination-meta shape change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L387 |
| CM-ERR-01 | Errors | Error status-code change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L653 |
| CM-ERR-02 | Errors | Error-code change for an existing condition | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L653 |
| CM-ERR-03 | Errors | Change `error.code` semantics in place | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q6 YES; §35 AN-19 | Reviewer MUST reject | Review check and negative test prove absence | 6A L653 |
| CM-ERR-04 | Errors | New error code | CONDITIONAL | NO when it covers a condition that did not exist on that route and is registered in the AEC first; YES when it replaces an existing code or makes a previously successful request fail | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | AEC registration first, then server deploy | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q2/Q6 decide | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | AEC L99, 6A L653 |
| CM-ERR-05 | Errors | Previously successful request now errors | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q2 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L839 |
| CM-ERR-06 | Errors | Retryability flip | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q8 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | AEC L172 |
| CM-ERR-07 | Errors | Error `details` field removed, renamed or retyped | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4/Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L653 |
| CM-ERR-08 | Errors | Add optional error `details` field | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q4 NO | Standard deploy | Existing-major contract test passes unchanged | 6A L834 |
| CM-ERR-09 | Errors | Human-readable error-message wording | NO | Always | NON-BREAKING | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | `message` is not a contract | Standard deploy | Existing-major contract test passes unchanged | 6A L653 |
| CM-ERR-10 | Errors | Error-envelope structure change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L653 |
| CM-ERR-11 | Errors | Expose internals (SQL text, stack traces) in errors | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L665 |
| CM-SEC-01 | AuthN/AuthZ | Authentication requirement strengthened (new credential, scope or token type) | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q5 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L838 |
| CM-SEC-02 | AuthN/AuthZ | Remove authentication from a business route | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L576 |
| CM-SEC-03 | AuthN/AuthZ | Accept an additional authentication mechanism | NO | Always | NON-BREAKING (SECURITY REVIEW REQUIRED) | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy after security review | None | MUST tolerate (tolerant reader) | MUST record the security review before merge | Security review REQUIRED before merge (6A L838; §34) | Q5 NO; widens access | Review record retained | Existing-major contract test passes; authorization regression test covers the widened grant | 6A L838 |
| CM-SEC-04 | AuthN/AuthZ | Authorization tightening | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q5 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L838 |
| CM-SEC-05 | AuthN/AuthZ | Authorization loosening | NO | Always | NON-BREAKING (SECURITY REVIEW REQUIRED) | Route axis (AX-A/AX-B) | None — ships inside the current major | Server deploy after security review | None | MUST tolerate (tolerant reader) | MUST record the security review before merge | Security review REQUIRED before merge (6A L838; §34) | Q5 NO; not automatically security-safe | Review record retained | Existing-major contract test passes; authorization regression test covers the widened grant | 6A L838 |
| CM-SEC-06 | Concealment | Change a concealing 404 into a revealing 403 | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | AAM L79 |
| CM-SEC-07 | Concealment | Change 403 into a concealing 404 | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q6 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | AAM L79 |
| CM-SEC-08 | Security | Bypass RLS or tenant isolation | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L576 |
| CM-SEC-09 | Security | Return a raw secret after issuance | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L579 |
| CM-SEC-10 | Security | Weaken sensitive-media controls | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L581, AAM L662 |
| CM-SEC-11 | Security | Weaken platform-admin or break-glass controls | PROHIBITED | Always | PROHIBITED | AX-A | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | AAM L587 |
| CM-SEC-12 | Security | Bypass compliance, suppression/DNC, billing or quota enforcement | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | AEC L171 |
| CM-SEC-13 | Security | Remove an audit requirement | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | AAM L79 |
| CM-IDM-01 | Idempotency | Change replay window, fingerprint, scope or mismatch code | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q8 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L437, 6A L439, 6A L440, 6A L442 |
| CM-IDM-02 | Idempotency | Add optional `Idempotency-Key` support to an unsafe method | CONDITIONAL | NO when the key is optional and its absence keeps V1 behavior; YES when the key becomes required (CM-REQ-12) | CONDITIONAL | Route axis (AX-A/AX-B) | None when the NO condition holds; successor major (AX-A §27.1, AX-B §27.3) when the YES condition holds | Server-first (§18) | None when NO; when YES: AX-A: per §28/§29; AX-B: removal only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | MUST NOT use it until every instance supports it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Q1/Q8 decide | Verify fleet convergence before client enablement | Mixed-fleet test: old and new instances both serve current clients | 6A L437, 6A L445 |
| CM-IDM-03 | Idempotency | Replay a V1 idempotency record on a successor major | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | NO REPLAY — NEW OPERATION: the endpoint component includes the major prefix | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-09, 6A L437, 6A L438 |
| CM-IDM-04 | Concurrency | `If-Match`/`ETag` behavior change | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q1/Q8 YES | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L143, 6A L460, 6A L461 |
| CM-IDM-05 | Idempotency | Relax a persistent uniqueness invariant | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q8 YES | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-09 |
| CM-RL-01 | Rate limit | Change a numeric request-rate or abuse-protection threshold (raise or lower) with the 429 signalling contract unchanged | NO | Always; only the numeric threshold changes and the 429 signalling contract is unchanged | OPERATIONAL | Route axis (AX-A/AX-B) | None — operational/security policy change (AVS-OD-10) | Configuration/deploy change; no version action | None | MUST honor the unchanged signalling contract | MUST keep the signalling contract unchanged | MUST NOT weaken authz, quota accounting, billing, abuse controls or tenant isolation | OPERATIONAL (AVS-OD-10): configured request-protection value outside the §17.1 contract-diff test; never priced | Change record and monitoring (§33) | Signalling-contract test passes unchanged | 6A L535, 6A L537, 6A L542, 6K L1923, AVS-OD-10 |
| CM-RL-02 | Rate limit | Change a commercial/usage/capacity quota value (plan, agreement or per-organization override, including `ACTIVE_AGENTS` and `CONCURRENT_CALLS`) | NO | Always; only the numeric value changes — a change to wire shape, error contract, admission semantics, pricing, billing calculation, authority or enforcement is classified by its own row (CM-RL-03, CM-RL-04, CM-RL-05, CM-SEC-12) | OPERATIONAL | Route axis (AX-A/AX-B) | None — quota values are governed by 6K §25 (Quotas) and 6M §18 (Quota Overrides); they are not API versions | Change through the owning domain contract (6K, 6M); no version action | None | MUST honor the unchanged signalling contract | MUST keep quota wire shape, error contract, admission semantics and enforcement unchanged | MUST NOT weaken authz, quota accounting, billing, abuse controls or tenant isolation | Configured quota value outside the §17.1 contract-diff test; governed by 6K §25 and 6M §18 and not an API version | Change record and monitoring (§33) | Signalling-contract test passes unchanged | AEC L171, 6K L2035, 6K L2046, 6K L1924, 6K L3625, 6M L155, 6M L251, AVS-OD-10 |
| CM-RL-03 | Rate limit | Change the 429 contract (status, `RATE_LIMIT_EXCEEDED`, `Retry-After`, `X-RateLimit-*` semantics) | YES | Always | BREAKING | Route axis (AX-A/AX-B) | Successor major REQUIRED on the route's axis; MUST NOT ship inside the current major | AX-A: §27.1 successor workflow, both majors served before any client migrates; AX-B: §27.3 producer-first, both internal majors coexist before any caller migrates | AX-A: deprecation and removal per §28/§29; AX-B: no public deprecation signals and no published retirement date, the old internal major is removed only after every authorized `service_id` caller is confirmed on the successor (AVS-OD-04) | AX-A: MUST migrate to the successor before the predecessor's published sunset date (§28); AX-B: every authorized `service_id` caller MUST migrate and be confirmed deployed before the old internal major is removed | MUST keep the old contract unchanged on the old major | MUST NOT weaken any §34 invariant | Q4/Q6 YES: the 429 signalling contract is contracted wire behavior, not a configured value; AVS-OD-10 does not cover it | Contract tests for old and new major; AX-B: authorized `service_id` caller inventory and deployment confirmation | Old-major contract test proves unchanged behavior; successor test proves new behavior; AX-B: caller-migration test proves every authorized caller is on the successor before removal | 6A L544, AEC L172, AVS-OD-10 |
| CM-RL-04 | Rate limit | Remove rate limiting or quota accounting | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-10 |
| CM-RL-05 | Rate limit | Use AVS-OD-10 to ship a change to pricing, billing calculation, admission, authority, enforcement, wire shape or error contract as an OPERATIONAL change | PROHIBITED | Always | PROHIBITED | Route axis (AX-A/AX-B) | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | AVS-OD-10 covers configured numeric values only; admission, authority, billing, pricing, enforcement, wire-shape and error-contract changes are outside it and are classified by §17.1 Q1–Q10 | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-10 |
| CM-CB-01 | Callback | Provider changes its callback contract | CONDITIONAL | NO when the platform accepts and verifies both old and new provider forms before provider cutover; YES when only one form can be verified | CONDITIONAL | AX-G | None on any API axis when NO; AVS-OD-05 sequence when YES | AVS-OD-05 sequence: accept both, verify both, confirm provider cutover, remove old | None when NO; when YES the old form is removed only after provider cutover is confirmed | Provider-controlled; no platform client obligation | MUST accept and verify both provider forms until provider cutover is confirmed | MUST NOT weaken any §34 invariant | Provider-native (§14) | Verify fleet convergence before client enablement | Both provider forms verify against the platform | AVS-OD-05, 6A L776 |
| CM-CB-02 | Callback | Change callback path or provider registration | YES | Always | BREAKING | AX-G | Successor callback registration via the AVS-OD-05 sequence; not a REST major | §27.5 AVS-OD-05 sequence: register/configure successor → accept both → verify signature/OAuth state on both → confirm provider cutover → remove old | Old callback removed only after provider cutover is confirmed; independent of any REST-major lifecycle | Provider cuts over to the successor registration; no platform client obligation | MUST accept and verify old and successor callbacks until provider cutover is confirmed | MUST NOT weaken any §34 invariant | Provider registration changes | Provider-cutover confirmation recorded | Both callbacks verify; the old callback stays active until provider cutover is confirmed | AVS-OD-05 |
| CM-CB-03 | Callback | Return 410 on, or remove, a callback before provider migration | PROHIBITED | Always, independent of the lifecycle state of any REST major, including when the callback path contains `/api/v1` | PROHIBITED | AX-G | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | OLD CALLBACK STAYS ACTIVE UNTIL PROVIDER MIGRATION | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-05 |
| CM-CB-04 | Callback | Relax callback signature or OAuth-state verification | PROHIBITED | Always | PROHIBITED | AX-G | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | 6A L776, AAM L648 |
| CM-WH-01 | Webhook | Additive webhook payload field | NO | Always | NON-BREAKING | AX-E | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q9 NO | Standard deploy | Existing-major contract test passes unchanged | 6J L1634, AVS-OD-07 |
| CM-WH-02 | Webhook | Breaking webhook payload change | YES | Always | BREAKING | AX-E | SUCCESSOR TOPIC REQUIRED (`X.vN`); the existing topic MUST NOT change shape | §27.5: publish the successor topic; subscribers opt in; the predecessor topic keeps delivering the predecessor schema | None — the predecessor topic remains valid and is never removed or repurposed (6J L1634); removal PROHIBITED (CM-WH-04) | MAY subscribe to the successor topic; migration is optional and has no deadline | MUST keep delivering the predecessor topic with the predecessor schema | MUST NOT weaken any §34 invariant | Q9 YES | Delivery monitoring for both topics | Predecessor-topic schema test passes unchanged; successor-topic schema test proves the new shape | 4F L893, AVS-OD-07 |
| CM-WH-03 | Webhook | Repurpose an existing topic string | PROHIBITED | Always | PROHIBITED | AX-E | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q9 YES | Reviewer MUST reject | Review check and negative test prove absence | 6J L1634 |
| CM-WH-04 | Webhook | Remove or retire a topic string | PROHIBITED | Always under current sources (6J L1634) | PROHIBITED | AX-E | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Topic strings are never removed or repurposed; the stronger source requirement prevails over AVS-OD-07 | Reviewer MUST reject | Review check and negative test prove absence | 6J L1634, AVS-OD-07 |
| CM-WH-05 | Webhook | Introduce successor topic `X.vN` alongside `X` | NO | Always | NON-BREAKING | AX-E | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Existing subscribers unaffected | Standard deploy | Existing-major contract test passes unchanged | 4F L893 |
| CM-WH-06 | Webhook | Webhook envelope structure change | YES | Always | BREAKING | AX-E | SUCCESSOR TOPIC REQUIRED for every affected topic; in-place envelope change MUST NOT ship | §27.5: publish the successor topic; subscribers opt in; the predecessor topic keeps delivering the predecessor schema | None — the predecessor topic remains valid and is never removed or repurposed (6J L1634); removal PROHIBITED (CM-WH-04) | MAY subscribe to the successor topic; migration is optional and has no deadline | MUST keep delivering the predecessor topic with the predecessor schema | MUST NOT weaken any §34 invariant | Q9 YES | Delivery monitoring for both topics | Predecessor-topic schema test passes unchanged; successor-topic schema test proves the new shape | 6J L809, AVS-OD-07 |
| CM-WH-07 | Webhook | Signature algorithm or signature syntax change in place (including behind a new REST major) | PROHIBITED | Always, even when a new REST major is released | PROHIBITED | AX-F | IN-PLACE CHANGE PROHIBITED — the algorithm behind `v1=`, the `v1=` syntax and `X-Platform-Signature` semantics MUST NOT change, and successor values MUST NOT be placed in that header, even with a new REST major | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Existing verifiers fail; the signature scheme is AX-F, not a REST major | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-08, 6J L805, 6J L1009, 4F L863 |
| CM-WH-08 | Webhook | Put multiple incompatible values in `X-Platform-Signature` | PROHIBITED | Always | PROHIBITED | AX-F | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Existing verifiers fail | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-08 |
| CM-WH-09 | Webhook | Alter the `v1=` syntax in place | PROHIBITED | Always | PROHIBITED | AX-F | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Existing verifiers fail | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-08, 6J L805 |
| CM-WH-10 | Webhook | Signing-secret rotation with dual-signature grace | NO | Always | OPERATIONAL | AX-L | None — secret rotation, not a scheme change (AX-L) | Configuration/deploy change; no version action | None | MUST honor the unchanged signalling contract | MUST keep the signalling contract unchanged | MUST NOT weaken authz, quota accounting, billing, abuse controls or tenant isolation | Consumers unaffected | Change record and monitoring (§33) | Signalling-contract test passes unchanged | 6J L811, 6J L2106 |
| CM-WH-11 | Webhook | Retire the legacy signature header | PROHIBITED | Always under current sources | PROHIBITED | AX-F | PROHIBITED pending a separately governed decision; legacy-header retirement is FUTURE REQUIRED WORK and has no REST lifecycle mechanism | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Separately governed (AVS-OD-08); FUTURE REQUIRED WORK | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-08 |
| CM-WH-12 | Webhook | Add a successor signature header while `v1=` continues to be emitted | PROHIBITED | Always under current frozen sources (6J L1009 one algorithm; 4F L863 Published Language) | PROHIBITED | AX-F | PROHIBITED pending owning-source amendment — no successor signature scheme may be built or emitted now. Future compatibility note (AVS-OD-08): if the owning source is later amended to authorize a successor signature scheme, introducing that successor in a separate additional header while continuing `X-Platform-Signature: v1=` unchanged is additive/non-breaking for existing v1-only verifiers | Not applicable now — MUST NOT be implemented; after amendment it would apply platform-wide, covering webhooks and plugin callouts, each with its own canonical input (§13 SG-06) | None — `v1=` keeps being emitted unchanged; legacy retirement is CM-WH-11 | None — v1-only verifiers are unaffected | MUST NOT implement or emit a successor signature header before the owning-source amendment; MUST keep emitting `X-Platform-Signature: v1=` unchanged | MUST NOT weaken any §34 invariant | PROHIBITED pending owning-source amendment; not BREAKING (see future compatibility note) | Reviewer MUST reject any successor-scheme implementation before the owning-source amendment | Review check and negative test prove no successor signature header is emitted | 6J L2106, 6J L1009, 4F L863, 6J L2539, AVS-OD-08 |
| CM-WS-01 | WebSocket | Additive WebSocket event field | NO | Always | NON-BREAKING | AX-D | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q10 NO | Standard deploy | Existing-major contract test passes unchanged | AVS-OD-11, 6A L823 |
| CM-WS-02 | WebSocket | Breaking WebSocket event change | YES | Always | BREAKING | AX-C | NEW WS MAJOR REQUIRED; MUST NOT ship in `/ws/v1` | §27.4: successor WebSocket major (HYPOTHETICAL, NOT CREATED) served alongside `/ws/v1`; no dual emit, no negotiation | Predecessor WebSocket major stays served; its deprecation and removal are BLOCKED until the WebSocket mechanism is specified (FUTURE REQUIRED WORK, CM-LC-11) | MAY migrate to the successor WebSocket major; no deadline exists while the mechanism is unspecified | MUST keep the `/ws/v1` contract unchanged | MUST NOT weaken any §34 invariant | Q10 YES | Contract tests for both WebSocket majors | `/ws/v1` contract test proves unchanged behavior; successor WebSocket contract test proves new behavior | AVS-OD-11 |
| CM-WS-03 | WebSocket | New WebSocket event type | CONDITIONAL | NO when clients are already required to tolerate events they do not subscribe to or process; YES when that tolerance is not already required | CONDITIONAL | AX-D | None when NO; NEW WS MAJOR (AX-C) when YES — MUST NOT ship in `/ws/v1` | Server-first (§18) when NO; §27.4 when YES | None when NO; when YES the `/ws/v1` retirement is BLOCKED (CM-LC-11) | MUST ignore event types it does not process | MUST keep existing event types unchanged | MUST NOT weaken any §34 invariant | Q10 decides | Verify the client tolerance requirement before emitting the new type | Existing `/ws/v1` client test passes with the new event type present | AVS-OD-11 |
| CM-WS-04 | WebSocket | Advance event `version` to carry a breaking change within `/ws/v1` | PROHIBITED | Always | PROHIBITED | AX-D | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q10 YES | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-11 |
| CM-WS-05 | WebSocket | Compatible event `version` advancement | NO | Always | NON-BREAKING | AX-D | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Q10 NO | Standard deploy | Existing-major contract test passes unchanged | AVS-OD-11, 6A L742 |
| CM-WS-06 | WebSocket | Binary audio contract change | YES | Always | BREAKING | AX-C | NEW WS MAJOR REQUIRED; MUST NOT ship in `/ws/v1` | §27.4: successor WebSocket major (HYPOTHETICAL, NOT CREATED) served alongside `/ws/v1`; no dual emit, no negotiation | Predecessor WebSocket major stays served; its deprecation and removal are BLOCKED until the WebSocket mechanism is specified (FUTURE REQUIRED WORK, CM-LC-11) | MAY migrate to the successor WebSocket major; no deadline exists while the mechanism is unspecified | MUST keep the `/ws/v1` contract unchanged | MUST NOT weaken any §34 invariant | Q10 YES | Contract tests for both WebSocket majors | `/ws/v1` contract test proves unchanged behavior; successor WebSocket contract test proves new behavior | 6D L529, 6A L723 |
| CM-WS-07 | WebSocket | WebSocket authentication handshake change | YES | Always | BREAKING | AX-C | NEW WS MAJOR REQUIRED; MUST NOT ship in `/ws/v1` | §27.4: successor WebSocket major (HYPOTHETICAL, NOT CREATED) served alongside `/ws/v1`; no dual emit, no negotiation | Predecessor WebSocket major stays served; its deprecation and removal are BLOCKED until the WebSocket mechanism is specified (FUTURE REQUIRED WORK, CM-LC-11) | MAY migrate to the successor WebSocket major; no deadline exists while the mechanism is unspecified | MUST keep the `/ws/v1` contract unchanged | MUST NOT weaken any §34 invariant | Q5/Q10 YES | Contract tests for both WebSocket majors | `/ws/v1` contract test proves unchanged behavior; successor WebSocket contract test proves new behavior | 6A L716, 6D L541 |
| CM-WS-08 | WebSocket | Close-code change (4404, 4408) | YES | Always | BREAKING | AX-C | NEW WS MAJOR REQUIRED; MUST NOT ship in `/ws/v1` | §27.4: successor WebSocket major (HYPOTHETICAL, NOT CREATED) served alongside `/ws/v1`; no dual emit, no negotiation | Predecessor WebSocket major stays served; its deprecation and removal are BLOCKED until the WebSocket mechanism is specified (FUTURE REQUIRED WORK, CM-LC-11) | MAY migrate to the successor WebSocket major; no deadline exists while the mechanism is unspecified | MUST keep the `/ws/v1` contract unchanged | MUST NOT weaken any §34 invariant | Q10 YES | Contract tests for both WebSocket majors | `/ws/v1` contract test proves unchanged behavior; successor WebSocket contract test proves new behavior | 6D L543, 6D L613 |
| CM-WS-09 | WebSocket | N−1/N dual-emit or connection-time version negotiation | PROHIBITED | Always | PROHIBITED | AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Competing selector | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-11 |
| CM-WS-10 | WebSocket | Change per-source connection-limit number | NO | Always | OPERATIONAL | AX-C | None — operational/security policy change (AVS-OD-10) | Configuration/deploy change; no version action | None | MUST honor the unchanged signalling contract | MUST keep the signalling contract unchanged | MUST NOT weaken authz, quota accounting, billing, abuse controls or tenant isolation | OPERATIONAL | Change record and monitoring (§33) | Signalling-contract test passes unchanged | 6A L719, AVS-OD-10 |
| CM-WS-11 | WebSocket | Resume semantics change | YES | Always | BREAKING | AX-C | NEW WS MAJOR REQUIRED; MUST NOT ship in `/ws/v1` | §27.4: successor WebSocket major (HYPOTHETICAL, NOT CREATED) served alongside `/ws/v1`; no dual emit, no negotiation | Predecessor WebSocket major stays served; its deprecation and removal are BLOCKED until the WebSocket mechanism is specified (FUTURE REQUIRED WORK, CM-LC-11) | MAY migrate to the successor WebSocket major; no deadline exists while the mechanism is unspecified | MUST keep the `/ws/v1` contract unchanged | MUST NOT weaken any §34 invariant | Q10 YES | Contract tests for both WebSocket majors | `/ws/v1` contract test proves unchanged behavior; successor WebSocket contract test proves new behavior | 6A L718, 6D L614 |
| CM-INT-01 | Internal | Additive internal API change | CONDITIONAL | NO when the producer serves the new shape on every instance before any caller depends on it; YES when an existing caller would fail | CONDITIONAL | AX-B | None when NO; successor internal major (§27.3) when YES | Producer-first (§9 IN-04) | None when NO; when YES the old internal major is removed only after caller confirmation (AVS-OD-04) | Callers MUST NOT depend on the new shape until every producer instance serves it | MUST deploy support to every instance before any client use | MUST NOT weaken any §34 invariant | Producer-first | Verify fleet convergence before client enablement | Mixed-fleet test: callers succeed against old and new producer instances | AVS-OD-04 |
| CM-INT-02 | Internal | Breaking internal API change | YES | Always | BREAKING | AX-B | Successor internal major REQUIRED (HYPOTHETICAL `/api/internal/v{n+1}`, NOT CREATED) | §27.3 (AVS-OD-04): producer supports the successor; both internal majors coexist; callers migrate | No public deprecation signals and no published retirement date; the old internal major is removed only after every authorized `service_id` caller is confirmed deployed on the successor (CM-LC-06) | Every authorized `service_id` caller MUST migrate to the successor and be confirmed deployed before the old internal major is removed | MUST serve both internal majors unchanged until caller confirmation; MUST keep `service_id` authentication, allowlist and fail-closed behavior on both | MUST NOT weaken any §34 invariant | Callers fail | Caller inventory from the `service_id` allowlist; deployment confirmation per caller | Old-internal-major contract test proves unchanged behavior; successor test proves new behavior; caller-inventory test proves every authorized caller is on the successor before removal | AVS-OD-04 |
| CM-INT-03 | Internal | Weaken `service_id` allowlist, internal authentication or fail-closed behavior | PROHIBITED | Always | PROHIBITED | AX-B | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q7 YES | Reviewer MUST reject | Review check and negative test prove absence | AAM L371, AAM L1247 |
| CM-PLG-01 | Plugin | Evaluate MINOR or PATCH of `min_platform_version` | PROHIBITED | Always | PROHIBITED | AX-I | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Invented platform SemVer | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-06 |
| CM-PLG-02 | Plugin | Serve a successor public major while V1 is served | NO | Always | NON-BREAKING | AX-I | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | `1.0.0` stays satisfied | Standard deploy | Existing-major contract test passes unchanged | AVS-OD-06 |
| CM-PLG-03 | Plugin | Sunset of a public major that plugins rely on | LIFECYCLE | Only when an AX-A public major reaches the §29 SUNSET state; a plugin becomes incompatible only when no served, non-sunset AX-A major satisfies its MAJOR | LIFECYCLE | AX-I | Lifecycle transition: plugin compatibility re-evaluated against served, non-sunset AX-A majors (AX-R05) | Evaluated at install and upgrade time (§15 PL-04) | Follows the AX-A major's §28/§29 state; AX-I never drives AX-A | Plugin publishers MAY publish a version whose MAJOR a served AX-A major satisfies | MUST mark a plugin incompatible only when no served, non-sunset AX-A major satisfies its MAJOR | MUST NOT weaken any §34 invariant | AVS-OD-06 | Install/upgrade compatibility outcomes observed | Compatibility test: `1.0.0` stays compatible while V1 is served | AVS-OD-06, 6J L1445 |
| CM-PLG-04 | Plugin | Edit an approved plugin manifest in place | PROHIBITED | Always | PROHIBITED | AX-H | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Immutable once approved | Reviewer MUST reject | Review check and negative test prove absence | 6J L1061 |
| CM-LC-01 | Lifecycle | Deprecate a public major | LIFECYCLE | Only after successor GA, AEC sunset-contract registration and publication of the sunset date | LIFECYCLE | AX-A | Lifecycle transition per §28/§29 | §27.1 steps 9–16 | Per §28 | MUST migrate before the published sunset date | MUST emit the §28 signals of the current state | MUST NOT weaken any §34 invariant | §28 | §33 adoption metrics observed | Lifecycle-signal test (`deprecated: true`, `Sunset`) | 6A L844, AVS-OD-01, AVS-OD-02 |
| CM-LC-02 | Lifecycle | Announce deprecation or sunset before the AEC registers the sunset error contract | PROHIBITED | Always | PROHIBITED | AX-A | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | BLOCKED until the Error Catalog amendment (AVS-OD-01) | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-01, AEC L466 |
| CM-LC-03 | Lifecycle | Sunset a public major | LIFECYCLE | Only after the six-month floor, the published sunset date and every §29 gate, including the AEC prerequisite | LIFECYCLE | AX-A | Lifecycle transition per §28/§29 | §27.1 steps 9–16 | Per §28 | MUST migrate before the published sunset date | MUST return, on every request to the retired major, 410 Gone + the registered sunset error envelope/code + `Link` to the migration guide + the `Sunset` header (§28 SUNSET, SN-01); callbacks excluded (AVS-OD-05) | MUST NOT weaken any §34 invariant | §29 | §33 adoption metrics observed | Sunset-signal test proves all four: 410, registered sunset error envelope/code, `Link`, `Sunset` | 6A L846, AVS-OD-01, AVS-OD-02 |
| CM-LC-04 | Lifecycle | Shorten the compatibility period below six months | PROHIBITED | Always | PROHIBITED | AX-A | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Binding floor | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-02 |
| CM-LC-05 | Lifecycle | Lengthen the compatibility period | LIFECYCLE | Always | LIFECYCLE | AX-A | Lifecycle transition per §28/§29 | §27.1 steps 9–16 | Per §28 | MUST migrate before the published sunset date | MUST emit the §28 signals of the current state | MUST NOT weaken any §34 invariant | Floor is a minimum | §33 adoption metrics observed | Lifecycle-signal test (`deprecated: true`, `Sunset`) | AVS-OD-02 |
| CM-LC-06 | Lifecycle | Retire an internal major | LIFECYCLE | Only after every authorized `service_id` caller is confirmed deployed against the successor | LIFECYCLE | AX-B | Lifecycle transition per AVS-OD-04 (§27.3); no public REST lifecycle applies | §27.3 steps 3–6: identify callers, migrate, confirm deployment, remove in a coordinated deployment | No public deprecation signals and no published retirement date | Every authorized `service_id` caller MUST be confirmed deployed on the successor before removal | MUST keep serving the old internal major until every authorized caller is confirmed; MUST remove it only in a coordinated deployment | MUST NOT weaken any §34 invariant | Deployment-coordinated caller migration (AVS-OD-04) | Caller inventory and per-caller deployment confirmation | Caller-migration test proves every authorized `service_id` caller uses the successor; coordinated-deployment test proves the old internal route is removable without a failing caller | AVS-OD-04 |
| CM-LC-07 | Lifecycle | Remove the predecessor instantly when the successor launches | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q2 YES | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-02, AVS-OD-04, AVS-OD-11 |
| CM-LC-08 | Lifecycle | Make a `Deprecation` header a mandatory lifecycle signal | PROHIBITED | Always | PROHIBITED | AX-A | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Signal set is fixed by source | Reviewer MUST reject | Review check and negative test prove absence | 6A L844 |
| CM-LC-09 | Lifecycle | Remove a contracted API for low usage, frontend non-use, apparent lack of documentation, provider non-use or apparent DB non-need | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C/AX-G | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Not a removal gate | Reviewer MUST reject | Review check and negative test prove absence | 6A L846 |
| CM-LC-10 | Lifecycle | Mark V1 deprecated or choose a sunset date in this phase | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Out of scope (§1.3) | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-02 |
| CM-LC-11 | Lifecycle | Announce or execute a WebSocket major deprecation or removal before the WebSocket mechanism is specified | PROHIBITED | Always until the WebSocket deprecation/removal mechanism is specified (FUTURE REQUIRED WORK) | PROHIBITED | AX-C | PROHIBITED — BLOCKED: the frozen sources define no WebSocket deprecation or removal mechanism; it is FUTURE REQUIRED WORK (§10 WSP-13) | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | No WebSocket carrier is defined by the frozen sources; REST signals are not a WebSocket mechanism | Reviewer MUST reject | Review check and negative test prove absence | AVS-OD-11, 6A L844 |
| CM-DB-01 | Database | EXPAND migration (additive column/table) | NO | Always | NON-BREAKING | AX-K | None — ships inside the current major | Server deploy; no client coordination | None | MUST tolerate (tolerant reader) | MUST keep every existing contract element unchanged | MUST NOT weaken any §34 invariant | Backward compatible | Standard deploy | Existing-major contract test passes unchanged | 5A L1367, 5A L1377 |
| CM-DB-02 | Database | CONTRACT while any served major still reads the element | PROHIBITED | Always | PROHIBITED | AX-K | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Q2 YES | Reviewer MUST reject | Review check and negative test prove absence | 5A L1379 |
| CM-DB-03 | Database | Database-per-major duplication | PROHIBITED | Always | PROHIBITED | AX-K | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | One schema serves all majors | Reviewer MUST reject | Review check and negative test prove absence | 5A L1374 |
| CM-VER-01 | Selection | Header-selected API major | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Competing selector | Reviewer MUST reject | Review check and negative test prove absence | 6J L1201 |
| CM-VER-02 | Selection | Query-parameter API major | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Competing selector | Reviewer MUST reject | Review check and negative test prove absence | 6J L1201 |
| CM-VER-03 | Selection | `Accept-Version` as a competing major mechanism | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Competing selector | Reviewer MUST reject | Review check and negative test prove absence | 6J L1201 |
| CM-VER-04 | Selection | Minor or patch number in a REST URL | PROHIBITED | Always | PROHIBITED | AX-A/AX-B | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | No minor/patch in URL | Reviewer MUST reject | Review check and negative test prove absence | 6A L824 |
| CM-VER-05 | Selection | Microservice-per-major split | PROHIBITED | Always | PROHIBITED | AX-A/AX-B/AX-C | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Modular monolith | Reviewer MUST reject | Review check and negative test prove absence | 3A L442 |
| CM-HLT-01 | Unversioned | Add a new unversioned business route | PROHIBITED | Always | PROHIBITED | none | PROHIBITED — no major, topic or scheme authorizes it; a source amendment is required | Not applicable — MUST NOT be implemented | Not applicable | None | MUST NOT implement | MUST NOT weaken any §34 invariant | Only §6.5 exceptions exist | Reviewer MUST reject | Review check and negative test prove absence | 6A L117 |

### 17.4 Required Category Cross-Reference (51)

| # | Category | Matrix rows | Primary classification |
|---|---|---|---|
| 1 | add optional request field | CM-REQ-01, CM-REQ-02 | CONDITIONAL |
| 2 | add required request field | CM-REQ-03 | BREAKING |
| 3 | remove request field | CM-REQ-04 | BREAKING |
| 4 | rename request field | CM-REQ-05 | BREAKING |
| 5 | request-field type change | CM-REQ-06 | BREAKING |
| 6 | request enum expansion | CM-REQ-07 | CONDITIONAL |
| 7 | request enum removal/restriction | CM-REQ-08 | BREAKING |
| 8 | request validation tightening | CM-REQ-09 | BREAKING |
| 9 | request validation loosening | CM-REQ-10 | CONDITIONAL |
| 10 | add optional response field | CM-RES-01 | NON-BREAKING |
| 11 | remove response field | CM-RES-02 | BREAKING |
| 12 | rename response field | CM-RES-03 | BREAKING |
| 13 | response-field type change | CM-RES-04 | BREAKING |
| 14 | response enum expansion | CM-RES-05 | NON-BREAKING |
| 15 | response enum removal | CM-RES-06, CM-RES-07 | BREAKING |
| 16 | change nullability | CM-NUL-01, CM-NUL-02, CM-NUL-03, CM-NUL-04 | CONDITIONAL |
| 17 | change requiredness | CM-RQD-01, CM-RQD-02, CM-RQD-03, CM-RQD-04 | BREAKING |
| 18 | change HTTP method | CM-RTE-03, CM-RTE-02 | BREAKING |
| 19 | change route | CM-RTE-04 | BREAKING |
| 20 | change route parameter | CM-RTE-05, CM-RTE-06 | BREAKING |
| 21 | change route-parameter semantics | CM-RTE-07 | BREAKING |
| 22 | change query semantics | CM-RTE-09, CM-RTE-10 | BREAKING |
| 23 | pagination default change | CM-PAG-01 | BREAKING |
| 24 | pagination maximum change | CM-PAG-02, CM-PAG-03 | CONDITIONAL |
| 25 | sorting default change | CM-PAG-04 | BREAKING |
| 26 | filtering behavior change | CM-PAG-07, CM-PAG-05, CM-PAG-06 | BREAKING |
| 27 | status-code change | CM-ERR-01, CM-RES-09 | BREAKING |
| 28 | error-code change | CM-ERR-02, CM-ERR-03, CM-ERR-04 | BREAKING |
| 29 | retryability change | CM-ERR-06 | BREAKING |
| 30 | error-detail schema change | CM-ERR-07, CM-ERR-08 | BREAKING |
| 31 | human-readable error-message wording | CM-ERR-09 | NON-BREAKING |
| 32 | authn requirement change | CM-SEC-01, CM-SEC-02, CM-SEC-03 | BREAKING |
| 33 | authz tightening | CM-SEC-04 | BREAKING |
| 34 | authz loosening | CM-SEC-05 | NON-BREAKING (SECURITY REVIEW REQUIRED) |
| 35 | concealment/404 policy changes | CM-SEC-06, CM-SEC-07 | PROHIBITED |
| 36 | idempotency behavior changes | CM-IDM-01, CM-IDM-02, CM-IDM-03, CM-IDM-04, CM-IDM-05 | BREAKING |
| 37 | rate-limit numeric change | CM-RL-01, CM-RL-02, CM-RL-05 | OPERATIONAL |
| 38 | 429 contract change | CM-RL-03 | BREAKING |
| 39 | callback-provider contract change | CM-CB-01, CM-CB-02, CM-CB-03, CM-CB-04 | CONDITIONAL |
| 40 | webhook additive schema change | CM-WH-01 | NON-BREAKING |
| 41 | webhook breaking schema change | CM-WH-02, CM-WH-03, CM-WH-06 | BREAKING |
| 42 | webhook topic version change | CM-WH-05, CM-WH-04 | NON-BREAKING |
| 43 | webhook signature change | CM-WH-07, CM-WH-08, CM-WH-09, CM-WH-10, CM-WH-11, CM-WH-12 | PROHIBITED |
| 44 | WebSocket additive event change | CM-WS-01, CM-WS-03, CM-WS-05 | NON-BREAKING |
| 45 | WebSocket breaking event change | CM-WS-02, CM-WS-04, CM-WS-09 | BREAKING |
| 46 | binary audio contract change | CM-WS-06 | BREAKING |
| 47 | internal API breaking change | CM-INT-02, CM-INT-01, CM-INT-03 | BREAKING |
| 48 | plugin minimum-version behavior | CM-PLG-01, CM-PLG-02, CM-PLG-03 | PROHIBITED |
| 49 | deprecation | CM-LC-01, CM-LC-02, CM-LC-08, CM-LC-11 | LIFECYCLE |
| 50 | sunset | CM-LC-03, CM-LC-02, CM-LC-04, CM-LC-05 | LIFECYCLE |
| 51 | endpoint removal | CM-RTE-08, CM-LC-07, CM-LC-09 | BREAKING |

## 18. Request Compatibility

Request models reject unknown fields (`extra="forbid"`, 6A L577). An instance that predates a field therefore returns 422 for a request carrying it, so any new request field, query parameter, enum value or accepted input is rolled out server-first.

### 18.1 Server-First Rollout (five steps)

| Step | Action | Exit condition |
|---|---|---|
| 1 | Server code that accepts the field deploys first. | Release artifact deployed |
| 2 | A mixed old/new fleet exists temporarily. | Rolling deploy in progress |
| 3 | Clients keep omitting the field. | No client release transmits it |
| 4 | Verify all incompatible old pods are gone. | Every serving instance runs the accepting version |
| 5 | Only then may clients transmit the field. | Client release enabled |

### 18.2 Rollback Implications

| Rollback point | Effect | Rule |
|---|---|---|
| Before step 5 | Safe: no client sends the field | Server MAY roll back freely |
| After step 5 | A rolled-back instance returns 422 to clients sending the field | Server MUST NOT roll back below the accepting version until clients stop sending the field; clients MUST be disabled first |
| Database | EXPAND migrations stay applied on rollback | Rollback MUST NOT run a CONTRACT (§26) |

Request rows: CM-REQ-01..CM-REQ-14, CM-NUL-01, CM-NUL-02, CM-RQD-01, CM-RQD-02 (§17.3).

## 19. Response Compatibility

| Rule ID | Rule | Source |
|---|---|---|
| RS-01 | Clients MUST be tolerant readers: unknown response fields are ignored. | 6A L834 |
| RS-02 | Removing, renaming or retyping a response field is breaking. | 6A L834, 6A L835 |
| RS-03 | Changing what a 200 response means is breaking. | 6A L839 |
| RS-04 | `ETag` on single-resource GETs and `Cache-Control: private, no-store` on tenant-scoped responses are contract elements. | 6A L288, 6A L289 |
| RS-05 | Response rows: CM-RES-01..CM-RES-12, CM-NUL-03, CM-NUL-04, CM-RQD-03, CM-RQD-04. | §17.3 |

## 20. Error Compatibility

| Rule ID | Rule | Source |
|---|---|---|
| ER-01 | Clients branch on `error.code`, never on `message`; `message` wording is NON-BREAKING. | 6A L653 |
| ER-02 | Status, code, `retryable` and `details` schema are contract; changing any of them for an existing condition is breaking. | 6A L653 |
| ER-03 | Changing `error.code` semantics in place is PROHIBITED. | 6A L653 |
| ER-04 | A new error code MUST be registered in the Error Catalog before it is emitted. | AEC L99 |
| ER-05 | Errors MUST NOT expose SQL text or stack traces. | 6A L665 |
| ER-06 | Envelope classes: public (AEC L84), platform-admin (AEC L85), internal (AEC L86), callback outcome (AEC L87). | AEC L84, AEC L85, AEC L86, AEC L87 |
| ER-07 | The sunset error code is not registered (FUTURE REQUIRED WORK, §29); no document, route or test may emit or claim it. | AVS-OD-01, AEC L466 |
| ER-08 | Error rows: CM-ERR-01..CM-ERR-11. | §17.3 |

## 21. Authorization / Security Compatibility

| Rule ID | Rule | Source |
|---|---|---|
| AZ-01 | Authorization tightening is BREAKING. | 6A L838 |
| AZ-02 | Authorization loosening is NON-BREAKING but MUST pass a recorded security review before merge. | 6A L838 |
| AZ-03 | Concealment outcomes (404 versus 403) are contract; revealing existence is PROHIBITED. | AAM L79 |
| AZ-04 | A new major is not permission to weaken any §34 invariant. | §34 |
| AZ-05 | Security rows: CM-SEC-01..CM-SEC-13. | §17.3 |

## 22. Pagination / Filter / Sort / Cursor Compatibility

| Rule ID | Rule | Source |
|---|---|---|
| PG-01 | Cursor pagination is the default for collection endpoints; cursors are opaque. | 6A L387, 6A L397 |
| PG-02 | Default page size (25) is contract; changing it is BREAKING. | 6A L403, 6A L840 |
| PG-03 | Maximum page size (100) is contract; lowering is BREAKING; raising is CONDITIONAL server-first. | 6A L404 |
| PG-04 | Default ordering is contract; changing it is BREAKING. | 6A L405, 6A L406 |
| PG-05 | Filter/sort fields outside the allow-list return 422; adding a field is CONDITIONAL server-first; removing one is BREAKING. | 6A L415, 6A L840 |
| PG-06 | Multi-field sort cap (2) and filter-parameter cap (10) are contract. | 6A L416, 6A L418 |
| PG-07 | Pagination rows: CM-PAG-01..CM-PAG-09. | §17.3 |

## 23. Idempotency / Concurrency Compatibility

| Rule ID | Rule | Source |
|---|---|---|
| ID-01 | The idempotency scope is `(organization_id, principal_id, endpoint, Idempotency-Key)` with a 24-hour window and a SHA-256 request fingerprint; reuse with a different request returns `IDEMPOTENCY_KEY_REUSE_MISMATCH`. | 6A L437, 6A L439, 6A L440, 6A L442, AEC L121 |
| ID-02 | `endpoint` means HTTP method + complete route template including the major-version prefix. | AVS-OD-09, 6A L438 |
| ID-03 | Each major is a separate idempotency namespace. A V1 record is never replayed to a successor major; a retry switched to a successor major is a new operation. | AVS-OD-09 |
| ID-04 | Idempotency keys are NOT portable; a retry sequence must remain on one API major. | AVS-OD-09 |
| ID-05 | Persistent uniqueness invariants remain in force across majors. | AVS-OD-09 |
| ID-06 | Safe methods never require or accept an `Idempotency-Key`. | 6A L445 |
| ID-07 | `PATCH` requires `If-Match`; ETag semantics are contract. | 6A L460, 6A L461, 6A L143 |
| ID-08 | No cache-key or Redis code is changed in this phase. | AVS-OD-09 |

| Example | Method + route template | Namespace |
|---|---|---|
| AMI-6B-001 | `POST /api/v1/auth/register` | V1 |
| HYPOTHETICAL counterpart (NOT CREATED) | `POST /api/v2/auth/register` | separate; no replay from V1 |

## 24. Enum Forward Compatibility

| Rule ID | Rule | Source |
|---|---|---|
| EN-01 | Clients MUST treat an unrecognized response enum value as unknown and MUST NOT fail. | 6A L848 |
| EN-02 | Adding a response enum value is NON-BREAKING; adding a request enum value is CONDITIONAL server-first. | 6A L836, 6A L577 |
| EN-03 | Removing an enum value is BREAKING; changing an existing value's meaning in place is PROHIBITED. | 6A L836 |
| EN-04 | Database enum/reference-data strategy is independent of API enum versioning. | 5A L1301 |

## 25. Multi-Major Runtime Architecture

| Rule ID | Rule | Source |
|---|---|---|
| MR-01 | The runtime is a modular monolith; a successor major is an interface-layer adapter (router and request/response schemas) over the same application services. | HLA L23, 3A L196 |
| MR-02 | Microservice-per-major and database-per-major are PROHIBITED. | 3A L442, 5A L1374 |
| MR-03 | The URL path is the only major selector; no version dispatcher is implemented in this phase. | 6J L1201 |
| MR-04 | Authentication, tenant context (RLS), authorization, quota and audit middleware are shared by every major and MUST NOT be forked per major in a way that weakens §34. | 6A L576 |
| MR-05 | No successor router, model or document exists; this section documents future introduction only. | §1.3 |

## 26. Database Expand / Contract

| Phase | Rule | Source |
|---|---|---|
| EXPAND | Add the new column/table; backward compatible; non-destructive; no data backfill inside the migration; the migration runs before the new application version deploys. | 5A L1377, 5A L1367, 5A L1369, 5A L1370, 5A L1392 |
| MIGRATE | Deploy the application that stops reading the old element; every served major keeps working. | 5A L1378 |
| CONTRACT | Drop the old element only after all application instances, for every served major, no longer reference it; this is §27 step 17. | 5A L1379 |
| Forbidden in place | Renaming a column; breaking type changes; NOT NULL without a default. | 5A L1395, 5A L1396, 5A L1397 |
| Large tables | Follow the large-table migration rules. | 5A L1383 |
| Zero downtime | Every step follows the zero-downtime deployment rule. | 5A L1390 |

No migration is added or changed by this document; the baseline head remains `112_5H5`.

## 27. Deployment / Rollout Ordering

### 27.1 AX-A Successor-Major Workflow (17 steps)

§27.1 applies to AX-A (public REST including platform-admin) only. AX-B follows §27.3, AX-C follows §27.4, and AX-E, AX-F, AX-G and AX-K follow §27.5; the §28/§29 lifecycle applies to none of them.

| Step | Action |
|---|---|
| 1 | propose change |
| 2 | compatibility classification |
| 3 | owner/security decision where required |
| 4 | decide new major |
| 5 | DB EXPAND if necessary |
| 6 | implement version-specific adapter/schema |
| 7 | contract tests for old + new major |
| 8 | deploy server support for both |
| 9 | publish migration guide |
| 10 | announce deprecation of old major |
| 11 | observe adoption |
| 12 | migrate clients |
| 13 | emit `Sunset` during compatibility period and at sunset |
| 14 | reach sunset |
| 15 | old major returns 410 Gone + registered sunset error envelope + `Link` + `Sunset` per the final sunset contract |
| 16 | remove old interface adapter only after sunset/removal gates |
| 17 | DB CONTRACT later |

Do not collapse release and retirement.

### 27.2 Per-Axis Ordering

| Axis / change | Order | Source |
|---|---|---|
| AX-A/AX-B/AX-C additive request input | §18 server-first | 6A L577 |
| AX-A breaking | §27.1 steps 1–17; step 10 is BLOCKED until the AEC registers the sunset error contract | AVS-OD-01 |
| AX-B breaking | §27.3: producer serves the successor; both internal majors coexist; callers migrate; every authorized caller confirmed; old internal major removed in a coordinated deployment | AVS-OD-04 |
| AX-C breaking | §27.4: successor WebSocket major served alongside `/ws/v1`; clients MAY migrate; predecessor deprecation and removal BLOCKED (WSP-13) | AVS-OD-11 |
| AX-E breaking | §27.5: publish successor topic; subscribers opt in; predecessor keeps delivering the predecessor schema; removal PROHIBITED | 6J L1634 |
| AX-F successor | §27.5: in-place change PROHIBITED; a successor header is PROHIBITED pending owning-source amendment (future compatibility note: additive/non-breaking for v1-only verifiers once authorized); legacy retirement PROHIBITED pending a separately governed decision | AVS-OD-08 |
| AX-G change | §27.5: register successor; accept old and new; verify both; confirm provider cutover; remove old | AVS-OD-05 |
| AX-K | Migration before application deploy; CONTRACT last | 5A L1392 |

### 27.3 AX-B Internal Successor-Major Sequence (AVS-OD-04)

| Order | Action | Source |
|---|---|---|
| 1 | Producer supports the successor internal major (HYPOTHETICAL `/api/internal/v{n+1}`, NOT CREATED) on every instance. | AVS-OD-04, 5A L1374 |
| 2 | Both internal majors coexist; `service_id` authentication, allowlist and fail-closed behavior are unchanged on both. | AVS-OD-04, AAM L371, AAM L1247 |
| 3 | Identify every authorized `service_id` caller from the allowlist. | AVS-OD-04, AAM L371 |
| 4 | Each caller migrates to the successor. | AVS-OD-04 |
| 5 | Confirm each caller's deployment against the successor. | AVS-OD-04 |
| 6 | Remove the old internal major in a coordinated deployment only after every caller is confirmed; expand/contract applies. | AVS-OD-04, 5A L1379 |

AX-B has no six-month floor, no `Sunset` header, no public OpenAPI deprecation, no 410 and no published retirement date (§28 DL-07).

### 27.4 AX-C WebSocket Successor Sequence (retirement BLOCKED)

| Order | Action | Source |
|---|---|---|
| 1 | A breaking WebSocket change (§10, §11 ES-N1..ES-N5) is delivered only on a successor `/ws/v{major}` (HYPOTHETICAL, NOT CREATED). | AVS-OD-11 |
| 2 | The successor MAY be served alongside `/ws/v1`; no dual emit and no connection-time negotiation. | AVS-OD-11 |
| 3 | Event `version` advancement within a WebSocket major is additive only. | AVS-OD-11, 6A L742 |
| 4 | Clients MAY migrate; no deadline exists. | AVS-OD-11 |
| 5 | Deprecation or removal of `/ws/v1` or any WebSocket major is BLOCKED: the mechanism is FUTURE REQUIRED WORK (§10 WSP-13, CM-LC-11). | AVS-OD-11, 6A L844 |

### 27.5 AX-E / AX-F / AX-G / AX-K Sequences

| Axis | Order | Action | Source |
|---|---|---|---|
| AX-E | 1 | Publish the successor topic `X.vN` (HYPOTHETICAL, NOT CREATED) alongside `X`. | 4F L893 |
| AX-E | 2 | Subscribers opt in; migration is optional and has no deadline. | AVS-OD-07 |
| AX-E | 3 | The predecessor topic keeps delivering the predecessor schema; it is never removed or repurposed (removal PROHIBITED). | 6J L1634 |
| AX-F | 1 | In-place change of the `v1=` algorithm, syntax or header semantics is PROHIBITED, even with a new REST major. | AVS-OD-08, 6J L805 |
| AX-F | 2 | A successor signature header is PROHIBITED pending owning-source amendment. Future compatibility note: once the owning source authorizes it, a successor in a separate additional header alongside unchanged `v1=` is additive/non-breaking for v1-only verifiers. | 6J L1009, 4F L863, AVS-OD-08 |
| AX-F | 3 | Legacy-header retirement is PROHIBITED pending a separately governed decision (FUTURE REQUIRED WORK). | AVS-OD-08 |
| AX-G | 1 | Register/configure the successor with the provider. | AVS-OD-05 |
| AX-G | 2 | Accept both old and successor. | AVS-OD-05 |
| AX-G | 3 | Verify signature/OAuth state on both. | AVS-OD-05, 6A L776 |
| AX-G | 4 | Confirm provider cutover. | AVS-OD-05 |
| AX-G | 5 | Remove the old only after provider cutover is confirmed; independent of any REST-major lifecycle. | AVS-OD-05 |
| AX-K | 1 | EXPAND migration runs before the application deploy. | 5A L1392 |
| AX-K | 2 | CONTRACT runs last, only after no served major reads the element. | 5A L1379 |

## 28. Deprecation Lifecycle

V1 is not deprecated. Every current major (`/api/v1`, `/api/internal/v1`, `/ws/v1`) is served and no retirement is planned; no sunset date exists.

Scope: this lifecycle governs AX-A (public REST including platform-admin) only. AX-B retires by the AVS-OD-04 caller-confirmed sequence (§27.3); AX-C deprecation and removal are future-gated (§10 WSP-13, CM-LC-11); AX-E topics are never removed; AX-F legacy retirement is PROHIBITED pending a separately governed decision; AX-G follows AVS-OD-05 only (§27.5).

| State | Entry condition | Signals | Allowed traffic | Support | Migration guide | Minimum duration | Removal prerequisites | AEC prerequisite (AVS-OD-01) | Post-sunset behavior |
|---|---|---|---|---|---|---|---|---|---|
| ACTIVE | Major released GA | None | All | Full: features, fixes, security | Not required | Unbounded | Not removable | Not applicable | Not applicable |
| SUCCESSOR_AVAILABLE/DEPRECATED | Successor GA and deprecation formally announced; sunset date published at announcement | `deprecated: true` on every operation of the major; `Sunset` on every response from the major (6A L844) | All; the major stays fully functional | Security fixes MUST be delivered inside the supported major | MUST be published (§30) before the announcement | Counts toward the six-month floor | Not removable | MUST be satisfied before entry | Not applicable |
| SUNSET_SCHEDULED | Six-month floor elapsed since announcement; published sunset date not yet reached | Same as DEPRECATED | All | Security fixes MUST be delivered inside the supported major | Published | Until the published sunset date; MAY be extended, MUST NOT be shortened | §29 gates evaluated | Satisfied | Not applicable |
| SUNSET | Published sunset date reached and every §29 gate passes | 410 Gone + the registered sunset error envelope/code + `Link` to the migration guide + the `Sunset` header (6A L846, AVS-OD-01); OpenAPI operations of the retired major remain `deprecated: true` as applicable | None served; every request receives 410 | None | Remains published | Terminal | Adapter removal after sunset (§27 step 16); DB CONTRACT later (step 17) | Satisfied | 410 Gone + registered sunset error envelope/code + `Link` + `Sunset`; callbacks excluded (AVS-OD-05) |

| Rule ID | Rule | Source |
|---|---|---|
| DL-01 | The compatibility period is a binding minimum of six months, running from formal deprecation announcement after the successor reaches GA. | AVS-OD-02, 6A L845 |
| DL-02 | The sunset date MUST be published when deprecation begins. | AVS-OD-02 |
| DL-03 | The period MAY be lengthened; it MUST NOT be shortened as a routine release decision. | AVS-OD-02 |
| DL-04 | No partner-specific compatibility period is defined. | AVS-OD-02 |
| DL-05 | No `Deprecation` header is mandatory; the deprecation signal set is `deprecated: true` + `Sunset`, and the sunset signal set is 410 Gone + the registered sunset error envelope/code + `Link` to the migration guide + the `Sunset` header (SN-01). | 6A L844, AVS-OD-01 |
| DL-06 | No public major deprecation/sunset may be announced until the Error Catalog has first been amended to register the sunset error contract. | AVS-OD-01 |
| DL-07 | AX-B is outside this lifecycle: no six-month floor, no `Sunset`, no public OpenAPI deprecation, no 410 and no published retirement date; removal follows §27.3. | AVS-OD-04 |
| DL-08 | AX-C is outside this lifecycle: `deprecated: true`, the `Sunset` header and 410 + the REST error envelope are not WebSocket mechanisms, and the frozen sources define none. The WebSocket deprecation/removal mechanism is FUTURE REQUIRED WORK; no WebSocket major deprecation or removal may be announced or executed until it is specified (§10 WSP-13, CM-LC-11, §42 M-07). | AVS-OD-11, 6A L844 |
| DL-09 | AX-E, AX-F and AX-G are outside this lifecycle and follow §27.5 only. | 6J L1634, AVS-OD-08, AVS-OD-05 |

## 29. Sunset Behavior

Gate (AVS-OD-01): no public major deprecation/sunset may be announced until the Error Catalog has first been amended to register the sunset error contract.

| Rule ID | Rule | Source |
|---|---|---|
| SN-01 | At sunset, once the AEC prerequisite is satisfied, the retired public major returns 410 Gone with the registered sunset error envelope/code, a `Link` header pointing to the migration guide and the `Sunset` header (AVS-OD-01 Option C). OpenAPI operations of the retired major remain `deprecated: true` as applicable. Callbacks are excluded (SN-04). | 6A L846, AVS-OD-01 |
| SN-02 | The AEC currently lists 410 for OAuth state expiry only; 410 on disallowed DELETE is a resource-level outcome. Neither is the sunset contract. | AEC L466, 6A L169, 6J L481 |
| SN-03 | The AEC count is not altered by this document (total 421; active 132). | AEC L99 |
| SN-04 | Callbacks are not sunset with a public major (§14). | AVS-OD-05 |
| SN-05 | This section applies to AX-A only. An internal major has no 410 and no sunset; it is removed after caller confirmation (§27.3). WebSocket retirement is BLOCKED (WSP-13). | AVS-OD-04, AVS-OD-11 |
| SN-06 | AX-A removal prerequisites: six-month floor elapsed, published date reached, §33 adoption observed, migration-completion signal, callback routes kept active independently per AVS-OD-05, AEC sunset contract registered. | AVS-OD-01, AVS-OD-02, AVS-OD-05 |
| SN-07 | A contracted API MUST NOT be removed because usage is low, the frontend stopped using it, it looks undocumented elsewhere, a provider no longer calls it, or the DB no longer seems to require it. | 6A L846 |

| Item | Code | HTTP | Envelope | retryable | Status |
|---|---|---|---|---|---|
| FUTURE REQUIRED WORK — sunset error contract | `API_VERSION_SUNSET` | 410 | public REST error envelope | `false` | not registered in the AEC; MUST be registered before any deprecation/sunset announcement |

## 30. Client Migration Guide Contract

A migration guide MUST exist before a deprecation is announced and MUST contain every field below. No actual guide is created in this phase.

| # | Required field |
|---|---|
| 1 | breaking-change inventory |
| 2 | endpoint old→new mappings |
| 3 | request changes |
| 4 | response changes |
| 5 | status changes |
| 6 | error code/details changes |
| 7 | authz changes |
| 8 | enum changes |
| 9 | pagination/filter/sort changes |
| 10 | idempotency implications |
| 11 | WS changes |
| 12 | webhook topic/schema/signature changes |
| 13 | behavior/default changes |
| 14 | examples |
| 15 | cutover guidance |
| 16 | sunset date |
| 17 | rollback guidance where supported |

## 31. OpenAPI / Documentation Strategy

| Rule ID | Rule | Source |
|---|---|---|
| OA-01 | OpenAPI is generated by FastAPI only; there is no hand-maintained OpenAPI file. | 6A L860 |
| OA-02 | No OpenAPI snapshot is committed; CI MAY generate ephemeral OpenAPI per major. | 6A L860 |
| OA-03 | Generation MUST preserve `deprecated: true` on deprecated operations. | 6A L844 |
| OA-04 | Every non-internal route carries the required `x-*` fields, checked by CI lint. | 6A L870 |
| OA-05 | OpenAPI-only diffing cannot model the AAM, cross-tenant concealment, break-glass, AEC behavior, webhook topics, WebSocket contracts, idempotency semantics, or all business behavior. | AAM L71 |
| OA-06 | No successor OpenAPI document is created in this phase. | §1.3 |

## 32. Contract-Diff / CI Strategy

A future contract-diff check MUST take as inputs: candidate and current generated OpenAPI, AMI, AAM, AEC, WebSocket contracts, webhook topic/signature contracts, and this strategy. It MUST detect a breaking change inside an existing major and either block it or require the §27.1 workflow. It is not implemented in this phase.

| Check | Detects | Matrix rows |
|---|---|---|
| Schema diff | Field removal/rename/type/nullability/requiredness | CM-REQ-*, CM-RES-*, CM-NUL-*, CM-RQD-* |
| Route diff | Method/path/parameter changes against AMI | CM-RTE-* |
| Authorization diff | AAM grant tightening/loosening | CM-SEC-* |
| Error diff | AEC status/code/retryable changes | CM-ERR-* |
| Topic/signature diff | Topic shape and signature header changes | CM-WH-* |
| WebSocket diff | Event/frame/close-code changes | CM-WS-* |

## 33. Version Observability

| # | Metric |
|---|---|
| 1 | request count per major |
| 2 | error rate per major |
| 3 | deprecated-major traffic |
| 4 | active consumers/tenants per major where safely measurable |
| 5 | API-key major usage where safe |
| 6 | WS connections per protocol major |
| 7 | webhook consumer/topic version |
| 8 | sunset traffic still arriving |
| 9 | a migration-completion signal |

Global dashboards MUST NOT carry tenant-sensitive identity. Observability is not an authorization bypass.

## 34. Security Invariants

Versioning MUST NEVER be used to bypass any invariant below. A new major is not permission to weaken them. Loosening keeps the mandatory security review; tightening is breaking.

| SI ID | Invariant | Source |
|---|---|---|
| SI-01 | authentication | 6A L716 |
| SI-02 | authorization | 6A L838 |
| SI-03 | tenant isolation | 6A L576 |
| SI-04 | row-level security | 6A L576 |
| SI-05 | sensitive-media permissions | AAM L662 |
| SI-06 | compliance enforcement | AAM L79 |
| SI-07 | suppression/DNC enforcement | AAM L79 |
| SI-08 | billing enforcement | AEC L171 |
| SI-09 | quota enforcement | AEC L171 |
| SI-10 | webhook signature verification | 6J L823 |
| SI-11 | callback verification | 6A L776 |
| SI-12 | purpose-bound access controls | AAM L662 |
| SI-13 | platform-admin controls | AAM L587 |
| SI-14 | internal-service authentication | AAM L371 |
| SI-15 | audit requirements | AAM L79 |

## 35. Anti-Patterns

| AN ID | Anti-pattern | Status | Governing rule |
|---|---|---|---|
| AN-01 | header-selected API major replacing URL-path major | PROHIBITED | CM-VER-01 |
| AN-02 | query-param API major | PROHIBITED | CM-VER-02 |
| AN-03 | Accept-Version as competing major mechanism | PROHIBITED | CM-VER-03 |
| AN-04 | minor/patch in REST URL | PROHIBITED | CM-VER-04 |
| AN-05 | silent breaking changes inside `/api/v1` | PROHIBITED | PR-04 |
| AN-06 | silent repurposing of existing webhook topic | PROHIBITED | CM-WH-03 |
| AN-07 | conflating signature `v1=` with REST `/api/v1` | PROHIBITED | SG-02 |
| AN-08 | conflating webhook version with REST major | PROHIBITED | WHR-03 |
| AN-09 | conflating Plugin SemVer with REST major | PROHIBITED | AX-R03 |
| AN-10 | conflating Agent/Workflow/Prompt/Plan versions with API major | PROHIBITED | §16 |
| AN-11 | conflating Alembic revision with API major | PROHIBITED | §16 |
| AN-12 | database-per-major duplication | PROHIBITED | CM-DB-03 |
| AN-13 | microservice-per-major split | PROHIBITED | CM-VER-05 |
| AN-14 | destructive DB contraction while old major lives | PROHIBITED | CM-DB-02 |
| AN-15 | client-first rollout of new strict request field | PROHIBITED | §18 |
| AN-16 | instant V1 removal when V2 launches | PROHIBITED | CM-LC-07 |
| AN-17 | assuming authorization loosening is automatically security-safe | PROHIBITED | CM-SEC-05 |
| AN-18 | using message text as machine error contract | PROHIBITED | ER-01 |
| AN-19 | changing error.code semantics in place | PROHIBITED | CM-ERR-03 |
| AN-20 | changing existing enum semantics in place | PROHIBITED | CM-RES-07 |
| AN-21 | repurposing webhook topic | PROHIBITED | CM-WH-03 |
| AN-22 | hand-maintained OpenAPI as second source of truth | PROHIBITED | OA-01 |
| AN-23 | creating V2 in this strategy phase | PROHIBITED | §1.3 |

## 36. Worked Compatibility Examples

| # | Proposed change | Matrix row | Classification | Result | Governing rule |
|---|---|---|---|---|---|
| 1 | Add optional request field under `extra="forbid"` | CM-REQ-01 | CONDITIONAL | CONDITIONAL — SERVER-FIRST | 6A L577, 6A L837 |
| 2 | Add required request field | CM-REQ-03 | BREAKING | BREAKING | 6A L837 |
| 3 | Add a response enum value | CM-RES-05 | NON-BREAKING | NON-BREAKING (TOLERANT READER) | 6A L836, 6A L848 |
| 4 | Remove a response field | CM-RES-02 | BREAKING | BREAKING | 6A L834 |
| 5 | Tighten authorization on an endpoint | CM-SEC-04 | BREAKING | BREAKING | 6A L838 |
| 6 | Loosen authorization on an endpoint | CM-SEC-05 | NON-BREAKING (SECURITY REVIEW REQUIRED) | NON-BREAKING (SECURITY REVIEW REQUIRED) | 6A L838 |
| 7 | Change default page size | CM-PAG-01 | BREAKING | BREAKING | 6A L840, 6A L403 |
| 8 | Lower an ingress rate limit | CM-RL-01 | OPERATIONAL | OPERATIONAL | 6A L535, 6A L537, 6A L542, 6K L1923, AVS-OD-10 |
| 9 | Change the 429 response shape | CM-RL-03 | BREAKING | BREAKING | 6A L544, AEC L172, AVS-OD-10 |
| 10 | Incompatible webhook payload change | CM-WH-02 | BREAKING | SUCCESSOR TOPIC REQUIRED | 4F L893, AVS-OD-07 |
| 11 | Change the signature algorithm in place | CM-WH-07 | PROHIBITED | IN-PLACE CHANGE PROHIBITED | AVS-OD-08, 6J L805, 6J L1009, 4F L863 |
| 12 | Reuse a V1 idempotency key on a HYPOTHETICAL successor major (NOT CREATED) | CM-IDM-03 | PROHIBITED | NO REPLAY — NEW OPERATION | AVS-OD-09, 6A L437, 6A L438 |
| 13 | Breaking `/ws/v1` event change | CM-WS-02 | BREAKING | NEW WS MAJOR REQUIRED | AVS-OD-11 |
| 14 | Provider callback on old path during public-major migration | CM-CB-03 | PROHIBITED | OLD CALLBACK STAYS ACTIVE UNTIL PROVIDER MIGRATION | AVS-OD-05 |
| 15 | Sunset announcement without the AEC sunset code | CM-LC-02 | PROHIBITED | BLOCKED | AVS-OD-01, AEC L466 |

## 37. Conflict / Reconciliation Ledger

| LG ID | Source A | Source B / gap | Reconciliation | Resolved by | Frozen-source amendment |
|---|---|---|---|---|---|
| LG-01 | 6A L846 (410 + `Link` at sunset) | AEC L466 (410 registered for OAuth state only) | Sunset returns 410 + registered sunset error envelope + `Link` + `Sunset`; the sunset contract is FUTURE REQUIRED WORK; announcement gated on AEC amendment | AVS-OD-01 | None |
| LG-02 | 6A L169 (410 on disallowed DELETE) | Sunset 410 | Distinct resource-level outcome; not the sunset contract | §29 SN-02 | None |
| LG-03 | 6A L845 (six months, indicative default) | Binding floor needed | Six months is a binding minimum | AVS-OD-02 | None |
| LG-04 | 6A L115, 6A L116, 6A L118 | Axis coupling unstated | Axes independent | AVS-OD-03 | None |
| LG-05 | 6A L116 | Internal lifecycle unstated | Producer-first; caller-confirmed removal; no `Sunset` | AVS-OD-04 | None |
| LG-06 | 6A L776, AMI L231 | Callbacks under `/api/v1` vs public sunset | Callbacks independent of any REST-major lifecycle; AVS-OD-05 sequence | AVS-OD-05 | None |
| LG-07 | 6J L1201 (current API version) | SemVer-shaped `min_platform_version` vs URL-path major | Only MAJOR evaluated against served, non-sunset majors | AVS-OD-06 | None |
| LG-08 | 4F L893 (versioned topics) | Topic retirement unstated | Successor topics side by side | AVS-OD-07 | None |
| LG-09 | 6J L1634 (never removed or repurposed) | AVS-OD-07 retirement floor | Stronger source prevails: topic removal PROHIBITED; predecessor subscribers keep the predecessor schema; migration optional with no deadline | AVS-OD-07 (stronger-source clause) | None |
| LG-10 | 6J L805 (`v1=`), 6J L2106 | Signature evolution unstated | In-place change PROHIBITED even with a new REST major; a successor header is PROHIBITED pending owning-source amendment (future compatibility note: additive/non-breaking for v1-only verifiers once authorized); legacy retirement PROHIBITED pending a separately governed decision | AVS-OD-08 | None |
| LG-11 | 6J L1009 (one algorithm) | Successor signature scheme | A successor scheme is PROHIBITED pending owning-source amendment; if later authorized it applies platform-wide; none now; webhook and plugin-callout canonical inputs stay distinct (6J L2539) | AVS-OD-08 | None |
| LG-12 | 6A L437 (`endpoint`) | Major in the endpoint key unstated | Endpoint includes the major prefix; no cross-major replay | AVS-OD-09 | None |
| LG-13 | 6A L535, 6A L544, 6K L2035 | Numeric vs contract change | Numeric request-rate/abuse thresholds OPERATIONAL and outside the §17.1 contract-diff test (§17.1 scope); quota values governed by 6K/6M and not API versions; 429 contract BREAKING; pricing, billing calculation, admission, authority and enforcement excluded (CM-RL-05) | AVS-OD-10 | None |
| LG-14 | 6A L742, 6A L823 (event version independent) | Breaking event change path | Breaking requires new WebSocket major; event `version` compatible only | AVS-OD-11 | None |
| LG-15 | 6A L837, 6A L840 (non-breaking additions) | 6A L577 (`extra="forbid"`) | Classified CONDITIONAL with server-first order | §18 | None |
| LG-16 | SRS L290 (`/v1/...`) | 6A L115 (`/api/v1`) | 6A form is authoritative; SRS states the versioning requirement only | §2 precedence | None |
| LG-17 | 6A L404 (maximum page size) | Over-maximum behavior unstated | Raising treated CONDITIONAL server-first; lowering BREAKING | §22 PG-03 | None |
| LG-18 | 6A L844 (REST deprecation signals) | WebSocket carrier for deprecation/removal undefined | WebSocket deprecation/removal FUTURE REQUIRED WORK; BLOCKED until specified | §10 WSP-13, CM-LC-11 | None |

## 38. Owner Decisions

| Decision ID | Chosen option | Status | Governing rule | Rationale | Compatibility impact | Security impact | Operational impact | Source gap resolved | Frozen-source impact |
|---|---|---|---|---|---|---|---|---|---|
| AVS-OD-01 | Option C | RESOLVED | At AX-A sunset the retired public major returns 410 Gone + the registered sunset error envelope/code + `Link` + `Sunset` (§28 SUNSET, SN-01, CM-LC-03); the sunset error code is not registered now (FUTURE REQUIRED WORK); no public major deprecation/sunset may be announced until the Error Catalog has first been amended to register the sunset error contract | Avoids emitting an unregistered code | Blocks deprecation until AEC amendment | No code claimed or emitted | AEC change precedes any announcement | Sunset error contract absent from AEC | None (0 amendments) |
| AVS-OD-02 | Option A | RESOLVED | Six months is a binding minimum after successor GA and formal announcement; sunset date published at deprecation; MAY lengthen, MUST NOT shorten routinely; security fixes delivered inside the supported major; no partner-specific periods | Predictable client planning | Floor on every public major retirement | Security fixes continue during the period | Two majors run for at least six months | 6A L845 indicative default | None (0 amendments) |
| AVS-OD-03 | Option A | RESOLVED | `/api/v{major}`, `/api/internal/v{major}` and `/ws/v{major}` advance independently; no successor route is created | Limits blast radius | One axis moves at a time | None | Independent release trains | Axis coupling unstated | None (0 amendments) |
| AVS-OD-04 | Option A | RESOLVED | Internal API: no public six-month lifecycle and no `Sunset`; producer ships compatibility first; old internal major stays until every authorized caller is confirmed on the successor; deployment-coordinated removal; allowlist, internal auth and fail-closed unchanged | Callers are platform-owned | Removal gated on caller confirmation | Allowlist and fail-closed preserved | Coordinated deploys | Internal lifecycle unstated | None (0 amendments) |
| AVS-OD-05 | Option A | RESOLVED | Public-major sunset does not retire callbacks; register successor → accept both → verify both → confirm provider cutover → remove old; provider-native contracts distinct; no path renames | Providers migrate on their schedule | Callbacks never 410 before provider migration | Verification on both paths | Provider coordination | Callbacks under `/api/v1` vs sunset | None (0 amendments) |
| AVS-OD-06 | Option A | RESOLVED | `min_platform_version` SemVer-shaped; only MAJOR evaluated; compatible when at least one served, non-sunset public major satisfies MAJOR; no 6J amendment; no invented platform SemVer | Uses the only formal version signal | `1.0.0` compatible while V1 served | None | Install/upgrade gate only | 6J L1201 current-version ambiguity | None (0 amendments) |
| AVS-OD-07 | Option A | RESOLVED | Bare topic = schema version 1; `X.vN` = version N; envelope `version` = schema version = `X-Platform-Webhook-Version`; additive needs no version; breaking needs successor topic; side by side; the owner-decision retirement floor never applies because the stronger source requirement 6J L1634 prevails: topic removal PROHIBITED; predecessor subscribers keep the predecessor schema; no subscription/DB change | Subscribers never silently broken | Old topics keep delivering | None | Parallel topic delivery | Topic retirement unstated | None (0 amendments) |
| AVS-OD-08 | Option A | RESOLVED | `v1=` in `X-Platform-Signature` stable; in-place change of its algorithm, syntax or header semantics PROHIBITED even with a new REST major; no multiple incompatible values; a successor scheme is PROHIBITED pending owning-source amendment; future compatibility note: if later authorized, a successor carried in a separate additional header while `v1=` continues unchanged is additive/non-breaking for v1-only verifiers; legacy retirement PROHIBITED pending a separately governed decision; no DB field, migration, selector or successor scheme now | Existing verifiers unaffected | No successor now; additive for v1-only verifiers once the owning source authorizes it | Verification never weakened | No dual emission before owning-source amendment | Signature evolution unstated | None (0 amendments) |
| AVS-OD-09 | Option A | RESOLVED | Endpoint = HTTP method + complete route template including the major-version prefix; majors are separate namespaces; NOT portable; a retry sequence must remain on one API major; persistent uniqueness invariants remain; no Redis code | Prevents cross-major duplicate or mismatched replay | Retry switched to a successor is a new operation | Uniqueness invariants preserved | None | Major in idempotency key unstated | None (0 amendments) |
| AVS-OD-10 | Option A | RESOLVED | A numeric request-rate or abuse-protection threshold change with an unchanged signalling contract is OPERATIONAL and outside the §17.1 contract-diff test; commercial/usage/capacity quota values (plan, agreement and per-organization overrides, including `ACTIVE_AGENTS` and `CONCURRENT_CALLS`) are governed by 6K and 6M and are not API versions; changing the 429 contract (429, `RATE_LIMIT_EXCEEDED`, `Retry-After`, `X-RateLimit-*` semantics) is BREAKING; AVS-OD-10 does not cover pricing, billing calculation, admission, authority, enforcement, wire-shape or error-contract changes, which are classified separately (CM-RL-05); never weaken authz, quota accounting, billing, abuse controls or tenant isolation | Operators tune numbers safely | Signalling contract stable | Abuse controls preserved | Numeric tuning without version action | Numeric vs contract unstated | None (0 amendments) |
| AVS-OD-11 | Option A — owner override of the initially recommended Option B | RESOLVED | A breaking WebSocket event-schema change requires a new WebSocket major; event `version` advancement within `/ws/v1` is compatible/additive only; no dual-emit; no negotiation; binary audio unchanged; no successor WebSocket route created; the WebSocket deprecation/removal mechanism is FUTURE REQUIRED WORK and no WebSocket deprecation or removal may be announced or executed until it is specified | One selector (URL path) for WebSocket contracts | Breaking event changes need a new WebSocket major | Handshake auth unchanged | Parallel WebSocket majors when introduced | Event version vs URL major interplay | None (0 amendments) |

### 38.1 Reconciliation Items

| Item | Resolved by |
|---|---|
| AVS-R-01 sunset error contract | AVS-OD-01 |
| AVS-R-02 compatibility period | AVS-OD-02 |
| AVS-R-03 axis coupling | AVS-OD-03 |
| AVS-R-04 plugin minimum version | AVS-OD-06 |
| AVS-R-05 webhook topic versions | AVS-OD-07 |
| AVS-R-06 idempotency across majors | AVS-OD-09 |
| AVS-R-07 callbacks during sunset | AVS-OD-05 |
| AVS-R-08 AEC 410 scope | AVS-OD-01 |
| AVS-R-09 forbid rollout / tolerant reader | §18, §19 |
| AVS-R-10 rate-limit changes | AVS-OD-10 |
| AVS-R-11 signature evolution | AVS-OD-08 |
| AVS-R-12 internal lifecycle | AVS-OD-04 |

## 39. Route / Surface Coverage

| Surface | Count | Profile(s) | Section |
|---|---|---|---|
| Public REST | 318 | PUBLIC_REST_V1 | §7 |
| Platform-admin REST | 42 | PLATFORM_ADMIN_REST_V1 | §8 |
| Internal REST | 4 | INTERNAL_REST_V1 | §9 |
| Provider/OAuth callbacks | 5 | CALLBACK_BROWSER_OAUTH, CALLBACK_VOICE_PROVIDER, CALLBACK_INTEGRATION_PROVIDER, CALLBACK_PAYMENT_PROVIDER | §14 |
| WebSocket | 4 | WS_MEDIA_V1, WS_EVENTS_V1 | §10, §11 |
| Webhook/event topics | 19 | AX-E | §12, §13 |
| Plugin | n/a | AX-H, AX-I | §15 |
| Idempotency/version | n/a | AX-A/AX-B | §23 |
| Pagination/version | n/a | AX-A/AX-B | §22 |
| Errors | n/a | AEC classes A–D | §20 |
| Auth/authz | n/a | AAM | §21, §34 |
| Rate limit | n/a | AVS-OD-10 | §17.3 CM-RL-* |
| Unversioned exceptions | 3 | §6.5 | §6.5 |
| Total REST/internal/callback routes | 369 | all classified | §6.2 |

## 40. Validation / Reproducibility

The document was produced by a deterministic generator and checked by an independent validator and a mutation harness, all kept outside the repository. Three generation passes MUST produce byte-identical output before installation.

| Check | Method |
|---|---|
| Source hashes | SHA-256 of every hash-gated source equals §0.2 |
| Anchors | Every §0.3 anchor is a substring of its source line |
| Citations | Every `<Key> L<line>` citation resolves to a §0.3 row |
| Route inventory | §6.2 rows equal AMI rows (ID, method, path, surface); AAM IDs identical |
| Profiles | Profile derived from surface and path prefix; counts 318/42/4/5 |
| WebSocket | §6.3 rows equal AMI WebSocket rows |
| Matrix | Unique CM IDs; Breaking? consistent with classification; CONDITIONAL rows carry NO/YES conditions |
| Axis semantics | REST lifecycle terms (`Sunset`, 410, `deprecated: true`, §28, §29) appear only on AX-A or inside an explicit `AX-A:` branch; AX-B, AX-C, AX-D, AX-E, AX-F and AX-G rows state their own retirement path |
| Scenarios | 15 scenarios map to rows with expected class and result token |
| Headings | Exactly `## 0.` to `## 42.` in order |
| Wording | Successor paths only on HYPOTHETICAL/NOT CREATED/MUST NOT lines; no minor/patch URL; sunset code only as FUTURE REQUIRED WORK |
| AX-A SUNSET signals | §3 Sunset, PR-09, §27.1 step 15, §28 SUNSET, SN-01, CM-LC-03 and AVS-OD-01 all state 410 Gone + registered sunset error envelope/code + `Link` + `Sunset` |
| Source-amendment authorization | No NON-BREAKING, NON-BREAKING (SECURITY REVIEW REQUIRED) or OPERATIONAL row is gated on a frozen-source amendment; CM-WH-12 is PROHIBITED pending owning-source amendment and not BREAKING |
| OD-10 contract vs configuration | §17.1 scope sentence present; CM-RL-01/02 OPERATIONAL, CM-RL-03 BREAKING, CM-RL-04/05 PROHIBITED |
| Mutation harness | Every seeded defect yields a validator FAIL; the unmutated control PASSes |

| Migration integrity | Value |
|---|---|
| SQL migration files | 112 |
| Alembic revision files | 112 |
| Root revision | `001_5B` |
| Head revision(s) | `112_5H5` (sole head) |
| Linear chain | yes |
| Migration `113` present | no |

## 41. Freeze Gates

| Gate | Check | Evidence | Result |
|---|---|---|---|
| G-01 | All 11 owner decisions recorded exactly | §38 | PASS |
| G-02 | AVS-OD-11 is Option A | §38 | PASS |
| G-03 | No unresolved owner decision | §38 | PASS |
| G-04 | All surfaces accounted for | §39 | PASS |
| G-05 | Every route classified | §6.2 | PASS |
| G-06 | All WebSocket routes accounted for | §6.3 | PASS |
| G-07 | Callback behavior explicit | §14, §27.5 | PASS |
| G-08 | Internal lifecycle explicit | §9, §27.3 | PASS |
| G-09 | Webhook topic/version/header relationship explicit | §12 | PASS |
| G-10 | Signature evolution explicit | §13 | PASS |
| G-11 | Idempotency-major isolation explicit | §23 | PASS |
| G-12 | Six-month floor explicit | §28 | PASS |
| G-13 | AEC sunset prerequisite explicit | §29 | PASS |
| G-14 | Forbid rollout explicit | §18 | PASS |
| G-15 | Matrix deterministic | §17 | PASS |
| G-16 | Current major is V1 | §5 | PASS |
| G-17 | No successor route exists | §5 | PASS |
| G-18 | No implementation code | §1.3 | PASS |
| G-19 | No migration changed | §40 | PASS (pre-install harness; re-verified after installation) |
| G-20 | No frozen source changed | §37 | PASS (pre-install harness; re-verified after installation) |
| G-21 | Source hashes match | §0.2 | PASS (pre-install harness; re-verified after installation) |
| G-22 | Repository delta is only this file | Closure report | PASS (pre-install harness; re-verified after installation) |
| G-23 | No concealed contradiction | §37, §42 | PASS |
| G-24 | AX-A SUNSET contract equals AVS-OD-01 | §28, §29, §38 | PASS |
| G-25 | No O-1 row gated on a frozen-source amendment | §13, §17.3 | PASS |
| G-26 | §17.1 contract-diff scope excludes configured operational values | §17.1, §38 | PASS |

## 42. Findings / Result

| Severity | Count |
|---|---|
| P0 blockers | 0 |
| P1 issues | 0 |
| Minor observations | 11 |

| ID | Observation | Disposition |
|---|---|---|
| M-01 | 6A L845 calls six months an indicative default | Bound as a minimum by AVS-OD-02; no amendment |
| M-02 | AEC L466 registers 410 for OAuth state only | Sunset contract is FUTURE REQUIRED WORK (AVS-OD-01) |
| M-03 | 6J L1201 compares against the platform's current API version | Reconciled by AVS-OD-06 |
| M-04 | 4F L893 defines versioned topics without retirement | Reconciled by AVS-OD-07 and 6J L1634 |
| M-05 | HLA and 3A are not hash-gated | Cited as informative only (§0.2) |
| M-06 | 6A L169 uses 410 for disallowed DELETE | Distinct from sunset (§29 SN-02) |
| M-07 | The frozen sources define no WebSocket deprecation/removal mechanism; REST signals (`deprecated: true`, `Sunset`, 410 + envelope) are not WebSocket mechanisms | FUTURE REQUIRED WORK; no WebSocket deprecation or removal may be announced or executed until it is specified (§10 WSP-13, §28 DL-08, CM-LC-11); none is planned |
| M-08 | 6J L1634 forbids topic removal while AVS-OD-07 anticipates predecessor-topic retirement | 6J L1634 governs; topic removal is PROHIBITED under current sources (§12 WHR-07, CM-WH-04) |
| M-09 | 6J L1009 fixes one signing algorithm across the whole platform, with distinct canonical inputs for webhooks and plugin callouts (6J L2539) | In-place change PROHIBITED (CM-WH-07, §13 SG-09); a successor header is PROHIBITED pending owning-source amendment; if later authorized it is additive/non-breaking for v1-only verifiers and applies platform-wide with each canonical input (§13 SG-04, SG-06, CM-WH-12) |
| M-10 | 6A L404 states a maximum page size but not over-maximum request behavior | Raising the maximum is CONDITIONAL; lowering it is BREAKING (CM-PAG-02, CM-PAG-03) |
| M-11 | Quota values are owned by 6K §25 and 6M §18, while AVS-OD-10 speaks of numeric limits | AVS-OD-10 covers numeric request-rate/abuse thresholds only; quota values are not API versions; pricing, billing calculation, admission, authority, enforcement, wire-shape and error-contract changes are classified separately (CM-RL-01, CM-RL-02, CM-RL-05) |

API VERSIONING STRATEGY = READY FOR FINAL INDEPENDENT FREEZE REVIEW
