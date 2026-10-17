# W0 / 8A — Visual Architecture Atlas

| Field | Value |
|---|---|
| Wave | W0 (document identity "Phase 8A" kept for continuity) |
| Date | 2026-10-16 (first submission); revised 2026-10-16 after the first independent review — see [Review-resolution ledger](W0-8A-Review-Resolution-Ledger.md) |
| Status | Planning record for independent re-review. The diagrams draw the frozen architecture; they decide nothing. |
| Sources | Every diagram file starts with a `%%` comment naming its frozen sources; node labels cite rule IDs where a status depends on a gate or packet |

## 1. Inventory

| ID | Diagram | Audience | Editable source | Rendered |
|---|---|---|---|---|
| A1 | Business architecture: onboarding → agent → numbers → calls → follow-up → reports → billing → administration | Business stakeholders | [A1-business-architecture.mmd](atlas/A1-business-architecture.mmd) | [SVG](atlas/A1-business-architecture.svg) |
| A2 | System context and external trust boundaries | Everyone | [A2-system-context.mmd](atlas/A2-system-context.mmd) | [SVG](atlas/A2-system-context.svg) |
| A3 | Developer component architecture: deployables, modules, ports, data stores; realtime vs durable paths | Developers | [A3-developer-component-architecture.mmd](atlas/A3-developer-component-architecture.mmd) | [SVG](atlas/A3-developer-component-architecture.svg) |
| A4 | Domain ownership and data: contexts, schemas, data classes, streams, owed consumer groups | Developers, reviewers | [A4-domain-ownership-and-data.mmd](atlas/A4-domain-ownership-and-data.mmd) | [SVG](atlas/A4-domain-ownership-and-data.svg) |
| A5 | Real inbound call sequence (milestone M1) | Developers | [A5-inbound-call-sequence.mmd](atlas/A5-inbound-call-sequence.mmd) | [SVG](atlas/A5-inbound-call-sequence.svg) |
| A6 | Deployment and security: environments, processes, data stores, roles, secrets, closed gates | Developers, operations, security | [A6-deployment-and-security.mmd](atlas/A6-deployment-and-security.mmd) | [SVG](atlas/A6-deployment-and-security.svg) |

## 2. Status legend (used in every diagram, in text and in colour)

| Tag | Colour | Meaning |
|---|---|---|
| `[BUILT]` | green | Exists in the repository today and passed its validation: D0 code and tests, or the executed and validated SQL migrations 001 – 112. "Built" never means deployed to staging or production — nothing is |
| `[PLANNED]` | blue | Buildable under frozen contracts in the wave named; no approval outstanding beyond ordinary review. A node whose only open item is a configuration choice that does not stop it being built (for example which LLM is the M1 default, OD-W0-03) stays PLANNED and names the open decision; anything that cannot be built or authored until a decision, approval or provisioning step is BLOCKED (re-review M-W0-03) |
| `[BLOCKED]` | red, dashed | Cannot be built or activated until a named packet approval, migration, owner decision or gate; the blocking ID is in the label |
| `[LATER]` | grey, dashed | Deferred by an owner decision or optional (for example class S cross-region recovery) |

Red edges in A2 cross the platform's trust boundary. Thick edges in A3 are the realtime voice path (in-process, no REST, no event bus — 6D §21.11); dotted edges are the asynchronous durable path (outbox → relay → Redis Streams → consumer).

## 3. Source traceability of material nodes

| Node (diagram) | Frozen source |
|---|---|
| Modular monolith, three deployables (A3, A6) | 2 §7.1; 3A §3; 6D §7.1 |
| `voice_agent/` root package (A3) | D0 README "Package root" (owner-approved) |
| Raw WebSocket for media **and** for the dashboard/supervisor observation channel; no Socket.IO server (A2, A3) | 6A §27.1 ADR-6A-05 (FINAL); 7A WS-01; 7K CNF-7K-07 ("7A governs" over "Socket.IO dashboard/supervisor-only" wording); 6D §7.2, §10.4. See Master Plan §2.3 |
| Callback route, media path, observation path (A2, A5) | 6D §10.4 |
| Number resolver; RLS (A4, A5) | `voice.resolve_inbound_phone_number` (015_5C); `organization.current_tenant_id()` (001_5B) |
| Capacity authority (A3, A5) | 6K §54.4 – §54.6; FAR-OD-04, -05 |
| Event IDs EV-005/006/073/074/079 (A5) | 7B producer table |
| Streams and owed groups (A4) | 7E §29.3 via 7L §34.5.2 |
| Per-turn checkpoint and finalization (A5) | 7L §34.6.3 (AP-7L-27 (iii)); G-02 |
| Providers (A2) | 2 §7.2; 3B §10; FR-STT-001, FR-TTS-001 (via 3B); DEP-6D-10 |
| SIP blocked (A1, A2) | AIR §19.1 RR-SIP |
| Class E single region, class S optional (A6) | 7K OD-7K-01, -02, -05; CNF-7K-01; AP-7L-15 … -20 |
| Database roles (A6) | 001_5B L44 (`app_platform_admin BYPASSRLS`); 7I §9; 7L §33.5; D0 runtime refusal |
| Gates (A1, A2, A4, A6) | 7L §23.3, §33.11, §34.10, §35.10 |
| Hot tier vs event transport Redis (A2, A3, A6) | 7E; 3F §16.3; AP-7L-46; AG-7L-05 |
| Callback ingress fast ACK and async processing; ACK boundary; identical 2xx for new and authenticated duplicates (A2, A3, A5, A6) | 7H §11.2 – §11.4 CBK-01 … -22, §17.2 TX-7/TX-8, MR-7H-09, AB-7H-04; 7I §16 CBI-01 … -14, IR-08, IR-23; OD-W0-08 |
| Managed cloud KMS for `CALLBACK_INPUT`; generate-only vs decrypt-only; non-production root separate (A2, A3, A5, A6) | 7I §12.1 KEY-01 … -11, IR-18; OD-W0-08; OD-W0-13 (open) |
| Capacity reservations in PostgreSQL, not Redis (A3, A5, A6) | 6K §54.4 – §54.9; FAR-OD-04, -05; OD-W0-09; W0-MR-01 |
| Inbound provider-call identity (A3, A5, A6) | 011_5C L14 – L59 (non-unique `provider_call_ref`, partitioned); 7H CBK-09; OD-W0-11; W0-MR-02 |
| Eleven durable streams, one SIGNAL stream, eleven durable groups, one SIGNAL group, 18 durable subscriptions; producers per stream (A4) | 7E §18 stream table, §29.1 – §29.3; 7L §34.5.2 |
| LS-D-VOX `CLOSED` in every environment; staging publishes only fully admitted streams (A3, A4, A6) | 7L SPA-7L-01 … -16, §34.5.2 – §34.5.4; OD-W0-10 |
| Normal-end vs abnormal-end service-end time for EV-079 (A5) | 7B OCC-01 … -07; 7L §34.6.3, CKP-7L-01 … -13; AP-7L-27 (iii) |
| Fenced admission T0 – T4 and the single admit-and-start transaction; receipt-only `FAILED` branch; receipt id allocated before encryption; decline as a separate `TelephonyPort` control (A3, A5) | 6A §17.3, §35 (4G §12 list); 6K §54.3 – §54.8; 7H CBK-09, -17, TX-8; 7I KEY-02; 111_5H4 precedent; Blueprint §3.1 – §3.3 |
| Latency labels: L-1 on the gateway clock, the 6D metric end on the caller side, L-4 only by calibrated synchronized capture (A5) | 6D §21.1, §21.3, §21.10; Blueprint §5 |

## 4. How to render and keep current

```bash
# one-time, outside the repository (any folder):
npm install @mermaid-js/mermaid-cli@11.4.2
# render one diagram (uses an installed Chrome or Edge through a puppeteer config file):
npx mmdc -p puppeteer-config.json -i docs/implementation/atlas/A5-inbound-call-sequence.mmd \
         -o docs/implementation/atlas/A5-inbound-call-sequence.svg -b white
```

`puppeteer-config.json` contains `{"executablePath": "<path to chrome.exe or msedge.exe>"}`. GitHub also renders Mermaid when a `.mmd` source is pasted into a fenced `mermaid` block.

**Update rule.** When a work package changes the status of a node (for example PLANNED → BUILT), the same pull request updates the tag in the `.mmd` file and re-renders its SVG. No other architecture document is created for that change.

## 5. Rendering evidence (executed 2026-10-16)

All six sources were rendered with `@mermaid-js/mermaid-cli` 11.4.2 using the locally installed Chrome. A5 first failed (a `;` inside a sequence message ends the statement in Mermaid); the semicolons were replaced and it re-rendered. All six SVGs were produced with no parse error, and A4 and A5 were also rendered to PNG and inspected visually for legibility. PNGs were not added to the repository (SVG is the exported format).

**Re-review pass (executed 2026-10-16).** All six sources were revised (ledger §2) and all six SVGs were regenerated from them with the same pinned CLI, `@mermaid-js/mermaid-cli` **11.4.2** (`mmdc --version` printed `11.4.2`), against the locally installed Chrome, with `-b white`. No SVG contains a parse-error marker. Each diagram was also rendered to a 2400-px-wide PNG outside the repository and inspected: A1, A2, A4, A5, A6 had no overlapping or unreadable labels; A3 first showed the label "same transaction as domain write" under the Redis hot-tier node, so the wording was moved into the outbox node and A3 was re-rendered and re-inspected without overlap. Status colours were checked against each node's tag. A5 is wide (twelve participants) and is readable at full width, not as a thumbnail.

**Second re-review pass (executed 2026-10-16).** Only A3 and A5 sources changed (P1-R2-01, P1-R2-02, M-R2-01 … -03). All six SVGs were regenerated with `@mermaid-js/mermaid-cli` **11.4.2** (`mmdc --version` = `11.4.2`). The four unchanged sources (A1, A2, A4, A6) re-rendered to SVGs byte-identical to their previous exports, which confirms each source/export pair is consistent. A3 and A5 were rendered to 2600-px PNGs outside the repository and inspected: no parse error, no unreadable or hidden label, status colours match tags; A5 shows the ACK boundary, the receipt-only `FAILED` branch, T0 – T4 and the single admit-and-start transaction, and the optional separate decline control.

**Third re-review pass (executed 2026-10-16).** Only A3 and A5 sources changed (P1-R3-01: claim epoch, database-time lease, fenced recovery claim, epoch fence on every completing transaction; M-R3-01: `FAILED` input retention). All six SVGs were regenerated with `@mermaid-js/mermaid-cli` **11.4.2**; no parse-error marker. A1, A2, A4 and A6 re-rendered byte-identical to their previous exports. All six were rendered to 2600-px PNGs outside the repository and inspected: labels readable, no hidden arrows, status colours match tags; A5 shows the recovery-claim branch after the first claim and the epoch fence in T2, T3 and the end-of-call transaction.

**Fourth re-review pass (executed 2026-10-16).** Only A3 and A5 sources changed (P1-R4-01: discovery returns only `receipt_id` and `organization_id`, then a tenant-scoped claim-or-recover; M-R4-02: `FAILED` carries no business effect, only the bounded setup disposition). All six SVGs were regenerated with `@mermaid-js/mermaid-cli` **11.4.2**; no parse-error marker; A1, A2, A4 and A6 re-rendered byte-identical to their previous exports. All six were rendered to 2600-px PNGs outside the repository and inspected: labels readable, status colours match tags.
