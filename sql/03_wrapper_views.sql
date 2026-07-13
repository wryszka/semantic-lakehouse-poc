-- =============================================================================
-- THE DUMB TIER: wrapper views
-- Plain SQL views that resolve MEASURE() at a pinned grain so any client that
-- can read a table (Excel, Power BI DirectQuery, anything ODBC) reads the
-- governed truth. Metrics CANNOT diverge: these are projections of the metric
-- view, they define nothing of their own.
--
-- Design rules:
--  * grain is pinned and named in the view (no accidental reaggregation grain)
--  * additive measures (premium, counts) can be summed by consumers
--  * ratio metrics carry their numerator + denominator so a pivot grand total
--    can be recomputed correctly — and the pre-computed ratio column is named
--    *_at_this_grain as a guardrail against naive summation
--  * time intelligence (YTD / rolling 12m) resolved here with window SQL,
--    reading only metric-view measures
-- =============================================================================

USE lr_dev_aws_us_catalog.semantic_lakehouse;

-- -----------------------------------------------------------------------------
-- 1. General-purpose wrapper: month x sector grain, with time intelligence
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_underwriting_monthly
COMMENT 'Wrapper view over mv_underwriting at MONTH x SECTOR grain. For Excel / Power BI. Additive columns may be summed; loss_ratio_at_this_grain must NOT be summed — recompute as SUM(claims_incurred)/SUM(earned_premium).'
AS
WITH base AS (
  SELECT
    `Month`  AS month,
    `Year`   AS year,
    `Sector` AS sector,
    MEASURE(`Gross Written Premium`) AS gross_written_premium,
    MEASURE(`Earned Premium`)        AS earned_premium,
    MEASURE(`Claims Incurred`)       AS claims_incurred,
    MEASURE(`Policy Count`)          AS policy_count,
    MEASURE(`Claim Count`)           AS claim_count,
    MEASURE(`Loss Ratio`)            AS loss_ratio
  FROM mv_underwriting
  GROUP BY ALL
)
SELECT
  month, year, sector,
  gross_written_premium,
  earned_premium,
  claims_incurred,
  policy_count,
  claim_count,
  -- ratio guardrail: valid ONLY at this grain; numerator/denominator above
  round(loss_ratio, 4) AS loss_ratio_at_this_grain,
  -- time intelligence, defined once here — not in any BI tool
  SUM(gross_written_premium) OVER (
    PARTITION BY sector, year ORDER BY month
  ) AS gwp_ytd,
  SUM(gross_written_premium) OVER (
    PARTITION BY sector ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
  ) AS gwp_rolling_12m,
  round(try_divide(
    SUM(claims_incurred)  OVER (PARTITION BY sector ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW),
    SUM(earned_premium)   OVER (PARTITION BY sector ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
  ), 4) AS loss_ratio_rolling_12m
FROM base;

-- -----------------------------------------------------------------------------
-- 2. BAU-report wrapper: the shape of a classic "premiums by sector" report.
--    This is the view an existing Excel BAU workbook gets repointed to
--    (Wave 1: swap the embedded query, keep the workbook).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_bau_premiums_by_sector
COMMENT 'BAU report shape: current-year premiums by sector with YTD and rolling 12m. Repoint legacy Excel embedded queries here.'
AS
SELECT
  sector,
  month,
  gross_written_premium,
  gwp_ytd,
  gwp_rolling_12m,
  policy_count,
  claims_incurred,
  earned_premium,
  loss_ratio_rolling_12m
FROM vw_underwriting_monthly
WHERE year = year(current_date())
ORDER BY sector, month;

-- -----------------------------------------------------------------------------
-- 3. Region x channel wrapper: second consumer shape to show the pattern
--    stamps out per reporting need — still zero metric definitions.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_underwriting_by_region_channel
COMMENT 'Wrapper view at YEAR x REGION x CHANNEL TYPE grain. Ratio carries numerator and denominator for correct client-side recombination.'
AS
SELECT
  `Year`         AS year,
  `Region`       AS region,
  `Channel Type` AS channel_type,
  MEASURE(`Gross Written Premium`) AS gross_written_premium,
  MEASURE(`Earned Premium`)        AS earned_premium,
  MEASURE(`Claims Incurred`)       AS claims_incurred,
  MEASURE(`Policy Count`)          AS policy_count,
  round(MEASURE(`Loss Ratio`), 4)  AS loss_ratio_at_this_grain
FROM mv_underwriting
GROUP BY ALL;
