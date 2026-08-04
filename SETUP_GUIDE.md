# Getting started — setup guide

*First steps for someone who hasn't done this before. Three parts: (1) install & configure
the Excel connector, incl. how internal IT distributes it; (2) create the governed metrics in
Databricks; (3) build a dashboard on the same metrics. Every step links to the official docs.*

> Prerequisites (all three parts): a Databricks workspace with **Unity Catalog** enabled, a
> **SQL warehouse** you can use (`CAN USE`), and your dim/fact tables already in Unity Catalog.

---

## 1. Install & configure the Databricks Add-in for Excel

The Add-in lets a business user connect Excel directly to Databricks — pick a model, pivot,
refresh — with no SQL. It requires Unity Catalog, and a workspace admin may need to enable the
connector if it is still in preview.

**Official docs:**
- Set up the Databricks Add-in for Excel — https://docs.databricks.com/aws/en/integrations/excel-setup
- Import & query data with the Add-in — https://docs.databricks.com/aws/en/integrations/excel-query
- Marketplace listing — search "Databricks" in Excel → Home → Add-ins (product ID `305c35cc-5f58-46b6-8701-d611c3379a86`)

### 1a. Individual / self-service (fastest — use this to test)
1. Open **Excel for the web** (excel.cloud.microsoft.com) — this path is the most reliable today.
2. **Home → Add-ins → Advanced → Upload My Add-in** → upload the add-in manifest.
3. Open the **Databricks** pane in the ribbon → **Connect to a different workspace** → enter your
   workspace URL → **Sign in** (SSO).
4. **New import → Select data →** browse the catalog → pick your model (a metric view, e.g.
   `mv_underwriting`) → tick **Pivot Data** → drag fields → **Save and import**.

> **Sign-in says "Need admin approval"?** A workspace/Entra admin must grant tenant-wide consent to
> the Databricks enterprise application (see the setup doc, "Microsoft Entra consent").
> **Connectivity note (preview):** the managed + Mac-desktop path has a known pre-GA limitation; the
> **Excel-for-web + self-service** path works today. Windows desktop works via a Trusted Add-in
> Catalog folder.

### 1b. Chapter for internal IT — mass distribution to users' computers
Most users can't (and shouldn't) install add-ins themselves. IT deploys it centrally and
allowlists the workspace so sign-in works. This is the **admin-managed** path.

**Deploy the add-in (Microsoft 365 admin center):**
1. **Microsoft 365 admin center → Settings → Integrated apps → Deploy Add-in.**
2. Either **Deploy from the Marketplace** ("Databricks") or **Upload a custom manifest**.
3. Assign to the target users / groups. The add-in then appears in their Excel ribbon automatically.
   - Docs: Deploy add-ins in the admin center — https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-deployment-of-add-ins

**Allowlist your Databricks workspace(s) via PowerShell** (so users can sign in), run as admin:
```powershell
Install-Module -Name O365CentralizedAddInDeployment
Import-Module O365CentralizedAddInDeployment
Connect-OrganizationAddInService          # sign in as a Microsoft 365 admin
Get-OrganizationAddIn                      # confirm the Databricks add-in is deployed
# Allowlist the workspace URL(s) the add-in may connect to:
Set-OrganizationAddInOverrides -ProductId <databricks-add-in-product-id> -AppDomains "https://<your-workspace>.cloud.databricks.com"
```
Allowlist changes take a few minutes to propagate. Full admin steps (module, manifest, per-platform
notes) are in the setup doc: https://docs.databricks.com/aws/en/integrations/excel-setup

**IT checklist:** UC enabled · connector preview enabled (if applicable) · Entra tenant-wide consent
granted · workspace URL allowlisted (`AppDomains`) · add-in assigned to user groups · users have
`CAN USE` on a SQL warehouse.

---

## 2. Create the governed metrics in Databricks (Unity Catalog metric views)

You already have dimensions and facts in Unity Catalog. A **metric view** turns them into *the
model*: pre-joined, business-named measures (Gross Written Premium, Loss Ratio) defined **once**.
It's written in YAML, created with `CREATE VIEW … WITH METRICS`.

**The one thing that matters:** define a measure here and it is visible **everywhere** — the Excel
Add-in, Databricks AI/BI dashboards, and Genie all read the *same* definition, so the number in an
Excel pivot, a dashboard, and a Genie answer is provably identical. There is no second definition to
drift.

**Official docs:**
- Create a metric view (SQL + UI, privileges) — https://docs.databricks.com/aws/en/uc-semantics/metric-views/create
- Metric view YAML reference (joins, measures, windows/time-intelligence, parameters) — https://docs.databricks.com/aws/en/uc-semantics/metric-views/yaml-reference
- Metric views overview — https://docs.databricks.com/aws/en/uc-semantics/metric-views/

**Minimal example** (adapt table/column names to yours):
```sql
CREATE OR REPLACE VIEW main.my_schema.mv_underwriting WITH METRICS LANGUAGE YAML AS $$
version: 1.1
comment: "Underwriting KPIs — one governed definition for Excel, dashboards and Genie."
source: main.my_schema.fct_underwriting
joins:
  - name: product
    source: main.my_schema.dim_product
    'on': source.product_key = product.product_key
  - name: geography
    source: main.my_schema.dim_geography
    'on': source.geography_key = geography.geography_key
dimensions:
  - name: Sector
    expr: product.sector
  - name: Region
    expr: geography.region
measures:
  - name: Gross Written Premium
    expr: SUM(source.gwp)
  - name: Claims Incurred
    expr: SUM(source.claims_incurred)
  - name: Loss Ratio
    expr: try_divide(SUM(source.claims_incurred), SUM(source.earned_premium))
$$;
```
Query it with `MEASURE()`: `SELECT Sector, MEASURE(\`Gross Written Premium\`), MEASURE(\`Loss Ratio\`)
FROM main.my_schema.mv_underwriting GROUP BY Sector`.

**Privileges to create one:** `SELECT` on the source tables, `USE CATALOG` + `USE SCHEMA` +
`CREATE TABLE` on the destination schema, and `CAN USE` on the warehouse.

**Time intelligence (YTD, rolling 12m):** metric views support windowed/semi-additive measures —
see the YAML reference "window" grammar (`window: {order, range, semiadditive}`; ranges like
`trailing 12 month`; semi-additive `first|last` required on windowed measures). This is the part
that replaces Tabular/DAX time-intelligence.

**Don't want to hand-write YAML?** Catalog Explorer has a UI to build a metric view (and generate
the YAML), and **Genie Code** can generate the YAML for you from a description.

---

## 3. Build a dashboard on the same metrics (AI/BI dashboards)

An AI/BI (Lakeview) dashboard built on the metric view reuses the exact same measures — so the
dashboard and the Excel pivot cannot disagree. Add a Genie space on the same metric view and users
can ask questions in natural language against the identical definition.

**Official docs:**
- AI/BI dashboards — https://docs.databricks.com/aws/en/dashboards/
- Create a dashboard — https://docs.databricks.com/aws/en/dashboards/create
- Genie (natural-language over your data) — https://docs.databricks.com/aws/en/genie/

**Steps:**
1. **New → Dashboard.** Add a **dataset** whose query targets the metric view, e.g.
   `SELECT Region, MEASURE(\`Gross Written Premium\`) gwp, MEASURE(\`Loss Ratio\`) lr FROM
   main.my_schema.mv_underwriting GROUP BY Region`.
2. Add widgets (bar/line/table/counter) bound to that dataset; add filters on the dimensions.
3. **Publish**, then share with the business audience.
4. (Optional) Create a **Genie space** over the same metric view so users can ask
   "Loss ratio by sector this year?" and get the governed number.

Because all three consumers (Excel, dashboard, Genie) read the metric view, changing a measure or
adding a dimension updates every consumer on next refresh — one definition, no rebuild.

---

## The working proof — open it in Databricks

A complete, runnable example of everything above (star schema, metric view, wrapper views with
YTD/rolling-12m, ER-diagram export, Excel pivot, dashboard, Genie, and a legacy-model → metric-view
migration with reconciliation) is public:

**Repo: https://github.com/wryszka/semantic-lakehouse-poc**

**To open it in Databricks (Git folder):**
1. In your workspace: **Workspace → (your home) → Create → Git folder**.
2. Git repository URL: `https://github.com/wryszka/semantic-lakehouse-poc` → Create.
3. Set a warehouse, then run the numbered SQL in `sql/` in order (`01_*` → `05_*`) to build the
   schema, tables and metric views; `sql/export_erd.py` regenerates the ER diagram from the
   declared PK/FK constraints. See the repo `README.md` and `demo/` for the walkthrough.
   (Docs: Git folders — https://docs.databricks.com/aws/en/repos/)

*All example data is synthetic. Replace `main.my_schema` and table/column names with your own.*
