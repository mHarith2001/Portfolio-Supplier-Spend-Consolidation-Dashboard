-- 46_export_tableau.sql
-- Layer: L4 reporting_ — the export surface
--
-- EXECUTED 2026-09-18. Run from a file on standard input. Needs 41-45 first.
--
-- ===========================================================================
-- WHY AN EXPORT LAYER EXISTS AT ALL
-- ===========================================================================
-- 08 §13: Tableau Public has NO database connectors — confirmed from its own FAQ
-- — so the star schema must leave BigQuery as flat files. These views are what
-- gets written to data/outputs/. They differ from the warehouse tables in ways
-- that are recorded here rather than applied by hand at export time, because a
-- hand-edited extract cannot be reproduced.
--
-- ---------------------------------------------------------------------------
-- DIFFERENCE 1 — integer surrogates, not SHA-256 hex (measured, not assumed)
-- ---------------------------------------------------------------------------
-- The first export averaged 321 bytes per fact row, of which 192 were three
-- 64-character hex keys, and repeated `entity`, `amount_vat_basis` and
-- `source_file` as literal strings on all 175,470 rows. That is denormalisation
-- in a star schema, which is the one thing a star schema is for.
--
-- The warehouse keeps its hash keys — they are stable across rebuilds and do not
-- depend on row order, which an integer id does. The EXPORT uses dense integer
-- ids, and every dimension carries BOTH, so any figure on the dashboard can be
-- traced back to the warehouse row it came from.
--
-- ---------------------------------------------------------------------------
-- DIFFERENCE 2 — `postcode` is not exported (charter L-3)
-- ---------------------------------------------------------------------------
-- L-3: registered addresses of small companies may be residential; only
-- aggregates and derived tables are published. 5,719 of 5,967 resolved suppliers
-- carry a registered postcode. It earns its place in the warehouse — tier 3
-- matches on it — and earns nothing on a dashboard with no map. It stays in
-- BigQuery for matching and audit and does not enter a published file.
--
-- ---------------------------------------------------------------------------
-- DIFFERENCE 3 — individual-looking UNRESOLVED names are withheld (L-1)
-- ---------------------------------------------------------------------------
-- Publishers redact individuals inconsistently. 162 supplier names look personal
-- — a title prefix, or an '@'. Republishing them would amplify personal data that
-- one publisher chose to redact and another did not.
--
-- THE MASK IS SCOPED TO UNRESOLVED NAMES, and the scoping is the point: 8 of the
-- 162 RESOLVED to a Companies House company, because real companies begin 'DR'
-- and 'MR' too. Masking those would hide matched companies to protect people who
-- are not there. The remaining 154 are withheld.
--
-- Measured 2026-09-18: 154 suppliers, 1,450 rows, GBP 3,230,588.33 — 0.0063% of
-- transaction value. THE ROWS AND THE MONEY STAY; only the label is withheld, so
-- every total still reconciles and the category stays visible. That is what L-1
-- requires: reported as a named category, never silently dropped.

-- ---------------------------------------------------------------------------
-- Dimensions — each carries its integer id AND its warehouse key
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_dim_supplier` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY supplier_key)                AS supplier_id,
  supplier_key,
  IF(NOT is_resolved
     AND (REGEXP_CONTAINS(UPPER(supplier_name), r'^(MR|MRS|MS|MISS|DR|PROF)[ .]')
          OR REGEXP_CONTAINS(supplier_name, r'@')),
     'Individual — name withheld',
     supplier_name)                                        AS supplier_name,
  company_number,
  legal_name,
  company_status,
  incorporation_date,
  name_variant_count,
  is_resolved,
  unresolved_reason,
  match_tier,
  match_confidence,
  resolution_state,
  (NOT is_resolved
   AND (REGEXP_CONTAINS(UPPER(supplier_name), r'^(MR|MRS|MS|MISS|DR|PROF)[ .]')
        OR REGEXP_CONTAINS(supplier_name, r'@')))          AS is_individual_withheld
FROM `portfolio-508106.portfolio_b.dim_supplier`;

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_dim_entity` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY entity)                      AS entity_id,
  *
FROM `portfolio-508106.portfolio_b.dim_entity`;

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_dim_category` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY category_key)                AS category_id,
  *
FROM `portfolio-508106.portfolio_b.dim_category`;

-- Provenance as a dimension. 62 source files repeated on 352,528 fact rows is
-- 13 MB of the same 62 strings; as a dimension it is 62 rows, and the fact keeps
-- its traceability through a 2-character id.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_dim_source_file` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY _source_file)                AS source_file_id,
  _source_file                                             AS source_file,
  ANY_VALUE(entity)                                        AS entity,
  COUNT(*)                                                 AS transaction_rows
FROM `portfolio-508106.portfolio_b.resolved_spend`
WHERE row_role = 'transaction'
GROUP BY _source_file;

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_dim_vat_basis` AS
SELECT
  ROW_NUMBER() OVER (ORDER BY amount_vat_basis)            AS vat_basis_id,
  amount_vat_basis,
  COUNT(*)                                                 AS transaction_rows
FROM `portfolio-508106.portfolio_b.resolved_spend`
WHERE row_role = 'transaction'
GROUP BY amount_vat_basis;

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_dim_date` AS
SELECT * FROM `portfolio-508106.portfolio_b.dim_date`;

-- ---------------------------------------------------------------------------
-- Facts — keys and measures only
-- ---------------------------------------------------------------------------
-- spend_ref is the first 16 hex characters of the warehouse spend_id: 64 bits,
-- and UNIQUENESS IS VERIFIED BY 94, not assumed. Full-length ids cost 17 MB
-- across the two extracts to carry entropy nothing uses.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_fact_spend` AS
SELECT
  SUBSTR(f.spend_id, 1, 16)   AS spend_ref,
  ds.supplier_id,
  de.entity_id,
  f.date_key,
  dc.category_id,
  dsf.source_file_id,
  dv.vat_basis_id,
  f.amount,
  f.is_grant_in_aid,
  f.transaction_number
FROM `portfolio-508106.portfolio_b.fact_spend` f
JOIN `portfolio-508106.portfolio_b.export_dim_supplier`    ds USING (supplier_key)
JOIN `portfolio-508106.portfolio_b.export_dim_entity`      de USING (entity)
JOIN `portfolio-508106.portfolio_b.export_dim_category`    dc USING (category_key)
JOIN `portfolio-508106.portfolio_b.export_dim_source_file` dsf ON dsf.source_file = f._source_file
JOIN `portfolio-508106.portfolio_b.export_dim_vat_basis`   dv  ON dv.amount_vat_basis = f.amount_vat_basis;

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.export_fact_spend_unresolved` AS
SELECT
  SUBSTR(f.spend_id, 1, 16)   AS spend_ref,
  ds.supplier_id,
  de.entity_id,
  f.date_key,
  dc.category_id,
  dsf.source_file_id,
  dv.vat_basis_id,
  f.amount,
  f.is_grant_in_aid,
  f.transaction_number,
  f.unresolved_reason
FROM `portfolio-508106.portfolio_b.fact_spend_unresolved` f
JOIN `portfolio-508106.portfolio_b.export_dim_supplier`    ds USING (supplier_key)
JOIN `portfolio-508106.portfolio_b.export_dim_entity`      de USING (entity)
JOIN `portfolio-508106.portfolio_b.export_dim_category`    dc USING (category_key)
JOIN `portfolio-508106.portfolio_b.export_dim_source_file` dsf ON dsf.source_file = f._source_file
JOIN `portfolio-508106.portfolio_b.export_dim_vat_basis`   dv  ON dv.amount_vat_basis = f.amount_vat_basis;
