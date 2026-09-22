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
-- WHO DECIDED. Every row here is a USER decision (decided_by = 'user'). Decisions
-- the builder takes under the standing Tier C authorisation live in a separate
-- file, 39_queue_delegated_decisions.sql, with decided_by = 'builder (Tier C)',
-- and a user decision on the same name always takes precedence over a delegated
-- one. The two are never merged, so a reader can always tell them apart.
--
-- HOW A DECISION TAKES EFFECT (from 2026-09-18, row 2).
--   rejected  -> the name stays unresolved; the decision is shown in the queue.
--   accepted  -> 35 resolves the name to the candidate, with match_confidence
--                'reviewed' -- but ONLY IF the accepted candidate still equals the
--                current tier-4 candidate. A rebuild that changes the candidate
--                makes the decision STALE: it is not applied, it is flagged, and
--                93 fails until a human looks again. An approval is of a specific
--                company, never of a name in general.
--
-- DECISIONS NEVER TOUCH E-3. Precision is measured by 95 on the method's own
-- tables (resolved_match_tier2 / tier4), never on resolved_supplier_match, so it
-- keeps measuring the METHOD rather than the method plus a human's corrections.
-- Every decision records its BASIS, and for an accept the basis must be evidence
-- beyond the score -- a score alone is wrong about one time in six at 1.00.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_queue_decisions` AS
SELECT *, 'user' AS decided_by FROM UNNEST([
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
  ),
  STRUCT(
    'WEST MIDLANDS TRAINS',
    '09860466',
    'accepted',
    DATE '2026-09-18',
    CONCAT(
      'BASIS IS CORROBORATION, NOT THE SCORE. The same payer also writes this ',
      'supplier as West Midlands Trains Limited and West Midlands Trains Ltd, and ',
      'that longer spelling already resolves at TIER 2, high confidence, to ',
      '09860466 -- the payer, in its own files, bridges the short form to this company ',
      'independently of any fuzzy matching. Supporting: under the corrected ',
      'prefix-filter blocking, 09860466 WEST MIDLANDS TRAINS LIMITED scores 1.00 ',
      'while all 99 other candidates score 0.50; SIC 49100 passenger rail; ',
      'active; incorporated 2015-11-06, before the first payment on 2024-03-20.')
  ),
  STRUCT(
    'CAPGEMINI',
    '00943935',
    'accepted',
    DATE '2026-09-20',
    CONCAT(
      'A DEMOTED TIER-1 ROW, decided on the own records of the payer rather than ',
      'on the single assertion that caused the demotion. HMRC names Capgemini on ',
      '8 of its own Contracts Finder awards dated 2024-04-08 to 2025-02-28, ',
      'inside the spend window, and states 00943935 on ALL 8 -- no other number ',
      'and no blanks -- including one award spelling the supplier CapGemini, the ',
      'same short form its spend file uses. Corroborated across payers: DfT and ',
      'MOJ write CAPGEMINI UK PLC, which resolves at TIER 2, high confidence, to ',
      '00943935. The demotion was a name-string difference (trading name against ',
      'registered name CAPGEMINI UK PLC), not a different company. Name ',
      'similarity alone does NOT decide this row: the best tier-4 score is 0.50, ',
      'below the floor, and ties with 03953511 CAPGEMINI OLDCO LTD. The class ',
      'statistic for demoted rows -- the stated number agreed with independent ',
      'evidence 10 times of 27, 37.04% -- is why a single assertion is not ',
      'enough, and is not what decided this row.')
  ),
  STRUCT(
    'NEXUS',
    'OE007963',
    'rejected',
    DATE '2026-09-20',
    CONCAT(
      'Evidence contradicts the score. The same payer, DfT, also pays NEXUS ',
      '(TYNE & WEAR) -- 2 rows, GBP 786,000 -- with the SAME first payment date, ',
      '2024-03-26. Nexus is the Tyne and Wear passenger transport executive, a ',
      'statutory public body, which has no Companies House number at all. The ',
      'candidate OE007963 is an OE-prefixed Register of Overseas Entities ',
      'registration dated 2022-12-14 with no SIC -- a foreign body recorded as ',
      'owning UK land, structurally implausible as the payee of transport ',
      'funding. No Contracts Finder award links this payer to any company number ',
      'for NEXUS. Score 1.00 against 99 rivals at 0.50 counts for nothing against ',
      'that: the class it belongs to is measured at 81.21% precision. This row ',
      'also prompted the OE class exclusion (30_match_universe.sql).')
  ),
  STRUCT(
    'CABINET OFFICE',
    '05756325',
    'rejected',
    DATE '2026-09-22',
    CONCAT(
      'Evidence contradicts the score, on four independent counts. SIX public ',
      'bodies pay this name -- MOJ, HMRC, DfT and the York, Bristol and ',
      'Manchester councils -- which is not the payment pattern of a single small ',
      'company. The candidate 05756325 THE CABINET OFFICE LTD is a private ',
      'company in Derbyshire, SIC 82990 other business support, incorporated ',
      '2006; the Cabinet Office is a government department. The payer names the ',
      'real body itself: DfT separately pays Cabinet Office (GPA), the ',
      'Government Property Agency, GBP 17,386,508.52. And Contracts Finder names ',
      'the Cabinet Office as SUPPLIER on 9 awards with no company number on any ',
      'of them. The fourth instance of the documented failure mode: a public ',
      'body scoring 1.00 against a private company of the same name.')
  )
]);
