# Match precision — the `E-3` measurement

**Measured 2026-09-18** by `sql/90_validation/95_measure_match_precision.sql`.
Published whether or not it flatters the method.

## What is measured

Contracts Finder award notices state the supplier's Companies House number for part
of their population. Those awards have a **known correct answer**. The number is
hidden, the matching tiers are run on the supplier **name alone**, and the
prediction is compared with the number the buyer stated.

**Population: 24,507 known-answer awards, of which 24,506 are measurable.** One award
carries a company number and an empty supplier name, which normalises to nothing and
can never be matched by name.

**Tier 1 is excluded by construction.** It reads the buyer-stated number, which is
the answer being measured against. **Tier 3 cannot enter**: it needs a postcode on
both sides, and Contracts Finder publishes none. So `E-3` measures **tiers 2 and 4**.

## Result

| Tier | Method | Matches made | Correct | Wrong | Precision |
|---|---|---:|---:|---:|---:|
| 2 | Exact normalised name | 18,469 | 17,914 | 555 | **96.99%** |
| 4 | Token-set similarity, review only | 2,236 | 1,808 | 428 | **80.86%** |
| — | No match | 0 | — | — | — |
| **All** | | **20,705** | **19,722** | **983** | **95.25%** |

**Recall: 20,705 of 24,506 = 84.49%.** 3,801 awards receive no match at all.

**Tier 4 never auto-accepts** (`04` §3 hard rule 1). Its matches are counted here as
predictions so the method can be measured, but in the resolved data they populate a
review queue with the score and the candidate count, decisions blank.

## The threshold, and why it is 0.85

Tier 4 scores a name against a company by **token-set similarity** on the
suffix-free core — shared tokens over total distinct tokens — blocked by the first
token, with edit distance as a tie-break. The threshold was chosen from the measured
curve, not assumed:

| Threshold | Matches | Precision | Recall | Tier-4 precision |
|---:|---:|---:|---:|---:|
| 0.50 | 22,994 | 88.94% | 93.83% | 56.07% |
| 0.65 | 21,781 | 92.27% | 88.88% | 65.94% |
| 0.70 | 21,058 | 94.47% | 85.93% | 76.48% |
| 0.80 | 20,807 | 94.99% | 84.91% | 79.17% |
| **0.85** | **20,705** | **95.25%** | **84.49%** | **80.86%** |
| 1.00 | 20,696 | 95.26% | 84.45% | 80.83% |

Above 0.85 the curve is flat — only 30 names sit between 0.85 and 0.99, because
2,748 of the best candidates score exactly 1.00, where the token sets are identical
and the difference is word order or truncation rather than spelling. Below 0.70
tier-4 precision falls away sharply. **0.85 is the precision plateau that still
leaves a review queue worth reviewing: 2,778 names, 67 of them ambiguous.**

Lowering the threshold to 0.70 would add 679 names to the queue and cost 4.4
percentage points of tier-4 precision — a trade available on the evidence above.

## What limits this result, beyond the method

Three ceilings sit above the figure and belong beside it whenever it is quoted.

1. **496 of the 11,593 distinct known-answer companies are absent from the Companies
   House snapshot.** No method could reach them: at most 23,883 of the 24,507 awards
   are reachable.
2. **608 names have no candidate block at all** — their first core token matches no
   company — covering GBP 450,408,335.70 of spend. Blocking is what makes tier 4
   affordable, and this is its cost.
3. **The population is central-government-weighted.** The three local authorities in
   this project publish company numbers at or near zero, so precision measured here
   does not generalise to local-authority spend. See `limitations.md` `P-1`.

## What is not claimed

- That the tier-4 matches are resolved. They are queued for review, with decisions blank.
- That 95.25% applies to the spend files. It is measured on Contracts Finder awards,
  which name suppliers in their own way.
- That the unresolved population is small. It is reported with its count and value.
