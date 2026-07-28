#!/usr/bin/env bash
# lib/backends/cargo.sh — Rust crates installed with `cargo install`.
# Fully user-space (~/.cargo/bin), so rollback is real here.
# shellcheck shell=bash

_cargo_require() {
  have cargo || die "cargo not found; install the 'rust' component first"
}

cargo_installed() {
  cargo install --list 2>/dev/null | grep -qE "^${1} v"
}

backend_cargo_install() {
  local id="$1" crate spec
  _cargo_require
  crate="$(manifest_package "$id")"
  [[ -n "$crate" ]] || die "component '${id}': .package is required for cargo"

  if cargo_installed "$crate"; then
    log_debug "${id}: crate ${crate} already installed"
    return 0
  fi

  spec="$(lockfile_version "$id")"
  [[ -z "$spec" || "$spec" == "unknown" ]] && spec="$(manifest_version_spec "$id")"

  local -a args=(install --locked)
  [[ "$spec" != "latest" && -n "$spec" ]] && args+=(--version "$spec")
  args+=("$crate")

  log_info "cargo ${args[*]}"
  run_user cargo "${args[@]}" || return $?
  rollback_record "cargo ${crate}"
}

backend_cargo_remove() {
  local crate
  _cargo_require
  crate="$(manifest_package "$1")"
  cargo_installed "$crate" || return 0
  run_user cargo uninstall "$crate"
}

backend_cargo_update() {
  local crate
  _cargo_require
  crate="$(manifest_package "$1")"
  run_user cargo install --locked --force "$crate"
}

backend_cargo_version() { component_version "$1"; }
