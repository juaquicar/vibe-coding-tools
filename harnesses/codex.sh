#!/usr/bin/env bash
# harnesses/codex.sh — adapter for OpenAI's Codex CLI.
#
# Codex keeps MCP configuration in TOML, so `jq` cannot write it. We prefer the
# native `codex mcp` and `codex plugin` commands and retain a narrow Python TOML
# fallback for MCP configuration on older releases.
#
# shellcheck shell=bash

codex_name() { printf 'Codex CLI'; }

codex_detect() { have codex; }

codex_version() {
  have codex || return 1
  codex --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

codex_config_path() { printf '%s/.codex/config.toml' "$HOME"; }
codex_config_format() { printf 'toml'; }

codex_supports() {
  case "$1" in
    plugin | skill | mcp-stdio | mcp-http) return 0 ;;
    *) return 1 ;;
  esac
}

# --- MCP ---------------------------------------------------------------------

_codex_has_mcp_cli() { codex mcp --help >/dev/null 2>&1; }

codex_mcp_add() {
  local name="$1" spec="$2"
  local kind
  kind="$(printf '%s' "$spec" | jq -r '.type // "stdio"')"

  if _codex_has_mcp_cli; then
    if [[ "$kind" == "http" ]]; then
      local url
      url="$(printf '%s' "$spec" | jq -r '.url')"
      run_user codex mcp add "$name" --url "$url" && return 0
    else
      local cmd
      cmd="$(printf '%s' "$spec" | jq -r '.command')"
      local -a args=(mcp add "$name")
      local envpair
      while IFS= read -r envpair; do
        [[ -z "$envpair" ]] && continue
        args+=(--env "$envpair")
      done < <(printf '%s' "$spec" | jq -r '(.env // {}) | to_entries[] | "\(.key)=\(.value)"')
      args+=(-- "$cmd")
      local a
      while IFS= read -r a; do
        [[ -z "$a" ]] && continue
        args+=("$a")
      done < <(printf '%s' "$spec" | jq -r '(.args // [])[]')
      run_user codex "${args[@]}" && return 0
    fi
    log_warn "codex mcp add failed; writing config.toml directly"
  fi

  # TOML fallback. Normalise the spec into the shape Codex expects.
  local toml_spec
  toml_spec="$(printf '%s' "$spec" | jq -c '
    if (.type // "stdio") == "http"
    then {url: .url} + (if (.headers // {}) == {} then {} else {headers: .headers} end)
    else {command: .command, args: (.args // [])}
         + (if (.env // {}) == {} then {} else {env: .env} end)
    end')"
  harness_toml_mcp_write "$(codex_config_path)" "$name" "$toml_spec"
}

codex_mcp_remove() {
  local name="$1"
  if _codex_has_mcp_cli; then
    run_user codex mcp remove "$name" && return 0
  fi
  harness_toml_mcp_delete "$(codex_config_path)" "$name"
}

codex_mcp_has() {
  local name="$1" cfg
  cfg="$(codex_config_path)"
  if _codex_has_mcp_cli && codex mcp list 2>/dev/null | grep -qE "(^|[[:space:]])${name}([[:space:]]|:|$)"; then
    return 0
  fi
  [[ -f "$cfg" ]] || return 1
  grep -qE "^\[mcp_servers\.${name}\]" "$cfg"
}

# --- Plugins -----------------------------------------------------------------

_codex_plugin_selector() {
  local plugin="$1"
  codex plugin list --json 2>/dev/null | jq -r --arg p "$plugin" '
    .installed[]?
    | select(
        if type == "string" then
          (. == $p or startswith($p + "@"))
        else
          ((.name // .plugin_name // .id // .pluginId // .plugin_id) == $p
           or ((.id // .pluginId // .plugin_id // "") | startswith($p + "@")))
        end
      )
    | if type == "string" then .
      elif (.id // .pluginId // .plugin_id) then
        (.id // .pluginId // .plugin_id)
      elif ((.name // .plugin_name) and (.marketplace // .marketplace_name)) then
        "\(.name // .plugin_name)@\(.marketplace // .marketplace_name)"
      else empty
      end
    ' | head -n1
}

codex_plugin_add() {
  local marketplace="$1" plugin="$2" result marketplace_name
  codex plugin add --help >/dev/null 2>&1 || return 3

  if [[ "$AI_DRY_RUN" == "1" ]]; then
    marketplace_name="${marketplace##*/}"
    marketplace_name="${marketplace_name%.git}"
    run_user codex plugin marketplace add "$marketplace"
    run_user codex plugin add "$plugin" --marketplace "$marketplace_name"
    return 0
  fi

  result="$(codex plugin marketplace add "$marketplace" --json 2>/dev/null)" ||
    log_warn "Codex marketplace '${marketplace}' may already be configured"
  marketplace_name="$(printf '%s' "$result" |
    jq -r '.name // .marketplace_name // .marketplace.name // empty' 2>/dev/null)"
  [[ -n "$marketplace_name" ]] || marketplace_name="${marketplace##*/}"
  marketplace_name="${marketplace_name%.git}"

  run_user codex plugin add "$plugin" --marketplace "$marketplace_name"
}

codex_plugin_remove() {
  local selector
  selector="$(_codex_plugin_selector "$1")"
  [[ -n "$selector" ]] || return 0
  run_user codex plugin remove "$selector"
}

codex_plugin_has() {
  [[ -n "$(_codex_plugin_selector "$1")" ]]
}

# --- Skills ------------------------------------------------------------------

# codex_skill_add <repo> [skill]
codex_skill_add() {
  local repo="$1" skill="${2:-}"
  local -a args=(--yes skills@latest add "$repo" --global --agent codex --yes)
  [[ -n "$skill" ]] && args+=(--skill "$skill")
  run_user npx "${args[@]}"
}

codex_skill_remove() {
  run_user npx --yes skills@latest remove "$1" --global --agent codex --yes
}

codex_skill_has() {
  local skill="$1"
  [[ -d "$HOME/.codex/skills/$skill" || -L "$HOME/.codex/skills/$skill" ||
    -d "$HOME/.agents/skills/$skill" || -L "$HOME/.agents/skills/$skill" ]]
}

codex_telemetry_optout_env() { printf ''; }
