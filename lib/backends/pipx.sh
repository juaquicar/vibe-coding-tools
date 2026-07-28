#!/usr/bin/env bash
# lib/backends/pipx.sh — fallback Python CLI backend.
# Prefer uv-tool; pipx exists for packages uv cannot resolve.
# shellcheck shell=bash

_pipx_require() {
  have pipx || die "pipx not found; install the 'python' component first"
}

pipx_installed() {
  pipx list --json 2>/dev/null | jq -e --arg p "$1" '.venvs | has($p)' >/dev/null 2>&1
}

backend_pipx_install() {
  local id="$1" pkg spec
  _pipx_require
  pkg="$(manifest_package "$id")"
  [[ -n "$pkg" ]] || die "component '${id}': .package is required for pipx"
  pipx_installed "$pkg" && { log_debug "${id}: already installed"; return 0; }

  spec="$(manifest_version_spec "$id")"
  local target="$pkg"
  [[ "$spec" != "latest" && -n "$spec" ]] && target="${pkg}==${spec}"

  run_user pipx install "$target" || return $?
  rollback_record "pipx ${pkg}"
}

backend_pipx_remove() {
  local pkg
  _pipx_require
  pkg="$(manifest_package "$1")"
  pipx_installed "$pkg" || return 0
  run_user pipx uninstall "$pkg"
}

backend_pipx_update() {
  _pipx_require
  run_user pipx upgrade "$(manifest_package "$1")"
}

backend_pipx_version() { component_version "$1"; }
