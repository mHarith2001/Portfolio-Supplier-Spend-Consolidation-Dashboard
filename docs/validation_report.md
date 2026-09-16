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
| `V2.9` name unless redacted (scoped) | HARD | 0 | **FAIL — 31 rows, GBP 2.08bn. See §6.5** |
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

#### Not acted on

Excluding total rows is a **new exclusion rule**. It is not in `08` §11, and it
changes the published spend figure for two publishers by GBP 1.76bn. That is a
specification decision, not a builder's. `V2.9a`, the per-file total-row
detector, is committed in `92_validate_staging.sql` so the test is repeatable
and the evidence is not a one-off query.

**No Layer 3 or Layer 4 work should proceed on these totals until it is ruled.**

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
