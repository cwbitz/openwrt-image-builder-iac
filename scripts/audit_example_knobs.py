#!/usr/bin/env python3
"""Audit the OpenWrt-image-builder operator templates against the project's knobs.

Three committed templates are the scaffold the operators copy:

* ``inventory/host_vars/example/main.yml`` — the per-machine build
  variants (``build_variants``); each YAML key inside a variant is a knob the
  role reads as ``(variant | default({})).<key>``.
* ``inventory/group_vars/builders/main.yml.example`` — the machine-wide overrides
  (e.g. ``create_admin_account``).
* ``inventory/host_vars/example/vault.yml.example`` — the firmware-secret dicts
  the role joins by variant name.

This audit (run by ``make lint`` / CI) keeps them complete:

* **Variant schema** — every variant key referenced by ``roles/imagebuilder/**``
  must appear inside at least one ``build_variants`` entry of the example.
* **Group knobs** — every machine-wide knob the project exposes must be an ACTIVE
  entry with its default in ``group_vars/builders/main.yml.example``.
* **Declared knobs** — any other non-internal knob declared in
  ``roles/*/defaults/main.yml`` must be represented in the example.
* **Vault keys** — every example variant must have a sub-key in both firmware
  dicts, and every sub-key must name one of the example's variants (the role
  joins secrets by variant name; a typo would silently skip a module).

Standard library only (like the other scripts/), so a plain `python3` can run it.

Usage: audit_example_knobs.py [repo root]      # exit 1 with a report on failure
"""
from __future__ import annotations

import glob
import os
import re
import sys

VARIANT_EXAMPLE = "inventory/host_vars/example/main.yml"
GROUP_EXAMPLE = "inventory/group_vars/builders/main.yml.example"
VAULT_EXAMPLE = "inventory/host_vars/example/vault.yml.example"
VARIANT_ROOTS = ["roles/imagebuilder/defaults/main.yml", "roles/imagebuilder/vars/main.yml"]

TOOLING = {"helper_vault_password_file", "helper_ansible_vault_bin"}
INTERNAL = {"build_dir", "output_dir", "artifacts_dir", "package_manager_min_version"}
GROUP_KNOBS = {"create_admin_account", "sshd_hardening_enabled", "sshd_permit_root_login"}
EXTRA = {"build_variants"}
VAULT_DICTS = ("vault_openwrt_root_password", "vault_openwrt_pppoe_password")

KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
INDENTED_KEY_RE = re.compile(r"^\s+(?:-\s+)?([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
VARIANT_REF_RE = re.compile(r"build_variant\s*\|\s*default\(\{\}\)\)?\.([A-Za-z0-9_]+)")
VARIANT_NAME_RE = re.compile(r"^\s*-\s+name:\s*([^\s#]+)\s*(?:#.*)?$")


def read(path: str) -> str:
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return ""


def declared_knobs(root: str) -> dict[str, str]:
    knobs: dict[str, str] = {}
    for path in sorted(glob.glob(os.path.join(root, "roles/*/defaults/main.yml"))):
        for line in read(path).splitlines():
            if (m := KEY_RE.match(line)):
                knobs[m.group(1)] = os.path.relpath(path, root)
    return knobs


def vault_dict_keys(text: str) -> dict[str, list[str]]:
    """Return the sub-keys of each firmware-secret dict in the vault example."""
    found: dict[str, list[str]] = {}
    current = ""
    for line in text.splitlines():
        if (m := KEY_RE.match(line)):
            current = m.group(1)
            if current in VAULT_DICTS:
                found[current] = []
            continue
        if current in VAULT_DICTS and (m := INDENTED_KEY_RE.match(line)):
            found[current].append(m.group(1))
    return found


def main(argv: list[str]) -> int:
    root = argv[1] if len(argv) > 1 else os.getcwd()
    variant_example = os.path.join(root, VARIANT_EXAMPLE)
    group_example = os.path.join(root, GROUP_EXAMPLE)
    vault_example = os.path.join(root, VAULT_EXAMPLE)
    for path in (variant_example, group_example, vault_example):
        if not os.path.isfile(path):
            print(f"ERROR: {path} does not exist", file=sys.stderr)
            return 1

    problems: list[str] = []

    referenced: dict[str, str] = {}
    for rel in VARIANT_ROOTS:
        path = os.path.join(root, rel)
        for m in VARIANT_REF_RE.finditer(read(path)):
            referenced.setdefault(m.group(1), os.path.relpath(path, root))
    example = read(variant_example)
    provided: set[str] = set()
    for line in example.splitlines():
        if (m := INDENTED_KEY_RE.match(line)):
            provided.add(m.group(1))
    for key, source in sorted(referenced.items()):
        if key not in provided:
            problems.append(f"{key}: variant key referenced by {source} is missing from "
                            f"{VARIANT_EXAMPLE}'s variants")

    top_level = {m.group(1) for line in example.splitlines() if (m := KEY_RE.match(line))}
    for key in sorted(EXTRA):
        if key not in top_level:
            problems.append(f"{key}: required top-level knob missing from {VARIANT_EXAMPLE}")

    group = read(group_example)
    group_active = {m.group(1) for line in group.splitlines() if (m := KEY_RE.match(line))}
    for key in sorted(GROUP_KNOBS):
        if key not in group_active:
            problems.append(f"{key}: machine-wide knob missing (or commented) in "
                            f"{GROUP_EXAMPLE} — list it as an active entry")

    for key, source in sorted(declared_knobs(root).items()):
        if (key in TOOLING or key in INTERNAL or key in GROUP_KNOBS
                or key in referenced or key == "vault_file" or key.startswith("openwrt_")):
            continue
        if key not in top_level and key not in provided:
            problems.append(f"{key}: missing from {VARIANT_EXAMPLE} (default in {source})")

    variant_names = [m.group(1) for line in example.splitlines()
                     if (m := VARIANT_NAME_RE.match(line))]
    vault = vault_dict_keys(read(vault_example))
    for dict_name in VAULT_DICTS:
        keys = vault.get(dict_name)
        if keys is None:
            problems.append(f"{dict_name}: firmware-secret dict missing from {VAULT_EXAMPLE}")
            continue
        for name in variant_names:
            if name not in keys:
                problems.append(f"{dict_name}.{name}: variant has no secret in {VAULT_EXAMPLE} "
                                f"(the role joins by variant name)")
        for key in keys:
            if key not in variant_names:
                problems.append(f"{dict_name}.{key}: not a variant name in {VARIANT_EXAMPLE} "
                                f"(the role joins by variant name)")

    if problems:
        print(f"audit_example_knobs: {len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(f"audit_example_knobs: OK ({len(referenced)} variant keys, "
          f"{len(GROUP_KNOBS)} group knobs, {len(VAULT_DICTS)} vault dicts checked)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
