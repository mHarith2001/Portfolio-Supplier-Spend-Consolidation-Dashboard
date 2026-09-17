-- 32_match_tier2_exact_name.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
--
-- EXECUTED 2026-09-17. Run from a file on standard input. Needs 31 first.
--
-- 04 §3 tier 2: supplier_name_norm = Companies House company_name_norm.
-- "Auto-accept only if exactly one active company matches."
--
-- ACCEPTED only when all hold:
--   * exactly ONE company carries the name (candidate_count = 1; V3.6, hard rule 2);
--   * that company is active;
--   * no payment predates its incorporation (hard rule 3). Plausibility can only be
--     tested where the name has spend payments; a Contracts Finder-only name is
--     not tested and is not rejected for it.
--
-- "ACTIVE" IS AN INTERPRETATION, stated. The snapshot holds no dissolved companies:
-- every status is a live one. A company is treated as active when its status begins
-- 'Active' — 'Active' and 'Active - Proposal to Strike off', which is still legally
-- active. Measured 2026-09-17 before this build: of 6,029 single-candidate spend
-- names, 5,902 are exactly 'Active' and 5,945 begin 'Active'; the other 84 are in
-- liquidation, administration or receivership and are not auto-accepted.
--
-- Runs over BOTH populations in resolved_names — spend names and E-3 known-answer
-- names — so the precision measurement scores this exact logic.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_match_tier2` AS
WITH ch AS (
  SELECT
    company_name_norm                              AS supplier_name_norm,
    COUNT(*)                                       AS candidate_count,
    COUNTIF(STARTS_WITH(company_status, 'Active')) AS active_count,
    ANY_VALUE(company_number)                      AS any_number,
    ANY_VALUE(company_status)                      AS any_status,
    ANY_VALUE(incorporation_date)                  AS any_incorporation
  FROM `portfolio-508106.portfolio_b.staging_companies`
  WHERE company_name_norm IS NOT NULL
  GROUP BY company_name_norm
)
SELECT
  n.supplier_name_norm,
  n.in_spend,
  n.in_e3,
  ch.candidate_count,
  ch.active_count,
  IF(ch.candidate_count = 1, ch.any_number, NULL)        AS candidate_company_number,
  IF(ch.candidate_count = 1, ch.any_status, NULL)        AS company_status,
  IF(ch.candidate_count = 1, ch.any_incorporation, NULL) AS incorporation_date,
  CASE
    WHEN ch.candidate_count > 1                                    THEN 'ambiguous'
    WHEN NOT STARTS_WITH(ch.any_status, 'Active')                  THEN 'single_candidate_not_active'
    WHEN n.first_payment_date < ch.any_incorporation               THEN 'implausible_before_incorporation'
  END                                                    AS reject_reason,
  (ch.candidate_count = 1
   AND STARTS_WITH(ch.any_status, 'Active')
   AND COALESCE(NOT (n.first_payment_date < ch.any_incorporation), TRUE)) AS accepted
FROM `portfolio-508106.portfolio_b.resolved_names` n
JOIN ch USING (supplier_name_norm);
