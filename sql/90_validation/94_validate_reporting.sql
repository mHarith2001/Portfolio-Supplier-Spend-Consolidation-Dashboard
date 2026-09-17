-- 94_validate_reporting.sql
-- Layer: validation. Runs AFTER L4.
--
-- EXECUTED 2026-09-18. V4.1-V4.6.
--
-- Run from a file on standard input:
--   cmd /c "bq query --use_legacy_sql=false --format=pretty < sql\90_validation\94_validate_reporting.sql"
--
-- V4.1 is the end-to-end reconciliation: the two fact tables together must equal
-- the transaction total in staging_spend. It is the last link in the chain
-- raw -> staging -> resolved -> reporting, and the one a reader can re-run.

-- ===========================================================================
-- V4.1  fact_spend + fact_spend_unresolved = transaction total      HARD
-- ===========================================================================
-- Scoped to transactions (05, 2026-09-18): Layer 4 carries transactions only, so
-- an all-rows comparison would fail by construction — by exactly the
-- GBP 2,556,596,745.72 that row_role excludes.

WITH src AS (
  SELECT COUNT(*) AS rows_n, ROUND(SUM(amount), 2) AS amt
  FROM `portfolio-508106.portfolio_b.staging_spend` WHERE row_role = 'transaction'
),
f AS (
  SELECT COUNT(*) AS rows_n, ROUND(SUM(amount), 2) AS amt FROM `portfolio-508106.portfolio_b.fact_spend`
),
u AS (
  SELECT COUNT(*) AS rows_n, ROUND(SUM(amount), 2) AS amt FROM `portfolio-508106.portfolio_b.fact_spend_unresolved`
)
SELECT
  src.rows_n                             AS staging_transaction_rows,
  f.rows_n                               AS fact_spend_rows,
  u.rows_n                               AS fact_unresolved_rows,
  f.rows_n + u.rows_n                    AS fact_rows_total,
  src.amt                                AS staging_transaction_amount,
  f.amt                                  AS fact_spend_amount,
  u.amt                                  AS fact_unresolved_amount,
  ROUND(f.amt + u.amt, 2)                AS fact_amount_total,
  ROUND(src.amt - (f.amt + u.amt), 2)    AS difference,
  IF(src.rows_n = f.rows_n + u.rows_n AND ROUND(src.amt - (f.amt + u.amt), 2) = 0,
     'PASS', 'FAIL  <-- HARD') AS v4_1
FROM src, f, u;

-- ===========================================================================
-- V4.2  every foreign key resolves to its dimension                 HARD
-- ===========================================================================
-- Both fact tables, all four keys. An orphan key is a row that will silently
-- vanish from a dashboard the first time someone adds a dimension filter.

WITH allf AS (
  SELECT spend_id, supplier_key, entity, date_key, category_key FROM `portfolio-508106.portfolio_b.fact_spend`
  UNION ALL
  SELECT spend_id, supplier_key, entity, date_key, category_key FROM `portfolio-508106.portfolio_b.fact_spend_unresolved`
)
SELECT
  COUNT(*)                                                     AS fact_rows,
  COUNTIF(ds.supplier_key IS NULL)                             AS orphan_supplier_key,
  COUNTIF(de.entity IS NULL)                                   AS orphan_entity,
  COUNTIF(dd.date_key IS NULL)                                 AS orphan_date_key,
  COUNTIF(dc.category_key IS NULL)                             AS orphan_category_key,
  COUNTIF(allf.supplier_key IS NULL OR allf.entity IS NULL
          OR allf.date_key IS NULL OR allf.category_key IS NULL) AS null_keys,
  IF(COUNTIF(ds.supplier_key IS NULL) = 0 AND COUNTIF(de.entity IS NULL) = 0
     AND COUNTIF(dd.date_key IS NULL) = 0 AND COUNTIF(dc.category_key IS NULL) = 0,
     'PASS', 'FAIL  <-- HARD') AS v4_2
FROM allf
LEFT JOIN `portfolio-508106.portfolio_b.dim_supplier` ds USING (supplier_key)
LEFT JOIN `portfolio-508106.portfolio_b.dim_entity`   de USING (entity)
LEFT JOIN `portfolio-508106.portfolio_b.dim_date`     dd USING (date_key)
LEFT JOIN `portfolio-508106.portfolio_b.dim_category` dc USING (category_key);

-- ===========================================================================
-- V4.3  dim_category has an uncategorised member                    HARD
-- V4.4  dim_date covers the full span with no gaps                  HARD
-- V4.5  dim_supplier includes an unresolved bucket                  HARD
-- ===========================================================================
-- V4.4 is checked two ways: the dimension has no internal gap (row count equals
-- the day count of its own span), AND it covers the observed fact dates. A
-- gapless dimension that stops short of the data is still a broken dimension.

SELECT
  (SELECT COUNTIF(is_uncategorised) FROM `portfolio-508106.portfolio_b.dim_category`) AS uncategorised_members,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.dim_category`)                  AS category_rows,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.dim_date`)                      AS date_rows,
  (SELECT DATE_DIFF(MAX(date_key), MIN(date_key), DAY) + 1
     FROM `portfolio-508106.portfolio_b.dim_date`)                                    AS days_in_span,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.fact_spend` f
    WHERE NOT EXISTS (SELECT 1 FROM `portfolio-508106.portfolio_b.dim_date` d
                       WHERE d.date_key = f.date_key))                                AS fact_dates_uncovered,
  (SELECT COUNTIF(is_in_analysis_window) FROM `portfolio-508106.portfolio_b.dim_date`) AS days_in_analysis_window,
  (SELECT COUNTIF(NOT is_resolved) FROM `portfolio-508106.portfolio_b.dim_supplier`)   AS unresolved_bucket_rows,
  (SELECT COUNTIF(is_resolved) FROM `portfolio-508106.portfolio_b.dim_supplier`)       AS resolved_suppliers,
  IF((SELECT COUNTIF(is_uncategorised) FROM `portfolio-508106.portfolio_b.dim_category`) = 1,
     'PASS', 'FAIL  <-- HARD') AS v4_3,
  IF((SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.dim_date`)
     = (SELECT DATE_DIFF(MAX(date_key), MIN(date_key), DAY) + 1 FROM `portfolio-508106.portfolio_b.dim_date`)
     AND (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.fact_spend` f
           WHERE NOT EXISTS (SELECT 1 FROM `portfolio-508106.portfolio_b.dim_date` d
                              WHERE d.date_key = f.date_key)) = 0,
     'PASS', 'FAIL  <-- HARD') AS v4_4,
  IF((SELECT COUNTIF(NOT is_resolved) FROM `portfolio-508106.portfolio_b.dim_supplier`) > 0,
     'PASS', 'FAIL  <-- HARD') AS v4_5;

-- ===========================================================================
-- V4.6  aggregating by supplier does not exceed the total           HARD
-- ===========================================================================
-- The fan-out check. A many-to-many join into dim_supplier would multiply rows
-- and inflate every supplier total on the dashboard while each individual figure
-- still looked plausible. This compares the fact total against the total after a
-- full group-by-and-join round trip.

WITH direct AS (
  SELECT ROUND(SUM(amount), 2) AS amt, COUNT(*) AS rows_n
  FROM `portfolio-508106.portfolio_b.fact_spend`
),
via_supplier AS (
  SELECT ROUND(SUM(t.amt), 2) AS amt, SUM(t.rows_n) AS rows_n
  FROM (
    SELECT d.supplier_key, SUM(f.amount) AS amt, COUNT(*) AS rows_n
    FROM `portfolio-508106.portfolio_b.fact_spend` f
    JOIN `portfolio-508106.portfolio_b.dim_supplier` d USING (supplier_key)
    GROUP BY d.supplier_key
  ) t
)
SELECT
  direct.rows_n            AS fact_rows,
  via_supplier.rows_n      AS rows_after_join,
  direct.amt               AS fact_amount,
  via_supplier.amt         AS amount_after_join,
  ROUND(via_supplier.amt - direct.amt, 2) AS inflation,
  IF(direct.rows_n = via_supplier.rows_n AND ROUND(via_supplier.amt - direct.amt, 2) = 0,
     'PASS', 'FAIL  <-- HARD') AS v4_6
FROM direct, via_supplier;

-- ===========================================================================
-- The consolidation finding — INFO, and the reason the project exists
-- ===========================================================================
-- How many vendor records exist, against how many suppliers there actually are.

SELECT
  (SELECT COUNT(DISTINCT supplier_name_raw) FROM `portfolio-508106.portfolio_b.staging_spend`
    WHERE row_role = 'transaction')                                     AS raw_vendor_spellings,
  (SELECT COUNT(DISTINCT supplier_name_norm) FROM `portfolio-508106.portfolio_b.staging_spend`
    WHERE row_role = 'transaction')                                     AS normalised_names,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.dim_supplier`)    AS dim_supplier_rows,
  (SELECT COUNTIF(is_resolved) FROM `portfolio-508106.portfolio_b.dim_supplier`) AS resolved_entities,
  (SELECT MAX(name_variant_count) FROM `portfolio-508106.portfolio_b.dim_supplier`) AS most_spellings_one_supplier;

-- ===========================================================================
-- Resolved against unresolved, by value — INFO
-- ===========================================================================

SELECT 'resolved'   AS population, COUNT(*) AS rows_n, ROUND(SUM(amount), 2) AS value
FROM `portfolio-508106.portfolio_b.fact_spend`
UNION ALL
SELECT 'unresolved', COUNT(*), ROUND(SUM(amount), 2)
FROM `portfolio-508106.portfolio_b.fact_spend_unresolved`
ORDER BY population;

-- ===========================================================================
-- The ten largest suppliers — INFO, the dashboard's headline table
-- ===========================================================================
-- Resolved suppliers only, because an unresolved name is not a supplier, it is a
-- string. name_variant_count is printed beside the value: it shows how many
-- spellings had to be collapsed before the figure could be stated at all.

SELECT
  d.supplier_name,
  d.company_number,
  d.company_status,
  d.name_variant_count,
  COUNT(*)                     AS transaction_rows,
  ROUND(SUM(f.amount), 2)      AS total_spend,
  COUNT(DISTINCT f.entity)     AS paying_bodies
FROM `portfolio-508106.portfolio_b.fact_spend` f
JOIN `portfolio-508106.portfolio_b.dim_supplier` d USING (supplier_key)
GROUP BY d.supplier_name, d.company_number, d.company_status, d.name_variant_count
ORDER BY total_spend DESC
LIMIT 10;

-- ===========================================================================
-- Out-of-window transactions — INFO, 09 P-8 made visible
-- ===========================================================================
-- The declared analysis window is 2024-03-01 to 2025-02-28. In-window FILES
-- carry out-of-window RECORDS. They are reported, not truncated away.

SELECT
  dd.is_in_analysis_window,
  COUNT(*)                          AS transaction_rows,
  ROUND(SUM(f.amount), 2)           AS value,
  MIN(f.date_key)                   AS earliest,
  MAX(f.date_key)                   AS latest
FROM (
  SELECT date_key, amount FROM `portfolio-508106.portfolio_b.fact_spend`
  UNION ALL
  SELECT date_key, amount FROM `portfolio-508106.portfolio_b.fact_spend_unresolved`
) f
JOIN `portfolio-508106.portfolio_b.dim_date` dd USING (date_key)
GROUP BY dd.is_in_analysis_window
ORDER BY dd.is_in_analysis_window DESC;
