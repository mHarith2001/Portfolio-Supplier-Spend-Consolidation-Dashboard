-- 11_create_raw_spend.sql
-- Layer: L1 raw_
-- Validation for this layer: sql/90_validation/91_validate_raw.sql
--
-- EXECUTABLE. Run these statements; do not re-create them in the console UI.
-- Charter E-6 is "clean-machine rebuild from scripts + provenance" — a file
-- that narrates what was clicked is not a rebuild path.
--
-- PREREQUISITE: scripts/05_preload_clean.py has run and all four §2.6 checks
-- pass. These statements load data/clean/, never data/raw/.
--
-- Every column is STRING, per 03-schema-specification.md §2: Layer 1 loads as
-- published. No casting, no cleaning. Layer 2 parses, with the raw text still
-- visible beside the parsed value.
--
-- Target, fixed 2026-09-15 (no placeholders left to fill):
--   PROJECT  portfolio-508106
--   DATASET  portfolio_b
--   BUCKET   gs://portfolio-b-spend-mh2026/
--   PREFIX   clean/          <- the 62 pre-load outputs live HERE, not at root
--
-- ONE BUCKET, TWO PREFIXES. The bucket root holds the 7 Companies House part
-- files loaded by 12_create_raw_reference.sql; the clean spend files go under
-- clean/. That is deliberate: D-P-029 condition 2 then has exactly one bucket
-- to delete at step 8, instead of two and a chance to forget one.
--
-- Both loaders are therefore PREFIXED, never a bare '*.csv'. 12's URI is
-- 'BasicCompanyData-2026-08-01-part*_7.csv' at the root; each statement below
-- is 'clean/<Publisher>__*.csv'. A bare wildcard in either would sweep in the
-- other's objects and neither statement would reproduce its own result —
-- E-6 (clean-machine rebuild) fails on a statement that is not re-runnable.
--
-- UPLOAD COMMAND that puts the files where these URIs expect them:
--   gcloud storage cp data/clean/*.csv gs://portfolio-b-spend-mh2026/clean/
-- Verify 62 objects before loading:
--   gcloud storage ls gs://portfolio-b-spend-mh2026/clean/ | Measure-Object -Line

-- ---------------------------------------------------------------------------
-- Bristol City Council  ->  raw_spend_bristol   (14 columns: 9 canonical + 5 metadata)
-- ---------------------------------------------------------------------------
LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_spend_bristol`
(
  body STRING,
  body_name STRING,
  supplier_name_src STRING,
  amount_src STRING,
  payment_date_src STRING,
  transaction_number STRING,
  description_1 STRING,
  description_2 STRING,
  description_3 STRING,
  _source_file STRING,
  _source_url STRING,
  _retrieved_at STRING,
  _period STRING,
  _row_num STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/clean/Bristol_City_Council__*.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = true,
  allow_jagged_rows = false
);

-- ---------------------------------------------------------------------------
-- City of York Council  ->  raw_spend_york   (18 columns: 13 canonical + 5 metadata)
-- ---------------------------------------------------------------------------
LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_spend_york`
(
  body_name STRING,
  directorate STRING,
  department STRING,
  service_plan STRING,
  supplier_name_src STRING,
  payment_date_src STRING,
  transaction_number STRING,
  card_transaction STRING,
  amount_src STRING,
  irrecoverable_vat_src STRING,
  subjective_group STRING,
  subjective_subgroup STRING,
  subjective_detail STRING,
  _source_file STRING,
  _source_url STRING,
  _retrieved_at STRING,
  _period STRING,
  _row_num STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/clean/City_of_York_Council__*.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = true,
  allow_jagged_rows = false
);

-- ---------------------------------------------------------------------------
-- Department for Transport  ->  raw_spend_dft   (15 columns: 10 canonical + 5 metadata)
-- ---------------------------------------------------------------------------
LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_spend_dft`
(
  department_family STRING,
  entity STRING,
  payment_date_src STRING,
  expense_type STRING,
  expense_area STRING,
  supplier_name_src STRING,
  transaction_number STRING,
  description_1 STRING,
  amount_src STRING,
  supplier_postcode_src STRING,
  _source_file STRING,
  _source_url STRING,
  _retrieved_at STRING,
  _period STRING,
  _row_num STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/clean/Department_for_Transport__*.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = true,
  allow_jagged_rows = false
);

-- ---------------------------------------------------------------------------
-- HM Revenue and Customs  ->  raw_spend_hmrc   (19 columns: 14 canonical + 5 metadata)
-- ---------------------------------------------------------------------------
LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_spend_hmrc`
(
  department_family STRING,
  entity STRING,
  payment_date_src STRING,
  expense_type STRING,
  expense_area STRING,
  supplier_name_src STRING,
  transaction_number STRING,
  amount_src STRING,
  description_1 STRING,
  supplier_postcode_src STRING,
  supplier_type STRING,
  contract_number STRING,
  project_code STRING,
  expenditure_type STRING,
  _source_file STRING,
  _source_url STRING,
  _retrieved_at STRING,
  _period STRING,
  _row_num STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/clean/HM_Revenue_and_Customs__*.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = true,
  allow_jagged_rows = false
);

-- ---------------------------------------------------------------------------
-- Manchester City Council  ->  raw_spend_manchester   (13 columns: 8 canonical + 5 metadata)
-- ---------------------------------------------------------------------------
LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_spend_manchester`
(
  body_name STRING,
  business_area STRING,
  service_area STRING,
  expense_type STRING,
  payment_date_src STRING,
  transaction_number STRING,
  supplier_name_src STRING,
  amount_src STRING,
  _source_file STRING,
  _source_url STRING,
  _retrieved_at STRING,
  _period STRING,
  _row_num STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/clean/Manchester_City_Council__*.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = true,
  allow_jagged_rows = false
);

-- ---------------------------------------------------------------------------
-- Ministry of Justice  ->  raw_spend_moj   (14 columns: 9 canonical + 5 metadata)
-- ---------------------------------------------------------------------------
LOAD DATA OVERWRITE `portfolio-508106.portfolio_b.raw_spend_moj`
(
  department_family STRING,
  entity STRING,
  payment_date_src STRING,
  expense_type STRING,
  expense_area STRING,
  supplier_name_src STRING,
  transaction_number STRING,
  amount_src STRING,
  description_1 STRING,
  _source_file STRING,
  _source_url STRING,
  _retrieved_at STRING,
  _period STRING,
  _row_num STRING
)
FROM FILES (
  format = 'CSV',
  uris = ['gs://portfolio-b-spend-mh2026/clean/Ministry_of_Justice__*.csv'],
  skip_leading_rows = 1,
  allow_quoted_newlines = true,
  allow_jagged_rows = false
);

-- allow_jagged_rows = false is deliberate and differs from the Companies House
-- load. The clean files are written by our own script with a fixed column count,
-- so a short row means the pre-load step malfunctioned. Let it fail loudly.
