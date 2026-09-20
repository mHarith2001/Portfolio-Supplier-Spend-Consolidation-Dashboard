-- 33_match_tier3_name_postcode.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
--
-- EXECUTED 2026-09-17. Run from a file on standard input. Needs 31 first.
--
-- 04 §3 tier 3: supplier_name_core + postcode, "postcode present on both sides".
-- Confidence 'medium'.
--
-- The CORE ignores the legal-form suffix (04 §2 step 9), so 'ACME' supplied as
-- 'ACME LTD' in one file and 'ACME LIMITED T/A ...' in another still meet — but
-- only where a postcode anchors them to the same registered office.
--
-- ACCEPTED only when exactly one company matches the core AND a supplier postcode
-- (candidate_count = 1; hard rule 2) and no payment predates its incorporation
-- (hard rule 3).
--
-- REACH IS NARROW, BY THE DATA. Only the Department for Transport and HMRC publish
-- supplier postcodes, and only valid-format postcodes are used (V2.11). Measured
-- 2026-09-17 before this build: 2,090 spend names carry one. Contracts Finder
-- carries no postcode, so tier 3 cannot enter the E-3 measurement.
--
-- Registered-office postcodes are used for matching only. They are never copied
-- into a published artefact (charter L-3).

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_match_tier3` AS
WITH ch AS (
  SELECT
    company_number, company_status, incorporation_date,
    `portfolio-508106.portfolio_b.name_core_from_norm`(company_name_norm) AS core,
    UPPER(REGEXP_REPLACE(postcode, r'\s', ''))                           AS pc
  FROM `portfolio-508106.portfolio_b.resolved_company_universe`
  WHERE postcode IS NOT NULL AND company_name_norm IS NOT NULL
),
sp AS (
  SELECT n.supplier_name_norm, n.supplier_name_core, n.first_payment_date, pc
  FROM `portfolio-508106.portfolio_b.resolved_names` n, UNNEST(n.spend_postcodes) AS pc
  WHERE n.in_spend AND n.supplier_name_core IS NOT NULL
),
cand AS (
  SELECT DISTINCT sp.supplier_name_norm, sp.first_payment_date,
         ch.company_number, ch.company_status, ch.incorporation_date
  FROM sp
  JOIN ch ON ch.core = sp.supplier_name_core AND ch.pc = sp.pc
)
SELECT
  supplier_name_norm,
  COUNT(DISTINCT company_number)                                             AS candidate_count,
  IF(COUNT(DISTINCT company_number) = 1, ANY_VALUE(company_number), NULL)    AS candidate_company_number,
  IF(COUNT(DISTINCT company_number) = 1, ANY_VALUE(company_status), NULL)    AS company_status,
  IF(COUNT(DISTINCT company_number) = 1, ANY_VALUE(incorporation_date), NULL) AS incorporation_date,
  CASE
    WHEN COUNT(DISTINCT company_number) > 1                               THEN 'ambiguous'
    WHEN ANY_VALUE(first_payment_date) < ANY_VALUE(incorporation_date)    THEN 'implausible_before_incorporation'
  END                                                                        AS reject_reason,
  (COUNT(DISTINCT company_number) = 1
   AND COALESCE(NOT (ANY_VALUE(first_payment_date) < ANY_VALUE(incorporation_date)), TRUE)) AS accepted
FROM cand
GROUP BY supplier_name_norm;
