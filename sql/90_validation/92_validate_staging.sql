-- 92_validate_staging.sql
-- Layer: validation. Runs AFTER L2, before any Layer 3 work begins.
--
-- EXECUTABLE. V2.1-V2.12 per 05-validation-rules.md, plus the mandatory
-- per-publisher reporting that 08 §6.5 and §10.5 require.
--
-- EXECUTED 2026-09-16.
--
-- ===========================================================================
-- V2.1 — REQUIRED VALUE IS 352,614, AND THAT WAS AMBIGUOUS UNTIL 2026-09-16
-- ===========================================================================
-- 05-validation-rules.md required staging_spend to equal the sum of the
-- raw_spend_* counts (364,835). 08 §12 required 352,614. Both HARD, and they
-- differ by exactly the 12,221 blank padding rows.
--
-- RESOLVED 2026-09-16, user-approved: 352,614 is operative and the 05 wording
-- was stale. The two layers count different things by design —
--
--   L1 raw_      364,835   Layer 1 drops nothing. A silent drop there would
--                          break _row_num and with it E-1's traceability claim.
--   L2 staging_  352,614   = records_real = 364,835 - 12,221. Padding removed
--                          HERE, in SQL, where the decision is visible.
--
-- The removal is reported per publisher below, not silent. A count that falls by
-- 12,221 between layers is otherwise indistinguishable from a join that lost
-- 12,221 rows, and V2.1 passing without those counts published is not a pass.

-- ===========================================================================
-- V2.1  staging_spend row count                                    HARD
-- ===========================================================================

SELECT
  COUNT(*)            AS staging_rows,
  352614              AS required,
  COUNT(*) - 352614   AS delta,
  IF(COUNT(*) = 352614, 'PASS', 'FAIL  <-- HARD') AS v2_1
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- Padding removal, per publisher — 08 §11.1 mandatory reporting
-- ===========================================================================
-- REQUIRED: HMRC 12,201 · MOJ 18 · Manchester 2 · total 12,221.
-- These must equal provenance.blank_padding_rows for the same publisher.
--
-- NOTE ON THE FILTER. §11.1's prose defines padding as every field empty; its
-- SQL tests only supplier, amount and date. For MOJ those differ: 27 rows are
-- blank in the three fields, but only 18 are blank in ALL fields. The other 9
-- carry publisher reconciliation notes in department_family ('Exempt items',
-- 'Bank Rec adjustments', 'Duplicate exempt transactions', ...), all in the
-- 2025-01 file. They are a data-quality finding, not padding. The all-fields
-- test is used; the three-field test gives 352,605 and fails V2.1 by 9.

WITH l1 AS (
  SELECT 'Bristol City Council' AS entity, COUNT(*) AS raw_rows FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
  UNION ALL SELECT 'City of York Council',     COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_york`
  UNION ALL SELECT 'Department for Transport', COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_dft`
  UNION ALL SELECT 'HM Revenue and Customs',   COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`
  UNION ALL SELECT 'Manchester City Council',  COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_manchester`
  UNION ALL SELECT 'Ministry of Justice',      COUNT(*) FROM `portfolio-508106.portfolio_b.raw_spend_moj`
),
l2 AS (
  SELECT entity, COUNT(*) AS staging_rows
  FROM `portfolio-508106.portfolio_b.staging_spend` GROUP BY entity
)
SELECT
  l1.entity,
  l1.raw_rows,
  l2.staging_rows,
  l1.raw_rows - l2.staging_rows AS padding_removed
FROM l1 JOIN l2 USING (entity)
ORDER BY padding_removed DESC, entity;

-- ===========================================================================
-- V2.2  spend_id unique                                            HARD
-- ===========================================================================

SELECT
  COUNT(*) - COUNT(DISTINCT spend_id) AS duplicate_ids,
  IF(COUNT(*) = COUNT(DISTINCT spend_id), 'PASS', 'FAIL  <-- HARD') AS v2_2
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- V2.3  every staging row traces to a _source_file + _row_num in L1   HARD
-- ===========================================================================
-- This is what makes padding removal safe. Removing rows and losing
-- traceability are the same failure wearing different clothes.

WITH raw_keys AS (
  SELECT _source_file, _row_num FROM `portfolio-508106.portfolio_b.raw_spend_bristol`
  UNION ALL SELECT _source_file, _row_num FROM `portfolio-508106.portfolio_b.raw_spend_york`
  UNION ALL SELECT _source_file, _row_num FROM `portfolio-508106.portfolio_b.raw_spend_dft`
  UNION ALL SELECT _source_file, _row_num FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`
  UNION ALL SELECT _source_file, _row_num FROM `portfolio-508106.portfolio_b.raw_spend_manchester`
  UNION ALL SELECT _source_file, _row_num FROM `portfolio-508106.portfolio_b.raw_spend_moj`
)
SELECT
  COUNTIF(r._source_file IS NULL) AS untraceable_rows,
  IF(COUNTIF(r._source_file IS NULL) = 0, 'PASS', 'FAIL  <-- HARD') AS v2_3
FROM `portfolio-508106.portfolio_b.staging_spend` s
LEFT JOIN raw_keys r
  ON r._source_file = s._source_file AND r._row_num = s._row_num;

-- ===========================================================================
-- V2.4 / §6.5  date-ladder rejection counts, per publisher          HARD
-- ===========================================================================
-- MANDATORY REPORTING. Unparsed dates are counted and published, never
-- silently nulled.
--
-- REQUIRED: MOJ 34 · Bristol 11 · Manchester 1 · York 0 · DfT 0 · HMRC 0
--           TOTAL 46
--
-- More than 46 means a format is missing from the ladder — find it before
-- proceeding. FEWER than 46 is worse: it means something parsed that should not
-- have, and the first thing to check is that %d/%m/%y has not been placed above
-- %d/%m/%Y, which would read 01/03/2024 as a two-digit year.

SELECT
  entity,
  COUNT(*)                                                 AS rows_total,
  COUNTIF(payment_date IS NULL)                            AS rows_unparsed,
  ROUND(100 * COUNTIF(payment_date IS NULL) / COUNT(*), 4) AS pct_unparsed
FROM `portfolio-508106.portfolio_b.staging_spend`
GROUP BY entity
ORDER BY rows_unparsed DESC, entity;

SELECT
  COUNTIF(payment_date IS NULL) AS total_unparsed,
  46                            AS required,
  IF(COUNTIF(payment_date IS NULL) = 46, 'PASS', 'FAIL  <-- HARD') AS v2_4
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- is_undated must agree with the ladder exactly — it is derived from it, so a
-- mismatch would mean the column was computed somewhere else.
SELECT
  COUNTIF(is_undated != (payment_date IS NULL)) AS disagreements,
  COUNTIF(is_undated)                           AS undated_rows
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- V2.5  dates outside the analysis window                          SOFT
-- ===========================================================================
-- 08 §9.5: do NOT assume a monthly file contains only its own month. A payment
-- dated 2024-02-28 sitting in the March file is a real thing that happens.
-- REQUIRED reconciliation (§9.6): in-window 289,990 · outside 62,578 · undated 46.

SELECT
  COUNTIF(is_undated) AS undated,
  COUNTIF(NOT is_undated AND payment_date BETWEEN DATE '2024-03-01' AND DATE '2025-02-28') AS in_window,
  COUNTIF(NOT is_undated AND NOT (payment_date BETWEEN DATE '2024-03-01' AND DATE '2025-02-28')) AS outside_window,
  COUNT(*) AS total
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- V2.6 / V2.7 / §10.5  amount parsing, per publisher               HARD / INFO
-- ===========================================================================
-- REQUIRED: amount_unparsed = 10, ALL Ministry of Justice. Anything higher
-- means a format was missed.
--
-- V2.7 is INFO and the negatives are RETAINED: credits and reversals are
-- legitimate. MOJ publishes 19 of them in accounting parentheses worth
-- GBP 2,766,216.08 — parsed with the wrong sign the total swings by
-- GBP 5,532,432.16 and still looks plausible, which is why the parenthesis
-- test runs before the strip rather than after.

SELECT
  entity,
  COUNT(*)                AS rows_total,
  COUNTIF(amount IS NULL) AS amount_unparsed,
  COUNTIF(amount < 0)     AS amount_negative,
  ROUND(SUM(amount), 2)   AS amount_sum
FROM `portfolio-508106.portfolio_b.staging_spend`
GROUP BY entity
ORDER BY entity;

SELECT
  COUNTIF(amount IS NULL) AS total_unparsed,
  10                      AS required,
  IF(COUNTIF(amount IS NULL) = 10, 'PASS', 'FAIL  <-- HARD') AS v2_6
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- V2.8  amount_vat_basis populated and in the permitted set        HARD
-- ===========================================================================
-- V2.8-note: 'unknown' is no longer producible, so a NULL or unexpected value
-- can only mean an entity string that matched none of the expected six — a
-- typo or a changed publisher name. That stops the pipeline; it is not counted.

SELECT
  amount_vat_basis,
  COUNT(*) AS rows_total,
  IF(amount_vat_basis IN ('net_plus_irrecoverable_confirmed',
                          'net_plus_irrecoverable_code_basis'),
     'PASS', 'FAIL  <-- HARD') AS v2_8
FROM `portfolio-508106.portfolio_b.staging_spend`
GROUP BY amount_vat_basis
ORDER BY rows_total DESC;

-- ===========================================================================
-- V2.9  supplier_name_raw non-null unless redacted                 HARD
-- ===========================================================================
-- SCOPED 2026-09-16, user-approved: tested only on rows CARRYING AN AMOUNT.
-- A row with neither a supplier name nor an amount cannot participate in
-- matching or aggregation and is inert bookkeeping, not a matching failure.
-- 9 rows fall out of scope on that basis, all Ministry of Justice.
--
-- ===========================================================================
-- THE SCOPING DID NOT MAKE THIS PASS. IT MADE IT POINT AT SOMETHING.
-- ===========================================================================
-- 31 rows carry an amount and no supplier name, worth GBP 2,084,055,613.01.
-- They are FILE TOTAL ROWS, and they are double-counting spend.
--
-- PROOF, not inference. For all 11 Bristol files that contain such a row, the
-- row's amount equals the sum of EVERY OTHER ROW IN THE SAME FILE to the penny
-- — difference 0.00 in all 11. Each sits at the file's final _row_num
-- (2024-04 at 6727 of 6727, 2024-05 at 6574 of 6574, ...). Bristol 2024-03 has
-- no such row and shows a difference of -70,277,619.67, i.e. no total present.
-- MOJ's carry a transaction_number exactly one below their _row_num.
--
--   Ministry of Justice       19 rows   GBP 1,350,879,438.54
--   Bristol City Council      11 rows   GBP   733,176,703.99
--   Manchester City Council    1 row    GBP          -529.52
--
-- Bristol's true spend is GBP 803,454,323.66, not the GBP 1,536,631,027.65
-- currently in staging_spend. Eleven of its twelve months are counted twice.
--
-- WHY NOTHING ELSE WOULD HAVE CAUGHT IT. The inflation is IN THE SOURCE, so it
-- reconciles perfectly at every layer: V2.1 ties to provenance, E-5 preserves
-- SUM(amount) L2->L3->L4 exactly as required, and every total agrees with every
-- other total. A double-count that reconciles is invisible to a reconciliation.
-- V2.9 is the only rule in the suite that asks whether money has a named
-- recipient, which is the one question that exposes it.
--
-- NOT ACTED ON. Excluding total rows is a new exclusion rule, it is not in 08
-- §11, and it changes the headline spend figure for two publishers. That is a
-- specification decision, not a builder's.

SELECT
  COUNTIF(COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted
          AND amount IS NOT NULL)                      AS missing_name_on_payment_rows,
  COUNTIF(COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted
          AND amount IS NULL)                          AS inert_rows_out_of_scope,
  ROUND(SUM(IF(COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted
               AND amount IS NOT NULL, amount, 0)), 2) AS value_at_stake,
  IF(COUNTIF(COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted
             AND amount IS NOT NULL) = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_9
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ---------------------------------------------------------------------------
-- V2.9a  Total-row detector — the test that turns the finding into evidence
-- ---------------------------------------------------------------------------
-- Per file: does the unnamed amount-bearing row equal the sum of all the other
-- rows in that file? A difference of 0.00 means the row is a total of its own
-- file and is being counted twice. Run this before trusting ANY spend total.

SELECT
  entity,
  _source_file,
  ROUND(SUM(IF(is_unnamed, amount, 0)), 2) AS unnamed_row_amount,
  ROUND(SUM(IF(is_unnamed, 0, amount)), 2) AS sum_of_other_rows,
  ROUND(SUM(IF(is_unnamed, amount, 0)) - SUM(IF(is_unnamed, 0, amount)), 2) AS difference,
  IF(ROUND(SUM(IF(is_unnamed, amount, 0)) - SUM(IF(is_unnamed, 0, amount)), 2) = 0,
     'TOTAL ROW  <-- double counted', 'not a total') AS verdict
FROM (
  SELECT entity, _source_file, amount,
         (COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted
          AND amount IS NOT NULL) AS is_unnamed
  FROM `portfolio-508106.portfolio_b.staging_spend`
)
GROUP BY entity, _source_file
HAVING SUM(IF(is_unnamed, 1, 0)) > 0
ORDER BY entity, _source_file;

-- ===========================================================================
-- V2.10  normalisation must not erase a name                       HARD
-- ===========================================================================
-- A name consisting only of punctuation or a legal suffix would normalise to an
-- empty string and vanish silently. This is the check that catches it.

SELECT
  COUNT(*) AS erased,
  IF(COUNT(*) = 0, 'PASS', 'FAIL  <-- HARD') AS v2_10
FROM `portfolio-508106.portfolio_b.staging_spend`
WHERE COALESCE(TRIM(supplier_name_raw), '') != ''
  AND COALESCE(TRIM(supplier_name_norm), '') = '';

-- ===========================================================================
-- V2.11  postcode format where present                             SOFT
-- ===========================================================================
-- Invalid postcodes are excluded from tier-3 matching, not deleted.

SELECT
  COUNTIF(supplier_postcode IS NOT NULL) AS with_postcode,
  COUNTIF(supplier_postcode IS NOT NULL
          AND NOT REGEXP_CONTAINS(UPPER(TRIM(supplier_postcode)),
                r'^[A-Z]{1,2}[0-9][A-Z0-9]?\s*[0-9][A-Z]{2}$')) AS invalid_format
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- V2.12  publisher_type complete                                   HARD
-- ===========================================================================

SELECT
  COUNTIF(publisher_type IS NULL) AS unclassified,
  COUNTIF(publisher_type = 'central') AS central_rows,
  COUNTIF(publisher_type = 'local')   AS local_rows,
  IF(COUNTIF(publisher_type IS NULL) = 0, 'PASS', 'FAIL  <-- HARD') AS v2_12
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ===========================================================================
-- §8.2  Grant-in-Aid — the figures D-P-022 requires reported
-- ===========================================================================
-- REQUIRED: 59 rows, GBP 10,788,523,565.00, 23.87% of DfT value.
-- 59 rows carry nearly a quarter of DfT's value, and one of them is
-- GBP 465,000,000.00 to National Highways Limited. Left in, National Highways
-- looks like the largest supplier in the whole six-publisher dataset, which is
-- false: it is a funding transfer to an arm's-length body, not a purchase.

SELECT
  COUNTIF(is_grant_in_aid)                     AS gia_rows,
  ROUND(SUM(IF(is_grant_in_aid, amount, 0)), 2) AS gia_value,
  ROUND(SUM(amount), 2)                         AS dft_total_value,
  ROUND(100 * SUM(IF(is_grant_in_aid, amount, 0)) / SUM(amount), 2) AS gia_pct_of_dft
FROM `portfolio-508106.portfolio_b.staging_spend`
WHERE entity = 'Department for Transport';

-- ===========================================================================
-- §11.4  redaction review — READ THIS OUTPUT, do not just count it
-- ===========================================================================
-- 'Redactive Publishing Ltd' is a real company. A bare REDACT match flags it as
-- redacted and removes a genuine supplier from matching entirely. Any entry
-- below that is plainly a real trading name needs an explicit exclusion added
-- to the §11.4 pattern, and every exclusion recorded in docs/validation_report.md.

SELECT supplier_name_raw, COUNT(*) AS n
FROM `portfolio-508106.portfolio_b.staging_spend`
WHERE is_redacted
GROUP BY supplier_name_raw
ORDER BY n DESC
LIMIT 50;
