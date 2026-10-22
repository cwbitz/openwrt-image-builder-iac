#!/usr/bin/env python3
"""Reject real infrastructure identifiers and credentials in tracked files.

``make lint`` and CI run this so a live host name, a routable address or a real
mailbox never reaches a commit: committed files carry placeholders only.

The checks run over ``git ls-files``, i.e. tracked content:

* **Protected trees** — host variables and backups are local-only; only the
  ``example/`` template of a host-vars tree may be tracked.
* **Credential files** — private keys, state files and a real ``vault.yml`` are
  never tracked (the ``.example`` template is).
* **Addresses** — an IPv4 literal must be unspecified, loopback, private or
  documentation-reserved, or listed in ``.privacy-allowlist``. Public and
  carrier-grade NAT (overlay) addresses are rejected. CIDR notations are treated
  as network specifications, not host addresses.
* **Mailboxes** — only the documentation domains are accepted.
* **Host names** — a name taken from the local (untracked) inventory must not
  appear in a tracked file.

Defaults: 0.0.0.0/32, 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 and
the RFC 5737 blocks. Add project-specific constants (fixed interfaces, container
subnets) to ``.privacy-allowlist``, one address or CIDR per line.

Standard library only, so a plain ``python3`` can run it.

Usage: check_repo_privacy.py [repo root]    # exit 1 with a report on failure
"""
from __future__ import annotations

import ipaddress
import pathlib
import re
import subprocess
import sys

DEFAULT_ALLOWED = (
    "0.0.0.0/32",
    "127.0.0.0/8",
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "192.0.2.0/24",
    "198.51.100.0/24",
    "203.0.113.0/24",
)
DOC_EMAIL_DOMAINS = {"example.com", "example.org", "example.net"}

SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".gz", ".tgz", ".zip",
    ".woff", ".woff2", ".ttf", ".pyc", ".so",
}
TRACKED_CREDENTIALS = (
    re.compile(r"(^|/)vault\.ya?ml$"),
    re.compile(r"(^|/)id_(rsa|dsa|ecdsa|ed25519)$"),
    re.compile(r"\.(pem|key|p12|pfx)$"),
    re.compile(r"\.tfstate(\..+)?$"),
    re.compile(r"\.tfvars$"),
)
LOCAL_ONLY_TREES = (
    re.compile(r"(^|/)host_vars/(?!example/)"),
    re.compile(r"^backup/"),
    re.compile(r"^\.cache/"),
    re.compile(r"^collections/"),
)
IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
CIDR = re.compile(r"^/\d{1,2}\b")
VERSION_SUFFIX = re.compile(r"^\.\d")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)")


def git(root: pathlib.Path, *args: str) -> str:
    return subprocess.run(
        ("git", "-C", str(root), *args),
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def tracked_files(root: pathlib.Path) -> list[str]:
    return [name for name in git(root, "ls-files").splitlines() if name]


def allowed_networks(root: pathlib.Path) -> list[ipaddress.IPv4Network]:
    networks = [ipaddress.ip_network(item) for item in DEFAULT_ALLOWED]
    extra = root / ".privacy-allowlist"
    if extra.is_file():
        for line in extra.read_text(encoding="utf-8").splitlines():
            entry = line.split("#", 1)[0].strip()
            if entry:
                networks.append(ipaddress.ip_network(entry))
    return networks


def inventory_hosts(root: pathlib.Path) -> set[str]:
    """Host names of the local (untracked) inventory, empty when there is none."""
    sources = [
        path
        for path in root.glob("**/hosts.y*ml")
        if path.parent.name == "inventory" and len(path.relative_to(root).parts) <= 3
    ]
    hosts: set[str] = set()
    for source in sources:
        result = subprocess.run(
            ("ansible-inventory", "-i", str(source), "--graph"),
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            continue
        for line in result.stdout.splitlines():
            if "|--" not in line:
                continue
            entry = line.rsplit("|--", 1)[1].strip()
            if entry and not entry.startswith("@"):
                hosts.add(entry)
    return hosts


def text_body(path: pathlib.Path) -> str | None:
    data = path.read_bytes()
    if b"\x00" in data[:8192]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def is_structural(address: ipaddress.IPv4Address) -> bool:
    """True for an address that is a network mask or a reserved broadcast form."""
    value = int(address)
    if value in (0, 0xFFFFFFFF):
        return True
    inverted = value ^ 0xFFFFFFFF
    return inverted & (inverted + 1) == 0


def scan(
    root: pathlib.Path, files: list[str], networks: list[ipaddress.IPv4Network], names: set[str]
) -> list[str]:
    problems: list[str] = []
    for name in files:
        for pattern in LOCAL_ONLY_TREES:
            if pattern.search(name):
                problems.append(f"{name}: local-only tree is tracked")
                break
        for pattern in TRACKED_CREDENTIALS:
            if pattern.search(name) and not name.endswith(".example"):
                problems.append(f"{name}: credential file is tracked")
                break
        if pathlib.PurePath(name).suffix in SKIP_SUFFIXES:
            continue
        path = root / name
        if not path.is_file():
            continue
        body = text_body(path)
        if body is None:
            continue
        for number, line in enumerate(body.splitlines(), start=1):
            for match in IPV4.finditer(line):
                if CIDR.match(line[match.end():]) or VERSION_SUFFIX.match(line[match.end():]):
                    continue
                if any(len(octet) > 1 and octet.startswith("0") for octet in match.group().split(".")):
                    continue
                address = ipaddress.ip_address(match.group())
                if is_structural(address) or any(address in network for network in networks):
                    continue
                problems.append(f"{name}:{number}: non-placeholder address {address}")
            for match in EMAIL.finditer(line):
                if match.group(1).lower() not in DOC_EMAIL_DOMAINS:
                    problems.append(f"{name}:{number}: real mailbox {match.group(0)}")
            for host in names:
                if re.search(rf"(?<![\w.-]){re.escape(host)}(?![\w-])", line):
                    problems.append(f"{name}:{number}: inventory host name {host}")
    return problems


def main(argv: list[str]) -> int:
    root = pathlib.Path(argv[1] if len(argv) > 1 else ".").resolve()
    try:
        files = tracked_files(root)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"check_repo_privacy: not a git work tree: {error}", file=sys.stderr)
        return 2
    problems = scan(root, files, allowed_networks(root), inventory_hosts(root))
    if problems:
        print(f"check_repo_privacy: {len(problems)} problem(s) in {root}:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(f"check_repo_privacy: OK ({len(files)} tracked files checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
