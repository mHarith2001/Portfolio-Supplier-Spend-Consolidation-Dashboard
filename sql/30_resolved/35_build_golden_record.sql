-- 35_build_golden_record.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input. Needs 31-34 first.
--
-- Builds the audit trail (resolved_supplier_match), then the golden record
-- (resolved_supplier_golden) from it. 03 §4 and 04 §5.

-- ===========================================================================
-- 1. resolved_supplier_match - one row per distinct normalised supplier name
-- ===========================================================================
-- FIRST MATCH WINS, tier order 1 -> 5 (04 §3). Acceptance is READ FROM each tier
-- table's own `accepted` column, never re-derived here: the tier files own their
-- rules, and a second copy of a rule is a second rule waiting to drift.
--
-- Every transaction name appears exactly once (V3.4), including redacted names,
-- which never enter matching and go straight to tier 5 (04 §3 hard rule 4).
--
-- TIER 4 CARRIES A CANDIDATE BUT RESOLVES NOTHING. Its candidate and score are
-- recorded so the review queue can be published with the evidence a reviewer
-- needs - and match_confidence is 'review', never 'high' (V3.7). Attribution in
-- 36 takes tiers 1-3 only. A tier-4 row is a question, not an answer.
--
-- THE 232 DEMOTED TIER-1 NAMES (04 §3 hard rule 6) land here as reject_reason
-- 'register_name_disagrees'. They do not flow as confirmed matches. Where tier 2
-- or 3 later confirms the same name on its own evidence, that acceptance stands -
-- the demotion rejects the buyer's assertion, not the name.
--
-- unresolved_reason 'review' is a FIFTH value beyond the four 03 §4 lists
-- (redacted / no_match / ambiguous / below_threshold). A queued tier-4 name is
-- neither resolved nor rejected, so none of the four fit. Flagged to the handler.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_supplier_match` AS
WITH redacted_names AS (
  SELECT DISTINCT supplier_name_norm
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction' AND is_redacted AND supplier_name_norm IS NOT NULL
),
spend_names AS (
  SELECT DISTINCT supplier_name_norm
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction' AND supplier_name_norm IS NOT NULL
),
base AS (
  SELECT
    n.supplier_name_norm,
    r.supplier_name_norm IS NOT NULL      AS is_redacted_name,
    COALESCE(t1.accepted, FALSE)          AS t1_ok,
    t1.candidate_company_number           AS t1_num,
    t1.reject_reason                      AS t1_rej,
    COALESCE(t2.accepted, FALSE)          AS t2_ok,
    t2.candidate_company_number           AS t2_num,
    t2.candidate_count                    AS t2_cnt,
    t2.reject_reason                      AS t2_rej,
    COALESCE(t3.accepted, FALSE)          AS t3_ok,
    t3.candidate_company_number           AS t3_num,
    t3.candidate_count                    AS t3_cnt,
    t3.reject_reason                      AS t3_rej,
    t4.candidate_company_number           AS t4_num,
    t4.candidate_company_name             AS t4_name,
    t4.match_score                        AS t4_score,
    t4.candidate_count                    AS t4_cnt
  FROM spend_names n
  LEFT JOIN redacted_names r USING (supplier_name_norm)
  LEFT JOIN `portfolio-508106.portfolio_b.resolved_match_tier1` t1 USING (supplier_name_norm)
  LEFT JOIN `portfolio-508106.portfolio_b.resolved_match_tier2` t2 USING (supplier_name_norm)
  LEFT JOIN `portfolio-508106.portfolio_b.resolved_match_tier3` t3 USING (supplier_name_norm)
  LEFT JOIN `portfolio-508106.portfolio_b.resolved_match_tier4` t4 USING (supplier_name_norm)
)
SELECT
  supplier_name_norm,
  CASE WHEN is_redacted_name THEN NULL
       WHEN t1_ok            THEN t1_num
       WHEN t2_ok            THEN t2_num
       WHEN t3_ok            THEN t3_num
       WHEN t4_score >= 0.85 THEN t4_num END                       AS matched_company_number,
  CASE WHEN is_redacted_name THEN 5
       WHEN t1_ok            THEN 1
       WHEN t2_ok            THEN 2
       WHEN t3_ok            THEN 3
       WHEN t4_score >= 0.85 THEN 4
       ELSE 5 END                                                  AS match_tier,
  CASE WHEN is_redacted_name THEN 'unresolved'
       WHEN t1_ok            THEN 'company_number'
       WHEN t2_ok            THEN 'exact_name'
       WHEN t3_ok            THEN 'name_postcode'
       WHEN t4_score >= 0.85 THEN 'fuzzy'
       ELSE 'unresolved' END                                       AS match_method,
  IF(NOT is_redacted_name AND NOT t1_ok AND NOT t2_ok AND NOT t3_ok, t4_score, NULL)
                                                                   AS match_score,
  CASE WHEN is_redacted_name THEN 'none'
       WHEN t1_ok            THEN 'high'
       WHEN t2_ok            THEN 'high'
       WHEN t3_ok            THEN 'medium'
       WHEN t4_score >= 0.85 THEN 'review'
       ELSE 'none' END                                             AS match_confidence,
  CASE WHEN is_redacted_name THEN 1
       WHEN t1_ok            THEN 1
       WHEN t2_ok            THEN t2_cnt
       WHEN t3_ok            THEN t3_cnt
       WHEN t4_score >= 0.85 THEN t4_cnt
       ELSE 1 END                                                  AS candidate_count,
  IF(NOT is_redacted_name AND NOT t1_ok AND NOT t2_ok AND NOT t3_ok AND t4_score >= 0.85,
     t4_name, NULL)                                                AS review_candidate_name,
  ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST([
    IF(is_redacted_name, 'redacted: never enters matching', NULL),
    IF(t1_rej = 'register_name_disagrees',
       CONCAT('tier 1 demoted to review: the stated number ', COALESCE(t1_num, '?'),
              ' belongs to a differently named company'), NULL),
    IF(t1_rej = 'ambiguous', 'tier 1: the award source states more than one number for this name', NULL),
    IF(t1_rej = 'number_not_in_register', 'tier 1: the stated number is absent from the snapshot', NULL),
    IF(t2_rej = 'ambiguous', 'tier 2: more than one company carries this name', NULL),
    IF(t2_rej = 'single_candidate_not_active', 'tier 2: the only company with this name is not active', NULL),
    IF(t2_rej = 'implausible_before_incorporation', 'tier 2: first payment precedes incorporation', NULL),
    IF(t3_rej = 'ambiguous', 'tier 3: more than one company at this name and postcode', NULL),
    IF(t3_rej = 'implausible_before_incorporation', 'tier 3: first payment precedes incorporation', NULL),
    IF(t4_score >= 0.85, CONCAT('tier 4 review candidate, score ', CAST(t4_score AS STRING)), NULL),
    IF(t4_score < 0.85, CONCAT('tier 4 best score ', CAST(t4_score AS STRING), ' is below the 0.85 threshold'), NULL),
    IF(t4_score IS NULL AND NOT is_redacted_name,
       'no tier-4 candidate: no company in the register shares the first core token', NULL)
  ]) x WHERE x IS NOT NULL), ' | ')                                AS resolution_notes,
  CASE WHEN is_redacted_name                                  THEN 'redacted'
       WHEN t1_ok OR t2_ok OR t3_ok                           THEN NULL
       WHEN t4_score >= 0.85                                  THEN 'review'
       WHEN t1_rej = 'register_name_disagrees'                THEN 'ambiguous'
       WHEN COALESCE(t1_rej, t2_rej, t3_rej) = 'ambiguous'    THEN 'ambiguous'
       WHEN t4_score IS NOT NULL                              THEN 'below_threshold'
       ELSE 'no_match' END                                         AS unresolved_reason
FROM base;

-- ===========================================================================
-- 2. resolved_supplier_golden - one row per supplier entity
-- ===========================================================================
-- SURVIVORSHIP, 04 §5: Companies House is authoritative for IDENTITY, the spend
-- files for MONEY. Neither overwrites the other's domain - no amount is taken
-- from any source but the spend files, and no legal name from anywhere but the
-- register.
--
-- RESOLVED entities are tiers 1-3 only. A tier-4 name is queued, not resolved, so
-- it keeps its own unresolved record: the review queue stays visible in the data
-- rather than merged into a supplier nobody confirmed (L-1).
--
-- EVERY transaction name has a golden row, resolved or not, so every transaction
-- row in 36 can carry a supplier_key. Unresolved keys are name-keyed and stay
-- unresolved; they are not quietly dropped out of the spend total.
--
-- name_variant_count is the headline-finding generator: how many distinct raw
-- spellings collapse into one entity (V3.15). It counts RAW spellings among
-- transaction rows - the count a reader of the source files would recognise.

-- Written with joins rather than correlated subqueries: BigQuery rejects a
-- correlated subquery over another table unless it can de-correlate it, and
-- `IN UNNEST(array_of_names)` is exactly the shape it cannot.
--
-- Summing distinct raw counts per normalised name is safe because normalisation
-- is a function: one raw spelling has exactly one norm, so the raw sets behind
-- two different norms never overlap and the sum cannot double-count.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_supplier_golden` AS
WITH variants AS (
  SELECT
    supplier_name_norm,
    supplier_name_raw,
    COUNT(*)            AS rows_n,
    MAX(payment_date)   AS last_payment
  FROM `portfolio-508106.portfolio_b.staging_spend`
  WHERE row_role = 'transaction' AND supplier_name_norm IS NOT NULL
  GROUP BY supplier_name_norm, supplier_name_raw
),
norm_variants AS (
  SELECT supplier_name_norm, COUNT(DISTINCT supplier_name_raw) AS raw_n
  FROM variants GROUP BY supplier_name_norm
),
top_raw AS (
  SELECT supplier_name_norm, supplier_name_raw
  FROM (
    SELECT supplier_name_norm, supplier_name_raw,
           ROW_NUMBER() OVER (PARTITION BY supplier_name_norm
                              ORDER BY rows_n DESC, last_payment DESC, supplier_name_raw) AS rn
    FROM variants
  )
  WHERE rn = 1
),
resolved AS (
  SELECT
    m.matched_company_number       AS company_number,
    SUM(nv.raw_n)                  AS name_variant_count
  FROM `portfolio-508106.portfolio_b.resolved_supplier_match` m
  JOIN norm_variants nv USING (supplier_name_norm)
  WHERE m.match_tier <= 3 AND m.matched_company_number IS NOT NULL
  GROUP BY m.matched_company_number
)
SELECT
  TO_HEX(SHA256(CONCAT('CH|', r.company_number)))    AS supplier_key,
  r.company_number,
  c.company_name                                     AS legal_name,
  c.company_name                                     AS display_name,
  c.company_status,
  c.incorporation_date,
  c.postcode,
  r.name_variant_count,
  TRUE                                               AS is_resolved,
  CAST(NULL AS STRING)                               AS unresolved_reason
FROM resolved r
JOIN `portfolio-508106.portfolio_b.staging_companies` c USING (company_number)

UNION ALL

SELECT
  TO_HEX(SHA256(CONCAT('NAME|', m.supplier_name_norm))) AS supplier_key,
  CAST(NULL AS STRING)                                  AS company_number,
  CAST(NULL AS STRING)                                  AS legal_name,
  tr.supplier_name_raw                                  AS display_name,
  CAST(NULL AS STRING)                                  AS company_status,
  CAST(NULL AS DATE)                                    AS incorporation_date,
  CAST(NULL AS STRING)                                  AS postcode,
  nv.raw_n                                              AS name_variant_count,
  FALSE                                                 AS is_resolved,
  m.unresolved_reason
FROM `portfolio-508106.portfolio_b.resolved_supplier_match` m
LEFT JOIN norm_variants nv USING (supplier_name_norm)
LEFT JOIN top_raw      tr USING (supplier_name_norm)
WHERE m.matched_company_number IS NULL OR m.match_tier >= 4;
