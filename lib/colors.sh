#!/usr/bin/env bash
# lib/colors.sh — ANSI colour handling.
#
# Colours are disabled automatically when stdout is not a TTY, when NO_COLOR is
# set (https://no-color.org/), when TERM is "dumb", or when AI_NO_COLOR=1.
# This keeps CI logs and piped output clean.
#
# shellcheck shell=bash

[[ -n "${_AI_COLORS_SH:-}" ]] && return 0
_AI_COLORS_SH=1

# colors_supported — true when it is safe to emit ANSI escapes.
colors_supported() {
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ "${AI_NO_COLOR:-0}" == "1" ]] && return 1
  [[ "${TERM:-dumb}" == "dumb" ]] && return 1
  [[ -t 1 ]] || return 1
  return 0
}

# colors_init — define the colour variables, empty when unsupported.
colors_init() {
  if colors_supported; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_GREY=$'\033[90m'
  else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_MAGENTA="" C_CYAN="" C_GREY=""
  fi
  export C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN C_GREY
}

# Status glyphs. ASCII fallback when the locale is not UTF-8, so `ai doctor`
# stays readable over a plain serial console or a minimal container.
colors_glyphs() {
  if [[ "${LANG:-}${LC_ALL:-}" == *UTF-8* || "${LANG:-}${LC_ALL:-}" == *utf8* ]]; then
    G_OK="✓" G_FAIL="✗" G_WARN="!" G_SKIP="-" G_MANUAL="~"
  else
    G_OK="OK" G_FAIL="XX" G_WARN="!!" G_SKIP="--" G_MANUAL="~~"
  fi
  export G_OK G_FAIL G_WARN G_SKIP G_MANUAL
}

colors_init
colors_glyphs
