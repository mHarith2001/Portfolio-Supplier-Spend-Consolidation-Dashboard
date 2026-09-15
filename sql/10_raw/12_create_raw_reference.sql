-- 12_create_raw_reference.sql
-- Layer: L1 raw_
-- Validation for this layer: sql/90_validation/91_validate_raw.sql
--
-- EXECUTED 2026-09-13. This is the statement that ran, not a description of it.
--
-- Source: Companies House Free Company Data Product, snapshot 2026-08-01.
--         7 parts, extracted from .zip to CSV (BigQuery cannot read .zip).
--         ~2.61 GB staged to GCS, europe-west2.
--
-- Autodetect is used HERE AND NOWHERE ELSE (08 §5.3): all seven parts come from
-- one publisher, one system, one day, one schema. Every spend load uses an
-- explicit schema — see 11_create_raw_spend.sql.
--
-- ===========================================================================
-- V1.5 — RESOLVED 2026-09-13. The expected figure was wrong; the load is right.
-- ===========================================================================
-- The load returned 5,695,466 against a provenance figure of 5,695,467. The
-- reconciliation is closed in favour of the LOADED number, on evidence:
--
--   1. 91a_reconcile_ch_per_file.sql localised the gap to ONE file: part4
--      loaded 849,999 against a census figure of 850,000. Every other part
--      matched exactly (delta 0), and the external-table total equalled the
--      managed-table total — so the load did not lose a row.
--
--   2. part4 on disk: 850,001 physical lines, 849,999 records when parsed with
--      Python csv.reader. BigQuery's parse and Python's parse agree exactly.
--      One record spans two physical lines.
--
--   3. The census could not have seen that. In provenance.csv, all seven
--      Companies House rows satisfy records_csv_parsed = row_count_raw - 1
--      EXACTLY. The column is named records_csv_parsed but for Companies House
--      it was populated from a LINE count, not a CSV parse — so it is blind to
--      embedded newlines by construction. The 62 spend rows were genuinely
--      parsed, which is why DfT correctly shows 32,524 raw against 32,515
--      records there and nothing similar appears here.
--
--   4. part1's 849,999 is real and benign. 91a returned delta 0 for it, so
--      BigQuery's parse agrees with the census figure; part1 simply has no
--      trailing newline on its final line. It is NOT a second short file.
--
-- CORRECTED per-part expectation (used by 91_validate_raw.sql V1.5):
--      part1 849,999 · part2 850,000 · part3 850,000 · part4 849,999
--      part5 850,000 · part6 850,000 · part7 595,468   TOTAL 5,695,466
--
-- CARRIED FORWARD, open and separate: whether part4's merged record is a
-- LEGITIMATE quoted newline (record intact — 849,999 is simply true) or a
-- MALFORMED stray quote (two company records merged; one company missing from
-- the table, another with corrupted fields, and tier-1 matching failing
-- silently for both). The row COUNT is settled either way; the row CONTENT is
-- not. Classify it with scripts/06_identify_part4_merged_record.py before
-- Layer 3 entity resolution. It does not block Layer 1 or the spend pipeline.
--
-- Also verified after load, before any bucket deletion:
--   CompanyNumber data_type = STRING   PASS
--     An INTEGER inference would strip the leading zeros from numbers like
--     00445790 and fail SC/NI/OC-prefixed ones, breaking tier-1 matching
--     silently. Confirmed STRING before deletion, while a reload was still cheap.

LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_companies_house`
FROM FILES (
  format = 'CSV',
  -- BUCKET CONFIRMED 2026-09-14 by `gcloud storage ls`: exactly ONE bucket
  -- exists in the project — gs://portfolio-b-spend-mh2026/ — holding 7 objects,
  -- 2,803,372,555 bytes (2.61 GiB), one per Companies House part, with sizes
  -- matching the local files byte for byte. 'portfolio-b-ch-staging' does NOT
  -- exist and never did; it was an error in an execution report. No second
  -- bucket, therefore no dead storage billing.
  --
  -- NOTE the name says "spend" but the contents are the Companies House
  -- reference data. The clean spend files should go into a prefix of THIS
  -- bucket (gs://portfolio-b-spend-mh2026/clean/) rather than a second bucket,
  -- so D-P-029 condition 2 has exactly one thing to delete.
  --
  -- The URI is therefore FILE-PREFIXED, not a bare '*.csv'. As executed it read
  -- '*.csv' against a bucket that held only the 7 part files; once clean spend
  -- files share the bucket, a bare wildcard would sweep them in and this
  -- statement would stop being re-runnable. Prefixing changes nothing about
  -- what was loaded and keeps E-6 honest.
  uris = ['gs://portfolio-b-spend-mh2026/BasicCompanyData-2026-08-01-part*_7.csv'],
  skip_leading_rows = 1,
  column_name_character_map = 'V2',
  allow_jagged_rows = true,
  allow_quoted_newlines = true
);
