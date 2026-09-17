-- 42_dim_entity.sql
-- Layer: L4 reporting_
-- Validation for this layer: sql/90_validation/94_validate_reporting.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input.
--
-- Six publishing bodies, central or local. `entity` is the PUBLISHER — the body
-- whose disclosure the file is — not the source body named inside the file: for
-- four of the six those differ, which is `09` P-11 and the reason the column is
-- defined rather than assumed.
--
-- The key is the entity name itself. Six short, unique, human-readable values do
-- not need a surrogate, and a surrogate here would make every Tableau filter one
-- join longer for nothing.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.dim_entity` AS
SELECT
  entity,
  ANY_VALUE(publisher_type)                            AS publisher_type,
  COUNT(*)                                             AS transaction_rows,
  ROUND(SUM(amount), 2)                                AS transaction_value,
  COUNT(DISTINCT supplier_key)                         AS distinct_suppliers,
  MIN(payment_date)                                    AS first_payment,
  MAX(payment_date)                                    AS last_payment,
  COUNT(DISTINCT _source_file)                         AS source_files
FROM `portfolio-508106.portfolio_b.resolved_spend`
WHERE row_role = 'transaction'
GROUP BY entity;
