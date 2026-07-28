#!/usr/bin/env bash
# lib/backends/script.sh — vendor install scripts (the `curl | bash` pattern).
#
# This backend is opt-in and hostile by default, because `curl | bash` is the
# single worst habit in developer tooling: you execute whatever the server
# feels like returning, as your user, with no record of what ran.
#
# Rules enforced here:
#   * AI_ALLOW_REMOTE_SCRIPTS=1 must be set, or we refuse.
#   * The script is downloaded to disk FIRST, never piped straight into a shell.
#   * A sha256 is verified when the manifest pins one.
#   * It runs as the invoking user. Never with sudo. Not negotiable.
#
# Used only where upstream offers no packaged alternative (fnm, rustup, uv).
#
# shellcheck shell=bash

backend_script_install() {
  local id="$1" url sha args work file

  url="$(manifest_field "$id" '.script.url' '')"
  sha="$(manifest_field "$id" '.script.sha256' '')"
  args="$(manifest_field "$id" '.script.args' '')"
  [[ -n "$url" ]] || die "component '${id}': .script.url is required"

  if component_verify "$id"; then
    log_debug "${id}: already present"
    return 0
  fi

  [[ "$url" == https://* ]] || die "refusing non-HTTPS script URL: ${url}"

  # A dry run reports; it never fails. Auditing a plan is exactly when you most
  # want to see which components would reach for a vendor script.
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    if [[ "${AI_ALLOW_REMOTE_SCRIPTS}" != "1" ]]; then
      printf '%s  [dry-run] WOULD SKIP %s: remote script %s (needs --allow-remote-scripts)%s\n' \
        "$C_YELLOW" "$id" "$url" "$C_RESET" >&2
    else
      printf '%s  [dry-run] fetch and run %s%s\n' "$C_GREY" "$url" "$C_RESET" >&2
    fi
    return 0
  fi

  if [[ "${AI_ALLOW_REMOTE_SCRIPTS}" != "1" ]]; then
    log_error "component '${id}' installs via a remote script: ${url}"
    log_error "re-run with --allow-remote-scripts after reviewing it, or see docs/Troubleshooting.md"
    return 1
  fi

  work="$(mktemp -d)"
  file="${work}/install.sh"
  log_info "fetching installer for ${id}"
  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$file" ||
    die "could not fetch ${url}"

  if [[ -n "$sha" ]]; then
    local actual
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    [[ "$actual" == "$sha" ]] || {
      rm -rf "$work"
      die "installer checksum mismatch for ${id}: expected ${sha}, got ${actual}"
    }
    log_ok "installer checksum verified"
  else
    log_warn "${id}: upstream publishes no checksum for its installer; running unverified"
  fi

  # Keep a copy of exactly what we executed. When something breaks in six
  # months, "which version of the installer ran?" is answerable.
  mkdir -p "$AI_CACHE_DIR/installers"
  cp "$file" "$AI_CACHE_DIR/installers/${id}-$(date -u +%Y%m%dT%H%M%SZ).sh"

  log_info "running installer for ${id} (as $(id -un), not root)"
  # shellcheck disable=SC2086
  local rc=0
  ( cd "$work" && bash "$file" $args ) || rc=$?
  rm -rf "$work"
  ((rc == 0)) || return "$rc"
  rollback_record "noop ${id} installed by vendor script; see 'ai remove ${id}'"
}

backend_script_remove() {
  local id="$1" cmd
  cmd="$(manifest_field "$id" '.script.uninstall' '')"
  if [[ -z "$cmd" ]]; then
    log_warn "${id} was installed by a vendor script and declares no uninstall path"
    log_warn "see ${AI_ROOT}/docs/Troubleshooting.md for manual removal"
    return 0
  fi
  # shellcheck disable=SC2086
  run_user $cmd
}

backend_script_update() {
  local id="$1" cmd
  cmd="$(manifest_field "$id" '.script.update' '')"
  if [[ -n "$cmd" ]]; then
    # shellcheck disable=SC2086
    run_user $cmd
  else
    backend_script_install "$id"
  fi
}

backend_script_version() { component_version "$1"; }
