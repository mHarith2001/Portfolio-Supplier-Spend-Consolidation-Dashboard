# Entity resolution — how a supplier name becomes a supplier

The intellectual core of this project. Every figure measured 2026-09-18.

## The problem

Six public bodies publish spend independently. **14,434 distinct raw vendor spellings**
appear across their files. They describe **at most 5,967 identified companies plus 7,396
names that could not be identified**. One supplier alone is spelled **16** different ways.

Nobody can answer "how much did the public sector pay this company?" until those spellings
are resolved to entities — and no resolution can be trusted unless its error rate is
measured.

## Normalisation, then a core

Two keys are derived from every name, and **both are kept**:

- **`supplier_name_norm`** — upper-cased, punctuation and noise stripped, legal suffixes
  canonicalised (`LIMITED` → `LTD`, `PUBLIC LIMITED COMPANY` → `PLC`).
- **`supplier_name_core`** — `norm` with the legal suffix **removed**.

`core` is what lets `NETWORK RAIL` meet `NETWORK RAIL LIMITED`. `norm` is what stops
`SMITH LTD` being treated as `SMITH PLC`. Collapsing them into one key would either miss the
first or conflate the second.

## Five tiers, first match wins

| Tier | Method | Confidence | Names | Value (GBP) |
|---|---|---|---:|---:|
| 1 | Company number, bridged via a Contracts Finder award | high | 1,172 | 3,981,459,526.06 |
| 2 | Exact normalised name against Companies House | high | 4,755 | 15,790,231,297.20 |
| 3 | Name core + postcode | medium | 54 | 10,164,008,997.88 |
| 4 | Token-set similarity ≥ 0.85 on the core | **review only** | 1,199 | 3,244,886,577.86 |
| 5 | Unresolved, with a stated reason | none | 6,197 | 18,149,672,696.38 |

**Tier 1 is a bridge, not a lookup.** Spend files carry no company numbers. A spend supplier
reaches a buyer-stated number only where its normalised name equals a Contracts Finder name
that carries one.

**Tier 4 scores** shared tokens ÷ total distinct tokens on the suffix-free core, blocked by
the first token, with edit distance as a tie-break. Token-set is the right measure for this
data: publishers truncate and reorder supplier names far more often than they misspell them.

**Resolution is tiers 1–3 only: 5,981 names, GBP 29,935,699,821.14 — 58.32% of transaction
value.**

## Seven hard rules

1. **Tier 4 never auto-merges.** It populates a review queue with its score and candidate
   count. A portfolio project cannot claim human review it did not do.
2. **`candidate_count > 1` is never accepted at any tier.** A name matching three active
   companies is not resolved because one was returned first.
3. **No match where the payment precedes incorporation.** Applied at every tier — tier 4
   included, since 2026-09-18.
4. **Redacted names never enter matching.** They go straight to tier 5, reason `redacted`.
5. **A matched company number must exist in the register.** No orphan references.
6. **Tier-1 register disagreement is demoted to review.** Where a buyer states a number whose
   *registered* name disagrees with the supplier name, the match does not stand on the
   buyer's assertion alone. **232 names demoted**; 27 were later confirmed by tier 2 or 3 on
   their own evidence, and **0 remained resolved at tier 1**.
7. **Suffix-conflict guard.** A candidate is rejected where both names carry a legal suffix
   and the suffixes differ — a `PLC` supplier against a `LIMITED` company. Without it, the
   suffix-free core re-introduces exactly the conflation the core key exists to avoid:
   measured at 4 names, GBP 39,014,117.12.

## Survivorship

**Companies House is authoritative for identity. The spend files are authoritative for
money.** Neither overwrites the other's domain: no amount comes from anywhere but the spend
files, and no legal name from anywhere but the register.

Where a supplier is unresolved, the display name is its **most frequent raw spelling**, and
it keeps its own key rather than being pooled into a single bucket — so unresolved spend
stays countable instead of disappearing.

## How good is it? — the measured answer

`E-3` hides the Contracts Finder company number, runs the tiers on the **name alone**, and
compares the prediction with the buyer's stated answer across **24,506 measurable awards**.

**95.32% precision, 84.42% recall.** Tier 2 alone 96.99%; tier 4 alone 81.40%; 968
predictions wrong. Full method, threshold curve and ceilings in `match_precision.md`.

**The threshold was chosen from the measured curve, not assumed.** 0.85 is where the
precision plateau begins; below 0.70, tier-4 precision collapses.

## The review queue

**1,404 rows, decisions blank, highest value first** (`review_queue.csv`): 1,199 tier-4
candidates and the 205 demoted tier-1 names that no other tier confirmed.

**The most confident batch in that queue — score 1.00 with a single candidate — is correct
81.34% of the time.** Bulk-accepting it would be wrong about one time in six, and only 43 of
its 289 errors are explained by the register snapshot missing the answer.

**The dominant failure mode is a public body matching a private company of the same name.** A
government department, a passenger transport executive and a transport authority all score
1.00 against unrelated private companies. Every one would have been merged by a threshold.
That is what the queue is for.
