#!/usr/bin/env bats

load helpers

setup() {
  setup_suite_env
  RESET_ROOT="$BATS_TEST_TMPDIR/reset"
  RESET_HOME="$RESET_ROOT/home"
  RESET_LOG="$RESET_ROOT/agent-commands.log"
  RESET_BACKUP="$RESET_ROOT/backup"
  mkdir -p "$RESET_ROOT"
  cp -a "$ROOT/tests/fixtures/reset-home" "$RESET_HOME"
  : >"$RESET_LOG"
}

@test "reset applies to all three agents, backs up, and preserves protected data" {
  run env \
    HOME="$RESET_HOME" \
    XDG_CONFIG_HOME="$RESET_HOME/.config" \
    XDG_CACHE_HOME="$RESET_HOME/.cache" \
    XDG_STATE_HOME="$RESET_HOME/.local/state" \
    XDG_DATA_HOME="$RESET_HOME/.local/share" \
    XDG_BIN_HOME="$RESET_HOME/.local/bin" \
    AI_DRY_RUN=0 \
    AI_ASSUME_YES=1 \
    AI_RESET_BACKUP_DIR="$RESET_BACKUP" \
    FAKE_AGENT_LOG="$RESET_LOG" \
    PATH="$ROOT/tests/fixtures/reset-bin:$PATH" \
    "$ROOT/bin/aistack" reset --apply --yes --no-color

  [ "$status" -eq 0 ]
  [ -f "$RESET_BACKUP/claude-code/claude.json" ]
  [ -f "$RESET_BACKUP/codex/config.toml" ]
  [ -f "$RESET_BACKUP/opencode/opencode.jsonc" ]

  [ -f "$RESET_HOME/.codex/skills/.system/KEEP" ]
  [ ! -e "$RESET_HOME/.codex/skills/demo" ]
  [ ! -e "$RESET_HOME/.agents/skills/shared-demo" ]
  [ ! -e "$RESET_HOME/.claude/skills/demo" ]
  [ ! -e "$RESET_HOME/.config/opencode/skills/demo" ]
  [ ! -e "$RESET_HOME/.config/opencode/plugins/demo.ts" ]
  [ ! -e "$RESET_HOME/.config/opencode/tools/demo.ts" ]
  [ ! -e "$RESET_HOME/.cache/opencode/node_modules" ]

  run jq -e '.theme == "dark" and (has("mcpServers") | not)' \
    "$RESET_HOME/.claude.json"
  [ "$status" -eq 0 ]
  run jq -e '.preferredNotifChannel == "terminal_bell"
             and (has("enabledPlugins") | not)' \
    "$RESET_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  run jq -e '.theme == "fixture"
             and (has("plugin") | not)
             and (has("mcp") | not)' \
    "$RESET_HOME/.config/opencode/opencode.jsonc"
  [ "$status" -eq 0 ]

  grep -q 'plugin uninstall demo@fixture' "$RESET_LOG"
  grep -q 'plugin remove demo@fixture' "$RESET_LOG"
  grep -q 'mcp remove legacy_codex' "$RESET_LOG"
  grep -q 'uninstall --yes --keep-cli' "$RESET_LOG"
}
