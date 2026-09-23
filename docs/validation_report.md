# BigQuery Engine Validation Report

**Verification Date:** 2026-08-29  
**Engine:** Google BigQuery (`portfolio-b-spend` / `portfolio_b`)  
**Specification Reference:** `08-transformation-guidelines.md` (§4)

---

## 1. Objective
Verify that Google BigQuery function behavior strictly matches specifications defined in §4 of the Transformation Guidelines prior to executing downstream SQL transformations (Rules 1, 2, 3, 4, and 7).

---

## 2. Test Execution Query

```sql
SELECT
  SAFE.PARSE_DATE('%d/%m/%Y',    '01/03/2024')            AS t1_ddmmyyyy,
  SAFE.PARSE_DATE('%d/%m/%y',    '01/03/24')              AS t2_ddmmyy,
  SAFE.PARSE_DATE('%d-%b-%y',    '01-Mar-24')             AS t3_ddMonyy,
  SAFE.PARSE_DATETIME('%d/%m/%Y %H:%M', '01/03/2024 00:00') AS t4_datetime,
  SAFE.PARSE_DATE('%d/%m/%Y',    'not a date')            AS t5_should_be_null,
  DATE_ADD(DATE '1899-12-30', INTERVAL 45659 DAY)         AS t6_excel_serial,
  LPAD('7140006', 8, '0')                                 AS t7_padded,
  REGEXP_REPLACE('  £465,000,000.00 ', r'[^0-9.\-]', '')  AS t8_stripped,
  SAFE_CAST('-1,258.14' AS NUMERIC)                       AS t9_should_be_null;
```

---

## 3. Results Verification Matrix

| Column | Required Result | Observed Result | Status | Dependency / Validation Target |
| :--- | :--- | :--- | :---: | :--- |
| `t1_ddmmyyyy` | `2024-03-01` | `2024-03-01` | **MATCH** | Date format elements in §6 |
| `t2_ddmmyy` | `2024-03-01` | `2024-03-01` | **MATCH** | Date format elements in §6 |
| `t3_ddMonyy` | `2024-03-01` | `2024-03-01` | **MATCH** | Manchester March file date parsing |
| `t4_datetime` | `2024-03-01T00:00:00` | `2024-03-01T00:00:00` | **MATCH** | York datetime string parsing |
| `t5_should_be_null` | `null` | `null` | **MATCH** | `SAFE.` prefix non-failing null behavior |
| `t6_excel_serial` | `2025-01-02` | `2025-01-02` | **MATCH** | Excel epoch offset calculation (§6.4) |
| `t7_padded` | `07140006` | `07140006` | **MATCH** | Company number zero-padding (§7) |
| `t8_stripped` | `465000000.00` | `465000000.00` | **MATCH** | Amount cleaning regex (§10) |
| `t9_should_be_null` | `null` | `null` | **MATCH** | Confirms commas must be stripped prior to casting |

---

## 4. Conclusion & Engine Verification

- **Total Tests:** 9
- **Passed:** 9
- **Failed:** 0
- **Engine Status:** **VERIFIED** — Google BigQuery behaves as specified. Output evidence confirms readiness for Phase 3 SQL pipeline execution.
---

## 5. Layer 1 validation — `V1.1`–`V1.5` and `V1.4a`

**Executed 2026-09-16** from `sql/90_validation/91_validate_raw.sql`. All HARD.
**Result: 6 rules run, 6 passed, 0 HARD failures. The L1 gate is closed.**

### 5.1 `V1.1` — row count per raw table vs source record count

| Table | Loaded | Expected | Delta | Result |
|---|---:|---:|---:|---|
| `raw_spend_bristol` | 71,375 | 71,375 | 0 | PASS |
| `raw_spend_york` | 124,803 | 124,803 | 0 | PASS |
| `raw_spend_dft` | 32,515 | 32,515 | 0 | PASS |
| `raw_spend_hmrc` | 23,759 | 23,759 | 0 | PASS |
| `raw_spend_manchester` | 107,223 | 107,223 | 0 | PASS |
| `raw_spend_moj` | 5,160 | 5,160 | 0 | PASS |
| `raw_companies_house` | 5,695,465 | 5,695,465 | 0 | PASS |

Spend total **364,835** = `provenance.records_csv_parsed` summed across 62 files.
These counts still include the 12,221 blank padding rows (HMRC 12,201, MOJ 18,
Manchester 2). Padding is removed at Layer 2, because Layer 1 drops nothing.

### 5.2 `V1.2` — no column dropped at load

| Table | Columns | Non-STRING |
|---|---:|---:|
| `raw_spend_bristol` | 14 | 0 |
| `raw_spend_dft` | 15 | 0 |
| `raw_spend_hmrc` | 19 | 0 |
| `raw_spend_manchester` | 13 | 0 |
| `raw_spend_moj` | 14 | 0 |
| `raw_spend_york` | 18 | 0 |

Every column matches the profiled source width, and every column is STRING — no
type was inferred at Layer 1.

### 5.3 `V1.3` — system columns non-null

All six spend tables return **0** for each of `_source_file`, `_source_url`,
`_retrieved_at`, `_period`, `_row_num`. PASS.

### 5.4 `V1.4` — `_row_num` unique within `_source_file`

All six spend tables return **0** duplicate `_source_file` + `_row_num` pairs. PASS.

### 5.5 `V1.4a` — per-file traceability (added 2026-09-16)

**62 files, 62 PASS, 0 failures.** For every file, the BigQuery row count equals
that file's own `provenance.records_csv_parsed`, and `_row_num` runs exactly
`1..N` with no gaps, no duplicates and nothing non-numeric.

`V1.4` alone cannot detect a uniformly renumbered file, nor a compensating error
where one file is over and another under, because `V1.1` reconciles only at
publisher level. `V1.4a` is what substantiates `E-1`'s claim that every row is
traceable to a physical line in a named file.

### 5.6 `V1.5` — Companies House loaded completely

| Measure | Value |
|---|---:|
| Table rows | 5,695,465 |
| Expected company records | 5,695,465 |
| CSV records (ratified) | 5,695,466 |
| Delta | 0 |

**Two quantities, both correct, and they differ by one blank line.** The seven
parts hold **5,695,466 CSV records** — a blank line is a record to `csv.reader`.
part4 record #454,676 is such a blank line (0 fields), and BigQuery does not
materialise an empty CSV line as a table row. The table therefore holds
**5,695,465 company records**, and a table row count can only be compared to
that figure.

Evidence: `docs/v1_5_part4_diagnostic.md`; an external table over the same GCS
objects anti-joined to the managed table on company number, returning exactly
one row absent from the table and that row carrying a NULL `CompanyNumber`; and
table metadata showing `creationTime == lastModifiedTime`, so the table has not
been modified since it was loaded.

**No reload was performed and no source file was altered.**

### 5.7 Finding carried to Layer 3 — `E-3`, settled benign

part4 record #454,675 contains an embedded newline inside
`PreviousName_10.CompanyName` of company `09056746`. The record has **55 fields
against a 55-field header** — a legitimate quoted newline. The record is intact,
no fields are shifted, no company is missing from the register, and tier-1
matching will not fail silently. No limitations-register entry is required.

### 5.8 Contracts Finder load — `08` §5.4

**Executed 2026-09-16** from `sql/10_raw/13_create_raw_contracts_finder.sql`.

| Measure | Value | Required |
|---|---:|---:|
| `raw_contracts_finder` rows | **76,449** | 76,449 |
| Columns | 9 | — |
| Non-STRING columns | **0** | 0 |

**The required figure was confirmed against the source before loading**, not
after. `q15-awards.csv` holds 76,450 physical lines; parsed with `csv.reader` it
yields **76,449 records**, every row 9 fields, **0 blank records and 0 embedded
newlines**. A physical line count is not a record count — the 9 DfT records
demonstrate that in this same project.

The file carries a UTF-8 BOM on its header line. It is harmless here because the
load uses an explicit schema with `skip_leading_rows=1`, so that line is
discarded. Under autodetect the first column would have been named with the BOM
attached, and every later reference to it would have failed invisibly.

`raw_contracts_finder` carries **no system columns**, for the same reason
`raw_companies_house` does not: it is a single-file reference load, not one of
the 62 per-period spend files. `V1.3` and `V1.4a` are scoped to the six spend
tables and this table is outside both by construction.

#### `E-3` known-answer subset — sizing the precision measurement

| Scheme | Releases | Distinct identifiers | Blank identifier |
|---|---:|---:|---:|
| `GB-COH` | 24,938 | 12,670 | 157 |
| *(none)* | 51,331 | — | 51,331 |
| `GB-CHC` | 175 | 153 | 0 |
| `GB-SC` | 4 | 4 | 0 |
| `GB-NIC` | 1 | 1 | 0 |
| **Total** | **76,449** | | |

**`E-3` is measured on the `GB-COH` subset carrying an identifier: 24,781
releases covering 12,670 distinct companies.** Two-thirds of Contracts Finder
releases (51,331) carry no supplier identifier at all, which is a property of
the source and not of the matching. **A precision figure quoted without the size
of the subset it was measured on is not a measurement**, so this table is the
denominator `docs/match_precision.md` must cite.

The operative measurement base is smaller still: it is the intersection of these
12,670 companies with suppliers actually appearing in the spend data, which is
not known until Layer 3.

### 5.9 Cloud storage — deleted 2026-09-16

`gs://portfolio-b-spend-mh2026/` and all **69 objects (2,941,913,742 bytes)** —
7 Companies House part CSVs and 62 clean spend CSVs — were deleted after
`V1.1`–`V1.5` and `V1.4a` all passed and `ext_ch_reconcile` was dropped.
**No bucket remains in the project.**

This closes `D-P-029` condition 2 and charter `L-3`: the full register carries
registered addresses that may be residential, and it does not persist in cloud
storage once loaded. Every deleted object was verified present on local disk
first; the 62 clean files are in any case regenerable by
`scripts/05_preload_clean.py`.

---

## 6. Layer 2 validation — `V2.1`–`V2.12`

**Executed 2026-09-16** from `sql/90_validation/92_validate_staging.sql` against
`staging_spend` built by `sql/20_staging/21_stage_spend_union.sql`.

| Rule | Severity | Required | Result |
|---|---|---:|---|
| `V2.1` row count | HARD | 352,614 | **PASS**, delta 0 |
| `V2.2` `spend_id` unique | HARD | 0 dupes | **PASS** |
| `V2.3` traces to L1 | HARD | 0 untraceable | **PASS** |
| `V2.4` unparsed dates | HARD | 46 | **PASS** |
| `V2.5` window split | SOFT | 289,990 / 62,578 | **PASS**, exact |
| `V2.6` unparsed amounts | HARD | 10 | **PASS** |
| `V2.8` `amount_vat_basis` | HARD | 2 permitted values | **PASS** |
| `V2.9` named payee on transactions | HARD | 0 | **PASS** — 0 unnamed transactions. See §6.5 and §6.8 |
| `V2.9a` file totals from amounts alone | HARD | 0 disagreements | **PASS** — 21 found = 21 flagged |
| `V2.9b` future-month re-check | HARD | 0 | **PASS** |
| `V2.9c` workbook integrity | HARD | ties | **PASS** |
| `V2.10` normalisation erasure | HARD | 0 | **PASS** |
| `V2.11` postcode format | SOFT | — | 4,562 of 44,073 invalid |
| `V2.12` `publisher_type` | HARD | 0 null | **PASS** |

### 6.1 Padding removal, per publisher — `08` §11.1 mandatory reporting

| Publisher | L1 rows | `staging_spend` | Padding removed |
|---|---:|---:|---:|
| HM Revenue and Customs | 23,759 | 11,558 | **12,201** |
| Ministry of Justice | 5,160 | 5,142 | **18** |
| Manchester City Council | 107,223 | 107,221 | **2** |
| Bristol City Council | 71,375 | 71,375 | 0 |
| City of York Council | 124,803 | 124,803 | 0 |
| Department for Transport | 32,515 | 32,515 | 0 |
| **Total** | **364,835** | **352,614** | **12,221** |

Each figure equals `provenance.blank_padding_rows` for that publisher.
**Publishing these counts is part of the rule**: a total that falls by 12,221
between layers is otherwise indistinguishable from a join that lost 12,221 rows.

**The §11.1 filter was corrected.** Its prose defines padding as every field
empty; its SQL tests only supplier, amount and date. For MOJ those differ — 27
rows are blank in the three fields but only **18 are blank in all fields**. The
other 9 carry publisher reconciliation notes in `department_family` ("Exempt
items", "Bank Rec adjustments", "Duplicate exempt transactions", "On AP18 return
- added to publish (to be cleared by SCS)" and similar), all in the 2025-01 file.
They are a data-quality finding, not padding. The all-fields test is used; the
three-field test yields 352,605 and fails `V2.1` by 9.

### 6.2 Date-ladder rejections — `08` §6.5 mandatory reporting

| Publisher | Rows | Unparsed | % |
|---|---:|---:|---:|
| Ministry of Justice | 5,142 | 34 | 0.6612 |
| Bristol City Council | 71,375 | 11 | 0.0154 |
| Manchester City Council | 107,221 | 1 | 0.0009 |
| City of York Council | 124,803 | 0 | 0 |
| Department for Transport | 32,515 | 0 | 0 |
| HM Revenue and Customs | 11,558 | 0 | 0 |
| **Total** | | **46** | |

`is_undated` agrees with the ladder on every row (0 disagreements).

### 6.3 A silent mis-dating defect in the §6.3 ladder, found and fixed

**`SAFE.PARSE_DATE('%d/%m/%Y', '01/03/24')` does not fail. It returns
`0024-03-01`.** `%Y` accepts a two-digit year, so rung 1 of the ladder consumed
all **4,451 Ministry of Justice `dd/mm/yy` dates** before rung 7 was reached.

Nothing failed to parse, so `is_undated` stayed FALSE and every one of those
rows looked correctly dated — while sitting roughly two thousand years outside
the analysis window. Measured before the fix: MOJ `MIN(payment_date)` =
`0024-02-01`, with 4,451 rows before `2000-01-01`.

§6.2 warns about the opposite ordering hazard. That one does not fire:
`PARSE_DATE` requires a full match, so `%d/%m/%y` on `01/03/2024` leaves `24`
unconsumed and correctly falls through.

**It was caught by the §9.6 window baseline**, which came out at 285,544 against
a required 289,990 — a shortfall of exactly 4,446. Rung 1 now carries a shape
guard (`^\d{1,2}/\d{1,2}/\d{4}$`); order is unchanged. After the fix the window
split is exactly 289,990 / 62,578 / 46 and no publisher has any date before 2000.

### 6.4 Redaction pattern exclusions — `08` §11.4 requires these recorded

The §11.4 pattern flagged **14 real trading names across 186 rows**, every one of
which would have gone to tier 5 reason `redacted` and been removed from matching:

| Excluded name | Rows | Matched on |
|---|---:|---|
| Streamline Taxi & Private Car Hire | 48 | `PRIVATE` |
| Tiddlywinks Private Day Nursery | 46 | `PRIVATE` |
| Diamonds Property Development Private Ltd | 34 | `PRIVATE` |
| ANGEL HOME CARE SERVICE PRIVATE | 15 | `PRIVATE` |
| Hastings Private Hire | 13 | `PRIVATE` |
| Redactive Publishing Limited | 8 | `REDACT` |
| Redactive Publishing Ltd | 6 | `REDACT` |
| Private Public Ltd | 4 | `PRIVATE` |
| Taylor Private Hire | 4 | `PRIVATE` |
| Redactive Events Ltd | 3 | `REDACT` |
| P Bixby T/A Constructive Individuals Ltd | 2 | `INDIVIDUAL` |
| HAGUE CONFERENCE ON PRIVATE INTERNATIONAL LAW | 1 | `PRIVATE` |
| REDACTIVE | 1 | `REDACT` |
| Tiddlywinks Private Day Nursery Easingwold | 1 | `PRIVATE` |

The pattern now matches the redaction **idiom** rather than a substring:
`REDACTED`/`REDACTION` rather than `REDACT`, `PRIVATE` only as a whole name or
within `PRIVATE INDIVIDUAL`, and `INDIVIDUAL` only as a whole word. Verified
against every distinct name the original flagged: all 5 genuine redaction
strings still flag, all 14 trading names no longer do.

**Result: 31,508 redacted rows across 5 distinct strings** — `Redacted Personal
Information` 25,355 · `REDACTED - PERSONAL DATA` 3,271 · `REDACTED` 2,540 ·
`REDACTED` (variant) 341 · `Name redacted` 1. Redaction rate 8.94%.

### 6.5 `V2.9` — a GBP 2.08bn double-count, found by scoping the rule

> **This section replaces an earlier version that recorded these 40 rows as
> "not a data error". That was wrong.** It was written before the rows were
> inspected, on the assumption that they were inert. Corrected 2026-09-16.

`V2.9` is scoped to rows **carrying an amount**: a row with neither a supplier
name nor an amount cannot participate in matching or aggregation. 9 rows fall
out of scope on that basis, all Ministry of Justice.

**The scoping did not make the rule pass. It made it point at something.**

| | Rows | Value |
|---|---:|---:|
| No supplier name, not redacted, **carrying an amount** | **31** | **GBP 2,084,055,613.01** |
| No supplier name, no amount — out of scope, inert | 9 | — |

**These are file total rows, and they are double-counting spend.** Proven, not
inferred: for 20 of the 22 affected files the unnamed row's amount equals the
sum of **every other row in the same file to the penny** — difference 0.00.

| Publisher | Files with a proven total row | Double-counted |
|---|---:|---:|
| Bristol City Council | 11 of 12 | GBP 733,176,703.99 |
| Ministry of Justice | 9 | GBP 1,022,864,893.02 |
| **Proven total** | **20** | **GBP 1,756,041,597.01** |

Each sits at its file's final `_row_num` — Bristol 2024-04 at row 6,727 of
6,727; 2024-05 at 6,574 of 6,574 — and MOJ's carry a `transaction_number`
exactly one below their `_row_num`. Bristol 2024-03 has no such row and shows a
difference of −70,277,619.67, confirming the test discriminates.

**Bristol's true spend is GBP 803,454,323.66, not the GBP 1,536,631,027.65 in
`staging_spend`.** Eleven of its twelve months are counted twice.

Two of the 22 are **not** totals and are excluded from the finding: Manchester
2024-04, a single unnamed credit of −GBP 529.52; and MOJ 2025-01, which holds 10
unnamed rows worth GBP 328,014,545.52 so the per-file test cannot isolate a
single total — it needs separate examination.

#### Why no other control would have caught it

**The inflation is in the source, so it reconciles perfectly at every layer.**
`V2.1` ties to provenance. `E-5` preserves `SUM(amount)` from L2 to L4 exactly as
required. Every total agrees with every other total. **A double-count that
reconciles is invisible to a reconciliation** — it would have passed the
completion gate and reached the dashboard as a headline figure roughly double
the truth for two publishers.

`V2.9` is the only rule in the suite that asks whether money has a **named
recipient**, and that is the single question that exposes this.

#### Not acted on at the time — resolved 2026-09-17, see §6.8

Excluding total rows is a **new exclusion rule**. It is not in `08` §11, and it
changes the published spend figure for two publishers by GBP 1.76bn. That is a
specification decision, not a builder's. `V2.9a`, the per-file total-row
detector, is committed in `92_validate_staging.sql` so the test is repeatable
and the evidence is not a one-off query.

> **Superseded 2026-09-17.** The ruling was to retain, flag and exclude, never delete.
> `row_role` implements it (§6.8). The 20 proven totals above became **21**: a
> name-independent test found a twenty-first total in Ministry of Justice 2024-04 that
> carries a label in its supplier column, which an unnamed-only test cannot see.

### 6.6 Amounts and Grant-in-Aid

| Publisher | Rows | Unparsed | Negative | Sum (GBP) |
|---|---:|---:|---:|---:|
| Bristol City Council | 71,375 | 0 | 1,069 | 1,536,631,027.65 |
| City of York Council | 124,803 | 0 | 2,215 | 532,545,696.76 |
| Department for Transport | 32,515 | 0 | 0 | 45,190,494,506.05 |
| HM Revenue and Customs | 11,558 | 0 | 393 | 2,282,004,549.81 |
| Manchester City Council | 107,221 | 0 | 5,202 | 1,247,793,286.58 |
| Ministry of Justice | 5,142 | 10 | 151 | 3,097,386,774.25 |

All 10 unparsed amounts are Ministry of Justice, as `08` §10.5 requires.
Negatives are **retained and counted** per `V2.7` — they are credits and
reversals. MOJ's 19 accounting-parenthesis negatives parse with the correct sign;
mis-parsed they would swing the total by GBP 5,532,432.16 while still looking
plausible.

**Grant-in-Aid (`D-P-022`, Option A per `D-P-028`): 59 rows, GBP
10,788,523,565.00, 23.87% of DfT's GBP 45,190,494,506.05.** Flagged and retained,
excluded from supplier concentration and cross-publisher rankings.

### 6.7 `amount_vat_basis` (`V2.8`)

`net_plus_irrecoverable_confirmed` 232,024 · `net_plus_irrecoverable_code_basis`
120,590. No NULL and no third value, so no entity string fell outside the
expected six. York's `Irrecoverable_VAT` column was independently confirmed
**empty in all 124,803 rows**, as `08` §11.3 states.

### 6.8 `row_role` — which rows are payments (`08` §11.6)

**Executed 2026-09-17.** Every staged row carries a `row_role`. **Rows are retained and
never deleted; every aggregation keys on `row_role = 'transaction'`.** `V2.1` stays
352,614.

| `row_role` | Detection | Rows | Value (GBP) |
|---|---|---:|---:|
| `file_total` | The file's last row equal to the sum of every other row, to the penny — name-independent | 21 | 1,841,069,862.61 |
| `reconciliation` | From a file's own `Reconciliation to stack:` marker to its stack row | 6 | 444,090,543.54 |
| `section_total` | Unnamed subtotal inside an anchored workbook | 9 | 179,984,364.34 |
| `out_of_scope_section` | Workbook body section whose label is not `Publish` | 16 | 59,439,768.95 |
| `annex_duplicate` | Change-log row re-listing a body transaction | 24 | 32,012,735.80 |
| `section_header` | No supplier, no amount, inside an anchored workbook | 9 | — |
| `trailing_artefact` | Unnamed last row equal to the nearest named row above | 1 | −529.52 |
| `transaction` | Everything else | 352,528 | 51,330,259,095.38 |

**Calculated result.** Excluded from aggregation: 86 rows, GBP 2,556,596,745.72 =
53,886,855,841.10 staged − 51,330,259,095.38 transactions. Of that, GBP 59,439,768.95 is
genuine Exempt and Bank rec entries excluded **by scope**; the remaining GBP
2,497,156,976.77 is not a payment at all.

| Publisher | Staged (GBP) | Transactions only (GBP) |
|---|---:|---:|
| Bristol City Council | 1,536,631,027.65 | **803,454,323.66** |
| Ministry of Justice | 3,097,386,774.25 | **1,273,966,203.00** |
| Manchester City Council | 1,247,793,286.58 | 1,247,793,816.10 |
| York, DfT, HMRC | unchanged | unchanged |

**Detection is not hard-coded.** No file or row number appears in the rules. `V2.9b`
re-checks every file on every run for a workbook marker or a labelled total among the
transactions, so a future month with either structure is caught before it is summed.

**All 46 undated rows are non-transaction rows** — 0 undated transactions. No payment line
lacks a date.

### 6.9 Ministry of Justice 2025-01 — a reconciliation workbook

The file publishes three body sections, each closed by a subtotal; a reconciliation block
restating them; and a seven-section change-log annex re-listing body transactions.

| `V2.9c` check | Result |
|---|---|
| Transactions = the publisher's own `Publish` label | 88,590,412.23 = 88,590,412.23 |
| Body rows = body section totals = the stack row | 148,030,181.18 three ways |
| Annex rows accounted for | 24 = 23 matched on transaction number and amount + 1 by redaction |

**Transaction scope: the 344 `Publish` rows, GBP 88,590,412.23**, the basis on which the
month is comparable with the Ministry's other eleven.

### 6.10 Reference tables — `staging_companies`, `staging_contracts`

| Control | Result |
|---|---|
| `V2.R1` companies reconcile | **PASS** — 5,695,465 raw − 93 rejected = 5,695,372 staged; every rejection is an `R` + 7-digit number |
| `V2.R2` `company_number` key | **PASS** — 0 null, 0 duplicate |
| `V2.R3` no company name erased | **PASS** — 0 |
| `V2.R4` contracts drop nothing | **PASS** — 76,449 = 76,449 |
| `V2.R5` `E-3` known answer | **PASS** — 24,507 rows, 11,593 companies |
| `V2.R6` recorded gap stays a gap | **PASS** — `award_value` and `classification` NULL on every row |
| `V2.R7` no supplier name erased | **PASS** — 0; 2 placeholder values counted (a lone `-` and a lone `.`) |
| `V2.R8` tier-1 reach | INFO — 11,097 of 11,593 known-answer companies are in the snapshot; **496 are not**, so tier 1 can reach at most 23,883 of 24,507 known-answer rows |

**`V2.R7` was refined after its first run.** As first written it failed on the two
placeholder values, which carry no name to erase. It now fails only when a value containing
a letter or digit normalises to empty. Recorded here because a control changed after
failing must say so.

**Recorded gaps, not filled.** Contracts Finder as acquired carries no award value and no
procurement classification; both columns are typed NULL. `award_date` is the award notice's
**release date** — an approximation, used by no match tier.

**Canonicalisation, both sides.** A pass-through rung for Companies House society and mutual
register numbers recovers 576 numbers the ladder rejected, with the Contracts Finder
figures proven unchanged (22,672 / 1,814 / 21 / 24,507 usable / 274 / distinct 11,593). The
93 `R` + 7-digit numbers are deliberately not covered: an `R` rung moves the Contracts
Finder figures by one record whose registered company is not the supplier named against it.

### 6.11 Confidentiality

One Ministry of Justice 2025-01 annex row repeats a payment the body publishes as REDACTED,
**with the payee's name**. Redaction now propagates to annex duplicates of redacted rows, so
that row never enters matching. The redaction review in `92_validate_staging.sql` masks any
row redacted by propagation — as first written, it printed the name. **No extract, table or
chart in this repository may select `supplier_name_raw` for an `is_redacted` row.**

---

## 7. Layer 3 — opened: tiers 1–3 (`93_validate_resolved.sql`)

> **§7 and §7.1 record the opening pass of 2026-09-17 and are superseded by §7.3
> onwards.** They are kept, not rewritten: the tier-1 count below (1,404 accepted) is
> the figure *before* the demotion rule of `04` §3 hard rule 6, and the difference
> between 1,404 and the final 1,172 is itself the evidence that the rule did
> something. A validation report that edits its own history proves nothing.

**Executed 2026-09-17. Layer 3 is open, not complete.** Tier 4, the matched-supplier
assembly, the golden record and `resolved_spend` are not built; `V3.1`–`V3.5`, `V3.7`,
`V3.9`, `V3.10` and `V3.12`–`V3.17` therefore have not run.

**Transactions only.** Every name entering matching comes from `row_role = 'transaction'`.
Redacted rows never enter matching (`04` §3 hard rule 4).

| Control | Result |
|---|---|
| `L3.0` name universe | **PASS** — 13,373 spend names, 0 duplicates, 0 missing; 13,003 `E-3` known-answer names alongside |
| Hard rules 2–3, `V3.6`, `V3.8`, `V3.11` at acceptance | **PASS** — tier 1: 1,404 accepted · tier 2: 13,488 · tier 3: 588; 0 ambiguous, 0 implausible, 0 orphan numbers in every tier |

### 7.1 Interim distribution — spend names, first match wins

| Tier | Names | Transaction rows | Value (GBP) |
|---|---:|---:|---:|
| 1 — company number, bridged | 1,404 | 58,883 | 4,646,004,115.19 |
| 2 — exact normalised name | 4,740 | 123,720 | 15,775,823,293.99 |
| 3 — name core + postcode | 42 | 1,190 | 10,095,056,684.98 |
| not yet resolved | 7,187 | 137,227 | 20,700,108,974.47 |

**Calculated result.** Rows 321,020 + 31,508 redacted = 352,528 transactions; value
51,216,993,068.63 + 113,266,026.75 redacted = GBP 51,330,259,095.38 — the transaction total
exactly. **"Not yet resolved" is a work queue for tier 4, not a finding.**

### 7.2 Findings that shape what comes next

- **Tier 1 is a bridge.** Spend rows carry no company number, so a spend supplier reaches a
  buyer-stated number only where its normalised name equals a Contracts Finder name that
  carries one. Of 1,404 accepted tier-1 names, **232 are registered under a different
  normalised name** than the supplier's. 132 names were rejected as ambiguous and 26 because
  the stated number is not in the register.
- **Tier 3 can re-introduce the `LTD`/`PLC` conflation `04` §2 exists to prevent**, because its
  key ignores the legal suffix. Of 42 tier-3 names, 36 (GBP 10,046,822,210.84) carry no suffix
  in the spend file — the case tier 3 is for. **4 names (GBP 39,014,117.12) carry a suffix that
  conflicts with the matched company's**, such as a `PLC` or `LLP` supplier matched to a
  `LIMITED` company.
- **Tier 4 is computationally feasible.** First-token blocking gives 11,048 names and
  12,697,337 candidate pairs; the largest block holds 31,189 companies.

### 7.3 Layer 3 complete — `V3.1`–`V3.17` all PASS (2026-09-18)

Executed by `93_validate_resolved.sql` after `34`, `35` and `36`. Every HARD control
prints its verdict beside the numbers it was computed from.

| Control | Result |
|---|---|
| `L3.0` name universe | **PASS** — 13,373 spend names, 0 duplicates, 0 missing |
| `V3.1` row count preserved | **PASS** — 352,614 → 352,614 |
| `V3.2` `SUM(amount)` preserved | **PASS** — GBP 53,886,855,841.10 both layers |
| `V3.3` every transaction row keyed | **PASS** — 0 transaction rows without a key, 0 non-transaction rows with one |
| `V3.4` one row per name | **PASS** — 13,377 names, 13,377 rows, 0 missing |
| `V3.5` tier/method agree | **PASS** — 0 mismatches |
| `V3.6` no ambiguous acceptance | **PASS** — 0 in every tier |
| `V3.7` no high-confidence tier 4 | **PASS** — 0 |
| `V3.8` no payment before incorporation | **PASS** — 0 of 175,470 attributed rows |
| `V3.9` redacted rows are tier 5 | **PASS** — 31,508 rows, 4 names, 0 wrong |
| `V3.10` every tier 5 states a reason | **PASS** — 0 without |
| `V3.11` no orphan company number | **PASS** — 0 |
| `V3.12` dissolved matches | **INFO — structurally unobservable, see §7.6** |
| `V3.13` `supplier_key` unique | **PASS** — 13,363 rows, 0 duplicates |
| `V3.14` `company_number` unique among resolved | **PASS** — 0 duplicates |
| `V3.15` `name_variant_count` correct | **PASS** — recomputed from `resolved_spend`, 0 disagreements |
| `V3.16` resolved `legal_name` from Companies House | **PASS** — 0 exceptions |
| `V3.17` unresolved carry no number | **PASS** — 0 |

**The name universe is 13,377, not 13,373.** The extra four are the redacted names,
which are held out of matching by `04` §3 hard rule 4 but still need a row in the audit
trail. Two quantities that look alike: names *entering matching* and names *needing a
verdict*.

### 7.4 The resolution profile — the figure the portfolio quotes

Transaction rows only (`row_role = 'transaction'`).

> **Re-measured 2026-09-18** after hard rule 3 was applied to tier 4 (§7.9). Tiers 1–3 are
> unchanged; 106 names moved from tier 4 to tier 5 because their only candidate was
> impossible. **The resolution claim does not move: 58.32%.**

| Tier | Supplier names | Transaction rows | Value (GBP) | % of value |
|---|---:|---:|---:|---:|
| 1 — company number | 1,172 | 50,129 | 3,981,459,526.06 | 7.76% |
| 1 — demoted, **accepted on recorded review** | 1 | 2,249 | 349,037,030.64 | 0.68% |
| 2 — exact normalised name | 4,758 | 124,303 | 15,846,552,637.36 | 30.87% |
| 3 — name core + postcode | 54 | 1,415 | 10,164,008,997.88 | 19.80% |
| 4 — fuzzy, **accepted on recorded review** | 1 | 120 | 870,427,482.80 | 1.70% |
| 4 — fuzzy, **review only, not resolved** | 1,214 | 41,070 | 2,216,774,873.40 | 4.32% |
| 5 — unresolved | 6,177 | 133,242 | 17,901,998,547.24 | 34.88% |

**Resolved is tiers 1–3: 5,981 names, GBP 29,935,699,821.14 — 58.32% of transaction
value.** Tier 4 is *not* counted as resolved anywhere in this project. Counting the still-unreviewed
queue would raise the total to 64.65% on the strength of 80.88% precision
(`docs/match_precision.md`) and no human review, which is the claim this build exists to avoid making.

**Why "unresolved" is published as loudly as "resolved":**

| Reason | Names | Value (GBP) |
|---|---:|---:|
| `no_match` — no candidate at any tier | 1,821 | 10,378,013,159.51 |
| `below_threshold` — best fuzzy score under 0.85 | 4,203 | 7,085,547,262.50 |
| `review` — tier-4 queue, decision pending | 1,214 | 2,216,774,873.40 |
| `ambiguous` — more than one candidate, or the register disagrees | 149 | 325,172,098.48 |
| `redacted` — payee withheld at source | 4 | 113,266,026.75 |

**A large unresolved share is expected and is not a defect.** Public bodies name
suppliers freely — departments, agencies, NHS trusts, councils, universities, charities
and individuals all appear, and **none of them are companies**, so no Companies House
method can ever reach them. `V3.12` in §7.6 shows a second, harder ceiling.

### 7.5 The golden record

**13,363 rows: 5,967 resolved entities and 7,396 unresolved buckets.** 5,981 matched
names collapse onto 5,967 companies — 14 names are alternative spellings of a company
another name already reached.

**The most-collapsed supplier carries 16 distinct raw spellings.** `name_variant_count`
was recomputed from `resolved_spend` by a different path than the one that built it
(`V3.15`), and agrees on every row.

Unresolved names keep their own key (`NAME|<normalised name>`) rather than being pooled
into one bucket or dropped. Every transaction row therefore carries a `supplier_key`, and
unresolved spend stays countable instead of disappearing from the total.

### 7.6 `V3.12` cannot be satisfied — and that is the finding

`V3.12` asks how much money went to companies the register calls **dissolved**. The
answer is structurally zero, because **the Companies House snapshot contains no dissolved
companies at all**:

| Status in the snapshot | Companies |
|---|---:|
| Active | 5,190,379 |
| Active – Proposal to Strike off | 388,951 |
| Liquidation | 108,791 |
| In Administration | 3,739 |
| 10 further insolvency states | 3,512 |

**Confirmed fact.** 14 distinct statuses, none of them `Dissolved`. The free
"basic company data" product is a snapshot of the *live* register.

Two consequences, both material:

1. **A supplier that has since dissolved can never be matched, at any tier.** Part of the
   `no_match` population is unreachable by construction, not by weak matching. The
   measured `E-3` precision is unaffected; recall carries this ceiling.
2. **`V3.12` should be restated** as *insolvency-state* matches, which the snapshot does
   carry and which the build does observe:

| Status of matched supplier | Suppliers | Transaction rows | Value (GBP) |
|---|---:|---:|---:|
| Active | 5,911 | 173,407 | 29,924,431,545.88 |
| Active – Proposal to Strike off | 43 | 1,260 | 4,165,339.25 |
| In Administration | 3 | 109 | 3,640,751.22 |
| Liquidation | 8 | 687 | 2,894,022.62 |
| Voluntary Arrangement | 2 | 7 | 568,162.17 |

**GBP 11,268,275.26 of public money reached 56 suppliers in an insolvency state** — a
finding a spend dashboard should surface rather than smooth over. Every one of those rows
is dated after the supplier's incorporation (`V3.8`).

### 7.7 The tier-1 demotion, published either way

`04` §3 hard rule 6: where a buyer states a company number whose *registered* name
disagrees with the supplier name, the match is demoted to review rather than accepted.

| | Names |
|---|---:|
| Tier 1 accepted | 1,172 |
| **Demoted to review** | **232** |
| Rejected — ambiguous | 132 |
| Rejected — number not in the register | 26 |
| Of the 232, later confirmed by tier 2 or 3 on their own evidence | 27 |
| Of the 232, still resolved at tier 1 | **0** |

The 27 are the rule working, not leaking: the demotion rejects *the buyer's assertion*,
not the name, so a name that independently matches the register by its own spelling is
still resolved. The remaining **205 enter the review queue**.

### 7.8 The review queue — `docs/review_queue.csv`

**1,351 rows, one per name, highest value first** (§7.15) — superseding the counts below: 1,215 tier-4 candidates, 204 demoted tier-1 names, and
1 decided name whose candidate was later withdrawn from matching (§7.14). Per `04` §8, plus `queue_reason` — because a reviewer looking at a row with no
`match_score` needs to know it arrived by demotion rather than by similarity — and, since
2026-09-18, `decision`, `decision_note` and `decided_on`.

**Decisions are recorded in `sql/30_resolved/38_queue_decisions.sql` as literals under
version control**, and joined in by the generator, so regenerating the queue never loses
them and every decision carries its reason. **Sixty rows are decided so far** — five by the user (§7.10–§7.13), fifty-five delegated (§7.15) — and a decided row stays in the queue; the rest
are blank, which remains the honest presentation.

The first row is `GREAT WESTERN RAILWAY` → `GREAT WESTERN RAILWAY LIMITED`, score 1.00,
GBP 1,645,099,386.59. It is **still queued**. That is the price of "tier 4 never
auto-accepts", paid visibly rather than argued away.

### 7.9 Hard rule 3 applied to tier 4 (2026-09-18)

**A rule that tiers 1–3 always enforced, and tier 4 never did.** A company incorporated
after the first payment cannot be the payee. Tier 4 was not applying that test, and **107 of
its 1,305 queued candidates were impossible on those grounds**, carrying GBP 64,259,806.06 —
one of them incorporated **2025-12-24**, after payments it supposedly received.

Nothing was ever mis-attributed, because tier 4 resolves nothing. What it meant was 107 queue
entries costing a reviewer time on a company that **cannot** be the payee.

The rule is applied as a filter on **candidates**, not on names, in
`34_match_tier4_fuzzy.sql` beside the suffix-conflict guard. The distinction is not
cosmetic: a name whose best candidate is impossible can still reach a plausible second-best
one.

| | Before | After |
|---|---:|---:|
| Tier-4 queue names | 1,305 | 1,199 |
| Queued value (GBP) | 3,309,114,953.18 | 3,244,886,577.86 |
| Impossible candidates remaining | 107 | **0** |
| Tier-4 precision (`E-3`) | 80.86% | 81.40% |
| Overall precision (`E-3`) | 95.25% | 95.32% |

> **The precision figures in this table were themselves measured under flawed blocking** and
> are superseded by §7.10. Kept because the rule change and the blocking change are separate
> events and collapsing them would hide which did what.

**106 names fell to tier 5, not 107** — one name found a plausible alternative candidate at
or above the threshold, which is the candidate-level filter behaving as designed.

**The resolution claim does not move.** Tiers 1–3 are untouched: 5,981 names,
GBP 29,935,699,821.14, **58.32%**. All 23 `V3`/`V4` controls were re-run after the rebuild
and every one still passes.

---

### 7.10 Tier-4 blocking corrected, and the first queue decision (2026-09-18)

**Found by working the queue, not by testing the code.** Queue row 1 —
`GREAT WESTERN RAILWAY` → `GREAT WESTERN RAILWAY LIMITED` (`01759457`), score 1.00,
`candidate_count` 1, GBP 1,645,099,386.59 — was put up for decision. The evidence
contradicted the score: the register holds **three** SIC 49100 passenger-rail companies in
that family, and `FIRST GREATER WESTERN LIMITED` (`05113733`) — the registered name behind
the trading name the payer used — had been **excluded from the comparison by first-token
blocking**. `candidate_count = 1` meant "one survived blocking", not "the register holds no
alternative".

**Row 1 was rejected** and returned to the queue, recorded with its reasoning in
`38_queue_decisions.sql`. No manual override was applied; the build has no mechanism for one,
and inventing one to rescue a single row would put GBP 1.65bn on a judgement the data cannot
support.

**The defect was systemic, so the fix came before any further queue work.** Blocking is now a
**prefix filter on frequency-ordered tokens**, which is *provably* lossless at the 0.5
candidate floor: if two names can reach the floor, their prefixes must intersect. Full
derivation in `34_match_tier4_fuzzy.sql` and `04` §3.1.

| | First token | Prefix filter |
|---|---:|---:|
| Candidate pairs considered | 99,930 scored | 86,927,511 → **997,229 scored** |
| Names with any candidate | 7,513 | **8,922** |
| Names above threshold | 2,672 | **2,716** |
| **Ambiguous above threshold** | 61 | **102** |
| Names unreachable by blocking | 608 (GBP 450,408,335.70) | **282 (GBP 181,361,789.01)** |
| Tier-4 precision (`E-3`) | 81.40% | **80.88%** |
| Overall precision (`E-3`) | 95.32% | **95.25%** |
| Recall (`E-3`) | 84.42% | **84.50%** |

**Precision fell, and the method improved.** 81.40% was measured with register rivals hidden
from the comparison; 80.88% is measured with a guarantee that none were. A number that gets
better when you stop looking at the competition was never a measurement of accuracy.

**`candidate_count` was understating ambiguity by a factor of about 1.7** — 61 flagged
ambiguous against 102 truly ambiguous. That is now recorded in `04` §3.1 and in the queue's
own documentation, because a reviewer reads `1` as "no alternatives exist".

**What the correction did not do:** row 1 still shows `candidate_count = 1`, because
`FIRST GREATER WESTERN` shares one token of five and scores **0.20** — below the candidate
floor. It is now compared and correctly rejected. A trading name that shares few tokens with
its registered name is beyond token-set similarity, which is a limit of the scoring function
and precisely why tier 4 is reviewed rather than merged.

**Unchanged by all of it: the resolution claim.** Tiers 1–3 are untouched — 5,981 names,
GBP 29,935,699,821.14, **58.32%** — and all 23 `V3`/`V4` controls were re-run after the
rebuild with **0 FAIL**.

### 7.11 The first accept, and how a decision takes effect (2026-09-18)

**Queue row 2 approved:** `WEST MIDLANDS TRAINS` → `WEST MIDLANDS TRAINS LIMITED`
(`09860466`), GBP 870,427,482.80.

**The basis recorded is corroboration, not the score.** The same payer also writes this
supplier as `West Midlands Trains Limited` and `West Midlands Trains Ltd`, and that longer
spelling already resolves at **tier 2, high confidence, to `09860466`**. The payer's own
files bridge the short form to the company independently of any fuzzy matching. The score
— 1.00 against 99 rivals all at 0.50 under the corrected blocking — supports the decision;
it is not the reason for it.

**How a decision now takes effect.** An accepted row resolves its name, with
`match_confidence = 'reviewed'`, **only if the accepted company is still the tier-4
candidate**. A rebuild that changes the candidate makes the decision stale: it is not
applied, it is flagged, and `93`'s new `D.1`–`D.4` controls fail until someone looks again.
An approval is of a specific company, never of a name in general.

The resolved/unresolved verdict is computed **once**, as `is_resolved` in
`resolved_supplier_match`, and the golden record, `resolved_spend` and `dim_supplier` all
read it. One predicate, not four copies of it waiting to disagree.

**The resolution claim, by basis** — reported separately so that one kind of evidence never
borrows the other's credibility:

| Basis | Names | Value (GBP) | % of value |
|---|---:|---:|---:|
| **Method** — tiers 1–3 | 5,981 | 29,935,699,821.14 | **58.32%** |
| **Reviewed** — tier 4 accepted on a recorded decision | 1 | 870,427,482.80 | **1.70%** |
| **Total resolved** | **5,982** | **30,806,127,303.94** | **60.02%** |
| Unresolved | 7,395 | 20,524,131,791.44 | 39.98% |

**`E-3` did not move** — 95.25% precision, 84.50% recall, tier 4 80.88%. Decisions change
what is resolved; they never touch the measurement of the method, which `95` takes from the
method's own tables.

**What moved:** the golden record fell from 13,363 rows to **13,362** — the short spelling's
unresolved bucket merged into the existing `09860466` entity, which now carries **3 raw
spellings** — and `fact_spend` rose from 175,470 rows to **175,590**. `V4.1` still reconciles
to the penny: 352,528 rows, GBP 51,330,259,095.38, difference 0.00. All `V3`, `V4` and
`D` controls pass.

**One defect the accept exposed, and fixed:** the review queue looked its labels up through
the golden record's `NAME|` key, and an accepted name no longer has one — it merges into the
company's `CH|` key. The first regeneration blanked the label of exactly the row just decided.
Labels now come from the spend files directly (`37`), and the regenerated queue has **0**
empty labels.

### 7.12 Row 3, and decisions extended to demoted tier-1 rows (2026-09-20)

**Queue row 3 approved:** `CAPGEMINI` → `CAPGEMINI UK PLC` (`00943935`), GBP 349,037,030.64.
This is a **demoted tier-1** row, not a fuzzy one: a buyer stated a number whose registered
name differs from the name the payer used (`04` §3 hard rule 6).

**Name similarity did not decide it, and could not.** The best tier-4 score is **0.50** —
below the candidate floor — and it **ties** with `03953511 CAPGEMINI OLDCO LTD`. The register
holds three active Capgemini companies, all SIC 62020.

**What decided it: the payer's own award notices.** HMRC names Capgemini on **8 of its own
Contracts Finder awards**, dated 2024-04-08 to 2025-02-28 — inside the spend window — and
states `00943935` on **all 8**, with no other number and no blanks. One of those awards
spells the supplier `CapGemini`, the same short form its spend file uses. Corroborated across
payers: DfT's and MOJ's `CAPGEMINI UK PLC` resolve at tier 2, high confidence, to the same
company.

**The class statistic did not govern the row.** Measured for demoted names: where tiers 2–3
later resolved them independently, the buyer's stated number was right **10 times out of 27 —
37.04%** (small sample, and biased toward disagreement). That is the reason a single
assertion never carries a row; it is not evidence about *this* row, which has eight
consistent statements from the payer itself.

**The mechanism, extended on the same rails.** A demoted tier-1 row can now be accepted
exactly as a tier-4 row can: same versioned literals in `38_queue_decisions.sql`, same
per-row protocol, **no auto-accept**, and the same stale guard — an accept applies only while
the approved company is still the candidate on offer, whether that candidate comes from
tier 4's scoring or tier 1's buyer statement.

**The basis split is keyed on `match_confidence`, not on tier.** An accepted demoted row keeps
`match_tier = 1`, because tier 1 is how it was found — but it is **reviewed**, not method.
Splitting on the tier number would have quietly banked a human decision as though the rule
had made it.

**Resolution by basis, after three decisions:**

| Basis | Names | Rows | Value (GBP) | % of value |
|---|---:|---:|---:|---:|
| **Method** — tiers 1–3, by rule | 5,981 | 175,470 | 29,935,699,821.14 | **58.32%** |
| **Reviewed** — accepted on a recorded decision | 2 | 2,369 | 1,219,464,513.44 | **2.38%** |
| **Total resolved** | **5,983** | **177,839** | **31,155,164,334.58** | **60.70%** |
| Unresolved | 7,394 | 174,689 | 20,175,094,760.80 | 39.30% |

**The method's claim has not moved through any of this: 58.32%.** That is the point of
reporting the two separately.

**A second defect the accept exposed, and fixed:** an accepted demoted row resolves at
tier 1, so the queue's `match_tier >= 4` filter dropped it — taking its recorded decision out
of the published log. The queue is the **decision log**, not only the to-do list, so a name
now stays if it is open **or** if a decision has been recorded against it. Regenerated: 1,431
rows, all three decisions visible, 0 empty labels.

All `V3`, `V4` and `D.1`–`D.4` controls pass: 3 decisions, 0 orphan, **0 stale**, 0 not
applied, 0 `reviewed` without an accept. `E-3` is untouched — 95.25% precision, tier 4
**80.88%** — because precision is measured on the method's own tables, never on human
decisions.

### 7.13 Row 4 rejected, and a whole class of candidate excluded (2026-09-20)

**Queue row 4 rejected:** `NEXUS` → `NEXUS LIMITED` (`OE007963`), GBP 106,362,560.99, score
1.00 against 99 rivals at 0.50.

**The evidence contradicted the score**, so the row-1 precedent applied:

- **The payer names the real entity itself.** DfT also pays `NEXUS (TYNE & WEAR)` — 2 rows,
  GBP 786,000 — with the **same first payment date, 2024-03-26**. Nexus is the Tyne and Wear
  passenger transport executive, a statutory body with no company number at all.
- **The candidate was not a company.** `OE007963` is a Register of Overseas Entities
  registration: a foreign body recorded as owning UK land, with no SIC.

**That made it a class problem, not a row problem.** The snapshot holds **30,199 `OE`
registrations**, and matching pointed at them **9 times**. `OE` entries are now excluded at
**candidate generation**, through one shared view (`30_match_universe.sql`) that tiers 1–4
all read — not by deleting register rows, which would break `V1.5` and destroy the audit
trail, and not as four copies of a predicate in four files. Tier 1 inherits it: a buyer
stating an `OE` number now reads as `number_not_in_register`. Recorded as `04` §3 hard rule 8.

| | Before | After |
|---|---:|---:|
| Match universe | 5,695,372 | **5,665,173** (−30,199) |
| Tier-2 acceptances | 13,488 | **13,504** |
| Matches pointing at an `OE` entry | 9 | **0** |
| Method resolution | 58.32% | **58.43%** |
| Tier-4 precision (`E-3`) | 80.88% | **81.24%** |
| Overall precision (`E-3`) | 95.25% | **95.27%** |

**The exclusion raised resolution rather than lowering it**, which was not the expected
direction. Names where a real company and an `OE` registration shared a name had been
rejected as **ambiguous**; removing the `OE` entry left a single candidate, and 3 more names
resolved — GBP 56,321,340.16 of spend that a register-semantics error had been holding back.

**The six exact-name `OE` resolutions, re-reviewed before the exclusion landed:**

| Name | `OE` entry | Payer | Value (GBP) |
|---|---|---|---:|
| MAPLEDURHAM PROPERTIES LTD | OE016602 | HMRC | 402,000.00 |
| CORNISH GATEWAY SERVICES LTD | OE006974 | DfT | 110,967.46 |
| CPE MANCHESTER 01 S.À R.L. | OE026070 | Manchester | 16,033.83 |
| AHS LTD | OE012016 | Bristol | 8,711.21 |
| UNITEX TRADING LTD | OE005460 | Manchester | 5,346.90 |
| GGC POLYGON MANCHESTER LTD | OE015161 | Manchester | 506.00 |

**All six were exact-name matches, and no non-`OE` company carries any of those names.** They
were therefore **right entity, wrong identifier class** — not wrong-entity errors. Every `OE`
registration involved was created between 2022-11-28 and 2023-02-13, the Register of Overseas
Entities window, and the names read like property-holding vehicles, which is what that
register records.

All six are now **unresolved** (`below_threshold`, except `GGC POLYGON MANCHESTER LTD` at
`no_match`), carrying GBP 543,565.40. **They are surfaced, not quietly dropped:** if the
handler judges the overseas entity to be the genuine payee, the per-row decision mechanism
can record that with its basis — which is exactly the protocol used for rows 2 and 3.

**Resolution by basis, after four decisions:**

| Basis | Names | Value (GBP) | % of value |
|---|---:|---:|---:|
| **Method** — tiers 1–3, by rule | 5,984 | 29,992,021,161.30 | **58.43%** |
| **Reviewed** — accepted on a recorded decision | 2 | 1,219,464,513.44 | **2.38%** |
| **Total resolved** | **5,986** | **31,211,485,674.74** | **60.81%** |
| Unresolved | 7,391 | 20,118,773,420.64 | 39.19% |

All `V3`, `V4` and `D.1`–`D.4` controls pass: 4 decisions, 0 orphan, **0 stale**, 0 not
applied. `V4.1` reconciles to the penny.

### 7.14 The same bug twice — the decision log is now complete by construction

The queue is built from names that are **open**. A decided name is normally open too, so it
appears — until something removes its candidate.

**It happened twice in two days, and the first fix was too narrow.** On 2026-09-20 an accepted
*demoted* row resolved at tier 1 and fell out of a `match_tier >= 4` filter; that branch was
patched. Hours later the **`OE` exclusion removed `NEXUS`'s tier-4 candidate**, dropping it to
tier 5 — and the *other* branch, unpatched, deleted the published record of its **rejection**.
A queue that loses a rejection is worse than one that loses a to-do: the decision was taken,
and the artefact no longer showed it.

`37` now has a third branch that re-adds **any** decided name the open branches missed,
carrying the company from the **decision record** rather than from a candidate table that no
longer offers one. Verified after regeneration: **1,420 rows, 4 of 4 decisions published, 0
empty labels.** `NEXUS` reads `decided; candidate withdrawn from matching` — which is what
actually happened to it.

### 7.15 The tiered protocol, the first delegated batch, and three things it exposed (2026-09-22)

**Row 5 rejected by the user:** `CABINET OFFICE` → `05756325`. Six public bodies pay the name,
the candidate is a Derbyshire business-support company, DfT separately pays
`Cabinet Office (GPA)`, and Contracts Finder names the Cabinet Office as supplier on 9 awards
with no company number on any.

**1. The queue double-counted 69 names.** A name both demoted at tier 1 and carrying a tier-4
candidate satisfied both queue routes and appeared twice. The protocol was sized on those
counts. One row per name now: **1,351 rows**, and where both routes fire the row says whether
they **AGREE** (51 names) or **CONFLICT** (18), keeping the buyer's company in
`alternative_company_number`.

| Tier | Band | Open rows | Open value (GBP) |
|---|---|---:|---:|
| A | ≥ GBP 10m | 14 | 306,479,966.62 |
| B | GBP 100k – < 10m | 403 | 362,810,394.71 |
| C | < GBP 100k | 874 | 16,784,662.85 |

**2. The first delegated batch: 55 Tier C accepts, every one reviewed.** Detectors ran only the
established classes. Of 929 Tier C rows: **55 accepted** on the same-payer bridge (the payer
writes the supplier with and without a legal suffix, and the suffixed spelling resolves by rule
to the same company), **11 escalated** (10 conflicts, 1 ambiguous), and **863 left open** — no
established class reaches them. Every accept was read before it was frozen as a literal in
`39_queue_delegated_decisions.sql`. New controls `D.5`–`D.8` hold them inside the authorisation:
0 outside Tier C, 0 on the wrong class, 0 names with two decisions in force, 0 without a
written basis.

**3. Basis belongs on the payment, not the supplier.** `dim_supplier.resolution_basis` read
`method` for **every** resolved entity, because accepted short spellings join companies already
reached by rule through a longer spelling. The dashboard would have shown GBP 1.2bn attributed
on user decisions as method. `fact_spend.resolution_basis` now records who stands behind each
payment row:

| Basis | Rows | Value (GBP) | % of value |
|---|---:|---:|---:|
| Method — tiers 1–3, by rule | 175,847 | 29,992,021,161.30 | 58.43% |
| User review | 2,369 | 1,219,464,513.44 | 2.38% |
| Delegated review — Tier C | 238 | 1,103,498.71 | 0.0021% |
| **Total resolved** | **178,454** | **31,212,589,173.45** | **60.81%** |

The row-level split reconciles exactly with the name-level split in `93`, and `V4.1` and
`V4.6` still pass after the new join.

**A finding for the handler — the register records previous names, and matching ignores them.**
Tier A row 1, `LENDLEASE CONSTRUCTION EUROPE LTD`, was demoted because `00467006` is registered
as `BOVIS CONSTRUCTION (EUROPE) LIMITED`. The register's own history shows it was **LENDLEASE
CONSTRUCTION (EUROPE) LIMITED until 2025-04-01** — covering every payment, 2024-03-18 to
2025-02-21. Across the open queue, **67 rows (GBP 90,896,550.91)** carry a supplier name equal
to a previous registered name of their candidate, **53 of them demoted tier-1 rows**. Hard rule 6
compares only against the current name. A new evidence class is the handler's decision, so it
is measured and proposed, not applied.

### 7.16 The previous-name class, 37 decisions, and a register-typing finding (2026-09-23)

**User decisions applied:** Tier A row 1 (`LENDLEASE CONSTRUCTION EUROPE LTD` → `00467006`,
decided on the register's own previous-name record) and Tier B batch 1 (26 accepts), each in
`38_queue_decisions.sql` with its basis. The batch was generated from the detector table and
checked against the approved count and total before it was written.

**The previous-name class, as adopted.** `34b_previous_name_evidence.sql` reads the register's
up-to-ten previous names and gives each a **validity window**: from the date the older name
was changed (or incorporation, for the oldest) until its own change date. A queued candidate
may cite a previous name only where the payer's spelling equals it **and the whole payment
window lies inside that validity period**. It is an evidence class inside the tiered protocol,
not a rule that resolves by itself.

| | Rows |
|---|---:|
| Open rows whose name matches a registered previous name of a candidate | 67 |
| — inside the validity window: the class applies | **38** |
| — outside it: the payer kept a brand after the legal rename | 29 |
| Applied in Tier C under the standing authorisation, each reviewed | 10 |
| Presented to the user as Tier B batch 3 | 27 + `INOVEM LTD` held per-row |

**The window assumption was tested, not assumed:** across 647,343 previous names, a name's
start is never after its end (0 inverted windows).

**Two defects caught before they ran.** The register's `CONDATE` columns 1–4 were typed DATE at
load but 5–10 are day-first strings; a bare cast would have nulled every one of those 1,355+
names without an error. And `WINDOW` is a reserved word.

**A finding for the handler (H-4).** `raw_companies_house` holds 19 typed columns (11 DATE, 8
INTEGER), because `08` §5.3 authorises autodetect for this load alone — while `03` §2 says
every Layer 1 column lands as STRING. **The two prep-package documents disagree, and the build
follows `08`.** The typed dates are sound: 3,426,845 of 5,695,465 incorporation dates have a day
above 12, which a month-first parse would have rejected at load. Proposed: record the
exception in `03` §2. Not written — a locked document.

**Resolution by basis, after 97 decisions:**

| Basis | Rows | Value (GBP) | % of value |
|---|---:|---:|---:|
| Method — tiers 1–3, by rule | 175,847 | 29,992,021,161.30 | 58.43% |
| User review | 3,156 | 1,289,774,240.94 | 2.51% |
| Delegated review — Tier C | 281 | 1,295,348.75 | 0.0025% |
| **Total resolved** | **179,284** | **31,283,090,750.99** | **60.94%** |

All `V3`, `V4` and `D.1`–`D.9` controls pass: 97 decisions (94 accepted, 3 rejected), 0 stale,
0 orphan, 10 previous-name decisions all backed by qualifying evidence. `E-3` is unchanged —
95.27%, tier 4 81.24%. **`07` §8 sections 2 and 3 were signed off by the user** and recorded in
the checklist with a dated backup.

---

## 8. Layer 4 — the star schema (`94_validate_reporting.sql`)

**Executed 2026-09-18. `V4.1`–`V4.6` all PASS.** Six tables: `dim_supplier`, `dim_entity`,
`dim_date`, `dim_category`, `fact_spend` and `fact_spend_unresolved`.

| Control | Result |
|---|---|
| `V4.1` end-to-end reconciliation | **PASS** — 352,528 rows and GBP 51,330,259,095.38 on both sides, difference **0.00** |
| `V4.2` no orphan foreign keys | **PASS** — 0 orphans across 4 keys × 352,528 rows, 0 null keys |
| `V4.3` `uncategorised` member | **PASS** — 1 member among 1,637 category rows |
| `V4.4` `dim_date` gapless and covering | **PASS** — 728 rows over a 728-day span, 0 fact dates uncovered |
| `V4.5` unresolved bucket present | **PASS** — 7,396 unresolved rows beside 5,967 resolved |
| `V4.6` no fan-out on aggregation | **PASS** — 175,470 rows and GBP 29,935,699,821.14 before and after the join, inflation 0.00 |

### 8.1 `V4.1` is the whole pipeline in one line

| | Rows | Value (GBP) |
|---|---:|---:|
| `staging_spend`, transactions | 352,528 | 51,330,259,095.38 |
| `fact_spend` (resolved) | 175,470 | 29,935,699,821.14 |
| `fact_spend_unresolved` | 177,058 | 21,394,559,274.24 |
| **Fact total** | **352,528** | **51,330,259,095.38** |
| **Difference** | **0** | **0.00** |

Four layers, two reconciliations (`E-5` at Layer 3, `V4.1` at Layer 4), and **not one row
or penny created or lost** between the published CSV files and the dashboard tables.

### 8.2 The consolidation finding

| Measure | Count |
|---|---:|
| Distinct raw vendor spellings in transaction rows | **14,434** |
| Distinct normalised names | 13,377 |
| Rows in `dim_supplier` | 13,363 |
| **Resolved supplier entities** | **5,967** |
| Most spellings collapsed into one supplier | **16** |

**14,434 vendor records describe at most 5,967 identified companies plus 7,396 names that
could not be identified.** That gap is the reason master data management exists, stated as
a measurement rather than as a claim.

### 8.3 The ten largest resolved suppliers

| Supplier | Company | Spellings | Rows | Spend (GBP) | Paying bodies |
|---|---|---:|---:|---:|---:|
| NETWORK RAIL LIMITED | 04402220 | 2 | 133 | 9,212,149,934.47 | 1 |
| NATIONAL HIGHWAYS LIMITED | 09346363 | 3 | 31 | 5,296,816,938.73 | 3 |
| GOVIA THAMESLINK RAILWAY LIMITED | 07934306 | 1 | 44 | 1,875,189,813.94 | 1 |
| NORTHERN TRAINS LIMITED | 03076444 | 3 | 46 | 1,190,625,688.74 | 3 |
| FIRST MTR SOUTH WESTERN TRAINS LIMITED | 07900320 | 1 | 33 | 911,676,351.72 | 1 |
| LONDON NORTH EASTERN RAILWAY LIMITED | 04659712 | 1 | 13 | 741,427,773.74 | 1 |
| TRANSPORT UK EAST MIDLANDS LIMITED | 09860485 | 1 | 37 | 470,778,190.15 | 1 |
| SE TRAINS LIMITED | 03266762 | 1 | 29 | 451,685,733.63 | 1 |
| CONNECT PLUS (M25) LIMITED | 06683845 | 2 | 117 | 401,511,467.76 | 1 |
| BALFOUR BEATTY CIVIL ENGINEERING LIMITED | 04482405 | 2 | 235 | 398,203,786.58 | 1 |

**Read this table with `P-9` in hand.** It is a rail and roads table because DfT dominates
by value; it is not a ranking of UK public-sector suppliers. `NETWORK RAIL LIMITED` reaches
GBP 9.2bn across **133 payment lines** — grant-in-aid scale, not procurement scale.

### 8.4 The declared window, carried as a flag rather than a filter

The declared analysis window is **2024-03-01 to 2025-02-28**. Observed transaction dates run
**2023-04-04 to 2025-03-31**, because in-window *files* carry out-of-window *records*.

| In the declared window | Rows | Value (GBP) | Span |
|---|---:|---:|---|
| Yes | 289,950 | 51,056,283,211.78 | 2024-03-01 → 2025-02-28 |
| No | **62,578** | 273,975,883.60 | 2023-04-04 → 2025-03-31 |

**62,578 is exactly the figure `09` `P-8` recorded** at preparation, reproduced here from
the built tables by an independent path.

`dim_date` spans the observed dates and flags the window (`is_in_analysis_window`).
Generating only the declared window would have failed `V4.2` — or, worse, passed it by
quietly discarding 62,578 real payments to make a date range look tidy.

**The `08` §12 window baseline reconciles too:** 289,950 in-window transactions + 24
`annex_duplicate` + 16 `out_of_scope_section` = **289,990**, the recorded baseline. That
baseline was measured before `row_role` existed, which is precisely the 40-row difference.
