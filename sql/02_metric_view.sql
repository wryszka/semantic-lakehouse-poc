-- =============================================================================
-- THE TRUNK: Unity Catalog Metric View
-- The only place any metric is defined. Everything downstream (Lakeview,
-- Genie, Excel wrapper, Power BI wrapper) reads this — never redefines it.
-- =============================================================================

CREATE OR REPLACE VIEW lr_dev_aws_us_catalog.semantic_lakehouse.mv_underwriting
(
  -- surfaced names documented for consumers
  `Month` COMMENT 'Calendar month (first day of month)',
  `Year` COMMENT 'Calendar year',
  `Quarter` COMMENT 'Calendar quarter, e.g. 2026-Q1',
  `Sector` COMMENT 'Business sector (management reporting view of products)',
  `Product` COMMENT 'Product name',
  `Line of Business` COMMENT 'Casualty / Property / Specialty',
  `Region` COMMENT 'Sales region',
  `Country` COMMENT 'Country',
  `Channel` COMMENT 'Distribution channel',
  `Channel Type` COMMENT 'Broker / Direct / Partner',
  `Gross Written Premium` COMMENT 'Sum of GWP',
  `Earned Premium` COMMENT 'Sum of earned premium',
  `Claims Incurred` COMMENT 'Sum of incurred claims',
  `Claims Paid` COMMENT 'Sum of paid claims',
  `Policy Count` COMMENT 'Number of policies written',
  `Claim Count` COMMENT 'Number of claims',
  `Loss Ratio` COMMENT 'Claims Incurred / Earned Premium. NON-ADDITIVE: never sum this across rows — recompute from the measures.',
  `Average Premium` COMMENT 'GWP / Policy Count. NON-ADDITIVE.'
)
WITH METRICS
LANGUAGE YAML
COMMENT 'Underwriting metric view — single source of truth for all underwriting metrics (Bricksurance SE synthetic).'
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
  - name: Product
    expr: p.product_name
  - name: Line of Business
    expr: p.line_of_business
  - name: Region
    expr: g.region
  - name: Country
    expr: g.country
  - name: Channel
    expr: c.channel_name
  - name: Channel Type
    expr: c.channel_type

measures:
  - name: Gross Written Premium
    expr: SUM(gross_written_premium)
  - name: Earned Premium
    expr: SUM(earned_premium)
  - name: Claims Incurred
    expr: SUM(claims_incurred)
  - name: Claims Paid
    expr: SUM(claims_paid)
  - name: Policy Count
    expr: SUM(policy_count)
  - name: Claim Count
    expr: SUM(claim_count)
  - name: Loss Ratio
    expr: try_divide(SUM(claims_incurred), SUM(earned_premium))
  - name: Average Premium
    expr: try_divide(SUM(gross_written_premium), SUM(policy_count))
$$;
