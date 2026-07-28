#!/usr/bin/env bats
# State and lockfile behaviour.

load helpers

setup() {
  setup_suite_env
  export AI_DRY_RUN=0
  rm -f "$AI_STATE_FILE"
  state_init
}

teardown() { rm -f "$AI_STATE_FILE" "$AI_LOCKFILE"; }

@test "state starts empty and valid" {
  run jq -e '.entries == {}' "$AI_STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "a component can be recorded and read back" {
  state_write ripgrep system 14.1.0 apt installed
  run state_is_installed ripgrep system
  [ "$status" -eq 0 ]
  [ "$(state_get ripgrep system version)" = "14.1.0" ]
}

@test "the same component is tracked separately per harness" {
  state_write caveman claude-code 1.9.1 claude-plugin installed
  state_write caveman opencode n/a agent-skill manual
  [ "$(state_get caveman claude-code status)" = "installed" ]
  [ "$(state_get caveman opencode status)" = "manual" ]
  run state_is_installed caveman opencode
  [ "$status" -ne 0 ]
}

@test "forgetting one harness leaves the others intact" {
  state_write caveman claude-code 1.0 claude-plugin installed
  state_write caveman codex 1.0 agent-skill installed
  state_forget caveman codex
  run state_is_installed caveman claude-code
  [ "$status" -eq 0 ]
  run state_is_installed caveman codex
  [ "$status" -ne 0 ]
}

@test "forgetting with no harness drops every row" {
  state_write caveman claude-code 1.0 claude-plugin installed
  state_write caveman codex 1.0 agent-skill installed
  state_forget caveman
  [ "$(state_harnesses_for caveman | wc -l)" -eq 0 ]
}

@test "failed components remain visible to repair" {
  state_write caveman opencode unknown claude-plugin failed
  [ "$(state_failed_components)" = "caveman" ]
}

@test "the lockfile records only installed components" {
  state_write node system 22.0.0 none installed
  state_write superpowers opencode n/a claude-plugin manual
  lockfile_write
  run jq -e '[.components[].component] | index("node")' "$AI_LOCKFILE"
  [ "$status" -eq 0 ]
  run jq -e '[.components[].component] | index("superpowers")' "$AI_LOCKFILE"
  [ "$status" -ne 0 ]
}

@test "a pinned version can be read back from the lockfile" {
  state_write node system 22.11.0 none installed
  lockfile_write
  [ "$(lockfile_version node)" = "22.11.0" ]
}
