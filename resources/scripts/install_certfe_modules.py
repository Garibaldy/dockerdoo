#!/usr/bin/env python3
"""
Install modules from certfe-modules-installed.txt into the current database.

Run via Odoo shell (env is provided by the shell):

  docker compose exec -T odoo odoo shell -d YOUR_DB --no-http \
    < /resources/scripts/install_certfe_modules.py

List file: /resources/certfe-modules-installed.txt (mounted in container).
"""
from __future__ import annotations

import os

LIST_PATH = os.environ.get(
    "CERTFE_MODULE_LIST",
    "/resources/certfe-modules-installed.txt",
)


def _load_names():
    with open(LIST_PATH) as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def main():
  # Odoo shell injects `env` into globals when executing stdin
    names = _load_names()
    Module = env["ir.module.module"]  # noqa: F821

    mods = Module.search([("name", "in", names)])
    found = set(mods.mapped("name"))
    missing_registry = sorted(set(names) - found)
    if missing_registry:
        print(f"WARNING: {len(missing_registry)} names not in ir.module.module:")
        for n in missing_registry[:30]:
            print(f"  - {n}")
        if len(missing_registry) > 30:
            print(f"  ... and {len(missing_registry) - 30} more")

    already = mods.filtered(lambda m: m.state == "installed")
    pending = mods.filtered(lambda m: m.state not in ("installed", "to upgrade"))

    print(f"Target list: {len(names)} | found: {len(mods)} | installed: {len(already)} | to install: {len(pending)}")

    if not pending:
        print("Nothing to install.")
        return

    # Install in chunks to reduce OOM / timeout risk
    chunk = 25
    pending_names = pending.mapped("name")
    for i in range(0, len(pending_names), chunk):
        batch_names = pending_names[i : i + chunk]
        batch = Module.search([("name", "in", batch_names)])
        batch = batch.filtered(lambda m: m.state not in ("installed", "to upgrade"))
        if not batch:
            continue
        print(f"Installing batch {i // chunk + 1}: {len(batch)} modules ...")
        try:
            batch.button_immediate_install()
            env.cr.commit()  # noqa: F821
            print(f"  OK: {', '.join(batch.mapped('name')[:8])}{'...' if len(batch) > 8 else ''}")
        except Exception as e:
            env.cr.rollback()  # noqa: F821
            print(f"  BATCH FAILED: {e}")
            for mod in batch:
                try:
                    mod.button_immediate_install()
                    env.cr.commit()  # noqa: F821
                    print(f"    OK {mod.name}")
                except Exception as e2:
                    env.cr.rollback()  # noqa: F821
                    print(f"    FAIL {mod.name}: {e2}")

    final_installed = Module.search_count(
        [("name", "in", names), ("state", "in", ("installed", "to upgrade"))]
    )
    print(f"Done. Installed/to-upgrade from list: {final_installed}/{len(names)}")


main()