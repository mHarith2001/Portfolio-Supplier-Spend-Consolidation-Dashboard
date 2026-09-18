-- 34_match_tier4_fuzzy.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
-- Precision measurement: sql/90_validation/95_measure_match_precision.sql
--
-- EXECUTED 2026-09-18 (blocking corrected). Run from a file on standard input.
--
-- ===========================================================================
-- TIER 4 NEVER AUTO-ACCEPTS
-- ===========================================================================
-- 04 §3 hard rule 1: fuzzy matches populate a review queue with match_score and
-- candidate_count; they never merge. There is no `accepted` column in this file
-- for that reason. A portfolio project cannot claim human review it did not do.
--
-- METHOD. BigQuery has neither Jaro-Winkler nor a token-set ratio built in, so
-- the token-set arm of 04 §3 is used:
--
--     score = |tokens(A) ∩ tokens(B)| / |tokens(A) ∪ tokens(B)|
--
-- on the suffix-free core, with EDIT_DISTANCE over the whole core as tie-break.
-- Token-set is right for this data: publishers truncate and reorder supplier
-- names far more often than they misspell them.
--
-- ===========================================================================
-- BLOCKING, CORRECTED 2026-09-18 — WHY THE OLD ONE WAS WRONG
-- ===========================================================================
-- This file used to block on the FIRST core token. That is a heuristic with no
-- guarantee: a genuine rival in the register beginning with a different word was
-- never compared, and never counted in candidate_count.
--
-- It was caught on the most valuable row in the queue. GREAT WESTERN RAILWAY
-- scored 1.00 against GREAT WESTERN RAILWAY LIMITED with candidate_count = 1,
-- while FIRST GREATER WESTERN LIMITED -- same SIC 49100 passenger rail, and the
-- registered name behind the trading name the payer used -- sat in the register
-- excluded on the token FIRST. GBP 1,645,099,386.59 rested on a count that read
-- as "no alternatives exist" and meant "none survived blocking".
--
-- THE REPLACEMENT IS A PREFIX FILTER ON FREQUENCY-ORDERED TOKENS.
--   score >= 0.5  =>  3c >= a + b  =>  c >= CEIL((a+b)/3), b <= 2a, a <= 2b
--   order each token set by register frequency, RAREST FIRST
--   index only the first  p(x) = |x| - CEIL(0.5*|x|) + 1  tokens
--
-- If two sets can reach the floor their prefixes MUST intersect: were the
-- prefixes disjoint, the whole overlap would have to come from the suffixes,
-- which are shorter than the required CEIL((a+b)/3). So NO CANDIDATE THAT COULD
-- REACH THE FLOOR IS EXCLUDED -- the guarantee first-token blocking never gave.
--
-- Rarest-first ordering is also what makes it affordable. Measured 2026-09-18:
--   any shared token + length bound   936,444,356 pairs
--   prefix filter, frequency-ordered   86,927,511 pairs   (90.7% fewer)
--
-- WHAT IT DOES NOT FIX. The filter is lossless with respect to the 0.5 CANDIDATE
-- FLOOR, not with respect to reality. GREAT WESTERN RAILWAY and FIRST GREATER
-- WESTERN share one token of five and score 0.20: they are now compared, and
-- correctly fall below the floor. A trading name sharing few tokens with its
-- registered name is beyond token-set similarity altogether. That belongs to the
-- scoring function, and it is exactly why tier 4 is reviewed and never merged.
--
-- THE SUFFIX-CONFLICT GUARD (04 §3 hard rule 7). A candidate is rejected where
-- BOTH names carry a legal suffix and the suffixes differ -- a PLC supplier
-- against a LIMITED company. The core is suffix-free by design, which is what
-- lets 'NETWORK RAIL' meet 'NETWORK RAIL LIMITED'; without this guard it also
-- lets the LTD/PLC conflation back in. Measured before the guard: 4 names,
-- GBP 39,014,117.12.
--
-- HARD RULE 3 (added 2026-09-18). A company incorporated after the first payment
-- cannot be the payee. Filters CANDIDATES, not names, so a name whose best
-- candidate is impossible can still reach a plausible second-best one.
--
-- POPULATION: every name not already accepted at TIER 2 OR TIER 3. Tier 1 is
-- deliberately NOT excluded: E-3 measures tiers 2-4 on the name alone (04 §4), so
-- excluding names tier 1 resolved would measure a different method from the one
-- that runs. First-match-wins still applies tier 1 ahead of tier 4.

-- ---------------------------------------------------------------------------
-- 1. Scored candidates, floor 0.5 -- the material the threshold is chosen from
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_tier4_candidates` AS
WITH resolved_23 AS (
  SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier2` WHERE accepted
  UNION DISTINCT
  SELECT supplier_name_norm FROM `portfolio-508106.portfolio_b.resolved_match_tier3` WHERE accepted
),
ch AS (
  SELECT
    company_number, company_name, company_status, incorporation_date, core,
    ARRAY(SELECT DISTINCT t FROM UNNEST(SPLIT(core, ' ')) t WHERE t != '')  AS tokens,
    REGEXP_EXTRACT(company_name_norm, r'\s(LTD|PLC|LLP)$')                  AS name_suffix
  FROM (
    SELECT *, `portfolio-508106.portfolio_b.name_core_from_norm`(company_name_norm) AS core
    FROM `portfolio-508106.portfolio_b.staging_companies`
  )
  WHERE core IS NOT NULL
),
-- Document frequency over the REGISTER. Both sides must order by the same global
-- frequency or the prefix-filter guarantee does not hold.
df AS (
  SELECT tok, COUNT(*) AS n FROM ch, UNNEST(tokens) AS tok GROUP BY tok
),
todo AS (
  SELECT
    n.supplier_name_norm, n.in_spend, n.in_e3, n.spend_value, n.first_payment_date,
    n.supplier_name_core,
    ARRAY(SELECT DISTINCT t FROM UNNEST(SPLIT(n.supplier_name_core, ' ')) t WHERE t != '') AS tokens,
    REGEXP_EXTRACT(n.supplier_name_norm, r'\s(LTD|PLC|LLP)$')               AS name_suffix
  FROM `portfolio-508106.portfolio_b.resolved_names` n
  LEFT JOIN resolved_23 r USING (supplier_name_norm)
  WHERE r.supplier_name_norm IS NULL AND n.supplier_name_core IS NOT NULL
),
n_prefix AS (
  SELECT supplier_name_norm, tok
  FROM (
    SELECT t.supplier_name_norm, tok, ARRAY_LENGTH(t.tokens) AS a,
           ROW_NUMBER() OVER (PARTITION BY t.supplier_name_norm
                              ORDER BY COALESCE(df.n, 0), tok) AS rk
    FROM todo t, UNNEST(t.tokens) AS tok
    LEFT JOIN df USING (tok)
  )
  WHERE rk <= a - CAST(CEIL(0.5 * a) AS INT64) + 1
),
c_prefix AS (
  SELECT company_number, tok
  FROM (
    SELECT c.company_number, tok, ARRAY_LENGTH(c.tokens) AS b,
           ROW_NUMBER() OVER (PARTITION BY c.company_number
                              ORDER BY COALESCE(df.n, 0), tok) AS rk
    FROM ch c, UNNEST(c.tokens) AS tok
    LEFT JOIN df USING (tok)
  )
  WHERE rk <= b - CAST(CEIL(0.5 * b) AS INT64) + 1
),
-- DISTINCT because a pair may share several prefix tokens and must be scored once.
pairs AS (
  SELECT DISTINCT n.supplier_name_norm, c.company_number
  FROM n_prefix n JOIN c_prefix c USING (tok)
),
scored AS (
  SELECT
    t.supplier_name_norm, t.in_spend, t.in_e3,
    c.company_number, c.company_name, c.company_status, c.incorporation_date,
    t.supplier_name_core, c.core,
    t.name_suffix AS n_suffix, c.name_suffix AS c_suffix,
    t.first_payment_date,
    ARRAY_LENGTH(t.tokens) AS name_tokens,
    ARRAY_LENGTH(c.tokens) AS company_tokens,
    ARRAY_LENGTH(ARRAY(
      SELECT tok FROM UNNEST(t.tokens) AS tok
      INTERSECT DISTINCT
      SELECT tok FROM UNNEST(c.tokens) AS tok))  AS shared_tokens
  FROM pairs p
  JOIN todo t USING (supplier_name_norm)
  JOIN ch   c USING (company_number)
  WHERE ARRAY_LENGTH(c.tokens) <= 2 * ARRAY_LENGTH(t.tokens)
    AND ARRAY_LENGTH(t.tokens) <= 2 * ARRAY_LENGTH(c.tokens)
)
SELECT
  supplier_name_norm, in_spend, in_e3,
  company_number, company_name, company_status, incorporation_date,
  shared_tokens, name_tokens, company_tokens,
  SAFE_DIVIDE(shared_tokens, name_tokens + company_tokens - shared_tokens) AS score,
  1 - SAFE_DIVIDE(EDIT_DISTANCE(supplier_name_core, core),
                  GREATEST(LENGTH(supplier_name_core), LENGTH(core)))      AS edit_similarity
FROM scored
WHERE NOT (n_suffix IS NOT NULL AND c_suffix IS NOT NULL AND n_suffix != c_suffix)
  AND COALESCE(NOT (first_payment_date < incorporation_date), TRUE)
  AND SAFE_DIVIDE(shared_tokens, name_tokens + company_tokens - shared_tokens) >= 0.5;

-- ---------------------------------------------------------------------------
-- 2. Best candidate per name, with the ambiguity count
-- ---------------------------------------------------------------------------
-- candidate_count is the number of DISTINCT companies tied at the best score.
-- Since 2026-09-18 that count means what a reader assumes it means: with the
-- prefix filter, no company that could reach the floor was excluded from the
-- comparison, so a count of 1 is a statement about the register rather than
-- about the blocking key.

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
