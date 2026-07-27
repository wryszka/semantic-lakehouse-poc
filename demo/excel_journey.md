# Excel walkthrough — connect to the model, pivot, refresh

The business user's journey, unchanged in gesture, now served from Databricks.
(Screenshots to be added inline; steps verified against the working add-in.)

1. **Ribbon** → open Excel → **Home** tab → the **Databricks** Add-in button.
   _[screenshot: ribbon with Databricks add-in]_
2. **Sign in** — enter the workspace URL, single sign-on.
   _[screenshot: add-in sign-in pane]_
   > Connectivity note: today the reliable path is **Excel for the web** with the
   > self-service manifest and third-party cookies allowed. The centrally-managed
   > desktop path (esp. macOS) has a known public-preview auth issue — see the
   > connectivity note in the runbook. Don't demo on managed+Mac.
3. **New import → Select data →** browse the **Catalog** to
   `lr_dev_aws_us_catalog → semantic_lakehouse → mv_underwriting_v2` → **Select**.
   _[screenshot: catalog browser showing the metric view]_
4. **Pivot fields** — tick **Pivot Data**. The metric view's dimensions and measures
   appear **by business name** (Sector, Region, Channel, GWP, Loss Ratio, GWP YTD…),
   joins already inside — nothing to link.
   _[screenshot: dimensions + measures list]_
5. **Configure** — drag Rows: `Sector`, Values: `GWP` + `Loss Ratio`, optional Filter:
   `Year`. **Save and import.** The pivot lands on a new sheet.
   _[screenshot: Row/Column/Value drop zones]_
6. **Re-slice** — swap `Sector` for `Region`, or add `Channel`, and import again — a
   different cut, the same governed measures.
   _[screenshot: re-sliced pivot]_
7. **Refresh** — **Imports** tab → Refresh (or Refresh All) re-runs against Databricks
   for the latest numbers.
   _[screenshot: Imports tab with refresh]_

**The line:** pick the model, drag, pivot, refresh — the experience they already know.
What changed is where the model lives (once, in Unity Catalog), and that's invisible
to them. Same definition answers Genie and the dashboards, so the numbers can't drift.

Mirrors the user-journey section of [`../SOLUTION_BLUEPRINT.md`](../SOLUTION_BLUEPRINT.md).
