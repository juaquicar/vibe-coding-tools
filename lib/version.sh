#!/usr/bin/env bash
# lib/version.sh — version metadata for vibe-coding-tools itself.
# shellcheck shell=bash

[[ -n "${_AI_VERSION_SH:-}" ]] && return 0
_AI_VERSION_SH=1

AI_VERSION="0.1.0"
AI_VERSION_CODENAME="corral"
export AI_VERSION AI_VERSION_CODENAME

# version_git — the checkout's commit, when the repo is a git clone.
version_git() {
  git -C "$AI_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

version_string() {
  printf 'vibe-coding-tools %s (%s, git %s)' \
    "$AI_VERSION" "$AI_VERSION_CODENAME" "$(version_git)"
}

version_banner() {
  printf '%s%s vibe-coding-tools%s %s%s%s\n' \
    "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$AI_VERSION" "$C_RESET"
}
