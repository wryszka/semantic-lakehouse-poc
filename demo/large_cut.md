# The large-cut anti-pattern (one honest paragraph)

Occasionally a user will try to pull a very large, fully-detailed cut — say every
policy-month row across all sectors, regions and channels for ten years — into an
Excel worksheet. Don't. That's hundreds of thousands to millions of rows; it's slow,
it bloats the workbook, and Excel's row cap (1,048,576) will silently truncate it.
The metric view aggregates **server-side** — a pivot returns the summarised answer,
not the raw rows — so the right home for "show me everything at full grain" is a
**dashboard** (a curated view that stays live) or **Genie** (ask the specific question
and get just that answer). The rule of thumb for users: *if you're about to drag a
raw fact into Values with no grouping, you want a dashboard or Genie, not a worksheet.*
The deep version of this story — "the monthly MI pack nobody can pivot in Excel any
more" on ~800k rows — is already built as Use Case 3 in the Excel migration accelerator;
point there rather than rebuilding it here.
