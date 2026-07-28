#!/usr/bin/env bash
# lib/backends/apt.sh — Debian/Ubuntu archive packages.
#
# NOTE ON ROLLBACK: apt operations are journalled as `noop`. dpkg keeps no
# previous state and auto-removing a package can break reverse dependencies,
# so we record the fact and let a human decide. See lib/rollback.sh.
#
# shellcheck shell=bash

_APT_UPDATED=0

# apt_refresh — run `apt-get update` at most once per process.
apt_refresh() {
  ((_APT_UPDATED)) && return 0
  log_info "refreshing apt index"
  local rc
  if run_priv apt-get update -qq; then
    _APT_UPDATED=1
    return 0
  else
    rc=$?
    log_error "APT could not refresh its indexes; fix or disable the failing source under /etc/apt/sources.list.d/"
    log_error "vibe-coding-tools will not modify unrelated APT repositories automatically"
    return "$rc"
  fi
}

# apt_installed <package>
apt_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

backend_apt_install() {
  local id="$1"
  local -a pkgs=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(manifest_packages "$id")
  [[ ${#pkgs[@]} -eq 0 ]] && {
    local single
    single="$(manifest_package "$id")"
    [[ -n "$single" ]] && pkgs=("$single")
  }
  [[ ${#pkgs[@]} -eq 0 ]] && die "component '${id}' declares backend apt but no packages"

  # Idempotence: skip the whole call when every package is already present.
  local missing=()
  for p in "${pkgs[@]}"; do
    apt_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log_debug "${id}: all apt packages already installed"
    return 0
  fi

  apt_refresh || return $?
  DEBIAN_FRONTEND=noninteractive run_priv apt-get install -y --no-install-recommends "${missing[@]}" ||
    return $?
  rollback_record "noop apt packages installed for ${id}: ${missing[*]}"
}

backend_apt_remove() {
  local id="$1"
  local -a pkgs=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(manifest_packages "$id")
  [[ ${#pkgs[@]} -eq 0 ]] && pkgs=("$(manifest_package "$id")")

  local present=()
  for p in "${pkgs[@]}"; do
    [[ -n "$p" ]] && apt_installed "$p" && present+=("$p")
  done
  [[ ${#present[@]} -eq 0 ]] && return 0

  log_warn "removing system packages can affect other software: ${present[*]}"
  confirm "Proceed with apt-get remove?" || return 0
  DEBIAN_FRONTEND=noninteractive run_priv apt-get remove -y "${present[@]}" || return $?
}

backend_apt_update() {
  local id="$1"
  apt_refresh || return $?
  local -a pkgs=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(manifest_packages "$id")
  [[ ${#pkgs[@]} -eq 0 ]] && pkgs=("$(manifest_package "$id")")
  [[ -z "${pkgs[0]}" ]] && return 0
  DEBIAN_FRONTEND=noninteractive run_priv apt-get install -y --only-upgrade "${pkgs[@]}" ||
    return $?
}

backend_apt_version() { component_version "$1"; }
