-- 13_create_raw_contracts_finder.sql
-- Layer: L1 raw_
-- Validation for this layer: sql/90_validation/91_validate_raw.sql
--
-- EXECUTED 2026-09-16. These are the statements that ran, not a description.
--
-- Source: Contracts Finder award notices, OCDS releases flattened to CSV by
--         scripts/04-measure-q15-v2.ps1 during acquisition (B-DS-04).
--         <VAULT>/06_ACTIVE_BUILD/portfolio-b/data/q15-v2/q15-awards.csv
--         14,643,256 bytes — under BigQuery's 100 MB local-upload limit, so it
--         is loaded directly per 08 §5.4, not staged to Cloud Storage.
--
-- WHY THIS FILE IS SPLIT INTO DDL + A LOAD COMMAND, AND THE OTHER LOADERS ARE NOT
--   11_ and 12_ use LOAD DATA FROM FILES, which reads Cloud Storage URIs.
--   BigQuery SQL CANNOT READ A LOCAL FILE. There is no SQL statement that
--   expresses this load, so the schema is defined here in DDL — one source of
--   truth, executable — and `bq load` appends into the table it creates. The
--   load command carries NO schema of its own precisely so the two cannot drift.
--
-- WHAT THIS TABLE IS FOR
--   E-3. Contracts Finder is the KNOWN-ANSWER SET for match precision: where a
--   release carries scheme = 'GB-COH', `identifier` is the company's registered
--   number as stated by the buying authority. Tier-1 matches are measured
--   against that subset in 95_measure_match_precision.sql. It is not spend data
--   and it is never summed.
--
-- NO SYSTEM COLUMNS, DELIBERATELY. raw_contracts_finder carries no _source_file,
--   _row_num or _period, for the same reason raw_companies_house does not: it is
--   a single-file REFERENCE load, not one of the 62 per-period spend files that
--   scripts/05_preload_clean.py stamps. V1.3 and V1.4a are scoped to the six
--   spend tables and this table is outside both by construction. Adding columns
--   the source does not have would be inventing provenance, not recording it.
--
-- SOURCE VERIFIED BEFORE LOADING, not after — 08 §5.4 requires 76,449 and a
-- physical line count is not a record count (the 9 DfT records prove that in
-- this very project). Parsed locally with csv.reader before any upload:
--
--     physical lines               76,450   = 1 header + 76,449 data lines
--     records parsed               76,449   <- MATCHES the required figure
--     field widths                 {9: 76449}   every row, no jagged rows
--     blank records                0
--     records w/ embedded newline  0
--
--   The file carries a UTF-8 BOM (EF BB BF) on its header line. It is harmless
--   here BECAUSE the schema below names the columns and skip_leading_rows=1
--   discards that line entirely. Had this load used autodetect, the first column
--   would have been named with the BOM attached and every later reference to it
--   would have failed for a reason nobody could see.

-- ---------------------------------------------------------------------------
-- 1. Schema — the single source of truth for this table. EXECUTABLE.
-- ---------------------------------------------------------------------------
-- Every column STRING. 03-schema-specification.md §2: "every column lands as
-- STRING. No casting, no cleaning, no dropping… casting at landing loses the
-- evidence of what was wrong."
--
-- `identifier` is the reason this matters most. It holds registered company
-- numbers such as 03813540 and 10185749. Typed as INTEGER it would lose the
-- leading zeros that Companies House numbers depend on, and the tier-1 join in
-- Layer 3 would miss exactly the records it exists to verify — silently, and in
-- the measurement that E-3 reports.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.raw_contracts_finder`
(
  slice         STRING OPTIONS(description = 'Weekly acquisition window, e.g. 2024-03-01_2024-03-07'),
  ocid          STRING OPTIONS(description = 'Open Contracting ID of the release'),
  party_id      STRING OPTIONS(description = 'Scheme-qualified supplier id, e.g. GB-COH-03813540'),
  release_date  STRING OPTIONS(description = 'ISO 8601 release timestamp, as published'),
  buyer         STRING OPTIONS(description = 'Buying authority name, as published'),
  supplier_name STRING OPTIONS(description = 'Awarded supplier name, as published'),
  scheme        STRING OPTIONS(description = 'Identifier scheme; GB-COH marks a Companies House number'),
  identifier    STRING OPTIONS(description = 'Registered number within the scheme — the E-3 known answer'),
  category      STRING OPTIONS(description = 'Scheme category, or "none" where the release carries no identifier')
);

-- ---------------------------------------------------------------------------
-- 2. Load — the step SQL cannot express. Run from the repository root.
-- ---------------------------------------------------------------------------
-- Substitute <VAULT> with the vault working folder. The path is deliberately
-- NOT written out here: this repository is public and publishing local vault
-- paths into it has been a defect in this project before.
--
--   bq --project_id=portfolio-508106 load \
--       --source_format=CSV \
--       --skip_leading_rows=1 \
--       --encoding=UTF-8 \
--       --allow_quoted_newlines \
--       --noreplace \
--       portfolio_b.raw_contracts_finder \
--       "<VAULT>/06_ACTIVE_BUILD/portfolio-b/data/q15-v2/q15-awards.csv"
--
-- --noreplace APPENDS into the table created above, so the DDL keeps ownership
-- of the schema and the load never infers one. Re-running this file end to end
-- is idempotent: CREATE OR REPLACE empties the table, then the load refills it.
--
-- --allow_quoted_newlines is set even though this file has none. It costs
-- nothing, and the alternative is that a future refresh of Contracts Finder
-- silently fragments a record into pieces that still pass a row count.

-- ---------------------------------------------------------------------------
-- 3. Verify — 08 §5.4. EXECUTABLE. REQUIRED RESULT: 76449.
-- ---------------------------------------------------------------------------

SELECT
  COUNT(*)            AS cf_rows,
  76449               AS expected,
  COUNT(*) - 76449    AS delta,
  IF(COUNT(*) = 76449, 'PASS', 'FAIL  <-- HARD') AS load_check
FROM `portfolio-508106.portfolio_b.raw_contracts_finder`;

-- ---------------------------------------------------------------------------
-- 4. Profile the E-3 known-answer subset — INFO, not a gate
-- ---------------------------------------------------------------------------
-- Recorded now, while the load is fresh, because it sizes the measurement that
-- E-3 depends on. A precision figure quoted without the size of the subset it
-- was measured on is not a measurement.

SELECT
  scheme,
  COUNT(*)                                             AS releases,
  COUNT(DISTINCT identifier)                           AS distinct_identifiers,
  COUNTIF(identifier IS NULL OR TRIM(identifier) = '') AS no_identifier
FROM `portfolio-508106.portfolio_b.raw_contracts_finder`
GROUP BY scheme
ORDER BY releases DESC;
