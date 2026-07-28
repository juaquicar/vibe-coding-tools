#!/usr/bin/env bash
# reset.sh — preview or reset global extensions for every supported agent.

set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/bin/aistack" reset "$@"
