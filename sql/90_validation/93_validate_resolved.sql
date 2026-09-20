-- 93_validate_resolved.sql
-- Layer: validation. Runs AFTER L3, before any Layer 4 work begins.
--
-- EXECUTED 2026-09-18 — COMPLETE. V3.1-V3.17, plus the universe control (L3.0)
-- and the acceptance-point controls on tiers 1-3.
--
-- Run from a file on standard input:
--   cmd /c "bq query --use_legacy_sql=false --format=pretty < sql\90_validation\93_validate_resolved.sql"
--
-- Every HARD control prints its own PASS / 'FAIL  <-- HARD' verdict beside the
-- numbers it was computed from, so a failure cannot be read past.
--
-- WHERE THE CHECKS RECOMPUTE RATHER THAN RE-READ: V3.15 counts raw spellings from
-- resolved_spend, not from the staging_spend + match join that built the column.
-- A control that reads the same expression twice proves only that the expression
-- is repeatable.

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
-- V3.1  row count preserved                                         HARD
-- V3.2  SUM(amount) preserved to the penny                          HARD
-- V3.3  every TRANSACTION row carries exactly one supplier_key      HARD
-- ===========================================================================
-- E-5. Resolution changes attribution, never totals. V3.3 is scoped to
-- transaction rows (05 V3.3-note, 2026-09-18): non-transaction rows carry NULL
-- BY DESIGN, and the second count below proves they carry nothing else.
--
-- The excluded value printed here is the H-5 amount. It is reported every run so
-- that a change in the row_role classification cannot pass unnoticed.

SELECT
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.staging_spend`)   AS staging_rows,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_spend`)  AS resolved_rows,
  (SELECT ROUND(SUM(amount), 2) FROM `portfolio-508106.portfolio_b.staging_spend`)  AS staging_amount,
  (SELECT ROUND(SUM(amount), 2) FROM `portfolio-508106.portfolio_b.resolved_spend`) AS resolved_amount,
  (SELECT ROUND(SUM(IF(row_role = 'transaction', amount, 0)), 2)
     FROM `portfolio-508106.portfolio_b.resolved_spend`)                AS transaction_amount,
  (SELECT ROUND(SUM(IF(row_role != 'transaction', amount, 0)), 2)
     FROM `portfolio-508106.portfolio_b.resolved_spend`)                AS excluded_amount_h5,
  (SELECT COUNTIF(row_role = 'transaction' AND supplier_key IS NULL)
     FROM `portfolio-508106.portfolio_b.resolved_spend`)                AS txn_rows_without_key,
  (SELECT COUNTIF(row_role != 'transaction' AND supplier_key IS NOT NULL)
     FROM `portfolio-508106.portfolio_b.resolved_spend`)                AS non_txn_rows_with_key,
  IF((SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.staging_spend`)
     = (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_spend`), 'PASS', 'FAIL  <-- HARD') AS v3_1,
  IF((SELECT ROUND(SUM(amount), 2) FROM `portfolio-508106.portfolio_b.staging_spend`)
     = (SELECT ROUND(SUM(amount), 2) FROM `portfolio-508106.portfolio_b.resolved_spend`), 'PASS', 'FAIL  <-- HARD') AS v3_2,
  IF((SELECT COUNTIF(row_role = 'transaction' AND supplier_key IS NULL)
        FROM `portfolio-508106.portfolio_b.resolved_spend`) = 0
     AND (SELECT COUNTIF(row_role != 'transaction' AND supplier_key IS NOT NULL)
        FROM `portfolio-508106.portfolio_b.resolved_spend`) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_3;

-- ===========================================================================
-- V3.4  one row per normalised name                                 HARD
-- V3.5  match_tier in 1-5 and match_method agrees with the tier      HARD
-- V3.7  no tier-4 match carries high confidence                     HARD
-- V3.10 every tier-5 row states a reason                            HARD
-- ===========================================================================
-- V3.4 is checked against the SOURCE population, not against itself: the match
-- table must cover every distinct transaction name once, no more and no fewer.

WITH names AS (
  SELECT DISTINCT supplier_name_norm
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction' AND supplier_name_norm IS NOT NULL
),
m AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_supplier_match`)
SELECT
  (SELECT COUNT(*) FROM names)                                        AS transaction_names,
  (SELECT COUNT(*) FROM m)                                            AS match_rows,
  (SELECT COUNT(DISTINCT supplier_name_norm) FROM m)                  AS match_distinct_names,
  (SELECT COUNT(*) FROM names LEFT JOIN m USING (supplier_name_norm)
     WHERE m.supplier_name_norm IS NULL)                              AS names_missing_from_match,
  (SELECT COUNTIF(match_tier NOT IN (1,2,3,4,5)) FROM m)              AS bad_tier,
  (SELECT COUNTIF(NOT ((match_tier = 1 AND match_method = 'company_number')
                    OR (match_tier = 2 AND match_method = 'exact_name')
                    OR (match_tier = 3 AND match_method = 'name_postcode')
                    OR (match_tier = 4 AND match_method = 'fuzzy')
                    OR (match_tier = 5 AND match_method = 'unresolved'))) FROM m) AS method_tier_mismatch,
  (SELECT COUNTIF(match_tier = 4 AND match_confidence = 'high') FROM m) AS tier4_high_confidence,
  (SELECT COUNTIF(match_tier = 5 AND unresolved_reason IS NULL) FROM m) AS tier5_without_reason,
  IF((SELECT COUNT(*) FROM m) = (SELECT COUNT(*) FROM names)
     AND (SELECT COUNT(*) FROM m) = (SELECT COUNT(DISTINCT supplier_name_norm) FROM m)
     AND (SELECT COUNT(*) FROM names LEFT JOIN m USING (supplier_name_norm)
            WHERE m.supplier_name_norm IS NULL) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_4,
  IF((SELECT COUNTIF(match_tier NOT IN (1,2,3,4,5)) FROM m) = 0
     AND (SELECT COUNTIF(NOT ((match_tier = 1 AND match_method = 'company_number')
                    OR (match_tier = 2 AND match_method = 'exact_name')
                    OR (match_tier = 3 AND match_method = 'name_postcode')
                    OR (match_tier = 4 AND match_method = 'fuzzy')
                    OR (match_tier = 5 AND match_method = 'unresolved'))) FROM m) = 0,
     'PASS', 'FAIL  <-- HARD') AS v3_5,
  IF((SELECT COUNTIF(match_tier = 4 AND match_confidence = 'high') FROM m) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_7,
  IF((SELECT COUNTIF(match_tier = 5 AND unresolved_reason IS NULL) FROM m) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_10;

-- ===========================================================================
-- V3.9  every redacted row is tier 5, reason 'redacted'              HARD
-- ===========================================================================
-- Checked from the SPEND side: every redacted transaction row, followed through
-- its name to its match row. 04 §3 hard rule 4 keeps these names out of matching
-- entirely — this control proves none slipped in.

WITH r AS (
  SELECT s.spend_id, s.supplier_name_norm, m.match_tier, m.unresolved_reason
  FROM `portfolio-508106.portfolio_b.resolved_spend` s
  LEFT JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
  WHERE s.row_role = 'transaction' AND s.is_redacted
)
SELECT
  COUNT(*)                                                      AS redacted_transaction_rows,
  COUNT(DISTINCT supplier_name_norm)                            AS redacted_names,
  COUNTIF(match_tier != 5)                                      AS not_tier5,
  COUNTIF(unresolved_reason != 'redacted' OR unresolved_reason IS NULL) AS wrong_reason,
  IF(COUNTIF(match_tier != 5) = 0
     AND COUNTIF(unresolved_reason != 'redacted' OR unresolved_reason IS NULL) = 0,
     'PASS', 'FAIL  <-- HARD') AS v3_9
FROM r;

-- ===========================================================================
-- V3.8  end to end — no attributed payment precedes incorporation   HARD
-- V3.11 end to end — no attributed key is an orphan                 HARD
-- ===========================================================================
-- The acceptance-point controls above test the tier tables. This one tests what
-- actually reached the spend rows, which is the claim that matters.

WITH a AS (
  SELECT s.payment_date, g.company_number, g.incorporation_date, g.is_resolved
  FROM `portfolio-508106.portfolio_b.resolved_spend` s
  JOIN `portfolio-508106.portfolio_b.resolved_supplier_golden` g USING (supplier_key)
  WHERE s.row_role = 'transaction' AND g.is_resolved
)
SELECT
  COUNT(*)                                                                    AS attributed_rows,
  COUNTIF(payment_date < incorporation_date)                                  AS rows_before_incorporation,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_supplier_golden` g
    WHERE g.is_resolved AND NOT EXISTS (
      SELECT 1 FROM `portfolio-508106.portfolio_b.staging_companies` c
      WHERE c.company_number = g.company_number))                             AS orphan_company_numbers,
  IF(COUNTIF(payment_date < incorporation_date) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_8_end_to_end,
  IF((SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_supplier_golden` g
    WHERE g.is_resolved AND NOT EXISTS (
      SELECT 1 FROM `portfolio-508106.portfolio_b.staging_companies` c
      WHERE c.company_number = g.company_number)) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_11_end_to_end
FROM a;

-- ===========================================================================
-- V3.13 supplier_key unique                                         HARD
-- V3.14 company_number unique among resolved records                HARD
-- V3.15 name_variant_count >= 1 and equals the raw names collapsing in  HARD
-- V3.16 resolved legal_name comes from Companies House              HARD
-- V3.17 unresolved records carry no company_number                  HARD
-- ===========================================================================
-- V3.15 RECOMPUTES the variant count from resolved_spend — a different path from
-- the one that built it — and compares row by row.

WITH g AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_supplier_golden`),
recount AS (
  SELECT supplier_key, COUNT(DISTINCT supplier_name_raw) AS raw_variants
  FROM `portfolio-508106.portfolio_b.resolved_spend`
  WHERE row_role = 'transaction' AND supplier_key IS NOT NULL
  GROUP BY supplier_key
)
SELECT
  (SELECT COUNT(*) FROM g)                                              AS golden_rows,
  (SELECT COUNT(*) - COUNT(DISTINCT supplier_key) FROM g)               AS duplicate_keys,
  (SELECT COUNTIF(is_resolved) - COUNT(DISTINCT IF(is_resolved, company_number, NULL)) FROM g) AS duplicate_company_numbers,
  (SELECT COUNTIF(name_variant_count IS NULL OR name_variant_count < 1) FROM g) AS bad_variant_count,
  (SELECT COUNT(*) FROM g JOIN recount USING (supplier_key)
    WHERE g.name_variant_count != recount.raw_variants)                 AS variant_count_disagrees,
  (SELECT COUNT(*) FROM g LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
     ON c.company_number = g.company_number
    WHERE g.is_resolved AND (c.company_name IS NULL OR c.company_name != g.legal_name)) AS legal_name_not_from_ch,
  (SELECT COUNTIF(NOT is_resolved AND company_number IS NOT NULL) FROM g) AS unresolved_with_number,
  IF((SELECT COUNT(*) - COUNT(DISTINCT supplier_key) FROM g) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_13,
  IF((SELECT COUNTIF(is_resolved) - COUNT(DISTINCT IF(is_resolved, company_number, NULL)) FROM g) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_14,
  IF((SELECT COUNTIF(name_variant_count IS NULL OR name_variant_count < 1) FROM g) = 0
     AND (SELECT COUNT(*) FROM g JOIN recount USING (supplier_key)
            WHERE g.name_variant_count != recount.raw_variants) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_15,
  IF((SELECT COUNT(*) FROM g LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` c
        ON c.company_number = g.company_number
       WHERE g.is_resolved AND (c.company_name IS NULL OR c.company_name != g.legal_name)) = 0,
     'PASS', 'FAIL  <-- HARD') AS v3_16,
  IF((SELECT COUNTIF(NOT is_resolved AND company_number IS NOT NULL) FROM g) = 0, 'PASS', 'FAIL  <-- HARD') AS v3_17;

-- ===========================================================================
-- V3.12 dissolved-company matches                                   INFO
-- ===========================================================================
-- A finding, not an error. Money paid to a company the register calls dissolved
-- is either a late payment, a stale name, or a mismatch — and it is exactly the
-- kind of thing a spend dashboard should surface rather than smooth over.

SELECT
  g.company_status,
  COUNT(DISTINCT g.supplier_key)                    AS suppliers,
  COUNT(*)                                          AS transaction_rows,
  ROUND(SUM(s.amount), 2)                           AS transaction_value,
  COUNTIF(s.payment_date > g.incorporation_date)    AS rows_after_incorporation
FROM `portfolio-508106.portfolio_b.resolved_spend` s
JOIN `portfolio-508106.portfolio_b.resolved_supplier_golden` g USING (supplier_key)
WHERE s.row_role = 'transaction' AND g.is_resolved
GROUP BY g.company_status
ORDER BY transaction_value DESC;

-- ===========================================================================
-- The resolution profile — INFO, and the figure the portfolio quotes
-- ===========================================================================
-- Names, rows and value by tier, over transaction rows only. The unresolved line
-- is published with the same prominence as the resolved ones.

SELECT
  CASE m.match_tier
    WHEN 1 THEN '1 company number'
    WHEN 2 THEN '2 exact name'
    WHEN 3 THEN '3 name + postcode'
    WHEN 4 THEN IF(m.match_confidence = 'reviewed',
                   '4 fuzzy — ACCEPTED on recorded review',
                   '4 fuzzy — REVIEW ONLY, not resolved')
    ELSE        '5 unresolved'
  END                                         AS tier,
  COUNT(DISTINCT m.supplier_name_norm)        AS supplier_names,
  COUNT(*)                                    AS transaction_rows,
  ROUND(SUM(s.amount), 2)                     AS transaction_value,
  ROUND(100 * SUM(s.amount) / SUM(SUM(s.amount)) OVER (), 2) AS pct_of_value
FROM `portfolio-508106.portfolio_b.resolved_spend` s
JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
WHERE s.row_role = 'transaction'
GROUP BY tier
ORDER BY tier;

-- ===========================================================================
-- Unresolved reasons, and the review queue — INFO
-- ===========================================================================
-- What 'unresolved' actually means, by value. 'review' is the tier-4 queue:
-- names with a candidate and a score, awaiting a human decision.

SELECT
  COALESCE(m.unresolved_reason, 'resolved')   AS unresolved_reason,
  COUNT(DISTINCT m.supplier_name_norm)        AS supplier_names,
  ROUND(SUM(s.amount), 2)                     AS transaction_value
FROM `portfolio-508106.portfolio_b.resolved_spend` s
JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
WHERE s.row_role = 'transaction'
GROUP BY unresolved_reason
ORDER BY transaction_value DESC;

-- ===========================================================================
-- Tier 1 demotion — INFO, and the count published either way
-- ===========================================================================
-- 04 §3 hard rule 6 (ruled 2026-09-18): where the buyer states a company number
-- whose registered name disagrees with the supplier name, the match is DEMOTED TO
-- REVIEW rather than accepted. The count is published whether it flatters the
-- method or not. Some demoted names are later confirmed by tier 2 or 3 on their
-- own evidence — that is the rule working, not leaking.

SELECT
  COUNTIF(accepted)                                           AS tier1_accepted,
  COUNTIF(reject_reason = 'register_name_disagrees')          AS demoted_to_review,
  COUNTIF(reject_reason = 'ambiguous')                        AS rejected_ambiguous,
  COUNTIF(reject_reason = 'number_not_in_register')           AS rejected_not_in_register,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_match_tier1` a
    JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
   WHERE a.reject_reason = 'register_name_disagrees' AND m.match_tier IN (2,3)) AS demoted_then_confirmed_elsewhere,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_match_tier1` a
    JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
   WHERE a.reject_reason = 'register_name_disagrees' AND m.match_tier = 1) AS demoted_but_still_tier1
FROM `portfolio-508106.portfolio_b.resolved_match_tier1`;

-- ===========================================================================
-- The resolution claim, by BASIS — INFO, and the only figure to quote
-- ===========================================================================
-- Two different kinds of evidence resolve a name, and they are reported
-- separately so one never borrows the credibility of the other:
--   METHOD    tiers 1-3, decided by rule, measured by E-3
--   REVIEWED  tier-4 candidates accepted on a recorded human decision (38),
--             each with a basis beyond the score
-- 58.32% was the method's claim before the queue was worked. It still is.
--
-- THE SPLIT IS ON match_confidence, NOT ON TIER. A demoted tier-1 row accepted on
-- review keeps match_tier 1 -- tier 1 is how it was found -- but it is REVIEWED,
-- not method. Splitting on the tier number would quietly bank a human decision as
-- if the rule had made it.

SELECT
  CASE
    WHEN m.is_resolved AND m.match_confidence != 'reviewed' THEN '1 METHOD — tiers 1-3, by rule'
    WHEN m.is_resolved                                      THEN '2 REVIEWED — accepted on a recorded decision'
    ELSE                                          '3 UNRESOLVED'
  END                                                           AS basis,
  COUNT(DISTINCT m.supplier_name_norm)                          AS supplier_names,
  COUNT(*)                                                      AS transaction_rows,
  ROUND(SUM(s.amount), 2)                                       AS transaction_value,
  ROUND(100 * SUM(s.amount) / SUM(SUM(s.amount)) OVER (), 2)    AS pct_of_value
FROM `portfolio-508106.portfolio_b.resolved_spend` s
JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
WHERE s.row_role = 'transaction'
GROUP BY basis
ORDER BY basis;

-- ===========================================================================
-- D.1-D.4  Review-queue decisions are applied exactly as recorded     HARD
-- ===========================================================================
-- D.1 every decision names a name that exists in the audit trail
-- D.2 no decision is STALE — an accept is of a specific company; if a rebuild
--     changes the tier-4 candidate the approval must not follow the name
-- D.3 every accept resolves its name; no reject is resolved BY REVIEW (a rejected
--     name may still be resolved later by method evidence -- that is the rule
--     working, not the decision leaking)
-- D.4 'reviewed' confidence exists only where an accept exists

WITH d AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_queue_decisions`),
m AS (SELECT * FROM `portfolio-508106.portfolio_b.resolved_supplier_match`)
SELECT
  (SELECT COUNT(*) FROM d)                                                        AS decisions,
  (SELECT COUNTIF(decision = 'accepted') FROM d)                                  AS accepted,
  (SELECT COUNTIF(decision = 'rejected') FROM d)                                  AS rejected,
  (SELECT COUNT(*) FROM d LEFT JOIN m USING (supplier_name_norm)
    WHERE m.supplier_name_norm IS NULL)                                           AS orphan_decisions,
  (SELECT COUNTIF(has_stale_decision) FROM m)                                     AS stale_decisions,
  (SELECT COUNT(*) FROM d JOIN m USING (supplier_name_norm)
    WHERE (d.decision = 'accepted' AND NOT m.is_resolved)
       OR (d.decision = 'rejected' AND m.match_confidence = 'reviewed'))          AS decisions_not_applied,
  (SELECT COUNT(*) FROM m LEFT JOIN d USING (supplier_name_norm)
    WHERE m.match_confidence = 'reviewed' AND COALESCE(d.decision, '') != 'accepted') AS reviewed_without_accept,
  IF((SELECT COUNT(*) FROM d LEFT JOIN m USING (supplier_name_norm) WHERE m.supplier_name_norm IS NULL) = 0
     AND (SELECT COUNTIF(has_stale_decision) FROM m) = 0
     AND (SELECT COUNT(*) FROM d JOIN m USING (supplier_name_norm)
           WHERE (d.decision = 'accepted' AND NOT m.is_resolved)
              OR (d.decision = 'rejected' AND m.match_confidence = 'reviewed')) = 0
     AND (SELECT COUNT(*) FROM m LEFT JOIN d USING (supplier_name_norm)
           WHERE m.match_confidence = 'reviewed' AND COALESCE(d.decision, '') != 'accepted') = 0,
     'PASS', 'FAIL  <-- HARD') AS d1_d4;
