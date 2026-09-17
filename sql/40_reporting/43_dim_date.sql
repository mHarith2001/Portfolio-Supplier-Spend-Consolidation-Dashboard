-- 43_dim_date.sql
-- Layer: L4 reporting_
-- Validation for this layer: sql/90_validation/94_validate_reporting.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input.
--
-- ===========================================================================
-- THE DIMENSION COVERS THE DATA, AND FLAGS THE WINDOW
-- ===========================================================================
-- V4.4 requires the full window with no gaps. Two spans are involved and they
-- are NOT the same span:
--
--   DECLARED ANALYSIS WINDOW   2024-03-01 to 2025-02-28   (12 months, 08 §12)
--   OBSERVED TRANSACTION DATES 2023-04-04 to 2025-03-31
--
-- The files selected as in-window contain records dated outside it — 09 P-8.
-- Those rows are real payments and are not dropped, so the dimension is
-- generated over the OBSERVED span. Generating only the declared window would
-- leave fact rows pointing at dates that do not exist, failing V4.2, and would
-- quietly delete payments to make a date range look tidy.
--
-- `is_in_analysis_window` carries the declared window as a FLAG, so a reader can
-- restrict to it deliberately and can see how much sits outside. That makes P-8
-- visible in the dashboard instead of resolved by silent truncation.
--
-- UK PUBLIC-SECTOR FISCAL YEAR runs 1 April to 31 March, which is why the
-- observed span starts in April: it is two fiscal years of published files.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.dim_date` AS
WITH bounds AS (
  SELECT MIN(payment_date) AS d0, MAX(payment_date) AS d1
  FROM `portfolio-508106.portfolio_b.resolved_spend`
  WHERE row_role = 'transaction'
)
SELECT
  d                                                        AS date_key,
  EXTRACT(YEAR    FROM d)                                  AS calendar_year,
  EXTRACT(QUARTER FROM d)                                  AS calendar_quarter,
  EXTRACT(MONTH   FROM d)                                  AS month_number,
  FORMAT_DATE('%B', d)                                     AS month_name,
  FORMAT_DATE('%Y-%m', d)                                  AS year_month,
  EXTRACT(DAY     FROM d)                                  AS day_of_month,
  FORMAT_DATE('%A', d)                                     AS day_name,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7)                      AS is_weekend,
  -- UK public-sector fiscal year: 1 April to 31 March, labelled by its start
  IF(EXTRACT(MONTH FROM d) >= 4, EXTRACT(YEAR FROM d), EXTRACT(YEAR FROM d) - 1) AS fiscal_year,
  FORMAT('%d/%d',
    IF(EXTRACT(MONTH FROM d) >= 4, EXTRACT(YEAR FROM d), EXTRACT(YEAR FROM d) - 1),
    MOD(IF(EXTRACT(MONTH FROM d) >= 4, EXTRACT(YEAR FROM d), EXTRACT(YEAR FROM d) - 1) + 1, 100))
                                                           AS fiscal_year_label,
  d BETWEEN DATE '2024-03-01' AND DATE '2025-02-28'        AS is_in_analysis_window
FROM bounds, UNNEST(GENERATE_DATE_ARRAY(bounds.d0, bounds.d1, INTERVAL 1 DAY)) AS d;
