#!/usr/bin/env bash
# tests/helpers.bash — shared test setup.
# shellcheck shell=bash

setup_suite_env() {
  ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export ROOT
  export AI_NO_COLOR=1
  export AI_DRY_RUN=1
  export AI_ASSUME_YES=1
  # shellcheck source=../lib/common.sh
  . "$ROOT/lib/common.sh"
  . "$AI_LIB_DIR/version.sh"
  . "$AI_LIB_DIR/state.sh"
  . "$AI_LIB_DIR/manifest.sh"
  . "$AI_LIB_DIR/deps.sh"
  . "$AI_LIB_DIR/harness.sh"
  . "$AI_LIB_DIR/backend.sh"
  . "$AI_LIB_DIR/rollback.sh"
}
