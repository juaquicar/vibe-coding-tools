#!/usr/bin/env bash
# lib/manifest.sh — the single source of truth about components.
#
# DESIGN: the manifest is DECLARATIVE. It never contains a shell command to be
# eval'd. Each component names a `backend`, and the backend knows how to
# install/verify/remove that class of thing. This is what makes `--dry-run`
# meaningful, keeps ShellCheck happy, and means a pull request adding a
# component cannot ship arbitrary root code.
#
# Source of truth for humans:  manifest/components.yaml
# Source of truth for runtime: manifest/components.json  (compiled, committed)
#
# The runtime only ever reads JSON, so `jq` is the sole parsing dependency —
# no `yq` in the bootstrap path.
#
# shellcheck shell=bash

[[ -n "${_AI_MANIFEST_SH:-}" ]] && return 0
_AI_MANIFEST_SH=1

manifest_require() {
  [[ -f "$AI_MANIFEST" ]] ||
    die "compiled manifest missing: $AI_MANIFEST (run: make manifest)"
  have jq || die "jq is required; run ./bootstrap.sh first"
}

_mq() { jq -r "$@" "$AI_MANIFEST"; }

# manifest_ids — every component id, in manifest order.
manifest_ids() { manifest_require && _mq '.components[].id'; }

# manifest_exists <id>
manifest_exists() {
  manifest_require
  [[ "$(_mq --arg i "$1" '[.components[] | select(.id == $i)] | length')" -gt 0 ]]
}

# manifest_field <id> <jq-path> [default]
#
# Boolean-safe: `false` is a real value, not a missing one. Do NOT rewrite this
# with jq's `//` operator — `false // "x"` yields "x", which would silently
# turn every `false` in the manifest into its default.
manifest_field() {
  manifest_require
  local id="$1" path="$2" default="${3:-}"
  local val
  val="$(_mq --arg i "$id" \
    "[.components[] | select(.id == \$i) | ${path} | select(. != null)] | first | if . == null then \"\" else tostring end")"
  [[ -z "$val" ]] && val="$default"
  printf '%s' "$val"
}

# manifest_list <id> <jq-path> — newline-separated array contents.
manifest_list() {
  manifest_require
  _mq --arg i "$1" "first(.components[] | select(.id == \$i) | ${2}) // [] | .[]"
}

manifest_backend() { manifest_field "$1" '.backend' 'none'; }
manifest_type() { manifest_field "$1" '.type' 'tool'; }
manifest_desc() { manifest_field "$1" '.description' ''; }
manifest_package() { manifest_field "$1" '.package' ''; }
manifest_version_spec() { manifest_field "$1" '.version' 'latest'; }
manifest_repo() { manifest_field "$1" '.repository' ''; }
manifest_bin() { manifest_field "$1" '.bin' ''; }
manifest_requires() { manifest_list "$1" '.requires'; }
manifest_packages() { manifest_list "$1" '.packages'; }
manifest_tags() { manifest_list "$1" '.tags'; }

manifest_needs_sudo() { [[ "$(manifest_field "$1" '.sudo' 'false')" == "true" ]]; }
manifest_needs_relogin() { [[ "$(manifest_field "$1" '.relogin' 'false')" == "true" ]]; }

# Verification contract. `kind` decides HOW we check, which matters enormously:
# an agent plugin is never on PATH, so `command -v superpowers` would report a
# false negative forever.
#   command : run `verify.cmd`, match stdout against `verify.match`
#   path    : test -e on `verify.path` (tilde expanded)
#   plugin  : ask the harness adapter whether the plugin is registered
#   mcp     : ask the harness adapter whether the MCP server is registered
#   none    : unverifiable, trust the state file
manifest_verify_kind() { manifest_field "$1" '.verify.kind' 'command'; }
manifest_verify_cmd() { manifest_field "$1" '.verify.cmd' ''; }
manifest_verify_match() { manifest_field "$1" '.verify.match' '.'; }
manifest_verify_path() { manifest_field "$1" '.verify.path' ''; }

# Harness support matrix.
# `harnesses` is a map: harness-id -> {scriptable: bool, method: string, note: string}
manifest_harnesses() { manifest_list "$1" '(.harnesses // {} | keys)'; }

manifest_is_harness_scoped() {
  manifest_require
  [[ "$(_mq --arg i "$1" 'first(.components[] | select(.id == $i) | (.harnesses // {} | length)) // 0')" -gt 0 ]]
}

# manifest_harness_field <id> <harness> <field> [default]
#
# Same boolean hazard as manifest_field, and it matters more here: `scriptable`
# is the field that decides whether vibe-coding-tools installs something or tells
# the user to do it by hand.
manifest_harness_field() {
  manifest_require
  local id="$1" harness="$2" field="$3" default="${4:-}"
  local val
  val="$(_mq --arg i "$id" --arg h "$harness" --arg f "$field" \
    '[.components[] | select(.id == $i) | .harnesses[$h][$f] | select(. != null)] | first | if . == null then "" else tostring end')"
  [[ -z "$val" ]] && val="$default"
  printf '%s' "$val"
}

# manifest_harness_declared <id> <harness> — does this component say anything
# at all about this agent? Distinct from "is it scriptable there".
manifest_harness_declared() {
  manifest_require
  [[ "$(_mq --arg i "$1" --arg h "$2" \
    '[.components[] | select(.id == $i) | (.harnesses // {}) | has($h)] | first // false')" == "true" ]]
}

# manifest_harness_scriptable <id> <harness>
# False means: we can register the intent and print instructions, but we must
# NOT pretend we installed it. See docs/Harnesses.md.
manifest_harness_scriptable() {
  [[ "$(manifest_harness_field "$1" "$2" 'scriptable' 'false')" == "true" ]]
}

manifest_harness_method() { manifest_harness_field "$1" "$2" 'method' ''; }
manifest_harness_arg() { manifest_harness_field "$1" "$2" 'arg' ''; }
manifest_harness_note() { manifest_harness_field "$1" "$2" 'note' ''; }

# manifest_hook <id> <phase> — absolute path to a hook script, or empty.
# Hooks are auto-discovered by convention: hooks/<id>/<phase>.sh
# Phases: pre-install, post-install, pre-remove, post-remove.
manifest_hook() {
  local path="$AI_ROOT/hooks/$1/$2.sh"
  [[ -x "$path" ]] && printf '%s' "$path"
}

# manifest_search <term> — id/description substring match, tab separated.
manifest_search() {
  manifest_require
  _mq --arg t "$1" \
    '.components[]
     | select((.id | ascii_downcase | contains($t | ascii_downcase))
           or ((.description // "") | ascii_downcase | contains($t | ascii_downcase)))
     | [.id, .type, .backend, (.description // "")] | @tsv'
}

# manifest_by_tag <tag>
manifest_by_tag() {
  manifest_require
  _mq --arg t "$1" '.components[] | select((.tags // []) | index($t)) | .id'
}

# manifest_profile <name> — component ids belonging to a profile.
manifest_profile() {
  manifest_require
  _mq --arg p "$1" '.profiles[$p].components // [] | .[]'
}

manifest_profile_harnesses() {
  manifest_require
  _mq --arg p "$1" '.profiles[$p].harnesses // [] | .[]'
}

manifest_profiles() { manifest_require && _mq '.profiles | keys[]'; }

manifest_profile_exists() {
  manifest_require
  [[ "$(_mq --arg p "$1" '.profiles | has($p)')" == "true" ]]
}
