-- 45_fact_spend.sql
-- Layer: L4 reporting_
-- Validation for this layer: sql/90_validation/94_validate_reporting.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input. Needs 41-44 first.
--
-- ===========================================================================
-- TWO FACT TABLES, ONE GRAIN, NOTHING HIDDEN
-- ===========================================================================
-- 03 §5: fact_spend carries payments to a RESOLVED supplier; fact_spend_unresolved
-- carries the rest at the SAME grain. Together they are every transaction row,
-- which is V4.1 — and the split is what makes the unresolved population a
-- reportable category rather than a silent omission (charter L-1).
--
-- ONLY row_role = 'transaction' ENTERS EITHER TABLE. File totals, workbook
-- sections and trailing artefacts stay in resolved_spend with their amounts and
-- are excluded here: GBP 2,556,596,745.72 that would otherwise be counted twice.
-- V4.1 is scoped to transactions for exactly this reason.
--
-- TIER 4 IS UNRESOLVED. Its rows land in fact_spend_unresolved with
-- unresolved_reason 'review'. Moving them across on a similarity score would
-- claim a human review that has not happened.
--
-- DEGENERATE DIMENSIONS. spend_id, transaction_number and _source_file stay on
-- the fact so any figure on the dashboard can be traced to the published row it
-- came from. That traceability is the point of the whole pipeline.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.fact_spend` AS
SELECT
  s.spend_id,
  s.supplier_key,
  s.entity,
  s.payment_date                                            AS date_key,
  TO_HEX(SHA256(CONCAT(s.entity, '||', s.expense_type_raw))) AS category_key,
  s.amount,
  s.amount_vat_basis,
  s.is_grant_in_aid,
  s.transaction_number,
  s._source_file,
  -- WHO STANDS BEHIND THIS ROW'S ATTRIBUTION, per payment line (2026-09-22).
  -- Basis is recorded HERE, on the fact, because it belongs to the SPELLING that
  -- routed the money, not to the company it reached. An accepted short spelling
  -- merges into a company that usually also has rule-based evidence through a
  -- longer spelling, so an entity-level basis reads 'method' and hides that this
  -- row's money was attributed on a human decision.
  CASE
    WHEN m.match_confidence = 'reviewed' AND m.review_decided_by = 'user' THEN 'user_review'
    WHEN m.match_confidence = 'reviewed'                                  THEN 'delegated_review'
    ELSE                                                                       'method'
  END                                                       AS resolution_basis
FROM `portfolio-508106.portfolio_b.resolved_spend` s
JOIN `portfolio-508106.portfolio_b.dim_supplier` d USING (supplier_key)
JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m USING (supplier_name_norm)
WHERE s.row_role = 'transaction' AND d.is_resolved;

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.fact_spend_unresolved` AS
SELECT
  s.spend_id,
  s.supplier_key,
  s.entity,
  s.payment_date                                            AS date_key,
  TO_HEX(SHA256(CONCAT(s.entity, '||', s.expense_type_raw))) AS category_key,
  s.amount,
  s.amount_vat_basis,
  s.is_grant_in_aid,
  s.transaction_number,
  s._source_file,
  d.unresolved_reason
FROM `portfolio-508106.portfolio_b.resolved_spend` s
JOIN `portfolio-508106.portfolio_b.dim_supplier` d USING (supplier_key)
WHERE s.row_role = 'transaction' AND NOT d.is_resolved;
