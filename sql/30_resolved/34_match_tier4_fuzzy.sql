-- 34_match_tier4_fuzzy.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
-- Precision measurement: sql/90_validation/95_measure_match_precision.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input. Needs 31-33 first.
--
-- ===========================================================================
-- TIER 4 NEVER AUTO-ACCEPTS
-- ===========================================================================
-- 04 §3 hard rule 1: fuzzy matches populate a review queue with match_score and
-- candidate_count; they never merge. There is no `accepted` column in this file
-- for that reason. A portfolio project cannot claim human review it did not do.
--
-- METHOD (04 §3: "token-set / Jaro-Winkler on supplier_name_core, blocked by
-- first token"). BigQuery has neither Jaro-Winkler nor a token-set ratio built
-- in, so the token-set arm is used:
--
--     score = |tokens(A) ∩ tokens(B)| / |tokens(A) ∪ tokens(B)|
--
-- on the suffix-free core, with EDIT_DISTANCE over the whole core as the
-- tie-break. Token-set is the right arm for this data: publishers truncate and
-- reorder supplier names far more often than they misspell them.
--
-- BLOCKING is the first token of the core, as specified. It is what makes this
-- affordable — and it is also a RECALL LIMIT, stated in the output: a name whose
-- first token is itself wrong or absent can never be compared. The count of names
-- with no candidate block is reported, not hidden.
--
-- THE SUFFIX-CONFLICT GUARD (ruled 2026-09-18). A candidate is rejected outright
-- where BOTH names carry a legal suffix and the suffixes differ — a PLC supplier
-- against a LIMITED company, an LLP against a LIMITED. The core key is suffix-free
-- by design (04 §2 step 9), which is what lets 'NETWORK RAIL' meet 'NETWORK RAIL
-- LIMITED'; without this guard it also lets the LTD/PLC conflation that 04 §2
-- exists to prevent back in. Measured at tier 3 before the guard: 4 names,
-- GBP 39,014,117.12.
--
-- POPULATION: every name not already accepted at TIER 2 OR TIER 3. Tier 1 is
-- deliberately NOT excluded. E-3 measures tiers 2-4 on the name alone (04 §4), so
-- excluding names that tier 1 resolved would measure a different method from the
-- one that runs. First-match-wins still applies tier 1 ahead of tier 4 when spend
-- is resolved.

-- ---------------------------------------------------------------------------
-- 1. Scored candidates, floor 0.5 — the material the threshold is chosen from
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_tier4_candidates` AS
WITH resolved_23 AS (
  SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier2` WHERE accepted
  UNION DISTINCT
  SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier3` WHERE accepted
),
todo AS (
  SELECT
    n.supplier_name_norm, n.in_spend, n.in_e3, n.spend_value,
    n.first_payment_date,
    SPLIT(n.supplier_name_core, ' ')[SAFE_OFFSET(0)]                     AS block_token,
    ARRAY(SELECT DISTINCT t FROM UNNEST(SPLIT(n.supplier_name_core, ' ')) t WHERE t != '') AS tokens,
    REGEXP_EXTRACT(n.supplier_name_norm, r'\s(LTD|PLC|LLP)$')            AS name_suffix,
    n.supplier_name_core
  FROM `portfolio-508106.portfolio_b.resolved_names` n
  LEFT JOIN resolved_23 r USING (supplier_name_norm)
  WHERE r.supplier_name_norm IS NULL AND n.supplier_name_core IS NOT NULL
),
ch AS (
  SELECT
    company_number, company_name, company_name_norm, company_status, incorporation_date, core,
    SPLIT(core, ' ')[SAFE_OFFSET(0)]                                     AS block_token,
    ARRAY(SELECT DISTINCT t FROM UNNEST(SPLIT(core, ' ')) t WHERE t != '') AS tokens,
    REGEXP_EXTRACT(company_name_norm, r'\s(LTD|PLC|LLP)$')                AS name_suffix
  FROM (
    SELECT *, `portfolio-508106.portfolio_b.name_core_from_norm`(company_name_norm) AS core
    FROM `portfolio-508106.portfolio_b.staging_companies`
  )
  WHERE core IS NOT NULL
)
SELECT
  t.supplier_name_norm, t.in_spend, t.in_e3,
  c.company_number, c.company_name, c.company_status, c.incorporation_date,
  ARRAY_LENGTH(ARRAY(
    SELECT tok FROM UNNEST(t.tokens) AS tok
    INTERSECT DISTINCT
    SELECT tok FROM UNNEST(c.tokens) AS tok))                             AS shared_tokens,
  ARRAY_LENGTH(t.tokens)                                                  AS name_tokens,
  ARRAY_LENGTH(c.tokens)                                                  AS company_tokens,
  SAFE_DIVIDE(
    ARRAY_LENGTH(ARRAY(
      SELECT tok FROM UNNEST(t.tokens) AS tok
      INTERSECT DISTINCT
      SELECT tok FROM UNNEST(c.tokens) AS tok)),
    ARRAY_LENGTH(t.tokens) + ARRAY_LENGTH(c.tokens) - ARRAY_LENGTH(ARRAY(
      SELECT tok FROM UNNEST(t.tokens) AS tok
      INTERSECT DISTINCT
      SELECT tok FROM UNNEST(c.tokens) AS tok)))                          AS score,
  1 - SAFE_DIVIDE(EDIT_DISTANCE(t.supplier_name_core, c.core),
                  GREATEST(LENGTH(t.supplier_name_core), LENGTH(c.core))) AS edit_similarity
FROM todo t
JOIN ch c USING (block_token)
WHERE NOT (t.name_suffix IS NOT NULL AND c.name_suffix IS NOT NULL AND t.name_suffix != c.name_suffix)
  -- HARD RULE 3, applied at tier 4 from 2026-09-18. A company incorporated AFTER
  -- the first payment cannot be the payee. Tiers 1-3 have always rejected this;
  -- tier 4 did not, and 107 of its 1,305 queued candidates were impossible on
  -- those grounds, carrying GBP 64,259,806.06 -- one of them incorporated
  -- 2025-12-24, after payments it supposedly received.
  --
  -- It is a FILTER ON CANDIDATES, not on names, and deliberately so: a name whose
  -- best candidate is impossible can still reach a plausible second-best one,
  -- which is the whole point of scoring more than one. Names with no payment date
  -- (the E-3 population) are kept, matching tier 1's treatment of unknown dates.
  AND COALESCE(NOT (t.first_payment_date < c.incorporation_date), TRUE)
  AND SAFE_DIVIDE(
        ARRAY_LENGTH(ARRAY(
          SELECT tok FROM UNNEST(t.tokens) AS tok
          INTERSECT DISTINCT
          SELECT tok FROM UNNEST(c.tokens) AS tok)),
        ARRAY_LENGTH(t.tokens) + ARRAY_LENGTH(c.tokens) - ARRAY_LENGTH(ARRAY(
          SELECT tok FROM UNNEST(t.tokens) AS tok
          INTERSECT DISTINCT
          SELECT tok FROM UNNEST(c.tokens) AS tok))) >= 0.5;

-- ---------------------------------------------------------------------------
-- 2. Best candidate per name, with the ambiguity count
-- ---------------------------------------------------------------------------
-- candidate_count is the number of DISTINCT companies tied at the best score.
-- 04 §3 hard rule 2 makes >1 ambiguous; tier 4 accepts nothing either way, so the
-- number is carried into the review queue rather than used to block.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_match_tier4` AS
WITH ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY supplier_name_norm ORDER BY score DESC, edit_similarity DESC, company_number) AS rn,
    MAX(score) OVER (PARTITION BY supplier_name_norm) AS best_score
  FROM `portfolio-508106.portfolio_b.resolved_tier4_candidates`
)
SELECT
  supplier_name_norm, in_spend, in_e3,
  company_number      AS candidate_company_number,
  company_name        AS candidate_company_name,
  company_status, incorporation_date,
  ROUND(score, 4)           AS match_score,
  ROUND(edit_similarity, 4) AS edit_similarity,
  (SELECT COUNT(DISTINCT c.company_number)
   FROM `portfolio-508106.portfolio_b.resolved_tier4_candidates` c
   WHERE c.supplier_name_norm = ranked.supplier_name_norm AND c.score = ranked.best_score) AS candidate_count
FROM ranked
WHERE rn = 1;
