#!/usr/bin/env bash
# hooks/cli-utils/post-install.sh — fix Ubuntu's binary renames.
#
# Debian ships fd as `fdfind` and bat as `batcat` to avoid collisions with
# other packages. Every tutorial, and most tooling, expects `fd` and `bat`.
# We create the conventional names in ~/.local/bin rather than aliasing, so
# they also work from scripts and from inside the coding agents.
set -Eeuo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

mkdir -p "$AI_BIN_DIR"

link_alias() {
  local real="$1" wanted="$2"
  have "$real" || return 0
  have "$wanted" && return 0
  ln -sf "$(command -v "$real")" "${AI_BIN_DIR}/${wanted}"
  log_ok "${wanted} -> ${real}"
}

link_alias fdfind fd
link_alias batcat bat
