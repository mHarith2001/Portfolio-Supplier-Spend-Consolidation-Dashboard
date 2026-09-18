-- 41_dim_supplier.sql
-- Layer: L4 reporting_
-- Validation for this layer: sql/90_validation/94_validate_reporting.sql
--
-- EXECUTED 2026-09-18. Run from a file on standard input. Needs 35 first.
--
-- ===========================================================================
-- THE UNRESOLVED BUCKET IS A MEMBER, NOT AN OMISSION
-- ===========================================================================
-- V4.5 and charter L-1: dim_supplier carries every unresolved name as its own
-- row, flagged, with the reason it is unresolved. A dashboard that lists only
-- the suppliers it managed to identify is not a spend dashboard, it is a
-- flattering subset — and the 41.68% of transaction value this build could not
-- resolve would disappear without a trace.
--
-- match_tier is the BEST tier that reached the entity. A company found by its
-- number through one name and by exact name through another is tier 1: the
-- strongest evidence is the evidence. An UNREVIEWED tier-4 candidate never
-- reaches a resolved entity (04 §3 hard rule 1), so `review` always means an
-- unresolved row; `reviewed` means a tier-4 candidate accepted on a recorded
-- human decision (38), and is the only way tier 4 resolves anything.

CREATE OR REPLACE TABLE `portfolio-508106.portfolio_b.dim_supplier` AS
WITH tier AS (
  SELECT
    IF(is_resolved AND matched_company_number IS NOT NULL,
       TO_HEX(SHA256(CONCAT('CH|', matched_company_number))),
       TO_HEX(SHA256(CONCAT('NAME|', supplier_name_norm))))  AS supplier_key,
    MIN(match_tier)                                          AS match_tier,
    -- confidence of the STRONGEST evidence reaching the entity, not a mapping
    -- from tier: a tier-4 accept is 'reviewed', which no tier number expresses
    ARRAY_AGG(match_confidence ORDER BY match_tier, match_confidence LIMIT 1)[OFFSET(0)]
                                                             AS match_confidence
  FROM `portfolio-508106.portfolio_b.resolved_supplier_match`
  GROUP BY supplier_key
)
SELECT
  g.supplier_key,
  g.company_number,
  g.display_name                    AS supplier_name,
  g.legal_name,
  g.company_status,
  g.incorporation_date,
  g.postcode,
  g.name_variant_count,
  g.is_resolved,
  g.unresolved_reason,
  t.match_tier,
  t.match_confidence,
  CASE
    WHEN g.is_resolved              THEN 'Resolved to Companies House'
    WHEN g.unresolved_reason = 'review'    THEN 'Awaiting review'
    WHEN g.unresolved_reason = 'redacted'  THEN 'Redacted at source'
    ELSE                                        'Unresolved'
  END                               AS resolution_state
FROM `portfolio-508106.portfolio_b.resolved_supplier_golden` g
LEFT JOIN tier t USING (supplier_key);
