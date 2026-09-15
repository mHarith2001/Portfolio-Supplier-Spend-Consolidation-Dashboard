-- 91a_reconcile_ch_per_file.sql
-- Layer: validation. Diagnostic for V1.5.
--
-- PURPOSE: the Companies House load came back ONE ROW SHORT — 5,695,466 against
-- provenance's 5,695,467. This localises the missing row to a single part file.
--
-- RUN THIS BEFORE DELETING THE STAGING BUCKET. It needs the GCS objects.
-- Do NOT reload first: an identical reload of identical inputs with identical
-- settings produces an identical result. Diagnose, then decide.
--
-- WHY AN EXTERNAL TABLE. LOAD DATA writes a managed table, and a managed table
-- does not retain which source file each row came from. An external table over
-- the same URIs exposes the _FILE_NAME pseudo-column, which is the only way to
-- get a per-file count without re-reading the local CSVs.
--
-- COST: a full scan of ~2.61 GB. Far inside the 1 TiB/month free tier.

-- ===========================================================================
-- EXECUTED 2026-09-13. RESULT RECORDED — outcome (b) of §3 below.
-- ===========================================================================
--   part1 849,999 = census   delta 0
--   part2 850,000 = census   delta 0
--   part3 850,000 = census   delta 0
--   part4 849,999 vs 850,000 delta -1   <-- THE SHORT FILE
--   part5 850,000 = census   delta 0
--   part6 850,000 = census   delta 0
--   part7 595,468 = census   delta 0
--   External total = managed total, so LOAD DATA lost nothing.
--
-- Resolved against the local CSV: part4 is 850,001 physical lines and 849,999
-- records under csv.reader. ONE record spans two physical lines. The census was
-- line-derived for this publisher (records_csv_parsed = row_count_raw - 1 for
-- all seven parts), so it could not see it. V1.5 expected corrected to
-- 5,695,466 — see 12_create_raw_reference.sql. NO RELOAD.
--
-- The §2 census literals below are left AS THEY WERE WHEN THIS RAN, so the
-- diagnostic still reproduces the delta that led to the finding. The corrected
-- expectation lives in 91_validate_raw.sql, which is the control; this file is
-- the diagnostic that produced it.
--
-- BUCKET: confirmed 2026-09-14 as gs://portfolio-b-spend-mh2026/ — the only
-- bucket in the project. 'portfolio-b-ch-staging' does not exist.

-- ---------------------------------------------------------------------------
-- 1. External table over the same objects the load read
-- ---------------------------------------------------------------------------
CREATE OR REPLACE EXTERNAL TABLE `portfolio-508106.portfolio_b.ext_ch_reconcile`
OPTIONS (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/BasicCompanyData-2026-08-01-part*_7.csv'],
  skip_leading_rows = 1,
  allow_jagged_rows = true,
  allow_quoted_newlines = true
);

-- ---------------------------------------------------------------------------
-- 2. Per-file counts against the acquisition census
-- ---------------------------------------------------------------------------
-- Census figures are from data/companies_house/companies-house-row-counts.csv,
-- taken 2026-08-29. Note part1: it is the ONLY part not at 850,000 records, and
-- the only one whose raw line count is 850,000 rather than 850,001. That
-- irregularity is exactly the size of the discrepancy, so it is the first place
-- to look — but it is a lead, not a conclusion.

WITH per_file AS (
  SELECT
    REGEXP_EXTRACT(_FILE_NAME, r'part(\d)_7') AS part,
    COUNT(*) AS loaded
  FROM `portfolio-508106.portfolio_b.ext_ch_reconcile`
  GROUP BY part
),
census AS (
  SELECT * FROM UNNEST([
    STRUCT('1' AS part, 849999 AS expected),
    STRUCT('2', 850000), STRUCT('3', 850000), STRUCT('4', 850000),
    STRUCT('5', 850000), STRUCT('6', 850000), STRUCT('7', 595468)
  ])
)
SELECT
  c.part,
  c.expected,
  p.loaded,
  p.loaded - c.expected AS delta,
  IF(p.loaded = c.expected, 'ok', '<-- THE SHORT FILE') AS flag
FROM census c
LEFT JOIN per_file p USING (part)
ORDER BY c.part;

-- ---------------------------------------------------------------------------
-- 3. Interpreting the result — two outcomes, two different actions
-- ---------------------------------------------------------------------------
--
-- (a) EVERY part matches its census figure, and the total is 5,695,467.
--     Then the managed table lost a row the external read did not, which
--     points at the load rather than the source. Reload and re-count.
--
-- (b) ONE part is short by 1 against the census.
--     Then the question is whether the census over-counted or the file really
--     holds one fewer record. Resolve it against the local CSV, which is the
--     only authority left once GCS and BigQuery agree with each other:
--
--       python -c "import csv,sys; f=open(sys.argv[1],encoding='utf-8',newline=''); print(sum(1 for _ in csv.reader(f))-1)" data/raw/BasicCompanyData-2026-08-01-part1_7.csv
--
--     A CSV-parsed count is authoritative; a line count is not. The 9 DfT
--     records prove that in this very project — raw lines 364,844 against
--     364,835 true records.
--
-- EITHER WAY, V1.1 passes against a CORRECTED, EVIDENCED figure or not at all.
-- Adjusting the expected number to match the loaded number without finding out
-- why is how a reconciliation control becomes decorative.

-- ---------------------------------------------------------------------------
-- 4. Clean up the external table once the answer is recorded
-- ---------------------------------------------------------------------------
-- DROP EXTERNAL TABLE `portfolio-508106.portfolio_b.ext_ch_reconcile`;
