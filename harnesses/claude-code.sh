#!/usr/bin/env bash
# harnesses/claude-code.sh — adapter for Anthropic's Claude Code.
#
# Claude Code is the best-behaved of the three for automation: it exposes
# non-interactive `claude plugin` and `claude mcp` subcommands, so we almost
# never have to edit its JSON by hand. File editing is kept only as a fallback
# for older builds.
#
# shellcheck shell=bash

claude_code_name() { printf 'Claude Code'; }

claude_code_detect() { have claude; }

claude_code_version() {
  have claude || return 1
  claude --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

claude_code_config_path() { printf '%s/.claude.json' "$HOME"; }
claude_code_config_format() { printf 'json'; }

claude_code_supports() {
  case "$1" in
    plugin | skill | mcp-stdio | mcp-http) return 0 ;;
    *) return 1 ;;
  esac
}

# --- MCP ---------------------------------------------------------------------

_claude_code_has_mcp_cli() { claude mcp --help >/dev/null 2>&1; }

# claude_code_mcp_add <name> <spec-json>
# spec-json: {"type":"stdio","command":"npx","args":[...],"env":{...}}
#        or  {"type":"http","url":"https://...","headers":{...}}
claude_code_mcp_add() {
  local name="$1" spec="$2"
  local kind
  kind="$(printf '%s' "$spec" | jq -r '.type // "stdio"')"

  if _claude_code_has_mcp_cli; then
    if [[ "$kind" == "http" ]]; then
      local url
      url="$(printf '%s' "$spec" | jq -r '.url')"
      local -a args=(mcp add --transport http --scope user "$name" "$url")
      local hdr
      while IFS= read -r hdr; do
        [[ -z "$hdr" ]] && continue
        args+=(--header "$hdr")
      done < <(printf '%s' "$spec" | jq -r '(.headers // {}) | to_entries[] | "\(.key): \(.value)"')
      run_user claude "${args[@]}" && return 0
    else
      local cmd
      cmd="$(printf '%s' "$spec" | jq -r '.command')"
      local -a args=(mcp add --scope user "$name")
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
      run_user claude "${args[@]}" && return 0
    fi
    log_warn "claude mcp add failed; falling back to config file"
  fi

  harness_json_merge "$(claude_code_config_path)" \
    '.mcpServers = ((.mcpServers // {}) + {($n): $s})' \
    --arg n "$name" --argjson s "$spec"
}

claude_code_mcp_remove() {
  local name="$1"
  if _claude_code_has_mcp_cli; then
    run_user claude mcp remove --scope user "$name" && return 0
  fi
  harness_json_merge "$(claude_code_config_path)" \
    'if .mcpServers then .mcpServers |= del(.[$n]) else . end' --arg n "$name"
}

claude_code_mcp_has() {
  local name="$1"
  if _claude_code_has_mcp_cli && claude mcp list 2>/dev/null | grep -qE "(^|[[:space:]])${name}([[:space:]]|:|$)"; then
    return 0
  fi
  local cfg
  cfg="$(claude_code_config_path)"
  [[ -f "$cfg" ]] || return 1
  [[ "$(harness_jsonc_read "$cfg" | jq -r --arg n "$name" '.mcpServers // {} | has($n)')" == "true" ]]
}

# --- Plugins -----------------------------------------------------------------

# claude_code_plugin_add <marketplace> <plugin>
# Both Superpowers and Caveman document exactly this non-interactive pair.
claude_code_plugin_add() {
  local marketplace="$1" plugin="$2"
  run_user claude plugin marketplace add "$marketplace" ||
    log_warn "marketplace '${marketplace}' may already be registered"
  local short="${marketplace##*/}"
  run_user claude plugin install "${plugin}@${short}"
}

claude_code_plugin_remove() {
  local plugin="$1"
  run_user claude plugin uninstall "$plugin"
}

claude_code_plugin_has() {
  local plugin="$1"
  claude plugin list 2>/dev/null | grep -qiE "(^|[[:space:]/@])${plugin}([[:space:]@]|$)" && return 0
  # Registry fallback. Third-party installers (claude-mem, for one) write this
  # file directly instead of shelling out to `claude plugin install`, so the
  # CLI listing alone is not authoritative. Keys are "<plugin>@<marketplace>".
  local registry="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
  if [[ -f "$registry" ]] && jq -e --arg p "$plugin" '
      (.plugins // {}) | keys[] | select(. == $p or startswith($p + "@"))
    ' "$registry" >/dev/null 2>&1; then
    return 0
  fi
  # Last fallback: the on-disk plugin directory.
  [[ -d "$HOME/.claude/plugins/${plugin}" ]]
}

# --- Skills ------------------------------------------------------------------

# claude_code_skill_add <repo> [skill]
# Without a skill name the registry installs every skill in the repository,
# which is rarely what a manifest row means. `--skill` narrows it to one.
claude_code_skill_add() {
  local repo="$1" skill="${2:-}"
  local -a args=(--yes skills@latest add "$repo" --global --agent claude-code --yes)
  [[ -n "$skill" ]] && args+=(--skill "$skill")
  run_user npx "${args[@]}"
}

claude_code_skill_remove() {
  run_user npx --yes skills@latest remove "$1" --global --agent claude-code --yes
}

claude_code_skill_has() {
  [[ -d "$HOME/.claude/skills/$1" || -L "$HOME/.claude/skills/$1" ]]
}

# --- Telemetry ---------------------------------------------------------------

claude_code_telemetry_optout_env() {
  printf 'DISABLE_TELEMETRY=1\nCLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1\n'
}
