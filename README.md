# Supplier Master Data and Spend Consolidation

Resolving inconsistently-spelled supplier names across six UK public bodies into a
single master record, and measuring how good that resolution actually is.

**Status: in build.** Sections marked `[TBC]` are filled from the analysis, not from
the plan. Figures already present are measured and sourced.

---

## The question

Six UK public bodies publish spend over £25,000 every month. **None of them attaches a
supplier identifier**, and the same company appears under different spellings within a
single publisher, let alone across six. Official Local Government Association guidance
states plainly that there are *"no UIDs for suppliers, and fields and their definitions
vary from file to file."*

So a question a procurement or finance analyst would actually ask —
**"how much do we spend with this supplier, in total, across these bodies?"** — cannot
be answered from the published files as they stand.

This project builds the master record that answers it, and **publishes the error rate
of the matching that produced it.**

## Headline finding

`[TBC — N vendor records resolve to M distinct suppliers; how the top-supplier ranking changes]`

## Data sources and licences

| ID | Source | Licence |
|---|---|---|
| `B-DS-01` | Spend over £25,000 — HM Revenue and Customs, Department for Transport, Ministry of Justice | Open Government Licence v3.0 |
| `B-DS-02` | Council spending — Bristol City Council, City of York Council, Manchester City Council | Open Government Licence v3.0 |
| `B-DS-03` | Companies House Free Company Data Product, snapshot **2026-08-01** | Crown copyright |
| `B-DS-04` | Contracts Finder OCDS award notices | Open Government Licence v3.0 |

```text
Contains public sector information licensed under the Open Government Licence v3.0.
```

```text
Contains public sector information from Companies House, licensed under Crown copyright.
```

**Manchester City Council** requires a council-specific attribution string and carries a
commercial-use condition; both are stated in `docs/limitations.md`.

**The raw Companies House register is not in this repository and never will be.** It is
~470 MB, registered addresses may be residential, and the data-protection
responsibility for any republication rests here rather than with Companies House.
`scripts/02_download_companies_house.py` plus `docs/provenance.csv` let you rebuild the
exact snapshot this analysis used.

## Method

Four layers, each with its own validation gate:

```text
L1  raw_         Load as published. Nothing altered. Row counts tie to provenance.csv
L2  staging_     Harmonise 13 header signatures into one schema. Parse 6 date formats.
                 Normalise names. Nothing resolved yet.
L3  resolved_    Five match tiers, then survivorship into a golden record.
L4  reporting_   Star schema — fact_spend plus dimensions.
```

Full specification: `docs/schema.md` · `docs/entity_resolution_rules.md`

**Two controls carry the project:**

| Control | What it prevents |
|---|---|
| `SUM(amount)` is identical before and after resolution, to the penny | Resolution changes *attribution*, never totals. A fan-out here is the single most likely way this analysis becomes quietly wrong |
| No tier-4 (fuzzy) match is ever auto-accepted | Ambiguity goes to `docs/review_queue.csv` with the decision left blank, not resolved by a threshold nobody looked at |

## How good is the matching?

`[TBC — precision and recall by tier, from docs/match_precision.md]`

**This section is named as a question because most projects of this kind never answer
it.** Precision is measured on a population where the correct answer is known
independently: Contracts Finder award notices carry both a supplier name *and* the
Companies House number the buyer stated. Running the resolution logic name-only against
that subset and scoring it against the known number turns fuzzy matching from an
assertion into a figure.

**32.42%** of awards in the window carry a company number — a complete census, not a
sample. That is the population the precision figure describes, and
`docs/limitations.md` records what it does and does not generalise to.

**The figures are published whether or not they flatter the method.**

## What this analysis does not claim

**Totals are presented per publisher and are not summed across all six.**

All six publish on the same governing basis — net of recoverable VAT, inclusive of
irrecoverable VAT — mandated by HM Treasury guidance for central departments and the
Local Government Transparency Code for local authorities. Two publishers evidence this
in their file structure; four are presumed on the governing rule with no stated
departure found. Both regimes permit a publisher whose systems cannot separate
recoverable VAT to publish gross instead, which would raise that publisher's figures by
up to 20% undetectably.

**A second reason not to sum:** the Department for Transport's spend runs to billions
per month against Bristol's tens of millions. A raw cross-publisher total is a chart of
which body is a central department.

**No named supplier is characterised as wrongdoing.** Concentration and variance
analysis is legitimate; spend data alone does not support an inference of impropriety
about an identifiable company.

## Reproducing this

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python scripts/01_download_spend.py
python scripts/02_download_companies_house.py
python scripts/03_download_contracts_finder.py
```

`docs/provenance.csv` carries the source URL, retrieval date, SHA-256 and row count for
every one of the 69 acquired files. **The scripts verify their downloads against those
hashes and halt on mismatch** — so a reader either reproduces the exact corpus this
analysis used, or is told immediately that the publishers have changed something.

SQL runs on **Google BigQuery** in layer order (`sql/10_raw` → `sql/90_validation`).
`sql/90_validation/` runs **after each layer**, not only at the end.

## Limitations

`docs/limitations.md` — read it before quoting any figure from this repository.

## Licence

Code and documentation in this repository: **MIT** (`LICENSE`).

**This does not relicense the source data.** The data licences are stated above and
apply on their own terms.
