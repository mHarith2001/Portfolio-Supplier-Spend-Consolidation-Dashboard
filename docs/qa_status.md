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
| `Q3.2` | No tier-4 auto-merge | **PASS** — 1,510 queue rows, **0 non-blank decisions** |
| `Q3.3` | Ambiguity surfaced, never auto-accepted | **PASS** — `V3.6`, 0 accepted with `candidate_count > 1` |
| `Q3.4` | Plausibility applied | **PASS at every tier** — 0 of 175,470 attributed rows precede incorporation, and since 2026-09-18 hard rule 3 also filters tier-4 candidates: **0 impossible candidates remain in the queue** |
| `Q3.5` | Redacted population reported as a named category | **PASS** — 4 names, 31,508 rows, GBP 113,266,026.75, **0.2207%** of transaction value |
| `Q3.6` | Precision measured and published | **PASS** — `docs/match_precision.md` |
| `Q3.7` | Precision reported honestly | **PASS** — 95.25% overall published with tier 4's 80.86%, recall 84.49%, and three ceilings |
| `Q3.8` | `name_variant_count` produces the headline | **PASS** — 14,434 vendor records → 5,967 identified suppliers + 7,396 unidentified names |

### `Q3.4` — how it came to pass at every tier (2026-09-18)

It did not start that way. Tiers 1–3 rejected a candidate incorporated after the first
payment; **tier 4 did not**, and 107 of its 1,305 queued candidates were impossible on those
grounds, carrying GBP 64,259,806.06.

Nothing was ever mis-attributed — tier 4 resolves nothing — so `Q3.4` passed as written
throughout. It was fixed anyway, because 107 queue entries were costing a reviewer time on a
company that cannot be the payee. The queue fell to 1,199 tier-4 names and tier-4 precision
rose from 80.86% to 81.40%. See validation report §7.9.

## Tableau QA (`07` §4) — **BLOCKED**

`Q4.1`–`Q4.7` require the workbook. The extracts exist (`data/outputs/`, 8 files, 28.3 MB);
no workbook has been built. Nothing here is claimed.

## Evidence matrix (`07` §5)

| Row | Claim | Status |
|---|---|---|
| `E-1` | Multi-source integration | **VERIFIED** — 6 publishers, 62 files, `V1.1` and `V2.1` reconcile to `provenance.csv` |
| `E-2` | Entity resolution performed | **VERIFIED** — 5 tiers implemented, rules published in `04` |
| `E-3` | **Match quality measured, not asserted** | **VERIFIED** — 95.25% precision / 84.49% recall on 24,506 known-answer awards |
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

**`07` §8 sign-off is not ticked here.** That is a locked document, and `H-8` is explicit:
no token upgrade on the builder's say-so.
