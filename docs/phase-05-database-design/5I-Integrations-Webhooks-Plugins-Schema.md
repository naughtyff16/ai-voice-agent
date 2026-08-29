# Phase 5I — Integrations / Webhooks / Plugins Schema
## Physical PostgreSQL Database Design — Correction Pass v1.1

| | |
|---|---|
| **Phase** | 5I — per PHASE-NUMBERING-RECONCILIATION.md |
| **Schemas** | `integrations`, `webhooks`, `plugins` |
| **Follows** | Phase 5H — Billing / Usage Schema (APPROVED, migration 058 is last) |
| **Precedes** | Phase 5J — Analytics / Audit Schema |
| **Migration chain** | 059–066 (continuing from 058; no renumbering) |
| **Authority** | Phase 5A standards + Phase 4F DDD (§6–§9) + Phase 3E §7–§8 + Phase 4H §18.3 |
| **Correction pass** | FIX-01 through FIX-14 applied; see §37 Validation Report |

---

## 1. Executive Summary

Phase 5I delivers the physical PostgreSQL schema for three bounded contexts that share a deployment phase:

| Schema | DDD Context | Aggregates |
|---|---|---|
| `integrations` | Integration Context | `IntegrationDefinition`, `IntegrationConnection`, `OAuthAttempt`, `IntegrationHealth` |
| `webhooks` | Webhook Context | `WebhookEndpoint`, `WebhookDelivery`, `InboundWebhookEvent` |
| `plugins` | Plugin Context | `Plugin`, `PluginVersion`, `PluginInstallation`, `PluginExecution` |

Key design positions (corrected from v1.0):

- **Credential security** — `credential_ref` columns are opaque secret-manager references (`secret_manager://...`); no plaintext secrets in DB; CHECK-enforced.
- **Webhook delivery partitioned from day one** — `webhook_deliveries` partitioned by `created_at` (monthly); 30-day purge for DELIVERED, 90-day for DEAD_LETTER (Phase 4H §18.3).
- **Inbound webhook idempotency** — `UNIQUE (organization_id, provider_slug, provider_event_id)` — tenant-scoped (FIX-08).
- **Outbound delivery claim** — `SELECT FOR UPDATE SKIP LOCKED` pattern via SECURITY DEFINER; one worker owns one delivery.
- **max_attempts enforced in DB** — `fn_delivery_failed()` computes `new_count = attempt_count + 1`; forces DEAD_LETTER when `new_count >= max_attempts`, regardless of caller intent (FIX-02).
- **Plugin version strictly pinned** — `fn_pi_version_immutable()` blocks ALL direct `plugin_version_id` changes; only `fn_upgrade_plugin()` SECURITY DEFINER may change it, after validating same-plugin ownership and APPROVED status (FIX-03, FIX-04).
- **Capability enforcement in DB** — `fn_activate_plugin()` validates `enabled_capabilities ⊆ manifest.capabilities`, plugin APPROVED, version APPROVED (FIX-06).
- **All SECURITY DEFINER functions have explicit `search_path`** — `SET search_path = <schema>, pg_catalog` in every function (FIX-05).
- **OQ-4F-07** — V1 enforces one active connection per `(organization_id, definition_id)` via explicit transactional check inside `fn_create_integration_connection()` SECURITY DEFINER using `SELECT FOR UPDATE`. Partial-unique-index `ON CONFLICT ON CONSTRAINT` removed (was invalid PostgreSQL for partial indexes — FIX-01).

---

## 2. Scope

**In scope:**
- `integrations` schema: `integration_definitions`, `integration_connections`, `oauth_attempts`, `integration_health`
- `webhooks` schema: `webhook_endpoints`, `webhook_deliveries` (partitioned), `inbound_webhook_events`
- `plugins` schema: `plugins`, `plugin_versions`, `plugin_installations`, `plugin_executions`

**Out of scope (referenced logically only):**
- Voice call state → `voice` schema (authoritative)
- CRM contacts → `crm` schema
- Campaign execution → `campaign` schema
- Billing invoices/payments → `billing` schema
- Workflow executions → `workflow` schema
- Analytics/Audit projections → Phase 5J

---

## 3. Bounded Context Ownership

**Integrations owns:** integration provider definitions, tenant connections, OAuth attempt state, credential references, integration health durable state.

**Webhooks owns:** outbound webhook endpoints, outbound delivery records, inbound webhook event records, delivery retry state, replay metadata.

**Plugins owns:** plugin registry, plugin versions/manifests, tenant installations, plugin execution records.

**None of these contexts own the domain data they route.** They own the routing, delivery, credential, and audit metadata. Voice, CRM, Billing, etc. remain authoritative for their own domain records.

Cross-context data flow (event-driven; no cross-schema FK):

```
Any domain event (Voice, CRM, Campaign, Billing, Workflow...)
    → Redis event bus
    → WebhookDispatchService (app layer)
    → webhooks.webhook_deliveries INSERT
    → Celery delivery worker
    → External HTTPS endpoint (SSRF-validated egress)
```

```
External provider webhook
    → Platform inbound endpoint
    → webhooks.inbound_webhook_events INSERT (idempotent; org+provider+event_id)
    → Celery processing worker
    → Integration ACL → domain command
```

---

## 4. Platform vs Tenant Ownership

| Table | Schema | Owner | organization_id | RLS |
|---|---|---|---|---|
| `integration_definitions` | integrations | Platform | — | No (public read) |
| `integration_connections` | integrations | Tenant | YES | YES |
| `oauth_attempts` | integrations | Tenant | YES | YES |
| `integration_health` | integrations | Tenant | YES | YES |
| `webhook_endpoints` | webhooks | Tenant | YES | YES |
| `webhook_deliveries` | webhooks | Tenant | YES | YES |
| `inbound_webhook_events` | webhooks | Tenant | YES | YES |
| `plugins` | plugins | Platform | — | No (public read) |
| `plugin_versions` | plugins | Platform | — | No (public read) |
| `plugin_installations` | plugins | Tenant | YES | YES |
| `plugin_executions` | plugins | Tenant | YES | YES |

---

## 5. Aggregate → Table Mapping

| DDD Aggregate | Table(s) |
|---|---|
| IntegrationDefinition | `integration_definitions` |
| IntegrationConnection | `integration_connections` |
| OAuthAttempt | `oauth_attempts` |
| IntegrationHealth | `integration_health` |
| WebhookEndpoint | `webhook_endpoints` |
| WebhookDelivery | `webhook_deliveries` (partitioned) |
| InboundWebhookEvent | `inbound_webhook_events` |
| Plugin | `plugins` |
| PluginVersion | `plugin_versions` |
| PluginInstallation | `plugin_installations` |
| PluginExecution | `plugin_executions` |

---

## 6. Domain Invariants

1. **INV-INT-01** — `integration_connections.credential_ref` is never a plaintext secret; always an opaque secret-manager reference. Enforced by CHECK.
2. **INV-INT-02** — `DISCONNECTED` and `FAILED` integration connections are terminal; reconnection creates a new row. Enforced by `fn_ic_terminal_guard()` trigger.
3. **INV-INT-03** — `oauth_attempts` expire after TTL (default 10 minutes); expired or already-redeemed attempts cannot be redeemed. Enforced by `fn_redeem_oauth_attempt()`.
4. **INV-INT-04** — V1: only one non-terminal connection per `(organization_id, definition_id)`. Enforced by `fn_create_integration_connection()` transactional check (FIX-01).
5. **INV-WH-01** — `webhook_endpoints.target_url` must be HTTPS. Enforced by CHECK. Full SSRF protection at application egress layer (FIX-07).
6. **INV-WH-02** — `webhook_endpoints.topics` must not be empty. Enforced by CHECK.
7. **INV-WH-03** — `webhook_endpoints.signing_secret_ref` is always an opaque reference. Enforced by CHECK.
8. **INV-WH-04** — Webhook delivery payload (`payload_json`, `payload_hash`, `event_id`, `event_type`, `webhook_endpoint_id`) is immutable after creation. Delivery lifecycle metadata (status, attempt_count, etc.) may transition only through SECURITY DEFINER state-transition functions. Direct UPDATE/DELETE by application roles is prohibited. Enforced by `fn_wd_identity_immutable()` trigger + REVOKE (FIX-09).
9. **INV-WH-05** — `webhook_deliveries.last_response_body_preview` is capped at 512 characters. Enforced by CHECK + LEFT() in functions.
10. **INV-WH-06** — Inbound events deduplicated by `UNIQUE (organization_id, provider_slug, provider_event_id)` (FIX-08). Different tenants receiving the same provider event ID are allowed; same tenant receiving the same event from the same provider is blocked.
11. **INV-WH-07** — `attempt_count` reaching `max_attempts` forces DEAD_LETTER regardless of caller intent. Enforced by `fn_delivery_failed()` (FIX-02).
12. **INV-WH-08** — Replay creates a new delivery row; original delivery payload and result history are immutable. `replay_count` and `last_replayed_at` are replay metadata — the only mutable fields on the original row updated by replay (FIX-10).
13. **INV-PLUG-01** — `plugin_versions.manifest` is immutable after `approved_at IS NOT NULL`. Enforced by `fn_pv_manifest_immutable()` trigger.
14. **INV-PLUG-02** — `plugin_installations.plugin_version_id` is immutable under normal UPDATE. Only `fn_upgrade_plugin()` SECURITY DEFINER may change it, after validating same-plugin ownership and APPROVED status (FIX-03).
15. **INV-PLUG-03** — `plugin_installations.credential_ref` is always an opaque reference when not null. Enforced by CHECK.
16. **INV-PLUG-04** — `UNINSTALLED` installations are terminal. Enforced by `fn_pi_terminal_guard()` trigger.
17. **INV-PLUG-05** — `plugins.slug` is globally unique and immutable. Enforced by UNIQUE constraint + trigger.
18. **INV-PLUG-06** — `plugin_installations.plugin_id` and `plugin_installations.plugin_version_id` must refer to the same plugin (`plugin_versions.plugin_id = plugin_installations.plugin_id`). Enforced in `fn_create_plugin_installation()` and `fn_upgrade_plugin()` (FIX-04).
19. **INV-PLUG-07** — `enabled_capabilities` at activation must be a subset of the installed version's `manifest.capabilities`. Enforced in `fn_activate_plugin()` (FIX-06).

---

## 7. Integration Provider Model

`integration_definitions` is platform-owned, read-only for tenant roles. Capabilities stored as `TEXT[]`. `auth_type` distinguishes `OAUTH2`, `API_KEY`, `BASIC`, `CUSTOM`.

---

## 8. Tenant Integration Connection Model

Status lifecycle (Phase 4F §7.5):
```
CONNECTING → ACTIVE → DEGRADED → DISCONNECTED (terminal)
CONNECTING → FAILED (terminal)
ACTIVE → DISCONNECTED (terminal)
DEGRADED → ACTIVE (credential refresh)
DEGRADED → DISCONNECTED (terminal)
```

**V1 single-connection rule (FIX-01):** Enforced transactionally inside `fn_create_integration_connection()`: before inserting, the function uses `SELECT FOR UPDATE` to check for any non-terminal connection for the same `(organization_id, definition_id)`. If found, exception raised. No partial-unique-index `ON CONFLICT ON CONSTRAINT` (which is not valid PostgreSQL for partial indexes).

---

## 9. Credential / OAuth Model

OAuth flow state in `oauth_attempts` — expires after 10 minutes. `state` (CSRF) and `code_verifier` (PKCE S256) stored. `fn_redeem_oauth_attempt()` transitions PENDING→REDEEMED atomically; second call raises exception. No OAuth tokens in the database.

---

## 10. Inbound Webhook Model

**Idempotency key (FIX-08):** `UNIQUE (organization_id, provider_slug, provider_event_id)`. Tenant-scoped — different tenants may receive the same provider event ID independently.

**Raw payload (FIX-12, resolved):** V1 default — raw payloads NOT stored in PostgreSQL or S3. If enabled per provider: S3 only, encrypted, tenant-scoped path, 7-day TTL. `raw_payload_ref` stores S3 key only.

`status`: `RECEIVED → PROCESSING → PROCESSED | FAILED | SKIPPED`.

---

## 11. Outbound Webhook Model

`webhook_endpoints.target_url` must be HTTPS (DB CHECK). Full SSRF protection (private IP, loopback, RFC1918, cloud metadata endpoints, DNS rebinding) enforced at two points by the application/egress layer: at registration time and at delivery time (FIX-07).

---

## 12. Webhook Subscription Model

Topics stored as `webhook_endpoints.topics TEXT[] NOT NULL`. **OQ-4F-06** (topic versioning) deferred to Phase 7.

---

## 13. Webhook Delivery Model

`webhook_deliveries` partitioned RANGE on `created_at` (monthly) per Phase 4H §18.3.

**Immutability clarification (FIX-09):** Immutable fields (identity/content): `payload_json`, `payload_hash`, `event_id`, `event_type`, `webhook_endpoint_id`, `organization_id`. Lifecycle fields transition only via SECURITY DEFINER functions; direct UPDATE/DELETE REVOKEd from app roles.

**Status lifecycle:**
```
PENDING → DELIVERING → DELIVERED (terminal)
DELIVERING → PENDING (retry; only if new attempt_count < max_attempts)
DELIVERING → DEAD_LETTER (terminal; when new attempt_count >= max_attempts — forced by DB)
DEAD_LETTER → (new PENDING row via replay — original stays DEAD_LETTER)
PENDING → CANCELLED (operator action)
```

**max_attempts enforcement (FIX-02):** `fn_delivery_failed()` computes `new_count = attempt_count + 1`. If `new_count >= max_attempts`, DEAD_LETTER is set regardless of `p_next_attempt_at`.

---

## 14. Retry / Dead Letter Model

Celery manages backoff scheduling; DB stores durable state. Application supplies backoff timestamp; DB enforces ceiling. DEAD_LETTER rows retained 90 days. `resolved_at` set when operator abandons.

---

## 15. Webhook Replay Model

Replay creates a new delivery row (`replay_of_delivery_id` set). Original row's payload/result history is immutable. `replay_count` and `last_replayed_at` on the original are replay metadata updated by `fn_replay_webhook_delivery()` only (FIX-10). Replay is idempotent — returns existing non-completed replay ID if one exists.

---

## 16. Webhook Security / Signing

Signing: `HMAC-SHA256(secret, f"ts={unix_timestamp}.{payload_json}")`. Header: `X-Platform-Signature: v1={hex_signature}`. `signing_secret_ref` is opaque. Consumers advised to reject `ts` > 5 minutes old.

**Error field bounds (FIX-11):** `failure_reason ≤ 2000 chars` (DB CHECK + LEFT); `last_response_body_preview ≤ 512` (DB CHECK + LEFT); `last_failure_reason / last_sync_error ≤ 1000` (DB CHECK). All external error content is untrusted data.

---

## 17. Plugin Registry Model

`plugins` is platform-owned. `slug` globally unique and immutable. Status: `PENDING_REVIEW → APPROVED | REJECTED` (terminal). Only APPROVED plugins may be installed.

---

## 18. Plugin Version / Capability Model

`plugin_versions` platform-owned. `manifest JSONB` stores `PluginManifest` including `capabilities[]`. Immutable after `approved_at IS NOT NULL`. Status: `PENDING_REVIEW → APPROVED | REJECTED | DEPRECATED`.

**Plugin base_url SSRF (FIX-13):** Validated at version approval (application layer) and at plugin callout time (egress proxy). Same two-point validation as webhook endpoints.

---

## 19. Plugin Installation / Configuration

`plugin_installations` tenant-owned. `UNINSTALLED` is terminal; re-installation creates a new row.

**Version pinning (FIX-03, FIX-04):** `fn_pi_version_immutable()` blocks ALL direct `plugin_version_id` changes. Only `fn_upgrade_plugin()` may change it after validating: non-UNINSTALLED status, new version belongs to same plugin, new version APPROVED. After upgrade, `enabled_capabilities` reset to `'{}'` and status to `INSTALLED`; tenant must re-activate.

---

## 20. Plugin Execution Model

`plugin_executions` tenant-owned. `failure_reason ≤ 2000 chars`. Unpartitioned V1; threshold >5M rows. `correlation_id` is logical (no FK).

---

## 21. Event Routing / Versioning

Application-layer routing (Celery + Redis Streams). `webhook_endpoints.topics TEXT[]` is the subscription filter. **OQ-4F-06** deferred to Phase 7.

---

## 22. Integration Health

`integration_health` stores durable health state per connection. `last_failure_reason ≤ 1000 chars` (DB CHECK). Real-time metrics go to Phase 5J.

---

## 23. GDPR / PII

| Table / Column | PII | Handling |
|---|---|---|
| `integration_connections.external_account_name` | pii:name | Anonymized on org deletion |
| `oauth_attempts.state / code_verifier` | None | Purged 24h after expiry or redemption |
| `inbound_webhook_events.raw_payload_ref` | Potential PII | V1 default: not retained; if enabled: S3 only, encrypted, 7-day TTL (FIX-12) |
| `webhook_deliveries.payload_json` | Potential PII | 30-day purge for DELIVERED |
| `webhook_deliveries.last_response_body_preview` | Potential PII | Capped 512 chars |
| `integration_health.last_failure_reason` | Potential PII | Capped 1000 chars; application must sanitize |

**GDPR erasure:** `fn_integrations_anonymize_org()` SECURITY DEFINER clears PII fields and disconnects connections.

---

## 24. Security Model

| Threat | Mitigation |
|---|---|
| Cross-tenant access | RLS `organization_id = organization.current_tenant_id()` on all tenant tables |
| Credential leakage | CHECK `LIKE 'secret_manager://%'`; REVOKE INSERT/UPDATE on connections from app roles |
| OAuth token theft | Tokens never in DB; 10-min expiry; state UNIQUE; PKCE stored |
| OAuth replay | `fn_redeem_oauth_attempt()`: PENDING+expiry check; exception on reuse |
| Webhook spoofing | HMAC-SHA256; opaque secret ref |
| Webhook replay attack | Timestamp in signature; consumer SDK rejects ts > 5 min old |
| Duplicate inbound event | UNIQUE `(organization_id, provider_slug, provider_event_id)` |
| Concurrent delivery claim | SKIP LOCKED in `fn_claim_delivery()` |
| SSRF — webhook endpoint | HTTPS CHECK (DB) + egress proxy (app, two-point: registration + delivery) |
| SSRF — plugin base_url | Validated at approval + at callout time via egress proxy |
| Malicious plugin | Plugins are external HTTP services; no in-process execution |
| Plugin privilege escalation | `fn_activate_plugin()` validates capabilities ⊆ manifest |
| Cross-plugin version mismatch | `fn_create_plugin_installation()` + `fn_upgrade_plugin()` validate version.plugin_id |
| search_path injection | SET search_path = schema, pg_catalog in all SECURITY DEFINER functions |
| Unbounded error content | DB CHECK bounds + LEFT() in all functions |

---

## 25. Concurrency / Idempotency

| Race | Mechanism |
|---|---|
| Duplicate inbound event | UNIQUE `(org_id, provider_slug, provider_event_id)` + ON CONFLICT DO NOTHING |
| Two workers claim same delivery | SKIP LOCKED in fn_claim_delivery |
| Duplicate replay | fn_replay_webhook_delivery returns existing PENDING/DELIVERING ID |
| OAuth state collision | UNIQUE (state) on oauth_attempts |
| OAuth attempt reuse | SELECT FOR UPDATE + status/expiry check in fn_redeem_oauth_attempt |
| Integration connection creation race | SELECT FOR UPDATE in fn_create_integration_connection |
| Plugin installation race | SELECT FOR UPDATE in fn_create_plugin_installation |
| Plugin upgrade race | SELECT FOR UPDATE in fn_upgrade_plugin |
| max_attempts ceiling | fn_delivery_failed computes new count and forces DEAD_LETTER (FIX-02) |

---

## 26. Index Strategy

```sql
-- integration_definitions
uq_id_slug                  (slug) UNIQUE
idx_id_active               (is_active)

-- integration_connections
idx_ic_org_def_nonterminal  (organization_id, definition_id)
                            WHERE status NOT IN ('DISCONNECTED','FAILED')
idx_ic_org_status           (organization_id, status)
idx_ic_ext_account          (definition_id, external_account_ref)
                            WHERE external_account_ref IS NOT NULL

-- oauth_attempts
uq_oa_state                 (state) UNIQUE
idx_oa_org_expires          (organization_id, expires_at)

-- integration_health
uq_ih_connection            (integration_connection_id) UNIQUE
idx_ih_org                  (organization_id)

-- webhook_endpoints
idx_we_org_status           (organization_id, status)
idx_we_org_topics           (topics) USING GIN WHERE status = 'ACTIVE'

-- webhook_deliveries (partitioned — inherited by child tables)
idx_wd_pending              (organization_id, next_attempt_at) WHERE status = 'PENDING'
idx_wd_endpoint             (webhook_endpoint_id, created_at DESC)
idx_wd_status               (organization_id, status)
idx_wd_replay               (replay_of_delivery_id) WHERE replay_of_delivery_id IS NOT NULL

-- inbound_webhook_events
uq_iwe_org_provider_event   (organization_id, provider_slug, provider_event_id) UNIQUE
idx_iwe_org_status          (organization_id, status, received_at DESC)
idx_iwe_org_type            (organization_id, event_type, received_at DESC)

-- plugins
uq_plugin_slug              (slug) UNIQUE
idx_pl_status               (status)

-- plugin_versions
uq_pv_plugin_semver         (plugin_id, semver) UNIQUE
idx_pv_approved             (plugin_id) WHERE status = 'APPROVED'

-- plugin_installations
uq_pi_org_plugin_active     (organization_id, plugin_id) WHERE status NOT IN ('UNINSTALLED')
idx_pi_org_status           (organization_id, status)
idx_pi_version              (plugin_version_id)

-- plugin_executions
idx_pe_installation         (plugin_installation_id, started_at DESC)
idx_pe_org_status           (organization_id, status)
idx_pe_correlation          (correlation_id) WHERE correlation_id IS NOT NULL
```

---

## 27. Partitioning

| Table | Strategy | V1 |
|---|---|---|
| `webhook_deliveries` | RANGE monthly on `created_at` (Phase 4H §18.3) | **Partitioned from V1** |
| `inbound_webhook_events` | Unpartitioned V1 | Partition if >5M rows |
| `plugin_executions` | Unpartitioned V1 | Partition if >5M rows |

---

## 28. Complete PostgreSQL DDL

```sql
-- ================================================================
-- Migration 059: schemas and GRANT USAGE
-- ================================================================

CREATE SCHEMA IF NOT EXISTS integrations;
CREATE SCHEMA IF NOT EXISTS webhooks;
CREATE SCHEMA IF NOT EXISTS plugins;

GRANT USAGE ON SCHEMA integrations TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA webhooks     TO app_api, app_worker, app_readonly, app_platform_admin;
GRANT USAGE ON SCHEMA plugins      TO app_api, app_worker, app_readonly, app_platform_admin;

-- ================================================================
-- Migration 060: integration_definitions (platform-owned)
-- ================================================================

CREATE TABLE integrations.integration_definitions (
  id                UUID    NOT NULL DEFAULT gen_uuid_v7(),
  slug              TEXT    NOT NULL,
  name              TEXT    NOT NULL,
  description       TEXT    NULL,
  auth_type         TEXT    NOT NULL,
  capabilities      TEXT[]  NOT NULL DEFAULT '{}',
  required_scopes   TEXT[]  NOT NULL DEFAULT '{}',
  manifest_version  TEXT    NOT NULL DEFAULT '1.0.0',
  documentation_url TEXT    NULL,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_integration_definitions  PRIMARY KEY (id),
  CONSTRAINT uq_id_slug                  UNIQUE (slug),
  CONSTRAINT chk_id_slug_format          CHECK (slug ~ '^[a-z][a-z0-9_]{0,98}[a-z0-9]$'),
  CONSTRAINT chk_id_auth_type            CHECK (auth_type IN ('OAUTH2','API_KEY','BASIC','CUSTOM')),
  CONSTRAINT chk_id_name                 CHECK (length(name) BETWEEN 1 AND 100)
);

-- FIX-05: search_path hardened on all SECURITY DEFINER functions
CREATE OR REPLACE FUNCTION integrations.fn_id_slug_immutable()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  IF NEW.slug <> OLD.slug THEN
    RAISE EXCEPTION 'integration_definitions.slug is immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_id_slug_immutable() FROM PUBLIC;

CREATE TRIGGER trg_id_slug_immutable
  BEFORE UPDATE ON integrations.integration_definitions
  FOR EACH ROW EXECUTE FUNCTION integrations.fn_id_slug_immutable();

CREATE TRIGGER trg_id_updated_at
  BEFORE UPDATE ON integrations.integration_definitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_id_active ON integrations.integration_definitions (is_active);

GRANT SELECT ON integrations.integration_definitions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON integrations.integration_definitions TO app_platform_admin;

-- ================================================================
-- Migration 061: integration_connections, oauth_attempts, integration_health
-- ================================================================

CREATE TABLE integrations.integration_connections (
  id                     UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID    NOT NULL,
  definition_id          UUID    NOT NULL REFERENCES integrations.integration_definitions(id) ON DELETE RESTRICT,
  display_name           TEXT    NOT NULL,
  status                 TEXT    NOT NULL DEFAULT 'CONNECTING',
  credential_ref         TEXT    NOT NULL,
  configuration          JSONB   NOT NULL DEFAULT '{}',
  enabled_capabilities   TEXT[]  NOT NULL DEFAULT '{}',
  external_account_ref   TEXT    NULL,
  external_account_name  TEXT    NULL,
  last_sync_at           TIMESTAMPTZ NULL,
  last_sync_error        TEXT    NULL,
  connected_at           TIMESTAMPTZ NULL,
  connected_by_ref       UUID    NULL,
  disconnected_at        TIMESTAMPTZ NULL,
  disconnect_reason      TEXT    NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_integration_connections    PRIMARY KEY (id),
  CONSTRAINT chk_ic_status                CHECK (status IN ('CONNECTING','ACTIVE','DEGRADED','DISCONNECTED','FAILED')),
  CONSTRAINT chk_ic_credential_ref        CHECK (credential_ref LIKE 'secret_manager://%'),
  CONSTRAINT chk_ic_display_name          CHECK (length(display_name) BETWEEN 1 AND 200),
  CONSTRAINT chk_ic_sync_error_len        CHECK (last_sync_error IS NULL OR length(last_sync_error) <= 1000),
  CONSTRAINT chk_ic_terminal_has_at       CHECK (
    (status IN ('DISCONNECTED','FAILED') AND disconnected_at IS NOT NULL)
    OR status NOT IN ('DISCONNECTED','FAILED')
  )
);

COMMENT ON COLUMN integrations.integration_connections.external_account_name IS 'pii:name';

-- Supporting index for the V1 one-active-connection-per-(org,definition) check
CREATE INDEX idx_ic_org_def_nonterminal ON integrations.integration_connections (organization_id, definition_id)
  WHERE status NOT IN ('DISCONNECTED','FAILED');

CREATE INDEX idx_ic_org_status ON integrations.integration_connections (organization_id, status);
CREATE INDEX idx_ic_ext_account ON integrations.integration_connections (definition_id, external_account_ref)
  WHERE external_account_ref IS NOT NULL;

-- Terminal state guard (FIX-05)
CREATE OR REPLACE FUNCTION integrations.fn_ic_terminal_guard()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  IF OLD.status IN ('DISCONNECTED','FAILED') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'integrations: connection % is in terminal state % — create a new connection',
      OLD.id, OLD.status;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_ic_terminal_guard() FROM PUBLIC;

CREATE TRIGGER trg_ic_terminal_guard
  BEFORE UPDATE ON integrations.integration_connections
  FOR EACH ROW EXECUTE FUNCTION integrations.fn_ic_terminal_guard();

CREATE TRIGGER trg_ic_updated_at
  BEFORE UPDATE ON integrations.integration_connections
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE integrations.integration_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.integration_connections FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ic_tenant ON integrations.integration_connections
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- app_api and app_worker cannot directly INSERT/UPDATE connections (FIX-01)
REVOKE INSERT, UPDATE, DELETE ON integrations.integration_connections FROM app_api, app_worker;
GRANT SELECT ON integrations.integration_connections TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON integrations.integration_connections TO app_platform_admin;

-- ----------------------------------------------------------------
-- SECURITY DEFINER: create integration connection (FIX-01)
-- Enforces V1 one-active-per-(org, definition) rule transactionally.
-- Replaces the invalid ON CONFLICT ON CONSTRAINT <partial_index> approach.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrations.fn_create_integration_connection(
  p_organization_id   UUID,
  p_definition_id     UUID,
  p_display_name      TEXT,
  p_credential_ref    TEXT,
  p_configuration     JSONB DEFAULT '{}'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_existing_id UUID;
  v_new_id      UUID;
BEGIN
  IF p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: credential_ref must be a secret_manager:// reference';
  END IF;

  -- V1 uniqueness: lock and check for any non-terminal connection for same (org, definition)
  SELECT id INTO v_existing_id
  FROM integrations.integration_connections
  WHERE organization_id = p_organization_id
    AND definition_id   = p_definition_id
    AND status NOT IN ('DISCONNECTED','FAILED')
  FOR UPDATE;

  IF FOUND THEN
    RAISE EXCEPTION
      'integrations: a non-terminal connection (id=%) already exists for this (org, definition). '
      'Disconnect it first, then create a new connection.',
      v_existing_id;
  END IF;

  INSERT INTO integrations.integration_connections
    (organization_id, definition_id, display_name, credential_ref, configuration, status)
  VALUES
    (p_organization_id, p_definition_id, p_display_name, p_credential_ref, p_configuration, 'CONNECTING')
  RETURNING id INTO v_new_id;

  -- Create health row atomically
  INSERT INTO integrations.integration_health (organization_id, integration_connection_id)
  VALUES (p_organization_id, v_new_id)
  ON CONFLICT (integration_connection_id) DO NOTHING;

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_create_integration_connection(UUID, UUID, TEXT, TEXT, JSONB)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_create_integration_connection(UUID, UUID, TEXT, TEXT, JSONB)
  TO app_api, app_worker, app_platform_admin;

-- ----------------------------------------------------------------
-- oauth_attempts
-- ----------------------------------------------------------------
CREATE TABLE integrations.oauth_attempts (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id  UUID    NOT NULL,
  definition_id    UUID    NOT NULL REFERENCES integrations.integration_definitions(id) ON DELETE RESTRICT,
  state            TEXT    NOT NULL,
  code_verifier    TEXT    NULL,
  redirect_uri     TEXT    NOT NULL,
  requested_scopes TEXT[]  NOT NULL DEFAULT '{}',
  status           TEXT    NOT NULL DEFAULT 'PENDING',
  expires_at       TIMESTAMPTZ NOT NULL,
  redeemed_at      TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_oauth_attempts    PRIMARY KEY (id),
  CONSTRAINT uq_oa_state          UNIQUE (state),
  CONSTRAINT chk_oa_status        CHECK (status IN ('PENDING','REDEEMED','EXPIRED','FAILED')),
  CONSTRAINT chk_oa_expires       CHECK (expires_at > created_at),
  CONSTRAINT chk_oa_redirect_uri  CHECK (redirect_uri LIKE 'https://%' OR redirect_uri LIKE 'http://localhost%')
);

CREATE INDEX idx_oa_org_expires ON integrations.oauth_attempts (organization_id, expires_at);

ALTER TABLE integrations.oauth_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.oauth_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_oa_tenant ON integrations.oauth_attempts
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON integrations.oauth_attempts FROM app_api, app_worker;
GRANT SELECT, INSERT ON integrations.oauth_attempts TO app_api, app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON integrations.oauth_attempts TO app_platform_admin;

-- SECURITY DEFINER: redeem OAuth attempt (FIX-05)
CREATE OR REPLACE FUNCTION integrations.fn_redeem_oauth_attempt(
  p_state           TEXT,
  p_organization_id UUID
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
DECLARE
  v_id       UUID;
  v_status   TEXT;
  v_expires  TIMESTAMPTZ;
BEGIN
  SELECT id, status, expires_at INTO v_id, v_status, v_expires
  FROM integrations.oauth_attempts
  WHERE state = p_state AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: OAuth attempt not found for this organization';
  END IF;
  IF v_status = 'REDEEMED' THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % already redeemed', v_id;
  END IF;
  IF v_status IN ('EXPIRED','FAILED') THEN
    RAISE EXCEPTION 'integrations: OAuth attempt % is in terminal state %', v_id, v_status;
  END IF;
  IF v_expires <= NOW() THEN
    UPDATE integrations.oauth_attempts SET status = 'EXPIRED' WHERE id = v_id;
    RAISE EXCEPTION 'integrations: OAuth attempt % has expired', v_id;
  END IF;

  UPDATE integrations.oauth_attempts
  SET status = 'REDEEMED', redeemed_at = NOW()
  WHERE id = v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_redeem_oauth_attempt(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_redeem_oauth_attempt(TEXT, UUID)
  TO app_api, app_worker, app_platform_admin;

-- ----------------------------------------------------------------
-- integration_health
-- ----------------------------------------------------------------
CREATE TABLE integrations.integration_health (
  id                         UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id            UUID    NOT NULL,
  integration_connection_id  UUID    NOT NULL
    REFERENCES integrations.integration_connections(id) ON DELETE CASCADE,
  last_success_at            TIMESTAMPTZ NULL,
  last_failure_at            TIMESTAMPTZ NULL,
  consecutive_failure_count  INTEGER NOT NULL DEFAULT 0,
  last_failure_reason        TEXT    NULL,
  auth_failure_count         INTEGER NOT NULL DEFAULT 0,
  rate_limit_reset_at        TIMESTAMPTZ NULL,
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_integration_health       PRIMARY KEY (id),
  CONSTRAINT uq_ih_connection            UNIQUE (integration_connection_id),
  CONSTRAINT chk_ih_failure_count        CHECK (consecutive_failure_count >= 0),
  CONSTRAINT chk_ih_auth_count           CHECK (auth_failure_count >= 0),
  CONSTRAINT chk_ih_failure_reason_len   CHECK (last_failure_reason IS NULL OR length(last_failure_reason) <= 1000)
);

CREATE INDEX idx_ih_org ON integrations.integration_health (organization_id);

CREATE TRIGGER trg_ih_updated_at
  BEFORE UPDATE ON integrations.integration_health
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE integrations.integration_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.integration_health FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_ih_tenant ON integrations.integration_health
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT ON integrations.integration_health TO app_api, app_readonly;
GRANT SELECT, INSERT, UPDATE ON integrations.integration_health TO app_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON integrations.integration_health TO app_platform_admin;

-- SECURITY DEFINER: rotate credential (FIX-05)
CREATE OR REPLACE FUNCTION integrations.fn_rotate_integration_credential(
  p_organization_id           UUID,
  p_integration_connection_id UUID,
  p_new_credential_ref        TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  IF p_new_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'integrations: new credential_ref must be a secret_manager:// reference';
  END IF;

  UPDATE integrations.integration_connections
  SET credential_ref = p_new_credential_ref, updated_at = NOW()
  WHERE id = p_integration_connection_id
    AND organization_id = p_organization_id
    AND status NOT IN ('DISCONNECTED','FAILED');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'integrations: connection not found or is in terminal state';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_rotate_integration_credential(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_rotate_integration_credential(UUID, UUID, TEXT)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: GDPR anonymize org (FIX-05)
CREATE OR REPLACE FUNCTION integrations.fn_integrations_anonymize_org(
  p_organization_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = integrations, pg_catalog AS $$
BEGIN
  UPDATE integrations.integration_connections
  SET external_account_name = '[redacted]',
      external_account_ref  = NULL,
      status                = CASE WHEN status NOT IN ('DISCONNECTED','FAILED')
                                   THEN 'DISCONNECTED' ELSE status END,
      disconnected_at       = CASE WHEN status NOT IN ('DISCONNECTED','FAILED')
                                   THEN NOW() ELSE disconnected_at END,
      disconnect_reason     = 'gdpr_erasure',
      updated_at            = NOW()
  WHERE organization_id = p_organization_id;
END;
$$;
REVOKE ALL ON FUNCTION integrations.fn_integrations_anonymize_org(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION integrations.fn_integrations_anonymize_org(UUID) TO app_platform_admin;

-- ================================================================
-- Migration 062: webhook_endpoints and inbound_webhook_events
-- ================================================================

CREATE TABLE webhooks.webhook_endpoints (
  id                   UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id      UUID    NOT NULL,
  display_name         TEXT    NOT NULL,
  target_url           TEXT    NOT NULL,
  signing_secret_ref   TEXT    NOT NULL,
  topics               TEXT[]  NOT NULL,
  status               TEXT    NOT NULL DEFAULT 'ACTIVE',
  max_attempts         INTEGER NOT NULL DEFAULT 7,
  timeout_ms           INTEGER NOT NULL DEFAULT 10000,
  endpoint_verified_at TIMESTAMPTZ NULL,
  created_by_ref       UUID    NULL,
  last_delivery_at     TIMESTAMPTZ NULL,
  disabled_at          TIMESTAMPTZ NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_webhook_endpoints       PRIMARY KEY (id),
  CONSTRAINT chk_we_target_https        CHECK (target_url LIKE 'https://%'),
  CONSTRAINT chk_we_signing_secret_ref  CHECK (signing_secret_ref LIKE 'secret_manager://%'),
  CONSTRAINT chk_we_topics_nonempty     CHECK (array_length(topics, 1) > 0),
  CONSTRAINT chk_we_status              CHECK (status IN ('ACTIVE','DISABLED','SUSPENDED')),
  CONSTRAINT chk_we_max_attempts        CHECK (max_attempts BETWEEN 1 AND 10),
  CONSTRAINT chk_we_timeout_ms          CHECK (timeout_ms BETWEEN 1000 AND 30000),
  CONSTRAINT chk_we_display_name        CHECK (length(display_name) BETWEEN 1 AND 200)
);

CREATE INDEX idx_we_org_status ON webhooks.webhook_endpoints (organization_id, status);
CREATE INDEX idx_we_org_topics ON webhooks.webhook_endpoints USING GIN (topics)
  WHERE status = 'ACTIVE';

CREATE TRIGGER trg_we_updated_at
  BEFORE UPDATE ON webhooks.webhook_endpoints
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE webhooks.webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks.webhook_endpoints FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_we_tenant ON webhooks.webhook_endpoints
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

GRANT SELECT, INSERT, UPDATE ON webhooks.webhook_endpoints TO app_api, app_worker;
GRANT SELECT ON webhooks.webhook_endpoints TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON webhooks.webhook_endpoints TO app_platform_admin;

-- ----------------------------------------------------------------
-- inbound_webhook_events (FIX-08: UNIQUE key includes organization_id)
-- ----------------------------------------------------------------
CREATE TABLE webhooks.inbound_webhook_events (
  id                UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id   UUID    NOT NULL,
  provider_slug     TEXT    NOT NULL,
  provider_event_id TEXT    NOT NULL,
  event_type        TEXT    NOT NULL,
  signature_header  TEXT    NULL,
  signature_valid   BOOLEAN NULL,
  raw_payload_ref   TEXT    NULL,
  status            TEXT    NOT NULL DEFAULT 'RECEIVED',
  received_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at      TIMESTAMPTZ NULL,
  failure_reason    TEXT    NULL,

  CONSTRAINT pk_inbound_webhook_events    PRIMARY KEY (id),
  -- FIX-08: scoped to tenant — different tenants may share provider_event_id
  CONSTRAINT uq_iwe_org_provider_event    UNIQUE (organization_id, provider_slug, provider_event_id),
  CONSTRAINT chk_iwe_status               CHECK (status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED','SKIPPED')),
  CONSTRAINT chk_iwe_provider_slug        CHECK (length(provider_slug) BETWEEN 1 AND 100),
  CONSTRAINT chk_iwe_provider_event_id    CHECK (length(provider_event_id) BETWEEN 1 AND 500),
  CONSTRAINT chk_iwe_failure_reason_len   CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000)
);

CREATE INDEX idx_iwe_org_status ON webhooks.inbound_webhook_events (organization_id, status, received_at DESC);
CREATE INDEX idx_iwe_org_type   ON webhooks.inbound_webhook_events (organization_id, event_type, received_at DESC);

ALTER TABLE webhooks.inbound_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks.inbound_webhook_events FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_iwe_tenant ON webhooks.inbound_webhook_events
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

REVOKE UPDATE, DELETE ON webhooks.inbound_webhook_events FROM app_api, app_worker;
GRANT SELECT, INSERT ON webhooks.inbound_webhook_events TO app_api, app_worker;
GRANT SELECT ON webhooks.inbound_webhook_events TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON webhooks.inbound_webhook_events TO app_platform_admin;

-- SECURITY DEFINER: update inbound event status (FIX-05)
CREATE OR REPLACE FUNCTION webhooks.fn_update_inbound_event_status(
  p_id              UUID,
  p_organization_id UUID,
  p_new_status      TEXT,
  p_failure_reason  TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
DECLARE
  v_current TEXT;
BEGIN
  IF p_new_status NOT IN ('PROCESSING','PROCESSED','FAILED','SKIPPED') THEN
    RAISE EXCEPTION 'webhooks: invalid target status %', p_new_status;
  END IF;

  SELECT status INTO v_current
  FROM webhooks.inbound_webhook_events
  WHERE id = p_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'webhooks: inbound event not found';
  END IF;
  IF v_current IN ('PROCESSED','SKIPPED') THEN
    RETURN; -- idempotent
  END IF;

  UPDATE webhooks.inbound_webhook_events
  SET status         = p_new_status,
      processed_at   = CASE WHEN p_new_status IN ('PROCESSED','FAILED','SKIPPED')
                            THEN NOW() ELSE processed_at END,
      failure_reason = CASE WHEN p_failure_reason IS NOT NULL
                            THEN LEFT(p_failure_reason, 2000) ELSE failure_reason END
  WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_update_inbound_event_status(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_update_inbound_event_status(UUID, UUID, TEXT, TEXT)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 063: webhook_deliveries (partitioned) and SECURITY DEFINER functions
-- ================================================================

CREATE TABLE webhooks.webhook_deliveries (
  id                         UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id            UUID    NOT NULL,
  webhook_endpoint_id        UUID    NOT NULL,   -- logical ref; no FK (cross-partition safe)
  event_type                 TEXT    NOT NULL,   -- immutable identity field
  event_id                   UUID    NOT NULL,   -- immutable source event identity
  payload_json               TEXT    NOT NULL,   -- immutable delivery content
  payload_hash               TEXT    NOT NULL,   -- immutable SHA-256 of payload_json
  status                     TEXT    NOT NULL DEFAULT 'PENDING',
  attempt_count              INTEGER NOT NULL DEFAULT 0,
  max_attempts               INTEGER NOT NULL DEFAULT 7,
  next_attempt_at            TIMESTAMPTZ NULL,
  last_attempt_at            TIMESTAMPTZ NULL,
  last_response_code         INTEGER NULL,
  last_response_body_preview TEXT    NULL,
  claimed_by                 TEXT    NULL,
  claimed_at                 TIMESTAMPTZ NULL,
  completed_at               TIMESTAMPTZ NULL,
  failure_reason             TEXT    NULL,
  replay_of_delivery_id      UUID    NULL,       -- set for replay rows
  replay_count               INTEGER NOT NULL DEFAULT 0,
  last_replayed_at           TIMESTAMPTZ NULL,
  resolved_at                TIMESTAMPTZ NULL,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_webhook_deliveries       PRIMARY KEY (id, created_at),
  CONSTRAINT chk_wd_status               CHECK (status IN ('PENDING','DELIVERING','DELIVERED',
                                                           'FAILED','DEAD_LETTER','CANCELLED')),
  CONSTRAINT chk_wd_max_attempts         CHECK (max_attempts BETWEEN 1 AND 10),
  CONSTRAINT chk_wd_attempt_count        CHECK (attempt_count >= 0),
  CONSTRAINT chk_wd_preview_length       CHECK (last_response_body_preview IS NULL OR
                                                 length(last_response_body_preview) <= 512),
  CONSTRAINT chk_wd_failure_reason_len   CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000),
  CONSTRAINT chk_wd_payload_nonempty     CHECK (length(payload_json) > 0)
) PARTITION BY RANGE (created_at);

CREATE TABLE webhooks.webhook_deliveries_y2026m08
  PARTITION OF webhooks.webhook_deliveries
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE webhooks.webhook_deliveries_y2026m09
  PARTITION OF webhooks.webhook_deliveries
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE webhooks.webhook_deliveries_y2026m10
  PARTITION OF webhooks.webhook_deliveries
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE webhooks.webhook_deliveries_default
  PARTITION OF webhooks.webhook_deliveries DEFAULT;

CREATE INDEX idx_wd_pending  ON webhooks.webhook_deliveries (organization_id, next_attempt_at)
  WHERE status = 'PENDING';
CREATE INDEX idx_wd_endpoint ON webhooks.webhook_deliveries (webhook_endpoint_id, created_at DESC);
CREATE INDEX idx_wd_status   ON webhooks.webhook_deliveries (organization_id, status);
CREATE INDEX idx_wd_replay   ON webhooks.webhook_deliveries (replay_of_delivery_id)
  WHERE replay_of_delivery_id IS NOT NULL;

-- FIX-09: identity/content immutability trigger (renamed from fn_wd_payload_immutable)
-- Immutable fields: payload_json, payload_hash, event_id, event_type, webhook_endpoint_id, organization_id
CREATE OR REPLACE FUNCTION webhooks.fn_wd_identity_immutable()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
BEGIN
  IF NEW.payload_json        <> OLD.payload_json
  OR NEW.payload_hash        <> OLD.payload_hash
  OR NEW.event_id            <> OLD.event_id
  OR NEW.event_type          <> OLD.event_type
  OR NEW.webhook_endpoint_id <> OLD.webhook_endpoint_id
  OR NEW.organization_id     <> OLD.organization_id
  THEN
    RAISE EXCEPTION 'webhooks: delivery identity/content fields are immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_wd_identity_immutable() FROM PUBLIC;

CREATE TRIGGER trg_wd_identity_immutable
  BEFORE UPDATE ON webhooks.webhook_deliveries
  FOR EACH ROW EXECUTE FUNCTION webhooks.fn_wd_identity_immutable();

ALTER TABLE webhooks.webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks.webhook_deliveries FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_wd_tenant ON webhooks.webhook_deliveries
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- Direct UPDATE/DELETE prohibited for app_api and app_worker
REVOKE UPDATE, DELETE ON webhooks.webhook_deliveries FROM app_api, app_worker;
GRANT SELECT, INSERT ON webhooks.webhook_deliveries TO app_api, app_worker;
GRANT SELECT ON webhooks.webhook_deliveries TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON webhooks.webhook_deliveries TO app_platform_admin;

-- SECURITY DEFINER: claim pending deliveries (FIX-05)
CREATE OR REPLACE FUNCTION webhooks.fn_claim_delivery(
  p_worker_id TEXT,
  p_limit     INTEGER DEFAULT 10
) RETURNS SETOF UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
BEGIN
  RETURN QUERY
  UPDATE webhooks.webhook_deliveries
  SET status     = 'DELIVERING',
      claimed_by = p_worker_id,
      claimed_at = NOW()
  WHERE id IN (
    SELECT id
    FROM webhooks.webhook_deliveries
    WHERE status = 'PENDING'
      AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())
    ORDER BY next_attempt_at ASC NULLS FIRST, created_at ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_claim_delivery(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_claim_delivery(TEXT, INTEGER)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: record delivery success (FIX-05)
CREATE OR REPLACE FUNCTION webhooks.fn_delivery_succeeded(
  p_delivery_id      UUID,
  p_created_at       TIMESTAMPTZ,
  p_response_code    INTEGER,
  p_response_preview TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
BEGIN
  UPDATE webhooks.webhook_deliveries
  SET status                     = 'DELIVERED',
      last_response_code         = p_response_code,
      last_response_body_preview = LEFT(COALESCE(p_response_preview, ''), 512),
      attempt_count              = attempt_count + 1,
      last_attempt_at            = NOW(),
      completed_at               = NOW(),
      claimed_by                 = NULL,
      claimed_at                 = NULL
  WHERE id = p_delivery_id
    AND created_at = p_created_at
    AND status = 'DELIVERING';
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_delivery_succeeded(UUID, TIMESTAMPTZ, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_delivery_succeeded(UUID, TIMESTAMPTZ, INTEGER, TEXT)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: record delivery failure (FIX-02: DB enforces max_attempts ceiling; FIX-05)
-- Returns resulting status: 'PENDING' or 'DEAD_LETTER'
CREATE OR REPLACE FUNCTION webhooks.fn_delivery_failed(
  p_delivery_id      UUID,
  p_created_at       TIMESTAMPTZ,
  p_response_code    INTEGER DEFAULT NULL,
  p_response_preview TEXT DEFAULT NULL,
  p_failure_reason   TEXT DEFAULT NULL,
  p_next_attempt_at  TIMESTAMPTZ DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
DECLARE
  v_current_count INTEGER;
  v_max_attempts  INTEGER;
  v_new_count     INTEGER;
  v_new_status    TEXT;
  v_next_at       TIMESTAMPTZ;
BEGIN
  SELECT attempt_count, max_attempts
  INTO v_current_count, v_max_attempts
  FROM webhooks.webhook_deliveries
  WHERE id = p_delivery_id AND created_at = p_created_at AND status = 'DELIVERING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'webhooks: delivery % not found or not in DELIVERING state', p_delivery_id;
  END IF;

  v_new_count := v_current_count + 1;

  -- FIX-02: DB enforces the ceiling — ignores p_next_attempt_at when limit reached
  IF v_new_count >= v_max_attempts THEN
    v_new_status := 'DEAD_LETTER';
    v_next_at    := NULL;
  ELSE
    v_new_status := 'PENDING';
    v_next_at    := p_next_attempt_at;
  END IF;

  UPDATE webhooks.webhook_deliveries
  SET status                     = v_new_status,
      attempt_count              = v_new_count,
      last_attempt_at            = NOW(),
      last_response_code         = p_response_code,
      last_response_body_preview = LEFT(COALESCE(p_response_preview, ''), 512),
      failure_reason             = LEFT(COALESCE(p_failure_reason, failure_reason, ''), 2000),
      next_attempt_at            = v_next_at,
      completed_at               = CASE WHEN v_new_status = 'DEAD_LETTER' THEN NOW() ELSE NULL END,
      claimed_by                 = NULL,
      claimed_at                 = NULL
  WHERE id = p_delivery_id AND created_at = p_created_at;

  RETURN v_new_status;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_delivery_failed(UUID, TIMESTAMPTZ, INTEGER, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_delivery_failed(UUID, TIMESTAMPTZ, INTEGER, TEXT, TEXT, TIMESTAMPTZ)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: replay delivery (FIX-05; FIX-10: clarified replay metadata vs. history)
CREATE OR REPLACE FUNCTION webhooks.fn_replay_webhook_delivery(
  p_organization_id UUID,
  p_delivery_id     UUID,
  p_created_at      TIMESTAMPTZ
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = webhooks, pg_catalog AS $$
DECLARE
  v_orig            RECORD;
  v_new_id          UUID := gen_uuid_v7();
  v_existing_replay UUID;
BEGIN
  SELECT * INTO v_orig
  FROM webhooks.webhook_deliveries
  WHERE id = p_delivery_id AND created_at = p_created_at AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'webhooks: delivery not found';
  END IF;
  IF v_orig.status NOT IN ('DEAD_LETTER','DELIVERED') THEN
    RAISE EXCEPTION 'webhooks: only DEAD_LETTER or DELIVERED deliveries can be replayed; status = %',
      v_orig.status;
  END IF;

  -- Idempotency: return existing non-completed replay
  SELECT id INTO v_existing_replay
  FROM webhooks.webhook_deliveries
  WHERE replay_of_delivery_id = p_delivery_id AND status IN ('PENDING','DELIVERING');
  IF FOUND THEN
    RETURN v_existing_replay;
  END IF;

  -- New delivery row: inherits identity from original; fresh lifecycle state
  INSERT INTO webhooks.webhook_deliveries
    (id, organization_id, webhook_endpoint_id, event_type, event_id,
     payload_json, payload_hash, status, max_attempts, next_attempt_at, replay_of_delivery_id)
  VALUES
    (v_new_id, p_organization_id, v_orig.webhook_endpoint_id,
     v_orig.event_type, v_orig.event_id,
     v_orig.payload_json, v_orig.payload_hash,
     'PENDING', v_orig.max_attempts, NOW(), p_delivery_id);

  -- Update replay metadata on original (payload/result history untouched — FIX-10)
  UPDATE webhooks.webhook_deliveries
  SET replay_count     = replay_count + 1,
      last_replayed_at = NOW()
  WHERE id = p_delivery_id AND created_at = p_created_at;

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION webhooks.fn_replay_webhook_delivery(UUID, UUID, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION webhooks.fn_replay_webhook_delivery(UUID, UUID, TIMESTAMPTZ)
  TO app_worker, app_platform_admin;

-- ================================================================
-- Migration 064: plugins and plugin_versions
-- ================================================================

CREATE TABLE plugins.plugins (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  developer_org_id UUID    NOT NULL,
  slug             TEXT    NOT NULL,
  name             TEXT    NOT NULL,
  description      TEXT    NULL,
  status           TEXT    NOT NULL DEFAULT 'PENDING_REVIEW',
  documentation_url TEXT   NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_plugins      PRIMARY KEY (id),
  CONSTRAINT uq_plugin_slug  UNIQUE (slug),
  CONSTRAINT chk_plug_slug   CHECK (slug ~ '^[a-z][a-z0-9_-]{0,98}[a-z0-9]$'),
  CONSTRAINT chk_plug_status CHECK (status IN ('PENDING_REVIEW','APPROVED','REJECTED')),
  CONSTRAINT chk_plug_name   CHECK (length(name) BETWEEN 1 AND 100)
);

CREATE OR REPLACE FUNCTION plugins.fn_plug_slug_immutable()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF NEW.slug <> OLD.slug THEN
    RAISE EXCEPTION 'plugins.slug is immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_plug_slug_immutable() FROM PUBLIC;

CREATE TRIGGER trg_plug_slug_immutable
  BEFORE UPDATE ON plugins.plugins
  FOR EACH ROW EXECUTE FUNCTION plugins.fn_plug_slug_immutable();

CREATE TRIGGER trg_plug_updated_at
  BEFORE UPDATE ON plugins.plugins
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_pl_status ON plugins.plugins (status);

GRANT SELECT ON plugins.plugins TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON plugins.plugins TO app_platform_admin;

-- ----------------------------------------------------------------
-- plugin_versions
-- ----------------------------------------------------------------
CREATE TABLE plugins.plugin_versions (
  id               UUID    NOT NULL DEFAULT gen_uuid_v7(),
  plugin_id        UUID    NOT NULL REFERENCES plugins.plugins(id) ON DELETE RESTRICT,
  semver           TEXT    NOT NULL,
  manifest         JSONB   NOT NULL,
  status           TEXT    NOT NULL DEFAULT 'PENDING_REVIEW',
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at      TIMESTAMPTZ NULL,
  approved_by_ref  UUID    NULL,
  rejected_at      TIMESTAMPTZ NULL,
  rejection_reason TEXT    NULL,
  deprecated_at    TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_plugin_versions      PRIMARY KEY (id),
  CONSTRAINT uq_pv_plugin_semver     UNIQUE (plugin_id, semver),
  CONSTRAINT chk_pv_status           CHECK (status IN ('PENDING_REVIEW','APPROVED','REJECTED','DEPRECATED')),
  CONSTRAINT chk_pv_semver           CHECK (semver ~ '^\d+\.\d+\.\d+'),
  CONSTRAINT chk_pv_manifest_object  CHECK (jsonb_typeof(manifest) = 'object'),
  CONSTRAINT chk_pv_approved_has_at  CHECK (
    (status = 'APPROVED' AND approved_at IS NOT NULL) OR status <> 'APPROVED'
  )
);

-- FIX-05: search_path hardened
CREATE OR REPLACE FUNCTION plugins.fn_pv_manifest_immutable()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF OLD.approved_at IS NOT NULL AND NEW.manifest <> OLD.manifest THEN
    RAISE EXCEPTION 'plugins: plugin_version manifest is immutable after approval';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_pv_manifest_immutable() FROM PUBLIC;

CREATE TRIGGER trg_pv_manifest_immutable
  BEFORE UPDATE ON plugins.plugin_versions
  FOR EACH ROW EXECUTE FUNCTION plugins.fn_pv_manifest_immutable();

CREATE INDEX idx_pv_plugin   ON plugins.plugin_versions (plugin_id, semver);
CREATE INDEX idx_pv_approved ON plugins.plugin_versions (plugin_id) WHERE status = 'APPROVED';

GRANT SELECT ON plugins.plugin_versions TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE ON plugins.plugin_versions TO app_platform_admin;

-- ================================================================
-- Migration 065: plugin_installations and plugin_executions
-- ================================================================

CREATE TABLE plugins.plugin_installations (
  id                    UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id       UUID    NOT NULL,
  plugin_id             UUID    NOT NULL REFERENCES plugins.plugins(id) ON DELETE RESTRICT,
  plugin_version_id     UUID    NOT NULL REFERENCES plugins.plugin_versions(id) ON DELETE RESTRICT,
  status                TEXT    NOT NULL DEFAULT 'INSTALLED',
  configuration         JSONB   NOT NULL DEFAULT '{}',
  credential_ref        TEXT    NULL,
  enabled_capabilities  TEXT[]  NOT NULL DEFAULT '{}',
  rate_limit_override   INTEGER NULL,
  installed_by_ref      UUID    NULL,
  installed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  activated_at          TIMESTAMPTZ NULL,
  suspended_at          TIMESTAMPTZ NULL,
  uninstalled_at        TIMESTAMPTZ NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pk_plugin_installations    PRIMARY KEY (id),
  CONSTRAINT chk_pi_status              CHECK (status IN ('INSTALLED','ACTIVE','SUSPENDED','UNINSTALLED')),
  CONSTRAINT chk_pi_credential_ref      CHECK (
    credential_ref IS NULL OR credential_ref LIKE 'secret_manager://%'
  ),
  CONSTRAINT chk_pi_rate_limit          CHECK (rate_limit_override IS NULL OR rate_limit_override > 0),
  CONSTRAINT chk_pi_uninstalled         CHECK (
    (status = 'UNINSTALLED' AND uninstalled_at IS NOT NULL) OR status <> 'UNINSTALLED'
  )
);

CREATE UNIQUE INDEX uq_pi_org_plugin_active
  ON plugins.plugin_installations (organization_id, plugin_id)
  WHERE status NOT IN ('UNINSTALLED');

CREATE INDEX idx_pi_org_status ON plugins.plugin_installations (organization_id, status);
CREATE INDEX idx_pi_version    ON plugins.plugin_installations (plugin_version_id);

-- FIX-03: blocks ALL direct plugin_version_id changes
-- fn_upgrade_plugin() sets session variable plugins.upgrade_in_progress = 'true' (local to transaction)
-- to permit the change exclusively within its own transaction.
CREATE OR REPLACE FUNCTION plugins.fn_pi_version_immutable()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF NEW.plugin_version_id <> OLD.plugin_version_id THEN
    -- current_setting with TRUE suppresses "variable not found" error; returns NULL instead
    IF current_setting('plugins.upgrade_in_progress', TRUE) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION
        'plugins: plugin_version_id is immutable; use fn_upgrade_plugin() to change the version';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_pi_version_immutable() FROM PUBLIC;

CREATE TRIGGER trg_pi_version_immutable
  BEFORE UPDATE ON plugins.plugin_installations
  FOR EACH ROW EXECUTE FUNCTION plugins.fn_pi_version_immutable();

-- Terminal state guard (FIX-05)
CREATE OR REPLACE FUNCTION plugins.fn_pi_terminal_guard()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
BEGIN
  IF OLD.status = 'UNINSTALLED' AND NEW.status <> 'UNINSTALLED' THEN
    RAISE EXCEPTION 'plugins: installation % is UNINSTALLED (terminal)', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_pi_terminal_guard() FROM PUBLIC;

CREATE TRIGGER trg_pi_terminal_guard
  BEFORE UPDATE ON plugins.plugin_installations
  FOR EACH ROW EXECUTE FUNCTION plugins.fn_pi_terminal_guard();

CREATE TRIGGER trg_pi_updated_at
  BEFORE UPDATE ON plugins.plugin_installations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE plugins.plugin_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE plugins.plugin_installations FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pi_tenant ON plugins.plugin_installations
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- app roles cannot directly INSERT/UPDATE/DELETE installations
REVOKE INSERT, UPDATE, DELETE ON plugins.plugin_installations FROM app_api, app_worker;
GRANT SELECT ON plugins.plugin_installations TO app_api, app_worker, app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON plugins.plugin_installations TO app_platform_admin;

-- SECURITY DEFINER: create plugin installation (FIX-04: validates plugin/version ownership)
CREATE OR REPLACE FUNCTION plugins.fn_create_plugin_installation(
  p_organization_id   UUID,
  p_plugin_id         UUID,
  p_plugin_version_id UUID,
  p_configuration     JSONB DEFAULT '{}',
  p_credential_ref    TEXT DEFAULT NULL,
  p_installed_by_ref  UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_plugin_status  TEXT;
  v_version_status TEXT;
  v_version_plugin UUID;
  v_new_id         UUID;
BEGIN
  -- FIX-04: verify version belongs to same plugin; both must be APPROVED
  SELECT pv.status, pv.plugin_id, pl.status
  INTO v_version_status, v_version_plugin, v_plugin_status
  FROM plugins.plugin_versions pv
  JOIN plugins.plugins pl ON pl.id = pv.plugin_id
  WHERE pv.id = p_plugin_version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: plugin version % not found', p_plugin_version_id;
  END IF;
  IF v_version_plugin <> p_plugin_id THEN
    RAISE EXCEPTION 'plugins: version % does not belong to plugin %',
      p_plugin_version_id, p_plugin_id;
  END IF;
  IF v_plugin_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin % is not APPROVED (status=%)', p_plugin_id, v_plugin_status;
  END IF;
  IF v_version_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: version % is not APPROVED (status=%)',
      p_plugin_version_id, v_version_status;
  END IF;
  IF p_credential_ref IS NOT NULL AND p_credential_ref NOT LIKE 'secret_manager://%' THEN
    RAISE EXCEPTION 'plugins: credential_ref must be a secret_manager:// reference';
  END IF;

  INSERT INTO plugins.plugin_installations
    (organization_id, plugin_id, plugin_version_id, configuration,
     credential_ref, installed_by_ref)
  VALUES
    (p_organization_id, p_plugin_id, p_plugin_version_id, p_configuration,
     p_credential_ref, p_installed_by_ref)
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_create_plugin_installation(UUID, UUID, UUID, JSONB, TEXT, UUID)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_create_plugin_installation(UUID, UUID, UUID, JSONB, TEXT, UUID)
  TO app_api, app_worker, app_platform_admin;

-- SECURITY DEFINER: activate plugin (FIX-06: validates capability subset + APPROVED status)
CREATE OR REPLACE FUNCTION plugins.fn_activate_plugin(
  p_organization_id      UUID,
  p_installation_id      UUID,
  p_enabled_capabilities TEXT[]
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_inst          RECORD;
  v_manifest_caps TEXT[];
  v_cap           TEXT;
BEGIN
  SELECT pi.status, pi.plugin_version_id,
         pv.status AS version_status, pl.status AS plugin_status, pv.manifest
  INTO v_inst
  FROM plugins.plugin_installations pi
  JOIN plugins.plugin_versions pv ON pv.id = pi.plugin_version_id
  JOIN plugins.plugins pl ON pl.id = pi.plugin_id
  WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_inst.status NOT IN ('INSTALLED','SUSPENDED') THEN
    RAISE EXCEPTION 'plugins: cannot activate from status %', v_inst.status;
  END IF;
  -- FIX-06: both plugin and version must still be APPROVED
  IF v_inst.plugin_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin is not APPROVED';
  END IF;
  IF v_inst.version_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: plugin version is not APPROVED (status=%)', v_inst.version_status;
  END IF;

  -- FIX-06: validate enabled_capabilities ⊆ manifest.capabilities
  SELECT ARRAY(SELECT jsonb_array_elements_text(v_inst.manifest -> 'capabilities'))
  INTO v_manifest_caps;

  FOREACH v_cap IN ARRAY p_enabled_capabilities LOOP
    IF NOT (v_cap = ANY(v_manifest_caps)) THEN
      RAISE EXCEPTION 'plugins: capability % is not in the plugin version manifest', v_cap;
    END IF;
  END LOOP;

  UPDATE plugins.plugin_installations
  SET status               = 'ACTIVE',
      enabled_capabilities = p_enabled_capabilities,
      activated_at         = COALESCE(activated_at, NOW()),
      updated_at           = NOW()
  WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_activate_plugin(UUID, UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_activate_plugin(UUID, UUID, TEXT[])
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: uninstall plugin (FIX-05)
CREATE OR REPLACE FUNCTION plugins.fn_uninstall_plugin(
  p_organization_id UUID,
  p_installation_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_status TEXT;
BEGIN
  SELECT status INTO v_status
  FROM plugins.plugin_installations
  WHERE id = p_installation_id AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found';
  END IF;
  IF v_status = 'UNINSTALLED' THEN
    RETURN; -- idempotent
  END IF;

  UPDATE plugins.plugin_installations
  SET status         = 'UNINSTALLED',
      uninstalled_at = NOW(),
      updated_at     = NOW()
  WHERE id = p_installation_id;
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_uninstall_plugin(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_uninstall_plugin(UUID, UUID)
  TO app_worker, app_platform_admin;

-- SECURITY DEFINER: upgrade plugin version (FIX-03, FIX-04)
-- Uses SET LOCAL session flag to permit the version-immutability trigger within this transaction only.
CREATE OR REPLACE FUNCTION plugins.fn_upgrade_plugin(
  p_organization_id   UUID,
  p_installation_id   UUID,
  p_new_version_id    UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = plugins, pg_catalog AS $$
DECLARE
  v_inst       RECORD;
  v_new_ver    RECORD;
BEGIN
  SELECT pi.status, pi.plugin_id, pi.plugin_version_id
  INTO v_inst
  FROM plugins.plugin_installations pi
  WHERE pi.id = p_installation_id AND pi.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: installation not found for this organization';
  END IF;
  IF v_inst.status = 'UNINSTALLED' THEN
    RAISE EXCEPTION 'plugins: cannot upgrade UNINSTALLED installation';
  END IF;

  -- FIX-04: verify new version belongs to same plugin
  SELECT pv.plugin_id, pv.status
  INTO v_new_ver
  FROM plugins.plugin_versions pv
  WHERE pv.id = p_new_version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plugins: new version % not found', p_new_version_id;
  END IF;
  IF v_new_ver.plugin_id <> v_inst.plugin_id THEN
    RAISE EXCEPTION 'plugins: version % does not belong to the same plugin', p_new_version_id;
  END IF;
  IF v_new_ver.status <> 'APPROVED' THEN
    RAISE EXCEPTION 'plugins: new version % is not APPROVED (status=%)',
      p_new_version_id, v_new_ver.status;
  END IF;
  IF p_new_version_id = v_inst.plugin_version_id THEN
    RETURN; -- already on this version; idempotent
  END IF;

  -- Set transaction-local flag to allow fn_pi_version_immutable to pass
  PERFORM set_config('plugins.upgrade_in_progress', 'true', TRUE);

  UPDATE plugins.plugin_installations
  SET plugin_version_id    = p_new_version_id,
      enabled_capabilities = '{}',    -- reset; tenant must re-activate
      status               = 'INSTALLED',
      updated_at           = NOW()
  WHERE id = p_installation_id;

  -- Reset (belt-and-suspenders; set_config(..., TRUE) already limits to transaction)
  PERFORM set_config('plugins.upgrade_in_progress', 'false', TRUE);
END;
$$;
REVOKE ALL ON FUNCTION plugins.fn_upgrade_plugin(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION plugins.fn_upgrade_plugin(UUID, UUID, UUID)
  TO app_worker, app_platform_admin;

-- ----------------------------------------------------------------
-- plugin_executions
-- ----------------------------------------------------------------
CREATE TABLE plugins.plugin_executions (
  id                     UUID    NOT NULL DEFAULT gen_uuid_v7(),
  organization_id        UUID    NOT NULL,
  plugin_installation_id UUID    NOT NULL REFERENCES plugins.plugin_installations(id) ON DELETE RESTRICT,
  plugin_version_id      UUID    NOT NULL REFERENCES plugins.plugin_versions(id) ON DELETE RESTRICT,
  capability             TEXT    NOT NULL,
  endpoint               TEXT    NOT NULL,
  status                 TEXT    NOT NULL DEFAULT 'PENDING',
  input_preview          TEXT    NULL,
  input_ref              TEXT    NULL,
  output_preview         TEXT    NULL,
  output_ref             TEXT    NULL,
  http_status_code       INTEGER NULL,
  failure_reason         TEXT    NULL,
  correlation_id         UUID    NULL,
  idempotency_key        TEXT    NULL,
  started_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at           TIMESTAMPTZ NULL,

  CONSTRAINT pk_plugin_executions      PRIMARY KEY (id),
  CONSTRAINT chk_pe_status             CHECK (status IN ('PENDING','RUNNING','SUCCEEDED','FAILED','TIMED_OUT')),
  CONSTRAINT chk_pe_capability         CHECK (length(capability) BETWEEN 1 AND 100),
  CONSTRAINT chk_pe_endpoint           CHECK (length(endpoint) BETWEEN 1 AND 500),
  CONSTRAINT chk_pe_failure_reason_len CHECK (failure_reason IS NULL OR length(failure_reason) <= 2000)
);

CREATE INDEX idx_pe_installation ON plugins.plugin_executions (plugin_installation_id, started_at DESC);
CREATE INDEX idx_pe_org_status   ON plugins.plugin_executions (organization_id, status);
CREATE INDEX idx_pe_correlation  ON plugins.plugin_executions (correlation_id)
  WHERE correlation_id IS NOT NULL;

REVOKE UPDATE, DELETE ON plugins.plugin_executions FROM app_api;
GRANT SELECT, INSERT ON plugins.plugin_executions TO app_api;
GRANT SELECT, INSERT, UPDATE ON plugins.plugin_executions TO app_worker;
GRANT SELECT ON plugins.plugin_executions TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON plugins.plugin_executions TO app_platform_admin;

ALTER TABLE plugins.plugin_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE plugins.plugin_executions FORCE ROW LEVEL SECURITY;
CREATE POLICY rls_pe_tenant ON plugins.plugin_executions
  FOR ALL
  USING (organization_id = organization.current_tenant_id())
  WITH CHECK (organization_id = organization.current_tenant_id());

-- ================================================================
-- Migration 066: grants finalization
-- ================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA integrations TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA webhooks     TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA plugins      TO app_readonly;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA integrations TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA webhooks     TO app_platform_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA plugins      TO app_platform_admin;
```

---

## 29. Query Patterns

**QP-01 Register integration provider**
```sql
INSERT INTO integrations.integration_definitions
  (slug, name, auth_type, capabilities, required_scopes, manifest_version)
VALUES ($1, $2, $3, $4, $5, $6);
```

**QP-02 Create tenant integration connection (FIX-01)**
```sql
-- Use SECURITY DEFINER function; enforces V1 one-active rule transactionally.
-- Invalid ON CONFLICT ON CONSTRAINT <partial_index> pattern removed.
SELECT integrations.fn_create_integration_connection(
  $organization_id,
  $definition_id,
  $display_name,
  $credential_ref,   -- must be 'secret_manager://...'
  $configuration     -- JSONB, optional
);
-- Returns: new connection UUID
-- Raises exception if a non-terminal connection already exists for (org, definition).
-- Health row created automatically inside the function.
```

**QP-03 Revoke integration connection**
```sql
UPDATE integrations.integration_connections
SET status = 'DISCONNECTED', disconnected_at = NOW(),
    disconnect_reason = $reason, updated_at = NOW()
WHERE id = $id AND organization_id = $org_id
  AND status NOT IN ('DISCONNECTED','FAILED');
-- Terminal guard trigger prevents reversal.
```

**QP-04 Rotate credential**
```sql
SELECT integrations.fn_rotate_integration_credential($org_id, $connection_id, $new_ref);
```

**QP-05 Create webhook endpoint**
```sql
INSERT INTO webhooks.webhook_endpoints
  (organization_id, display_name, target_url, signing_secret_ref, topics, max_attempts, timeout_ms)
VALUES ($1, $2, $3, $4, $5::TEXT[], $6, $7);
-- Application layer must SSRF-validate target_url before inserting (FIX-07).
```

**QP-06 Update webhook topics**
```sql
UPDATE webhooks.webhook_endpoints
SET topics = $new_topics::TEXT[], updated_at = NOW()
WHERE id = $id AND organization_id = $org_id AND status <> 'SUSPENDED';
```

**QP-07 Record inbound webhook event (idempotent; FIX-08)**
```sql
INSERT INTO webhooks.inbound_webhook_events
  (organization_id, provider_slug, provider_event_id, event_type,
   signature_header, signature_valid, raw_payload_ref)
VALUES ($1, $2, $3, $4, $5, $6, $7)
ON CONFLICT (organization_id, provider_slug, provider_event_id) DO NOTHING;
-- Same org + same provider + same event_id → second INSERT ignored.
-- Different tenant + same provider + same event_id → both rows created (tenant-scoped).
```

**QP-08 Check inbound event status (scoped by org; FIX-08)**
```sql
SELECT status FROM webhooks.inbound_webhook_events
WHERE organization_id = $org_id
  AND provider_slug = $slug
  AND provider_event_id = $event_id;
```

**QP-09 Find active outbound subscriptions for topic**
```sql
SELECT id, organization_id, signing_secret_ref, target_url, max_attempts, timeout_ms
FROM webhooks.webhook_endpoints
WHERE organization_id = $org_id
  AND status = 'ACTIVE'
  AND topics && ARRAY[$event_topic]::TEXT[];
```

**QP-10 Create webhook delivery**
```sql
INSERT INTO webhooks.webhook_deliveries
  (organization_id, webhook_endpoint_id, event_type, event_id,
   payload_json, payload_hash, max_attempts)
VALUES ($1, $2, $3, $4, $5, $6, $7);
```

**QP-11 Claim pending deliveries (worker)**
```sql
SELECT webhooks.fn_claim_delivery($worker_id, 10);
-- Returns: set of UUIDs claimed by this worker.
```

**QP-12 Record delivery success**
```sql
SELECT webhooks.fn_delivery_succeeded($delivery_id, $created_at, $response_code, $preview);
```

**QP-13 Record delivery failure (FIX-02: DB enforces max_attempts)**
```sql
SELECT webhooks.fn_delivery_failed(
  $delivery_id,
  $created_at,
  $response_code,
  $response_preview,
  $failure_reason,
  $next_attempt_at  -- DB ignores this and forces DEAD_LETTER when new_count >= max_attempts
);
-- Returns: 'PENDING' or 'DEAD_LETTER'
```

**QP-14 Replay dead-lettered delivery**
```sql
SELECT webhooks.fn_replay_webhook_delivery($org_id, $delivery_id, $created_at);
-- Returns: UUID of new delivery row (or existing PENDING/DELIVERING replay if idempotent).
```

**QP-15 Register plugin (platform admin)**
```sql
INSERT INTO plugins.plugins (developer_org_id, slug, name, description)
VALUES ($1, $2, $3, $4)
RETURNING id;

INSERT INTO plugins.plugin_versions (plugin_id, semver, manifest)
VALUES ($plugin_id, $semver, $manifest_jsonb);
```

**QP-16 Install plugin (FIX-04)**
```sql
SELECT plugins.fn_create_plugin_installation(
  $organization_id,
  $plugin_id,
  $plugin_version_id,   -- must belong to same plugin; both must be APPROVED
  $configuration,
  $credential_ref,
  $installed_by_ref
);
-- Returns: installation UUID
```

**QP-17 Activate plugin (FIX-06)**
```sql
SELECT plugins.fn_activate_plugin(
  $organization_id,
  $installation_id,
  $enabled_capabilities::TEXT[]  -- must be ⊆ manifest.capabilities; plugin+version must be APPROVED
);
```

**QP-18 Upgrade plugin version (FIX-03, FIX-04)**
```sql
SELECT plugins.fn_upgrade_plugin($organization_id, $installation_id, $new_version_id);
-- Resets enabled_capabilities to '{}' and status to INSTALLED; re-activate via QP-17.
-- New version must belong to same plugin and be APPROVED.
```

**QP-19 Record plugin execution**
```sql
INSERT INTO plugins.plugin_executions
  (organization_id, plugin_installation_id, plugin_version_id,
   capability, endpoint, input_preview, correlation_id, idempotency_key)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id;

-- Update on completion (app_worker):
UPDATE plugins.plugin_executions
SET status           = $status,
    output_preview   = LEFT($output, 4096),
    http_status_code = $code,
    failure_reason   = LEFT($reason, 2000),
    completed_at     = NOW()
WHERE id = $exec_id AND organization_id = $org_id;
```

**QP-20 Uninstall plugin**
```sql
SELECT plugins.fn_uninstall_plugin($org_id, $install_id);
```

**QP-21 Check integration health**
```sql
SELECT ih.*, ic.status AS connection_status
FROM integrations.integration_health ih
JOIN integrations.integration_connections ic ON ic.id = ih.integration_connection_id
WHERE ih.integration_connection_id = $conn_id
  AND ic.organization_id = $org_id;
```

---

## 30. Migration Plan

```
Phase 5H last migration: 058_billing_grants_finalize
        ↓
Phase 5I migrations:

059_integrations_webhooks_plugins_schemas
    down_revision = '058_billing_grants_finalize'
    purpose: CREATE SCHEMA integrations/webhooks/plugins; GRANT USAGE on all three

060_integration_definitions
    down_revision = '059_integrations_webhooks_plugins_schemas'
    purpose: integration_definitions; fn_id_slug_immutable (search_path hardened — FIX-05);
             indexes; grants

061_integration_connections_oauth_health
    down_revision = '060_integration_definitions'
    purpose:
      integration_connections (terminal guard; credential_ref CHECK; len CHECKs;
                               idx_ic_org_def_nonterminal; REVOKE INSERT/UPDATE/DELETE);
      fn_create_integration_connection() SECURITY DEFINER (FIX-01: transactional uniqueness;
                                          search_path hardened — FIX-05);
      oauth_attempts (state UNIQUE; fn_redeem_oauth_attempt SECURITY DEFINER; FIX-05);
      integration_health (failure_reason len CHECK;
                          fn_rotate_integration_credential SECURITY DEFINER; FIX-05;
                          fn_integrations_anonymize_org SECURITY DEFINER; FIX-05);
      RLS + grants

062_webhook_endpoints_inbound
    down_revision = '061_integration_connections_oauth_health'
    purpose:
      webhook_endpoints (HTTPS CHECK; signing_secret_ref CHECK; GIN topic index);
      inbound_webhook_events (UNIQUE now includes organization_id — FIX-08;
                              failure_reason len CHECK;
                              fn_update_inbound_event_status SECURITY DEFINER; FIX-05);
      REVOKE UPDATE/DELETE on inbound_webhook_events; RLS; grants

063_webhook_deliveries_partitioned
    down_revision = '062_webhook_endpoints_inbound'
    purpose:
      webhook_deliveries (partitioned RANGE monthly; failure_reason len CHECK);
      fn_wd_identity_immutable trigger (FIX-09: expanded to cover all identity fields);
      3 initial partitions + DEFAULT;
      REVOKE UPDATE/DELETE from app_api and app_worker;
      fn_claim_delivery() SECURITY DEFINER (FIX-05);
      fn_delivery_succeeded() SECURITY DEFINER (FIX-05);
      fn_delivery_failed() SECURITY DEFINER (FIX-02: DB enforces max_attempts ceiling; FIX-05);
      fn_replay_webhook_delivery() SECURITY DEFINER (FIX-05; FIX-10: replay metadata clarified);
      RLS; grants

064_plugins_and_versions
    down_revision = '063_webhook_deliveries_partitioned'
    purpose:
      plugins (fn_plug_slug_immutable; FIX-05);
      plugin_versions (fn_pv_manifest_immutable; FIX-05);
      platform-only grants (no tenant RLS)

065_plugin_installations_and_executions
    down_revision = '064_plugins_and_versions'
    purpose:
      plugin_installations;
      fn_pi_version_immutable (FIX-03: blocks ALL direct changes; session-flag bypass);
      fn_pi_terminal_guard (FIX-05);
      REVOKE INSERT/UPDATE/DELETE from app roles;
      uq_pi_org_plugin_active partial unique index;
      fn_create_plugin_installation() SECURITY DEFINER (FIX-04: validates plugin ownership; FIX-05);
      fn_activate_plugin() SECURITY DEFINER (FIX-06: validates capabilities ⊆ manifest;
                                              validates APPROVED status; FIX-05);
      fn_uninstall_plugin() SECURITY DEFINER (FIX-05);
      fn_upgrade_plugin() SECURITY DEFINER (FIX-03, FIX-04: atomic version upgrade;
                                             session-flag bypass; FIX-05);
      plugin_executions (failure_reason len CHECK; REVOKE from app_api);
      RLS; grants

066_grants_finalize
    down_revision = '065_plugin_installations_and_executions'
    purpose: app_readonly SELECT on all 5I tables; app_platform_admin full access
```

**Migration numbering:** 059–066 unchanged per project rules. All corrections applied by updating migration content; no new migration numbers introduced (correction pass for pre-production schema).

**Downgrade order:** 066 → 065 → 064 → 063 → 062 → 061 → 060 → 059

---

## 31. Seed Data

No seed data in schema migrations. `integration_definitions` and `plugins` are operational data seeded by `app_platform_admin` at bootstrap.

---

## 32. ADRs

### ADR-5I-001: Three PostgreSQL Schemas, One Phase
`integrations`, `webhooks`, `plugins` — three bounded contexts, one migration chain. Unchanged.

### ADR-5I-002: credential_ref as Opaque Secret Manager Reference
`CHECK (... LIKE 'secret_manager://%')`. No raw secrets in DB. Unchanged.

### ADR-5I-003: Inbound Webhook Idempotency Scoped to Tenant (FIX-08)
**Decision:** `UNIQUE (organization_id, provider_slug, provider_event_id)`.

**Rationale:** Provider event IDs are not guaranteed globally unique across tenants. Multi-tenant SaaS must scope idempotency to the tenant. The previous global `UNIQUE (provider_slug, provider_event_id)` was unsafe for multi-tenant operation.

**ODD-5I-07 resolved.**

### ADR-5I-004: Webhook Delivery Partitioned from Day One
Unchanged per Phase 4H §18.3.

### ADR-5I-005: Delivery Claim via SELECT FOR UPDATE SKIP LOCKED
Unchanged.

### ADR-5I-006: Webhook Replay Preserves Original History (FIX-10)
Replay creates a new row. The original row's payload and result history are immutable. `replay_count` and `last_replayed_at` on the original are replay metadata — not result history — and are the only fields updated by `fn_replay_webhook_delivery()` on the original.

### ADR-5I-007: Single Active Connection Enforced Transactionally (FIX-01)
V1 enforces one non-terminal connection per `(organization_id, definition_id)` inside `fn_create_integration_connection()` using `SELECT FOR UPDATE` before INSERT. No partial-unique-index `ON CONFLICT ON CONSTRAINT` — that construct is not valid PostgreSQL for partial indexes.

### ADR-5I-008: Plugin Version Pinned; Upgrade via Controlled Function (FIX-03, FIX-04)
`fn_pi_version_immutable()` blocks ALL direct `plugin_version_id` changes. `fn_upgrade_plugin()` uses `set_config('plugins.upgrade_in_progress', 'true', TRUE)` — transaction-local — to permit the trigger to pass. After upgrade, capabilities reset to `'{}'` and status to `INSTALLED`; re-activation required. **ODD-5I-05 resolved.**

### ADR-5I-009: SSRF Validation Boundary (FIX-07, FIX-13)
DB enforces HTTPS schema. Network-layer SSRF validation at application egress proxy at two points: registration and delivery/execution time.

### ADR-5I-010: Raw Inbound Payload — V1 Default Not Retained (FIX-12)
V1 default: not retained. If enabled: S3 only, encrypted, tenant-scoped, 7-day TTL, deletion on GDPR erasure. **ODD-5I-03 resolved.**

### ADR-5I-011: max_attempts Ceiling Enforced in DB (FIX-02)
`fn_delivery_failed()` computes `new_count = attempt_count + 1`. If `new_count >= max_attempts`, DEAD_LETTER forced regardless of `p_next_attempt_at`. Application supplies backoff timestamps; DB supplies the ceiling.

### ADR-5I-012: Capability Validation Enforced at Activation in DB (FIX-06)
`fn_activate_plugin()` validates `enabled_capabilities ⊆ manifest.capabilities` via JSONB array extraction. Both plugin and version must be APPROVED. Application-layer validation is supplementary, not sufficient. **ODD-5I-08 resolved.**

### ADR-5I-013: search_path Hardening for SECURITY DEFINER Functions (FIX-05)
All SECURITY DEFINER functions use `SET search_path = <schema>, pg_catalog`.

### ADR-5I-014: Delivery Immutability Scope Clarification (FIX-09)
`fn_wd_identity_immutable()` explicitly protects: `payload_json`, `payload_hash`, `event_id`, `event_type`, `webhook_endpoint_id`, `organization_id`. Lifecycle fields mutable only via SECURITY DEFINER functions.

### ADR-5I-015: Error Field Bounds (FIX-11)
External provider error content is untrusted. DB CHECK bounds: `failure_reason ≤ 2000`; `last_response_body_preview ≤ 512`; `last_failure_reason / last_sync_error ≤ 1000`. Functions apply LEFT() before storage.

---

## 33. Security Matrix

| Scenario | Mechanism | Expected |
|---|---|---|
| Tenant A reads Tenant B rows | RLS | 0 rows |
| INSERT connection with plaintext credential | CHECK LIKE 'secret_manager://%' | Violation |
| INSERT endpoint with HTTP target | CHECK LIKE 'https://%' | Violation |
| app_api direct INSERT integration_connection | REVOKE INSERT | Permission denied |
| app_api direct UPDATE webhook_deliveries | REVOKE UPDATE | Permission denied |
| app_worker direct UPDATE plugin_installations | REVOKE UPDATE | Permission denied |
| Duplicate inbound event (same org) | UNIQUE (org, provider_slug, provider_event_id) | Silently ignored |
| Different tenant, same provider event_id | UNIQUE scoped to org | Both rows created |
| Two workers claim same delivery | SKIP LOCKED | Distinct deliveries per worker |
| fn_delivery_failed attempt 7 of 7 | DB ceiling in fn_delivery_failed | DEAD_LETTER |
| fn_delivery_failed attempt 7 of 7 with backoff supplied | DB overrides p_next_attempt_at | DEAD_LETTER |
| fn_delivery_failed attempt 6 of 7 | DB ceiling not reached | PENDING |
| OAuth reuse after redemption | fn_redeem_oauth_attempt PENDING check | Exception |
| OAuth used after expiry | expires_at > NOW() check | Exception; EXPIRED set |
| Replay original payload | fn_wd_identity_immutable trigger | Exception |
| Plugin install with version from other plugin | fn_create_plugin_installation validates | Exception |
| Plugin activate with unauthorized capability | fn_activate_plugin validates ⊆ | Exception |
| Plugin activate with REJECTED/DEPRECATED version | fn_activate_plugin checks version_status | Exception |
| Direct plugin_version_id update | fn_pi_version_immutable trigger | Exception |
| fn_upgrade_plugin with cross-plugin version | fn_upgrade_plugin validates plugin_id | Exception |
| UNINSTALLED reactivation | fn_pi_terminal_guard trigger | Exception |
| search_path injection | SET search_path in SECURITY DEFINER | Prevented |
| last_failure_reason > 1000 chars | CHECK chk_ih_failure_reason_len | Violation |
| failure_reason > 2000 chars | CHECK chk_wd_failure_reason_len | Violation |

---

## 34. Test Matrix

### Integration Connection (FIX-01)
- [ ] `fn_create_integration_connection` with no existing connection → succeeds; connection row + health row created
- [ ] `fn_create_integration_connection` with existing CONNECTING for same (org, definition) → exception
- [ ] `fn_create_integration_connection` with existing ACTIVE for same (org, definition) → exception
- [ ] `fn_create_integration_connection` after DISCONNECTED connection → succeeds (terminal excluded)
- [ ] `fn_create_integration_connection` after FAILED connection → succeeds
- [ ] Concurrent calls from two workers → SELECT FOR UPDATE serializes; one succeeds, one raises exception
- [ ] UPDATE connection from DISCONNECTED → terminal guard trigger raises exception
- [ ] UPDATE connection from FAILED → terminal guard trigger raises exception

### OAuth
- [ ] `fn_redeem_oauth_attempt` valid state+org → returns ID; status = REDEEMED
- [ ] `fn_redeem_oauth_attempt` already REDEEMED → exception
- [ ] `fn_redeem_oauth_attempt` expired attempt → status set EXPIRED; exception
- [ ] `fn_redeem_oauth_attempt` state from different org → NOT FOUND exception
- [ ] INSERT two oauth_attempts with same `state` → UNIQUE violation

### Credential
- [ ] INSERT integration_connection with plaintext credential_ref → CHECK violation
- [ ] INSERT webhook_endpoint with plaintext signing_secret_ref → CHECK violation
- [ ] `fn_rotate_integration_credential` with non-secret-manager ref → exception
- [ ] `fn_rotate_integration_credential` on DISCONNECTED connection → exception

### Inbound Webhook Deduplication (FIX-08)
- [ ] Same tenant + same provider + same event_id → second INSERT silently ignored
- [ ] Different tenant + same provider + same event_id → both rows created; no conflict
- [ ] Same tenant + different provider + same event_id → both rows created
- [ ] `fn_update_inbound_event_status` on PROCESSED event → idempotent return
- [ ] `fn_update_inbound_event_status` with invalid target status → exception

### Webhook Delivery — max_attempts (FIX-02)
- [ ] `fn_delivery_failed` attempt 1 of 7 with valid backoff → returns 'PENDING'
- [ ] `fn_delivery_failed` attempt 6 of 7 with valid backoff → returns 'PENDING'
- [ ] `fn_delivery_failed` attempt 7 of 7 → returns 'DEAD_LETTER'; next_attempt_at = NULL
- [ ] `fn_delivery_failed` attempt 7 of 7 with p_next_attempt_at supplied → DB ignores; DEAD_LETTER
- [ ] `fn_delivery_failed` on non-DELIVERING row → exception
- [ ] `fn_delivery_succeeded` on non-DELIVERING row → 0 rows; no side effect

### Webhook Delivery — concurrency
- [ ] `fn_claim_delivery` from two concurrent workers → each claims distinct delivery IDs; no overlap
- [ ] Stale claimed delivery (claimed_at old) → detectable via claimed_at column; worker timeout logic

### Webhook Payload Immutability (FIX-09)
- [ ] UPDATE webhook_deliveries SET payload_json → fn_wd_identity_immutable raises exception
- [ ] UPDATE webhook_deliveries SET event_id → trigger raises exception
- [ ] UPDATE webhook_deliveries SET webhook_endpoint_id → trigger raises exception
- [ ] Direct UPDATE by app_worker → REVOKE; permission denied

### Webhook Replay (FIX-10)
- [ ] `fn_replay_webhook_delivery` on DEAD_LETTER → new PENDING row; original replay_count incremented
- [ ] `fn_replay_webhook_delivery` called twice while first replay PENDING → returns existing ID
- [ ] Original payload_json unchanged after replay
- [ ] Replay of PENDING delivery → exception

### Plugin Installation (FIX-04)
- [ ] `fn_create_plugin_installation` version from different plugin → exception
- [ ] `fn_create_plugin_installation` PENDING_REVIEW plugin → exception
- [ ] `fn_create_plugin_installation` REJECTED version → exception
- [ ] `fn_create_plugin_installation` APPROVED plugin + APPROVED version (same) → succeeds
- [ ] Two concurrent installs for same (org, plugin) → partial unique index rejects second

### Plugin Activation (FIX-06)
- [ ] `fn_activate_plugin` with valid capability subset → succeeds
- [ ] `fn_activate_plugin` with capability not in manifest → exception
- [ ] `fn_activate_plugin` with empty capabilities → succeeds (empty subset is valid)
- [ ] `fn_activate_plugin` with REJECTED version → exception
- [ ] `fn_activate_plugin` with DEPRECATED version → exception
- [ ] `fn_activate_plugin` with capability from another plugin's manifest → exception (not in this manifest)

### Plugin Version Pinning (FIX-03)
- [ ] Direct UPDATE plugin_installations SET plugin_version_id → trigger raises exception
- [ ] `fn_upgrade_plugin` with APPROVED version from same plugin → succeeds; status=INSTALLED; capabilities reset
- [ ] `fn_upgrade_plugin` with version from different plugin → exception
- [ ] `fn_upgrade_plugin` with PENDING_REVIEW version → exception
- [ ] `fn_upgrade_plugin` with same version as currently installed → idempotent
- [ ] `fn_upgrade_plugin` on UNINSTALLED installation → exception
- [ ] `fn_activate_plugin` after upgrade (with valid capabilities from new version) → succeeds

### Plugin Lifecycle
- [ ] `fn_uninstall_plugin` on ACTIVE → status = UNINSTALLED
- [ ] `fn_uninstall_plugin` on already UNINSTALLED → idempotent
- [ ] UPDATE plugin_installations from UNINSTALLED → fn_pi_terminal_guard raises exception

### Error Field Bounds (FIX-11)
- [ ] integration_health.last_failure_reason with 1001 chars → CHECK violation
- [ ] webhook_deliveries.failure_reason with 2001 chars → CHECK violation
- [ ] webhook_deliveries.last_response_body_preview with 513 chars → CHECK violation
- [ ] inbound_webhook_events.failure_reason with 2001 chars → CHECK violation
- [ ] plugin_executions.failure_reason with 2001 chars → CHECK violation

### Tenant Isolation
- [ ] SELECT from integration_connections for wrong tenant → 0 rows (RLS)
- [ ] SELECT from webhook_deliveries for wrong tenant → 0 rows
- [ ] SELECT from plugin_installations for wrong tenant → 0 rows
- [ ] INSERT plugin_execution with wrong organization_id → RLS WITH CHECK violation

### GDPR
- [ ] `fn_integrations_anonymize_org` clears external_account_name; transitions non-terminal connections to DISCONNECTED
- [ ] After anonymization: connection status/timestamps retained; name/ref cleared

---

## 35. Open Design Decisions

| ID | Topic | Notes |
|---|---|---|
| ODD-5I-01 | OQ-4F-07: Multiple active connections per definition | V1 restricts to one via fn_create_integration_connection check. Drop check if Product resolves to allow multiple. |
| ODD-5I-02 | OQ-4F-06: Webhook topic versioning | TEXT topics are forward-compatible. Full spec deferred to Phase 7. |
| ODD-5I-04 | GDPR interaction with delivery payload retention | 30-day operational purge; GDPR erasure before purge window requires legal review. |
| ODD-5I-06 | Plugin developer verification | developer_org_id stored; KYC/terms workflow Phase 9. |
| ODD-5I-09 | Retroactive webhook_delivery partitions | Create retroactive partitions before backfilling historical data predating Aug 2026. |
| ODD-5I-10 | Analytics carry-forward | Phase 5J owns analytics projections. |

Previously open decisions now resolved: ODD-5I-03 (raw payload — FIX-12), ODD-5I-05 (upgrade path — FIX-03), ODD-5I-07 (inbound org scoping — FIX-08), ODD-5I-08 (capability validation — FIX-06).

---

## 36. Final Consistency Review

### Against Phase 5A

| Standard | Status |
|---|---|
| All PKs use `gen_uuid_v7()` | ✅ |
| All timestamps `TIMESTAMPTZ` | ✅ |
| No monetary columns in 5I | ✅ |
| TEXT + CHECK for all status columns | ✅ |
| No cross-schema FK to voice/crm/campaign/billing/knowledge/workflow | ✅ |
| JSONB justified for manifest | ✅ |
| Migration chain 059–066 continuous from 058 | ✅ |
| No migration number reuse | ✅ |

### Against Phase 5B

| Standard | Status |
|---|---|
| ENABLE + FORCE ROW LEVEL SECURITY on all tenant tables | ✅ |
| RLS uses `organization.current_tenant_id()` | ✅ |
| SECURITY DEFINER: REVOKE ALL FROM PUBLIC + explicit GRANT EXECUTE | ✅ |
| SECURITY DEFINER: SET search_path hardened (FIX-05) | ✅ |

### Critical Invariants

| Invariant | Enforcement | Status |
|---|---|---|
| No plaintext secrets | CHECK + REVOKE + SECURITY DEFINER | ✅ |
| No cross-tenant leakage | RLS on all tenant tables | ✅ |
| Duplicate inbound event blocked (tenant-scoped) | UNIQUE (org, provider_slug, provider_event_id) | ✅ |
| Duplicate delivery claim impossible | SKIP LOCKED | ✅ |
| Delivery identity/content immutable | fn_wd_identity_immutable trigger + REVOKE | ✅ |
| max_attempts ceiling enforced in DB | fn_delivery_failed (FIX-02) | ✅ |
| Replay creates new row; original immutable | fn_replay_webhook_delivery | ✅ |
| Plugin manifest immutable after approval | fn_pv_manifest_immutable trigger | ✅ |
| plugin_version_id immutable under normal update | fn_pi_version_immutable trigger (FIX-03) | ✅ |
| Plugin/version cross-ownership blocked | fn_create_plugin_installation + fn_upgrade_plugin (FIX-04) | ✅ |
| Capabilities validated as ⊆ manifest | fn_activate_plugin (FIX-06) | ✅ |
| UNINSTALLED is terminal | fn_pi_terminal_guard trigger | ✅ |
| Connection terminal states irreversible | fn_ic_terminal_guard trigger | ✅ |
| OAuth replay blocked | fn_redeem_oauth_attempt | ✅ |
| V1 one-active-connection rule | fn_create_integration_connection SELECT FOR UPDATE (FIX-01) | ✅ |
| SSRF — HTTPS enforced at DB layer | CHECK on target_url + CHECK in fn_create_plugin_installation | ✅ |
| Error fields bounded | DB CHECK + LEFT() in functions (FIX-11) | ✅ |
| search_path injection prevented | SET search_path in all SECURITY DEFINER functions (FIX-05) | ✅ |
| No migration collision | 059–066 continuous from 058 | ✅ |

---

## 37. Validation Report

### Corrections Applied

| Fix | Description | Status |
|---|---|---|
| FIX-01 | QP-02: replaced invalid `ON CONFLICT ON CONSTRAINT <partial_index>` with SECURITY DEFINER `fn_create_integration_connection()` using `SELECT FOR UPDATE` transactional uniqueness check. QP-02, concurrency section, test matrix updated. | **RESOLVED** |
| FIX-02 | `fn_delivery_failed()`: DB computes `new_count = attempt_count + 1`; forces DEAD_LETTER when `new_count >= max_attempts` regardless of `p_next_attempt_at`. INV-WH-07 added. Retry section, QP-13, tests updated. | **RESOLVED** |
| FIX-03 | `fn_pi_version_immutable()`: now blocks ALL direct `plugin_version_id` changes; session flag `plugins.upgrade_in_progress` (transaction-local via `set_config(..., TRUE)`) permits change exclusively within `fn_upgrade_plugin()`. INV-PLUG-02 updated. | **RESOLVED** |
| FIX-04 | `fn_create_plugin_installation()` and `fn_upgrade_plugin()` both validate `plugin_versions.plugin_id = p_plugin_id`. INV-PLUG-06 added. Cross-plugin version mismatch tests added. | **RESOLVED** |
| FIX-05 | All SECURITY DEFINER functions: added `SET search_path = <schema>, pg_catalog`. ADR-5I-013 added. | **RESOLVED** |
| FIX-06 | `fn_activate_plugin()`: validates `enabled_capabilities ⊆ manifest.capabilities` via JSONB array extraction; validates plugin status = APPROVED; validates version status = APPROVED. INV-PLUG-07 added. ODD-5I-08 resolved. Tests added. | **RESOLVED** |
| FIX-07 | SSRF architecture documented: DB enforces HTTPS CHECK; egress proxy enforces full SSRF protection at registration and delivery time. Same protection applies to plugin base_url. ADR-5I-009 added. | **RESOLVED** |
| FIX-08 | Inbound webhook uniqueness key: `UNIQUE (provider_slug, provider_event_id)` → `UNIQUE (organization_id, provider_slug, provider_event_id)`. DDL, index, QP-07, QP-08, INV-WH-06, ADR-5I-003, concurrency section, tests updated. ODD-5I-07 resolved. | **RESOLVED** |
| FIX-09 | Payload immutability trigger renamed `fn_wd_identity_immutable()`; explicitly covers `payload_json`, `payload_hash`, `event_id`, `event_type`, `webhook_endpoint_id`, `organization_id`. INV-WH-04 updated. Append-only/lifecycle reconciliation documented. ADR-5I-014 added. | **RESOLVED** |
| FIX-10 | Replay terminology clarified throughout: original payload/result history immutable; `replay_count` + `last_replayed_at` are replay metadata, not result history. INV-WH-08 added. ADR-5I-006 updated. | **RESOLVED** |
| FIX-11 | DB CHECK constraints added for `failure_reason ≤ 2000`, `last_response_body_preview ≤ 512`, `last_failure_reason ≤ 1000`, `last_sync_error ≤ 1000`. LEFT() applied in all functions. ADR-5I-015 added. Tests added. | **RESOLVED** |
| FIX-12 | V1 raw payload retention policy resolved: default = not retained. If enabled: S3 only, encrypted, tenant-scoped, 7-day TTL, GDPR deletion workflow. ODD-5I-03 resolved. ADR-5I-010 updated. | **RESOLVED** |
| FIX-13 | Plugin base_url SSRF: validated at version approval (application layer) and at plugin callout time (egress proxy). Documented in §11 and §18. ADR-5I-009 covers both webhook and plugin SSRF. | **RESOLVED** |
| FIX-14 | Full state-machine audit performed. All transitions documented in §13. All terminal states blocked by triggers or SECURITY DEFINER logic. No undocumented transitions. See table below. | **RESOLVED** |

### State Machine Audit (FIX-14)

| State Machine | States | Terminals | Guard |
|---|---|---|---|
| Integration Connection | CONNECTING→ACTIVE→DEGRADED→DISCONNECTED; CONNECTING→FAILED; DEGRADED→ACTIVE | DISCONNECTED, FAILED | fn_ic_terminal_guard trigger |
| OAuth Attempt | PENDING→REDEEMED/EXPIRED/FAILED | REDEEMED, EXPIRED, FAILED | fn_redeem_oauth_attempt |
| Webhook Endpoint | ACTIVE↔DISABLED↔SUSPENDED | None (operator-managed) | Application layer |
| Webhook Delivery | PENDING→DELIVERING→DELIVERED/DEAD_LETTER; DELIVERING→PENDING(retry); PENDING→CANCELLED | DELIVERED, DEAD_LETTER, CANCELLED | REVOKE + fn_wd_identity_immutable + fn_delivery_failed ceiling |
| Inbound Event | RECEIVED→PROCESSING→PROCESSED/FAILED/SKIPPED | PROCESSED, SKIPPED | fn_update_inbound_event_status idempotency |
| Plugin | PENDING_REVIEW→APPROVED/REJECTED | REJECTED | app_platform_admin only |
| Plugin Version | PENDING_REVIEW→APPROVED/REJECTED/DEPRECATED | REJECTED | fn_pv_manifest_immutable |
| Plugin Installation | INSTALLED→ACTIVE→SUSPENDED→ACTIVE→UNINSTALLED | UNINSTALLED | fn_pi_terminal_guard trigger |

### Remaining Open Design Decisions

6 items remain genuinely open (ODD-5I-01, -02, -04, -06, -09, -10). None block V1. 4 previously open decisions resolved.

### PostgreSQL Correctness

All DDL and query patterns are valid PostgreSQL 15+. Key correctness items:
- `ON CONFLICT ON CONSTRAINT <partial_index>` — **removed** (was invalid); replaced with transactional function ✅
- Partitioned table PK includes partition key `(id, created_at)` ✅
- `fn_delivery_failed` uses `SELECT FOR UPDATE` before UPDATE to prevent lost-update ✅
- `current_setting('plugins.upgrade_in_progress', TRUE)` — second argument `TRUE` suppresses "variable not found" error; returns NULL safely ✅
- `set_config('plugins.upgrade_in_progress', 'true', TRUE)` — third argument `TRUE` limits to current transaction (SET LOCAL equivalent) ✅
- `fn_activate_plugin` uses `SELECT ARRAY(SELECT jsonb_array_elements_text(...))` — valid PostgreSQL ✅
- All functions use `RETURNS VOID` or concrete return types consistent with GRANT EXECUTE ✅

### Security

| Concern | Verified |
|---|---|
| RLS | ✅ ENABLE + FORCE on all 8 tenant tables |
| FORCE RLS | ✅ All tenant tables (prevents superuser bypass for app roles) |
| SECURITY DEFINER | ✅ All mutation/transition functions |
| search_path hardening | ✅ All SECURITY DEFINER functions (FIX-05) |
| Credential protection | ✅ CHECK + REVOKE + opaque refs only |
| SSRF protection | ✅ HTTPS CHECK (DB) + egress proxy (application) at two points |
| Plugin capability enforcement | ✅ DB-enforced in fn_activate_plugin (FIX-06) |
| Plugin/version ownership | ✅ DB-enforced in fn_create_plugin_installation + fn_upgrade_plugin (FIX-04) |
| Unapproved plugin gate | ✅ fn_create_plugin_installation checks APPROVED status |

### Migration Chain

```
058 → 059 → 060 → 061 → 062 → 063 → 064 → 065 → 066
```
✅ Confirmed. No gaps. No renumbering. (Migration 101_5I1 — §38 below — continues the chain from `100_5G1`, not from 066; migrations 067-100 belong to other phases' own amendments and are unaffected by, and unrelated to, this section.)

---

## 38. Controlled Amendment — Phase 5I.1 (2026-08-29)

**Source:** independent-review remediation pass against `docs/phase-06-api-design/6J-Integrations-Webhooks-Plugins-APIs.md`. Full rationale, security test matrix requirements, and per-finding reconciliation live in that document and in `5K/MIGRATION_MANIFEST.md`'s own "Phase 6J Remediation Pass" section — this section records only the schema-facing summary, per this document's role as the schema's authoritative record.

**Migration:** `5K/migrations/101_5I1.sql`, Alembic revision `101_5I1`, `down_revision = '100_5G1'`. Additive only — no 059-066 statement is edited or removed.

**What it adds:**
- `oauth_attempts.connection_id` (nullable FK to `integration_connections`), `oauth_attempts.failure_reason` (nullable, ≤1000 chars) — closes the ambiguous `(organization_id, definition_id)`-inference correlation this document's §13 originally relied on (ODD-adjacent, not a numbered ODD at v1.1 time).
- `webhook_endpoints.previous_signing_secret_ref`, `webhook_endpoints.previous_secret_expires_at` (both nullable, paired by CHECK) — enables genuine dual-signature secret-rotation grace (the platform signs outbound deliveries with both the current and, while unexpired, the previous secret during the grace window), closing a cryptographic defect in the API layer's originally-proposed rotation design (retaining the old secret without ever signing with it gave a consumer no working grace period).
- `integrations.fn_activate_integration_connection`, `fn_fail_integration_connection`, `fn_degrade_integration_connection`, `fn_disconnect_integration_connection`, `fn_update_integration_connection_config`, `fn_record_integration_sync_result` — the full `CONNECTING/ACTIVE/DEGRADED/DISCONNECTED/FAILED` transition surface §8's state machine defines but 059-066 never implemented beyond the initial `CONNECTING` insert (`fn_create_integration_connection`) and the GDPR-only forced-disconnect (`fn_integrations_anonymize_org`). All five new transition functions are `SELECT ... FOR UPDATE`-guarded, `organization_id`-scoped, and respect the existing `fn_ic_terminal_guard` trigger without modification.
- `integrations.fn_redeem_oauth_callback_state(state)`, `fn_fail_oauth_callback_state(state, reason)` — the tenant-bootstrap-safe OAuth callback redemption/denial path (takes `state` alone, no `organization_id` input, returning tenant identity as output instead) used by an unauthenticated browser-redirect callback. `fn_redeem_oauth_attempt` (061) is unmodified and still present.
- `plugins.fn_suspend_plugin_installation`, `fn_reactivate_plugin_installation`, `fn_update_plugin_installation_config`, `fn_rotate_plugin_installation_credential` — closes the `SUSPENDED`/config-update/credential-rotation gap §19/§27 of this document's original v1.1 text left open (`SUSPENDED` was a valid `chk_pi_status` value with no function ever reaching or leaving it).
- `webhooks.fn_rotate_webhook_secret` — atomic current↔previous secret-reference rotation backing the two new `webhook_endpoints` columns above.
- `CREATE OR REPLACE` on `fn_create_integration_connection` (061) — same signature; body now additionally checks `integration_definitions.is_active` before creating a connection (defense-in-depth; the application layer was already expected to check this).
- `GRANT EXECUTE ... TO app_api` on five pre-existing `app_worker`-only functions (`fn_activate_plugin`, `fn_uninstall_plugin`, `fn_upgrade_plugin`, `fn_rotate_integration_credential`, `fn_replay_webhook_delivery`) — grants only, no body changed; each of the five already performs its own tenant-scoped authorization internally, so direct `app_api` execution carries no new risk.

**RLS posture:** unchanged. `oauth_attempts` and `integration_connections` keep `ENABLE + FORCE ROW LEVEL SECURITY` exactly as this document's §24/§28 originally specified. The new OAuth-bootstrap function does not bypass RLS by policy change — it relies on the pre-existing fact (confirmed against `001_5B.sql` and the live `077_5J1_VALIDATION_REPORT.md`) that `app_migration`, the role owning every `SECURITY DEFINER` function in this schema, was already created `BYPASSRLS`.

**Validation status (superseded by §39 below — this paragraph is the original, pre-live-validation record, kept for history):** at the time this section was first written, `101_5I1.sql` had been authored and manually traced against source but not executed against a live PostgreSQL instance. §39 records the subsequent live-validation pass that closed this gap.

---

## 39. Live Validation — Phase 5I.1 (2026-08-29, same-day follow-up)

A second remediation pass (independent review of §38's first-pass `101_5I1.sql`) found three further P0 defects and, during its own live testing, one additional major platform-wide-impact defect. Full detail: `5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`; summary: `5K/MIGRATION_MANIFEST.md`'s "Phase 6J FINAL Blocker Remediation" section.

**§38's function list is amended as follows** (all via `CREATE OR REPLACE`, same signatures, within the same `101_5I1.sql` file — no new migration number):

- Every function §38 lists, plus the pre-existing `fn_redeem_oauth_attempt` (061), now additionally requires `organization.current_tenant_id() = p_organization_id` before touching any row (the SECURITY DEFINER tenant-forgery guard) — closing a P0 that affected every `app_api`-callable function taking `p_organization_id` as a parameter, including two functions §38 did not flag as needing amendment (`fn_create_integration_connection`, `fn_create_plugin_installation` — both already `app_api`-callable since 059-066, sharing the identical defect class).
- `fn_redeem_oauth_callback_state`/`fn_fail_oauth_callback_state` gained a mandatory `p_expected_definition_id` parameter, verified against the attempt's own `definition_id` before consuming `state` — closing a cross-provider state-binding P0.
- A new function, `fn_record_oauth_exchange_failure(state, reason)`, was added — `fn_fail_oauth_callback_state` is now scoped to pre-redemption denial only; the new function handles a post-redemption token-exchange failure without reopening `state` for reuse (`status` stays `REDEEMED`). A new `oauth_attempts.exchange_failed_at TIMESTAMPTZ NULL` column backs this.
- `fn_redeem_oauth_callback_state`/`fn_fail_oauth_callback_state`/`fn_record_oauth_exchange_failure`'s `EXECUTE` grant was narrowed to `app_api, app_platform_admin` (no `app_worker` — no worker process handles OAuth callbacks).
- **`public.gen_uuid_v7()` (001_5B.sql) — a pre-existing defect in the frozen 001-100 baseline, discovered live, fixed here:** no `SET search_path` of its own, so its call to the unqualified `gen_random_bytes()` (in `public`) fails when nested inside any `SECURITY DEFINER` function whose own search_path excludes `public` — live-confirmed to affect 84 of the 99 `SECURITY DEFINER` functions across the entire 001-100 baseline, this schema's own included. Fixed via `CREATE OR REPLACE FUNCTION public.gen_uuid_v7() ... SET search_path = public, pg_catalog` (not `SECURITY DEFINER`, no privilege change). **A full audit of the other 83 affected functions outside this schema is out of scope for this document and is recorded as a forward finding.**

**Live validation, PostgreSQL 18.6 (engine-version deviation from the requested 16, disclosed):** fresh-database `alembic upgrade head` (full `001_5B → … → 101_5I1`, 101 revisions) — **PASS**. Incremental (`100_5G1` pinned, `101_5I1` applied alone) — **PASS**. Single head, `current == head`, linear history. `downgrade -1` correctly raises `NotImplementedError`, no partial DDL. Full adversarial matrix — tenant-forgery (11/11 across integration/plugin/webhook function families), OAuth (14/14, including the state-machine-contradiction and provider-binding fixes), integration-connection lifecycle (all legal/illegal/idempotent transitions), plugin-installation lifecycle (all legal/illegal/idempotent transitions, live-proven version-pinning capability-reset), webhook dual-secret rotation, a genuine two-process concurrency race for inbound-event dedup, RLS isolation (including the fail-closed-with-no-tenant-context guarantee), full privilege matrix (`PUBLIC EXECUTE = false` on all 34 functions), full `SECURITY DEFINER` inventory (owner/`BYPASSRLS`/`search_path`), and a targeted regression check — **all PASS**. This document's own §37 Validation Report above (`059-066` baseline) is unaffected and unmodified by any of this; `101_5I1` is now separately, fully live-validated in its own right.

**Not covered by this live-validation pass:** SSRF/application-layer tests (no deployed application code exists anywhere in this repository to test against); a full re-run of every historical 001-100 test file (targeted spot-checks only); the other 83 `gen_uuid_v7`-affected functions outside this schema (forward finding, not audited here); 6I's `graph_json` node-config schema does not yet define the `plugin_installation_id`/`plugin_version_id` fields 6J's own version-pinning design targets — an explicit, disclosed cross-phase coordination item (6I is frozen, out of this schema's or 6J's authority to amend unilaterally), not silently claimed resolved.

---

```
PHASE 5I — INTEGRATIONS / WEBHOOKS / PLUGINS SCHEMA (Correction Pass v1.1)
Schemas:         integrations, webhooks, plugins
Migration chain: 059–066, continuous from 058

All FIX-01 through FIX-14: RESOLVED
Critical issues remaining: NONE
Significant issues remaining: NONE
Open design decisions: 6 (non-blocking)

STATUS: APPROVED FOR FREEZE
PHASE 5J READY

--------------------------------------------------------------------
Phase 5I.1 controlled amendment (101_5I1.sql, §38-39 above, 2026-08-29):
STATUS: LIVE-VALIDATED (PostgreSQL 18.6). Fresh + incremental upgrade
PASS, single Alembic head, full adversarial test matrix PASS
(tenant-forgery, OAuth, integration/plugin lifecycle, webhook
rotation, concurrency race, RLS, privileges, SECURITY DEFINER
inventory). See §39 above and
5K/validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md for
full detail, including the disclosed out-of-scope items (SSRF
application-layer tests; the 6I plugin-version-pinning cross-phase
schema-compatibility item; the other 83 gen_uuid_v7-affected
functions outside this schema).
--------------------------------------------------------------------
```
