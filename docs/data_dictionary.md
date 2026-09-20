# Data dictionary

Column-level reference for the published extracts in `data/outputs/` and the warehouse
tables behind them. Measured 2026-09-18.

---

## `fact_spend.csv` — 178,216 rows

One payment line to a **resolved** supplier.

| Column | Type | Notes |
|---|---|---|
| `spend_ref` | STRING(16) | Row reference. First 16 hex characters of the warehouse `spend_id`; **verified unique across all 352,528 fact rows** |
| `supplier_id` | INT64 | → `dim_supplier.supplier_id` |
| `entity_id` | INT64 | → `dim_entity.entity_id` — the **publishing body** |
| `date_key` | DATE | → `dim_date.date_key`. The payment date |
| `category_id` | INT64 | → `dim_category.category_id` |
| `source_file_id` | INT64 | → `dim_source_file.source_file_id`. Provenance to the published file |
| `vat_basis_id` | INT64 | → `dim_vat_basis.vat_basis_id` |
| `amount` | NUMERIC | GBP. **Negatives are real** — credits and corrections are retained, never dropped |
| `is_grant_in_aid` | BOOL | Grant-in-aid transfers, which are not procurement |
| `transaction_number` | STRING | The publisher's own reference, as published |

## `fact_spend_unresolved.csv` — 174,312 rows

Identical grain and columns, plus:

| Column | Type | Notes |
|---|---|---|
| `unresolved_reason` | STRING | `no_match` · `below_threshold` · `review` · `ambiguous` · `redacted` |

**Together the two fact tables are every transaction row**: 352,528 rows,
GBP 51,330,259,095.38, identical to `staging_spend`'s transaction total. Neither is a
subset to be ignored.

---

## `dim_supplier.csv` — 13,361 rows

| Column | Type | Notes |
|---|---|---|
| `supplier_id` | INT64 | Export key |
| `supplier_key` | STRING | Warehouse key — the bridge back to BigQuery |
| `supplier_name` | STRING | Registered name where resolved; most frequent raw spelling where not. **154 individual-looking unresolved names read "Individual — name withheld"** |
| `company_number` | STRING | Companies House. NULL where unresolved. **Never an `OE` overseas-entity registration** — those are excluded from matching (`04` §3 hard rule 8) |
| `legal_name` | STRING | Companies House. NULL where unresolved |
| `company_status` | STRING | 14 values, **all live — the snapshot holds no `Dissolved` companies** |
| `incorporation_date` | DATE | Used by the plausibility rule |
| `name_variant_count` | INT64 | **How many raw spellings collapsed into this record.** Max observed: 16 |
| `is_resolved` | BOOL | TRUE for tiers 1–3, and for a queued name — tier 4, or a demoted tier 1 — accepted on a recorded review decision |
| `unresolved_reason` | STRING | NULL where resolved |
| `match_tier` | INT64 | 1–5. The **best** tier that reached this entity |
| `match_confidence` | STRING | `high` · `medium` · `reviewed` · `review` · `none`. **`reviewed`** = a queued candidate accepted on a recorded human decision, whatever tier found it; **`review`** = still queued |
| `resolution_state` | STRING | Reader-facing label |
| `is_individual_withheld` | BOOL | TRUE where the name was withheld |

**`postcode` is deliberately absent** from the published extract. It exists in the warehouse
for tier-3 matching; registered addresses of small companies may be residential.

## `dim_entity.csv` — 6 rows

`entity_id` · `entity` · `publisher_type` (`central` / `local`) · `transaction_rows` ·
`transaction_value` · `distinct_suppliers` · `first_payment` · `last_payment` ·
`source_files`

**`entity` is the publisher** — the body whose disclosure the file is — not the source body
named inside the file. For four of six publishers those differ.

## `dim_date.csv` — 728 rows

`date_key` · `calendar_year` · `calendar_quarter` · `month_number` · `month_name` ·
`year_month` · `day_of_month` · `day_name` · `is_weekend` · `fiscal_year` ·
`fiscal_year_label` · `is_in_analysis_window`

**Spans the observed payment dates (2023-04-04 → 2025-03-31), gapless.**
`is_in_analysis_window` flags the declared window 2024-03-01 → 2025-02-28. **365 days are in
the window; 62,578 transaction rows fall outside it** and are retained.

`fiscal_year` follows the UK public-sector year, 1 April to 31 March.

## `dim_category.csv` — 1,637 rows

`category_id` · `category_key` · `entity` · `expense_type` · `category_label` ·
`is_uncategorised` · `transaction_rows` · `transaction_value`

**Keyed on (`entity`, `expense_type`).** Categories are each publisher's own vocabulary and
are **not comparable across publishers**. One publisher's expense types are a labelled
inference: it publishes the field unlabelled.

The `uncategorised` member is mandatory and currently has no members — it exists so that a
future row without an expense type is counted rather than dropped.

## `dim_source_file.csv` — 62 rows

`source_file_id` · `source_file` · `entity` · `transaction_rows`

Every published file that contributed a transaction row. This is the provenance chain: any
figure on the dashboard reaches the file it came from.

## `dim_vat_basis.csv` — 2 rows

`vat_basis_id` · `amount_vat_basis` · `transaction_rows`

Which VAT basis an amount is stated on. **No single combined total across all six publishers
should be quoted without the VAT caveat** in `limitations.md` `P-2`.

---

## Warehouse tables not exported

| Table | Why it stays in BigQuery |
|---|---|
| `staging_spend` | 352,614 rows including non-payment rows; the export carries transactions only |
| `staging_companies` | 5,695,372 companies. The raw register is never republished |
| `resolved_supplier_match` | The match audit trail, one row per name, with `reject_reason` and notes |
| `resolved_tier4_candidates` | Every scored (name, company) pair ≥ 0.5 |

`review_queue.csv` publishes the decision-bearing part of the audit trail: 1,419 rows, four
decided (two accepted, two rejected) and the rest blank, each decision carrying its reason and date from
`38_queue_decisions.sql`.
