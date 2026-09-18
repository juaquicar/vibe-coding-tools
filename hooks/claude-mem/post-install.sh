#!/usr/bin/env bash
# hooks/claude-mem/post-install.sh — telemetry opt-out and the one manual step.
#
# claude-mem enables anonymous telemetry by default and captures memory through
# a local worker process. We install with --no-auto-start, so nothing is left
# running in the background without the user asking; this hook tells them the
# single command that starts it.
set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/common.sh
. "${ROOT}/lib/common.sh"

node_runtime_activate || true
have npx || die "npx not found after installing claude-mem"

# This hook runs once per agent. Telemetry is a single global setting, so the
# marker keeps a three-agent install from asking three times.
marker="$AI_CACHE_DIR/claude-mem.telemetry-off"
if [[ "${AI_OPT_OUT_TELEMETRY:-1}" == "1" && ! -f "$marker" ]]; then
  if run_user npx --yes claude-mem@latest telemetry disable; then
    log_ok "claude-mem telemetry disabled"
    [[ "$AI_DRY_RUN" == "1" ]] || : >"$marker"
  else
    log_warn "could not disable claude-mem telemetry; run: npx claude-mem telemetry disable"
  fi
fi

log_info "claude-mem worker is not running yet. Start it with: npx claude-mem start"
log_info "restart ${AI_HARNESS:-your agent} to load the memory hooks"
