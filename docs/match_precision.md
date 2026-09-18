# Match precision — the `E-3` measurement

**Measured 2026-09-18** by `sql/90_validation/95_measure_match_precision.sql`, on the
**corrected blocking**. Published whether or not it flatters the method.

> **This figure went down when the method got better, and that is the point.** Tier-4
> precision read 81.40% under first-token blocking, which excluded register rivals from the
> comparison. Under the prefix filter, which provably excludes none, it reads **80.88%**. The
> earlier number was not better; it was measured with the rivals hidden.

## What is measured

Contracts Finder award notices state the supplier's Companies House number for part of their
population. Those awards have a **known correct answer**. The number is hidden, the matching
tiers are run on the supplier **name alone**, and the prediction is compared with the number
the buyer stated.

**Population: 24,507 known-answer awards, of which 24,506 are measurable.** One award carries
a company number and an empty supplier name, which normalises to nothing and can never be
matched by name.

**Tier 1 is excluded by construction.** It reads the buyer-stated number, which is the answer
being measured against. **Tier 3 cannot enter**: it needs a postcode on both sides, and
Contracts Finder publishes none. So `E-3` measures **tiers 2 and 4**.

## Result

| Tier | Method | Matches made | Correct | Wrong | Precision |
|---|---|---:|---:|---:|---:|
| 2 | Exact normalised name | 18,469 | 17,914 | 555 | **96.99%** |
| 4 | Token-set similarity, review only | 2,239 | 1,811 | 428 | **80.88%** |
| — | No match | 0 | — | — | — |
| **All** | | **20,708** | **19,725** | **983** | **95.25%** |

**Recall: 20,708 of 24,506 = 84.50%.** 3,798 awards receive no match at all.

**Tier 4 never auto-accepts** (`04` §3 hard rule 1). Its matches are counted here as
predictions so the method can be measured; in the resolved data they populate a review queue
with the score and the candidate count, decisions blank.

## Blocking — corrected 2026-09-18

Tier 4 cannot compare every name against 5.69 million companies, so it blocks. **How it
blocks decides which rivals a reviewer ever sees.**

The original method blocked on the **first core token**. It was a heuristic with no guarantee
behind it, and it failed on the most valuable row in the queue: `GREAT WESTERN RAILWAY`
scored 1.00 with `candidate_count = 1`, while `FIRST GREATER WESTERN LIMITED` — same
SIC 49100 passenger rail — was excluded from the comparison on the token `FIRST`.

The replacement is a **prefix filter on frequency-ordered tokens**:

- `score = c/(a+b−c) ≥ 0.5` implies `3c ≥ a+b`, so `b ≤ 2a` and `a ≤ 2b`.
- Order each token set by its frequency **in the register, rarest first**.
- Index only the first `p(x) = |x| − ⌈0.5·|x|⌉ + 1` tokens.
- **If two names can reach the floor, their prefixes must intersect** — otherwise the whole
  overlap would come from the suffixes, which are shorter than the required `⌈(a+b)/3⌉`.

So **no candidate that could reach the floor is excluded.** Measured over this register:

| Blocking | Candidate pairs | Guarantee |
|---|---:|---|
| Any shared token + length bound | 936,444,356 | Lossless, but 46% of pairs sit in one token |
| First token (original) | 99,930 scored | **None** |
| **Prefix filter (current)** | **86,927,511 → 997,229 scored** | **Lossless at the 0.5 floor** |

**What changed as a result:** the tier-4 population went from 7,513 names to **8,922**, and
names flagged ambiguous above threshold went from 61 to **102**. `candidate_count` was
understating ambiguity by a factor of roughly 1.7.

**What it does not fix.** The filter is lossless with respect to the **0.5 candidate floor**,
not with respect to reality. `GREAT WESTERN RAILWAY` and `FIRST GREATER WESTERN` share one
token of five and score **0.20** — now compared, and correctly below the floor. A trading name
that shares few tokens with its registered name is beyond token-set similarity altogether.
That is the scoring function's limit, and it is why tier 4 is reviewed and never merged.

## The threshold, and why it is 0.85

| Threshold | Matches | Precision | Recall | Tier-4 precision |
|---:|---:|---:|---:|---:|
| 0.50 | 23,572 | 86.83% | 96.19% | 50.03% |
| 0.65 | 22,061 | 91.18% | 90.02% | 61.28% |
| 0.70 | 21,135 | 94.19% | 86.24% | 74.76% |
| 0.80 | 20,818 | 94.99% | 84.95% | 79.18% |
| **0.85** | **20,708** | **95.25%** | **84.50%** | **80.88%** |
| 1.00 | 20,698 | 95.26% | 84.46% | 80.84% |

Above 0.85 the curve is flat — only **34** names sit between 0.85 and 0.99, because **2,682**
of the best candidates score exactly 1.00, where the token sets are identical and the
difference is word order or truncation rather than spelling. Below 0.70, tier-4 precision
falls away sharply.

**0.85 is the precision plateau that still leaves a queue worth reviewing: 2,716 names, 102
of them ambiguous**, with 6,206 scoring below it. Lowering to 0.70 would add 822 names and
cost 6.12 percentage points of tier-4 precision — a trade available on the evidence above.

## A warning about the queue

**Score 1.00 with a single candidate is not a safe bulk-accept.** Measured against the `E-3`
known answers, on the corrected blocking:

| Queue batch | Names | Correct | Wrong | Precision |
|---|---:|---:|---:|---:|
| Score 1.00, single candidate | 1,533 | 1,245 | 288 | **81.21%** |
| Score 1.00, ambiguous | 73 | 46 | 27 | 63.01% |
| Score 0.85–0.99 | 9 | 8 | 1 | 88.89% |

Only **42** of those 288 errors are explained by the answer being absent from the snapshot
(`P-12`); **246 are genuine wrong matches with the correct company present in the register**.
Precision on reachable cases is **83.50%** — roughly one in six wrong.

**The dominant failure mode is a public body matching a private company of the same name.** A
government department, a passenger transport executive and a transport authority all score
1.00 against unrelated private companies. Every one would have been merged by a threshold.
That is what the review queue is for.

## What limits this result, beyond the method

1. **496 of the 11,593 distinct known-answer companies are absent from the Companies House
   snapshot.** No method could reach them: at most 23,883 of the 24,507 awards are reachable.
2. **282 names are unreachable under blocking** — none of their prefix tokens appears in any
   company prefix — covering GBP 181,361,789.01 of spend. Under first-token blocking this was
   608 names and GBP 450,408,335.70, so the correction **more than halved** the blocking
   ceiling as well as removing the exclusion defect.
3. **The population is central-government-weighted.** The three local authorities publish
   company numbers at or near zero, so precision measured here does not generalise to
   local-authority spend. See `limitations.md` `P-1`.
4. **The snapshot contains no dissolved companies**, so a supplier that has since dissolved is
   unreachable at every tier — `limitations.md` `P-16`.

## What is not claimed

- That the tier-4 matches are resolved. They are queued for review, with decisions blank.
- That 95.25% applies to the spend files. It is measured on Contracts Finder awards, which
  name suppliers in their own way.
- That the unresolved population is small. It is reported with its count and value.
