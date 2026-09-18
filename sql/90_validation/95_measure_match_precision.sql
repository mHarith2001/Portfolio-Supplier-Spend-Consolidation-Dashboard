-- 95_measure_match_precision.sql
-- Layer: validation. Runs AFTER L3, not once at the end.
--
-- EXECUTED 2026-09-18. Run from a file on standard input.
--
-- ===========================================================================
-- E-3 — THE LOAD-BEARING MEASUREMENT
-- ===========================================================================
-- 04 §4: take the Contracts Finder awards where the company number is known,
-- HIDE the number, run tiers 2-4 on the name alone, compare the prediction with
-- the known answer, and report precision and recall per tier —
-- "whether or not they flatter the method".
--
-- TIER 1 IS EXCLUDED BY CONSTRUCTION. It reads the buyer-stated number, which is
-- the answer being measured against; scoring it would measure nothing.
--
-- TIER 3 CANNOT ENTER. It needs a postcode on both sides and Contracts Finder
-- carries none. E-3 therefore measures tiers 2 and 4.
--
-- POPULATION: 24,507 known-answer awards, of which 24,506 are measurable — one
-- award carries a company number and an EMPTY supplier name, which normalises to
-- nothing and so cannot be matched by name.
--
-- THE MEASUREMENT IS NOT THE WHOLE PICTURE. Two ceilings sit above it and must be
-- published beside it:
--   * 496 of the 11,593 distinct known-answer companies are absent from the
--     Companies House snapshot, so no method could reach them (09 P-12);
--   * the population is central-government-weighted (09 P-1), because the three
--     local authorities publish almost no company numbers.

-- ---------------------------------------------------------------------------
-- 1. Precision and recall across thresholds — the evidence for the choice
-- ---------------------------------------------------------------------------
-- MEASURED 2026-09-18. Threshold 0.85 chosen: the curve is flat above it (30
-- names sit between 0.85 and 0.99), and below 0.70 tier-4 precision collapses —
-- 65.94% at 0.65, 56.07% at 0.50.

WITH t2 AS (
  SELECT supplier_name_norm, candidate_company_number
  FROM `portfolio-508106.portfolio_b.resolved_match_tier2` WHERE accepted
),
t4 AS (
  SELECT supplier_name_norm, candidate_company_number, match_score
  FROM `portfolio-508106.portfolio_b.resolved_match_tier4`
),
pop AS (
  SELECT supplier_name_norm, supplier_company_number
  FROM `portfolio-508106.portfolio_b.staging_contracts`
  WHERE supplier_company_number IS NOT NULL AND supplier_name_norm IS NOT NULL
),
th AS (SELECT t AS threshold FROM UNNEST([0.50,0.55,0.60,0.65,0.70,0.75,0.80,0.85,0.90,0.95,1.00]) AS t),
scored AS (
  SELECT th.threshold, p.supplier_company_number,
    CASE WHEN t2.candidate_company_number IS NOT NULL THEN 2
         WHEN t4.match_score >= th.threshold           THEN 4 END AS tier,
    COALESCE(t2.candidate_company_number,
             IF(t4.match_score >= th.threshold, t4.candidate_company_number, NULL)) AS pred
  FROM th CROSS JOIN pop p
  LEFT JOIN t2 USING (supplier_name_norm)
  LEFT JOIN t4 USING (supplier_name_norm)
)
SELECT
  threshold,
  COUNT(*)                                                         AS population_awards,
  COUNTIF(pred IS NOT NULL)                                        AS matches_made,
  COUNTIF(pred = supplier_company_number)                          AS correct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(pred = supplier_company_number), COUNTIF(pred IS NOT NULL)), 2) AS precision_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(pred IS NOT NULL), COUNT(*)), 2) AS recall_pct,
  COUNTIF(tier = 4)                                                AS tier4_matches,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(tier = 4 AND pred = supplier_company_number), COUNTIF(tier = 4)), 2) AS tier4_precision_pct
FROM scored GROUP BY threshold ORDER BY threshold;

-- ---------------------------------------------------------------------------
-- 2. E-3 at the chosen threshold, per tier — the published figures
-- ---------------------------------------------------------------------------

WITH t2 AS (
  SELECT supplier_name_norm, candidate_company_number
  FROM `portfolio-508106.portfolio_b.resolved_match_tier2` WHERE accepted
),
t4 AS (
  SELECT supplier_name_norm, candidate_company_number, match_score
  FROM `portfolio-508106.portfolio_b.resolved_match_tier4` WHERE match_score >= 0.85
),
pop AS (
  SELECT supplier_name_norm, supplier_company_number
  FROM `portfolio-508106.portfolio_b.staging_contracts`
  WHERE supplier_company_number IS NOT NULL AND supplier_name_norm IS NOT NULL
),
scored AS (
  SELECT p.supplier_company_number,
    CASE WHEN t2.candidate_company_number IS NOT NULL THEN '2 exact name'
         WHEN t4.candidate_company_number IS NOT NULL THEN '4 fuzzy (review only)'
         ELSE                                              '5 no match' END AS tier,
    COALESCE(t2.candidate_company_number, t4.candidate_company_number) AS pred
  FROM pop p
  LEFT JOIN t2 USING (supplier_name_norm)
  LEFT JOIN t4 USING (supplier_name_norm)
)
SELECT
  tier,
  COUNT(*)                                                AS awards,
  COUNTIF(pred IS NOT NULL)                               AS matches_made,
  COUNTIF(pred = supplier_company_number)                 AS correct,
  COUNTIF(pred IS NOT NULL AND pred != supplier_company_number) AS wrong,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(pred = supplier_company_number), COUNTIF(pred IS NOT NULL)), 2) AS precision_pct
FROM scored GROUP BY tier
UNION ALL
SELECT 'ALL TIERS', COUNT(*), COUNTIF(pred IS NOT NULL), COUNTIF(pred = supplier_company_number),
  COUNTIF(pred IS NOT NULL AND pred != supplier_company_number),
  ROUND(100 * SAFE_DIVIDE(COUNTIF(pred = supplier_company_number), COUNTIF(pred IS NOT NULL)), 2)
FROM scored
ORDER BY tier;

-- ---------------------------------------------------------------------------
-- 3. The recall limit blocking imposes — stated, not hidden
-- ---------------------------------------------------------------------------
-- REWRITTEN 2026-09-18 for the prefix filter. The previous version measured
-- FIRST-TOKEN reachability, which stopped describing the method the day blocking
-- was corrected. A control that measures a method no longer in use reports a
-- number that is true of nothing.
--
-- Under the prefix filter a name is unreachable only if NONE of its prefix tokens
-- appears in ANY company's prefix. That is a far smaller population than before,
-- and it is the honest statement of what blocking now costs.

WITH resolved_23 AS (
  SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier2` WHERE accepted
  UNION DISTINCT SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier3` WHERE accepted
),
ch AS (
  SELECT company_number,
         ARRAY(SELECT DISTINCT t FROM UNNEST(SPLIT(
           `portfolio-508106.portfolio_b.name_core_from_norm`(company_name_norm), ' ')) t WHERE t != '') AS tokens
  FROM `portfolio-508106.portfolio_b.staging_companies`
),
df AS (SELECT tok, COUNT(*) AS n FROM ch, UNNEST(tokens) AS tok GROUP BY tok),
c_prefix AS (
  SELECT DISTINCT tok FROM (
    SELECT c.company_number, tok, ARRAY_LENGTH(c.tokens) AS b,
           ROW_NUMBER() OVER (PARTITION BY c.company_number ORDER BY COALESCE(df.n, 0), tok) AS rk
    FROM ch c, UNNEST(c.tokens) AS tok LEFT JOIN df USING (tok)
  ) WHERE rk <= b - CAST(CEIL(0.5 * b) AS INT64) + 1
),
todo AS (
  SELECT n.supplier_name_norm, n.in_spend, n.in_e3, n.spend_value,
         ARRAY(SELECT DISTINCT t FROM UNNEST(SPLIT(n.supplier_name_core, ' ')) t WHERE t != '') AS tokens
  FROM `portfolio-508106.portfolio_b.resolved_names` n
  LEFT JOIN resolved_23 r USING (supplier_name_norm)
  WHERE r.supplier_name_norm IS NULL AND n.supplier_name_core IS NOT NULL
),
n_prefix AS (
  SELECT supplier_name_norm, in_spend, in_e3, spend_value, tok FROM (
    SELECT t.supplier_name_norm, t.in_spend, t.in_e3, t.spend_value, tok,
           ARRAY_LENGTH(t.tokens) AS a,
           ROW_NUMBER() OVER (PARTITION BY t.supplier_name_norm ORDER BY COALESCE(df.n, 0), tok) AS rk
    FROM todo t, UNNEST(t.tokens) AS tok LEFT JOIN df USING (tok)
  ) WHERE rk <= a - CAST(CEIL(0.5 * a) AS INT64) + 1
),
reach AS (
  SELECT n.supplier_name_norm, ANY_VALUE(n.in_spend) AS in_spend, ANY_VALUE(n.in_e3) AS in_e3,
         ANY_VALUE(n.spend_value) AS spend_value,
         COUNTIF(c.tok IS NOT NULL) AS matched_prefix_tokens
  FROM n_prefix n LEFT JOIN c_prefix c USING (tok)
  GROUP BY n.supplier_name_norm
)
SELECT
  COUNT(*)                                                    AS names_in_tier4_population,
  COUNTIF(matched_prefix_tokens = 0)                          AS unreachable_names,
  COUNTIF(matched_prefix_tokens = 0 AND in_spend)             AS unreachable_spend_names,
  COUNTIF(matched_prefix_tokens = 0 AND in_e3)                AS unreachable_e3_names,
  ROUND(SUM(IF(matched_prefix_tokens = 0, spend_value, 0)), 2) AS unreachable_spend_value
FROM reach;
