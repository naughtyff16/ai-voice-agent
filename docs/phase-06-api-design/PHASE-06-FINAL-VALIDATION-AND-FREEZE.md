# Phase 6 — Final Validation and Freeze-Candidate Certificate

## 1. Document Control

| Field | Value |
|---|---|
| Document | `docs/phase-06-api-design/PHASE-06-FINAL-VALIDATION-AND-FREEZE.md` |
| Phase | 6 — API Design (roadmap `docs/product/PROJECT_ROADMAP.md`) |
| Type | Final independent validation of the Phase-6 corpus; freeze-candidate certificate |
| Validation date | 2026-09-26 |
| Revalidation | 2026-09-26 — FV-P1-01 remediation: owner-approved controlled AIR factual erratum applied; every gate re-run independently on the corrected corpus (§4, §5, §11, §34–§39) |
| Evidence basis | Filesystem contents only. Version-control metadata is not used as evidence and no version-control command is a gate |
| Authority | Subordinate to every artifact it validates (§3). It amends nothing, creates no route, error code, permission, table, migration or event |
| Freeze authority | None. This certificate does **not** freeze or close Phase 6; only the owner can do that after independent freeze review |
| Phase 7 | Not started. This document designs no event architecture |
| Result | See the final line of this document and §38 |

## 2. Purpose and Scope

This certificate re-derives, from the files on disk, whether the Phase-6 API corpus is coherent, compatible with the frozen Phase-5 database, complete for authorization, errors and versioning, implementation-ready, free of P0/P1 defects and safe to hand to Phase 7 (Event Architecture, roadmap L39).

In scope: the 19 Phase-6 documents (6A–6M, AAM, AEC, AIR, AMI, AVS, FAR); the Phase-5 database design (5A–5J, 5L) and the 5K migration set (112 SQL files and 112 Alembic wrappers); the SRS (phase 1), HLA (phase 2), LLD 3A–3F, DDD 4A–4I and the roadmap as upstream trace sources.

Out of scope: application code (none exists — AIR §5 L108), runtime measurement, Phase 7 design, and any edit to an existing artifact other than the single owner-approved controlled AIR factual erratum that resolves FV-P1-01 (§5, §37). Every check in this certificate was recomputed by a scratch validator that lives outside the project tree; AIR's own "READY" verdict was not accepted as evidence of anything it asserts.

## 3. Authority Hierarchy

Used as stated in AIR §3 (L30–L60). A lower rank never overrides a higher one; where they disagree, the higher rank is the truth and the lower rank carries the defect.

| Rank | Authority | Anchor used by this validation |
|---|---|---|
| 1 | Roadmap | `PROJECT_ROADMAP.md` L145 "Implementation begins only after architecture approval." |
| 2 | Owner documents 6A–6M | route definitions, contracts, events, per-domain rules |
| 3 | Phase-5 DB design + 5K migrations | 112 SQL / 112 revisions, root `001_5B`, head `112_5H5` |
| 4 | FAR | §9 L352 ledger, §11 L971 |
| 5 | AMI | route rows L117–L520; WS rows L551–L554 |
| 6 | AAM | §13 L682; WS §14 L1060 |
| 7 | AEC | §5 registry L101–L239 ("Active codes: 132", L238); §15 L873; WS §16 L1251 |
| 8 | AVS | axes L319–L341; §38 L1605 |
| 9 | AIR | subordinate readiness register |

AIR §3.1: the seven owner-approved decisions resolve only their stated scope; "No owner decision overrides any source document as a whole." This certificate applies the same limit (§30).

## 4. Validation Snapshot

| Item | Value |
|---|---|
| Project root | `/home/crm-lp-1/karthi/Chunk_Mates/ai-voice-agent` |
| Snapshot method | SHA-256 of every regular file under the project root, excluding the version-control directory |
| Files in pre-snapshot | 733 |
| Files at remediation start (FV-P1-01) | 734 (733 + this certificate) |
| Phase-6 documents before this certificate | 19 |
| Phase-6 documents after this certificate | 20 |
| Application code | not present (AIR §5 L108 confirmed by inspection) |
| Scratch validators | 17, all outside the project tree: `migr`, `routes`, `owner`, `reverse`, `surfaces`, `aec`, `avs`, `air`, `air18`, `far`, `airreg`, `claims`, `hashreg`, `sem`, `frozen`, `aeccount`, `cert` |
| Real-corpus result (after the FV-P1-01 erratum) | 17/17 PASS: 15 original validators; `aeccount` PASS (AEC §5 rows 132, unique 132, declared 132; AIR §16 L959 = 132); `cert` PASS (structure, consistency and current AIR identity of this file) |

Disclosure — scratch recovery: during this validation the session scratch directory was lost once. The validators were recreated byte-for-byte from the session record, the full-project hash snapshot was re-captured **before** any write to the project, and every validator was re-run on the real corpus. The frozen hashes in §5 were matched against AIR §6 (an independent, in-corpus register), so the recovery does not weaken the frozen-artifact evidence.

## 5. Frozen Artifact Hash Register

Computed SHA-256 and newline counts. Every non-AIR value equals the AIR §6 registry row (`hashreg` PASS; AIR does not register itself) and, for the closure artifacts, the independently pinned values (`frozen` PASS). The AIR row is the current AIR after the controlled erratum.

| Artifact | SHA-256 | Lines | Result |
|---|---|---|---|
| 6A | `a13e295f8041627751bf0648d4c2b37aa665a096bb79ab758243b1bac69971ab` | 1140 | MATCH |
| 6B | `f8b43a258fee15824fcc6323ac0bcd612ca1cfa4d9278095fc899b776bac6cfe` | 2783 | MATCH |
| 6C | `269b5978a72d5526d2a6ce5a332b6bbf2ba87b6d584a8e8d4b11c1836e26813c` | 1338 | MATCH |
| 6D | `0971c372de32bd58f01521a3f493b7458b5fd103c9ac28f5a6ff95cd5dfafd42` | 2157 | MATCH |
| 6E | `6c9b500ac2afac65cf8b5c9f237170a72f29d4c468c4991f169c5f52145241bf` | 1785 | MATCH |
| 6F | `8a38ce1f4f3def3b819c0bb3588d66f24d2be2757a5a2f3811a9d3a6a0d7a7f2` | 1457 | MATCH |
| 6G | `907ca4165290932bc631c0d416bbe3b477a4bad0df8f1c22853ffc5189e56211` | 1386 | MATCH |
| 6H | `9639498818c48e1a6b9ecbf34312cf94e509929a89fb111f5b4320b695e28c18` | 2832 | MATCH |
| 6I | `00023a92b86230849fa6ff3ba076350a6e94037feba049ed377603bfdd792dbe` | 1762 | MATCH |
| 6J | `adebb15b6f132816b2adfef5d3b62c93de18f31fbbd5885cafd05fc3640782a9` | 2690 | MATCH |
| 6K | `db4df2883cdeafb41035176a5c8a5199088044ea00626a52e036fd862fa0d675` | 3936 | MATCH |
| 6L | `b268460c4fc954ce2d833415f058201afec7f8c74420d1d9ac7804d6c6ce96e9` | 1388 | MATCH |
| 6M | `88684f96527fd7ceb14ab88ac5fcc5458d531f993625ddf1b7140ac7ad7dd0f8` | 1136 | MATCH |
| AAM | `f61d2d742a3193803c36cf7b9b9f78ce974da35fac94c61ce238b334dfd94843` | 1732 | MATCH |
| AEC | `2505acda65a07d98247bb2cbd5d3e28421bbf6cc75f7cfd0fff1ba07d7f65c7a` | 1404 | MATCH |
| AIR | `81dd63dc3160b1eb642ab524b5159794fdc1f0aec74602987b45eb97097a54e2` | 2484 | MATCH |
| AMI | `cb033a2f334aee1563d05e6db535b9d1a17038cf163ff4ea6925313cf9756c38` | 845 | MATCH |
| AVS | `ad3341ce73e5459783e7a00ff8ecb2cf04e1e8a93112ab2565bdbd6813ab222f` | 1741 | MATCH |
| FAR | `5853982e7209d84f097405c6ad149f180013d6351645db3aaa7297553addbc3f` | 2552 | MATCH |
| Roadmap | `23df5f236b7c9bc3da56c5336b3297471f2a30fe01b8a6e9a748fca54533254e` | 145 | MATCH |

AIR differs from the previously approved AIR (superseded, historical only: SHA-256 c5492a86eb122f9ba90cff54ecfb85dce2eece513913c1e2e52242086d1fe9dc, 2483 lines) solely by the owner-approved controlled factual erratum FV-P1-01: §1 Date row (L10), §16 AEC row (L959), §37 remediated count (L2367) and §37.1 FV-P1-01 row (L2416); +1 line. The other 19 hashes above are unchanged, including AEC (the erratum direction is AIR → AEC; AEC was not edited).

## 6. Phase-6 Source Inventory

| Group | Documents | Count |
|---|---|---|
| Owner documents | 6A API Architecture & Standards; 6B Authentication & Authorization; 6C Core Platform; 6D Voice/Call/Agent; 6E AI Agent; 6F Knowledge/RAG; 6G CRM/Leads; 6H Campaign; 6I Workflow; 6J Integrations/Webhooks/Plugins; 6K Billing/Usage; 6L Analytics/Audit; 6M Admin/Platform | 13 |
| Cross-cutting registers | AMI, AAM, AEC, AVS | 4 |
| Reconciliation / readiness | FAR, AIR | 2 |
| Total before this certificate | — | 19 |

AIR §5 L104 reports "Phase-6 source documents | 18 (6A–6M, AAM, AEC, AMI, AVS, FAR)", excluding AIR itself — consistent with 19 including AIR. No unregistered or missing Phase-6 document exists.

## 7. API Inventory Validation

| Check | Expected | Observed | Result |
|---|---|---|---|
| HTTP routes in AMI | 369 | 369 | PASS |
| Surfaces | PUBLIC 360 · CALLBACK 5 · INTERNAL 4 | same | PASS |
| Methods | GET 175 · POST 161 · PATCH 19 · DELETE 13 · PUT 1 | same | PASS |
| Owner distribution | 6A 1 · 6B 36 · 6C 42 · 6D 21 · 6E 17 · 6F 21 · 6G 78 · 6H 25 · 6I 12 · 6J 40 · 6K 23 · 6L 14 · 6M 39 | same | PASS |
| Row identity across AMI, AAM §13, AEC §15, AVS, AIR §8 (ID + method + path + surface) | 369 × 5 | 369 × 5; duplicates 0, missing 0, mismatches 0 | PASS |
| Every AMI path present in its owner document | 369 | 369 | PASS |
| Owner-document method+path pairs resolved into AMI | 215 pairs | 214 in AMI §5 route rows, 1 in AMI §9 register of excluded and resolved items; unresolved 0 | PASS |
| Major path prefixes | `/api/v1`, `/api/internal/v1`, `/ws/v1`, provider callback paths | same; no v2 major path anywhere | PASS |

Internal routes: AMI-6C-041, AMI-6C-042, AMI-6D-020, AMI-6E-017. Inbound voice has no public route; it arrives via callback AMI-6D-021. Outbound voice is AMI-6D-001 `POST /api/v1/calls`.

## 8. WebSocket Validation

| ID | Path | Result |
|---|---|---|
| AMI-WS-6D-001 | `/ws/v1/voice/media/{session_id}` | PASS |
| AMI-WS-6D-002 | `/ws/v1/voice/calls/{call_id}` | PASS |
| AMI-WS-6D-003 | `/ws/v1/voice/calls/stream` | PASS |
| AMI-WS-6I-001 | `/ws/v1/workflow-executions/{execution_id}` | PASS |

4/4 are present in AMI (L551–L554), AAM §14 (L1060), AEC §16 (L1251), AVS (AX-C 4) and AIR §9. API keys and Platform-Admin sessions are rejected on all four; WS push is non-durable (6A L778); WS errors follow AEC §13. Readiness: 2 READY WITH IMPLEMENTATION OBLIGATION (WS-6D-001/002, DEP-6D-08) and 2 READY TO IMPLEMENT.

## 9. Callback Validation

| ID | Owner | Signature / state | Error contract | Event class | Result |
|---|---|---|---|---|---|
| AMI-6B-013 | 6B OAuth login callback | OAuth state | profile CALLBACK | OUTBOX_NONE | PASS |
| AMI-6D-021 | 6D `POST /webhooks/voice/{provider_slug}/events` | provider signature | AEC §12 | PROVIDER_CALLBACK | PASS |
| AMI-6J-011 | 6J OAuth integration callback | OAuth state | AEC §12 | OUTBOX_CONDITIONAL | PASS |
| AMI-6J-014 | 6J inbound provider webhook | provider signature | AEC §12 | PROVIDER_CALLBACK | PASS |
| AMI-6K-023 | 6K payment webhook | provider signature | AEC §12 | PROVIDER_CALLBACK | PASS |

5/5 callbacks: AAM key and PA columns DENY SIG; no bearer-role access; AVS axis AX-G (provider-cutover lifecycle, AVS-OD-05); fast-ACK with no provider I/O inside an open transaction.

## 10. Authorization Validation

| Check | Result |
|---|---|
| Routes without an AAM principal class | 0 |
| Routes without a permission / guard / explicit N/A | 0 |
| Tenant-RBAC on Platform-Admin routes | 0 |
| API key accepted on Platform-Admin routes | 0 (DENY 403 TPF 42) |
| Internal token accepted on public routes | 0 |
| Bearer tokens accepted on callbacks | 0 |
| Sensitive-media routes without scope condition | 0 of 7 (AMI-6D-010…014 C-KEY-SM / C-BG-SM; AMI-6M-008/009 C-BG-SM) |
| AAM ↔ AEC authorization-profile mismatches | 0 (TENANT-KEY 242 · SESSION 66 · PA 42 · CALLBACK 5 · INTERNAL 4 · PRE-AUTH 10) |

AMI↔AAM: 369/369 rows agree on ID, method, path, surface and principal class; orphans 0. Principal classes: user token or API key 242; user token 65; Platform Admin 42; anonymous 4; internal JWT 4; provider signature 3; OAuth state 2; seven single-route classes. PA column: DENY 403 149, C-BG-R-GENERAL 123, ALLOW 40, N/A 28, C-BG-R-BILLING 16, DENY SIG 5, DENY 401 4, C-BG-SM 2, LIFECYCLE 1, QUOTA 1. Key column: C-KEY 233, DENY 403 67, DENY 403 TPF 42, N/A 9, DENY SIG 5, DENY 401 4, ALLOW 2, C-KEY-SM 2, C-KEY+C-TARGET 2, C-KEY+C-JOB 1, C-KEY+C-ATTACH 1, C-KEY+C-AUTHOR 1. Internal service tokens are READY WITH IMPLEMENTATION OBLIGATION under DEP-6B-07.

## 11. Error Validation

| Check | Expected | Observed | Result |
|---|---|---|---|
| AEC §15 route rows | 369 | 369 | PASS |
| AEC §5 active registry (declared L238 / parsed rows L101–L239) | equal | 132 / 132 (A 102 · B 24 · C 3 · D 3) | PASS |
| Distinct codes referenced by route rows | — | 105 | PASS |
| Referenced codes not registered | 0 | 0 | PASS |
| Callback rows governed by AEC §12 | 4 | AMI-6D-021, AMI-6J-011, AMI-6J-014, AMI-6K-023 | PASS |
| V1 route error gaps | 0 | 0 | PASS |
| Wire leakage of categories G/H/N | 0 | 0 | PASS |
| `API_VERSION_SUNSET` on any V1 route | 0 | 0 (FUTURE registration only, AVS-OD-01) | PASS |
| New error code invented by AIR or this certificate | 0 | 0 | PASS |
| AIR §16 "AEC §5 active registry codes" = AEC §5 active count | 132 | 132 | PASS |

Envelope AEC §3 L68; precedence 401 → 403 → 404-concealment AEC §8 L479; retryability AEC §9 L490; "409 CONFLICT" prose normalises to `STATE_CONFLICT`.

Four distinct measures, kept separate: **registered active codes 132** (AEC §5 rows L101–L239, 132 unique, declared L238); **used codes 105** (distinct codes referenced by AEC §15 route rows); **unregistered used codes 0**; **current V1 route error gaps 0**. The error contract has no gap, and the former reporting defect (AIR §16 = 189) is corrected to 132 by the controlled AIR erratum (§37 FV-P1-01, RESOLVED); AEC itself is unchanged (SHA-256 in §5).

## 12. Versioning Validation

| Check | Result |
|---|---|
| Route axis coverage AX-A 360 + AX-B 4 + AX-G 5 = 369; AX-C 4 WS | PASS |
| AVS surface ↔ AMI surface mismatches | 0 |
| AVS-OD-01…11 | all RESOLVED (AVS §38 L1605) |
| AVS gates | 26/26 PASS |
| v2 major path in any artifact | none — AVS prohibits creating one |
| Webhook signing input | `HMAC-SHA256(signing_secret, f"ts={X-Platform-Timestamp}.{raw_request_body}")` (6J; AVS SG-01) |
| Plugin signing input | `ts={unix_timestamp}.{method}.{canonical_request_path}.{raw_body}` (6J; AVS SG-06) — distinct from the webhook formula |
| `v1=` signature | immutable; no in-place mutation (AVS-OD-08) |
| Predecessor webhook topic | retained while the successor is served (AVS-OD-07) |
| Idempotency keys | isolated per major (AVS-OD-09) |
| `API_VERSION_SUNSET` | FUTURE registration only; required by no V1 route |

AVS gaps: 0.

## 13. Database/Migration Validation

| Check | Expected | Observed | Result |
|---|---|---|---|
| SQL migrations | 112 | 112 | PASS |
| Alembic revisions | 112 | 112 | PASS |
| Root / head | `001_5B` / `112_5H5` | same | PASS |
| Graph | single linear chain, acyclic, no branch, no merge, no duplicate ID | same | PASS |
| Migration `113` | absent | absent | PASS |
| Every SQL wrapped by exactly one revision | 112 | 112 | PASS |
| Series | 5B 15 · 5C 12 · 5D 13 · 5E 8 · 5F 19 · 5G 7 · 5H 17 · 5I 9 · 5J 11 · 5K 1 | same | PASS |

Security surface present in SQL: SECURITY DEFINER in 49 files (257 occurrences); RLS ENABLE 103, FORCE 104, POLICY 119; `FOR UPDATE` in 29 files (99 occurrences); advisory locks in 041_5G, 083_5F6, 088_5F8, 092_5F12, 100_5G1, 110_5C2, 111_5H4, 112_5H5.

Route DB authority: persistent 347; no-persistence 2 (AMI-6B-012, AMI-6C-004); approved-not-materialized 1 (AMI-6C-018); provider 3; composite 16; **unresolved 0**. No route requires a table, column or function absent from the 112 migrations; no feature-flag table and no invitation-linkage column exist, consistent with the Release-Train and IR registers.

## 14. Transaction Validation

| Class | Routes |
|---|---|
| TX-RO | 175 |
| TX-1 | 179 |
| TX-NET (provider I/O, no DB transaction open) | 11 |
| TX-SEQ (AMI-6C-016) | 1 |
| TX-AUDIT (AMI-6D-011, AMI-6M-008, AMI-6M-009) | 3 |
| Total | 369 |

Business mutations 191 + read-only 175 + audit-only 3 = 369; routes with any persistent write 194. 29 routes carry a post-commit continuation; 6 leave internal ordering to implementation under the 6A §35 invariant (no DB transaction held across network I/O, no 2PC). Pinned cases re-verified: 6B OAuth callback is not a pure read; 6J OAuth callback does not span the provider exchange in one transaction; authorize/check and workflow validate write nothing. Transaction ambiguity: **0**.

## 15. Concurrency Validation

CC-01…CC-15 are contiguous and cover 100 routes: CC-01 refresh; CC-02 invitation resend; CC-03 last owner; CC-04 Agent quota (`111_5H4:752`, `fn_create_agent` `110_5C2:272`); CC-05 concurrent calls (shared CONCURRENT_CALLS pool, capacity `112_5H5:373`); CC-06 dispatch (`call_dispatch_keys` `099_5C1:205`); CC-07 workflow CAS; CC-08 idempotency; CC-09 usage; CC-10 invoice sequence (`052_5H:55`); CC-11 refunds (reserve `107_5B5:577`); CC-12 webhook retries; CC-13 WS sessions; CC-14 callback replay (inbound dedup `062_5I:38`); CC-15 outbox publication (77 routes = the producer set). Every scenario names its DB primitive. The capacity runtime is not implemented (obligation, not ambiguity). Concurrency blockers: **0**.

## 16. Audit Validation

| Class | Routes |
|---|---|
| AUDIT_NONE | 182 |
| AUDIT_SYNC | 94 |
| AUDIT_ASYNC | 84 |
| AUDIT_CONDITIONAL | 6 |
| AUDIT_DOMAIN / PROVIDER_PROCESSING | 3 |

Audit is a mixed contract (5J §14.5), not globally synchronous; audit rows are not domain events. `audit.audit_events` is anchored at `072_5J:17`; the nightly hash chain provides tamper evidence. AIR-OD-03 (owner-approved hybrid) maps 14 CRM/campaign/workflow routes to AUDIT_ASYNC: 5 reuse existing action kinds (AMI-6G-009/010 CONTACT_UPDATED; AMI-6G-028 COMPANY_UPDATED; AMI-6G-042 PIPELINE_UPDATED; AMI-6G-073 CRM_FIELD_DEFINITION_UPDATED) and 9 name new kinds (AMI-6G-032 DEAL_UPDATED; AMI-6G-037 DEAL_OWNER_ASSIGNED; AMI-6G-044 ACTIVITY_RECORDED; AMI-6G-051 TASK_UPDATED; AMI-6G-059 NOTE_PINNED; AMI-6G-060 NOTE_UNPINNED; AMI-6G-065 APPOINTMENT_CONFIRMED; AMI-6H-018 CSV_IMPORT_SUBMITTED; AMI-6I-004 WORKFLOW_METADATA_UPDATED). The 5 reused kinds exist in 5J/6G; the 9 new kinds exist nowhere else, as the decision requires. The 5J vocabulary sync is a non-blocking governance item. Audit-action gaps: **0**.

## 17. Event/Outbox Validation

| Class | Routes |
|---|---|
| OUTBOX_NONE | 265 |
| OUTBOX_REQUIRED | 75 |
| OUTBOX_CONDITIONAL | 2 |
| DIRECT_REDIS_STREAM | 20 |
| WS_ONLY | 1 |
| PROVIDER_CALLBACK | 3 |
| OUTBOX_WORKER_EMITTED (AMI-6H-018) | 1 |
| PUBLIC_WEBHOOK_DELIVERY | 2 |
| Total | 369 |

EVENT_TRIGGER_UNRESOLVED = **0**

Producers = 75 + 2 = 77 = CC-15 routes; no OUTBOX_NONE route is in CC-15. The outbox is `audit.domain_event_outbox` (`077_5J1:48`), claimed by `audit.fn_claim_outbox_events()`, delivered at-least-once. Owner-decided triggers re-verified: AMI-6F-007 upload-url emits no `document.uploaded` (EVT-01 B; AMI-6F-008 is the producer); AMI-6F-012 reprocess emits no new durable event (EVT-02 C); AMI-6H-007 campaign Start request does not emit `campaign.started` (EVT-03 B); AMI-6J-004 returns 201 CONNECTING, never ACTIVE, the post-commit worker emits exactly one event on success and none on activation failure (EVT-04 B). AIR §18 separates eight mechanisms: outbox, Redis Streams, Celery, APScheduler, public webhooks, provider callbacks, audit and WS.

## 18. Security Validation

22 security controls are specified (AIR §14); all require runtime tests and none is implemented, which is the expected state before implementation. Re-verified contracts: tenant isolation (cross-tenant → 404, 6A §23 L595; RLS FORCE on tenant tables); sensitive-media scope (7 routes); break-glass (`087_5B1:34`, `fn_break_glass_check` `105_5B4:200`); Platform Admin via `is_platform_admin` (`107_5B5:134`), never tenant RBAC; callbacks signature-only; webhook and plugin signing inputs distinct and timestamped; `v1=` immutable; password-reset tokens `002_5B:77`; internal tokens READY WITH IMPLEMENTATION OBLIGATION (DEP-6B-07). Security contradictions: 0.

## 19. Billing/Quota Validation

| Rule | Anchor | Result |
|---|---|---|
| Money is server-authoritative | 6K; AIR §26 | PASS |
| Usage minutes are exact `duration_seconds / 60`, no `CEIL` | 6K | PASS |
| Ordinary tenants never create plans, publish plan versions or change global prices | 6K §16.3 | PASS |
| Price resolved server-side (`102_5H2:394`; plan versions `047_5H:38`) | 6K §13.1 | PASS |
| Discount is not client-authoritative and not built in V1 | 6K §27 | PASS |
| No tenant refund creation; refund amount bounded server-side (`055_5H:37`) | 6K §31 | PASS |
| Payment amount computed from `total_due_amount` | 6K §39.4 | PASS |
| Provider cost (`cost_entries`) never read by a tenant-facing endpoint; margin internal | 6K §24 L2029 | PASS |
| Agent quota (`111_5H4:752`) and shared CONCURRENT_CALLS pool (6K L3745) | 5H/6K | PASS |
| Usage records `050_5H:46`; invoice sequence `052_5H:55` | 5H | PASS |

Financial-authority contradictions: 0.

## 20. Voice/Realtime Validation

Outbound voice: AMI-6D-001 durably records intent and does not block on answer. Inbound voice: provider callback AMI-6D-021. Recordings/transcripts AMI-6D-010…014 (sensitive media; `014_5C:8`, `014_5C:45`); phone numbers AMI-6D-017…019; internal AMI-6D-020; call sessions `011_5C:12`. Telephony: Exotel is V1 (FR-TEL-001, SRS L121); SIP (FR-TEL-002, SRS L122) is a **V1 Release-Train** item (6L §61.3 E → P9 + P18) with no route today — no route is required for the RT item to be implemented in its phase. Turn latency "≤750 ms" is a TARGET, not MEASURED (AIR L1424; 6D L1893); its benchmark is RT item DEP-6D-11 (P23/P24). DEP-6D-05 and DEP-6D-10 remain known future owner decisions (§31); no value or vendor is set here.

## 21. Knowledge/RAG Validation

21 routes (6F); knowledge bases `035_5F:8`, pgvector `034_5F:9`, chunks `038_5F:8`. Upload-url (AMI-6F-007) is not a producer; upload completion (AMI-6F-008) is; reprocess (AMI-6F-012) emits no new durable event. 6F audit is AUDIT_ASYNC. IR: DEP-6F-06, DEP-6F-07, DEP-6F-08 (P10), DEP-6K-02 (P10), 6A R-6 (P10–P13). No contradiction.

## 22. CRM Validation

78 routes (6G); contacts `020_5D:8`. AIR-OD-03 audit mapping verified (§16). The CRM merge outbox ordering (F-11) and `contact.erased` (F-10) are non-normative clarity notes that do not make the V1 contract ambiguous. No contradiction.

## 23. Campaign Validation

25 routes (6H); campaigns `029_5E:14`, campaign contacts `030_5E:8`, dispatch keys `099_5C1:205`. Start request (AMI-6H-007) is OUTBOX_NONE; `campaign.started` is not a request-path event (EVT-03 B). CSV import (AMI-6H-018) is worker-emitted. DNC dispatch-proof is RT DEP-6H-11 (P12 + Legal). No contradiction.

## 24. Workflow Validation

12 HTTP routes + 1 WS (6I); `workflow_definitions` `040_5G:8`, `workflow_executions` `041_5G:14` with advisory-lock CAS (CC-07). Validate writes nothing. IR: DEP-6K-05, 6I §54-5, 6I §54-10 (P13). No contradiction.

## 25. Integrations/Webhooks/Plugins Validation

40 routes (6J); integration connections `061_5I:3`; webhook endpoints `062_5I:3`; inbound dedup `062_5I:38`; deliveries `063_5I:5`; `fn_activate_integration_connection` `101_5I1:280`. Activation (AMI-6J-004) returns CONNECTING, is completed by a post-commit worker, and emits `integration.connected` only on success (EVT-04 B). Webhook and plugin signatures verified in §12. IR: DEP-6K-01 (P17). No contradiction.

## 26. Analytics/Audit/Admin Validation

6L: 14 routes. 10 of 12 projections have no executed population function (only `fn_apply_projection_call_latency` and `fn_apply_projection_call_metrics` exist in the migrations; projections `069_5J`); a backfill mechanism is not specified. No CSAT in V1 (6L L35). Overview excludes cost/margin (DEC-6L-02). IR: 6L §55-5, 6M §52 (P19). 6M: 39 routes, 42 Platform-Admin principal routes in total, break-glass conditions per AAM; sensitive media AMI-6M-008/009 are TX-AUDIT. Feature flags (FR-FLAG-001 / DBGAP-6M-01) are V1 Release-Train under AIR-OD-02 (V1 Platform Foundation). No contradiction.

## 27. Implementation-Readiness Register

21/21 IR items present in AIR §28 and FAR; each has a phase; "Prevents P7?" = No for all 21.

| # | Item | Phase |
|---|---|---|
| 1 | DEP-6B-04 | P8 |
| 2 | DEP-6B-07 | P22 (derived) |
| 3 | DEP-6C-12 | P8 (AIR-OD-01) |
| 4 | DEP-6D-05 | P9 (known future owner decision) |
| 5 | DEP-6D-08 | P9 |
| 6 | DEP-6D-10 | P9/P16 (known future owner decision) |
| 7 | DEP-6F-06 | P10 |
| 8 | DEP-6F-07 | P10 |
| 9 | DEP-6F-08 | P10 |
| 10 | DEP-6F-10 | P20 |
| 11 | DEP-6K-01 | P17 |
| 12 | DEP-6K-02 | P10 |
| 13 | DEP-6K-05 | P13 |
| 14 | 6A R-4 | P23 (derived) |
| 15 | 6A R-6 | P10–P13 |
| 16 | 6I §54-5 | P13 |
| 17 | 6I §54-10 | P13 |
| 18 | 6K §54.5 | P20 |
| 19 | 6K §54.6 | P9 |
| 20 | 6L §55-5 | P19 |
| 21 | 6M §52 | P19 |

## 28. Release-Train Register

4/4 RT items, all V1:

| Item | Destination |
|---|---|
| DEP-6D-11 latency / provider benchmark | P23 / P24 |
| DEP-6H-11 DNC dispatch-proof | P12 + Legal |
| 6L §61.3 E SIP trunk support | P9 + P18 |
| FR-FLAG-001 / DBGAP-6M-01 feature flags | V1 Platform Foundation (AIR-OD-02) |

SIP and feature flags are V1 Release-Train, not FUTURE (verified in AIR §29 and FAR §11.1). CSAT is not V1.

## 29. Future Register

83/83 FUTURE items present in AIR §30 and FAR, each non-blocking; none carries a V1 route, code or table.

FAR ledger: CLOSED 106 · FUTURE 83 · RT 4 · IR 21 · BLOCKER 0 = 214. FAR BLOCKER = **0**

## 30. Owner-Decision Ledger

| Decision | Choice | Exact scope | Preserved |
|---|---|---|---|
| AIR-OD-01 | Option A | DEP-6C-12 → IR (P8) | yes |
| AIR-OD-02 | Option A | feature flags → V1 Release-Train, V1 Platform Foundation | yes |
| AIR-P0-EVT-01 | Option B | AMI-6F-007 no event; AMI-6F-008 producer | yes |
| AIR-P0-EVT-02 | Option C | AMI-6F-012 no new durable event | yes |
| AIR-P0-EVT-03 | Option B | AMI-6H-007 does not emit `campaign.started` | yes |
| AIR-P0-EVT-04 | Option B | AMI-6J-004 CONNECTING + worker | yes |
| AIR-OD-03 | owner-approved hybrid mapping | 14 routes AUDIT_ASYNC, 5 reused / 9 new kinds | yes |

Each decision resolves only its stated scope; none is treated as a global override. Unapproved amendments to frozen artifacts: 0; one owner-approved controlled AIR factual erratum (FV-P1-01) is recorded — it is a count correction, not a design decision, and changes no route, code, permission, table or event. Owner decisions required now: **0**

## 31. Known Future Owner Decisions

| Item | Owner | Phase | Stated here |
|---|---|---|---|
| DEP-6D-05 | Owner / Product | P9 | no timer value |
| DEP-6D-10 | Owner / Architecture | P9 / P16 | no vendor |

Upstream, non-blocking: ODD-5H-02 and ODD-5J-01…07. None is required before Phase 7.

## 32. Major V1 Traceability

Each chain is Requirement → Architecture/domain → DB authority → API owner (AMI) → Authorization (AAM §13 L682) → Errors (AEC §15 L873) → Versioning (AVS) → IR → Roadmap. Every link was checked to exist in the named file.

| # | Capability | Requirement (SRS) | Architecture / domain | DB authority | API owner | Authz | Errors | Versioning | IR / RT | Roadmap |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Org / tenancy | §3.1 L84 | HLA; 3A; 4A | 5B; `003_5B:14` organizations, `003_5B:111` memberships | 6C (AMI L164) | AAM §13 TENANT-KEY / SESSION | AEC §15 | AX-A | DEP-6C-12 | P8 L45 |
| 2 | AuthN / AuthZ | §3.2 L94 | HLA; 3A; 4A | 5B; `002_5B:10` users, `002_5B:77` reset tokens, `087_5B1:34` break-glass | 6B (AMI L123) | AAM §13 PRE-AUTH / SESSION | AEC §15 | AX-A, AX-G (6B-013) | DEP-6B-04, DEP-6B-07 | P8 L45 |
| 3 | Inbound voice | §3.3 L104 FR-VOICE-001 L108; §3.4 L117 | 3B; 4B | 5C; `011_5C:12` call sessions | 6D callback AMI-6D-021 (AMI L211) | DENY SIG | AEC §12 | AX-G | DEP-6D-08; RT SIP | P9 L51 |
| 4 | Outbound voice | §3.3 FR-VOICE-002 L109 | 3B; 4B | 5C; `099_5C1:205` dispatch keys; `112_5H5:373` capacity | 6D AMI-6D-001 | C-KEY `call:initiate` | AEC §15 | AX-A | DEP-6D-05, DEP-6D-10; RT DEP-6D-11 | P9 L51 |
| 5 | AI agents | §3.6 L134; §3.7 L143 | 3B; 4B; 4E | 5C; `010_5C:8` agents; `110_5C2:272`; `111_5H4:752` quota | 6E (AMI L237) | C-KEY `agent:write` | AEC §15 | AX-A, AX-B (6E-017) | DEP-6K-01, 6K §54.6 | P9 L51; P16 L93; P17 L99 |
| 6 | Knowledge / RAG | §3.8 L152 | 3D; 4E | 5F; `035_5F:8`, `034_5F:9`, `038_5F:8` | 6F (AMI L259) | C-KEY `knowledge:write` | AEC §15 | AX-A | DEP-6F-06/07/08, DEP-6K-02 | P10 L57 |
| 7 | CRM | §3.9 L162 | 3C; 4C | 5D; `020_5D:8` contacts | 6G (AMI L285) | C-KEY `contact:write` | AEC §15 | AX-A | 6A R-6 | P11 L63 |
| 8 | Campaign | §3.10 L171 | 3C; 4D | 5E; `029_5E:14`, `030_5E:8` | 6H (AMI L368) | C-KEY `campaign:write` | AEC §15 | AX-A | RT DEP-6H-11 | P12 L69 |
| 9 | Workflow | §3.11 L181 | 3D; 4E | 5G; `040_5G:8`, `041_5G:14` | 6I (AMI L398) | C-KEY `workflow:write` | AEC §15; WS AEC §16 | AX-A, AX-C | DEP-6K-05, 6I §54-5, §54-10 | P13 L75 |
| 10 | Integrations / webhooks / plugins | §3.16 L224; §3.17 L231 | 3E; 4F | 5I; `061_5I:3`, `062_5I:3`, `063_5I:5`, `101_5I1:280` | 6J (AMI L415) | C-KEY `integration:read`; DENY SIG on callbacks | AEC §15; §12 | AX-A, AX-E, AX-F, AX-G | DEP-6K-01 | P18 L105 |
| 11 | Billing | §3.15 L216 | 3E; 4F | 5H; `049_5H:3`, `047_5H:38`, `050_5H:46`, `052_5H:55`, `055_5H:37`, `102_5H2:394` | 6K (AMI L460) | C-KEY `billing:read`; C-BG-R-BILLING | AEC §15; §12 (6K-023) | AX-A, AX-G | DEP-6F-10, 6K §54.5 | P20 L117 |
| 12 | Analytics / audit | §3.14 L207 | 3E; 4G | 5J; `069_5J`, `072_5J:17`, `077_5J1:48` | 6L (AMI L488) | C-KEY `analytics:read` | AEC §15 | AX-A | 6L §55-5 | P19 L111 |
| 13 | Platform admin | §3.19 L244; §3.18 L238 flags | 3A; 4A; 4G | 5B; `107_5B5:134` `is_platform_admin`, `105_5B4:200` | 6M (AMI L507) | PA session; C-BG-R-GENERAL / C-BG-SM | AEC §15 | AX-A | 6M §52; RT FR-FLAG-001 | P8 L45; P19 L111 |

13/13 capabilities have a deterministic chain. Capabilities without a chain: 0.

## 33. Phase-7 Entry Gate

Independently recomputed from AIR §18.1/§18.2, the CC register and the migrations — not copied from AIR §32.

| # | Proof | Result |
|---|---|---|
| 1 | PostgreSQL baseline: 112/112, root `001_5B`, head `112_5H5`, linear, no `113` | PASS |
| 2 | Outbox contract exists (`077_5J1:48`, claim function, at-least-once) | PASS |
| 3 | Durable producers named: OUTBOX_REQUIRED 75 | PASS |
| 4 | Conditional producers named: OUTBOX_CONDITIONAL 2 | PASS |
| 5 | Worker producer attributed to the worker: AMI-6H-018 | PASS |
| 6 | OUTBOX_NONE routes each carry a reason: 265 | PASS |
| 7 | Redis Streams separated: DIRECT_REDIS_STREAM 20, not outbox | PASS |
| 8 | WS separated: WS_ONLY 1 + 4 WS channels, non-durable | PASS |
| 9 | Public webhooks separated: PUBLIC_WEBHOOK_DELIVERY 2 | PASS |
| 10 | Provider callbacks separated: PROVIDER_CALLBACK 3; 5/5 callbacks classified | PASS |
| 11 | Audit separated from events: mixed audit contract, audited set ≠ producer set | PASS |
| 12 | No unresolved trigger: EVENT_TRIGGER_UNRESOLVED 0; CC-15 = 77 = producers | PASS |
| 13 | No owner decision required now: 0 | PASS |
| 14 | Phase 7 need not invent behavior: 21/21 IR "Prevents P7?" = No; no route, code, permission, table or migration to add | PASS |

PHASE 7 ENTRY GATE (independent) = **PASS** — 14/14. This is an entry-condition proof only; Phase 7 is not started.

## 34. Minor Observation Review

All 24 AIR §37 minors and MO-FV-02 (25 in total) were re-reviewed individually on the corrected corpus against the promotion triggers (nondeterminism, missing V1 contract, Phase-7 ambiguity, security / financial / DB contradiction, incorrect normative count). The AIR erratum touched none of them. Promoted to P0/P1: **0**

| ID | Observation | Classification | Promotion test |
|---|---|---|---|
| F-01 | AMI-6D-021 envelope follows AEC §12 | minor | contract explicit in AEC §12 — deterministic |
| F-02 | SIP is RT with no route | RT | RT destination P9 + P18 — no V1 route contract missing today |
| F-03 | Some phases derived | minor | derivations labelled; no behavior depends on them |
| F-04 | DEP-6C-12 resolved by AIR-OD-01 | IR | owner decision preserved |
| F-05 | WS errors per AEC §13 | minor | contract explicit |
| F-06 | Old FUTURE numbering | governance sync | numbering only; 83/83 reconcile |
| F-07 | Flags resolved by AIR-OD-02 | RT | owner decision preserved |
| F-08 | Upstream ODDs | known future OD | non-blocking upstream items |
| F-09 | Socket.IO vs raw WS wording | minor | wire paths and auth fixed in AMI/AAM |
| F-10 | `contact.erased` naming | minor | no Phase-7 ambiguity; event named in owner doc |
| F-11 | 6G merge outbox ordering | IR | ordering inside one TX-1; implementation note |
| F-12 | Plugin audit async default | minor | class fixed per route in AIR §8 |
| F-13 | `plugin.reactivated` | minor | event named in owner doc |
| F-14 | DEGRADED→ACTIVE transition | minor | transition in 6J state model |
| F-15 | SUBSCRIPTION_CREATED sync wording | minor | route class fixed; wording only |
| F-16 | AMI-6M-003 emits no event | minor | explicit OUTBOX_NONE |
| F-17 | QUOTA_OVERRIDE_SET atomic | minor | atomicity fixed by TX-1 |
| F-18 | 6C synchrony wording | minor | classes fixed per route |
| F-19 | `data_subject_request` family | future | FUTURE-registered |
| F-20 | Internal bus → DIRECT_REDIS_STREAM | minor | classification explicit (20) |
| F-21 | Break-glass wording | minor | AAM conditions deterministic |
| F-22 | 6B L2052 superseded | governance sync | superseded history, not current |
| F-23 | `campaign.started` → EVT-03 | minor | owner decision B preserved |
| F-24 | INTEGRATION_CONNECTION_CREATED sync | minor | route class fixed |

New observation from this validation:

| ID | Observation | Classification | Promotion test |
|---|---|---|---|
| MO-FV-02 | AIR §18 mention-density table, "webhook deliver" column: no search rule is stated and at most 9/13 values reproduce under any tested rule; the other seven columns reproduce (WebSocket with `websocket` or `/ws/`) | minor | AIR marks the table "evidence of coverage only; it is not a specification"; it is a non-normative evidence-density reproducibility issue: no route, event, audit, transaction or gate value is derived from it, so it determines no implementation behavior |

(The earlier working label MO-FV-01 was withdrawn: that observation is FV-P1-01, a P1, see §37.)

## 35. Whole-Corpus Contradiction Scan

Amendments, resolved dependencies, owner decisions and superseded history were taken into account; superseded text (e.g. 6B L2052) is not flagged.

| Topic | Sources compared | Result |
|---|---|---|
| Method / path | AMI, AAM, AEC, AVS, AIR, owner docs | 0 contradictions |
| Owner | AMI owner column vs owner docs | 0 |
| Auth mechanism | AMI, AAM, AEC profiles | 0 |
| Permissions | AMI, AAM, owner docs | 0 |
| Scopes | AAM key column, 6B | 0 |
| Tenant handling | 6A §23, AAM, RLS migrations | 0 |
| Internal auth | AAM, 6B DEP-6B-07, AVS AX-B | 0 |
| Sensitive media | AAM, 6D, 6M, AIR | 0 |
| Transaction behavior | AIR §12, owner docs, 6A §35 | 0 |
| Provider I/O | TX-NET/TX-SEQ set vs owner docs | 0 |
| Audit synchrony | AIR §18.1, 5J §14.5, owner docs | 0 |
| Audit action kind | AIR-OD-03 mapping vs 5J / 6G | 0 (5J vocabulary sync is governance) |
| Outbox ownership | 5J outbox, 6C claim function, AIR | 0 |
| Event producer | AIR §18.2, owner event catalogs, CC-15 | 0 |
| Event payload | owner catalogs, AVS AX-D | 0 |
| Callback security | AAM DENY SIG, AEC §12, AVS AX-G | 0 |
| Webhook signature | 6J, AVS SG-01 | 0 |
| Plugin signature | 6J, AVS SG-06 | 0 |
| Billing authority | 6K, 5H, AIR §26 | 0 |
| Quota authority | 6K, `111_5H4` | 0 |
| Agent quota | 6E, 6K, `111_5H4:752` | 0 |
| Concurrent-call pool | 6D, 6K L3745, `112_5H5:373` | 0 |
| SIP V1 | SRS L122, 6L §61.3 E, FAR, AIR §29 | 0 — V1 RT everywhere |
| CSAT | 6L L35, AIR, AMI | 0 — not V1 everywhere |
| Provider-cost visibility | 6K §24, 6L DEC-6L-02 | 0 — internal only |
| Margin visibility | 6K §24, 6L | 0 — internal only |
| API versioning | AVS, AMI, AIR §17 | 0 — v1 only, no v2 major path |
| Feature flags | SRS L238, 6M, FAR, AIR-OD-02 | 0 — V1 RT |
| Invitation resend | 6C, CC-02, migrations | 0 |
| Campaign start | 6H, EVT-03 | 0 |
| Integration activation | 6J, EVT-04, `101_5I1:280` | 0 |
| Numeric summaries (AIR vs source registers) | AIR §16 L959 vs AEC §5 L238 | 0 — 132 = 132 after the FV-P1-01 erratum |
| Error registry counts | AIR, AEC, FAR, AMI, AAM, AVS, this certificate | 0 |

Targeted searches on the corrected corpus: "AEC registry codes = 189", "AEC registry codes" with value 189, "189 codes" and any other active-registry count — no normative occurrence. The number 189 survives only as erratum history (AIR §37.1 FV-P1-01, this certificate §5/§37) and in unrelated values (AIR L760 "189 non-GET mutations", line/row references and hash substrings). Contradictions remaining: **0**.

## 36. Adversarial Validation

Method: the corpus (Phase-6 docs, Phase-5 docs and migrations, roadmap) was copied to a scratch area outside the project; each mutation is applied to a fresh copy, the named validator runs, and the mutation counts as caught only if the validator fails **and** its output contains the intended failure reason. No mutation involves version-control state.

| Spec # | Mutation | Caught by (mutation IDs) |
|---|---|---|
| 1–5 | AIR / AMI / AAM / AEC / AVS byte change | FRZ-AIR, FRZ-AMI, FRZ-AAM, FRZ-AEC, FRZ-AVS (+ FRZ-FAR, FRZ-LN, FRZ-RM, HSH-01…05) |
| 6–9 | migration 113; second head; missing revision; duplicate ID | MIG-01, MIG-08; MIG-03; MIG-12, MIG-02; MIG-07 |
| 10–15 | remove AMI route; duplicate ID; method; path; remove AAM row; profile mismatch | RTE-01; RTE-14; RTE-02; RTE-07, RTE-04; RTE-15; SEM-01, SEM-02 |
| 16–20 | sensitive-media scope; PA → tenant RBAC; callback bearer; webhook timestamp; plugin = webhook formula | SUR-13, SUR-14; SUR-07; SUR-10; SEM-05, SCP-09; SEM-03, SEM-04, SCP-10 |
| 21–25 | current SUNSET; v2 API path; v2 WS path; predecessor topic removed; `v1=` mutated | AEC-03, AEC-04; RTE-10; RTE-11, SUR-02; SEM-06; SEM-07, SEM-08 |
| 26–30 | provider I/O in TX; 6B callback pure read; 6J callback one TX; authorize/check writes; validate writes | SEM-09, SEM-10; SEM-12; SEM-13; SEM-14; SEM-15 |
| 31–34 | all audit sync; 6F sync; OD-03 mapping removed; action kind changed | SEM-17; SEM-18; CLM-18; CLM-13, CLM-15, CLM-17, CLM-25 |
| 35–42 | upload-url emits; reprocess emits; Start emits; 6J-004 ACTIVE; worker removed; failure emits; ETU with P7 PASS; all mutations CC-15 | EVT-05; SEM-19, EVT-04; EVT-03; SEM-20, SEM-21; EVT-06; SEM-22; SEM-24…26; SEM-27, AIR-10 |
| 43–47 | client price; client discount; client refund; rounded minutes; tenant sees cost | SEM-28, SEM-29; SEM-30; SEM-31…34; SCP-11; SCP-13 |
| 48–50 | SIP → FUTURE; flags → FUTURE; CSAT in V1 | REG-06, FAR-04, SCP-14; REG-07, FAR-06, SCP-15; SCP-05 |
| 51–58 | OD-01 removed; OD-02 removed; EVT-01…04 changed; OD-03 changed; global override | CLM-19; CLM-20; CLM-22, CLM-06, CLM-23, CLM-24; CLM-25; SEM-36, SEM-37 |
| 59–63 | certificate READY with P0 / P1 / ETU / Phase-7 FAIL / FAR BLOCKER | CRT-59, CRT-60, CRT-60B; CRT-61; CRT-62; CRT-63 |
| extra | certificate structure, forbidden claims, gate/findings consistency | CRT-64…CRT-82, CLM-26, CLM-27 |
| extra | AIR↔AEC registry-count probe | ACN-01…ACN-03 |
| FV 1–10 | AIR 132→189; AIR 132→105; certificate §11 says 189 while AEC has 132; AIR 132 with AEC parse altered to 131; duplicate active AEC code; unregistered used code; FV-P1-01 RESOLVED while AIR≠AEC; certificate READY with FV-P1-01 OPEN; certificate keeps the superseded AIR SHA; AEC edited to match the stale AIR | FV-01…FV-10 |

| Family | Count |
|---|---|
| SEM | 38 |
| CLM | 27 |
| CRT | 25 |
| RTE | 15 |
| SUR | 15 |
| SCP | 15 |
| MIG | 12 |
| AIR | 12 |
| REG | 10 |
| FRZ | 8 |
| FAR | 7 |
| AEC | 6 |
| EVT | 6 |
| AVS | 6 |
| HSH | 5 |
| ACN | 3 |
| FV | 10 |
| **Total** | **220** |

Result: **220/220 caught for the intended reason** (210 pre-existing, re-based on the corrected corpus, + 10 FV); 0 not applied; 0 caught for a wrong reason.

Controls: (a) the real corrected corpus passes all 17 validators, and the unmutated scratch base passes every validator; (b) the real certificate passes `cert` with status READY; (c) a scratch copy of this certificate with FV-P1-01 reopened, P1 = 1, G-30 FAIL and the status NOT READY passes `cert` (the status logic accepts a consistent NOT READY); (d) the real AIR and AEC pass `aeccount` (132 = 132); (e) the superseded AIR value 189 fails `aeccount` with `AIR_AEC_REGISTRY_COUNT_MISMATCH air=189 aec=132` (FV-01).

## 37. Findings Register

| ID | Severity | Status | Finding | Evidence | Remediation |
|---|---|---|---|---|---|
| FV-P1-01 | P1 | RESOLVED | Controlled AIR factual erratum: stale AEC active-registry count corrected from 189 to 132; AEC itself unchanged. (Original finding: AIR §16 reported "AEC registry codes (§5 L101–456) = 189"; AEC §5 declares and contains 132 active codes) | AEC L238 "Active codes: 132 (A 102, B 24, C 3, D 3)"; parsed §5 rows L101–L239 = 132; AIR L959 = 189. No reading reproduces 189: §5 rows 132; §5 code-shaped tokens 135; §5 ∪ §6.1 187; code-shaped first cells L101–L456 188; with literal casings 196. AEC (rank 7) governs AIR (rank 9). Severity policy lists "incorrect count" as P1. Resolution evidence: AEC active 132; AIR L959 "AEC §5 active registry codes" = 132; no contradictory 189 statement remains (§35); current V1 error gaps 0; AEC SHA-256 unchanged (§5); `aeccount` PASS | Applied: AIR §16 L959 relabelled and set to 132; AIR §1, §37, §37.1 record the erratum; the new AIR SHA-256 and line count are registered in §5 and G-01; all gates re-run (§38) |
| MO-FV-02 | minor | OPEN — non-blocking | AIR §18 "webhook deliver" density column not reproducible (§34) | at most 9/13 values reproduce; table declared non-specification | optional clarification at the next AIR revision |
| F-01 | minor | carried (AIR §37) | AMI-6D-021 envelope per AEC §12 | §34 | none required |
| F-02 | minor | carried (AIR §37) | SIP RT, no route | §34 | RT P9 + P18 |
| F-03 | minor | carried (AIR §37) | derived phases | §34 | none required |
| F-04 | minor | carried (AIR §37) | DEP-6C-12 → AIR-OD-01 | §34 | IR P8 |
| F-05 | minor | carried (AIR §37) | WS errors per AEC §13 | §34 | none required |
| F-06 | minor | carried (AIR §37) | old FUTURE numbering | §34 | governance sync |
| F-07 | minor | carried (AIR §37) | flags → AIR-OD-02 | §34 | RT |
| F-08 | minor | carried (AIR §37) | upstream ODDs | §34 | known future OD |
| F-09 | minor | carried (AIR §37) | Socket.IO vs raw WS | §34 | none required |
| F-10 | minor | carried (AIR §37) | `contact.erased` | §34 | none required |
| F-11 | minor | carried (AIR §37) | 6G merge outbox order | §34 | IR note |
| F-12 | minor | carried (AIR §37) | plugin audit async default | §34 | none required |
| F-13 | minor | carried (AIR §37) | `plugin.reactivated` | §34 | none required |
| F-14 | minor | carried (AIR §37) | DEGRADED→ACTIVE | §34 | none required |
| F-15 | minor | carried (AIR §37) | SUBSCRIPTION_CREATED sync wording | §34 | none required |
| F-16 | minor | carried (AIR §37) | AMI-6M-003 no event | §34 | none required |
| F-17 | minor | carried (AIR §37) | QUOTA_OVERRIDE_SET atomic | §34 | none required |
| F-18 | minor | carried (AIR §37) | 6C synchrony | §34 | none required |
| F-19 | minor | carried (AIR §37) | `data_subject_request` family | §34 | FUTURE |
| F-20 | minor | carried (AIR §37) | internal bus → DIRECT_REDIS_STREAM | §34 | none required |
| F-21 | minor | carried (AIR §37) | break-glass wording | §34 | none required |
| F-22 | minor | carried (AIR §37) | 6B L2052 superseded | §34 | governance sync |
| F-23 | minor | carried (AIR §37) | `campaign.started` → EVT-03 | §34 | none required |
| F-24 | minor | carried (AIR §37) | INTEGRATION_CONNECTION_CREATED sync | §34 | none required |

AIR §37.1 now lists 10 P0 and 7 P1 (the seventh P1 is FV-P1-01), all RESOLVED; none was reopened.

Remaining — P0: 0 · P1: 0 · minor: 25.

## 38. Final Freeze Candidate Gate

| Gate | Criterion | Expected | Observed | Status |
|---|---|---|---|---|
| G-01 | AIR SHA exact | 81dd63dc…54e2 | 81dd63dc…54e2 | PASS |
| G-02 | Phase-6 inventory complete | 19 | 19 | PASS |
| G-03 | HTTP/internal/callback routes | 369 | 369 | PASS |
| G-04 | WebSocket routes | 4 | 4 | PASS |
| G-05 | Callback routes | 5 | 5 | PASS |
| G-06 | Authorization orphans | 0 | 0 | PASS |
| G-07 | AEC route error gaps | 0 | 0 | PASS |
| G-08 | AVS gaps | 0 | 0 | PASS |
| G-09 | SQL migrations | 112 | 112 | PASS |
| G-10 | Alembic revisions | 112 | 112 | PASS |
| G-11 | Root revision | 001_5B | 001_5B | PASS |
| G-12 | Head revision | 112_5H5 | 112_5H5 | PASS |
| G-13 | Migration graph | linear, acyclic | linear, acyclic | PASS |
| G-14 | Migration 113 | absent | absent | PASS |
| G-15 | Transaction ambiguity | 0 | 0 | PASS |
| G-16 | Concurrency blockers | 0 | 0 | PASS |
| G-17 | Audit-action gaps | 0 | 0 | PASS |
| G-18 | EVENT_TRIGGER_UNRESOLVED = 0 | 0 | 0 | PASS |
| G-19 | CC-15 routes = producers | 77 | 77 | PASS |
| G-20 | AIR owner decisions preserved | 7 | 7 | PASS |
| G-21 | IR items | 21 | 21 | PASS |
| G-22 | RT items | 4 | 4 | PASS |
| G-23 | SIP classification | V1 RT | V1 RT | PASS |
| G-24 | Feature-flag classification | V1 RT | V1 RT | PASS |
| G-25 | FUTURE items | 83 | 83 | PASS |
| G-26 | FAR BLOCKER = 0 | 0 | 0 | PASS |
| G-27 | current owner decisions required = 0 | 0 | 0 | PASS |
| G-28 | minor-observation promotions = 0 | 0 | 0 | PASS |
| G-29 | P0 = 0 | 0 | 0 | PASS |
| G-30 | P1 = 0 | 0 | 0 | PASS |
| G-31 | Phase-7 gate PASS | PASS | PASS | PASS |
| G-32 | unapproved frozen-source modifications = 0 | 0 | 0 | PASS |
| G-33 | only the certificate created | 1 | 1 | PASS |

33 of 33 gates pass.

Blockers (complete list): none. FV-P1-01 is RESOLVED by the owner-approved controlled AIR erratum (§37) and G-30 passes after independent revalidation; P0 = 0, P1 = 0, current owner decisions required = 0, Phase-7 entry gate 14/14. G-33 refers to the original validation run (1 file created); the remediation created no file (§39). This certificate does not freeze or close Phase 6; that remains the owner's decision after independent freeze review.

## 39. Final Artifact State

| Item | Value |
|---|---|
| Certificate path | `docs/phase-06-api-design/PHASE-06-FINAL-VALIDATION-AND-FREEZE.md` |
| Certificate SHA-256 / line count | recorded in the owner report that accompanies this file; a file cannot contain its own hash |
| Method | full-project filesystem SHA-256 snapshot before writing, compared with a snapshot after writing (version-control directory excluded) |
| Files before / after (original validation) | 733 / 734 |
| Files added (original validation) | 1 (this certificate) |
| Files at remediation start / after remediation | 734 / 734 |
| Files modified by the remediation | 2 — AIR (controlled erratum FV-P1-01) and this certificate |
| Files added / deleted by the remediation | 0 / 0 |
| Owner-approved controlled AIR errata | 1 (FV-P1-01) |
| Unapproved frozen-source modifications: **0** | 19 of 20 hashes in §5 unchanged; AIR changed only by the approved erratum |
| Unexpected project-file changes | 0 |
| Scratch validators or broken copies in the project | 0 |
| Committed | no |

PHASE 6 FINAL VALIDATION = READY FOR INDEPENDENT FREEZE REVIEW
