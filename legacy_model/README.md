# Legacy model — the migration source

`Model.tmdl` is a small **Tabular model in TMDL format** (the plain-text format
[Tabular Editor](https://tabulareditor.com) and Power BI use to save a semantic
model). It stands in for what a real engagement starts from: the client's
existing SSAS / Power BI / Tabular model, **exported to TMDL**.

In a real migration you would:

1. Open the client's model in Tabular Editor (or connect to the SSAS/PBI dataset).
2. **Save as TMDL** (or use "Export" → TMDL) — producing exactly this kind of folder.
3. Hand that folder to the translation step — it's plain text, diffable, reviewable.

This synthetic version deliberately mirrors the star schema in
`lr_dev_aws_us_catalog.semantic_lakehouse` (FactPolicy ≈ `fct_premiums`,
FactClaims ≈ `fct_claims`, FactReserves ≈ `fct_reserves_snapshot`, the four dims)
so the DAX → metric-view translation can be shown and reconciled end to end.

## Why these 8 measures

They span the whole difficulty spectrum a real migration hits — so the scoping
conversation is honest, not a happy-path demo:

| # | Measure | Class | What it demonstrates |
|---|---------|-------|----------------------|
| 1 | GWP | clean | Direct `SUM` — trivial |
| 2 | Policy Count | clean | Distinct count |
| 3 | Incurred | clean | Sum of additive columns |
| 4 | Loss Ratio | clean | Measure composition → self-contained expression |
| 5 | GWP YTD | pattern | Time intelligence (`TOTALYTD`) → window measure |
| 6 | GWP Rolling 12m | pattern | Trailing period → window measure |
| 7 | Time Calc (calc group) | does-not-translate | No metric-view equivalent → **explode** into named measures |
| 8 | Open Reserves | does-not-translate | Semi-additive → **re-model** as a closing-position measure |

The translation of each is in [`../migration/translation.md`](../migration/translation.md),
and every translated number is reconciled against legacy semantics in
[`../migration/reconciliation.py`](../migration/reconciliation.py).

> The TMDL here is syntactically plausible but is **not** meant to compile against
> a live SSAS instance — it is the migration *input artifact*, read by humans and
> the translation step, not executed.
