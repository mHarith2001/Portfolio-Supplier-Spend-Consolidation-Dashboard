-- 91_validate_raw.sql
-- Layer: validation. Runs AFTER L1, not once at the end.
--
-- EXECUTABLE. V1.1-V1.5 plus V1.4a, ALL HARD. Every one must return zero
-- failures before any Layer 2 work begins.
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
--
-- ===========================================================================
-- REVISION 2026-09-16 — three changes. Read this before editing any expected
-- value in this file.
-- ===========================================================================
--
--   1. COMPANIES HOUSE: THE CHECK WAS WRONG, NOT THE LOAD AND NOT THE FIGURE.
--      V1.1 and V1.5 compared a BigQuery TABLE ROW COUNT against a CSV RECORD
--      COUNT. Those are two different quantities. They differ by exactly one
--      blank line, so the check could never pass however well the load ran.
--
--          5,695,466   CSV records across the seven parts.
--                      csv.reader yields this; a blank line IS a record.
--                      THE RATIFIED FIGURE — unchanged, and correct as such.
--        -         1   part4 record #454,676 — an empty line, 0 fields.
--                      BigQuery does not materialise an empty CSV line as a row.
--        = 5,695,465   company records = COUNT(*) on raw_companies_house.
--                      THE ONLY QUANTITY A TABLE ROW COUNT CAN BE COMPARED TO.
--
--      Evidence, three independent strands:
--        a. Local stream of part4 — docs/v1_5_part4_diagnostic.md. 849,999 CSV
--           records, reproducing the ratified chain EXACTLY, of which one is
--           blank. 849,998 company records. Field widths {55: 849998, 0: 1}.
--        b. External table over the same GCS objects, anti-joined to the managed
--           table on company number: exactly ONE row present in GCS and absent
--           from the table, and it carries a NULL CompanyNumber and a NULL
--           CompanyName. No company record is missing.
--        c. Table metadata: creationTime == lastModifiedTime == 2026-09-13
--           19:24:51 UTC, numRows 5,695,465. The table has never been modified
--           since creation, so there was no load change to investigate.
--
--      CORRECTED per-part line, both quantities stated:
--        part1 849,999 · part2 850,000 · part3 850,000
--        part4 849,999 CSV records / 849,998 company records   <- the blank line
--        part5 850,000 · part6 850,000 · part7 595,468
--        TOTAL 5,695,466 CSV records / 5,695,465 company records
--
--      NOTHING WAS RELOADED AND NO SOURCE FILE WAS ALTERED.
--
--   2. V1.3 AND V1.4 NOW RUN ON ALL SIX SPEND TABLES. Both were written against
--      raw_spend_bristol alone. A per-table check that ran on one table is not a
--      pass for six, and reporting it as one is how a validation report becomes
--      decorative.
--
--   3. V1.4a ADDED. V1.4 is necessary but weak — see its own header.

-- ===========================================================================
-- V1.1  Row count per raw table equals the source record count
-- ===========================================================================
-- provenance.csv column records_csv_parsed is the reference for the six spend
-- tables. NOT row_count_raw: the two differ by 9 for DfT (embedded newlines).
-- Comparing against row_count_raw fails correctly-loaded data.
--
-- For Companies House the reference is the derived COMPANY-RECORD figure below,
-- not the provenance column. That column is line-derived for this publisher and
-- counts part4's blank line as a record. See REVISION 2026-09-16 item 1.

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
  STRUCT('raw_spend_dft',              32515),               -- 12 files, 32,524 raw lines
  STRUCT('raw_spend_hmrc',             23759),               -- 12 files
  STRUCT('raw_spend_manchester',      107223),               -- 12 files
  STRUCT('raw_spend_moj',               5160),               -- 12 files
  -- Companies House COMPANY RECORDS = 5,695,466 CSV records - 1 blank line.
  -- The blank line is part4 record #454,676. Corrected 2026-09-16. The ratified
  -- CSV-record figure of 5,695,466 is unchanged and is simply not what a table
  -- row count measures. See REVISION 2026-09-16 item 1.
  STRUCT('raw_companies_house',      5695465)
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
-- ALL SIX SPEND TABLES. Every count must read 0.
-- Extended 2026-09-16; this was written against raw_spend_bristol alone.

WITH s AS (
  SELECT 'raw_spend_bristol'    AS tbl, _source_file,_source_url,_retrieved_at,_period,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
  UNION ALL SELECT 'raw_spend_york',        _source_file,_source_url,_retrieved_at,_period,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_york`
  UNION ALL SELECT 'raw_spend_dft',         _source_file,_source_url,_retrieved_at,_period,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_dft`
  UNION ALL SELECT 'raw_spend_hmrc',        _source_file,_source_url,_retrieved_at,_period,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`
  UNION ALL SELECT 'raw_spend_manchester',  _source_file,_source_url,_retrieved_at,_period,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_manchester`
  UNION ALL SELECT 'raw_spend_moj',         _source_file,_source_url,_retrieved_at,_period,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_moj`
)
SELECT
  tbl,
  COUNTIF(_source_file  IS NULL OR _source_file  = '') AS null_source_file,
  COUNTIF(_source_url   IS NULL OR _source_url   = '') AS null_source_url,
  COUNTIF(_retrieved_at IS NULL OR _retrieved_at = '') AS null_retrieved_at,
  COUNTIF(_period       IS NULL OR _period       = '') AS null_period,
  COUNTIF(_row_num      IS NULL OR _row_num      = '') AS null_row_num
FROM s
GROUP BY tbl
ORDER BY tbl;

-- ===========================================================================
-- V1.4  _row_num is unique within _source_file
-- ===========================================================================
-- ALL SIX SPEND TABLES. duplicate_file_rownum_pairs must be 0.
-- Extended 2026-09-16; this was written against raw_spend_bristol alone — the
-- same defect V1.3 had, in the statement immediately above it.
--
-- A non-zero result means the pre-load script numbered rows per-run instead of
-- per-file, and E-1's "traceable to a physical line in a named file" is broken.

WITH s AS (
  SELECT 'raw_spend_bristol'    AS tbl, _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
  UNION ALL SELECT 'raw_spend_york',        _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_york`
  UNION ALL SELECT 'raw_spend_dft',         _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_dft`
  UNION ALL SELECT 'raw_spend_hmrc',        _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`
  UNION ALL SELECT 'raw_spend_manchester',  _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_manchester`
  UNION ALL SELECT 'raw_spend_moj',         _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_moj`
)
SELECT
  tbl,
  COUNT(*) AS rows_total,
  COUNT(*) - COUNT(DISTINCT CONCAT(_source_file, '#', _row_num)) AS duplicate_file_rownum_pairs
FROM s
GROUP BY tbl
ORDER BY tbl;

-- ===========================================================================
-- V1.4a  Per-file traceability — the check V1.4 cannot perform
-- ===========================================================================
-- ADDED 2026-09-16. HARD. 62 rows expected, every one PASS.
--
-- WHY THIS EXISTS. V1.4 passes on a file whose rows were uniformly renumbered,
-- because a contiguous renumbering is still perfectly unique within that file.
-- It also passes on a COMPENSATING error — one file over, another under —
-- because V1.1 reconciles only at publisher level.
--
-- This project has already produced exactly that failure mode once. The pre-load
-- script skipped blank padding rows, and because the padding in
-- Ministry_of_Justice__2025-01.csv is INTERIOR rather than trailing (body
-- positions 346, 347, 364, 365, 370, 376, 378, 393, 401, 406, with real records
-- continuing to 418), every _row_num after position 346 was silently shifted.
-- V1.4 WOULD HAVE PASSED ON THAT CORRUPTION.
--
-- WHAT IT TESTS, per file: the row count equals that file's own
-- provenance.records_csv_parsed, AND _row_num runs exactly 1..N with no gaps,
-- no duplicates and nothing non-numeric. A FULL OUTER JOIN is used so that a
-- file missing from either side is a failure rather than a silently absent row.
--
-- The 62 expected values below are GENERATED from docs/provenance.csv, not
-- transcribed. Regenerate and diff them after any provenance correction:
--
--   python -c "import csv,io;[print(r['local_file'],r['records_csv_parsed']) for r in csv.DictReader(io.open('docs/provenance.csv',encoding='utf-8-sig',newline='')) if r['publisher']!='Companies House']"
--
-- Companies House is absent by construction: raw_companies_house carries no
-- _source_file column, so it cannot participate in a per-file tie. Its
-- equivalent control is V1.5.

WITH s AS (
  SELECT _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
  UNION ALL SELECT _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_york`
  UNION ALL SELECT _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_dft`
  UNION ALL SELECT _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`
  UNION ALL SELECT _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_manchester`
  UNION ALL SELECT _source_file,_row_num FROM `portfolio-508106.portfolio_b.raw_spend_moj`
),
per_file AS (
  SELECT
    _source_file,
    COUNT(*)                                      AS rows_in_file,
    COUNT(DISTINCT _row_num)                      AS distinct_row_nums,
    MIN(SAFE_CAST(_row_num AS INT64))             AS min_rn,
    MAX(SAFE_CAST(_row_num AS INT64))             AS max_rn,
    COUNTIF(SAFE_CAST(_row_num AS INT64) IS NULL) AS non_numeric_rn
  FROM s
  GROUP BY _source_file
),
expected AS (
  SELECT * FROM UNNEST([
    STRUCT('Bristol_City_Council__2024-03.csv'     AS f,   7167 AS expected),
    STRUCT('Bristol_City_Council__2024-04.csv'    ,         6727),
    STRUCT('Bristol_City_Council__2024-05.csv'    ,         6574),
    STRUCT('Bristol_City_Council__2024-06.csv'    ,         5381),
    STRUCT('Bristol_City_Council__2024-07.csv'    ,         5945),
    STRUCT('Bristol_City_Council__2024-08.csv'    ,         6077),
    STRUCT('Bristol_City_Council__2024-09.csv'    ,         4984),
    STRUCT('Bristol_City_Council__2024-10.csv'    ,         5868),
    STRUCT('Bristol_City_Council__2024-11.csv'    ,         5898),
    STRUCT('Bristol_City_Council__2024-12.csv'    ,         5412),
    STRUCT('Bristol_City_Council__2025-01.csv'    ,         5725),
    STRUCT('Bristol_City_Council__2025-02.csv'    ,         5617),
    STRUCT('City_of_York_Council__2024-03.csv'    ,        61708),
    STRUCT('City_of_York_Council__2024-04.csv'    ,        63095),
    STRUCT('Department_for_Transport__2024-03.csv',         3515),
    STRUCT('Department_for_Transport__2024-04.csv',         3045),
    STRUCT('Department_for_Transport__2024-05.csv',         2446),
    STRUCT('Department_for_Transport__2024-06.csv',         2599),
    STRUCT('Department_for_Transport__2024-07.csv',         2838),
    STRUCT('Department_for_Transport__2024-08.csv',         2492),
    STRUCT('Department_for_Transport__2024-09.csv',         2440),
    STRUCT('Department_for_Transport__2024-10.csv',         2793),
    STRUCT('Department_for_Transport__2024-11.csv',         2561),
    STRUCT('Department_for_Transport__2024-12.csv',         2644),
    STRUCT('Department_for_Transport__2025-01.csv',         2556),
    STRUCT('Department_for_Transport__2025-02.csv',         2586),
    STRUCT('HM_Revenue_and_Customs__2024-03.csv'  ,         1072),
    STRUCT('HM_Revenue_and_Customs__2024-04.csv'  ,          987),
    STRUCT('HM_Revenue_and_Customs__2024-05.csv'  ,          875),
    STRUCT('HM_Revenue_and_Customs__2024-06.csv'  ,          900),
    STRUCT('HM_Revenue_and_Customs__2024-07.csv'  ,         4991),
    STRUCT('HM_Revenue_and_Customs__2024-08.csv'  ,         4991),
    STRUCT('HM_Revenue_and_Customs__2024-09.csv'  ,         4991),
    STRUCT('HM_Revenue_and_Customs__2024-10.csv'  ,          976),
    STRUCT('HM_Revenue_and_Customs__2024-11.csv'  ,          955),
    STRUCT('HM_Revenue_and_Customs__2024-12.csv'  ,         1101),
    STRUCT('HM_Revenue_and_Customs__2025-01.csv'  ,          918),
    STRUCT('HM_Revenue_and_Customs__2025-02.csv'  ,         1002),
    STRUCT('Manchester_City_Council__2024-03.csv' ,         5355),
    STRUCT('Manchester_City_Council__2024-04.csv' ,        10440),
    STRUCT('Manchester_City_Council__2024-05.csv' ,         7550),
    STRUCT('Manchester_City_Council__2024-06.csv' ,        10047),
    STRUCT('Manchester_City_Council__2024-07.csv' ,        10446),
    STRUCT('Manchester_City_Council__2024-08.csv' ,         6286),
    STRUCT('Manchester_City_Council__2024-09.csv' ,         9275),
    STRUCT('Manchester_City_Council__2024-10.csv' ,        11748),
    STRUCT('Manchester_City_Council__2024-11.csv' ,        10698),
    STRUCT('Manchester_City_Council__2024-12.csv' ,         9879),
    STRUCT('Manchester_City_Council__2025-01.csv' ,         8298),
    STRUCT('Manchester_City_Council__2025-02.csv' ,         7201),
    STRUCT('Ministry_of_Justice__2024-03.csv'     ,          522),
    STRUCT('Ministry_of_Justice__2024-04.csv'     ,          504),
    STRUCT('Ministry_of_Justice__2024-05.csv'     ,          410),
    STRUCT('Ministry_of_Justice__2024-06.csv'     ,          429),
    STRUCT('Ministry_of_Justice__2024-07.csv'     ,          377),
    STRUCT('Ministry_of_Justice__2024-08.csv'     ,          394),
    STRUCT('Ministry_of_Justice__2024-09.csv'     ,          440),
    STRUCT('Ministry_of_Justice__2024-10.csv'     ,          382),
    STRUCT('Ministry_of_Justice__2024-11.csv'     ,          441),
    STRUCT('Ministry_of_Justice__2024-12.csv'     ,          497),
    STRUCT('Ministry_of_Justice__2025-01.csv'     ,          418),
    STRUCT('Ministry_of_Justice__2025-02.csv'     ,          346)
  ])
)
SELECT
  COALESCE(p._source_file, e.f) AS source_file,
  e.expected                    AS provenance_records,
  p.rows_in_file,
  p.min_rn,
  p.max_rn,
  CASE
    WHEN p._source_file IS NULL                   THEN 'FAIL  <-- HARD  file absent from BigQuery'
    WHEN e.f IS NULL                              THEN 'FAIL  <-- HARD  file absent from provenance'
    WHEN p.rows_in_file      != e.expected        THEN 'FAIL  <-- HARD  row count'
    WHEN p.distinct_row_nums != e.expected        THEN 'FAIL  <-- HARD  _row_num not unique'
    WHEN p.min_rn != 1 OR p.max_rn != e.expected  THEN 'FAIL  <-- HARD  _row_num range'
    WHEN p.non_numeric_rn    != 0                 THEN 'FAIL  <-- HARD  _row_num non-numeric'
    ELSE 'PASS'
  END AS v1_4a
FROM per_file p
FULL OUTER JOIN expected e ON e.f = p._source_file
ORDER BY IF(v1_4a = 'PASS', 1, 0), source_file;

-- ===========================================================================
-- V1.5  Companies House snapshot loaded completely
-- ===========================================================================
-- Snapshot frozen 2026-08-01, 7 parts.
--
-- The expected value is COMPANY RECORDS, because COUNT(*) on a table returns
-- rows and a blank CSV line never becomes one:
--
--       5,695,466   CSV records across the seven parts   <- ratified, unchanged
--     -         1   part4 record #454,676, a blank line, 0 fields
--     = 5,695,465   company records
--
-- Evidence: docs/v1_5_part4_diagnostic.md — a local stream of part4 returning
-- 849,999 CSV records, 1 blank, 849,998 company records, field widths
-- {55: 849998, 0: 1} — plus the GCS-to-table anti-join, which returns exactly
-- one row and that row carries a NULL CompanyNumber. No company record is
-- missing from the table.
--
-- The part4 embedded newline is a separate question and it is SETTLED BENIGN:
-- record #454,675 has 55 fields against a 55-field header — a LEGITIMATE quoted
-- newline inside PreviousName_10.CompanyName of company 09056746. The record is
-- intact, no fields are shifted, and tier-1 matching will not fail silently.

SELECT
  COUNT(*)              AS total_rows,
  5695465               AS expected_company_records,
  5695466               AS csv_records_ratified,
  COUNT(*) - 5695465    AS delta,
  IF(COUNT(*) = 5695465, 'PASS', 'FAIL  <-- HARD') AS v1_5
FROM `portfolio-508106.portfolio_b.raw_companies_house`;
