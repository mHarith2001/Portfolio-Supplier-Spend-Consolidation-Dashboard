# Entity resolution — how a supplier name becomes a supplier

The intellectual core of this project. Every figure measured 2026-09-18.

## The problem

Six public bodies publish spend independently. **14,434 distinct raw vendor spellings**
appear across their files. They describe **at most 5,970 identified companies plus 7,336
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
| 1 | …demoted, then accepted on recorded review | **reviewed** | 1 | 349,037,030.64 |
| 2 | Exact normalised name against Companies House | high | 4,758 | 15,846,552,637.36 |
| 3 | Name core + postcode | medium | 54 | 10,164,008,997.88 |
| 4 | Token-set similarity ≥ 0.85 on the core | **review**; resolves only on a recorded human accept | 1,214 | 2,216,774,873.40 |
| 4 | …accepted on recorded review | **reviewed** | 1 | 870,427,482.80 |
| 5 | Unresolved, with a stated reason | none | 6,177 | 17,901,998,547.24 |

**Tier 1 is a bridge, not a lookup.** Spend files carry no company numbers. A spend supplier
reaches a buyer-stated number only where its normalised name equals a Contracts Finder name
that carries one.

**Tier 4 scores** shared tokens ÷ total distinct tokens on the suffix-free core, blocked by a
**prefix filter on frequency-ordered tokens** — provably lossless at the candidate floor,
corrected 2026-09-18 — with edit distance as a tie-break. Token-set is the right measure for this
data: publishers truncate and reorder supplier names far more often than they misspell them.

**Resolution by method is tiers 1–3: 5,984 names, GBP 29,992,021,161.30 — 58.43% of transaction
value.** Human review adds tier-4 names accepted on a recorded decision, reported
**separately** so one kind of evidence never borrows the other's credibility: so far 2 names by
the user, GBP 1,219,464,513.44 (2.38%), and 55 names by the builder under the Tier C
authorisation, GBP 1,103,498.71 (0.0021%) — **60.81% in total**.

## Eight hard rules

1. **Tier 4 never auto-merges.** It populates a review queue with its score and candidate
   count. A tier-4 name resolves **only** on a recorded human decision whose basis is evidence
   beyond the score, and only for the exact company approved — a rebuild that changes the
   candidate makes the decision stale, and it is not carried across.
2. **`candidate_count > 1` is never accepted at any tier.** A name matching three active
   companies is not resolved because one was returned first.
3. **No match where the payment precedes incorporation.** Applied at every tier — tier 4
   included, since 2026-09-18.
4. **Redacted names never enter matching.** They go straight to tier 5, reason `redacted`.
5. **A matched company number must exist in the register.** No orphan references.
6. **Tier-1 register disagreement is demoted to review.** Where a buyer states a number whose
   *registered* name disagrees with the supplier name, the match does not stand on the
   buyer's assertion alone. **232 names demoted**; 27 were later confirmed by tier 2 or 3 on
   their own evidence, and **0 were resolved at tier 1 by the rule**. A demoted name resolves
   only on a recorded human decision, on the same rails as tier 4. Measured: where independent
   evidence exists, the buyer's stated number was right 10 times of 27 — **37.04%**, which is
   why the assertion alone never carries a row.
7. **Suffix-conflict guard.** A candidate is rejected where both names carry a legal suffix
   and the suffixes differ — a `PLC` supplier against a `LIMITED` company. Without it, the
   suffix-free core re-introduces exactly the conflation the core key exists to avoid:
   measured at 4 names, GBP 39,014,117.12.
8. **Only company registrations are candidates** (added 2026-09-20). The snapshot holds
   **30,199 `OE` Register of Overseas Entities registrations** — a foreign body recorded as
   owning UK land, not a UK company. They are excluded at candidate generation, in one shared
   view every tier reads. Found on a row where a statutory transport executive scored 1.00
   against an overseas property registration. The exclusion **raised** method resolution, from
   58.32% to 58.43%: names where a real company and an `OE` entry shared a name had been
   rejected as ambiguous, and removing the `OE` entry left a single candidate.

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

**95.27% precision, 84.48% recall.** Tier 2 alone 96.93%; tier 4 alone 81.24%; 979
predictions wrong. Full method, threshold curve and ceilings in `match_precision.md`.

**The threshold was chosen from the measured curve, not assumed.** 0.85 is where the
precision plateau begins; below 0.70, tier-4 precision collapses.

## The review queue

**1,351 rows, one per name, highest value first** (`review_queue.csv`). Worked by value in
three tiers: A (≥ GBP 10m) per-row by the user, B (GBP 100k–10m) in user-approved evidence
batches, C (< GBP 100k) delegated to the builder where the evidence fits an established
class. **60 decided** — 5 by the user, 55 delegated — and **1,291 open**, GBP 686,075,024.18. **A decided row stays in the queue**: it is the
decision log, not only the to-do list.

**The most confident batch in that queue — score 1.00 with a single candidate — is correct
81.23% of the time.** Bulk-accepting it would be wrong about one time in six, and only 42 of
its 288 errors are explained by the matchable universe missing the answer.

**The dominant failure mode is a public body matching a private company of the same name.** A
government department, a passenger transport executive and a transport authority all score
1.00 against unrelated private companies. Every one would have been merged by a threshold.
That is what the queue is for.
