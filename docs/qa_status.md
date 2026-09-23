# QA status against the checklist

**Measured 2026-09-18.** Every figure here was regenerated in the same session from the
built tables. Items that cannot yet be evidenced are marked **BLOCKED**, with what blocks
them — an unticked box is more useful than a tick that is not true.

## Per-layer validation (`07` §2)

| Layer | Rules | Status |
|---|---|---|
| L1 `raw_` | `V1.1`–`V1.5`, `V1.4a` | **PASS** — `91_validate_raw.sql` |
| L2 `staging_` | `V2.1`–`V2.12`, `V2.9a/b/c`, `V2.R1`–`V2.R8` | **PASS** — `92_validate_staging.sql` |
| L3 `resolved_` | `V3.1`–`V3.17` | **PASS** — `93_validate_resolved.sql`. `V3.1`/`V3.2` are the non-negotiable pair and both hold |
| L4 `reporting_` | `V4.1`–`V4.6` | **PASS** — `94_validate_reporting.sql` |

## Entity-resolution QA (`07` §3)

| # | Check | Status |
|---|---|---|
| `Q3.1` | Tier distribution by count **and value** | **PASS** — validation report §7.4 |
| `Q3.2` | No tier-4 auto-merge | **PASS** — 1,351 queue rows, one per name, **no auto-accept anywhere**; 220 decisions, each with its basis recorded — 81 by the user, 139 delegated under the Tier C authorisation and controlled by `D.5`–`D.11` — and 1,134 open |
| `Q3.3` | Ambiguity surfaced, never auto-accepted | **PASS** — `V3.6`: 0 method accepts with `candidate_count > 1`. Two ties were resolved by **user decision** on same-payer evidence (2026-09-24), under an override the user scoped to those two names; `D.10` fails on any other |
| `Q3.4` | Plausibility applied | **PASS at every tier** — 0 of 182,784 attributed rows precede incorporation, and since 2026-09-18 hard rule 3 also filters tier-4 candidates: **0 impossible candidates remain in the queue** |
| `Q3.5` | Redacted population reported as a named category | **PASS** — 4 names, 31,508 rows, GBP 113,266,026.75, **0.2207%** of transaction value |
| `Q3.6` | Precision measured and published | **PASS** — `docs/match_precision.md` |
| `Q3.7` | Precision reported honestly | **PASS** — 95.27% overall published with tier 4's 81.24%, recall 84.48%, and four ceilings, including a figure that **fell** when blocking was corrected |
| `Q3.8` | `name_variant_count` produces the headline | **PASS** — 14,434 vendor records → 6,066 identified suppliers + 7,180 unidentified names |

### `Q3.4` — how it came to pass at every tier (2026-09-18)

It did not start that way. Tiers 1–3 rejected a candidate incorporated after the first
payment; **tier 4 did not**, and 107 of its 1,305 queued candidates were impossible on those
grounds, carrying GBP 64,259,806.06.

Nothing was ever mis-attributed — tier 4 resolves nothing — so `Q3.4` passed as written
throughout. It was fixed anyway, because 107 queue entries were costing a reviewer time on a
company that cannot be the payee. The queue fell to 1,199 tier-4 names. See validation report
§7.9 — and §7.10, where correcting tier-4 blocking re-measured precision again on a sounder
basis.

## Tableau QA (`07` §4) — **BLOCKED**

`Q4.1`–`Q4.7` require the workbook. The extracts exist (`data/outputs/`, 8 files, 28.3 MB);
no workbook has been built. Nothing here is claimed.

## Evidence matrix (`07` §5)

| Row | Claim | Status |
|---|---|---|
| `E-1` | Multi-source integration | **VERIFIED** — 6 publishers, 62 files, `V1.1` and `V2.1` reconcile to `provenance.csv` |
| `E-2` | Entity resolution performed | **VERIFIED** — 5 tiers implemented, rules published in `04` |
| `E-3` | **Match quality measured, not asserted** | **VERIFIED** — 95.27% precision / 84.48% recall on 24,506 known-answer awards |
| `E-4` | Dimensional model | **VERIFIED** — `V4.2` and `V4.6` pass, grain documented per table |
| `E-5` | **Spend restated, not altered** | **VERIFIED** — `V3.1`, `V3.2`, `V4.1`: 352,614 rows and GBP 53,886,855,841.10 preserved, difference 0.00 |
| `E-6` | Reproducibility | **BLOCKED** — no clean-machine rebuild has been run |
| `E-7` | Public artefact | **PARTIAL** — the repository is public; Tableau Public is not yet published |

## Completion gate (`07` §6)

| Gate | Status |
|---|---|
| RUN | **BLOCKED** — not executed end to end on a clean machine |
| RECONCILE | **PASS** — `V3.1`, `V3.2`, `V4.1` all hold; `V1.1` ties to source counts |
| DOCUMENT | **COMPLETE** — README, `validation_report.md`, `match_precision.md`, `review_queue.csv`, `limitations.md`, `schema.md`, `entity_resolution.md`, `data_dictionary.md`. The `limitations.md` citation in `match_precision.md` now resolves |
| PUBLISH | **PARTIAL** — GitHub is public and carries no raw register. Tableau Public not published |
| EXPLAIN | Not attempted — `07` §7 |

**`07` §8: §2 and §3 were signed off by the user on 2026-09-23** and are recorded in the locked
checklist with a dated backup. The remaining items are not ticked, and `H-8` stands: no token
upgrade on the builder's say-so.

## What is ready for the handler to sign, and what is not (2026-09-22)

| `07` §8 item | Builder's reading |
|---|---|
| §2 per-layer validation | **☑ Signed off by the user, 2026-09-23** |
| §3 entity-resolution QA | **☑ Signed off by the user, 2026-09-23** — the open queue stays published as a limitation |
| §4 Tableau QA | **Not ready** — no workbook |
| §5 evidence matrix | **Partly** — `E-1`–`E-5` verified; `E-6` blocked, `E-7` partial |
| §6 completion gate | **Not ready** — RUN and EXPLAIN outstanding, PUBLISH partial |
| §7 explain test | **Not attempted** |

**The open review queue does not block sign-off of §2 or §3** — it is recorded in
`limitations.md` §6 as an open human-review register, which is what `07` asks for: a
limitation stated, with its count and value.
