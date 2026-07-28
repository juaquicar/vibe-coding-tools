#!/usr/bin/env bash
# hooks/codegraph/post-install.sh — wire CodeGraph into the detected agents.
#
# Installing the npm package alone does nothing useful: it puts the CLI on
# PATH but does not register the MCP server with any agent. `codegraph install`
# is the step that actually connects it, and it has a documented
# non-interactive form, which is why CodeGraph is the cleanest of the three
# agent tools to automate.
set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/common.sh
. "${ROOT}/lib/common.sh"
# shellcheck source=../../lib/harness.sh
. "$AI_LIB_DIR/harness.sh"

have codegraph || die "codegraph not found after install"

# Map our harness ids onto CodeGraph's own --target names.
targets=()
harness_detect claude-code >/dev/null 2>&1 && targets+=("claude")
harness_detect codex       >/dev/null 2>&1 && targets+=("codex")
harness_detect opencode    >/dev/null 2>&1 && targets+=("opencode")

if [[ ${#targets[@]} -eq 0 ]]; then
  log_warn "no supported coding agent detected; skipping CodeGraph agent wiring"
  exit 0
fi

target_csv="$(IFS=,; printf '%s' "${targets[*]}")"
log_info "wiring CodeGraph into: ${target_csv}"
run_user codegraph install --yes --target="${target_csv}" --location=global

if [[ "${AI_OPT_OUT_TELEMETRY:-1}" == "1" ]]; then
  run_user codegraph telemetry off || log_warn "could not disable CodeGraph telemetry"
  log_ok "telemetry disabled"
fi

log_ok "CodeGraph wired in. Run 'ai index <path>' to build a project graph."
