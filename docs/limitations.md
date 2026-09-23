# Limitations

What this project does not claim, and why. Every figure here was measured against the
built tables, not estimated.

A limitation stated up front is a finding. The same limitation discovered by a reader is a
defect.

---

## 1. Structural limits of the data itself

| # | Limitation |
|---|---|
| `L-1` | Supplier names are redacted for individuals and sole traders under data protection. These records are **structurally unresolvable** and are reported as a named category, never silently dropped |
| `L-2` | Companies House numbers appear in Contracts Finder only where the buyer supplied them. Precision is measured on that subset and **inferred**, not proven, for the remainder |
| `L-3` | Registered addresses of small companies may be residential. **Only derived tables are published — the raw register is never republished, and no postcode appears in any published extract** |
| `L-4` | Scope is a bounded sample of UK public bodies, **not the UK public sector** |
| `L-5` | Spend is payment-line data, not contract value. The two do not reconcile and are not presented as if they do |
| `L-6` | UK domain. The transferable claim is the **method** — entity resolution and spend consolidation — not UK procurement knowledge |

**`L-1` in numbers:** 4 redacted supplier names, 31,508 transaction rows,
GBP 113,266,026.75 — **0.2207%** of transaction value. Reported as a category, included in
every total, excluded from no headline.

---

## 2. Limitations found while building

| # | Limitation | Severity |
|---|---|---|
| `P-1` | `E-3` precision is measured on a central-government-weighted population | **Material** |
| `P-2` | VAT basis: all six publishers share one governing basis; the residual is an undetectable gross escape clause | Bounded |
| `P-3` | 46 records carry no usable payment date — **all 46 are non-payment rows** | Minor |
| `P-4` | 12,221 blank padding rows, 12,201 of them from one publisher | Minor |
| `P-5` | 274 Contracts Finder company numbers are unrecoverable; **93 Companies House numbers are in an `R`-form the canonicalisation ladder does not admit and are excluded by count** | Minor |
| `P-6` | Six date formats across six publishers; two publishers mix formats in one column | Handled |
| `P-7` | 322 supplier names carry characters that survive only through correct encoding handling | Handled |
| `P-8` | **62,578 records fall outside the analysis window despite being in in-window files** | Handled |
| `P-9` | One publisher dominates by value at a scale that makes cross-publisher comparison of totals misleading | **Material** |
| `P-10` | **Non-payment rows in published spend files** — 86 rows, GBP 2,556,596,745.72, excluded from aggregation | **Material** |
| `P-11` | The source body column is not the publisher for four of six publishers | Handled |
| `P-12` | Part of `E-3`'s known answer is absent from the Companies House snapshot | **Material** to `E-3` |
| `P-13` | Contracts Finder carries no award value and no procurement classification; its award date is the notice's **release** date | Bounded |
| `P-14` | A payee redacted in one source file is named in the same file's annex | Handled — confidentiality |
| `P-15` | One publisher publishes its expense fields unlabelled | Minor |
| `P-16` | **Dissolved suppliers are unreachable — the snapshot carries no dissolved companies at all** | **Material** to recall |

---

## 3. The four that change how a figure should be read

### `P-9` — one publisher dominates, so the supplier ranking is not a league table

**Required beside any top-supplier ranking, wherever it appears:**

> Department for Transport dominates this sample by value. This ranking covers six
> publishing bodies over twelve months and is **not** a ranking of UK public-sector
> suppliers.

The ten largest resolved suppliers are nine rail and roads bodies plus one civil-engineering
contractor. The largest reaches **GBP 9,212,149,934.47 across 133 payment lines** from a
single paying body — grant-in-aid scale, not procurement scale. The payment-line count is
what gives it away.

### `P-10` — GBP 2.56bn in the files is not spending

Published spend files contain rows that are not payments: file totals, a reconciliation
workbook's sections, and a trailing artefact. **86 rows carrying GBP 2,556,596,745.72.**

They are **retained, flagged, and excluded from aggregation — never deleted**. Every row and
every pound still reconciles from the source files to the dashboard; they simply carry no
supplier and enter no total. Summing a spend file without this classification overstates it
by 4.98%.

### `P-16` — a dissolved supplier can never be matched

The Companies House snapshot in use carries **14 distinct company statuses across 5,695,372
companies, and none of them is `Dissolved`**: 5,190,379 `Active`, 388,951
`Active - Proposal to Strike off`, 108,791 `Liquidation`, 3,739 `In Administration`, and
3,512 across ten further insolvency states. The free "basic company data" product is a
snapshot of the **live** register.

A supplier that has since been dissolved is therefore unreachable at **every** tier. Part of
the unresolved population is beyond **any** method operating on this snapshot, not beyond
this one.

- **Precision is unaffected** — it asks whether the matches made are correct.
- **Recall carries the ceiling**, including the 84.48% measured recall and the 58.43%
  resolution rate.
- **It is structural and permanent for this snapshot.** Only the full register would lift
  it, which is a data-acquisition change, not a method change.

### `P-8` — the window is a flag, not a filter

The declared analysis window is 2024-03-01 to 2025-02-28. Observed payment dates run
2023-04-04 to 2025-03-31, because in-window *files* carry out-of-window *records*.

The date dimension spans the **observed** dates and carries the declared window as a flag.
Generating it over the declared window would have discarded **62,578 real payments** worth
GBP 273,975,883.60 to make a date range look tidy.

---

## 4. Reconciliation baselines a reader can check

| Baseline | Value |
|---|---|
| Rows, staging → resolved → reporting | 352,614 → 352,614 → 352,528 transactions |
| `SUM(amount)`, staging and resolved | GBP 53,886,855,841.10, identical |
| Transaction value | GBP 51,330,259,095.38 |
| Excluded non-payment value | GBP 2,556,596,745.72 |
| In-window transactions | 289,950 (+ 24 annex duplicates + 16 out-of-scope section rows = 289,990) |
| Vendor spellings → identified suppliers | 14,434 → 6,012, plus 7,255 unidentified names |

---

## 5. What is deliberately not claimed

- **That tier-4 fuzzy matches are resolved.** They are queued for human review with
  decisions blank. Measured against known answers, the queue's most confident batch — score
  1.00 with a single candidate — is correct **81.23%** of the time. Bulk-accepting it would
  be wrong about one time in six.
- **That 58.43% is a good resolution rate or a bad one.** It is the method's measured rate for
  these six publishers against this snapshot. User review adds 2.60% and delegated review
  0.0025% so far, each reported separately, for 61.04% in total.
- **That the unresolved population is small.** It is 38.96% of transaction value, reported
  with its reasons and its value.
- **That any named supplier has done anything wrong.** This is payment-line data.
  Concentration and variance are legitimate readings; impropriety is not supported by spend
  data alone.

---

## 6. Open human-review register (from 2026-09-22)

Tier-4 fuzzy matches and demoted tier-1 matches are **never resolved by the method**. They are
queued for a human decision, and the queue is worked by value under a tiered protocol. What
remains open is a limitation of this build, not a finding about the suppliers, and it is
published as such.

| Tier | Band | How it is decided | Open rows | Open value (GBP) |
|---|---|---|---:|---:|
| **A** | ≥ GBP 10m | Per-row user decision | 12 | 211,590,831.24 |
| **B** | GBP 100k – < 10m | User-approved evidence batches | 341 | 295,185,494.29 |
| **C** | < GBP 100k | Delegated to the builder on established evidence classes | 856 | 16,289,707.42 |
| **Total** | | | **1,209** | **523,066,032.95** |

**Decisions recorded: 145.** 80 by the user (73 accepted, 4 rejected, 3 left open — the evidence cannot separate the candidates, so they stay in the open count above) and 65 by the builder under
the Tier C authorisation (all accepted — 55 on the same-payer bridge, 10 on the register's
previous names — each reviewed individually). Every decision is recorded with its basis and is published in
`review_queue.csv`; a user decision always overrides a delegated one. Two of the user's accepts
resolve a hard-rule-2 tie on same-payer evidence, under an override the user scoped to those
two names (control `D.10`).

**How much the open queue could move the headline, and how little it can.** Resolution by
method is **58.43%**. The open queue holds GBP 523,066,032.95 — **1.02%** of transaction value.
Even if every open row were eventually accepted, the resolution rate could rise by at most that
much. Most of the unresolved 38.96% is not in the queue at all: it is `no_match` and
`below_threshold` names that no candidate reaches.

**Three ceilings sit under the open queue:**

- **Evidence is unevenly available by payer.** The payer's own award notices are a decisive
  evidence class, but only three of the six publishers state company numbers in Contracts
  Finder. **DfT has no awards in this extract; Bristol and Manchester state no company number
  on any award.** Rows paid by those three cannot be corroborated that way.
- **Previous names help only inside their validity window** (adopted 2026-09-23). Hard rule 6
  compares a buyer's number to the company's **current** name, so a renamed company is demoted.
  The register's previous names are now evidence — but only where the payer's spelling was the
  company's registered name for the **whole** period it was paid. Of the 67 queued rows whose name
  matched a previous name on 2026-09-23, **29 fell outside the window**: the payers kept using a brand after
  the legal rename (Click Travel is the clearest case). Those rows need a per-row decision.
- **Public bodies do not all lack company numbers.** Some government-owned bodies are
  registered companies (National Highways Limited is one), so "looks like a public body" is
  not a safe structural reason to reject. It is used only on a per-row decision, never as a
  delegated rule.
