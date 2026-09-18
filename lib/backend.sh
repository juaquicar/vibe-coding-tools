#!/usr/bin/env bash
# lib/backend.sh — backend dispatch.
#
# A backend knows how to install one CLASS of thing (an apt package, an npm
# global, a Claude Code plugin). Components in the manifest only name a backend
# and its parameters — they never carry shell commands. Ten backends cover the
# entire stack today; adding an ecosystem is one new file here.
#
# Contract, implemented in lib/backends/<name>.sh:
#
#   backend_<name>_install <component-id> [harness]
#   backend_<name>_remove  <component-id> [harness]
#   backend_<name>_update  <component-id> [harness]
#   backend_<name>_version <component-id>            -> version on stdout
#
# shellcheck shell=bash

[[ -n "${_AI_BACKEND_SH:-}" ]] && return 0
_AI_BACKEND_SH=1

backend_load() {
  local name="$1"
  local guard="_AI_BACKEND_LOADED_${name//-/_}"
  [[ -n "${!guard:-}" ]] && return 0
  local file="$AI_ROOT/lib/backends/${name}.sh"
  [[ -f "$file" ]] || die "unknown backend '${name}'"
  # shellcheck source=/dev/null
  . "$file"
  printf -v "$guard" '%s' 1
  export "${guard?}"
}

backend_fn() {
  local name="${1//-/_}"
  printf 'backend_%s_%s' "$name" "$2"
}

# backend_call <backend> <verb> <args...>
backend_call() {
  local name="$1" verb="$2"
  shift 2
  backend_load "$name"
  local fn
  fn="$(backend_fn "$name" "$verb")"
  declare -F "$fn" >/dev/null 2>&1 ||
    die "backend '${name}' does not implement '${verb}'"
  "$fn" "$@"
}

backend_all() {
  local f
  for f in "$AI_ROOT"/lib/backends/*.sh; do
    [[ -e "$f" ]] || continue
    basename "$f" .sh
  done | sort
}

# ---------------------------------------------------------------------------
# Shared verification, used by install, doctor and repair alike.
# ---------------------------------------------------------------------------

# component_verify <id> [harness] — is this component actually present?
component_verify() {
  local id="$1" harness="${2:-system}"
  local kind
  kind="$(manifest_verify_kind "$id")"

  case "$kind" in
    command)
      local cmd match
      cmd="$(manifest_verify_cmd "$id")"
      match="$(manifest_verify_match "$id")"
      [[ -z "$cmd" ]] && return 1
      local bin="${cmd%% *}"
      have "$bin" || return 1
      local out
      out="$(eval_verify "$cmd")" || return 1
      [[ "$out" =~ $match ]]
      ;;
    path)
      local p
      p="$(manifest_verify_path "$id")"
      p="${p/#\~/$HOME}"
      p="${p//\$HOME/$HOME}"
      [[ -e "$p" ]]
      ;;
    plugin)
      local plugin method
      plugin="$(manifest_field "$id" '.plugin' "$id")"
      method="$(manifest_harness_method "$id" "$harness")"
      if [[ "$method" == "skills-registry" ]]; then
        harness_skill_has "$harness" "$id"
      else
        harness_plugin_has "$harness" "$plugin"
      fi
      ;;
    skill)
      local skill
      skill="$(manifest_field "$id" '.skill' "$id")"
      harness_skill_has "$harness" "$skill"
      ;;
    mcp)
      local server
      server="$(manifest_field "$id" '.server' "$id")"
      harness_mcp_has "$harness" "$server"
      ;;
    none) return 0 ;;
    *) return 1 ;;
  esac
}

# eval_verify <cmd> — run a verification command.
#
# This is the ONLY place the manifest influences execution, and it is
# deliberately narrow: verification commands are read-only version probes such
# as `rg --version`. They are validated by the JSON schema against a
# conservative allowlist pattern, never run with sudo, and their output is only
# ever regex-matched. Install/remove paths use typed backends exclusively.
eval_verify() {
  local cmd="$1"
  # shellcheck disable=SC2086
  timeout 20 ${cmd} 2>/dev/null | head -n5
}

# component_version <id> — best-effort installed version string.
component_version() {
  local id="$1"
  local cmd
  cmd="$(manifest_verify_cmd "$id")"
  [[ -z "$cmd" ]] && {
    printf 'n/a'
    return 0
  }
  local out
  out="$(eval_verify "$cmd" || true)"
  local ver
  ver="$(printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?([-.][0-9A-Za-z.]+)?' | head -n1)"
  printf '%s' "${ver:-unknown}"
}

# component_path <id> — where the binary lives, for `ai doctor`.
component_path() {
  local bin
  bin="$(manifest_bin "$1")"
  [[ -z "$bin" ]] && {
    printf '-'
    return 0
  }
  command -v "$bin" 2>/dev/null || printf '-'
}
