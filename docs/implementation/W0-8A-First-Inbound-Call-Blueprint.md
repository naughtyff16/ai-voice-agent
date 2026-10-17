# W0 / 8A — First Real Single-Tenant Inbound Call Blueprint (Milestone M1)

| Field | Value |
|---|---|
| Wave | W0 plan for wave **W2** (milestone **M1**) |
| Date | 2026-10-16 (first submission); revised 2026-10-16 after the first independent review (P1-W0-01, -02, -04, -05; M-W0-01; NF-01); revised again 2026-10-16 after the second independent review (P1-R2-01, -02; M-R2-01 … -04); revised a third time after the third independent review (P1-R3-01, M-R3-01); revised a fourth time after the fourth independent review (P1-R4-01, M-R4-01, M-R4-02) — see [Review-resolution ledger](W0-8A-Review-Resolution-Ledger.md) |
| Status | Planning record for independent re-review. Nothing here is implemented, migrated, tested or provider-validated. |
| Sequence diagram | [Atlas A5](atlas/A5-inbound-call-sequence.mmd) ([SVG](atlas/A5-inbound-call-sequence.svg)) |
| Work packages | W2 rows of [Master Plan §9](W0-8A-Implementation-Master-Plan.md#9-backlog-w1--w6) |

## 1. The milestone, exactly

**One organization → one business phone number → one published AI agent version → one real provider-originated inbound call → a realtime Tamil-first conversation → a verified call outcome → authoritative persistence → measured evidence.**

M1 runs in a **non-production integration environment** with synthetic test organizations. It is not a production launch: AG-7K-08 gates any stack serving production, AB-7H-04 gates production use of the callback route, and every production gate stays closed (Register §3). M1 is **not** downgraded: it keeps crash-after-acknowledgement recovery of accepted callbacks (owner decision OD-W0-08).

Assumptions (implementation inputs, not provider decisions): one Exotel number; Deepgram STT and ElevenLabs TTS (frozen FR-STT-001, FR-TTS-001; Tamil capability **unverified**); one LLM chosen by the owner after FS-02 (OD-W0-03); a minimal Next.js call log; the D0 PostgreSQL/Redis foundation. **All four provider accounts and the managed cloud KMS are PENDING OWNER SETUP.**

## 2. Preconditions (the hidden dependencies, made explicit)

| # | Precondition | Why (frozen source) | Work package | State |
|---|---|---|---|---|
| P-1 | Tenant-scoped transactions and RLS-negative tests | `FORCE ROW LEVEL SECURITY` on `organization.current_tenant_id()` (001_5B; 010/011/015_5C) | W1-D2-01 | READY |
| P-2 | Login, sessions, RBAC with `call:read`, `agent:write`, `agent:publish` | 6B §8 – §13; 6D §25 | W1-D3-01 … -03 | After P-1 |
| P-3 | Outbox producer in the same transaction as the state change | 7D PTX-01 … -04; 6D §24 | W1-D4-01 | After P-1 |
| P-4 | Entitlements: `ACTIVE_AGENTS` usage quota (agent creation is DB-enforced, 111_5H4) and `CONCURRENT_CALLS` capacity quota (zero rows = refuse, 6K §54.3) | 6K §52, §54.2 – §54.3; 112_5H5 resolvers; quota rows written by `app_worker` on plan provisioning (052_5H), not by `app_platform_admin` (106_5H3 revoke) | W2-D3-06 | After P-2; blocker raised if the frozen provisioning path needs a payment call |
| P-5 | **Capacity authority on a durable PostgreSQL reservation relation** (W0-MR-01): Billing-owned, keyed by `call_session_id`, states `RESERVED` → `BOUND` → `RELEASED`, per-(organization, metric) serialization, idempotent acquire/release, fenced orphan sweep and reconciler, Billing guarded read of reservation state for Voice, fail closed (§3.3) | 6K §54.4 – §54.8; FAR-OD-04, -05; **OD-W0-09 (approved: A)** | W2-D2-03, W2-D3-06 | **BLOCKED — migration authoring authorization (OD-W0-12)** |
| P-6 | Published agent version, `language_policy` primary `ta-IN` | 6D §8 – §9; 6E §12; 4I §4.2 | W2-D7-01 | After P-2, P-4 |
| P-7 | The agent's prompt text (no V1 prompt route; `prompt.prompt_versions` exists) | 6D §8.2; AIR §24, §30 | W2-D7-02 | **BLOCKED — OD-W0-02** |
| P-8 | Phone-number row (out-of-band, DEP-6D-07) assigned to the agent | 6D §19 | W2-D7-01 | After P-6; inserted as `app_api` under tenant context |
| P-9 | **G-02 extended** (accumulator, guard, marker, checkpoint row and function) | 7L §31 P9; §34.6.3 | W2-D2-01 | **BLOCKED — OD-W0-01** |
| P-10 | **Durable callback processing input and receipt recovery: MR-7H-09** (7L G-07 part) with **7I IR-08** (receipt-and-input function; no table privilege on inputs) and **IR-23** (`FAILED` input 7-day diagnostic retention) | 7H CBK-04, -09, -10, -15 … -21, §17.3; 7I CBI-01 … -14; **OD-W0-08 (approved: A1)** | W2-D2-02 | **BLOCKED — OD-W0-12** |
| P-11 | **Envelope encryption key service for purpose `CALLBACK_INPUT`** on a managed cloud KMS (7I IR-18 for this purpose): per-organization KEK, non-production root keys separate from production (KEY-05), ingress generate-only / processing decrypt-only (KEY-08), rotation (KEY-09, -10) | 7I §12.1 KEY-01 … -11; CBI-03, -04; OD-W0-08 | W2-D9-04 | **BLOCKED — OD-W0-13 (KMS vendor, account, India region) and owner provisioning** |
| P-12 | **Voice-owned inbound provider-call identity relation** (W0-MR-02): `UNIQUE (organization_id, provider_slug, provider_call_ref)`, bound to one `call_session_id`, across `started_at` partitions; states `PENDING` → `BOUND` → `CLOSED`, `PENDING` → `REFUSED` / `ABANDONED`, terminal states immutable; Voice guarded read of setup state for the Billing reconciler (§3.3) | NF-01: `voice.call_sessions.provider_call_ref` has only a non-unique index (011_5C L56) and the table is partitioned by `started_at` (PK `(id, started_at)`); 7H CBK-09 requires domain-owned idempotency; **OD-W0-11 (approved: A)** | W2-D2-04, W2-D6-02 | **BLOCKED — OD-W0-12** |
| P-13 | Provider accounts; Exotel number routed to a media-streaming flow; Exotel's callback signature scheme and stable call identifier confirmed | Owner decision OD-W0-R2; 7H CBK-02, -14 | Owner; FS-01 | **PENDING OWNER SETUP** |
| P-14 | Public HTTPS/WSS endpoint for Exotel | Provider traffic is inbound | W2-D10-01 | **BLOCKED — OD-W0-04** |
| P-15 | DEP-6D-05 call-lifecycle timer values; the setup grace period of 6K §54.5 rule 8 and the callback stale thresholds (runtime configuration, not contract values) | 6D §11; 6K §54.5 rule 8; 7H CBK-10 | W2-D6-08, W2-D3-06 | Dev defaults configurable; **owner values before M1 acceptance (OD-W0-06)** |

Not required for M1: the relay and every consumer (no logical stream is admitted; Voice rows stay `PENDING`); the 7G recovery ledger (no consumer runs); compliance policy (6D §20.3: outbound only); recordings (AG-7L-09); internal service tokens (no internal HTTP route on the inbound path).

## 3. The call, step by step

Transaction boundaries follow 6A §35 and 7H §17.2: no transaction spans provider, KMS or network I/O (PER-01); ingress (TX-7) never contains domain processing; processing (TX-8) never contains provider calls.

### 3.1 Callback ingress — the fast acknowledgement (7H §11.2, CBK-01 … -05, -11 … -17; 7I CBI-01 … -05; 6J §24.4)

| # | Step | Writes | Failure behaviour |
|---|---|---|---|
| I-1 | Size and rate guards (6J §24.4, §24.6) | None | Rejected; nothing written |
| I-2 | Retain the exact raw request bytes | None | — |
| I-3 | Routing lookup: which provider credential could verify this | None | — |
| I-4 | **Verify the provider signature over the raw bytes** (CBK-02) | None | Invalid, tampered, unsigned or replayed outside the provider's window: **reject, zero rows written, no processing** (CBK-01). If Exotel offers no verifiable signature, FS-01 raises a feasibility blocker; the route is not built without verification |
| I-5 | Resolve the organization **from platform-held state** (`voice.resolve_inbound_phone_number(to)`, 015_5C, SECURITY DEFINER) — never from a payload field, query parameter or header (CBK-03, -08) | None | Unknown, inactive or inbound-disabled number: reject; nothing written |
| I-6 | Derive `provider_event_id` (provider-native; else SHA-256 of `provider_slug || "." || verified bytes`); **allocate the receipt identifier `R`** (UUIDv7) in the ingress process | None | — |
| I-7 | **Extract the processing input** from the verified bytes only: the closed, versioned Voice schema (normalized event kind, provider call reference, provider timestamps, coded states, numeric measures; the two numbers of the inbound call only because admission needs them, CBI-02); bounded size ([REC] 8 KB); CPU only, no I/O | None | **Extraction fails (signed but malformed): go to I-8m.** No KMS call is made and no input exists |
| I-8m | **Receipt-only `FAILED` commit** (TX-7; CBK-17; 6J §24.4): one transaction, tenant context of I-5, guarded receipt function inserts the receipt with identifier `R`, status `FAILED` and a category code, `ON CONFLICT DO NOTHING`; no processing input row | Receipt only | Commit fails: 5xx, nothing stored. Then I-9: the 2xx here means "durably received and recorded as not processable"; nothing is owed, nothing is processed or retried. This differs from an **invalid signature**, which writes zero rows (I-4) |
| I-8a | Obtain a wrapped data key from the KMS (generate-only, KEY-08) and encrypt the whole input with AES-256-GCM or equivalent; associated data = purpose `CALLBACK_INPUT`, the organization resolved in I-5, **receipt identifier `R`**, schema version (KEY-01 … -03). This happens **before** any transaction is opened (6A §35; PER-01) | None | KMS unavailable or encryption fails: **no commit, 5xx** (CBI-05); the provider's own retry is the recovery |
| I-8b | **One transaction**, tenant context of I-5, through the guarded receipt-and-input function (IR-08): `INSERT` receipt with id `R` `ON CONFLICT (organization_id, provider_slug, provider_event_id) DO NOTHING RETURNING id`; **only if that statement returned exactly `R`**, insert the encrypted input keyed by `R` (primary key = receipt id, write-once), storing the associated-data fields with it | Receipt; encrypted input | Duplicate: no row returned, the pre-allocated `R` and its ciphertext are discarded unused, nothing is overwritten (CBK-11, -16). Commit fails: 5xx, nothing stored |
| I-9 | **Respond 2xx — identical for a new event and an authenticated duplicate.** For a receipt with an input it means "receipt and processing input durably stored", not "processed" (CBK-05) | None | — |
| I-10 | Hand a wake-up hint to the processing worker | Optional hint | Losing the hint loses nothing (CBK-04) |

**Why the associated data cannot be substituted (M-R2-02).** `R` is generated by the ingress process, never read from the payload. The guarded function writes the input only under the receipt row it has just inserted with that same `R`, in the tenant context the function itself checks against `organization.current_tenant_id()`. Processing rebuilds the associated data from the stored row (purpose, the row's `organization_id`, the row's receipt id, schema version) and decrypts; a ciphertext copied to another receipt, organization or purpose fails AEAD authentication (KEY-02). A duplicate never reaches the input insert, so an existing input is never overwritten.

**Authenticated duplicate** (provider retry of an accepted event): I-8b returns no row; the first stored input stands; same 2xx; no second processing. **Invalid signature**: rejected at I-4 with zero writes. **Signed but malformed**: I-8m, a durable `FAILED` receipt and a 2xx. These are three evidence cases (E-02a, E-02b, E-02d).

### 3.2 Callback processing — fenced claims and one transaction per receipt (CBK-06, -09, -10, -17, -18, -21, -22; TX-8; CBI-06, -08 … -12; MR-7H-09 (b) – (d); IR-08, IR-23)

**Invariant CBP-1 (completion).** A receipt reaches `PROCESSED` or `SKIPPED`, and its processing input is deleted, **only in the transaction that commits every owner effect that receipt is owed** — session, identity binding, conversation, `conversation_id` reference and outbox rows as applicable (CBK-18; CBI-09). There is no transaction in which a receipt becomes `PROCESSED` or `SKIPPED` before its effects, so no recovery from a terminal receipt is ever needed or claimed.

**Invariant CBP-2 (failure).** A receipt that **had** an extracted input reaches `FAILED` only in a fenced transaction (P-1 exhaustion or P-4 deterministic failure) that commits **no normal callback business effect**: no session, conversation, `conversation_id`, call-state transition, outbox row, capacity reservation or usage. The **only** permitted companion write is the **setup disposition** defined here: an identity whose **origin receipt** is this receipt and whose state is still `PENDING` moves to `ABANDONED` in the same transaction. An identity that is `BOUND`, `CLOSED`, `REFUSED` or `ABANDONED`, or that another receipt created, is **not** touched — in particular a bound call is never abandoned because its end callback exhausted its attempts; such a call is ended by the stale-session reaper on the abnormal-end path (§3.5 F-2). The encrypted input is **retained** for diagnosis for at most 7 days from the terminal transition, then erased promptly by the maintenance principal; earlier under an erasure that is due; later only under a recorded hold (CBK-18; CBI-10, -11; IR-23). A receipt-only `FAILED` (signed but malformed, §3.1 I-8m) never had an input and involves no KMS operation (CBK-17). The two kinds of `FAILED` are never conflated: the first is reached only from `PROCESSING`, the second only at ingress.

**Claim record (part of MR-7H-09; physical names are the governed migration's).** One record per receipt, written only by guarded functions (`app_api` and `app_worker` hold no `UPDATE` on receipts, 062_5I): `claim_epoch` (integer, 0 at ingress), `claimed_by` (worker identity), `claimed_at` and `lease_expires_at` (both from `clock_timestamp()` read inside the guarded function — database time is the only time authority; `DEFAULT NOW()` is not used because it is the transaction start), `attempt_count`, `last_failure_category`. **`claim_epoch` is incremented on exactly three paths and no other: an initial claim, a recovery claim, and the exhaustion fence.** Completion, deterministic failure, yield, a lost claim and a no-op never change it. The frozen `webhooks.fn_update_inbound_event_status` (062_5I) is not a claim, allows `FAILED → PROCESSING`, and is revoked from runtime roles once superseded (7I IR-08). Each identity (W0-MR-02) records its **origin receipt** (the receipt whose processing created it; a logical ID reference, 5A §2.2).

**Receipt state machine (statuses are the frozen `chk_iwe_status` set; nothing is added).** Every row below is decided **inside** a tenant-scoped guarded function under the receipt row lock (`FOR UPDATE`), from the stored status, epoch, lease and attempts; none of these values crosses the tenant boundary.

| From | To | Only through | Predicate evaluated under the receipt row lock | Effect on input | Attempts / epoch |
|---|---|---|---|---|---|
| (none) | `RECEIVED` | Ingress receipt-and-input function (§3.1 I-8b) | Receipt with id `R` newly inserted | Input written once | 0 / 0 |
| (none) | `FAILED` (receipt-only) | Ingress receipt-only function (§3.1 I-8m) | Newly inserted | None ever existed | 0 / 0 |
| `RECEIVED` | `PROCESSING` | **Claim-or-recover** (P-1), outcome `CLAIMED` | `status = 'RECEIVED'` | Returned to this caller only | `= 1` / **+ 1** |
| `PROCESSING` | `PROCESSING` | **Claim-or-recover** (P-1), outcome `RECOVERED` | `status = 'PROCESSING' AND lease_expires_at < clock_timestamp() AND attempt_count < max_attempts` | Returned to this caller only | **+ 1** / **+ 1** |
| `PROCESSING` | `FAILED` | **Claim-or-recover** (P-1), outcome `EXHAUSTED` — the exhaustion fence | `status = 'PROCESSING' AND lease_expires_at < clock_timestamp() AND attempt_count >= max_attempts` | Retained ≤ 7 days (CBP-2) | unchanged / **+ 1** (fences the last holder) |
| any other | unchanged | **Claim-or-recover** (P-1), outcome `NOT_AVAILABLE` | Lease not expired, terminal status, wrong tenant, or no such receipt | Nothing returned | unchanged / unchanged |
| `PROCESSING` | `PROCESSED` / `SKIPPED` | **Completion** (P-3, TX-8) | `status = 'PROCESSING' AND claim_epoch = :my_epoch` | Deleted in the same transaction (CBP-1) | unchanged / unchanged |
| `PROCESSING` | `FAILED` | **Deterministic failure** (P-4) | `status = 'PROCESSING' AND claim_epoch = :my_epoch` | Retained ≤ 7 days (CBP-2) | unchanged / unchanged |
| `PROCESSING` | `PROCESSING` (lease shortened) | **Yield** (P-4, transient) | `status = 'PROCESSING' AND claim_epoch = :my_epoch` | Unchanged | unchanged / unchanged — a yield never resets attempts or status |
| `PROCESSED`, `SKIPPED`, `FAILED` | anything | — | Rejected by the guarded functions and by a transition trigger | — | — |

There is **no** transition back to `RECEIVED`, so no reset can restart the attempt count; every initial or recovery claim consumes an attempt; `max_attempts`, the lease length and the backoff are Voice-set runtime values (OD-W0-06).

| # | Step | Transaction | Notes |
|---|---|---|---|
| P-0 | **Discovery** (MR-7H-09 (d); CBI-08): a guarded cross-tenant function returns **exactly two columns, `receipt_id` and `organization_id`**, for receipts `RECEIVED` longer than the hint delay or `PROCESSING` with an expired lease (both evaluated inside the function with `clock_timestamp()`). It returns no status, epoch, lease, attempt count, ciphertext, provider fact or any other field | Read | Executable by the Voice processing principal only; its result type has exactly those two columns |
| P-1 | **Claim-or-recover, one short transaction per receipt**: the worker sets that receipt's organization as transaction-local tenant context (one tenant per transaction) and calls the tenant-scoped guarded function with **only `receipt_id`**. The function verifies `organization.current_tenant_id()` equals the receipt's organization, locks the receipt row, and decides internally per the table above. **`CLAIMED` / `RECOVERED`**: sets `claimed_by`, `claimed_at`, `lease_expires_at`, increments attempts and epoch, and returns the **new epoch** and the encrypted input, wrapped key, KEK reference and version, nonce and associated-data fields — to this caller only. **`EXHAUSTED`**: sets `FAILED` with category `ATTEMPTS_EXHAUSTED`, increments the epoch, returns no input; **in the same transaction** the worker applies the CBP-2 setup disposition (lock identities whose origin receipt is `R`; `PENDING → ABANDONED`; any other state untouched). **`NOT_AVAILABLE`**: nothing changes and nothing is returned. Commit before any I/O | One short transaction | The input relation has no table privilege for any role (CBI-06, IR-08); this function is the only read path; there is no tenant or platform-admin read (CBI-12) |
| P-2 | Decrypt in the processing workload's memory (decrypt-only permission, KEY-08); never logged or traced. **No transaction is open** | — | KMS unavailable → P-4 yield |
| P-2a | Before any Billing call for this receipt, the worker calls a tenant-scoped guarded check that returns only whether `status = 'PROCESSING' AND claim_epoch = :my_epoch` still holds, and stops if not | Read | Narrows, but does not replace, the TX-8 fence |
| P-3 | **TX-8, one transaction**: **first** lock the receipt row `FOR UPDATE` and require `status = 'PROCESSING' AND claim_epoch = :my_epoch`; if not, roll back with category `LOST_CLAIM` and write nothing. Then run the Voice command — §3.3 T2 (identity lock, setup fence, reservation revalidation, session, conversation, reference, EV-073, EV-074), or the end fact (§3.5 F-1), or the answer fact (§3.3 A-4) — and set `PROCESSED` (or `SKIPPED`) and delete the input | One transaction | CBP-1 |
| P-4 | Deterministic rejection → `SKIPPED` (owner effects of a skip, e.g. identity `ABANDONED`, in the same transaction) or `FAILED` (CBP-2: no business effect, only the setup disposition; input retained), both behind the same epoch fence as P-3. Transient failure (KMS, capacity authority `UNAVAILABLE`, lock timeout, database error) → roll back; optionally **yield** (shorten the lease, same epoch, attempts unchanged) so recovery can start sooner | One transaction | — |
| P-5 | **Re-dispatch**: each `(receipt_id, organization_id)` pair from P-0 is sent to P-1, which alone decides claim, recovery, exhaustion or no-op | — | No decision is taken from discovery output |

**Lock order.** Receipt row → identity row → setup fence → (Billing guarded read) → Voice rows. Billing transactions never lock receipt or identity rows (§3.3), so there is no cycle.

**Why a displaced worker cannot commit.** P-1 and P-3 lock the same receipt row. If a recovery (or the exhaustion fence) commits first, it has incremented `claim_epoch`; the old worker's P-3 then reads a different epoch and rolls back with nothing written. If the old worker's P-3 holds the row lock first, P-1 waits and, after the commit, finds a terminal status and returns `NOT_AVAILABLE`. Matching `status = 'PROCESSING'` alone is never sufficient. An expired lease by itself does not invalidate a holder; only a committed recovery or exhaustion does, so a slow worker that finishes before anyone re-claims completes normally. Because P-1 decides from the values it reads under its own lock, a stale view held by the caller cannot matter: the caller never supplies a status, epoch or lease.

**Stale worker and Billing.** A displaced worker that already passed P-2a may still call T1 once. That can only create or find a reservation for the same `call_session_id` (one identity per provider call): `ALREADY_HELD` if live, or a new `RESERVED` row if the call has meanwhile ended. Its P-3 then fails the epoch fence, and T4 releases such a reservation at once because Voice setup state is `SESSION_TERMINAL` or the identity is terminal. The effect is a bounded under-admission (until the reconciler's next run), **never** an over-admission, and no session.

**Crash and race windows (each is a planned PG-FAULT test in E-15b; NOT EXECUTED; assertions in §4).**

| # | Situation | Outcome |
|---|---|---|
| R-1 | New receipt, hint lost | P-0 returns `(R, org)`; P-1 → `CLAIMED` (epoch 1); completes once |
| R-2 | W1 claims (epoch 1), is killed before P-3 | After lease expiry P-0 returns `(R, org)`; W2's P-1 → `RECOVERED` (epoch 2, attempt 2), loads the input, completes once |
| R-3 | W1 claims, pauses before P-3; lease expires; W2's P-1 → `RECOVERED` (epoch 2); W1 resumes | W1's P-3 reads epoch 2 ≠ 1 → rollback, nothing written; W2 completes; at most one EV-073 and one EV-074 for an answered call, one terminal effect for an end fact |
| R-4 | W1 is inside P-3 holding the receipt lock when W2 calls P-1 | W2 waits, then sees a terminal status → `NOT_AVAILABLE`; W1's commit stands |
| R-5 | Two workers call P-1 for the same expired receipt | The row lock serializes them; the first gets `RECOVERED` (new epoch, new lease); the second then sees an unexpired lease → `NOT_AVAILABLE` |
| R-6 | Receipt `PROCESSED` before a scheduled P-1 runs | `NOT_AVAILABLE`; nothing happens |
| R-7 | KMS unavailable at P-2 | Yield; recovery later; attempts counted; at the limit `EXHAUSTED`, input retained (CBP-2) |
| R-8 | Database unavailable | No transition happens; leases are evaluated in database time when it returns; owed work is kept (never deleted by age while non-terminal, CBI-11) |
| R-9 | `max_attempts` reached on an **incoming-call** receipt whose identity (origin = `R`) is `PENDING` | P-1 → `EXHAUSTED`: receipt `FAILED`, epoch + 1 (any late holder is fenced), identity `ABANDONED` in the same transaction; input retained ≤ 7 days, then erased |
| R-9b | `max_attempts` reached on an **end-of-call** receipt for a call whose identity is `BOUND` | P-1 → `EXHAUSTED`: receipt `FAILED`, epoch + 1; identity **unchanged** (`BOUND`), session unchanged; the stale-session reaper later ends the call on the abnormal path (§3.5 F-2) |
| R-10 | Wrong tenant context or a non-processing principal calls P-1 or the P-2a check | `NOT_AVAILABLE` / no row; no input; `SELECT` on the input relation denied for every role |
| R-11 | Discovery output inspected | Exactly `receipt_id` and `organization_id`; nothing else, for any receipt state |

**Timeliness (CBK-22).** Recovery restores **facts**, not **timeliness**. A recovered "call ended" still closes the session, releases capacity and is accounted. A recovered "incoming call" whose provider call has already ended is `SKIPPED` and its identity becomes `ABANDONED`; it is never admitted late. The Voice command decides from current state whether a late fact still applies.

**Frozen compatibility.** MR-7H-09 (b) names a guarded claim `RECEIVED → PROCESSING` that "reports whether the caller won, records when processing started and counts processing attempts"; (d) requires a guarded cross-tenant discovery "returning identifiers only (receipt ID, `organization_id`)" for receipts stale in `RECEIVED` **or** `PROCESSING`; CBI-08 repeats "identifiers only"; CBK-10 requires that a re-dispatched stale receipt be processed from its stored input; CBI-06 allows the input to be returned "only by the guarded processing claim, to the caller that won the claim". P-0 now returns exactly those two identifiers; the tenant-scoped claim-or-recover function, the epoch and the lease are the physical form of the remaining requirements and are **not** a new behaviour, so no 7H or 7I amendment is needed. They are part of the MR-7H-09 / IR-08 migration whose authoring waits for **OD-W0-12** (**PENDING OWNER ACT**); production use of the route stays gated by AB-7H-04.

### 3.3 Inbound admission — linearization and fencing protocol (4B §14.1; 6K §54.3 – §54.8; FAR-OD-04, -05; 6A §17.3, §35; 7H CBK-09; OD-W0-09, -11)

**Constraint that shapes the protocol.** 6A §35 allows same-transaction atomicity across aggregates only for the fixed 4G §12 list, which includes "Start Call + Conversation" and does **not** include a Billing capacity reservation. So the Billing reservation and the Voice session are never written in one transaction. Safety instead comes from three frozen-compatible mechanisms, all inside guarded database functions (6A §17.3):

1. **Billing alone writes reservations**, through its guarded functions; Voice holds `EXECUTE` on them and no table privilege (owner boundary preserved; W0-MR-01).
2. **Cross-context guarded reads**, as frozen precedent already does in both directions: Voice reads a Billing fact inside its own transaction (111_5H4: `voice.fn_assert_agent_quota_admission` calls `billing.fn_resolve_effective_quota`), and the Billing reconciler reads authoritative Voice call and dispatch state (6K §54.5 rule 8).
3. **One setup fence per call**: a transaction-scoped advisory lock on the key `capacity.setup:<call_session_id>`, taken as the **first** statement-level action of every guarded function that can create a session for that call or release its reservation, and held until that transaction ends. Advisory locks are used here only to serialize; uniqueness and capacity are enforced by constraints and by Billing's counted check (OD-W0-11 forbids relying on advisory locks alone for deduplication, and this design does not).

**Durable states.** *Provider-call identity* (Voice, W0-MR-02; unique `(organization_id, provider_slug, provider_call_ref)`, non-partitioned): `PENDING` → `BOUND` → `CLOSED`; `PENDING` → `REFUSED`; `PENDING` → `ABANDONED`. `REFUSED`, `ABANDONED`, `CLOSED` are terminal; no edge leaves them, and an attempted transition out of a terminal state is rejected by a trigger. *Reservation* (Billing, W0-MR-01, one row per `call_session_id` per admission generation): `RESERVED` → `BOUND` → `RELEASED`, or `RESERVED` → `RELEASED`; `RELEASED` is terminal; a later admission of the same `call_session_id` creates a new generation.

| # | Transaction (context) | Exact content | Commit makes true |
|---|---|---|---|
| T0 | Voice — identity claim | `INSERT` identity `ON CONFLICT DO NOTHING` with a new `call_session_id`; read the row. Terminal state → no admission (the receipt is `SKIPPED` in its P-3 transaction); `BOUND` → no admission (duplicate; continue with the facts that apply to a bound call) | One identity and one `call_session_id` per provider call, across all `call_sessions` partitions |
| T1 | Billing — `AcquireCapacity(org, CONCURRENT_CALLS, call_session_id)` | Fence lock; lock the (organization, metric) pool row `FOR UPDATE` (created on first use with `INSERT … ON CONFLICT DO NOTHING`, then locked); resolve the effective limit with `billing.fn_resolve_effective_capacity_quota` (zero rows → `REFUSED_NOT_CONFIGURED`); a live generation for the ID → `ALREADY_HELD`; else count `RESERVED` + `BOUND` reservations of the pool and admit iff `(occupied + 1) <= hard_limit` compared as stored (NULL = uncapped, still recorded); insert `RESERVED` | A reservation that every later acquisition counts; or a refusal that writes nothing |
| T2 | Voice — **admit and start** (the P-3 transaction) | **Receipt epoch fence first** (lock the receipt row, require `status = 'PROCESSING' AND claim_epoch = :my_epoch`, §3.2 P-3); then lock the identity row `FOR UPDATE` and require `PENDING`; setup fence lock; **revalidate** through the Billing guarded read `capacity_reservation_state(call_session_id)` and require `RESERVED` or `BOUND` (a statement issued after the fence lock, so under `READ COMMITTED` it sees every commit of a release that held the fence); insert `call_sessions`; if the incoming fact is also the provider's answer fact (FS-01 decides), create the conversation, set `call_sessions.conversation_id`, write EV-073 and EV-074 (6D §23.4, approved "Start Call + Conversation" exception); identity `BOUND`; receipt `PROCESSED`; delete input | The session exists **only** with a live reservation; the receipt is terminal only with all its effects |
| T2-fail | Voice | If revalidation finds no live reservation: roll back everything; the worker runs **a new T1** (a new admission). `ADMITTED` → retry T2; `REFUSED_*` → T3 | No session is ever created on a released reservation |
| T3 | Voice — refusal | **Receipt epoch fence first** (§3.2 P-3); then lock the identity row `FOR UPDATE` and require `PENDING` (if a parallel retry has meanwhile admitted the call, the identity is `BOUND` and T3 changes nothing but the receipt's terminal state); identity `PENDING → REFUSED`; receipt `PROCESSED`; input deleted; one transaction. Then, outside any transaction, the provider-facing decline (§3.3 note) | A refused provider call can never later start a session |
| T4 | Billing — reconciler (6K §54.5 rule 8), per candidate reservation | Fence lock; lock pool row, then the reservation row; **then** (new statement) read Voice's guarded `capacity_setup_state(call_session_id)` ∈ {`SESSION_NON_TERMINAL`, `SESSION_TERMINAL`, `NO_SESSION_ADMISSION_OWED`, `NO_SESSION_ABANDONED_OR_REFUSED`, `NO_IDENTITY`}. Release iff `SESSION_TERMINAL`; or `NO_SESSION_ABANDONED_OR_REFUSED`; or (`NO_SESSION_ADMISSION_OWED` or `NO_IDENTITY`) **and** the reservation's database-time age exceeds the setup grace; **never** for `SESSION_NON_TERMINAL`; **never** while an outbound dispatch is `SUBMITTING` / `AMBIGUOUS` (W4). Mark `RESERVED` with a non-terminal session `BOUND` | No reservation is released while a session for it could still be committed with it |
| T5 | Voice then Billing — normal release | Terminal transition (P-3 of the end fact) commits first; then `ReleaseCapacity` (fence lock, pool lock, `BOUND → RELEASED`, idempotent `NOT_HELD`) | Release exactly once; if the release is lost, T4 releases it (`SESSION_TERMINAL`) |

**Why no over-admission is possible.** Billing counts every `RESERVED` and `BOUND` row under the pool lock, so the number of live reservations never exceeds the limit. A session is inserted only inside T2, after a revalidation made under the fence lock; every release (T4, T5, a setup-failure release) holds the same fence lock for its whole transaction and re-reads Voice state after taking it. Therefore either the release commits first (T2's revalidation sees `RELEASED`, T2 rolls back, a new admission is required) or T2 commits first (the release's later read sees `SESSION_NON_TERMINAL` and does nothing). A non-terminal session therefore always has a live reservation. A worker's earlier `ALREADY_HELD` answer is never trusted at commit time.

**In-flight versus abandoned.** The durable owed-work signal is the identity row in `PENDING` whose receipt is not terminal. The reconciler does not release such a reservation before the grace has passed (it is owed work); after the grace it may release it, which is safe because of the fence — the setup then needs a new admission and may be refused. A setup whose receipt has ended `FAILED`, or whose identity is `REFUSED` or `ABANDONED`, is released without waiting. Process memory and unfenced counts play no part.

**Lock order (no cycle).** Voice transactions: receipt row (epoch fence, §3.2) → identity row → setup fence → (Billing read, no row lock) → Voice rows. Billing transactions: fence → pool row → reservation row → (Voice read, no row lock). A transaction never takes a lock of the other context's rows.

**Other rules kept.** One organization pool for inbound and outbound (FAR-OD-05; outbound joins it in W4 through the same T1/T4 functions). Store or resolver unreachable → `UNAVAILABLE` → fail closed (T2 is never attempted); the receipt stays for the sweep and its attempts are bounded, ending `ABANDONED` with the receipt `FAILED`. Database restart: advisory locks end with their transactions; every state above is durable, and recovery resumes from it.

**Answer fact arriving separately (A-4).** If FS-01 shows the answer is a later, separate provider event, T2 creates the session without a conversation, and the answer event's own P-3 transaction creates the conversation, sets `conversation_id`, writes EV-073 and EV-074, and terminalizes that receipt, guarded by the session state compare-and-set. An answer fact whose identity is still `PENDING` is a transient failure (left to the sweep, bounded); one whose identity is `REFUSED` or `ABANDONED` is `SKIPPED`.

**Provider-facing decline.** After the 2xx, the platform can no longer answer in that HTTP response. A decline is a separate `TelephonyPort` control operation (for example rejecting or hanging up the provider call) **only if FS-01 verifies that Exotel supports one**; otherwise the platform does not accept the media stream for that call (closes it) and the missing decline capability is a named FS-01 feasibility blocker for 6K §54.6. It is never a synchronous wait before the callback acknowledgement.

**Crash and race windows (each is a test in E-16; observable assertions in SQL).**

| Window | Durable state left | Recovery | Assertion |
|---|---|---|---|
| After T0 | Identity `PENDING`; receipt `PROCESSING` | Sweep → P-1 → T0 finds the same `call_session_id` | One identity row per provider call |
| After T1 (`ADMITTED`) | Reservation `RESERVED`; no session | Retry → `ALREADY_HELD` → T2; or after the grace T4 releases and the retry re-admits | `count(live reservations) <= hard_limit` at every instant |
| Inside T2 (killed before commit) | As after T1 | Same as above | No session, conversation, outbox row, terminal receipt or input deletion from the killed attempt |
| After T2 | Session, (conversation, reference, EV-073, EV-074), identity `BOUND`, receipt `PROCESSED`, input gone | Nothing owed | Exactly one session and, if answered, exactly one conversation with `call_sessions.conversation_id` equal to it; one EV-073 and one EV-074 |
| T3 killed | Identity `PENDING` | Retry: a new T1 may admit if capacity was freed (CBK-22 decides whether the fact still applies) | Never a session for a `REFUSED` identity |
| T5 lost after the terminal commit | Session terminal; reservation `BOUND` | T4 releases (`SESSION_TERMINAL`) | Release exactly once (`NOT_HELD` on repeat) |
| Store `UNAVAILABLE` | Identity `PENDING` | Bounded retries, then `ABANDONED` + receipt `FAILED` | No session without a reservation |

### 3.4 Media and the turn loop

| # | Step | Contract | Failure behaviour |
|---|---|---|---|
| M-1 | Exotel opens the media WebSocket; the gateway binds it to the admitted session by call-setup correlation (6D §10.4), waiting a bounded time for admission to commit if the socket arrives first | 3B §8, §17; FS-01 decides the correlation token | No admitted session within the bound, or bad correlation: close the socket; nothing created |
| M-2 | Turn loop: VAD → streaming STT → LLM stream → sentence splitter → streaming TTS → audio out; no REST, no event bus, no synchronous Billing/CRM/Analytics write on the hot path | 6D §21.5, §21.11 | Provider failure per 3B §19; all providers open → call `FAILED` (6D §21.9) |
| M-3 | Per-turn checkpoint (validated usage; `checkpoint_at = GREATEST(clock_timestamp(), previous)` read after the totals) and final transcript segment | CKP-7L-01 … -09; 6D §17.2 | Checkpoint fails: that turn is never billed (RR-7L-C1) |
| M-4 | Barge-in: caller speech during playback cancels TTS and LLM, drops queued audio | 6D §14; DEP-6D-08 | No stale audio after cancel (6D §14.3) |

### 3.5 Call end, release and accounting finalization (AP-7L-27 (i) – (iii); 7B OCC-01 … -07; 7L §34.6.3)

| # | Path | Service-end time (`EV-079.occurred_at`) | Totals | Writes |
|---|---|---|---|---|
| F-1 | **Normal end** (verified provider hang-up or completion fact, processed through §3.2) | The authoritative service-end time **persisted at normal call end**, in the transaction that commits the terminal state (OCC-02); later reused verbatim | The committed accumulator totals (CKP-7L-10: no billable time beyond what checkpoints prove) | Terminal state, persisted service-end, outbox **EV-005 `call.ended`** or **EV-006 `call.failed`**, identity `BOUND → CLOSED`, receipt terminal, input deleted — one transaction (CBP-1) |
| F-2 | **Abnormal end** (process death, socket loss, or end forced by the stale-session reaper) | The `checkpoint_at` of the **last validated, durably committed checkpoint** (§34.6.3 cell 3; CKP-7L-11) | That checkpoint's totals | Terminal state via the reaper (3B §18.2) |
| F-3 | Either path: `ReleaseCapacity(call_session_id)` | — | — | Reservation released once; reconciler backstop |
| F-4 | Shared atomic finalization (normal finalizer worker; reaper/recovery worker on F-2), serialized with checkpoints by the conversation accounting row lock (CKP-7L-06): claim the guard, read the persisted service-end and totals, insert **EV-079 `conversation.completed`** once | As F-1 / F-2 — **never** the worker's or reaper's clock, Redis delivery or relay time (OCC-04; CKP-7L-08, -09) | As F-1 / F-2 | Guard + outbox row |
| F-5 | Service-end missing or corrupt (normal path), or no checkpoint / invalid checkpoint (abnormal path) | None | None | `CORRUPT_STATE`, `RECONCILIATION_REQUIRED` marker, **no EV-079, no usage, no estimate** (OCC-05; CKP-7L-12); repair stays closed (AG-7L-04) |

**Billing-period boundary.** `EV-079.occurred_at` is the `occurred_at` of every usage row Billing derives (OCC-01), so the whole conversation is attributed to the period containing its service-end time, deterministically on retry or re-read (OCC-06). Usage arriving after that period closed is handled only by 6K's late-usage adjustment path, which leaves the original invoice unchanged (6K; `fn_create_late_usage_billing_adjustment`, 102_5H2). **In M1 none of this runs:** CON-06 is not built and no usage row is written.

**Events produced and where they stop.** EV-073, EV-074, EV-005 or EV-006, and EV-079 are written to `audit.domain_event_outbox` and stay `PENDING`; LS-D-VOX owes six groups (CON-04, -05, -06, -07, -08, -10, 7E §29.3) and is not admitted, so nothing claims them in any environment (owner decisions; SPA-7L-02, -10). EV-004 has only an outbound producer (7B); the inbound path does not emit it (7L HND-7L-02 if that changes). 3B §6.1's direct `publish call.started` is superseded by the outbox and AB-7H-03 (HND-7L-01).

### 3.6 Read access

`GET /api/v1/calls`, `GET /calls/{id}` need `call:read`; transcript content needs `transcript:access_content` (6D §17.4); `summary_text` follows AP-7L-43 (a) as a design input. A resource of another organization is `RESOURCE_NOT_FOUND` (6A L141). Processing inputs have no tenant or platform-admin read path (CBI-12).

## 4. Required evidence and acceptance criteria

Every item comes from an executed run, stored with the M1 report (W2-D10-01). Each row names the evidence source it requires; a different source does not satisfy it:

- **LIVE** — a real Exotel PSTN call into the M1 environment.
- **PG-FAULT** — real PostgreSQL 18 (the D0 disposable cluster or the M1 database) with deterministic fault injection: barriers that pause a named transaction at a named statement, process kill, controlled database clock for ages, database restart. Provider I/O in these tests may be a labelled test double; that never makes a PG-FAULT result a provider validation.
- **SANDBOX** — real provider APIs (Deepgram, ElevenLabs, LLM, Exotel test number) with test data.
- **KMS** — the real managed KMS non-production key ring (OD-W0-13).
- **CAPTURE** — caller-side calibrated capture (§5).

**Status at W0: every row and schedule below (E-01 … E-17, E-15b, S-1 … S-9, R-1 … R-11) is a planned acceptance test and is NOT EXECUTED.** No PostgreSQL fault-injection, KMS, Exotel, provider or latency evidence exists yet.

| # | Evidence | Source | How it is produced | Passes when |
|---|---|---|---|---|
| E-01 | Real provider-originated inbound calls | LIVE | Owner dials the Exotel number from a PSTN phone | Admitted at least 20 times across sessions |
| E-02a | **Authenticated duplicate** callback | LIVE + PG-FAULT | A real signed Exotel event captured in M1, replayed to the M1 endpoint | Same 2xx; no second receipt, no second input, no second effect (CBK-11, -16) |
| E-02b | **Invalid / tampered / unsigned** callback | PG-FAULT | Mutated body, wrong key, missing signature | Rejected; **zero rows** in any table; no processing (CBK-01) |
| E-02c | Encryption or commit failure | KMS + PG-FAULT | KMS permission denied or unreachable; forced commit failure | 5xx; nothing stored (CBI-05) |
| E-02d | **Signed but malformed** callback | PG-FAULT, signed by the scheme FS-01 verified (else LIVE) | Validly signed body the closed schema rejects | One receipt `FAILED` with a category code; **no input row, no KMS call**; 2xx; never processed or retried (CBK-17); distinct from E-02b |
| E-03 | Tenant → number → agent mapping | PG-FAULT + LIVE | Two synthetic orgs; a signed payload naming the other org's IDs | Each number reaches only its own agent; payload IDs never change the tenant (CBK-03) |
| E-04 | Bidirectional media | LIVE + CAPTURE | Caller-side capture | Caller hears agent audio; agent transcribes caller; no platform recording |
| E-05 | Tamil speech recognition | SANDBOX + LIVE | FS-02 set + live Tamil/Tanglish turns | Scores per 4I §4.4 with a recorded verdict |
| E-06 | Streaming LLM | LIVE | Per-turn spans | TTFT recorded on every turn |
| E-07 | Streaming voice | LIVE + CAPTURE | Spans + caller capture | TTS starts on the first sentence fragment (6D §21.5 rule 2) |
| E-08 | Interruption / cancellation | LIVE | ≥ 20 scripted barge-ins | No stale agent audio after cancel; cancellation latency reported |
| E-09 | Safe finalization and capacity release | PG-FAULT + LIVE (normal end, caller hang-up) | Normal end, hang-up, provider error, socket kill, process kill | Exactly one terminal state per call; one live reservation per `call_session_id` while non-terminal, released exactly once after it; normal path EV-079 `occurred_at` = persisted call-end service-end; abnormal path = last checkpoint's `checkpoint_at`; or `RECONCILIATION_REQUIRED` with no EV-079 — never both, never an estimate |
| E-10 | Durable mandatory events | PG-FAULT + LIVE | SQL over the outbox; forced rollback | Rows committed with their state change; none orphaned; all `PENDING`, never claimed |
| E-11 | Authorized visibility | PG-FAULT (API tests) | Three users with different permissions | `call:read` sees metadata; content only with `transcript:access_content`; other org sees nothing; no read path to processing inputs |
| E-12 | Latency | LIVE + CAPTURE | §5 | L-1 and L-3 with sample sizes, partitions and confidence intervals; L-4 only if the calibrated method meets its bound, else **NOT MEASURED**; no PASS claimed against ≤ 750 ms (DEP-6D-11, W6) |
| E-13 | Negative tenant isolation | PG-FAULT | Automated, in CI and on the M1 database | Every cross-tenant read/write fails at API and database layer, including inputs, identity and reservation rows |
| E-14 | End-to-end traces | LIVE | OpenTelemetry trace per call | One trace from callback → processing → admission → turns → finalization; no secret, audio, transcript or decrypted input in logs |
| E-15 | Callback durability and completion (P1-R2-02 matrix) | PG-FAULT (+ KMS for the KMS cases) | Kill the ingress process after I-8b and before the 2xx; drop the hint; kill the worker after P-1; **inside the P-3 transaction, kill after each statement in turn**: identity lock, fence, revalidation, session insert, conversation insert, `conversation_id` set, EV-073, EV-074, receipt `PROCESSED`, input deletion; kill after commit; run each with the provider retry first and with the sweep first; stop the KMS during P-2 | Every accepted, applicable receipt ends terminal through the sweep with **all** its effects or with none (transient state kept); SQL assertions: (1) `0` receipts terminal while a required effect is missing — in particular `0` incoming-call receipts `PROCESSED` whose identity is `BOUND` without a session, and `0` answered calls whose session has no conversation or a `conversation_id` that does not reference it; (2) exactly one EV-073 and one EV-074 per answered call; (3) an input row exists **iff** its receipt is non-terminal, or `FAILED` after a successful extraction and within 7 days of that terminal transition (or under a recorded hold) — never after `PROCESSED` / `SKIPPED`, never for a receipt-only `FAILED` (CBP-1, CBP-2; IR-23, controlled clock); (4) attempts bounded; (5) no stuck non-terminal session after the reaper interval |
| E-15b | Fenced claim and recovery of stale `PROCESSING` receipts (P1-R3-01, P1-R4-01) — **planned, NOT EXECUTED** | PG-FAULT (+ KMS for R-7) | Blueprint §3.2 R-1 … R-11 (incl. R-9b) as deterministic schedules with barriers and a controlled database clock, driven only by the two-column discovery output: **W1 claims then is killed; W2's claim-or-recover returns `RECOVERED` and finishes once**; **W1 pauses before P-3, the lease expires, W2 recovers, W1 resumes and cannot commit under its stale epoch**; two workers calling claim-or-recover concurrently; completion before a scheduled recovery; KMS and database outages; exhaustion of an incoming-call receipt with a `PENDING` identity and of an end-of-call receipt with a `BOUND` identity; answered-call and end-fact variants | SQL assertions after every step: **`claim_epoch` changes only by + 1 and only on the three allowed paths — `CLAIMED`, `RECOVERED`, `EXHAUSTED` — and never on completion, deterministic failure, yield, `LOST_CLAIM` or `NOT_AVAILABLE`** (checked by comparing every committed transition against its outcome code); exactly one claimant holds each claim epoch; a stale-epoch P-3 writes **no** row in any table; at most one EV-073 and one EV-074 per answered call and one terminal effect per end fact; `attempt_count <= max_attempts`, never reset; no transition out of `PROCESSED` / `SKIPPED` / `FAILED`; **a `FAILED` transition commits no session, conversation, call-state, outbox, reservation or usage row; the only companion write is `PENDING → ABANDONED` of an identity whose origin receipt is that receipt; a `BOUND` or `CLOSED` identity is unchanged by exhaustion (R-9b)**; every accepted receipt with an input ends `PROCESSED`, `SKIPPED` or `FAILED` (`ATTEMPTS_EXHAUSTED` or deterministic) — never lost, never silently deleted. Recovery of facts is tested; timeliness is not claimed |
| E-16 | Admission linearization and identity (P1-R2-01 schedules) | PG-FAULT | Schedules S-1 … S-9 below, each with SQL assertions checked after **every** step | At every step: `count(RESERVED+BOUND for org) <= hard_limit`; `count(non-terminal sessions for org) <= hard_limit`; every non-terminal session has exactly one live reservation; at most one identity and one session per provider call. "Detect and alert after over-admission" is **not** an accepted result |
| E-17 | Key handling, input access and the discovery boundary — **planned, NOT EXECUTED** | KMS + PG-FAULT | Rotate the `CALLBACK_INPUT` KEK while receipts are pending, including a receipt recovered after the rotation; workload permission tests; AAD substitution (copy a ciphertext to another receipt and to another organization); claim-or-recover and the P-2a check called under the wrong tenant context, by `app_api`, `app_readonly` and `app_platform_admin`; direct `SELECT` on the input relation by every role; **discovery checked both by its declared result type (catalogue) and by its runtime rows, over receipts in every state** | Version-*n* input processed after *n+1* is active, also after a recovery (KEY-10); ingress cannot decrypt, processing cannot generate (KEY-08); non-production cannot unwrap production (KEY-05); substituted ciphertexts fail authentication (KEY-02); **discovery returns exactly two columns, `receipt_id` and `organization_id`, and no other value for any receipt state (MR-7H-09 (d), CBI-08)**; the tenant-scoped winning claim-or-recover returns its new epoch and the authorized encrypted input; wrong-tenant or wrong-principal calls return `NOT_AVAILABLE` / no row and no input; every direct `SELECT` is denied (CBI-06, CBI-12) |

**E-16 schedules** (capacity `hard_limit` = 1 unless stated; "pause" = a test barrier at a named point):

| ID | Schedule | Expected |
|---|---|---|
| S-1 | A: T0, T1 `ADMITTED`; A enters T2 and pauses **right after revalidation** (fence held); database clock moved past the grace; T4 starts for A's reservation; B: T0, T1; A commits; T4 continues | T4 blocks on the fence; B's T1 is `REFUSED_AT_LIMIT` (A's `RESERVED` counted); after A commits, T4 reads `SESSION_NON_TERMINAL` and releases nothing; one session (A) |
| S-2 | A: T0, T1 `ADMITTED`; A pauses **before T2** (no fence held); grace passes; T4 releases A's reservation; B: T0, T1 `ADMITTED`, T2 commits; A resumes T2 | A's revalidation reads `RELEASED`; A's T2 rolls back with no row written; A's new T1 is `REFUSED_AT_LIMIT`; A's T3 marks the identity `REFUSED`; one session (B); A's provider call gets the decline path |
| S-3 | As S-2, but T4 holds the fence first and A's T2 waits on it | Same result as S-2 |
| S-4 | Process death after T0, after T1, inside T2, after T2, inside T3, after the terminal commit before T5; then database restart | Recovery as §3.3 windows; the invariants hold before and after restart; reservations and identities survive the restart |
| S-5 | Cross-direction: an inbound T1 and an outbound T1 (database-level fixture of the W4 call path) for the final slot | Exactly one `ADMITTED`, one `REFUSED_AT_LIMIT` (FAR-OD-05 one pool) |
| S-6 | Two receipts for one provider call processed concurrently; the second session attempt timed so its `started_at` falls in a different `call_sessions` partition | One identity, one `call_session_id`, one session; the second run takes no reservation (`ALREADY_HELD` or no T1) |
| S-7 | `hard_limit` 1.5: two calls → `ADMITTED`, `REFUSED_AT_LIMIT`; 0.5 → `REFUSED_AT_LIMIT`; 2.0 → two `ADMITTED`, third refused; zero quota rows → `REFUSED_NOT_CONFIGURED`; resolver or store unreachable → `UNAVAILABLE` | No session in any refused or unavailable case (6K §54.5 matrix) |
| S-8 | Reservation whose (fixture) outbound dispatch is `SUBMITTING`, then `AMBIGUOUS`, past the grace | T4 never releases it |
| S-9 | Later callback for a provider call whose identity is `REFUSED` (and for `ABANDONED`, `CLOSED`); direct `UPDATE` of a terminal identity state | Receipt `SKIPPED`, no session, no reservation; the trigger rejects the update |

**M1 is accepted** only when E-01 … E-17 pass, including E-02a – E-02d and E-15b (E-12 as defined), the slice passes the Development Slice Freeze Gate (Master Plan §11.2), and the report lists the gates that remain closed. M1 acceptance authorizes nothing in production.

## 5. Latency measurement (6D §21.1, not redefined)

The metric `voice_turn_response_latency_ms` starts when the platform **commits the end of the caller's utterance (VAD endpoint)** and ends when **the caller starts receiving the first audible audio** of the reply. The quantities below are kept in their own time domains; none is derived by subtracting quantities from different clocks or different start events.

| Quantity | Start → end | Clock / time domain | Method |
|---|---|---|---|
| **L-1 platform segment** | VAD commit → first egress frame containing audible (non-silent) agent audio, written to the provider socket | Gateway host monotonic clock (one domain) | Span timestamps, per stage (VAD, STT final, router, LLM TTFT, TTS TTFA, egress). The "audible" threshold on egress PCM is the same energy threshold used for L-3 |
| **L-3 caller-perceived turn** | Acoustic end of the caller's speech → acoustic onset of agent audio at the handset | One caller-side recording (one sample clock) | Two-channel capture of the handset (caller microphone and earpiece via a wired interface), onset/offset by a documented energy threshold; a random 10 % of turns annotated by hand to measure detector error |
| **L-4 the 6D metric** | VAD commit → acoustic onset at the handset | **Two domains**: gateway clock and recording sample clock | Only by **calibrated synchronized capture**: both hosts disciplined to a common reference (chrony/NTP to the same source, offset logged every second); the recording laptop timestamps its capture start against that reference and is calibrated by a loopback click of known system time; per turn, T_onset(handset, mapped to reference) − T_VAD(gateway, mapped to reference). Uncertainty u = clock-offset bound of both hosts + capture-start calibration error + onset detection error, computed per session |
| L-2 | (not reported) | — | The return leg is **not** derived as L-3 − L-1: those start at different events (acoustic speech end vs VAD commit), so the difference contains VAD endpointing and the inbound leg |

**Reporting rules.**
- Pairing: every turn has a platform `turn_id`; it is paired with the recording by synchronized time and turn order; unpaired turns are counted and listed, never silently dropped.
- Partitions: Tamil vs English; cold first turn vs warm turns (6D §21.10 items 3, 4); tool turns excluded and barge-in-interrupted turns reported separately (§21.6, §21.7).
- Statistics: p50, p95, p99 per partition with distribution-free (order-statistic) 95 % confidence intervals. Minimum per partition: n ≥ 30 for p50; n ≥ 100 for p95; p99 is labelled **indicative** below n = 400 (fewer samples cannot bound it).
- L-4 is reported only when its per-session uncertainty u ≤ 20 ms ([REC], to be confirmed in the W2-D10-01 review); otherwise L-4 is reported as **NOT MEASURED** with the achieved u. L-1 and L-3 are always reported.
- Every figure is labelled **MEASURED — M1, non-production, single call at a time**. None of them satisfies DEP-6D-11, which needs the per-provider, concurrent benchmark in W6.

## 6. Mandatory exclusions and limits

- Recording storage is off (AG-7L-09). Caller-side test captures stay on the owner's device and contain only consenting participants.
- No raw provider payload is retained (CBI-07); processing inputs are encrypted, never logged, deleted at terminal success (CBI-09) or 7 days after `FAILED` (CBI-10).
- No billable effect: CON-06 does not run; no `usage_events` row is written.
- No relay publication of LS-D-VOX rows; no deletion, reclassification or manual marking of outbox rows.
- No privileged role in the runtime; no RLS bypass for seeding; no platform-admin access to processing inputs (CBI-12).
- No legal hold, erasure or retention change is exercised beyond the IR-23 clock test on synthetic data.
- Mocked or fixture tests are labelled as such and never reported as provider validation.

## 7. Early feasibility investigations

Each FS report records documentation read (URL, date), what was executed, raw results and a verdict **SUPPORTED / NOT SUPPORTED / UNVERIFIED**. NOT SUPPORTED against a frozen requirement is raised as a feasibility blocker with alternatives evaluated through the existing port; provider decisions are not changed without the owner.

| ID | Question | Frozen requirement | Method | Needs |
|---|---|---|---|---|
| FS-01 | Exotel: bidirectional WS audio; which signal arrives first; WS authentication; codec/sample rate; playback clearing; capacity decline; **callback signature scheme over the raw body**; **stable call identifier** for `provider_call_ref`; whether the provider expects anything other than a plain 2xx | 6D §10.4; 7H CBK-02, -05, -14; 6K §54.6; 3B §17; AP-7L-27 (v) | Docs now; sandbox number + throwaway probe | Exotel account + number; OD-W0-04 |
| FS-02 | Tamil/Tanglish STT quality and finalization latency (Deepgram; Gladia fallback); LLM TTFT and Tamil quality | 4I §4.4; 6D §21.3 | Versioned evaluation set | Deepgram, LLM accounts |
| FS-03 | Tamil TTS naturalness, pronunciation, TTFA, real cancellation | 4I §4.4; 6D §14, DEP-6D-08 | MOS panel, pronunciation set, cancel timing | ElevenLabs account |
| FS-04 | Audio conversion and interruption timing end to end | 3B §17; 6D §21.5 | Loopback harness, then FS-01 sandbox | FS-01 |
| FS-05 | SIP interoperability | RR-SIP (API surface missing) | Desk research only in W2 | — |
| FS-06 | Provider cost and availability, including KMS request cost | 4I §10 – §11 | Price pages, dated | Accounts |

## 8. Test levels kept apart

| Level | Example | May be called |
|---|---|---|
| Unit / mocked | State machine, §54.5 boundary matrix, envelope builder, fake STT/TTS | "unit tested" |
| Integration (real PostgreSQL 18 + Redis) | RLS negatives, outbox atomicity, capacity and identity races, checkpoint ordering, receipt claim and sweep | "integration tested" |
| Provider sandbox | FS-01 … FS-03; KMS key operations | "provider validated: <capability>, <date>" |
| Integrated single-tenant product test | E-01 … E-17 | "M1 verified (non-production)" |
| Production authorization | Gate evidence + owner act | Owner only (7L §23.1) |
