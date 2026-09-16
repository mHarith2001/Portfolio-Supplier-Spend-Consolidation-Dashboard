-- 22_normalise_names.sql
-- Layer: L2 staging_
-- Validation for this layer: sql/90_validation/92_validate_staging.sql
--
-- EXECUTED 2026-09-16. These are the statements that ran.
--
-- ===========================================================================
-- RUN THIS BEFORE 21_stage_spend_union.sql
-- ===========================================================================
-- The file numbering is from 06-repo-scaffold.md and is kept unchanged, but the
-- dependency runs the other way: 21_ calls the functions defined here. Running
-- 21_ against an empty dataset fails with "Function not found".
--
-- WHY PERSISTENT FUNCTIONS AND NOT CREATE TEMP FUNCTION
--   04-entity-resolution-rules.md §2: the ladder is "applied identically to
--   spend names, Companies House names, and Contracts Finder names". Three
--   callers, and Layer 3 is a fourth. A TEMP function would have to be pasted
--   into each script, and the moment one copy is edited the tiers stop
--   comparing like with like — silently, because a name that normalises two
--   different ways simply fails to match and looks like an unresolved supplier.
--   One definition, four callers.

-- ===========================================================================
-- normalise_name — 04 §2 steps 1-8, the tier-2 key
-- ===========================================================================
-- ORDER DEVIATION, DELIBERATE AND FLAGGED. 04 §2 lists punctuation removal as
-- step 4 and trading-as truncation as step 7. Implemented in that literal order
-- the truncation CANNOT WORK: step 4 removes the slash, so by step 7 the marker
-- `T/A` has already become `TA`, and matching a bare `TA` token would truncate
-- any company with those letters as a word. The truncation is therefore applied
-- BEFORE punctuation removal, which is the only order in which step 7 does what
-- 04 §2 says it does. Nothing else about the ladder is changed.

CREATE OR REPLACE FUNCTION `portfolio-508106.portfolio_b.normalise_name`(raw STRING)
RETURNS STRING
OPTIONS (description = '04-entity-resolution-rules.md §2 steps 1-8. Suffix canonicalised, not stripped. Tier-2 key.')
AS ((
  WITH
  -- 1. uppercase
  s1 AS (SELECT UPPER(COALESCE(raw, '')) AS v),
  -- 2. strip accents, then drop anything still non-ASCII
  s2 AS (SELECT REGEXP_REPLACE(
                  REGEXP_REPLACE(NORMALIZE(v, NFD), r'\p{M}', ''),
                  r'[^\x00-\x7F]', ' ') AS v FROM s1),
  -- 3. & -> AND
  s3 AS (SELECT REGEXP_REPLACE(v, r'&', ' AND ') AS v FROM s2),
  -- 7 (moved up, see header). Truncate at trading-as markers.
  s4 AS (SELECT REGEXP_REPLACE(v, r'\s+(T\s*/\s*A|T\s*\\\s*A|TRADING\s+AS)\s+.*$', '') AS v FROM s3),
  -- 4. remove punctuation, keeping hyphens for now
  s5 AS (SELECT REGEXP_REPLACE(v, r'[^A-Z0-9\s-]', ' ') AS v FROM s4),
  -- 4b. drop hyphens that are not internal; an internal one is kept (ABC-DEF)
  s6 AS (SELECT REGEXP_REPLACE(REGEXP_REPLACE(v, r'(^|\s)-+', ' '), r'-+(\s|$)', ' ') AS v FROM s5),
  -- 5. collapse whitespace
  s7 AS (SELECT TRIM(REGEXP_REPLACE(v, r'\s+', ' ')) AS v FROM s6),
  -- 6. strip a leading THE
  s8 AS (SELECT REGEXP_REPLACE(v, r'^THE\s+', '') AS v FROM s7),
  -- 8. canonicalise the legal-form suffix. Longest form first, anchored to the
  --    end: LIMITED mid-name is part of the name, not a suffix.
  s9 AS (SELECT
           REGEXP_REPLACE(
             REGEXP_REPLACE(
               REGEXP_REPLACE(v, r'\s+PUBLIC\s+LIMITED\s+COMPANY$', ' PLC'),
               r'\s+LIMITED\s+LIABILITY\s+PARTNERSHIP$', ' LLP'),
             r'\s+LIMITED$', ' LTD') AS v FROM s8)
  SELECT NULLIF(TRIM(v), '') FROM s9
));

-- ===========================================================================
-- name_core — 04 §2 step 9, the tier-3/4 blocking key
-- ===========================================================================
-- The suffix is REMOVED here, not canonicalised. 04 §2 is explicit that two
-- keys exist for a reason: "Collapsing LTD and PLC into one entity is a real and
-- common error." ACME LTD and ACME PLC are different legal entities, so tier 2
-- must keep them apart — and the same entity recorded inconsistently must still
-- be catchable, so tier 3/4 need a key that ignores the suffix.
--
-- 04 §3: tier 4 uses this "as a blocking key only, never as a match on its own".

CREATE OR REPLACE FUNCTION `portfolio-508106.portfolio_b.name_core`(raw STRING)
RETURNS STRING
OPTIONS (description = '04-entity-resolution-rules.md §2 step 9. Legal-form suffix removed. Tier-3/4 blocking key only — never a match on its own.')
AS (
  NULLIF(
    TRIM(REGEXP_REPLACE(
      `portfolio-508106.portfolio_b.normalise_name`(raw),
      r'\s+(LTD|PLC|LLP)$', '')),
    '')
);

-- ===========================================================================
-- canon_company_number — 08 §7.2
-- ===========================================================================
-- Applied to BOTH sides of the tier-1 join: Contracts Finder identifiers and
-- Companies House CompanyNumber. 08 §7.1: 3,579 of 24,781 GB-COH identifiers
-- (14.4%) are short, almost all from leading zeros stripped by a spreadsheet,
-- and 886 of them collide with an un-padded form of the same number elsewhere
-- in the same file. Joined as published, the DETERMINISTIC tier fails silently
-- on 14.4% of the records it exists to be reliable about.
--
-- Anything this function cannot parse returns NULL and goes to the exception
-- log. 08 §7.4 is explicit that the 92 unparseable are NOT auto-corrected:
-- 0C303675 is almost certainly OC303675, but "almost certainly" is guessing at
-- the publisher's intent, and the log is itself portfolio evidence.

CREATE OR REPLACE FUNCTION `portfolio-508106.portfolio_b.canon_company_number`(raw STRING)
RETURNS STRING
OPTIONS (description = '08-transformation-guidelines.md §7.2. Canonical 8-char Companies House number, or NULL for the exception log. Never guesses.')
AS ((
  WITH cleaned AS (
    -- 08 §7.2 writes this class as [\s"\x27]. \x22 IS the double-quote
    -- character, so this is the identical class with no literal " in the
    -- statement — which matters because a literal double quote breaks the
    -- statement when it is passed to bq on a Windows command line rather than
    -- pasted into a console. Same regex, same result, one fewer way to fail.
    SELECT UPPER(REGEXP_REPLACE(COALESCE(raw, ''), r'[\s\x22\x27]', '')) AS v
  )
  SELECT
    CASE
      -- empties and all-zero placeholders (82 records)
      WHEN v = ''                      THEN NULL
      WHEN REGEXP_CONTAINS(v, r'^0+$') THEN NULL

      -- purely numeric: strip leading zeros, then pad to 8
      WHEN REGEXP_CONTAINS(v, r'^\d+$') THEN
        CASE
          WHEN LENGTH(REGEXP_REPLACE(v, r'^0+', '')) > 8 THEN NULL   -- 99 records
          WHEN REGEXP_REPLACE(v, r'^0+', '') = ''        THEN NULL
          ELSE LPAD(REGEXP_REPLACE(v, r'^0+', ''), 8, '0')
        END

      -- two-letter prefix + digits: keep prefix, pad numeric part to 6.
      -- SC Scotland, NI N. Ireland, OC/SO LLP, IP Industrial & Provident Society
      WHEN REGEXP_CONTAINS(v, r'^[A-Z]{2}\d{1,6}$') THEN
        CONCAT(SUBSTR(v, 1, 2),
               LPAD(REGEXP_REPLACE(SUBSTR(v, 3), r'^0+', ''), 6, '0'))

      -- already-valid 8-char prefixed form, e.g. SC123456
      WHEN REGEXP_CONTAINS(v, r'^[A-Z]{2}\d{6}$') THEN v

      -- special registered forms ending in a letter, e.g. IP19059R
      WHEN REGEXP_CONTAINS(v, r'^[A-Z]{2}\d{5}[A-Z]$') THEN v

      -- anything else goes to the exception log, NOT to a guess
      ELSE NULL
    END
  FROM cleaned
));

-- ===========================================================================
-- Self-check — 08 §7.3. These figures are REQUIRED, not indicative.
-- ===========================================================================
-- "If your numbers differ from these, stop. These were measured directly from
--  q15-awards.csv, the same file you loaded. A different result means the
--  function was transcribed incorrectly."

SELECT
  COUNTIF(c IS NOT NULL AND REGEXP_CONTAINS(c, r'^\d{8}$'))        AS usable_numeric,        -- 22,672
  COUNTIF(c IS NOT NULL AND REGEXP_CONTAINS(c, r'^[A-Z]{2}\d{6}$')) AS usable_prefixed,      -- 1,815
  COUNTIF(c IS NOT NULL AND REGEXP_CONTAINS(c, r'^[A-Z]{2}\d{5}[A-Z]$')) AS usable_special,  -- 21
  COUNTIF(c IS NOT NULL)                                            AS total_usable,         -- 24,508
  COUNTIF(c IS NULL)                                                AS not_usable,           -- 273
  COUNT(*)                                                          AS gb_coh_records        -- 24,781
FROM (
  SELECT `portfolio-508106.portfolio_b.canon_company_number`(identifier) AS c
  FROM `portfolio-508106.portfolio_b.raw_contracts_finder`
  WHERE category = 'GB-COH' AND COALESCE(TRIM(identifier), '') != ''
);

-- Distinct company numbers: 12,666 as published -> 11,593 canonicalised.
-- The rule removes 1,073 spurious entities.

SELECT
  COUNT(DISTINCT identifier)                                                AS distinct_as_published,
  COUNT(DISTINCT `portfolio-508106.portfolio_b.canon_company_number`(identifier)) AS distinct_canonicalised
FROM `portfolio-508106.portfolio_b.raw_contracts_finder`
WHERE category = 'GB-COH' AND COALESCE(TRIM(identifier), '') != '';
