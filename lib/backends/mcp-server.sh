#!/usr/bin/env bash
# lib/backends/mcp-server.sh — MCP server registration.
#
# Installs nothing on PATH. It writes a server entry into each selected
# harness's configuration, using that harness's native subcommand where one
# exists and its config format where one does not (JSON for Claude Code,
# JSON/JSONC for OpenCode, TOML for Codex).
#
# This backend is what makes the roadmap cheap: PostgreSQL MCP, Docker MCP,
# GitHub MCP and Playwright MCP are all pure manifest entries. No new code.
#
# shellcheck shell=bash

backend_mcp_server_install() {
  local id="$1" harness="${2:-}"
  local server spec cap

  server="$(manifest_field "$id" '.server' "$id")"
  spec="$(manifest_field "$id" '.mcp' '')"
  [[ -n "$spec" ]] || die "component '${id}': .mcp spec is required"
  [[ -n "$harness" ]] || die "component '${id}': mcp-server is harness-scoped"

  if ! harness_detect "$harness"; then
    log_warn "${harness} is not installed; skipping MCP registration of ${id}"
    return 0
  fi

  local kind
  kind="$(printf '%s' "$spec" | jq -r '.type // "stdio"')"
  cap="mcp-${kind}"
  if ! harness_supports "$harness" "$cap"; then
    log_warn "$(harness_name "$harness") does not support ${cap} servers"
    state_write "$id" "$harness" "n/a" "mcp-server" "manual"
    return 0
  fi

  if harness_mcp_has "$harness" "$server"; then
    log_debug "${id}: MCP server '${server}' already registered in ${harness}"
    return 0
  fi

  # Expand ${VAR} references from the environment so secrets (API keys) stay
  # out of the manifest and out of git.
  local resolved
  resolved="$(printf '%s' "$spec" | envsubst)" || return $?

  log_info "registering MCP server '${server}' with $(harness_name "$harness")"
  harness_mcp_add "$harness" "$server" "$resolved" || return $?
  rollback_record "mcp ${harness} ${server}"
}

backend_mcp_server_remove() {
  local id="$1" harness="${2:-}"
  local server
  server="$(manifest_field "$id" '.server' "$id")"
  harness_detect "$harness" || return 0
  harness_mcp_has "$harness" "$server" || return 0
  harness_mcp_remove "$harness" "$server"
}

backend_mcp_server_update() {
  # Registration is declarative: rewrite it so manifest changes take effect.
  local id="$1" harness="${2:-}"
  backend_mcp_server_remove "$id" "$harness"
  backend_mcp_server_install "$id" "$harness"
}

backend_mcp_server_version() { printf 'registered'; }
