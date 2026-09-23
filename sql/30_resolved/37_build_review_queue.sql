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

-- From 2026-09-22 this builds a TABLE, so the tiered protocol can be queried and
-- controlled; scripts/07_export_outputs.ps1 writes the CSV from it, ordered.
--
-- review_tier follows the protocol ruled 2026-09-22, on the name's total
-- transaction spend: A >= GBP 10m, B >= GBP 100k, C below.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_review_queue` AS
WITH spend AS (
  SELECT supplier_name_norm, ROUND(SUM(amount), 2) AS total_spend
  FROM `portfolio-508106.portfolio_b.resolved_spend`
  WHERE row_role = 'transaction'
  GROUP BY supplier_name_norm
),
-- The label comes from the SPEND FILES, per normalised name -- not from the
-- golden record. An accepted name merges into its company's CH| key and no
-- longer has a NAME| row there, so a golden-record lookup blanks the label of
-- exactly the rows a reviewer has just decided. (Found 2026-09-18 on row 2.)
raw_name AS (
  SELECT supplier_name_norm, supplier_name_raw AS display_name
  FROM (
    SELECT supplier_name_norm, supplier_name_raw,
           ROW_NUMBER() OVER (PARTITION BY supplier_name_norm
                              ORDER BY COUNT(*) DESC, MAX(payment_date) DESC, supplier_name_raw) AS rn
    FROM `portfolio-508106.portfolio_b.resolved_spend`
    WHERE row_role = 'transaction'
    GROUP BY supplier_name_norm, supplier_name_raw
  )
  WHERE rn = 1
),
m AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_supplier_match`),
t1 AS (
  SELECT supplier_name_norm, candidate_company_number, candidate_count
  FROM `portfolio-508106.portfolio_b.resolved_match_tier1`
  WHERE reject_reason = 'register_name_disagrees'
),
t4b AS (
  SELECT
    m.supplier_name_norm,
    m.review_candidate_name        AS candidate_company_name,
    m.matched_company_number       AS candidate_company_number,
    m.match_score,
    m.candidate_count
  FROM m WHERE m.match_tier = 4
),
t1b AS (
  SELECT
    t1.supplier_name_norm,
    c.company_name                 AS candidate_company_name,
    t1.candidate_company_number,
    t1.candidate_count
  FROM t1
  JOIN m USING (supplier_name_norm)
  LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
    ON c.company_number = t1.candidate_company_number
  -- A DECIDED ROW NEVER LEAVES THE QUEUE. An accepted demoted row resolves at
  -- tier 1, so a bare `match_tier >= 4` test would drop it -- and take its
  -- recorded decision out of the published log with it. The queue is the decision
  -- LOG, not only the to-do list: a name stays if it is still open OR if a
  -- decision has been recorded against it. (Found 2026-09-20 on row 3.)
  WHERE m.match_tier >= 4
     OR EXISTS (SELECT 1 FROM `portfolio-508106.portfolio_b.resolved_queue_all_decisions` dd
                 WHERE dd.supplier_name_norm = t1.supplier_name_norm)
),
-- ONE ROW PER NAME. Until 2026-09-22 the two branches were UNIONed, so a name
-- that was BOTH demoted at tier 1 AND had a tier-4 candidate appeared twice: 69
-- names, double-counted in every published queue count and value, including the
-- tier sizes the review protocol was ruled on. The branches are now JOINED, and
-- when both fire they say something the separate rows hid:
--   * same company from both routes -> the fuzzy score and the buyer's statement
--     independently agree, which is evidence, and is labelled as such;
--   * different companies           -> a genuine conflict, labelled CONFLICT, with
--     the buyer's company kept in alternative_company_number rather than dropped.
q_open AS (
  SELECT
    COALESCE(a.supplier_name_norm, b.supplier_name_norm)             AS supplier_name_norm,
    COALESCE(a.candidate_company_name, b.candidate_company_name)     AS candidate_company_name,
    COALESCE(a.candidate_company_number, b.candidate_company_number) AS candidate_company_number,
    a.match_score,
    COALESCE(a.candidate_count, b.candidate_count)                   AS candidate_count,
    CASE
      WHEN a.supplier_name_norm IS NOT NULL AND b.supplier_name_norm IS NOT NULL
           AND a.candidate_company_number = b.candidate_company_number
        THEN 'tier 4 fuzzy and tier 1 buyer statement AGREE'
      WHEN a.supplier_name_norm IS NOT NULL AND b.supplier_name_norm IS NOT NULL
        THEN 'CONFLICT: tier 4 and tier 1 name different companies'
      WHEN a.supplier_name_norm IS NOT NULL
        THEN 'tier 4 fuzzy'
      ELSE 'tier 1 demoted: register name disagrees'
    END                                                              AS queue_reason,
    IF(a.candidate_company_number != b.candidate_company_number,
       b.candidate_company_number, NULL)                             AS alternative_company_number
  FROM t4b a
  FULL OUTER JOIN t1b b USING (supplier_name_norm)
),
-- EVERY DECISION APPEARS, WHATEVER HAPPENED TO ITS CANDIDATE AFTERWARDS.
-- The two branches above list names that are OPEN. A decided name usually also
-- sits in one of them, but not always: NEXUS was rejected, and the later OE class
-- exclusion removed its tier-4 candidate, so it fell to tier 5 and vanished from
-- the queue -- deleting the published record of its rejection. (Found 2026-09-20,
-- the second time this shape of bug appeared; the first was patched on the
-- demoted branch alone, which is why it came back.)
--
-- This branch is the general fix: it re-adds any decided name the branches above
-- missed, carrying the company from the DECISION rather than from a candidate
-- table that no longer offers one.
q_decided AS (
  SELECT
    d.supplier_name_norm,
    c.company_name                 AS candidate_company_name,
    d.candidate_company_number,
    CAST(NULL AS FLOAT64)          AS match_score,
    1                              AS candidate_count,
    'decided; candidate withdrawn from matching' AS queue_reason,
    CAST(NULL AS STRING)           AS alternative_company_number
  FROM `portfolio-508106.portfolio_b.resolved_queue_all_decisions` d
  LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
    ON c.company_number = d.candidate_company_number
  WHERE d.supplier_name_norm NOT IN (SELECT supplier_name_norm FROM q_open)
),
q AS (
  SELECT * FROM q_open
  UNION ALL
  SELECT * FROM q_decided
)
SELECT
  r.display_name          AS supplier_name_raw,
  q.supplier_name_norm,
  q.candidate_company_number,
  q.candidate_company_name,
  q.match_score,
  q.candidate_count,
  s.total_spend,
  COALESCE(d.decision, '')      AS decision,
  COALESCE(d.decision_note, '') AS decision_note,
  CAST(d.decided_on AS STRING)  AS decided_on,
  q.queue_reason,
  q.alternative_company_number,
  CASE WHEN s.total_spend >= 10000000 THEN 'A'
       WHEN s.total_spend >= 100000   THEN 'B'
       ELSE 'C' END                 AS review_tier,
  COALESCE(d.decided_by, '')      AS decided_by,
  COALESCE(d.evidence_class, '')  AS evidence_class,
  -- ACCEPT-PREVIOUS-NAME evidence (34b), shown so a reviewer can see it: the
  -- candidate's registered previous name the payer used, and its validity window.
  IF(pe.prev_name IS NULL, '',
     CONCAT(pe.prev_name, ' valid ', CAST(pe.valid_from AS STRING), ' to ',
            CAST(pe.valid_to AS STRING), '; paid ', CAST(pe.first_payment AS STRING),
            ' to ', CAST(pe.last_payment AS STRING)))                 AS previous_name_evidence,
  IF(pa.prev_name IS NULL, '',
     CONCAT(pa.prev_name, ' valid ', CAST(pa.valid_from AS STRING), ' to ',
            CAST(pa.valid_to AS STRING)))                            AS alternative_previous_name_evidence
FROM q
JOIN spend s USING (supplier_name_norm)
LEFT JOIN raw_name r
  ON r.supplier_name_norm = q.supplier_name_norm
LEFT JOIN `portfolio-508106.portfolio_b.resolved_queue_all_decisions` d
  ON d.supplier_name_norm = q.supplier_name_norm
LEFT JOIN `portfolio-508106.portfolio_b.resolved_prev_name_evidence` pe
  ON pe.supplier_name_norm = q.supplier_name_norm
 AND pe.company_number     = q.candidate_company_number
LEFT JOIN `portfolio-508106.portfolio_b.resolved_prev_name_evidence` pa
  ON pa.supplier_name_norm = q.supplier_name_norm
 AND pa.company_number     = q.alternative_company_number;
