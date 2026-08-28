# 6G — CRM + Leads APIs

## AI Voice Agent Platform — Phase 6 — API Design — Phase 6G

---

## 1. Document Control

| Field | Value |
|---|---|
| Document | 6G-CRM-Leads-APIs.md |
| Phase | 6G (sixth business-domain document of Phase 6 — API Design) |
| Depends on | Phase 1 SRS, Phase 3C LLD, Phase 4C DDD (authoritative for domain semantics), Phase 5A/5B/5D/5J database design, Phase 5L Global Database Reconciliation, Phase 6A (binding standards), 6B–6F (precedent + boundary) |
| Status of dependencies | Phase 5 (5A–5J, 5K, 5K.1, 5L) is **APPROVED / FROZEN**. SQL/Alembic head: Revision 1 = `092_5F12`; Revision 2 = `096_5B2` (four controlled forward migrations, Phase 6G CRM Reconciliation, 2026-08-28); Revision 3 = `097_5D5` (one further controlled forward migration, a follow-up review finding, 2026-08-28) — see §5a. No previously frozen Phase 5 migration was ever modified; every reconciliation change to date has been an additive controlled forward migration, live-validated. 6A–6F are **APPROVED / FROZEN** and remain untouched. |
| Revision | **Revision 3** (2026-08-28) — supersedes Revision 2 in place. An independent whole-project review found that Revision 2's `crm.fn_merge_contacts()` copied the secondary Contact's name/phone directly into an immutable, GDPR-erasure-exempt Activity payload — a genuine erasure-boundary defect. Fixed via `097_5D5.sql` (§10.3, §5a). No 6A–6F change; 6H not started. |
| Author scope | CRM + Lead Management API design only (Contacts/Leads, Companies, Deals, Pipelines, Activities, Tasks, Notes, Appointments, Lead Scoring, Custom Fields, Consent, Suppression/DNC). No Campaign execution, no external CRM connectors, no Voice call-control endpoints, no Agent configuration. |
| Supersedes | Nothing (6G is a new document) |
| Governs | Nothing downstream directly, but 6H, 6J, 6K, 6L must consume the contracts fixed in §23–§25 without redesigning them |
| Date | 2026-08-28 |

---

## 2. Purpose

This document is the authoritative API specification for the CRM and Lead Management bounded contexts: Contact/Lead lifecycle, Company, Deal, Pipeline, Activity, Task, Note, Appointment, Lead Scoring, CRM Custom Fields, Consent evidence, and Contact Suppression/DNC. It fixes, for every resource, exactly which operations exist, what permission gates them, what physical table/function backs them, and — where the frozen Phase 5 schema cannot safely execute a piece of the Phase 4C domain design — says so plainly instead of pretending otherwise.

It is not an implementation. No application code, no migration, and no change to any 5A–5J document is made here.

---

## 3. Scope / Hard Boundary

### 3.1 6G Owns

Contact (lead lifecycle included), Company, Deal, Pipeline, Activity/call-history read model, Task, Note, Appointment, Lead Scoring (read + async trigger surfaces), CRM custom-field definitions/values, Consent evidence (append/read), Contact Suppression/DNC (check/create/lift), and the CRM-facing surfaces Agent Builder/operators/tenant users need to work these resources.

### 3.2 6G Does Not Own

| Excluded | Owner |
|---|---|
| Campaign execution, CSV campaign dispatch, retries, scheduling, queue/concurrency, ROI | 6H |
| External CRM connectors (Salesforce/HubSpot/Zoho), OAuth credential setup, sync schedules, plugin execution | 6J |
| Voice call lifecycle, transcripts, call controls | 6D |
| Agent configuration | 6E |
| Billing/wallet/usage/quotas | 6K |
| Analytics/reporting projections | 6L |
| Admin/platform control plane (including PLATFORM/REGULATORY suppression administration) | 6M |

No endpoint in this document reaches into any of the above. Where a genuine boundary exists (e.g., the data 6H needs to check before dialing), it is specified as a **contract 6G exposes**, never as a 6H endpoint designed here.

---

## 4. Governing Documents

| Document | Role |
|---|---|
| `docs/phase-01-srs/SOFTWARE_REQUIREMENTS_SPECIFICATION.md` | FR-CRM-001..004, FR-VOICE-006/008, FR-EVT-001, FR-TEN-001..005, NFR-SEC/COMPLY |
| `docs/phase-03-low-level-design/3C-CRM-Campaigns.md` | Lead=Contact origin decision, CQRS-lite rationale, cross-module port pattern |
| `docs/phase-04-domain-driven-design/4C-CRM-Domain.md` | **Primary domain authority** — aggregates, state machines, commands, events, DDRs |
| `docs/phase-05-database-design/5D-CRM-Schema.md` | Physical schema prose (cross-checked against executed SQL) |
| `docs/phase-05-database-design/5K/migrations/019–026_5D.sql`, `085_5D1.sql`, `093_5D2.sql`–`097_5D5.sql` | **Executed migration — wins over prose on any conflict.** The last five are this document's own controlled amendments across Revisions 2–3 (§5a). |
| `docs/phase-05-database-design/5A-Database-Architecture-and-Standards.md` | JSONB/money/enum/delete conventions |
| `docs/phase-05-database-design/5B-Identity-Organization-Multitenancy-Security.md` | **Frozen permission catalog** (§27) |
| `docs/phase-05-database-design/5J-Analytics-Audit-Schema.md` | `audit.fn_insert_audit_event()`, `action_kind` vocabulary, `audit.domain_event_outbox` |
| `docs/phase-05-database-design/5L-Global-Database-Reconciliation/5L-Global-Database-Reconciliation.md` | Confirms `uq_sup_active` (085) and overall CRM schema readiness |
| `docs/phase-06-api-design/6A-API-Architecture-and-Standards.md` | **Binding** envelope, pagination, idempotency, ETag, errors, tiers, audit/outbox wiring |
| `docs/phase-06-api-design/6B/6C/6D/6E/6F` | Precedent for permission-mapping style, DEP register format, endpoint inventory format |

---

## 5. Source Reconciliation Findings

1. **Migrations `019_5D.sql`–`026_5D.sql` and `085_5D1.sql` match 5D's prose byte-for-byte** on every table, constraint, index, grant, RLS policy, and function checked. No 5D-vs-executed-SQL contradiction was found anywhere in the CRM schema. Where this document cites a column, constraint, or grant, it is citing the executed migration, not just the narrative.
2. **5L Global Database Reconciliation item #36** states: *"6G CRM + Leads — READY WITH CURRENT SCHEMA — `crm.contacts`/`deals`/`activities`/`tasks`/`notes`/`lead_score_records` already support the bounded context; `contact_suppressions` now has DB-level uniqueness (085) strengthening any 6G suppression endpoints. No blocker found."* This document treats that as the baseline finding and drills one level deeper per-endpoint (§35, §40). 5L's own "Phase 6G CRM Reconciliation" addendum (2026-08-28) records the deeper findings below as superseding item #36 for 6G specifically, not contradicting it.
3. **4C describes richer Contact-level policy machinery than 5B's frozen permission catalog implements.** 4C's policy table (§8) references `contact:qualify`, `contact:score_override`, `contact:force_convert`, and `crm:admin`. Confirmed by direct grep of 5B's seed-data INSERT blocks (`007_5B.sql`) that none of these four exist as permission strings. Reviewed against the classification rule in §39: `contact:qualify` is adequately served by the existing `contact:write` (Classification A — 5B intentionally consolidates); `contact:force_convert` and `contact:score_override` gate capabilities not exposed in this revision (Classification C); `crm:admin`'s one exposed use (non-author note delete) is already conservatively restricted to `OWNER`/`ADMIN` role membership, at least as strict as a dedicated permission (Classification A). **None of the four crossed the bar for a new 5B permission** — recorded as **DEP-6G-02, NON-BLOCKING, closed by classification, not by a schema change.**
4. **5B has no dedicated permission scope for Company, Pipeline, Task, Note, or Appointment.** These reuse `contact:read`/`contact:write` as the nearest existing CRM-scoped permission (**DEP-6G-03, NON-BLOCKING**) — reviewed and found not to cross the bar for a new permission, since none of these five carries the tenant-wide schema-impact concern that CRM Custom Field Definitions did (see finding 9 below, which *did* cross that bar).
5. **5J's `action_kind` vocabulary already contains `CONTACT_ERASED`, `SUPPRESSION_ADDED`, `SUPPRESSION_LIFTED`** (5J §14.3, Compliance/Data category) — usable with zero governance amendment. Every other CRM mutation this document defines had no governed value. **Resolved in this revision**: `5J-Analytics-Audit-Schema.md` §14.3 now carries a marked ¶ Controlled Phase 6G amendment sanctioning 29 new values (§29.2) — a pure documentation amendment, since `chk_ae_action_kind` (`072_5J.sql`) is length-only and no SQL migration was needed or made. **DEP-6G-06 is RESOLVED.**
6. **4C's `ContactsMergeService` (§6.2) requires re-pointing Activities and LeadScoreRecords to the surviving Contact.** The executed schema (`022_5D.sql`, `023_5D.sql`) grants `app_api`/`app_worker` only `SELECT, INSERT` on `crm.activities` and `crm.lead_score_records`, with `REVOKE UPDATE, DELETE` explicitly issued — no application role can re-point either table, a genuine, physical, migration-proven fact. **Resolved in this revision, not by widening that privilege** (which the reconciliation review explicitly forbade) **but by reconciling the domain rule**: `crm.fn_merge_contacts()` (`093_5D2.sql`) re-points only the four mutable child aggregates that already hold real `UPDATE` grants (Deals/Tasks/Notes/Appointments); Activities/LeadScoreRecords remain physically attached to their original Contact id, with a marker Activity recording that a merge occurred, and the surviving Contact's read-side history follows merge lineage at the application layer (§10). **DEP-6G-01 is RESOLVED** — full detail and live-validation evidence in §10.
7. **`crm.deals.pipeline_id` has a real `ON DELETE RESTRICT` foreign key** (`fk_deals_pipeline`, `021_5D.sql`), but **`app_api`/`app_worker` hold no `DELETE` grant on `crm.pipelines` at all** (`021_5D.sql` grants only `SELECT, INSERT, UPDATE`) — the FK guard is real but currently unreachable by any application role regardless. This is moot, not a gap to close: **4C's own Pipeline command catalogue (§4.4, §11) never defines a `DeletePipeline` command in the first place** — `CreatePipeline`, `RenamePipeline`, `AddStage`, `RenameStage`, `ReorderStages`, `RemoveStage`, `SetDefaultPipeline` are the complete list. Pipeline deletion is **DEFERRED / NOT EXPOSED** in this revision on DDD-command grounds, independent of and prior to the grant question (§13). By contrast, **`crm.contacts.company_id` is a logical reference with no FK at all** (5D §12/§13) — nothing in the database prevents deleting a Company row out from under Contacts that reference it, and Company deletion is likewise not exposed (§11), for a different, genuinely physical reason.
8. **`crm.notes` grants `UPDATE` broadly** (needed for `pinned_at`/`updated_at`), but **4C never defines an "edit note body" command** — not even for `HUMAN`-authored notes (4C §4.7, §11.3: only `AddNote`, `PinNote`, `UnpinNote`, `DeleteNote` exist). This document therefore exposes no body-edit endpoint for any note, human or AI-authored — the absence is a DDD command-catalogue fact, not merely a trigger-enforced restriction on AI notes (§16).
9. **CRM Custom Field Definition administration has tenant-wide schema impact but was mapped onto the `MEMBER`-eligible `contact:write`** for lack of a dedicated scope — a materially larger blast radius than an ordinary per-record edit, and the one 4C/5B terminology gap in this review that *did* cross the bar for a new permission. **Resolved in this revision**: `crm_field:manage` (`096_5B2.sql`, `OWNER`/`ADMIN` only). **DEP-6G-10 is RESOLVED.**
10. **4C §4.3 invariant 5 requires Deal `Currency` to match "the Organisation's configured base currency."** Revision 1 did not locate the backing field. **Resolved in this revision**: `organization.organizations.currency` (`CHAR(3) NOT NULL`, `003_5B.sql`, protected by `trg_organizations_currency_immutable`) is exactly that field — it was already present, simply not located in the first pass. **DEP-6G-07 is RESOLVED** (§12.2).
11. **Voice→CRM event-consumer idempotency (Revision 1) used a race-prone "`SELECT` for existing `call_ref`, then `INSERT`" application pattern**, vulnerable to a genuine at-least-once-delivery TOCTOU race. **Resolved in this revision**: `crm.event_consumer_dedup` + `crm.fn_claim_event()` (`094_5D3.sql`), a true `PRIMARY KEY`-backed atomic claim, live-validated under a genuine two-connection concurrent race (§14.4, §23, §27).
12. **The denormalized `contacts.lead_score`/`lead_temperature` apply (Revision 1) accepted an out-of-order-overwrite race as a documented risk.** **Resolved in this revision, with no new column**: `crm.fn_apply_lead_score()` (`095_5D4.sql`) — a Contact-row lock plus a `(computed_at, id)` recency check against the already-append-only `lead_score_records` history, live-validated under a genuine concurrent race (§18, §27).
13. **(Revision 3.) `crm.fn_merge_contacts()`'s marker Activity (Revision 2, `093_5D2.sql`) copied the secondary Contact's `full_name` and `phone_e164` directly into the Activity `payload`.** Since `crm.activities` is append-only and outside Contact GDPR erasure's field-clearing scope (erasure clears fields on `crm.contacts` only), this created a second, erasure-proof copy of exactly the PII `DELETE /contacts/{id}` is meant to clear — a genuine GDPR-erasure-boundary defect found by an independent whole-project review, not a cosmetic concern. **Resolved**: `097_5D5.sql` (`CREATE OR REPLACE FUNCTION crm.fn_merge_contacts(...)`, `093_5D2.sql` itself untouched) — the marker payload now carries `{event, primary_contact_id, secondary_contact_id, merged_by}` only, live-validated to contain no trace of the secondary's name or phone (§10.3, §10.4).

### 5a. Phase 6G CRM Reconciliation — Amendment Summary (Revisions 2–3)

Five new forward migrations were added on top of the pre-reconciliation baseline (head `092_5F12`), across two independent review passes. No 5A–5J table, column, constraint, index, function, or grant described prior to this reconciliation was altered — every change is additive, and no privilege was widened on any append-only table. All five were live-executed (fresh-DB `001_5B → 097_5D5` and, at each step, existing-DB incremental upgrade from the immediately-prior head, all exit code 0, single head `097_5D5`) against a disposable local PostgreSQL 18 database, including genuine multi-connection concurrency races, not simulated sequentially.

| Migration | Phase | Resolves | Physical change |
|---|---|---|---|
| `093_5D2.sql` | 5D.2 | DEP-6G-01 | `crm.contacts.merged_into_contact_id`/`merged_at`, two guard triggers, `crm.fn_merge_contacts()` (superseded in body by `097_5D5.sql`, columns/triggers/constraints unchanged) |
| `094_5D3.sql` | 5D.3 | Voice→CRM idempotency race | `crm.event_consumer_dedup`, `crm.fn_claim_event()` |
| `095_5D4.sql` | 5D.4 | Lead-score out-of-order race | `crm.fn_apply_lead_score()` — no new column |
| `096_5B2.sql` | 5B.2 | DEP-6G-10 | `crm_field:manage` permission (`OWNER`/`ADMIN` only) |
| `097_5D5.sql` | 5D.5 | Merge-marker PII leak (finding 13) | `CREATE OR REPLACE FUNCTION crm.fn_merge_contacts(...)` — PII-minimal marker payload only; `093_5D2.sql` itself not edited |

Full rationale, DDL, and live-validation transcripts: `MIGRATION_MANIFEST.md`'s "Phase 6G CRM Reconciliation" and "Phase 6G CRM Reconciliation, Follow-up" entries, `5D-CRM-Schema.md`'s matching amendment sections, `5B-Identity-Organization-Multitenancy-Security.md`'s matching amendment section, `5J-Analytics-Audit-Schema.md` §14.3's ¶ amendment, `4C-CRM-Domain.md` §6.2's Physical Implementation Note, and `5L-Global-Database-Reconciliation.md`'s two "Phase 6G CRM Reconciliation" sections.

---

## 6. Resource Ownership Matrix

| Resource | Canonical table(s) | Owning aggregate (4C) | 6G endpoint group |
|---|---|---|---|
| Contact / Lead | `crm.contacts` | `Contact` | §8–§11 |
| Company | `crm.companies` | `Company` | §12 |
| Deal | `crm.deals` | `Deal` | §13 |
| Pipeline | `crm.pipelines` (stages embedded JSONB) | `Pipeline` | §14 |
| Activity / Call History | `crm.activities` (partitioned, append-only) | `Activity` | §15 |
| Task | `crm.tasks` | `Task` | §16 |
| Note | `crm.notes` | `Note` | §16 |
| Appointment | `crm.appointments` | `Appointment` | §17 |
| Lead Score | `crm.lead_score_records` (append-only) + `contacts.lead_score`/`lead_temperature` (denormalized) | `LeadScoreRecord` | §18 |
| Custom Field Definitions | `crm.crm_field_definitions` (JSONB) | `CRMFieldDefinitionSet` | §19 |
| Consent | `crm.consent_records` (partitioned, append-only) | `ConsentRecord` (Phase 4I) | §20 |
| Suppression / DNC | `crm.contact_suppressions` | `ContactSuppression` (Phase 4I) | §21 |

No table in the `crm` schema is exposed as a CRUD resource beyond this list. `crm.contact_suppressions` is not addressed by `contact_id` anywhere in this API — it is addressed by `id` (suppression record) or looked up by `phone_e164` (§21), per ADR-5D-002.

---

## 7. CRM Architecture Overview

```
Client (Web console / Partner API key)
  │
  ▼
6A canonical pipeline (auth → tenant resolution → rate limit → authz → validation)
  │
  ▼
CRM Application Services (4C §13) ── guarded state machines / policies (4C §7–§8)
  │                                        │
  ▼                                        ▼
crm.* tables (RLS, tenant-scoped)   audit.fn_insert_audit_event()   audit.domain_event_outbox
  │                                        (sole audit write path)   (sole domain-event write path)
  ▼
Redis (idempotency keys, suppression/consent read-through cache, RBAC cache)

Voice Platform (4B) ── in-process application-service calls (no HTTP hop) ──▶ CRM tool-callable entry points
  (FindOrCreateContact, UpdateContactFromCall, BookAppointmentFromCall, CreateTaskFromCall)
                                                                             + event subscribers
  (call.ended, conversation.qualification_set, conversation.summarization_completed)

CRM ── domain events (contact.*, deal.*, appointment.*, ...) ──▶ audit.domain_event_outbox ──▶ Campaign(6H) / Analytics(6L) / Billing(6K) / Webhook Engine / Integrations(6J)
```

Everything below "Client" through "Redis" is synchronous REST per 6A §6. Everything below "Voice Platform" is in-process/event-driven — never a network hop on the voice turn path (6A §6, 4H §9.1 invariant, restated in 6D §21.11).

---

## 8. Contact API

### 8.1 Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/contacts` | Create a Contact (also the entry point a lead effectively "is") |
| `GET` | `/api/v1/contacts` | List/filter/search Contacts, including lead-oriented views |
| `GET` | `/api/v1/contacts/{contact_id}` | Get one Contact |
| `PATCH` | `/api/v1/contacts/{contact_id}` | Update free-form mutable fields |
| `POST` | `/api/v1/contacts/{contact_id}/lead-status` | Guarded LeadStatus transition (§9) |
| `POST` | `/api/v1/contacts/{contact_id}/qualify` | `SetQualificationStatus` (§9) |
| `POST` | `/api/v1/contacts/{contact_id}/convert` | `ConvertLead` (§9) |
| `POST` | `/api/v1/contacts/{contact_id}/owner` | `AssignOwner` |
| `POST` | `/api/v1/contacts/{contact_id}/tags` | `AddTag` |
| `DELETE` | `/api/v1/contacts/{contact_id}/tags/{tag}` | `RemoveTag` |
| `POST` | `/api/v1/contacts/{contact_id}/merge` | `MergeContacts` via `crm.fn_merge_contacts()` (§10) |
| `DELETE` | `/api/v1/contacts/{contact_id}` | GDPR erasure (PII clearing/tombstone, §22) |
| `POST` | `/api/v1/contacts/{contact_id}/suppress` | Convenience wrapper creating an ORG suppression keyed on the contact's current phone (§21.6) |
| `GET` | `/api/v1/contacts/{contact_id}/deals` | `ListDealsForContact` |
| `GET` | `/api/v1/contacts/{contact_id}/activities` | Call-history / activity timeline (§15) |
| `GET` | `/api/v1/contacts/{contact_id}/tasks` | `GetTasksForSubject` |
| `GET` | `/api/v1/contacts/{contact_id}/notes` | `GetNotesForSubject` |
| `GET` | `/api/v1/contacts/{contact_id}/appointments` | `GetAppointmentsForContact` |
| `GET` | `/api/v1/contacts/{contact_id}/score` | Current score/temperature (§18) |
| `GET` | `/api/v1/contacts/{contact_id}/score-history` | `GetLeadScoreHistory` (§18) |
| `GET` | `/api/v1/contacts/{contact_id}/consent` | Effective consent (§20) |
| `GET` | `/api/v1/contacts/{contact_id}/consent/history` | Full consent history (§20) |
| `POST` | `/api/v1/contacts/{contact_id}/consent` | Append a consent record (§20) |

No `PATCH`/`DELETE` exists for `lead_status`, `qualification_status`, `lead_score`, `lead_temperature`, `converted_at`, `merged_into_contact_id`, or `merged_at` directly — these are guarded (§9, §10) per 6A §8.3's rule that a state-machine-guarded field is never exposed on a generic `PATCH`. `merged_into_contact_id`/`merged_at` move only via `crm.fn_merge_contacts()` (§10) and are additionally trigger-immutable once set (`trg_contacts_merge_immutable`, `093_5D2.sql`) — even an internal bug attempting a direct `UPDATE` on them is rejected at the database layer.

### 8.2 Create Contact (Showcase A)

```
POST /api/v1/contacts
Idempotency-Key: <required — creation has real-world consequences, 6A §16.1>
```

**Request:**
```json
{
  "full_name": "Priya Sharma",
  "phone_e164": "+919876543210",
  "primary_email": "priya@example.com",
  "company_id": "0193...",
  "owned_by": "0193...",
  "source": "MANUAL",
  "tags": ["hot-lead"],
  "custom_field_values": [{"field_id": "0193...", "value": "Marketing"}]
}
```

`source` is restricted server-side to `MANUAL | API` for tenant-initiated creates — `INBOUND_CALL`/`OUTBOUND_CALL`/`CSV_IMPORT`/`WEBHOOK` are set only by the internal call paths that actually correspond to them (Voice event subscriber, CSV import, inbound webhook processor), never by a client-supplied value on this endpoint (mass-assignment guard, 6A §22).

**Validation:**
- `phone_e164` normalized/validated against the DB's own canonical regex (`^\+[1-9][0-9]{6,14}$`, `020_5D.sql`) — the API is the single normalization boundary (6A §7.5); it never trusts a client-declared "already E.164" string without re-validating.
- `full_name` 1–200 chars, `tags` ≤ 20 (`chk_contacts_tag_count`), `custom_field_values` validated against the tenant's active `CRMFieldDefinitionSet` (§19) and capped at 50.
- **A suppressed phone number is never rejected at Contact-creation time.** Suppression (§21) governs call eligibility, not CRM record existence — 4C draws no such link, and inventing one would block legitimate CRM data entry (e.g., recording that a suppressed number belongs to a real person for service purposes). The response includes an informational `suppression_status` field (derived from a read of `crm.contact_suppressions`, not blocking) so the UI can surface it, but creation is never refused on this basis alone.

**Concurrency — same phone, concurrent create:**
```sql
INSERT INTO crm.contacts (...) VALUES (...)
ON CONFLICT (organization_id, phone_e164) WHERE deleted_at IS NULL DO NOTHING;
```
(exact pattern from `5D §15.1`, backed by the partial unique index `uq_contacts_phone`). If the `INSERT` affects 0 rows, the application re-`SELECT`s the existing row and returns **200 OK** with the existing Contact (not 409) when the caller's intent was `find-or-create` semantics (internal tool-callable path, §23); the tenant-facing `POST /contacts` endpoint instead returns **409 Conflict**, `error.code = STATE_CONFLICT`, `error.details.reason = "DUPLICATE_PHONE"`, `error.details.existing_contact_id` — a human-initiated create is not silently redirected to update someone else's record. This distinction (idempotent-find-or-create for the internal tool path vs. explicit-conflict for the human-facing endpoint) is deliberate: the two callers have different intents even though they hit the same unique index.

**GDPR-erased contact re-import:** the partial unique index excludes `deleted_at IS NOT NULL` rows, so a new `INSERT` for a previously-erased phone number succeeds and creates a fresh Contact row — the tombstoned row and the new row coexist, both queryable by internal ID, only one active per phone (5D §5.1, ADR-5D-007). The new Contact is **not** automatically re-suppressed by this endpoint; suppression enforcement happens at the authoritative suppression check (§21), which will find the original suppression record by phone regardless of which Contact row currently owns that number.

**Transaction boundary:** single `INSERT` on `crm.contacts` (or the `ON CONFLICT DO NOTHING` variant), inside one short transaction. Commit. Then, outside the transaction: `audit.fn_insert_audit_event(action_kind => 'CONTACT_CREATED', ...)` (async per 5J §14.5 — configuration/CRM lifecycle changes are the general async category, and Contact creation is not one of 6D's named synchronous exceptions) and an `audit.domain_event_outbox` row for `contact.created`.

**Response:** `201 Created`, `Location: /api/v1/contacts/{id}`, full `ContactDTO` (§8.4). `200 OK` on find-or-create idempotent hit.

**Readiness: IMPLEMENTATION-READY.**

### 8.3 List / Get Contacts

`GET /api/v1/contacts` — cursor-paginated (6A §14), default sort `created_at DESC`, allow-listed filters only (6A §15):

| Filter | Backing index |
|---|---|
| `lead_status` | `idx_contacts_org_lead_status` |
| `qualification_status` | `idx_contacts_org_qualification` |
| `lead_temperature` (HOT/WARM only, per partial index) | `idx_contacts_org_temperature` |
| `owned_by` | `idx_contacts_owner` |
| `company_id` | `idx_contacts_company` |
| `campaign_ref` | `idx_contacts_campaign` |
| `created_after` / `created_before` | `idx_contacts_org_created` |
| `search` (name/phone/email prefix) | Not backed by a `tsvector`/GIN index in the executed schema — see DEP-6G note below |
| `tag` | Not index-backed (`tags` is a plain `TEXT[]`, no GIN index in `020_5D.sql`) |

**`search` and `tag` filters are NOT exposed** as query parameters on `GET /contacts` in this revision: 6A §15 forbids exposing a filter/sort field that would force a sequential scan, and neither a full-text index nor a GIN index on `tags` exists in the executed schema. This is recorded as a non-blocking limitation, not silently worked around with an unindexed `ILIKE` scan.

Lead-oriented views are exactly this same endpoint with filters — **not** a separate `/leads` resource (DDR-4C-001, ADR-5D-001, reconfirmed at the API layer as **ADR-6G-01**, §41):
```
GET /api/v1/contacts?lead_status=QUALIFIED
GET /api/v1/contacts?qualification_status=QUALIFIED&lead_temperature=HOT
```

`GET /api/v1/contacts/{contact_id}` returns 404 (never 403) for a contact in another tenant or a soft-deleted contact viewed by a non-privileged caller (6A §7.4, §22).

**Readiness: IMPLEMENTATION-READY.**

### 8.4 Contact DTO — PII Exposure

| Field | List DTO (`ContactSummaryDTO`) | Detail DTO (`ContactDTO`) |
|---|---|---|
| `id`, `lead_status`, `qualification_status`, `lead_score`, `lead_temperature`, `owned_by`, `created_at`, `updated_at`, `last_contacted_at` | ✅ | ✅ |
| `full_name` (pii:name) | ✅ | ✅ |
| `phone_e164` (pii:phone) | ✅ (needed for list operability) | ✅ |
| `secondary_phone_e164`, `primary_email` (pii:email/phone) | — | ✅ |
| `address_*` (pii:address) | — | ✅ |
| `custom_field_values` | — | ✅ |
| `qualification_reason` | — | ✅ |
| `do_not_call` | ✅ (informational badge) | ✅ (informational — never authoritative, §21) |
| `tags`, `source`, `campaign_ref`, `company_id` | ✅ | ✅ |
| `merged_into_contact_id`, `merged_at` | ✅ (needed so a list view can visually distinguish a merged-away row) | ✅ |
| GDPR-erased placeholder values (`+99000000000`, `[ERASED]`) | Suppressed from both DTOs — an erased contact returns `deleted_at` and a `redacted: true` flag, never the literal tombstone string, so a client cannot mistake the placeholder for a real phone number | |

### 8.5 PATCH Contact — Free-Form Fields

```
PATCH /api/v1/contacts/{contact_id}
If-Match: "<etag>"
```

Mutable via `PATCH`: `full_name`, `secondary_phone_e164`, `primary_email`, `company_id`, `address_*`, `custom_field_values`, `tags` (full replace — see note below). `null` clears a field; an omitted field is left unchanged (6A §7.5). ETag derived from `hash(id, updated_at)` (6A §17.2, ADR-6A-08 — the platform has no `version_number` column on `crm.contacts`); mismatch → `412 Precondition Failed`.

`tags` supports full-array replacement via `PATCH` for bulk editing convenience, in addition to the incremental `POST .../tags` / `DELETE .../tags/{tag}` actions — both paths validate the same ≤20 cap.

Fields **not** writable via `PATCH`, ever: `lead_status`, `qualification_status`, `qualification_reason`, `lead_score`, `lead_temperature`, `converted_at`, `do_not_call`, `phone_e164` (primary phone change is not a modeled command in 4C — not exposed at all in this revision), `deleted_at`.

**Readiness: IMPLEMENTATION-READY.**

---

## 9. Contact / Lead Lifecycle (Showcase B)

### 9.1 The State Machine (4C §7.1, verbatim legal transitions)

```
                 ┌─────────────────────────────────────────────┐
                 │                                               │
  [*] ──CreateContact──▶ NEW ──(qualifying Activity recorded, automatic)──▶ CONTACTED
                          │                                        │  │
                          │ SetQualificationStatus(DISQUALIFIED)   │  │
                          ▼                                        │  │
                    DISQUALIFIED ◀───────SetQualificationStatus────┘  │
                     │   ▲  │                                          │
   (Activity, automatic)  │  UpdateLeadStatus(NURTURING)               │ SetQualificationStatus(QUALIFIED)
                     │   │  │  [reason_for_re_engagement required]     │  [qualifying Activity type required]
                     ▼   │  ▼                                          ▼
                 CONTACTED│NURTURING ◀──────────────────────────── QUALIFIED
                          │    ▲                                    │    │
                          │    │ SetQualificationStatus(QUALIFIED)  │    │ ConvertLead
                (Activity,│    │ SetQualificationStatus(DISQUALIFIED) │    │ [WON Deal required,
                 automatic)    │                                    │    │  or contact:force_convert
                          └────┘                                    │    │  bypass — NOT EXPOSED,
                                                                     │    │  DEP-6G-02]
                                                                     ▼    ▼
                                                              UpdateLeadStatus(NURTURING)   CONVERTED [*] (terminal)
```

### 9.2 Which Endpoint Moves Which Transition

| Transition | Endpoint | Guard |
|---|---|---|
| `NEW → CONTACTED`, `DISQUALIFIED → CONTACTED` | *None — automatic.* Side effect of `RecordActivity` (§15) when the Activity's type is `CALL\|EMAIL\|SMS\|WHATSAPP\|MEETING` and current `lead_status` is `NEW` or `DISQUALIFIED` | Application-service rule inside `RecordActivity`, not a client-invokable action |
| `NEW → DISQUALIFIED`, `CONTACTED → QUALIFIED`, `CONTACTED → DISQUALIFIED`, `QUALIFIED → DISQUALIFIED`, `NURTURING → QUALIFIED`, `NURTURING → DISQUALIFIED` | `POST /contacts/{id}/qualify` | `CONTACTED → QUALIFIED` requires ≥1 prior Activity of type `CALL` or `MEETING` (`QualificationRequiresContact` policy) |
| `CONTACTED → NURTURING`, `QUALIFIED → NURTURING`, `DISQUALIFIED → NURTURING` | `POST /contacts/{id}/lead-status` | `DISQUALIFIED → NURTURING` requires `reason` in the request body |
| `QUALIFIED → CONVERTED` | `POST /contacts/{id}/convert` | Requires a linked `Deal` in `WON` status (`LeadConversionRequiresDeal` policy) |

`POST /contacts/{id}/lead-status` validates the requested `new_status` against this exact table for the contact's *current* `lead_status` — any other target (including a direct jump to `QUALIFIED`, `DISQUALIFIED`, or `CONVERTED` through this endpoint) is rejected with `409 Conflict`, `error.code = STATE_CONFLICT`, `error.details.reason = "ILLEGAL_LEAD_TRANSITION"`, `error.details.current_state`. This is the 6A §8.3 rule applied precisely: a guarded transition is never a bare `PATCH {"status": "..."}`.

### 9.3 Qualification — AI vs. Human

`POST /contacts/{id}/qualify` accepts the same shape whether the caller is a human operator or the internal Voice event subscriber (`handle_qualification_set`, consuming `conversation.qualification_set`) — both go through the identical `SetQualificationStatus` application service (4C §13.1). The distinguishing field is `set_by_type: AI_AGENT | HUMAN` (server-derived from the actual authenticated principal — the internal service JWT for the event-subscriber path, 6A §23.4 — never a client-supplied claim). The AI's determination is authoritative unless a human with `contact:write` (mapped for `contact:qualify`, DEP-6G-02) explicitly re-issues the command — there is no "lock" preventing override; the most recent qualification call wins, and the full sequence is visible in the Activity timeline (`QUALIFICATION_CHANGE` activity type) and audit trail for either party to see who overrode whom and when.

### 9.4 Lead Temperature and Score — Never Directly Writable

Confirmed at every layer: no request body on any Contact endpoint accepts `lead_temperature`. It is written only as part of the score-update transaction (§18, `5D §15.8` exact pattern), computed as `CASE WHEN score>=70 THEN 'HOT' WHEN score>=40 THEN 'WARM' ELSE 'COLD' END`. DDR-4C-004 / ADR-5D-007 hold at the API layer as **ADR-6G-02**.

### 9.5 `ConvertLead`

```json
POST /api/v1/contacts/{contact_id}/convert
{ "triggering_deal_id": "0193..." }
```
Verifies the referenced `Deal` belongs to this Contact and has `status = WON`. On success: `lead_status → CONVERTED`, `converted_at = NOW()` (set exactly once — a second call returns `409` `error.details.reason = "ALREADY_CONVERTED"`, not a silent no-op, since `converted_at` re-assignment would violate 4C §4.1 invariant 6). Permission: `contact:convert`.

The 4C-described bypass ("Owner with `contact:force_convert` may convert without a WON Deal") is **not exposed** — no such permission exists in 5B (DEP-6G-02). Every conversion in this API requires a WON Deal.

**Readiness: IMPLEMENTATION-READY** (all four endpoints — `/qualify`, `/lead-status`, `/convert`, automatic Activity-driven transition — save the explicitly-unexposed force-convert bypass, which is DEFERRED, not broken).

---

## 10. Contact Merge (Showcase C — High-Risk)

### 10.1 What 4C Requires, and How It Is Physically Represented

`MergeContacts` (4C §6.2, §11.1): survivor (`primary`) keeps its identity; `secondary` is folded in. Fields from `secondary` fill nulls in `primary`; `primary` wins conflicts. `secondary.lead_status` is applied to `primary` if further along the state machine. `secondary` becomes a terminal, non-`ACTIVE` identity state distinct from ordinary Contact lifecycle. A merge event carries both IDs and the field-merge map. This touches two Contact aggregates in one `UnitOfWork` — the one explicitly-named dual-aggregate exception in 4C's entire transaction-boundary model (4C §4.1 "Transaction boundary").

**Physical representation (`093_5D2.sql`):** `crm.contacts.merged_into_contact_id` (self-referential FK) + `merged_at`, both-or-neither, set exactly once by `crm.fn_merge_contacts()` and immutable thereafter (`trg_contacts_merge_immutable`). **This is deliberately not `deleted_at`.** `deleted_at` remains exclusively the GDPR-erasure tombstone (§22, ADR-5D-007) — a merged Contact's PII is *not* cleared, it is folded into the survivor. The two states are independent and compose freely: a merged-away Contact can later still be the subject of a GDPR erasure request, live-validated (§10.4).

### 10.2 Re-Pointing: What Is Physically Mutable vs. What Stays Put

| Referencing table | Grant on `app_api`/`app_worker` | Re-pointed by `fn_merge_contacts()`? |
|---|---|---|
| `crm.deals.contact_id` | `SELECT, INSERT, UPDATE` (`021_5D.sql`) | **Yes** |
| `crm.tasks.subject_id` | `SELECT, INSERT, UPDATE` (`022_5D.sql`) | **Yes** |
| `crm.notes.subject_id` | `SELECT, INSERT, UPDATE, DELETE` (`022_5D.sql`) | **Yes** |
| `crm.appointments.contact_id` | `SELECT, INSERT, UPDATE` (`023_5D.sql`) | **Yes** |
| `crm.activities.subject_id` | `SELECT, INSERT` **only** — `REVOKE UPDATE, DELETE` (`022_5D.sql`) | **No — deliberately, not a gap** |
| `crm.lead_score_records.contact_id` | `SELECT, INSERT` **only** — `REVOKE UPDATE, DELETE` (`023_5D.sql`) | **No — deliberately, not a gap** |
| `crm.contact_suppressions.contact_id` | `SELECT, INSERT` **only** — `REVOKE UPDATE, DELETE` (`024_5D.sql`) | **No — by design** (ADR-5D-002, suppression is phone-keyed, not contact-keyed) |

Activities and LeadScoreRecords are append-only, audit-grade histories (DDR-4C-002); re-pointing them would mean mutating rows that must never be mutated. This document's resolution — reconciling the domain rule rather than weakening the privilege — is that **the surviving Contact's history is read as a lineage, not rewritten as a single table's rows.** A merge is recorded via a **new**, immutable, **PII-minimal** marker Activity on the survivor (`activity_type = 'STAGE_CHANGE'`, `payload->>'event' = 'contact_merged'` — exact payload shape in §10.3 step 10), and any read that must present "this Contact's full history including predecessors" walks `merged_into_contact_id` at query time (§10.5) rather than requiring the database to have already merged the rows.

**PII-minimal is a structural property of the marker payload, not a documentation promise, and it is load-bearing for GDPR erasure.** `crm.activities` is append-only and untouched by Contact GDPR erasure (§22 — erasure clears fields on `crm.contacts` only). Copying a Contact's direct PII (name, phone, email, address, custom-field values, qualification reason) into this payload would create a second, permanently unerasable copy of exactly the data `DELETE /contacts/{id}` exists to clear — a real defect an independent review found in this document's own Revision 2 and that `097_5D5.sql` fixes (§10.3 step 10, §10.4).

### 10.3 `crm.fn_merge_contacts()` — The Guarded Write Path

```
POST /api/v1/contacts/{primary_id}/merge
Idempotency-Key: <required>
{ "secondary_contact_id": "0193..." }
```

Calls `crm.fn_merge_contacts(p_primary_contact_id, p_secondary_contact_id, p_organization_id, p_merged_by_ref)` — `SECURITY DEFINER` (`093_5D2.sql`), not for privilege elevation (every grant this function uses, `app_api`/`app_worker` already hold) but for centralized, atomic invariant enforcement, one code path every merge goes through. In one transaction:

1. Rejects `primary == secondary`.
2. Locks both Contact rows in deterministic id order (smaller id first) to prevent deadlock against a concurrent merge naming the same pair.
3. Rejects if either Contact is not found under the caller's `organization_id` — a cross-tenant secondary resolves to this same "not found" outcome, a non-disclosing failure mode (6A §7.4), not a distinct "cross-tenant" error.
4. Rejects if either Contact is already GDPR-erased (`deleted_at IS NOT NULL`).
5. Rejects if either Contact is already merged away (`merged_into_contact_id IS NOT NULL`) — checked for **both** primary and secondary. This single check is what makes a merge cycle structurally impossible: a Contact that has ever been a merge secondary can never again be chosen as a primary, so it can never receive a new outbound merge pointer of its own (proven live with a two-hop chain, §10.4).
6. Field-fills nulls on `primary` from `secondary` (`primary` wins conflicts); adopts `secondary.lead_status` onto `primary` only if it ranks further along a documented interpretation of 4C §7.1's non-linear diagram (`NEW`=0; `CONTACTED`/`NURTURING`/`DISQUALIFIED`=1, lateral to each other; `QUALIFIED`=2; `CONVERTED`=3 — 4C gives no numeric ranking itself, so this ordering is this document's explicit, auditable interpretation, the same kind of documented DDD-gap resolution 6F's Interpretation A/B precedent already established).
7. Unions `tags` (cap 20) and `custom_field_values` by `field_id`, primary wins ties (cap 50) — either cap exceeded aborts the whole operation before any write (`422`, `error.details.reason` names the exceeded cap), never a silent truncation.
8. Re-points the four mutable child tables (§10.2).
9. Marks `secondary`: `merged_into_contact_id = primary_id`, `merged_at = NOW()`.
10. Records the marker Activity on `primary` (§10.2) — `activity_type = 'STAGE_CHANGE'`, `payload = {"event": "contact_merged", "primary_contact_id": ..., "secondary_contact_id": ..., "merged_by": ...}`. **This is the complete field set, by design (`097_5D5.sql`) — no Contact name, phone, email, address, custom-field value, or qualification reason is ever included**, because this payload is append-only and outside GDPR erasure's reach (§10.2, §22).
11. Returns; caller commits and then, outside the transaction, calls `audit.fn_insert_audit_event(action_kind => 'CONTACT_MERGED', ...)` and writes an `audit.domain_event_outbox` row for `contact.merged` (`{primary_id, secondary_id, field_merge_map}`).

Two independent trigger-level guards back this up even against a direct-SQL bypass of the function (both live-validated, §10.4): `trg_contacts_merge_tenant_guard` rejects a cross-tenant `merged_into_contact_id`; `trg_contacts_merge_immutable` rejects any attempt to change or clear an already-recorded merge lineage.

### 10.4 Live-Validated Behavior

All of the following were exercised against a real, disposable PostgreSQL 18 database (not a design-time claim):

| Scenario | Result |
|---|---|
| Valid same-tenant merge | Field-fill, lead-status ranking, tag/custom-field union with cap enforcement, all four mutable children repointed, Activities/LeadScoreRecords correctly left in place, marker Activity recorded on the survivor |
| Marker Activity payload contains no Contact PII | Confirmed via `jsonb_object_keys()` — the persisted key set is exactly `{event, primary_contact_id, secondary_contact_id, merged_by}`; `payload ? 'secondary_full_name'` and `payload ? 'secondary_phone_e164'` both evaluate `false`; a direct `payload::text LIKE '%<fixture's actual name/phone>%'` search confirms neither string appears anywhere in the row |
| GDPR erasure of an already-merged secondary | Succeeds unobstructed (as in Revision 2); the marker payload, already PII-free before erasure, is unaffected by it — confirming no Contact PII survives an erasure solely because a prior merge had copied it |
| Self-merge | Rejected — `MERGE_SELF_REJECTED` |
| Cross-tenant secondary | Rejected — resolves as "secondary not found" (non-disclosing) |
| Already-merged Contact used as primary | Rejected — `MERGE_PRIMARY_ALREADY_MERGED` |
| Already-merged Contact used as secondary | Rejected — `MERGE_SECONDARY_ALREADY_MERGED` |
| GDPR-erased Contact used as primary or secondary | Rejected — `MERGE_PRIMARY_ERASED` / `MERGE_SECONDARY_ERASED` |
| Two-connection concurrent merge of the identical `(primary, secondary)` pair | Genuine race: one connection succeeded, the other received a real `MERGE_SECONDARY_ALREADY_MERGED` exception — not simulated sequentially |
| Multi-hop lineage (A merged into B; B later merged into C) | Succeeds — B is a normal, non-merged Contact right up until it itself becomes a secondary; A's `merged_into_contact_id` (pointing at B) is correctly left unrewritten |
| Attempt to use A (now a secondary two hops removed) as a primary again | Rejected — `MERGE_PRIMARY_ALREADY_MERGED`, confirming the cycle-freedom argument in §10.3 point 5 |
| Direct-SQL bypass: `UPDATE crm.contacts SET merged_into_contact_id = ...` on an already-merged row | Rejected by `trg_contacts_merge_immutable` |
| Direct-SQL bypass: `UPDATE ... SET merged_into_contact_id = <cross-tenant id>` | Rejected by `trg_contacts_merge_tenant_guard` |
| GDPR erasure of an **already-merged** Contact | **Succeeds unobstructed** — `trg_contacts_merge_immutable` fires only on `merged_into_contact_id`/`merged_at` changes, never on the erasure field-set, confirming the two states are genuinely independent |

### 10.5 Read-Side: Merge Lineage in the Survivor's History

`GET /contacts/{secondary_id}` on an already-merged Contact returns `200`, not `404` and not a redirect (6A defines no HTTP redirect convention for this platform's APIs) — the response body carries `merged_into_contact_id`/`merged_at` so a client can follow the pointer to the canonical survivor. A direct read of a merged Contact is not an error; it is a normal read of a Contact whose lineage has moved on.

`GET /contacts/{id}/activities` and `GET /contacts/{id}/score-history` on the **survivor** return only that Contact's own directly-recorded rows by default — they do not automatically pull in a merged predecessor's history, since 4C defines `GetActivitiesForSubject`/`GetLeadScoreHistory` as single-subject queries. A client that needs the full lineage-inclusive view walks `merged_into_contact_id` client-side: `GET /contacts/{predecessor_id}/activities` remains a valid, readable call against the predecessor's own (still-`GET`table, still soft-non-deleted-unless-separately-erased) row. A future enhancement could add a `?include_lineage=true` flag performing this UNION server-side; this revision does not claim that flag exists.

**Readiness: IMPLEMENTATION-READY.**

---

## 11. Company API

| Method | Path | Command | Permission |
|---|---|---|---|
| `POST` | `/api/v1/companies` | `CreateCompany` | `contact:write` (DEP-6G-03) |
| `GET` | `/api/v1/companies` | `ListCompanies` (filters: `owned_by`; `domain` exact-match) | `contact:read` |
| `GET` | `/api/v1/companies/{id}` | `GetCompany` | `contact:read` |
| `PATCH` | `/api/v1/companies/{id}` | `UpdateCompanyDetails` | `contact:write` |
| `POST` | `/api/v1/companies/{id}/owner` | `AssignCompanyOwner` | `contact:write` |

**`email_domain` uniqueness:** enforced by `uq_companies_domain` (partial unique, `WHERE email_domain IS NOT NULL`) — duplicate insert maps to `409`, `error.details.reason = "DUPLICATE_DOMAIN"`.

**No `DELETE /companies/{id}`.** 4C §4.2 invariant 2 requires "cannot be deleted while it has active Contacts referencing it," but `contacts.company_id` is a **logical reference with no FK** (5D §12/§13 — confirmed against `020_5D.sql`, which defines `company_id UUID NULL` with no `REFERENCES` clause). A `SELECT count(*) FROM contacts WHERE company_id = $id`-then-`DELETE` pre-check is TOCTOU-racy and not a safe physical guarantee. Rather than expose a delete that can silently orphan Contact→Company references, this document does not expose Company deletion at all. **DEP-6G-05, NON-BLOCKING** (the safe choice is simply not exposing it; a future FK `RESTRICT` amendment would unblock a real delete).

**Readiness: IMPLEMENTATION-READY** for all five endpoints; delete is DEFERRED / NOT EXPOSED by design, not blocked.

---

## 12. Deal API (Showcase D)

### 12.1 Endpoints

| Method | Path | Command | Permission |
|---|---|---|---|
| `POST` | `/api/v1/deals` | `CreateDeal` | `deal:write` |
| `GET` | `/api/v1/deals` | List (filters: `pipeline_id`, `current_stage_id`, `status`, `owned_by`, `contact_id`, `company_id`) | `deal:read` |
| `GET` | `/api/v1/deals/{id}` | `GetDeal` | `deal:read` |
| `PATCH` | `/api/v1/deals/{id}` | `UpdateDealDetails` (mutable fields only while `status = OPEN`) | `deal:write` |
| `POST` | `/api/v1/deals/{id}/stage` | `MoveDealStage` | `deal:write` |
| `POST` | `/api/v1/deals/{id}/win` | `WinDeal` | `deal:close` |
| `POST` | `/api/v1/deals/{id}/lose` | `LoseDeal` | `deal:close` |
| `POST` | `/api/v1/deals/{id}/abandon` | `AbandonDeal` | `deal:close` |
| `POST` | `/api/v1/deals/{id}/owner` | `AssignDealOwner` | `deal:write` |

### 12.2 Create / Move / Win / Lose

`POST /deals`: `pipeline_id` + optional `initial_stage_ref` (defaults to the pipeline's `order = 1` stage per `DealFactory`, 4C §15.2). `value_amount`/`value_currency` are both-or-neither (`chk_deals_money_pair`) and rendered per 6A §7.5's money-object convention (`{"amount": "1234.5000", "currency": "INR"}` — string amount, never a JSON number).

`POST /deals/{id}/stage` — `{"target_stage_id": "..."}`. Validated against `crm.pipelines.stages` JSONB for the deal's `pipeline_id` (`DealStageValidationService.can_move`, 4C §6.5): the target must be a `stage_id` present in that pipeline's `stages` array. `409 STATE_CONFLICT` / `INVALID_PIPELINE_STAGE` if not, or if the deal is already terminal (`chk_deals_status`-legal values are `OPEN|WON|LOST|ABANDONED`; the application layer additionally enforces `TerminalDealIsImmutable`, 4C §8, since the CHECK alone doesn't prevent a stage change on a `WON` deal — that guard is enforced in the application service, mirroring `contacts.lead_temperature`'s pattern of "CHECK enforces vocabulary, application enforces the transition rule," 5D §5.1).

`POST /deals/{id}/win`: sets `status = WON`, `won_at = NOW()` (once — `409 DEAL_TERMINAL` on retry). `POST /deals/{id}/lose`: requires `lost_reason` (free text, no enum — 4C §4.3 business rule), sets `status = LOST`, `lost_at = NOW()`, and (per `chk_deals_status`) `close_date` must be set to the loss date if not already present. `POST /deals/{id}/abandon`: `status = ABANDONED`.

**AI tool-call boundary:** the `createDeal`/`advanceDealStage` tool runners invoke the identical `CreateDeal`/`MoveDealStage` application services this API exposes (4C §17.4) — not a parallel implementation. **`WinDeal`/`LoseDeal`/`AbandonDeal` are never reachable from an AI tool call** — 4C explicitly reserves terminal Deal closure for human permission (`deal:close`, which exists in 5B and requires `OWNER`/`ADMIN`), and no tool-runner entry point in 4C's catalogue (§13.2) exposes them.

**Currency invariant:** 4C §4.3 invariant 5 requires `Currency` to match "the Organisation's configured base currency." That field is `organization.organizations.currency` (`CHAR(3) NOT NULL`, `003_5B.sql`, itself protected by `trg_organizations_currency_immutable` — an org's base currency cannot change once set). `POST /deals`/`PATCH /deals/{id}` validate, at the application layer, that `value_currency = organizations.currency` for the caller's tenant whenever `value_amount` is set — the DB `CHECK` (`chk_deals_currency_format`) validates ISO-4217 *format* only, so this cross-table match is an application-layer read-then-compare, not a DB constraint (a cross-table `CHECK` isn't expressible in Postgres; a trigger was considered and rejected as unnecessary given `organizations.currency` is itself immutable post-creation, so there's no concurrent-currency-change race to guard against — the value being compared against cannot move underneath the check). **DEP-6G-07 is RESOLVED.**

**Concurrency:**

| Scenario | Handling |
|---|---|
| Two simultaneous stage moves | `PATCH`/action semantics: no ETag on `Deal` in this revision (state-machine-guarded resources use action endpoints + `409`, not ETag, per 6A §17.2) — the second `MoveDealStage` call re-validates `current_stage_id` server-side inside the same transaction as the `UPDATE`; if the deal's actual current stage no longer matches what the client believed, a plain `UPDATE ... WHERE id=$1 AND current_stage_id=$expected` affecting 0 rows signals a race, and the application returns `409` with the deal's now-current `current_stage_id` in `error.details` |
| Stage move racing a `Win`/`Lose` | Same CAS-on-current-state pattern: a `Win`/`Lose` transaction includes `AND status = 'OPEN'` in its `UPDATE`; if a concurrent stage move committed first, the deal is still `OPEN` (stage moves don't change `status`) so no conflict; if a concurrent `Win`/`Lose` committed first, the second terminal-action's `UPDATE` affects 0 rows → `409 DEAL_TERMINAL` |
| Two simultaneous `Win`/`Lose`/`Abandon` calls | Whichever `UPDATE ... WHERE status='OPEN'` commits first wins; the loser's `UPDATE` affects 0 rows → `409 DEAL_TERMINAL`, `error.details.current_state` reflects the actual terminal state |

No `SELECT ... FOR UPDATE` is used here — the CAS-via-`WHERE`-clause pattern is suf2ficient and matches 6A §17.3's instruction to avoid introducing a second, API-layer locking scheme beyond what Phase 5's actual mechanisms already provide.

**Readiness: IMPLEMENTATION-READY** for all nine endpoints.

---

## 13. Pipeline API

| Method | Path | Command |
|---|---|---|
| `POST` | `/api/v1/pipelines` | `CreatePipeline` (with initial `stages[]`) |
| `GET` | `/api/v1/pipelines` | `ListPipelines` |
| `GET` | `/api/v1/pipelines/{id}` | `GetPipeline` |
| `PATCH` | `/api/v1/pipelines/{id}` | `RenamePipeline` / whole-`stages[]` replace (`AddStage`/`RenameStage`/`ReorderStages`/`RemoveStage` collapse to one atomic aggregate write, per 4C §4.4's "Stages embedded, always read/written together") |
| `POST` | `/api/v1/pipelines/{id}/default` | `SetDefaultPipeline` |

Permission: `deal:write`/`deal:read` (DEP-6G-03 — no dedicated `pipeline:*` scope exists in 5B; Pipelines exist to serve the Deal process).

**`PATCH .../pipelines/{id}` stage validation** (application layer, since `stages` is unstructured JSONB to the DB): unique `order` per stage, exactly one `is_terminal_win`, 1–20 stages (4C §4.4 invariants 1–3), and — critically — a stage cannot be removed if any `crm.deals.current_stage_id` currently references it (checked via `SELECT 1 FROM crm.deals WHERE pipeline_id=$1 AND current_stage_id=$removed_stage_id AND status='OPEN' LIMIT 1` inside the same transaction as the `stages` `UPDATE`, so the check and the write are atomic — this is exactly the case a bare `SELECT`-then-`UPDATE` outside a transaction would race).

**No `DELETE /pipelines/{id}` — DEFERRED / NOT EXPOSED, on DDD-command grounds, not a grant gap.** 4C's Pipeline command catalogue (§4.4, §11) defines `CreatePipeline`, `RenamePipeline`, `AddStage`, `RenameStage`, `ReorderStages`, `RemoveStage`, `SetDefaultPipeline` — no `DeletePipeline` command exists at all. This document does not invent one. (For completeness: even if a delete command existed, `crm.deals.pipeline_id` carries a real `ON DELETE RESTRICT` foreign key, `fk_deals_pipeline`, `021_5D.sql` — but `app_api`/`app_worker` hold no `DELETE` grant on `crm.pipelines` in the first place, `021_5D.sql` grants only `SELECT, INSERT, UPDATE` — so the FK guard is currently unreachable by any application role regardless of the DDD question. Both facts point the same direction independently.)

**No independent `/pipeline-stages` resource** — stages are never addressable outside their parent Pipeline (embedded JSONB, ADR-5D-004, reconfirmed as **ADR-6G-03**).

**Readiness: IMPLEMENTATION-READY** for the five endpoints above; Pipeline deletion is DEFERRED / NOT EXPOSED, not blocked.

---

## 14. Activity / Call History API (Showcase I)

### 14.1 FR-CRM-003 and the Voice↔CRM Relationship

FR-CRM-003 requires full call history per Contact. The canonical representation is **`crm.activities` rows with `activity_type = 'CALL'`**, created by the CRM event subscriber consuming `call.ended` (4C §13.1, §17.1) — never a duplicate copy of `voice.call_sessions`. The `CALL` Activity's `payload` carries `{duration_seconds, direction, outcome, recording_ref, transcript_ref}` (4C §4.5.2) and `call_ref` points to `voice.call_sessions.id` (a cross-schema logical reference, 5D §13) for a client that needs the full Voice-side record. This satisfies "full call history per Contact" via a lightweight, CRM-owned projection rather than re-storing Voice's data — exactly the design 3C §5.6 and 4C §20 already fixed; 6G does not redesign it, only exposes it as REST.

### 14.2 Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/activities` | `RecordActivity` — manual/system activity logging |
| `GET` | `/api/v1/contacts/{id}/activities` | Contact timeline (primary FR-CRM-003 surface) |
| `GET` | `/api/v1/deals/{id}/activities` | Deal activity timeline |
| `GET` | `/api/v1/companies/{id}/activities` | Company activity timeline |
| `GET` | `/api/v1/activities/{id}` | Get one Activity (API-layer convenience; not a distinct 4C query, low-risk PK+RLS read) |

**No `PATCH`, no `DELETE`, ever** — `405 Method Not Allowed`. This is a Phase 5 invariant (`REVOKE UPDATE, DELETE ON crm.activities`, `022_5D.sql`), not merely an API-layer choice (matches 6A §7.6's "append-only/immutable resources" rule exactly).

**No global `GET /api/v1/activities`** — 4C's only defined read query is `GetActivitiesForSubject` (§12); a tenant-wide activity feed is not a source-grounded query and is not exposed.

### 14.3 Timeline Read

```
GET /api/v1/contacts/{contact_id}/activities?type=CALL&occurred_after=2026-08-01T00:00:00Z
```
Cursor-paginated, ordered `occurred_at DESC, id` (matches `idx_act_subject`'s column order exactly). Allow-listed filters: `type` (`activity_type`), `occurred_after`/`occurred_before`. `call_ref` filter also allowed (backed by `idx_act_call_ref`).

**Partition pruning:** the query pattern documented in `5D §15.3` recommends an `occurred_at >=` bound for large lookback windows; this API defaults `occurred_after` to unset (full history) but documents that unbounded historical queries on high-volume contacts pay the BRIN-index cost rather than a partition-pruned one — acceptable per 5D's stated retention/volume assumptions.

### 14.4 Create Activity

```json
POST /api/v1/activities
{ "activity_type": "MEETING", "subject_type": "CONTACT", "subject_id": "0193...",
  "occurred_at": "2026-08-27T10:00:00Z", "summary": "In-person demo", "payload": {} }
```
Permission gates on the *subject's* resource type (`contact:write` for `CONTACT`/`COMPANY` subjects — reusing the CRM-write scope per DEP-6G-03 — `deal:write` for `DEAL` subjects). `actor_type`/`actor_ref`/`actor_name` are always server-derived from the authenticated principal — never client-supplied (mass-assignment guard). `occurred_at` cannot be in the future; human-created manual activities may backdate up to 90 days (4C §4.5 invariant 1) — a system-created activity (the Voice subscriber path) is exempt from the 90-day backdate cap since it always reflects a just-completed call.

**Duplicate delivery:** the Voice→CRM `call.ended` handler is the only automated writer of `CALL` activities; at-least-once event delivery is handled durably via `crm.fn_claim_event('crm.call_ended_subscriber', <event_id>, <organization_id>)` (`094_5D3.sql`, §23) — the claim and the `RecordActivity` write commit atomically in one transaction, so a redelivered event either finds itself already claimed (no-op, `crm.activities` gets no second row) or genuinely wins the claim and proceeds. This is a real `PRIMARY KEY`-backed guarantee, not a `SELECT`-then-`INSERT` pre-check — `crm.activities` itself still carries no unique constraint on `call_ref` (a call can legitimately generate more than one Activity type, e.g. a follow-up `NOTE`), but duplicate-delivery protection no longer depends on that column at all.

**Readiness: IMPLEMENTATION-READY.**

---

## 15. Task API

| Method | Path | Command |
|---|---|---|
| `POST` | `/api/v1/tasks` | `CreateTask` |
| `GET` | `/api/v1/tasks` | List (filters: `assigned_to`, `status`, `due_before`/`due_after`, `subject_type`+`subject_id`) |
| `GET` | `/api/v1/tasks/{id}` | Get |
| `PATCH` | `/api/v1/tasks/{id}` | Mutable fields while `status = OPEN` (`title`, `due_at`, `priority`, `assigned_to`) |
| `POST` | `/api/v1/tasks/{id}/complete` | `CompleteTask` |
| `POST` | `/api/v1/tasks/{id}/cancel` | `CancelTask` |
| `GET` | `/api/v1/contacts/{id}/tasks` | `GetTasksForSubject` (nested convenience) |
| `GET` | `/api/v1/me/tasks` | `GetUpcomingTasks` — tasks assigned to the caller |

Permission: `contact:write`/`contact:read` (DEP-6G-03). `DueAt` must be in the future at creation (4C §4.6 invariant 1). `COMPLETED`/`CANCELLED` are terminal (`chk_tasks_status`, application-enforced transition guard) — `PATCH` after completion returns `409 STATE_CONFLICT`. No `DELETE` — terminal-status resource, matches 6A §7.6.

**Readiness: IMPLEMENTATION-READY.**

---

## 16. Note API

| Method | Path | Command |
|---|---|---|
| `POST` | `/api/v1/notes` | `AddNote` — always `note_source = HUMAN` for a tenant-authenticated caller |
| `GET` | `/api/v1/notes/{id}` | Get |
| `GET` | `/api/v1/contacts/{id}/notes` (+ Deal/Company equivalents) | `GetNotesForSubject` |
| `POST` | `/api/v1/notes/{id}/pin` | `PinNote` |
| `POST` | `/api/v1/notes/{id}/unpin` | `UnpinNote` |
| `DELETE` | `/api/v1/notes/{id}` | `DeleteNote` |

**No `PATCH` exists for any Note, human or AI-authored.** This is not merely "AI notes are immutable" (DDR-4C-003, enforced by `trg_ai_note_immutable`) — 4C's command catalogue (§4.7, §11.3) never defines a body-edit command for a *human* note either. The database's `UPDATE` grant on `crm.notes` exists only to support `pinned_at`/`updated_at`/(the trigger's own before-image check) — exposing a body-edit `PATCH` would have zero grounding in the DDD. If a human's note needs correcting, they delete it and add a new one — consistent with the same "corrections are new records" philosophy the platform applies to Activities.

**`DELETE /notes/{id}`** maps to `UPDATE crm.notes SET deleted_at = NOW()` (soft-delete, per 6A §7.6 and the `deleted_at` column already on the table) — not a raw SQL `DELETE`, even though `app_api` holds the `DELETE` grant (`022_5D.sql`). Permission: the note's own `author_ref` may always delete their own note; deleting *someone else's* human note requires an elevated check. 5B has no `crm:admin` permission (4C §4.7 invariant 2 names one that doesn't exist in the frozen catalog) — this document falls back to an `OWNER`/`ADMIN` role check for non-author deletion, documented as an interim mapping (**DEP-6G-02**). AI-generated notes may be deleted (soft-delete) by anyone holding `contact:write` on the subject — 4C explicitly permits deletion of AI notes, only body-editing is forbidden.

**Readiness: IMPLEMENTATION-READY.**

---

## 17. Appointment API (Showcase E)

### 17.1 Endpoints

| Method | Path | Command |
|---|---|---|
| `POST` | `/api/v1/appointments` | `BookAppointment` |
| `GET` | `/api/v1/appointments` | List (filters: `contact_id`, `organizer_ref`, `status`, date range) |
| `GET` | `/api/v1/appointments/{id}` | Get |
| `POST` | `/api/v1/appointments/{id}/confirm` | `ConfirmAppointment` |
| `POST` | `/api/v1/appointments/{id}/reschedule` | `RescheduleAppointment` |
| `POST` | `/api/v1/appointments/{id}/cancel` | `CancelAppointment` |
| `POST` | `/api/v1/appointments/{id}/complete` | `MarkCompleted` |
| `POST` | `/api/v1/appointments/{id}/no-show` | `MarkNoShow` |
| `GET` | `/api/v1/contacts/{id}/appointments` | `GetAppointmentsForContact` |

### 17.2 State Machine (4C §7.3)

```
[*] → SCHEDULED → CONFIRMED → COMPLETED [*]
        │             │  └────→ NO_SHOW [*]   (only if scheduled_start is in the past)
        │             └────→ CANCELLED [*]     (CancellationReason required from CONFIRMED)
        └───────────────────→ CANCELLED [*]
```

### 17.3 Book / Reschedule / Cancel

`POST /appointments` — `{contact_id, organizer_ref, title, scheduled_start, scheduled_end, location, source}`. `scheduled_end > scheduled_start` is a real `CHECK` (`chk_appt_end_after_start`). `BookingWindowEnforced` (≤ 90 days out, configurable) and `organizer_ref` must be an active Member (4C §4.8 invariant 4) are application-layer checks. `source` is server-derived: `MANUAL` for a human-authenticated caller, `AI_AGENT` for the internal `BookAppointmentFromCall` tool-callable path (with `conversation_ref` set), `WORKFLOW` for the Workflow Engine's node executor.

`POST /appointments/{id}/reschedule` — `{scheduled_start, scheduled_end}` — an action endpoint, not a `PATCH`, because it re-runs both the `end > start` and `BookingWindowEnforced` guards and emits `AppointmentRescheduled` (old vs. new start, 4C §10.5) — a plain `PATCH` on the raw fields would bypass those guards, exactly the case 6A §8.3 reserves action endpoints for. Only legal from `SCHEDULED`/`CONFIRMED`.

`POST /appointments/{id}/cancel` — `cancellation_reason` required only from `CONFIRMED` (`SCHEDULED → CANCELLED` needs no reason per the 4C diagram; `CONFIRMED → CANCELLED` does).

**`FR-EVT-001` `appointment.booked`** is emitted on every successful `POST /appointments`, regardless of `source` — covering both human-booked and AI-tool-booked appointments through the identical application service (§23).

**Concurrency — reschedule vs. cancel racing:** both are action endpoints with a `WHERE status IN (...)`-guarded `UPDATE` inside their transaction; whichever commits first wins, the loser's `UPDATE` affects 0 rows → `409`, `error.details.current_state`. No `SELECT ... FOR UPDATE` needed — same CAS-on-status pattern as Deals (§12.2).

**Readiness: IMPLEMENTATION-READY** for all nine endpoints.

---

## 18. Lead Scoring API (Showcase H)

### 18.1 The Four Layers (DDR-4C-006 — scoring is always asynchronous)

1. **Current state** — `contacts.lead_score` / `contacts.lead_temperature` (denormalized, `GET /contacts/{id}` or `GET /contacts/{id}/score`).
2. **Immutable history** — `crm.lead_score_records` (`GET /contacts/{id}/score-history`).
3. **Trigger** — never a client-invoked synchronous computation. Scores are recomputed by a Celery worker reacting to `call.ended`, `conversation.qualification_set`, `conversation.sentiment_computed`, `appointment.booked`, `deal.created` (4C §16.2) — always off any request path. The worker applies its result via `crm.fn_apply_lead_score()` (§18.1a), never a bare `UPDATE`.
4. **Implementation** — `LeadScoringService` (domain service) behind no public API surface; its internals (weights, signal formula) are never returned to a client.

### 18.1a `crm.fn_apply_lead_score()` — CAS-Safe Denormalized Apply

Every scoring computation, regardless of which trigger produced it, is applied via `crm.fn_apply_lead_score(p_contact_id, p_organization_id, p_score, p_previous_score, p_score_version, p_signals, p_computed_at, p_computed_by, p_computed_by_user_ref)` (`095_5D4.sql`) — never a bare `INSERT`-then-`UPDATE` pair. In one transaction: inserts the immutable `lead_score_records` row; locks the Contact row (`FOR UPDATE`); re-reads the true latest `lead_score_records` row for this Contact by `(computed_at, id)` ordering; applies the denormalized `contacts.lead_score`/`lead_temperature` **only if** the just-inserted row is still that latest row, returning `FALSE` (no denormalized change) otherwise. **No new column was added** — the fix is the Contact-row lock plus the recency comparison against the already-existing append-only history, not a new "current version" field. Live-validated: an older, slow-to-arrive computation applied after a newer one correctly loses (returns `FALSE`, denormalized fields untouched) while both immutable history rows persist regardless; a genuine two-connection concurrent race for the same Contact with different `computed_at` values converges on the objectively newer value regardless of which transaction's `INSERT` or lock acquisition happened to complete first.

### 18.2 Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/contacts/{id}/score` | Current `lead_score` + `lead_temperature` |
| `GET` | `/api/v1/contacts/{id}/score-history` | `GetLeadScoreHistory` — paginated, `computed_at DESC` |

### 18.3 What Is Deliberately NOT Exposed

- **`POST .../score/recompute`** — 4C defines no manual "trigger a recompute" command; scoring is entirely event-subscription-driven (DDR-4C-006). Inventing a synchronous or even async-trigger endpoint here would fabricate a capability the DDD never specifies. **DEFERRED / NOT EXPOSED.**
- **`POST .../score/override`** (manual override) — 4C's `manual_score_override` use case exists in the package structure (§18 packaging, `lead_scoring/application/use_cases/manual_score_override.py`) and requires `contact:score_override` permission — which **does not exist in 5B**. Exposing manual override under the nearest existing permission (`contact:write`, MEMBER-eligible) would let any MEMBER-role user manipulate a lead's score, directly enabling the "score manipulation" abuse scenario named in §36's security review. This document does **not** expose a manual-override endpoint at all in this revision. **DEP-6G-04, NON-BLOCKING** (not exposing is the safe default; a future 5B permission amendment — `contact:score_override`, `OWNER`/`ADMIN` only — is the correct unblock, not a workaround).

### 18.4 Response Shape — Safe Fields Only

`GET /score-history` returns `{score, previous_score, score_version, computed_at, computed_by}` and a **redacted** view of `signals`: `[{signal_type, weight, source}]` — `raw_value` is omitted from the public response when its value could reveal internal AI/provider scoring internals beyond what a tenant needs (e.g., a raw sentiment float from a specific model). This is a deliberate response-model choice (6A §10.2's "explicit allow-list" principle) — the full `signals` JSONB stays in the database and in internal tooling, not in the tenant-facing API, per the instruction to derive safe response fields rather than expose scoring-signal internals unrestrictedly.

**Readiness: IMPLEMENTATION-READY** for the two read endpoints. Recompute and manual-override are DEFERRED / NOT EXPOSED.

---

## 19. Custom Field API

| Method | Path | Command |
|---|---|---|
| `POST` | `/api/v1/crm-field-definitions` | `CreateField` |
| `GET` | `/api/v1/crm-field-definitions` | List (one org-wide set) |
| `PATCH` | `/api/v1/crm-field-definitions/{field_id}` | `UpdateField` |
| `POST` | `/api/v1/crm-field-definitions/{field_id}/archive` | `DeactivateField` (`is_active = false`) |

No `DELETE` — 4C's `CRMFieldDefinitionSet` (§4.10) defines create/update/deactivate only; a hard-delete command doesn't exist, and deactivation is the correct terminal state for a field that historical `custom_field_values` still reference.

`FieldType ∈ {TEXT, NUMBER, DATE, BOOLEAN, SELECT, MULTISELECT}`; `SelectOptions` required (and validated non-empty) only for `SELECT`/`MULTISELECT`. Max 50 fields per tenant enforced before insert (`SELECT jsonb_array_length(fields) FROM crm.crm_field_definitions WHERE organization_id = $1` inside the same transaction as the append, to avoid a TOCTOU race on the cap).

**Values** are never separate rows — they live as JSONB array elements on `contacts.custom_field_values`/`companies.custom_field_values`/`deals.custom_field_values`, set only through those resources' own `PATCH`/create endpoints (§8.5, §11, §12), each validated against: the referenced `field_id` belongs to the caller's tenant (never a foreign-tenant definition — checked by loading the tenant's own `CRMFieldDefinitionSet` before validating the array, never trusting a client-supplied `field_id` blindly), `is_active = true`, `AppliesTo` matches the target entity type, and the value's shape matches `FieldType`.

**Permission: `crm_field:manage`** (`096_5B2.sql`, `OWNER`/`ADMIN` only). Revision 1 had mapped this onto `contact:write` (`MEMBER`-eligible) for lack of a dedicated scope, flagging the mismatch as DEP-6G-10 — a field-definition change has tenant-wide schema impact (every future Contact/Company/Deal create/edit is affected), a materially larger blast radius than an ordinary per-record edit. `crm_field:manage` closes that gap. **DEP-6G-10 is RESOLVED.**

**Readiness: IMPLEMENTATION-READY.**

---

## 20. Consent API (Showcase G)

### 20.1 What This API Answers

How a tenant records consent, how history is read, what "effective consent" means right now, and how withdrawal is represented — all without ever mutating historical evidence.

### 20.2 Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/contacts/{contact_id}/consent` | Append a new `ConsentRecord` |
| `GET` | `/api/v1/contacts/{contact_id}/consent` | Effective consent per `(purpose, channel)` |
| `GET` | `/api/v1/contacts/{contact_id}/consent/history` | Full append-only history, cursor-paginated |

Permission: `consent:manage` (append), `consent:read` (read) — both exist in 5B exactly as named, granted to `OWNER`/`ADMIN`/`MEMBER`.

### 20.3 Append

```json
POST /api/v1/contacts/{contact_id}/consent
{
  "purpose": "OUTBOUND_CALL", "channel": "VOICE", "status": "GRANTED",
  "source": "VERBAL_ON_CALL", "source_ref": "<call_id>",
  "evidence": {"transcript_excerpt_ref": "..."},
  "obtained_at": "2026-08-27T10:00:00Z", "expires_at": null
}
```
`obtained_at` required when `status = GRANTED`; `withdrawn_at` required when `status = WITHDRAWN` (`chk_cr_status`-adjacent application validation — the DB CHECK validates the vocabulary, the applicaton validates the required-companion-field rule, same layering pattern as `lead_temperature`). Pure `INSERT` into `crm.consent_records` — **no endpoint accepts a body field that would map to `UPDATE`**; there is no consent record ID accepted for mutation anywhere in this API. `REVOKE UPDATE, DELETE ON crm.consent_records` (`024_5D.sql`) makes this a physical guarantee, not just a documented convention.

**Withdrawal is a new record, never a mutation of the `GRANTED` one:**
```json
POST /api/v1/contacts/{contact_id}/consent
{ "purpose": "OUTBOUND_CALL", "channel": "VOICE", "status": "WITHDRAWN",
  "source": "SMS_REPLY", "withdrawn_at": "2026-08-27T11:00:00Z" }
```
Both records persist; "effective consent" is always "most recent record by `recorded_at` for this `(contact_id, purpose, channel)`" (5D §15.5's exact query pattern), never a computed diff.

### 20.4 Consent vs. Suppression — Not Interchangeable

A Contact can have `consent.status = WITHDRAWN` for `MARKETING` purpose while having **no** active suppression at all (they withdrew marketing consent but can still be called for `TRANSACTIONAL` reasons on a different purpose/channel), or the reverse (an active `REGULATORY` suppression exists on their phone number with no consent record ever having been created for this org, e.g., the number appeared on a national DNC registry sync before this org ever contacted them). `GET /contacts/{id}` never conflates the two — `consent_status` (a summary field on Contact) and `do_not_call` (denormalized suppression read) are separate fields with separate meanings, and neither is authoritative over the other's domain (§21).

**Readiness: IMPLEMENTATION-READY.**

---

## 21. Suppression / DNC API (Showcase F — Highest Risk)

### 21.1 The Non-Negotiable Rule

**`crm.contacts.do_not_call` is never read for enforcement, by anything, anywhere in this API.** The authoritative source is `crm.contact_suppressions`, keyed on `phone_e164` (ADR-5D-002) — not `contact_id` — precisely so suppression survives Contact deletion, GDPR erasure, merge, and re-import (5D §16.8).

### 21.2 Endpoints

| Method | Path | Purpose | Permission |
|---|---|---|---|
| `GET` | `/api/v1/suppressions/check` | Effective suppression check (`phone_e164`, `channel` query params) | `suppression:read` |
| `POST` | `/api/v1/suppressions` | Create an **ORG**-scope suppression | `suppression:manage` |
| `GET` | `/api/v1/suppressions` | List (own ORG rows + all PLATFORM/REGULATORY rows) | `suppression:read` |
| `GET` | `/api/v1/suppressions/{id}` | Get one | `suppression:read` |
| `POST` | `/api/v1/suppressions/{id}/lift` | ACTIVE → LIFTED via `crm.lift_suppression()` | `suppression:lift` |
| `POST` | `/api/v1/contacts/{contact_id}/suppress` | Convenience: create an ORG suppression keyed on the Contact's current `phone_e164` | `suppression:manage` |

**PLATFORM/REGULATORY suppression creation and lift are never reachable through this API** — those rows are inserted/lifted exclusively by `app_platform_admin` (BYPASSRLS), which is not a role any tenant-facing endpoint assumes. That surface belongs to a future Admin Control Plane. **DEP-6G-08, DEFERRED TO 6M.**

### 21.3 Effective Suppression Check

```
GET /api/v1/suppressions/check?phone_e164=%2B919876543210&channel=VOICE
```
Executes both halves of `5D §16.4`'s combined query — the ORG-scope check and the PLATFORM/REGULATORY check — and returns:
```json
{ "data": { "suppressed": true, "scope": "ORG", "reason": "CUSTOMER_REQUEST", "suppression_id": "0193..." } }
```
or `{"data": {"suppressed": false}}`. If **both** ORG and PLATFORM/REGULATORY rows are active simultaneously, the response reports the most restrictive (PLATFORM/REGULATORY takes precedence in the `scope` field) but the check itself is a boolean OR of both — matching `5D §16.4`'s "NOT_SUPPRESSED only if both queries return 0 rows" exactly.

**This is the exact endpoint 6H must call before dispatching any campaign call — never a read of `contacts.do_not_call`** (§23.2).

### 21.4 Create ORG Suppression

```
POST /api/v1/suppressions
Idempotency-Key: <required>
{ "phone_e164": "+919876543210", "channel": "ALL", "reason": "CUSTOMER_REQUEST", "source": "VERBAL_ON_CALL", "source_ref": "<call_id>" }
```
`organization_id` and `scope = 'ORG'` are always server-derived — the RLS `WITH CHECK` (`rls_suppression_insert`) would reject a mismatched value anyway, but the API never even accepts them as client-settable fields (defense-in-depth, 6A §22).

**Duplicate handling — the `085_5D1.sql` mechanism, exactly:** `uq_sup_active` is a partial unique index on `(organization_id, phone_e164, scope, channel) WHERE status = 'ACTIVE'`, with `NULLS NOT DISTINCT`. A second `INSERT` for the identical tuple while the first is still `ACTIVE` raises `unique_violation` at the database engine level — this is a real, live-validated constraint (5L §26), not an application-only pre-check. The API catches this specific constraint violation and returns `409 Conflict`, `error.code = STATE_CONFLICT`, `error.details.reason = "ALREADY_SUPPRESSED"`, `error.details.existing_suppression_id` (resolved by a follow-up `SELECT` for the active row). A **different** `reason`/`source` for the same `(org, phone, scope, channel)` is still rejected — per the migration's own documentation, two ACTIVE rows for the identical tuple are "functionally the same suppression regardless of differing reason/source."

**A different `channel` for the same phone is a genuinely independent row** — `VOICE`-channel and `SMS`-channel suppressions for the same number coexist (both legitimately ACTIVE), matching `scope` being part of the uniqueness key too: an `ORG`-scope and a `PLATFORM`-scope suppression for the same phone/channel are independent, both-valid rows (5L §26 "cross-scope independence preserved," live-validated).

### 21.5 Lift

```
POST /api/v1/suppressions/{id}/lift
```
Calls `crm.lift_suppression(p_suppression_id, p_lifted_by_ref, p_organization_id)` — the `SECURITY DEFINER` function, never a direct `UPDATE` (`app_api`/`app_worker` hold no `UPDATE` grant on `crm.contact_suppressions` at all, `024_5D.sql`). The function itself validates ownership (ORG suppressions: caller's tenant must match; PLATFORM/REGULATORY: rejected unless `p_organization_id IS NULL`, which this tenant-facing endpoint never passes — so a tenant caller can **never** lift a PLATFORM/REGULATORY row through this API, enforced twice: once by the function's own guard, once by this endpoint simply never being wired to the platform-admin code path) and current status (`ACTIVE` only — `409` `error.details.reason = "SUPPRESSION_NOT_LIFTABLE"` if already `LIFTED` or expired-by-time). On success: `audit.fn_insert_audit_event(action_kind => 'SUPPRESSION_LIFTED', ...)` — this exact value already exists in 5J's governed vocabulary (§5 finding 5), no amendment needed — and an `audit.domain_event_outbox` row for `contact.suppression_lifted`.

**Re-insert after lift:** a `LIFTED` row does not block a fresh `POST /suppressions` for the same tuple — `uq_sup_active`'s `WHERE status = 'ACTIVE'` predicate excludes `LIFTED` rows entirely, so re-suppression after a lift is a normal, unobstructed `INSERT` creating a brand-new row (the original stays intact as history, 5D §16.2).

### 21.6 Suppression Lifecycle — Full Test Matrix (per task requirement)

| Scenario | Outcome |
|---|---|
| ORG suppression, own tenant | Full CRUD-minus-update as specified above |
| PLATFORM suppression | Read-only via `GET /suppressions` (visible cross-tenant by RLS design); create/lift not reachable from this API |
| REGULATORY suppression | Same as PLATFORM |
| Channel-specific (`VOICE` vs `SMS` vs `ALL`) | Independent rows; `ALL` matches any channel in the effective-check query (`channel = $channel OR channel = 'ALL'`) |
| Expiry | Never a DB mutation — evaluated at read time via `expires_at IS NULL OR expires_at > NOW()` in every enforcement query and in `GET /suppressions/check`; `idx_sup_expires` supports a housekeeping *read* (e.g., "show suppressions expiring soon"), never a background *writer* |
| Lift | Via `crm.lift_suppression()` only, as above |
| Reinsert after lift | Succeeds — new row, `uq_sup_active` only guards ACTIVE rows |
| Concurrent duplicate suppress | Second `INSERT` gets a real `unique_violation` from `uq_sup_active` (live-validated at the DB engine level per 5L §26 — a genuine two-process race, not simulated sequentially) |
| Contact delete/GDPR erasure | No effect — suppression keyed on `phone_e164`, never touched during Contact erasure (5D §5.1, §16.8) |
| Contact merge | No effect on suppression rows for either the primary's or the secondary's phone — merge never writes `contact_suppressions` (§10.2 table) |
| Contact re-import (same phone) | New Contact row created; first eligibility check for that phone finds the original suppression and is suppressed immediately — this is the exact scenario ADR-5D-002 exists to guarantee |
| Cross-tenant access | RLS: a tenant sees only its own ORG rows plus all PLATFORM/REGULATORY rows; attempting to read another tenant's ORG-scope row returns 0 rows (never 403 — matches 6A §7.4's non-disclosure rule) |
| Missing tenant context | `organization.current_tenant_id()` is `NULL` → RLS predicate matches 0 rows on the ORG half of every query — fail-closed (6A §23.3) |

### 21.7 Campaign (6H) Handoff — Formal Contract, In-Process

**6H must never read `contacts.do_not_call`, and must never call its own public REST endpoint over HTTP to check suppression on every dispatched call — both the wrong mechanism.** The canonical check is one application service, `EffectiveSuppressionService.check(phone_e164, channel, tenant_context)`, implemented once against exactly the two queries in §21.3 (ORG-scope + PLATFORM/REGULATORY-scope). `GET /api/v1/suppressions/check` is a REST front door onto this same service, for human/partner-API-key callers. **6H's campaign dispatcher, running in the same modular monolith, calls the identical in-process application service directly** — not a second implementation of the suppression query, and not a network hop through the platform's own public ingress for every outbound call (which 6A §6's general rule against unnecessary internal HTTP hops already discourages, and which would also make 6H's per-call dispatch latency budget pay REST-stack overhead it doesn't need to). The same in-process pattern applies to effective-consent reads (§20) where 6H's dispatch policy needs them. This is the single most important cross-phase contract this document establishes (§23.2). Recorded as **DEP-6G-11 — RESOLVED from 6G's side (the contract, including its in-process shape, is fully specified here); 6H's consumption of it is DEFERRED TO 6H.**

**Readiness: IMPLEMENTATION-READY** for all six endpoints. PLATFORM/REGULATORY administration is DEFERRED TO 6M, not blocked.

---

## 22. GDPR / Retention

### 22.1 Contact Erasure

```
DELETE /api/v1/contacts/{contact_id}
```
Maps to the exact field-set `UPDATE` specified in `5D §5.1` / ADR-5D-007 — a single, deterministic, plain `UPDATE` (no `SECURITY DEFINER` function exists for this, and none is needed: `app_api` already holds `UPDATE` on `crm.contacts`, and the erasure is a fixed, non-partial field list, not an arbitrary caller-supplied patch):

```sql
UPDATE crm.contacts
SET full_name = '[ERASED]',
    phone_e164 = '+99000000000',
    secondary_phone_e164 = NULL,
    primary_email = NULL,
    primary_email_normalized = NULL,
    address_line1 = NULL, address_line2 = NULL, address_city = NULL,
    address_state = NULL, address_postal_code = NULL, address_country_code = NULL,
    deleted_at = NOW()
WHERE id = $1 AND organization_id = organization.current_tenant_id();
```

This is safe precisely because it is **not** a generic partial-update endpoint accepting arbitrary fields — it is one hardcoded field list, matching 5D's own erasure sequence exactly, gated behind `contact:delete` (self-service, tenant-initiated) or `data_subject:manage` (formal Data-Subject-Request-driven erasure, per 5B's catalog). Permission: **both** exist in 5B; this document requires `contact:delete` at minimum, and treats a Data-Subject-Request-triggered erasure (via whatever surface a future Core Platform/Compliance document exposes DSR fulfillment through) as additionally gated by `data_subject:manage` for that trigger path.

**What survives:** Activities, Deals, Tasks, Notes, Appointments, LeadScoreRecords (all reference `contact_id` — untouched, per §12 "Aggregate independence" cross-schema rule). Suppression records for the original phone (§21.6). Consent records (§20 — retained per compliance policy, never erased by this endpoint).

**Re-import:** the partial unique index (`uq_contacts_phone ... WHERE deleted_at IS NULL`) excludes the tombstoned row, so a fresh `POST /contacts` for the same original phone number succeeds and creates a new row (§8.2). The new contact is subject to the same suppression check as any other — if the number was also suppressed, it stays suppressed regardless of the erasure.

**Cross-tenant:** the `WHERE organization_id = organization.current_tenant_id()` clause plus RLS makes an attempt to erase another tenant's contact a 404, not a 403 or a silent no-op.

**Readiness: IMPLEMENTATION-READY.**

### 22.2 What Is Not Redesigned Here

Retention periods, `CompliancePolicy.RetentionProfile`, and formal Data Subject Request workflow (verification, holds, rejection) are Core Platform / Compliance concerns (5B, 5J, and whichever Phase 6 document owns the DSR surface) — this document only fixes the CRM-side erasure mechanics a DSR fulfillment flow would invoke.

---

## 23. Voice → CRM Boundary

### 23.1 In-Process, Never a Network Hop

Per 6A §6's binding rule and 4H §9.1's invariant ("the voice hot path must never make a synchronous call to ... CRM-write"), every Voice→CRM interaction in this document is either (a) an **in-process application-service call** invoked by a Tool Runner (4B), or (b) an **async event subscription** reacting to a domain event already on the durable outbox/event bus. Nothing here introduces an HTTP round-trip on the call turn.

| Mechanism | Voice-side trigger | CRM-side entry point | Endpoint(s) it corresponds to |
|---|---|---|---|
| Tool-callable, in-process | `createLead`/`updateLead` tool call | `FindOrCreateContact` / `UpdateContactFromCall` | Same application service as `POST /contacts` / `PATCH /contacts/{id}` |
| Tool-callable, in-process | `bookAppointment` tool call | `BookAppointmentFromCall` | Same application service as `POST /appointments` |
| Tool-callable, in-process | `createTask`/`scheduleFollowup` tool call | `CreateTaskFromCall` | Same application service as `POST /tasks` |
| Event subscription | `call.ended` | `handle_call_completed` — find/create Contact, `RecordActivity(CALL)`, `update_last_contacted_at()` | Same write path as `POST /activities` |
| Event subscription | `conversation.qualification_set` | `handle_qualification_set` — `SetQualificationStatus` | Same as `POST /contacts/{id}/qualify` |
| Event subscription | `conversation.summarization_completed` | `handle_summary_ready` — `AddNote(source=AI_SUMMARY)` | Same as `POST /notes`, but with `note_source = AI_SUMMARY` — a value only the internal event-subscriber principal may set (never a tenant/API-key caller, §16) |

### 23.2 Contact Creation From Inbound Calls

Per 4C's `ContactFactory.create_from_call`: an inbound call from an unrecognized number creates a minimal Contact (`full_name` defaults to the phone number string, `source = INBOUND_CALL`, `lead_status = NEW`) — this happens entirely inside the `call.ended`/`handle_call_completed` subscriber, never via a client-facing `POST /contacts` call with a spoofable `source`.

### 23.3 last_contacted_at, Qualification Write-Back, Lead-Score Triggers

All three are event-driven side effects of the subscriptions above, using the exact application services this document already specifies for the equivalent human-facing action — there is no parallel/duplicate business logic for the AI path (4C §26 requirement 5, reconfirmed).

**Readiness: IMPLEMENTATION-READY** for the entire boundary — no endpoint gap exists on the CRM side; the boundary is fully described by application-service reuse, not new REST surface.

---

## 24. CRM → Campaign Boundary

6H must be able to answer, using the contracts fixed in this document — never `contacts.do_not_call` — and, for the dispatch-time checks specifically, via the **in-process application service**, not a REST round-trip to 6G's own endpoint (§21.7):

| 6H question | 6G contract | Call shape |
|---|---|---|
| Is this phone/contact suppressed? | `EffectiveSuppressionService.check()` (§21.3, §21.7) | In-process (dispatch-time); `GET /api/v1/suppressions/check` is the same service's REST front door for human/partner callers |
| What consent evidence/status exists? | The same-shaped effective-consent read (§20) | In-process (dispatch-time); `GET /api/v1/contacts/{id}/consent` is the REST front door |
| Is this contact eligible (combined)? | 6H combines the above two — 6G does not define a single "is eligible" service or endpoint, since eligibility policy (which purposes/channels a campaign type requires) is a 6H concern, not a CRM one | — |
| What is lead status/qualification/score? | `GET /api/v1/contacts/{id}` (§8.4), `GET /api/v1/contacts/{id}/score` (§18) | REST (not a per-call dispatch-time hot path) |
| Campaign-origin contact metadata | `contacts.campaign_ref`, `contacts.source = CSV_IMPORT`, exposed on `ContactDTO` already (§8.4) — no new field needed | REST |

No campaign-specific CRM endpoint is created — 6H is expected to compose the above, not receive a bespoke `/campaign-eligibility` endpoint from 6G. **DEP-6G-11** (§21.7) is the formal record of this handoff, now explicit about the in-process shape of the two dispatch-time checks.

---

## 25. CRM → Integrations Boundary

FR-CRM-004's external CRM sync is **not designed here**. 6G's contribution to that future 6J document is limited to:

- **Canonical entities:** Contact/Company/Deal/Activity/Note/Appointment as specified in §8–§17, with stable `id` (UUIDv7), `updated_at` (already present on every mutable table), and `organization_id` — exactly the "sync-safe IDs/updated_at semantics already present" the boundary requires.
- **Domain events:** every event in §29's catalogue is available on `audit.domain_event_outbox` for 6J's connector adapters to subscribe to.
- **`CrmSyncPort`** (4C §5.7, 3C §5.7): `push_contact()`/`push_deal()` are Phase 18/6J's port contract to implement against — 6G fixes only that the port exists conceptually and what data it would push (the same `ContactDTO`/`DealDTO` shapes already defined here), never a Salesforce/HubSpot/Zoho endpoint, OAuth flow, or connector schedule. **DEP-6G-12, DEFERRED TO 6J.**

---

## 26. Transactions

For every mutation category:

| Mutation | Validation (no I/O) | Transaction content | SECURITY DEFINER? | Commit point | Post-commit | Domain event | Audit |
|---|---|---|---|---|---|---|---|
| Create Contact | E.164 format, tags/custom-field caps | `INSERT ... ON CONFLICT DO NOTHING` | No | After INSERT | — | `contact.created` (outbox) | `CONTACT_CREATED` (async) |
| Lead-status / Qualify / Convert | Transition legality against current state | Single-row `UPDATE crm.contacts` w/ `WHERE lead_status = $expected` CAS | No | After UPDATE | Score-trigger event (async worker, not this transaction) | `contact.lead_status_changed` / `contact.qualified` / `contact.converted` | Async |
| Merge | Both contacts exist, not already merged/erased, not cross-tenant | `crm.fn_merge_contacts()` — locks both Contact rows (deterministic order), field-fill, repoints Deals/Tasks/Notes/Appointments, marks secondary, inserts a PII-minimal marker Activity — all inside the function's own transaction | **Yes** (`crm.fn_merge_contacts()`, `093_5D2.sql`, function body current as of `097_5D5.sql` — centralization/atomicity, not privilege elevation) | Function return | — | `contact.merged` | `CONTACT_MERGED` (async) |
| GDPR Erase | None beyond ownership | Single fixed-field `UPDATE` | No | After UPDATE | — | `contact.erased` (propose; or reuse existing pattern) | `CONTACT_ERASED` — **already governed** (5J), **synchronous** per the Data-Subject/compliance category (5J §14.5) |
| Create Deal / Stage Move / Win / Lose / Abandon | Stage-belongs-to-pipeline, terminal check | Single-row CAS `UPDATE`/`INSERT` on `crm.deals` | No | After write | — | `deal.created`/`deal.stage_changed`/`deal.won`/`deal.lost`/`deal.abandoned` | Async |
| Book/Reschedule/Cancel/Confirm/Complete/No-Show Appointment | Guard per §17.2 | Single-row CAS `UPDATE`/`INSERT` on `crm.appointments` | No | After write | — | `appointment.*` (`appointment.booked` — FR-EVT-001) | Async |
| Record Activity (manual/API) | Type/subject validity, backdate cap | `INSERT` only (append-only) | No | After INSERT | Lead-status auto-advance check (same txn if it's the qualifying-Activity path) | `activity.recorded` | Async |
| Record Activity (Voice-event-driven) | Event not already claimed | `crm.fn_claim_event()` + `INSERT` into `crm.activities`, one transaction (§14.4, §23) | **Yes** (`crm.fn_claim_event()`, `094_5D3.sql`) | After INSERT | — | `activity.recorded` | Async |
| Apply Lead Score | Recency vs. existing history | `crm.fn_apply_lead_score()` — `INSERT` immutable record + Contact-row lock + conditional denormalized `UPDATE` (§18.1a) | **Yes** (`crm.fn_apply_lead_score()`, `095_5D4.sql`) | Function return | — | `contact.score_updated` | Async |
| Add Note | Author/subject validity | `INSERT` (or `UPDATE deleted_at`/`pinned_at` for pin/unpin/delete) | No | After write | — | `note.added`/`note.deleted` | Async |
| Consent Append | Required-companion-field rule | `INSERT` only | No | After INSERT | — | `consent.recorded` | Async |
| Suppression Create | Idempotent dedup via unique index | `INSERT`, relies on `uq_sup_active` for the race guarantee | No | After INSERT (or `unique_violation` caught) | — | `contact.dnc_flagged` / `suppression.added` | `SUPPRESSION_ADDED` — **already governed**, synchronous (compliance category, 5J §14.5) |
| Suppression Lift | Ownership/status inside the function | `crm.lift_suppression()` call | **Yes** | Function return | — | `contact.suppression_lifted` | `SUPPRESSION_LIFTED` — **already governed**, synchronous |
| Custom Field Definition CRUD | Field-count cap, type validity | Single-row `UPDATE crm.crm_field_definitions.fields` (whole-JSONB rewrite) | No | After UPDATE | Redis cache invalidation (`crm_field_defs:{org_id}`) | — | Async |

**Never held across a transaction, for any of the above:** an external HTTP call, a Voice/telephony provider call, an email/SMS/webhook dispatch, a scoring-model/provider call — matching 6A §35 exactly. Lead scoring computation happens entirely outside any of these transactions, in the Celery worker (§18.1).

---

## 27. Concurrency / Idempotency

| # | Scenario | Resolution |
|---|---|---|
| 1 | Two Contacts created with same phone, concurrently | `ON CONFLICT (organization_id, phone_e164) WHERE deleted_at IS NULL DO NOTHING`; 409 (tenant-facing) or idempotent-return (tool-callable path), §8.2 |
| 2 | Create Contact vs. GDPR erase (same phone, different contact rows possible) | Partial unique index excludes `deleted_at IS NOT NULL`; a create for a phone whose only existing row is erased succeeds cleanly — no race, since they operate on physically distinct rows once erasure has committed |
| 3 | Contact merge vs. contact update (on the secondary) | `crm.fn_merge_contacts()` locks both Contact rows (deterministic order) for its full duration; a concurrent `PATCH` on the secondary either commits first (its fields are visible to the merge's field-fill) or blocks until the merge transaction completes, §10.3 |
| 4 | Two merge requests, same pair | Idempotency-Key collapses exact retries; distinct concurrent requests are serialized by the function's own deterministic-order row locks — live-validated with a genuine two-connection race: one succeeds, the other receives a real `MERGE_SECONDARY_ALREADY_MERGED` exception, §10.4 |
| 5 | Lead-status update vs. AI qualification event | Both go through the same `SetQualificationStatus`/`UpdateLeadStatus` CAS-guarded `UPDATE`; last-committed wins, both are visible in the Activity/audit trail (§9.3) — no lock needed beyond the CAS |
| 6 | Manual override vs. delayed qualification event | Manual override is not exposed in this revision (§18.3) — moot until DEP-6G-04 is resolved |
| 7 | Owner reassignment races | Plain `UPDATE ... SET owned_by = $new` — last write wins; `OwnerAssigned` event fires each time; no invariant requires locking (assignment has no "current owner must match" guard in 4C) |
| 8 | Two Deal stage moves | CAS `UPDATE ... WHERE current_stage_id = $expected`, §12.2 |
| 9 | Stage move vs. Win/Lose | CAS `UPDATE ... WHERE status = 'OPEN'` on the terminal action; stage move doesn't touch `status`, §12.2 |
| 10 | Two Win/Lose/Abandon calls | Same CAS; loser gets `409 DEAL_TERMINAL`, §12.2 |
| 11 | Appointment reschedule vs. cancel | CAS `UPDATE ... WHERE status IN (...)`, §17.3 |
| 12 | Task completion vs. edit | `PATCH` on a `COMPLETED` task's CAS `UPDATE ... WHERE status = 'OPEN'` affects 0 rows → 409 |
| 13 | Duplicate Activity event delivery | `crm.fn_claim_event('crm.call_ended_subscriber', ...)` — atomic `PRIMARY KEY`-backed claim in the same transaction as the `INSERT`, §14.4/§23. Live-validated: a genuine two-connection concurrent claim on the identical event id returns exactly one `TRUE` and one `FALSE`, exactly one row persisted |
| 14 | Duplicate AI note creation | `crm.fn_claim_event('crm.summarization_completed_subscriber', ...)` — same atomic claim primitive as row 13, applied to the `AddNote(AI_SUMMARY)` side effect |
| 15 | Duplicate consent record delivery | Append-only by design — a duplicate delivery simply creates a second identical-looking record; "effective consent" always reads the latest, so a harmless duplicate never changes the effective answer. No dedup needed because duplication is not harmful for an append-only evidence log (unlike suppression, where a duplicate implies double-billing/double-DNC intent, not just double evidence) |
| 16 | Duplicate suppression creation | `uq_sup_active`, real `unique_violation`, §21.4 |
| 17 | Suppression lift vs. dispatch eligibility read | `crm.lift_suppression()` commits atomically; a concurrent `GET /suppressions/check` either sees the pre-lift (still `ACTIVE`) or post-lift (now `LIFTED`, not suppressed) state — no torn read is possible since Postgres MVCC gives each transaction a consistent snapshot |
| 18 | Suppression expiry boundary | Never a write race — `expires_at` is fixed at insert time and evaluated by every reader independently; two readers straddling the exact expiry instant may briefly disagree by definition of "at read time," which is the accepted, documented trade-off (5D §16.5) |
| 19 | Contact GDPR erase vs. active suppression | No interaction — suppression is phone-keyed and untouched by erasure (§21.6, §22.1) |
| 20 | Lead-score recompute results arriving out of order | **Resolved, not accepted as a risk.** `crm.fn_apply_lead_score()` (§18.1a) locks the Contact row and applies the denormalized `lead_score`/`lead_temperature` only if the just-inserted `lead_score_records` row is still the newest by `(computed_at, id)` — a stale, slow-to-arrive computation returns `FALSE` and leaves the denormalized fields untouched, while its own immutable history row still persists. This is the one narrow case where a Contact-row lock is justified (a real ordering invariant exists), not a blanket new locking scheme — consistent with 6A §17.3's instruction that locking be added only where a real invariant requires it. Live-validated under a genuine two-connection concurrent race for the same Contact. |

---

## 28. Authorization Matrix

Permissions are cited **exactly** as they exist in 5B (§27) — verbatim strings, no invented values.

| Endpoint group | Permission | OWNER | ADMIN | MEMBER | BILLING_ADMIN | VIEWER | API Key |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| Contact read | `contact:read` | ✅ | ✅ | ✅ | — | ✅ | Yes |
| Contact write / lead-status / qualify / tags / owner | `contact:write` | ✅ | ✅ | ✅ | — | — | Yes |
| Contact convert | `contact:convert` | ✅ | ✅ | ✅ | — | — | Yes |
| Contact delete (GDPR erase) | `contact:delete` | ✅ | ✅ | — | — | — | **No** (human session only) |
| Contact merge | `contact:merge` | ✅ | ✅ | — | — | — | **No** |
| Company / Pipeline / Task / Note / Appointment / Custom Field read | `contact:read` (DEP-6G-03) | ✅ | ✅ | ✅ | — | ✅ | Yes |
| Company / Pipeline / Task / Note / Appointment / Custom Field write | `contact:write` (DEP-6G-03) | ✅ | ✅ | ✅ | — | — | Yes |
| Deal read | `deal:read` | ✅ | ✅ | ✅ | — | ✅ | Yes |
| Deal write / stage move / owner | `deal:write` | ✅ | ✅ | ✅ | — | — | Yes |
| Deal terminal (win/lose/abandon) | `deal:close` | ✅ | ✅ | — | — | — | **No** |
| Suppression read / check | `suppression:read` | ✅ | ✅ | ✅ | — | — | Yes |
| Suppression create | `suppression:manage` | ✅ | ✅ | — | — | — | Yes (scope-limited key) |
| Suppression lift | `suppression:lift` | ✅ | ✅ | — | — | — | **No** |
| Consent read | `consent:read` | ✅ | ✅ | ✅ | — | — | Yes |
| Consent append | `consent:manage` | ✅ | ✅ | ✅ | — | — | Yes |
| Custom field definition admin | `crm_field:manage` (`096_5B2.sql`) | ✅ | ✅ | — | — | — | **No** |

**API-key eligibility policy (this document's addition, consistent with 6A §22/6B precedent):** an endpoint is API-key eligible when its permission is in the key's granted `scopes` **and** the action is reversible/non-catastrophic. GDPR erasure, contact merge, suppression lift, and Deal terminal closure are restricted to human JWT-session principals regardless of API-key scope grants — these are exactly the six operations §28 of the governing task named for special review, and all six are marked **No** above. Custom field definition administration is now gated on its own dedicated, `OWNER`/`ADMIN`-only permission (`crm_field:manage`) rather than a restricted-despite-broader-grant `contact:write` mapping, and remains API-key ineligible given its tenant-wide schema impact.

---

## 29. Audit

### 29.1 Write Path

**Every** CRM state-changing endpoint calls `audit.fn_insert_audit_event(...)` — never a direct `INSERT INTO audit.audit_events`, which is structurally impossible anyway (`REVOKE ALL ... FROM app_api, app_worker, app_readonly, app_platform_admin`, 5J §14.2). Synchronous vs. asynchronous follows 5J §14.5 exactly: CRM lifecycle mutations are the general "Configuration ... lifecycle changes → Asynchronous" category **except** the three values already governed for compliance-sensitive CRM actions (`CONTACT_ERASED`, `SUPPRESSION_ADDED`, `SUPPRESSION_LIFTED`), which fall under 5J's "Data subject requests" / compliance category and are **synchronous** — the audit insert is part of the same transaction, and a failure there aborts the erasure/suppression action itself. No new synchronous category is introduced by this document beyond what 5J already assigns to these three values.

### 29.2 Action Kind Vocabulary — Governed as of This Revision

| Classification | Values |
|---|---|
| **A. Exact existing, usable since Revision 1** | `CONTACT_ERASED`, `SUPPRESSION_ADDED`, `SUPPRESSION_LIFTED` (5J §14.3, Compliance/Data category) |
| **B. Semantically reusable** | None found — CRM's remaining mutations (Contact/Deal/Company/Pipeline/Task/Note/Appointment lifecycle) have no close analog elsewhere in the governed vocabulary; `AGENT_CREATED`/`AGENT_CONFIG_UPDATED`'s naming pattern is the template followed, not a value reused |
| **C. Newly governed by this revision's ¶ amendment to `5J-Analytics-Audit-Schema.md` §14.3** | `CONTACT_CREATED`, `CONTACT_UPDATED`, `CONTACT_MERGED`, `CONTACT_OWNER_ASSIGNED`, `LEAD_STATUS_CHANGED`, `QUALIFICATION_SET`, `LEAD_CONVERTED`, `DEAL_CREATED`, `DEAL_STAGE_CHANGED`, `DEAL_WON`, `DEAL_LOST`, `DEAL_ABANDONED`, `COMPANY_CREATED`, `COMPANY_UPDATED`, `PIPELINE_CREATED`, `PIPELINE_UPDATED`, `TASK_CREATED`, `TASK_COMPLETED`, `TASK_CANCELLED`, `NOTE_ADDED`, `NOTE_DELETED`, `APPOINTMENT_BOOKED`, `APPOINTMENT_CANCELLED`, `APPOINTMENT_RESCHEDULED`, `APPOINTMENT_COMPLETED`, `APPOINTMENT_NO_SHOW`, `CRM_FIELD_DEFINITION_CREATED`, `CRM_FIELD_DEFINITION_UPDATED`, `CONSENT_RECORDED` |

**5J was amended, documentation-only, exactly as the 6C/6D/6F precedent amendments were.** The underlying constraint (`chk_ae_action_kind`, length-only, `072_5J.sql`) meant every value in category C was already *usable* without any SQL change — but per the same precedent that governed 6C's †, 6D's ‡, and 6F's § amendments, a value only becomes *sanctioned* through a documented governance pass. `5J-Analytics-Audit-Schema.md` §14.3 now carries that pass (the ¶ marker), added in this reconciliation and requiring zero SQL migration. **DEP-6G-06 is RESOLVED.**

---

## 30. Domain Events / Outbox

Every event below is written to `audit.domain_event_outbox` (migration `077_5J1.sql`) in the same transaction as its triggering write — **no second, CRM-specific outbox table is introduced.**

| SRS / 4C event | `event_type` on outbox | Triggering endpoint |
|---|---|---|
| `lead.created` (FR-EVT-001) → `contact.created` (4C) | `contact.created` | `POST /contacts` |
| — | `contact.updated` | `PATCH /contacts/{id}` |
| `lead.qualified` (FR-EVT-001) → `contact.qualified`/`contact.disqualified` (4C) | `contact.qualified` / `contact.disqualified` | `POST /contacts/{id}/qualify` |
| — | `contact.lead_status_changed` | `POST /contacts/{id}/lead-status`, automatic Activity-driven transitions |
| — | `contact.converted` | `POST /contacts/{id}/convert` |
| — | `contact.merged` | `POST /contacts/{id}/merge` |
| — | `contact.owner_assigned` | `POST /contacts/{id}/owner` |
| — | `contact.score_updated` | Async scoring worker (never a REST endpoint, §18) |
| — | `contact.dnc_flagged` / `suppression.added` | `POST /suppressions`, `POST /contacts/{id}/suppress` |
| — | `contact.suppression_lifted` | `POST /suppressions/{id}/lift` |
| — | `company.created` / `company.updated` | `POST /companies`, `PATCH /companies/{id}` |
| — | `deal.created` / `deal.stage_changed` / `deal.won` / `deal.lost` / `deal.abandoned` | §12 endpoints |
| — | `activity.recorded` | `POST /activities` |
| — | `task.created` / `task.completed` / `task.cancelled` | §15 endpoints |
| — | `note.added` / `note.deleted` | §16 endpoints |
| `appointment.booked` (FR-EVT-001) | `appointment.booked` | `POST /appointments` |
| — | `appointment.confirmed` / `appointment.cancelled` / `appointment.completed` / `appointment.no_show` / `appointment.rescheduled` | §17 endpoints |
| — | `consent.recorded` | `POST /contacts/{id}/consent` |

**FR-SRS terminology vs. 4C terminology reconciliation:** the SRS names `lead.created`/`lead.qualified` (FR-EVT-001); 4C's actual event catalogue uses `contact.created`/`contact.qualified` (consistent with Lead=Contact, DDR-4C-001). This document uses 4C's exact names on the outbox (`event_type` field) since 4C is the authoritative domain vocabulary — a webhook-facing consumer that expects the SRS's product-language names (`lead.created`) is a webhook-topic-mapping concern for whichever document owns the outbound webhook topic catalog, not a reason to rename the internal domain event.

---

## 31. Error Catalog

Reusing 6A §24's families exclusively — no new top-level `error.code` is introduced. CRM-specific detail lives in `error.details.reason`:

| `error.details.reason` | `error.code` | Scenario |
|---|---|---|
| `DUPLICATE_PHONE` | `STATE_CONFLICT` | Concurrent/duplicate Contact create, §8.2 |
| `ILLEGAL_LEAD_TRANSITION` | `STATE_CONFLICT` | `POST /contacts/{id}/lead-status` to an illegal target, §9.2 |
| `ALREADY_CONVERTED` | `STATE_CONFLICT` | Second `POST /contacts/{id}/convert` |
| `CONTACT_ALREADY_MERGED` | `STATE_CONFLICT` | §10.3, §27 #3/#4 |
| `INVALID_QUALIFICATION_STATE` | `VALIDATION_ERROR` | `SetQualificationStatus` on a `NEW` contact with no Activity, §9.2 guard |
| `DEAL_TERMINAL` | `STATE_CONFLICT` | Stage move / second terminal action on a closed Deal, §12.2 |
| `INVALID_PIPELINE_STAGE` | `VALIDATION_ERROR` | `target_stage_id` not in the deal's pipeline, §12.2 |
| `PIPELINE_STAGE_HAS_DEALS` | `STATE_CONFLICT` | `PATCH /pipelines/{id}` attempting to remove a stage with `OPEN` Deals still in it, §13 (`PIPELINE_HAS_DEALS`/pipeline-level deletion is not applicable — Pipeline deletion is not exposed, §13) |
| `DUPLICATE_DOMAIN` | `STATE_CONFLICT` | Company `email_domain` uniqueness, §11 |
| `AI_NOTE_IMMUTABLE` | `STATE_CONFLICT` | (Structurally unreachable via this API since no body-edit endpoint exists at all, §16 — retained here only in case a future internal path attempts one and the DB trigger fires) |
| `MAX_CUSTOM_FIELDS` | `VALIDATION_ERROR` | §19 cap exceeded |
| `ALREADY_SUPPRESSED` | `STATE_CONFLICT` | §21.4, `uq_sup_active` violation |
| `SUPPRESSION_NOT_LIFTABLE` | `STATE_CONFLICT` | Lift on a non-`ACTIVE` row, §21.5 |
| `CONSENT_APPEND_ONLY` | `STATE_CONFLICT` | (Structurally unreachable — no mutation endpoint exists for consent, §20; retained for completeness) |
| `MERGE_SELF_REJECTED` / `MERGE_PRIMARY_ALREADY_MERGED` / `MERGE_SECONDARY_ALREADY_MERGED` / `MERGE_PRIMARY_ERASED` / `MERGE_SECONDARY_ERASED` | `STATE_CONFLICT` / `VALIDATION_ERROR` | `crm.fn_merge_contacts()` guard rejections, §10.3/§10.4 — mapped from the function's own exception messages |

---

## 32. Endpoint Contract Inventory

Latency tiers per 6A §11. `Idem.` = Idempotency-Key required. `Sync` = synchronous audit (per 5J §14.5); all others async.

| # | Method | Path | Permission | API Key | Idem. | Tier | Success | Readiness |
|---|---|---|---|---|---|---|---|---|
| 1 | POST | `/contacts` | `contact:write` | Yes | Yes | A | 201/200 | IMPLEMENTATION-READY |
| 2 | GET | `/contacts` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 3 | GET | `/contacts/{id}` | `contact:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 4 | PATCH | `/contacts/{id}` | `contact:write` | Yes | — | A | 200/412 | IMPLEMENTATION-READY |
| 5 | POST | `/contacts/{id}/lead-status` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 6 | POST | `/contacts/{id}/qualify` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 7 | POST | `/contacts/{id}/convert` | `contact:convert` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 8 | POST | `/contacts/{id}/owner` | `contact:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 9 | POST | `/contacts/{id}/tags` | `contact:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 10 | DELETE | `/contacts/{id}/tags/{tag}` | `contact:write` | Yes | — | A | 200/204 | IMPLEMENTATION-READY |
| 11 | POST | `/contacts/{id}/merge` | `contact:merge` | No | Yes | B | 200/409 | IMPLEMENTATION-READY (`crm.fn_merge_contacts()`, §10) |
| 12 | DELETE | `/contacts/{id}` | `contact:delete` | No | — | B | 204/404 | IMPLEMENTATION-READY |
| 13 | POST | `/contacts/{id}/suppress` | `suppression:manage` | Yes | Yes | A | 201/409 | IMPLEMENTATION-READY |
| 14 | GET | `/contacts/{id}/deals` | `deal:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 15 | GET | `/contacts/{id}/activities` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 16 | GET | `/contacts/{id}/tasks` | `contact:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 17 | GET | `/contacts/{id}/notes` | `contact:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 18 | GET | `/contacts/{id}/appointments` | `contact:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 19 | GET | `/contacts/{id}/score` | `contact:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 20 | GET | `/contacts/{id}/score-history` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 21 | GET | `/contacts/{id}/consent` | `consent:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 22 | GET | `/contacts/{id}/consent/history` | `consent:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 23 | POST | `/contacts/{id}/consent` | `consent:manage` | Yes | Yes | A | 201 | IMPLEMENTATION-READY |
| 24 | POST | `/companies` | `contact:write` | Yes | Yes | A | 201/409 | IMPLEMENTATION-READY |
| 25 | GET | `/companies` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 26 | GET | `/companies/{id}` | `contact:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 27 | PATCH | `/companies/{id}` | `contact:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 28 | POST | `/companies/{id}/owner` | `contact:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| — | DELETE | `/companies/{id}` | — | — | — | — | — | DEFERRED / NOT EXPOSED (DEP-6G-05) |
| 29 | POST | `/deals` | `deal:write` | Yes | Yes | A | 201 | IMPLEMENTATION-READY |
| 30 | GET | `/deals` | `deal:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 31 | GET | `/deals/{id}` | `deal:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 32 | PATCH | `/deals/{id}` | `deal:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 33 | POST | `/deals/{id}/stage` | `deal:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 34 | POST | `/deals/{id}/win` | `deal:close` | No | — | A | 200/409 | IMPLEMENTATION-READY |
| 35 | POST | `/deals/{id}/lose` | `deal:close` | No | — | A | 200/409 | IMPLEMENTATION-READY |
| 36 | POST | `/deals/{id}/abandon` | `deal:close` | No | — | A | 200/409 | IMPLEMENTATION-READY |
| 37 | POST | `/deals/{id}/owner` | `deal:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 38 | POST | `/pipelines` | `deal:write` | Yes | Yes | A | 201 | IMPLEMENTATION-READY |
| 39 | GET | `/pipelines` | `deal:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 40 | GET | `/pipelines/{id}` | `deal:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 41 | PATCH | `/pipelines/{id}` | `deal:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 42 | POST | `/pipelines/{id}/default` | `deal:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| — | DELETE | `/pipelines/{id}` | — | — | — | — | — | DEFERRED / NOT EXPOSED — no `DeletePipeline` command exists in 4C (§5 finding 7) |
| 43 | GET | `/pipelines/{id}/board` | `deal:read` | Yes | — | C | 200 | IMPLEMENTATION-READY |
| 44 | POST | `/activities` | `contact:write`/`deal:write` | Yes | — | A | 201 | IMPLEMENTATION-READY |
| 45 | GET | `/activities/{id}` | `contact:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 46 | GET | `/deals/{id}/activities` | `deal:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 47 | GET | `/companies/{id}/activities` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 48 | POST | `/tasks` | `contact:write` | Yes | — | A | 201 | IMPLEMENTATION-READY |
| 49 | GET | `/tasks` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 50 | GET | `/tasks/{id}` | `contact:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 51 | PATCH | `/tasks/{id}` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 52 | POST | `/tasks/{id}/complete` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 53 | POST | `/tasks/{id}/cancel` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 54 | GET | `/me/tasks` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 55 | POST | `/notes` | `contact:write`/`deal:write` | Yes | — | A | 201 | IMPLEMENTATION-READY |
| 56 | GET | `/notes/{id}` | `contact:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 57 | GET | `/deals/{id}/notes` | `deal:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 58 | GET | `/companies/{id}/notes` | `contact:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 59 | POST | `/notes/{id}/pin` | `contact:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 60 | POST | `/notes/{id}/unpin` | `contact:write` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 61 | DELETE | `/notes/{id}` | `contact:write` + author/role check (DEP-6G-02) | Yes | — | A | 204 | IMPLEMENTATION-READY |
| 62 | POST | `/appointments` | `contact:write` | Yes | Yes | A | 201 | IMPLEMENTATION-READY |
| 63 | GET | `/appointments` | `contact:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 64 | GET | `/appointments/{id}` | `contact:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 65 | POST | `/appointments/{id}/confirm` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 66 | POST | `/appointments/{id}/reschedule` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 67 | POST | `/appointments/{id}/cancel` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 68 | POST | `/appointments/{id}/complete` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 69 | POST | `/appointments/{id}/no-show` | `contact:write` | Yes | — | A | 200/409 | IMPLEMENTATION-READY |
| 70 | POST | `/crm-field-definitions` | `crm_field:manage` | No | — | A | 201/422 | IMPLEMENTATION-READY |
| 71 | GET | `/crm-field-definitions` | `contact:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 72 | PATCH | `/crm-field-definitions/{id}` | `crm_field:manage` | No | — | A | 200 | IMPLEMENTATION-READY |
| 73 | POST | `/crm-field-definitions/{id}/archive` | `crm_field:manage` | No | — | A | 200 | IMPLEMENTATION-READY |
| 74 | GET | `/suppressions/check` | `suppression:read` | Yes | — | A | 200 | IMPLEMENTATION-READY |
| 75 | POST | `/suppressions` | `suppression:manage` | Yes | Yes | A | 201/409 | IMPLEMENTATION-READY |
| 76 | GET | `/suppressions` | `suppression:read` | Yes | — | A/C | 200 | IMPLEMENTATION-READY |
| 77 | GET | `/suppressions/{id}` | `suppression:read` | Yes | — | A | 200/404 | IMPLEMENTATION-READY |
| 78 | POST | `/suppressions/{id}/lift` | `suppression:lift` | No | — | A | 200/409 | IMPLEMENTATION-READY |
| — | POST | `/contacts/{id}/score/recompute` | — | — | — | — | — | DEFERRED / NOT EXPOSED |
| — | POST | `/contacts/{id}/score/override` | — | — | — | — | — | DEFERRED / NOT EXPOSED (DEP-6G-04) |
| — | PLATFORM/REGULATORY suppression create/lift | — | — | — | — | — | DEFERRED TO 6M (DEP-6G-08) |

**Totals: 78 tenant-facing endpoints designed — all 78 IMPLEMENTATION-READY.**
- **IMPLEMENTATION-READY: 78**
- **CONTRACT-DEFINED BUT EXECUTION-BLOCKED: 0**
- **DEFERRED / NOT EXPOSED: 4** (Company delete, Pipeline delete, score recompute, score override) plus PLATFORM/REGULATORY suppression administration (DEFERRED TO 6M — a different, cross-phase category, not a same-document gap)

Revision 1 counted 79 endpoints (77 ready + 1 ready-at-reduced-scope + 1 execution-blocked, describing the same merge endpoint twice at two fidelity levels) plus 3 deferred. Revision 2's count is genuinely lower by one *designed* endpoint (Pipeline delete is removed from the inventory entirely, on DDD-command grounds — §5 finding 7) and the merge endpoint now counts once, fully ready — 78 total, all ready, 4 deferred/not-exposed within this document plus the separate PLATFORM/REGULATORY administration item.

---

## 33. Rate Limits / Latency

Per 6A §11/§20 — no CRM-specific tier deviates from the platform defaults. Standard CRUD (contacts/companies/deals/pipelines/tasks/notes/appointments/custom-fields/consent/suppression) is **Tier A**, default 300 req/min per org. List/history endpoints marked "A/C" in §32 may additionally be served from Tier C treatment (heavy filtering, `?fields=` sparse fieldsets) per 6A §10.2/§11 without needing a different permission or endpoint. `Bulk` suppression import (mentioned by the task brief's §21 CSV-adjacent language) is **not** designed here — 6H's CSV/campaign lead flow already calls CRM's `find_or_create_contact`; a bespoke CRM-side bulk-suppression-import endpoint is not source-grounded in 4C/5D and is not added.

---

## 34. PII / Data Exposure

| Field class | List DTO | Detail DTO | Notes |
|---|---|---|---|
| Name | Summary | Full | Erasure → `[ERASED]`, never leaked as if real |
| Primary/secondary phone | Summary (primary only) | Full | Erasure → `+99000000000` placeholder, flagged `redacted: true`, never presented as a dialable number |
| Email | — | Full | NULL on erasure |
| Address | — | Full | NULL on erasure |
| Company | Summary (`company_id` only) | Full | — |
| Notes body | — | Full (subject to permission on the parent) | AI-generated bodies flagged `note_source` so a client can render provenance |
| Activities | — | Full (subject to permission on the parent) | `payload.SMS`/`WHATSAPP` never carries full message content — only `{direction, message_preview_hash}` per 4C §4.5.2 |
| Merge marker Activity (`payload->>'event' = 'contact_merged'`) | — | Full (subject to permission on the parent) | **Identifiers/provenance only — `{event, primary_contact_id, secondary_contact_id, merged_by}`. Never the secondary Contact's name, phone, email, address, custom-field values, or qualification reason** (`097_5D5.sql`). This is structural, not a response-model filter: the payload never contains that data in the database row to begin with, so no serialization-layer redaction is doing the work — even a direct `SELECT` against `crm.activities` cannot recover PII this payload never held (§10.2–§10.4) |
| Appointment details | — | Full | Location detail (address/URL) only on detail view |
| Qualification reason | — | Full | Free text — may contain sensitive call-derived detail; never in summary |
| Consent evidence | — | Full (via `/consent`, `consent:read` gated) | `evidence` JSONB is not summarized elsewhere |
| Suppression reason/source | Summary (`reason` only, needed for UI badges) | Full | `source_ref` (e.g., raw call ID) never in list views |
| Custom fields | — | Full | Value-shape validated against field type before ever being stored or returned |

List endpoints universally use summary DTOs (6A §10.2). GDPR-erased/tombstone placeholder values are never rendered as if genuine (§8.4). Contact Merge does not create an undeletable copy of a Contact's name or phone number: the one immutable record a merge produces (the marker Activity above) is PII-minimal by construction, so `DELETE /contacts/{id}` remains fully effective on any Contact regardless of its merge history (§10.2, §22).

---

## 35. Observability

Bounded-cardinality metrics only — no `organization_id`, `contact_id`, `deal_id`, `appointment_id`, `phone`, or `email` label, per 6A §25/§26 and the platform-wide anti-pattern list (6A §36):

| Metric | Labels |
|---|---|
| `crm_contacts_created_total` | `source` |
| `crm_lead_conversions_total` | — |
| `crm_qualifications_total` | `status`, `set_by_type` |
| `crm_deals_created_total` | `pipeline_id`? **No** — pipeline count per org is small but still per-tenant-unbounded across the platform; use no label, or a bounded `pipeline_default` boolean if a dimension is needed |
| `crm_deals_terminal_total` | `outcome` (`WON\|LOST\|ABANDONED`) |
| `crm_appointments_booked_total` | `source` (`MANUAL\|AI_AGENT\|WORKFLOW`) |
| `crm_appointments_terminal_total` | `outcome` (`COMPLETED\|NO_SHOW\|CANCELLED`) |
| `crm_scoring_computations_total` | `scorer_type`, `score_version` |
| `crm_suppressions_created_total` | `scope`, `channel`, `reason` |
| `crm_suppressions_lifted_total` | `scope` |
| `crm_consent_records_total` | `purpose`, `channel`, `status` |
| `crm_merges_total` | — |
| `crm_operation_duration_seconds` | `operation`, `tier` (histogram, matches `platform_http_request_duration_seconds` convention, 6A §25) |

IDs/PII belong in redacted structured logs/traces (6A §25's PII-redacting processor), never in a Prometheus label.

---

## 36. Security / Abuse Review

| Threat | Mitigation |
|---|---|
| Cross-tenant contact lookup | RLS (`rls_contacts_tenant`) + 404-never-403 (6A §7.4) |
| Phone/email enumeration | 404 on not-found regardless of reason; negative caching (6A §19) blunts probing; `GET /contacts` never accepts an unauthenticated or under-scoped phone-exact-match without `contact:read` |
| CRM data scraping / mass export abuse | Cursor pagination caps page size at 100 (6A §14.3); no bulk unauthenticated export endpoint exists; heavy-read rate class (6A §20) applies to list/history endpoints |
| Unauthorized DNC lifting | `crm.lift_suppression()` SECURITY DEFINER validates ownership server-side regardless of what the API layer believes; `suppression:lift` required; PLATFORM/REGULATORY unreachable from tenant API at all (§21.2) |
| False consent evidence insertion | `consent:manage` required; append-only design means a false entry cannot erase a true prior one — it becomes visible alongside it in history, auditable |
| Fraudulent suppression removal | Same as DNC lifting above — no direct `UPDATE` path exists for any application role |
| AI note tampering | DB trigger (`trg_ai_note_immutable`) blocks body mutation regardless of API-layer bugs; no PATCH-body endpoint exists at all (§16) |
| Score manipulation | Manual override **not exposed** in this revision (§18.3, DEP-6G-04) — the highest-risk lever is simply not built until a dedicated permission exists |
| Unauthorized Deal closing | `deal:close` required, `OWNER`/`ADMIN` only, never AI-tool-reachable (§12.2) |
| Merge abuse / destroying identity history | `contact:merge` required (`OWNER`/`ADMIN` only); Activities/LeadScoreRecords are physically un-repointable (§10.2) — an unintended side effect of the same immutability that also protects against abuse: a malicious merge cannot rewrite history, only fork it |
| GDPR erase abuse | `contact:delete` (or `data_subject:manage` for DSR-triggered) required; erasure is a fixed field-list, not an arbitrary patch — cannot be used to smuggle other field changes |
| GDPR erasure defeated by a prior merge (undeletable PII copy) | `crm.fn_merge_contacts()`'s marker Activity is structurally PII-minimal (`{event, primary_contact_id, secondary_contact_id, merged_by}` only, `097_5D5.sql`) — no Contact name/phone/email/address/custom-field value is ever written into it, so no merge, past or future, can leave a durable copy of a Contact's PII that `DELETE /contacts/{id}` cannot subsequently clear. Live-validated: GDPR erasure of an already-merged Contact succeeds, and the marker payload (already PII-free) is unaffected by it (§10.4) |
| Custom field injection / mass assignment | Pydantic strict schemas (`extra="forbid"`, 6A §22); `field_id` always tenant-verified before any value is accepted; type-shape validated |
| Phone-normalization bypass | API re-validates E.164 format server-side on every phone-accepting field, never trusts a client's "already normalized" claim (6A §7.5) |
| Reused deleted-contact identifiers | A soft-deleted Contact's `id` remains stable and never reassigned (UUIDv7, never reused) — only its *phone number* becomes available for a *different* new Contact row |
| Webhook/plugin-derived untrusted CRM data | Out of 6G's scope (6J owns connector data ingestion) — but this document's own filter/sort fields are 100% allow-listed (§8.3, §15 base pattern), and no endpoint accepts a plugin-supplied string as a SQL fragment anywhere in this design |

---

## 37. Test Strategy

Per 6A §33's categories, applied to CRM:

- **Contract tests:** every endpoint in §32 against its OpenAPI-derived schema.
- **Authorization tests:** the full matrix in §28, plus explicit cross-tenant probes (read another org's Contact/Deal/Suppression/Consent by ID manipulation) — extends 5B §38's Tenant Isolation Test Matrix up through this API, and specifically re-runs the suppression-specific matrix at §21.6 through the REST layer, not just the DB layer.
- **Functional / state-machine tests:** every guard in §9.2 (lead-status), §12.2 (deal), §17.2 (appointment) — both the legal-transition and illegal-transition paths.
- **Concurrency tests:** every scenario in §27, especially #1 (duplicate-phone race), #16 (duplicate-suppression race — already live-validated at the DB layer per 5L §26, re-run through the API to confirm correct HTTP-layer translation), and #4 (concurrent merge).
- **Security tests:** the abuse scenarios in §36, especially AI-note-tamper attempts and unauthorized-lift attempts.
- **Performance tests:** Tier A/C targets (6A §11) for list/history endpoints, especially `GET /contacts/{id}/activities` against a partitioned, high-volume `activities` table.

---

## 38. Traceability

| Requirement | Coverage | Notes |
|---|---|---|
| FR-CRM-001 (Contacts/Companies/Deals/Tasks/Activities/Notes/Appointments/Pipelines) | **Fully covered** | §8–§17 |
| FR-CRM-002 (configurable/model-based lead scores) | **Fully covered** (read + async trigger); manual override deferred | §18, DEP-6G-04 |
| FR-CRM-003 (full call history per Contact) | **Fully covered** | §14, via Activity projection, no Voice data duplication |
| FR-CRM-004 (external CRM sync via Plugin SDK) | **Partially covered — contract only** | §25, DEFERRED TO 6J (DEP-6G-12) |
| FR-VOICE-006 (call summary/sentiment/lead score) | **Fully covered on the CRM-consuming side** | §23; the scores/sentiment themselves originate in 6D, consumed here |
| FR-VOICE-008 (post-call outcomes into CRM) | **Fully covered** | §23 |
| FR-EVT-001 (`lead.created`, `lead.qualified`, `appointment.booked`) | **Fully covered** (with naming reconciliation) | §30 |
| FR-TEN-001..005 (multi-tenancy) | **Fully covered** | RLS throughout, §21.6/§27/§36 |
| NFR-SEC-001..008 | **Fully covered** | §22, §28, §36 |
| NFR-COMPLY-001 (recording/retention/consent config) | **Partially covered** | §20 (consent), §22.2 (retention owned elsewhere) |

---

## 39. Dependency Register

| ID | Issue | Source | Owner / Resolution | Status | Affected endpoint(s) |
|---|---|---|---|---|---|
| DEP-6G-01 | Full 4C merge fidelity requires re-pointing `crm.activities`/`crm.lead_score_records`, but `REVOKE UPDATE` on both makes this physically impossible for any application role | 4C §6.2 vs. `022_5D.sql`/`023_5D.sql` | Resolved by reconciling the domain rule (application-layer lineage read, §10.5), not by widening the privilege: `crm.fn_merge_contacts()`, `093_5D2.sql` (marker-Activity payload subsequently hardened to be PII-minimal by `097_5D5.sql` — see DEP-6G-18) | **RESOLVED** | `POST /contacts/{id}/merge` |
| DEP-6G-18 | *(Revision 3.)* `crm.fn_merge_contacts()`'s marker Activity copied the secondary Contact's `full_name`/`phone_e164` into an immutable, GDPR-erasure-exempt payload — an erasure-boundary defect | 4C §6.2 note in §6.2's Physical Implementation Note vs. `022_5D.sql`'s `REVOKE UPDATE, DELETE` on `crm.activities` (erasure never touches this table) | Resolved: `097_5D5.sql`, `CREATE OR REPLACE FUNCTION crm.fn_merge_contacts(...)` — payload now `{event, primary_contact_id, secondary_contact_id, merged_by}` only | **RESOLVED** | `POST /contacts/{id}/merge` |
| DEP-6G-02 | 4C policies reference `contact:qualify`, `contact:score_override`, `contact:force_convert`, `crm:admin` — none exist in 5B | 4C §8 vs. 5B §17 | Classified per-item (§5 finding 3): `contact:qualify` → Classification A (served by `contact:write`); `contact:force_convert`/`contact:score_override` → Classification C (not exposed); `crm:admin` → Classification A (OWNER/ADMIN role check already at least as strict) | **NON-BLOCKING, closed by classification** — no new permission needed | Qualify, force-convert bypass, manual score override, non-author note delete |
| DEP-6G-03 | No dedicated 5B permission scope for Company/Pipeline/Task/Note/Appointment | 5B §17 | Reviewed and found not to cross the bar for a new permission — none carries CRM Custom Field's tenant-wide schema-impact concern | **NON-BLOCKING, closed by classification** | §11, §13, §15–§17 |
| DEP-6G-04 | Manual lead-score override has no safe permission to gate on | 4C §16.2, 5B §17 | Not exposed in this revision; a future 5B amendment adding `contact:score_override` (OWNER/ADMIN only) would be the correct unblock | **NON-BLOCKING** (endpoint simply not exposed) | Score override (not exposed) |
| DEP-6G-05 | `contacts.company_id` has no FK; Company delete cannot be safely guaranteed | 5D §12/§13 | Not exposed; a future 5B/5D FK amendment would be the correct unblock if delete is ever required | **NON-BLOCKING** (delete simply not exposed) | Company delete (not exposed) |
| DEP-6G-06 | New CRM `action_kind` values needed; 5J's CHECK is length-only, not yet formally governed | 5J §14.3 | Resolved: `5J-Analytics-Audit-Schema.md` §14.3 ¶ amendment sanctions 29 new values, documentation-only, zero SQL | **RESOLVED** | All CRM mutation endpoints |
| DEP-6G-07 | Deal currency-must-match-org-base-currency invariant's backing field not located in Revision 1 | 4C §4.3 inv.5 | Resolved: `organization.organizations.currency` (`003_5B.sql`) was already present; wired at the application layer, §12.2 | **RESOLVED** | `POST /deals`, `PATCH /deals/{id}` |
| DEP-6G-08 | PLATFORM/REGULATORY suppression administration is `app_platform_admin`-only; no tenant surface | 5D §11.3 | Admin Control Plane | **DEFERRED TO 6M** | Suppression create/lift (PLATFORM/REGULATORY only) |
| DEP-6G-09 | Suppression active-uniqueness race — already resolved by `085_5D1.sql` | 5D §16.6, 5L §26 | None — closed | **RESOLVED** | `POST /suppressions` |
| DEP-6G-10 | Custom-field-definition administration has tenant-wide schema impact but was gated on a MEMBER-eligible permission | 5B §17 | Resolved: `crm_field:manage` (OWNER/ADMIN only), `096_5B2.sql` | **RESOLVED** | §19 |
| DEP-6G-11 | 6H must use the effective-suppression/consent contract, never `contacts.do_not_call`, and must call it in-process, not over HTTP | 4C §20, 5D §19.2 | 6H must implement against the `EffectiveSuppressionService`/effective-consent application services (§21.7/§24) | **DEFERRED TO 6H** (contract, including its in-process shape, is RESOLVED here) | 6H's dispatch logic |
| DEP-6G-12 | External CRM sync (Salesforce/HubSpot/Zoho, OAuth, connector schedules) not designed | FR-CRM-004, 3C §5.7 | 6J | **DEFERRED TO 6J** | `CrmSyncPort` implementation |
| DEP-6G-13 | Voice-side call outcome fields (sentiment, transcript_ref, recording_ref) used in Activity payload originate in Voice's own schema; 6G projects them but does not re-validate Voice internals | 4C §4.5.2, 5D §13 | Cross-reference to 6D | **NON-BLOCKING** | Activity `CALL` payload |
| DEP-6G-14 | `contact.converted` consumption by Billing (if conversion is billable) not designed here | 4C §20 | 6K | **DEFERRED TO 6K** | — (event emission only, consumption is 6K's) |
| DEP-6G-15 | Analytics projection of the full CRM event catalogue | 4C §20 | 6L | **DEFERRED TO 6L** (informational handoff, contract fully specified at §30) | — |
| DEP-6G-16 | Workflow Engine node executors (`bookAppointment`, `createTask`, `createNote`) must call this document's public application services, not reimplement | 4C §26 requirement 5 | 6I | **DEFERRED TO 6I** (contract itself RESOLVED here, mirrors §23) | — |

**Zero BLOCKING items remain.** DEP-6G-01, DEP-6G-06, DEP-6G-07, DEP-6G-10, and DEP-6G-18 — the five items closed across Revisions 2–3 — are all **RESOLVED**, live-validated, and reflected consistently throughout this document (§10, §12.2, §19, §29.2, §34, §36). DEP-6G-02/03/04/05 are closed by explicit classification (not every terminology gap warrants a new permission — §5 findings 3–4) or remain honestly NON-BLOCKING because the gated capability is simply not exposed. DEP-6G-08/09/11–16 are cross-phase handoffs or already-closed items, not gaps in this document. (DEP-6G-17 was never assigned a permanent register entry — §40 retired it as a non-issue the moment the underlying DDD fact was found, rather than carrying forward a "grant gap" framing that was never the real story.)

---

## 40. High-Risk Contradiction Check

Per-endpoint physical verification table for every write endpoint (representative sample covering every distinct grant/trigger/constraint pattern found; the full inventory in §32 follows the same method):

| Endpoint | DDD command | Physical table/function | Grant | RLS | Constraint/trigger | Execution status | Gap |
|---|---|---|---|---|---|---|---|
| `POST /contacts` | `CreateContact` | `crm.contacts` INSERT | `INSERT` ✅ (`020_5D.sql`) | `rls_contacts_tenant` (FOR ALL) | `uq_contacts_phone` partial unique | Executes as designed | None |
| `DELETE /contacts/{id}` | GDPR erasure (Phase 4I, not a 4C command per se) | `crm.contacts` UPDATE | `UPDATE` ✅ | Same | Fixed field-list, no CHECK conflict (`+99...` placeholder satisfies `chk_contacts_phone`); does not conflict with an already-merged Contact (`trg_contacts_merge_immutable` fires only on `merged_into_contact_id`/`merged_at`, live-verified) | Executes as designed | None |
| `POST /contacts/{id}/merge` | `MergeContacts` | `crm.fn_merge_contacts()` — internally: `crm.deals`/`tasks`/`notes`/`appointments` UPDATE (repointed); `crm.contacts` UPDATE (both rows); `crm.activities` INSERT (marker only) | Function `EXECUTE` ✅ (`app_api`, `app_worker`, `app_platform_admin`, `093_5D2.sql`); every table-level grant the function's body uses already existed pre-amendment | `SECURITY DEFINER` — owning role's BYPASSRLS means every statement inside filters explicitly by `organization_id = p_organization_id`, verified live (cross-tenant secondary resolves to not-found) | `chk_contacts_merge_pair`, `chk_contacts_no_self_merge`, `fk_contacts_merged_into`, `trg_contacts_merge_tenant_guard`, `trg_contacts_merge_immutable` — all five live-verified | Executes as designed | None — `crm.activities`/`lead_score_records` are correctly left un-repointed by design (§10.2), not a gap |
| `POST /deals/{id}/win` | `WinDeal` | `crm.deals` UPDATE | `UPDATE` ✅ (`021_5D.sql`) | `rls_deals_tenant` | `chk_deals_status`; app-layer `TerminalDealIsImmutable` guard (no DB trigger) | Executes as designed | None (guard is app-layer by design, consistent with `lead_temperature`'s documented pattern) |
| `POST /pipelines` / `PATCH /pipelines/{id}` | `CreatePipeline`/stage commands | `crm.pipelines` INSERT/UPDATE | `SELECT, INSERT, UPDATE` ✅ (`021_5D.sql`) | `rls_pipelines_tenant` | Stage-cap/uniqueness checks app-layer | Executes as designed | None. (Note: `021_5D.sql` grants **no `DELETE`** on `crm.pipelines` to `app_api`/`app_worker` at all — moot for this document, since no `DeletePipeline` command exists in 4C to begin with, §5 finding 7; not listed as a gap because nothing here claims delete is exposed) |
| `POST /notes/{id}/pin` | `PinNote` | `crm.notes` UPDATE (`pinned_at`) | `UPDATE` ✅ (`022_5D.sql`, full grant incl. DELETE) | `rls_notes_tenant` | `trg_ai_note_immutable` only fires on `body` change, not `pinned_at` | Executes as designed | None |
| `POST /suppressions/{id}/lift` | Suppression lift (Phase 4I) | `crm.lift_suppression()` | `EXECUTE` ✅ (`024_5D.sql`) | N/A (function is `SECURITY DEFINER`) | Internal status/ownership checks inside the function | Executes as designed | None |
| `POST /contacts/{id}/consent` | Consent append (Phase 4I) | `crm.consent_records` INSERT | `INSERT` ✅ (`024_5D.sql`) | `rls_consent_insert` | Partition routing via `recorded_at` | Executes as designed | None |
| Activity/Note event-subscriber writes | `RecordActivity`/`AddNote(AI_SUMMARY)` via Voice event | `crm.fn_claim_event()` + `crm.activities`/`crm.notes` INSERT | Function `EXECUTE` ✅ (`app_worker`, `app_platform_admin` only — never `app_api`, `094_5D3.sql`) | `rls_event_consumer_dedup_tenant` (FOR ALL) on the dedup table; standard RLS on the target table | `pk_event_consumer_dedup` composite PK is the atomicity guarantee | Executes as designed, live-validated (two-connection race) | None |
| Lead-score apply | (async worker, no direct REST command) | `crm.fn_apply_lead_score()` | Function `EXECUTE` ✅ (`app_worker`, `app_platform_admin` only, `095_5D4.sql`) | N/A (SECURITY DEFINER; explicit `organization_id` filtering inside) | Contact-row `FOR UPDATE` lock + `(computed_at, id)` recency check | Executes as designed, live-validated (two-connection race, correct winner) | None |

**This revision's own mid-review correction (carried forward from Revision 1, now closed):** Revision 1 found that `021_5D.sql` grants no `DELETE` on `crm.pipelines` to any application role, and initially treated this as a gap requiring a grants amendment (DEP-6G-17). Re-review during this reconciliation found the deeper, prior fact: **4C's own Pipeline command catalogue never defines a `DeletePipeline` command at all** (§5 finding 7) — the missing grant was never something to unblock, because nothing in the DDD calls for Pipeline deletion to be exposed in the first place. DEP-6G-17 is retired as a non-issue, not carried forward as a permanent NON-BLOCKING entry in §39 — §13/§32 reflect Pipeline deletion as DEFERRED / NOT EXPOSED on DDD grounds.

---

## 41. Architecture Decision Records

| ID | Decision | Rationale | Status |
|---|---|---|---|
| ADR-6G-01 | Lead = Contact at the API layer; no `/leads` resource | Extends DDR-4C-001/ADR-5D-001 to the API surface — lead-oriented views are `GET /contacts` filters only | **Decided** |
| ADR-6G-02 | `lead_status`/`qualification_status`/`lead_score`/`lead_temperature`/`converted_at` are never `PATCH`-writable; only guarded action endpoints move them | Extends DDR-4C-004 and 6A §8.3's guarded-transition rule | **Decided** |
| ADR-6G-03 | Pipeline stages remain embedded JSONB with no independent stage resource; stage mutation is a whole-aggregate `PATCH` | Extends ADR-5D-004 | **Decided** |
| ADR-6G-04 | Contact Merge is represented by dedicated `merged_into_contact_id`/`merged_at` columns, never `deleted_at`; mutable child aggregates (Deals/Tasks/Notes/Appointments) are physically repointed via `crm.fn_merge_contacts()`; Activities/LeadScoreRecords remain physically attached to their original Contact id, with lineage followed at the read layer instead of rewritten at the write layer | §10; alternatives rejected: reusing `deleted_at` (conflates merge with GDPR erasure, semantically wrong); widening `REVOKE UPDATE` on append-only tables (violates immutability invariants the same schema enforces elsewhere) | **Decided**, live-validated |
| ADR-6G-14 | 6H's dispatch-time suppression/consent checks are in-process application-service calls (`EffectiveSuppressionService.check()` and its consent equivalent), never a REST round-trip to 6G's own public endpoint | §21.7, §24; alternative (6H calls `GET /api/v1/suppressions/check` over HTTP per outbound call) rejected as unnecessary internal network overhead on a per-call dispatch path, inconsistent with 6A §6's general preference against needless internal HTTP hops | **Decided** |
| ADR-6G-15 | CRM event-consumer idempotency uses a dedicated, CRM-owned durable ledger (`crm.event_consumer_dedup` + `crm.fn_claim_event()`), not a `SELECT`-then-`INSERT` pre-check and not a reuse of `analytics.analytics_event_dedup` | §14.4, §23; alternative (reuse Analytics' dedup table) rejected per the governing reconciliation's explicit instruction to prefer CRM-owned persistence absent an architectural mandate for cross-context writes into Analytics | **Decided**, live-validated |
| ADR-6G-16 | Lead-score denormalized apply uses a Contact-row lock plus a `(computed_at, id)` recency check (`crm.fn_apply_lead_score()`), with no new schema column | §18.1a, §27 #20; alternative (add a `lead_score_computed_at` column to `contacts` for an explicit CAS field) rejected as unnecessary — the existing append-only `lead_score_records` history already carries everything the recency check needs | **Decided**, live-validated |
| ADR-6G-17 | The merge marker Activity's payload is structurally PII-minimal — identifiers and provenance only (`event`, `primary_contact_id`, `secondary_contact_id`, `merged_by`) — never the secondary Contact's name, phone, email, address, custom-field values, or qualification reason (`097_5D5.sql`) | §10.2–§10.4, §34, §36; alternative (copy secondary's identifying fields into the payload for a self-contained audit record, as Revision 2 originally did) rejected once an independent review identified it as a genuine GDPR-erasure-boundary defect — `crm.activities` is append-only and outside erasure's reach, so any Contact PII written there becomes permanently unerasable | **Decided**, live-validated |
| ADR-6G-05 | Activities remain append-only with zero exceptions, including for merge re-pointing | DDR-4C-002 confirmed to hold even under merge pressure — immutability wins over convenience | **Decided** |
| ADR-6G-06 | AI-note immutability extends to "no body-edit endpoint at all," not just "AI notes specifically blocked" | §16 finding — 4C defines no edit command for any note | **Decided** |
| ADR-6G-07 | Lead scoring exposes read + async-trigger surfaces only; no synchronous recompute, no manual override until a permission exists | DDR-4C-006, DEP-6G-04 | **Decided** |
| ADR-6G-08 | Consent API is strictly append-only; withdrawal is a new record | Phase 4I §8.1 | **Decided** |
| ADR-6G-09 | `contact_suppressions` remains the sole DNC enforcement source; `contacts.do_not_call` is never read by any endpoint's enforcement logic | ADR-5D-003 extended to the API layer | **Decided** |
| ADR-6G-10 | Voice→CRM and Workflow→CRM handoffs are in-process application-service calls / event subscriptions — never a new internal HTTP endpoint | 6A §6, 4H §9.1 | **Decided** |
| ADR-6G-11 | 6H→6G eligibility contract is `GET /suppressions/check` + `GET /contacts/{id}/consent` composition; no bespoke `/campaign-eligibility` endpoint | §24 | **Decided** |
| ADR-6G-12 | 6G→6J boundary is canonical entity shape + outbox events + `CrmSyncPort` contract only; no connector/OAuth/schedule endpoints | §25 | **Decided** |
| ADR-6G-13 | GDPR Contact erasure is PII-clearing via a fixed field-list `UPDATE`, never a hard delete, never a generic patch | ADR-5D-007 extended to the API layer | **Decided** |

---

## 42. OpenAPI / Implementation Readiness

Per 6A §32: every endpoint in §32's inventory carries `x-latency-tier`, `x-idempotent`, `x-permission-required`, `x-audit-action-kind` (all 29 CRM-specific values are now governed, §29.2 — no `"proposed"`-tagged vendor extension is needed for any of them), and `x-rate-limit-class: "standard-crud"` vendor extensions, generated from the FastAPI route decorators — no separately hand-maintained OpenAPI file (ADR-6A-06, reused without modification).

**Readiness is internally consistent with physical reality per §40's verification.** All 78 designed endpoints are IMPLEMENTATION-READY; nothing in §32's final counts overstates what the executed grants and functions actually allow.

---

## 43. Final Closure / Freeze Recommendation

### 43.1 Freeze Gate Checklist (against §41 of the governing task)

| # | Criterion | Status |
|---|---|---|
| 1 | Lead modeled only as Contact | ✅ |
| 2 | No campaign endpoints leaked | ✅ |
| 3 | No external CRM connector endpoints leaked | ✅ |
| 4 | Every public resource maps to 4C and 5D | ✅ |
| 5 | Every mutation has a legal physical write path | ✅ — including Contact Merge, now via `crm.fn_merge_contacts()` (§10); Pipeline deletion has no mutation to check since it is not exposed (§13) |
| 6 | Contact phone uniqueness/concurrency correct | ✅ |
| 7 | GDPR erasure behavior safe | ✅ |
| 8 | Suppression survives Contact lifecycle | ✅ |
| 9 | `do_not_call` not authoritative | ✅ |
| 10 | Suppression uniqueness uses `085_5D1` | ✅ |
| 11 | Suppression lift uses `crm.lift_suppression()` | ✅ |
| 12 | PLATFORM/REGULATORY suppression not tenant-mutable | ✅ |
| 13 | Consent append-only | ✅ |
| 14 | Activities append-only | ✅ |
| 15 | AI note body immutable | ✅ (and human note body immutable too, by DDD-command absence) |
| 16 | Lead temperature never directly settable | ✅ |
| 17 | Scoring remains asynchronous | ✅ |
| 18 | Deal terminal transitions guarded | ✅ |
| 19 | Pipeline stages not independent CRUD | ✅ |
| 20 | Appointment transitions guarded | ✅ |
| 21 | Call history satisfies FR-CRM-003 without duplicating Voice data | ✅ |
| 22 | Voice→CRM handoff explicit | ✅ |
| 23 | 6H suppression/eligibility handoff explicit | ✅ |
| 24 | 6J external CRM sync handoff explicit | ✅ |
| 25 | Permission names come only from 5B | ✅ |
| 26 | API-key eligibility explicit | ✅ |
| 27 | Audit write path is `audit.fn_insert_audit_event()` | ✅ |
| 28 | Domain events use existing outbox | ✅ |
| 29 | No high-cardinality metrics | ✅ |
| 30 | PII exposure reviewed | ✅ |
| 31 | Cross-tenant behavior non-disclosing | ✅ |
| 32 | OpenAPI readiness consistent with physical reality | ✅ |
| 33 | Dependency register has zero *hidden* blockers | ✅ — zero BLOCKING items of any kind remain (§39) |
| 34 | Endpoint inventory count internally consistent | ✅ (§32: 78 total, all IMPLEMENTATION-READY, 4 deferred/not-exposed within-document + PLATFORM/REGULATORY admin deferred to 6M) |
| 35 | No previously frozen Phase 5 migration was modified; required reconciliation changes were implemented only as additive controlled forward migrations | ✅ — no row 001–092 was ever edited; five controlled forward migrations (`093_5D2.sql`–`097_5D5.sql`) were added across Revisions 2–3, all additive, all live-validated, following the exact controlled-amendment discipline already established by `085_5D1`/`077_5J1`/`087_5B1`. This is not "Phase 5 untouched" — Phase 5's physical schema genuinely grew by five migrations; what did not happen is any edit to a previously-frozen, checksummed migration file |
| 36 | 6A–6F untouched | ✅ |
| 37 | 6H not started | ✅ |

### 43.2 Recommendation

Revision 1 identified one genuine BLOCKING item (DEP-6G-01) and three NON-BLOCKING gaps that an independent reconciliation review determined were worth closing rather than carrying forward (DEP-6G-06, DEP-6G-07, DEP-6G-10). All four were resolved in Revision 2, each via the smallest correct fix: a physical-schema amendment reconciling a domain rule with an immutability invariant (merge), a documentation-only governance amendment (audit vocabulary), locating an already-existing field (currency), and one narrowly-scoped new permission (custom fields). Two further defects were found and fixed *during* Revision 2's own work, before either was ever left in a broken state: a `search_path` omission reproducing a previously-documented class of bug, and an accepted-as-risk lead-score race that is now genuinely resolved rather than merely documented. A subsequent independent whole-project review then found one further real defect in Revision 2's own fix: the merge marker Activity copied the secondary Contact's name and phone into an immutable, GDPR-erasure-exempt payload. **Revision 3** resolves this with `097_5D5.sql` — the marker payload is now structurally PII-minimal (identifiers and provenance only), leaving `093_5D2.sql` itself untouched. Every fix across all three revisions was live-validated against a real, disposable PostgreSQL 18 database, including genuine multi-connection concurrency races — not asserted from design reasoning alone. No privilege was widened on any append-only table; Activities, LeadScoreRecords, and consent records remain exactly as immutable as Revision 1 left them; suppression enforcement remains exactly as authoritative; GDPR erasure remains fully effective on any Contact regardless of merge history. 6A–6F remain untouched; 6H was not started.

**PHASE 6G — APPROVED / FROZEN CANDIDATE**

The independent reviewer makes the final freeze determination.
