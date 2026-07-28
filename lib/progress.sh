#!/usr/bin/env bash
# lib/progress.sh — progress reporting.
#
# On an interactive TTY this draws a single redrawn bar. Anywhere else (CI,
# pipes, `dumb` terminals) it degrades to one plain line per step, because a
# carriage-return bar turns a CI log into unreadable soup.
#
# shellcheck shell=bash

[[ -n "${_AI_PROGRESS_SH:-}" ]] && return 0
_AI_PROGRESS_SH=1

_PROGRESS_TOTAL=0
_PROGRESS_CURRENT=0
_PROGRESS_ACTIVE=0

progress_interactive() {
  [[ "${AI_NO_PROGRESS:-0}" == "1" ]] && return 1
  colors_supported
}

# progress_start <total>
progress_start() {
  _PROGRESS_TOTAL="$1"
  _PROGRESS_CURRENT=0
  _PROGRESS_ACTIVE=1
}

# progress_tick <label> — advance one step and redraw.
progress_tick() {
  local label="$1"
  ((_PROGRESS_ACTIVE)) || return 0
  _PROGRESS_CURRENT=$((_PROGRESS_CURRENT + 1))
  progress_render "$label"
}

# progress_render <label>
progress_render() {
  local label="$1"
  ((_PROGRESS_ACTIVE)) || return 0
  ((_PROGRESS_TOTAL > 0)) || return 0

  local pct=$((_PROGRESS_CURRENT * 100 / _PROGRESS_TOTAL))

  if ! progress_interactive; then
    printf '[%d/%d] (%d%%) %s\n' \
      "$_PROGRESS_CURRENT" "$_PROGRESS_TOTAL" "$pct" "$label" >&2
    return 0
  fi

  local cols width filled empty bar
  cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
  width=$((cols - 34))
  ((width < 10)) && width=10
  ((width > 40)) && width=40
  filled=$((_PROGRESS_CURRENT * width / _PROGRESS_TOTAL))
  empty=$((width - filled))

  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  bar+="$(printf '%*s' "$empty" '' | tr ' ' '.')"

  # Truncate the label so the line never wraps and corrupts the redraw.
  local max_label=$((cols - width - 20))
  ((max_label < 8)) && max_label=8
  if ((${#label} > max_label)); then
    label="${label:0:$((max_label - 1))}…"
  fi

  printf '\r\033[K%s[%s]%s %3d%% %s%s%s' \
    "$C_CYAN" "$bar" "$C_RESET" "$pct" "$C_DIM" "$label" "$C_RESET" >&2
}

# progress_done — clear the bar and leave the cursor on a fresh line.
progress_done() {
  ((_PROGRESS_ACTIVE)) || return 0
  if progress_interactive; then
    printf '\r\033[K' >&2
  fi
  _PROGRESS_ACTIVE=0
  _PROGRESS_CURRENT=0
  _PROGRESS_TOTAL=0
}
