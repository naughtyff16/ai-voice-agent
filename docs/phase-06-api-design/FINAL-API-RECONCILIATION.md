# Final API Reconciliation — Phase 6 (6A–6M)

## AI Voice Agent Platform — Phase 6 — API Design — Cross-Document Reconciliation Pass

---

## 0. Document Control

| Field | Value |
|---|---|
| Document | `FINAL-API-RECONCILIATION.md` |
| Phase | Final API Reconciliation (post-6A–6M) |
| Depends on | All 13 Phase 6 API design documents (6A–6M), as they stand after this pass's controlled source edits (§12), **plus** the **three** Phase 5 documents amended by the authorized database remediations (`5C-Voice-Schema.md`, `5H-Billing-Usage-Schema.md`, `5K/MIGRATION_MANIFEST.md`) — `5H-Billing-Usage-Schema.md` added by the `FAR-OD-02` billing / quota-override closure (§10A, §12.1) and amended again by the `FAR-OD-03` / `FAR-OD-04` capacity-quota closure (§10B, §12.4) |
| Scope | API-contract reconciliation **plus one authorized additive database remediation** *(original `110_5C2` scope — historical; as extended below the reconciliation now carries **three** separately owner-authorized additive migrations, `110_5C2`, `111_5H4` and `112_5H5`)*. The owner's Option-B decision could not be implemented legally under frozen 6A §17.3 by the API layer alone (§10.1), so the DB-conformant closure directive authorized exactly **one** new migration, `110_5C2`; after the second independent review (P0 = 0, P1 = 2, P2 = 1) that same migration was **amended in place** by the micro-remediation (§13) — no second migration was created. No application code, no OpenAPI document. Migrations `001`–`109` and their Alembic wrappers are **byte-identical to `HEAD`** (§16). Live PostgreSQL 18.6 and Alembic validation was executed against **disposable** databases only (§16). **Extended by the billing / quota-override closure:** owner decision `FAR-OD-02` = Option B authorized exactly **one** further additive migration, `111_5H4` (`down_revision = '110_5C2'`), closing `FAR-P1-04` and `FAR-P1-05`. `110_5C2` was **not** amended again and *(historical, 111 pass — superseded)* ~~no migration `112` exists~~; as of that pass the byte-identity statement read **`001`–`110`** (§16.3). **Extended by the capacity-quota closure:** owner decisions `FAR-OD-03` = Option B and `FAR-OD-04` = ADMISSION→TERMINAL authorized exactly **one** further additive migration, `112_5H5` (`down_revision = '111_5H4'`), closing `FAR-P1-06` and `FAR-P2-08`. `110_5C2` and `111_5H4` were **not** amended; **no migration `113` exists**; the byte-identity statement now reads **`001`–`111`** (§16.4). **Current project head: `112_5H5`.** |
| Method | Independent, reproducible **dual** route extraction (semantic-normalized **and** literal) over the full body text of all 13 documents. **Current exact re-extraction (112 state, `FAR-P2-07`): 1,683 raw route occurrences → 595 unique literal Method+Path → 448 unique semantic Method+Path → 55 cross-document semantic collision groups (31 of which carry more than one literal spelling).** The earlier figures 1,640 / 598 / 448 / 55 / 32 are **historical / intermediate** (pre-normalization state of the original pass). See §1. |
| Owner decision of record | **`FAR-OD-01` = OPTION B** — hard synchronous Agent-count quota enforcement on `POST /api/v1/agents`. Applied in full (§10). Closes `DEP-6E-20`.<br>**`FAR-OD-02` = OPTION B** — true temporary Platform-Admin quota overrides with live commercial-baseline fallback; an override never overwrites the base, and expiry falls back to the **current** base, not to unlimited. Applied in full (§10A). Closes `FAR-P1-04`, `FAR-P1-05`, `FAR-P2-04`, `FAR-P2-05`.<br>**`FAR-OD-03` = OPTION B** — `CONCURRENT_CALLS` is a separate **CAPACITY / ENTITLEMENT** quota domain (instantaneous reservation), not an accumulated usage metric. Applied in full (§10B). Closes `FAR-P1-06`, `FAR-P2-08`.<br>**`FAR-OD-04` = ADMISSION→TERMINAL** — one `CONCURRENT_CALLS` reservation per call, acquired once at outbound admission and released once at setup failure or on entry to a frozen terminal state (6K §54.6, 6D §42.4, 6H §54.2). Applied in full (§10B). |
| Forbidden artifacts (per governing task) | `API-MASTER-INDEX.md`, `AUTHORIZATION-MATRIX.md`, `ERROR-CATALOG.md`, `API-VERSIONING-STRATEGY.md` — **none created.** No implementation code, no OpenAPI document. Migration history of this reconciliation: `110_5C2` (`FAR-OD-01`, amended in place by the micro-remediation, §12.1) → `111_5H4` (`FAR-OD-02`, §12.3) → `112_5H5` (`FAR-OD-03` / `FAR-OD-04`, §12.4). *Historical statements "no migration `111` exists" (110 pass) and "no migration `112` exists" (111 pass) are superseded.* **`112_5H5` is the single Alembic head; no migration `113` exists** (§14.1, §16.4). |
| Date | 2026-09-15 (110 / 111 passes); 2026-09-16 (112 capacity-quota pass); **2026-09-17** (master-FAR closure) |
| Result | **See §15.** |

This document does **not** self-declare any Phase 6 document APPROVED or FROZEN. Freeze remains an independent-review decision.

---

## 1. Method

Prior sessions' route counts ("558/308/35", and this artifact's own earlier "445/52") were treated as **unverified** and re-derived from zero. This pass ran a **dual** extraction so that semantic collisions and literal-spelling drift are measured separately and neither hides the other.

1. **Corpus.** Full body text of all 13 documents (not headings only) — several documents (6A, 6F, 6G, 6I, 6L, 6M) declare or reference endpoints inline in prose, auth matrices and error tables.
2. **Match.** Two patterns applied to every line: inline `(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+`?<path>` and table-cell `| `?<METHOD>`? | `?<path>`, with `<path>` = `/[A-Za-z0-9_\-./{}:*]*` (case-insensitive method for the inline form). Rejected: paths shorter than 2 characters, file-like / repository paths (`.md`, `.sql`, `.py`, `.json`, `.yaml`, `.yml`, `.ts`, `.tsx`, `/docs`, `/home`, `phase-0`), paths with unbalanced `{`, and bare `/`. Identical (file, line, literal) hits are counted once. Trailing punctuation and trailing `/` are stripped.
3. **Prefix normalization (both passes).** `/api/internal/v1/…` and `/internal/v1/…` → `INTERNAL …`; `/api/v1/…` → `PUBLIC …`. This is required because 6I and 6M frequently omit the `/api/v1` prefix when referring to their own already-declared routes, and because an internal-surface route must never be allowed to collide with a public-surface route of the same tail. A bare `/api/v1` or `/api/internal/v1` normalizes to `PUBLIC /` / `INTERNAL /`; any other path without a recognized prefix is treated as `PUBLIC`.
4. **Pass A — literal.** Parameter names preserved exactly as written. → **595 unique literal Method+Path pairs** from **1,683 raw occurrences** (current exact re-extraction, `FAR-P2-07`).
5. **Pass B — semantic.** Every `{anything}` segment collapsed to `{param}`. → **448 unique semantic Method+Path pairs**.
6. **Collision detection.** Group Pass-B keys by (method, semantic path); a group is a *cross-document collision group* when it appears in **two or more distinct documents**. → **55 groups**.
7. **Literal-variance detection.** For each of the 55 groups, all Pass-A literals were retained. **31 groups currently carry more than one literal spelling** — each was individually adjudicated in §3, and three real defects were corrected at source (§12 edits #3–#5).
8. **Verification.** Every one of the 55 groups was verified by reading the actual source text on all sides — never accepted from the normalized match alone, because normalization itself manufactures false positives (three found; §2.1 rows 8, 46, 47).
9. **Scratch artifacts.** The extraction helper and its JSON output were kept exclusively under the session scratchpad directory **outside the repository** and are not part of this deliverable. No `__pycache__`, `*.pyc` or `*.pyo` exists anywhere in the repository (§15, gate 27).

**1.1 Count history (FAR-P2-07).** The same extractor and the same matcher were used throughout; no algorithm change was made in any re-run.

| Run | Raw | Literal | Semantic | Groups | Multi-spelling groups | Status |
|---|---:|---:|---:|---:|---:|---|
| Original pass, first run | 1,640 | 600 | 448 | 55 | 33 | historical |
| Original pass, after in-pass literal corrections (figures the original §1–§3 recorded) | 1,640 | 598 | 448 | 55 | 32 | **historical / intermediate** — pre-normalization state |
| Committed corpus after literal normalization (110/111 passes) | 1,660 | 595 | 448 | 55 | 31 | historical |
| **Current exact re-extraction (112 state)** | **1,683** | **595** | **448** | **55** | **31** | **current** |

The 112 documentation amendments (6D, 6E, 6H, 6K, 6M) raised raw references 1,660 → 1,683 but changed **neither** the literal set (595), **nor** the semantic set (448), **nor** the 55-group set, **nor** the 31 variance groups: **no group was added or removed**. They added references, not contracts. The only participation change is group 41 (`POST /calls`), which gained 6K and 6M as referencing documents (§2.1 row 41).

---

## 2. Endpoint Collision Ledger

### 2.0 Legend and adjudication rules

| Class | Meaning |
|---|---|
| **A** | **SAME CONTRACT** — two or more documents independently declare the same route with the same contract. |
| **B** | **CANONICAL OWNER + CONSUMER REFERENCE** — exactly one document declares it; the others cite/consume it without re-declaring shape, auth or errors. |
| **C** | **CONTROLLED EXTENSION** — one owner, plus a bounded, mutually-cited amendment from another document. |
| **D** | **EXAMPLE ONLY** — a non-owning document uses the path illustratively (convention examples), and disowns the domain in its own text. |
| **E** | **TRUE CONTRADICTION** — two documents assert incompatible contracts for the same route. |
| **FALSE POSITIVE** | Not a collision: normalization or a document's local shorthand made two genuinely different routes look identical. |

Two adjudication rules were applied and are stated here so the classification is reproducible:

- **Mixed-group rule.** Where a group contains both a real owner/consumer relation **and** a 6A example-only component (groups 27 and 42), the group is classified by its **strongest** relation (**B**), and 6A's example-only participation is recorded in the *Contract Difference* column. A group in which 6A is the **only** other document is classified **D**.
- **Shorthand rule.** A path written in a document's local shorthand (prefix omitted, or `{id}` for a canonical `{descriptive_id}`) is **not** a declaration. It is evidence of literal drift (§3), and only makes a group a FALSE POSITIVE when the shorthand collides with a *different document's real route*.

### 2.1 Ledger — all 55 cross-document collision groups, one row each

Every group appears below. No grouping, no "~", no "etc.".

| # | Method | Literal Path(s) Seen | Semantic-Normalized Path | Documents Appearing In | Canonical Owner | Classification | Contract Difference | Resolution | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `DELETE` | `/contacts/{contact_id}` · `/contacts/{id}` | `/contacts/{param}` | 6G, 6H | **6G** | **B** | Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. 6G §22.1 declares `DELETE /api/v1/contacts/{contact_id}` (GDPR erasure). | 6H cites 6G's route verbatim with an explicit ownership attribution ("owned by 6G"); no 6H contract exists. | CLOSED |
| 2 | `GET` | `/agents/{agent_id}/versions/{version_id}` | `/agents/{param}/versions/{param}` *(internal)* | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Internal-service surface, internal JWT only. | 6D's auth-matrix row corrected this pass to the canonical literal `GET /api/internal/v1/agents/{agent_id}/versions/{version_id}` (was `/internal/v1/.../{id}/versions/{id}` — malformed prefix + duplicated parameter name). | CLOSED |
| 3 | `GET` | `/organizations/{organization_id}/compliance-policy` | `/organizations/{param}/compliance-policy` *(internal)* | 6C, 6D, 6H | **6C** | **B** | None. 6C declares the internal contract; 6D and 6H consume it. | 6H's three occurrences corrected this pass from `{id}` to `{organization_id}` (§8 edit #1). 6C/6D already canonical. | CLOSED |
| 4 | `GET` | `/agents` | `/agents` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. | 6D reference-only; 6E canonical. | CLOSED |
| 5 | `GET` | `/agents/{agent_id}` · `/agents/{id}` | `/agents/{param}` | 6D, 6E, 6H | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D and 6H reference-only; 6E canonical. | CLOSED |
| 6 | `GET` | `/agents/{agent_id}/versions` · `/agents/{id}/versions` | `/agents/{param}/versions` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D reference-only; 6E canonical. | CLOSED |
| 7 | `GET` | `/agents/{agent_id}/versions/{version_id}` · `/agents/{id}/versions/{id}` · `/agents/{id}/versions/{version_id}` | `/agents/{param}/versions/{param}` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Three literal spellings seen, all in prose/matrix shorthand. | 6E §12 canonical declaration is `{agent_id}`/`{version_id}`; the `{id}` forms are shorthand in the same documents' narrative text, not competing declarations. | CLOSED |
| 8 | `GET` | `/audit/events` | `/audit/events` | 6L, 6M | **—** | **FALSE POSITIVE** | Not the same route. 6L owns tenant-scoped `GET /api/v1/audit/events` (`audit:read`, RLS-filtered). 6M's §25 inventory row is `GET /api/v1/platform-admin/audit/events` (`PLATFORM_ADMIN`, cross-tenant). | Extraction artifact: 6M line 415 used a local shorthand omitting the `/api/v1/platform-admin` prefix. Disambiguated this pass by an explicit shorthand-scope note above 6M's error table (§8 edit #4); no row changed. Also a positively closed 6L §61 → 6M handoff (§5). | CLOSED |
| 9 | `GET` | `/auth/me` | `/auth/me` | 6B, 6C | **6B** | **B** | None. 6B owns `/auth/me` (session/identity view); 6C's `/users/me` is a different resource (tenant profile) and 6C says so explicitly. | 6C reference-only. The prior artifact's ledger typo `POST /auth/me (as GET /auth/me)` is removed — the route is `GET`, and no `POST /auth/me` exists anywhere in the corpus. | CLOSED |
| 10 | `GET` | `/billing/invoices` | `/billing/invoices` | 6K, 6L | **6K** | **B** | None. 6K owns the billing read contract; 6L links to it rather than duplicating it (6L's own words). | 6L reference/link only — no re-declared contract, no CQRS projection endpoint. | CLOSED |
| 11 | `GET` | `/billing/quotas` | `/billing/quotas` | 6K, 6L | **6K** | **B** | None. 6K owns the billing read contract; 6L links to it rather than duplicating it (6L's own words). | 6L reference/link only — no re-declared contract, no CQRS projection endpoint. | CLOSED |
| 12 | `GET` | `/billing/summary` | `/billing/summary` | 6K, 6L | **6K** | **B** | None. 6K owns the billing read contract; 6L links to it rather than duplicating it (6L's own words). | 6L reference/link only — no re-declared contract, no CQRS projection endpoint. | CLOSED |
| 13 | `GET` | `/billing/usage` | `/billing/usage` | 6K, 6L | **6K** | **B** | None. 6K owns the billing read contract; 6L links to it rather than duplicating it (6L's own words). | 6L reference/link only — no re-declared contract, no CQRS projection endpoint. | CLOSED |
| 14 | `GET` | `/billing/usage/summary` | `/billing/usage/summary` | 6K, 6L | **6K** | **B** | None. 6K owns the billing read contract; 6L links to it rather than duplicating it (6L's own words). | 6L reference/link only — no re-declared contract, no CQRS projection endpoint. | CLOSED |
| 15 | `GET` | `/calls/{call_id}` · `/calls/{id}` | `/calls/{param}` | 6D, 6H | **6D** | **B** | 6D owns the Call/Conversation runtime contract. The other document(s) read 6D's state as consumers and cite it explicitly; neither re-declares request/response shape, auth, or errors. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6H reference-only; 6D canonical. | CLOSED |
| 16 | `GET` | `/calls/{call_id}/recording` · `/calls/{id}/recording` | `/calls/{param}/recording` | 6D, 6H | **6D** | **B** | 6D owns the Call/Conversation runtime contract. The other document(s) read 6D's state as consumers and cite it explicitly; neither re-declares request/response shape, auth, or errors. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6H reference-only; 6D canonical. | CLOSED |
| 17 | `GET` | `/campaigns/{campaign_id}` · `/campaigns/{id}` | `/campaigns/{param}` | 6H, 6L | **6H** | **B** | Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. 6H owns the Campaign contract. | 6L reference-only (analytics drill-down link). | CLOSED |
| 18 | `GET` | `/campaigns/{campaign_id}/contacts/{campaign_contact_id}/call-reports` · `/campaigns/{id}/contacts/{cc_id}/call-reports` | `/campaigns/{param}/contacts/{param}/call-reports` | 6H, 6L | **6H** | **B** | None semantically. 6L uses the shorthand `{id}`/`{cc_id}` for 6H §15.6's `{campaign_id}`/`{campaign_contact_id}`. | 6L §49/§61 and ADR-6L-15 state explicitly that this is "an operational drill-down composition… never a 6L/CQRS projection endpoint," owned by 6H. | CLOSED |
| 19 | `GET` | `/contacts/{contact_id}/activities` · `/contacts/{id}/activities` · `/contacts/{predecessor_id}/activities` | `/contacts/{param}/activities` | 6G, 6H | **6G** | **B** | None. The third literal (`{predecessor_id}`) is not a third spelling of the same route — it is 6G §23's worked merge example naming a *different* Contact (the merged predecessor) on the same route shape. | 6H reference-only; 6G canonical. No edit required. | CLOSED |
| 20 | `GET` | `/conversations/{conversation_id}` · `/conversations/{id}` | `/conversations/{param}` | 6D, 6H | **6D** | **B** | 6D owns the Call/Conversation runtime contract. The other document(s) read 6D's state as consumers and cite it explicitly; neither re-declares request/response shape, auth, or errors. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6H reference-only; 6D canonical. | CLOSED |
| 21 | `GET` | `/conversations/{conversation_id}/tool-executions` · `/conversations/{id}/tool-executions` | `/conversations/{param}/tool-executions` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Tool-execution observability follows the Tool contract, which is 6E's. | 6D reference-only (6D §-auth matrix maps it to `call:read` as an adequate reuse, no gap flagged). | CLOSED |
| 22 | `GET` | `/conversations/{conversation_id}/transcript` · `/conversations/{id}/transcript` | `/conversations/{param}/transcript` | 6D, 6H | **6D** | **B** | 6D owns the Call/Conversation runtime contract. The other document(s) read 6D's state as consumers and cite it explicitly; neither re-declares request/response shape, auth, or errors. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6H reference-only; 6D canonical. | CLOSED |
| 23 | `GET` | `/conversations/{conversation_id}/transcript/segments` · `/conversations/{id}/transcript/segments` | `/conversations/{param}/transcript/segments` | 6D, 6H, 6L | **6D** | **B** | 6D owns the Call/Conversation runtime contract. The other document(s) read 6D's state as consumers and cite it explicitly; neither re-declares request/response shape, auth, or errors. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6H and 6L reference-only; 6D canonical. | CLOSED |
| 24 | `GET` | `/jobs/{job_id}` | `/jobs/{param}` | 6A, 6J | **6A** | **B** | None. This is the one platform-level route 6A genuinely owns: §18.3's cross-cutting async-job status envelope (`202 Accepted` + `job_id` → `GET /api/v1/jobs/{job_id}`), not a domain route. | 6J §-sync consumes the convention and discloses a bounded deviation (its `job_id` is a Celery task ID, not a persisted row) as an API-DESIGN DEPENDENCY under 6A §18.3's own explicit allowance. Disclosed deviation, not a competing contract. | CLOSED |
| 25 | `GET` | `/language-evaluations` | `/language-evaluations` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Language-evaluation reference data drives Agent configuration. | 6D reference-only; 6E canonical. | CLOSED |
| 26 | `GET` | `/provider-health` | `/provider-health` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Provider health informs Agent model/voice configuration. | 6D reference-only; 6E canonical. | CLOSED |
| 27 | `GET` | `/recordings/{id}/download-url` · `/recordings/{recording_id}/download-url` | `/recordings/{param}/download-url` | 6A, 6D, 6H, 6L | **6D** | **B** | None. 6D owns the signed-recording-URL contract. 6A's participation is Classification-D example-only (worked example for the sensitive-URL logging rule); 6H and 6L are consumers. | Mixed group, classified by its strongest relation (B). 6A component is example-only per the mixed-group rule (§2.0); 6A §3 disowns all concrete domain routes. | CLOSED |
| 28 | `GET` | `/suppressions/check` | `/suppressions/check` | 6G, 6H | **6G** | **B** | Not a duplicate HTTP contract at all — a transport-boundary prohibition. 6H is explicitly forbidden from calling it over REST and must use the in-process `EffectiveSuppressionService.check()`. | DEP-6G-11 / ADR-6H-04 / ADR-6G-14 — both sides agree in writing. 6H's single occurrence is the citation of the prohibition itself. | CLOSED |
| 29 | `GET` | `/tool-executions/{execution_id}` · `/tool-executions/{id}` | `/tool-executions/{param}` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D reference-only; 6E canonical. | CLOSED |
| 30 | `GET` | `/tools` | `/tools` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. | 6D reference-only; 6E canonical. | CLOSED |
| 31 | `GET` | `/tools/{id}` · `/tools/{tool_id}` | `/tools/{param}` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D reference-only; 6E canonical. | CLOSED |
| 32 | `GET` | `/webhook-deliveries` | `/webhook-deliveries` | 6A, 6J | **6J** | **D** | 6A owns no webhook route. 6A line 772 states: "endpoint design itself deferred to a Phase 6B+ Integrations/Webhooks document — this section only fixes the underlying delivery contract." | 6A citation is illustrative; 6J §- declares the real contract. No edit required. | CLOSED |
| 33 | `PATCH` | `/agents/{agent_id}` · `/agents/{id}` | `/agents/{param}` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D reference-only; 6E canonical. | CLOSED |
| 34 | `PATCH` | `/contacts/{contact_id}` · `/contacts/{id}` | `/contacts/{param}` | 6A, 6G | **6G** | **D** | 6A lines 180/201 use `/contacts/{id}` generically to illustrate resource-nesting and `PATCH` conventions; 6A §3 explicitly lists CRM endpoints as out of scope. | Example-only. 6G canonical. | CLOSED |
| 35 | `PATCH` | `/tools/{id}` · `/tools/{tool_id}` | `/tools/{param}` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D reference-only; 6E canonical. | CLOSED |
| 36 | `POST` | `/agents` | `/agents` | 6D, 6E, 6K | **6E** | **C** | 6E owns the endpoint. 6K supplies the commercial authority. This pass executed a controlled extension in both directions: 6E §43 (hard synchronous `ACTIVE_AGENTS` admission control) and 6K §52 (the metric's counted-state set + reuse of `429 QUOTA_EXCEEDED`). | Owner decision `FAR-OD-01` = Option B, applied as a bounded, mutually-cited amendment to two documents. 6D remains reference-only. Closes `DEP-6E-20` (§5.1). | CLOSED |
| 37 | `POST` | `/agents/{agent_id}/clone` · `/agents/{id}/clone` | `/agents/{param}/clone` | 6D, 6E, 6K | **6E** | **C** | Same as `POST /agents` — clone also commits a `DRAFT` `voice.agents` row, so leaving it ungated would defeat the owner's invariant. Gated identically (6E §43.8). | Forced corollary of `FAR-OD-01`, documented as such in 6E §43.8 and 6K §52. 6D/6K reference-only otherwise. | CLOSED |
| 38 | `POST` | `/agents/{agent_id}/deprecate` · `/agents/{id}/deprecate` | `/agents/{param}/deprecate` | 6D, 6E, 6K | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. 6K's reference is new this pass: deprecation is the sole slot-release path for `ACTIVE_AGENTS` (6E §43.2, 6K §52.3). | 6D reference-only; 6K references it as the release semantic, not as a competing contract. | CLOSED |
| 39 | `POST` | `/agents/{agent_id}/publish` · `/agents/{id}/publish` | `/agents/{param}/publish` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. Only literal parameter spelling differs (canonical `{descriptive_id}` in the owning declaration vs. `{id}` in prose/matrix shorthand). Semantics, auth, and response shape identical. | 6D reference-only; 6E canonical. | CLOSED |
| 40 | `POST` | `/auth/invitations/accept` | `/auth/invitations/accept` | 6B, 6C | **6B** | **B** | None. 6C discloses that 6B owns exactly one invitation-accept endpoint and does not declare a second. | 6C reference-only; 6B canonical. | CLOSED |
| 41 | `POST` | `/calls` | `/calls` | 6D, 6E, 6H, 6K, 6M *(historically 6D, 6E, 6H; 6K and 6M added by the 112 pass)* | **6D** | **C** | 6D owns call creation. 6H's campaign dispatch flows *through* 6D's endpoint under an already-executed, named amendment (6D §28.10a, campaign dispatch idempotency) — not a second endpoint. 6E's single occurrence is a disclaimer, not a declaration. **112 pass:** 6K §54 defines the `CONCURRENT_CALLS` capacity authority that `POST /calls` *consumes* (6K §54.6: "every admitting path consumes it: 6D `POST /calls`…"); 6M references `POST /calls` only in capacity / admin reconciliation prose (6M: "The runtime consumers are 6D §42 (`POST /calls`) and 6H §54 … through 6K §54's single capacity authority"). Neither 6K nor 6M declares a second endpoint. | 6E states outright: "no 6E endpoint ever returns it, since no 6E endpoint initiates a call." Controlled extension executed in a prior pass; the 112 pass added capacity-authority *references* only (§10B), no contract change. Class unchanged (**C**), owner unchanged (**6D**). | CLOSED |
| 42 | `POST` | `/calls/{call_id}/terminate` · `/calls/{id}/terminate` | `/calls/{param}/terminate` | 6A, 6D, 6I | **6D** | **B** | 6D owns call control. 6I never implements a second call-control path — `terminate`/`transfer` are explicitly "6D's own existing call-control mechanism," invoked in-process (6I lines 566, 1335). 6A's participation is example-only. | Mixed group (B + a 6A example-only component), classified by strongest relation per §2.0. | CLOSED |
| 43 | `POST` | `/calls/{call_id}/transfer` · `/calls/{id}/transfer` | `/calls/{param}/transfer` | 6D, 6I | **6D** | **B** | As above — 6I invokes 6D's mechanism in-process; no Workflow-owned HTTP path exists. | 6I reference-only; 6D canonical. | CLOSED |
| 44 | `POST` | `/campaigns/{campaign_id}/pause` · `/campaigns/{id}/pause` | `/campaigns/{param}/pause` | 6A, 6H | **6H** | **D** | 6A lines 192–196 are an explicitly labelled block of illustrative example routes for the action-sub-resource naming convention. | Example-only. 6H canonical. | CLOSED |
| 45 | `POST` | `/campaigns/{campaign_id}/resume` · `/campaigns/{id}/resume` | `/campaigns/{param}/resume` | 6A, 6H | **6H** | **D** | Same 6A illustrative block (lines 192–196). | Example-only. 6H canonical. | CLOSED |
| 46 | `POST` | `/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` · `/integrations/providers/{slug}/callbacks/{opaque_connection_route_id}` | `/integrations/providers/{param}/callbacks/{param}` | 6J, 6K | **6J** | **FALSE POSITIVE** | Not the same route. 6J §24.6 owns `POST /api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` (tenant-created `IntegrationConnection` routing). 6K §30.2 declares a *different literal path*: `POST /api/v1/billing/payment-providers/{provider_slug}/webhook`. | **`FAR-P3-01` RESOLVED this pass by direct grep.** The collision exists only because 6K §30.1 ("Why This Is Not 6J's `IntegrationConnection` Route") quotes 6J's path in order to disown it. Neither route modified. 6J's second literal (`{slug}`) is its own §-inventory shorthand for `{provider_slug}`. | CLOSED |
| 47 | `POST` | `/organizations/{id}/suspend` · `/organizations/{organization_id}/suspend` | `/organizations/{param}/suspend` | 6C, 6M | **6C** | **FALSE POSITIVE** | Not the same route. 6C owns tenant self-service `POST /api/v1/organizations/{organization_id}/suspend` (`OWNER` role, ADR-6C-01). 6M's §25 inventory row is `POST /api/v1/platform-admin/organizations/{id}/suspend` (`PLATFORM_ADMIN`, forced). | Extraction artifact from 6M line 388's prefix-omitting shorthand — disambiguated this pass by the shorthand-scope note added above 6M's error table (§8 edit #4). Different paths, different principals, different purposes; neither route modified. | CLOSED |
| 48 | `POST` | `/platform-admin/break-glass/{grant_id}/release` | `/platform-admin/break-glass/{param}/release` | 6B, 6M | **6B** | **B** | None — identical literal path in both documents. 6M reuses 6B's frozen contract verbatim. | 6M's own freeze-gate narrative (line 234) discloses and corrects an earlier draft's competing-route error, reclassifying these rows to "REUSED EXISTING 6B." 6M line 122 corrected this pass from `{id}` to `{grant_id}` (§8 edit #2). | CLOSED |
| 49 | `POST` | `/platform-admin/organizations/{any}/break-glass` · `/platform-admin/organizations/{organization_id}/break-glass` | `/platform-admin/organizations/{param}/break-glass` | 6B, 6M | **6B** | **B** | None. The second literal, `{any}`, is not a parameter name — it is 6B line 2341's prose token in a principal-matrix cell meaning "any org, by design." | 6M reuses 6B's contract verbatim. Extraction shorthand only; no edit required. | CLOSED |
| 50 | `POST` | `/platform-admin/users/{user_id}/sessions/revoke-all` | `/platform-admin/users/{param}/sessions/revoke-all` | 6B, 6M | **6B** | **B** | None — identical literal path (`{user_id}`) in both documents. | 6M reuses 6B's contract; 6M's `identity.fn_platform_revoke_all_sessions()` narrows its own DB grants to match 6B rather than reimplement it. | CLOSED |
| 51 | `POST` | `/tools` | `/tools` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. | 6D reference-only; 6E canonical. | CLOSED |
| 52 | `POST` | `/tools/{id}/deactivate` · `/tools/{toolX}/deactivate` · `/tools/{tool_id}/deactivate` | `/tools/{param}/deactivate` | 6D, 6E | **6E** | **B** | 6E owns the Agent/Tool management contract outright (ADR-6E-01: "6E becomes authoritative for Agent management APIs; 6D remains authoritative for Call/Voice-runtime consumption"). 6D's rows are historical/consumer references, never a competing declaration. The third literal, `{toolX}`, is not a parameter name — it is 6D §18.1's worked timeline example naming a specific tool instance. | 6D reference-only; 6E canonical. No edit required. | CLOSED |
| 53 | `POST` | `/webhook-deliveries/{delivery_id}/replay` · `/webhook-deliveries/{id}/replay` | `/webhook-deliveries/{param}/replay` | 6A, 6J | **6J** | **D** | 6A lines 192–196/772 — illustrative example only; 6A explicitly defers webhook endpoint design to the Integrations document. | Example-only. 6J canonical. | CLOSED |
| 54 | `POST` | `/webhook-endpoints` | `/webhook-endpoints` | 6A, 6J | **6J** | **D** | Same 6A deferral statement (line 772). | Example-only. 6J canonical. | CLOSED |
| 55 | `POST` | `/workflows/{id}/publish` · `/workflows/{workflow_id}/publish` | `/workflows/{param}/publish` | 6A, 6I | **6I** | **D** | 6A line 196's illustrative example block. | Example-only. 6I canonical. | CLOSED |
### 2.2 Classification arithmetic (must sum exactly)

| Class | Count | Group numbers |
|---|---|---|
| **A** — SAME CONTRACT | **0** | — |
| **B** — CANONICAL OWNER + CONSUMER REFERENCE | **42** | 1–7, 9–31, 33, 35, 38, 39, 40, 42, 43, 48, 49, 50, 51, 52 |
| **C** — CONTROLLED EXTENSION | **3** | 36, 37, 41 |
| **D** — EXAMPLE ONLY | **7** | 32, 34, 44, 45, 53, 54, 55 |
| **E** — TRUE CONTRADICTION | **0** | — |
| **FALSE POSITIVE** | **3** | 8, 46, 47 |
| **Total** | **55** | A 0 + B 42 + C 3 + D 7 + E 0 + FP 3 = **55** ✅ |

**Headline result: zero (E) TRUE CONTRADICTIONS across all 55 collision groups.** Every group resolves to a single named canonical owner, or is not a collision at all.

### 2.3 Why the total is 55 and not the previously recorded 52

The earlier revision of this artifact recorded "445 unique routes / 52 raw collision groups". That figure is **superseded, not reconciled to**: it was produced by a single-pass extraction that (a) collapsed every parameter to `{id}` **and** stripped `/api/v1` without distinguishing the internal surface, and (b) grouped several related routes into single ledger rows rather than counting them individually. Per the governing instruction, the fresh reproducible result is used and the difference is explained rather than forced back to 52:

| Cause of the delta | Effect on the count |
|---|---|
| The internal surface is now normalized separately (`INTERNAL` vs. `PUBLIC`), so internal routes can no longer be merged into, or masked by, a public route of the same tail. | Splits groups apart (+) |
| Route-family rows (e.g. the old §2.1 row 1 covering "~15 pairs" of 6E agent/tool routes in one line) are now expanded to one row per Method+Path, as required. | Reveals groups that were previously invisible inside a single row (+) |
| Two real source defects corrected this pass (6D's `/internal/v1/` prefix omission and its duplicated `{id}/versions/{id}` parameter) previously produced malformed keys that grouped incorrectly. | Corrects mis-grouping (±) |
| The unique-route denominator itself changed shape: 448 **semantic** vs. 598 **literal** unique pairs *(598 = historical / intermediate; current literal count 595, §1.1)*. The old "445" was a semantic-style count and is closest to today's 448; the 3-pair difference is attributable to the internal/public split plus the two corrected 6D literals. | Denominator now stated twice, unambiguously |

**No group was added or removed to reach a target number.** *(Historical / intermediate — original pass:)* the same normalization rules over the source text as it then stood yielded 1,640 / 598 / 448 / 55 / 32. **Current exact re-extraction (112 state): 1,683 / 595 / 448 / 55 / 31** — same group set, same arithmetic (A 0 + B 42 + C 3 + D 7 + E 0 + FP 3 = 55), zero Class E (§1.1).

---

## 3. Final Route Literal Consistency Check

Scope: Method spelling, path spelling, singular/plural, prefix correctness, and parameter naming — across the collision groups carrying more than one literal spelling (32 in the historical / intermediate original-pass state; **31** in the current exact re-extraction, §1.1), plus the two prefix families.

### 3.1 Defects found and corrected at source (5)

| # | Document | Literal before | Literal after | Why it is a real defect, not a style preference |
|---|---|---|---|---|
| 1 | `6D-Voice-Call-Agent-APIs.md` (auth matrix, line 1254) | `GET /internal/v1/calls/{id}` | `GET /api/internal/v1/calls/{call_id}` | The corpus's internal surface is `/api/internal/v1/` in **every other occurrence in all 13 documents**; these were the only two `/internal/v1/` literals. A missing `/api` segment is a wrong path, not a shorthand. |
| 2 | `6D-Voice-Call-Agent-APIs.md` (auth matrix, line 1255) | `GET /internal/v1/agents/{id}/versions/{id}` | `GET /api/internal/v1/agents/{agent_id}/versions/{version_id}` | Same prefix defect, **plus** the same parameter name used twice in one path — structurally ambiguous and un-implementable as written. 6E's canonical declaration supplies the correct names. |
| 3 | `6H-Campaign-APIs.md` (3 occurrences) | `…/organizations/{id}/compliance-policy` | `…/organizations/{organization_id}/compliance-policy` | 6C owns this internal route and declares `{organization_id}`; a consumer must cite the owner's literal. |
| 4 | `6M-Admin-Platform-APIs.md` (line 122) | `…/break-glass/{id}/release` | `…/break-glass/{grant_id}/release` | 6B owns the break-glass contract and declares `{grant_id}`; 6M reuses 6B's route verbatim, so the literal must match. |
| 5 | `6M-Admin-Platform-APIs.md` (95 literals, corpus-wide within 6M) | `…/organizations/{id}`, `…/recordings/{id}/access`, `…/plans/{id}`, `…/users/{id}`, `…/sessions/{id}`, `…/api-keys/{id}`, `…/commercial-pricing-agreements/{id}`, `…/workflow-executions/{id}`, `…/transcripts/{id}/access`, `…/refunds/{id}` | `{organization_id}`, `{recording_id}`, `{plan_id}`, `{user_id}`, `{session_id}`, `{api_key_id}`, `{agreement_id}`, `{workflow_execution_id}`, `{transcript_id}`, `{refund_id}` | 6A's resource-specific parameter naming is the corpus convention and 6B already declares `{organization_id}` for the sibling resource. A non-descriptive `{id}` is not merely a style choice on a **normative endpoint inventory**: 6M's §25 inventory and §27.2 matrix are the platform surface's contract of record, and leaving two competing conventions live would push the decision onto a later index document. Normalized at source instead — see §3.3. |

Post-fix residual check for the prefix family: **0** remaining `/internal/v1/` occurrences that are not `/api/internal/v1/`, corpus-wide.

### 3.2 Divergences deliberately **not** changed, with reasons

| # | Divergence | Why left as-is |
|---|---|---|
| 1 | *(withdrawn — this row previously deferred 6M's `{id}` convention to the API Master Index)* | **No longer a deliberate non-change.** The DB-conformant closure directive required `FAR-P3-03` to be **closed here, not carried as an open reconciliation ticket**. It is closed by **Option A** — normalizing 6M's normative endpoint inventory and matrices to 6A's descriptive parameter names — recorded as §3.1 row 5 and detailed in §3.3. |
| 2 | `{id}` shorthand inside prose, auth matrices and error tables where the same document declares the canonical `{descriptive_id}` elsewhere. | Narrative shorthand, not a declaration. Changing it would touch dozens of frozen documents for zero contract effect. The Master Index must read the **declaration**, not the prose, as canonical — stated explicitly here so that rule is not left implicit. |
| 3 | 6L's `{cc_id}` for 6H's `{campaign_contact_id}`; 6J's `{slug}` for its own `{provider_slug}`. | Same reason as #2 — both documents declare the long form in their own inventories. |
| 4 | `{any}` (6B line 2341), `{toolX}` (6D §18.1), `{predecessor_id}` (6G §23). | **Not parameter names at all** — respectively a principal-matrix prose token meaning "any org", a worked-example tool instance, and a worked-example Contact in the merge narrative. Pure extraction artifacts. |

**Method, singular/plural and resource-name spelling:** no inconsistency found. Every collision group's members agree on HTTP method; no group was found mixing singular/plural of the same resource (`/agents`, `/calls`, `/contacts`, `/campaigns`, `/tools`, `/conversations`, `/recordings`, `/invoices`, `/workflows`, `/webhook-endpoints`, `/webhook-deliveries` are plural in every document that uses them).

---

### 3.3 `FAR-P3-03` closure — 6M path-parameter normalization (Option A)

`FAR-P3-03` recorded that 6M spelled its platform-admin path parameters `{id}` while 6A's convention and 6B's sibling routes use resource-specific names. Two closure options existed:

| Option | Action | Verdict |
|---|---|---|
| **A** | Normalize 6M's **normative** endpoint inventory and matrices to 6A's resource-specific parameter names | **SELECTED.** 6A is frozen and is the naming authority for the corpus; the divergence sat in a normative inventory, not in prose. |
| B | Declare `{id}` acceptable on the platform surface and record a permanent two-convention rule | Rejected — it would make the corpus permanently ambiguous and would contradict a frozen document to accommodate a later one. |

**Canonical rule applied:** 6A's resource-specific parameter naming governs. The names used are the ones the owning documents already declare for those resources: `{organization_id}`, `{recording_id}`, `{transcript_id}`, `{refund_id}`, `{plan_id}`, `{agreement_id}`, `{workflow_execution_id}`, `{user_id}`, `{session_id}`, `{api_key_id}`.

**What actually changed in 6M:** 95 `{id}` literals normalized; **0 remain**. The edit is a literal-spelling normalization only — no route added, removed, split, merged or re-scoped. Verified after the edit: the §25 endpoint inventory still carries **42** one-route-per-row entries and §27.2 still carries **42**, matching each other exactly as before. A labelled *FINAL API RECONCILIATION — path-parameter normalization* note was added above the §25 inventory so the change is disclosed at source rather than appearing as silent drift.

**Effect on §2's collision ledger: none.** Pass-B normalization already collapses every `{anything}` segment to `{param}`, so semantic collision grouping is invariant under this rename; the 55 groups are unchanged. Pass-A literal variance decreases, which is the point. The `/api/v1/platform-admin` prefix continues to separate these routes from 6C's tenant `/api/v1/organizations/{organization_id}/suspend` and 6L's tenant `/api/v1/audit/events` — the surfaces differ by **prefix**, never by parameter name (§2.1 rows 8 and 47).

**§3.2 rows 2–4 are unaffected** and remain deliberate non-changes: they concern narrative shorthand and worked-example tokens inside documents whose own declarations already carry the long form, not normative inventories.

---

## 4. Auth Contradiction Ledger

| # | Surface | Documents | Principal / Role | Permission / Scope | Difference | Verdict | Status |
|---|---|---|---|---|---|---|---|
| 1 | `GET /api/v1/auth/me` vs. `GET /api/v1/users/me` | 6B (owner), 6C | Authenticated user | session/identity read vs. tenant-profile read | Different resources, both intentional | 6C discloses the split explicitly; no competing declaration | **NO CONTRADICTION** |
| 2 | `POST /api/v1/organizations/{organization_id}/suspend` vs. `POST /api/v1/platform-admin/organizations/{id}/suspend` | 6C (owner), 6M (owner of the platform route) | `OWNER` vs. `PLATFORM_ADMIN` | tenant self-service vs. cross-tenant forced action | Different paths, different principals, different purposes | Not the same route (§2.1 row 47); 6M's shorthand disambiguated this pass (§12 edit #4) | **NO CONTRADICTION** |
| 3 | Break-glass grant/release + `sessions/revoke-all` | 6B (owner), 6M | `PLATFORM_ADMIN` under break-glass grant | identical in both | None — 6M reuses 6B's frozen contract verbatim | 6M line 234 discloses and retracts an earlier draft's competing route, reclassifying its rows to "REUSED EXISTING 6B"; 6M's `identity.fn_platform_revoke_all_sessions()` narrows its own DB grants to match 6B | **NO CONTRADICTION** |
| 4 | `GET /api/v1/audit/events` (6L, tenant) vs. `GET /api/v1/platform-admin/audit/events` (6M, platform) | 6L, 6M | tenant principal + `audit:read` (RLS-filtered) vs. `PLATFORM_ADMIN` (cross-tenant) | different scopes on one audit substrate | Different routes; clean tenant/platform split | §2.1 row 8; 6M shorthand note added (§12 edit #4) | **NO CONTRADICTION** |
| 5 | `GET /api/v1/suppressions/check` | 6G (owner), 6H | — | — | A **transport-boundary** rule, not an auth rule: 6H is forbidden to call it over HTTP and must use the in-process `EffectiveSuppressionService.check()` | DEP-6G-11 / ADR-6H-04 / ADR-6G-14 — both sides agree in writing | **NO CONTRADICTION** |
| 6 | `POST /api/v1/agents`, `POST /api/v1/agents/{agent_id}/clone` | 6E (owner), 6K | **`agent:write`** (unchanged) | unchanged by `FAR-OD-01` | Option B adds a **commercial admission check**, not an authorization change | 6E §43.9 states authorization, RLS and audit behaviour are unchanged; the quota check runs *after* authorization | **NO CONTRADICTION** |
| 7 | `is_platform_admin()` fail-open defect | 6B, 6M | `PLATFORM_ADMIN` | — | Historical defect found during 6M's design | Fixed via existing migration `106_5H3.sql` and reconciled into 6B's dependency register (5th pass) — disclosed and closed | **CLOSED, NOT LIVE** |
| 8 | **Invitation acceptance ownership** — `POST /api/v1/auth/invitations/accept` vs. 6C's `/organizations/{organization_id}/invitations*` | 6B (owner of acceptance), 6C (owner of creation/list/resend/cancel) | unauthenticated token-bearer at acceptance; `member:invite`-holding tenant principal at creation | token redemption + membership activation + session issuance vs. ordinary tenant RBAC | Two halves of one flow, split across two documents — a classic place for a competing re-declaration | 6B §3.2 carves the creation half out explicitly; 6C §9.5/§10 consumes 6B's acceptance endpoint unmodified and never re-declares it. The security-relevant half is reconciled in state, not just in prose: a pending invitation is `status='SUSPENDED', accepted_at IS NULL`, and `POST .../reactivate` is guarded by `WHERE status='SUSPENDED' AND accepted_at IS NOT NULL` — so the membership API **cannot** be used to bypass token redemption | **NO CONTRADICTION** |
| 9 | **API-key scope ceiling** — every tenant route reachable by an API key | 6B (owner, §16.4), consumed by 6C, 6D, 6E, 6F, 6G, 6H, 6K, 6L | `API_KEY` | `effective permissions = key.scopes ∩ issuer's own permissions at issuance` | A ceiling, not a grant: a key can never exceed its issuer, and its `scopes` never widen implicitly | No document was found treating a key's `scopes` as additive or as implying an unlisted permission. 6C §17's matrix shows the canonical denial (`scopes=['member:read']` → `member:suspend` → `403`); 6D §43 restates the same ceiling for sensitive media without redefining it | **NO CONTRADICTION** |
| 10 | **Internal-service routes** — `/api/internal/v1/...` | 6A (owner, §8.5/§23.4), used by 6C, 6D, 6H, 6I, 6J | `INTERNAL_SERVICE` (`auth_method` ∈ 6B §9.2's five-value set) | internal service-principal mechanism — **never** tenant JWT, never an API key | A distinct principal type, not a privileged tenant | 6A states it once: never in the public OpenAPI surface, never tenant-JWT-authenticated, excluded from the tenant rate-limit/quota system (fixed internal ceiling instead). 6C §15.31–§15.32 consumes exactly that and adds "no fallback to a user/API-key credential". `actor_type` maps onto 5J's existing `WORKER \| SYSTEM \| PLATFORM_ADMIN \| INTEGRATION` vocabulary — no new principal type invented | **NO CONTRADICTION** |
| 11 | **Provider / payment webhook principals** — `POST /webhooks/voice/{provider_slug}/events` (6D) and the payment-provider webhook (6K §30) | 6A (owner of the carve-out, §28.2), 6D, 6K | the **provider**, not a tenant | provider-native signature verification (per-adapter HMAC in the Telephony ACL; `PaymentProviderPort.verify_webhook` for payments) | Inbound webhooks are authenticated by signature and are deliberately outside tenant JWT/API-key auth — this is 6A's own explicit carve-out, invoked identically by both consumers | Neither document invented a second inbound-webhook mechanism: 6D records into the existing `webhooks.inbound_webhook_events` with `UNIQUE (organization_id, provider_slug, provider_event_id)`; 6K persists a receipt **only after** verification succeeds and resolves tenant identity server-side from the originating attempt, never from the payload's own claimed identity | **NO CONTRADICTION** |
| 12 | **Platform Admin vs. tenant `ADMIN`** — every `/api/v1/platform-admin/*` route vs. every tenant route | 6B (owner of the trust model, §18.3a/§31), 6M, 6C | `PLATFORM_ADMIN` claim vs. tenant `OWNER`/`ADMIN` org role | two **disjoint** authorization systems, not two tiers of one | The single most collision-prone boundary in the corpus — a platform role that silently satisfied tenant RBAC (or vice versa) would be a P0 | Both directions are stated and neither is implicit. Downward: a `PLATFORM_ADMIN` without a break-glass grant calling any tenant-scoped `/organizations/{organization_id}/*` route gets `403` — "platform-admin status alone never satisfies tenant RBAC" (6C §17, restating 6B unmodified). Upward: a tenant principal — human **or** API key — calling a `/platform-admin/*` route gets `403 TENANT_PRINCIPAL_FORBIDDEN`, rejected at the application router **before any DB session is established** | **NO CONTRADICTION** |
| 13 | **Tenant API key on a Platform Admin route** | 6M (§27.1), 6B | `API_KEY` | denied **unconditionally** | Not a scope question at all — there is no Platform-Admin-scoped API key concept in this system, so no `scopes` array can ever satisfy these routes | 6M's principal matrix marks `API_KEY` "✗, unconditionally" on every `/platform-admin/*` row, and states the reason rather than leaving it to inference. This is strictly stronger than the §9 ceiling and does not contradict it: the ceiling bounds what a key *can* carry; this rule says the route is unreachable regardless | **NO CONTRADICTION** |
| 14 | **Break-glass issuance and release** — `POST /platform-admin/organizations/{organization_id}/break-glass`, `POST /platform-admin/break-glass/{grant_id}/release` | 6B (owner of the contract), 6M (reuses it) | `PLATFORM_ADMIN` | `is_platform_admin()` re-checked **inside** `organization.fn_break_glass_grant` / `fn_break_glass_release`; `app_api` explicitly revoked by `107_5B5` | Layered, never substitutive: a break-glass grant is an *additional* gate on top of the `PLATFORM_ADMIN` ALLOW, and never a substitute for it | 6M marks both routes "REUSED EXISTING 6B" and cites 6B §21.4/§21.35 endpoint-for-endpoint. Purpose scoping is enforced server-side — every consuming function passes its own **hardcoded** `p_required_purpose` literal to `fn_break_glass_check`, so a `SUPPORT_BILLING` grant can never be reused to justify a `SENSITIVE_MEDIA_ACCESS` read, and the required purpose is never client-suppliable | **NO CONTRADICTION** |
| 15 | **Sensitive recording access** — tenant `GET /recordings/{recording_id}/download-url` (6D) vs. platform `POST /platform-admin/recordings/{recording_id}/access` (6M) | 6D (tenant), 6M (platform) | tenant principal + `recording:access_media` vs. `PLATFORM_ADMIN` + `SENSITIVE_MEDIA_ACCESS` break-glass grant | `recording:access_media` (new, `104_5B3.sql`; `OWNER`/`ADMIN` only, never `VIEWER`/`BILLING_ADMIN`) vs. grant-gated platform path | Two different principals reaching the same bytes by two deliberately different gates | Not one gate with two spellings: the tenant path is a permission upgrade over `recording:read` (which no longer suffices) and is **audited on success only**, emitting `RECORDING_ACCESS_GRANTED` and never including the signed URL in the snapshot; the platform path additionally requires a durable, purpose-bound, releasable grant re-checked per access, with its audit write fused into the same transaction. An API key must list `recording:access_media` explicitly — `call:read`/`recording:read` never widens into it | **NO CONTRADICTION** |
| 16 | **Sensitive transcript access** — `GET /conversations/{conversation_id}/transcript/segments` (6D) vs. `POST /platform-admin/transcripts/{transcript_id}/access` (6M) | 6D, 6M | as row 15 | `transcript:access_content` (new, `104_5B3.sql`) — **identical shape** to `recording:access_media` | Same split, same gates, deliberately symmetric | 6D §17.4 gates segment `text` (`pii:voice`) on `transcript:access_content` while `transcript:read` continues to gate metadata only, with its existing grant set unchanged — and 6D corrected its own prior, inaccurate claim about `VIEWER` rather than bending the permission to the claim. The documented audit asymmetry with the recording case (no per-request audit here) is stated as a deliberate choice, not left as a silent difference | **NO CONTRADICTION** |
| 17 | **`analytics_platform:read` — the platform-only boundary** | 6L (owner, §11/§26), 6M (consumer) | platform operator only | granted to **zero** tenant system roles in the executed seed | The risk was a permission that *exists* in the catalog being reachable from a tenant role by accident | 6L verified against the executed seed that it is assigned to none of `OWNER`/`ADMIN`/`MEMBER`/`BILLING_ADMIN`/`VIEWER`, and consequently treats any endpoint requiring it as **not** part of the tenant-facing `/api/v1/analytics/*` surface — which is why no tenant cost endpoint exists (`DEC-6L-02` = Option A). 6M's `GET /platform-admin/analytics/financial` consumes it through 6L's projection port and never queries billing OLTP directly. The cache key folds the caller's compiled permission set in, so a response generated for a caller without it can never be served to one with it | **NO CONTRADICTION** |

**Zero unresolved auth contradictions across all 17 rows.** No `TBD`, `UNKNOWN` or `OWNER DECISION REQUIRED` entry remains in this ledger.

Scope note, restated deliberately: this is a **contradiction** ledger, not an authorization matrix. Each row exists because two or more documents touch one authorization surface and could have disagreed. Rows are adjudicated for agreement only — the complete per-route × per-principal matrix is the Global Authorization Matrix's job and is **not** constructed here.

---

## 5. Error Semantic Ledger

Per the governing scope, corpus-wide error codes were examined **only** to hunt for cross-document conflicts. No standalone catalog was compiled (explicitly forbidden — that is the Global Error Catalog's job, not this pass's).

| # | Code | HTTP status | Owning doc | Meaning | Also referenced by | Same semantic everywhere? | Status |
|---|---|---|---|---|---|---|---|
| 1 | `QUOTA_EXCEEDED` | `429` | **6K** (§36) | Commercial quota/entitlement limit reached; the operation is refused, not retried | 6E §43.6 (new this pass) | **Yes** — 6E reuses 6K's code and status verbatim; no new code invented | **CLOSED** |
| 2 | `AGENT_NOT_PUBLISHED` | `409` | **6D** (§27.2) | Call initiation refused because the referenced Agent version is not `PUBLISHED` | 6E line 988 (disclaimer only) | Yes — 6E explicitly states it never returns this code, because no 6E endpoint initiates a call | **CLOSED** |
| 3 | Suppression / consent errors | `403`/`409` | **6G** | contact-level suppression and consent violations | 6H | Yes — 6H consumes 6G's semantics via the in-process service, not via HTTP | **CLOSED** |
| 4 | Call state-machine errors | `409` | **6D** | illegal call-state transitions | 6H, 6I | Yes — both invoke 6D's mechanism rather than defining their own | **CLOSED** |
| 5 | Async-job envelope (`202 Accepted` + `job_id`) | `202` | **6A** (§18.3) | platform-wide long-running-operation convention | 6J | Yes, with one **disclosed bounded deviation**: 6J's `job_id` is a Celery task ID, not a persisted row — declared as an API-DESIGN DEPENDENCY under 6A §18.3's own explicit allowance | **CLOSED (disclosed deviation)** |
| 6 | Signed-URL / sensitive-response logging rule | n/a | **6A** | responses carrying signed URLs must not be body-logged | 6D (`recordings/{recording_id}/download-url`) | Yes — 6D explicitly disables body logging for that response class | **CLOSED** |
| 7 | Permission strings touched by this pass (`agent:write`, `campaign:read`, `call:read`, `audit:read`, `organization:suspend`-family) | n/a | respective owners | — | — | Yes — consistent naming and consistent tenant-vs-platform scoping across every document that shares them | **CLOSED** |
| 8 | `AUTHENTICATION_REQUIRED` | `401` | **6A** (§24.2) | The credential is absent, malformed, expired or revoked — resolved at the authentication layer, **before** any permission evaluation | 6B (owner of the mechanism), and every document exposing an authenticated route | **Yes** — one code, one status, one layer. No document defines a competing "not logged in" code, and none splits it by credential type: an expired API key, a revoked refresh token and a missing `Authorization` header are deliberately indistinguishable to the client | **CLOSED** |
| 9 | `AUTHORIZATION_DENIED` | `403` | **6A** (§24.2) | An authenticated principal lacks the required permission for this resource | 6B, 6C, 6D, 6E, 6F, 6G, 6H, 6K, 6L | **Yes** — and, importantly, the same code covers the API-key **scope-ceiling** denial (6B §16.4) rather than a separate code that would tell a caller *why* it failed. Cross-tenant requests resolve to `404`, not `403`, everywhere — a deliberate non-disclosure rule, applied consistently | **CLOSED** |
| 10 | `BREAK_GLASS_GRANT_INVALID` | `403` | **6B** (§18.3a) | Any break-glass runtime-authorization failure — missing header, grant not found, expired, released, wrong org, wrong admin, wrong session — **deliberately collapsed into one non-distinguishing code** | 6M | **Yes, after a correction made in 6M's own closure pass.** 6M previously defined a 6M-local `BREAK_GLASS_GRANT_REQUIRED` for exactly this condition and reconciled it onto 6B's canonical code — a rename, not a new or removed condition; client-visible behaviour is identical. 6M's own sweep of its `BREAK_GLASS_*`/`PLAN_*`/`CREDIT_*`/`BILLING_ADJUSTMENT_*`/`REFUND_*`/`TAX_*` codes against 6A and 6B found this to be the **only** reuse required | **CLOSED (collision found and removed at source)** |
| 11 | `IDEMPOTENCY_KEY_REUSE_MISMATCH` | `409` | **6A** (§16.2) | Same `Idempotency-Key`, materially different request body | 6D, 6E, 6F, 6H, 6J, 6K | **Yes** — every consumer reproduces 6A's three-outcome rule identically (same key + same fingerprint → replay the cached response; same key + different body → this code; no key → normal processing). No document narrows the key scope `(organization_id, principal_id, endpoint, Idempotency-Key)` or alters the 24-hour TTL. `FAR-OD-01`'s quota interaction (§10.7) changes the *outcome semantics* of a replay, never the key contract | **CLOSED** |
| 12 | `RATE_LIMIT_EXCEEDED` vs. `QUOTA_EXCEEDED` — the **429 dual-use** | `429` (both) | **6A** (§20) and **6K** (§36) respectively | Request-**rate** limiting (a transient traffic control: retry later and it succeeds) vs. commercial **quota**/entitlement (a business-state refusal: retrying changes nothing until state or plan changes) | 6A, 6K, 6E (via `FAR-OD-01`) | **Yes — the shared status is permitted precisely because the bodies are unambiguous.** The two are distinguished by `error.code`, and by retry semantics: `RATE_LIMIT_EXCEEDED` carries `Retry-After` and is retryable; `QUOTA_EXCEEDED` is **not** retryable in the same sense and carries no `Retry-After` promise that the same request will later succeed. They are also governed by different systems entirely — L1/L2 buckets vs. `billing.quota_configs` — and 6A §20 already separates internal traffic and outbound webhook delivery from the tenant rate-limit system. A client can therefore always tell "slow down" from "you are out of Agents" without inspecting anything but the body | **CLOSED (dual use, disambiguated)** |
| 13 | Payment-failure and provider-webhook-failure conditions | `4xx`/`5xx` per condition | **6K** (§30, §31) | Provider-side settlement failures and inbound-webhook processing failures | 6M (consumer) | **Yes** — and the security-relevant rule is uniform: a webhook whose signature fails verification is **discarded and logged**, never reaching a domain command, and **no receipt row is ever created for it**. Forged and replayed events are handled by signature verification plus uniqueness, not by an error code. `PAYMENT_ATTEMPTED`/`PAYMENT_SUCCEEDED`/`PAYMENT_FAILED` are audit vocabulary, not client error codes — the two are not conflated | **CLOSED** |
| 14 | `REFUND_NOT_ALLOWED`, `REFUND_AMOUNT_EXCEEDED` | `409` (both) | **6K** (§31) | No `SUCCEEDED` payment to refund against; refund would exceed the refundable balance (`fn_validate_refund_amount`) | 6M (internal/platform surface only) | **Yes** — both are explicitly marked internal/6M-only in 6K's own catalog, and 6M consumes them without redefining either. The refundable-balance invariant is enforced in the database, not merely documented, so the error code reports a DB-enforced refusal rather than a hopeful application check | **CLOSED** |
| 15 | Sensitive-media authorization failures | `403` (permission), `403 BREAK_GLASS_GRANT_INVALID` (platform path), `404` (unavailable) | **6D** (tenant), **6M** (platform) | Denial of recording bytes / transcript text | 6L (references only) | **Yes** — with one deliberate asymmetry that is *documented rather than accidental*: on the tenant path, a denial produces **no audit event** (no signed URL was minted, so there is nothing to record as granted), whereas a success does. `404 RECORDING_NOT_AVAILABLE` is a resource-state answer (`status != 'STORED'`), not an authorization answer, and authorization is checked **strictly before** the availability check and before any URL signing | **CLOSED** |
| 16 | Generic families — `VALIDATION_ERROR` (`422`), `RESOURCE_NOT_FOUND` (`404`), `STATE_CONFLICT` (`409`), `PRECONDITION_FAILED` (`412`), `PAYLOAD_TOO_LARGE` (`413`), `DEPENDENCY_UNAVAILABLE` (`502`/`503`), `INTERNAL_ERROR` (`500`) | as listed | **6A** (§24.2) | the platform-wide error families every document draws from | all 12 downstream documents | **Yes** — spot-checked in every document that enumerates its own error surface (6E §33, 6F §54, 6K §35, 6M §26). Downstream documents **select from** this list and add domain codes alongside it; none redefines a family's status, and none was found using a family name for a different meaning. `STATE_CONFLICT` consistently carries `error.details.current_state` on guarded transitions | **CLOSED** |

**Across all 16 rows, no two documents were found using the same code string for different semantics.** One genuine collision was found and removed **at source** rather than being adjudicated in this ledger — 6M's local `BREAK_GLASS_GRANT_REQUIRED`, reconciled onto 6B's canonical `BREAK_GLASS_GRANT_INVALID` (row 10). In particular, `FAR-OD-01` deliberately introduced **no** new error code (§10.6): the hard Agent quota reuses 6K's existing `QUOTA_EXCEEDED` verbatim, and the database signals refusal with SQLSTATE `53400`, which the API layer maps onto that existing code.

Scope note: this ledger reconciles **shared** codes for conflicts. It is not, and must not be read as, the corpus-wide error catalog — that remains the Global Error Catalog's job and is **not** constructed here.

---

## 6. DTO / Contract Ledger

| # | Shared object | Declared once by | Referenced (never re-declared) by | Divergence found | Status |
|---|---|---|---|---|---|
| 1 | Response envelope `{data, meta}` | 6A | all 12 downstream documents | None — no downstream document silently diverges from 6A's envelope | **CLOSED** |
| 2 | Cursor-pagination contract | 6A | all documents exposing list endpoints | None | **CLOSED** |
| 3 | Idempotency-Key handling and scope `(organization_id, principal_id, endpoint, Idempotency-Key)` | 6A §16 | 6D, 6E, 6H, 6J, 6K | None — 6E §43.7 extends the *interaction* with quota (§10.7) without altering the key scope or the 24-hour TTL | **CLOSED** |
| 4 | Agent / AgentVersion | 6E (ADR-6E-01) | 6D, 6H, 6K | None | **CLOSED** |
| 5 | Call / Conversation / Transcript / Recording | 6D | 6E, 6H, 6I, 6L | None | **CLOSED** |
| 6 | Contact / Activity / Suppression | 6G | 6H | None | **CLOSED** |
| 7 | Campaign / CampaignContact / call-report | 6H | 6L | None — 6L links to 6H's composition rather than projecting it (ADR-6L-15) | **CLOSED** |
| 8 | Organization / compliance-policy | 6C | 6D, 6H | None after §12 edit #1 (literal parameter corrected) | **CLOSED** |
| 9 | Quota / usage / invoice records | 6K | 6L, and 6E (`ACTIVE_AGENTS` only, new this pass) | None — 6E consumes 6K's metric definition; 6K §52.3 states the counted set precisely so there is exactly one definition | **CLOSED** |
| 10 | `credential_reference` shape for `WebhookNodeConfig` / `ApiCallNodeConfig` | 6J (contract) → 6I (implementation) | — | None — 6I §67 adds exactly the three fields 6J specified | **CLOSED** |
| 11 | **Error envelope** `{error: {code, message, details?, request_id}}` | 6A §24.1 | all 12 downstream documents | None — every document that enumerates its own error surface emits 6A's envelope shape unchanged and adds domain codes *inside* it, never alongside it. `error.details.current_state` on guarded transitions is a consistent `STATE_CONFLICT` convention, not a competing envelope | **CLOSED** |
| 12 | **Authentication context / principal shape** — `principal_type`, `auth_method ∈ {PASSWORD, OAUTH_<PROVIDER>, API_KEY, INTERNAL_SERVICE, PLATFORM_ADMIN}`, compiled permission set | 6B §9.2 | 6A (actor mapping onto 5J's `WORKER \| SYSTEM \| PLATFORM_ADMIN \| INTEGRATION`), 6C, 6D, 6L, 6M | None — no document invents a sixth `auth_method`, and no document re-derives permissions locally instead of consuming the compiled set. 6L folds the caller's compiled permission set into its analytics cache key rather than defining a parallel notion of "caller identity" | **CLOSED** |
| 13 | **Break-glass grant** — grant id, target organization, purpose (`<@` allow-list), TTL bounded to `[60, 86400]`, release state | 6B §18.3a/§21.4 | 6M | None — 6M reuses 6B's endpoints and the same `organization.fn_break_glass_grant` / `fn_break_glass_release` functions, and never carries a client-supplied `required_purpose`: each guarded function passes its own hardcoded purpose literal to `fn_break_glass_check` | **CLOSED** |
| 14 | **Signed-URL response** for sensitive media | 6D §17 | 6M (platform access path) | None — one shape, one TTL contract, and one uniform logging rule: the signed URL itself is **never** written into an audit snapshot, a log line, or an analytics projection by either consumer | **CLOSED** |
| 15 | **Inbound provider-webhook envelope** — `webhooks.inbound_webhook_events` row, deduplicated on `UNIQUE (organization_id, provider_slug, provider_event_id)` | 6D §12 (voice providers); 6K §30 applies the same shape to payment providers | 6H, 6M | None — the payment case adds a verification-first ordering rule (no receipt row unless the signature verifies) and resolves tenant identity from the originating attempt row rather than the payload, which *strengthens* the shared contract without forking it | **CLOSED** |
| 16 | **Outbound webhook delivery envelope** — 5I `webhooks.webhook_deliveries`, HMAC-SHA256 over `ts={unix}.{payload_json}`, header `X-Platform-Signature: v1={hex}` | 6A §11/§22 | 6D, 6H, 6K | None — consumers name event types (`call.completed`, `campaign.finished`, `invoice.generated`) but none redefines the signature scheme, the `PENDING → DELIVERING → DELIVERED \| DEAD_LETTER \| CANCELLED` lifecycle, or the retry contract | **CLOSED** |

**Zero cross-document DTO conflicts across all 16 rows.** Per the governing scope rule, rows were added only where a shared contract sits behind one of the accepted 55 collision groups and was not already represented — this ledger is a conflict register, not an exhaustive schema inventory.

---

## 7. Event / Audit / Outbox Ledger

**Class vocabulary — these five mechanisms are deliberately distinct and are not interchangeable:**

| Class | Substrate | Consumer | Delivery semantics |
|---|---|---|---|
| **AUDIT** | `audit.audit_events` via `audit.fn_insert_audit_event(...)` | compliance / forensic readers (6L tenant read, 6M platform read) | durable, append-only, immutable record of *who did what* |
| **DOMAIN EVENT** | a business fact published for other bounded contexts | internal consumers only | fact-of-record; never a tenant-facing notification |
| **OUTBOX** | `audit.domain_event_outbox` + `fn_claim_outbox_events` / `fn_mark_outbox_published` / `fn_mark_outbox_failed` | the relay worker | the *transport* that makes a domain event durable — written in the producing transaction, published after commit, at-least-once |
| **WEBHOOK** | 5I `webhooks.webhook_deliveries` (outbound) / `webhooks.inbound_webhook_events` (inbound) | tenant-owned external systems (outbound); providers (inbound) | HMAC-signed, retried with backoff, dead-lettered; ordering **not** guaranteed across event types |
| **REALTIME** | `/ws/v1/voice/...` WebSocket session | a live, connected client | ephemeral, in-session, **not** durable, and never a record of anything |

A single operation routinely produces rows in several classes. The purpose of this ledger is to confirm that each document places each surface in the *same* class as every other document touching it, and that no document substitutes one class for another.

| # | Surface | AUDIT | DOMAIN EVENT / OUTBOX | WEBHOOK | REALTIME | Owning doc | Participating | Divergence | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Durable domain-event publication (the mechanism itself) | — | `audit.domain_event_outbox` + claim/publish/fail functions | — | — | 6C | 6D, 6E, 6H, 6J, 6K, 6M | None — no document was found bypassing the outbox with a direct cross-context write, and none introduced a second outbox | **CLOSED** |
| 2 | Audit-event writes (the mechanism itself) | `audit.fn_insert_audit_event(...)`, used uniformly | — | — | — | 6C / 6D correction | all | None. `action_kind` is constrained only by `CHECK (length BETWEEN 1 AND 200)`, so new values are pure vocabulary additions requiring no migration — and every document treats them that way rather than proposing schema changes | **CLOSED** |
| 3 | **Organization creation follow-up** | `ORGANIZATION_CREATED` | `organization.created` via outbox | — | — | 6C | 6K (subscription / quota provisioning), 6M | None — downstream provisioning consumes the event; it is not performed synchronously inside the creation request, and no second trigger mechanism was introduced | **CLOSED** |
| 4 | **Forced session revocation** (break-glass and admin-initiated) | `BREAK_GLASS_GRANTED` / `BREAK_GLASS_RELEASED`, written **synchronously** — the single documented exception to 6B's otherwise-async audit posture | session-revocation event on the same outbox, written in the same transaction as the CAS session update | — | — | 6M (reusing 5L's amendment) | 6B | None — closed without a new table. The synchronous-audit exception is stated as a deliberate choice in 6B, not discovered as an inconsistency here | **CLOSED** |
| 5 | **Agent creation** (`POST /agents`, `POST /agents/{agent_id}/clone`) under `FAR-OD-01` | `AGENT_CREATED` | `agent.created` via outbox | — | — | 6E §43.4/§43.9 | 6K | None — audit row, outbox row and the `voice.agents` INSERT are written in **one** transaction. A quota rejection rolls the whole transaction back, so a refused creation emits **neither** an audit row nor an outbox row; validated live (§16.2, cases C and D, and the `1/1/1` vs `0/0/0` integrity check) | **CLOSED** |
| 6 | **Call lifecycle / initiation** | `CALL_INITIATED` and terminal-state audit | `call.started`, `call.ended`, `conversation.qualification_set` via outbox — internal domain events | `call.completed` may be delivered outbound to tenant systems | in-session events over `/ws/v1/voice/...` | 6D | 6H, 6I, 6K, 6L | None, and the class split is explicit exactly where it matters most: 6H states that `call.ended` / `conversation.qualification_set` arrive as **internal domain events over the outbox**, *not* as tenant-facing signed webhooks. The realtime channel carries the live conversation; it is never the record of it | **CLOSED** |
| 7 | **Campaign dispatch** | `CAMPAIGN_CREATED`, dispatch-state audit | `campaign.created` and dispatch events via outbox, written outside the single `INSERT` but within the documented creation flow | `campaign.finished` outbound | — | 6H | 6G, 6L | None — and the Redis executor lock `campaign:lock:{campaign_id}` (SETNX + TTL) is documented as **Layer 1 only**, explicitly *not* the correctness guarantee; Layer 2 database idempotency is. A cache lock is never presented as a durability or exactly-once mechanism | **CLOSED** |
| 8 | **Workflow execution** | execution-lifecycle audit | workflow node / execution events via outbox | webhook **nodes** inside a workflow are a tenant-authored integration — a separate concern from platform outbound webhooks, and not conflated with them | — | 6I / 6J | 6D | None — the one-ACTIVE-per-session invariant lives in `workflow.fn_start_workflow_execution` (the same `SECURITY DEFINER` + advisory-lock pattern migration `110_5C2` follows), enforced by the database rather than by an event | **CLOSED** |
| 9 | **Knowledge ingestion** | ingestion-job audit | ingestion / indexing events via outbox | — | — | 6F | 6E | None — long-running ingestion reports through 6A's async-job `202` envelope, not through a bespoke progress channel | **CLOSED** |
| 10 | **Billing usage recording** | usage-adjustment audit where a human acts | usage arrives **only** as domain events, consumed into `billing.usage_events` | — | — | 6K | 6D, 6H, 6I, 6L | None, and it is enforced rather than merely asserted: billing does not query voice / CRM / campaign / knowledge / workflow tables directly, and `REVOKE INSERT ON billing.usage_events FROM app_api` closes the API-layer shortcut structurally | **CLOSED** |
| 11 | **Payment webhook settlement** | `PAYMENT_ATTEMPTED` / `PAYMENT_SUCCEEDED` / `PAYMENT_FAILED` (5J §14.3 vocabulary) | settlement events via outbox | **inbound** provider webhook, signature-verified via `PaymentProviderPort.verify_webhook` | — | 6K §30 | 6M | None — the receipt function is a durability / dedup layer and is explicitly **never** a security boundary; an unverified webhook is discarded with no receipt row. Tenant identity is resolved server-side from the originating attempt row, never from the payload (the confused-deputy correction) | **CLOSED** |
| 12 | **Refund saga** | `REFUND_ISSUED`, plus `REFUND_RESERVED` / `REFUND_SETTLED` / `REFUND_FAILED` action kinds | saga step transitions via outbox | inbound provider confirmation | — | 6K §31 | 6M | None — idempotency rests on `UNIQUE (payment_provider, provider_refund_id)` and the refundable-balance invariant on `fn_validate_refund_amount`. The saga's steps are events; the money-safety invariants are database constraints. The two are not conflated | **CLOSED** |
| 13 | **Sensitive-media access** | `RECORDING_ACCESS_GRANTED` on success (tenant path); grant-gated platform access audited in the same transaction | — | — | — | 6D §17 / 6M | 6L | None — audit only, deliberately: no domain event, no outbox row, no webhook. The signed URL is never recorded in the snapshot. The documented asymmetry (transcript segments carry no per-request audit) is disclosed in 6D as a considered decision rather than left implicit | **CLOSED** |
| 14 | **Outbound webhook delivery** | delivery-configuration changes audited | the outbox feeds delivery; the two are distinct stages, not one mechanism | 5I `webhooks.webhook_deliveries`: HMAC-SHA256 `X-Platform-Signature: v1={hex}`, 10 s timeout, exponential backoff, `max_attempts` default 7 (range 1–10), then `DEAD_LETTER` | — | 6A §11/§22 | 6D, 6H, 6K | None — governed by its own retry / backoff contract and explicitly **excluded** from the tenant request-rate-limit system, so a tenant's 429 budget is never consumed by platform-initiated deliveries. The table is append-only and DELETE is never exposed (`405`). At-least-once with dead-lettering; cross-type ordering is explicitly not promised | **CLOSED** |
| 15 | **Realtime voice channel** (`/ws/v1/voice/...`) | — | — | — | connection lifecycle, message envelope and catalog, barge-in / TTS cancellation, reconnect and backpressure | 6D §13 | 6A (generic envelope) | None — 6D instantiates the generic realtime envelope 6A §27.3 deliberately declined to fill in, rather than competing with it. No document treats a delivered realtime frame as a durable record | **CLOSED** |
| 16 | Tenant vs. platform audit **read** surfaces | RLS-filtered tenant read vs. cross-tenant platform read | — | — | — | 6L / 6M | — | None — a scope split on one substrate, not two audit designs | **CLOSED** |

**Zero divergences across all 16 rows, and zero class conflations.** No document was found treating a cache lock as durability, an outbox row as a tenant notification, a realtime frame as a record, or a webhook receipt as an authorization decision.

---

## 8. PostgreSQL Baseline Ledger

Unchanged from the prior pass; re-verified, no new work required. Current authoritative baseline is **PostgreSQL 18** per `MIGRATION_MANIFEST.md`; genuine historical validation evidence (what was actually tested on PostgreSQL 16/16.10, and when) is **preserved verbatim everywhere** — no blanket replace was performed in any document.

| Document | PG16 mentions | Classification | Action |
|---|---|---|---|
| 6D | Yes (§28.10a) | Historical validation evidence (preserved) + one live-baseline-claim phrase | **Corrected earlier in this pass** — §1a amendment added (§12 edit #6) |
| 6H | Yes (§5, findings 22–28, Revisions 4–7) | Same mix | **Corrected earlier in this pass** — §1a amendment added (§12 edit #6) |
| 6I | Yes | Pure historical evidence | No action |
| 6J | Yes (§63) | Already self-corrected by 6J | No action |
| 6K, 6L, 6M | Yes | Already PostgreSQL-18-native | No action |
| 6A, 6B, 6C, 6E, 6F, 6G | None | N/A | No action |

---

## 9. Handoff Closure Ledger

| # | Handoff | From → To | Item | Evidence | Status |
|---|---|---|---|---|---|
| 1 | **`DEP-6E-20`** | **6E → 6K** | **Agent-count quota (FR-TEN-005) not enforced by any 6E endpoint** | **Owner decision `FAR-OD-01` = Option B, applied in full: 6E §43 (§43.1–§43.11) declares hard synchronous enforcement on `POST /agents` and `POST /agents/{agent_id}/clone`; 6K §52 states the `ACTIVE_AGENTS` counted-state set and confirms the error contract. 6E §38's register row now reads "RESOLVED BY OWNER DECISION `FAR-OD-01` — OPTION B", Blocking: No.** | **CLOSED (§10)** |
| 2 | Compliance-policy internal endpoint | 6C → 6D / 6H | consumers must not re-declare 6C's internal contract | §2.1 row 3; 6H's literal corrected this pass (§12 edit #1) | **CLOSED** |
| 3 | `GET /suppressions/check` in-process boundary | 6G → 6H | HTTP call forbidden; in-process service required | DEP-6G-11 RESOLVED-from-6G's-side / ADR-6H-04 / ADR-6G-14 | **CLOSED** |
| 4 | Platform audit-event exploration | 6L §61 → 6M | 6L named a platform-scope audit gap | 6M built `GET /api/v1/platform-admin/audit/events` explicitly to satisfy it — a model closure: a concrete endpoint linked back to the originating document's named item | **CLOSED** |
| 5 | Break-glass durable revocation | 6B `DEP-6B-01`/`DEP-6B-08` → 6M | durable delivery of forced-revocation events | `identity.fn_platform_revoke_all_sessions()` writes to the existing outbox in the same transaction as the CAS update — no new table | **CLOSED** |
| 6 | `credential_reference` field shape | 6J `DEP-6J-12` → 6I | three named fields on two node configs | 6I §67 amendment; 6J Document Control updated; 6J line 2687 confirms "Zero P0. Zero implementation-blocking P1." | **CLOSED** |
| 7 | Async-job status convention | 6A §18.3 → 6J | `GET /api/v1/jobs/{job_id}` semantics | 6J consumes the convention and discloses its bounded deviation (Celery task ID) under 6A's own allowance | **CLOSED (disclosed deviation)** |
| 8 | **`DEP-6E-20` — database-layer continuation** | **Phase 6 (API design) → Phase 5 (database)**, under the owner authorization granted for this pass only | `FAR-OD-01` settled the *policy* (Option B, hard synchronous quota), but the API-layer enforcement mechanism was not legal under frozen 6A §17.3 — raised here as `FAR-P1-01` / `DB-BLOCKER-FINAL-API-001` | **CLOSED BY MIGRATION `110_5C2`** — serialization moved inside a Phase-5 `SECURITY DEFINER` boundary, raw `INSERT ON voice.agents` revoked from every runtime role, both Agent-creating operations routed through the same guard, and the whole path validated live (§16.2). Nothing is carried forward as future debt | **CLOSED** |

*(Historical — 110/111 passes:)* ~~Zero open handoffs across all 8 rows. Zero pending owner decisions.~~ This line described only the eight cross-document handoffs traced in the rows above. It was **not** a whole-corpus classification. `FAR-P2-06` found that wording overbroad, and it is superseded by the full 213-item classification in §9.1–§9.5. The eight rows above stay CLOSED and are counted inside §9.3.

### 9.1 `FAR-P2-06` — whole-corpus handoff classification: method and dedupe

Every deferred, future, handoff, residual or open item declared anywhere in 6A–6M was classified into exactly one class:

| Class | Meaning |
|---|---|
| **CLOSED** | Resolved by an executed amendment, migration or explicit closure text in the source document, or a retracted/retired item. |
| **FUTURE — NON-BLOCKING** | A disclosed, deliberately not-designed capability or residual. It needs no V1 API contract change, and no V1 endpoint depends on it. |
| **RELEASE-TRAIN** | Not an API-design blocker, but it must be delivered or validated before a V1 release. It must **not** be demoted to future debt. |
| **IMPLEMENTATION-READINESS** | The API contract is complete. What remains is an implementation-phase build/validation dependency, such as a producer, runtime value, vendor verification or service build-out. |
| **BLOCKER** | Prevents API-contract closure. |

**Dedupe methodology.**
1. **Anchoring.** Every item is anchored to one source document plus a text pattern that must match that document's current text. Items without a match are rejected, so the ledger cannot drift from the documents.
2. **DEP coverage.** The complete set of `DEP-6X-NN` identifiers was extracted from every register row **and** every prose mention across 6A–6M. That gives **142** unique IDs: 141 register rows plus the row-less retired mention `DEP-6G-17`. Classification was asserted to cover all 142, with none missing and none extra.
3. **Non-DEP registers.** These cover 6A §R-1..R-8, 6B §34, 6D/6E §3.2, 6H ADR/§18.4 residuals, 6I §54 (rows 1–14), 6J §57 (J1–J4), 6K §54.5/§54.6, 6L §55/§61/ODD-5J-01..07, and 6M §46/§51/§52/§53. There were **85** such entries.
4. **Explicit `same_as`.** When the same item appears in two registers (for example 6A R-5 and `DEP-6D-10`), the later entry is collapsed onto the canonical one with an explicit `same_as` link. A duplicate must carry the **same class** as its canonical item, and chains are not allowed. **14** duplicates were collapsed.
5. **Closure-word cross-check.** Every CLOSED item was checked for closure wording in its full source line, and every non-CLOSED item was checked for the absence of it. Each flag was reviewed by hand against the source: `DEP-6E-03` (resolved by 6I §54 row 9), `DEP-6E-04` (resolved by 6F §21), `DEP-6F-11` (6I via the 6F service), `DEP-6G-02` ("closed by classification") and `DEP-6G-15` (6L COVERED). **Residual flags: 0.**
6. **Reclassification recorded.** `DEP-6G-14` (`contact.converted` billing consumption) is **FUTURE**, not CLOSED, because 6K never consumes it. `DEP-6E-16` is **FUTURE** because it is mitigated on the output side only.
7. The classifier ran only from the session scratchpad **outside the repository**. No script was added to the repo.

**Arithmetic.** Raw entries = 142 DEP + 85 non-DEP = **227** (CLOSED 107, FUTURE 92, RELEASE-TRAIN 4, IMPLEMENTATION-READINESS 24). Subtracting the 14 `same_as` duplicates (2 CLOSED, 8 FUTURE, 4 IMPLEMENTATION-READINESS) leaves **213 unique items**.

### 9.2 `DEP-*` register items (142), grouped by document and class

| Doc | CLOSED | FUTURE — NON-BLOCKING | RELEASE-TRAIN | IMPLEMENTATION-READINESS | Total |
|---|---|---|---|---|---:|
| 6B | 01, 02, 08 *(08 = RESOLVED Phase 5L via outbox reuse, `077_5J1`)* | 03 MFA recovery · 05 phone verification · 06 CAPTCHA / adaptive challenge | — | 04 OAuth2/OIDC IdP integration · 07 central internal token issuer build-out | 8 |
| 6C | 02, 07, 10, 11, 14, 15, 16 | 01 org reactivation · 03 `team:*` permission · 04 team-membership cascade (narrowed) · 05 `user_preferences` · 06 email change · 08 cancellation→billing cascade · 09 member reactivation permission (narrowed) · 13 concurrent-invitation constraint | — | 12 invitation resend token invalidation | 16 |
| 6D | 04, 09, 13, 14 | 01 call-control permissions · 02 `tool:*` permission · 03 `phone_number:*` permission · 06 tenant ProviderConfig CRUD · 07 phone-number provisioning · 12 Agent archival/delete | **11 per-stage latency budget / provider benchmark validation** | 05 ring/hold runtime timers · 08 `TtsPort.cancel()` live-provider validation · 10 TTS fallback vendor | 14 |
| 6E | 01, 03, 04, 05, 06, 07, 13, 15, 17, 18, 19, 20, 21, 22, 23, 24 *(20 = `FAR-OD-01`)* | 02 `prompt_ref` existence validation · 08 tool permission reuse · 09 preview/test/validate · 10 ProviderConfig CRUD · 11 provider/model compatibility · 12 LanguageEvaluationRecord residuals · 14 Agent archival · **16 `qualification_criteria` (output-side mitigation only)** | — | — | 24 |
| 6F | 01, 02, 03, 09, 11, 14, 15, 16 | 04 `knowledge_base_refs` validation · 05 embedding-model registry · 12 Knowledge analytics (→6L) · 13 knowledge-provider plugins (→6J) | — | 06 prompt-injection mechanism · 07 malware scanner · 08 crawler implementation · 10 embedding quota integration | 16 |
| 6G | 01, 02, 03, 06, 07, 09, 10, 11, 15, 17 *(retired, row-less)*, 18 | 04 manual score override · 05 Company delete · 08 PLATFORM/REGULATORY suppression admin · 12 external CRM sync · 13 Voice outcome fields · 14 `contact.converted` billing · 16 node executors (→6I) | — | — | 18 |
| 6H | 01, 02, 03, 04, 12, 15, 18–29 | 05 `action_kind` vocabulary · 06 list source · 07 list rename · 08 import cancel/retry · 09 outcome index · 10 CampaignContact command · 13 `CostLookupPort` / cost · 14 outcome comparison analytics · 16 affordability pre-flight · 17 campaign budget | **11 DNC dispatch-proof logging (legal/product)** | — | 29 |
| 6J | 01, 02, 04, 05, 06, 09, 10, 11, 12 | 03 `external_account_ref` uniqueness · 07 webhook auto-suspend · 08 definition metadata columns | — | — | 12 |
| 6K | — | 03 manual billing-account suspend/reactivate override (6M) · 04 6C tax-profile endpoint | — | 01 `TOOL_EXECUTIONS` producer · 02 `KNOWLEDGE_RETRIEVALS` producer · 05 workflow-completion payload discriminator | 5 |
| **Σ** | **76** | **51** | **2** | **13** | **142** |

### 9.3 Non-`DEP` register items (71 unique of 85 entries)

| Doc / register | CLOSED | FUTURE — NON-BLOCKING | RELEASE-TRAIN | IMPLEMENTATION-READINESS | Collapsed `same_as` |
|---|---|---|---|---|---|
| 6A risks R-1..R-8 | R-1 WebSocket vs Socket.IO · R-2 service-to-service auth | R-3 India data residency · R-7 weak ETag | — | R-4 Redis pool defaults · R-6 async SLA placeholders | R-5 → `DEP-6D-10` · R-8 → `DEP-6B-06` |
| 6B | — | §34 custom per-membership permissions | — | — | MFA recovery → 03 · IdP → 04 · phone verification → 05 · CAPTCHA → 06 · internal token issuer → 07 · audit vocabulary Tier 2 → 02 |
| 6C | — | — | — | — | invitation resend token invalidation → `DEP-6C-12` |
| 6D | §3.2 out-of-scope contexts | — | — | — | — |
| 6E | — | §3.2 Prompt Management | — | — | — |
| 6H | — | campaign DELETE not exposed · recurring campaigns (ADR-6H-09) · telephony provider-side ambiguity residual (§18.4) | — | — | — |
| 6I §54 rows 1–14 | 4 WorkflowTrigger absent · 6 side-effecting node idempotency · 7 platform-admin DML bypass · 8 checkpoint ordering · 12 billing token-cost dependency | 1 ADR-5G-010 prompt-version pinning · 2 partition automation · 3 `started_at` pruning · 11 publish idempotency replay strength · 13 node-level analytics telemetry · 14 admin stuck-workflow intervention | — | 5 WEBHOOK/API_CALL execution (egress runtime, 6J) · 10 campaign↔workflow ACL | 9 → `DEP-6E-03` |
| 6J §57 | — | J1 multiple connections per provider · J2 private-network egress allow-list · J3 plugin marketplace · J4 integration usage billable | — | — | — |
| 6K §54 | — | §54.6 inbound calls under `CONCURRENT_CALLS` governance | — | §54.5 capacity runtime (reservation store, grace period, reconciler cadence) | — |
| 6L | §61.1 cross-tenant sensitive-media support access | §61.2 campaign cost attribution · §55-11 historical archive API · §61.3 A AI-assisted setup · B advanced agent config · C preview/test · D controlled deployment snapshots · ODD-5J-01..07 (7) | **§61.3 E SIP trunk support (V1 requirement)** | §55-5 10 of 12 projection-population functions | §55-16 campaign ROI on billed spend → §61.2 |
| 6M §52 | provider health · cross-tenant revenue/margin · internal financial analytics · analytics ingestion diagnostics · analytics dead-letter inspection · retention administration · platform audit-event exploration · audit-chain verification · recording support · transcript support | — | — | historical rebuild/backfill control | — |
| 6M §53 | plan/plan-version/plan-price admin · pricing agreement admin · pricing activation · tax config · manual credits · billing adjustments · refunds · payment-attempt diagnostics · stuck payment webhook receipt visibility · payment reconciliation status | — | — | — | billing-account manual override → `DEP-6K-03` |
| 6M §46 / §51 | — | §46 cross-tenant admin webhook replay (DBGAP-6M-04) · §51 FR-ADM-001 mutable system configuration | **§46 FR-FLAG-001 feature-flag persistence / CRUD (DBGAP-6M-01)** | — | manual suspend override → `DEP-6K-03` · stuck-workflow intervention (DBGAP-6M-05) → 6I §54-14 |
| **Σ** | **29** | **33** | **2** | **7** | **14** |

### 9.4 Totals

| Class | DEP | Non-DEP | **Unique total** |
|---|---:|---:|---:|
| CLOSED | 76 | 29 | **105** |
| FUTURE — NON-BLOCKING | 51 | 33 | **84** |
| RELEASE-TRAIN | 2 | 2 | **4** |
| IMPLEMENTATION-READINESS | 13 | 7 | **20** |
| BLOCKER | 0 | 0 | **0** |
| **Total** | **142** | **71** | **213** |

105 + 84 + 4 + 20 + 0 = **213**. **Non-closed = 108** (84 + 4 + 20). The 108 non-closed items are **disclosed and registered** (§11), not hidden. None is described as implemented.

**RELEASE-TRAIN (4):** `DEP-6D-11` voice latency / provider benchmark validation · `DEP-6H-11` DNC dispatch-proof logging (legal) · 6L §61.3 E **SIP trunk support (V1)** · `FR-FLAG-001` / `DBGAP-6M-01` feature-flag persistence / CRUD.

**IMPLEMENTATION-READINESS (20):** `DEP-6B-04`, `DEP-6B-07`, `DEP-6C-12`, `DEP-6D-05`, `DEP-6D-08`, `DEP-6D-10`, `DEP-6F-06`, `DEP-6F-07`, `DEP-6F-08`, `DEP-6F-10`, `DEP-6K-01`, `DEP-6K-02`, `DEP-6K-05`; 6A R-4, 6A R-6; 6I §54-5, 6I §54-10; 6K §54.5; 6L §55-5; 6M §52 historical rebuild/backfill.

### 9.5 Result

**ZERO BLOCKING HANDOFFS.** 108 items remain open but none blocks, broken down as 84 FUTURE — NON-BLOCKING, 4 RELEASE-TRAIN and 20 IMPLEMENTATION-READINESS. The register does **not** claim zero open handoffs. **`FAR-P2-06` is CLOSED** (§13).

---

## 10. `FAR-OD-01` = OPTION B — Hard Synchronous Agent-Count Quota (enforcement contract of record)

**Owner decision (binding):** `POST /api/v1/agents` **MUST** synchronously enforce the organization's effective Agent-count quota. At the limit, the Agent **MUST NOT** be created. The check is server-side, inside the authoritative transaction, using 6K's canonical commercial authority, and trusts **no** client-supplied value.

Recorded at source in **6E §43** (lines 1510–1638) and **6K §52** (lines 3485–3526). This section is the reconciliation-level record of *why* that contract is sound; it does not restate it in full.

### 10.1 Database-capability verification — result: **`DB-BLOCKER-FINAL-API-001` RAISED, then RESOLVED BY MIGRATION `110_5C2`**

> **Correction of an earlier conclusion in this document.** A previous revision of §10.1 concluded "**NO BLOCKER**" on the ground that an existing serialization *primitive* (`pg_advisory_xact_lock`) was present in the executed schema. That reasoning was wrong, and it is corrected here rather than quietly dropped: **an existing primitive is not an existing compliant enforcement path.** The primitive was present, but the only place the design could issue it from was the API/service/repository layer, and frozen **6A §17.3** forbids the API tier from taking an application-level lock of its own. A design that can only be made to work by contradicting a frozen document is a genuine gap, not a style deviation — so the gap is a **database blocker**, `DB-BLOCKER-FINAL-API-001`, and the mis-severity `FAR-P3-02` is reclassified to **`FAR-P1-01`** (§13).

The required invariant is **hard, synchronous, server-authoritative `ACTIVE_AGENTS` admission with concurrency safety**, reachable by both Agent-creating operations and bypassable by neither. Candidates evaluated against the executed Phase 5 artifacts:

| Candidate primitive | Verdict | Reason |
|---|---|---|
| Naïve `SELECT COUNT(*)` → compare → `INSERT` | **Rejected** | Two concurrent transactions both read `count = N-1` under READ COMMITTED and both commit. This is exactly the pattern the instruction declares unacceptable. |
| `SELECT … FOR UPDATE` on `billing.quota_configs` | **Impossible** | PostgreSQL requires `UPDATE` privilege to take a row lock via `FOR UPDATE`. `app_api` holds **`SELECT` only** on that table in the executed grants. Not a preference — a hard privilege bar. |
| `SELECT … FOR UPDATE` on `billing.billing_accounts` | **Unsound** | The row is not guaranteed to exist for every organization at Agent-creation time; a lock anchor that may be absent cannot serialize the first concurrent pair. |
| `SERIALIZABLE` isolation | **Rejected** | Correct in principle, but the corpus defines **no** `40001` serialization-failure retry contract at the API layer. Adopting it would silently introduce a new client-visible failure mode that no document specifies. |
| `pg_advisory_xact_lock(hashtext(...))` **issued by the API layer** | **REJECTED — conflicts with frozen 6A §17.3** | The primitive itself is the already-established project pattern — `workflow.fn_start_workflow_execution()` in `041_5G.sql` uses precisely `v_lock_key := hashtext(p_organization_id::text \|\| ':' \|\| p_session_ref::text); PERFORM pg_advisory_xact_lock(v_lock_key);`. But in that precedent the lock is taken **inside** a `SECURITY DEFINER` function. Issuing it from the API/service/repository tier is what 6A §17.3 prohibits, and 6A is frozen and was **not** weakened to legalise it. |
| Raw `INSERT INTO voice.agents` left available to `app_api` alongside any guard | **REJECTED** | A guard that a legitimate raw-INSERT path can walk around is not a hard quota. Structural enforceability requires that the guard be the **sole** insert path. |
| **New `SECURITY DEFINER` guarded functions in one additive migration** | **SELECTED — implemented as `110_5C2`** | Matches `041_5G.sql` exactly in shape: `voice.fn_create_agent()` and `voice.fn_clone_agent()` both call the shared `voice.fn_assert_agent_quota_admission()`, which takes the transaction-scoped advisory lock **inside the database**, resolves the effective hard limit from `billing.quota_configs` server-side, counts the canonical set and raises **before** any INSERT. `REVOKE INSERT ON voice.agents FROM app_api, app_worker, app_platform_admin;` makes those functions the only insert path. `REVOKE ALL … FROM PUBLIC` on every new function; `EXECUTE` granted to `app_api` only. |

**Conclusion: the executed schema did *not* supply a compliant enforcement path, so `DB-BLOCKER-FINAL-API-001` was raised.** It is **RESOLVED** by exactly one additive migration, **`110_5C2`** (historical, as of the 110 pass: at that time the only new migration authorized and no `111` existed; superseded by `111_5H4` §10A and `112_5H5` §10B), validated live against PostgreSQL 18.6 on disposable databases — fresh `001 → 110`, incremental `109 → 110`, single head `110_5C2`, a ten-case live two-process concurrency battery and a privilege/RLS-bypass battery (§16). Migrations `001`–`109` and their Alembic wrappers are byte-identical to `HEAD`.

**`FAR-P1-01` is therefore CLOSED, not carried as future debt**, and the previously-registered `FR-DB-001` is removed from §11 because `110_5C2` implements exactly that remediation.

### 10.2 The counted set — derived, not chosen

6E §43.2 / 6K §52.3 fix the `ACTIVE_AGENTS` counted set as:

```sql
SELECT COUNT(*) FROM voice.agents
WHERE organization_id = :org
  AND status IN ('DRAFT','PUBLISHED')
  AND deleted_at IS NULL
```

The lifecycle is `DRAFT | PUBLISHED | DEPRECATED` (`chk_agents_status`). Each membership decision is **forced by the frozen documents**, not selected by this pass:

- **`DRAFT` must count.** `POST /agents` creates a `DRAFT` row. If `DRAFT` did not count, the owner's gate would be a no-op on the very endpoint the decision governs.
- **`PUBLISHED` must count.** It is the revenue-bearing state; excluding it is incoherent with a commercial quota.
- **`DEPRECATED` must not count.** `DEPRECATED` is terminal, and `DEP-6E-14` records that **no** delete or archive endpoint exists and `deleted_at` is never populated by any endpoint. If `DEPRECATED` counted, an organization that reached its limit could never create another Agent by any available API action — the quota would become a permanent lockout with no user-reachable remedy.

6K's §21.1 row previously said only "`COUNT` of `voice.agents` in a billable state", which is imprecise. Per the instruction not to decide this silently, the imprecision is recorded as **`FAR-P2-02`** (§13) and the precise set is now stated in 6K itself (§52.3) so there is exactly one definition.

### 10.3 Effective-quota resolution — server-side only

Resolved inside the same transaction from 6K's commercial authority: `PlanVersion` entitlement → `CommercialPricingAgreement` overlay (where present) → the versioned terms in force at request time. Per 6K §25.1 as corrected, `overage_allowed = (hard_limit IS NULL)`, full stop — so a `NULL` hard limit means unlimited and the check is skipped; a non-`NULL` hard limit is enforced.

**The client MUST NOT submit, and the server MUST ignore, any client-supplied `agent_limit`, `quota_limit`, `plan_limit` or `current_agent_count`.** Stated normatively in 6E §43.3.

### 10.4 Serialization proof

```sql
BEGIN;
  SET LOCAL app.tenant_id = :organization_id;
  -- The API layer takes NO application-level lock of its own (6A §17.3).
  -- It calls the guarded function; serialization, quota resolution, the
  -- count and the INSERT all happen inside the database, atomically.
  SELECT voice.fn_create_agent(:organization_id, :actor_user_id, :name, :description);
  -- On success: exactly one DRAFT voice.agents row exists and its id is returned.
  --   No voice.agent_versions row is created (versions are publish-only).
  -- On refusal: the function raises SQLSTATE 53400, which the API layer maps
  --   to 6K's canonical 429 QUOTA_EXCEEDED; the transaction rolls back and no
  --   row, audit entry or outbox record is written.
  -- Same transaction, same connection: AGENT_CREATED audit row + agent.created
  --   outbox row (the existing transactional-outbox mechanism; no second one).
COMMIT;
```

Inside `voice.fn_create_agent()` / `voice.fn_clone_agent()`, the shared `voice.fn_assert_agent_quota_admission(p_organization_id)` performs, in order: derive the tenant from `organization.current_tenant_id()` server-side and cross-check the supplied `organization_id` against it; `PERFORM pg_catalog.pg_advisory_xact_lock(...)` on a per-organization key; resolve `billing.quota_configs.hard_limit` for the in-force row; `COUNT` the §10.2 set; `RAISE` with SQLSTATE `53400` if `counted >= hard_limit`. Because the lock is acquired **before** the count and released only at `COMMIT`/`ROLLBACK`, count-then-insert is atomic against every competing transaction for the same organization.

**Why more than N can never commit, for quota N:** every transaction that can insert a quota-counted row must go through a guarded function — raw `INSERT` on `voice.agents` is revoked from every application role — and each such function first acquires the *same* advisory lock key for that organization, so all such transactions for one organization are totally ordered. Within a holder's critical section, the `COUNT` observes every previously **committed** insert (the previous holder released the lock only at `COMMIT`/`ROLLBACK`, so its insert is already visible to the next holder under READ COMMITTED). A transaction inserts only when `counted < hard_limit`, so the committed count increases by at most one per holder and can never pass `hard_limit`. Rolled-back transactions release the lock and leave the count unchanged. The lock key is per-organization, so tenants never serialize against each other.

**6A §17.3 is satisfied without an exception.** Every advisory-lock use in the schema — including this one — sits *inside* a `SECURITY DEFINER`-reached Phase 5 function. The API/service/repository layer executes **no** `SELECT pg_advisory_xact_lock(...)` of its own on this path; it issues one `SELECT voice.fn_create_agent(...)` / `voice.fn_clone_agent(...)` call. There is no disclosed deviation left on this contract: `FAR-P3-02` is superseded by `FAR-P1-01`, which is **CLOSED BY MIGRATION `110_5C2`** (§13).

### 10.5 Concurrency cases (normative — 6E §43.5)

| Case | Scenario | Required outcome |
|---|---|---|
| **1** | Two concurrent creations, org is **below** the limit with ≥2 free slots | **Both succeed.** Serialized, both observe `counted < hard_limit`. |
| **2** | Two concurrent creations, **exactly one** free slot | **Exactly one succeeds; the other returns `429 QUOTA_EXCEEDED`.** The loser observes the winner's committed row. |
| **3** | Creation attempted while **already at** the limit | **Refused with `429 QUOTA_EXCEEDED`. No row is created**, and no audit/outbox row is emitted. |
| **4** | **Idempotent replay** of a successful creation (same `Idempotency-Key`) | **The stored response is returned; no second quota slot is consumed and no second row is created** (§10.7). |
| **5** | Creation transaction **rolls back** after passing the check (any later failure) | **No slot is consumed.** The advisory lock taken inside the guarded function is transaction-scoped, so it is released at `ROLLBACK`, the insert never became visible, and the next holder's `COUNT` is unchanged. Verified live (evidence battery case D). |

### 10.6 Error contract — reused, not invented

`429 QUOTA_EXCEEDED` — **6K's existing canonical quota error (§36)**, reused verbatim by 6E §43.6. No new code, no new status.

The governing instruction's caution is honoured explicitly: a commercial quota is **not** a rate limit, and `429` is used here **only because 6K already assigns `429` to `QUOTA_EXCEEDED`** as its canonical commercial-quota refusal. Because the two share a status code, 6E §43.6 requires the response body's error code (`QUOTA_EXCEEDED`, not a rate-limit code) to be the discriminator, and requires that no rate-limit `Retry-After` semantics be implied — the condition is not cleared by waiting, only by deprecating an Agent or raising the plan.

### 10.7 Idempotency interaction (6E §43.7)

Idempotency uses 6A §16's unchanged scope `(organization_id, principal_id, endpoint, Idempotency-Key)` with Redis as primary store and a 24-hour TTL. A replay of a **successful** creation returns the stored response **without re-entering the quota critical section**, so a replay can never consume a second slot. A replay of a **`429`-refused** attempt is not a completed operation: it re-enters the check, and may legitimately succeed if a slot has since been released (§10.8). This asymmetry is stated in 6E §43.7 so implementers do not cache the refusal as a terminal idempotent result.

### 10.8 Slot-release semantics (derived, not guessed)

Derived from 6K's `ACTIVE_AGENTS` counted set (§10.2) combined with 6E's lifecycle: **`POST /api/v1/agents/{agent_id}/deprecate` is the sole slot-release path.** Moving a row from `PUBLISHED` (or `DRAFT`) to the terminal `DEPRECATED` state removes it from the counted set and frees exactly one slot, effective immediately for the next transaction to take the lock. There is no delete path and no archive path (`DEP-6E-14`), and `deleted_at` is never populated — so the `deleted_at IS NULL` predicate in §10.2 is defensive, not load-bearing, today. The semantic is therefore **defined**, and no blocking issue was raised on this point.

### 10.9 OpenAPI implementation readiness — `POST /api/v1/agents`

No OpenAPI document is generated here (out of scope). What a generator will need is now unambiguous at source:

| Element | State | Ready |
|---|---|---|
| Route literal, method | `POST /api/v1/agents` — single canonical declaration in 6E | ✅ |
| Request body | 6E's existing Agent-creation schema, **unchanged**; no quota field added, and client-supplied limit/count fields are explicitly forbidden (§10.3) | ✅ |
| Success response | `201` with 6A's `{data, meta}` envelope, unchanged | ✅ |
| Quota-refusal response | `429`, body error code `QUOTA_EXCEEDED`, 6K §36's shape | ✅ |
| Authorization | **`agent:write`**, unchanged (§4 row 6) — the canonical 5B catalog string; `agent:create` / `agents:write` do not exist (§4 row 7) | ✅ |
| Headers | `Idempotency-Key` per 6A §16, unchanged | ✅ |
| Enforcement note | Server-side only, **inside the database**: the API layer calls `voice.fn_create_agent()` / `voice.fn_clone_agent()` and takes no lock of its own (6E §43.4; frozen 6A §17.3). Nothing about the lock is client-visible | ✅ |
| `POST /api/v1/agents/{agent_id}/clone` | Same quota contract, same error (6E §43.8) | ✅ |

---

## 10A. `FAR-OD-02` = OPTION B — Temporary Quota Overrides With Live Baseline Fallback

Owner decision **`FAR-OD-02` = Option B**: a Platform Admin quota override is a **true temporary
grant**. It does not edit, replace or consume the commercial quota it overrides. The commercial
quota stays live underneath it and is what the tenant returns to. This section is the contract of
record; it is carried by migration **`111_5H4`** and live-validated in §16.3.

### 10A.1 The two persistence layers, and the one resolver

| Concern | Where it lives | Who may write it |
|---|---|---|
| **Commercial / base quota** — the quota the tenant is entitled to under its plan or agreement | `billing.quota_configs` | The existing commercial/billing path. Unchanged by this pass |
| **Temporary admin override** — a time-boxed grant layered on top | `billing.quota_overrides` (**new**, additive, created by `111_5H4`) | Platform Admin only, through `billing.fn_platform_set_quota_override(...)`. No application role holds `INSERT` / `UPDATE` / `DELETE` on the table |
| **Effective quota** — what any consumer must actually enforce and report | Nothing. It is **computed**, never stored | `billing.fn_resolve_effective_quota(organization_id, metric)` — the single resolver |

**The override never overwrites the base.** Setting, superseding or expiring an override makes no
change whatsoever to `billing.quota_configs`. The two layers are separate rows in separate tables,
and this is the whole point of Option B: Option A (overwrite-in-place) would have destroyed the
commercial value the tenant returns to, which is exactly the defect recorded as `FAR-P1-05`.

### 10A.2 Resolution order — normative

`billing.fn_resolve_effective_quota(p_organization_id UUID, p_metric TEXT)` resolves, in order:

1. **An active, non-superseded Platform Admin override** — `superseded_at IS NULL` and not expired.
   Source reported as `PLATFORM_OVERRIDE`.
2. **Otherwise the CURRENT commercial/base quota** row in `billing.quota_configs`. Source reported
   as `BASE`.
3. **Otherwise no configured quota.** This is *not* "unlimited". It is the absence of a
   configuration, and every consumer must treat it as such under its own contract.

The resolver is `SECURITY INVOKER`, `STABLE`, with `SET search_path = billing, organization,
pg_catalog`. It requires **no** administrative privilege: `app_api`, `app_worker` and
`app_readonly` all resolve effective quota directly (§16.3, Battery J).

### 10A.3 The lifecycle rules that make "temporary" mean temporary

| Rule | Normative statement |
|---|---|
| **Expiry falls back to the CURRENT base** | When an override expires, the effective quota becomes the **current** value of `billing.quota_configs` — **not** a stale historical base captured when the override was written, **not** the previous superseded override, and **not** unlimited. If the base was changed while the override was active, the **new** base is what takes effect at expiry (Battery B4/B5: base raised 1000 → 1200 under an active override of 2000; at expiry the effective quota is **1200**) |
| **Expiry is read-time** | Evaluated against `NOW()` = `transaction_timestamp()`. There is no sweeper job and no background state mutation. An effective quota is therefore stable within a transaction, and an expiry becomes visible to the **next** transaction |
| **A permanent override is `expires_at IS NULL`** | `NULL` here means *permanent until superseded*. It does **not** mean expired, and it does not mean unlimited |
| **A superseded override never reactivates** | Supersession is one-way and terminal. The previous current row is stamped `superseded_at` and the replacement inserted under one advisory lock in one transaction. No later expiry, deletion or edit can bring a superseded row back into effect |
| **`hard_limit IS NULL` means unlimited** | On the **effective** result, a `NULL` `hard_limit` is unlimited, and that is exactly what `overage_allowed` reports. This is a property of the resolved value, not a restriction on what may be stored — `hard_limit` is deliberately left nullable and limits are `NUMERIC(18,4)`, compared **as stored** and never rounded |
| **The audit record is transactional** | The `QUOTA_OVERRIDE_SET` row in `audit.audit_events` is written inside the **same** transaction as the override row. A rolled-back override leaves no audit trace, and an audited override always exists |

Structural guarantee: the partial unique index
`uq_qo_org_metric_current ON billing.quota_overrides (organization_id, metric) WHERE superseded_at IS NULL`
makes a second *current* row for the same `(organization, metric)` impossible — `23505` — rather
than merely discouraged.

### 10A.4 Metric vocabulary — canonical, and not aliased

The override layer is constrained to the **canonical 15-metric 5H §11.1 vocabulary**:

`CALL_MINUTES`, `AI_MINUTES`, `STT_SECONDS`, `TTS_CHARACTERS`, `LLM_PROMPT_TOKENS`,
`LLM_COMPLETION_TOKENS`, `EMBEDDING_TOKENS`, `CAMPAIGN_CALLS`, `WORKFLOW_EXECUTIONS`,
`TOOL_EXECUTIONS`, `KNOWLEDGE_RETRIEVALS`, `STORAGE_GB`, `API_REQUESTS`, **`ACTIVE_AGENTS`**,
`ACTIVE_PHONE_NUMBERS`.

All 15 are accepted; **0** are missing. Enforcement is at two independent layers — the function
layer (`P0001`) and the table layer (`23514 / chk_qo_metric_canonical`) — so the constraint does
not depend on callers going through the function.

**`AGENT_COUNT` is rejected, not aliased.** The legacy name evaluates **false** against
`billing.fn_is_canonical_usage_metric()`; `ACTIVE_AGENTS` evaluates **true**. No silent
translation layer was introduced, as the governing directive required. A caller using the legacy
vocabulary gets an error, not a quiet remapping to a different metric.

Scope boundary, stated plainly: this canonical constraint binds the **override** layer.
`billing.quota_configs.metric` remains plain `TEXT NOT NULL` with no CHECK (`052_5H.sql:7`), and
this pass did **not** retro-constrain it — that would not be additive, and no owner decision
authorized it.

### 10A.5 Every consumer reads the resolver — no second source of truth

| Consumer | Contract |
|---|---|
| **`ACTIVE_AGENTS` admission** (`POST /agents`, `POST /agents/{agent_id}/clone`) | `voice.fn_assert_agent_quota_admission()` continues to use the concurrency-safe database guard established by `110_5C2` — the advisory lock, the canonical counted set `{DRAFT, PUBLISHED} ∧ deleted_at IS NULL`, and the `(active + 1) > hard_limit` comparison. **`111_5H4` changes only the quota SOURCE**, from a direct `billing.quota_configs` read to `billing.fn_resolve_effective_quota()`. The clone path reads the **same** resolver as the create path |
| **Tenant `GET /billing/quotas`** (6K §53) | Reports **effective** values — the override when one is active, the base otherwise — with the source labelled. A tenant never has to hold Platform Admin privilege to learn its own effective quota, and tenant isolation is unchanged (RLS **FORCED**; Battery J proves isolation in both directions) |
| **Platform Admin `GET`** (6M §66.3) | Lists override **history and states** — `ACTIVE`, `EXPIRED`, `SUPERSEDED` — as actual rows, superseding §18's older `quota_configs`-only read model. It is a read model over `billing.quota_overrides`, not a second authority |
| **Any Redis / cache / snapshot layer** | Must derive from the **same effective semantics**. A cache may store the resolved value; it may not invent a different resolution order, and it may not treat "no configured quota" as unlimited. The database is the authority; caches are projections of it |

**No client controls quota or pricing authority.** The override write path is Platform-Admin-only
and `SECURITY DEFINER`; `app_api` holds **no** `EXECUTE` on it (the 107-era grant is gone).

### 10A.6 The lower-limit contract is non-destructive

When the effective limit drops below current usage — by expiry, by supersession, or by a
deliberately lower override — the database **closes admission only**:

- New `ACTIVE_AGENTS` admissions are refused with `53400`.
- **No existing Agent is deleted, deprecated or soft-deleted.** Measured: `auto_deprecated = 0`,
  `soft_deleted_rows = 0`.
- Publishing remains **count-neutral** — an existing Agent may still transition
  `DRAFT → PUBLISHED` while the tenant is over limit, because publishing does not add a row to
  the counted set.
- The state is fully recoverable: a new override re-opens admission without touching customer data.

The database never destroys, deprecates or mutates customer Agents or phone numbers to make a
quota true. Reconciling usage down to a lower limit is a product/commercial decision surfaced
through the API, not a database side effect.

### 10A.7 Why `FAR-P1-04` and `FAR-P1-05` were genuine P1 findings

Both were **reproduced from the committed sources** before `111_5H4` was written. Neither is a
reviewer assertion, and neither is cosmetic.

**`FAR-P1-04` — metric-vocabulary regression (P1, not P2).** `107_5B5` issued a
`CREATE OR REPLACE` of `billing.fn_platform_set_quota_override()` carrying a hard-coded legacy
metric list. Set arithmetic against the **live** function, not against documentation, showed:

```
legacy_107_size = 15 | canonical_5h_size = 15 | intersection = 2
legacy_only = 13     | canonical_absent_from_107 = 13
```

Only `CALL_MINUTES` and `STORAGE_GB` were reachable through both vocabularies. **Thirteen of the
fifteen canonical metrics — `ACTIVE_AGENTS` among them — could not be overridden at all.** This is
P1 because the owner decision `FAR-OD-01` depends on `ACTIVE_AGENTS` being an overridable quota:
the executed schema silently could not express the metric the entire Option-B enforcement contract
is built on. A documentation-only divergence would have been P2; an enforcement path that cannot
name its own metric is a defect in the contract itself.

**`FAR-P1-05` — base-quota overwrite and fail-open on expiry (P1).** Two compounding defects in
the pre-`111` behaviour:

1. `106`/`107` wrote overrides by `INSERT … ON CONFLICT ON CONSTRAINT uq_qc_org_metric DO UPDATE
   SET soft_limit = …, hard_limit = …` — that is, an "override" **overwrote the commercial base
   row in place**. The value the tenant was entitled to was destroyed, with no record of what it
   had been. There was nothing to fall back to.
2. `110_5C2`'s admission guard read `IF NOT FOUND OR v_hard_limit IS NULL THEN RETURN; END IF;` —
   a **fail-open**. An expired or absent quota configuration therefore resolved to *unlimited*
   rather than to the commercial limit.

Together these mean an expiring temporary grant did not return the tenant to its plan limit; it
left the tenant either at the overwritten value permanently or at **no limit at all**. That is a
revenue-affecting enforcement failure in the default direction — the system failed *open*, granting
more than was sold — which is why it is P1 and why it could not be closed by documentation. The
fix is structural: a separate override table, a resolver that reads the live base, and no
fail-open branch.

Both are closed by `111_5H4` and proven in §16.3.

### 10A.8 Carrier, and what was deliberately not done

| Statement | Detail |
|---|---|
| **`111_5H4` is the carrier** | One additive migration. `down_revision = '110_5C2'`. It adds `billing.fn_is_canonical_usage_metric()`, the `billing.quota_overrides` table, `billing.fn_resolve_effective_quota()`, a `CREATE OR REPLACE` of `billing.fn_platform_set_quota_override()` **at the same public signature**, a `CREATE OR REPLACE` of `voice.fn_assert_agent_quota_admission()`, and documentation-only `COMMENT ON COLUMN` statements marking the `106`-era override columns legacy |
| **`110_5C2` is unchanged** | This pass did **not** amend `110_5C2` again. Its five functions, its trigger and its privilege posture are intact and are re-proven by the fresh and incremental legs in §16.3 |
| *(Historical — 111 pass; superseded by §10B)* ~~**No migration `112` exists**~~ | ~~Exactly one further migration was authorized and exactly one was created. `111_5H4` is the single Alembic head~~ — true when the 111 pass closed. `FAR-OD-03` later authorized `112_5H5` (`down_revision = '111_5H4'`), which is now the single project head (§10B, §14.1) |
| **Nothing was dropped** | No table, column, constraint, index or policy was dropped or altered destructively; no RLS was weakened; **no new `BYPASSRLS`** — the inventory remains `app_migration`, `app_platform_admin`, `postgres`, all pre-existing |

---

## 10B. `FAR-OD-03` = OPTION B and `FAR-OD-04` = ADMISSION → TERMINAL — Capacity / Entitlement Quota (contract of record)

**Owner decisions (binding).**
- **`FAR-OD-03` = Option B.** `CONCURRENT_CALLS` is a **CAPACITY / ENTITLEMENT** quota. It is a separate domain from the accumulated USAGE quotas and is **not** a sixteenth usage metric.
- **`FAR-OD-04` = Admission → terminal.** A `CONCURRENT_CALLS` reservation is held from admission until the call enters a frozen terminal state, or until setup fails.

**Why this section exists.** It closes **`FAR-P1-06`**. Three frozen Phase-6 documents governed `CONCURRENT_CALLS` as a per-organization limit: 6D (`CheckQuota(CONCURRENT_CALLS)`), 6H (campaign dispatch fail-closed) and 6K (quota vocabulary and the 429 mapping). The limit was not representable anywhere in the database at head `111_5H4`: the 111 setter could not write it and `billing.fn_resolve_effective_quota` raised on it (`FAR_112_02` §1).

The closure has two parts. The database carrier is migration **`112_5H5`** (`down_revision = '111_5H4'`). The API contract is carried by controlled amendments in 6K §54 (the authority), 6D §42 and 6H §54 (the consumers), 6M §67 (the Platform Admin route) and 6E §43 (scope note), plus 5H at the schema-document layer. No endpoint, request field, response field, permission string or top-level error code was added.

### 10B.1 Two quota domains — not collapsed

| Property | USAGE / ACCOUNTING | CAPACITY / ENTITLEMENT |
|---|---|---|
| Vocabulary | the canonical **15** metrics (5H §11.1, 6K §53.3) — **unchanged** | **`CONCURRENT_CALLS` only** |
| Vocabulary predicate | `billing.fn_is_canonical_usage_metric` (replaced by 112, NULL-safe) | `billing.fn_is_canonical_capacity_quota_metric` (new in 112, NULL-safe) |
| Table `CHECK` | `chk_qo_metric_canonical` | `chk_cqo_metric_canonical` |
| Base commercial limit | `billing.quota_configs` | `billing.quota_configs` — **the same shared base table** |
| Temporary Platform Admin override | `billing.quota_overrides` (111) | `billing.capacity_quota_overrides` (112), with partial unique index `uq_cqo_org_metric_current` and RLS `ENABLE` + `FORCE` |
| Effective resolver | `billing.fn_resolve_effective_quota` (111, **not modified by 112**) | `billing.fn_resolve_effective_capacity_quota(UUID, TEXT)` (new in 112), `STABLE`, **`SECURITY INVOKER`**, explicit `search_path` |
| Semantics | **accumulated** over a period, monotonic counter, bounded over-consumption tolerated | **instantaneous** occupied capacity, acquire/release **reservation** gauge, no over-admission |
| Billable | yes — usage events, rating, overage | **no** — capacity is never metered, rated, invoiced or treated as billable overage (6K §54.1) |

Separation is enforced at three independent layers: the two table `CHECK` constraints, the two resolvers, and the Platform Admin dispatcher. The usage resolver rejects `CONCURRENT_CALLS`. The capacity resolver rejects every usage metric, including `ACTIVE_AGENTS`. The legacy `AGENT_COUNT` is rejected by both and aliased into neither. `NULL` is rejected by both. No row has ever crossed domains (`FAR_112_03` §7, H.1–H.7b; `FAR_112_02` §11).

### 10B.2 One Platform Admin setter, dispatching by domain

`billing.fn_platform_set_quota_override(UUID, UUID, TEXT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ, TEXT)` keeps its **existing 8-argument public signature** and its `UUID` return. The route contract `POST /api/v1/platform-admin/organizations/{organization_id}/quota-overrides` (6M §66.2 / §67.3) is therefore unchanged. The function body dispatches by vocabulary:
- a usage metric writes `billing.quota_overrides`, with behaviour identical to 111;
- `CONCURRENT_CALLS` writes `billing.capacity_quota_overrides`;
- anything else is refused with `P0001`.

`EXECUTE` is granted to `app_platform_admin` only, and `PUBLIC` and `app_api` are revoked. It is the only `SECURITY DEFINER` of the five governed quota functions. Each write and its audit row commit or roll back together (`FAR_112_02` §12; `FAR_112_03` §§8–10; audit atomicity in 112 report §3.10).

### 10B.3 Resolution outcomes — zero rows fails closed; `NULL` hard limit is uncapped

| Case | Resolver result | Meaning | Admission |
|---|---|---|---|
| A | one row, `hard_limit IS NULL` | **Explicitly uncapped**: a deliberate configuration decision recorded in a row | Admit. The reservation is still recorded |
| B | **zero rows** | Capacity configuration **absent** | **FAIL CLOSED**: refuse and never read as unlimited → `503 DEPENDENCY_UNAVAILABLE`, `details.reason = "CAPACITY_QUOTA_NOT_CONFIGURED"` |
| C | one row, finite `hard_limit` | Capped | Admit only while occupied `<` `hard_limit`; at the limit → `429 QUOTA_EXCEEDED`, `details.metric = "CONCURRENT_CALLS"` |
| — | reservation store or resolver unreachable | Authority unavailable | **FAIL CLOSED** → `503 DEPENDENCY_UNAVAILABLE`, `details.reason = "CAPACITY_AUTHORITY_UNAVAILABLE"` |

At the SQL layer, case B is a clean zero-row result (`FAR_112_02` §15), so refusing it is a consumer obligation that 6K §54.3 imposes on every consumer. Case A is proven in `FAR_112_02` §10. Resolution precedence and read-time expiry are those of 111: an active non-superseded override, otherwise the **current** base; expiry falls back to the current base, never to unlimited (`FAR_112_02` §§3–9). Both reasons are `details.reason` values reusing the existing `DEPENDENCY_UNAVAILABLE` code (6K §54.7), not new error codes.

### 10B.4 Reservation lifecycle — `FAR-OD-04` (6K §54.4–§54.6, 6D §42.2–§42.4, 6H §54.2)

| Rule | Contract |
|---|---|
| **Acquire exactly once, at admission** | At exactly two outbound admission points: 6D `POST /api/v1/calls`, and Campaign → Voice dispatch through 6D §28.10a `InitiateOutboundCallUseCase`. Acquire happens **before** the provider is contacted |
| **Reservation identity** | `reservation_id` = `voice.call_sessions.id` (= 6D `call_id` = `call_session_id`). It is never a request ID, an idempotency key or a random token |
| **Idempotent acquire** | A repeat for a held `reservation_id` returns `ALREADY_HELD` and takes no second slot. This covers `Idempotency-Key` replay, dispatch replay and worker retry |
| **Held across all non-terminal states** | `INITIATED`, `RINGING`, `ANSWERED`, `ACTIVE`, `ON_HOLD`, `TRANSFERRING`, `WRAP_UP`. There is **no** release or re-acquire on any transition into or out of `ACTIVE` |
| **Transfer / resume** | `ON_HOLD → ACTIVE` and `TRANSFERRING → ACTIVE` keep the slot. **No reacquire**, so a resume or failed transfer can never be refused mid-call |
| **Release exactly once — (A) setup failure** | Release after `ADMITTED` and before the call is established: session transaction rollback, dispatch recorded `FAILED`, or provider rejects `place_call` |
| **Release exactly once — (B) terminal** | Release on entry to one of the **7 frozen terminal states**: `NO_ANSWER`, `CANCELLED`, `VOICEMAIL`, `TRANSFERRED`, `COMPLETED`, `FAILED`, `ABANDONED` |
| **Idempotent release** | A repeat, or a release for a never-held ID, returns `NOT_HELD` and never decrements a second time |
| **No new states** | The frozen 6D §11.1 / 4B §7.1 / 5C §5.1 state machine is used exactly as frozen. Nothing is added, renamed or reinterpreted |
| **ACTIVE-only index** | The frozen `status = 'ACTIVE'` count through `idx_cs_org_status` is **retained** for reporting, observability and reconciliation cross-check **only**. It is no longer the admission decision |
| **Crash backstop** | The reconciler releases against authoritative Postgres state. It **never** releases while dispatch is `SUBMITTING` or `AMBIGUOUS` (6K §54.5 rule 8) |
| **Inbound** | Inbound calls pass through neither admission point, so in V1 they are neither admitted nor refused and hold no reservation. Inbound capacity admission is registered by 6K §54.6 as a **future, non-blocking** item, *"not silently adopted"* (§9.3, §11) |

**Status.** This lifecycle is an **API contract of record**. It is not a database-implemented mechanism, and this section does not describe it as implemented. The reservation store, grace period and reconciler cadence are **IMPLEMENTATION-READINESS** items (6K §54.5, §9.3/§9.4). The database side that 112 implements is the configuration, override and resolution layer only.

### 10B.5 Consumers use one authority; the campaign sub-ceiling is separate

- **6K is the single runtime admission owner** (6K §54.4). `AcquireCapacity` → `ADMITTED` / `ALREADY_HELD` / `REFUSED_AT_LIMIT` / `REFUSED_NOT_CONFIGURED` / `UNAVAILABLE`. `ReleaseCapacity` → `RELEASED` / `NOT_HELD` / `UNAVAILABLE`. `ReadCapacity` is advisory and never admits. These are in-process ports, and no route is added.
- **6D consumes it** (6D §42.2 `POST /calls` acquisition and release; §42.3 the campaign in-process caller uses the same authority; §42.4 counted lifetime; §42.7 error mapping).
- **6H consumes it** (6H §54.2 dispatch sequence; §54.3 start pre-flight; §54.4 outcome mapping: at the limit the contact is `DEFERRED` under the existing `TENANT_CALL_QUOTA_REACHED` reason, with no client error).
- A campaign slot and a `POST /calls` slot are drawn from **the same per-organization gauge** (6K §54.5 rule 10).
- **The campaign sub-ceiling is separate** (6H §54.6). `campaigns.concurrency_policy.max_concurrent_calls` and its Redis counter `campaign:concurrency:{tenant_id}:{campaign_id}` are campaign-scoped and non-authoritative. They are never used as, summed into or substituted for the tenant `CONCURRENT_CALLS` gauge, and the two reconcilers do not touch each other's state.

### 10B.6 Lowering capacity is non-destructive

When the effective limit drops below the occupied count — by a lower base, a lower override, supersession, or read-time **expiry** of a higher override:
- **no** in-progress call is terminated;
- **no** provider call is acted on;
- **no** `voice.call_sessions` row is mutated;
- **no** reservation is revoked.

Only **new** acquisitions are refused until occupied falls below the new limit (6K §54.8, 6D §42.5, 6H §54.5).

### 10B.7 Closures carried by this pass

| Ticket | Closure | Evidence |
|---|---|---|
| **`FAR-P1-06`** | **CLOSED** by `112_5H5` plus the controlled API amendments (6K §54, 6D §42, 6H §54, 6M §67, 6E §43 scope note, 5H) | `FAR_112_02` §1 before-state, §§2–15 after-state; `FAR_112_03` §7 |
| **`FAR-P2-08`** | **CLOSED BY 112**. The `p_metric = ANY(ARRAY[...])` guard returned `NULL`, not `FALSE`, for a `NULL` metric, so `IF NOT <NULL>` silently did not fire. Both predicates are now wrapped in `COALESCE(..., FALSE)` and both resolvers check `p_metric IS NOT NULL` first | `FAR_112_02` §2; `FAR_112_03` §7 H.5, H.5b, H.6 |
| **`FAR-P2-09`** | **CLOSED as a controlled audit-contract extension**. Before 111, `resource_type` was `QUOTA_CONFIG`. From 111 it is `QUOTA_OVERRIDE`, covering both domains in 112, with the domain carried in `resource_snapshot.quota_domain`. `action_kind` stays `QUOTA_OVERRIDE_SET`. The change is not described as "unchanged". No migration was needed: the `audit.audit_events` constraints are length-only | `FAR_112_02` §14; `FAR_112_03` §10.3 P10, §10.4 P11; 6M §67.6 |
| **`FAR-P3-07`** | **CLOSED BY CONTROLLED ERRATUM**. "The five functions 112 created or replaced" is wrong: `112_5H5.sql` has **four** `CREATE OR REPLACE FUNCTION` statements. 112 **replaces** `fn_is_canonical_usage_metric` and `fn_platform_set_quota_override`, and **creates** `fn_is_canonical_capacity_quota_metric` and `fn_resolve_effective_capacity_quota`. The fifth probed function, `fn_resolve_effective_quota`, belongs to 111 and is untouched. The correct label is **"the five governed quota functions at head `112_5H5`"**. The evidence is unchanged: exactly one `SECURITY DEFINER`, an explicit `search_path` on all five, and no PUBLIC `EXECUTE`. Captured transcripts are left verbatim | 112 report §3.9 erratum block; `FAR_112_03` §8.1; `FAR_112_01` §2 |

### 10B.8 Security statement — scoped (`FAR-P3-04`)

The guarantee is: within the application's runtime trust boundary (sessions connecting as the non-superuser application roles, under normal SQL), the capacity-override mutation path is the guarded `SECURITY DEFINER` setter, with explicit `search_path`, minimum `EXECUTE` grants, no raw DML grant, in-function validation, same-transaction audit, the partial-unique-index backstop, and RLS `ENABLE` + `FORCE` for tenant read isolation.

**It is not claimed** that superuser privilege cannot be bypassed, that `FORCE ROW LEVEL SECURITY` binds a superuser, or that triggers cannot be disabled. Deliberate superuser or table-owner DDL, trigger disabling and `session_replication_role = replica` are **outside** the guarantee.

112 added **no** role and granted `BYPASSRLS` to no role. The `BYPASSRLS` inventory is unchanged: `app_migration` and `app_platform_admin` (both pre-existing from `001_5B`), plus `postgres` (112 report §3.9 and §4; 5C scoped notes; 6M §67.7).

### 10B.9 Carrier, and what was deliberately not done

| Statement | Detail |
|---|---|
| **`112_5H5` is the carrier** | One additive, forward-only migration, `down_revision = '111_5H4'`. `downgrade()` raises `NotImplementedError` |
| **`001`–`111` unchanged** | 222/222 frozen files (111 `.sql` + 111 `.py`) verify byte-identical against a pre-authoring SHA-256 baseline (`FAR_112_01`: 222 OK / 0 FAILED). `110_5C2` and `111_5H4` were not amended. The `111_5H4` header over-attribution is corrected by record, not by edit (`FAR-P3-06`) |
| **No migration `113`** | None was authorized and none exists. `112_5H5` is the single project head |
| **Nothing dropped** | No table, column, constraint, index or policy was dropped or destructively altered. No RLS was weakened. No new `BYPASSRLS` |
| **Usage domain not redefined** | The 15-metric vocabulary, `billing.quota_overrides` and `billing.fn_resolve_effective_quota` behave exactly as at 111. This is re-proven by the targeted 111 regression (`FAR_112_03` §6) |

---

## 11. Future / Release-Train Register

Every non-closed item from the whole-corpus classification (§9.1–§9.5, `FAR-P2-06`) is listed here by owning document. Nothing is silently dropped, silently promoted into V1, or described as implemented. The class definitions are in §9.1.

**Totals: 108 non-closed = 84 FUTURE — NON-BLOCKING + 4 RELEASE-TRAIN + 20 IMPLEMENTATION-READINESS. BLOCKER = 0.** Each item is counted once, under its canonical owner. Duplicates collapsed by `same_as` (§9.1 step 4) are shown as "→ canonical" and are not counted a second time.

### 11.1 RELEASE-TRAIN (4) — must be delivered or validated before a V1 release; not future debt

| ID | Item | Owning doc | Status |
|---|---|---|---|
| `DEP-6D-11` | Per-stage voice latency budget / provider benchmark validation | 6D | **RELEASE-TRAIN** |
| `DEP-6H-11` | DNC dispatch-proof logging (legal / product) | 6H | **RELEASE-TRAIN** |
| 6L §61.3 **E** | **SIP trunk support — V1 requirement** | 6L | **RELEASE-TRAIN (V1)**. Not demoted to future |
| `FR-FLAG-001` / `DBGAP-6M-01` | Feature-flag persistence / CRUD | 6M §46 | **RELEASE-TRAIN** *(supersedes the earlier "Non-blocking forward item" wording in this register)* |

### 11.2 Per-document register

| Doc | FUTURE — NON-BLOCKING | RELEASE-TRAIN | IMPLEMENTATION-READINESS | Non-closed |
|---|---|---|---|---:|
| **6A** | R-3 India data residency · R-7 weak ETag *(R-5 → `DEP-6D-10`; R-8 → `DEP-6B-06`)* | — | R-4 Redis pool defaults · R-6 async SLA placeholders | 4 |
| **6B** | `DEP-6B-03` **MFA recovery** · `DEP-6B-05` **phone verification** · `DEP-6B-06` **CAPTCHA / adaptive challenge** · §34 custom per-membership permissions | — | `DEP-6B-04` **OAuth2/OIDC IdP integration** · `DEP-6B-07` **central internal token issuer** build-out | 6 |
| **6C** | `DEP-6C-01` org reactivation · `-03` `team:*` permission · `-04` team-membership cascade · `-05` `user_preferences` · `-06` email change · `-08` cancellation→billing cascade · `-09` member reactivation permission · `-13` concurrent-invitation constraint | — | `DEP-6C-12` **invitation resend token invalidation** | 9 |
| **6D** | `DEP-6D-01` call-control permissions · `-02` `tool:*` permission · `-03` `phone_number:*` permission · `-06` **tenant ProviderConfig CRUD** · `-07` **phone-number provisioning** · `-12` Agent archival/delete | `DEP-6D-11` **latency / provider benchmark** | `DEP-6D-05` **ring/hold runtime timers** · `DEP-6D-08` **`TtsPort.cancel()` live-provider validation** · `DEP-6D-10` **TTS fallback vendor** | 10 |
| **6E** | `DEP-6E-02` `prompt_ref` existence validation · `-08` tool permission reuse · `-09` **preview/test/validate** · `-10` **ProviderConfig CRUD** · `-11` **provider/model compatibility** · `-12` LanguageEvaluationRecord residuals · `-14` Agent archival · `-16` **`qualification_criteria`** (mitigated on the output side only; deliberately not promoted) · §3.2 Prompt Management | — | — | 9 |
| **6F** | `DEP-6F-04` `knowledge_base_refs` validation · `-05` embedding-model registry · `-12` Knowledge analytics (→6L) · `-13` knowledge-provider plugins (→6J) | — | `DEP-6F-06` **prompt-injection mechanism** · `-07` **malware scanner** · `-08` **crawler implementation** · `-10` **embedding quota integration** | 8 |
| **6G** | `DEP-6G-04` manual score override · `-05` Company delete · `-08` PLATFORM/REGULATORY suppression admin · `-12` **external CRM sync** · `-13` Voice outcome fields · `-14` `contact.converted` billing consumption · `-16` node executors (→6I) — **non-exposed / future CRM** | — | — | 7 |
| **6H** | `DEP-6H-05` `action_kind` vocabulary · `-06` list source · `-07` list rename · `-08` import cancel/retry · `-09` outcome index · `-10` CampaignContact command · `-13` **`CostLookupPort` / cost** · `-14` **outcome comparison analytics** · `-16` **affordability pre-flight** · `-17` **campaign budget** · **recurring campaigns** (ADR-6H-09) · campaign DELETE not exposed · telephony provider-side ambiguity residual (§18.4) | `DEP-6H-11` **DNC dispatch-proof logging (legal)** | — | 14 |
| **6I** | §54-1 ADR-5G-010 prompt-version pinning · §54-2 partition automation · §54-3 `started_at` pruning · §54-11 **publish idempotency replay residual** · §54-13 node-level analytics telemetry · §54-14 admin stuck-workflow intervention *(6M `DBGAP-6M-05` → here)* | — | §54-5 **`WEBHOOK`/`API_CALL` egress runtime** (6J) · §54-10 **campaign↔workflow ACL** | 8 |
| **6J** | `DEP-6J-03` `external_account_ref` uniqueness · `-07` webhook auto-suspend · `-08` definition metadata columns · **J1** multiple connections per provider · **J2** private-network egress allow-list · **J3** plugin marketplace · **J4** integration usage billable | — | — | 7 |
| **6K** | `DEP-6K-03` manual billing-account suspend/reactivate override *(6M billing-account override → here)* · `DEP-6K-04` 6C tax-profile endpoint · §54.6 **inbound calls under `CONCURRENT_CALLS` governance** ("registered as a future, non-blocking item, not silently adopted") | — | `DEP-6K-01` `TOOL_EXECUTIONS` producer · `DEP-6K-02` `KNOWLEDGE_RETRIEVALS` producer · `DEP-6K-05` workflow-completion payload discriminator · §54.5 **capacity runtime** (reservation store, grace period, reconciler cadence) | 7 |
| **6L** | §61.2 **campaign spend / cost attribution** *(§55-16 → here)* · §55-11 **historical archive API** · §61.3 **A** AI-assisted setup · **B** advanced agent config · **C** preview/test · **D** controlled deployment snapshots · **ODD-5J-01..07** (7) | §61.3 **E SIP trunk support (V1)** | §55-5 **10 of 12 projection-population functions** | 15 |
| **6M** | §46 **cross-tenant admin webhook replay** (`DBGAP-6M-04`) · §51 `FR-ADM-001` mutable system configuration | §46 **`FR-FLAG-001`** / `DBGAP-6M-01` | §52 **historical rebuild / backfill** control | 4 |
| **Σ** | **84** | **4** | **20** | **108** |

Owner requirements A–E in 6L §61.3 are all registered: A–D are FUTURE, and **E (SIP trunk) is V1 RELEASE-TRAIN**. The 6M stuck-workflow and billing-override items appear under their canonical owners, 6I §54-14 and `DEP-6K-03`.

### 11.3 Removed from this register (closed, not dropped)

- `DEP-6E-20` is **closed** (§9 row 1, `FAR-OD-01`).
- `FR-DB-001` is **closed**. It was raised in an earlier revision of this document as a deferred database remediation, and migration **`110_5C2`** implements exactly that remediation. The forward item is removed rather than left standing as phantom debt (§10.1, §13).
- `FAR-P1-06` (`CONCURRENT_CALLS` not representable) is **closed** by `112_5H5` (§10B). It is **not** carried as future debt. Only the capacity **runtime** (6K §54.5, IMPLEMENTATION-READINESS) and **inbound** capacity admission (6K §54.6, FUTURE) remain, and both are listed above.

---

## 12. Source-Document Change Register

Every edit made to any document or artifact during this reconciliation pass, including the **authorized additive database remediation**. Only corrections resolvable against frozen precedence, required by the owner decision, or required to close `DB-BLOCKER-FINAL-API-001` were made.

| # | File | Section | Why Changed | Change Type | Architecture Changed? |
|---|---|---|---|---|---|
| 1 | `6E-AI-Agent-APIs.md` | **New §43** (§43.1–§43.11, lines 1510–1638); §38 `DEP-6E-20` register row; §32 concurrency note; §-pointer at line 1202; FR-TEN-005 traceability row (line 1311) | Owner decision `FAR-OD-01` = Option B required a normative, synchronous Agent-count quota contract on `POST /agents`, and required `DEP-6E-20` to be marked resolved rather than open | Additive amendment (§43) + 4 in-place status/pointer corrections. 6E was **not** rewritten. | **YES at API behaviour level** — `POST /agents` and `POST /agents/{agent_id}/clone` now refuse at quota. **YES at database architecture level** — §43.4/§43.8 now bind the contract to the new `SECURITY DEFINER` functions delivered by migration `110_5C2`, and the API layer's own advisory lock is removed. |
| 2 | `6K-Billing-Usage-APIs.md` | **New §52** (§52.1–§52.6, lines 3485–3526); §21.1 `ACTIVE_AGENTS` row; §36 `429 QUOTA_EXCEEDED` foreign-surface column | 6K's text implied periodic/snapshot-only accounting for `ACTIVE_AGENTS` and left "billable state" imprecise; Option B requires one authority, one precise counted set, and 6K's own error reused | Additive amendment (§52) + 2 in-place row extensions | **YES at API behaviour level** (6K's quota authority now has a synchronous consumer). **YES at database architecture level** — §52.2/§52.4 now name `voice.fn_create_agent()` / `voice.fn_clone_agent()` as the enforcement point and new §52.7 corrects 6K's earlier "no DB change required" claim. Periodic 6K accounting is retained for reporting/reconciliation/drift detection — §52.2 states it is not a second quota source. |
| 3 | `6H-Campaign-APIs.md` | 3 occurrences of the internal compliance-policy route | Consumer cited 6C's owned route with the wrong literal parameter (`{id}` for `{organization_id}`) | In-place literal correction | **NO** |
| 4 | `6M-Admin-Platform-APIs.md` | §-break-glass route (line 122); new disambiguation note above the error-code table (line 383) | (a) 6M reuses 6B's break-glass contract verbatim, so its literal must match 6B's `{grant_id}`. (b) all 22 distinct paths in the error table's `Relevant Endpoint(s)` column use a prefix-omitting local shorthand (verified by enumeration), two of which — `POST /organizations/{id}/suspend` and `GET /audit/events` — read as collisions with 6C's and 6L's real tenant routes | (a) In-place literal correction. (b) Additive note only — **no table row altered**; the 29-named-condition count and every code, status, meaning and retry semantic are unchanged | **NO** |
| 5 | `6D-Voice-Call-Agent-APIs.md` | Auth matrix, lines 1254–1255 | The corpus's only two `/internal/v1/` literals (missing the mandatory `/api` segment), one of which also used the same parameter name twice in a single path | In-place literal corrections (2) | **NO** |
| 6 | `6D-…` and `6H-…` | §1a in each | PostgreSQL-baseline clarification made earlier in this reconciliation: PG16/16.10 mentions are historical validation evidence, not a live baseline claim (§8) | Additive, non-destructive; no existing sentence edited | **NO** |
| 7 | `6M-Admin-Platform-APIs.md` | §25 endpoint inventory, §27/§27.1/§27.2 matrices, §28 error table's `Relevant Endpoint(s)` column, §51 SRS traceability rows, §53/§62/§63 request-response tables; labelled normalization note inserted above the §25 inventory | `FAR-P3-03` closure by **Option A** (§3.3): 6M's normative inventory spelled path parameters `{id}` while frozen 6A's convention and the owning documents use resource-specific names | In-place literal normalization of **95** `{id}` occurrences → `{organization_id}`, `{plan_id}`, `{agreement_id}`, `{user_id}`, `{session_id}`, `{api_key_id}`, `{recording_id}`, `{transcript_id}`, `{workflow_execution_id}`, `{refund_id}`; **0 remain**. Plus one additive disclosure note | **NO** — literal spelling only. No route added, removed, split, merged or re-scoped; §25 inventory still 42 rows and §27.2 still 42 rows, verified after the edit |

### 12.1 Authorized database remediation — Phase 5 artifacts

*(Historical — `110_5C2` pass. "Exactly one" describes that pass's authorization only. It is superseded for the project by the separate `FAR-OD-02` authorization of `111_5H4` (§12.3) and the `FAR-OD-03` / `FAR-OD-04` authorization of `112_5H5` (§12.4).)* The DB-conformant closure directive authorized **exactly one** new additive migration for this pass. It is listed here in full because the change register must not report `Architecture Changed? = NO` for the database remediation. After the second independent review, `110_5C2` was **amended in place** — not followed by a new migration — to close `FAR-P1-02`, `FAR-P1-03` and `FAR-P2-03` (§13); rows 8–10 record the amended files.

| # | File | Nature | Why | Architecture Changed? |
|---|---|---|---|---|
| 8 | `docs/phase-05-database-design/5K/migrations/110_5C2.sql` | **NEW file, amended in place** — 27,979 bytes, 544 lines, `sha256 3d5b2273…a9e26` (the pre-amendment 15,044-byte `3b76d835…d776c` is **SUPERSEDED**) | Resolves `DB-BLOCKER-FINAL-API-001` and closes `FAR-P1-02` / `FAR-P1-03` / `FAR-P2-03`: `voice.fn_assert_agent_quota_admission()` (advisory lock + server-side quota resolution + canonical count, raising `53400` when `(active + 1) > hard_limit` — the stored `NUMERIC(18,4)` limit, never rounded — before any INSERT), `voice.fn_assert_agent_actor()` (`created_by` membership cross-check in the same tenant), `voice.fn_create_agent()` and `voice.fn_clone_agent()` (both `SECURITY DEFINER`), `voice.fn_agents_mutation_guard()` with the `BEFORE UPDATE` trigger `trg_agents_mutation_guard` (`DEPRECATED` terminal, `organization_id` immutable, no soft-delete resurrection; binds every principal, the superuser included), `REVOKE INSERT ON voice.agents FROM app_api, app_worker, app_platform_admin`, `REVOKE ALL … FROM PUBLIC` on all five functions, with `EXECUTE` to `app_api` only and only on the two endpoint functions | **YES — this is the database architecture change.** Additive only: five functions and one trigger added; no table, column, constraint, index or policy dropped or altered; no RLS weakened; `UPDATE` grants unchanged |
| 9 | `docs/phase-05-database-design/5K/alembic/versions/110_5C2.py` | **NEW file, amended in place** — 10,659 bytes, `sha256 8885326e…76104` (the pre-amendment 5,810-byte `735366af…71d5` is **SUPERSEDED**) | Alembic wrapper: `revision = '110_5C2'`, `down_revision = '109_5B7'`, `run_frozen_sql('110_5C2.sql')`, `downgrade()` raises `NotImplementedError` per the repository's existing forward-only policy (no destructive downgrade invented) | **YES** (same change, wrapper) |
| 10 | `docs/phase-05-database-design/5C-Voice-Schema.md` | **Additive amendment** — clearly labelled *FINAL API RECONCILIATION CONTROLLED DB AMENDMENT* | Records the five new functions, the `trg_agents_mutation_guard` trigger, the revoked raw INSERT, the counted set and the `53400` → `QUOTA_EXCEEDED` mapping in the owning Phase 5 schema document | **YES** (documentation of #8) |
| 11 | `docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md` | **Additive** — Row 110 entry, live-validation record, project-wide current-state table, explicit head-ownership statement; four Phase-6M paragraphs **scope-clarified, not falsified** | The manifest is the authoritative migration ledger and must carry Row 110. Earlier Phase-6M statements that "no migration followed `109_5B7`" were true **within Phase 6M** and are preserved with a forward pointer rather than rewritten | **YES** (documentation of #8) |

### 12.2 Reconciliation artifacts (this document and its evidence)

| # | File | Nature |
|---|---|---|
| 12 | `docs/phase-06-api-design/FINAL-API-RECONCILIATION.md` | This document — extended and corrected in this pass (§0, §3.1, §3.2, new §3.3, §4–§9 ledgers, §10, §11, §12, §13, §14, §15, §16, §17); updated again by the `110_5C2` micro-remediation closure (§0, §12.1, §12.2, §13, §14.1, §15, §16, §17) |
| 13 | `docs/phase-05-database-design/5K/validation/FINAL_API_RECONCILIATION_DB_VALIDATION_REPORT.md` | Live PostgreSQL 18.6 validation report for migration `110_5C2` (as amended in place) |
| 14 | `…/validation/FAR_DB_01_migration_and_integrity.txt` | Evidence 1 — fresh `001 → 110`, incremental `109 → 110`, single head, `001`–`109` integrity (re-run against amended `110_5C2`; rewritten in place) |
| 15 | `…/validation/FAR_DB_02_quota_concurrency_battery.txt` | Evidence 2 — §2 fractional-limit battery (9/9), §11 live two-process concurrency battery (cases A, B, E, K, L), §7 UPDATE / reactivation battery (30/30), §13 sequential quota / tenant / clone battery, §15 atomicity (rewritten in place) |
| 16 | `…/validation/FAR_DB_03_privilege_rls_bypass_battery.txt` | Evidence 3 — `pg_proc` / `pg_trigger` / role-grant / table-privilege inspection, raw-INSERT bypass attempts as every runtime role, and the Part 2b superuser guard battery (rewritten in place) |

*Measurement as at the `110_5C2` micro-remediation pass. It is **superseded for the current total** by §12.3 below, which recomputes the register from the actual working tree and reaches **23 change groups**. The original sentence is preserved unedited rather than overwritten:* **Total: 16 change groups — 7 Phase 6 documents/groups, 4 Phase 5 artifacts (the authorized remediation), 5 reconciliation/evidence artifacts.** Migrations `001`–`109` and their Alembic wrappers are **byte-identical to `HEAD`** (§16); no migration `111` exists *(true as at the `110_5C2` pass; **superseded** — migration `111_5H4` was subsequently created under the `FAR-OD-02` authorization, see §10A, §12.3, §14.1 and §16.3)*; no existing normative statement was deleted — the two corrected claims (6E §43.10, 6K §52.6) are struck **in place with an explicit correction**, not removed silently. The micro-remediation additionally amended 6E §43.4a / §43.4b / §43.10a and 6K §52.3a; those edits sit inside the existing 6E and 6K groups, so the total stays 16. Evidence is capped at one report plus three compact files, rewritten in place by the micro-remediation with no new evidence file: **no evidence sprawl.** *(Scope: that cap describes the `110_5C2` evidence set. The `111_5H4` pass added one report plus three further compact files of its own — §12.3 rows 20–23 — and rewrote none of the `110` evidence except to add scope notices. The current repository therefore holds two reports and six evidence files in total, which remains a capped, per-pass set and not per-statement log sprawl.)*

### 12.3 Post-`111_5H4` additions to the change register (`FAR-OD-02` closure)

The rows above were compiled at the `110_5C2` micro-remediation. This subsection recomputes the register from the **actual current working tree** rather than carrying the earlier total forward.

**Committed history vs. current working tree.** Rows 8, 9 and 10 (`110_5C2.sql`, `110_5C2.py`, `5C-Voice-Schema.md`) are **committed** — they landed at commit `5038bbc` and therefore no longer appear in `git status`. They remain register rows because the register records what each pass changed, not what is currently uncommitted. Every row below is **uncommitted working-tree state** as reported by `git diff --name-status` and `git status --short` at the close of this pass.

**Re-edited files fold into their existing rows.** The `111_5H4` pass amended seven files that the register already carries. Following the precedent §12.2 set for the micro-remediation ("those edits sit inside the existing 6E and 6K groups"), these add **no** new group: `6E-AI-Agent-APIs.md` → row 1 (new §43.12); `6K-Billing-Usage-APIs.md` → row 2 (new §53); `6M-Admin-Platform-APIs.md` → rows 4 and 7 (§18, §28 correction, §66, `FR-TEN-005`); `5K/MIGRATION_MANIFEST.md` → row 11 (new Row 111 block + Row 110 scope markers); this document → row 12 (§0, §10A, §12.3, §13, §14.1, §15, §16.3, §17); `FINAL_API_RECONCILIATION_DB_VALIDATION_REPORT.md` → row 13 (scope notices); `FAR_DB_01_migration_and_integrity.txt` → row 14 (scope notice).

| # | File | Nature | Why | Architecture Changed? |
|---|---|---|---|---|
| 17 | `docs/phase-05-database-design/5H-Billing-Usage-Schema.md` | **Modified** — additive amendment, `§13` scope-marked and `ODD-5H-04` resolved | 5H is the owning Phase 5 document for billing/quota schema. `FAR-OD-02` = Option B introduces a second persistence layer (`billing.quota_overrides`) and an effective-quota resolver, which must be recorded in the owning schema document, and it settles the open design decision `ODD-5H-04` | **YES** (documentation of rows 18–19) |
| 18 | `docs/phase-05-database-design/5K/migrations/111_5H4.sql` | **NEW file** — 44,726 bytes, 836 lines, `sha256 5fe2bc96…f4c048` | The single additive migration authorized to carry `FAR-OD-02` = Option B: `billing.quota_overrides` (RLS enabled **and** forced), `billing.fn_is_canonical_usage_metric`, `billing.fn_resolve_effective_quota`, `billing.fn_platform_set_quota_override`, a `CREATE OR REPLACE` of `voice.fn_assert_agent_quota_admission` to read the resolver, and `COMMENT`-only `LEGACY (111_5H4)` marking of the `quota_configs` override columns | **YES — this is the database architecture change.** Additive only: one table, three new functions, one function replaced, no table/column/constraint/index/policy dropped, no RLS weakened, **no new `BYPASSRLS`** |
| 19 | `docs/phase-05-database-design/5K/alembic/versions/111_5H4.py` | **NEW file** — 9,227 bytes, 161 lines, `sha256 78b3fda4…7e70ea` | Alembic wrapper: `revision = '111_5H4'`, `down_revision = '110_5C2'`, `run_frozen_sql('111_5H4.sql')`, `downgrade()` raises `NotImplementedError` per the repository's existing forward-only policy | **YES** (same change, wrapper) |
| 20 | `…/5K/validation/FINAL_API_RECONCILIATION_111_VALIDATION_REPORT.md` | **NEW file** | Live PostgreSQL 18.6 validation report for migration `111_5H4`. It does not replace the `110` report (row 13); the two stand side by side as per-pass records | **NO** (evidence) |
| 21 | `…/5K/validation/FAR_111_01_migration_integrity.txt` | **NEW file** | Evidence 1 — fresh `001 → 111_5H4`, incremental `… → 110_5C2 → 111_5H4`, single head `111_5H4`, object-dump convergence between the two legs, `001`–`110` frozen-history integrity | **NO** (evidence) |
| 22 | `…/5K/validation/FAR_111_02_override_resolver_battery.txt` | **NEW file** | Evidence 2 — Batteries A, B, C, D, F: canonical metric vocabulary, effective-quota resolution and fallback, supersession, permanent overrides, fractional and `NULL` limits | **NO** (evidence) |
| 23 | `…/5K/validation/FAR_111_03_security_integration_battery.txt` | **NEW file** | Evidence 3 — Batteries E, G, H, I, J: ACL/RLS/privilege posture, Platform-Admin write path, the `created_by` negative battery that closes `FAR-P2-04`, `ACTIVE_AGENTS` admission against the resolver, and audit atomicity | **NO** (evidence) |

**Recomputed total: 23 change groups** — 16 carried forward from §12–§12.2 plus 7 added here: 1 Phase 5 schema document (row 17), the authorized `111_5H4` SQL + Alembic pair (rows 18–19), and 4 reconciliation/evidence artifacts (rows 20–23). By phase: **7 Phase 6 documents/groups, 7 Phase 5 artifacts, 9 reconciliation/evidence artifacts.**

**Working-tree reconciliation** *(historical — measured at the close of the `111_5H4` pass; superseded for the current working tree by §12.4)*. `git status --short` reports exactly **8 modified** and **6 untracked** files — 14 paths, which is fewer than 23 because rows 3, 5, 6, 8, 9 and 10 are committed history and rows 4 and 7 are two register groups inside one file (`6M`). No file appears in the working tree that is not accounted for by a row above: **zero unexpected files.** Migrations `001`–`110` and their Alembic wrappers remain **byte-identical to `HEAD`** (§16.3); `110_5C2` was **not** amended again by this pass.

### 12.4 Post-`112_5H5` additions to the change register (`FAR-OD-03` / `FAR-OD-04` closure)

This subsection recomputes the register again, from the **actual working tree at the close of the master-FAR closure (2026-09-17)**. The earlier totals are not carried forward.

**Committed history vs. current working tree.** Commit `eb234bf` (current `HEAD`) contains the whole `111_5H4` pass: rows 17–23 and the 111-pass re-edits to rows 1, 2, 4, 7, 11, 12, 13 and 14. Those rows remain register rows but no longer appear in `git status`. Every `112_5H5`-pass change listed below is **uncommitted**. `git status --short` reports **15 paths**:

- **14 staged** (index): 8 modified (`M`): 5C, 5H, `MIGRATION_MANIFEST`, 6D, 6E, 6H, 6K, 6M. 6 added (`A`): `112_5H5.sql`, `112_5H5.py`, `FAR_112_01`, `FAR_112_02`, `FAR_112_03`, the 112 validation report.
- **1 unstaged** modification: this document.

Nothing was committed, stashed or reset by the closure pass.

**Re-edited files fold into their existing rows.** This follows the §12.2 / §12.3 precedent, so these re-edits add **no** new group:

| Existing row | File | `112_5H5`-pass edit | Change type |
|---|---|---|---|
| 10 | `5C-Voice-Schema.md` | Six controlled notes: two `FAR-OD-03` notes that mark the `idx_cs_org_status` "concurrent quota check" wording as historical; two `FAR-P3-04` notes that scope "unbypassable" and the superuser result; two `FAR-P3-05` notes that mark the "`110_5C2` head / no `111`" statements as superseded by head `112_5H5` | Additive notes only; no existing text edited |
| 17 | `5H-Billing-Usage-Schema.md` | New controlled amendment for `112_5H5`: two quota domains, `billing.capacity_quota_overrides`, `fn_resolve_effective_capacity_quota`, the non-fail-open rule, the `FAR-P2-08` NULL-safe guard, runtime semantics owned by 6K, and scope markers on earlier statements | Additive amendment |
| 11 | `5K/MIGRATION_MANIFEST.md` | New Row 112 block, its live PostgreSQL 18.6 validation record and the post-`112_5H5` authoritative state. Also `FAR-P3-05` scope notes on the Row 111 "no `112`" sentence, the post-`111_5H4` state table and head-ownership statement, and the `FAR-P3-06` controlled note in Row 111 (`111_5H4` not edited) | Additive |
| 5 / 6 | `6D-Voice-Call-Agent-APIs.md` | New **§42**, `CONCURRENT_CALLS` capacity admission on `POST /api/v1/calls` and on the campaign in-process caller. Also pointer notes at the affected earlier sections | Additive amendment + pointer notes |
| 1 | `6E-AI-Agent-APIs.md` | Two `FAR-P3-05` head-supersession notes (at the 110 and 111 statements) | Additive notes only |
| 3 / 6 | `6H-Campaign-APIs.md` | New **§54**, tenant `CONCURRENT_CALLS` capacity admission in dispatch and start pre-flight, non-destructive lowering, and the campaign sub-ceiling kept separate. Also pointer notes | Additive amendment + pointer notes |
| 2 | `6K-Billing-Usage-APIs.md` | New **§54**: the two quota domains, the three resolution outcomes, the single runtime admission authority (Acquire / Release / Read ports), the counted lifetime, error mapping, non-destructive lowering, security scope and audit | Additive amendment |
| 4 / 7 | `6M-Admin-Platform-APIs.md` | New **§67**: `FR-TEN-005` across both domains, one Platform-Admin route with database-side dispatch, the read model, the `FAR-P2-09` audit-contract extension and security scope. Also pointer notes | Additive amendment + pointer notes |
| 12 | `FINAL-API-RECONCILIATION.md` (this document) | §0, §1 / §1.1 (`FAR-P2-07`), §2–§3 re-extraction, §9 / §9.1–§9.5 (`FAR-P2-06`), §10.1 / §10A.8 historical markers, new §10B, §11 rewrite, §12.1 / §12.3 historical markers, new §12.4, §13, §14 / §14.1, §15, §16.3 marker, new §16.4, §17 | Controlled update |

**New rows.**

| # | File | Nature | Why | Architecture Changed? |
|---|---|---|---|---|
| 24 | `docs/phase-05-database-design/5K/migrations/112_5H5.sql` | **NEW file**: 38,635 bytes, 744 lines, `sha256 6c3c0e0c546ccfa845822e94781193f6a5516a0176de0ec3bd24449b1abfdb53` | The single additive migration authorized to carry `FAR-OD-03` = Option B. It adds `billing.capacity_quota_overrides` (RLS `ENABLE` + `FORCE`, CHECK `chk_cqo_metric_canonical`, partial unique index `uq_cqo_org_metric_current`) and the new functions `billing.fn_is_canonical_capacity_quota_metric` and `billing.fn_resolve_effective_capacity_quota`. It replaces (`CREATE OR REPLACE`) `billing.fn_is_canonical_usage_metric`, making it NULL-safe (`FAR-P2-08`), and `billing.fn_platform_set_quota_override`, which now dispatches by domain. That is four `CREATE OR REPLACE FUNCTION` statements in total (`FAR-P3-07`) | **YES — the database architecture change.** Additive only: one table and two new functions; two functions replaced with an unchanged signature. Nothing is dropped, no RLS is weakened and no `BYPASSRLS` is added |
| 25 | `docs/phase-05-database-design/5K/alembic/versions/112_5H5.py` | **NEW file**: 12,673 bytes, 214 lines, `sha256 fb53b23ae715060fcffa987ee03b7411ae72f252f574e7ab8cd4241925f0e238` | Alembic wrapper with `revision = '112_5H5'` (L183) and `down_revision = '111_5H4'` (L184). `downgrade()` raises `NotImplementedError` under the forward-only policy | **YES** (same change, wrapper) |
| 26 | `…/5K/validation/FINAL_API_RECONCILIATION_112_VALIDATION_REPORT.md` | **NEW file**: 27,488 bytes, 497 lines, `sha256 145cbf8f…3fb` | Live PostgreSQL 18.6 validation report for `112_5H5`, including the §3.9 `FAR-P3-07` erratum block. The 110 and 111 reports stay alongside it as per-pass records | **NO** (evidence) |
| 27 | `…/5K/validation/FAR_112_01_migration_integrity.txt` | **NEW file**: 13,261 bytes, 243 lines, `sha256 7847d6fd…3fea` | Evidence 1: frozen `001`–`111` integrity (222 OK / 0 FAILED), migration counts and no `113`, fresh `001 → 112`, incremental `111 → 112`, single head, catalog convergence | **NO** (evidence) |
| 28 | `…/5K/validation/FAR_112_02_capacity_quota_battery.txt` | **NEW file**: 49,207 bytes, 1,009 lines, `sha256 a3390cf0…facc` | Evidence 2 (§§1–15): vocabulary, NULL safety, base, temporary override, expiry, base changes, permanent, supersession, no reactivation, NULL `hard_limit`, domain rejection, dispatcher, read model, audit, zero-row | **NO** (evidence) |
| 29 | `…/5K/validation/FAR_112_03_cross_domain_security_regression.txt` | **NEW file**: 59,661 bytes, 1,154 lines, `sha256 604becf4…11bd` | Evidence 3 (§§1–11): 110 regression, concurrency, actor and lifecycle guards, 111 regression, domain separation, privileges, RLS, audit, scoped guarantee | **NO** (evidence) |

**Recomputed total: 29 change groups.** That is the 23 carried forward from §12.3 plus 6 added here: the authorized `112_5H5` SQL + Alembic pair (rows 24–25) and 4 evidence artifacts (rows 26–29). By phase: **7 Phase 6 documents/groups, 9 Phase 5 artifacts, 13 reconciliation/evidence artifacts** (7 + 9 + 13 = 29).

**Working-tree reconciliation (current).** There are 15 paths. That is fewer than 29 because rows 3, 5, 6, 8, 9, 10 (the `110_5C2` artifacts), 13–23 and the earlier 5C/6E content are committed history, and several register groups share one file (rows 4/7 in 6M, rows 5/6 in 6D, rows 3/6 in 6H). The accounting is:

- All 15 paths map to a row above: 5C → 10, 5H → 17, manifest → 11, 6D → 5/6, 6E → 1, 6H → 3/6, 6K → 2, 6M → 4/7, rows 24–29, and this document → 12.
- **Zero unexpected files.**
- Migrations `001`–`111` and their Alembic wrappers are byte-identical to the pre-authoring baseline (222/222, §16.4).
- `110_5C2` and `111_5H4` were **not** amended.
- **No migration `113` exists.**

---

## 13. Issue Ledger (FAR-P0 / P1 / P2 / P3)

| ID | Severity | Issue | Resolution | Status |
|---|---|---|---|---|
| `FAR-P2-01` | P2 | `DEP-6E-20`: Agent-count quota enforcement was periodic/async only and never attached to `POST /agents` — an unfulfilled forward dependency, previously flagged in this artifact as requiring an owner decision | Owner decided `FAR-OD-01` = **Option B**; applied in full at source (6E §43, 6K §52) and recorded in §10 | **CLOSED** |
| `FAR-P3-01` | P3 | 6K's literal payment-webhook path had not been independently re-derived, leaving an apparent route collision with 6J's integration callback unproven either way | Re-derived by direct grep: 6K §30.2 declares `POST /api/v1/billing/payment-providers/{provider_slug}/webhook`; 6K §30.1 merely *quotes* 6J's `POST /api/v1/integrations/providers/{provider_slug}/callbacks/{opaque_connection_route_id}` in order to disown it. **Different surfaces; NO ROUTE COLLISION; neither route modified.** | **RESOLVED — NO ROUTE COLLISION** |
| `FAR-P2-02` | P2 | 6K's original `ACTIVE_AGENTS` definition ("`COUNT` of `voice.agents` in a billable state") did not state which lifecycle states count — an imprecision that Option B cannot be implemented against | Not silently decided. The counted set `{DRAFT, PUBLISHED}` is **derived** from constraints in the frozen documents (§10.2) and the derivation is written into 6K §52.3 so exactly one definition exists | **CLOSED (derivation recorded, not assumed)** |
| `FAR-P1-01` | **P1** | **Reclassified from `FAR-P3-02`.** Issuing `SELECT pg_advisory_xact_lock(...)` from the API/service/repository layer **directly conflicts with frozen 6A §17.3**, which permits application-level locking only inside a Phase 5 `SECURITY DEFINER` function or via the Campaign Redis `SETNX` pattern. This is not a cosmetic deviation: the Option-B design could only work by contradicting a frozen document, which makes it a P1 design defect, not a P3 disclosure | 6A was **not** weakened to legalise the old design. The serialization was moved behind a database boundary by migration **`110_5C2`**: `voice.fn_assert_agent_quota_admission()` takes the transaction-scoped lock inside the database, `voice.fn_create_agent()` / `voice.fn_clone_agent()` are `SECURITY DEFINER` and are the **sole** insert paths (raw `INSERT ON voice.agents` revoked from `app_api`, `app_worker`, `app_platform_admin`). 6E §43.4/§43.8 and 6K §52.4 now state the API layer takes no lock of its own | **CLOSED BY MIGRATION `110_5C2`** |
| `FAR-P1-02` | **P1** | **Raised by the second independent review.** The pre-amendment admission test `v_active >= v_hard_limit` compared an integer count against `billing.quota_configs.hard_limit NUMERIC(18,4)`. With a fractional limit such as `1.5` and one active Agent, `1 >= 1.5` is false, so a second Agent was admitted and the committed count (2) exceeded the stored limit | `110_5C2` **amended in place**: admission rejects when `(v_active + 1) > v_hard_limit` — the post-insert count is compared against the limit **as stored**, never rounded. Normative text: 6E §43.4b, 6K §52.3a. Live evidence: `FAR_DB_02` §2 fractional battery **9/9**, and concurrent fractional cases K (`1.5`) and L (`2.5`) in `FAR_DB_02` §11 | **CLOSED BY AMENDED `110_5C2`** |
| `FAR-P1-03` | **P1** | **Raised by the second independent review.** Revoking raw `INSERT` closed only one edge of the counted set. `UPDATE` on `voice.agents` is legitimately retained for the 6E lifecycle (PATCH, publish, deprecate, soft-delete), so a raw `UPDATE` could put a row back into `{DRAFT, PUBLISHED} ∧ deleted_at IS NULL` without admission: `DEPRECATED → DRAFT/PUBLISHED`, clearing `deleted_at`, or moving `organization_id` into another tenant under a `BYPASSRLS` role | `110_5C2` **amended in place** with `voice.fn_agents_mutation_guard()` and the `BEFORE UPDATE … FOR EACH ROW` trigger `trg_agents_mutation_guard` (no `WHEN` clause, no role test): `organization_id` is immutable; `deleted_at` cannot be cleared; the only permitted status changes are `DRAFT→PUBLISHED` and `PUBLISHED→DEPRECATED` (`DEPRECATED` is terminal); same-state updates pass. Normative text: 6E §43.4a. Live evidence: `FAR_DB_02` §7 **30/30** (ten cases × `app_api`, `app_worker`, `app_platform_admin`; active count unchanged after every rejection) and `FAR_DB_03` Part 2b (the trigger binds the superuser) | **CLOSED BY AMENDED `110_5C2`** |
| `FAR-P2-03` | P2 | **Raised by the second independent review.** `fn_create_agent` / `fn_clone_agent` accepted `p_created_by` with no database-side cross-check, so a `SECURITY DEFINER` path could stamp an arbitrary user id as an Agent's creator | `110_5C2` **amended in place** with `voice.fn_assert_agent_actor(UUID, UUID)` (`SECURITY INVOKER`, no `EXECUTE` grant to any role), called by both endpoint functions before admission. It raises `P0001` when `p_created_by` is `NULL` or has no `organization.memberships` row in the same tenant. It is a consistency check, not authentication — `app_api` remains the trusted principal boundary (6E §43.10a). No public DTO change. Verified by code (`110_5C2.sql` lines 237–262; called at line 297 in create and line 367 in clone), by catalog (`FAR_DB_03` Part 1 §1–§3), and on the positive path (every accepted create and clone in `FAR_DB_02` passed it). **The negative non-member case is not separately transcribed.** ***AMENDED BY THE `111_5H4` PASS:*** *that sentence was true when written and is preserved unedited, but it is now **stale as a description of the evidence set**. The negative case **is** directly transcribed — `FAR_111_03_security_integration_battery.txt`, **Battery H**, cases H.0–H.7 (**7/7**): an outsider non-member is refused `P0001`, an other-tenant member is refused `P0001`, a `NULL` actor is refused `P0001`, a real member succeeds as the control, the three rejected attempts wrote **0** Agent rows, the clone path enforces the same guard, and `app_api` holds no `EXECUTE` on `fn_assert_agent_actor` (`42501`). This closure is tracked as its own ticket, `FAR-P2-04` below.* | **CLOSED BY AMENDED `110_5C2`**; *negative-evidence gap closed separately by `FAR-P2-04`* |
| `FAR-P3-02` | P3 → superseded | Original (mis-severity) registration of the same advisory-lock deviation as a non-blocking P3 disclosure with a deferred removal path (`FR-DB-001`) | **Misclassified.** Superseded in full by `FAR-P1-01` above; `FR-DB-001` removed from §11 because `110_5C2` implements exactly that remediation. Not carried forward as future debt | **CLOSED — superseded by `FAR-P1-01`** |
| `FAR-P3-03` | P3 | 6M's `{id}` parameter convention on its normative platform-admin endpoint inventory diverges from frozen 6A's resource-specific naming and from the owning documents' own declarations | **Closed at source, not deferred to a later index document.** Option A applied (§3.3): 6A's resource-specific naming is canonical; 6M normalized — 95 literals changed, 0 remain; §25 inventory (42 rows) and §27.2 matrix (42 rows) unchanged in content; labelled disclosure note added at source | **CLOSED** |
| `DB-BLOCKER-FINAL-API-001` | **Blocker** | The executed schema supplied a serialization *primitive* but **no compliant enforcement path**: with raw `INSERT ON voice.agents` available to `app_api` and no guarded function, a hard, synchronous, server-authoritative `ACTIVE_AGENTS` admission could not be structurally enforced without the API layer taking its own lock. Affects `POST /api/v1/agents` and `POST /api/v1/agents/{agent_id}/clone` | **RAISED** in this pass (an earlier revision of this document wrongly recorded it as NOT RAISED — corrected in §10.1). Resolved by the single authorized additive migration `110_5C2`, live-validated on PostgreSQL 18.6 against disposable databases: fresh `001 → 110`, incremental `109 → 110`, one head, fractional battery 9/9, concurrency battery (cases A, B, E, K, L), UPDATE / reactivation battery 30/30, sequential quota / tenant / clone battery, privilege / RLS-bypass battery including the superuser guard check — all re-run against the amended `110_5C2` (§16) | **RESOLVED BY MIGRATION `110_5C2`** (amended in place) |
| `FAR-P1-04` | **P1** | **Raised by the `111_5H4` pass.** The quota-metric vocabulary had diverged between layers. The legacy `107` allow-list and the canonical 15-metric Phase-5H vocabulary share only **2** members; **13** are legacy-only and **13** canonical metrics are absent from `107` (set arithmetic transcribed in the `111` validation report §3 and restated in §10A.7). Critically, `ACTIVE_AGENTS` was **not** in the legacy allow-list — so the very metric that `FAR-OD-01` = Option B made synchronously enforceable could not be expressed as a quota override at all. This is P1, not cosmetic: `FAR-OD-02` is unimplementable on a vocabulary that cannot name its own subject | `111_5H4` establishes the canonical 15-metric vocabulary as the single override vocabulary, enforced at **two independent layers** — `billing.fn_is_canonical_usage_metric` (raising `P0001`) and the table CHECK `chk_qo_metric_canonical` (raising `23514`). Canonical metrics missing from the override layer = **0**. `ACTIVE_AGENTS` is accepted; **`AGENT_COUNT` is rejected, not aliased** — no legacy alias was introduced (§10A.4). Scope boundary stated explicitly: `billing.quota_configs.metric` remains plain `TEXT` with no CHECK (`052_5H.sql:7`) and was deliberately **not** retro-constrained, because narrowing the committed commercial/base layer is outside this pass's authorization. Live evidence: `FAR_111_02` Battery A | **CLOSED BY MIGRATION `111_5H4`** |
| `FAR-P1-05` | **P1** | **Raised by the `111_5H4` pass.** Two compounding defects in the pre-`111` override design. (a) *Overwrite-in-place:* migrations `106` / `107` applied a quota override as `INSERT … ON CONFLICT ON CONSTRAINT uq_qc_org_metric DO UPDATE SET soft_limit = …, hard_limit = …`, which **destroys the commercial baseline**. After a temporary override expired there was nothing to fall back to, because the sold value had been overwritten by the override value. (b) *Fail-open:* `110_5C2`'s admission guard read `IF NOT FOUND OR v_hard_limit IS NULL THEN RETURN; END IF;` — so a missing or `NULL`-limit configuration **admitted without limit**. Combined, the system failed **open**, granting more than was sold | Resolved by `FAR-OD-02` = **Option B** (§10A): base and override become **two separate persistence layers** — the override never writes to `billing.quota_configs` — and the effective value is **computed, never stored**, by `billing.fn_resolve_effective_quota(organization_id, metric)`. On expiry the effective value falls back to the **CURRENT** base, not to a stale historical base and not to unlimited. Live evidence: `FAR_111_02` Battery B — B1 base `1000`; B2 override `2000` wins with source `PLATFORM_OVERRIDE`; **B4** the base is raised to `1200` *while the override is active* and the effective value is still `2000`; **B5** after expiry the effective value is **`1200`** with source `BASE` — the current base, proving the fallback is live and not a snapshot | **CLOSED BY MIGRATION `111_5H4`** |
| `FAR-P2-04` | P2 | **The `created_by` non-member negative-evidence gap.** The `110_5C2` master ledger closed `FAR-P2-03` on code inspection, catalog inspection and the positive path, and disclosed plainly that the **negative** non-member case had not been separately transcribed. That disclosure was honest but left the guard's rejection behaviour proven only by reading the function body, not by executing it | **Closed by direct transcript.** `FAR_111_03_security_integration_battery.txt`, **Battery H**, **7/7**: H.0 establishes the roster (the outsider has `outsider_membership_rows = 0`); H.1 an outsider non-member is **refused `P0001`**; H.2 an other-tenant member is **refused `P0001`**; H.3 a `NULL` actor is **refused `P0001`**; H.4 a valid same-tenant member **succeeds** (control, agent `01a0a5ab-…`); H.5 confirms H.1–H.3 created **no Agent row**; H.6 the **clone** path applies the same actor guard; H.7 `app_api` **cannot** call `fn_assert_agent_actor` directly (`42501`). The guard itself was not modified — only the evidence set changed, so `110_5C2` needed no amendment | **CLOSED BY EVIDENCE (`FAR_111_03` Battery H)** |
| `FAR-P2-05` | P2 | **Overbroad privileged/superuser security wording.** Earlier text asserted, in effect, that there was "no privileged escape hatch". Stated absolutely that claim is **false for PostgreSQL**: a superuser or the table owner can always issue `ALTER TABLE … DISABLE TRIGGER`, `CREATE OR REPLACE FUNCTION` or direct DDL. Publishing an unbounded claim would misrepresent the guarantee to the independent reviewer | **Closed by adopting a precise, scoped security statement** in place of the absolute one, verbatim wherever the claim appears: *"Under normal SQL execution with the defined triggers/functions/ACLs enabled, the tested runtime principals and tested privileged session cannot bypass the application invariant; deliberate superuser DDL or trigger-disabling actions are outside the application guarantee."* Adopted in `5K/MIGRATION_MANIFEST.md` (Row 110 narrative, where the absolute phrase was removed), in the `111` validation report §6, and in §17 of this document. Live evidence for the in-scope half: `FAR_111_03` Batteries E, G, I, J | **CLOSED BY SCOPED RESTATEMENT** |
| `FAR-OD-02` | **Owner decision** | Temporary quota overrides needed an authoritative persistence and fallback model. Option A (overwrite the base in place) is what `106`/`107` did and is the defect behind `FAR-P1-05`; Option B keeps the commercial baseline intact and computes the effective value | Owner decided **`FAR-OD-02` = Option B — temporary quota overrides with live baseline fallback.** Applied in full: recorded normatively in §10A (all sixteen contract points), carried by migration `111_5H4`, documented at source in 5H, 6E §43.12, 6K §53 and 6M §18/§66, and live-validated (§16.3) | **DECIDED AND APPLIED — no residual decision** |
| `FAR-OD-03` | **Owner decision** | `CONCURRENT_CALLS` was cited as a per-organization limit by 6D, 6H and 6K, but it had no governed home. The options were to treat it as an accumulated usage metric in the 15-metric vocabulary (Option A) or as a separate instantaneous **capacity / entitlement** domain (Option B) | Owner decided **`FAR-OD-03` = Option B**: `CONCURRENT_CALLS` is a separate **CAPACITY** domain, and usage and capacity are not collapsed. Applied in full: normative text in §10B, carried by migration `112_5H5`, documented at source in 5H, 6K §54, 6D §42, 6H §54 and 6M §67, and live-validated (§16.4) | **RESOLVED / APPLIED — no residual decision** |
| `FAR-OD-04` | **Owner decision** | The capacity reservation's counted lifetime had to be fixed against the frozen 6D call state machine: when a slot is acquired, when it is released, and what happens on transfer / resume | Owner confirmed **ADMISSION → TERMINAL**. One reservation per call is acquired once at outbound admission, idempotently. It is released once, idempotently, on setup failure or on entry to a frozen terminal state. Transfer and resume do **not** reacquire. Lowering the limit is non-destructive. Recorded in §10B.4, 6K §54.6, 6D §42.4 and 6H §54.2 / §54.5. **Status:** this is an API contract of record. The capacity runtime is IMPLEMENTATION-READINESS and is not claimed as implemented (§10B.4, §11) | **RESOLVED / APPLIED — no residual decision** |
| `FAR-P1-06` | **P1** | **Raised by the `112_5H5` pass.** `CONCURRENT_CALLS` was governed as a per-organization limit by three frozen API documents: 6D (`CheckQuota(CONCURRENT_CALLS)`), 6H (campaign dispatch fail-closed) and 6K (quota vocabulary, `429` mapping). It was **not representable in the database**. It sat outside the canonical 15-metric usage vocabulary, so `fn_platform_set_quota_override` could not write it and `fn_resolve_effective_quota` raised on it | Migration `112_5H5` creates the governed capacity domain: predicate, `billing.capacity_quota_overrides`, `fn_resolve_effective_capacity_quota`, and domain dispatch inside the unchanged 8-argument Platform-Admin setter. The controlled API amendments are 6K §54, 6D §42, 6H §54, 6M §67 and 5H. Evidence: `FAR_112_02` §§1–15 (§1 also records zero `%capacity%` billing functions at `111_5H4`), `FAR_112_03` §7; 112 report §2 | **CLOSED** (`112_5H5` + controlled API amendments) |
| `FAR-P2-06` | P2 | The handoff register's "Zero open handoffs across all 8 rows" was **overbroad**. It described eight traced cross-document handoffs but read as a whole-corpus claim, while the corpus declares many future, release-train and implementation-readiness items | Whole-corpus classification with an explicit dedupe method (§9.1): 142 `DEP-*` IDs plus 85 non-DEP entries, minus 14 `same_as` duplicates, gives **213 unique items**. The split is **105 CLOSED / 84 FUTURE — NON-BLOCKING / 4 RELEASE-TRAIN / 20 IMPLEMENTATION-READINESS / 0 BLOCKER** (§9.4). Result: **ZERO BLOCKING HANDOFFS**, with 108 non-closed items disclosed (§9.5, §11). The overbroad line is struck and marked historical, not deleted. SIP trunk support stays **RELEASE-TRAIN (V1)** | **CLOSED** (213-item classification) |
| `FAR-P2-07` | P2 | The route figures this document recorded (1,640 raw / 598 literal / 448 semantic / 55 groups / 32 multi-spelling) no longer matched the corpus. They were the intermediate state of the original pass, and the literal normalizations and the 112 amendments had since changed the text | **Current exact re-extraction** with the same extractor and matcher (no algorithm change) gives **1,683 / 595 / 448 / 55 / 31**. The 55-group set is **unchanged**: no group was added or removed, the arithmetic is A 0 + B 42 + C 3 + D 7 + E 0 + FP 3 = 55, and there is **zero Class E**. The only participation change is group 41 (`POST /calls`), which now spans 6D, 6E, 6H, 6K and 6M, with owner 6D and Class C. The old figures are kept and labelled historical / intermediate (§0, §1, §1.1, §2.1 row 41, §2.3) | **CLOSED** (current exact re-extraction) |
| `FAR-P2-08` | P2 | **NULL-unsafe vocabulary guard.** `p_metric = ANY(ARRAY[...])` yields `NULL`, not `FALSE`, for a `NULL` metric, and PL/pgSQL `IF NOT <NULL>` does not fire, so the guard silently let a `NULL` metric through | `112_5H5` wraps both predicates in `COALESCE(..., FALSE)`, and both resolvers check `p_metric IS NOT NULL` first. Evidence: `FAR_112_02` §2; `FAR_112_03` §7 H.5, H.5b, H.6 (both predicates return `f`) | **CLOSED BY `112_5H5`** |
| `FAR-P2-09` | P2 | Override audit events changed `resource_type` from `QUOTA_CONFIG` (before 111) to `QUOTA_OVERRIDE` (111 and later, both domains at 112), while earlier text implied the audit shape was unchanged | Recorded as a **controlled audit-contract extension**, not as "unchanged". `action_kind` stays `QUOTA_OVERRIDE_SET`, and the domain is carried in `resource_snapshot.quota_domain`. No migration is needed because the `audit.audit_events` constraints are length-only. Evidence: `FAR_112_02` §14; `FAR_112_03` §10.3 P10, §10.4 P11, §10.5 atomicity; 6M §67.6; §10B.7 | **CLOSED** (controlled audit-contract extension) |
| `FAR-P3-04` | P3 | **Overbroad security / superuser wording** in the capacity context: "unbypassable", and the implication that `FORCE ROW LEVEL SECURITY` binds a superuser | Scoped at every occurrence to the application runtime trust boundary (non-superuser application roles, normal SQL). Superuser / table-owner DDL, trigger disabling and `session_replication_role = replica` are stated as **outside** the guarantee. `BYPASSRLS` inventory unchanged (`app_migration`, `app_platform_admin` from `001_5B`, plus `postgres`). Recorded at: 5C (two controlled notes), 6K §54.10, 6M §67.7, 112 report §4, §10B.8 | **CLOSED** (security / superuser wording scoped) |
| `FAR-P3-05` | P3 | **Stale head statements.** 5C, 6E and the manifest still read "`110_5C2` is the (new / current) head", "no `111`", or "`111_5H4` is the current head … no `112`" | Additive `FAR-P3-05` controlled notes mark each statement historical and state the progression `109_5B7` → `110_5C2` → `111_5H4` → **`112_5H5` (current single head)**, no `113`. Placement: 5C (two notes), 6E (two notes) and `5K/MIGRATION_MANIFEST.md` (Row 111 notes). Original sentences are preserved, not rewritten. In this document the same supersession is applied by historical labels in §12.1, §12.3, §13, §14, §14.1, §15 and §17, and by §12.4 | **CLOSED** (5C / head supersession) |
| `FAR-P3-06` | P3 | **`111_5H4` over-attributes closure.** Its SQL header (`111_5H4.sql:13`) and Alembic docstring (`111_5H4.py:16`) list `FAR-P2-04` and `FAR-P2-05` among the tickets the migration closes. Neither needed DDL: `-04` was closed by evidence and `-05` by documentation | **Corrected by record, not by editing the frozen file.** `111_5H4` is untouched (222/222 frozen files byte-identical). The accurate attribution: the SQL implemented `FAR-OD-02` and closed `FAR-P1-04` / `-05`; `FAR-P2-04` closed by `FAR_111_03` Battery H; `FAR-P2-05` closed by scoped restatement. Recorded in the `FAR-P3-06` controlled note in `5K/MIGRATION_MANIFEST.md` Row 111, the 112 report §3.5 and this ledger | **CLOSED** (111 provenance correction without editing 111) |
| `FAR-P3-07` | P3 | **Mislabelled function set in the 112 evidence.** The 112 report §3.9 said "the five functions 112 created or replaced". The `FAR_112_03` §8.1 heading said "EXECUTE ACLs on every function 112 created or replaced". `FAR_112_01` §2 said "the three pre-existing functions it forward-replaces". None of these labels matches the SQL | **Controlled erratum.** `112_5H5.sql` has **four** `CREATE OR REPLACE FUNCTION` statements. It **replaces** `fn_is_canonical_usage_metric` and `fn_platform_set_quota_override`, and **creates** `fn_is_canonical_capacity_quota_metric` and `fn_resolve_effective_capacity_quota` (SQL lines 147, 199, 373, 518). The fifth probed function, `fn_resolve_effective_quota`, belongs to `111_5H4` and is not modified by 112. Correct label: **"the five governed quota functions at head `112_5H5`"**. The measured result is unchanged. Erratum block in the 112 report §3.9; the raw transcripts are left verbatim (§10B.7, §16.4) | **CLOSED BY CONTROLLED ERRATUM** |

*(Historical — 111 pass: "The table holds 15 rows: 5 P1, 5 P2, 3 P3, 1 blocker, 1 owner decision." Superseded by the recomputation below.)*

**Ledger arithmetic — computed from the rows above, not asserted.** The table holds **26** rows (the original 15 plus 11 added by the `112_5H5` pass and the master-FAR closure): **6 P1, 9 P2, 7 P3, 1 blocker, 3 owner-decision rows** (6 + 9 + 7 + 1 + 3 = 26). The owner-decision **class** counts **4** decisions: `FAR-OD-01` has no standalone row. It is recorded in the `FAR-P2-01` row it closed and in §10. So the class tally below is 4 while the row count is 3.

| Class | Raised | Closed / resolved / superseded | **Open** |
|---|---|---|---|
| **FAR-P0** | 0 | 0 | **0** |
| **FAR-P1** | 6: `FAR-P1-01` … `-06` | 6: `-01` by `110_5C2`; `-02`, `-03` by amended `110_5C2`; `-04`, `-05` by `111_5H4`; `-06` by `112_5H5` + controlled API amendments | **0** |
| **FAR-P2** | 9: `FAR-P2-01` … `-09` | 9: `-01`, `-02` closed at source; `-03` by amended `110_5C2`; `-04` by `FAR_111_03` Battery H; `-05` by scoped restatement; `-06` by the 213-item classification; `-07` by current exact re-extraction; `-08` by `112_5H5`; `-09` as a controlled audit-contract extension | **0** |
| **FAR-P3** | 7: `FAR-P3-01` … `-07` | 7: `-01` resolved (no route collision); `-02` superseded by `FAR-P1-01`; `-03` closed at source; `-04` security wording scoped; `-05` head supersession notes; `-06` corrected by record; `-07` controlled erratum | **0** |
| **Database blockers** | 1: `DB-BLOCKER-FINAL-API-001` | 1: resolved by `110_5C2` (amended in place) | **0** |
| **Owner decisions** | 4: `FAR-OD-01`, `-02`, `-03`, `-04` | 4: `-01`, `-02`, `-03` decided **Option B**; `-04` decided **ADMISSION → TERMINAL**; all applied (§10, §10A, §10B) | **0 unresolved** |

**FAR-P0 = 0. Open FAR-P1 = 0. Open FAR-P2 = 0. Open FAR-P3 = 0. Unresolved owner decisions = 0. Open database blockers = 0.** Each `0` is the result of the row-by-row tally above, not a bare declaration, and every row names the artifact and evidence that closes it. No **ticket in this ledger** is left open or deferred to a later document. That is a statement about FAR tickets only. The corpus **does** carry disclosed non-blocking debt, which this ledger does not hide: **108** non-closed handoff items (84 FUTURE — NON-BLOCKING, 4 RELEASE-TRAIN including V1 SIP trunk support, 20 IMPLEMENTATION-READINESS including the capacity runtime), registered in §9 and §11. *(Historical — 111 pass: the earlier sentence "No item in this ledger is carried forward as future debt" was accurate for the ledger rows but read as corpus-wide; it is superseded by this scoping.)*

**Disclosure — second independent review.** An earlier revision of this document declared READY FOR INDEPENDENT REVIEW with this ledger ending at `DB-BLOCKER-FINAL-API-001`. A second independent review of that revision found **P0 = 0, P1 = 2, P2 = 1**: `FAR-P1-02` (a fractional `hard_limit` admitted one Agent too many), `FAR-P1-03` (a raw `UPDATE` could re-enter the counted set) and `FAR-P2-03` (`created_by` was trusted without a tenant cross-check). It also judged the earlier claim that the quota was "structurally un-bypassable" overstated, because that claim rested on the `INSERT` revoke alone. All three findings were remediated by amending `110_5C2` **in place** (no migration `111` at that time; *historical, superseded by §12.3 / §12.4*) and re-validated live on disposable PostgreSQL 18.6 databases. They are recorded as their own rows above rather than folded silently into the earlier rows. All pre-amendment `110_5C2` hashes and transcripts are **SUPERSEDED** (§16.1).

---

## 14. Cross-Phase Status Register

Per-document terminal status **as declared by each document itself** — not asserted by this pass.

| Doc | Status (self-declared) |
|---|---|
| 6A | **APPROVED / FROZEN** (§42) — foundational architecture/standards; governs 6B onward |
| 6B | Multi-dimension final approval (§38); reconciled with 6M's break-glass findings in a disclosed 5th pass |
| 6C | **APPROVED / FROZEN** as of Revision 7 |
| 6D | **APPROVED / FROZEN** (§40) — two auth-matrix literals corrected this pass (§12 edit #5) |
| 6E | **CANDIDATE — APPROVED/FROZEN CANDIDATE**, pending independent review; `DEP-6E-20` now closed (§9), `DEP-6E-16` remains non-blocking |
| 6F | **APPROVED / FROZEN** (updated 2026-08-24, post-Phase-5L.2) |
| 6G | **APPROVED / FROZEN CANDIDATE** |
| 6H | **APPROVED / FROZEN, LIVE-VALIDATED ON POSTGRESQL 18 AND POSTGRESQL 16** (baseline clarified, §8) |
| 6I | **APPROVED / FROZEN** (2026-08-29, FINAL Blocker Remediation pass; unconditional) |
| 6J | **IMPLEMENTATION READY** — zero P0, zero implementation-blocking P1; does not self-declare FROZEN |
| 6K | **READY FOR INDEPENDENT FREEZE-GATE REVIEW** — DEC-6K-01…04 ACCEPTED, FINAL |
| 6L | **READY FOR INDEPENDENT FREEZE-GATE REVIEW** — explicitly does not self-freeze |
| 6M | **READY FOR INDEPENDENT FREEZE-GATE REVIEW** — migration `109_5B7` live-validated. Amended this pass for path-parameter normalization only (§3.3, §12 row 7); **Phase 6M is not reopened** |

No document in the corpus reports an unresolved P0/P1 blocker of its own. Documents amended this pass (6D, 6E, 6H, 6K, 6M) keep the status they declare for themselves; this pass re-declares nothing.

**Post-`112_5H5` addendum.** The status column above is unchanged by the `112_5H5` pass. That pass added one controlled amendment section each to 6D (§42), 6H (§54), 6K (§54) and 6M (§67), plus two `FAR-P3-05` head-supersession notes to 6E (change register: §12.4 of this document). None of these edits re-declares a document status. **Phase 6M is not reopened** by `112_5H5`: §67 is an additive capacity-domain amendment that adds no route and removes no route, role, error or SRS mapping.

### 14.1 Migration-head ownership — an explicit distinction

| Question | Answer |
|---|---|
| What is the **current project migration head**? | **`112_5H5`** — the single Alembic head, created by the `FAR-OD-03` / `FAR-OD-04` closure (`revision = '112_5H5'`, `down_revision = '111_5H4'`; `112_5H5.py` L183–184). *Historical note (111 pass): this row answered **`111_5H4`**, which was correct from the `FAR-OD-02` closure until `112_5H5` was created, and is superseded here. Historical note (110 pass): this row previously answered `110_5C2`. That answer was correct as at the `110_5C2` micro-remediation and is superseded here, not erased — `110_5C2` was the head from that pass until `111_5H4` was created.* |
| What is `110_5C2`'s standing now? | **The immediate parent of `111_5H4`**, and the carrier of the FAR Agent/Voice hard-quota admission remediation (`FAR-P1-01`, `-02`, `-03`, `FAR-P2-03`, `DB-BLOCKER-FINAL-API-001`). It is **no longer the project head**. It was **not amended again** by the `111_5H4` pass and is byte-identical to its post-micro-remediation state: SQL `3d5b2273…a9e26`, 27,979 B; Alembic `8885326e…76104`, 10,659 B (§16.3). |
| What is `111_5H4`'s standing now? | **The immediate parent of `112_5H5`**, and the carrier of the `FAR-OD-02` usage-override closure. It is **no longer the project head**. It was **not edited** by the `112_5H5` pass, and it is among the 222/222 byte-identical frozen files (`FAR_112_01` §2). Its over-attributed closure header is corrected by record, not by edit (`FAR-P3-06`, §13). |
| What does `112_5H5` own? | The **`FAR-OD-03` capacity / entitlement domain** (Phase 5H.5 by content, this reconciliation pass by provenance). It creates `billing.capacity_quota_overrides`, `billing.fn_is_canonical_capacity_quota_metric` and `billing.fn_resolve_effective_capacity_quota`. It forward-replaces `billing.fn_is_canonical_usage_metric` (NULL-safe, `FAR-P2-08`) and `billing.fn_platform_set_quota_override` (unchanged 8-argument signature, now dispatching by domain). That is four `CREATE OR REPLACE FUNCTION` statements (`FAR-P3-07`). The `FAR-OD-04` reservation lifecycle is an API contract (6K §54.6, 6D §42.4). It is **not** implemented in the database. |
| What does `111_5H4` own? | The **`FAR-OD-02` billing-quota-override closure** (Phase 5H.4 by content, this reconciliation pass by provenance): `billing.quota_overrides`, `billing.fn_is_canonical_usage_metric`, `billing.fn_resolve_effective_quota`, `billing.fn_platform_set_quota_override`, and a `CREATE OR REPLACE` of `voice.fn_assert_agent_quota_admission` so that admission reads the effective resolver (§10A, §16.3). |
| What was **Phase 6M's** head? | **`109_5B7`**, and it remains Phase 6M's frozen head **historically**. Phase 6M's own statements that no migration followed `109_5B7` were true within Phase 6M and are preserved as scope-clarified, not falsified (§12 row 11). |
| Did **Phase 6M create migration 110**? | **No.** `110_5C2` was created by this FINAL API RECONCILIATION DB-conformant closure pass, under the explicit one-migration authorization in the governing directive, to resolve `DB-BLOCKER-FINAL-API-001`. It belongs to Phase 5C.2 by content and to this reconciliation pass by provenance. |
| Is Phase 6M reopened? | **No.** 6M's only change this pass is literal path-parameter normalization (§3.3), which alters no route, role, error or SRS mapping. |
| Does a migration `111` exist? | **Yes — `111_5H4`.** *This row previously answered "No", which was true as at the `110_5C2` micro-remediation: that pass deliberately amended `110_5C2` in place rather than creating `111`. The answer is superseded, and the chronology is preserved rather than rewritten.* `111_5H4` was created subsequently, under the separate `FAR-OD-02` authorization, as the carrier for the temporary-quota-override architecture. |
| Does a migration `112` exist? | **Yes — `112_5H5`** (SQL `6c3c0e0c…fdb53`, 38,635 B; Alembic `fb53b23a…e238`, 12,673 B). *Historical note (111 pass): this row answered "No", with 0 files matching `^112`. That was true at the close of the `111_5H4` pass (§16.3), and is superseded here rather than erased.* |
| Does a migration `113` exist? | **No.** `find` over `5K/migrations` and `5K/alembic/versions` returns **0** files matching `^113` in either directory (§16.4). No migration `113` was created or authorized. |
| Is Phase 6M reopened by `112_5H5`? | **No.** `109_5B7` remains untouched and remains Phase 6M's historical frozen head. 6M §67 is additive (both quota domains behind the existing Platform-Admin override route) and reopens no route, role, error or SRS mapping. |
| Is Phase 6M reopened by `111_5H4`? | **No.** `109_5B7` remains Phase 6M's frozen head as a matter of project history, and remains untouched (SQL `a761239d…b0cf3`, Python `d60f497b…fb9602`). 6M's document changes in this pass are additive/corrective API text (§18, §28, §66, `FR-TEN-005`) and reopen no route, role, error or SRS mapping. |
| What is the full head chain? | `…` → **`109_5B7`** (historical frozen Phase 6M head) → **`110_5C2`** (FAR Agent admission) → **`111_5H4`** (FAR `FAR-OD-02` usage overrides) → **`112_5H5`** (**current single project head**, FAR `FAR-OD-03` / `FAR-OD-04` capacity domain). One linear chain, one head, no branch, no merge point, **no `113`**. *(Historical, 111 pass: the chain ended at `111_5H4` as "current project head" with "no `112`". Superseded.)* |

---

## 15. Final Acceptance Gate

| # | Check | Result |
|---|---|---|
| 1 | All 13 Phase 6 documents reconciled (targeted verification reads, not a from-scratch re-read) | ✅ |
| 2 | Route extraction reproducible and stated in both dimensions (1,640 / 598 literal / 448 semantic) | ✅. *(Historical / intermediate figures.)* ***Superseded by row 120***: the current exact re-extraction, with the same extractor and matcher, gives **1,683 / 595 / 448 / 55 / 31** (`FAR-P2-07`, §1.1) |
| 3 | Every cross-document collision group has its **own row** — no grouping, no "~", no "etc." | ✅ — 55 rows (§2.1) |
| 4 | Classification counts sum exactly to the total | ✅ — 0+42+3+7+0+3 = 55 (§2.2) |
| 5 | Fresh total differing from the prior "52" explained, not forced | ✅ (§2.3) |
| 6 | Every group has exactly one named canonical owner (or is a proven false positive) | ✅ |
| 7 | Zero Class-E true contradictions | ✅ |
| 8 | Zero unresolved auth contradictions | ✅ (§4) |
| 9 | Zero conflicting error semantics; no new error code invented | ✅ (§5, §10.6) |
| 10 | Zero cross-document DTO conflicts | ✅ (§6) |
| 11 | Event/audit/outbox single-mechanism discipline verified | ✅ (§7) |
| 12 | `DEP-6E-20` explicitly present in the Handoff ledger and **CLOSED** | ✅ (§9 row 1) |
| 13 | All other handoffs closed | ✅ (§9). *(Historical — this referred to the 8 traced register rows only.)* ***Superseded by rows 122–123***: a whole-corpus classification of **213** unique items gives **0 BLOCKER** and 108 disclosed non-closed items. It does **not** say all handoffs are closed (`FAR-P2-06`, §9) |
| 14 | `FAR-OD-01` = Option B applied: hard synchronous enforcement, server-side, in-transaction | ✅ (§10, 6E §43) |
| 15 | Naïve `COUNT`→compare→`INSERT` explicitly rejected; concurrency safety proven for quota N | ✅ (§10.1, §10.4) |
| 16 | Serialization mechanism follows the established project pattern rather than an invented one | ✅ — `SECURITY DEFINER` guarded function + `pg_advisory_xact_lock(hashtext(...))` + `REVOKE INSERT`, exactly the `041_5G.sql` shape |
| 17 | `DB-BLOCKER-FINAL-API-001` **raised** (an existing primitive ≠ an existing compliant enforcement path) and **resolved** by one authorized additive migration | ✅ (§10.1, §13) |
| 18 | `ACTIVE_AGENTS` counted set stated precisely and **derived**, not silently chosen | ✅ (§10.2, `FAR-P2-02`) |
| 19 | Effective quota resolved server-side from 6K; client-supplied limits/counts forbidden | ✅ (§10.3) |
| 20 | One quota authority; periodic 6K accounting retained for reporting/reconciliation only | ✅ (6K §52.2) |
| 21 | Canonical quota error reused from 6K; commercial quota distinguished from rate limiting | ✅ (§10.6) |
| 22 | Concurrency cases 1–5 documented normatively | ✅ (§10.5, 6E §43.5) |
| 23 | Idempotent replay cannot consume a second slot | ✅ (§10.7) |
| 24 | Slot-release semantic derived from 6K + 6E lifecycle, not guessed | ✅ (§10.8) |
| 25 | OpenAPI implementation readiness stated for `POST /agents` (no OpenAPI generated) | ✅ (§10.9) |
| 26 | Source-Document Change Register complete, in the mandated format, with the API-vs-DB architecture distinction stated | ✅ (§12) |
| 27 | Route literal consistency check performed; defects fixed; deliberate non-changes justified | ✅ (§3) |
| 28 | Legitimate deferred items preserved, none promoted to V1 to close reconciliation | ✅ (§11) |
| 29 | Historical PostgreSQL 16 evidence preserved; PostgreSQL 18 baseline stated | ✅ (§8) |
| 30 | No live `TBD`, `UNKNOWN` or pending-owner-decision entry anywhere in this document (the phrases occur only in §4, §13 and this row, each describing a closed or historical state) | ✅ |
| 31 | Zero FAR-P0, zero **open** FAR-P1 (including `FAR-P1-02` and `FAR-P1-03`, raised by the second independent review), zero unresolved owner decisions | ✅ (§13) |
| 32 | Migrations `001`–`109` and their Alembic wrappers **byte-identical to `HEAD`**; no earlier Phase 5 history rewritten | ✅ — 218 files compared, **0 differences** (§16.1). ***Superseded by row 85***, which re-measures the same property across `001`–`110` after `111_5H4`: **220 files, 0 differences** (§16.3) |
| 33 | Exactly **one** new migration created (`110_5C2`, amended in place by the micro-remediation); **no migration `111`** exists | ✅ *as measured at the `110_5C2` pass* — 110 SQL files and 110 Alembic `.py` files present, `111` count = 0 (§16.1). ***Superseded by rows 86–89***: migration `111_5H4` was subsequently created under the `FAR-OD-02` authorization, so the current inventory is **111** SQL / **111** Alembic with a single head `111_5H4` and **no `112`** (§16.3). ***Further superseded by rows 101–103***: `112_5H5` was created under the `FAR-OD-03` / `FAR-OD-04` authorization. The current inventory is **112** SQL / **112** Alembic, with single head `112_5H5` and **no `113`** (§16.4) |
| 34 | `FAR-P1-01` reclassified from P3 and **CLOSED BY MIGRATION `110_5C2`**; 6A §17.3 satisfied **without an exception**; 6A not weakened | ✅ (§10.1, §10.4, §13) |
| 35 | API/service/repository layer executes **no** `SELECT pg_advisory_xact_lock(...)` on the Agent-creation path | ✅ (§10.4, 6E §43.4, 6K §52.4) |
| 36 | Hard quota enforced at the database boundary on the `INSERT` edge: raw `INSERT ON voice.agents` revoked from every application role; guarded functions are the sole insert path | ✅ — live raw-INSERT battery denied for **all 8 runtime roles** (§16.2). The `UPDATE` re-entry edge is closed separately by `trg_agents_mutation_guard` (rows 55–57) |
| 37 | `PUBLIC` receives **no** `EXECUTE` on any new function; only intended roles can execute | ✅ — `has_function_privilege('public', …) = f` ×5 (all five `110_5C2` functions); `EXECUTE` to `app_api` only, and only on `fn_create_agent` / `fn_clone_agent`; no role can execute `fn_assert_agent_quota_admission`, `fn_assert_agent_actor` or `fn_agents_mutation_guard` (§16.2) |
| 38 | RLS not weakened; no accidental `BYPASSRLS`; `app_platform_admin` gains no new write bypass | ✅ — policy unchanged, enabled + forced, 0 new grants; `app_platform_admin` *lost* INSERT (§16.1) |
| 39 | No `AgentVersion` created on the Agent-creation path; version creation remains publish-only | ✅ — asserted in `110_5C2`, 6E §43.4; live clone-boundary case wrote **0** `agent_versions` (§16.1) |
| 40 | Counted `ACTIVE_AGENTS` predicate unchanged by the DB remediation; `DEPRECATED` still consumes no slot | ✅ — `FAR_DB_02` §13 lifecycle at limit 2: a third create is rejected `53400`; publishing keeps the Agent counted; deprecating frees exactly one slot, which is re-admitted exactly once (§10.2, §16.2) |
| 41 | Live PostgreSQL 18 validation performed on **disposable** databases: fresh `001 → 110`, incremental `109 → 110`, exactly one head | ✅ — both containers destroyed after the run (§16.1). ***Re-performed for `112_5H5` — see rows 104–105*** (fresh `001 → 112`, incremental `111 → 112`, containers `far112_*`) |
| 42 | Concurrency proven with **real concurrent processes**, not sequential statements | ✅ — two workers confirmed simultaneously blocked inside the function via `pg_locks` before the key was released (§16.1) |
| 43 | Agent row + `AGENT_CREATED` audit + `agent.created` outbox atomic in one transaction; rejection and rollback emit neither; no second event mechanism introduced | ✅ — 1/1/1 on commit, 0/0/0 on rollback and on rejection (§16.1) |
| 44 | Alembic wrapper follows the repository's existing forward-only policy; no destructive downgrade invented | ✅ — `downgrade()` raises `NotImplementedError` (§12.1 row 9) |
| 45 | Among pre-existing Phase 5 documents only `5C-Voice-Schema.md` and `5K/MIGRATION_MANIFEST.md` amended; the only other Phase 5 files touched are the authorized `110_5C2` SQL + Alembic pair, its validation report and its three evidence files; Phase-6M statements scope-clarified, not falsified; Phase 6M **not reopened**; `109_5B7` remains Phase 6M's historical head while `110_5C2` is the project head | ✅ *as at that pass* (§12.1, §14.1). ***Superseded by row 61 and §14.1***: the `111_5H4` pass additionally amended `5H-Billing-Usage-Schema.md` and added the `111_5H4` SQL + Alembic pair, its validation report and its three evidence files. `109_5B7` is still Phase 6M's historical head and Phase 6M is still **not** reopened, but the **project head is now `111_5H4`**. ***Further superseded by row 124 and §14.1***: the `112_5H5` pass amended 5C, 5H and the manifest again (controlled notes), added the `112_5H5` SQL + Alembic pair and its capped evidence set, and amended 6D, 6E, 6H, 6K and 6M. **Phase 6M is still not reopened**, and `112_5H5` is now the project head |
| 46 | Canonical permission string is `agent:write` everywhere; `agent:create` / `agents:write` appear nowhere as live strings | ✅ — verified against the 5B catalog (68 permissions; `agent:` = `read, write, publish, delete`) (§4, §10.9) |
| 47 | `FAR-P3-03` **closed at source**, not left as an open ticket for the API Master Index | ✅ (§3.3, §13) |
| 48 | Evidence capped at one report + three compact files; no per-statement execution-log sprawl; the micro-remediation rewrote those four files **in place** and created no new evidence file | ✅ *for the `110_5C2` evidence set* (§12.2, §16). ***Superseded by row 91***: the `111_5H4` pass added its own capped set — one report plus three compact files (`FAR_111_01/02/03`) — and rewrote none of the `110` evidence except to add scope notices. The repository now holds **two reports and six evidence files**, one capped set per pass; still no per-statement execution-log sprawl (§12.3) |
| 49 | Supporting ledgers expanded to the required coverage — Auth Contradiction (17 rows), Error Semantic (16), DTO / Contract (16), Event / Audit / Outbox (16, with an explicit five-class vocabulary), Handoff Closure (8) — each adjudicating **conflicts**, not enumerating a corpus-wide matrix or catalog | ✅ (§4–§7, §9). *(Historical — the Handoff Closure ledger's 8 rows were traced handoffs, not the corpus.)* ***Superseded for corpus coverage by rows 122–123*** (213-item classification, §9.1–§9.5) |
| 50 | The accepted **55-row** Endpoint Collision Ledger was **not** redone, and no global Authorization Matrix or Error Catalog was created in place of the ledgers | ✅ — §2.1 carries the same 55 groups this pass inherited; §4 and §5 each state the scope boundary explicitly |
| 51 | No forbidden artifact created (`API-MASTER-INDEX.md`, `AUTHORIZATION-MATRIX.md`, `ERROR-CATALOG.md`, `API-VERSIONING-STRATEGY.md`), no implementation code, no OpenAPI document | ✅ — `find` count = **0** (§16.1) |
| 52 | No extraction helper, `__pycache__`, `*.pyc` or `*.pyo` inside the repository; disposable validation containers destroyed | ✅ (§16.1). ***Re-verified after `111_5H4`*** — see row 96: the `111` containers `far_fresh` / `far_incr` are also destroyed and the repository is still free of cache and temporary-script artifacts (§16.3) |
| 53 | This document self-declares no APPROVED / FROZEN status for itself or any Phase 6 document | ✅ (§0, §14) |
| 54 | Fractional `hard_limit` (`NUMERIC(18,4)`) enforced as stored: admission rejects when `(active + 1) > hard_limit`; `FAR-P1-02` closed | ✅ — `FAR_DB_02` §2 **9/9**: limit 1.5 with 0 active admitted; 1.5 with 1 rejected `53400`; 0.5 with 0 rejected; 2 with 1 admitted; 2 with 2 rejected; clone at 1.5 with 1 rejected; clone at 2 with 1 admitted; no quota row admitted; `NULL` limit admitted. Concurrent fractional cases K (1.5) and L (2.5) also pass (§16.2) |
| 55 | Raw `UPDATE` cannot re-enter the counted set: `DEPRECATED` is terminal (→`DRAFT` and →`PUBLISHED` rejected), `organization_id` is immutable, `deleted_at` cannot be cleared (no resurrection), `DRAFT→DEPRECATED` rejected; `FAR-P1-03` closed | ✅ — `FAR_DB_02` §7 cases A, B, F, G, I rejected `P0001` for `app_api`, `app_worker` and `app_platform_admin` (`BYPASSRLS`); active count unchanged after every rejection (§16.2) |
| 56 | Legitimate lifecycle still works with `UPDATE` retained: `DRAFT→PUBLISHED`, `PUBLISHED→DEPRECATED`, same-state PATCH, soft-delete; raw `INSERT` still denied | ✅ — `FAR_DB_02` §7 cases C, D, E, H applied and J denied `42501`, **30/30** across the three writing roles; `FAR_DB_03` Part 1 §7 (§16.2) |
| 57 | The guard trigger binds every principal, `BYPASSRLS` roles and the superuser included (no `WHEN` clause, no role test) | ✅ — `FAR_DB_03` Part 1 §1b (enabled, `ROW`, `BEFORE UPDATE`) and Part 2b: as superuser, P2b-1…P2b-3 rejected `P0001` and P2b-4 `DRAFT→PUBLISHED` applied (§16.2) |
| 58 | `created_by` trust boundary: `fn_assert_agent_actor` rejects a `NULL` or non-member `created_by` in the same tenant; no public DTO change; `FAR-P2-03` closed | ✅ — code (`110_5C2.sql` lines 237–262; called at line 297 in create and line 367 in clone, before admission), catalog (`FAR_DB_03` Part 1 §1–§3: `SECURITY INVOKER`, no `EXECUTE` for any role), and the positive path exercised by every accepted create and clone. **The negative non-member case is not separately transcribed** (disclosed in §13 and §17). ***Superseded by row 82***: the negative case **is** now directly transcribed — `FAR_111_03` **Battery H, 7/7** — and the gap is tracked and closed as `FAR-P2-04`. The disclosure is retained here as the historical record of what the `110_5C2` pass could and could not prove |
| 59 | Amended `110_5C2` contains exactly five functions and one trigger; its final identity is recorded and the pre-amendment identity is marked SUPERSEDED | ✅ — `FAR_DB_03` Part 1 §1 (5 functions, 2 `SECURITY DEFINER`, 4 with a pinned `search_path`) and §1b (1 trigger); SQL `3d5b2273…a9e26`, 27,979 B; Alembic `8885326e…76104`, 10,659 B (§16, §16.1) |
| 60 | The second independent review's findings (P0 = 0, P1 = 2, P2 = 1) are disclosed, not hidden, and each is shown remediated | ✅ (§13 disclosure, §17) |
| **61** | **`FAR-OD-02` = Option B applied in full** — temporary quota overrides with live baseline fallback, recorded normatively with all sixteen contract points | ✅ (§10A, §13, §17; 5H, 6E §43.12, 6K §53, 6M §18/§66) |
| 62 | Canonical quota-metric vocabulary is the **15-metric** Phase-5H set, enforced at two independent layers (`fn_is_canonical_usage_metric` → `P0001`; `chk_qo_metric_canonical` → `23514`) | ✅ — `FAR_111_02` Battery A (§10A.4) |
| 63 | Canonical metrics **missing** from the override vocabulary = **0** | ✅ — all 15 accepted; set difference empty (§10A.4) |
| 64 | Legacy metric names are **rejected**, not silently accepted | ✅ — `23514 / chk_qo_metric_canonical` at the table layer and `P0001` at the function layer (`FAR_111_02` Battery A) |
| 65 | `ACTIVE_AGENTS` is a valid, overridable metric — the defect behind `FAR-P1-04` is closed | ✅ — accepted by both layers; exercised end-to-end in `FAR_111_03` Battery I |
| 66 | **`AGENT_COUNT` is rejected, not aliased** — no legacy alias was introduced anywhere | ✅ — rejected identically to any other non-canonical string; zero alias mappings exist (§10A.4) |
| 67 | Base and override are **separate persistence layers**; an override **never** overwrites the base | ✅ — base `billing.quota_configs` untouched by `fn_platform_set_quota_override`; override rows live only in `billing.quota_overrides` (§10A.1, `FAR_111_02` Battery B4) |
| 68 | An active, non-superseded override **wins** over the base | ✅ — `FAR_111_02` B2: base `1000`, override `2000`, effective **`2000`**, source `PLATFORM_OVERRIDE` |
| 69 | On expiry the effective value falls back to the **CURRENT** base — not a stale historical base, not the previous superseded override, not unlimited | ✅ — `FAR_111_02` B5: effective **`1200`**, source `BASE` (§10A.3) |
| 70 | A base change made **while an override is active** does not disturb the override, and takes effect once the override ends | ✅ — `FAR_111_02` B4: base raised `1000 → 1200` mid-override, effective still **`2000`**; then B5 yields **`1200`** |
| 71 | A **permanent** override is expressed as `expires_at IS NULL` and remains effective until superseded | ✅ — `FAR_111_02` Battery D; `chk_qo_expires_after_start` permits `NULL` and rejects `expires_at <= effective_from` |
| 72 | `hard_limit IS NULL` means **unlimited** on the effective result and is reported as such; it is not coerced to a number and no integer-only restriction is imposed | ✅ — `NUMERIC(18,4)` throughout, compared **as stored**; `FAR_111_02` Battery F |
| 73 | A **superseded** override never reactivates — supersession is one-way and terminal | ✅ — `superseded_at` set under one advisory lock; partial unique index `uq_qo_org_metric_current` structurally permits at most one current row per `(organization_id, metric)`, second insert `23505` (`FAR_111_02` Battery C) |
| 74 | The Platform-Admin override **write** path is secure: `SECURITY DEFINER`, `EXECUTE` to `app_platform_admin` only, `REVOKE ALL … FROM PUBLIC`, and no application role holds `INSERT`/`UPDATE`/`DELETE` on `billing.quota_overrides` | ✅ — `FAR_111_03` Batteries E and G; `42501` for every other principal |
| 75 | The Platform-Admin **read** model reflects actual override state (ACTIVE / EXPIRED / SUPERSEDED history) and is a read model, **not** a second quota authority | ✅ — 6M §66.3; `FAR_111_03` Battery G |
| 76 | The tenant-facing `GET /billing/quotas` reports **effective** values with a source label, under FORCED RLS, and requires **no** Platform-Admin privilege | ✅ — 6K §53; resolver is `SECURITY INVOKER` and callable by `app_api` / `app_worker` / `app_readonly` (`FAR_111_03` Battery J) |
| 77 | `ACTIVE_AGENTS` admission on `POST /agents` reads the **effective resolver**; `110_5C2`'s concurrency-safe database guard is retained and only the quota **source** changed | ✅ — `CREATE OR REPLACE voice.fn_assert_agent_quota_admission`; advisory lock, counted set and `53400` unchanged (`FAR_111_03` Battery I) |
| 78 | `POST /agents/{agent_id}/clone` reads the **same** resolver — no second code path, no divergent limit | ✅ — `FAR_111_03` Battery I clone cases |
| 79 | Lowering a limit below current usage is **non-destructive**: existing Agents remain, `auto_deprecated = 0`, `soft_deleted_rows = 0`, publish stays count-neutral, and only new create/clone is refused `53400` until admission would satisfy the limit | ✅ — `FAR_111_02` / `FAR_111_03` lower-limit cases (§10A.6). The database never deletes, deprecates or mutates customer Agents or phone numbers to make a quota true |
| 80 | Fractional-limit arithmetic is preserved end-to-end through the resolver: `(active + 1) > hard_limit`, compared as stored, never rounded | ✅ — `FAR_111_02` Battery F; `FAR-P1-02`'s fix survives the `111` replacement |
| 81 | Create/clone **concurrency** remains safe after the source change — the advisory lock still serializes admission | ✅ — `pg_advisory_xact_lock(hashtext('voice.agent_quota:' \|\| org))` retained verbatim; override writes take their own key `billing.quota_override:<org>:<metric>` (`FAR_111_03` Battery I) |
| 82 | The `created_by` **negative** case is **directly transcribed**, not inferred from code | ✅ — `FAR_111_03` **Battery H, 7/7**: non-member `P0001`, other-tenant member `P0001`, `NULL` actor `P0001`, valid member succeeds, 0 rows written by the rejected attempts, clone enforces the same guard, `app_api` denied `EXECUTE` (`42501`). Closes `FAR-P2-04` and supersedes row 58 |
| 83 | ACL / RLS / security posture: `billing.quota_overrides` has RLS **enabled and forced**; `PUBLIC` holds no `EXECUTE` on any new function; **no new `BYPASSRLS` role**; no existing policy weakened or dropped | ✅ — `FAR_111_03` Batteries E, G, J; `BYPASSRLS` remains only `app_migration`, `app_platform_admin` and `postgres`, all pre-existing |
| 84 | The override audit write (`QUOTA_OVERRIDE_SET` into `audit.audit_events.action_kind`) is **atomic with** the override creation/supersession — same transaction, nothing on rollback | ✅ — `FAR_111_03` Battery K.10c–K.10e |
| 85 | Migrations `001`–`110` and their Alembic wrappers **byte-identical to `HEAD`**; `110_5C2` **not** amended again by this pass | ✅ — **220 files compared, 0 differences**; 0 present in the working tree but absent from `HEAD` (§16.3). Supersedes row 32 |
| 86 | Frozen SQL migration count | ✅ — **111** files in `5K/migrations` (`001` … `111_5H4`) (§16.3). *(Historical — `111` state.)* ***Superseded by row 101*** (**112** files) |
| 87 | Alembic revision count | ✅ — **111** files in `5K/alembic/versions` (§16.3). *(Historical — `111` state.)* ***Superseded by row 101*** (**112** files) |
| 88 | Exactly **one** Alembic head, and it is `111_5H4` | ✅ — `alembic heads` → `111_5H4 (head)`; `down_revision = '110_5C2'`; linear chain, no branch, no merge point (§16.3). *(Historical — `111` state.)* ***Superseded by row 102***: the single head is now `112_5H5` |
| 89 | **No migration `112`** exists | ✅ — `^112` count = **0** in both `5K/migrations` and `5K/alembic/versions` (§16.3). *(Historical — `111` state.)* ***Superseded by row 102***: `112_5H5` exists; ***row 103*** records that no `113` exists |
| 90 | `111_5H4` identity recorded exactly | ✅ — SQL `5fe2bc96431236d637dbe2558c0c78d13ab17b7cce647aac3e61db2ac2f4c048`, **44,726 B**, 836 lines; Alembic `78b3fda47b22e9e5ef55b66ce4815a415578351a5e786f6977355cdd067e70ea`, **9,227 B**, 161 lines (§16.3). *(Still accurate: `111_5H4` is unchanged, see row 100.)* The `112_5H5` identity is recorded in row 101 |
| 91 | Evidence set for this pass is capped at one report plus three compact files, and no `110` evidence file was rewritten except to add a scope notice | ✅ — `FAR_111_01`, `FAR_111_02`, `FAR_111_03` + `FINAL_API_RECONCILIATION_111_VALIDATION_REPORT.md` (§12.3 rows 20–23). Supersedes row 48 |
| 92 | **No unresolved ticket** in the issue ledger: open P0 / P1 / P2 / P3 = **0 / 0 / 0 / 0**, computed from a 15-row tally rather than declared | ✅ (§13 arithmetic table). *(Historical — 15-row tally.)* ***Superseded by row 125***: a **26-row** tally, still 0 / 0 / 0 / 0 open |
| 93 | **No owner decision left unresolved** — `FAR-OD-01` = Option B and `FAR-OD-02` = Option B, both applied in full | ✅ (§10, §10A, §13, §17). *(Historical — two decisions.)* ***Superseded by row 98***: all **four** owner decisions are resolved and applied |
| 94 | **No database blocker open** — `DB-BLOCKER-FINAL-API-001` resolved; this pass raised no new blocker and no new `OWNER DECISION REQUIRED` item | ✅ (§13) |
| 95 | **No forbidden next-phase artifact** created: no `API-MASTER-INDEX.md`, `AUTHORIZATION-MATRIX.md`, `ERROR-CATALOG.md` or `API-VERSIONING-STRATEGY.md`; no implementation-readiness artifact, no FastAPI/application code, no frontend code, no OpenAPI output | ✅ — `find` count = **0** (§16.3) |
| 96 | Repository hygiene at close: no `__pycache__`, `*.pyc` or `*.pyo`; no temporary validation script or SQL file inside the repository (the harness stays in the session scratchpad); the disposable containers `far_fresh` and `far_incr` destroyed and **no unrelated container touched** | ✅ (§16.3). Re-verifies row 52 at the `111` state. *(Historical — `111` containers.)* ***Superseded for the `112` pass by rows 127–128*** |
| 97 | This pass declares **no** phase, document or migration APPROVED or FROZEN — including `111_5H4` itself; that determination belongs to the independent reviewer | ✅ (§0, §14, §17; `5K/MIGRATION_MANIFEST.md` Row 111 closing statement). ***Re-affirmed at the `112` state by row 130*** |
| **98** | **All four owner decisions are resolved and applied.** `FAR-OD-01` = B (hard synchronous `ACTIVE_AGENTS`). `FAR-OD-02` = B (temporary usage overrides with live baseline fallback). `FAR-OD-03` = B (`CONCURRENT_CALLS` is a separate CAPACITY domain). `FAR-OD-04` = ADMISSION → TERMINAL | ✅ (§10, §10A, §10B, §13) |
| 99 | Migrations `001`–`111` **byte-unchanged**: `110_5C2` and `111_5H4` were not amended by the `112` pass | ✅ — **222/222** frozen files (111 `.sql` + 111 `.py`) verified against the pre-authoring SHA-256 baseline: `FAR_112_01` §2, **OK = 222, FAILED = 0**. Also re-checked at master-FAR close against git `HEAD` (§16.4). Supersedes row 85 |
| 100 | `111_5H4` is untouched, and its closure over-attribution is corrected **by record only** (`FAR-P3-06`) | ✅ — the `111_5H4.sql` / `.py` identity in row 90 is unchanged. The correction lives in the `5K/MIGRATION_MANIFEST.md` Row 111 `FAR-P3-06` note, the 112 report §3.5 and §13 |
| 101 | Migration inventory and `112_5H5` identity | ✅ — **112** SQL files and **112** Alembic files. SQL `6c3c0e0c546ccfa845822e94781193f6a5516a0176de0ec3bd24449b1abfdb53`, **38,635 B**, 744 lines. Alembic `fb53b23ae715060fcffa987ee03b7411ae72f252f574e7ab8cd4241925f0e238`, **12,673 B**, 214 lines (§16.4) |
| 102 | **Single current head `112_5H5`**, linear chain `109_5B7` → `110_5C2` → `111_5H4` → `112_5H5`, with no branch or merge point | ✅ — `FAR_112_01` §7 (`alembic heads` on both databases). `down_revision = '111_5H4'` and no other revision names `112_5H5` or `111_5H4` as its parent (§14.1, §16.4) |
| 103 | **No migration `113`** | ✅ — `^113` count = **0** in both `5K/migrations` and `5K/alembic/versions` (`FAR_112_01` §4; re-checked §16.4) |
| 104 | Live PostgreSQL **18.6** fresh path `001 → 112` on a disposable database | ✅ — **PASS** (`FAR_112_01` §5; 112 report §3.1) |
| 105 | Live PostgreSQL **18.6** incremental path `111 → 112` on a disposable database | ✅ — **PASS** (`FAR_112_01` §6; 112 report §3.2) |
| 106 | **Catalog convergence**: fresh and incremental converge | ✅ — fingerprint lines **3,969 / 3,969**, identical (`FAR_112_01` §8; 112 report §3.3). Security-surface convergence is also PASS (112 report §3.4) |
| 107 | **Targeted 110 Agent-admission regression** and **targeted 111 usage-quota regression** at head `112` | ✅ — PASS / PASS (`FAR_112_03` §§1–5 and §6; 112 report §3.6, §3.7) |
| 108 | **Usage / capacity separation**: two vocabularies, two `CHECK`s, two resolvers, one dispatcher. `CONCURRENT_CALLS` is not a 16th usage metric, and `ACTIVE_AGENTS` / `AGENT_COUNT` are rejected by the capacity domain | ✅ — `FAR_112_02` §11; `FAR_112_03` §7 H.1–H.7b (§10B.1) |
| 109 | **NULL safety** of both vocabulary predicates (`FAR-P2-08`) | ✅ — `COALESCE(..., FALSE)`; `NULL` returns `f` from both (`FAR_112_02` §2; `FAR_112_03` §7 H.5, H.5b, H.6) |
| 110 | **Capacity resolver and override lifecycle** follow 111's rules: base, temporary override, expiry to the **current** base, base change under an override, permanent override, supersession, no reactivation | ✅ — `FAR_112_02` §§3–9; resolver `STABLE SECURITY INVOKER` with explicit `search_path` (§10B.3) |
| 111 | **Zero rows fails closed**: absent capacity configuration is never read as unlimited | ✅ — SQL zero-row result `FAR_112_02` §15. The consumer obligation is 6K §54.3: `503 DEPENDENCY_UNAVAILABLE`, `details.reason = "CAPACITY_QUOTA_NOT_CONFIGURED"` (§10B.3 case B) |
| 112 | **`NULL` `hard_limit` = explicitly uncapped**: a recorded configuration decision, distinct from an absent row | ✅ — `FAR_112_02` §10 (§10B.3 case A) |
| 113 | **Platform Admin dispatcher**: the unchanged 8-argument `fn_platform_set_quota_override`, returning `UUID`, routes usage metrics to `billing.quota_overrides` and `CONCURRENT_CALLS` to `billing.capacity_quota_overrides`, and refuses anything else with `P0001`. `EXECUTE` to `app_platform_admin` only | ✅ — `FAR_112_02` §12; `FAR_112_03` §8 (§10B.2; 6M §67.3) |
| 114 | **Audit transition** recorded as a controlled extension (`FAR-P2-09`): `QUOTA_CONFIG` → `QUOTA_OVERRIDE`, `quota_domain` in `resource_snapshot`, `action_kind` `QUOTA_OVERRIDE_SET`; audit is atomic with the write | ✅ — `FAR_112_02` §14; `FAR_112_03` §10.3–§10.5; 112 report §3.10 (rollback removes both rows) |
| 115 | **`FAR-P3-07` label erratum** applied, with raw evidence left verbatim | ✅ — 112 report §3.9 erratum block: four `CREATE OR REPLACE FUNCTION` statements (SQL lines 147, 199, 373, 518); the correct label is "the five governed quota functions at head `112_5H5`". The measured ACL / `SECURITY DEFINER` / `search_path` results are unchanged (§10B.7, §13) |
| 116 | **Admission → terminal lifecycle** (`FAR-OD-04`) recorded against the frozen 6D state machine with **no new state**: acquire once at the two outbound admission points before the provider is contacted, and hold across all 7 non-terminal states | ✅ — contract of record: §10B.4; 6K §54.6; 6D §42.2–§42.4. **Not claimed as implemented** (row 121) |
| 117 | **Idempotent acquire / release**: `ALREADY_HELD` never takes a second slot, `NOT_HELD` never decrements twice, and `reservation_id` = `voice.call_sessions.id` | ✅ — contract: 6K §54.4–§54.5; §10B.4, §10B.5 |
| 118 | **Setup-failure release, terminal release, and transfer / resume without reacquire** | ✅ — contract: release (A) on setup failure after `ADMITTED`; release (B) on entry to one of the 7 frozen terminal states; `ON_HOLD → ACTIVE` and `TRANSFERRING → ACTIVE` keep the slot (6K §54.6; 6D §42.4; §10B.4). Lowering the limit is non-destructive (6K §54.8; §10B.6) |
| 119 | **6D and 6H consume the single 6K authority**; the **campaign sub-ceiling is separate**. 6H at the limit → contact `DEFERRED` / `TENANT_CALL_QUOTA_REACHED`. 6D at the limit → `429 QUOTA_EXCEEDED`, `details.metric = "CONCURRENT_CALLS"`. `campaign:concurrency:{tenant_id}:{campaign_id}` is never the tenant gauge | ✅ — 6D §42.2, §42.3, §42.7; 6H §54.2, §54.4, §54.6; 6K §54.4, §54.7 (§10B.5). No endpoint, field, permission or top-level error code added |
| 120 | **Route counts are current**, from the exact re-extraction with the unchanged extractor and matcher: **1,683** raw, **595** literal, **448** semantic, **55** collision groups, **31** multi-spelling (`FAR-P2-07`) | ✅ — §1, §1.1. `1,640 / 598 / 448 / 55 / 32` is retained as historical / intermediate |
| 121 | **55-group collision set unchanged**, with **zero Class E**. Arithmetic A 0 + B 42 + C 3 + D 7 + E 0 + FP 3 = 55. The only participation change is group 41 (`POST /calls`), which now spans 6D, 6E, 6H, 6K and 6M with owner 6D and Class C. Capacity runtime and inbound admission are registered as IMPLEMENTATION-READINESS and FUTURE, not as implemented | ✅ — §2.1 row 41, §2.2, §2.3; §10B.4 status; §11 |
| 122 | **Handoff classification is whole-corpus and deduplicated**: 213 unique items = **105 CLOSED / 84 FUTURE / 4 RELEASE-TRAIN / 20 IMPLEMENTATION-READINESS / 0 BLOCKER** (`FAR-P2-06`) | ✅ — §9.1–§9.5. 105 + 84 + 4 + 20 + 0 = 213 |
| 123 | **ZERO BLOCKING HANDOFFS**, with the **108** non-closed items disclosed rather than hidden. SIP trunk support remains **RELEASE-TRAIN (V1)** | ✅ — §9.5, §11.1. No FUTURE or IMPLEMENTATION-READINESS item is described as implemented |
| 124 | **Security wording scoped** (`FAR-P3-04`): no claim that superuser, table-owner DDL, trigger disabling or `session_replication_role = replica` is inside the guarantee. **No new `BYPASSRLS`**; the inventory is `app_migration`, `app_platform_admin` (`001_5B`) and `postgres` | ✅ — §10B.8; 5C notes; 6K §54.10; 6M §67.7; 112 report §4; `FAR_112_03` §8.7 |
| 125 | **Issue ledger**: 26 rows (6 P1, 9 P2, 7 P3, 1 blocker, 3 OD rows); 4 owner decisions; **open P0 / P1 / P2 / P3 = 0 / 0 / 0 / 0**; unresolved owner decisions **0**; open DB blockers **0** — computed, not declared | ✅ (§13 arithmetic table). Supersedes row 92 |
| 126 | **Stale-statement sweep**: "no migration `112`", "`111_5H4` is the current project head", "1,640", "598", "32 groups", "zero open handoffs", "all 8 rows", "one authorized migration" and "exactly one migration" occur in this document **only** where labelled historical, superseded or pass-scoped. Every ticket ID from `FAR-P1-01` to `FAR-P3-07` and `FAR-OD-01` to `FAR-OD-04` is present | ✅ (§16.4) |
| 127 | **Repository hygiene at master-FAR close**: no `__pycache__`, `*.pyc` or `*.pyo`; no temporary script or SQL harness in the repository; no pending-placeholder marker; no new to-do marker introduced by the `112` pass | ✅ (§16.4) |
| 128 | **Disposable `112` validation containers** `far112_runner`, `far112_incr` and `far112_fresh` removed; network `far112_net` removed only if exclusive and unused; **no unrelated container touched** | ✅ — see the cleanup record in §16.4 |
| 129 | **No forbidden next-phase artifact**: no `API-MASTER-INDEX.md`, `AUTHORIZATION-MATRIX.md`, `ERROR-CATALOG.md` or `API-VERSIONING-STRATEGY.md`; no application code; no OpenAPI output; the next phase not started | ✅ — `find` count = **0** (§16.4) |
| 130 | This pass declares **no** phase, document or migration APPROVED or FROZEN, including `112_5H5` and this document. Nothing was committed, stashed or reset | ✅ (§0, §14, §17) |

---

## 16. Verification Evidence

> **SCOPE — THIS TABLE AND §16.1 / §16.2 ARE THE `110_5C2` CLOSURE RECORD (historical).**
> The table below, the `git status` transcript in §16.1 and the battery summaries in §16.2 were
> captured by the `110_5C2` micro-remediation pass and were **true and correct for that pass**.
> They are retained unedited as evidence of what that pass could and could not prove. They are
> **superseded as a description of the CURRENT repository**. §16.3 (the `111_5H4` pass) superseded
> them first and is itself now **historical**: the current inventory, head, hashes, hygiene and
> container state are recorded in **§16.4** (the `112_5H5` pass and master-FAR closure), which
> governs wherever §16.4 and any earlier record differ. Individual superseded rows are marked inline below.

| Check | Command | Result |
|---|---|---|
| Migrations `001`–`109` byte-identical to `HEAD` | `git show HEAD:<path> \| cmp -s - <path>` over every `≤109` SQL + Alembic file | **218 files, 0 differences** — ***superseded by §16.3 item 9***: the current measurement covers migrations `001`–`110` and is **220 files, 0 differences**; ***further superseded by §16.4 item 7***: `001`–`111`, **222 files, 0 differences** |
| Exactly one new migration (amended in place); no `111` | `ls …/5K/migrations/*.sql \| wc -l`; `ls …/5K/alembic/versions/*.py \| wc -l`; `ls …/migrations …/alembic/versions \| grep -c '^111'` | **110** SQL, **110** Alembic; `111` count = **0** — ***superseded by §16.3 items 6–8***: migration `111_5H4` was subsequently created under the `FAR-OD-02` authorization, so the current inventory is **111** SQL, **111** Alembic, and the count that is now **0** is `^112`; ***further superseded by §16.4 items 4–6***: `112_5H5` was created under `FAR-OD-03`, the inventory is **112** SQL, **112** Alembic, and the count that is now **0** is `^113` |
| `110_5C2` identity (amended) | `sha256sum`, `stat -c %s` | SQL `3d5b2273…a9e26`, 27,979 B; Alembic `8885326e…76104`, 10,659 B. Pre-amendment `3b76d835…` / `735366af…` are **SUPERSEDED** |
| Historical `109_5B7` unchanged | `sha256sum` vs the Phase-6M freeze record | SQL `a761239d…b0cf3`, Python `d60f497b…fb9602` — **match** |
| Single Alembic head | `alembic heads` (disposable DB) | `110_5C2 (head)` — ***superseded by §16.3 item 5***: still exactly one head, now `111_5H4`, with `110_5C2` as its immediate parent; ***further superseded by §16.4 item 3***: exactly one head, now `112_5H5`, with `111_5H4` as its immediate parent |
| Fresh + incremental legs | `alembic upgrade head` on two disposable PG18 containers | exit 0 / exit 0 |
| Fractional-limit battery | `FAR_DB_02` §2, nine cases on `NUMERIC(18,4)` limits | **9/9 PASS** |
| Live concurrency battery | `FAR_DB_02` §11, cases A, B, E, K, L — two real worker processes + `pg_locks` observation | **PASS** — 2 workers simultaneously blocked in every case; limit respected in every case |
| UPDATE / reactivation battery | `FAR_DB_02` §7, ten cases × `app_api`, `app_worker`, `app_platform_admin` | **30/30 PASS** |
| Sequential quota / tenant / clone battery | `FAR_DB_02` §13 | **PASS** |
| Audit / outbox atomicity | `FAR_DB_02` §15 | **PASS** — 1/1/1 on commit; nothing on rollback or rejection; 0 locks after |
| Privilege / RLS / bypass battery | `FAR_DB_03`: `pg_proc`, `pg_trigger`, `has_function_privilege`, ACL and `pg_policy` inspection; raw INSERT as all 8 roles (Part 2) | **PASS** — `PUBLIC` `EXECUTE` = `f` ×5; RLS enabled + forced, policy unchanged |
| Guard binds the superuser | `FAR_DB_03` Part 2b | **PASS** — 3 re-entry attempts rejected `P0001`; legitimate publish applied |
| No forbidden artifact | `find docs -name 'API-MASTER-INDEX.md' -o -name 'AUTHORIZATION-MATRIX.md' -o -name 'ERROR-CATALOG.md' -o -name 'API-VERSIONING-STRATEGY.md' \| wc -l` | **0** |
| No stray build artifacts | `find docs -name '__pycache__' -o -name '*.pyc' -o -name '*.pyo' \| wc -l` | **0** |
| Disposable containers destroyed | `docker ps -a \| grep far-pg18` | **none** — ***re-verified after `111_5H4`***, see §16.3 item 21: the two containers of the later pass (`far_fresh`, `far_incr`) were likewise destroyed, and no unrelated container was touched; ***re-verified after `112_5H5`***, see §16.4 item 17: `far112_runner`, `far112_incr`, `far112_fresh` and network `far112_net` removed, no unrelated container touched |
| Working-tree scope | `git status --short` | *(recorded at §16.1)* |

### 16.1 Verification run (actual output, 2026-09-15)

```text
$ files_compared=218 differences=0          # migrations 001-109 SQL + Alembic vs git show HEAD:
files_compared=218 differences=0

$ ls docs/phase-05-database-design/5K/migrations/*.sql | wc -l
110
$ ls docs/phase-05-database-design/5K/alembic/versions/*.py | wc -l
110
$ ls docs/phase-05-database-design/5K/migrations/ docs/phase-05-database-design/5K/alembic/versions/ | grep -c '^111'
0

$ sha256sum docs/phase-05-database-design/5K/migrations/110_5C2.sql \
            docs/phase-05-database-design/5K/alembic/versions/110_5C2.py
3d5b22737d1d8f58e7976037510b6a9aa42ea2087d6cdf3d7d6908a9208e9a26  110_5C2.sql   (27,979 bytes, 544 lines)
8885326ee0b085dbd1f6d7e5a1726ef8956c6027266bcc2281e588002a376104  110_5C2.py    (10,659 bytes)

$ sha256sum .../migrations/109_5B7.sql .../alembic/versions/109_5B7.py
a761239d7e63e3d2d982f4dbf7291b81711a24dc051c2577bc44ff46052b0cf3  109_5B7.sql
d60f497b9c6c494e051b86d2f086211c77aef8e6b46bc390321e179e83fb9602  109_5B7.py

$ grep '^revision\|^down_revision' .../alembic/versions/110_5C2.py
revision: str = '110_5C2'
down_revision: Union[str, None] = '109_5B7'

$ find docs -name 'API-MASTER-INDEX.md' -o -name 'AUTHORIZATION-MATRIX.md' \
            -o -name 'ERROR-CATALOG.md' -o -name 'API-VERSIONING-STRATEGY.md' | wc -l
0

$ find docs -name '__pycache__' -o -name '*.pyc' -o -name '*.pyo' | wc -l
0

$ docker ps -a --format '{{.Names}}' | grep -E 'far-pg18' || echo none
none

$ git status --short
 M docs/phase-05-database-design/5C-Voice-Schema.md
 M docs/phase-05-database-design/5K/MIGRATION_MANIFEST.md
 M docs/phase-05-database-design/5K/alembic/versions/110_5C2.py
 M docs/phase-05-database-design/5K/migrations/110_5C2.sql
 M docs/phase-05-database-design/5K/validation/FAR_DB_01_migration_and_integrity.txt
 M docs/phase-05-database-design/5K/validation/FAR_DB_02_quota_concurrency_battery.txt
 M docs/phase-05-database-design/5K/validation/FAR_DB_03_privilege_rls_bypass_battery.txt
 M docs/phase-05-database-design/5K/validation/FINAL_API_RECONCILIATION_DB_VALIDATION_REPORT.md
 M docs/phase-06-api-design/6E-AI-Agent-APIs.md
 M docs/phase-06-api-design/6K-Billing-Usage-APIs.md
 M docs/phase-06-api-design/FINAL-API-RECONCILIATION.md
```

The earlier reconciliation pass — its 6D, 6H and 6M edits and the then-new `110_5C2` files, report and evidence — is committed at `HEAD` `16c0ee1`. The working tree therefore shows only the files touched by the `110_5C2` micro-remediation: the amended migration pair, the three evidence files and the validation report rewritten in place, the two Phase 5 documents (`5C-Voice-Schema.md`, `5K/MIGRATION_MANIFEST.md`), 6E, 6K and this document. That is eleven modified files and **zero untracked files**, with nothing else in the working tree. **No migration `001`–`109` was modified, no migration `111` exists, and no new evidence file was created.**

**All pre-amendment 110 hashes/transcripts are SUPERSEDED.** The pre-amendment identity — SQL `3b76d83515942f6e2193667e7c376e26cd1102bfb7926d080dda297e693d776c` (15,044 bytes) and Alembic `735366afb9141c9f31cb3b8ad05da10d63544f278890667a68431456bbf871d5` (5,810 bytes) — describes a migration that no longer exists on disk. The same applies to the pre-amendment "concurrency battery A–J, 10/10" and the "`PUBLIC` `EXECUTE` = `f` ×3" results recorded by earlier revisions of this section. They are kept here only as a labelled historical record, not as evidence.

**Correction of an earlier statement in this section.** A previous revision of §16.1 recorded "`109_5B7.sql` ← highest migration; no `110_*.sql` exists" and "No PostgreSQL, Alembic or Docker command was executed at any point in this pass." Both were true of the *earlier, pre-authorization* pass and are false now: the DB-conformant closure directive explicitly authorized one additive migration and **required** real PostgreSQL 18 validation. The superseded lines are replaced above rather than left standing.

### 16.2 Live database validation — summary

Real PostgreSQL **18.6** (`pgvector/pgvector:pg18`; the pgvector image is required because `034_5F.sql` creates the `vector` extension), Alembic 1.19.1 / SQLAlchemy 2.0.52 / psycopg2 2.9.12. Two **disposable** containers (`far-pg18-fresh`, `far-pg18-incr`), both destroyed at the end of the pass — verified above. No persistent or shared database was used.

| Leg | Result |
|---|---|
| Fresh `001 → 110` | **PASS** — exit 0, 0 errors, `current` = `110_5C2 (head)` |
| Incremental `109 → 110` | **PASS** — exit 0 as one discrete step |
| Exactly one head | **PASS** — `alembic heads` → `110_5C2 (head)` |

**Quota batteries, all run against the amended `110_5C2` (concurrency uses real processes — not simulated):**

- **Fractional limits (`FAR_DB_02` §2, 9/9):** limit 1.5 with 0 active → admitted; 1.5 with 1 → rejected `53400`; 0.5 with 0 → rejected; 2 with 1 → admitted; 2 with 2 → rejected; clone at 1.5 with 1 → rejected; clone at 2 with 1 → admitted; no quota row → admitted; `NULL` limit → admitted. The committed count never exceeds the stored limit.
- **Concurrency (`FAR_DB_02` §11, cases A, B, E, K, L):** a controller session held the guarded function's own advisory key while two worker processes were confirmed via `pg_locks` to be *simultaneously blocked inside the function* before release. **A** limit 5, none prefilled → both succeed. **B** limit 3, 2 prefilled → exactly one winner, exactly one `53400`. **E** clone, limit 3, 2 prefilled → exactly one winner, **0** `agent_versions` written. **K** limit 1.5, none prefilled, and **L** limit 2.5, 1 prefilled → exactly one winner each. Every rejection originates in `fn_assert_agent_quota_admission`, before either endpoint function's INSERT.
- **UPDATE / reactivation (`FAR_DB_02` §7, 30/30):** ten cases for each of `app_api`, `app_worker` and `app_platform_admin`. Rejected with `P0001`: `DEPRECATED→DRAFT`, `DEPRECATED→PUBLISHED`, moving `organization_id`, clearing `deleted_at`, `DRAFT→DEPRECATED`. Applied: `DRAFT→PUBLISHED`, `PUBLISHED→DEPRECATED`, same-state PATCH, soft-delete. Raw INSERT → `42501`. The active count is unchanged after every rejection.
- **Sequential quota / tenant / clone (`FAR_DB_02` §13):** at limit 2 a third create is rejected `53400`; `PUBLISHED` still counts; deprecating frees exactly one slot, which is re-admitted exactly once; a `NULL` limit and an absent quota row are unlimited; an org mismatch or missing tenant context is rejected `P0001`; cross-tenant and nonexistent clone sources return **byte-identical** `P0002` (non-disclosing); clone works from a `DRAFT` source and from a `PUBLISHED` version, and a foreign version is rejected `P0002`; `agent_versions` is unchanged.
- **Raw INSERT (`FAR_DB_03` Part 2):** denied for **all 8 runtime roles**, 0 rows committed.

**Privilege / RLS / guard battery (`FAR_DB_03`):** `PUBLIC` cannot execute any of the five `110_5C2` functions (`has_function_privilege('public', …) = f` ×5). `EXECUTE` is held by `app_api` only, and only on `fn_create_agent` / `fn_clone_agent`; no role can execute `fn_assert_agent_quota_admission`, `fn_assert_agent_actor` or `fn_agents_mutation_guard`. No role retains raw `INSERT` on `voice.agents`, so the directive's "if any role must retain raw INSERT" fallback does not apply to any role. `UPDATE` is deliberately retained for the 6E lifecycle (`app_api`, `app_worker`, `app_platform_admin`) and is constrained by `trg_agents_mutation_guard` (`BEFORE UPDATE`, `FOR EACH ROW`, enabled, no `WHEN` clause, no role test). `app_platform_admin` *lost* INSERT and gained nothing. RLS remains enabled **and** forced, with the policy unchanged and **0** new grants. `app_migration` and `app_platform_admin` hold `BYPASSRLS`, which skips row-level *policies* but not table-level *ACLs* or triggers — demonstrated live, not assumed. Run as the superuser (Part 2b), the trigger still rejected all three re-entry attempts with `P0001` and let a legitimate `DRAFT→PUBLISHED` through. Deliberate out-of-band DDL by the table owner or a superuser, such as disabling the trigger, is outside this claim, as it is for any database constraint.

**Transactional integrity (§15 of the directive):** Agent row + `AGENT_CREATED` audit + `agent.created` outbox commit **1/1/1** in one transaction; an explicit `ROLLBACK` persists none of the three; a quota rejection emits **no** audit event and **no** outbox event. No second event mechanism was introduced.

Full evidence: `docs/phase-05-database-design/5K/validation/FINAL_API_RECONCILIATION_DB_VALIDATION_REPORT.md` plus `FAR_DB_01_migration_and_integrity.txt`, `FAR_DB_02_quota_concurrency_battery.txt`, `FAR_DB_03_privilege_rls_bypass_battery.txt`. One report, three files — all rewritten in place by the micro-remediation, with no new evidence file and no evidence sprawl.

The route-extraction helper and its JSON output live only under the session scratchpad, outside the repository, and are not part of this deliverable.

---

### 16.3 Post-`111_5H4` Final Billing / Quota Override Validation

> **SCOPE — §16.3 IS THE `111_5H4` CLOSURE RECORD (historical).** It was the current inventory when
> captured and is retained unedited as evidence of that pass. It is **superseded as a description of
> the CURRENT repository by §16.4** wherever the two differ; in particular items 2, 4, 5, 6, 7, 8, 9,
> 12 and 22 below describe the repository at head `111_5H4` and are marked inline. Everything else in
> §16.3 remains valid for migration `111_5H4`, which `112_5H5` did not amend (§16.4 item 7).
Every value below is captured output from `FINAL_API_RECONCILIATION_111_VALIDATION_REPORT.md`,
`FAR_111_01_migration_integrity.txt`, `FAR_111_02_override_resolver_battery.txt` and
`FAR_111_03_security_integration_battery.txt`. Nothing here is inferred.

1. **Engine.** PostgreSQL **18.6** (Debian 18.6-1.pgdg12+2) on x86_64, image `pgvector/pgvector:pg18`
   — the pgvector image is required because `034_5F.sql` creates the `vector` extension. Disposable
   throwaway databases only; no project or customer data at any point.
2. **Fresh leg.** `001 → 111_5H4` applied to an empty database — **PASS**, exit 0, reaching head
   `111_5H4`. ***Historical (111 pass); current fresh leg `001 → 112_5H5`: §16.4 item 1.***
3. **Incremental leg.** `… → 109_5B7 → 110_5C2 → 111_5H4` applied as discrete steps — **PASS**,
   exit 0, same head. `110_5C2`'s five functions, its trigger and its privilege posture are re-proven
   intact by this leg.
4. **Chain convergence.** `diff objects_fresh.txt objects_incr.txt` produced **no output** — the two
   catalogs are **identical, 113 lines each**. The fresh and incremental paths are indistinguishable.
   ***Historical (111 pass): the `112_5H5` catalog fingerprint is 3969 / 3969 lines, identical — §16.4 item 2.***
5. **Single head.** `alembic heads` returns exactly one revision: **`111_5H4`**, with
   `down_revision = '110_5C2'`. One linear chain, no branch, no merge point. ***Historical (111 pass);
   superseded by §16.4 item 3: the single head is now `112_5H5`.***
6. **SQL migration count.** **111** files in `5K/migrations`. ***Historical (111 pass); now 112 — §16.4 item 4.***
7. **Alembic revision count.** **111** files in `5K/alembic/versions`. ***Historical (111 pass); now 112 — §16.4 item 4.***
8. **No migration `112`.** Files matching `^112` in either directory: **0**. The next step after this
   pass is independent review, not another migration. ***Historical, superseded by §16.4 items 5–6:*** *migration
   `112_5H5` was subsequently created under the owner's `FAR-OD-03` authorization; the absent revision is now `113`.*
9. **Frozen history.** Every tracked file at or below `110` compared byte-for-byte against
   `git show HEAD:<path>`: **220 files compared, 0 differences, 0 present-but-absent-in-`HEAD`**.
   Migrations `001`–`110` and their Alembic wrappers are byte-identical to `HEAD`, and **`110_5C2`
   was NOT amended again by this pass**. ***Historical (111 pass); superseded by §16.4 item 7: 222 files (`001`–`111`),
   0 differences.***
10. **Historical Phase 6M head `109_5B7`, reconfirmed unchanged.** SQL
    `a761239d…b0cf3` (53,473 B); Python `d60f497b…fb9602` (4,949 B). Phase 6M is **not** reopened.
11. **Immediate parent `110_5C2`, reconfirmed unchanged.** SQL `3d5b2273…a9e26` (27,979 B, 544 lines);
    Alembic `8885326e…76104` (10,659 B, 194 lines) — identical to the values §16 recorded for the
    amended `110_5C2`.
12. **`111_5H4` identity** *(head at the time of the 111 pass — historical label; now the immediate parent of `112_5H5`, identity unchanged, §16.4 item 7)*. SQL
    `5fe2bc96431236d637dbe2558c0c78d13ab17b7cce647aac3e61db2ac2f4c048` (44,726 B, 836 lines);
    Alembic `78b3fda47b22e9e5ef55b66ce4815a415578351a5e786f6977355cdd067e70ea` (9,227 B, 161 lines).
13. **Evidence files of this pass (three).** `FAR_111_01_migration_integrity.txt` (220 lines,
    12,366 B) — chains, head, object-dump equality; `FAR_111_02_override_resolver_battery.txt`
    (462 lines, 24,245 B) — Batteries A, B, C, D, F; `FAR_111_03_security_integration_battery.txt`
    (688 lines, 38,532 B) — Batteries E, G, H, I, J plus catalog/ACL/RLS and audit atomicity.
14. **Report of this pass.** `FINAL_API_RECONCILIATION_111_VALIDATION_REPORT.md` (239 lines,
    14,931 B), carrying the ten-battery coverage table, the acceptance gate, the artifact checksums
    and the disclosed caveats. **No placeholder remains in it**: the deferred-value marker that an
    earlier revision carried while container destruction was still pending has been replaced with
    the actual final cleanup statement, and a repository-wide search for that marker token now
    returns **zero occurrences**.
15. **Security posture.** Exactly **one** `SECURITY DEFINER` routine (the admin mutation path
    `fn_platform_set_quota_override`); every other routine is `SECURITY INVOKER` with an explicit
    `search_path` terminating in `pg_catalog`. `app_api` holds **no** `EXECUTE` on the admin mutation
    function — the 107-era grant is gone. No application role holds `INSERT`/`UPDATE`/`DELETE` on
    `billing.quota_overrides`; RLS is enabled **and FORCED**. **No new `BYPASSRLS`** — the inventory
    remains `app_migration`, `app_platform_admin`, `postgres`, all pre-existing. The claim is bounded
    by the scope statement recorded at `FAR-P2-05` in §13.
16. **`created_by` negative evidence — now direct.** `FAR_111_03` **Battery H, 7/7**: an outsider
    non-member is refused `P0001`, an other-tenant member is refused `P0001`, a `NULL` actor is
    refused `P0001`, a valid same-tenant member succeeds as the control, the rejected attempts wrote
    **0** Agent rows, the clone path enforces the identical guard, and `app_api` cannot call
    `fn_assert_agent_actor` directly (`42501`). This closes `FAR-P2-04` and supersedes the
    `110_5C2`-era disclosure that the negative case had not been separately transcribed.
17. **Lower-limit contract — non-destructive.** When the effective limit drops below current usage,
    by expiry, supersession or a deliberately lower override, the database **closes admission only**:
    new `ACTIVE_AGENTS` admissions are refused `53400`; **`auto_deprecated = 0`,
    `soft_deleted_rows = 0`**; an existing Agent may still transition `DRAFT → PUBLISHED` while the
    tenant is over limit; and the state is recoverable, because a new override re-opens admission
    without touching customer data. No Agent, phone number or other customer resource is deleted,
    deprecated or mutated to make a quota true.
18. **Effective-quota resolution.** `billing.fn_resolve_effective_quota(organization_id, metric)` is
    the single read authority: an active, non-superseded Platform Admin override wins; otherwise the
    **current** commercial base in `billing.quota_configs`; otherwise no configured quota. An
    override **never** overwrites the base — the two layers persist separately — and on expiry the
    resolver returns the **current** base, not a stale historical value, not a previous superseded
    override, and not unlimited unless the effective base itself carries a `NULL` `hard_limit`.
    Evidenced across Battery B and restated as §15 rows 68–71.
19. **Concurrency.** `ACTIVE_AGENTS` admission continues to use the concurrency-safe database guard
    established by `110_5C2` — `pg_advisory_xact_lock(hashtext('voice.agent_quota:' || org))` — with
    `111_5H4` changing only the quota **source** to the effective resolver. Simultaneous override
    writes are serialized by `pg_advisory_xact_lock` on the override key and by the partial unique
    index `uq_qo_org_metric_current`. Evidence: `FAR_111_03` Battery G.
20. **Audit atomicity.** The override audit record (`QUOTA_OVERRIDE_SET` written into
    `audit.audit_events.action_kind`) is committed **inside the same transaction** as the override
    creation or supersession; a refusal or a rollback leaves neither the override row nor the audit
    row. Evidence: `FAR_111_03` K.10c–K.10e.
21. **Disposable infrastructure destroyed.** `docker rm -f far_fresh far_incr` returned both names,
    and `docker ps -a --format '{{.Names}}' | grep -E '^far_(fresh|incr)$'` then returned **none**.
    Destruction happened **after** every transcript quoted in the evidence files was captured. The
    two throwaway databases (`far_v2` on host port 55441, `far_i2` on 55442) went with their
    containers. **No unrelated container was stopped, removed or otherwise touched.**
22. **Repository hygiene and working-tree scope.** No `__pycache__`, `*.pyc` or `*.pyo` anywhere in
    the repository; no temporary validation script, harness or scratch SQL file inside the
    repository — the harness lives in the session scratchpad, outside the repository tree; and none
    of the four forbidden artifacts exists (`find` count **0**). `git status --short` reports exactly
    **8 modified** and **6 untracked** paths, every one of them accounted for by the §12.3 change
    register: **zero unexpected files** (§12.3). ***Historical (111 pass); the current working-tree scope and
   hygiene record, including a later-found root-owned `__pycache__` that was removed, are §16.4 items 18–20.***

**Disclosed caveats are retained, not hidden.** The six limitations in §8 of the `111_5H4` report
stand as written — including step **E.6b**, which printed `FAIL` because an exception raised by an
earlier probe in the same `psql` `DO` block had already rolled back the agent that step was trying to
re-create. That is a **harness expectation error, not an engine defect**, and the transcript is kept
rather than removed. Likewise disclosed: the EXPIRED state was produced by deliberate superuser time
travel rather than by waiting out wall-clock expiry; `CREATE OR REPLACE` does not revalidate existing
rows behind a CHECK, so any future narrowing of the vocabulary needs an explicit revalidation; and
fixture planting in Batteries A, B and C used superuser to create starting conditions only, never to
make a result come out right.

### 16.4 Post-`112_5H5` Capacity-Quota Validation and Master-FAR Closure Record

*This subsection is the **current** inventory, validation and closure record for the repository. Where it*
*and §16, §16.1, §16.2 or §16.3 disagree, §16.4 governs. Those earlier records remain valid for the passes*
*they describe and are retained unedited: `FAR_DB_01..03` (migration `110_5C2`, §16–§16.2) and*
*`FAR_111_01..03` (migration `111_5H4`, §16.3) are **not** rewritten or withdrawn. The only class of*
*statement in them that is superseded is "no migration `111`" / "no migration `112`" and the head and*
*count statements that follow from it (112 report §6).*

Items 1–16 are captured output from `FINAL_API_RECONCILIATION_112_VALIDATION_REPORT.md`,
`FAR_112_01_migration_integrity.txt`, `FAR_112_02_capacity_quota_battery.txt` and
`FAR_112_03_cross_domain_security_regression.txt`, apart from the close-out re-checks noted in items 4–7.
Items 17–21 were measured at master-FAR close (2026-09-17), after those evidence files had been captured.
The full PostgreSQL validation and the DB batteries were **not** run again at close. Nothing here is inferred.

**Evidence set of the `112_5H5` pass**

| File (under `docs/phase-05-database-design/5K/validation/`) | Bytes | Lines | sha256 |
|---|---:|---:|---|
| `FAR_112_01_migration_integrity.txt` | 13,261 | 243 | `7847d6fdb1bd749056d78b9498d29e4225ffa96c40002c10486e70aa264f3fea` |
| `FAR_112_02_capacity_quota_battery.txt` | 49,207 | 1,009 | `a3390cf03ba25048748ba22a907aca39c82963105acae11a6bdbad12e5b6facc` |
| `FAR_112_03_cross_domain_security_regression.txt` | 59,661 | 1,154 | `604becf49b551dcbde4ae3a7ea316c337d4aa825ea0ba50724ef221e19c011bd` |
| `FINAL_API_RECONCILIATION_112_VALIDATION_REPORT.md` | 27,488 | 497 | `145cbf8fb790aba46bfc16512c896d70d7c620dd4a106dc7bc3e8f640c4fe3fb` |

**Identity of the current head (re-verified at close)**

| File | Bytes | Lines | sha256 |
|---|---:|---:|---|
| `5K/migrations/112_5H5.sql` | 38,635 | 744 | `6c3c0e0c546ccfa845822e94781193f6a5516a0176de0ec3bd24449b1abfdb53` |
| `5K/alembic/versions/112_5H5.py` | 12,673 | 214 | `fb53b23ae715060fcffa987ee03b7411ae72f252f574e7ab8cd4241925f0e238` |

1. **Engine and legs.** PostgreSQL **18.6** on image `pgvector/pgvector:pg18`, disposable databases
   only. **Fresh path `001 → 112_5H5`: PASS**, exit 0, all 112 revisions in one pass (`FAR_112_01` §5;
   report §3 row 1). **Incremental path `111_5H4 → 112_5H5`: PASS**, exit 0. A genuine pre-existing
   `111_5H4` usage override survived the upgrade unchanged and still resolves as `PLATFORM_OVERRIDE`
   (`FAR_112_01` §6; report §3 row 2).
2. **Catalog convergence.** Fingerprint over columns, constraints, indexes, function definitions
   (md5 of `pg_get_functiondef`), RLS policies and flags, table grants and triggers: **3969 / 3969
   lines, identical** (`FAR_112_01` §8; report §3 row 3). The security surface that fingerprint does not
   cover (role attributes, function ACLs, PUBLIC privileges) was probed separately on both instances
   and was **identical** (report §3.4, row 4; `FAR_112_03` DISCLOSURE 6).
3. **Single head.** `alembic current` = `alembic heads` = **`112_5H5`** on both instances, one
   `alembic_version` row (`FAR_112_01` §7; report §3.5). **Re-checked at close** by parsing every
   revision module: 112 revisions; heads = `['112_5H5']`; only `112_5H5.py` declares
   `down_revision = '111_5H4'`; no module declares `down_revision = '112_5H5'`; no duplicate parent.
4. **Counts.** **112** SQL files and **112** Alembic revision modules (`FAR_112_01` §4). Re-checked at
   close: 112 / 112; the only files matching `^112` are `112_5H5.sql` and `112_5H5.py`.
5. **No migration `113`.** Files matching `^113` in either directory: **0** (`FAR_112_01` §4; report §3
   row 6). Re-checked at close: **0**.
6. **Authorization.** `112_5H5` is the one additive migration authorized by `FAR-OD-03` = Option B
   (§10B, §12.4). It was not recreated at close, and no migration was created after it.
7. **Frozen history `001`–`111`.** SHA-256 manifest of all **222** frozen files captured before
   authoring: `OK = 222 FAILED = 0 entries = 222` (`FAR_112_01` §2; report §3 row 7). **Re-checked at
   close** against `git show HEAD:<path>`: **222 compared, 0 differences**. `110_5C2` and `111_5H4`
   were not amended. `111_5H4` still has SQL `5fe2bc96…c048` (44,726 B) and Alembic `78b3fda4…70ea`
   (9,227 B). Its over-attributing docstring is corrected in the ledger (`FAR-P3-06`), not in the frozen file.
8. **Targeted regressions.** `110_5C2` Agent admission (create/clone concurrency, fractional limit,
   actor and lifecycle guards): **PASS** (`FAR_112_03` §§1–5; report §3.6). `111_5H4` usage-quota
   override and resolver: **PASS** (`FAR_112_03` §6; report §3.7).
9. **Capacity domain.** Vocabulary, NULL-safe predicates, resolver, override lifecycle and supersession,
   NULL `hard_limit` uncapped, domain rejection, Platform Admin dispatcher, read model, audit resource
   contract, and zero-row fail-closed: **PASS** (`FAR_112_02` §§1–15; report §3.8, row 10).
10. **Domain separation.** USAGE and CAPACITY are not collapsed. Separation is enforced at three layers:
    - **Resolvers.** Each resolver rejects the other domain's metric, the legacy `AGENT_COUNT` and a
      `NULL` metric. The two vocabulary predicates are disjoint and NULL-safe (`FAR_112_03` §7 H.1–H.6).
    - **Table CHECKs.** `chk_qo_metric_canonical` and `chk_cqo_metric_canonical` refuse a cross-domain
      row even to the table owner (`FAR_112_02` §11).
    - **Dispatcher.** The Platform Admin dispatcher routes by domain (`FAR_112_02` §12).

    No row has crossed between the stores (`FAR_112_03` §7 H.7; report §3 row 11).
11. **Security.** One `SECURITY DEFINER` routine in the probed set (`fn_platform_set_quota_override`).
    Both resolvers are `SECURITY INVOKER` with explicit `search_path`. No PUBLIC `EXECUTE`. The setter
    is executable by `app_platform_admin` only (`app_api` revoked). No application role holds any
    write privilege on `billing.capacity_quota_overrides`. RLS is ENABLE + FORCE on all three
    governed quota tables. **No new `BYPASSRLS`**: `112_5H5` contains no role statement, and the
    holders remain `app_migration` and `app_platform_admin` (`001_5B.sql:41`, `:44`) plus `postgres`
    (`FAR_112_03` §§8–9, §11; report §3.9). The claim is bounded by the scope statement at `FAR-P3-04`
    (§10B.8) and `FAR_112_03` §11.3.
12. **Audit atomicity.** Baseline audit/capacity rows 13 / 7. Setter inside an explicit transaction
    gave 14 / 8. **`ROLLBACK`** gave **13 / 7**. A rejected call left 13 / 7 (`FAR_112_03` §10.5;
    report §3.10). Neither an override without its audit event nor the reverse is reachable.
13. **`FAR-P3-07` correction.** The report's §3.9 erratum block (L323, additive, no evidence re-run)
    corrects three labels: "the five functions 112 created or replaced" (report §3.9), "EXECUTE ACLs on
    every function 112 created or replaced" (`FAR_112_03` §8.1) and "the three pre-existing functions it
    forward-replaces" (`FAR_112_01` §2). `112_5H5.sql` has **four** `CREATE OR REPLACE FUNCTION`
    statements (L147, L199, L373, L518). Two replace pre-existing functions and two create new ones.
    The fifth probed function, `fn_resolve_effective_quota`, was not touched by 112. The raw transcripts
    in `FAR_112_01` and `FAR_112_03` are **left verbatim**. No PASS result depended on the label.
14. **Disclosed harness limitations retained.** Report §5 L1–L7 stand as written. They cover structural
    vs behavioural instances, `NOW()` as transaction timestamp, two mislabelled probe columns, two
    first attempts pointed at the wrong target, cumulative fixture state, owner-run cases and disposable
    single-node containers. Report §4 ("not claimed") also stands. The capacity **runtime**
    (reservation acquire/release) is **IMPLEMENTATION-READINESS**, not implemented. Inbound admission
    is **FUTURE**. The SIP trunk is **V1 RELEASE-TRAIN** (§10B.4, §11).
15. **Report verdict.** Report §3 rows 1–12: **all PASS**. Report §7 submits for independent review and
    does not approve, accept or freeze anything.
16. **API-side closure measured by this document.** Routes 1,683 raw / 595 literal / 448 semantic /
    55 collision groups / 31 multi-spelling, same extractor and matcher, collision set unchanged, zero
    Class E (§1.1, §15 rows 120–121). Handoffs 213 classified, **0 blocking**, 108 open and disclosed
    (84 FUTURE, 4 RELEASE-TRAIN, 20 IMPLEMENTATION-READINESS) (§15 rows 122–123). Ledger 26 rows,
    **0 open** (§13).
17. **Disposable infrastructure — cleanup at close (actual record).** Before: `far112_runner` (Exited 255,
    `python:3.11-slim`, network `far112_net`, bind mount of the repository) and `far112_incr` /
    `far112_fresh` (Exited 255, `pgvector/pgvector:pg18`, network `far112_net`, one anonymous volume
    each: `ce6ce6ed33b6…bc83005` and `9d2353d25304…268f984`). `docker rm -v far112_runner far112_incr
    far112_fresh` returned all three names, and their anonymous volumes went with them. `far112_net` then
    had 0 attached containers and no container referencing it, so `docker network rm far112_net`
    was run and succeeded. After: `far112_*` containers **0**, `far112_net` **absent**, both volumes
    **absent**. Every cleanup command named only the three `far112_*` containers and `far112_net`.
    **No unrelated container was stopped, removed or otherwise acted on.** At the close re-check,
    `freellmapi-freellmapi-1` and the five `learnhouse-*-dcbe3039` containers were Up and
    `charming_rosalind` was still Exited. No image was removed: `python:3.11-slim`,
    `pgvector/pgvector:pg18` and the unrelated `pgvector/pgvector:pg16` are still present.
18. **Hygiene.** At close, two `__pycache__` directories were found under `5K/alembic`
    (`alembic/__pycache__`, `alembic/versions/__pycache__`). They were root-owned, created 2026-09-16
    by `far112_runner`, and git-ignored (`.gitignore:11`), so they were never staged. They were removed
    with a transient, self-removing, network-less `python:3.11-slim` container mounting only
    `5K/alembic`, because the host user could not delete root-owned files. Recount: `__pycache__` /
    `*.pyc` / `*.pyo` = **0**. No temporary script, harness or scratch SQL is in the repository; the
    harness lives in the session scratchpad. The pending-placeholder marker occurs **0** times in the
    repository. No new to-do marker was introduced by the working-tree diff.
19. **Forbidden artifacts.** `API-MASTER-INDEX.md`, `AUTHORIZATION-MATRIX.md`, `ERROR-CATALOG.md`,
    `API-VERSIONING-STRATEGY.md` and any OpenAPI document: `find` count **0**. The next phase was not started.
20. **Working-tree scope.** `git status --short` reports **15** paths and **0** untracked
    (`--untracked-files=all`). There are 14 staged paths from the `112_5H5` pass: `M` 5C, 5H,
    `MIGRATION_MANIFEST.md`, 6D, 6E, 6H, 6K, 6M; `A` `112_5H5.py`, `112_5H5.sql`, `FAR_112_01/02/03`
    and the 112 report. There is 1 unstaged path, this document. Every path is in the §12.4 change
    register. Nothing was committed, stashed or reset.
21. **Static sweep of this document.** The listed stale statements are "no migration `112`", "`111_5H4`
    is the current project head", "1,640", "598", "32 groups", "zero open handoffs", "all 8 rows", "one
    authorized migration" and "exactly one migration". Each occurrence is either explicitly marked
    historical / intermediate / superseded, struck through, or quoted inside a ledger finding or gate row
    that describes the correction. Every ticket ID is present: `FAR-P1-01`..`06`, `FAR-P2-01`..`09`,
    `FAR-P3-01`..`07`, `FAR-OD-01`..`04`, `DB-BLOCKER-FINAL-API-001`.

---

## 17. Result

All **130** acceptance-gate checks pass (§15). They are:
- the 60 checks carried forward from the `110_5C2` closure;
- the 37 added by the `111_5H4` billing / quota-override closure (rows 61–97);
- the **33** added by the `112_5H5` capacity-quota closure and this master-FAR closure (rows 98–130).

Earlier rows that later passes overtook are scope-marked as historical and superseded, not deleted. Each carries a pointer to the row that replaces it.

*(Historical — `111_5H4` pass:)* ~~All **97** acceptance-gate checks pass (§15) — the 60 checks carried forward from the `110_5C2` closure, six of which are explicitly scope-marked as superseded rather than deleted, plus the **37** added by the `111_5H4` billing / quota-override closure (rows 61–97).~~

**Current closure state (`112_5H5`, master-FAR close).**

- **Ledger (§13):** FAR-P0 = **0**.
  - FAR-P1: **6** raised, **0** open.
  - FAR-P2: **9** raised, **0** open.
  - FAR-P3: **7** raised, **0** open.
  - `DB-BLOCKER-FINAL-API-001`: **1** raised, **0** open.
  - Owner decisions: **4**, **0** unresolved.
- **Tickets closed after the `111_5H4` pass:**
  - `FAR-P1-06`: closed by `112_5H5` plus controlled API amendments.
  - `FAR-P2-06`: closed by the 213-item handoff classification.
  - `FAR-P2-07`: closed by the current exact route re-extraction.
  - `FAR-P2-08`: closed by `112_5H5` (NULL-safe predicates).
  - `FAR-P2-09`: closed as a controlled audit-contract extension.
  - `FAR-P3-04`: security / superuser wording scoped.
  - `FAR-P3-05`: head-supersession notes.
  - `FAR-P3-06`: `111_5H4` over-attribution corrected by record; frozen file untouched.
  - `FAR-P3-07`: controlled erratum for the mislabelled function set; raw evidence verbatim (§16.4 item 13).
- **Routes (§1.1):** **1,683** raw, **595** literal, **448** semantic, **55** collision groups, **31**
  multi-spelling. Same extractor and matcher. The 55-group set is unchanged, with zero Class E. Group 41
  (`POST /calls`) now spans 6D, 6E, 6H, 6K and 6M.
- **Handoffs (§9):** **213** unique items: 105 CLOSED, 84 FUTURE — NON-BLOCKING, 4 RELEASE-TRAIN,
  20 IMPLEMENTATION-READINESS and **0 BLOCKER**. The result is **zero blocking handoffs**, not zero open
  handoffs. The **108** non-closed items are disclosed in §9.5 and §11. They are not future debt of any FAR
  ticket and are not hidden.

*(Historical — `110_5C2` / `111_5H4` passes; superseded by the current closure state above and by §13 / §9:)*

Zero FAR-P0. Zero **open** FAR-P1 — `FAR-P1-01` was raised, reclassified up from a mis-severity P3, and **closed by migration `110_5C2`**, not deferred; `FAR-P1-02` and `FAR-P1-03` were raised by the second independent review and are **closed by amended `110_5C2`**. Zero open FAR-P2: `FAR-P2-01` and `FAR-P2-02` are closed, and `FAR-P2-03` is **closed by amended `110_5C2`**. Zero open FAR-P3: `FAR-P3-01` is resolved, `FAR-P3-02` is superseded, and `FAR-P3-03` is closed at source rather than handed to a later index document. `DB-BLOCKER-FINAL-API-001` was **raised** — correcting an earlier revision of this document that wrongly recorded it as not raised — and is **resolved** by that same migration. Zero Class-E contradictions across the 55 collision groups, ~~zero open handoffs~~ *(overbroad; corrected by `FAR-P2-06` — zero **blocking** handoffs, 108 open non-blocking items disclosed)*, zero unresolved owner decisions, **zero items carried forward as future debt** from this pass *(scoped by §13 to FAR ledger tickets only)*.

`FAR-OD-01` = Option B is enforced as the owner decided: hard, synchronous, server-authoritative `ACTIVE_AGENTS` admission on both `POST /api/v1/agents` and `POST /api/v1/agents/{agent_id}/clone`, serialized **inside** the database and compared against the limit as stored, fractional limits included. Both edges of the counted set are closed at the database boundary. A row can enter it by `INSERT` only through the two guarded functions, because raw `INSERT` is revoked from every application role. It cannot re-enter it by `UPDATE`, because `trg_agents_mutation_guard` binds every principal, `BYPASSRLS` roles and the superuser included. Deliberate out-of-band DDL by the table owner or a superuser, such as disabling the trigger, is outside that claim. The enforcement is live-validated on PostgreSQL 18.6 against disposable databases with real concurrent processes. Frozen 6A §17.3 is satisfied **without an exception**, and 6A was not weakened to achieve it.

`FAR-OD-02` = Option B is likewise enforced as the owner decided: the commercial baseline lives in
`billing.quota_configs`, a temporary Platform Admin override lives in `billing.quota_overrides`, and
the effective value is resolved by `billing.fn_resolve_effective_quota(organization_id, metric)` —
active override first, otherwise the **current** base, otherwise no configured quota. An override
never overwrites the base, a superseded override never reactivates, and an expiry falls back to the
live baseline rather than to a stale value or to unlimited. `ACTIVE_AGENTS` admission keeps the
concurrency-safe guard `110_5C2` established and changes only its quota **source**. `FAR-P1-04`
(canonical-vocabulary divergence) and `FAR-P1-05` (fail-open on override expiry) were genuine P1
findings — the first would have let a non-canonical metric be quota-governed, the second would have
removed the limit entirely at the moment an override lapsed — and both are **closed by `111_5H4`**.
`FAR-P2-04` is **closed by direct transcript** (`FAR_111_03` Battery H, 7/7). `FAR-P2-05` is **closed
by scoped restatement**: under normal SQL execution with the defined triggers/functions/ACLs enabled,
the tested runtime principals and tested privileged session cannot bypass the application invariant;
deliberate superuser DDL or trigger-disabling actions are outside the application guarantee. No
client holds quota or pricing authority. `110_5C2` was **not** amended again and *(historical —
`111_5H4` pass; superseded below)* ~~**no migration `112`** was created~~.

`FAR-OD-03` = Option B is enforced as the owner decided. `CONCURRENT_CALLS` is a separate
**CAPACITY / ENTITLEMENT** domain, not one of the 15 usage metrics:
- its override store is `billing.capacity_quota_overrides`;
- its resolver is `billing.fn_resolve_effective_capacity_quota`;
- its vocabulary predicate is NULL-safe;
- the unchanged 8-argument Platform Admin setter dispatches writes by domain.

Usage and capacity are separated at three layers (resolvers, table CHECKs, dispatcher) and were never
collapsed (§16.4 item 10). Zero configured rows fail closed with `503 DEPENDENCY_UNAVAILABLE` and
reason `CAPACITY_QUOTA_NOT_CONFIGURED`. At the limit the result is `429 QUOTA_EXCEEDED` for API admission
and `DEFERRED` / `TENANT_CALL_QUOTA_REACHED` for campaign dispatch.

`FAR-OD-04` = ADMISSION → TERMINAL is recorded as an **API contract**:
- one reservation per call, keyed by `voice.call_sessions.id`;
- acquired once, idempotently, at outbound admission;
- released once, idempotently, on setup failure or on entry to a terminal state;
- transfer and resume do not reacquire;
- lowering the limit is non-destructive.

6D §42 and 6H §54 consume the 6K §54 authority. The campaign sub-ceiling is a separate key. The capacity
**runtime** is **IMPLEMENTATION-READINESS** and is **not** claimed implemented. Inbound admission is
**FUTURE**. The SIP trunk is **V1 RELEASE-TRAIN** (§10B.4, §11).

Migration `112_5H5` was live-validated on PostgreSQL 18.6:
- fresh `001 → 112` and incremental `111 → 112` both PASS;
- catalog 3969 / 3969 lines, identical;
- 110 and 111 regressions PASS;
- ACL / RLS / audit atomicity PASS;
- no new `BYPASSRLS`;
- `001`–`111` byte-unchanged (222 / 222).

**No migration `113`** exists (§16.4).

**Head chain.** `… → 109_5B7 → 110_5C2 → 111_5H4 → 112_5H5`.
- `109_5B7` remains the frozen historical **Phase 6M** head. Phase 6M is **not** reopened by `111_5H4`
  or `112_5H5`; 6M §67 is a controlled amendment, not a reopening.
- `110_5C2` and `111_5H4` are ancestors of the current head and were not amended.
- **`112_5H5` is the current single project head**, owned by the Final API Reconciliation / Phase 5H.5
  capacity-quota closure.

One linear chain, exactly one Alembic head, no `113`.

*(Historical — `111_5H4` pass; superseded by the paragraph above:)* ~~**Head chain.** `… → 109_5B7 → 110_5C2 → 111_5H4`. … **`111_5H4` is the current project head** … One linear chain, exactly one Alembic head, no `112`.~~

**Readiness for the next phase.** On the API side, the next artifacts (API Master Index, Authorization
Matrix, Error Catalog, API Versioning Strategy) have what they need to **begin after independent review**.
None of them has been created, and the next phase has not been started.

**Disclosure.** An earlier revision of this section declared this document ready for independent review. A second independent review then found **P0 = 0, P1 = 2, P2 = 1** (`FAR-P1-02`, `FAR-P1-03`, `FAR-P2-03`) and judged the earlier "structurally un-bypassable" wording overstated. Those findings were remediated by amending `110_5C2` in place and re-validating live; they are recorded in §13 and §15 rows 54–60, not hidden. ~~One evidence limit is stated plainly: the `FAR-P2-03` negative case (a non-member `created_by`) is verified by code and catalog inspection, not by a separate transcript.~~ ***Corrected by the `111_5H4` pass:*** *that limit no longer exists. The negative case is now **directly transcribed** — `FAR_111_03` **Battery H, 7/7** — and the gap is tracked and closed on its own ticket, `FAR-P2-04` (§13, §15 row 82, §16.3 item 16). The original sentence is struck in place rather than deleted so that the change in the evidence set remains auditable.*

This document does not declare itself, or any Phase 6 document, APPROVED or FROZEN.

# FINAL API RECONCILIATION = READY FOR INDEPENDENT REVIEW
