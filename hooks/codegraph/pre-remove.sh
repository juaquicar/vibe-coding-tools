#!/usr/bin/env bash
# hooks/codegraph/pre-remove.sh — deregister from agents before dropping the CLI.
#
# Order matters: `codegraph uninstall` needs the binary to strip its own MCP
# config out of each agent. Remove the npm package first and you leave dead
# server entries behind in every agent config.
set -Eeuo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

have codegraph || exit 0
log_info "deregistering CodeGraph from all agents"
run_user codegraph uninstall --yes --keep-cli || \
  log_warn "codegraph uninstall reported an error; agent configs may need manual cleanup"
