#!/usr/bin/env python3
"""Execute a .sql file statement-by-statement against a Databricks SQL warehouse.

Usage: python3 run_sql.py <file.sql> [<file2.sql> ...]
Relies on `databricks auth token -p DEV` for auth.
Splits on ';' at line ends outside $$...$$ blocks.
"""
import json
import re
import subprocess
import sys
import time
import urllib.request

PROFILE = "DEV"
HOST = "https://fevm-lr-dev-aws-us.cloud.databricks.com"
WAREHOUSE = "a3b61648ea4809e3"


def token():
    out = subprocess.run(["databricks", "auth", "token", "-p", PROFILE],
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)["access_token"]


def split_statements(sql: str):
    stmts, buf, in_dollar = [], [], False
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--") and not in_dollar:
            continue
        if "$$" in line:
            in_dollar = not in_dollar if line.count("$$") % 2 else in_dollar
        buf.append(line)
        code = re.sub(r"--.*$", "", stripped).strip() if not in_dollar else stripped
        if not in_dollar and code.endswith(";"):
            stmt = "\n".join(buf).strip().rstrip(";").strip()
            if stmt:
                stmts.append(stmt)
            buf = []
    tail = "\n".join(buf).strip().rstrip(";").strip()
    if tail:
        stmts.append(tail)
    return stmts


def execute(tok: str, stmt: str):
    body = json.dumps({
        "warehouse_id": WAREHOUSE,
        "statement": stmt,
        "catalog": "lr_dev_aws_us_catalog",
        "schema": "semantic_lakehouse",
        "wait_timeout": "50s",
        "on_wait_timeout": "CONTINUE",
    }).encode()
    req = urllib.request.Request(
        f"{HOST}/api/2.0/sql/statements/", data=body,
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    resp = json.load(urllib.request.urlopen(req))
    sid = resp["statement_id"]
    while resp["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(3)
        req = urllib.request.Request(
            f"{HOST}/api/2.0/sql/statements/{sid}",
            headers={"Authorization": f"Bearer {tok}"})
        resp = json.load(urllib.request.urlopen(req))
    return resp


def main():
    tok = token()
    failures = 0
    for path in sys.argv[1:]:
        print(f"\n=== {path} ===")
        sql = open(path).read()
        for i, stmt in enumerate(split_statements(sql), 1):
            head = re.sub(r"\s+", " ", stmt)[:90]
            resp = execute(tok, stmt)
            state = resp["status"]["state"]
            if state == "SUCCEEDED":
                print(f"  [{i:02d}] OK    {head}")
            else:
                failures += 1
                err = resp["status"].get("error", {}).get("message", "?")
                print(f"  [{i:02d}] {state} {head}\n        ERROR: {err[:500]}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
