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
