-- 38_queue_decisions.sql
-- Layer: L3 resolved_ -- the human decisions on the review queue
--
-- EXECUTED 2026-09-18. Run from a file on standard input.
--
-- ===========================================================================
-- DECISIONS LIVE IN VERSION CONTROL, NOT IN A SPREADSHEET
-- ===========================================================================
-- 04 §8 publishes the queue with `decision` blank. As decisions are taken they
-- are recorded HERE, as literals in a file under version control, so that:
--
--   * regenerating the queue never loses them -- 37 joins this table;
--   * every decision carries its date and its REASON, so a reader can disagree
--     with the reasoning rather than just with the outcome;
--   * `git log` shows who decided what and when, which a spreadsheet does not.
--
-- A DECISION IS NOT A MATCH. Nothing in this table feeds resolution: a rejected
-- row stays unresolved and an accepted row would still need an override
-- mechanism this build does not have. The table records JUDGEMENT, and the
-- separation is deliberate -- measured precision must keep measuring the METHOD,
-- not the method plus a human's corrections.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_queue_decisions` AS
SELECT * FROM UNNEST([
  STRUCT(
    'GREAT WESTERN RAILWAY'                     AS supplier_name_norm,
    '01759457'                                  AS candidate_company_number,
    'rejected'                                  AS decision,
    DATE '2026-09-18'                           AS decided_on,
    CONCAT(
      'Evidence contradicts the score. The register holds three SIC 49100 ',
      'passenger-rail companies in this family: 05113733 FIRST GREATER WESTERN ',
      'LIMITED, the candidate 01759457, and 04661194 GREATER WESTERN RAILWAY ',
      'LIMITED. candidate_count = 1 was an artefact of first-token blocking, ',
      'which excluded 05113733 on the token FIRST. Bristol City Council pays ',
      'First Greater Western Ltd as a separate named payee, and Great Western ',
      'Railway is the trading name of that company, so 05113733 is the likelier ',
      'recipient of the franchise payments. Returned to the queue; no manual ',
      'override was applied.')                  AS decision_note
  )
]);
