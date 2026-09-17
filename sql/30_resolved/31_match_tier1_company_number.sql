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
-- DEMOTED TO REVIEW, ruled 2026-09-18: register_name_agrees = FALSE, where the
-- company registered under the stated number carries a different normalised name
-- from the supplier. These do NOT flow as confirmed matches. Measured 2026-09-17:
-- 232 of 1,404 candidates disagree.
--
-- Why they are not simply accepted. 04 §3 calls tier 1 deterministic because the
-- buyer stated the number — but a buyer can state the number of a parent, a group
-- company or the wrong company entirely, and nothing in the spend file contradicts
-- it. A name that does not match the register is the only signal available that
-- this has happened, and a high-confidence match to a differently named company is
-- worse than no match: it is wrong and it looks certain.
--
-- The name is not discarded. It continues down the ladder, so a stronger tier can
-- still resolve it; if nothing does, it reaches the review queue carrying this
-- candidate. The count is published either way.
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
    WHEN NOT (c.company_name_norm = n.supplier_name_norm)     THEN 'register_name_disagrees'
  END                                                                     AS reject_reason,
  -- demoted to review, not accepted, and not discarded
  (cf.candidate_count = 1 AND c.company_number IS NOT NULL
   AND COALESCE(NOT (n.first_payment_date < c.incorporation_date), TRUE)
   AND NOT COALESCE(c.company_name_norm = n.supplier_name_norm, FALSE))   AS demoted_to_review,
  (cf.candidate_count = 1 AND c.company_number IS NOT NULL
   AND COALESCE(NOT (n.first_payment_date < c.incorporation_date), TRUE)
   AND COALESCE(c.company_name_norm = n.supplier_name_norm, FALSE))       AS accepted
FROM `portfolio-508106.portfolio_b.resolved_names` n
JOIN cf USING (supplier_name_norm)
LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
  ON c.company_number = IF(cf.candidate_count = 1, cf.any_number, NULL)
WHERE n.in_spend;
