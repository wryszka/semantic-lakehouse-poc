-- =============================================================================
-- WS3 — Semi-additive reserves: month-end SNAPSHOT positions (not transactions)
-- A reserve balance is a *position*: at each month-end it has a value that
-- replaces (not adds to) the prior month. Summing positions across months is
-- the classic semi-additive mistake — this table exists to demonstrate it.
-- =============================================================================

USE lr_dev_aws_us_catalog.semantic_lakehouse;

CREATE OR REPLACE TABLE fct_reserves_snapshot (
  snapshot_date DATE NOT NULL COMMENT 'Month-end position date',
  product_key INT NOT NULL,
  geo_key INT NOT NULL,
  channel_key INT NOT NULL,
  open_reserve DECIMAL(18,2) NOT NULL COMMENT 'Outstanding reserve BALANCE at snapshot_date (a position, not a flow) — semi-additive: additive across segments, non-additive across time'
) COMMENT 'Month-end outstanding reserve positions per segment. Semi-additive over time — use the closing snapshot of a period, never SUM across snapshots.';

-- Build a plausible reserve balance that walks month to month: opening + new
-- incurred - paid, drifting per segment. Deterministic (hash-seeded), monthly.
INSERT INTO fct_reserves_snapshot
WITH months AS (
  SELECT date_key AS snapshot_date FROM dim_date
),
seg AS (
  SELECT p.product_key, g.geo_key, c.channel_key, p.sector
  FROM dim_product p CROSS JOIN dim_geography g CROSS JOIN dim_channel c
),
grid AS (
  SELECT m.snapshot_date, s.product_key, s.geo_key, s.channel_key, s.sector,
         (year(m.snapshot_date) - 2018) * 12 + month(m.snapshot_date) AS t,
         abs(hash(s.product_key, s.geo_key, s.channel_key, 11)) % 1000 / 1000.0 AS base_r,
         abs(hash(s.product_key, s.geo_key, s.channel_key, month(m.snapshot_date), 23)) % 1000 / 1000.0 AS mth_r
  FROM months m CROSS JOIN seg s
)
SELECT
  snapshot_date, product_key, geo_key, channel_key,
  CAST(
    -- a smoothly-varying balance: base level + growth + seasonal wobble, always positive
    (400000 + base_r * 2600000)                       -- segment base reserve level
    * (1 + 0.04 * (t / 12.0))                          -- gentle upward drift over years
    * (1 + 0.18 * (mth_r - 0.5))                       -- month-to-month variation (position moves)
    * (CASE WHEN sector = 'Property' AND month(snapshot_date) IN (12,1,2) THEN 1.25 ELSE 1.0 END)
    AS DECIMAL(18,2)) AS open_reserve
FROM grid;

ALTER TABLE fct_reserves_snapshot ADD CONSTRAINT fk_res_product FOREIGN KEY (product_key) REFERENCES dim_product;
ALTER TABLE fct_reserves_snapshot ADD CONSTRAINT fk_res_geo     FOREIGN KEY (geo_key)     REFERENCES dim_geography;
ALTER TABLE fct_reserves_snapshot ADD CONSTRAINT fk_res_channel FOREIGN KEY (channel_key) REFERENCES dim_channel;
-- date FK added after dim_date PK confirmed (see 01b); add here too for the ERD
ALTER TABLE fct_reserves_snapshot ADD CONSTRAINT fk_res_date FOREIGN KEY (snapshot_date) REFERENCES dim_date;
