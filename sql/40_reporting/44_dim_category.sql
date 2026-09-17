-- 44_dim_category.sql
-- Layer: L4 reporting_
-- Validation for this layer: sql/90_validation/94_validate_reporting.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input.
--
-- ===========================================================================
-- CATEGORIES ARE THE PUBLISHER'S OWN VOCABULARY, NOT A HARMONISED ONE
-- ===========================================================================
-- 03 §5, re-sourced 2026-09-17: Contracts Finder supplies no procurement
-- classification, so categories come from each publisher's own expense type.
-- The grain is therefore (entity, expense_type_raw) and NOT expense_type alone.
--
-- TWO LIMITS TRAVEL WITH THIS TABLE and belong on the dashboard beside it:
--   * Categories are NOT comparable across publishers. 'Professional Services'
--     at one body and at another are two different vocabularies that happen to
--     share a string. The entity is part of the key so the two never merge.
--   * Bristol's expense types are a LABELLED INFERENCE (09 P-15): it publishes
--     the field unlabelled, as 'Description 1'.
--
-- THE `uncategorised` MEMBER IS MANDATORY (V4.3). Measured 2026-09-18: 0
-- transaction rows lack an expense type, so it currently has no members — and it
-- stays anyway. A dimension that gains an 'uncategorised' row only once a row
-- needs it is a dimension that drops that row on the day it arrives.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.dim_category` AS
SELECT
  TO_HEX(SHA256(CONCAT(entity, '||', expense_type_raw)))   AS category_key,
  entity,
  expense_type_raw                                         AS expense_type,
  CONCAT(entity, ' — ', expense_type_raw)                  AS category_label,
  FALSE                                                    AS is_uncategorised,
  COUNT(*)                                                 AS transaction_rows,
  ROUND(SUM(amount), 2)                                    AS transaction_value
FROM `portfolio-508106.portfolio_b.resolved_spend`
WHERE row_role = 'transaction'
  AND expense_type_raw IS NOT NULL AND TRIM(expense_type_raw) != ''
GROUP BY entity, expense_type_raw

UNION ALL

SELECT
  'UNCATEGORISED'                                          AS category_key,
  CAST(NULL AS STRING)                                     AS entity,
  CAST(NULL AS STRING)                                     AS expense_type,
  'Uncategorised'                                          AS category_label,
  TRUE                                                     AS is_uncategorised,
  (SELECT COUNT(*) FROM `portfolio-508106.portfolio_b.resolved_spend`
    WHERE row_role = 'transaction'
      AND (expense_type_raw IS NULL OR TRIM(expense_type_raw) = '')) AS transaction_rows,
  (SELECT ROUND(COALESCE(SUM(amount), 0), 2) FROM `portfolio-508106.portfolio_b.resolved_spend`
    WHERE row_role = 'transaction'
      AND (expense_type_raw IS NULL OR TRIM(expense_type_raw) = '')) AS transaction_value;
