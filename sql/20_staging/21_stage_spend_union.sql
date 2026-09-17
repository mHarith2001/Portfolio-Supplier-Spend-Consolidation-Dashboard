-- 21_stage_spend_union.sql
-- Layer: L2 staging_
-- Validation for this layer: sql/90_validation/92_validate_staging.sql
--
-- EXECUTED 2026-09-16; RE-EXECUTED 2026-09-17 with row_role. This is the
-- statement that ran.
--
-- RUN IT FROM A FILE ON STANDARD INPUT. At over 10,000 characters it exceeds the
-- Windows command-line limit, so pass it as `bq query ... < file`, not as an
-- argument.
--
-- RUN 22_normalise_names.sql FIRST. It defines normalise_name(), which this
-- statement calls. The numbering is from 06-repo-scaffold.md; the dependency
-- runs the other way.
--
-- Implements 08-transformation-guidelines.md §6 (date ladder), §8 (grant-in-aid),
-- §9 (is_undated), §10 (amount parsing) and §11 (padding, publisher_type,
-- amount_vat_basis, is_redacted, spend_id). Target schema: 03 §3.
--
-- GRAIN: one payment line. Unchanged from L1 — no aggregation happens here.
--
-- ===========================================================================
-- FOUR FINDINGS FROM THE SOURCE DATA THAT CHANGE HOW THIS IS WRITTEN
-- ===========================================================================
--
-- 1. `entity` IS THE PUBLISHER, AND IT IS NOT THE SOURCE `entity` COLUMN.
--    Measured across the six raw tables, the source body field holds:
--
--       bristol    body_name  = an Ordnance Survey URI, all 71,364 rows
--       york       body_name  = 'City of York Council'          OK
--       dft        entity     = 11 DIFFERENT BODIES — National Highways 17,133,
--                               'Department for Transport' only 7,186, plus HS2,
--                               MCA, DVLA, DVSA, British Transport Police, EWR,
--                               Active Travel England, VCA, Transport Focus
--       hmrc       entity     = 'HMRC'
--       manchester body_name  = 'Manchester City Council'       OK
--       moj        entity     = 'MoJ HQ'
--
--    Four of six do not carry the canonical publisher name at all. §8.3, §11.2,
--    §11.3 and the §6.5 reporting table ALL key on `entity` holding one of the
--    six canonical names. Using the source column would put 25,329 of DfT's
--    32,515 rows outside the `entity = 'Department for Transport'` test in §8.3,
--    and would drive publisher_type to NULL for four publishers, failing V2.12.
--
--    `entity` is therefore the PUBLISHER, set per source table as a literal.
--    The source body field remains available in Layer 1, which drops nothing.
--
-- 2. THE §11.1 PADDING FILTER AS WRITTEN REMOVES 9 ROWS TOO MANY.
--    §11.1's prose defines padding as rows "present in the CSV with every field
--    empty". Its SQL tests only three fields — supplier, amount, date. For
--    Ministry of Justice those are not the same set:
--
--       blank in supplier+amount+date        27
--       of which every field blank           18   <- provenance.blank_padding_rows
--       of which carry an annotation          9
--
--    The 9 carry publisher reconciliation notes in `department_family`:
--    'Exempt items', 'Bank Rec adjustments', 'Duplicate exempt transactions',
--    'On AP18 return - added to publish (to be cleared by SCS)' and similar.
--    All 9 are in Ministry_of_Justice__2025-01.csv. They are spreadsheet
--    footnotes the publisher left in the data — a data-quality finding of
--    exactly the kind §11.1's own note says to keep and report, not padding.
--
--    THE ALL-FIELDS TEST IS USED, and three independent controls confirm it:
--       provenance.blank_padding_rows   HMRC 12,201 · MOJ 18 · Manchester 2
--       V2.1                            352,614 retained
--       §10.5                           MOJ blank amounts = 10
--       §6.5                            MOJ unparsed dates = 34
--    The three-field test gives 12,230 / 352,605 and fails V2.1 by 9.
--
-- 3. BRISTOL PUBLISHES THREE UNLABELLED DESCRIPTION FIELDS.
--    Its CSV header is literally `Description 1,Description 2,Description 3`.
--    The CONTENT is plainly type / area / detail —
--       1: 'Grants paid out'      2: 'Capital - Adaptations'
--       3: 'Mandatory D F G´s - Adaptations'
--    so they are mapped to expense_type_raw / expense_area_raw / description.
--    LABELLED INFERENCE, accepted 2026-09-17: this is the builder's reading of
--    fields the publisher did not label — an inference from their content, not
--    a claim the specification makes.
--    03 §3 marks these columns 'Publisher vocabulary, not harmonised', so they
--    are not comparable across publishers by design — but if the reading is
--    rejected, the alternative is all three into `description` and NULL type and
--    area for Bristol. Nothing else in the pipeline depends on the choice.
--
-- 4. NOT EVERY ROW IS A PAYMENT — row_role, ADDED 2026-09-17 (08 §11.6).
--    Publishers leave spreadsheet totals, section subtotals and reconciliation
--    workings in the published files. They carry amounts, so they are summed,
--    and because the inflation is IN THE SOURCE it reconciles perfectly at
--    every layer. A double-count that reconciles is invisible to a
--    reconciliation.
--
--    row_role classifies every row; rows are RETAINED, never deleted, and every
--    aggregation keys on row_role = 'transaction'. V2.1 stays 352,614.
--
--      file_total           last row of a file equal to the sum of every other
--                           row in it, to the penny. NAME-INDEPENDENT: MOJ
--                           2024-04's total carries a label in the supplier
--                           column that an unnamed-only test cannot see.
--      section_total        unnamed subtotal inside an anchored workbook
--      section_header       no supplier, no amount, inside an anchored workbook
--      reconciliation       from the file's own marker to its stack row
--      annex_duplicate      named row after the stack row, re-listing a body row
--      out_of_scope_section body section whose label is not 'Publish'. An EIGHTH
--                           value, added at build: the ruling excluded the Exempt
--                           and Bank rec sections from aggregation and none of the
--                           seven ruled roles describes them.
--      trailing_artefact    unnamed last row equal to the nearest named row above
--      transaction          everything else
--
--    WORKBOOK ANCHOR. A file is a workbook only if it carries its own
--    'Reconciliation to stack:' marker. No file or row is hard-coded: a future
--    month with the same marker is classified by the same rules, and V2.9b in
--    92_validate_staging.sql reports every anchored file. MOJ 2025-01's
--    transaction scope is its 'Publish' section: the 344 rows, GBP 88,590,412.23,
--    that the publisher's own label states.
--
--    REDACTION PROPAGATES. An annex_duplicate matching a redacted body row on
--    amount and expense type inherits is_redacted = TRUE. MOJ 2025-01 publishes
--    one payee as REDACTED in its body and repeats the payment WITH THE NAME in
--    its annex.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.staging_spend` AS
WITH src AS (

  -- ---- Bristol City Council ------------------------------------------------
  SELECT
    'Bristol City Council' AS entity,
    payment_date_src, description_1 AS expense_type_src, description_2 AS expense_area_src,
    supplier_name_src, CAST(NULL AS STRING) AS supplier_postcode_src,
    amount_src, transaction_number, description_3 AS description_src,
    _source_file, _row_num,
    (SELECT COUNTIF(COALESCE(TRIM(v), '') != '') FROM UNNEST([
       body, body_name, supplier_name_src, amount_src, payment_date_src,
       transaction_number, description_1, description_2, description_3]) v) AS non_blank_fields
  FROM `portfolio-508106.portfolio_b.raw_spend_bristol`

  -- ---- City of York Council ------------------------------------------------
  UNION ALL SELECT
    'City of York Council',
    payment_date_src, subjective_detail, department,
    supplier_name_src, CAST(NULL AS STRING),
    amount_src, transaction_number, CAST(NULL AS STRING),
    _source_file, _row_num,
    (SELECT COUNTIF(COALESCE(TRIM(v), '') != '') FROM UNNEST([
       body_name, directorate, department, service_plan, supplier_name_src,
       payment_date_src, transaction_number, card_transaction, amount_src,
       irrecoverable_vat_src, subjective_group, subjective_subgroup,
       subjective_detail]) v)
  FROM `portfolio-508106.portfolio_b.raw_spend_york`

  -- ---- Department for Transport --------------------------------------------
  UNION ALL SELECT
    'Department for Transport',
    payment_date_src, expense_type, expense_area,
    supplier_name_src, supplier_postcode_src,
    amount_src, transaction_number, description_1,
    _source_file, _row_num,
    (SELECT COUNTIF(COALESCE(TRIM(v), '') != '') FROM UNNEST([
       department_family, entity, payment_date_src, expense_type, expense_area,
       supplier_name_src, transaction_number, description_1, amount_src,
       supplier_postcode_src]) v)
  FROM `portfolio-508106.portfolio_b.raw_spend_dft`

  -- ---- HM Revenue and Customs ----------------------------------------------
  UNION ALL SELECT
    'HM Revenue and Customs',
    payment_date_src, expense_type, expense_area,
    supplier_name_src, supplier_postcode_src,
    amount_src, transaction_number, description_1,
    _source_file, _row_num,
    (SELECT COUNTIF(COALESCE(TRIM(v), '') != '') FROM UNNEST([
       department_family, entity, payment_date_src, expense_type, expense_area,
       supplier_name_src, transaction_number, amount_src, description_1,
       supplier_postcode_src, supplier_type, contract_number, project_code,
       expenditure_type]) v)
  FROM `portfolio-508106.portfolio_b.raw_spend_hmrc`

  -- ---- Manchester City Council ---------------------------------------------
  -- business_area is present in only some months (25,351 of 107,223 rows) and
  -- is a different axis from service_area. It stays in Layer 1.
  UNION ALL SELECT
    'Manchester City Council',
    payment_date_src, expense_type, service_area,
    supplier_name_src, CAST(NULL AS STRING),
    amount_src, transaction_number, CAST(NULL AS STRING),
    _source_file, _row_num,
    (SELECT COUNTIF(COALESCE(TRIM(v), '') != '') FROM UNNEST([
       body_name, business_area, service_area, expense_type, payment_date_src,
       transaction_number, supplier_name_src, amount_src]) v)
  FROM `portfolio-508106.portfolio_b.raw_spend_manchester`

  -- ---- Ministry of Justice -------------------------------------------------
  UNION ALL SELECT
    'Ministry of Justice',
    payment_date_src, expense_type, expense_area,
    supplier_name_src, CAST(NULL AS STRING),
    amount_src, transaction_number, description_1,
    _source_file, _row_num,
    (SELECT COUNTIF(COALESCE(TRIM(v), '') != '') FROM UNNEST([
       department_family, entity, payment_date_src, expense_type, expense_area,
       supplier_name_src, transaction_number, amount_src, description_1]) v)
  FROM `portfolio-508106.portfolio_b.raw_spend_moj`
),

parsed AS (
  SELECT
    -- §11.5 surrogate key. The | separator is not decorative: without it
    -- A1.csv row 23 and A.csv row 123 produce the same input and collide.
    TO_HEX(SHA256(CONCAT(_source_file, '|', _row_num))) AS spend_id,

    entity,

    -- §11.2. No ELSE: a typo in an entity literal must surface as a NULL that
    -- V2.12 catches, not be silently classified as 'local'.
    CASE entity
      WHEN 'Department for Transport'  THEN 'central'
      WHEN 'HM Revenue and Customs'    THEN 'central'
      WHEN 'Ministry of Justice'       THEN 'central'
      WHEN 'Bristol City Council'      THEN 'local'
      WHEN 'City of York Council'      THEN 'local'
      WHEN 'Manchester City Council'   THEN 'local'
    END AS publisher_type,

    -- §6.3 date ladder.
    --
    -- DEFECT FOUND AND FIXED 2026-09-16 — rung 1 needed a shape guard.
    -- §6.2 warns that %d/%m/%y must not precede %d/%m/%Y, or a 4-digit year is
    -- misread. That hazard does not actually fire: PARSE_DATE requires a full
    -- match, so '%d/%m/%y' on 01/03/2024 leaves '24' unconsumed and FAILS,
    -- falling through correctly.
    --
    -- THE REAL HAZARD IS THE EXACT OPPOSITE, AND IT IS SILENT:
    --     SAFE.PARSE_DATE('%d/%m/%Y', '01/03/24')  ->  0024-03-01
    -- %Y accepts a two-digit year and returns a valid date in the year 24 AD.
    -- Rung 1 therefore swallowed all 4,451 Ministry of Justice dd/mm/yy dates
    -- before rung 7 was ever reached. They did not fail, so is_undated stayed
    -- FALSE and every row looked perfectly dated — while sitting 2,000 years
    -- outside the analysis window. Measured: MOJ min(payment_date) = 0024-02-01
    -- and 4,451 rows before 2000-01-01.
    --
    -- Caught by the §9.6 window baseline: in-window came out at 285,544 against
    -- a required 289,990, a shortfall of 4,446. That check earned its place.
    --
    -- The guard makes rung 1 match only its own shape. Order is unchanged.
    COALESCE(
      CASE WHEN REGEXP_CONTAINS(TRIM(payment_date_src), r'^\d{1,2}/\d{1,2}/\d{4}$')
           THEN SAFE.PARSE_DATE('%d/%m/%Y', TRIM(payment_date_src)) END,
      DATE(SAFE.PARSE_DATETIME('%d/%m/%Y %H:%M', TRIM(payment_date_src))),
      DATE(SAFE.PARSE_DATETIME('%d/%m/%Y %H:%M:%S', TRIM(payment_date_src))),
      SAFE.PARSE_DATE('%d-%b-%y', TRIM(payment_date_src)),
      SAFE.PARSE_DATE('%d-%b-%Y', TRIM(payment_date_src)),
      SAFE.PARSE_DATE('%Y-%m-%d', TRIM(payment_date_src)),
      SAFE.PARSE_DATE('%d/%m/%y', TRIM(payment_date_src)),
      -- Excel serial, MOJ Jan 2025. Epoch 1899-12-30 verified against the
      -- file's own reporting month (§6.4); the ^\d{5}$ guard stops a 5-digit
      -- transaction number in a date column becoming a plausible date.
      CASE WHEN REGEXP_CONTAINS(TRIM(payment_date_src), r'^\d{5}$')
           THEN DATE_ADD(DATE '1899-12-30',
                         INTERVAL CAST(TRIM(payment_date_src) AS INT64) DAY)
      END
    ) AS payment_date,

    payment_date_src AS payment_date_raw,
    NULLIF(TRIM(expense_type_src), '') AS expense_type_raw,
    NULLIF(TRIM(expense_area_src), '') AS expense_area_raw,

    supplier_name_src AS supplier_name_raw,
    `portfolio-508106.portfolio_b.normalise_name`(supplier_name_src) AS supplier_name_norm,

    NULLIF(TRIM(supplier_postcode_src), '') AS supplier_postcode,
    CAST(NULL AS STRING) AS vat_number,   -- no publisher supplies one; 03 §3 nullable

    -- §10.3 amount. The parenthesis test MUST come first: strip before testing
    -- and the brackets are gone and the sign with them. MOJ's 19 accounting
    -- negatives are GBP 2,766,216.08, so a wrong sign swings the total by
    -- GBP 5,532,432.16 and still looks plausible.
    CASE
      WHEN REGEXP_CONTAINS(TRIM(amount_src), r'^\(.*\)$')
        THEN -1 * SAFE_CAST(REGEXP_REPLACE(TRIM(amount_src), r'[^0-9.]', '') AS NUMERIC)
      ELSE SAFE_CAST(REGEXP_REPLACE(TRIM(amount_src), r'[^0-9.\-]', '') AS NUMERIC)
    END AS amount,

    -- §11.3. All six publish net of recoverable VAT, inclusive of irrecoverable.
    -- code_basis = the mandated basis with no stated departure found, which is
    -- an inference and is disclosed as such; confirmed = evidenced in the file.
    CASE entity
      WHEN 'City of York Council'    THEN 'net_plus_irrecoverable_confirmed'
      WHEN 'Manchester City Council' THEN 'net_plus_irrecoverable_confirmed'
      ELSE 'net_plus_irrecoverable_code_basis'
    END AS amount_vat_basis,

    -- §11.4, TIGHTENED 2026-09-16 after running the review §11.4 requires.
    --
    -- The pattern as specified —
    --   REDACT|PERSONAL INFORMATION|WITHHELD|NOT DISCLOSED|INDIVIDUAL|PRIVATE
    -- flagged 14 REAL TRADING NAMES across 186 rows, not just the one the spec
    -- names. Every one would have gone to tier 5 reason 'redacted' and been
    -- removed from matching entirely:
    --
    --   PRIVATE  as a bare substring caught  Streamline Taxi & Private Car Hire
    --            (48), Tiddlywinks Private Day Nursery (46+1), Diamonds
    --            Property Development Private Ltd (34), ANGEL HOME CARE SERVICE
    --            PRIVATE (15), Hastings Private Hire (13), Private Public Ltd
    --            (4), Taylor Private Hire (4), HAGUE CONFERENCE ON PRIVATE
    --            INTERNATIONAL LAW (1)
    --   REDACT   caught  Redactive Publishing Limited (8), Redactive Publishing
    --            Ltd (6), Redactive Events Ltd (3), REDACTIVE (1)
    --   INDIVIDUAL caught  P Bixby T/A Constructive Individuals Ltd (2)
    --
    -- The tightened pattern matches the redaction IDIOM rather than a substring:
    -- REDACTED/REDACTION rather than REDACT (so REDACTIVE is not a match),
    -- PRIVATE only as a whole name or in PRIVATE INDIVIDUAL, and INDIVIDUAL
    -- only as a whole word (so INDIVIDUALS is not a match).
    --
    -- Verified against every distinct name the original pattern flagged: all 5
    -- genuine redaction strings still flag, all 14 trading names no longer do.
    -- Exclusions recorded in docs/validation_report.md as §11.4 requires.
    REGEXP_CONTAINS(UPPER(COALESCE(supplier_name_src, '')),
      r'REDACTED|REDACTION|PERSONAL INFORMATION|PERSONAL DATA|WITHHELD|NOT DISCLOSED|PRIVATE INDIVIDUAL|\bINDIVIDUAL\b|^PRIVATE$'
    ) AS is_redacted,

    -- §8.3. Requires entity to be the publisher — see finding 1.
    CASE WHEN entity = 'Department for Transport'
          AND TRIM(expense_type_src) = 'Grt Aid to NDPBs'
         THEN TRUE ELSE FALSE END AS is_grant_in_aid,

    NULLIF(TRIM(transaction_number), '') AS transaction_number,
    NULLIF(TRIM(description_src), '')    AS description,
    _source_file,
    _row_num
  FROM src
  -- §11.1 padding removal, all six publishers. A row is padding only when EVERY
  -- source field is blank. See finding 2.
  WHERE non_blank_fields > 0
),

-- ===========================================================================
-- row_role — 08 §11.6. See finding 4.
-- ===========================================================================
rr_flags AS (
  SELECT
    s.*,
    SAFE_CAST(s._row_num AS INT64) AS rr_rn,
    COALESCE(TRIM(s.supplier_name_raw), '') = '' AS rr_no_name,
    (COALESCE(TRIM(s.supplier_name_raw), '') = '' AND NOT s.is_redacted AND s.amount IS NOT NULL) AS rr_unnamed_amt
  FROM parsed s
),

-- ---- Workbook anchor: a file that carries its OWN reconciliation marker ----
-- Not a hard-coded file or row. Any future file with the same marker is
-- classified by the same rules, and V2.9b reports every anchored file.
rr_marker AS (
  SELECT _source_file, MIN(rr_rn) AS recon_rn
  FROM rr_flags
  WHERE UPPER(TRIM(supplier_name_raw)) = 'RECONCILIATION TO STACK:'
  GROUP BY _source_file
),
rr_anchor AS (
  SELECT m._source_file, m.recon_rn, MIN(f.rr_rn) AS stack_rn
  FROM rr_marker m
  JOIN rr_flags f
    ON f._source_file = m._source_file
   AND f.rr_rn > m.recon_rn
   AND REGEXP_CONTAINS(UPPER(TRIM(f.supplier_name_raw)), r'\bSTACK$')
  GROUP BY m._source_file, m.recon_rn
),
rr_wb AS (
  SELECT f.*, a.recon_rn, a.stack_rn,
    -- body section index: 1 + number of body section totals strictly above this row
    1 + COALESCE(COUNTIF(f.rr_rn < a.recon_rn AND f.rr_unnamed_amt) OVER (
          PARTITION BY f._source_file ORDER BY f.rr_rn
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS body_section_k
  FROM rr_flags f
  JOIN rr_anchor a USING (_source_file)
),
-- the publisher's own section labels, in order, between the marker and the stack row
rr_labels AS (
  SELECT _source_file, UPPER(TRIM(supplier_name_raw)) AS label, amount AS label_amount,
         ROW_NUMBER() OVER (PARTITION BY _source_file ORDER BY rr_rn) AS section_k
  FROM rr_wb
  WHERE rr_rn > recon_rn AND rr_rn < stack_rn AND NOT rr_no_name AND amount IS NOT NULL
),
rr_publish AS (
  SELECT _source_file, section_k AS publish_k FROM rr_labels WHERE label = 'PUBLISH'
),
rr_wb_role AS (
  SELECT w._source_file, w.rr_rn,
    CASE
      WHEN w.rr_rn < w.recon_rn THEN
        CASE
          WHEN w.rr_unnamed_amt                        THEN 'section_total'
          WHEN w.rr_no_name AND w.amount IS NULL       THEN 'section_header'
          WHEN w.body_section_k = p.publish_k          THEN 'transaction'
          ELSE                                              'out_of_scope_section'
        END
      WHEN w.rr_rn <= w.stack_rn                       THEN 'reconciliation'
      WHEN w.rr_unnamed_amt                            THEN 'section_total'
      WHEN w.rr_no_name AND w.amount IS NULL           THEN 'section_header'
      ELSE                                                  'annex_duplicate'
    END AS wb_role
  FROM rr_wb w
  LEFT JOIN rr_publish p USING (_source_file)
),
-- redaction propagates to an annex duplicate of a redacted body row
rr_redact AS (
  SELECT DISTINCT a._source_file, a.rr_rn
  FROM rr_wb a
  JOIN rr_wb_role ar ON ar._source_file = a._source_file AND ar.rr_rn = a.rr_rn
  JOIN rr_wb b
    ON b._source_file = a._source_file
   AND b.rr_rn < b.recon_rn
   AND b.is_redacted
   AND b.amount = a.amount
   AND b.expense_type_raw = a.expense_type_raw
  WHERE ar.wb_role = 'annex_duplicate' AND NOT a.is_redacted
),

-- ---- Non-workbook files: file totals and trailing artefacts ----
-- file_total is NAME-INDEPENDENT: the file's last row, whose amount equals the
-- sum of every other row in the file to the penny. MOJ 2024-04 row 503 is a
-- NAMED total ('Publish total after adding in AP18 Reconciliation missing
-- items') that an unnamed-only test cannot see.
rr_file AS (
  SELECT _source_file,
    ROUND(SUM(amount), 2) AS file_sum,
    MAX(rr_rn) AS last_rn
  FROM rr_flags
  GROUP BY _source_file
),
rr_prev AS (
  SELECT _source_file, rr_rn,
    LAST_VALUE(IF(NOT rr_no_name, amount, NULL) IGNORE NULLS) OVER (
      PARTITION BY _source_file ORDER BY rr_rn
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_named_amount
  FROM rr_flags
),
rr_classified AS (
  SELECT
    f.* EXCEPT (rr_rn, rr_no_name, rr_unnamed_amt, is_redacted),
    (f.is_redacted OR r.rr_rn IS NOT NULL) AS is_redacted,
    CASE
      WHEN w.wb_role IS NOT NULL                                        THEN w.wb_role
      WHEN f.rr_rn = x.last_rn AND f.amount IS NOT NULL AND f.amount != 0
           AND ROUND(f.amount - (x.file_sum - f.amount), 2) = 0          THEN 'file_total'
      WHEN f.rr_unnamed_amt AND f.rr_rn = x.last_rn
           AND f.amount = pv.prev_named_amount                          THEN 'trailing_artefact'
      ELSE                                                                   'transaction'
    END AS row_role
  FROM rr_flags f
  LEFT JOIN rr_wb_role w ON w._source_file = f._source_file AND w.rr_rn = f.rr_rn
  LEFT JOIN rr_redact  r ON r._source_file = f._source_file AND r.rr_rn = f.rr_rn
  LEFT JOIN rr_file    x ON x._source_file = f._source_file
  LEFT JOIN rr_prev   pv ON pv._source_file = f._source_file AND pv.rr_rn = f.rr_rn
)

SELECT
  *,
  -- §9.1. Derived from payment_date so it cannot disagree with the ladder.
  (payment_date IS NULL) AS is_undated
FROM rr_classified;
