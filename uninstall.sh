#!/usr/bin/env bash
# uninstall.sh — remove vibe-coding-tools.
#
# By default this removes only vibe-coding-tools itself: the CLI symlinks, the shell
# hook block, and its own state. Components stay, because you probably still
# want git and Docker.
#
# --components  also remove every component recorded in the state file
# --purge       also delete config, cache, state and ~/.ai

set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${ROOT}/lib/common.sh"
# shellcheck source=lib/version.sh
. "$AI_LIB_DIR/version.sh"
# shellcheck source=lib/state.sh
. "$AI_LIB_DIR/state.sh"

common_trap_install
log_init "$AI_LOG_DIR"

REMOVE_COMPONENTS=0
PURGE=0
for arg in "$@"; do
  case "$arg" in
    --components) REMOVE_COMPONENTS=1 ;;
    --purge)      PURGE=1 ;;
    -y|--yes)     AI_ASSUME_YES=1 ;;
    *) die "unknown option: ${arg}" ;;
  esac
done

version_banner
log_warn "this will remove vibe-coding-tools from ${HOME}"
confirm "Continue?" || exit 0

if ((REMOVE_COMPONENTS)); then
  log_step "Removing components"
  if [[ -f "$AI_STATE_FILE" ]]; then
    mapfile -t comps < <(state_components)
    if [[ ${#comps[@]} -gt 0 ]]; then
      "$ROOT/bin/aistack" remove "${comps[@]}" --harness=all --yes || \
        log_warn "some components could not be removed cleanly"
    fi
  fi
fi

log_step "Removing the CLI"
rm -f "$AI_BIN_DIR/aistack" "$AI_BIN_DIR/${AI_CLI_NAME}"
log_ok "symlinks removed"

log_step "Cleaning shell configuration"
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  [[ -f "$rc" ]] || continue
  marker_block_remove "$rc" "vibe-coding-tools"
  log_ok "cleaned ${rc}"
done
rm -f "$AI_DATA_DIR/shellenv.sh"

if ((PURGE)); then
  log_step "Purging data"
  rm -rf "$AI_CONFIG_DIR" "$AI_CACHE_DIR" "$AI_STATE_DIR" "$AI_DATA_DIR"
  [[ -L "$HOME/.ai/config" ]] && rm -rf "$HOME/.ai"
  log_ok "all vibe-coding-tools data removed"
else
  printf '\n  Config and state kept at:\n    %s\n    %s\n  Use --purge to delete them.\n\n' \
    "$AI_CONFIG_DIR" "$AI_STATE_DIR" >&2
fi

log_ok "vibe-coding-tools uninstalled"
