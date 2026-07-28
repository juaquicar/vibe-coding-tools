#!/usr/bin/env bash
# lib/common.sh — shared runtime for every entry point.
#
# Responsibilities:
#   * resolve repo/XDG paths
#   * install the error trap
#   * OS/arch preflight
#   * sudo policy
#   * single-instance locking
#   * small assertion helpers
#
# Source this first; it pulls in colors/log/state/rollback in the right order.
#
# shellcheck shell=bash

[[ -n "${_AI_COMMON_SH:-}" ]] && return 0
_AI_COMMON_SH=1

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# AI_ROOT is the checkout of this repository. Resolved from this file's own
# location so the scripts work from any working directory and through symlinks.
_common_self="${BASH_SOURCE[0]}"
while [[ -L "$_common_self" ]]; do
  _common_dir="$(cd -P "$(dirname "$_common_self")" && pwd)"
  _common_self="$(readlink "$_common_self")"
  [[ "$_common_self" != /* ]] && _common_self="${_common_dir}/${_common_self}"
done
AI_LIB_DIR="$(cd -P "$(dirname "$_common_self")" && pwd)"
AI_ROOT="$(cd -P "${AI_LIB_DIR}/.." && pwd)"
unset _common_self _common_dir
export AI_LIB_DIR AI_ROOT

# XDG base directories. `~/.ai` is created as a convenience symlink farm by the
# shell hook, but the real data lives in XDG-correct locations so backups,
# dotfile managers and `rm -rf ~/.cache` all behave as users expect.
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"

AI_CONFIG_DIR="${AI_CONFIG_DIR:-$XDG_CONFIG_HOME/vibe-coding-tools}"
AI_CACHE_DIR="${AI_CACHE_DIR:-$XDG_CACHE_HOME/vibe-coding-tools}"
AI_STATE_DIR="${AI_STATE_DIR:-$XDG_STATE_HOME/vibe-coding-tools}"
AI_DATA_DIR="${AI_DATA_DIR:-$XDG_DATA_HOME/vibe-coding-tools}"
AI_LOG_DIR="${AI_LOG_DIR:-$AI_STATE_DIR/logs}"
AI_BIN_DIR="${AI_BIN_DIR:-$XDG_BIN_HOME}"

AI_STATE_FILE="${AI_STATE_FILE:-$AI_STATE_DIR/state.json}"
AI_LOCK_FILE="${AI_LOCK_FILE:-$AI_STATE_DIR/ai.lock.pid}"
AI_LOCKFILE="${AI_LOCKFILE:-$AI_CONFIG_DIR/ai.lock}"
AI_MANIFEST="${AI_MANIFEST:-$AI_ROOT/manifest/components.json}"
AI_MANIFEST_SRC="${AI_MANIFEST_SRC:-$AI_ROOT/manifest/components.yaml}"

export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_BIN_HOME
export AI_CONFIG_DIR AI_CACHE_DIR AI_STATE_DIR AI_DATA_DIR AI_LOG_DIR AI_BIN_DIR
export AI_STATE_FILE AI_LOCK_FILE AI_LOCKFILE AI_MANIFEST AI_MANIFEST_SRC

# Put every user-space runtime location on PATH before installation starts.
# The directories may not exist yet; keeping them on PATH means a component
# installed midway through this same process is immediately visible to the
# following backends and hooks.
_ai_path_prepend() {
  case ":${PATH}:" in
    *":$1:"*) ;;
    *) PATH="$1:${PATH}" ;;
  esac
}
_ai_path_prepend "$HOME/.fnm"
_ai_path_prepend "$HOME/.fnm/aliases/default/bin"
_ai_path_prepend "$XDG_DATA_HOME/fnm"
_ai_path_prepend "$XDG_DATA_HOME/fnm/aliases/default/bin"
_ai_path_prepend "$HOME/.cargo/bin"
_ai_path_prepend "$XDG_BIN_HOME"
unset -f _ai_path_prepend
export PATH

# Behaviour flags, all overridable from the environment or the CLI.
AI_DRY_RUN="${AI_DRY_RUN:-0}"
AI_ASSUME_YES="${AI_ASSUME_YES:-0}"
AI_OPT_OUT_TELEMETRY="${AI_OPT_OUT_TELEMETRY:-1}"
AI_ALLOW_REMOTE_SCRIPTS="${AI_ALLOW_REMOTE_SCRIPTS:-0}"
AI_CLI_NAME="${AI_CLI_NAME:-ai}"
export AI_DRY_RUN AI_ASSUME_YES AI_OPT_OUT_TELEMETRY AI_ALLOW_REMOTE_SCRIPTS AI_CLI_NAME

# shellcheck source=lib/colors.sh
. "$AI_LIB_DIR/colors.sh"
# shellcheck source=lib/log.sh
. "$AI_LIB_DIR/log.sh"

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

# on_error — ERR trap. Prints a real stack trace, then hands over to the
# rollback journal so partial work in user space can be undone.
on_error() {
  local rc=$? cmd="$BASH_COMMAND" i
  set +e
  log_error "aborted (rc=${rc}) while running: ${cmd}"
  for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
    printf '      %sat %s (%s:%s)%s\n' \
      "$C_GREY" "${FUNCNAME[$i]}" "${BASH_SOURCE[$i]}" "${BASH_LINENO[$((i - 1))]}" "$C_RESET" >&2
  done
  if declare -F rollback_run >/dev/null 2>&1; then
    rollback_run
  fi
  [[ -n "${AI_LOG_FILE:-}" ]] && log_error "full log: $AI_LOG_FILE"
  exit "$rc"
}

common_trap_install() {
  trap on_error ERR
  trap 'lock_release' EXIT
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# require_linux — refuse to run anywhere the manifest was not written for.
require_linux() {
  local id="" ver="" arch
  arch="$(uname -m)"
  [[ "$(uname -s)" == "Linux" ]] || die "vibe-coding-tools only supports Linux (found $(uname -s))"
  [[ "$arch" == "x86_64" ]] || die "vibe-coding-tools only supports amd64 (found ${arch})"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    ver="${VERSION_ID:-}"
  fi
  [[ "$id" == "ubuntu" ]] || die "vibe-coding-tools targets Ubuntu (found '${id:-unknown}')"
  case "$ver" in
    24.04 | 26.04) : ;;
    *)
      log_warn "Ubuntu ${ver} is untested; supported releases are 24.04 and 26.04"
      confirm "Continue anyway?" || die "aborted by user"
      ;;
  esac
  export AI_OS_ID="$id" AI_OS_VERSION="$ver"
}

# ---------------------------------------------------------------------------
# Privilege
# ---------------------------------------------------------------------------

# require_sudo — validate the sudo timestamp once, up front, so a long install
# never stalls on a password prompt halfway through.
require_sudo() {
  [[ "$AI_DRY_RUN" == "1" ]] && return 0
  if [[ "$(id -u)" -eq 0 ]]; then
    die "refusing to run as root: install as your normal user; sudo is requested per-step"
  fi
  command -v sudo >/dev/null 2>&1 || die "sudo is required but not installed"
  if ! sudo -n true 2>/dev/null; then
    log_info "elevated privileges are required for system packages"
    sudo -v || die "could not obtain sudo"
  fi
}

# run_priv <cmd...> — run a command as root, honouring dry-run.
run_priv() {
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] sudo %s%s\n' "$C_GREY" "$*" "$C_RESET" >&2
    return 0
  fi
  log_cmd sudo "$@"
}

# run_user <cmd...> — run a command as the invoking user, honouring dry-run.
run_user() {
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] %s%s\n' "$C_GREY" "$*" "$C_RESET" >&2
    return 0
  fi
  log_cmd "$@"
}

# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------

_AI_LOCK_FD=""

# lock_acquire — take an exclusive flock so two `ai install` runs cannot race
# on the state file or on dpkg.
lock_acquire() {
  mkdir -p "$(dirname "$AI_LOCK_FILE")"
  exec {_AI_LOCK_FD}>"$AI_LOCK_FILE"
  if ! flock -n "$_AI_LOCK_FD"; then
    local owner
    owner="$(cat "$AI_LOCK_FILE" 2>/dev/null || echo "?")"
    die "another vibe-coding-tools process is running (pid ${owner}); wait for it to finish"
  fi
  printf '%s\n' "$$" >&"$_AI_LOCK_FD"
}

lock_release() {
  [[ -n "$_AI_LOCK_FD" ]] || return 0
  flock -u "$_AI_LOCK_FD" 2>/dev/null || true
  exec {_AI_LOCK_FD}>&- 2>/dev/null || true
  _AI_LOCK_FD=""
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  log_error "$*"
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# node_runtime_activate — prefer fnm's stable default toolchain over Ubuntu's
# system node/npm. This does not need fnm's per-shell temporary directory and
# therefore also works in non-interactive installers and restricted shells.
node_runtime_activate() {
  local root bin
  for root in "$XDG_DATA_HOME/fnm" "$HOME/.fnm"; do
    [[ -n "$root" ]] || continue
    bin="$root/aliases/default/bin"
    [[ -x "$bin/node" && -x "$bin/npm" ]] || continue
    case ":${PATH}:" in
      *":$root:"*) ;;
      *) PATH="$root:${PATH}" ;;
    esac
    case ":${PATH}:" in
      *":$bin:"*) ;;
      *) PATH="$bin:${PATH}" ;;
    esac
    export PATH
    hash -r
    return 0
  done
  return 1
}

# confirm <prompt> — yes/no gate that auto-accepts under --yes or non-interactive.
confirm() {
  [[ "$AI_ASSUME_YES" == "1" ]] && return 0
  [[ -t 0 ]] || return 0
  local reply
  printf '%s?%s %s [y/N] ' "$C_YELLOW" "$C_RESET" "$1" >&2
  read -r reply || return 1
  [[ "$reply" =~ ^[YySs]$ ]]
}

# ensure_dirs — create the full XDG layout plus the ~/.ai convenience view.
ensure_dirs() {
  local d
  for d in "$AI_CONFIG_DIR" "$AI_CACHE_DIR" "$AI_STATE_DIR" "$AI_DATA_DIR" \
    "$AI_LOG_DIR" "$AI_BIN_DIR" \
    "$AI_DATA_DIR/memory" "$AI_DATA_DIR/projects" "$AI_DATA_DIR/prompts" \
    "$AI_DATA_DIR/skills"; do
    mkdir -p "$d"
  done
  # ~/.ai is a directory of symlinks, not a second copy of the data.
  local home_ai="$HOME/.ai"
  mkdir -p "$home_ai"
  _link_into "$home_ai/config" "$AI_CONFIG_DIR"
  _link_into "$home_ai/cache" "$AI_CACHE_DIR"
  _link_into "$home_ai/logs" "$AI_LOG_DIR"
  _link_into "$home_ai/memory" "$AI_DATA_DIR/memory"
  _link_into "$home_ai/projects" "$AI_DATA_DIR/projects"
  _link_into "$home_ai/prompts" "$AI_DATA_DIR/prompts"
  _link_into "$home_ai/skills" "$AI_DATA_DIR/skills"
}

_link_into() {
  local link="$1" target="$2"
  if [[ -L "$link" ]]; then
    [[ "$(readlink -f "$link")" == "$(readlink -f "$target")" ]] && return 0
    rm -f "$link"
  elif [[ -e "$link" ]]; then
    log_warn "$link exists and is not a symlink; leaving it alone"
    return 0
  fi
  ln -s "$target" "$link"
}

# version_ge <a> <b> — true when version a >= version b. Uses sort -V.
version_ge() {
  [[ "$1" == "$2" ]] && return 0
  local first
  first="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)"
  [[ "$first" == "$2" ]]
}

# join_by <sep> <items...>
join_by() {
  local sep="$1"
  shift
  local out=""
  local item
  for item in "$@"; do
    [[ -n "$out" ]] && out+="$sep"
    out+="$item"
  done
  printf '%s' "$out"
}

# in_list <needle> <haystack...>
in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# marker_block_write <file> <tag> <content> — idempotently maintain a fenced
# block inside a config file. Rewrites the block if present, appends if not.
marker_block_write() {
  local file="$1" tag="$2" content="$3"
  local begin="# >>> ${tag} >>>"
  local end="# <<< ${tag} <<<"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1 }
    skip != 1 { print }
    $0 == e { skip = 0 }
  ' "$file" >"$tmp"
  # Collapse any trailing blank lines left behind by the removal.
  printf '%s\n%s\n%s\n' "$begin" "$content" "$end" >>"$tmp"
  mv "$tmp" "$file"
}

# marker_block_remove <file> <tag>
marker_block_remove() {
  local file="$1" tag="$2"
  [[ -f "$file" ]] || return 0
  local begin="# >>> ${tag} >>>"
  local end="# <<< ${tag} <<<"
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1 }
    skip != 1 { print }
    $0 == e { skip = 0 }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}
