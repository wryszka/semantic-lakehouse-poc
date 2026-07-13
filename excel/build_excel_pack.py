#!/usr/bin/env python3
"""Build the Excel demo pack: BAU report snapshot + live-connection wiring instructions.

Run: uv run --with openpyxl --native-tls build_excel_pack.py
"""
import json
import subprocess
import urllib.request

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

HOST = "https://fevm-lr-dev-aws-us.cloud.databricks.com"
WAREHOUSE = "a3b61648ea4809e3"
HTTP_PATH = f"/sql/1.0/warehouses/{WAREHOUSE}"
BAU_SQL = "SELECT * FROM lr_dev_aws_us_catalog.semantic_lakehouse.vw_bau_premiums_by_sector"
PIVOT_SQL = ("SELECT month, year, sector, gross_written_premium, earned_premium, claims_incurred, "
             "policy_count, claim_count, loss_ratio_at_this_grain, gwp_ytd, gwp_rolling_12m, "
             "loss_ratio_rolling_12m FROM lr_dev_aws_us_catalog.semantic_lakehouse.vw_underwriting_monthly "
             "WHERE year >= 2024")

tok = json.loads(subprocess.run(["databricks", "auth", "token", "-p", "DEV"],
                                capture_output=True, text=True).stdout)["access_token"]


def query(stmt):
    body = json.dumps({"warehouse_id": WAREHOUSE, "statement": stmt,
                       "wait_timeout": "50s", "format": "JSON_ARRAY"}).encode()
    req = urllib.request.Request(f"{HOST}/api/2.0/sql/statements/", data=body,
                                 headers={"Authorization": f"Bearer {tok}",
                                          "Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req))
    assert r["status"]["state"] == "SUCCEEDED", r["status"]
    cols = [c["name"] for c in r["manifest"]["schema"]["columns"]]
    types = [c["type_name"] for c in r["manifest"]["schema"]["columns"]]
    return cols, types, r["result"].get("data_array", [])


def write_sheet(ws, cols, types, rows):
    hdr_fill = PatternFill("solid", fgColor="1B3139")
    for j, c in enumerate(cols, 1):
        cell = ws.cell(row=1, column=j, value=c)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = hdr_fill
    for i, row in enumerate(rows, 2):
        for j, (v, t) in enumerate(zip(row, types), 1):
            if v is None:
                continue
            if t in ("DECIMAL", "DOUBLE", "FLOAT"):
                v = float(v)
            elif t in ("INT", "BIGINT", "LONG", "SMALLINT"):
                v = int(v)
            ws.cell(row=i, column=j, value=v)
    for j, c in enumerate(cols, 1):
        ws.column_dimensions[get_column_letter(j)].width = max(14, len(c) + 2)
    ws.freeze_panes = "A2"


wb = Workbook()

# Sheet 1: the BAU report (what the business opens every morning)
ws = wb.active
ws.title = "BAU Premiums by Sector"
cols, types, rows = query(BAU_SQL)
write_sheet(ws, cols, types, rows)

# Sheet 2: pivot-ready extract from the wrapper view
ws2 = wb.create_sheet("Pivot Source (2024+)")
cols, types, rows = query(PIVOT_SQL)
write_sheet(ws2, cols, types, rows)

# Sheet 3: how to wire the live refresh
ws3 = wb.create_sheet("Live Connection Setup")
lines = [
    ("How this workbook goes live (one-time setup, ~2 minutes)", True),
    ("", False),
    ("This snapshot was produced from the governed wrapper view. To make Data > Refresh All", False),
    ("pull live data, add a Power Query connection:", False),
    ("", False),
    ("1. Data > Get Data > From Other Sources > From ODBC (or 'From Databricks' if available)", True),
    (f"   Server hostname:  {HOST.replace('https://', '')}", False),
    (f"   HTTP path:        {HTTP_PATH}", False),
    ("   Authentication:   OAuth (Azure AD / U2M) or personal access token", False),
    ("", False),
    ("2. Paste this SQL as the query:", True),
    (f"   {BAU_SQL}", False),
    ("", False),
    ("3. Load to the 'BAU Premiums by Sector' sheet. Done - the workbook now refreshes", False),
    ("   from the same governed metric definitions as Genie, dashboards and Power BI.", False),
    ("", False),
    ("Power Query (M) equivalent:", True),
    (f'   Odbc.Query("DSN=Databricks", "{BAU_SQL}")', False),
    ("", False),
    ("IMPORTANT - the loss_ratio_* columns are valid only at the row grain.", True),
    ("Never SUM a ratio column in a pivot: recompute as SUM(claims_incurred) / SUM(earned_premium).", False),
    ("The additive columns (premiums, counts) are safe to total.", False),
    ("", False),
    ("About this demo: synthetic Bricksurance SE data, generated for demonstration purposes.", False),
]
for i, (txt, bold) in enumerate(lines, 1):
    c = ws3.cell(row=i, column=1, value=txt)
    if bold:
        c.font = Font(bold=True)
ws3.column_dimensions["A"].width = 110

wb.save("underwriting_bau_report.xlsx")
print("written underwriting_bau_report.xlsx")
