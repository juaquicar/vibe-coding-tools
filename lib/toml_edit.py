#!/usr/bin/env python3
"""Minimal TOML read/modify/write helper.

Why this exists
---------------
Codex keeps its configuration in TOML, and `jq` cannot write TOML. Rather than
pull in `taplo` or `tomli-w` as a runtime dependency, we use Python: `tomllib`
is stdlib from 3.11 for reading, and the writer below only has to emit the
narrow subset an agent config needs (tables, scalars, arrays of scalars).

It lives in one file instead of three inline heredocs because every caller
needs the same two invariants:

  * keys that are not bare-key safe MUST be quoted. Codex plugin tables are
    named after plugin specs such as `claude-mem@claude-mem-local`, and an
    unquoted `[plugins.claude-mem@claude-mem-local]` is not valid TOML — it
    corrupts the config of anyone who has that plugin installed.
  * a parent table's scalars must be emitted before its sub-tables, or the
    scalars end up inside the wrong table.

Usage:
    toml_edit.py set    <file>                 # JSON patch on stdin, deep-merged
    toml_edit.py delete <file> <key> [key...]  # remove one nested key

Both commands rewrite the file in place and create it when missing. Comments
and key order in the original file are NOT preserved; this is a config writer,
not a formatter.
"""

from __future__ import annotations

import json
import os
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - guarded by bootstrap.sh
    sys.exit("python3.11+ with tomllib is required to edit TOML configuration")

BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


def load(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, "rb") as fh:
        return tomllib.load(fh)


def emit(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return json.dumps(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ", ".join(emit(v) for v in value) + "]"
    raise TypeError(f"unsupported TOML value: {value!r}")


def key(name: str) -> str:
    return name if BARE_KEY.match(name) else json.dumps(name)


def render(prefix: str, table: dict, lines: list[str]) -> None:
    scalars = {k: v for k, v in table.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in table.items() if isinstance(v, dict)}
    # A header is needed for its own keys, or to declare a table that has none
    # at all. A pure container such as `[profiles]` is implied by the
    # `[profiles.fast]` that follows it, so printing it only adds noise.
    if prefix and (scalars or not tables):
        lines.append(f"[{prefix}]")
        for name, val in scalars.items():
            lines.append(f"{key(name)} = {emit(val)}")
        lines.append("")
    elif not prefix:
        for name, val in scalars.items():
            lines.append(f"{key(name)} = {emit(val)}")
        if scalars:
            lines.append("")
    for name, val in tables.items():
        child = f"{prefix}.{key(name)}" if prefix else key(name)
        render(child, val, lines)


def write(path: str, data: dict) -> None:
    lines: list[str] = []
    render("", data, lines)
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")


def merge(base: dict, patch: dict) -> dict:
    """Deep-merge `patch` into `base`. Tables recurse; everything else wins."""
    for k, v in patch.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v
    return base


def delete(data: dict, path: list[str]) -> None:
    node = data
    for step in path[:-1]:
        nxt = node.get(step)
        if not isinstance(nxt, dict):
            return
        node = nxt
    node.pop(path[-1], None)
    # Prune tables left empty, so removing the last MCP server does not leave
    # a bare `[mcp_servers]` header behind.
    for depth in range(len(path) - 1, 0, -1):
        parent = data
        for step in path[:depth - 1]:
            parent = parent[step]
        name = path[depth - 1]
        if isinstance(parent.get(name), dict) and not parent[name]:
            parent.pop(name)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        sys.exit(__doc__)
    command, path = argv[1], argv[2]

    if command == "set":
        patch = json.load(sys.stdin)
        if not isinstance(patch, dict):
            sys.exit("toml_edit.py set: the patch must be a JSON object")
        write(path, merge(load(path), patch))
        return 0

    if command == "delete":
        keys = argv[3:]
        if not keys:
            sys.exit("toml_edit.py delete: at least one key is required")
        if not os.path.exists(path):
            return 0
        data = load(path)
        delete(data, keys)
        write(path, data)
        return 0

    sys.exit(f"unknown command: {command}")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
