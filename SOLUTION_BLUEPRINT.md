# Excel on a Governed Model — Solution Blueprint

The business keeps working in Excel exactly as they do today — open a workbook, connect to
"the model", drag fields into a pivot, get answers. The difference is invisible to them: the
model no longer lives in a Power BI dataset / SSAS cube / Tabular file that has to be rebuilt
every morning. It lives once in Databricks, and Excel reads it directly.

---

## The problem, in the users' own terms

- They don't connect Excel to tables — they connect to **a model**: pre-joined facts and
  dimensions with business-named measures (Gross Written Premium, Loss Ratio…). They pick fields
  and pivot; they never write SQL or join anything.
- That model is defined in **several places at once** — a Power BI/Tabular semantic model, an
  older SSAS cube, and per-report logic. The same metric can disagree between them.
- The delivery chain is fragile: the model often isn't rebuilt by 9am, gateways fail, and adding
  a table breaks it on volume/data-type errors — so users get reverted to old systems.

**What they actually want:** the same Excel experience, from one definition that can't drift and
doesn't fall over.

---

## 1. The Excel user journey (what the business sees)

This is the whole point — the gesture is unchanged. Restored, direct to Databricks:

1. Open Excel → the **Databricks Add-in** in the ribbon → **Sign in** (single sign-on).
2. **New import → Select data →** browse the catalog → pick **the model** (one object —
   e.g. `mv_underwriting`). Its dimensions and measures show up **by business name**; the joins
   are already inside it, so there is nothing to link.
3. Tick **Pivot Data** → drag fields into **Rows / Columns / Values / Filters**
   (e.g. Rows = Sector, Values = Gross Written Premium + Loss Ratio).
4. **Save and import** → the pivot lands on a sheet.
5. To re-slice: swap a dimension (Sector → Region, add Channel) and import again — a different
   cut, the same governed measures.
6. **Refresh** re-runs against Databricks for the latest numbers.

Net: pick the model, drag, pivot, refresh — the experience they already know. What changed is
where the model lives, and that's invisible to them.

Same governed definition also answers **Genie** (natural-language questions) and **AI/BI
dashboards** — so the number in an Excel pivot, a dashboard, and a Genie answer is provably the
same figure, because there is only one definition.

---

## 2. The components on the Databricks side (what an SA builds)

High level — five things, in one schema:

| # | Component | What it is | Why it's here |
|---|-----------|-----------|---------------|
| 1 | **Star schema** — fact + dimension tables (Unity Catalog) | The dimensional layer: `fct_*` measures, `dim_*` descriptors | The data the model sits on; full history, no 7-year cut needed |
| 2 | **Declared PK / FK constraints** (`ALTER TABLE … ADD CONSTRAINT`) | The relationships between facts and dims, declared once | Powers the auto ER diagram; documents the joins the model uses |
| 3 | **Metric view** (`CREATE VIEW … WITH METRICS LANGUAGE YAML`) | **The model.** Dimensions + measures (incl. time intelligence: YTD, rolling 12m) with the joins baked in | The single source of truth — the one object Excel, Genie and dashboards all read |
| 4 | **Serverless SQL warehouse** | The compute the add-in queries through | Scale-to-zero; aggregation happens here, only summarized rows return to Excel |
| 5 | **Databricks Excel Add-in** (public preview) | The bridge from Excel to the metric view | Delivers the connect-to-model pivot experience above |

Nothing about the metric is defined in Excel. Change a measure, add a dimension, add a table in
the metric view → every consumer (Excel included) sees it on next refresh. No workbook to
maintain, no second definition anywhere.

Two supporting artifacts, both generated from the catalog (not hand-drawn), so they stay current:
- **ER diagram** exported to PNG/PDF from the declared constraints (`sql/export_erd.py`) — for
  people who want to see the model's relationships without opening Databricks.
- The metric-view YAML itself is the human-readable definition of every measure.

---

## 3. Old → new: the easiest path, proven before scaled

Don't boil the ocean. Prove the smallest real slice end to end, then repeat the pattern. Three
waves, each retiring something, each independent:

### Wave 1 — one Excel report onto the model (start here; lowest risk)
- **Pick one simple, well-defined BAU Excel report** on a test system.
- Build (or reuse) the metric view for its subject area; point that workbook's Excel Add-in at
  the metric view instead of the legacy model.
- **Success test:** the same user opens Excel, pivots as before, numbers match the old report —
  and it's ready reliably, not "maybe by 9am".
- **Retires:** for that report, the SSAS/SSIS/SQL-Server chain behind it.
- **Why first:** no metric translation needed if the measures are simple sums/counts; it's the
  fastest visible win and it de-risks the whole approach.

### Wave 2 — the modelled metrics (the real semantic move)
- **Export the existing Tabular/Power BI model definition** (.bim / TMDL) and translate its
  measures — including YTD and rolling-12m time intelligence — into metric-view YAML
  (semi-automated; the hard part is the time-intelligence logic).
- Repoint the reports that used that model at the metric view.
- **Retires:** the Tabular/Power BI authoring layer for those metrics.

### Wave 3 — net-new (no migration; gravity)
- New dashboards and questions go to AI/BI + Genie on the same metric views. Nothing to migrate —
  new work simply lands in the right place.

**Delivery model:** we build the **first example of each wave together** with your team and hand
over a runbook; your team (or a partner working to the same runbook) industrialises the rest.

### The concrete first step to agree
1. **Candidate report** — you name one simple BAU Excel report + point us at a test system.
2. **Excel Add-in for IT** — the connector is public preview; deployment details supplied
   separately. (Known preview limitation on the managed-desktop path — see connectivity note;
   the web + self-service path works today.)
3. **Model** — we build the metric view for that report's subject area on synthetic-then-real data.
4. **Prove it** — same user, same Excel gesture, matching numbers, reliably on time. Then plan
   the rest from evidence, not slides.

---

## Reference — the working proof
A complete working example of all of the above (star schema, metric view, wrapper views, ER-diagram
export, Excel pivot, Genie, dashboard) is built on synthetic insurance data. It's the pattern this
blueprint describes, runnable end to end.
