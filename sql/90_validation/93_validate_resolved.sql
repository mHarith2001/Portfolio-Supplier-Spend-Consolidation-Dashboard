-- 93_validate_resolved.sql
-- Layer: validation. Runs AFTER L3, before any Layer 4 work begins.
--
-- EXECUTED 2026-09-17 — TIERS 1-3 ONLY. Layer 3 is open, not complete.
--
-- WHAT RUNS NOW: the checks that apply to the tier candidate tables built by
-- 31-33 — the name universe, hard rules 2 and 3, and V3.6, V3.8 and V3.11 at the
-- point of acceptance.
--
-- WHAT DOES NOT RUN YET, and why:
--   V3.1-V3.3   resolved_spend (36) is not built. V3.3 requires EVERY resolved_spend
--               row to carry a supplier_key, while Layer 3 aggregates transactions
--               only — a decision is open on how non-transaction rows are keyed.
--   V3.4-V3.5,  resolved_supplier_match is assembled after tier 4 (34), which is
--   V3.7, V3.9,  not built: its similarity method and threshold need measuring
--   V3.10       against E-3 first.
--   V3.12-V3.17 the golden record (35) is not built.

-- ===========================================================================
-- L3.0  The name universe is complete and unique                    HARD
-- ===========================================================================
-- Every non-redacted transaction name in staging_spend appears in resolved_names
-- exactly once, flagged in_spend; nothing else is flagged in_spend.

WITH src AS (
  SELECT DISTINCT supplier_name_norm
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction' AND NOT is_redacted AND supplier_name_norm IS NOT NULL
),
u AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_names`)
SELECT
  (SELECT COUNT(*) FROM src)                                          AS spend_names_in_staging,
  (SELECT COUNTIF(in_spend) FROM u)                                   AS in_spend_in_universe,
  (SELECT COUNT(*) - COUNT(DISTINCT supplier_name_norm) FROM u)       AS duplicate_names,
  (SELECT COUNT(*) FROM src LEFT JOIN u USING (supplier_name_norm)
    WHERE u.supplier_name_norm IS NULL OR NOT u.in_spend)             AS missing_from_universe,
  (SELECT COUNTIF(in_e3) FROM u)                                      AS e3_names,
  IF((SELECT COUNT(*) FROM src) = (SELECT COUNTIF(in_spend) FROM u)
     AND (SELECT COUNT(*) - COUNT(DISTINCT supplier_name_norm) FROM u) = 0,
     'PASS', 'FAIL  <-- HARD') AS l3_0;

-- ===========================================================================
-- Hard rule 2 / V3.6 — no acceptance where candidate_count > 1       HARD
-- Hard rule 3 / V3.8 — no acceptance before incorporation            HARD
-- V3.11 — every accepted number exists in staging_companies          HARD
-- ===========================================================================

WITH acc AS (
  SELECT 1 AS tier, a.supplier_name_norm, a.candidate_count, a.candidate_company_number, n.first_payment_date
  FROM `portfolio-508106.portfolio_b.resolved_match_tier1` a JOIN `portfolio-508106.portfolio_b.resolved_names` n USING (supplier_name_norm) WHERE a.accepted
  UNION ALL
  SELECT 2, a.supplier_name_norm, a.candidate_count, a.candidate_company_number, n.first_payment_date
  FROM `portfolio-508106.portfolio_b.resolved_match_tier2` a JOIN `portfolio-508106.portfolio_b.resolved_names` n USING (supplier_name_norm) WHERE a.accepted
  UNION ALL
  SELECT 3, a.supplier_name_norm, a.candidate_count, a.candidate_company_number, n.first_payment_date
  FROM `portfolio-508106.portfolio_b.resolved_match_tier3` a JOIN `portfolio-508106.portfolio_b.resolved_names` n USING (supplier_name_norm) WHERE a.accepted
)
SELECT
  acc.tier,
  COUNT(*)                                                         AS accepted,
  COUNTIF(acc.candidate_count > 1)                                 AS accepted_ambiguous,
  COUNTIF(c.company_number IS NULL)                                AS accepted_orphan_number,
  COUNTIF(acc.first_payment_date < c.incorporation_date)           AS accepted_implausible,
  IF(COUNTIF(acc.candidate_count > 1) = 0 AND COUNTIF(c.company_number IS NULL) = 0
     AND COUNTIF(acc.first_payment_date < c.incorporation_date) = 0,
     'PASS', 'FAIL  <-- HARD') AS v3_6_v3_8_v3_11
FROM acc
LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c ON c.company_number = acc.candidate_company_number
GROUP BY acc.tier
ORDER BY acc.tier;

-- ===========================================================================
-- Tiers 1-3, first match wins — INFO. The interim picture, not the result.
-- ===========================================================================
-- Spend names only. Tier 4 and the unresolved reasons are not yet assigned, so
-- 'not yet resolved' is a work queue, not a finding.

WITH n AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_names` WHERE in_spend),
t1 AS (SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier1` WHERE accepted),
t2 AS (SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier2` WHERE accepted),
t3 AS (SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier3` WHERE accepted)
SELECT
  CASE
    WHEN t1.supplier_name_norm IS NOT NULL THEN '1 company number (bridged)'
    WHEN t2.supplier_name_norm IS NOT NULL THEN '2 exact name'
    WHEN t3.supplier_name_norm IS NOT NULL THEN '3 name + postcode'
    ELSE                                        'not yet resolved'
  END                                   AS tier,
  COUNT(*)                              AS supplier_names,
  SUM(n.spend_rows)                     AS transaction_rows,
  ROUND(SUM(n.spend_value), 2)          AS transaction_value
FROM n
LEFT JOIN t1 USING (supplier_name_norm)
LEFT JOIN t2 USING (supplier_name_norm)
LEFT JOIN t3 USING (supplier_name_norm)
GROUP BY tier
ORDER BY tier;

-- ===========================================================================
-- Tier 1 register disagreement — INFO, and a review candidate
-- ===========================================================================
-- Accepted tier-1 names whose stated number is registered under a different
-- normalised name. 04 §3 treats the buyer's statement as deterministic; this is
-- the population where that assumption deserves a second look.

SELECT
  COUNTIF(accepted)                                  AS tier1_accepted,
  COUNTIF(accepted AND register_name_agrees)         AS register_name_agrees,
  COUNTIF(accepted AND NOT register_name_agrees)     AS register_name_differs,
  COUNTIF(reject_reason = 'ambiguous')               AS rejected_ambiguous,
  COUNTIF(reject_reason = 'number_not_in_register')  AS rejected_not_in_register,
  COUNTIF(reject_reason = 'implausible_before_incorporation') AS rejected_implausible
FROM `portfolio-508106.portfolio_b.resolved_match_tier1`;
