#!/usr/bin/env bash
# lib/backends/npm-global.sh — globally installed npm packages.
#
# Node is installed through fnm into the user's home, so `npm -g` NEVER needs
# sudo and uninstall is genuinely clean. That is the reason this project does
# not use NodeSource: half the sudo calls in a typical AI-tooling installer
# exist only because Node landed in /usr.
#
# shellcheck shell=bash

_npm_require() {
  [[ "$AI_DRY_RUN" == "1" ]] && return 0
  # common.sh was loaded before fnm/node may have been installed, so refresh
  # the stable fnm path here and never fall back silently to /usr/bin/npm.
  node_runtime_activate || true
  if ! have npm; then
    log_error "npm not found; install the 'node' component first"
    return 1
  fi
  local npm_path
  npm_path="$(command -v npm)"
  case "$npm_path" in
    "$XDG_DATA_HOME/fnm/"* | "$HOME/.fnm/"*) ;;
    *)
      log_error "refusing unmanaged npm at ${npm_path}; the fnm-managed Node runtime is not active"
      return 1
      ;;
  esac
}

# npm_global_installed <package>
npm_global_installed() {
  npm ls -g --depth=0 --json 2>/dev/null |
    jq -e --arg p "$1" '.dependencies // {} | has($p)' >/dev/null 2>&1
}

npm_global_version() {
  npm ls -g --depth=0 --json 2>/dev/null |
    jq -r --arg p "$1" '.dependencies[$p].version // ""' 2>/dev/null
}

backend_npm_global_install() {
  local id="$1"
  _npm_require || return $?
  local pkg spec target
  pkg="$(manifest_package "$id")"
  [[ -n "$pkg" ]] || die "component '${id}': .package is required for npm-global"

  # Version resolution order: lockfile pin > manifest pin > latest.
  spec="$(lockfile_version "$id")"
  [[ -z "$spec" || "$spec" == "unknown" ]] && spec="$(manifest_version_spec "$id")"
  if [[ "$spec" == "latest" || -z "$spec" ]]; then
    target="${pkg}@latest"
  else
    target="${pkg}@${spec}"
  fi

  if npm_global_installed "$pkg"; then
    local have_ver
    have_ver="$(npm_global_version "$pkg")"
    if [[ "$spec" != "latest" && "$have_ver" == "$spec" ]]; then
      log_debug "${id}: ${pkg}@${have_ver} already installed"
      return 0
    fi
    if [[ "$spec" == "latest" ]]; then
      log_debug "${id}: ${pkg}@${have_ver} present; leaving it (use 'ai update' to bump)"
      return 0
    fi
  fi

  log_info "npm install -g ${target}"
  run_user npm install -g --no-fund --no-audit "$target" || return $?
  rollback_record "npm ${pkg}"
}

backend_npm_global_remove() {
  local id="$1"
  _npm_require || return $?
  local pkg
  pkg="$(manifest_package "$id")"
  npm_global_installed "$pkg" || return 0
  run_user npm uninstall -g "$pkg"
}

backend_npm_global_update() {
  local id="$1"
  _npm_require || return $?
  local pkg spec
  pkg="$(manifest_package "$id")"
  spec="$(manifest_version_spec "$id")"
  [[ "$spec" == "latest" ]] || {
    log_debug "${id} is pinned to ${spec}; not updating"
    return 0
  }
  run_user npm install -g --no-fund --no-audit "${pkg}@latest"
}

# The generic command probe can find an older system-wide CLI. For state
# adoption and repair, require the package to exist inside fnm's npm prefix.
backend_npm_global_managed() {
  local pkg
  node_runtime_activate || return 1
  have npm && have jq || return 1
  pkg="$(manifest_package "$1")"
  [[ -n "$pkg" ]] || return 1
  npm_global_installed "$pkg"
}

backend_npm_global_version() {
  local pkg
  pkg="$(manifest_package "$1")"
  local v
  v="$(npm_global_version "$pkg" 2>/dev/null)"
  printf '%s' "${v:-$(component_version "$1")}"
}
