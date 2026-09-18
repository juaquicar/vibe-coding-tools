#!/usr/bin/env bash
# lib/backends/agent-skill.sh — cross-agent skills via the `skills` registry.
#
# This is the one distribution mechanism that spans Claude Code, Codex,
# OpenCode and Cursor alike, which makes it the portability escape hatch for
# components whose native plugin path is interactive-only on some harness.
#
# shellcheck shell=bash

backend_agent_skill_install() {
  local id="$1" harness="${2:-}"
  local repo skill

  repo="$(manifest_repo "$id")"
  # `.skill` names one skill inside a multi-skill repository. Without it the
  # registry installs every skill the repo publishes, which is a very different
  # component from the one the manifest row claims to be.
  skill="$(manifest_field "$id" '.skill' '')"
  [[ -n "$repo" ]] || die "component '${id}': .repository is required for agent-skill"
  [[ -n "$harness" ]] || die "component '${id}': agent-skill is harness-scoped"

  if ! harness_detect "$harness"; then
    log_warn "${harness} is not installed; skipping ${id}"
    return 0
  fi

  if ! manifest_harness_scriptable "$id" "$harness"; then
    local note
    note="$(manifest_harness_note "$id" "$harness")"
    log_warn "${id} has no non-interactive install for $(harness_name "$harness")"
    [[ -n "$note" ]] && printf '      %s%s%s\n' "$C_YELLOW" "$note" "$C_RESET" >&2
    state_write "$id" "$harness" "n/a" "agent-skill" "manual"
    return 0
  fi

  node_runtime_activate || true
  have npx || die "npx not found; install the 'node' component first"

  if [[ -n "$skill" ]] && harness_skill_has "$harness" "$skill"; then
    log_debug "${id}: already installed in ${harness}"
    return 0
  fi

  log_info "adding skill ${repo}${skill:+ (${skill})} to $(harness_name "$harness")"
  harness_skill_add "$harness" "$repo" "$skill" || return $?
  rollback_record "noop skill ${repo} added to ${harness}"
}

backend_agent_skill_remove() {
  local id="$1" harness="${2:-}" skill
  skill="$(manifest_field "$id" '.skill' "$id")"
  harness_detect "$harness" || return 0
  harness_skill_has "$harness" "$skill" || return 0
  harness_skill_remove "$harness" "$skill"
}

backend_agent_skill_update() {
  backend_agent_skill_install "$1" "${2:-}"
}

backend_agent_skill_version() { printf 'registry'; }
