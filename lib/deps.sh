#!/usr/bin/env bash
# lib/deps.sh — dependency resolution.
#
# Produces a topologically ordered install plan from a set of requested
# components. Detects cycles rather than looping forever, and explains the
# chain when it refuses (`ai why <id>`).
#
# The graph matters more here than in a normal package manager because of the
# agent-extension layering: superpowers depends on claude-code depends on node
# depends on fnm. Installing superpowers on a machine with no Node has to fail
# loudly at plan time, not silently halfway through.
#
# shellcheck shell=bash

[[ -n "${_AI_DEPS_SH:-}" ]] && return 0
_AI_DEPS_SH=1

declare -A _DEPS_MARK=()
declare -a _DEPS_ORDER=()
declare -a _DEPS_STACK=()

_deps_visit() {
  local id="$1"

  case "${_DEPS_MARK[$id]:-}" in
    done) return 0 ;;
    open)
      local chain
      chain="$(join_by ' -> ' "${_DEPS_STACK[@]}" "$id")"
      die "dependency cycle detected: ${chain}"
      ;;
  esac

  manifest_exists "$id" || die "unknown component '${id}' (try: ${AI_CLI_NAME} search ${id})"

  _DEPS_MARK[$id]="open"
  _DEPS_STACK+=("$id")

  local dep
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    _deps_visit "$dep"
  done < <(manifest_requires "$id")

  unset '_DEPS_STACK[${#_DEPS_STACK[@]}-1]'
  _DEPS_MARK[$id]="done"
  _DEPS_ORDER+=("$id")
}

# deps_resolve <id...> — print the full install order, one id per line.
deps_resolve() {
  _DEPS_MARK=()
  _DEPS_ORDER=()
  _DEPS_STACK=()
  local id
  for id in "$@"; do
    _deps_visit "$id"
  done
  printf '%s\n' "${_DEPS_ORDER[@]}"
}

# deps_reverse <id> — components that directly require <id>. Used by
# `ai remove` to refuse orphaning something, and by `ai why`.
deps_reverse() {
  manifest_require
  jq -r --arg i "$1" \
    '.components[] | select((.requires // []) | index($i)) | .id' "$AI_MANIFEST"
}

# deps_why <id> — human explanation of where a component sits in the graph.
deps_why() {
  local id="$1"
  manifest_exists "$id" || die "unknown component '${id}'"

  printf '%s%s%s — %s\n\n' "$C_BOLD" "$id" "$C_RESET" "$(manifest_desc "$id")"

  printf '%sRequires%s\n' "$C_CYAN" "$C_RESET"
  local dep found=0
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    found=1
    printf '  %s  (%s)\n' "$dep" "$(manifest_backend "$dep")"
  done < <(manifest_requires "$id")
  ((found)) || printf '  %s(nothing)%s\n' "$C_GREY" "$C_RESET"

  printf '\n%sRequired by%s\n' "$C_CYAN" "$C_RESET"
  found=0
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    found=1
    printf '  %s\n' "$dep"
  done < <(deps_reverse "$id")
  ((found)) || printf '  %s(nothing)%s\n' "$C_GREY" "$C_RESET"

  printf '\n%sFull install order%s\n' "$C_CYAN" "$C_RESET"
  local step
  while IFS= read -r step; do
    if [[ "$step" == "$id" ]]; then
      printf '  %s%s%s\n' "$C_BOLD" "$step" "$C_RESET"
    else
      printf '  %s\n' "$step"
    fi
  done < <(deps_resolve "$id")
}
