#!/usr/bin/env bash
# tests/run.sh — test entry point.
#
# Uses bats when available, and falls back to a small built-in runner so the
# suite still runs on a machine where bats is not installed. CI installs bats.
set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export AI_TEST=1
export AI_NO_COLOR=1
export AI_CONFIG_DIR="$ROOT/tests/tmp/config"
export AI_CACHE_DIR="$ROOT/tests/tmp/cache"
export AI_STATE_DIR="$ROOT/tests/tmp/state"
export AI_DATA_DIR="$ROOT/tests/tmp/data"
export AI_LOG_DIR="$ROOT/tests/tmp/state/logs"
export AI_BIN_DIR="$ROOT/tests/tmp/bin"
export AI_STATE_FILE="$AI_STATE_DIR/state.json"
export AI_LOCKFILE="$AI_CONFIG_DIR/ai.lock"
export AI_LOCK_FILE="$AI_STATE_DIR/ai.lock.pid"

rm -rf "$ROOT/tests/tmp"
mkdir -p "$AI_CONFIG_DIR" "$AI_STATE_DIR" "$AI_LOG_DIR" "$AI_BIN_DIR" "$AI_DATA_DIR"

[[ -f manifest/components.json ]] || python3 scripts/compile-manifest.py

if command -v bats >/dev/null 2>&1; then
  echo "==> bats"
  exec bats tests/*.bats
fi

echo "==> bats not found; running the fallback suite"
exec bash tests/fallback.sh
