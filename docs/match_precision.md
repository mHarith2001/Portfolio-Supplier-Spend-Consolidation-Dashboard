# Match precision — the `E-3` measurement

**Measured 2026-09-18** by `sql/90_validation/95_measure_match_precision.sql`.
Published whether or not it flatters the method.

> **Re-measured after hard rule 3 was applied to tier 4 (2026-09-18).** Tiers 1–3 have
> always rejected a company incorporated after the first payment; tier 4 did not. Applying
> it removed 107 impossible candidates and **raised tier-4 precision from 80.86% to 81.40%**.
> The earlier figures are superseded, not hidden: they are in this file's git history.

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
| 4 | Token-set similarity, review only | 2,220 | 1,807 | 413 | **81.40%** |
| — | No match | 0 | — | — | — |
| **All** | | **20,689** | **19,721** | **968** | **95.32%** |

**Recall: 20,689 of 24,506 = 84.42%.** 3,817 awards receive no match at all.

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
| 0.50 | 22,975 | 89.01% | 93.75% | 56.30% |
| 0.65 | 21,757 | 92.37% | 88.78% | 66.39% |
| 0.70 | 21,041 | 94.54% | 85.86% | 76.94% |
| 0.80 | 20,791 | 95.06% | 84.84% | 79.67% |
| **0.85** | **20,689** | **95.32%** | **84.42%** | **81.40%** |
| 1.00 | 20,680 | 95.32% | 84.39% | 81.37% |

Above 0.85 the curve is flat — only **30** names sit between 0.85 and 0.99, because
**2,642** of the best candidates score exactly 1.00, where the token sets are identical
and the difference is word order or truncation rather than spelling. Below 0.70
tier-4 precision falls away sharply. **0.85 is the precision plateau that still
leaves a review queue worth reviewing: 2,672 names, 61 of them ambiguous**, with 4,644
scoring below it.

Lowering the threshold to 0.70 would add 664 names to the queue and cost 4.46
percentage points of tier-4 precision — a trade available on the evidence above.

## A warning about the queue, measured 2026-09-18

**Score 1.00 with a single candidate is not a safe bulk-accept.** Measured against the
`E-3` known answers:

| Queue batch | Names | Correct | Wrong | Precision |
|---|---:|---:|---:|---:|
| Score 1.00, single candidate | 1,549 | 1,260 | 289 | **81.34%** |
| Score 1.00, ambiguous | 47 | 29 | 18 | 61.70% |
| Score 0.85–0.99 | 8 | 7 | 1 | 87.50% |

Only **43** of those 289 errors are explained by the answer being absent from the
snapshot (`P-12`); **246 are genuine wrong matches with the correct company present in
the register**. Precision on reachable cases is **83.67%**.

**The dominant failure mode is a public body matching a private company of the same
name** — a government department, a passenger transport executive and a transport
authority all score 1.00 against unrelated private companies. Every one of them would
have been merged by a threshold. That is what the review queue is for.

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

A fourth ceiling sits under all of them: **the snapshot contains no dissolved companies**,
so a supplier that has since dissolved is unreachable at every tier — `limitations.md`
`P-16`.

## What is not claimed

- That the tier-4 matches are resolved. They are queued for review, with decisions blank.
- That 95.32% applies to the spend files. It is measured on Contracts Finder awards,
  which name suppliers in their own way.
- That the unresolved population is small. It is reported with its count and value.
