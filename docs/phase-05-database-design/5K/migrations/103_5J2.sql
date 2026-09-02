-- =================================================================
-- Migration 103 (Phase 5J.2): FX-normalized ROI / gross-margin
--   provenance for analytics.roi_by_campaign and
--   analytics.billing_revenue_monthly
-- down_revision: 102_5H2
-- Transaction: yes
-- Source: docs/phase-06-api-design/6L-Analytics-Audit-APIs.md
--   §53 Schema Gap Analysis (SCHEMA-GAP-6L-01). DESIGNED, NOT YET
--   VALIDATED against a live PostgreSQL 18 instance -- no database
--   credentials were available in the authoring session (a local
--   PostgreSQL 18.6 server exists but requires a password this
--   session was not given, and this migration does not attempt to
--   alter the local server's auth configuration to obtain one). See
--   6L §55 for exact validation status and the required next step
--   before this file is applied to any environment.
--
-- Trigger -- a genuine, evidenced cross-phase defect, not a
-- convenience improvement:
--
--   analytics.roi_by_campaign (071_5J.sql) stores
--   total_cost_amount/total_cost_currency (default 'USD') and
--   estimated_revenue_amount/estimated_revenue_currency (nullable, NO
--   default) as two INDEPENDENTLY-defaulted currency columns, with a
--   single roi_pct column computed from both. 4G §7.2's own
--   ROIComputationService sums total_cost directly from
--   billing.cost_entries (provider currency, typically USD) and
--   computes estimated_revenue as qualified_count x
--   estimated_conversion_value (a tenant-configured value, presumed
--   tenant/billing currency, e.g. INR) -- i.e. the two amounts feeding
--   the one roi_pct are, by the frozen domain model's own construction,
--   not guaranteed to share a currency.
--
--   analytics.billing_revenue_monthly (071_5J.sql) has the identical
--   shape: billed_amount/billed_currency (default 'INR') vs.
--   provider_cost_amount/provider_cost_currency (default 'USD'), with
--   no combined-currency profit/margin column at all today.
--
--   This directly contradicts:
--     - Phase 4I §11.3: "CostEntry adds: AmountInBillingCurrency,
--       FxRateUsed, FxRateSource, FxRateAt ... the FX rate used for a
--       cost conversion is recorded on the row, never looked up
--       retrospectively."
--     - Phase 4I §17.4: "campaign cost is aggregated in the tenant's
--       billing currency using recorded FX rates; revenue is in the
--       tenant's currency; ROI is currency-consistent."
--     - Phase 6K INV-6K-14 / §32: "No implicit FX" -- a binding
--       invariant for every financial computation in this schema, not
--       only billing's own invoice/payment flows.
--     - billing.cost_entries (5H §7, migration 051_5H.sql) already
--       implements exactly this normalization pattern
--       (amount_in_billing_currency_amount/_currency, fx_rate_used,
--       fx_rate_source, fx_rate_captured_at) for the identical
--       provider-cost-vs-tenant-currency problem -- roi_by_campaign and
--       billing_revenue_monthly never adopted it when they were
--       authored in migration 071_5J.sql.
--
-- What this migration does: adds the FX-normalized "amount expressed
-- in a single common currency, plus the rate/source/timestamp used to
-- get there" column set -- mirroring billing.cost_entries' own
-- existing, already-frozen pattern exactly -- to both tables, and adds
-- CHECK constraints making a currency-inconsistent roi_pct/
-- gross_margin_amount structurally unrepresentable once a population
-- job populates these columns. It does NOT change how roi_pct is
-- computed today: 071_5J.sql defines no fn_apply_projection_roi
-- function (roi_by_campaign is an application-layer nightly batch job
-- per 5J §10.9, not an event-per-event projection -- see 6L §12/§54),
-- so there is no existing computation this migration could break.
-- Populating the new columns and correctly gating roi_pct/
-- gross_margin_amount computation on them is that (not-yet-built)
-- job's responsibility, tracked as an IMPLEMENTATION DEPENDENCY in 6L
-- §54, not something this schema-only migration performs.
--
-- What this migration does NOT do: it does not rename, retype, or
-- change the default/nullability of any existing column on either
-- table; it does not add a projection function; it does not touch any
-- table, function, role, or grant outside these two tables; it does
-- not modify migrations 001-102 (102_5H2.sql's SHA-256 is unaffected
-- by this file's existence).
--
-- Constraint-validation strategy: the four "normalization must be
-- present before the derived figure is trusted" CHECK constraints
-- below are added NOT VALID. This is a deliberate safety choice, not
-- an oversight: this migration cannot prove, without live database
-- access (see the validation-status note above), whether either table
-- already holds test-fixture rows with roi_pct/gross_margin_amount
-- populated from an earlier, non-normalized computation. NOT VALID
-- adds the constraint immediately for all NEW writes without scanning
-- or rejecting on any pre-existing row, avoiding a spurious migration
-- failure against pre-existing fixture data while still closing the
-- gap for every row written from this point forward. A follow-up
-- VALIDATE CONSTRAINT pass (cheap once the population job backfills
-- org_currency on historical rows, or trivial if the tables are
-- confirmed empty) is an explicit implementation-phase follow-up, not
-- silently deferred -- see 6L §55.
-- =================================================================

-- ---------------------------------------------------------------
-- Part A: analytics.roi_by_campaign
-- ---------------------------------------------------------------

ALTER TABLE analytics.roi_by_campaign
  ADD COLUMN org_currency                          CHAR(3)       NULL,
  ADD COLUMN total_cost_amount_org_currency         NUMERIC(18,4) NULL,
  ADD COLUMN total_cost_fx_rate_used                NUMERIC(12,6) NULL,
  ADD COLUMN total_cost_fx_rate_source              TEXT          NULL,
  ADD COLUMN total_cost_fx_rate_captured_at         TIMESTAMPTZ   NULL,
  ADD COLUMN estimated_revenue_amount_org_currency  NUMERIC(18,4) NULL,
  ADD COLUMN estimated_revenue_fx_rate_used         NUMERIC(12,6) NULL,
  ADD COLUMN estimated_revenue_fx_rate_source       TEXT          NULL,
  ADD COLUMN estimated_revenue_fx_rate_captured_at  TIMESTAMPTZ   NULL;

COMMENT ON COLUMN analytics.roi_by_campaign.org_currency IS
  'Snapshot of billing.billing_accounts.currency at compute time -- the single common-denominator currency roi_pct/cost_per_call/cost_per_qualified/cost_per_converted are expressed in once populated. NULL on every row until the (future, 6L Section 54) population job runs against this column set.';
COMMENT ON COLUMN analytics.roi_by_campaign.total_cost_amount_org_currency IS
  'total_cost_amount converted into org_currency. Equal to total_cost_amount with total_cost_fx_rate_used = 1.000000 when total_cost_currency already equals org_currency -- a recorded no-op rate, not an implicit skip.';
COMMENT ON COLUMN analytics.roi_by_campaign.total_cost_fx_rate_used IS
  'Rate applied to convert total_cost_amount (in total_cost_currency) into total_cost_amount_org_currency, recorded on the row per 4I Section 11.3 -- never recomputed retrospectively for historical reporting.';
COMMENT ON COLUMN analytics.roi_by_campaign.total_cost_fx_rate_source IS
  'Rate provenance identifier (e.g. a billing.fx_rates row reference). Mirrors billing.cost_entries.fx_rate_source (5H Section 7) exactly.';
COMMENT ON COLUMN analytics.roi_by_campaign.estimated_revenue_amount_org_currency IS
  'estimated_revenue_amount converted into org_currency, on the same terms as total_cost_amount_org_currency above.';

ALTER TABLE analytics.roi_by_campaign
  ADD CONSTRAINT chk_rbc_org_currency_code
    CHECK (org_currency IS NULL OR org_currency ~ '^[A-Z]{3}$');

ALTER TABLE analytics.roi_by_campaign
  ADD CONSTRAINT chk_rbc_cost_normalization_present
    CHECK (
      org_currency IS NULL
      OR total_cost_currency = org_currency
      OR (total_cost_amount_org_currency IS NOT NULL
          AND total_cost_fx_rate_used IS NOT NULL)
    ) NOT VALID;

ALTER TABLE analytics.roi_by_campaign
  ADD CONSTRAINT chk_rbc_revenue_normalization_present
    CHECK (
      estimated_revenue_amount IS NULL
      OR org_currency IS NULL
      OR estimated_revenue_currency = org_currency
      OR (estimated_revenue_amount_org_currency IS NOT NULL
          AND estimated_revenue_fx_rate_used IS NOT NULL)
    ) NOT VALID;

ALTER TABLE analytics.roi_by_campaign
  ADD CONSTRAINT chk_rbc_roi_requires_normalization
    CHECK (
      roi_pct IS NULL
      OR (org_currency IS NOT NULL
          AND total_cost_amount_org_currency IS NOT NULL
          AND (estimated_revenue_amount IS NULL
               OR estimated_revenue_amount_org_currency IS NOT NULL))
    ) NOT VALID;

-- No grant changes on analytics.roi_by_campaign: app_api, app_readonly,
-- app_worker, and app_platform_admin keep exactly the SELECT/INSERT/
-- UPDATE/DELETE grants 071_5J.sql already established. This migration
-- adds columns and CHECK constraints only.

-- ---------------------------------------------------------------
-- Part B: analytics.billing_revenue_monthly
-- ---------------------------------------------------------------

ALTER TABLE analytics.billing_revenue_monthly
  ADD COLUMN provider_cost_amount_org_currency  NUMERIC(18,4) NULL,
  ADD COLUMN provider_cost_fx_rate_used         NUMERIC(12,6) NULL,
  ADD COLUMN provider_cost_fx_rate_source       TEXT          NULL,
  ADD COLUMN provider_cost_fx_rate_captured_at  TIMESTAMPTZ   NULL,
  ADD COLUMN gross_margin_amount                NUMERIC(18,4) NULL,
  ADD COLUMN gross_margin_pct                   NUMERIC(8,4)  NULL;

COMMENT ON COLUMN analytics.billing_revenue_monthly.provider_cost_amount_org_currency IS
  'provider_cost_amount converted into billed_currency. On this table billed_currency IS the organization''s own billing currency (billing.billing_accounts.currency, immutable per fn_ba_currency_immutable, 5H) -- there is no separate org_currency snapshot column here, unlike roi_by_campaign. Equal to provider_cost_amount with provider_cost_fx_rate_used = 1.000000 when provider_cost_currency already equals billed_currency.';
COMMENT ON COLUMN analytics.billing_revenue_monthly.gross_margin_amount IS
  'billed_amount - provider_cost_amount_org_currency, both already expressed in billed_currency. Platform-internal financial data (6K Section 24, restated 6L Section 25/54) -- never exposed by any tenant-facing analytics:read or analytics_cost:read endpoint; readable only under analytics_platform:read / platform-admin internal contracts.';
COMMENT ON COLUMN analytics.billing_revenue_monthly.gross_margin_pct IS
  'gross_margin_amount / NULLIF(billed_amount, 0) * 100, rounded per 6L Section 34''s percentage convention. NULL when billed_amount = 0 -- never a division-by-zero error and never a false 0% signal.';

ALTER TABLE analytics.billing_revenue_monthly
  ADD CONSTRAINT chk_brm_margin_requires_normalization
    CHECK (
      gross_margin_amount IS NULL
      OR provider_cost_amount_org_currency IS NOT NULL
    ) NOT VALID;

ALTER TABLE analytics.billing_revenue_monthly
  ADD CONSTRAINT chk_brm_margin_pct_requires_amount
    CHECK (
      gross_margin_pct IS NULL
      OR gross_margin_amount IS NOT NULL
    ) NOT VALID;

-- ---------------------------------------------------------------
-- Part C: column-level visibility note (no GRANT/REVOKE issued)
-- ---------------------------------------------------------------
-- gross_margin_amount and gross_margin_pct are platform gross-margin
-- data (6K Section 24, restated 6L Section 25) and must never be
-- readable by a tenant caller, even though app_api holds whole-table
-- SELECT on analytics.billing_revenue_monthly (071_5J.sql, unchanged
-- by this migration). PostgreSQL grants are table-grained; there is no
-- column-level REVOKE that coexists with the existing blanket
-- table-level SELECT grant without introducing a column-privilege
-- precedent this schema does not otherwise use (5A Section 27,
-- reaffirmed by 6L Section 57's SECURITY DEFINER / grant audit).
-- Access to these two columns is therefore enforced exclusively at the
-- 6L API response-model layer (an explicit Pydantic allow-list per 6A
-- Section 10.2 that simply never includes them in any tenant-facing
-- response model) -- the same "DB grant is necessary but not
-- sufficient for business authorization" pattern already governing
-- analytics.analytics_events (6L Section 11/45) and the cost-visibility
-- boundary on analytics.usage_cost_daily (6L Section 25, DEC-6L-02).
-- This is recorded here explicitly, not silently assumed, per 6L
-- Section 57's requirement that DB-grant/API-permission gaps be
-- documented wherever they occur.
