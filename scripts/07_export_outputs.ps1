# 07_export_outputs.ps1
# Writes the eight Layer 4 extracts to data/outputs/ -- the Tableau source.
#
# Run from the repository root, in PowerShell (the bq CLI does not run under Git
# Bash on this machine):
#   .\scripts\07_export_outputs.ps1
#
# Needs sql/40_reporting/41-46 to have been run first; 46 builds the export_*
# tables this reads.
#
# DETERMINISTIC ORDER. Every query ends ORDER BY 1, and the first column of every
# export table is its unique key (an id, date_key, or spend_ref -- verified unique
# across all 352,528 fact rows). Without it BigQuery returns rows in whatever order
# the plan produces, so an unchanged table re-exports as a different file: found
# 2026-09-18, when four dimensions whose content had not changed showed as modified.
# A published file that churns on every run makes its own diff meaningless.
#
# CONFIDENTIALITY (H-7) is enforced upstream, in 46: no postcode, individual-looking
# unresolved names withheld. Re-run the H-7 review on the output before any commit.

param(
  [string]$Project = 'portfolio-508106',
  [string]$Dataset = 'portfolio_b'
)

$tables = 'dim_supplier', 'dim_entity', 'dim_date', 'dim_category',
          'dim_source_file', 'dim_vat_basis', 'fact_spend', 'fact_spend_unresolved'

New-Item -ItemType Directory -Force -Path 'data\outputs' | Out-Null

foreach ($t in $tables) {
  $out = "data\outputs\$t.csv"
  cmd /c "bq query --use_legacy_sql=false --format=csv --max_rows=400000 ""SELECT * FROM $Project.$Dataset.export_$t ORDER BY 1"" > $out" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "export failed: $t" }
  $rows = (Get-Content $out | Measure-Object -Line).Lines - 1
  '{0,-24} {1,9:N0} rows' -f $t, $rows
}
