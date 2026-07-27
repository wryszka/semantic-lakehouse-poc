# Demo script — migration evidence (20 minutes)

Audience: the BI/modelling team and business stakeholders deciding whether to migrate
their SSAS cube / Tabular model / Power BI datasets to one governed metric view.

The arc: **it works → here's how your model translates → here's exactly where it's
easy, where the effort is, where the experience changes → and here's the proof the
numbers tie.** Evidence, not assertion.

Everything runs on synthetic insurance data (Bricksurance) on any workspace with a
serverless SQL warehouse. Numbers below are the deterministic demo values.

---

### 1 · Excel pivot on the metric view — the unchanged gesture (4 min)
Open Excel → Databricks Add-in → pick **`mv_underwriting_v2`** → Pivot Data →
Rows: Sector, Values: GWP + Loss Ratio. Drag, pivot, refresh — exactly as today.
**Say:** "your users' gesture doesn't change. What changed is invisible — the model
lives once in Databricks now, not in a cube that rebuilds every night."

### 2 · Same number, several doors (3 min)
The loss ratio you just saw per sector (Technology highest ≈ **0.58**) — show it
identical in **Genie** (ask "loss ratio by sector this year") and on the **AI/BI
dashboard**. **Say:** "one definition, so Excel, Genie and the dashboard can't
disagree. That's the whole point — no more seven-numbers-from-seven-models."

### 3 · Open the legacy model, show a measure and its twin (3 min)
Open [`legacy_model/Model.tmdl`](../legacy_model/Model.tmdl) → measure **GWP**
(`SUM(FactPolicy[GrossPremium])`) → its YAML twin in
[`sql/05_metric_view_v2.sql`](../sql/05_metric_view_v2.sql). **Say:** "this is your
Tabular model, exported to text. Most measures — about 70–80% — translate like this,
one line to one line, in minutes." Point at [`migration/translation.md`](../migration/translation.md).

### 4 · Time intelligence — where the effort goes (3 min)
Measure **[5] GWP YTD** (`TOTALYTD`) → the window-measure YAML
(`range: trailing 12 month`). **Say:** "the middle slice — time intelligence — is
the real work. DAX filter-context becomes a declarative window. It's a known rewrite,
but you budget time here, and you *reconcile* it (coming up) because calendar-YTD and
trailing-12m are easy to conflate."

### 5 · Calculation group — the explosion, UX change stated plainly (2 min)
Measure **[7] Time Calc** → explain there is no calc-group concept; it becomes
explicit named measures (`GWP YTD`, `GWP PY`, `GWP YoY %`…). **Say honestly:** "this
one changes the user experience. Instead of dragging a 'Time Calculation' modifier,
users pick a named measure variant. More names, but each is unambiguous. This is the
kind of change you tell people about up front." Point at
[`demo/ux_changes.md`](ux_changes.md).

### 6 · Semi-additive reserves — the silent-failure slide (3 min)
Run [`migration/semi_additive_demo.sql`](../migration/semi_additive_demo.sql).
**Wrong** (sum across Apr+May+Jun) shows Technology ≈ **£547M**; **right** (closing
position 30 Jun) ≈ **£184M**. **Say:** "this is the mistake a naive migration makes
*silently*. Summing a reserve balance across months triple-counts it, and it looks
perfectly plausible on a dashboard. The metric view's semi-additive measure gets the
closing position right — and matches the hand-written check to the penny."

### 7 · Reconciliation — you decide from evidence (2 min)
Open the output of [`migration/reconciliation.py`](../migration/reconciliation.py)
(table `migration_reconciliation`, or in Excel via the add-in). 20 rows, 19 pass,
**one flagged**: Loss Ratio / Property (legacy 0.508 vs metric view 0.586).
**Say:** "we re-implemented your old model's numbers and diffed them against the new
metric view. Everything ties to the penny except this one row — and it's not a bug,
it's a definitional drift: the old measure divided by written premium, the new one by
earned. That's the conversation reconciliation forces you to have *before* an auditor
does. You sign off on evidence, not on my word — check column D yourself."

---

**Close:** clean majority translates fast; time intelligence is the budgeted middle;
calc-groups and semi-additive force a couple of explicit decisions (and one UX change);
and every number is reconciled. That's a migration you can scope and defend — one real
report at a time (Wave 1), then repeat.
