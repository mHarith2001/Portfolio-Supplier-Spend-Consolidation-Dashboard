-- 31_match_tier1_company_number.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
--
-- EXECUTED 2026-09-17. Run from a file on standard input.
-- Reads: staging_spend, staging_contracts, staging_companies (Layer 2).
--
-- ===========================================================================
-- LAYER 3 AGGREGATES TRANSACTIONS ONLY
-- ===========================================================================
-- Every name that enters matching comes from row_role = 'transaction'
-- (03 §3, 08 §11.6). File totals, workbook sections and trailing artefacts
-- never become suppliers. Redacted rows never enter matching (04 §3 hard rule 4);
-- they are assigned tier 5, reason 'redacted', when matches are assembled.
--
-- ===========================================================================
-- 1. resolved_names — the name universe every tier reads
-- ===========================================================================
-- One row per supplier_name_norm, from two populations:
--   in_spend  a non-redacted TRANSACTION name in staging_spend — what is resolved
--   in_e3     a Contracts Finder name carrying a known company number — the E-3
--             known answer (04 §4), scored by hiding the number and running
--             tiers 2-4 on the name alone
-- Tiers 2 and 4 read this one table for both, so the spend resolution and the
-- precision measurement run IDENTICAL logic. Measuring a copy of the method is
-- not measuring the method.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_names` AS
WITH spend AS (
  SELECT
    supplier_name_norm,
    COUNT(*)                                        AS spend_rows,
    SUM(amount)                                     AS spend_value,
    MIN(payment_date)                               AS first_payment_date,
    ARRAY_AGG(DISTINCT IF(
      REGEXP_CONTAINS(UPPER(REGEXP_REPLACE(supplier_postcode, r'\s', '')),
                      r'^[A-Z]{1,2}[0-9][A-Z0-9]?[0-9][A-Z]{2}$'),
      UPPER(REGEXP_REPLACE(supplier_postcode, r'\s', '')), NULL) IGNORE NULLS) AS spend_postcodes
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction'
    AND NOT is_redacted
    AND supplier_name_norm IS NOT NULL
  GROUP BY supplier_name_norm
),
e3 AS (
  SELECT DISTINCT supplier_name_norm
  FROM `portfolio-508106.portfolio_b.staging_contracts`
  WHERE supplier_company_number IS NOT NULL AND supplier_name_norm IS NOT NULL
)
SELECT
  COALESCE(s.supplier_name_norm, e.supplier_name_norm)                                  AS supplier_name_norm,
  `portfolio-508106.portfolio_b.name_core_from_norm`(COALESCE(s.supplier_name_norm, e.supplier_name_norm)) AS supplier_name_core,
  s.supplier_name_norm IS NOT NULL                                                      AS in_spend,
  e.supplier_name_norm IS NOT NULL                                                      AS in_e3,
  s.spend_rows, s.spend_value, s.first_payment_date,
  COALESCE(s.spend_postcodes, [])                                                       AS spend_postcodes
FROM spend s
FULL OUTER JOIN e3 e USING (supplier_name_norm);

-- ===========================================================================
-- 2. resolved_match_tier1 — company number stated by a buyer (04 §3 tier 1)
-- ===========================================================================
-- THE KEY IS BRIDGED, AND THAT IS AN INTERPRETATION. Spend rows carry no company
-- number (vat_number is NULL for every publisher). A spend supplier reaches a
-- buyer-stated number only where its normalised name equals a Contracts Finder
-- supplier name carrying one. That is the reading of 04 §3 this implements.
--
-- ACCEPTED only when all hold:
--   * the Contracts Finder name carries exactly ONE distinct number
--     (candidate_count > 1 blocks acceptance at every tier — hard rule 2);
--   * that number exists in staging_companies (V3.11 — no orphan references);
--   * no payment predates incorporation (hard rule 3).
--
-- FLAGGED, NOT BLOCKED: register_name_agrees = FALSE where the company registered
-- under the stated number has a different normalised name from the supplier.
-- 04 §3 makes tier 1 'high' because the buyer stated it, and that is implemented;
-- the disagreement is recorded so it can be seen and reviewed. Measured
-- 2026-09-17 before this build: 232 of 1,404 candidates disagree.
--
-- Not applicable to E-3: for Contracts Finder names the stated number IS the
-- answer being measured against.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_match_tier1` AS
WITH cf AS (
  SELECT supplier_name_norm,
         COUNT(DISTINCT supplier_company_number) AS candidate_count,
         ANY_VALUE(supplier_company_number)      AS any_number
  FROM `portfolio-508106.portfolio_b.staging_contracts`
  WHERE supplier_company_number IS NOT NULL AND supplier_name_norm IS NOT NULL
  GROUP BY supplier_name_norm
)
SELECT
  n.supplier_name_norm,
  cf.candidate_count,
  IF(cf.candidate_count = 1, cf.any_number, NULL)                         AS candidate_company_number,
  c.company_number IS NOT NULL                                            AS in_register,
  c.company_name_norm                                                     AS register_name_norm,
  c.company_status,
  c.incorporation_date,
  (c.company_name_norm = n.supplier_name_norm)                            AS register_name_agrees,
  NOT (n.first_payment_date < c.incorporation_date)                       AS plausible,
  CASE
    WHEN cf.candidate_count > 1                               THEN 'ambiguous'
    WHEN c.company_number IS NULL                             THEN 'number_not_in_register'
    WHEN n.first_payment_date < c.incorporation_date          THEN 'implausible_before_incorporation'
  END                                                                     AS reject_reason,
  (cf.candidate_count = 1 AND c.company_number IS NOT NULL
   AND COALESCE(NOT (n.first_payment_date < c.incorporation_date), TRUE)) AS accepted
FROM `portfolio-508106.portfolio_b.resolved_names` n
JOIN cf USING (supplier_name_norm)
LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
  ON c.company_number = IF(cf.candidate_count = 1, cf.any_number, NULL)
WHERE n.in_spend;
