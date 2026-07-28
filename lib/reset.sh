#!/usr/bin/env bash
# lib/reset.sh — reset global agent extensions without removing the agents.
#
# The reset is intentionally narrower than uninstalling a workstation:
#   * removes user-installed skills, plugins, MCP registrations and OpenCode
#     custom tools;
#   * keeps Claude Code, Codex and OpenCode themselves;
#   * keeps authentication, conversations and unrelated preferences;
#   * never touches project-local configuration outside this checkout.
#
# Preview is the default. The caller must pass --apply and confirm (or --yes)
# before any destructive operation starts.
#
# shellcheck shell=bash

[[ -n "${_AI_RESET_SH:-}" ]] && return 0
_AI_RESET_SH=1

RESET_BACKUP_DIR=""
RESET_ERRORS=0

reset_targets() {
  local spec="${HARNESS_SPEC:-all}"
  if [[ -z "$spec" || "$spec" == "all" || "$spec" == "any" ]]; then
    harness_all
    return 0
  fi

  local h
  local IFS=','
  for h in $spec; do
    h="${h// /}"
    [[ -z "$h" ]] && continue
    harness_exists "$h" ||
      die "unknown harness '${h}' (available: $(harness_all | tr '\n' ' '))"
    printf '%s\n' "$h"
  done
}

reset_opencode_configs() {
  printf '%s\n' \
    "$XDG_CONFIG_HOME/opencode/opencode.json" \
    "$XDG_CONFIG_HOME/opencode/opencode.jsonc"
}

reset_plan_harness() {
  case "$1" in
    claude-code)
      printf '  %-12s %s\n' "Claude Code" \
        "user plugins, user MCPs, and skills in $HOME/.claude/skills"
      ;;
    codex)
      printf '  %-12s %s\n' "Codex" \
        "installed plugins, MCPs, and user skills (system skills are kept)"
      ;;
    opencode)
      printf '  %-12s %s\n' "OpenCode" \
        "global plugins, MCPs, skills, custom tools, and plugin package cache"
      ;;
  esac
}

reset_path_allowed() {
  local raw="$1" resolved base
  resolved="$(realpath -m -- "$raw")"
  [[ "$resolved" != "/" ]] || return 1

  for base in "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"; do
    base="$(realpath -m -- "$base")"
    [[ "$resolved" != "$base" && "$resolved" == "$base/"* ]] && return 0
  done
  return 1
}

reset_backup_copy() {
  local src="$1" rel="$2" dest
  [[ -e "$src" || -L "$src" ]] || return 0
  reset_path_allowed "$src" || die "refusing to back up unexpected path: $src"
  dest="$RESET_BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -a -- "$src" "$dest"
}

reset_backup_harness() {
  local h="$1" cfg
  case "$h" in
    claude-code)
      reset_backup_copy "$HOME/.claude.json" "claude-code/claude.json"
      reset_backup_copy "$HOME/.claude/settings.json" "claude-code/settings.json"
      reset_backup_copy "$HOME/.claude/skills" "claude-code/skills"
      reset_backup_copy "$HOME/.claude/plugins/installed_plugins.json" \
        "claude-code/plugins/installed_plugins.json"
      reset_backup_copy "$HOME/.claude/plugins/data" "claude-code/plugins/data"
      ;;
    codex)
      reset_backup_copy "$HOME/.codex/config.toml" "codex/config.toml"
      reset_backup_copy "$HOME/.codex/skills" "codex/skills"
      reset_backup_copy "$HOME/.agents/skills" "shared/agents-skills"
      ;;
    opencode)
      while IFS= read -r cfg; do
        reset_backup_copy "$cfg" "opencode/$(basename "$cfg")"
      done < <(reset_opencode_configs)
      reset_backup_copy "$XDG_CONFIG_HOME/opencode/skills" "opencode/skills"
      reset_backup_copy "$XDG_CONFIG_HOME/opencode/plugins" "opencode/plugins"
      reset_backup_copy "$XDG_CONFIG_HOME/opencode/tools" "opencode/tools"
      ;;
  esac
}

reset_empty_dir() {
  local dir="$1" keep="${2:-}" entry
  [[ -d "$dir" ]] || return 0
  reset_path_allowed "$dir" || die "refusing to clean unexpected path: $dir"

  while IFS= read -r -d '' entry; do
    [[ -n "$keep" && "$(basename "$entry")" == "$keep" ]] && continue
    rm -rf -- "$entry"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
}

reset_json_delete() {
  local path="$1" filter="$2"
  [[ -f "$path" ]] || return 0
  harness_json_merge "$path" "$filter"
}

reset_claude_plugins() {
  have claude || {
    log_warn "Claude Code CLI not found; only its on-disk skills/config will be cleaned"
    return 0
  }

  local json id
  if ! json="$(claude plugin list --json 2>/dev/null)"; then
    log_warn "could not list Claude Code plugins"
    RESET_ERRORS=$((RESET_ERRORS + 1))
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! claude plugin uninstall "$id" --scope user --prune --yes; then
      log_warn "could not uninstall Claude Code plugin: $id"
      RESET_ERRORS=$((RESET_ERRORS + 1))
    fi
  done < <(printf '%s' "$json" | jq -r '
    .[]?
    | if type == "string" then .
      elif ((.scope // "user") == "user") then
        (.id // .pluginId // .plugin_id // .name // empty)
      else empty
      end')
}

reset_codex_plugins() {
  have codex || {
    log_warn "Codex CLI not found; only its on-disk skills will be cleaned"
    return 0
  }
  codex plugin remove --help >/dev/null 2>&1 || {
    log_warn "this Codex version cannot remove plugins non-interactively"
    RESET_ERRORS=$((RESET_ERRORS + 1))
    return 0
  }

  local json id
  if ! json="$(codex plugin list --json 2>/dev/null)"; then
    log_warn "could not list Codex plugins"
    RESET_ERRORS=$((RESET_ERRORS + 1))
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! codex plugin remove "$id" --json >/dev/null; then
      log_warn "could not remove Codex plugin: $id"
      RESET_ERRORS=$((RESET_ERRORS + 1))
    fi
  done < <(printf '%s' "$json" | jq -r '
    .installed[]?
    | if type == "string" then .
      elif (.id // .pluginId // .plugin_id) then
        (.id // .pluginId // .plugin_id)
      elif ((.name // .plugin_name) and (.marketplace // .marketplace_name)) then
        "\(.name // .plugin_name)@\(.marketplace // .marketplace_name)"
      else empty
      end')
}

reset_codex_mcps() {
  have codex || return 0
  local json name
  if ! json="$(codex mcp list --json 2>/dev/null)"; then
    log_warn "could not list Codex MCP servers"
    RESET_ERRORS=$((RESET_ERRORS + 1))
    return 0
  fi

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! codex mcp remove "$name"; then
      log_warn "could not remove Codex MCP server: $name"
      RESET_ERRORS=$((RESET_ERRORS + 1))
    fi
  done < <(printf '%s' "$json" | jq -r '.[]? | .name // empty')
}

reset_apply_harness() {
  local h="$1" cfg
  log_step "Resetting $(harness_name "$h")"

  case "$h" in
    claude-code)
      reset_claude_plugins
      reset_json_delete "$HOME/.claude.json" 'del(.mcpServers)'
      reset_json_delete "$HOME/.claude/settings.json" \
        'del(.mcpServers, .enabledPlugins)'
      reset_empty_dir "$HOME/.claude/skills"
      ;;
    codex)
      reset_codex_plugins
      reset_codex_mcps
      reset_empty_dir "$HOME/.codex/skills" ".system"
      reset_empty_dir "$HOME/.agents/skills"
      ;;
    opencode)
      while IFS= read -r cfg; do
        reset_json_delete "$cfg" 'del(.mcp, .plugin, .plugins)'
      done < <(reset_opencode_configs)
      reset_empty_dir "$XDG_CONFIG_HOME/opencode/skills"
      reset_empty_dir "$XDG_CONFIG_HOME/opencode/plugins"
      reset_empty_dir "$XDG_CONFIG_HOME/opencode/tools"
      if [[ -d "$XDG_CACHE_HOME/opencode/node_modules" ]]; then
        reset_path_allowed "$XDG_CACHE_HOME/opencode/node_modules" ||
          die "refusing to clean unexpected OpenCode cache path"
        rm -rf -- "$XDG_CACHE_HOME/opencode/node_modules"
      fi
      ;;
  esac

  if [[ -f "$AI_STATE_FILE" ]]; then
    local id
    while IFS= read -r id; do
      manifest_is_harness_scoped "$id" || continue
      state_forget "$id" "$h"
    done < <(manifest_ids)
  fi
  log_ok "$(harness_name "$h") reset"
}

agent_reset() {
  local apply=0 arg h stamp
  for arg in "${ARGS[@]+"${ARGS[@]}"}"; do
    case "$arg" in
      --apply) apply=1 ;;
      *) die "usage: ${AI_CLI_NAME} reset [--apply] [--harness=<spec>] [--yes]" ;;
    esac
  done

  log_step "Agent extension reset plan"
  while IFS= read -r h; do
    reset_plan_harness "$h"
  done < <(reset_targets)
  printf '\n  Keeps agent binaries, authentication, conversations, preferences,\n'
  printf '  Codex system skills, and system/developer packages.\n\n'

  if ((apply == 0)) || [[ "$AI_DRY_RUN" == "1" ]]; then
    log_info "preview only; run '${AI_CLI_NAME} reset --apply' to perform the reset"
    return 0
  fi

  if [[ "$AI_ASSUME_YES" != "1" ]]; then
    [[ -t 0 ]] ||
      die "refusing a non-interactive reset without --yes; run the preview first"
    confirm "Back up and remove these global agent extensions?" || {
      log_info "reset cancelled"
      return 0
    }
  fi

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  RESET_BACKUP_DIR="${AI_RESET_BACKUP_DIR:-$AI_STATE_DIR/backups/reset-${stamp}-$$}"
  mkdir -p "$RESET_BACKUP_DIR"
  chmod 700 "$RESET_BACKUP_DIR"

  log_step "Backing up agent configuration"
  while IFS= read -r h; do
    reset_backup_harness "$h"
  done < <(reset_targets)
  printf 'created=%s\n' "$stamp" >"$RESET_BACKUP_DIR/RESET_INFO"
  chmod 600 "$RESET_BACKUP_DIR/RESET_INFO"
  log_ok "backup: $RESET_BACKUP_DIR"

  rollback_begin "reset"

  if have codegraph; then
    codegraph uninstall --yes --keep-cli ||
      log_warn "CodeGraph could not remove every agent integration"
  fi

  while IFS= read -r h; do
    reset_apply_harness "$h"
  done < <(reset_targets)

  [[ -f "$AI_STATE_FILE" ]] && lockfile_write
  rollback_commit

  if ((RESET_ERRORS > 0)); then
    log_warn "reset completed with ${RESET_ERRORS} cleanup error(s); backup kept at $RESET_BACKUP_DIR"
    exit 1
  fi
  log_ok "agent extensions reset; backup kept at $RESET_BACKUP_DIR"
}
