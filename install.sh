#!/usr/bin/env bash
# install.sh — first-run installer.
#
# Thin wrapper: it links the `ai` command onto PATH, wires up the shell
# environment, then delegates every real decision to `aistack install`. All the
# logic lives in bin/aistack and the backends, so there is exactly one code
# path whether you install on day one or add a component six months later.

set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${ROOT}/lib/common.sh"
# shellcheck source=lib/version.sh
. "$AI_LIB_DIR/version.sh"

common_trap_install
ensure_dirs
log_init "$AI_LOG_DIR"

version_banner
require_linux

# --- prerequisites ----------------------------------------------------------
for cmd in curl git jq python3 flock; do
  have "$cmd" || die "${cmd} not found; run ./bootstrap.sh first"
done

# --- compile the manifest if the committed JSON is missing ------------------
if [[ ! -f "$AI_MANIFEST" ]]; then
  log_step "Compiling manifest"
  python3 "$AI_ROOT/scripts/compile-manifest.py" || die "manifest compilation failed"
fi

# --- link the CLI onto PATH -------------------------------------------------
log_step "Installing the ${AI_CLI_NAME} command"
mkdir -p "$AI_BIN_DIR"
ln -sf "$AI_ROOT/bin/aistack" "$AI_BIN_DIR/aistack"
ln -sf "$AI_ROOT/bin/aistack" "$AI_BIN_DIR/${AI_CLI_NAME}"
log_ok "${AI_BIN_DIR}/${AI_CLI_NAME} -> ${AI_ROOT}/bin/aistack"

# --- shell environment ------------------------------------------------------
bash "$AI_ROOT/hooks/shell/post-install.sh"

# --- delegate ---------------------------------------------------------------
exec "$AI_ROOT/bin/aistack" install "$@"
