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
       * (CASE WHEN sector = 'Property' AND mth IN (11, 12, 1, 2) THEN 1.6 ELSE 1.0 END)
       * (CASE WHEN sector = 'Technology' AND yr_idx >= 5 THEN 1.25 ELSE 1.0 END)
       AS DECIMAL(18,2)) AS claims_incurred,
  CAST((1 + r * 8) * (9000 + r * 25000) * (1 + 0.05 * yr_idx) * 0.7
       AS DECIMAL(18,2)) AS claims_paid
FROM cells
WHERE r > 0.45;

ALTER TABLE dim_date ADD CONSTRAINT pk_dim_date PRIMARY KEY (date_key);
ALTER TABLE fct_premiums ADD CONSTRAINT fk_prem_date FOREIGN KEY (date_key) REFERENCES dim_date;
ALTER TABLE fct_claims ADD CONSTRAINT fk_clm_date FOREIGN KEY (date_key) REFERENCES dim_date;
ALTER TABLE fct_underwriting ADD CONSTRAINT fk_uw_date FOREIGN KEY (date_key) REFERENCES dim_date;

DELETE FROM fct_underwriting WHERE true;

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
