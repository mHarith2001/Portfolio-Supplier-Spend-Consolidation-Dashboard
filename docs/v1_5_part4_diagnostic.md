# V1.5 — Companies House part4 embedded-newline diagnostic

- Source file: `BasicCompanyData-2026-08-01-part4_7.csv`
- Size: 417,195,850 bytes
- Header fields: **55**
- Records parsed: **849,999** (expected 849,999; physical lines 850,001)
- Records containing an embedded newline: **1**
- Blank records: **1** (expected 1)

## The count question — two quantities, both correct

| Quantity | Value | What produces it |
|---|---:|---|
| CSV records in part4 | **849,999** | `csv.reader`; a blank line is a record |
| Blank records | **1** | record #454,676 (0 fields) |
| Company records in part4 | **849,998** | `LOAD DATA`; BigQuery does not materialise an empty line as a row |

Seven-part totals follow from this: **5,695,466 CSV records** (the ratified figure, unchanged) and **5,695,465 company records** (`COUNT(*)` on `raw_companies_house`). `V1.5` compares a table row count, so it must be measured against the second. The two differ by this one blank line and by nothing else.

## Findings

### Record #454,675

| Property | Value |
|---|---|
| Fields in record | **55** |
| Fields in header | **55** |
| Field count matches | **YES** |
| Newline in field | `[52]  PreviousName_10.CompanyName` |
| CompanyName | `LIONS BOXING ORGANIZATION LIONS LIONESSES WORLD CUP & FOOTBALL WORLD CUP + PAKISTANS 1KO CHAMPIONSHIP BOXING NIGERIAS LI` |
| CompanyNumber | `09056746` |

Field value containing the newline, repr-escaped:

```text
'1KO BOXING CHAMPIONSHIPS AFGHANIS\nTANS (LIONS) LIMITED'
```

**Verdict:** LEGITIMATE QUOTED NEWLINE — record intact, field count correct. No company is missing and no field is shifted, so tier-1 matching will not fail silently. See the count table above for which total this supports: it confirms the CSV record count, not the table row count.
