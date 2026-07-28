#!/usr/bin/env bats
# End-to-end CLI behaviour, all in dry-run.

load helpers

setup() { setup_suite_env; }

AI() { "$ROOT/bin/aistack" "$@"; }

@test "version prints" {
  run AI version
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'vibe-coding-tools'
}

@test "help prints and lists the commands" {
  run AI help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'install'
  echo "$output" | grep -q 'doctor'
}

@test "an unknown command fails" {
  run AI frobnicate
  [ "$status" -ne 0 ]
}

@test "list shows components and profiles" {
  run AI list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'claude-code'
  echo "$output" | grep -q 'developer'
}

@test "search finds a component" {
  run AI search caveman
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'caveman'
}

@test "why explains the graph" {
  run AI why superpowers
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'claude-code'
}

@test "a dry-run install changes nothing" {
  run AI install minimal --dry-run --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'dry run'
}

@test "harness list runs" {
  run AI harness list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'claude-code'
}

@test "reset is preview-only by default" {
  run AI reset
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'preview only'
  echo "$output" | grep -q 'Claude Code'
  echo "$output" | grep -q 'Codex'
  echo "$output" | grep -q 'OpenCode'
}

@test "an unknown profile is rejected" {
  run AI install nonexistent-profile-xyz --dry-run
  [ "$status" -ne 0 ]
}
