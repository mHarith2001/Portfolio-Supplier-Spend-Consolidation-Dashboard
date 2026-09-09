#!/usr/bin/env bash
# ==============================================================================
# Portfolio B — Phase 3 Step 0 scaffold
# Repository: Portfolio-Supplier-Spend-Consolidation-Dashboard  (PUBLIC)
#
# RUN THIS ONLY AFTER:
#   1. the repo is cloned empty
#   2. .gitignore is committed ALONE as the first commit
#   3. `git status --ignored` has been verified
#
# It refuses to run if .gitignore is not already committed.
# It creates structure only. No data file is created, downloaded or moved.
# ==============================================================================
set -euo pipefail

# --- Guard 1: we are inside a git work tree -----------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "REFUSED: not inside a git repository." >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

# --- Guard 2: .gitignore is COMMITTED, not merely present ---------------------
if ! git cat-file -e HEAD:.gitignore 2>/dev/null; then
  echo "REFUSED: .gitignore is not committed at HEAD." >&2
  echo "         The binding sequence is: commit .gitignore ALONE first," >&2
  echo "         verify with 'git status --ignored', then run this script." >&2
  exit 1
fi

# --- Guard 3: nothing else is tracked yet -------------------------------------
tracked=$(git ls-files | grep -v '^\.gitignore$' || true)
if [ -n "$tracked" ]; then
  echo "WARNING: files other than .gitignore are already tracked:" >&2
  echo "$tracked" >&2
  read -r -p "Continue anyway? [y/N] " ans
  [ "$ans" = "y" ] || exit 1
fi

echo "==> Guards passed. .gitignore is committed at HEAD."

# --- Directory tree -----------------------------------------------------------
echo "==> Creating directory tree"
mkdir -p data/raw data/interim data/outputs
mkdir -p scripts
mkdir -p sql/10_raw sql/20_staging sql/30_resolved sql/40_reporting sql/90_validation
mkdir -p tableau/screenshots
mkdir -p docs/figures
mkdir -p .github

# .gitkeep placeholders — data/raw and data/interim are ignored except these
touch data/raw/.gitkeep data/interim/.gitkeep data/outputs/.gitkeep
touch tableau/screenshots/.gitkeep docs/figures/.gitkeep

# --- SQL placeholders, numbered by layer decade (06 §2) -----------------------
echo "==> Creating SQL placeholders"
sql_files=(
  "sql/10_raw/11_create_raw_spend.sql"
  "sql/10_raw/12_create_raw_reference.sql"
  "sql/20_staging/21_stage_spend_union.sql"
  "sql/20_staging/22_normalise_names.sql"
  "sql/20_staging/23_stage_reference.sql"
  "sql/30_resolved/31_match_tier1_company_number.sql"
  "sql/30_resolved/32_match_tier2_exact_name.sql"
  "sql/30_resolved/33_match_tier3_name_postcode.sql"
  "sql/30_resolved/34_match_tier4_fuzzy.sql"
  "sql/30_resolved/35_build_golden_record.sql"
  "sql/30_resolved/36_resolve_spend.sql"
  "sql/40_reporting/41_dim_supplier.sql"
  "sql/40_reporting/42_dim_entity.sql"
  "sql/40_reporting/43_dim_date.sql"
  "sql/40_reporting/44_dim_category.sql"
  "sql/40_reporting/45_fact_spend.sql"
  "sql/90_validation/91_validate_raw.sql"
  "sql/90_validation/92_validate_staging.sql"
  "sql/90_validation/93_validate_resolved.sql"
  "sql/90_validation/94_validate_reporting.sql"
  "sql/90_validation/95_measure_match_precision.sql"
)
for f in "${sql_files[@]}"; do
  [ -f "$f" ] || printf -- "-- %s\n-- Not yet written. Phase 3.\n-- Rules: 05a_PREP_PACKAGES/portfolio-b-prep-package/08-transformation-guidelines.md\n" "$(basename "$f")" > "$f"
done

# --- Python script placeholders ----------------------------------------------
echo "==> Creating script placeholders"
for f in 01_download_spend 02_download_companies_house 03_download_contracts_finder 04_profile_sources; do
  [ -f "scripts/${f}.py" ] || printf '"""%s — not yet written. Phase 3.\n\nAcquisition closed 2026-08-29; these scripts reproduce it from provenance.csv.\n"""\n' "$f" > "scripts/${f}.py"
done

echo "==> Scaffold created. Nothing staged yet."
echo
echo "NEXT — verify the ignore rules actually bite, then commit:"
echo
echo "  git status --ignored --short"
echo "  git add -A"
echo "  git status --short          # <- READ THIS. Nothing under data/raw or data/interim"
echo "                              #    should appear except the two .gitkeep files."
echo "  git commit -m 'Step 0: repository scaffold — structure only, no data'"
echo "  git push"
