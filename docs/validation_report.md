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
