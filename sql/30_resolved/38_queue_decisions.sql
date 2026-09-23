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
  ),
  STRUCT(
    'LENDLEASE CONSTRUCTION EUROPE LTD',
    '00467006',
    'accepted',
    DATE '2026-09-23',
    CONCAT(
      'TIER A, USER DECISION. A demoted tier-1 row, decided on the register own ',
      'previous-name record. 00467006 is registered today as BOVIS CONSTRUCTION ',
      '(EUROPE) LIMITED, which is why hard rule 6 demoted it; but its name history ',
      'records LENDLEASE CONSTRUCTION (EUROPE) LIMITED as the registered name until ',
      '2025-04-01, and every payment on this name falls inside that period, ',
      '2024-03-18 to 2025-02-21. The payer spelled the supplier as the company was ',
      'then registered. Supporting: the Ministry of Defence states 00467006 for ',
      'Lendlease Construction (Europe) Limited in Contracts Finder; SIC 41201 ',
      'construction of commercial buildings; no other register entry carries the ',
      'name. Class precision for demoted rows, 37.04% on 27, is why the buyer ',
      'assertion alone could not decide it.')
  ),
  STRUCT('NATIONAL GRID ELECTRICITY TRANSMISSION', '02366977', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays NATIONAL GRID ELECTRICITY TRANSMISSION PLC, a spelling with the same suffix-free name that resolves BY RULE to 02366977 NATIONAL GRID ELECTRICITY TRANSMISSION PLC. Same payer, same name core, same company. Single candidate. GBP 3,527,965.98.'),
  STRUCT('VIRGIN MEDIA BUSINESS', '01785381', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays VIRGIN MEDIA BUSINESS LTD, a spelling with the same suffix-free name that resolves BY RULE to 01785381 VIRGIN MEDIA BUSINESS LIMITED. Same payer, same name core, same company. Single candidate. GBP 2,313,453.03.'),
  STRUCT('CAPGEMINI UK', '00943935', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays CAPGEMINI UK PLC, a spelling with the same suffix-free name that resolves BY RULE to 00943935 CAPGEMINI UK PLC. Same payer, same name core, same company. Single candidate. GBP 2,130,039.58.'),
  STRUCT('HEATHCOTES CARE', '05232834', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). City of York Council pays HEATHCOTES CARE LTD, a spelling with the same suffix-free name that resolves BY RULE to 05232834 HEATHCOTES CARE LIMITED. Same payer, same name core, same company. Single candidate. GBP 1,803,325.99.'),
  STRUCT('WITHERSLACK GROUP', '03579104', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Bristol City Council pays WITHERSLACK GROUP LTD, a spelling with the same suffix-free name that resolves BY RULE to 03579104 WITHERSLACK GROUP LIMITED. Same payer, same name core, same company. Single candidate. GBP 1,765,311.59.'),
  STRUCT('WE CARE AND REPAIR', 'IP25479R', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Bristol City Council pays WE CARE AND REPAIR LTD, a spelling with the same suffix-free name that resolves BY RULE to IP25479R WE CARE & REPAIR LIMITED. Same payer, same name core, same company. Single candidate. GBP 1,275,855.72.'),
  STRUCT('MUDDY BOOTS NURSERY', '07479672', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). City of York Council pays MUDDY BOOTS NURSERY LTD, a spelling with the same suffix-free name that resolves BY RULE to 07479672 MUDDY BOOTS NURSERY LTD.. Same payer, same name core, same company. Single candidate. GBP 1,250,743.35.'),
  STRUCT('CARE TODAY CHILDRENS SERVICES', '03576741', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Manchester City Council pays CARE TODAY CHILDRENS SERVICES LTD, a spelling with the same suffix-free name that resolves BY RULE to 03576741 CARE TODAY (CHILDRENS SERVICES) LTD. Same payer, same name core, same company. Single candidate. GBP 909,994.01.'),
  STRUCT('ARVATO', '03923307', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays ARVATO LTD, a spelling with the same suffix-free name that resolves BY RULE to 03923307 ARVATO LIMITED. Same payer, same name core, same company. Single candidate. GBP 760,609.41.'),
  STRUCT('IFF RESEARCH LTD', '00849983', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-PAYER-AWARDS (the row-3 class). The payer own Contracts Finder awards state the candidate: HM Revenue and Customs states 00849983; Ministry of Justice states 00849983 (4 award(s)), none stating another number. Single candidate. GBP 706,894.12.'),
  STRUCT('JONES LANG LASALLE', '01188567', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays JONES LANG LASALLE LTD, a spelling with the same suffix-free name that resolves BY RULE to 01188567 JONES LANG LASALLE LIMITED. Same payer, same name core, same company. Single candidate. GBP 525,222.93.'),
  STRUCT('TIDDLYWINKS DAY NURSERY', '05627488', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Manchester City Council pays TIDDLYWINKS DAY NURSERY LTD, a spelling with the same suffix-free name that resolves BY RULE to 05627488 TIDDLYWINKS DAY NURSERY LTD. Same payer, same name core, same company. Single candidate. GBP 518,176.79.'),
  STRUCT('SKILLSOFT UK LTD', '02051729', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-PAYER-AWARDS (the row-3 class). The payer own Contracts Finder awards state the candidate: HM Revenue and Customs states 02051729 (1 award(s)), none stating another number. Single candidate. GBP 454,200.00.'),
  STRUCT('1SPATIAL GROUP', '04785688', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays 1SPATIAL GROUP LTD, a spelling with the same suffix-free name that resolves BY RULE to 04785688 1SPATIAL GROUP LIMITED. Same payer, same name core, same company. Single candidate. GBP 403,080.00.'),
  STRUCT('THOMPSONS SOLICITORS', 'OC356468', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Manchester City Council pays THOMPSONS SOLICITORS LLP, a spelling with the same suffix-free name that resolves BY RULE to OC356468 THOMPSONS SOLICITORS LLP. Same payer, same name core, same company. Single candidate. GBP 339,629.00.'),
  STRUCT('CITY CARE PARTNERSHIP', '04386239', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Manchester City Council pays CITY CARE PARTNERSHIP LTD, a spelling with the same suffix-free name that resolves BY RULE to 04386239 CITY CARE PARTNERSHIP LIMITED. Same payer, same name core, same company. Single candidate. GBP 271,975.97.'),
  STRUCT('AECOM', '01846493', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays AECOM LTD, a spelling with the same suffix-free name that resolves BY RULE to 01846493 AECOM LIMITED. Same payer, same name core, same company. Single candidate. GBP 263,589.98.'),
  STRUCT('SFJ AWARDS', '06926458', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-PAYER-AWARDS (the row-3 class). The payer own Contracts Finder awards state the candidate: Ministry of Justice states 06926458 (1 award(s)), none stating another number. Single candidate. GBP 258,021.00.'),
  STRUCT('NORTH EAST TRUCK AND VAN', '02786349', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-PAYER-AWARDS (the row-3 class). The payer own Contracts Finder awards state the candidate: City of York Council states 02786349 (1 award(s)), none stating another number. Single candidate. GBP 223,250.69.'),
  STRUCT('INTEGRITY360', '03538529', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays INTEGRITY360 LTD, a spelling with the same suffix-free name that resolves BY RULE to 03538529 INTEGRITY360 LIMITED. Same payer, same name core, same company. Single candidate. GBP 208,137.41.'),
  STRUCT('HUNTINGTON KINDER CLASS', '12049422', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). City of York Council pays HUNTINGTON KINDER CLASS LTD, a spelling with the same suffix-free name that resolves BY RULE to 12049422 HUNTINGTON KINDER CLASS LTD. Same payer, same name core, same company. Single candidate. GBP 172,038.92.'),
  STRUCT('SOPRA STERIA', '04077975', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Department for Transport pays SOPRA STERIA LTD, a spelling with the same suffix-free name that resolves BY RULE to 04077975 SOPRA STERIA LIMITED. Same payer, same name core, same company. Single candidate. GBP 159,900.00.'),
  STRUCT('COWLING SWIFT AND KITCHIN', '07935708', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). City of York Council pays COWLING SWIFT AND KITCHIN LTD, a spelling with the same suffix-free name that resolves BY RULE to 07935708 COWLING SWIFT & KITCHIN LIMITED. Same payer, same name core, same company. Single candidate. GBP 157,650.00.'),
  STRUCT('INAAYA SOLICITORS', '10364401', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Manchester City Council pays INAAYA SOLICITORS LTD, a spelling with the same suffix-free name that resolves BY RULE to 10364401 INAAYA SOLICITORS LIMITED. Same payer, same name core, same company. Single candidate. GBP 121,675.57.'),
  STRUCT('AMR CYBER SECURITY LTD', '11551941', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-PAYER-AWARDS (the row-3 class). The payer own Contracts Finder awards state the candidate: HM Revenue and Customs states 11551941 (1 award(s)), none stating another number. Single candidate. GBP 119,518.20.'),
  STRUCT('CABOT LEARNING FEDERATION LTD', '06207590', 'accepted', DATE '2026-09-23', 'TIER B, USER DECISION, approved as batch 1 on 2026-09-23. ACCEPT-SAME-PAYER-BRIDGE (the row-2 class). Bristol City Council pays CABOT LEARNING FEDERATION, a spelling with the same suffix-free name that resolves BY RULE to 06207590 CABOT LEARNING FEDERATION. Same payer, same name core, same company. Single candidate. GBP 103,535.95.')
]);
