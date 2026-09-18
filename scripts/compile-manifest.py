#!/usr/bin/env python3
"""Compile manifest/components.yaml into manifest/components.json.

Why this exists
---------------
YAML is the right format for humans reviewing a pull request. JSON is the right
format for a Bash runtime, because `jq` is a single small dependency that is
already in the bootstrap set, whereas `yq` is a heavier one that would have to
be installed before anything else could be parsed.

So: YAML is the source of truth for people, JSON is the compiled artefact for
machines, and the JSON is committed so a fresh clone works with no build step.
CI verifies the two are in sync.

Usage:
    scripts/compile-manifest.py [--check]

    --check   exit non-zero if the committed JSON is stale (used in CI)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    sys.exit(
        "PyYAML is required to compile the manifest.\n"
        "  uv tool install --with pyyaml yamllint   # or\n"
        "  pip install --break-system-packages pyyaml"
    )

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "manifest" / "components.yaml"
DST = ROOT / "manifest" / "components.json"

VALID_BACKENDS = {
    "apt",
    "apt-repo",
    "npm-global",
    "cargo",
    "uv-tool",
    "pipx",
    "github-release",
    "script",
    "claude-plugin",
    "agent-skill",
    "npx-installer",
    "mcp-server",
    "none",
}

VALID_TYPES = {"tool", "harness", "extension", "mcp", "meta"}
VALID_VERIFY_KINDS = {"command", "path", "plugin", "skill", "mcp", "none"}

# Verification commands are the only manifest strings that reach a shell. They
# are restricted to a read-only probe shape: a bare command plus flag-like
# arguments. No pipes, redirects, substitution, chaining or globbing.
VERIFY_CMD_RE = re.compile(r"^[A-Za-z0-9_./-]+(?: [A-Za-z0-9_.=/-]+)*$")


class ManifestError(Exception):
    pass


def fail(msg: str) -> None:
    raise ManifestError(msg)


def validate(doc: dict) -> None:
    components = doc.get("components")
    if not isinstance(components, list) or not components:
        fail("manifest must define a non-empty 'components' list")

    ids: set[str] = set()
    for comp in components:
        cid = comp.get("id")
        if not cid:
            fail(f"component without an id: {comp!r}")
        if cid in ids:
            fail(f"duplicate component id: {cid}")
        ids.add(cid)

        ctype = comp.get("type", "tool")
        if ctype not in VALID_TYPES:
            fail(f"{cid}: unknown type '{ctype}' (valid: {sorted(VALID_TYPES)})")

        backend = comp.get("backend")
        if backend not in VALID_BACKENDS:
            fail(f"{cid}: unknown backend '{backend}' (valid: {sorted(VALID_BACKENDS)})")

        verify = comp.get("verify", {})
        kind = verify.get("kind", "command")
        if kind not in VALID_VERIFY_KINDS:
            fail(f"{cid}: unknown verify.kind '{kind}'")

        if kind == "command":
            cmd = verify.get("cmd", "")
            if not cmd:
                fail(f"{cid}: verify.kind=command requires verify.cmd")
            if not VERIFY_CMD_RE.match(cmd):
                fail(
                    f"{cid}: verify.cmd {cmd!r} is not a plain read-only probe. "
                    "Shell metacharacters are rejected by design."
                )
        if kind == "path" and not verify.get("path"):
            fail(f"{cid}: verify.kind=path requires verify.path")

        # Harness-scoped backends must declare their support matrix, otherwise
        # `ai doctor` cannot tell "not installed" from "not supported here".
        if backend in {"claude-plugin", "agent-skill", "npx-installer", "mcp-server"}:
            if not comp.get("harnesses"):
                fail(f"{cid}: backend '{backend}' requires a 'harnesses' matrix")
            for hid, hcfg in comp["harnesses"].items():
                if "scriptable" not in hcfg:
                    fail(f"{cid}.harnesses.{hid}: 'scriptable' is required")
                if hcfg["scriptable"] is False and not hcfg.get("note"):
                    fail(
                        f"{cid}.harnesses.{hid}: a non-scriptable entry must carry a "
                        "'note' telling the user exactly what to do by hand"
                    )

        if backend == "npx-installer":
            if not comp.get("package"):
                fail(f"{cid}: backend 'npx-installer' requires a 'package'")
            installer = comp.get("installer") or {}
            if installer.get("target_flag"):
                for hid, hcfg in comp["harnesses"].items():
                    if hcfg.get("scriptable") and not hcfg.get("arg"):
                        fail(
                            f"{cid}.harnesses.{hid}: installer.target_flag is set, so "
                            "'arg' must name this agent's installer target"
                        )
            scope = installer.get("remove_scope", "agent")
            if scope not in {"agent", "global"}:
                fail(f"{cid}.installer.remove_scope must be 'agent' or 'global'")
            for field in ("install", "remove", "update"):
                value = installer.get(field)
                if value is not None and not isinstance(value, str):
                    fail(f"{cid}.installer.{field} must be a single subcommand string")
            for token in installer.get("args") or []:
                if not isinstance(token, str):
                    fail(f"{cid}.installer.args must be a list of literal argv strings")

        if backend == "script" and not comp.get("script", {}).get("url"):
            fail(f"{cid}: backend 'script' requires script.url")
        if backend == "github-release":
            rel = comp.get("release", {})
            if not (rel.get("sha256") or rel.get("checksums")):
                fail(f"{cid}: github-release requires a checksum (sha256 or checksums)")

    # Dependency edges must point somewhere real.
    for comp in components:
        for dep in comp.get("requires", []) or []:
            if dep not in ids:
                fail(f"{comp['id']}: requires unknown component '{dep}'")

    for pname, prof in (doc.get("profiles") or {}).items():
        for cid in prof.get("components", []):
            if cid not in ids:
                fail(f"profile '{pname}': unknown component '{cid}'")

    # Cycle detection, so `ai install` never spins.
    graph = {c["id"]: list(c.get("requires") or []) for c in components}

    # The full profile is the catalogue coverage invariant. Components may be
    # pulled transitively, but none may become orphaned from every advertised
    # "Everything" installation as happened with ruff/pyright/parser tools.
    full = (doc.get("profiles") or {}).get("full")
    if full is not None:
        reachable: set[str] = set()

        def include(node: str) -> None:
            if node in reachable:
                return
            reachable.add(node)
            for dep in graph[node]:
                include(dep)

        for node in full.get("components", []):
            include(node)
        missing_from_full = sorted(ids - reachable)
        if missing_from_full:
            fail(
                "profile 'full' does not reach every component: "
                + ", ".join(missing_from_full)
            )

    state: dict[str, int] = {}

    def visit(node: str, stack: list[str]) -> None:
        if state.get(node) == 2:
            return
        if state.get(node) == 1:
            fail("dependency cycle: " + " -> ".join(stack + [node]))
        state[node] = 1
        for nxt in graph[node]:
            visit(nxt, stack + [node])
        state[node] = 2

    for node in graph:
        visit(node, [])


def main() -> int:
    check = "--check" in sys.argv

    try:
        doc = yaml.safe_load(SRC.read_text(encoding="utf-8"))
        validate(doc)
    except ManifestError as exc:
        print(f"manifest validation failed: {exc}", file=sys.stderr)
        return 1
    except yaml.YAMLError as exc:
        print(f"could not parse {SRC}: {exc}", file=sys.stderr)
        return 1

    rendered = json.dumps(doc, indent=2, sort_keys=False, ensure_ascii=False) + "\n"

    if check:
        if not DST.exists() or DST.read_text(encoding="utf-8") != rendered:
            print(
                "components.json is out of date with components.yaml.\n"
                "Run: make manifest",
                file=sys.stderr,
            )
            return 1
        print(f"manifest is in sync ({len(doc['components'])} components)")
        return 0

    DST.write_text(rendered, encoding="utf-8")
    print(
        f"compiled {len(doc['components'])} components "
        f"and {len(doc.get('profiles') or {})} profiles -> {DST.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
