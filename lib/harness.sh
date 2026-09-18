#!/usr/bin/env bash
# lib/harness.sh — coding-agent ("harness") abstraction.
#
# WHY THIS EXISTS
# ---------------
# Once you support more than one coding agent, the agent stops being an
# implementation detail and becomes a dimension of the data model. Caveman can
# be present in Claude Code and absent from OpenCode. Context7 has to be
# registered three different ways. `ai doctor` is a matrix, not a list.
#
# Every harness ships one file in harnesses/<id>.sh implementing this contract:
#
#   <id>_name              -> human label
#   <id>_detect            -> 0 if the agent is installed
#   <id>_version           -> version string on stdout
#   <id>_config_path       -> path to its config file
#   <id>_config_format     -> json | jsonc | toml
#   <id>_supports <cap>    -> 0 if capability supported
#                             caps: plugin skill mcp-stdio mcp-http
#   <id>_mcp_add <name> <json-spec>
#   <id>_mcp_remove <name>
#   <id>_mcp_has <name>
#   <id>_plugin_add <marketplace> <plugin>
#   <id>_plugin_remove <plugin>
#   <id>_plugin_has <plugin>
#   <id>_skill_add <repo> [skill]   # empty skill = every skill in the repo
#   <id>_skill_remove <skill>
#   <id>_skill_has <skill>
#
# Adding Cursor or Gemini CLI later is one new file here plus manifest rows.
# The core never changes. That is the whole point.
#
# shellcheck shell=bash

[[ -n "${_AI_HARNESS_SH:-}" ]] && return 0
_AI_HARNESS_SH=1

# The pseudo-harness "system" means "not agent-scoped at all" (ripgrep, docker).
HARNESS_SYSTEM="system"

# harness_all — every adapter present in harnesses/, sorted.
harness_all() {
  local f
  for f in "$AI_ROOT"/harnesses/*.sh; do
    [[ -e "$f" ]] || continue
    basename "$f" .sh
  done | sort
}

# harness_load <id> — source an adapter exactly once.
harness_load() {
  local id="$1"
  local guard="_AI_HARNESS_LOADED_${id//-/_}"
  [[ -n "${!guard:-}" ]] && return 0
  local file="$AI_ROOT/harnesses/${id}.sh"
  [[ -f "$file" ]] || die "unknown harness '${id}' (available: $(harness_all | tr '\n' ' '))"
  # shellcheck source=/dev/null
  . "$file"
  printf -v "$guard" '%s' 1
  export "${guard?}"
}

# harness_fn <id> <verb> — the adapter function name, with underscores.
harness_fn() {
  local id="${1//-/_}"
  printf '%s_%s' "$id" "$2"
}

# harness_call <id> <verb> [args...] — dispatch, or fail cleanly when the
# adapter does not implement that verb.
harness_call() {
  local id="$1" verb="$2"
  shift 2
  harness_load "$id"
  local fn
  fn="$(harness_fn "$id" "$verb")"
  if ! declare -F "$fn" >/dev/null 2>&1; then
    log_debug "harness ${id} does not implement ${verb}"
    return 3
  fi
  "$fn" "$@"
}

harness_exists() { [[ -f "$AI_ROOT/harnesses/${1}.sh" ]]; }
harness_detect() { harness_call "$1" detect; }
harness_name() { harness_call "$1" name 2>/dev/null || printf '%s' "$1"; }
harness_version() { harness_call "$1" version 2>/dev/null || printf 'unknown'; }
harness_supports() { harness_call "$1" supports "$2"; }
harness_config_path() { harness_call "$1" config_path; }

harness_mcp_add() { harness_call "$1" mcp_add "$2" "$3"; }
harness_mcp_remove() { harness_call "$1" mcp_remove "$2"; }
harness_mcp_has() { harness_call "$1" mcp_has "$2"; }
harness_plugin_add() { harness_call "$1" plugin_add "$2" "$3"; }
harness_plugin_remove() { harness_call "$1" plugin_remove "$2"; }
harness_plugin_has() { harness_call "$1" plugin_has "$2"; }
harness_skill_add() { harness_call "$1" skill_add "$2" "${3:-}"; }
harness_skill_remove() { harness_call "$1" skill_remove "$2"; }
harness_skill_has() { harness_call "$1" skill_has "$2"; }

# harness_installed — the subset of adapters whose agent is actually present.
harness_installed() {
  local h
  while IFS= read -r h; do
    harness_detect "$h" >/dev/null 2>&1 && printf '%s\n' "$h"
  done < <(harness_all)
}

# harness_selection <spec> — expand a --harness value into concrete ids.
#   all       -> every harness that is actually installed
#   any       -> alias for all
#   a,b,c     -> exactly those, validated
#   (empty)   -> AI_HARNESSES if set, else all installed
harness_selection() {
  local spec="${1:-}"
  [[ -z "$spec" ]] && spec="${AI_HARNESSES:-all}"
  if [[ "$spec" == "all" || "$spec" == "any" ]]; then
    harness_installed
    return 0
  fi
  local h
  local IFS=','
  for h in $spec; do
    h="${h// /}"
    [[ -z "$h" ]] && continue
    harness_exists "$h" || die "unknown harness '${h}' (available: $(harness_all | tr '\n' ' '))"
    printf '%s\n' "$h"
  done
}

# harness_jsonc_read <path> — read a JSON/JSONC config into strict JSON on
# stdout. OpenCode permits comments; jq does not. We strip line comments
# conservatively and never touch anything inside a string literal.
harness_jsonc_read() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf '{}'
    return 0
  fi
  python3 - "$path" <<'PY'
import json, re, sys

raw = open(sys.argv[1], encoding="utf-8").read()
out, i, n = [], 0, len(raw)
in_str = esc = False
while i < n:
    c = raw[i]
    if in_str:
        out.append(c)
        if esc:
            esc = False
        elif c == "\\":
            esc = True
        elif c == '"':
            in_str = False
        i += 1
        continue
    if c == '"':
        in_str = True
        out.append(c)
        i += 1
        continue
    if c == "/" and i + 1 < n and raw[i + 1] == "/":
        while i < n and raw[i] != "\n":
            i += 1
        continue
    if c == "/" and i + 1 < n and raw[i + 1] == "*":
        i += 2
        while i + 1 < n and not (raw[i] == "*" and raw[i + 1] == "/"):
            i += 1
        i += 2
        continue
    out.append(c)
    i += 1

text = re.sub(r",(\s*[}\]])", r"\1", "".join(out)).strip()
try:
    print(json.dumps(json.loads(text or "{}")))
except json.JSONDecodeError as exc:
    print(f"malformed config {sys.argv[1]}: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

# harness_json_merge <path> <jq-filter> [jq-args...] — read/modify/write a JSON
# config atomically, taking a rollback backup first.
harness_json_merge() {
  local path="$1" filter="$2"
  shift 2
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] edit %s%s\n' "$C_GREY" "$path" "$C_RESET" >&2
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  rollback_backup "$path"
  local current tmp
  current="$(harness_jsonc_read "$path")"
  tmp="$(mktemp)"
  printf '%s' "$current" | jq "$@" "$filter" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$path"
}

# harness_toml_patch <path> <json-patch>
# Deep-merge a JSON object into a TOML file. Codex keeps its config in TOML and
# jq cannot write TOML, so the writing lives in lib/toml_edit.py — one
# implementation, which is what keeps key quoting correct everywhere.
harness_toml_patch() {
  local path="$1" patch="$2"
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] edit %s%s\n' "$C_GREY" "$path" "$C_RESET" >&2
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  rollback_backup "$path"
  printf '%s' "$patch" | python3 "$AI_LIB_DIR/toml_edit.py" set "$path"
}

# harness_toml_mcp_write <path> <server-name> <spec-json>
harness_toml_mcp_write() {
  local path="$1" name="$2" spec="$3"
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] edit %s (mcp_servers.%s)%s\n' "$C_GREY" "$path" "$name" "$C_RESET" >&2
    return 0
  fi
  local patch
  patch="$(jq -nc --arg n "$name" --argjson s "$spec" '{mcp_servers: {($n): $s}}')" || return 1
  harness_toml_patch "$path" "$patch"
}

# harness_toml_mcp_delete <path> <server-name>
harness_toml_mcp_delete() {
  local path="$1" name="$2"
  [[ -f "$path" ]] || return 0
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] remove mcp_servers.%s from %s%s\n' "$C_GREY" "$name" "$path" "$C_RESET" >&2
    return 0
  fi
  rollback_backup "$path"
  python3 "$AI_LIB_DIR/toml_edit.py" delete "$path" mcp_servers "$name"
}
