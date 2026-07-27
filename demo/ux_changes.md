# What changes for the user — the educated-decision one-pager

Migrating the semantic model to Databricks keeps the Excel gesture the same, but a
few things genuinely change. Better to say them plainly up front than have users
discover them. None is a blocker; each is a known trade with a clear answer.

| Area | Today (SSAS / Tabular / PBI) | On the metric view | Honest read |
|------|------------------------------|--------------------|-------------|
| **Calculation groups** | Drag a "Time Calculation" modifier (YTD/PY/YoY) onto any measure | **Named measure variants** — pick `Loss Ratio YTD`, `GWP PY`, etc. from the field list | More field names, but each is unambiguous and self-describing. Explode only the combinations actually used. |
| **Hierarchies** | Drill-down hierarchies (e.g. Region → Country → Branch) built into the model | **Flat dimension fields**; drill by adding the next field to Rows | Familiar to pivot users; less "one-click drill". Model the levels as dimensions. |
| **Cube formulas** (`CUBEVALUE`/`CUBEMEMBER`) | Excel sheets wired directly to cube cells keep working | **Break** — no XMLA/cube endpoint on Databricks | Audit for these before migrating a workbook. Rebuild as pivots on the metric view or as parameterised add-in queries. This is the one to inventory early. |
| **Latency / interactivity** | In-memory cube = instant re-slice | Query round-trips to the SQL warehouse; re-slice is reconfigure-and-refresh | Fine for reporting; serverless keeps it quick. Very-low-latency interactivity is on the roadmap (real-time serving), not today. |
| **Freshness** | Whatever last night's cube rebuild produced (often "not ready by 9am") | **Live by default**, or a chosen as-of snapshot for sign-off users | A choice, not a constraint — see [`freshness.md`](freshness.md). Removes the 9am-rebuild fragility. |
| **Very large extracts** | Users try to pull huge cuts into a worksheet | Belongs in a dashboard/Genie, not a worksheet | See [`large_cut.md`](large_cut.md). The aggregation stays server-side. |

**The one to action first:** inventory any **cube formulas** (`CUBEVALUE`/`CUBEMEMBER`)
in existing workbooks — those are the only thing that outright breaks, and you want to
know where they are before you migrate a report, not after.

Everything else is either identical (the pivot gesture) or a manageable, explainable
change. Lead with what's the same; be candid about these; and the decision is an
informed one.
