# Match precision — the `E-3` measurement

**Re-measured 2026-09-20** by `sql/90_validation/95_measure_match_precision.sql`, on the
corrected blocking **and the OE-free match universe**. Published whether or not it flatters the method.

> **This figure went down when the method got better, and that is the point.** Tier-4
> precision read 81.40% under first-token blocking, which excluded register rivals from the
> comparison. Under the prefix filter, which provably excludes none, it read **80.88%**. The
> earlier number was not better; it was measured with the rivals hidden.
>
> **It reads 81.24% since 2026-09-20**, when 30,199 overseas-entity registrations were removed
> from candidacy (`04` §3 hard rule 8). That is a different method again, so it is a different
> measurement — not a revision of the same one.

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
| 2 | Exact normalised name | 18,512 | 17,944 | 568 | **96.93%** |
| 4 | Token-set similarity, review only | 2,191 | 1,780 | 411 | **81.24%** |
| — | No match | 0 | — | — | — |
| **All** | | **20,703** | **19,724** | **979** | **95.27%** |

**Recall: 20,703 of 24,506 = 84.48%.** 3,803 awards receive no match at all.

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
| **Prefix filter (current)** | **86,927,511 → 991,640 scored** | **Lossless at the 0.5 floor** |

The two blocking-cost figures were measured 2026-09-18, before the OE exclusion; the scored
count is current.

**What changed as a result:** the tier-4 population went from 7,513 names to **8,883**, and
names flagged ambiguous above threshold went from 61 to **75**. `candidate_count` was
understating ambiguity.

**What it does not fix.** The filter is lossless with respect to the **0.5 candidate floor**,
not with respect to reality. `GREAT WESTERN RAILWAY` and `FIRST GREATER WESTERN` share one
token of five and score **0.20** — now compared, and correctly below the floor. A trading name
that shares few tokens with its registered name is beyond token-set similarity altogether.
That is the scoring function's limit, and it is why tier 4 is reviewed and never merged.

## The threshold, and why it is 0.85

| Threshold | Matches | Precision | Recall | Tier-4 precision |
|---:|---:|---:|---:|---:|
| 0.50 | 23,548 | 86.92% | 96.09% | 50.10% |
| 0.65 | 22,053 | 91.21% | 89.99% | 61.28% |
| 0.70 | 21,129 | 94.21% | 86.22% | 74.97% |
| 0.80 | 20,812 | 95.01% | 84.93% | 79.52% |
| **0.85** | **20,703** | **95.27%** | **84.48%** | **81.24%** |
| 1.00 | 20,694 | 95.27% | 84.44% | 81.16% |

Above 0.85 the curve is flat — only **33** names sit between 0.85 and 0.99, because **2,655**
of the best candidates score exactly 1.00, where the token sets are identical and the
difference is word order or truncation rather than spelling. Below 0.70, tier-4 precision
falls away sharply.

**0.85 is the precision plateau that still leaves a queue worth reviewing: 2,688 names, 75
of them ambiguous**, with 6,195 scoring below it. Lowering to 0.70 would add 821 names and
cost 6.27 percentage points of tier-4 precision — a trade available on the evidence above.

## A warning about the queue

**Score 1.00 with a single candidate is not a safe bulk-accept.** Measured against the `E-3`
known answers, on the corrected blocking:

| Queue batch | Names | Correct | Wrong | Precision |
|---|---:|---:|---:|---:|
| Score 1.00, single candidate | 1,534 | 1,246 | 288 | **81.23%** |
| Score 1.00, ambiguous | 48 | 31 | 17 | 64.58% |
| Score 0.85–0.99 | 8 | 8 | 0 | 100.00% |

Only **42** of those 288 errors are explained by the answer being absent from the matchable
universe (`P-12`); **246 are genuine wrong matches with the correct company present in it**.
Precision on reachable cases is **83.51%** — roughly one in six wrong.

**The dominant failure mode is a public body matching a private company of the same name.** A
government department, a passenger transport executive and a transport authority all score
1.00 against unrelated private companies. Every one would have been merged by a threshold.
That is what the review queue is for.

## What limits this result, beyond the method

1. **496 of the 11,593 distinct known-answer companies are absent from the Companies House
   snapshot.** No method could reach them: at most 23,883 of the 24,507 awards are reachable.
2. **283 names are unreachable under blocking** — none of their prefix tokens appears in any
   company prefix — covering GBP 181,361,789.01 of spend. Under first-token blocking this was
   608 names and GBP 450,408,335.70, so the correction **more than halved** the blocking
   ceiling as well as removing the exclusion defect.
3. **The population is central-government-weighted.** The three local authorities publish
   company numbers at or near zero, so precision measured here does not generalise to
   local-authority spend. See `limitations.md` `P-1`.
4. **The snapshot contains no dissolved companies**, so a supplier that has since dissolved is
   unreachable at every tier — `limitations.md` `P-16`.

## The match universe — `OE` entries excluded (2026-09-20)

The snapshot carries **30,199 `OE`-prefixed Register of Overseas Entities registrations**. An
overseas entity is a foreign body recorded as owning UK land; it is not a UK company and its
`OE` number is not a company number. Matching a supplier to one is a **register-semantics
mismatch, not a scoring error**, so `OE` entries are excluded at candidate generation (`04`
§3 hard rule 8).

**Found on the `NEXUS` row**, where a statutory transport executive scored 1.00 against an
overseas property registration for GBP 106,362,560.99.

**The exclusion raised method resolution rather than lowering it.** Tier-2 acceptances went
from 13,488 to **13,504**: names where a real company and an `OE` registration shared a name
had been rejected as *ambiguous*, and removing the `OE` entry left a single candidate.
Resolution by method rose from 58.32% to **58.43%**.

**What it cost, measured before the change:** 6 names had resolved to an `OE` registration by
exact name (GBP 543,565.40) — and **no non-`OE` company carries any of those names**, so they
were right-entity / wrong-identifier-class rather than wrong-entity errors. They are now
unresolved and surfaced for decision, not quietly dropped.

## What is not claimed

- That the tier-4 matches are resolved. They are queued for review, with decisions blank.
- That 95.27% applies to the spend files. It is measured on Contracts Finder awards, which
  name suppliers in their own way.
- That the unresolved population is small. It is reported with its count and value.
