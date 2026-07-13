#!/usr/bin/env python3
"""Create + publish the Underwriting Performance Lakeview dashboard (DEV)."""
import json
import os
import subprocess

MV = "lr_dev_aws_us_catalog.semantic_lakehouse.mv_underwriting"
WV = "lr_dev_aws_us_catalog.semantic_lakehouse.vw_underwriting_monthly"
WAREHOUSE = os.environ.get("DATABRICKS_WAREHOUSE_ID", "REPLACE-ME")
PROFILE = os.environ.get("DATABRICKS_PROFILE", "REPLACE-ME")
PARENT = "/Workspace/Shared/semantic-lakehouse-poc"

datasets = [
    {"name": "ds_monthly", "displayName": "Underwriting monthly (metric view)",
     "queryLines": [f"SELECT `Month` AS month, `Sector` AS sector, MEASURE(`Gross Written Premium`) AS gwp, MEASURE(`Claims Incurred`) AS claims_incurred, MEASURE(`Policy Count`) AS policies FROM {MV} GROUP BY ALL"]},
    {"name": "ds_kpi", "displayName": "Current year KPIs (metric view)",
     "queryLines": [f"SELECT MEASURE(`Gross Written Premium`) AS gwp_ytd, MEASURE(`Loss Ratio`) AS loss_ratio, MEASURE(`Policy Count`) AS policies FROM {MV} WHERE `Year` = year(current_date())"]},
    {"name": "ds_sector_cy", "displayName": "Current year by sector (metric view)",
     "queryLines": [f"SELECT `Sector` AS sector, MEASURE(`Gross Written Premium`) AS gwp, MEASURE(`Loss Ratio`) AS loss_ratio FROM {MV} WHERE `Year` = year(current_date()) GROUP BY ALL"]},
    {"name": "ds_r12", "displayName": "Rolling 12m (wrapper view)",
     "queryLines": [f"SELECT month, sector, gwp_rolling_12m, loss_ratio_rolling_12m FROM {WV} WHERE month >= '2020-01-01'"]},
    {"name": "ds_region", "displayName": "Region x channel (metric view)",
     "queryLines": [f"SELECT `Region` AS region, `Channel Type` AS channel_type, MEASURE(`Gross Written Premium`) AS gwp, round(MEASURE(`Loss Ratio`), 3) AS loss_ratio FROM {MV} WHERE `Year` = year(current_date()) GROUP BY ALL"]},
]


def text(name, md, x, y, w=6, h=1):
    return {"widget": {"name": name, "multilineTextboxSpec": {"lines": [md]}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def counter(name, title, field, x, y):
    return {"widget": {
        "name": name,
        "queries": [{"name": "main_query", "query": {
            "datasetName": "ds_kpi",
            "fields": [{"name": field, "expression": f"`{field}`"}],
            "disaggregated": True}}],
        "spec": {"version": 2, "widgetType": "counter",
                 "encodings": {"value": {"fieldName": field, "displayName": title}},
                 "frame": {"showTitle": True, "title": title}}},
        "position": {"x": x, "y": y, "width": 2, "height": 3}}


layout = [
    text("title", "## Underwriting Performance — Bricksurance SE", 0, 0),
    text("subtitle", "Every number on this page reads the **same governed metric view** (`mv_underwriting`) that also serves Genie, Excel and Power BI. Metrics are defined once, nowhere else.", 0, 1),
    counter("kpi-gwp", "GWP YTD", "gwp_ytd", 0, 2),
    counter("kpi-lr", "Loss Ratio YTD", "loss_ratio", 2, 2),
    counter("kpi-pol", "Policies YTD", "policies", 4, 2),
    # management report: premiums by sector (current year)
    {"widget": {
        "name": "bar-premiums-sector",
        "queries": [{"name": "main_query", "query": {
            "datasetName": "ds_sector_cy",
            "fields": [{"name": "sector", "expression": "`sector`"},
                       {"name": "sum(gwp)", "expression": "SUM(`gwp`)"}],
            "disaggregated": False}}],
        "spec": {"version": 3, "widgetType": "bar",
                 "encodings": {
                     "x": {"fieldName": "sector", "scale": {"type": "categorical", "sort": {"by": "y-reversed"}}, "displayName": "Sector"},
                     "y": {"fieldName": "sum(gwp)", "scale": {"type": "quantitative"}, "displayName": "Gross Written Premium"},
                     "label": {"show": True}},
                 "frame": {"showTitle": True, "title": "Premiums by Sector — current year (the management report)"}}},
     "position": {"x": 0, "y": 5, "width": 3, "height": 6}},
    # monthly GWP trend by sector
    {"widget": {
        "name": "line-gwp-monthly",
        "queries": [{"name": "main_query", "query": {
            "datasetName": "ds_monthly",
            "fields": [{"name": "monthly(month)", "expression": "DATE_TRUNC(\"MONTH\", `month`)"},
                       {"name": "sector", "expression": "`sector`"},
                       {"name": "sum(gwp)", "expression": "SUM(`gwp`)"}],
            "disaggregated": False}}],
        "spec": {"version": 3, "widgetType": "line",
                 "encodings": {
                     "x": {"fieldName": "monthly(month)", "scale": {"type": "temporal"}, "displayName": "Month"},
                     "y": {"fieldName": "sum(gwp)", "scale": {"type": "quantitative"}, "displayName": "GWP"},
                     "color": {"fieldName": "sector", "scale": {"type": "categorical"}, "displayName": "Sector"}},
                 "frame": {"showTitle": True, "title": "Monthly GWP by Sector — full history"}}},
     "position": {"x": 3, "y": 5, "width": 3, "height": 6}},
    # rolling 12m loss ratio (time intelligence from the wrapper tier)
    {"widget": {
        "name": "line-lr-r12",
        "queries": [{"name": "main_query", "query": {
            "datasetName": "ds_r12",
            "fields": [{"name": "monthly(month)", "expression": "DATE_TRUNC(\"MONTH\", `month`)"},
                       {"name": "sector", "expression": "`sector`"},
                       {"name": "avg(loss_ratio_rolling_12m)", "expression": "AVG(`loss_ratio_rolling_12m`)"}],
            "disaggregated": False}}],
        "spec": {"version": 3, "widgetType": "line",
                 "encodings": {
                     "x": {"fieldName": "monthly(month)", "scale": {"type": "temporal"}, "displayName": "Month"},
                     "y": {"fieldName": "avg(loss_ratio_rolling_12m)", "scale": {"type": "quantitative"}, "displayName": "Loss ratio (rolling 12m)"},
                     "color": {"fieldName": "sector", "scale": {"type": "categorical"}, "displayName": "Sector"}},
                 "frame": {"showTitle": True, "title": "Rolling 12m Loss Ratio by Sector — time intelligence defined once"}}},
     "position": {"x": 0, "y": 11, "width": 3, "height": 6}},
    # region x channel table
    {"widget": {
        "name": "table-region",
        "queries": [{"name": "main_query", "query": {
            "datasetName": "ds_region",
            "fields": [{"name": "region", "expression": "`region`"},
                       {"name": "channel_type", "expression": "`channel_type`"},
                       {"name": "gwp", "expression": "`gwp`"},
                       {"name": "loss_ratio", "expression": "`loss_ratio`"}],
            "disaggregated": True}}],
        "spec": {"version": 2, "widgetType": "table",
                 "encodings": {"columns": [
                     {"fieldName": "region", "displayName": "Region"},
                     {"fieldName": "channel_type", "displayName": "Channel"},
                     {"fieldName": "gwp", "displayName": "GWP (current year)"},
                     {"fieldName": "loss_ratio", "displayName": "Loss Ratio"}]},
                 "frame": {"showTitle": True, "title": "Region x Channel — current year"}}},
     "position": {"x": 3, "y": 11, "width": 3, "height": 6}},
]

dash = {
    "datasets": datasets,
    "pages": [{"name": "overview", "displayName": "Underwriting", "pageType": "PAGE_TYPE_CANVAS", "layout": layout}],
    "uiSettings": {"theme": {"widgetHeaderAlignment": "ALIGNMENT_UNSPECIFIED"}, "applyModeEnabled": False},
}

payload = {
    "display_name": "Underwriting Performance (Semantic Lakehouse POC)",
    "warehouse_id": WAREHOUSE,
    "parent_path": PARENT,
    "serialized_dashboard": json.dumps(dash),
}

subprocess.run(["databricks", "workspace", "mkdirs", PARENT, "-p", PROFILE], check=True)
out = subprocess.run(["databricks", "api", "post", "/api/2.0/lakeview/dashboards", "-p", PROFILE,
                      "--json", json.dumps(payload)], capture_output=True, text=True)
if out.returncode:
    print("CREATE FAILED:", out.stderr[:2000])
    raise SystemExit(1)
resp = json.loads(out.stdout)
did = resp["dashboard_id"]
print("dashboard_id:", did)
pub = subprocess.run(["databricks", "api", "post", f"/api/2.0/lakeview/dashboards/{did}/published",
                      "-p", PROFILE, "--json", json.dumps({"warehouse_id": WAREHOUSE, "embed_credentials": True})],
                     capture_output=True, text=True)
print("publish:", "OK" if pub.returncode == 0 else pub.stderr[:1000])
host = os.environ.get("DATABRICKS_HOST", "https://REPLACE-ME.cloud.databricks.com")
print(f"URL: {host}/dashboardsv3/{did}/published")
