-- =============================================================================
-- WS3 — Semi-additive reserves: the mistake a naive migration makes SILENTLY.
--
-- A reserve balance is a POSITION. At each month-end it has a value that
-- REPLACES last month's, it doesn't add to it. "Open reserves for Q2" is the
-- balance at 30 June — NOT June + May + April.
--
-- Run both queries. The naive one is ~3x too big and looks perfectly plausible
-- on a dashboard. That is the danger: nobody notices until an auditor does.
-- =============================================================================

USE lr_dev_aws_us_catalog.semantic_lakehouse;

-- -----------------------------------------------------------------------------
-- WRONG — naive SUM across every month-end in the period.
-- This is what you get if you migrate FactReserves as if 'Amount' were additive
-- (the default), or drag it into a pivot Values area without thinking.
-- -----------------------------------------------------------------------------
SELECT
  'WRONG: sum across snapshots' AS method,
  p.sector,
  round(SUM(r.open_reserve) / 1e6, 1) AS reserves_q2_2026_m
FROM fct_reserves_snapshot r
JOIN dim_product p ON r.product_key = p.product_key
WHERE r.snapshot_date BETWEEN DATE'2026-04-01' AND DATE'2026-06-01'  -- Apr, May, Jun snapshots
GROUP BY p.sector
ORDER BY p.sector;

-- -----------------------------------------------------------------------------
-- RIGHT — the CLOSING position: the balance at the last snapshot in the period.
-- This is what the metric view's semi-additive `Open Reserves` measure returns.
-- -----------------------------------------------------------------------------
SELECT
  'RIGHT: closing position (30 Jun)' AS method,
  p.sector,
  round(SUM(r.open_reserve) / 1e6, 1) AS reserves_q2_2026_m
FROM fct_reserves_snapshot r
JOIN dim_product p ON r.product_key = p.product_key
WHERE r.snapshot_date = DATE'2026-06-01'  -- the closing month-end of Q2
GROUP BY p.sector
ORDER BY p.sector;

-- -----------------------------------------------------------------------------
-- RIGHT, via the governed metric view — proves the semi-additive measure gives
-- the same closing-position answer, with no hand-written window logic.
-- -----------------------------------------------------------------------------
SELECT
  'RIGHT: metric view Open Reserves' AS method,
  `Sector`,
  round(MEASURE(`Open Reserves`) / 1e6, 1) AS reserves_q2_2026_m
FROM mv_reserves
WHERE `Month` = DATE'2026-06-01'
GROUP BY `Sector`
ORDER BY `Sector`;
