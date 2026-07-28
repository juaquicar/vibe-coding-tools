#!/usr/bin/env bash
# lib/state.sh — persistent installation state.
#
# The state file is the answer to "what is actually installed here?". Without
# it `ai repair`, `ai remove`, `ai update` and resuming a failed install are all
# impossible — you would be guessing from PATH.
#
# Entries are keyed on the pair (component, harness). A harness-independent
# tool such as ripgrep uses the pseudo-harness "system". An extension such as
# caveman genuinely has one row per harness, because it can be installed for
# Claude Code and missing from OpenCode.
#
# Schema (state.json):
# {
#   "version": 1,
#   "updated": "2026-07-27T10:00:00Z",
#   "entries": {
#     "ripgrep@system":     {"component":"ripgrep","harness":"system","version":"14.1.0",
#                            "backend":"apt","installed_at":"...","status":"installed"},
#     "caveman@claude-code":{"component":"caveman","harness":"claude-code", ...}
#   }
# }
#
# shellcheck shell=bash

[[ -n "${_AI_STATE_SH:-}" ]] && return 0
_AI_STATE_SH=1

STATE_SCHEMA_VERSION=1

state_init() {
  mkdir -p "$(dirname "$AI_STATE_FILE")"
  if [[ ! -f "$AI_STATE_FILE" ]]; then
    printf '{"version":%s,"updated":null,"entries":{}}\n' "$STATE_SCHEMA_VERSION" >"$AI_STATE_FILE"
  fi
  local v
  v="$(jq -r '.version // 0' "$AI_STATE_FILE")"
  if [[ "$v" -gt "$STATE_SCHEMA_VERSION" ]]; then
    die "state file schema v${v} is newer than this vibe-coding-tools (v${STATE_SCHEMA_VERSION}); upgrade the tool"
  fi
}

_state_key() { printf '%s@%s' "$1" "${2:-system}"; }

# state_write <component> <harness> <version> <backend> <status>
# status: installed | manual | failed
state_write() {
  local comp="$1" harness="${2:-system}" ver="${3:-unknown}" backend="${4:-unknown}" status="${5:-installed}"
  [[ "$AI_DRY_RUN" == "1" ]] && return 0
  state_init
  local key tmp now
  key="$(_state_key "$comp" "$harness")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  jq --arg k "$key" --arg c "$comp" --arg h "$harness" --arg v "$ver" \
    --arg b "$backend" --arg s "$status" --arg t "$now" \
    '.entries[$k] = {component:$c, harness:$h, version:$v, backend:$b, status:$s, installed_at:$t}
     | .updated = $t' \
    "$AI_STATE_FILE" >"$tmp" && mv "$tmp" "$AI_STATE_FILE"
}

# state_forget <component> [harness] — drop one row, or every row for a
# component when no harness is given.
state_forget() {
  local comp="$1" harness="${2:-}"
  [[ "$AI_DRY_RUN" == "1" ]] && return 0
  state_init
  local tmp now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  if [[ -n "$harness" ]]; then
    jq --arg k "$(_state_key "$comp" "$harness")" --arg t "$now" \
      'del(.entries[$k]) | .updated = $t' "$AI_STATE_FILE" >"$tmp"
  else
    jq --arg c "$comp" --arg t "$now" \
      '.entries |= with_entries(select(.value.component != $c)) | .updated = $t' \
      "$AI_STATE_FILE" >"$tmp"
  fi
  mv "$tmp" "$AI_STATE_FILE"
}

# state_is_installed <component> [harness]
state_is_installed() {
  local comp="$1" harness="${2:-system}"
  state_init
  local s
  s="$(jq -r --arg k "$(_state_key "$comp" "$harness")" \
    '.entries[$k].status // "absent"' "$AI_STATE_FILE")"
  [[ "$s" == "installed" ]]
}

# state_get <component> <harness> <field>
state_get() {
  state_init
  jq -r --arg k "$(_state_key "$1" "$2")" --arg f "$3" \
    '.entries[$k][$f] // ""' "$AI_STATE_FILE"
}

# state_components — every distinct component with at least one installed row.
state_components() {
  state_init
  jq -r '[.entries[] | select(.status == "installed") | .component] | unique | .[]' \
    "$AI_STATE_FILE"
}

# state_failed_components — components whose last attempted installation
# failed. `ai repair` must include these even when no installed row exists, or
# a failed harness entry can become invisible after an interrupted profile.
state_failed_components() {
  state_init
  jq -r '[.entries[] | select(.status == "failed") | .component] | unique | .[]' \
    "$AI_STATE_FILE"
}

# state_harnesses_for <component>
state_harnesses_for() {
  state_init
  jq -r --arg c "$1" \
    '[.entries[] | select(.component == $c and .status == "installed") | .harness] | unique | .[]' \
    "$AI_STATE_FILE"
}

# state_rows — tab-separated dump for `ai status`.
state_rows() {
  state_init
  jq -r '.entries | to_entries | sort_by(.key)[] |
         [.value.component, .value.harness, .value.version, .value.backend, .value.status]
         | @tsv' "$AI_STATE_FILE"
}

# ---------------------------------------------------------------------------
# Lockfile
# ---------------------------------------------------------------------------
#
# ai.lock pins the exact resolved versions of everything installed, so the same
# stack can be reproduced on another machine with `ai install --from-lock`.
# This is the feature that separates this project from a curl|bash script with
# nicer colours: onboarding a new engineer becomes deterministic.

lockfile_write() {
  [[ "$AI_DRY_RUN" == "1" ]] && return 0
  state_init
  mkdir -p "$(dirname "$AI_LOCKFILE")"
  local tmp
  tmp="$(mktemp)"
  jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg os "${AI_OS_ID:-ubuntu}-${AI_OS_VERSION:-unknown}" \
    '{generated: $t, platform: $os,
      components: [.entries[] | select(.status == "installed")
                   | {component, harness, version, backend}]
                  | sort_by(.component, .harness)}' \
    "$AI_STATE_FILE" >"$tmp" && mv "$tmp" "$AI_LOCKFILE"
  log_ok "lockfile written: $AI_LOCKFILE"
}

# lockfile_components — component ids recorded in an existing lockfile.
lockfile_components() {
  [[ -f "$AI_LOCKFILE" ]] || die "no lockfile at $AI_LOCKFILE"
  jq -r '[.components[].component] | unique | .[]' "$AI_LOCKFILE"
}

# lockfile_version <component> — the pinned version, or empty.
lockfile_version() {
  [[ -f "$AI_LOCKFILE" ]] || return 0
  jq -r --arg c "$1" \
    'first(.components[] | select(.component == $c) | .version) // ""' "$AI_LOCKFILE"
}
