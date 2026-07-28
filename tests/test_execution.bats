#!/usr/bin/env bats
# Failure propagation and user-space runtime selection.

load helpers

setup() {
  setup_suite_env
  export AI_DRY_RUN=0
  export AI_LOG_FILE=""
}

@test "log_cmd preserves the command's real exit status" {
  run log_cmd bash -c 'printf "boom\n" >&2; exit 23'
  [ "$status" -eq 23 ]
  [[ "$output" == *"command failed (rc=23)"* ]]
  [[ "$output" == *"boom"* ]]
}

@test "node_runtime_activate selects fnm instead of system npm" {
  local fake_home="$BATS_TEST_TMPDIR/home"
  local fake_data="$fake_home/.local/share"
  local fake_bin="$fake_data/fnm/aliases/default/bin"
  mkdir -p "$fake_bin"
  ln -s /bin/true "$fake_bin/node"
  ln -s /bin/true "$fake_bin/npm"

  HOME="$fake_home"
  XDG_DATA_HOME="$fake_data"
  PATH="/usr/bin:/bin"
  export HOME XDG_DATA_HOME PATH

  node_runtime_activate
  [ "$(command -v npm)" = "$fake_bin/npm" ]
}

@test "npm backend propagates an npm install failure" {
  backend_load npm-global
  _npm_require() { return 0; }
  npm_global_installed() { return 1; }
  lockfile_version() { return 0; }
  run_user() { return 74; }
  rollback_record() { return 0; }

  run backend_npm_global_install codegraph
  [ "$status" -eq 74 ]
}

@test "apt refresh propagates failure and does not mark the index fresh" {
  backend_load apt
  run_priv() { return 73; }
  apt_probe() {
    _APT_UPDATED=0
    apt_refresh
    local rc=$?
    printf 'updated=%s\n' "$_APT_UPDATED"
    return "$rc"
  }

  run apt_probe
  [ "$status" -eq 73 ]
  [[ "$output" == *"updated=0"* ]]
  [[ "$output" == *"will not modify unrelated APT repositories"* ]]
}

@test "Superpowers passes its git package spec to OpenCode" {
  backend_load claude-plugin
  harness_detect() { return 0; }
  harness_plugin_has() { return 1; }
  harness_supports() { return 0; }
  harness_name() { printf 'OpenCode'; }
  harness_plugin_add() { printf '%s\n' "$3"; }
  rollback_record() { return 0; }

  run backend_claude_plugin_install superpowers opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *"superpowers@git+https://github.com/obra/superpowers.git"* ]]
}
