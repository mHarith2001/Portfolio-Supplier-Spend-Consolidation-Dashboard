#!/usr/bin/env python3
"""
Portfolio B — Repository input setup (run this FIRST, before any other script)

===============================================================================
PREREQUISITES
===============================================================================
Run from        repository root
Python          3.8+, standard library only. No pip install needed.

READS (outside the repo — this is the whole point of the script):
    <VAULT>/data/provenance.csv                69 rows x 18 columns
    <VAULT>/data/raw/*.csv                     62 files, ~48 MB

    <VAULT> defaults to
    H:\\My Drive\\Obsidian\\Obsidian Vault\\03_projects\\
        Portfolio_Data_Analytic_Career\\06_ACTIVE_BUILD\\portfolio-b
    Override with --vault "<path>".

WRITES (inside the repo):
    docs/provenance.csv                        TRACKED — evidence, committed
    data/raw/*.csv                             62 files, GITIGNORED
    data/clean/.gitkeep                        creates the directory 08 s2.5 writes to

DOES NOT COPY:
    data/companies_house/*                     ~470 MB, already loaded to BigQuery,
                                               and blocked by name in .gitignore.
                                               It must never enter this tree.

===============================================================================
WHY THIS SCRIPT EXISTS
===============================================================================
data/raw/ and data/clean/ are gitignored and docs/provenance.csv is not produced
by any script in this repo. A fresh clone therefore CANNOT run the pipeline —
the inputs live in the Obsidian vault, outside version control, because they are
either too large or are acquisition evidence held in the project workspace.

Charter E-6 requires a clean-machine rebuild from scripts plus provenance. This
script is the first step of that rebuild. Without it, E-6 is not satisfiable.

===============================================================================
USAGE
===============================================================================
    python scripts/00_setup_inputs.py                 copy + verify SHA-256
    python scripts/00_setup_inputs.py --check         report only, copy nothing
    python scripts/00_setup_inputs.py --no-verify     copy, skip hashing
    python scripts/00_setup_inputs.py --force         re-copy files already present
    python scripts/00_setup_inputs.py --vault "D:\\..."

Idempotent. A file already present with a matching SHA-256 is left alone.
"""

from __future__ import annotations
import argparse, csv, hashlib, shutil, sys
from pathlib import Path

ROOT       = Path(__file__).resolve().parents[1]
RAW_DST    = ROOT / "data" / "raw"
CLEAN_DST  = ROOT / "data" / "clean"
PROV_DST   = ROOT / "docs" / "provenance.csv"

VAULT_DEFAULT = Path(
    r"H:\My Drive\Obsidian\Obsidian Vault\03_projects"
    r"\Portfolio_Data_Analytic_Career\06_ACTIVE_BUILD\portfolio-b"
)

EXPECTED_SPEND_FILES = 62           # 08 s1.1 row 1
EXPECTED_PROV_ROWS   = 69           # 08 s1.1 row 4 (62 spend + 7 Companies House)
EXPECTED_PROV_COLS   = 18


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(chunk), b""):
            h.update(block)
    return h.hexdigest().upper()


def read_provenance(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        sys.exit(f"FAIL  {path} is empty.")
    ncols = len(rows[0])
    if len(rows) != EXPECTED_PROV_ROWS or ncols != EXPECTED_PROV_COLS:
        print(f"WARN  provenance.csv is {len(rows)} rows x {ncols} columns; "
              f"08 s1.1 expects {EXPECTED_PROV_ROWS} x {EXPECTED_PROV_COLS}.")
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--vault", type=Path, default=VAULT_DEFAULT)
    ap.add_argument("--check",      action="store_true", help="report only, copy nothing")
    ap.add_argument("--no-verify",  action="store_true", help="skip SHA-256 verification")
    ap.add_argument("--force",      action="store_true", help="re-copy files already present")
    args = ap.parse_args()

    vault     = args.vault
    prov_src  = vault / "data" / "provenance.csv"
    raw_src   = vault / "data" / "raw"

    print("Portfolio B — input setup")
    print(f"  repo  : {ROOT}")
    print(f"  vault : {vault}")
    print()

    # -- source side -------------------------------------------------------
    missing = [p for p in (vault, prov_src, raw_src) if not p.exists()]
    if missing:
        print("FAIL  the vault source is not reachable. Missing:")
        for p in missing:
            print(f"       {p}")
        print()
        print("       If the vault is on a different drive or the Google Drive")
        print("       stream is not mounted, pass the correct path:")
        print('           python scripts/00_setup_inputs.py --vault "<path to portfolio-b>"')
        return 1

    prov_rows = read_provenance(prov_src)
    hashes = {
        r["local_file"]: (r.get("file_hash") or "").strip().upper()
        for r in prov_rows
        if r["local_file"].lower().endswith(".csv") and "BasicCompanyData" not in r["local_file"]
    }

    src_files = sorted(p for p in raw_src.glob("*.csv") if p.is_file())
    print(f"  source raw files      : {len(src_files)} (expect {EXPECTED_SPEND_FILES})")
    print(f"  provenance rows       : {len(prov_rows)}")
    print(f"  hashed spend files    : {len(hashes)}")
    if len(src_files) != EXPECTED_SPEND_FILES:
        print()
        print(f"FAIL  08 s1.2 requires exactly {EXPECTED_SPEND_FILES} files in data/raw/.")
        print("      A missing file means every count downstream will be wrong. Stop.")
        return 1

    # -- destination side --------------------------------------------------
    if args.check:
        have = sorted(p.name for p in RAW_DST.glob("*.csv"))
        print()
        print("CHECK ONLY — nothing copied.")
        print(f"  docs/provenance.csv   : {'present' if PROV_DST.exists() else 'ABSENT'}")
        print(f"  data/raw/*.csv        : {len(have)} of {EXPECTED_SPEND_FILES}")
        print(f"  data/clean/           : {'present' if CLEAN_DST.exists() else 'ABSENT'}")
        ready = PROV_DST.exists() and len(have) == EXPECTED_SPEND_FILES
        print()
        print("  READY" if ready else "  NOT READY — run without --check")
        return 0 if ready else 1

    RAW_DST.mkdir(parents=True, exist_ok=True)
    CLEAN_DST.mkdir(parents=True, exist_ok=True)
    PROV_DST.parent.mkdir(parents=True, exist_ok=True)
    gitkeep = CLEAN_DST / ".gitkeep"
    if not gitkeep.exists():
        gitkeep.write_text("", encoding="utf-8")

    shutil.copy2(prov_src, PROV_DST)
    print(f"\n  copied  docs/provenance.csv  ({PROV_DST.stat().st_size:,} bytes)")

    copied = skipped = 0
    mismatch: list[str] = []
    unhashed: list[str] = []

    for src in src_files:
        dst = RAW_DST / src.name
        if dst.exists() and not args.force and dst.stat().st_size == src.stat().st_size:
            skipped += 1
        else:
            shutil.copy2(src, dst)
            copied += 1

        if args.no_verify:
            continue
        expected = hashes.get(src.name)
        if not expected:
            unhashed.append(src.name)
            continue
        if sha256(dst) != expected:
            mismatch.append(src.name)

    print(f"  copied  data/raw/           {copied} file(s), {skipped} already present")

    # -- report ------------------------------------------------------------
    print()
    print("-" * 70)
    have = sorted(p.name for p in RAW_DST.glob("*.csv"))
    ok = True

    print(f"  1. data/raw/ file count      : {len(have):>3}   expect {EXPECTED_SPEND_FILES}"
          f"   {'PASS' if len(have) == EXPECTED_SPEND_FILES else 'FAIL'}")
    ok &= len(have) == EXPECTED_SPEND_FILES

    print(f"  2. docs/provenance.csv       : {'present':>7}"
          f"                {'PASS' if PROV_DST.exists() else 'FAIL'}")
    ok &= PROV_DST.exists()

    print(f"  3. data/clean/ exists        : {'yes':>7}"
          f"                {'PASS' if CLEAN_DST.exists() else 'FAIL'}")
    ok &= CLEAN_DST.exists()

    if args.no_verify:
        print("  4. SHA-256 verification      :  SKIPPED (--no-verify)")
    else:
        print(f"  4. SHA-256 vs provenance     : {len(mismatch):>3} mismatch"
              f"        {'PASS' if not mismatch else 'FAIL'}")
        ok &= not mismatch
        for name in mismatch:
            print(f"       MISMATCH  {name}")
        for name in unhashed:
            print(f"       no hash in provenance: {name}")
    print("-" * 70)

    if not ok:
        print("\nFAIL  setup incomplete. Do not run 05_preload_clean.py.")
        return 1

    print("\nOK    inputs are in place.")
    print("\nBEFORE the next step, confirm .gitignore covers data/clean/:")
    print("    git check-ignore -v data/clean/x.csv")
    print("  It must print a .gitignore line. If it prints nothing, STOP and")
    print("  amend .gitignore first — data/clean/ holds 62 derived CSVs and this")
    print("  repository is public.")
    print("\nThen:")
    print("    python scripts/05_preload_clean.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
