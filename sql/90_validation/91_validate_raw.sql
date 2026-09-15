-- 91_validate_raw.sql
-- Layer: validation. Runs AFTER L1, not once at the end.
--
-- EXECUTABLE. V1.1-V1.5, ALL HARD. Every one must return zero failures before
-- any Layer 2 work begins.
--
-- V1.1 is the foundation of E-1. If row counts do not tie to provenance.csv,
-- nothing downstream can be trusted: resolution, the golden record, the
-- precision figure and the dashboard are all computed on whatever L1 loaded.
-- A discrepancy found here is a reload. The same discrepancy found at L4
-- invalidates every number in between.
--
-- REVISION 2026-09-13
--   * The six spend expected values are no longer 0. They are filled from
--     08-transformation-guidelines.md §5.2, independently re-derived by summing
--     provenance.records_csv_parsed per publisher — the two agree exactly.
--   * The Companies House expected value is corrected 5,695,467 -> 5,695,466.
--     See 12_create_raw_reference.sql for the full V1.5 resolution. In short:
--     part4 holds one record spanning two physical lines, and the Companies
--     House rows of provenance.csv were populated from a LINE count, not a CSV
--     parse, so the census could not see it.

-- ===========================================================================
-- V1.1  Row count per raw table equals the source record count
-- ===========================================================================
-- provenance.csv column records_csv_parsed is the reference for the six spend
-- tables. NOT row_count_raw: the two differ by 9 for DfT (embedded newlines).
-- Comparing against row_count_raw fails correctly-loaded data.
--
-- For Companies House the reference is the CORRECTED figure below, not the
-- provenance column, because that column is line-derived for this publisher.

WITH loaded AS (
  SELECT 'raw_spend_bristol'    AS tbl, COUNT(*) AS n FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
  UNION ALL SELECT 'raw_spend_york',        COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_york`
  UNION ALL SELECT 'raw_spend_dft',         COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_dft`
  UNION ALL SELECT 'raw_spend_hmrc',        COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`
  UNION ALL SELECT 'raw_spend_manchester',  COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_manchester`
  UNION ALL SELECT 'raw_spend_moj',         COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_moj`
  UNION ALL SELECT 'raw_companies_house',   COUNT(*) FROM `portfolio-508106.portfolio_b.raw_companies_house`
)
SELECT
  tbl,
  n                     AS loaded_rows,
  expected              AS expected_records,
  n - expected          AS delta,
  IF(n = expected, 'PASS', 'FAIL  <-- HARD') AS v1_1
FROM loaded
JOIN UNNEST([
  -- 08 §5.2, confirmed against provenance.records_csv_parsed summed per publisher.
  -- Spend total = 364,835 across 62 files. These counts still include the
  -- 12,221 blank padding rows (HMRC 12,201, MOJ 18, Manchester 2) — padding is
  -- removed at Layer 2, because Layer 1 drops nothing.
  STRUCT('raw_spend_bristol'   AS t,   71375 AS expected),   -- 12 files
  STRUCT('raw_spend_york',            124803),               --  2 files
  STRUCT('raw_spend_dft',              32515),               -- 12 files; 32,524 raw lines
  STRUCT('raw_spend_hmrc',             23759),               -- 12 files
  STRUCT('raw_spend_manchester',      107223),               -- 12 files
  STRUCT('raw_spend_moj',               5160),               -- 12 files
  -- Companies House: CORRECTED 2026-09-13 (was 5,695,467). See V1.5 below.
  STRUCT('raw_companies_house',      5695466)
]) AS e ON e.t = loaded.tbl
ORDER BY tbl;

-- ===========================================================================
-- V1.2  No column was dropped at load
-- ===========================================================================
-- Expected counts = canonical columns + 5 metadata:
--   bristol 14 · york 18 · dft 15 · hmrc 19 · manchester 13 · moj 14

SELECT
  table_name,
  COUNT(*) AS columns_loaded,
  COUNTIF(data_type != 'STRING') AS non_string_columns   -- must be 0 at L1
FROM `portfolio-508106.portfolio_b.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name LIKE 'raw_spend_%'
GROUP BY table_name
ORDER BY table_name;

-- ===========================================================================
-- V1.3  Every row carries the five system columns, non-null
-- ===========================================================================
-- Run per table; bristol shown. No nulls permitted in any system column.

SELECT
  COUNTIF(_source_file  IS NULL OR _source_file  = '') AS null_source_file,
  COUNTIF(_source_url   IS NULL OR _source_url   = '') AS null_source_url,
  COUNTIF(_retrieved_at IS NULL OR _retrieved_at = '') AS null_retrieved_at,
  COUNTIF(_period       IS NULL OR _period       = '') AS null_period,
  COUNTIF(_row_num      IS NULL OR _row_num      = '') AS null_row_num
FROM `portfolio-508106.portfolio_b.raw_spend_bristol`;

-- ===========================================================================
-- V1.4  _row_num is unique within _source_file
-- ===========================================================================
-- A non-zero result means the pre-load script numbered rows per-run instead of
-- per-file, and E-1's "traceable to a physical line in a named file" is broken.

SELECT _source_file, _row_num, COUNT(*) AS occurrences
FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
GROUP BY _source_file, _row_num
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;

-- ===========================================================================
-- V1.5  Companies House snapshot loaded completely
-- ===========================================================================
-- Snapshot frozen 2026-08-01, 7 parts.
--
-- RESOLVED 2026-09-13. Expected corrected 5,695,467 -> 5,695,466 on evidence
-- from 91a_reconcile_ch_per_file.sql plus a local CSV-parsed count of part4.
-- The per-part expectation is now:
--
--     part1 849,999   part2 850,000   part3 850,000   part4 849,999
--     part5 850,000   part6 850,000   part7 595,468   TOTAL 5,695,466
--
-- The only change against the acquisition census is part4, 850,000 -> 849,999:
-- one record in that file spans two physical lines (850,001 lines, 849,999
-- records). Full reasoning in 12_create_raw_reference.sql.
--
-- This corrects an EXPECTATION, not a LOAD. Nothing was reloaded and no source
-- file was altered. Whether that merged record is a legitimate quoted newline
-- or a malformed stray quote is a CONTENT question, tracked separately and
-- settled by scripts/06_identify_part4_merged_record.py before Layer 3.

SELECT
  COUNT(*)              AS total_rows,
  5695466               AS expected,
  COUNT(*) - 5695466    AS delta,
  IF(COUNT(*) = 5695466, 'PASS', 'FAIL  <-- HARD') AS v1_5
FROM `portfolio-508106.portfolio_b.raw_companies_house`;
