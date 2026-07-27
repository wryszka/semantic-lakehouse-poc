# Translation pack — DAX → metric-view YAML

How each measure in the legacy Tabular model ([`../legacy_model/Model.tmdl`](../legacy_model/Model.tmdl))
becomes a measure in the Databricks metric view ([`../sql/05_metric_view_v2.sql`](../sql/05_metric_view_v2.sql)),
and — honestly — where it's trivial, where the effort goes, and where the user
experience changes. Every translated number is proven against legacy semantics in
[`reconciliation.py`](reconciliation.py).

## The three classes

| Class | What it means | Rough share of a real model | Effort |
|-------|---------------|------------------------------|--------|
| **Clean** | Direct SUM/COUNT/ratio — one-to-one translation | **~70–80%** of measures | Minutes each |
| **Pattern** | Time intelligence & similar — a known rewrite (DAX filter-context → window measure) | **~15–25%** | The real work; budget time here |
| **Re-derive** | No metric-view equivalent as written (calc groups, semi-additive) — must re-model | **a handful** | Design decision + a UX change |

The rule of thumb matters for scoping: most of a model is clean and fast; a
meaningful slice is patterned time-intelligence that needs careful rewriting; and
a small tail forces a genuine re-modelling decision. Plan the project around the
middle and the tail, not the easy majority.

---

## Clean (direct translation)

### [1] GWP
```
DAX:   GWP = SUM(FactPolicy[GrossPremium])
YAML:  - name: GWP
         expr: SUM(gross_written_premium)
```
Rule: additive column SUM → identical SUM. Nothing to think about.

### [2] Policy Count
```
DAX:   Policy Count = DISTINCTCOUNT(FactPolicy[PolicyNumber])
YAML:  - name: Policy Count
         expr: COUNT(DISTINCT policy_id)     -- (synthetic fact is pre-aggregated: SUM(policy_count))
```
Rule: `DISTINCTCOUNT` → `COUNT(DISTINCT …)`. (In this synthetic star the fact is
already at monthly-segment grain with a `policy_count` column, so the demo view
sums it; against raw policy rows it's a straight distinct count.)

### [3] Incurred
```
DAX:   Incurred = SUM(FactClaims[Paid]) + SUM(FactClaims[OutstandingReserve])
YAML:  - name: Incurred
         expr: SUM(claims_incurred)          -- claims_incurred = paid + outstanding
```
Rule: sum-of-sums → single SUM over the combined column. (Watch the definition:
"incurred" must include the reserve movement — the reconciliation notebook seeds
exactly this trap to show what happens when a legacy measure quietly didn't.)

### [4] Loss Ratio
```
DAX:   Loss Ratio = DIVIDE([Incurred], [GWP])
YAML:  - name: Loss Ratio
         expr: try_divide(SUM(claims_incurred), SUM(earned_premium))
```
Rule: **measure composition inlines** — DAX references other measures; the metric
view expression is self-contained (numerator and denominator written out).
`DIVIDE` → `try_divide` (null-safe on zero). Note the correct denominator is
**earned** premium — the "which premium base?" choice is the seeded reconciliation
finding.

---

## Pattern (time intelligence → window measures)

DAX time intelligence relies on the marked date table and filter context.
Metric views express the same thing declaratively as **window measures**:
`window: { order, range, semiadditive }`. Grammar verified on this warehouse —
`range` accepts `current | cumulative | trailing <n> <unit> | leading <n> <unit>`;
`semiadditive` (`first|last`) is **required** on any windowed measure.

### [5] GWP YTD
```
DAX:   GWP YTD = TOTALYTD([GWP], DimDate[Date])
YAML:  - name: GWP YTD
         expr: SUM(gross_written_premium)
         window:
           - order: Month
             range: trailing 12 month     # (see note on YTD vs rolling below)
             semiadditive: last
```
Rule: `TOTALYTD` → cumulative window over the date order. **Effort note:** true
calendar-YTD (resets 1 Jan) vs a trailing-12-month running total are *different*
and easy to conflate — decide which the business actually means, per measure.
Reconcile against the legacy numbers to be sure.

### [6] GWP Rolling 12m
```
DAX:   GWP Rolling 12m =
         CALCULATE([GWP], DATESINPERIOD(DimDate[Date], MAX(DimDate[Date]), -12, MONTH))
YAML:  - name: GWP Rolling 12m
         expr: SUM(gross_written_premium)
         window:
           - order: Month
             range: trailing 12 month
             semiadditive: last
```
Rule: `DATESINPERIOD(..., -12, MONTH)` → `range: trailing 12 month`. This is the
clean, unambiguous window case.

---

## Re-derive (does not translate as written)

### [7] Time Calc — calculation group → **explode into named measures**
```
DAX (calc group items applied to ANY measure):
   YTD    = TOTALYTD(SELECTEDMEASURE(), DimDate[Date])
   PY     = CALCULATE(SELECTEDMEASURE(), SAMEPERIODLASTYEAR(DimDate[Date]))
   YoY %  = DIVIDE(SELECTEDMEASURE() - PY, PY)
```
**There is no calculation-group concept in metric views.** A calc group is a
*modifier* the user drags alongside any measure. In the metric view you instead
create the **explicit combinations you need**:
```
YAML:  GWP YTD, GWP PY, GWP YoY %, Incurred YTD, Incurred PY, Loss Ratio YTD, …
```
**UX change to state plainly:** users stop dragging a "Time Calculation" modifier
and instead **pick the named measure variant** (e.g. `Loss Ratio YTD`) from the
field list. It's more field names, but each is unambiguous and self-describing —
and there's no hidden interaction between a modifier and an arbitrary base measure.
Explode only the combinations that are actually used; don't generate the full
cross-product for its own sake.

### [8] Open Reserves — semi-additive → **re-model as a closing position**
```
DAX:   Open Reserves =
         CALCULATE(SUM(FactReserves[Amount]),
                   LASTNONBLANK(DimDate[Date], CALCULATE(SUM(FactReserves[Amount]))))
YAML:  - name: Open Reserves           # in mv_reserves (own source/grain)
         expr: SUM(open_reserve)
         window:
           - order: Month
             range: current
             semiadditive: last
```
Rule: `LASTNONBLANK`-style semi-additivity → a **window measure with
`semiadditive: last`** over month-end snapshots. This requires the source to be a
**snapshot** table (`fct_reserves_snapshot`, one balance per month-end), not a
transaction feed — that's the re-modelling. The failure mode if you *don't* do
this is spelled out and demonstrated in [`semi_additive_demo.sql`](semi_additive_demo.sql):
a naive SUM across months is ~3× too big and looks plausible.

---

## Summary

| # | Measure | Class | Translation rule |
|---|---------|-------|------------------|
| 1 | GWP | clean | SUM → SUM |
| 2 | Policy Count | clean | DISTINCTCOUNT → COUNT(DISTINCT) |
| 3 | Incurred | clean | sum-of-sums → single SUM (mind the definition) |
| 4 | Loss Ratio | clean | measure composition → self-contained `try_divide` |
| 5 | GWP YTD | pattern | TOTALYTD → cumulative/trailing window |
| 6 | GWP Rolling 12m | pattern | DATESINPERIOD → `range: trailing 12 month` |
| 7 | Time Calc group | re-derive | no equivalent → explode into named measures (UX change) |
| 8 | Open Reserves | re-derive | semi-additive → snapshot source + `semiadditive: last` |

Proof that the clean + pattern translations tie to legacy semantics — and what a
caught discrepancy looks like — is in [`reconciliation.py`](reconciliation.py).
