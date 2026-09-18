#!/usr/bin/env bats
# Harness-specific path and format behaviour.

load helpers

setup() {
  setup_suite_env
}

@test "OpenCode sees global skills in the universal registry" {
  local fake_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fake_home/.agents/skills/caveman"
  HOME="$fake_home"
  XDG_CONFIG_HOME="$fake_home/.config"
  export HOME XDG_CONFIG_HOME

  harness_load opencode
  run opencode_skill_has caveman
  [ "$status" -eq 0 ]
}

@test "OpenCode still sees skills copied into its legacy global directory" {
  local fake_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fake_home/.config/opencode/skills/caveman"
  HOME="$fake_home"
  XDG_CONFIG_HOME="$fake_home/.config"
  export HOME XDG_CONFIG_HOME

  harness_load opencode
  run opencode_skill_has caveman
  [ "$status" -eq 0 ]
}

@test "OpenCode recognizes a git-backed plugin spec by package name" {
  local fake_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fake_home/.config/opencode"
  printf '%s\n' \
    '{"plugin":["superpowers@git+https://github.com/obra/superpowers.git"]}' \
    >"$fake_home/.config/opencode/opencode.json"
  HOME="$fake_home"
  XDG_CONFIG_HOME="$fake_home/.config"
  export HOME XDG_CONFIG_HOME

  harness_load opencode
  run opencode_plugin_has superpowers
  [ "$status" -eq 0 ]
}

@test "OpenCode removes a git-backed plugin without touching preferences" {
  local fake_home="$BATS_TEST_TMPDIR/home"
  local cfg="$fake_home/.config/opencode/opencode.json"
  mkdir -p "$(dirname "$cfg")"
  printf '%s\n' \
    '{"theme":"dark","plugin":["other","superpowers@git+https://github.com/obra/superpowers.git"]}' \
    >"$cfg"
  HOME="$fake_home"
  XDG_CONFIG_HOME="$fake_home/.config"
  AI_DRY_RUN=0
  export HOME XDG_CONFIG_HOME AI_DRY_RUN

  harness_load opencode
  opencode_plugin_remove superpowers
  run jq -e '.theme == "dark" and .plugin == ["other"]' "$cfg"
  [ "$status" -eq 0 ]
}

@test "the TOML writer quotes keys that are not bare-key safe" {
  # Regression: Codex plugin tables are named after plugin specs such as
  # "claude-mem@claude-mem-local". Emitting that header unquoted produced a
  # config.toml that Codex could no longer parse.
  local cfg="$BATS_TEST_TMPDIR/config.toml"
  printf '%s\n' '[plugins."claude-mem@claude-mem-local"]' 'enabled = true' >"$cfg"

  printf '%s' '{"model":"gpt-5.6-terra"}' |
    python3 "$ROOT/lib/toml_edit.py" set "$cfg"

  run python3 -c "
import sys, tomllib
with open(sys.argv[1], 'rb') as fh:
    data = tomllib.load(fh)
assert data['plugins']['claude-mem@claude-mem-local']['enabled'] is True
assert data['model'] == 'gpt-5.6-terra'
" "$cfg"
  [ "$status" -eq 0 ]
}

@test "a TOML patch leaves MCP servers and unrelated tables alone" {
  local cfg="$BATS_TEST_TMPDIR/config.toml"
  printf '%s\n' 'model = "old"' '' '[mcp_servers.pycharm]' \
    'url = "http://127.0.0.1:64462/stream"' >"$cfg"

  printf '%s' '{"model":"gpt-5.6-terra","profiles":{"fast":{"model":"gpt-5.6-luna"}}}' |
    python3 "$ROOT/lib/toml_edit.py" set "$cfg"

  run python3 -c "
import sys, tomllib
with open(sys.argv[1], 'rb') as fh:
    data = tomllib.load(fh)
assert data['mcp_servers']['pycharm']['url'].endswith('/stream')
assert data['profiles']['fast']['model'] == 'gpt-5.6-luna'
assert data['model'] == 'gpt-5.6-terra'
" "$cfg"
  [ "$status" -eq 0 ]
}

@test "deleting the last MCP server prunes the empty table" {
  local cfg="$BATS_TEST_TMPDIR/config.toml"
  printf '%s\n' 'model = "x"' '' '[mcp_servers.context7]' 'url = "https://example"' >"$cfg"

  python3 "$ROOT/lib/toml_edit.py" delete "$cfg" mcp_servers context7

  run grep -c 'mcp_servers' "$cfg"
  [ "$output" = "0" ]
}

@test "a skill selector reaches the registry CLI" {
  harness_load claude-code
  run claude_code_skill_add mattpocock/skills grill-me
  [[ "$output" == *"--skill grill-me"* ]]
}

@test "OpenCode recognises a plugin registered as a local bundle path" {
  local fake_home="$BATS_TEST_TMPDIR/oc-home"
  mkdir -p "$fake_home/.config/opencode"
  printf '%s\n' '{"plugin":["./plugins/claude-mem.js"]}' \
    >"$fake_home/.config/opencode/opencode.json"
  HOME="$fake_home"
  XDG_CONFIG_HOME="$fake_home/.config"
  export HOME XDG_CONFIG_HOME

  harness_load opencode
  run opencode_plugin_has claude-mem
  [ "$status" -eq 0 ]
}

@test "Claude Code sees plugins written straight into its registry" {
  local fake_home="$BATS_TEST_TMPDIR/cc-home"
  mkdir -p "$fake_home/.claude/plugins"
  printf '%s\n' '{"version":2,"plugins":{"claude-mem@thedotmack":[{"scope":"user"}]}}' \
    >"$fake_home/.claude/plugins/installed_plugins.json"
  HOME="$fake_home"
  CLAUDE_CONFIG_DIR="$fake_home/.claude"
  export HOME CLAUDE_CONFIG_DIR

  harness_load claude-code
  run claude_code_plugin_has claude-mem
  [ "$status" -eq 0 ]
}
