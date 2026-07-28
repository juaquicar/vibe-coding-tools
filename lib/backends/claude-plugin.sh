#!/usr/bin/env bash
# lib/backends/claude-plugin.sh — agent plugins installed through a marketplace.
#
# Harness-scoped: one install per harness, one state row per (component,
# harness) pair. When a harness cannot do this non-interactively, we record
# status=manual and print the exact steps rather than reporting a success that
# did not happen.
#
# shellcheck shell=bash

backend_claude_plugin_install() {
  local id="$1" harness="${2:-claude-code}"
  local marketplace plugin install_arg method repo

  marketplace="$(manifest_field "$id" '.marketplace' '')"
  plugin="$(manifest_field "$id" '.plugin' "$id")"
  method="$(manifest_harness_method "$id" "$harness")"
  install_arg="$(manifest_harness_arg "$id" "$harness")"
  repo="$(manifest_repo "$id")"
  [[ -n "$marketplace" ]] || die "component '${id}': .marketplace is required"

  if ! harness_detect "$harness"; then
    log_warn "${harness} is not installed; skipping ${id}"
    return 0
  fi

  if [[ "$method" == "skills-registry" ]]; then
    node_runtime_activate || true
    have npx || die "npx not found; install the 'node' component first"
    harness_skill_has "$harness" "$id" && return 0
    log_info "adding skill ${repo} to $(harness_name "$harness")"
    harness_skill_add "$harness" "$repo" || return $?
    rollback_record "noop skill ${repo} added to ${harness}"
    return 0
  fi

  if ! manifest_harness_scriptable "$id" "$harness"; then
    local note
    note="$(manifest_harness_note "$id" "$harness")"
    log_warn "${id} cannot be installed non-interactively on $(harness_name "$harness")"
    [[ -n "$note" ]] && printf '      %s%s%s\n' "$C_YELLOW" "$note" "$C_RESET" >&2
    state_write "$id" "$harness" "n/a" "claude-plugin" "manual"
    return 0
  fi

  if harness_plugin_has "$harness" "$plugin"; then
    log_debug "${id}: already installed in ${harness}"
    return 0
  fi

  if ! harness_supports "$harness" plugin; then
    log_warn "$(harness_name "$harness") does not support plugin installs"
    state_write "$id" "$harness" "n/a" "claude-plugin" "manual"
    return 0
  fi

  [[ -n "$install_arg" ]] || install_arg="$plugin"
  log_info "installing plugin ${plugin} into $(harness_name "$harness")"
  harness_plugin_add "$harness" "$marketplace" "$install_arg" || return $?
  rollback_record "plugin ${harness} ${plugin}"
}

backend_claude_plugin_remove() {
  local id="$1" harness="${2:-claude-code}"
  local plugin method
  plugin="$(manifest_field "$id" '.plugin' "$id")"
  method="$(manifest_harness_method "$id" "$harness")"
  harness_detect "$harness" || return 0
  if [[ "$method" == "skills-registry" ]]; then
    harness_skill_has "$harness" "$id" || return 0
    harness_skill_remove "$harness" "$id"
    return 0
  fi
  harness_plugin_has "$harness" "$plugin" || return 0
  harness_plugin_remove "$harness" "$plugin"
}

backend_claude_plugin_update() {
  local id="$1" harness="${2:-claude-code}"
  # Marketplace plugins self-update on the agent's own schedule; re-running the
  # install is the documented way to force a refresh.
  backend_claude_plugin_install "$id" "$harness"
}

backend_claude_plugin_version() {
  printf 'marketplace'
}
