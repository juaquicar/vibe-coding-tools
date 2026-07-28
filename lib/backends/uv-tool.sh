#!/usr/bin/env bash
# lib/backends/uv-tool.sh — Python CLIs via `uv tool`.
#
# PEP 668: on Ubuntu 24.04+ the system Python is externally managed and
# `pip install --user` fails outright. Every Python tool in this stack goes
# through `uv tool` (or pipx), never pip. This backend aborts loudly if it is
# ever asked to shell out to pip.
#
# shellcheck shell=bash

_uv_require() {
  have uv || die "uv not found; install the 'uv' component first"
}

uv_tool_installed() {
  uv tool list 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

backend_uv_tool_install() {
  local id="$1" pkg spec
  _uv_require
  pkg="$(manifest_package "$id")"
  [[ -n "$pkg" ]] || die "component '${id}': .package is required for uv-tool"

  if uv_tool_installed "$pkg"; then
    log_debug "${id}: uv tool ${pkg} already installed"
    return 0
  fi

  spec="$(lockfile_version "$id")"
  [[ -z "$spec" || "$spec" == "unknown" ]] && spec="$(manifest_version_spec "$id")"

  local target="$pkg"
  [[ "$spec" != "latest" && -n "$spec" ]] && target="${pkg}==${spec}"

  log_info "uv tool install ${target}"
  run_user uv tool install "$target" || return $?
  rollback_record "uvtool ${pkg}"
}

backend_uv_tool_remove() {
  local pkg
  _uv_require
  pkg="$(manifest_package "$1")"
  uv_tool_installed "$pkg" || return 0
  run_user uv tool uninstall "$pkg"
}

backend_uv_tool_update() {
  local pkg
  _uv_require
  pkg="$(manifest_package "$1")"
  run_user uv tool upgrade "$pkg"
}

backend_uv_tool_version() { component_version "$1"; }
