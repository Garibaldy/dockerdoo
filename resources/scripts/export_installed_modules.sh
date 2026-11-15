#!/usr/bin/env bash
# Regenerate certfe-modules-installed.{txt,json} from a running Postgres (Odoo DB).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_TXT="${ROOT}/resources/certfe-modules-installed.txt"
OUT_JSON="${ROOT}/resources/certfe-modules-installed.json"

COMPOSE_PROJECT="${COMPOSE_PROJECT:-doo16-hardened}"
PGUSER="${PGUSER:-odoo_16}"
DBNAME="${DBNAME:-doo16}"

cd "${ROOT}"

docker compose -p "${COMPOSE_PROJECT}" exec -T db psql -U "${PGUSER}" -d "${DBNAME}" -t -A \
  -c "SELECT name FROM ir_module_module WHERE state='installed' ORDER BY name;" \
  > "${OUT_TXT}"

python3 - "${ROOT}" "${OUT_TXT}" "${OUT_JSON}" "${DBNAME}" <<'PY'
import importlib.util
import json
import os
import sys
from datetime import datetime, timezone

repo_root, txt_path, json_path, dbname = sys.argv[1:5]
with open(txt_path) as f:
    modules = [line.strip() for line in f if line.strip()]

spec = importlib.util.spec_from_file_location(
    "getaddons4", os.path.join(repo_root, "resources", "getaddons4.py")
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
custom = os.path.join(repo_root, "custom")
discovered = set(mod.get_modules(custom, depth=4)) if os.path.isdir(custom) else set()
on_custom = sorted(set(modules) & discovered)
custom_path = os.path.join(repo_root, "resources", "certfe-modules-custom-path.txt")
with open(custom_path, "w") as f:
    f.write("\n".join(on_custom) + ("\n" if on_custom else ""))

payload = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_db": dbname,
    "count": len(modules),
    "count_custom_path": len(on_custom),
    "modules": modules,
    "modules_custom_path": on_custom,
}
with open(json_path, "w") as f:
    json.dump(payload, f, indent=2)
print(
    f"Wrote {len(modules)} installed + {len(on_custom)} custom-path to "
    f"{txt_path}, {custom_path}, {json_path}"
)
PY