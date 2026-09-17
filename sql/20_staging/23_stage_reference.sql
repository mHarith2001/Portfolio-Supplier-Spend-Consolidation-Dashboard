-- 23_stage_reference.sql
-- Layer: L2 staging_
-- Validation for this layer: sql/90_validation/92_validate_staging.sql
--
-- EXECUTED 2026-09-17. These are the statements that ran.
--
-- RUN 22_normalise_names.sql FIRST. Both tables call normalise_name() and
-- canon_company_number(). Run from a file on standard input (bq query ... < file).
--
-- Target schema: 03-schema-specification.md §3, staging_companies and
-- staging_contracts. Canonicalisation: 08 §7.2, including the society and mutual
-- pass-through rung added 2026-09-17.
--
-- ===========================================================================
-- staging_companies — one row per Companies House company
-- ===========================================================================
-- company_number is the canonical form (08 §7.2) and the primary key.
--
-- 93 COMPANIES ARE NOT STAGED, DELIBERATELY AND REVERSIBLY. The ladder does not
-- canonicalise the old-style 'R' + 7-digit numbers, so those 93 have no key and
-- cannot be matched at tier 1. An 'R' rung was tested and NOT adopted: it moves
-- the Contracts Finder figures by one record, a genuine Companies House number
-- registered to a different company from the supplier named against it, which
-- would become a high-confidence tier-1 match to the wrong company (08 §7.3).
-- Excluding the 93 is the builder's handling while that proposal is open; if an
-- 'R' rung is ruled in, one UDF rung and a re-run of this statement restores them.
-- Measured 2026-09-17: 5,695,465 in raw_companies_house, 93 rejected, 5,695,372
-- staged. V2.R1 in 92_validate_staging.sql reconciles those counts exactly.
--
-- DATA PROTECTION. Registered-office postcodes may be residential (charter L-3).
-- Only the postcode is carried, for tier-3 matching; no address lines. This table
-- never leaves BigQuery.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.staging_companies` AS
SELECT
  `portfolio-508106.portfolio_b.canon_company_number`(t.` CompanyNumber`) AS company_number,
  t.CompanyName                                                           AS company_name,
  `portfolio-508106.portfolio_b.normalise_name`(t.CompanyName)            AS company_name_norm,
  NULLIF(TRIM(t.CompanyStatus), '')                                       AS company_status,
  t.IncorporationDate                                                     AS incorporation_date,
  NULLIF(TRIM(t.RegAddress_PostCode), '')                                 AS postcode,
  NULLIF(TRIM(t.SICCode_SicText_1), '')                                   AS sic_code
FROM `portfolio-508106.portfolio_b.raw_companies_house` t
WHERE `portfolio-508106.portfolio_b.canon_company_number`(t.` CompanyNumber`) IS NOT NULL;

-- ===========================================================================
-- staging_contracts — one row per Contracts Finder award line
-- ===========================================================================
-- GRAIN: one row per raw_contracts_finder row — a release naming one supplier.
-- release_id is NOT unique: measured 2026-09-17, 76,449 rows carry 60,226
-- distinct releases. 166 rows repeat an earlier (release, supplier, identifier)
-- key across 136 keys; no two rows are fully identical (they differ in release
-- date or weekly slice), and NONE of the 136 keys carries a Companies House
-- number, so E-3's known-answer subset contains no repeats. Nothing is
-- de-duplicated at Layer 2: dropping rows needs a rule, and none is ruled.
--
-- THE GAP, RECORDED RATHER THAN FILLED (ruled 2026-09-17).
--   award_value     03 §3 requires it. Contracts Finder, as acquired, carries no
--   classification  value and no procurement classification: 9 columns, none of
--                   either kind. Its `category` column holds the identifier
--                   scheme (none / GB-COH / other_scheme), not a contract class.
--                   Both columns are carried as TYPED NULL so the schema holds
--                   and no downstream query invents a value. 05 V4.3 was
--                   re-scoped so categories do not depend on Contracts Finder.
--   award_date      Contracts Finder carries release_date, the award notice's
--                   publication timestamp, not the date the contract was awarded.
--                   It is carried as award_date — LABELLED APPROXIMATION. No
--                   match tier uses it.
--
-- supplier_company_number is set only where the release states a Companies House
-- number (category = 'GB-COH') and the ladder accepts it. That subset is E-3's
-- known answer. REQUIRED 2026-09-17: 24,507 non-null, 11,593 distinct — the
-- 08 §7.3 figures.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.staging_contracts` AS
SELECT
  ocid                                                          AS release_id,
  NULLIF(TRIM(buyer), '')                                       AS buyer_name,
  supplier_name                                                 AS supplier_name_raw,
  `portfolio-508106.portfolio_b.normalise_name`(supplier_name)  AS supplier_name_norm,
  IF(category = 'GB-COH',
     `portfolio-508106.portfolio_b.canon_company_number`(identifier),
     NULL)                                                      AS supplier_company_number,
  CAST(NULL AS NUMERIC)                                         AS award_value,
  DATE(SAFE_CAST(release_date AS TIMESTAMP))                    AS award_date,
  CAST(NULL AS STRING)                                          AS classification
FROM `portfolio-508106.portfolio_b.raw_contracts_finder`;
