# Databricks notebook source
# MAGIC %md
# MAGIC # Migration reconciliation — the sign-off artifact
# MAGIC
# MAGIC The question a modelling team actually asks before they trust a migration:
# MAGIC **"does the new metric view return the same numbers our old model did?"**
# MAGIC
# MAGIC This notebook answers it with evidence, not assertion:
# MAGIC 1. Re-implement each legacy measure's semantics **directly in SQL** against the
# MAGIC    star schema — this simulates *what the old SSAS/Tabular model would have said*.
# MAGIC 2. Query the same figures from the **metric view** (`mv_underwriting_v2`).
# MAGIC 3. Diff them: measure × cut × legacy × metric-view × delta × pass/fail.
# MAGIC
# MAGIC Every row should pass **except one deliberately seeded discrepancy**, left in to
# MAGIC show what a *failed* reconciliation looks like and how you investigate it. In a
# MAGIC real migration this is the row that saves you: a silent definitional drift caught
# MAGIC before it reaches a regulator.
# MAGIC
# MAGIC Runs on a serverless SQL warehouse / serverless notebook. Deterministic data.

# COMMAND ----------

CATALOG = "lr_dev_aws_us_catalog"
SCHEMA = "semantic_lakehouse"
YEAR = 2025
TOL = 0.01  # absolute tolerance for money (pennies); ratios compared at 1e-6
spark.sql(f"USE {CATALOG}.{SCHEMA}")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 1. Legacy semantics, re-implemented in SQL ("what SSAS would say")
# MAGIC
# MAGIC One row per Sector. Each column reproduces a legacy DAX measure's meaning.
# MAGIC **Note the seeded issue:** for the `Property` sector only, the legacy `Loss Ratio`
# MAGIC is computed on **written** premium (GWP) instead of **earned** premium —
# MAGIC reproducing a real-world "which premium base?" drift that hides in one filter
# MAGIC context. Every other cell reproduces the correct definition. So exactly one row
# MAGIC will fail reconciliation, showing what a genuine finding looks like among passes.

# COMMAND ----------

legacy = spark.sql(f"""
  SELECT
    p.sector                                            AS sector,
    SUM(u.gross_written_premium)                        AS gwp,
    SUM(u.policy_count)                                 AS policy_count,
    SUM(u.claims_incurred)                              AS incurred,
    -- SEEDED DISCREPANCY (one row): for 'Property' the legacy measure divides by
    -- WRITTEN premium; everywhere else by EARNED premium (the correct base the
    -- metric view uses). Expected to fail for Property only — a definitional
    -- drift to adjudicate, not a bug.
    CASE WHEN p.sector = 'Property'
         THEN try_divide(SUM(u.claims_incurred), SUM(u.gross_written_premium))
         ELSE try_divide(SUM(u.claims_incurred), SUM(u.earned_premium))
    END                                                 AS loss_ratio
  FROM fct_underwriting u
  JOIN dim_product p ON u.product_key = p.product_key
  JOIN dim_date d    ON u.date_key    = d.date_key
  WHERE d.year = {YEAR}
  GROUP BY p.sector
""")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 2. The same figures from the governed metric view

# COMMAND ----------

mv = spark.sql(f"""
  SELECT
    `Sector`                     AS sector,
    MEASURE(`GWP`)               AS gwp,
    MEASURE(`Policy Count`)      AS policy_count,
    MEASURE(`Incurred`)          AS incurred,
    MEASURE(`Loss Ratio`)        AS loss_ratio
  FROM mv_underwriting_v2
  WHERE `Year` = {YEAR}
  GROUP BY `Sector`
""")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 3. Reconciliation diff — measure × cut × legacy × metric view × delta × flag

# COMMAND ----------

from pyspark.sql import functions as F

MEASURES = [
    ("GWP", "gwp", "money"),
    ("Policy Count", "policy_count", "money"),
    ("Incurred", "incurred", "money"),
    ("Loss Ratio", "loss_ratio", "ratio"),
]

l = legacy.alias("l")
m = mv.alias("m")
joined = l.join(m, "sector")

rows = []
for label, col, kind in MEASURES:
    tol = TOL if kind == "money" else 1e-6
    r = (joined
         .select(
             F.lit(label).alias("measure"),
             F.col("sector"),
             F.col(f"l.{col}").alias("legacy_value"),
             F.col(f"m.{col}").alias("metric_view_value"),
             (F.col(f"l.{col}") - F.col(f"m.{col}")).alias("delta"))
         .withColumn("pass", F.abs(F.col("delta")) <= F.lit(tol)))
    rows.append(r)

recon = rows[0]
for r in rows[1:]:
    recon = recon.unionByName(r)

recon = recon.orderBy(F.col("pass").asc(), "measure", "sector")
display(recon)

# COMMAND ----------
# MAGIC %md
# MAGIC ## 4. Summary — and the flagged row(s)

# COMMAND ----------

total = recon.count()
failed = recon.filter(~F.col("pass")).count()
print(f"Reconciliation: {total - failed}/{total} rows pass.")
print(f"{failed} row(s) flagged for investigation.\n")

if failed:
    print("FLAGGED — investigate before sign-off:")
    for row in recon.filter(~F.col("pass")).collect():
        print(f"  • {row['measure']} / {row['sector']}: "
              f"legacy={row['legacy_value']:.2f} vs metric view={row['metric_view_value']:.2f} "
              f"(delta {row['delta']:.2f})")
    print("\nExpected finding: 'Loss Ratio / Property' differs because the LEGACY measure\n"
          "divided by written premium (GWP) while the metric view uses earned premium —\n"
          "a 'which premium base?' drift hiding in one filter context. This is a\n"
          "definitional difference to confirm with the business, exactly what a\n"
          "reconciliation is for. Fix: agree the correct base, then re-run. Every other\n"
          "measure and cut ties to the penny / to 1e-6.")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 5. Export the diff (check column D yourself)
# MAGIC
# MAGIC Written to a Unity Catalog table you can open in Excel via the add-in, or export
# MAGIC to CSV — the "don't take my word for it, check the deltas" artifact.

# COMMAND ----------

(recon.write.mode("overwrite")
      .option("overwriteSchema", "true")
      .saveAsTable(f"{CATALOG}.{SCHEMA}.migration_reconciliation"))
print(f"Saved → {CATALOG}.{SCHEMA}.migration_reconciliation")
