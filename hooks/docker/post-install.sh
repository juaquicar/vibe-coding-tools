#!/usr/bin/env bash
# hooks/docker/post-install.sh — post-install for Docker Engine.
#
# SECURITY, STATED PLAINLY: membership of the `docker` group is equivalent to
# passwordless root on this machine. Any process that can talk to the Docker
# socket can mount the host filesystem and escalate. This is a real trade-off,
# so we ask rather than doing it silently the way most installers do.
set -Eeuo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/common.sh"

have docker || die "docker not found after install"

run_priv systemctl enable --now docker || log_warn "could not enable the docker service"

if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  log_debug "$USER is already in the docker group"
else
  printf '\n' >&2
  log_warn "Adding you to the 'docker' group grants root-equivalent access to this machine."
  log_warn "Skip it and use 'sudo docker' if this box handles anything sensitive."
  if confirm "Add ${USER} to the docker group?"; then
    run_priv usermod -aG docker "$USER"
    log_ok "added; log out and back in for it to take effect"
  else
    log_info "skipped; use 'sudo docker'"
  fi
fi

docker compose version >/dev/null 2>&1 && log_ok "compose $(docker compose version --short)"
