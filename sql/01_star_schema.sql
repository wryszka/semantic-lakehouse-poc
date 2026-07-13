-- =============================================================================
-- Semantic Lakehouse POC — Wave 0: dimensional model (the base layer)
-- Bricksurance SE synthetic data. Best-practice target state, not a port of
-- any legacy estate.
-- One schema, star schema naming (dim_/fct_) to mirror a classic
-- Kimball dimensional layer.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS lr_dev_aws_us_catalog.semantic_lakehouse
  COMMENT 'Semantic Lakehouse POC: dimensional model + metric views (single source of semantic truth) + wrapper views for dumb consumers (Excel / Power BI). Synthetic Bricksurance SE data.';

USE lr_dev_aws_us_catalog.semantic_lakehouse;

-- -----------------------------------------------------------------------------
-- Dimensions
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE dim_date (
  date_key DATE NOT NULL COMMENT 'Calendar date (month start for monthly grain)',
  year INT NOT NULL,
  quarter STRING NOT NULL COMMENT 'e.g. 2026-Q1',
  month INT NOT NULL,
  month_name STRING NOT NULL,
  year_month STRING NOT NULL COMMENT 'e.g. 2026-01'
) COMMENT 'Date dimension, monthly grain';

INSERT INTO dim_date
SELECT
  d AS date_key,
  year(d), concat(year(d), '-Q', quarter(d)), month(d), date_format(d, 'MMMM'),
  date_format(d, 'yyyy-MM')
FROM (SELECT explode(sequence(DATE'2018-01-01', DATE'2026-07-01', INTERVAL 1 MONTH)) AS d);

CREATE OR REPLACE TABLE dim_product (
  product_key INT NOT NULL,
  product_code STRING NOT NULL,
  product_name STRING NOT NULL,
  sector STRING NOT NULL COMMENT 'Business sector used in management reporting',
  line_of_business STRING NOT NULL
) COMMENT 'Product dimension';

INSERT INTO dim_product VALUES
  (1, 'PI',   'Professional Indemnity',   'Professions',        'Casualty'),
  (2, 'CYB',  'Cyber & Data',             'Technology',         'Specialty'),
  (3, 'DO',   'Directors & Officers',     'Financial Services', 'Casualty'),
  (4, 'PROP', 'Commercial Property',      'Property',           'Property'),
  (5, 'ART',  'Fine Art & Collectibles',  'Art & Private',      'Specialty'),
  (6, 'HH',   'High Value Household',     'Art & Private',      'Property'),
  (7, 'EL',   'Employers Liability',      'Professions',        'Casualty'),
  (8, 'MED',  'Media & Entertainment',    'Technology',         'Specialty');

CREATE OR REPLACE TABLE dim_geography (
  geo_key INT NOT NULL,
  region STRING NOT NULL,
  country STRING NOT NULL
) COMMENT 'Geography dimension';

INSERT INTO dim_geography VALUES
  (1, 'London',        'United Kingdom'),
  (2, 'South East',    'United Kingdom'),
  (3, 'North',         'United Kingdom'),
  (4, 'Midlands',      'United Kingdom'),
  (5, 'Scotland',      'United Kingdom'),
  (6, 'Ireland',       'Ireland'),
  (7, 'Iberia',        'Spain & Portugal'),
  (8, 'DACH',          'Germany & Austria');

CREATE OR REPLACE TABLE dim_channel (
  channel_key INT NOT NULL,
  channel_name STRING NOT NULL,
  channel_type STRING NOT NULL
) COMMENT 'Distribution channel dimension';

INSERT INTO dim_channel VALUES
  (1, 'Broker - National',   'Broker'),
  (2, 'Broker - Regional',   'Broker'),
  (3, 'Direct Online',       'Direct'),
  (4, 'Direct Phone',        'Direct'),
  (5, 'Partnerships',        'Partner');

-- -----------------------------------------------------------------------------
-- Facts (transaction-shaped, full history — no 7-year cut needed here)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE fct_premiums (
  premium_id BIGINT NOT NULL,
  date_key DATE NOT NULL,
  product_key INT NOT NULL,
  geo_key INT NOT NULL,
  channel_key INT NOT NULL,
  policy_count INT NOT NULL,
  gross_written_premium DECIMAL(18,2) NOT NULL,
  earned_premium DECIMAL(18,2) NOT NULL
) COMMENT 'Written/earned premium fact, monthly transaction grain';

INSERT INTO fct_premiums
WITH cells AS (
  SELECT d.date_key, p.product_key, g.geo_key, c.channel_key,
         -- deterministic pseudo-random per cell
         abs(hash(d.date_key, p.product_key, g.geo_key, c.channel_key)) % 1000 / 1000.0 AS r,
         year(d.date_key) - 2018 AS yr_idx,
         month(d.date_key) AS mth
  FROM dim_date d CROSS JOIN dim_product p CROSS JOIN dim_geography g CROSS JOIN dim_channel c
)
SELECT
  row_number() OVER (ORDER BY date_key, product_key, geo_key, channel_key) AS premium_id,
  date_key, product_key, geo_key, channel_key,
  CAST(5 + r * 40 + yr_idx * 2 AS INT) AS policy_count,
  CAST((5 + r * 40 + yr_idx * 2) * (2500 + r * 6000)
       * (1 + 0.06 * yr_idx)                          -- growth
       * (CASE WHEN mth IN (1, 4) THEN 1.35 ELSE 1.0 END)  -- renewal seasonality
       AS DECIMAL(18,2)) AS gross_written_premium,
  CAST((5 + r * 40 + yr_idx * 2) * (2500 + r * 6000) * (1 + 0.06 * yr_idx) * 0.92
       AS DECIMAL(18,2)) AS earned_premium
FROM cells;

CREATE OR REPLACE TABLE fct_claims (
  claim_event_id BIGINT NOT NULL,
  date_key DATE NOT NULL,
  product_key INT NOT NULL,
  geo_key INT NOT NULL,
  channel_key INT NOT NULL,
  claim_count INT NOT NULL,
  claims_incurred DECIMAL(18,2) NOT NULL,
  claims_paid DECIMAL(18,2) NOT NULL
) COMMENT 'Incurred/paid claims fact, monthly transaction grain';

INSERT INTO fct_claims
WITH cells AS (
  SELECT d.date_key, p.product_key, g.geo_key, c.channel_key,
         abs(hash(d.date_key, p.product_key, g.geo_key, c.channel_key, 7)) % 1000 / 1000.0 AS r,
         year(d.date_key) - 2018 AS yr_idx,
         month(d.date_key) AS mth,
         p.sector
  FROM dim_date d CROSS JOIN dim_product p CROSS JOIN dim_geography g CROSS JOIN dim_channel c
)
SELECT
  row_number() OVER (ORDER BY date_key, product_key, geo_key, channel_key) AS claim_event_id,
  date_key, product_key, geo_key, channel_key,
  CAST(1 + r * 8 AS INT) AS claim_count,
  CAST((1 + r * 8) * (9000 + r * 25000)
       * (1 + 0.05 * yr_idx)
       * (CASE WHEN sector = 'Property' AND mth IN (11, 12, 1, 2) THEN 1.6 ELSE 1.0 END) -- winter storms
       * (CASE WHEN sector = 'Technology' AND yr_idx >= 5 THEN 1.25 ELSE 1.0 END)        -- cyber trend
       AS DECIMAL(18,2)) AS claims_incurred,
  CAST((1 + r * 8) * (9000 + r * 25000) * (1 + 0.05 * yr_idx) * 0.7
       AS DECIMAL(18,2)) AS claims_paid
FROM cells
WHERE r > 0.45;  -- not every cell has claims

-- -----------------------------------------------------------------------------
-- Declared PK/FK constraints (informational) → powers the Catalog Explorer ERD
-- -----------------------------------------------------------------------------
ALTER TABLE dim_date      ADD CONSTRAINT pk_dim_date      PRIMARY KEY (date_key);
ALTER TABLE dim_product   ADD CONSTRAINT pk_dim_product   PRIMARY KEY (product_key);
ALTER TABLE dim_geography ADD CONSTRAINT pk_dim_geography PRIMARY KEY (geo_key);
ALTER TABLE dim_channel   ADD CONSTRAINT pk_dim_channel   PRIMARY KEY (channel_key);
ALTER TABLE fct_premiums  ADD CONSTRAINT pk_fct_premiums  PRIMARY KEY (premium_id);
ALTER TABLE fct_claims    ADD CONSTRAINT pk_fct_claims    PRIMARY KEY (claim_event_id);

ALTER TABLE fct_premiums ADD CONSTRAINT fk_prem_date    FOREIGN KEY (date_key)    REFERENCES dim_date;
ALTER TABLE fct_premiums ADD CONSTRAINT fk_prem_product FOREIGN KEY (product_key) REFERENCES dim_product;
ALTER TABLE fct_premiums ADD CONSTRAINT fk_prem_geo     FOREIGN KEY (geo_key)     REFERENCES dim_geography;
ALTER TABLE fct_premiums ADD CONSTRAINT fk_prem_channel FOREIGN KEY (channel_key) REFERENCES dim_channel;
ALTER TABLE fct_claims   ADD CONSTRAINT fk_clm_date     FOREIGN KEY (date_key)    REFERENCES dim_date;
ALTER TABLE fct_claims   ADD CONSTRAINT fk_clm_product  FOREIGN KEY (product_key) REFERENCES dim_product;
ALTER TABLE fct_claims   ADD CONSTRAINT fk_clm_geo      FOREIGN KEY (geo_key)     REFERENCES dim_geography;
ALTER TABLE fct_claims   ADD CONSTRAINT fk_clm_channel  FOREIGN KEY (channel_key) REFERENCES dim_channel;

-- -----------------------------------------------------------------------------
-- Unified underwriting fact: single source for the metric view
-- (premiums + claims conformed to one monthly grain)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE fct_underwriting (
  date_key DATE NOT NULL,
  product_key INT NOT NULL,
  geo_key INT NOT NULL,
  channel_key INT NOT NULL,
  policy_count INT,
  gross_written_premium DECIMAL(18,2),
  earned_premium DECIMAL(18,2),
  claim_count INT,
  claims_incurred DECIMAL(18,2),
  claims_paid DECIMAL(18,2)
) COMMENT 'Conformed monthly underwriting fact combining premiums and claims. Source of the underwriting metric view.';

INSERT INTO fct_underwriting
SELECT
  coalesce(p.date_key, c.date_key), coalesce(p.product_key, c.product_key),
  coalesce(p.geo_key, c.geo_key), coalesce(p.channel_key, c.channel_key),
  p.policy_count, p.gross_written_premium, p.earned_premium,
  c.claim_count, c.claims_incurred, c.claims_paid
FROM (SELECT date_key, product_key, geo_key, channel_key,
             sum(policy_count) policy_count, sum(gross_written_premium) gross_written_premium,
             sum(earned_premium) earned_premium
      FROM fct_premiums GROUP BY ALL) p
FULL OUTER JOIN
     (SELECT date_key, product_key, geo_key, channel_key,
             sum(claim_count) claim_count, sum(claims_incurred) claims_incurred,
             sum(claims_paid) claims_paid
      FROM fct_claims GROUP BY ALL) c
  ON p.date_key = c.date_key AND p.product_key = c.product_key
 AND p.geo_key = c.geo_key AND p.channel_key = c.channel_key;

ALTER TABLE fct_underwriting ADD CONSTRAINT fk_uw_date    FOREIGN KEY (date_key)    REFERENCES dim_date;
ALTER TABLE fct_underwriting ADD CONSTRAINT fk_uw_product FOREIGN KEY (product_key) REFERENCES dim_product;
ALTER TABLE fct_underwriting ADD CONSTRAINT fk_uw_geo     FOREIGN KEY (geo_key)     REFERENCES dim_geography;
ALTER TABLE fct_underwriting ADD CONSTRAINT fk_uw_channel FOREIGN KEY (channel_key) REFERENCES dim_channel;
