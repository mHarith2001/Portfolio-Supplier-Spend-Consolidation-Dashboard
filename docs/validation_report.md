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