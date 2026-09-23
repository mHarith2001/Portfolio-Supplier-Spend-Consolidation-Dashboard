-- 34c_other_buyer_award_evidence.sql
-- Layer: L3 resolved_ -- buyers' own statements of a tier-4 candidate, as review evidence
--
-- EXECUTED 2026-09-24. Run after 34, before 37. Adopted by the user 2026-09-24.
--
-- ===========================================================================
-- WHY ANOTHER BUYER'S AWARD IS EVIDENCE
-- ===========================================================================
-- A tier-4 candidate is a similarity score and nothing more; measured against
-- known answers it is right 81.24% of the time. A Contracts Finder award in which
-- a buyer -- ANY buyer, not only the payer -- names the supplier AND states the
-- candidate's company number is a statement made independently of that score.
-- Where it agrees with the fuzzy candidate, and no buyer states a different
-- number, the two independent signals corroborate each other.
--
-- ===========================================================================
-- THE SCOPING, AS RULED (04 §8.1, fourth evidence class)
-- ===========================================================================
--   * TIER-4 ROWS ONLY: a tier-4 candidate at or above 0.85 with
--     candidate_count = 1. Demoted tier-1 rows are excluded -- there a buyer's
--     stated number is the very assertion hard rule 6 demoted.
--   * "Naming the supplier" = the award's supplier name has the same
--     suffix-free core as the payer's spelling (the key tier 4 scores on).
--   * AN AWARD THAT STATES NO NUMBER SUPPLIES NOTHING -- the Cabinet Office
--     precedent: nine awards naming the supplier, not one with a number.
--   * If any award states a DIFFERENT number, the pair does not qualify and the
--     row is escalated. (A CONFLICT row never qualifies for that reason: its
--     tier-1 number comes from an award with the same name.)
--
-- HOW IT TAKES EFFECT. As an EVIDENCE CLASS, ACCEPT-OTHER-BUYER-AWARDS, inside the
-- tiered protocol -- not a rule that resolves by itself. Nothing here changes a
-- tier table or E-3. 93 D.11 fails on any decision citing the class for a pair
-- this table does not qualify.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_other_buyer_award_evidence` AS
WITH cand AS (
  SELECT supplier_name_norm, candidate_company_number AS company_number, candidate_count,
         `portfolio-508106.portfolio_b.name_core_from_norm`(supplier_name_norm) AS core
  FROM `portfolio-508106.portfolio_b.resolved_match_tier4`
  WHERE match_score >= 0.85
),
aw AS (
  SELECT `portfolio-508106.portfolio_b.name_core_from_norm`(supplier_name_norm) AS core,
         supplier_company_number, buyer_name, award_date
  FROM `portfolio-508106.portfolio_b.staging_contracts`
  WHERE supplier_company_number IS NOT NULL          -- no number, no evidence
)
SELECT
  c.supplier_name_norm,
  c.company_number,
  c.candidate_count,
  COUNTIF(a.supplier_company_number = c.company_number)                        AS awards_for,
  COUNTIF(a.supplier_company_number != c.company_number)                       AS awards_other,
  STRING_AGG(DISTINCT IF(a.supplier_company_number = c.company_number, a.buyer_name, NULL), '; ')
                                                                               AS buyers_for,
  STRING_AGG(DISTINCT IF(a.supplier_company_number != c.company_number, a.supplier_company_number, NULL), '; ')
                                                                               AS other_numbers,
  MIN(IF(a.supplier_company_number = c.company_number, a.award_date, NULL))    AS first_award,
  MAX(IF(a.supplier_company_number = c.company_number, a.award_date, NULL))    AS last_award,
  (COUNTIF(a.supplier_company_number = c.company_number) > 0
   AND COUNTIF(a.supplier_company_number != c.company_number) = 0
   AND c.candidate_count = 1)                                                  AS qualifies
FROM cand c
JOIN aw a USING (core)
GROUP BY c.supplier_name_norm, c.company_number, c.candidate_count;
