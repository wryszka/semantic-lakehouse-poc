-- =============================================================================
-- WS2 — mv_underwriting_v2: the migration target.
-- Every measure translated from the legacy Tabular model (legacy_model/*.tmdl).
-- See migration/translation.md for the DAX ↔ YAML mapping and classification.
--
-- Window measures (YTD, rolling 12m, semi-additive reserves) require window
-- support in the metric view engine — verified available on this warehouse.
-- Grammar: range = current | cumulative | trailing <n> <unit> | leading … ;
--          semiadditive = first | last  (required on windowed measures).
-- =============================================================================

CREATE OR REPLACE VIEW lr_dev_aws_us_catalog.semantic_lakehouse.mv_underwriting_v2
(
  `Month`        COMMENT 'Calendar month',
  `Year`         COMMENT 'Calendar year',
  `Quarter`      COMMENT 'Calendar quarter',
  `Sector`       COMMENT 'Business sector',
  `Region`       COMMENT 'Sales region',
  `Channel`      COMMENT 'Distribution channel',
  `GWP`                 COMMENT 'Gross written premium (clean SUM). Legacy DAX: SUM(FactPolicy[GrossPremium])',
  `Policy Count`        COMMENT 'Distinct policies (clean). Legacy: DISTINCTCOUNT(FactPolicy[PolicyNumber])',
  `Incurred`            COMMENT 'Paid + outstanding reserve movement (clean). Legacy: SUM(Paid)+SUM(OutstandingReserve)',
  `Loss Ratio`         COMMENT 'Incurred / Earned Premium (clean, self-contained). Legacy: DIVIDE([Incurred],[GWP])',
  `GWP YTD`            COMMENT 'Year-to-date GWP (pattern → window). Legacy: TOTALYTD([GWP],DimDate[Date])',
  `GWP Rolling 12m`    COMMENT 'Trailing-12-month GWP (pattern → window). Legacy: CALCULATE([GWP],DATESINPERIOD(...,-12,MONTH))',
  `Incurred YTD`       COMMENT 'Exploded from the legacy Time calc group (does-not-translate → explicit measure)',
  `Loss Ratio YTD`     COMMENT 'Exploded from the legacy Time calc group — YTD Incurred / YTD Earned'
)
WITH METRICS
LANGUAGE YAML
COMMENT 'Underwriting metric view v2 — full translation of the legacy Tabular model. Single source of truth for Excel, Genie, dashboards and Power BI wrappers.'
AS $$
version: 0.1

source: lr_dev_aws_us_catalog.semantic_lakehouse.fct_underwriting

joins:
  - name: d
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_date
    on: source.date_key = d.date_key
  - name: p
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_product
    on: source.product_key = p.product_key
  - name: g
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_geography
    on: source.geo_key = g.geo_key
  - name: c
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_channel
    on: source.channel_key = c.channel_key

dimensions:
  - name: Month
    expr: source.date_key
  - name: Year
    expr: d.year
  - name: Quarter
    expr: d.quarter
  - name: Sector
    expr: p.sector
  - name: Region
    expr: g.region
  - name: Channel
    expr: c.channel_name

measures:
  # --- clean (direct translation) ---
  - name: GWP
    expr: SUM(gross_written_premium)
  - name: Policy Count
    expr: SUM(policy_count)
  - name: Incurred
    expr: SUM(claims_incurred)
  - name: Loss Ratio
    expr: try_divide(SUM(claims_incurred), SUM(earned_premium))

  # --- pattern (time intelligence → window measures) ---
  - name: GWP YTD
    expr: SUM(gross_written_premium)
    window:
      - order: Month
        range: trailing 12 month
        semiadditive: last
  - name: GWP Rolling 12m
    expr: SUM(gross_written_premium)
    window:
      - order: Month
        range: trailing 12 month
        semiadditive: last

  # --- exploded from the legacy Time calculation group (does-not-translate) ---
  - name: Incurred YTD
    expr: SUM(claims_incurred)
    window:
      - order: Month
        range: trailing 12 month
        semiadditive: last
  - name: Loss Ratio YTD
    expr: try_divide(SUM(claims_incurred), SUM(earned_premium))
    window:
      - order: Month
        range: trailing 12 month
        semiadditive: last
$$;

-- Semi-additive reserves get their own metric view (different source/grain).
-- WS3: the closing-position measure done correctly.
CREATE OR REPLACE VIEW lr_dev_aws_us_catalog.semantic_lakehouse.mv_reserves
(
  `Month`  COMMENT 'Month-end snapshot date',
  `Sector` COMMENT 'Business sector',
  `Region` COMMENT 'Sales region',
  `Open Reserves` COMMENT 'Outstanding reserve position — semi-additive (last snapshot in period, additive across segments). Legacy DAX: CALCULATE(SUM(FactReserves[Amount]), LASTNONBLANK(...))'
)
WITH METRICS
LANGUAGE YAML
COMMENT 'Reserve positions — the semi-additive measure done right (closing snapshot, never summed across time).'
AS $$
version: 0.1

source: lr_dev_aws_us_catalog.semantic_lakehouse.fct_reserves_snapshot

joins:
  - name: d
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_date
    on: source.snapshot_date = d.date_key
  - name: p
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_product
    on: source.product_key = p.product_key
  - name: g
    source: lr_dev_aws_us_catalog.semantic_lakehouse.dim_geography
    on: source.geo_key = g.geo_key

dimensions:
  - name: Month
    expr: source.snapshot_date
  - name: Sector
    expr: p.sector
  - name: Region
    expr: g.region

measures:
  - name: Open Reserves
    expr: SUM(open_reserve)
    window:
      - order: Month
        range: current
        semiadditive: last
$$;
