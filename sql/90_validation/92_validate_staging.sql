-- 92_validate_staging.sql
-- Layer: validation. Runs AFTER L2, before any Layer 3 work begins.
--
-- EXECUTABLE. V2.1-V2.12 per 05-validation-rules.md, plus the mandatory
-- per-publisher reporting that 08 §6.5 and §10.5 require.
--
-- EXECUTED 2026-09-16. V2.9 family re-executed 2026-09-17 after row_role (08 §11.6).
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
-- have. Passing this check is NOT enough on its own: a date that parses to the
-- WRONG value still counts as parsed. Rung 1 without its shape guard read all
-- 4,451 MOJ dd/mm/yy dates as year 24 AD and this check still returned 46 —
-- the V2.5 window split is what caught it (08 §6.2, corrected 2026-09-17).

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
-- SCOPE (05 V2.9, amended 2026-09-17): rows that carry an amount AND whose
-- row_role is 'transaction'. A row with neither a supplier name nor an amount
-- is inert. A non-transaction row is classified by row_role (08 §11.6) and
-- excluded from aggregation — it is not a payment missing its payee.
--
-- HISTORY. Scoped to amount-bearing rows on 2026-09-16, this rule stopped
-- passing and pointed at something instead: file total rows double-counting
-- spend. It is the only rule in the suite that asks whether money has a NAMED
-- RECIPIENT — the one question a reconciliation cannot ask, because a
-- double-count that sits in the source reconciles perfectly at every layer.
-- row_role now classifies those rows, and this rule must find none left among
-- the transactions. Anything it does find is a structure the classification
-- does not yet cover. Stop and examine it before it is summed.

SELECT
  COUNTIF(row_role = 'transaction' AND amount IS NOT NULL
          AND COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted) AS unnamed_transactions,
  COUNTIF(row_role != 'transaction' AND amount IS NOT NULL
          AND COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted) AS unnamed_non_transactions_reported,
  COUNTIF(amount IS NULL
          AND COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted) AS inert_rows_reported,
  IF(COUNTIF(row_role = 'transaction' AND amount IS NOT NULL
             AND COALESCE(TRIM(supplier_name_raw), '') = '' AND NOT is_redacted) = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_9
FROM `portfolio-508106.portfolio_b.staging_spend`;

-- ---------------------------------------------------------------------------
-- V2.9a  File-total detector — independent of row_role               HARD
-- ---------------------------------------------------------------------------
-- Recomputes from the amounts alone which rows are the total of their own file:
-- the file's LAST row whose amount equals the sum of every other row in the
-- file, to the penny. NAME-INDEPENDENT, because MOJ 2024-04's total carries a
-- label in the supplier column. Every hit must carry row_role = 'file_total',
-- and every file_total row must be a hit. Any disagreement fails.
--
-- MEASURED 2026-09-17: 21 hits — Bristol 11 files, MOJ 10 — 0 disagreements.

WITH f AS (
  SELECT _source_file,
         ROUND(SUM(amount), 2)               AS file_sum,
         MAX(SAFE_CAST(_row_num AS INT64))   AS last_rn
  FROM `portfolio-508106.portfolio_b.staging_spend`
  GROUP BY _source_file
),
t AS (
  SELECT s.row_role, s.amount,
    (SAFE_CAST(s._row_num AS INT64) = f.last_rn AND s.amount IS NOT NULL AND s.amount != 0
     AND ROUND(s.amount - (f.file_sum - s.amount), 2) = 0) AS is_total_by_amounts
  FROM `portfolio-508106.portfolio_b.staging_spend` s
  JOIN f USING (_source_file)
)
SELECT
  COUNTIF(is_total_by_amounts)                                  AS totals_by_amounts,
  COUNTIF(row_role = 'file_total')                              AS flagged_file_total,
  COUNTIF(is_total_by_amounts AND row_role != 'file_total')     AS total_not_flagged,
  COUNTIF(NOT is_total_by_amounts AND row_role = 'file_total')  AS flagged_not_total,
  ROUND(SUM(IF(row_role = 'file_total', amount, 0)), 2)         AS file_total_value,
  IF(COUNTIF(is_total_by_amounts AND row_role != 'file_total') = 0
     AND COUNTIF(NOT is_total_by_amounts AND row_role = 'file_total') = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_9a
FROM t;

-- ---------------------------------------------------------------------------
-- V2.9b  Future-month re-check                                      HARD
-- ---------------------------------------------------------------------------
-- Every file is re-checked on every run, so a new month with a workbook layout
-- or a labelled total is caught BEFORE it is summed:
--   * a row carrying the 'Reconciliation to stack:' marker must never be a
--     transaction — its file must have been classified as a workbook;
--   * no transaction may carry a reconciliation label in the supplier column
--     (Publish, Exempt, Total, Subtotal, Bank rec adjustments,
--     Reconciliation..., ...Stack, Publish total...).
-- Also lists every anchored workbook, so the anchor set is visible.

WITH c AS (
  SELECT
    COUNT(DISTINCT IF(UPPER(TRIM(supplier_name_raw)) = 'RECONCILIATION TO STACK:', _source_file, NULL)) AS files_with_marker,
    COUNTIF(UPPER(TRIM(supplier_name_raw)) = 'RECONCILIATION TO STACK:' AND row_role = 'transaction')  AS marker_rows_as_transaction,
    COUNTIF(row_role = 'transaction'
            AND REGEXP_CONTAINS(UPPER(TRIM(COALESCE(supplier_name_raw, ''))),
                r'^(PUBLISH|EXEMPT|TOTAL|GRAND TOTAL|SUB ?TOTAL|BANK REC ADJUSTMENTS)$|^RECONCILIATION|\bSTACK$|^PUBLISH TOTAL')) AS labelled_rows_as_transaction,
    STRING_AGG(DISTINCT IF(row_role IN ('reconciliation', 'annex_duplicate', 'section_header',
                                        'section_total', 'out_of_scope_section'), _source_file, NULL), '; ') AS anchored_workbooks
  FROM `portfolio-508106.portfolio_b.staging_spend`
)
SELECT
  c.*,
  IF(marker_rows_as_transaction = 0 AND labelled_rows_as_transaction = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_9b
FROM c;

-- ---------------------------------------------------------------------------
-- V2.9c  Workbook integrity — every anchored workbook must tie      HARD
-- ---------------------------------------------------------------------------
-- For each file carrying the marker, using row_role alone:
--   transactions             = the publisher's own 'Publish' label
--   body rows (transaction + out_of_scope_section) = body section totals
--   body section totals      = the publisher's stack row
--   every annex_duplicate    re-lists a body row on transaction number and
--                            amount, or inherited is_redacted from one
-- MEASURED 2026-09-17 on MOJ 2025-01: 88,590,412.23 = Publish label;
-- 148,030,181.18 three ways; 24 annex rows = 23 matched + 1 by redaction.

WITH wb AS (
  SELECT _source_file,
         MIN(IF(UPPER(TRIM(supplier_name_raw)) = 'RECONCILIATION TO STACK:',
                SAFE_CAST(_row_num AS INT64), NULL)) AS recon_rn
  FROM `portfolio-508106.portfolio_b.staging_spend`
  GROUP BY _source_file
  HAVING recon_rn IS NOT NULL
),
r AS (
  SELECT s.*, SAFE_CAST(s._row_num AS INT64) AS rn, wb.recon_rn
  FROM `portfolio-508106.portfolio_b.staging_spend` s
  JOIN wb USING (_source_file)
),
body_keys AS (
  SELECT DISTINCT _source_file, transaction_number, amount
  FROM r
  WHERE rn < recon_rn AND row_role IN ('transaction', 'out_of_scope_section')
),
per AS (
  SELECT _source_file,
    ROUND(SUM(IF(row_role = 'transaction', amount, 0)), 2) AS transactions,
    ROUND(MAX(IF(row_role = 'reconciliation' AND UPPER(TRIM(supplier_name_raw)) = 'PUBLISH', amount, NULL)), 2) AS publish_label,
    ROUND(SUM(IF(rn < recon_rn AND row_role IN ('transaction', 'out_of_scope_section'), amount, 0)), 2) AS body_rows,
    ROUND(SUM(IF(rn < recon_rn AND row_role = 'section_total', amount, 0)), 2) AS body_section_totals,
    ROUND(MAX(IF(row_role = 'reconciliation' AND REGEXP_CONTAINS(UPPER(TRIM(supplier_name_raw)), r'\bSTACK$'), amount, NULL)), 2) AS stack_row
  FROM r
  GROUP BY _source_file
),
annex AS (
  SELECT r._source_file,
    COUNT(*)                                          AS annex_rows,
    COUNTIF(k._source_file IS NOT NULL)               AS matched_txn_and_amount,
    COUNTIF(k._source_file IS NULL AND r.is_redacted) AS matched_by_redaction,
    COUNTIF(k._source_file IS NULL AND NOT r.is_redacted) AS unmatched
  FROM r
  LEFT JOIN body_keys k
    ON k._source_file = r._source_file
   AND k.transaction_number = r.transaction_number
   AND k.amount = r.amount
  WHERE r.row_role = 'annex_duplicate'
  GROUP BY r._source_file
)
SELECT
  per.*,
  annex.annex_rows, annex.matched_txn_and_amount, annex.matched_by_redaction, annex.unmatched,
  IF(per.transactions = per.publish_label
     AND per.body_rows = per.body_section_totals
     AND per.body_section_totals = per.stack_row
     AND annex.unmatched = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_9c
FROM per
JOIN annex USING (_source_file);

-- ---------------------------------------------------------------------------
-- row_role summary — INFO. Publish this beside every headline figure: it is
-- the answer to "what did the total exclude, and why".
-- ---------------------------------------------------------------------------

SELECT entity, row_role,
       COUNT(*)                AS n_rows,
       ROUND(SUM(amount), 2)   AS value,
       COUNTIF(is_undated)     AS undated,
       COUNTIF(is_redacted)    AS redacted
FROM `portfolio-508106.portfolio_b.staging_spend`
GROUP BY entity, row_role
ORDER BY entity, row_role;

SELECT entity,
       ROUND(SUM(amount), 2)                                  AS staged_value,
       ROUND(SUM(IF(row_role = 'transaction', amount, 0)), 2) AS transaction_value,
       COUNTIF(row_role = 'transaction')                      AS transaction_rows,
       COUNTIF(is_undated AND row_role = 'transaction')       AS undated_transactions
FROM `portfolio-508106.portfolio_b.staging_spend`
GROUP BY entity
ORDER BY entity;

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
-- V2.R  Reference tables — staging_companies and staging_contracts
-- ===========================================================================
-- ADDED 2026-09-17 with 23_stage_reference.sql. Build controls; not yet rules
-- in 05-validation-rules.md, which covers staging_spend only.

-- ---------------------------------------------------------------------------
-- V2.R1  staging_companies reconciles to Companies House            HARD
-- ---------------------------------------------------------------------------
-- staged = raw - rejected by canon_company_number, and every rejection is an
-- 'R' + 7-digit number (08 §7.3: deliberately not canonicalised).

WITH raw AS (
  SELECT COUNT(*) AS raw_rows,
         COUNTIF(`portfolio-508106.portfolio_b.canon_company_number`(t.` CompanyNumber`) IS NULL) AS rejected,
         COUNTIF(`portfolio-508106.portfolio_b.canon_company_number`(t.` CompanyNumber`) IS NULL
                 AND NOT REGEXP_CONTAINS(t.` CompanyNumber`, r'^R\d{7}$')) AS rejected_not_r_form
  FROM `portfolio-508106.portfolio_b.raw_companies_house` t
),
stg AS (SELECT COUNT(*) AS staged FROM `portfolio-508106.portfolio_b.staging_companies`)
SELECT raw.*, stg.staged,
  IF(stg.staged = raw.raw_rows - raw.rejected AND raw.rejected_not_r_form = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_r1
FROM raw, stg;

-- ---------------------------------------------------------------------------
-- V2.R2  company_number is a primary key                             HARD
-- V2.R3  normalisation erases no company name                        HARD
-- ---------------------------------------------------------------------------

SELECT
  COUNTIF(company_number IS NULL)                        AS null_keys,
  COUNT(*) - COUNT(DISTINCT company_number)              AS duplicate_keys,
  COUNTIF(COALESCE(TRIM(company_name), '') != ''
          AND COALESCE(TRIM(company_name_norm), '') = '') AS erased_names,
  COUNTIF(incorporation_date IS NULL)                    AS no_incorporation_date_info,
  COUNTIF(postcode IS NULL)                              AS no_postcode_info,
  IF(COUNTIF(company_number IS NULL) = 0 AND COUNT(*) = COUNT(DISTINCT company_number),
     'PASS', 'FAIL  <-- HARD') AS v2_r2,
  IF(COUNTIF(COALESCE(TRIM(company_name), '') != '' AND COALESCE(TRIM(company_name_norm), '') = '') = 0,
     'PASS', 'FAIL  <-- HARD') AS v2_r3
FROM `portfolio-508106.portfolio_b.staging_companies`;

-- ---------------------------------------------------------------------------
-- V2.R4  staging_contracts drops nothing                             HARD
-- V2.R5  the E-3 known answer matches 08 §7.3                         HARD
-- V2.R6  the recorded gap stays a gap                                HARD
-- V2.R7  normalisation erases no supplier name                       HARD
-- ---------------------------------------------------------------------------
-- R5 REQUIRED: 24,507 non-null company numbers, 11,593 distinct.
-- R6: award_value and classification are NULL on every row. A non-NULL value
--     would be an invented one — Contracts Finder, as acquired, supplies neither.
-- R7: a raw value containing a letter or digit must not normalise to empty.
--     REFINED AFTER ITS FIRST RUN, 2026-09-17, and flagged for confirmation. As
--     first written it failed on 2 rows whose ENTIRE supplier value is a lone
--     '-' and a lone '.', neither carrying a company number. Those are
--     placeholders, not names: there was no name to erase. They are counted as
--     placeholder_names, not hidden. A real name that vanishes still fails.

WITH c AS (
  SELECT
    (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.raw_contracts_finder`) AS raw_rows,
    COUNT(*)                                             AS staged,
    COUNTIF(supplier_company_number IS NOT NULL)         AS known_answer_rows,
    COUNT(DISTINCT supplier_company_number)              AS known_answer_companies,
    COUNTIF(award_value IS NOT NULL)                     AS award_value_filled,
    COUNTIF(classification IS NOT NULL)                  AS classification_filled,
    COUNTIF(REGEXP_CONTAINS(COALESCE(supplier_name_raw, ''), r'[A-Za-z0-9]')
            AND COALESCE(TRIM(supplier_name_norm), '') = '') AS erased_names,
    COUNTIF(COALESCE(TRIM(supplier_name_raw), '') != ''
            AND NOT REGEXP_CONTAINS(supplier_name_raw, r'[A-Za-z0-9]')) AS placeholder_names,
    COUNTIF(award_date IS NULL)                          AS award_date_null
  FROM `portfolio-508106.portfolio_b.staging_contracts`
)
SELECT c.*,
  IF(staged = raw_rows, 'PASS', 'FAIL  <-- HARD')                                    AS v2_r4,
  IF(known_answer_rows = 24507 AND known_answer_companies = 11593, 'PASS', 'FAIL  <-- HARD') AS v2_r5,
  IF(award_value_filled = 0 AND classification_filled = 0, 'PASS', 'FAIL  <-- HARD') AS v2_r6,
  IF(erased_names = 0, 'PASS', 'FAIL  <-- HARD')                                     AS v2_r7
FROM c;

-- ---------------------------------------------------------------------------
-- V2.R8  Tier-1 reach — INFO. Sizes E-3 before Layer 3 runs.
-- ---------------------------------------------------------------------------
-- How much of the known answer can tier 1 reach at all: a Contracts Finder
-- company number that is absent from staging_companies can never match,
-- however good the matching. Reported, not gated.

SELECT
  COUNT(DISTINCT k.supplier_company_number)                                    AS known_answer_companies,
  COUNT(DISTINCT IF(s.company_number IS NOT NULL, k.supplier_company_number, NULL)) AS found_in_companies_house,
  COUNT(DISTINCT IF(s.company_number IS NULL, k.supplier_company_number, NULL))     AS not_in_snapshot,
  COUNTIF(s.company_number IS NOT NULL)                                        AS known_answer_rows_reachable,
  COUNT(*)                                                                     AS known_answer_rows
FROM `portfolio-508106.portfolio_b.staging_contracts` k
LEFT JOIN `portfolio-508106.portfolio_b.staging_companies` s
  ON s.company_number = k.supplier_company_number
WHERE k.supplier_company_number IS NOT NULL;

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

-- CONFIDENTIALITY, 2026-09-17. A row can be redacted by PROPAGATION (08 §11.4):
-- an annex duplicate of a redacted body row inherits is_redacted, but its own
-- supplier_name_raw still holds the name the publisher redacted elsewhere. Listed
-- naively, this review PRINTS THAT NAME. It did so on its first run after
-- propagation was added. Only names that are themselves redaction strings are
-- shown; any other redacted row is masked. Never paste an unmasked version of
-- this output into docs/, a README, an extract or any public artefact.

SELECT
  IF(REGEXP_CONTAINS(UPPER(COALESCE(supplier_name_raw, '')),
       r'REDACTED|REDACTION|PERSONAL INFORMATION|PERSONAL DATA|WITHHELD|NOT DISCLOSED|PRIVATE INDIVIDUAL|\bINDIVIDUAL\b|^PRIVATE$'),
     supplier_name_raw,
     '<name withheld: redacted by propagation>') AS supplier_name_shown,
  COUNT(*) AS n
FROM `portfolio-508106.portfolio_b.staging_spend`
WHERE is_redacted
GROUP BY supplier_name_shown
ORDER BY n DESC
LIMIT 50;
