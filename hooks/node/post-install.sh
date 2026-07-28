#!/usr/bin/env bash
# hooks/node/post-install.sh — install Node LTS through fnm.
#
# fnm keeps Node entirely under $HOME. That single decision removes sudo from
# every subsequent `npm install -g`, makes uninstall a directory delete, and
# means Claude Code, Codex, OpenCode and CodeGraph all install as your user.
set -Eeuo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

export PATH="$XDG_DATA_HOME/fnm:$HOME/.local/share/fnm:$HOME/.fnm:$HOME/.local/bin:$PATH"
have fnm || die "fnm not on PATH; the 'fnm' component must be installed first"

eval "$(fnm env --shell bash)"

if fnm list 2>/dev/null | grep -q 'lts-latest\|lts/'; then
  log_debug "an LTS Node is already installed"
else
  log_info "installing Node LTS via fnm"
  run_user fnm install --lts
fi

run_user fnm default lts-latest 2>/dev/null || run_user fnm default "$(fnm list | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tail -n1)"
eval "$(fnm env --shell bash)"

have node || die "node still not on PATH after fnm install"
log_ok "node $(node --version), npm $(npm --version)"

# Keep global npm packages inside the fnm-managed prefix. No sudo, ever.
npm config set fund false >/dev/null 2>&1 || true
npm config set audit false >/dev/null 2>&1 || true
