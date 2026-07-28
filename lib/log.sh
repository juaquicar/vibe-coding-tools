#!/usr/bin/env bash
# lib/log.sh — dual logging.
#
# Every log call writes twice:
#   1. A human-readable, coloured line on stderr (so stdout stays machine-clean
#      and can be piped into jq).
#   2. A structured JSONL record into the state directory, for `ai status`,
#      post-mortem debugging and CI artefact collection.
#
# Levels: debug < info < warn < error. Controlled with AI_LOG_LEVEL.
#
# shellcheck shell=bash

[[ -n "${_AI_LOG_SH:-}" ]] && return 0
_AI_LOG_SH=1

# shellcheck source=lib/colors.sh
. "${AI_LIB_DIR:?AI_LIB_DIR must be set}/colors.sh"

AI_LOG_LEVEL="${AI_LOG_LEVEL:-info}"
AI_LOG_FILE="${AI_LOG_FILE:-}"

_log_level_num() {
  case "$1" in
    debug) echo 10 ;;
    info) echo 20 ;;
    warn) echo 30 ;;
    error) echo 40 ;;
    *) echo 20 ;;
  esac
}

# log_init <log_dir> — open a run-scoped JSONL log and prune old ones.
log_init() {
  local dir="$1"
  mkdir -p "$dir"
  AI_LOG_FILE="${dir}/$(date -u +%Y%m%dT%H%M%SZ)-$$.jsonl"
  : >"$AI_LOG_FILE"
  export AI_LOG_FILE
  # Rotation: keep the 20 most recent runs. `ls -1t` is fine here because our
  # own filenames never contain newlines.
  local count
  count="$(find "$dir" -maxdepth 1 -name '*.jsonl' -type f | wc -l)"
  if ((count > 20)); then
    find "$dir" -maxdepth 1 -name '*.jsonl' -type f -printf '%T@ %p\n' 2>/dev/null |
      sort -n | head -n "$((count - 20))" | cut -d' ' -f2- |
      while IFS= read -r old; do rm -f "$old"; done
  fi
}

# _log_json <level> <message> — append one structured record.
_log_json() {
  [[ -z "$AI_LOG_FILE" ]] && return 0
  local level="$1" msg="$2" ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Escape the message for JSON without requiring jq to be installed yet
  # (bootstrap runs before jq exists).
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  msg="${msg//$'\n'/\\n}"
  msg="${msg//$'\t'/\\t}"
  printf '{"ts":"%s","level":"%s","component":"%s","msg":"%s"}\n' \
    "$ts" "$level" "${AI_LOG_COMPONENT:-core}" "$msg" >>"$AI_LOG_FILE"
}

# _log <level> <colour> <label> <message...>
_log() {
  local level="$1" colour="$2" label="$3"
  shift 3
  local msg="$*"
  _log_json "$level" "$msg"
  local want cur
  want="$(_log_level_num "$level")"
  cur="$(_log_level_num "$AI_LOG_LEVEL")"
  ((want < cur)) && return 0
  printf '%s%s%s %s\n' "$colour" "$label" "$C_RESET" "$msg" >&2
}

log_debug() { _log debug "$C_GREY" "  ·" "$@"; }
log_info() { _log info "$C_BLUE" "  ▸" "$@"; }
log_ok() { _log info "$C_GREEN" "  $G_OK" "$@"; }
log_warn() { _log warn "$C_YELLOW" "  $G_WARN" "$@"; }
log_error() { _log error "$C_RED" "  $G_FAIL" "$@"; }

# log_step <message> — a top-level heading for a phase of work.
log_step() {
  _log_json info "$*"
  printf '\n%s%s==>%s %s%s%s\n' \
    "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_BOLD" "$*" "$C_RESET" >&2
}

# log_cmd <cmd...> — run a command, streaming its output into the log file at
# debug level while keeping the terminal quiet unless something fails.
log_cmd() {
  local out rc=0
  log_debug "exec: $*"
  if out="$("$@" 2>&1)"; then
    [[ -n "$out" ]] && _log_json debug "$out"
    return 0
  else
    rc=$?
    log_error "command failed (rc=$rc): $*"
    [[ -n "$out" ]] && printf '%s\n' "$out" >&2
    _log_json error "$out"
    return "$rc"
  fi
}
