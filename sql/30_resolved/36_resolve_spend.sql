-- 36_resolve_spend.sql
-- Layer: L3 resolved_
-- Validation for this layer: sql/90_validation/93_validate_resolved.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input. Needs 31-35 first.
--
-- ===========================================================================
-- RESOLUTION CHANGES ATTRIBUTION, NEVER TOTALS
-- ===========================================================================
-- 03 §4: resolved_spend must carry EXACTLY as many rows as staging_spend and the
-- same SUM(amount). That is E-5, and it is why this file starts from `s.*` rather
-- than a hand-listed column set: a SELECT list that has to be maintained is a
-- place for a row or a column to go missing.
--
-- ATTRIBUTION IS TRANSACTIONS-ONLY (03 §4, ruled 2026-09-18). A supplier_key is
-- assigned only where row_role = 'transaction'. File totals, workbook sections and
-- trailing artefacts keep their rows and their amounts but carry NULL, so they
-- reconcile in E-5 and vanish from every aggregation. This is the mechanism that
-- keeps the GBP 2,556,596,745.72 of H-5 non-payment value out of supplier spend
-- without deleting a single row.
--
-- WHICH KEY A TRANSACTION GETS -- read from resolved_supplier_match.is_resolved,
-- never re-derived here:
--   resolved   -> the Companies House entity key    CH|<company_number>
--                 (tiers 1-3, plus tier-4 names accepted on recorded review)
--   unresolved -> its own unresolved key            NAME|<supplier_name_norm>
-- An UNREVIEWED tier-4 candidate is a question, not a resolution (04 §3 hard
-- rule 1), so it must not inherit the company's key. Every transaction row still
-- gets a key, so unresolved spend is counted and visible rather than dropped.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.resolved_spend` AS
SELECT
  s.*,
  CASE
    WHEN s.row_role != 'transaction'                    THEN NULL
    WHEN m.is_resolved AND m.matched_company_number IS NOT NULL
      THEN TO_HEX(SHA256(CONCAT('CH|', m.matched_company_number)))
    WHEN s.supplier_name_norm IS NOT NULL
      THEN TO_HEX(SHA256(CONCAT('NAME|', s.supplier_name_norm)))
  END                                                   AS supplier_key
FROM `portfolio-508106.portfolio_b.staging_spend` s
LEFT JOIN `portfolio-508106.portfolio_b.resolved_supplier_match` m
  USING (supplier_name_norm);
