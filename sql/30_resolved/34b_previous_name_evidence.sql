-- 34b_previous_name_evidence.sql
-- Layer: L3 resolved_ -- the register's own name history, as review evidence
--
-- EXECUTED 2026-09-23. Run after 34, before 35. Adopted by the user 2026-09-23.
--
-- ===========================================================================
-- WHY A PREVIOUS NAME IS EVIDENCE
-- ===========================================================================
-- Hard rule 6 demotes a tier-1 match when the buyer's stated number belongs to a
-- company whose CURRENT registered name differs from the supplier name. Companies
-- rename. The register records up to ten previous names with the date each was
-- changed, so it can say what a company was called ON THE DAY IT WAS PAID.
--
-- Found on Tier A row 1: 00467006 is registered today as BOVIS CONSTRUCTION
-- (EUROPE) LIMITED, but was LENDLEASE CONSTRUCTION (EUROPE) LIMITED until
-- 2025-04-01 -- covering every payment the payer made under that name.
--
-- ===========================================================================
-- THE SCOPING, AS RULED
-- ===========================================================================
-- A queued candidate may cite a registered previous name ONLY WHERE
--   (a) the payer's own spelling of the supplier normalises to that previous name
--       (compared on the suffix-free core, the same key tier 4 scores on), AND
--   (b) the WHOLE payment window -- first to last transaction on that spelling --
--       falls inside that name's registered validity period.
-- A previous name that had already been dropped before the first payment, or
-- was adopted after it, is not evidence: the company was not called that when
-- the payer paid it.
--
-- VALIDITY WINDOW. `PreviousName_k_CONDATE` is the date the company changed AWAY
-- from name k (checked below: name k's date is never before name k+1's). So
--   valid_to   = CONDATE_k
--   valid_from = CONDATE_(k+1), or the incorporation date for the oldest
--                recorded name. For k = 10 an older, unrecorded name may exist, so
--                its start is unknown and it is not used.
--
-- HOW IT TAKES EFFECT. As an EVIDENCE CLASS, ACCEPT-PREVIOUS-NAME, inside the
-- tiered review protocol (04 §8.1) -- not as a rule that resolves by itself.
-- Tier C decisions cite it under the standing authorisation; Tiers A and B come
-- to the user. Nothing here changes a tier table or E-3.
--
-- MIXED TYPES, FOUND 2026-09-23. The register was loaded with autodetect (08 §5.3),
-- which typed CONDATE 1-4 as DATE but left 5-10 as day-first STRINGS
-- ('26/06/2025'). A bare cast would have returned NULL for every one of them --
-- silently dropping every fifth-to-tenth previous name. They are parsed
-- day-first explicitly.
--
-- The register columns carry leading spaces in some names, kept from the source
-- header because Layer 1 alters nothing. They are quoted exactly.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_company_previous_names` AS
WITH r AS (
  SELECT
    TRIM(` CompanyNumber`) AS company_number,
    IncorporationDate      AS incorporation_date,
    [
      STRUCT(1 AS k, ` PreviousName_1_CompanyName`  AS name, `PreviousName_1_CONDATE`   AS condate),
      STRUCT(2,  ` PreviousName_2_CompanyName`,  ` PreviousName_2_CONDATE`),
      STRUCT(3,  ` PreviousName_3_CompanyName`,  `PreviousName_3_CONDATE`),
      STRUCT(4,  ` PreviousName_4_CompanyName`,  `PreviousName_4_CONDATE`),
      STRUCT(5,  ` PreviousName_5_CompanyName`,  SAFE.PARSE_DATE('%d/%m/%Y', TRIM(`PreviousName_5_CONDATE`))),
      STRUCT(6,  ` PreviousName_6_CompanyName`,  SAFE.PARSE_DATE('%d/%m/%Y', TRIM(`PreviousName_6_CONDATE`))),
      STRUCT(7,  ` PreviousName_7_CompanyName`,  SAFE.PARSE_DATE('%d/%m/%Y', TRIM(`PreviousName_7_CONDATE`))),
      STRUCT(8,  ` PreviousName_8_CompanyName`,  SAFE.PARSE_DATE('%d/%m/%Y', TRIM(`PreviousName_8_CONDATE`))),
      STRUCT(9,  ` PreviousName_9_CompanyName`,  SAFE.PARSE_DATE('%d/%m/%Y', TRIM(`PreviousName_9_CONDATE`))),
      STRUCT(10, ` PreviousName_10_CompanyName`, SAFE.PARSE_DATE('%d/%m/%Y', TRIM(`PreviousName_10_CONDATE`)))
    ] AS names
  FROM `portfolio-508106.portfolio_b.raw_companies_house`
),
flat AS (
  SELECT r.company_number, r.incorporation_date, n.k, TRIM(n.name) AS prev_name, n.condate
  FROM r, UNNEST(r.names) AS n
  WHERE n.name IS NOT NULL AND TRIM(n.name) != '' AND n.condate IS NOT NULL
)
SELECT
  f.company_number,
  f.k,
  f.prev_name,
  `portfolio-508106.portfolio_b.name_core_from_norm`(
    `portfolio-508106.portfolio_b.normalise_name`(f.prev_name))            AS prev_core,
  CASE
    WHEN older.condate IS NOT NULL THEN older.condate
    WHEN f.k < 10                  THEN f.incorporation_date
  END                                                                      AS valid_from,
  f.condate                                                                AS valid_to
FROM flat f
LEFT JOIN flat older
  ON older.company_number = f.company_number AND older.k = f.k + 1
-- only register entries that can be a payee at all (hard rule 8)
WHERE f.company_number IN (
  SELECT company_number FROM `portfolio-508106.portfolio_b.resolved_company_universe`);

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_prev_name_evidence` AS
WITH pay_window AS (
  SELECT supplier_name_norm,
         MIN(payment_date) AS first_payment,
         MAX(payment_date) AS last_payment,
         STRING_AGG(DISTINCT entity, '; ' ORDER BY entity) AS payers
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction' AND supplier_name_norm IS NOT NULL
  GROUP BY supplier_name_norm
),
-- every candidate the queue can offer: the tier-4 best candidate and the
-- buyer-stated tier-1 candidate
cand AS (
  SELECT supplier_name_norm, candidate_company_number AS company_number, 'tier 4' AS route
  FROM `portfolio-508106.portfolio_b.resolved_match_tier4`
  UNION DISTINCT
  SELECT supplier_name_norm, candidate_company_number, 'tier 1'
  FROM `portfolio-508106.portfolio_b.resolved_match_tier1`
  WHERE candidate_company_number IS NOT NULL
)
SELECT
  c.supplier_name_norm,
  c.company_number,
  STRING_AGG(DISTINCT c.route, ' + ' ORDER BY c.route)                     AS candidate_route,
  ANY_VALUE(p.prev_name)                                                   AS prev_name,
  ANY_VALUE(p.valid_from)                                                  AS valid_from,
  ANY_VALUE(p.valid_to)                                                    AS valid_to,
  ANY_VALUE(w.first_payment)                                               AS first_payment,
  ANY_VALUE(w.last_payment)                                                AS last_payment,
  ANY_VALUE(w.payers)                                                      AS payers
FROM cand c
JOIN pay_window w USING (supplier_name_norm)
JOIN `portfolio-508106.portfolio_b.resolved_company_previous_names` p
  ON p.company_number = c.company_number
 AND p.prev_core = `portfolio-508106.portfolio_b.name_core_from_norm`(c.supplier_name_norm)
WHERE p.valid_from IS NOT NULL
  AND w.first_payment >= p.valid_from
  AND w.last_payment  <  p.valid_to
GROUP BY c.supplier_name_norm, c.company_number;
