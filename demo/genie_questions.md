# Genie questions — the target-state journey (same definition, natural language)

Genie answers over the **same metric view** the Excel pivot and the dashboard read.
The point of this track: a business user asks in plain English and gets the governed
number — no SQL, no model rebuild, and it agrees with Excel because there's one
definition.

Curated questions spanning the measures. Verify against the space before a live run
(first answer can take ~30–60s; a warmed conversation is instant).

### The measures, in plain English
1. **"What is our loss ratio by sector this year?"**
   → the same figures as the Excel pivot (Technology highest ≈ 0.58). *This is the
   scripted "same number, several doors" moment — show it beside the pivot.*
2. **"Show gross written premium by sector for the latest full year."**
3. **"Which sector has the highest loss ratio, and what's its GWP?"**
4. **"Plot monthly gross written premium for Technology over the last three years."**
   → exercises the time dimension.
5. **"What's the rolling 12-month GWP for Property as of the latest month?"**
   → exercises a window measure (`GWP Rolling 12m`).
6. **"Break loss ratio down by region and channel for this year."**
   → multi-dimension slice, the kind of ad-hoc cut users used to build by hand.

### The scripted side-by-side (the beat that lands)
Run **Q1 in Genie** and the **same pivot in Excel** on screen together. Same loss
ratio per sector, to the same figures. Say: *"different door, same governed number —
because both read `mv_underwriting_v2`, not their own copy of the logic."*

### One question Genie should decline / clarify (governed behaviour, honestly)
7. **"What's our solvency capital requirement by entity?"**
   → the metric view has no such measure. Genie should say it can't answer that from
   this data / ask for clarification, rather than invent a number. *Show this on
   purpose:* a governed semantic layer is trustworthy precisely because it declines
   what it doesn't know, instead of hallucinating. That honesty is the selling point,
   not a weakness.

> Reuse note: the mature "ad-hoc BI on 800k rows, Excel can't pivot this" Genie +
> AI/BI story already lives in the **Excel migration accelerator** (Use Case 3). This
> semantic-lakehouse demo focuses on *the same governed number across doors*; point
> at the accelerator for the deep self-service-BI narrative rather than rebuilding it.
