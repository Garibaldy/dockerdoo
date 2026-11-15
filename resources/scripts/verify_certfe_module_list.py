#!/usr/bin/env python3
"""Compare certfe-modules-installed.txt with modules discoverable under custom/."""
from __future__ import annotations

import argparse
import importlib.util
import os
import sys


def load_getaddons(repo_root: str):
    path = os.path.join(repo_root, "resources", "getaddons4.py")
    spec = importlib.util.spec_from_file_location("getaddons4", path)
    if not spec or not spec.loader:
        raise RuntimeError(f"Cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        default=os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")),
    )
    parser.add_argument(
        "--addons-root",
        default=None,
        help="Path mounted as ODOO_EXTRA_ADDONS (default: <repo>/custom)",
    )
    parser.add_argument(
        "--list-file",
        default=None,
        help="Modules that must exist under custom/ (default: certfe-modules-custom-path.txt)",
    )
    args = parser.parse_args()

    repo_root = os.path.abspath(args.repo_root)
    addons_root = args.addons_root or os.path.join(repo_root, "custom")
    list_file = args.list_file or os.path.join(
        repo_root, "resources", "certfe-modules-custom-path.txt"
    )

    if not os.path.isdir(addons_root):
        print(f"ERROR: addons root not found: {addons_root}", file=sys.stderr)
        return 2
    if not os.path.isfile(list_file):
        print(f"ERROR: list file not found: {list_file}", file=sys.stderr)
        return 2

    with open(list_file) as f:
        desired = {line.strip() for line in f if line.strip() and not line.startswith("#")}

    getaddons = load_getaddons(repo_root)
    discovered = set(getaddons.get_modules(addons_root, depth=4))

    missing_on_disk = sorted(desired - discovered)
    extra_on_disk_not_in_list = sorted(discovered - desired)

    full_list = os.path.join(repo_root, "resources", "certfe-modules-installed.txt")
    full_count = 0
    if os.path.isfile(full_list):
        with open(full_list) as f:
            full_count = sum(1 for line in f if line.strip())

    print(f"Must exist under custom/ (from {os.path.basename(list_file)}): {len(desired)}")
    if full_count:
        print(f"Full golden install list (incl. core/EE in image): {full_count}")
    print(f"Discoverable under {addons_root}: {len(discovered)}")
    print(f"Missing on disk: {len(missing_on_disk)}")
    if missing_on_disk:
        for name in missing_on_disk[:50]:
            print(f"  - {name}")
        if len(missing_on_disk) > 50:
            print(f"  ... and {len(missing_on_disk) - 50} more")

    if missing_on_disk:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())