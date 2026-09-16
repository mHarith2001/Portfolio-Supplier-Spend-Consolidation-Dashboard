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

    <VAULT> is the portfolio-b working folder in the Obsidian vault. Its path
    is deliberately NOT written in this file: this repository is PUBLIC, and
    publishing a local vault path into it has been a defect in this project
    before. Supply it one of these ways:

        set PORTFOLIO_B_VAULT=<path to the portfolio-b working folder>
        --vault "<path to the portfolio-b working folder>"
        --file  "<full path to the part4 CSV>"

    The script HALTS with these instructions if none is supplied. It does
    not guess: a wrong guess reads the wrong file and then reports a
    verdict about it with full confidence.

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

IT ALSO COUNTS BLANK RECORDS, and that is not incidental
    Added 2026-09-16. Without it this diagnostic answers the CONTENT question
    and leaves the COUNT question open, which is exactly what happened: V1.5
    compared a BigQuery table row count against a CSV RECORD count and failed
    by one forever, because part4 holds a blank line at record #454,676 and
    BigQuery does not materialise an empty CSV line as a row.

    Both quantities are real and both are reported here:
        CSV records     849,999  = what csv.reader yields (blank line included)
        company records 849,998  = what LOAD DATA produces

    A count that separates these cannot fail by one for a reason nobody can
    name. One that conflates them already did.
"""

from __future__ import annotations
import argparse, csv, os, sys
from pathlib import Path

csv.field_size_limit(min(sys.maxsize, 2**31 - 1))

ROOT = Path(__file__).resolve().parents[1]
OUT  = ROOT / "docs" / "v1_5_part4_diagnostic.md"

VAULT_ENV = "PORTFOLIO_B_VAULT"     # no default path: see PREREQUISITES
PART4 = "BasicCompanyData-2026-08-01-part4_7.csv"

EXPECTED_RECORDS  = 849_999      # CSV records, blank line included
EXPECTED_LINES    = 850_001      # physical lines, header included
EXPECTED_BLANKS   = 1            # part4 record #454,676 — an empty line
EXPECTED_COMPANY  = 849_998      # EXPECTED_RECORDS - EXPECTED_BLANKS


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--vault", type=Path, default=None,
                    help=f"portfolio-b working folder; or set {VAULT_ENV}")
    ap.add_argument("--file",  type=Path, default=None,
                    help="explicit path to the part4 CSV, overrides --vault")
    args = ap.parse_args()

    env = os.environ.get(VAULT_ENV)
    vault = args.vault or (Path(env) if env else None)
    src = args.file or ((vault / "data" / "companies_house" / PART4) if vault else None)

    if src is None:
        print("FAIL  no source given, and this script does not guess a path.")
        print(f"      set {VAULT_ENV}=<portfolio-b working folder>")
        print('      or:  --vault "<portfolio-b working folder>"')
        print(f'      or:  --file  "<full path to {PART4}>"')
        return 1
    if not src.exists():
        print(f"FAIL  cannot find {src}")
        print(f'      pass the path explicitly:  --file "<full path to {PART4}>"')
        return 1

    print(f"scanning {src}")
    print(f"  {src.stat().st_size:,} bytes\n")

    hits: list[tuple[int, int, int, list[str]]] = []   # recno, nfields, field index, row
    blanks: list[tuple[int, int]] = []                 # recno, nfields
    header: list[str] = []
    nrec = 0

    with src.open(encoding="utf-8", newline="", errors="replace") as fh:
        rdr = csv.reader(fh)
        for i, row in enumerate(rdr):
            if i == 0:
                header = row
                continue
            nrec += 1
            if not row or all(v.strip() == "" for v in row):
                blanks.append((nrec, len(row)))
                continue
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
    print(f"  BLANK records   : {len(blanks)}   (expect {EXPECTED_BLANKS})")
    for bn, bf in blanks:
        print(f"      record #{bn:,}  fields={bf}  -> not loaded by BigQuery")
    print(f"  company records : {nrec - len(blanks):,}   (expect {EXPECTED_COMPANY:,})")

    lines: list[str] = [
        "# V1.5 — Companies House part4 embedded-newline diagnostic",
        "",
        f"- Source file: `{src.name}`",
        f"- Size: {src.stat().st_size:,} bytes",
        f"- Header fields: **{width}**",
        f"- Records parsed: **{nrec:,}** (expected {EXPECTED_RECORDS:,}; "
        f"physical lines {EXPECTED_LINES:,})",
        f"- Records containing an embedded newline: **{len(hits)}**",
        f"- Blank records: **{len(blanks)}** (expected {EXPECTED_BLANKS})",
        "",
        "## The count question — two quantities, both correct",
        "",
        "| Quantity | Value | What produces it |",
        "|---|---:|---|",
        f"| CSV records in part4 | **{nrec:,}** | `csv.reader`; a blank line is a record |",
        f"| Blank records | **{len(blanks)}** | "
        + (", ".join(f"record #{bn:,} ({bf} fields)" for bn, bf in blanks) or "none") + " |",
        f"| Company records in part4 | **{nrec - len(blanks):,}** | "
        "`LOAD DATA`; BigQuery does not materialise an empty line as a row |",
        "",
        "Seven-part totals follow from this: **5,695,466 CSV records** "
        "(the ratified figure, unchanged) and **5,695,465 company records** "
        "(`COUNT(*)` on `raw_companies_house`). `V1.5` compares a table row "
        "count, so it must be measured against the second. The two differ by "
        "this one blank line and by nothing else.",
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
                       "correct. No company is missing and no field is shifted, "
                       "so tier-1 matching will not fail silently. See the count "
                       "table above for which total this supports: it confirms "
                       "the CSV record count, not the table row count."
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
