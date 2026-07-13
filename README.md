# Semantic Lakehouse POC

A best-practice pattern for a **governed semantic layer on Databricks**: metrics are
defined once in a Unity Catalog **metric view**, and every consumer — Genie, AI/BI
Dashboards, Excel, Power BI — reads that single definition. Nothing downstream defines
a metric of its own.

## About this demo

All data is synthetic, generated for **Bricksurance SE**, a fictional insurer. Nothing
here reflects any real company's data, systems, or figures. Built for demonstration
purposes only.

## The pattern

```
star schema (dim_/fct_, PK/FK declared → auto ER diagram)
        └── metric view  mv_underwriting          ← the ONLY place metrics are defined
              ├── native tier: AI/BI Dashboards + Genie (metric-aware, NL answers)
              └── governed SQL tier: wrapper views (plain SQL projections)
                    ├── Excel  (embedded query + Data → Refresh)
                    └── Power BI (DirectQuery, reads like a table)
```

Design rules encoded in the SQL:

- **Metrics defined once.** Wrapper views only resolve `MEASURE()` at a pinned,
  named grain — they contain no business logic of their own, so numbers cannot drift.
- **Ratio guardrail.** Non-additive metrics (loss ratio) are exposed alongside their
  numerator and denominator, and the pre-computed column is named
  `*_at_this_grain` so a pivot grand total is recomputed, never summed.
- **Time intelligence in the platform, not the BI tool.** YTD and rolling-12-month
  measures are windowed SQL in the wrapper tier — defined once, read everywhere.
- **Full history.** Nothing is imported into a BI tool, so no row-count cuts are needed.

## Contents

| Path | What |
|------|------|
| `sql/01_star_schema.sql` | Schema, dims, facts, synthetic data, PK/FK constraints |
| `sql/01b_remediation.sql` | Claims fact + constraints follow-up (idempotent re-run helpers) |
| `sql/02_metric_view.sql` | The metric view (the trunk) |
| `sql/03_wrapper_views.sql` | Wrapper views: monthly + BAU report + region/channel |
| `sql/run_sql.py` | Statement-by-statement runner against a SQL warehouse |
| `sql/build_dashboard.py` | Lakeview dashboard (reads the metric view with `MEASURE()`) |
| `excel/build_excel_pack.py` | BAU Excel workbook generator + live-connection instructions |

## Running it

```bash
# point run_sql.py at your workspace/warehouse, then:
python3 sql/run_sql.py sql/01_star_schema.sql sql/01b_remediation.sql \
                       sql/02_metric_view.sql sql/03_wrapper_views.sql
python3 sql/build_dashboard.py
uv run --native-tls --with openpyxl excel/build_excel_pack.py
```

A Genie space is created over `mv_underwriting` with a non-additivity instruction —
see the space description in the workspace.
