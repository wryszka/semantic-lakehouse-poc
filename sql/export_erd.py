#!/usr/bin/env python3
"""Export an ER diagram of a Unity Catalog schema to PNG + PDF.

Reads the DECLARED primary/foreign keys from information_schema (the same
constraints that power Catalog Explorer's "View relationships"), renders with
Graphviz. The diagram is therefore always current with the catalog — rerun to
refresh, schedule it if you want a nightly artifact.

Usage:
  DATABRICKS_PROFILE=DEV DATABRICKS_HOST=https://<ws> DATABRICKS_WAREHOUSE_ID=<id> \
    python3 export_erd.py [catalog] [schema] [out_basename]

Requires: graphviz `dot` on PATH.
"""
import json
import os
import subprocess
import sys
import urllib.request

PROFILE = os.environ.get("DATABRICKS_PROFILE", "REPLACE-ME")
HOST = os.environ.get("DATABRICKS_HOST", "https://REPLACE-ME.cloud.databricks.com")
WAREHOUSE = os.environ.get("DATABRICKS_WAREHOUSE_ID", "REPLACE-ME")

CATALOG = sys.argv[1] if len(sys.argv) > 1 else "lr_dev_aws_us_catalog"
SCHEMA = sys.argv[2] if len(sys.argv) > 2 else "semantic_lakehouse"
OUT = sys.argv[3] if len(sys.argv) > 3 else f"erd_{SCHEMA}"

tok = json.loads(subprocess.run(["databricks", "auth", "token", "-p", PROFILE],
                                capture_output=True, text=True, check=True).stdout)["access_token"]


def q(stmt):
    body = json.dumps({"warehouse_id": WAREHOUSE, "statement": stmt,
                       "wait_timeout": "50s"}).encode()
    req = urllib.request.Request(f"{HOST}/api/2.0/sql/statements/", data=body,
                                 headers={"Authorization": f"Bearer {tok}",
                                          "Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req))
    assert r["status"]["state"] == "SUCCEEDED", r["status"]
    return r["result"].get("data_array", [])


IS = f"{CATALOG}.information_schema"

columns = q(f"""
  SELECT c.table_name, c.column_name, c.full_data_type
  FROM {IS}.columns c
  JOIN {IS}.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  WHERE c.table_schema = '{SCHEMA}' AND t.table_type = 'MANAGED'
  ORDER BY c.table_name, c.ordinal_position""")

pk_cols = q(f"""
  SELECT k.table_name, k.column_name
  FROM {IS}.table_constraints tc
  JOIN {IS}.key_column_usage k ON k.constraint_name = tc.constraint_name
  WHERE tc.table_schema = '{SCHEMA}' AND tc.constraint_type = 'PRIMARY KEY'""")

fks = q(f"""
  SELECT k.table_name AS fk_table, k.column_name AS fk_column,
         pk.table_name AS pk_table
  FROM {IS}.table_constraints tc
  JOIN {IS}.key_column_usage k ON k.constraint_name = tc.constraint_name
  JOIN {IS}.referential_constraints rc ON rc.constraint_name = tc.constraint_name
  JOIN {IS}.table_constraints pk ON pk.constraint_name = rc.unique_constraint_name
  WHERE tc.table_schema = '{SCHEMA}' AND tc.constraint_type = 'FOREIGN KEY'""")

pk_set = {(t, c) for t, c in pk_cols}
fk_set = {(t, c) for t, c, _ in fks}

tables = {}
for t, c, dt in columns:
    tables.setdefault(t, []).append((c, dt))

# facts dark header, dims teal header
def header_color(name):
    return "#1B3139" if name.startswith("fct_") else "#1B5161"


lines = [
    "digraph ERD {",
    '  graph [rankdir=LR, splines=spline, nodesep=0.7, ranksep=1.1,'
    f' label="{CATALOG}.{SCHEMA} — entity relationships (from declared PK/FK constraints)",'
    ' labelloc=t, fontname="Helvetica", fontsize=16];',
    '  node [shape=plain, fontname="Helvetica", fontsize=11];',
    '  edge [color="#5B7C8A", arrowsize=0.8];',
]
for t, cols in sorted(tables.items()):
    rows = []
    for c, dt in cols:
        marker = " 🔑" if (t, c) in pk_set else (" ⧉" if (t, c) in fk_set else "")
        rows.append(f'<tr><td align="left" port="{c}">{c}{marker}'
                    f'  <font color="#8899A6" point-size="9">{dt.lower()}</font></td></tr>')
    lines.append(
        f'  {t} [label=<<table border="0" cellborder="1" cellspacing="0" cellpadding="4">'
        f'<tr><td bgcolor="{header_color(t)}"><font color="white"><b>{t}</b></font></td></tr>'
        + "".join(rows) + "</table>>];")
for fk_table, fk_column, pk_table in fks:
    lines.append(f'  {fk_table}:{fk_column} -> {pk_table} [arrowhead=crow, dir=back];')
lines.append("}")

dot = "\n".join(lines)
open(f"{OUT}.dot", "w").write(dot)
for fmt in ("png", "pdf"):
    subprocess.run(["dot", f"-T{fmt}", f"{OUT}.dot", "-o", f"{OUT}.{fmt}"], check=True)
    print(f"written {OUT}.{fmt}")
print(f"{len(tables)} tables, {len(fks)} relationships")
