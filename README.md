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

## Migration evidence

Beyond "Excel works on Databricks", this repo shows **how a legacy Tabular/SSAS model
migrates** — where it's easy, where the effort is, where the user experience changes,
and proof the numbers tie:

- `legacy_model/` — a synthetic Tabular model in **TMDL** (the migration *source*), with
  8 DAX measures spanning clean → pattern → does-not-translate.
- `migration/translation.md` — **DAX → metric-view YAML**, measure by measure, with the
  clean / pattern / re-derive classification and scoping rule of thumb.
- `migration/semi_additive_demo.sql` — the **silent-failure** slide: naive SUM of a
  reserve balance across months (~3× too big) vs the correct closing position.
- `migration/reconciliation.py` — **the sign-off artifact.** Re-implements legacy
  semantics in SQL, diffs against the metric view (measure × sector), all rows pass
  **except one seeded discrepancy** (a "which premium base?" drift on one cut) left in
  to show what a caught finding looks like. Writes table `migration_reconciliation`.
- `demo/` — 20-minute `demo_script.md`, `ux_changes.md` (calc-groups → named measures,
  cube formulas break, freshness), `genie_questions.md`, `excel_journey.md`, plus the
  large-cut and freshness notes.

## Metric-view capability notes

Window measures (YTD, rolling-12m, semi-additive reserves) require window support in the
metric-view engine — **verified available on the target serverless warehouse**. Grammar:
`window: { order, range, semiadditive }`; `range` ∈ `current | cumulative | trailing <n>
<unit> | leading <n> <unit>`; `semiadditive` (`first|last`) is **required** on any
windowed measure. If a workspace's runtime/warehouse channel rejects window measures,
fall back to the wrapper-view windowed SQL (`sql/03_wrapper_views.sql`) and note the
required channel rather than failing silently.

## Contents

| Path | What |
|------|------|
| `sql/01_star_schema.sql` | Schema, dims, facts, synthetic data, PK/FK constraints |
| `sql/01b_remediation.sql` | Claims fact + constraints follow-up (idempotent re-run helpers) |
| `sql/02_metric_view.sql` | The original metric view (the trunk) |
| `sql/03_wrapper_views.sql` | Wrapper views: monthly + BAU report + region/channel |
| `sql/04_reserves_snapshot.sql` | Month-end reserve **positions** (semi-additive source) |
| `sql/05_metric_view_v2.sql` | `mv_underwriting_v2` (full translation) + `mv_reserves` |
| `sql/export_erd.py` | ER diagram → PNG/PDF from declared PK/FKs (9 tables) |
| `sql/run_sql.py` | Statement-by-statement runner against a SQL warehouse |
| `sql/build_dashboard.py` | Lakeview dashboard (reads the metric view with `MEASURE()`) |
| `legacy_model/` | TMDL legacy model (migration source) + README |
| `migration/` | translation pack, semi-additive demo, reconciliation notebook |
| `demo/` | demo script + UX-change / Genie / Excel-journey docs |
| `excel/build_excel_pack.py` | BAU Excel workbook generator + connectivity instructions |

## Running it

```bash
# point run_sql.py at your workspace/warehouse (env vars), then:
export DATABRICKS_PROFILE=… DATABRICKS_HOST=https://… DATABRICKS_WAREHOUSE_ID=…
python3 sql/run_sql.py sql/01_star_schema.sql sql/01b_remediation.sql \
                       sql/02_metric_view.sql sql/03_wrapper_views.sql \
                       sql/04_reserves_snapshot.sql sql/05_metric_view_v2.sql
python3 sql/build_dashboard.py
python3 sql/export_erd.py                         # ER diagram PNG/PDF
uv run --native-tls --with openpyxl excel/build_excel_pack.py
# reconciliation notebook: import migration/reconciliation.py to the workspace and
# run on a serverless notebook / warehouse — writes table migration_reconciliation.
```

A Genie space is created over the metric view with a non-additivity instruction —
see the space description in the workspace.
