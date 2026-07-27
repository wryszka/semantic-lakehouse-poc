# Freshness — live vs as-of, a choice not a constraint

The legacy cube gave users "whatever last night's rebuild produced" — and when that
rebuild slipped, the model wasn't ready by 9am and people got reverted to old systems.
On the metric view, freshness becomes a **deliberate choice per consumer**, and the
9am-rebuild fragility goes away because nothing has to be rebuilt into a cube.

- **Live (default).** Excel refresh, Genie and dashboards query the current tables.
  Numbers reflect the latest loaded data. This is what most reporting wants.
- **As-of snapshot (for sign-off).** Some users — reserving, financial close, anyone
  who signs a number — need a *frozen* view they can reproduce later. Two ways:
  - **Delta time travel:** query the table `AS OF` a timestamp/version — reproduce
    exactly what a report said on the sign-off date, months later.
  - **Dated snapshot tables / `_asof` views:** materialise a labelled month-end
    position (this is already how `fct_reserves_snapshot` works for reserves) and
    point sign-off consumers at the snapshot rather than the live table.

The design rule: **live for exploration and BAU reporting; snapshot/as-of for anything
that gets signed.** Both read the same governed metric definitions — freshness is a
consumption choice layered on top, not a second copy of the logic.

> Optional to build for a given engagement: a small set of `_asof` views or a daily
> snapshot job. Mentioned here as the pattern; not required for the core demo.
