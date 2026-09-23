# Schema — four layers

Every table, its grain, and why the layer exists. Figures measured 2026-09-18.

```text
L1  raw_        Landing. Everything STRING. Nothing dropped.
L2  staging_    Typed and harmonised. All publishers UNION into one table.
L3  resolved_   Supplier identity established. Golden records + match audit trail.
L4  reporting_  Star schema for Tableau. Dimensions + facts.
```

## Why four layers rather than three

**L3 is separated from L4 so that entity resolution is auditable independently of
reporting.** The match audit trail has to survive into the published artefact — that is what
the `E-3` precision measurement inspects. Folding resolution into the reporting build would
make the measurement unverifiable, because there would be no record of *why* a name became a
supplier.

**L1 is separated from L2 so that a load is never a transformation.** Everything lands as
`STRING`; nothing is cast, cleaned or dropped at the door. When a date turns out to parse
wrongly, the evidence is still in `raw_`.

## L1 — `raw_`

One table per publisher, because their schemas differ. Every column `STRING`.

| Table | Rows |
|---|---:|
| `raw_spend_*` (six publishers, 62 files) | 364,835 |
| `raw_companies_house` | 5,695,466 CSV records / 5,695,465 company records |
| `raw_contracts_finder` | 76,449 |

The two Companies House quantities are **not the same number**: one blank record separates
them. Conflating them produced an off-by-one that cost a validation cycle.

## L2 — `staging_`

| Table | Grain | Rows |
|---|---|---:|
| `staging_spend` | One published spend line, all six publishers | 352,614 |
| `staging_companies` | One company | 5,695,372 |
| `staging_contracts` | One award release per supplier | 76,449 |

`staging_companies` excludes **93** companies whose number is an `R`-form the
canonicalisation ladder does not admit — excluded by count, recorded, never silently
dropped.

### `row_role` — the column that decides what counts as spending

Published spend files contain rows that are **not payments**. `row_role` classifies every
row, and only `transaction` rows are ever aggregated:

| Value | Meaning |
|---|---|
| `transaction` | A payment line. 352,528 rows, GBP 51,330,259,095.38 |
| `file_total` | A total row the publisher included in the data |
| `annex_duplicate` | A row repeated in an annex within the same file |
| `out_of_scope_section` | A workbook section that is not spend |
| `trailing_artefact` | A stray row after the data ends |
| …and three further non-payment roles | |

**86 rows carrying GBP 2,556,596,745.72 are non-payment.** They are retained and flagged,
excluded from aggregation, and never deleted — so every row still reconciles while none of
them inflates a total.

## L3 — `resolved_`

| Table | Grain |
|---|---|
| `resolved_company_universe` | One matchable register entry — `staging_companies` minus 30,199 `OE` overseas-entity registrations (a view) |
| `resolved_names` | One normalised supplier name — the matching universe, spend and `E-3` together |
| `resolved_match_tier1`–`tier4` | One name per tier, with `accepted`, `candidate_count` and `reject_reason` |
| `resolved_tier4_candidates` | One (name, company) pair scoring ≥ 0.5 |
| `resolved_company_previous_names` | One registered previous name of a matchable company, with its validity window |
| `resolved_prev_name_evidence` | One (name, candidate) pair where the payer's spelling was the candidate's registered name for the whole payment window |
| `resolved_supplier_match` | One name, with its winning tier, method, confidence and notes |
| `resolved_supplier_golden` | One supplier entity — 5,983 resolved + 7,299 unresolved buckets |
| `resolved_spend` | **Every** `staging_spend` row, carrying `row_role` and a `supplier_key` |
| `resolved_review_queue` | One queued name — tier-4 candidates and demoted tier-1 names — with `review_tier` and any decision |
| `resolved_queue_decisions` | One **user** decision, as a versioned literal with its basis |
| `resolved_queue_delegated` | One **builder** decision under the Tier C authorisation, frozen with its evidence class and basis |
| `resolved_queue_all_decisions` | The decisions in force — user overriding delegated (a view) |

**`resolved_spend` holds exactly as many rows and exactly the same `SUM(amount)` as
`staging_spend`.** That is the `E-5` control. Resolution changes *attribution*, never totals.

**A `supplier_key` is assigned only where `row_role = 'transaction'`.** Non-payment rows keep
their rows and their amounts and carry none, which is how they reconcile while vanishing
from every aggregate.

## L4 — `reporting_`

```text
      dim_supplier        dim_date        dim_entity
             └───────────────┼───────────────┘
                   fact_spend │ fact_spend_unresolved
                        dim_category
```

| Table | Grain | Rows |
|---|---|---:|
| `dim_supplier` | One supplier entity, **including the unresolved bucket** | 13,282 |
| `dim_entity` | One publishing body | 6 |
| `dim_date` | One day | 728 |
| `dim_category` | One (`entity`, `expense_type_raw`) pair + `uncategorised` | 1,637 |
| `fact_spend` | One payment line to a **resolved** supplier, with its `resolution_basis` | 179,284 |
| `fact_spend_unresolved` | One payment line, supplier **not** resolved | 173,244 |

**Two fact tables, one grain.** The split exists so the unresolved population is a reportable
category rather than a silent omission. Together they are every transaction row:
352,528 rows, GBP 51,330,259,095.38 — identical to `staging_spend`'s transaction total.

**`dim_category` is keyed on (`entity`, `expense_type`) and not on `expense_type` alone**,
because each publisher uses its own vocabulary. Two publishers' "Professional Services" are
two different categories that happen to share a string, and the entity in the key keeps them
apart.

**`dim_date` spans the observed payment dates, not the declared analysis window**, and
carries the window as a flag. Generating it over the window would have discarded 62,578 real
payments.

## The export layer

Tableau Public has no database connectors, so the star schema leaves BigQuery as flat files
in `data/outputs/`. The export differs from the warehouse in three recorded ways, all
implemented in `sql/40_reporting/46_export_tableau.sql`:

1. **Integer surrogate keys** instead of SHA-256 hex. Each dimension carries both, so any
   published figure traces back to its warehouse row. This alone took the extract from
   114 MB to 28.3 MB.
2. **No `postcode`.** Registered addresses of small companies may be residential.
3. **Individual-looking unresolved names withheld** — 154 of them. The rows and the money
   stay; only the label is withheld.
