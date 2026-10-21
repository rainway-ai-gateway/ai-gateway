#!/usr/bin/env python3
"""
Generate the derived MySQL DDL copies from the upstream master.

Master (single source of truth):
    ../ai-gateway-api/db_ddl.sql

Derived outputs:
    conf/db/api_db_ddl_mysql.sql                     (compose / standalone)
    kubernetes/deploy/mysql-deploy.yaml              (embedded in ConfigMap)

Only the seed section differs between the two outputs (epp_instances host).
Everything else -- every CREATE TABLE and every seed row -- is copied verbatim
from the master, so a truncated or hand-edited derived copy cannot happen.

Usage:
    python3 scripts/gen-db-ddl.py --check     # verify derived copies are in sync
    python3 scripts/gen-db-ddl.py --write     # regenerate derived copies
"""

import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = os.path.join(REPO, "..", "ai-gateway-api", "db_ddl.sql")
CONF_DDL = os.path.join(REPO, "conf", "db", "api_db_ddl_mysql.sql")
K8S_YAML = os.path.join(REPO, "kubernetes", "deploy", "mysql-deploy.yaml")

# The seed block that replaces the master's "-- insert default user" section.
# Kept byte-identical except for the epp_instances rows.
SEED_HEAD = """-- ---------------------------------------------------------------------------
-- Seed data
-- ---------------------------------------------------------------------------
-- Built-in administrator. scopes=System, password is the upstream bcrypt hash
-- ($2a$10$w2oNyh4MO7SB...). Change it after the first login.
insert into users (id, name, password, scopes, created_at) values(1, 'admin', '$2a$10$w2oNyh4MO7SB.NHLPSq6kOj1GMiX1fApPYcWJmL8toZXGCQs3AJ0K', 'System', now());

-- Built-in products. id 2 is the one the demo account is bound to below;
-- without it the Product scope resolves to no product and every scoped
-- OpenAPI call answers 402 "Feature Access Deny".
insert into products (id, name, `description`, mail_list, contact_person, created_at) values
    (1, 'BFE', 'Build-in Product, User by System Manager', 'bfe@cncf.com', 'bfe', now()),
    (2, 'AI_product', 'ai 产品线', '', '', now());

-- Service accounts used by the standalone/compose stack (conf-agent, demo UI).
insert into users (id, name, type, password, ticket, ticket_created_at, scopes, created_at) values (2, 'demo', 1, '', 'eT5QWkLhQmp6lO4NWxAc', now(), 'Product', now());
insert into users (id, name, type, password, ticket, ticket_created_at, scopes, created_at) values (3, 'conf-agent', 1, '', 'c5QFb-MrlKktJbOid2M3', now(), 'System', now());
insert into user_products (user_id, product_id, created_at, updated_at) values (2, 2, now(), now());

-- Pre-seed EPP instances (group == instance in the v0.0.11 single-instance-group model).
"""

EPP_COMPOSE = (
    "INSERT INTO `epp_instances` (`id`, `host`, `port`, `group_name`) "
    "VALUES ('epp-0', '127.0.0.1', 9002, 'epp-0');\n"
)

EPP_K8S = (
    "INSERT INTO `epp_instances` (`id`, `host`, `port`, `group_name`) "
    "VALUES ('epp-0', 'epp-0.ai-gateway-epp.ai-gateway-system.svc.cluster.local', 9002, 'epp-0');\n"
    "INSERT INTO `epp_instances` (`id`, `host`, `port`, `group_name`) "
    "VALUES ('epp-1', 'epp-1.ai-gateway-epp.ai-gateway-system.svc.cluster.local', 9002, 'epp-1');\n"
)

# The master section that gets replaced: from the "-- insert default user"
# comment up to (not including) the pools seed block.
SEED_START_MARK = "-- insert default user"
SEED_END_MARK = "-- pools 表初始化数据"


def build(epp_rows: str) -> str:
    with open(MASTER, encoding="utf-8") as f:
        master = f.read()

    start = master.index(SEED_START_MARK)
    end = master.index(SEED_END_MARK)
    return master[:start] + SEED_HEAD + epp_rows + "\n" + master[end:]


def count_tables(sql: str) -> int:
    return len(re.findall(r"^CREATE TABLE", sql, re.MULTILINE))


def embed(sql: str) -> str:
    """Indent SQL for a YAML literal block scalar under `key: |` (6 spaces)."""
    body = sql.rstrip("\n")
    return "\n".join(("      " + ln) if ln.strip() else "" for ln in body.split("\n"))


def unwrap(yaml_text: str, key: str) -> str:
    """Extract the literal block scalar for `key` and remove the 6-space indent."""
    m = re.search(r"^  " + re.escape(key) + r": \|\n(.*?)(?=^  \S|\Z)", yaml_text, re.MULTILINE | re.DOTALL)
    if not m:
        raise SystemExit("cannot find key %s in %s" % (key, K8S_YAML))
    lines = []
    for ln in m.group(1).split("\n"):
        if ln.startswith("      "):
            lines.append(ln[6:])
        elif ln.strip() == "":
            lines.append("")
        else:
            # stray line that is not part of the block
            break
    return "\n".join(lines).strip("\n") + "\n"


def expected_epp(sql: str) -> int:
    return 2 if "epp-1.ai-gateway-epp" in sql else 1


# ---------------------------------------------------------------------------
# The derived copy is NOT identical to the master. The gateway repo adds a few
# seed rows for local/cluster bring-up, inherited from v0.1.0 and still present
# in v0.7.0's api_db_ddl.sql. That delta is intentional and must stay exactly
# these four rows: anything else is either a lost seed or an accidental trim.
EXTRA_SEEDS = ["'demo'", "'conf-agent'", "user_products", "epp_instances"]

INSERT_RE = re.compile(r"^insert\s+(?:ignore\s+)?into\s+.*?;", re.IGNORECASE | re.MULTILINE | re.DOTALL)


def norm(sql: str) -> str:
    return re.sub(r"\s+", " ", sql).strip().lower()


def extract_inserts(sql: str) -> list:
    return INSERT_RE.findall(sql)


def validate(gen: str, master: str) -> list:
    """Fail on any drift from the master other than the documented seed delta."""
    problems = []

    if count_tables(gen) != count_tables(master):
        problems.append("table count %d != master %d" % (count_tables(gen), count_tables(master)))
    for t in ["keyrotate_sweep_tasks", "keyrotate_sweep_lock", "batch_files", "batch_tasks"]:
        if "CREATE TABLE `%s`" % t not in gen:
            problems.append("missing table: %s" % t)

    master_ins = extract_inserts(master)
    master_norm = set(norm(x) for x in master_ins)
    gen_ins = extract_inserts(gen)
    gen_norm = set(norm(x) for x in gen_ins)

    # Every master seed must survive verbatim, except the two products rows,
    # which this repo rewrites into one insert with explicit ids 1 and 2.
    for raw in master_ins:
        n = norm(raw)
        if n in gen_norm:
            continue
        if n.startswith("insert into products"):
            continue
        problems.append("master seed lost: %s" % n[:100])

    # Collect what the generated copy adds, minus the products rewrite.
    extras = []
    for raw in gen_ins:
        n = norm(raw)
        if n in master_norm:
            continue
        if n.startswith("insert into products"):
            if "(1," not in n or "(2," not in n or "'ai_product'" not in n:
                problems.append("products rewrite is not the expected merged (1,2) form")
            continue
        extras.append(n)

    if len(extras) != len(EXTRA_SEEDS):
        problems.append("expected %d extra seed rows, found %d: %s"
                        % (len(EXTRA_SEEDS), len(extras), [e[:60] for e in extras]))
    for key in EXTRA_SEEDS:
        if not any(key in e for e in extras):
            problems.append("documented extra seed missing: %s" % key)

    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not (args.write or args.check):
        ap.error("pass --write or --check")

    compose_sql = build(EPP_COMPOSE)
    k8s_sql = build(EPP_K8S)

    # sanity of freshly generated content
    master_sql = open(MASTER, encoding="utf-8").read()
    n_tables = count_tables(compose_sql)
    problems = validate(compose_sql, master_sql)
    if problems:
        print("GENERATED CONTENT INVALID:")
        for p in problems:
            print("  -", p)
        return 1

    yaml_text = open(K8S_YAML, encoding="utf-8").read()

    if args.write:
        with open(CONF_DDL, "w", encoding="utf-8") as f:
            f.write(compose_sql)
        print("wrote", os.path.relpath(CONF_DDL, REPO), "(%d tables, %d lines)" % (n_tables, compose_sql.count("\n")))
        # replace only the api DDL block inside the configmap
        old_block = unwrap(yaml_text, "api_db_ddl_mysql.sql")
        header = "  api_db_ddl_mysql.sql: |\n"
        new_block = header + embed(k8s_sql) + "\n"
        pattern = re.escape(header) + r".*?(?=^  report_db_ddl_mysql\.sql: \|)"
        new_yaml, cnt = re.subn(pattern, new_block, yaml_text, count=1, flags=re.MULTILINE | re.DOTALL)
        if cnt != 1:
            print("FAILED to replace api DDL block in %s" % K8S_YAML)
            return 1
        with open(K8S_YAML, "w", encoding="utf-8") as f:
            f.write(new_yaml)
        print("wrote %s (api_db_ddl_mysql.sql block, %d tables)" % (os.path.relpath(K8S_YAML, REPO), count_tables(k8s_sql)))
        return 0

    # --check
    disk_compose = open(CONF_DDL, encoding="utf-8").read()
    disk_k8s = unwrap(yaml_text, "api_db_ddl_mysql.sql")
    ok = True
    if disk_compose.strip() != compose_sql.strip():
        ok = False
        print("DIFF: conf/db/api_db_ddl_mysql.sql is out of sync with master")
        d = difflib_lines(compose_sql, disk_compose)
        print(d)
    if disk_k8s.strip() != k8s_sql.strip():
        ok = False
        print("DIFF: configmap api_db_ddl_mysql.sql is out of sync with master")
        print(difflib_lines(k8s_sql, disk_k8s))
    if ok:
        print("OK: both derived DDL copies match master (%d tables)" % n_tables)
        return 0
    return 1


def difflib_lines(a: str, b: str) -> str:
    import difflib
    d = list(difflib.unified_diff(a.splitlines(), b.splitlines(), "expected", "on-disk", lineterm="", n=2))
    return "\n".join(d[:60])


if __name__ == "__main__":
    sys.exit(main())
