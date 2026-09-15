#!/usr/bin/env python3
"""
Portfolio B — Identify and classify the embedded-newline record in Companies
House part4 (V1.5 diagnostic, ruling (b))

===============================================================================
PREREQUISITES
===============================================================================
Run from        repository root
Python          3.8+, standard library only. No pip install needed.

READS (outside the repo — NOT copied in by 00_setup_inputs.py, deliberately):
    <VAULT>/data/companies_house/BasicCompanyData-2026-08-01-part4_7.csv
                                               ~417 MB

    <VAULT> defaults to
    H:\\My Drive\\Obsidian\\Obsidian Vault\\03_projects\\
        Portfolio_Data_Analytic_Career\\06_ACTIVE_BUILD\\portfolio-b
    Override with --vault "<path>" or point at the file with --file "<path>".

WRITES:
    docs/v1_5_part4_diagnostic.md              TRACKED — this is the evidence
                                               that closes V1.5

DOES NOT:
    copy, move or modify the source file. Read-only, streaming.

MEMORY / TIME
    Streams one record at a time; peak memory is one record, not one file.
    Safe on 8 GB. Expect roughly 1-3 minutes on a mechanical or network drive —
    if the vault is on the Google Drive stream, copy the file to a local disk
    first or the read will be bound by the network, not the CPU.

===============================================================================
WHAT IT DECIDES
===============================================================================
part4 holds 850,001 physical lines but parses to 849,999 records. One record
therefore spans two physical lines. There are two possibilities and they
require opposite responses:

  LEGITIMATE QUOTED NEWLINE
      A real newline inside a properly quoted field (an address line, most
      likely). The record is INTACT, field count is correct, 849,999 is the
      true record count, and the load is correct. No action.

  MALFORMED STRAY QUOTE
      An unbalanced quote character made the parser swallow the following line.
      TWO real company records were merged into one: one company is absent from
      the table entirely and another has corrupted fields. Tier-1 matching on
      CompanyNumber would then fail SILENTLY for those companies.

The test is the field count. Companies House BasicCompanyData has a fixed
header; a legitimate quoted newline leaves the field count unchanged, a stray
quote does not. The script reports the header width, the offending record's
width, and the field that contains the newline.
"""

from __future__ import annotations
import argparse, csv, sys
from pathlib import Path

csv.field_size_limit(min(sys.maxsize, 2**31 - 1))

ROOT = Path(__file__).resolve().parents[1]
OUT  = ROOT / "docs" / "v1_5_part4_diagnostic.md"

VAULT_DEFAULT = Path(
    r"H:\My Drive\Obsidian\Obsidian Vault\03_projects"
    r"\Portfolio_Data_Analytic_Career\06_ACTIVE_BUILD\portfolio-b"
)
PART4 = "BasicCompanyData-2026-08-01-part4_7.csv"

EXPECTED_RECORDS = 849_999
EXPECTED_LINES   = 850_001


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--vault", type=Path, default=VAULT_DEFAULT)
    ap.add_argument("--file",  type=Path, default=None,
                    help="explicit path to the part4 CSV, overrides --vault")
    args = ap.parse_args()

    src = args.file or (args.vault / "data" / "companies_house" / PART4)
    if not src.exists():
        print(f"FAIL  cannot find {src}")
        print('      pass the path explicitly:  --file "<path to part4 csv>"')
        return 1

    print(f"scanning {src}")
    print(f"  {src.stat().st_size:,} bytes\n")

    hits: list[tuple[int, int, int, list[str]]] = []   # recno, nfields, field index, row
    header: list[str] = []
    nrec = 0

    with src.open(encoding="utf-8", newline="", errors="replace") as fh:
        rdr = csv.reader(fh)
        for i, row in enumerate(rdr):
            if i == 0:
                header = row
                continue
            nrec += 1
            for j, val in enumerate(row):
                if "\n" in val or "\r" in val:
                    hits.append((nrec, len(row), j, row))
                    break
            if nrec % 100_000 == 0:
                print(f"  {nrec:,} records...")

    width = len(header)
    print(f"\n  header fields   : {width}")
    print(f"  records parsed  : {nrec:,}   (expect {EXPECTED_RECORDS:,})")
    print(f"  records with an embedded newline: {len(hits)}")

    lines: list[str] = [
        "# V1.5 — Companies House part4 embedded-newline diagnostic",
        "",
        f"- Source file: `{src.name}`",
        f"- Size: {src.stat().st_size:,} bytes",
        f"- Header fields: **{width}**",
        f"- Records parsed: **{nrec:,}** (expected {EXPECTED_RECORDS:,}; "
        f"physical lines {EXPECTED_LINES:,})",
        f"- Records containing an embedded newline: **{len(hits)}**",
        "",
    ]

    if not hits:
        verdict = ("NO embedded newline found. The record-count gap has another "
                   "cause and V1.5 is NOT closed by this diagnostic.")
        print(f"\n  VERDICT: {verdict}")
        lines += ["## Verdict", "", verdict, ""]
    else:
        lines += ["## Findings", ""]
        for recno, nfields, j, row in hits:
            intact = (nfields == width)
            colname = header[j] if j < len(header) else f"(field {j})"
            verdict = ("LEGITIMATE QUOTED NEWLINE — record intact, field count "
                       "correct. 849,999 is the true record count and the load "
                       "is correct."
                       if intact else
                       "MALFORMED — field count differs from the header. Two "
                       "records were merged. This is real corruption and part4 "
                       "must be repaired and reloaded.")
            print(f"\n  record #{recno:,}")
            print(f"    fields in record : {nfields}  (header {width})  "
                  f"{'MATCH' if intact else 'MISMATCH'}")
            print(f"    newline in field : [{j}] {colname}")
            print(f"    CompanyName      : {row[0][:80] if row else ''}")
            print(f"    CompanyNumber    : {row[1][:40] if len(row) > 1 else ''}")
            print(f"    VERDICT          : {verdict}")

            lines += [
                f"### Record #{recno:,}",
                "",
                f"| Property | Value |",
                f"|---|---|",
                f"| Fields in record | **{nfields}** |",
                f"| Fields in header | **{width}** |",
                f"| Field count matches | **{'YES' if intact else 'NO'}** |",
                f"| Newline in field | `[{j}] {colname}` |",
                f"| CompanyName | `{row[0][:120] if row else ''}` |",
                f"| CompanyNumber | `{row[1][:40] if len(row) > 1 else ''}` |",
                "",
                "Field value containing the newline, repr-escaped:",
                "",
                "```text",
                repr(row[j])[:2000],
                "```",
                "",
                f"**Verdict:** {verdict}",
                "",
            ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nwrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
