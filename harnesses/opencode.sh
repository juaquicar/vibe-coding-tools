#!/usr/bin/env bash
# harnesses/opencode.sh — adapter for OpenCode.
#
# OpenCode's config is JSON/JSONC (NOT TOML — that confusion is widespread and
# has produced a lot of broken tutorials). It ships `opencode mcp add` and
# `opencode plugin`, so automation is straightforward.
#
# The one component we cannot drive here is Superpowers, whose OpenCode install
# path is "ask the agent to fetch and follow an INSTALL.md". That is an
# LLM-driven install, not a scriptable one, and we refuse to launder it into a
# fake success. It is reported MANUAL.
#
# shellcheck shell=bash

opencode_name() { printf 'OpenCode'; }

opencode_detect() { have opencode; }

opencode_version() {
  have opencode || return 1
  opencode --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

opencode_config_path() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  if [[ -n "${OPENCODE_CONFIG:-}" ]]; then
    printf '%s' "$OPENCODE_CONFIG"
  elif [[ -f "$dir/opencode.jsonc" ]]; then
    printf '%s/opencode.jsonc' "$dir"
  else
    printf '%s/opencode.json' "$dir"
  fi
}
opencode_config_format() { printf 'jsonc'; }

opencode_supports() {
  case "$1" in
    plugin | skill | mcp-stdio | mcp-http) return 0 ;;
    *) return 1 ;;
  esac
}

# --- MCP ---------------------------------------------------------------------

_opencode_has_mcp_cli() { opencode mcp --help >/dev/null 2>&1; }

opencode_mcp_add() {
  local name="$1" spec="$2"
  local kind
  kind="$(printf '%s' "$spec" | jq -r '.type // "stdio"')"

  if _opencode_has_mcp_cli; then
    if [[ "$kind" == "http" ]]; then
      local url
      url="$(printf '%s' "$spec" | jq -r '.url')"
      run_user opencode mcp add "$name" --url "$url" && return 0
    else
      local cmd
      cmd="$(printf '%s' "$spec" | jq -r '.command')"
      local -a args=(mcp add "$name" -- "$cmd")
      local a
      while IFS= read -r a; do
        [[ -z "$a" ]] && continue
        args+=("$a")
      done < <(printf '%s' "$spec" | jq -r '(.args // [])[]')
      run_user opencode "${args[@]}" && return 0
    fi
    log_warn "opencode mcp add failed; writing opencode.json directly"
  fi

  # OpenCode's schema uses local/remote rather than stdio/http.
  local oc_spec
  oc_spec="$(printf '%s' "$spec" | jq -c '
    if (.type // "stdio") == "http"
    then {type: "remote", url: .url, enabled: true}
         + (if (.headers // {}) == {} then {} else {headers: .headers} end)
    else {type: "local", command: ([.command] + (.args // [])), enabled: true}
         + (if (.env // {}) == {} then {} else {environment: .env} end)
    end')"
  harness_json_merge "$(opencode_config_path)" \
    '.["$schema"] = (.["$schema"] // "https://opencode.ai/config.json")
     | .mcp = ((.mcp // {}) + {($n): $s})' \
    --arg n "$name" --argjson s "$oc_spec"
}

opencode_mcp_remove() {
  local name="$1"
  if _opencode_has_mcp_cli; then
    run_user opencode mcp remove "$name" && return 0
  fi
  harness_json_merge "$(opencode_config_path)" \
    'if .mcp then .mcp |= del(.[$n]) else . end' --arg n "$name"
}

opencode_mcp_has() {
  local name="$1" cfg
  cfg="$(opencode_config_path)"
  [[ -f "$cfg" ]] || return 1
  [[ "$(harness_jsonc_read "$cfg" | jq -r --arg n "$name" '.mcp // {} | has($n)')" == "true" ]]
}

# --- Plugins -----------------------------------------------------------------

opencode_plugin_add() {
  local _marketplace="$1" plugin="$2"
  run_user opencode plugin "$plugin" --global
}

opencode_plugin_remove() {
  local plugin="$1" cfg
  cfg="$(opencode_config_path)"
  harness_json_merge "$cfg" '
    def without_plugin:
      map(select(type != "string"
                 or (. != $p and (startswith($p + "@") | not))));
    if .plugin then .plugin |= without_plugin else . end
    | if .plugins then .plugins |= without_plugin else . end
  ' --arg p "$plugin"
}

opencode_plugin_has() {
  local plugin="$1" cfg
  cfg="$(opencode_config_path)"
  if [[ -f "$cfg" ]] && [[ "$(harness_jsonc_read "$cfg" | jq -r --arg p "$plugin" '
      [(.plugin // [])[], (.plugins // [])[]]
      | any(type == "string" and (. == $p or startswith($p + "@")))
    ')" == "true" ]]; then
    return 0
  fi
  [[ -e "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/${plugin}" ]]
}

# --- Skills ------------------------------------------------------------------

opencode_skill_add() {
  local repo="$1"
  run_user npx --yes skills@latest add "$repo" --global --agent opencode --yes
}

opencode_skill_remove() {
  run_user npx --yes skills@latest remove "$1" --global --agent opencode --yes
}

opencode_skill_has() {
  local skill="$1" dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
  # skills@latest treats OpenCode as a universal agent: global skills live in
  # the canonical ~/.agents/skills directory instead of being symlinked into
  # ~/.config/opencode/skills. Keep the latter for older/copied installs.
  [[ -d "$dir/$skill" || -L "$dir/$skill" ||
    -d "$HOME/.agents/skills/$skill" || -L "$HOME/.agents/skills/$skill" ]]
}

opencode_telemetry_optout_env() { printf 'DO_NOT_TRACK=1\n'; }
