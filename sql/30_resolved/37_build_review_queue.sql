-- 37_build_review_queue.sql
-- Layer: L3 resolved_ -- the published review-queue artefact
--
-- EXECUTED 2026-09-18. Produces docs/review_queue.csv (04 section 8).
--
-- Two populations, one queue: tier-4 candidates, and the tier-1 names demoted
-- because the register name disagrees with the buyer (04 section 3 hard rule 6)
-- that no other tier later confirmed. queue_reason tells them apart, because a
-- demoted row carries no match_score and a reviewer must not read an absent
-- score as a low one.
--
-- Sorted by total_spend DESCENDING: 04 section 8 makes value the sort key so the
-- most expensive ambiguity is decided first. Measured 2026-09-18: the top 10
-- names hold 88.2 percent of queued value.
--
-- decision is exported BLANK. Publishing the queue empty of decisions is the
-- honest presentation -- it shows the work a production implementation would
-- require without pretending it was done.

WITH spend AS (
  SELECT supplier_name_norm, ROUND(SUM(amount), 2) AS total_spend
  FROM `portfolio-508106.portfolio_b.resolved_spend`
  WHERE row_role = 'transaction'
  GROUP BY supplier_name_norm
),
raw_name AS (
  SELECT supplier_key, display_name FROM `portfolio-508106.portfolio_b.resolved_supplier_golden`
),
m AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_supplier_match`),
t1 AS (
  SELECT supplier_name_norm, candidate_company_number, candidate_count
  FROM `portfolio-508106.portfolio_b.resolved_match_tier1`
  WHERE reject_reason = 'register_name_disagrees'
),
q AS (
  SELECT
    m.supplier_name_norm,
    m.review_candidate_name        AS candidate_company_name,
    m.matched_company_number       AS candidate_company_number,
    m.match_score,
    m.candidate_count,
    'tier 4 fuzzy'                 AS queue_reason
  FROM m WHERE m.match_tier = 4

  UNION ALL

  SELECT
    t1.supplier_name_norm,
    c.company_name,
    t1.candidate_company_number,
    CAST(NULL AS FLOAT64),
    t1.candidate_count,
    'tier 1 demoted: register name disagrees'
  FROM t1
  JOIN m USING (supplier_name_norm)
  LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
    ON c.company_number = t1.candidate_company_number
  WHERE m.match_tier >= 4
)
SELECT
  r.display_name          AS supplier_name_raw,
  q.supplier_name_norm,
  q.candidate_company_number,
  q.candidate_company_name,
  q.match_score,
  q.candidate_count,
  s.total_spend,
  ''                      AS decision,
  q.queue_reason
FROM q
JOIN spend s USING (supplier_name_norm)
LEFT JOIN raw_name r
  ON r.supplier_key = TO_HEX(SHA256(CONCAT('NAME|', q.supplier_name_norm)))
ORDER BY s.total_spend DESC;
