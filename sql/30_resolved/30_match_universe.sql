-- 30_match_universe.sql
-- Layer: L3 resolved_ -- the company universe every matching tier reads
--
-- EXECUTED 2026-09-20. Run from a file on standard input, before 31-34.
--
-- ===========================================================================
-- WHICH REGISTER ENTRIES CAN BE A PAYEE AT ALL
-- ===========================================================================
-- The Companies House snapshot carries more than companies. 30,199 of its rows
-- are REGISTER OF OVERSEAS ENTITIES registrations, numbered OE######. An overseas
-- entity is a foreign body that owns UK land; the ROE records it so ownership is
-- visible. It is not a UK company, and an OE number is not a company number.
--
-- Matching a supplier name to an OE registration is a REGISTER-SEMANTICS
-- MISMATCH, not a scoring error, so it is excluded at candidate generation
-- rather than corrected afterwards. Ruled 2026-09-20.
--
-- WHY HERE, AND NOT ELSEWHERE:
--   * NOT by deleting rows from staging_companies. The register is the register.
--     Removing 30,199 rows would break the V1.5 reconciliation and destroy the
--     audit trail for exactly the entries under dispute.
--   * NOT as four copies of a predicate in 31, 32, 33 and 34. Four copies of a
--     rule are four rules waiting to disagree.
--   * HERE, as one view every tier reads. Tier 1 inherits it for free: a buyer
--     stating an OE number now reads as `number_not_in_register`, which is the
--     correct semantics and needs no new rejection reason.
--
-- WHAT IT COST, measured 2026-09-20 before the change:
--   * 6 names were resolved to an OE registration by exact name, GBP 543,565.40.
--     All 6 are exact-name matches and NO non-OE company carries those names, so
--     they were right-entity / wrong-identifier-class, not wrong-entity errors.
--     They are surfaced for decision rather than quietly dropped.
--   * 3 queued names carried an OE candidate, GBP 106,427,556.11 -- almost all of
--     it the NEXUS row, where a statutory transport executive was matched to an
--     overseas property registration.
--   * 1,619 candidate pairs across 586 names lose an OE option at tier 4.

CREATE OR REPLACE VIEW `portfolio-508106.portfolio_b.resolved_company_universe` AS
SELECT *
FROM `portfolio-508106.portfolio_b.staging_companies`
WHERE NOT STARTS_WITH(company_number, 'OE');
