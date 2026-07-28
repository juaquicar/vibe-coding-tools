#!/usr/bin/env bash
# lib/backends/github-release.sh — binaries pulled from GitHub releases.
#
# SECURITY: a checksum is MANDATORY. Either the manifest carries an explicit
# sha256, or the release ships a checksum file we fetch and verify against.
# An unverified binary dropped on PATH is a supply-chain hole, and "it is only
# a dev machine" is exactly the excuse that makes dev machines the target.
#
# shellcheck shell=bash

backend_github_release_install() {
  local id="$1"
  local repo tag asset sha sums_file dest bin

  repo="$(manifest_repo "$id")"
  [[ -n "$repo" ]] || die "component '${id}': .repository is required"
  tag="$(manifest_field "$id" '.release.tag' 'latest')"
  asset="$(manifest_field "$id" '.release.asset' '')"
  sha="$(manifest_field "$id" '.release.sha256' '')"
  sums_file="$(manifest_field "$id" '.release.checksums' '')"
  bin="$(manifest_bin "$id")"
  dest="${AI_BIN_DIR}/${bin}"

  [[ -n "$asset" ]] || die "component '${id}': .release.asset is required"
  [[ -n "$sha" || -n "$sums_file" ]] ||
    die "component '${id}': refusing to install without a checksum (.release.sha256 or .release.checksums)"

  if [[ -x "$dest" ]] && component_verify "$id"; then
    log_debug "${id}: already installed at ${dest}"
    return 0
  fi

  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] download %s from %s@%s%s\n' "$C_GREY" "$asset" "$repo" "$tag" "$C_RESET" >&2
    return 0
  fi

  local base="https://github.com/${repo}/releases"
  local url
  if [[ "$tag" == "latest" ]]; then
    url="${base}/latest/download/${asset}"
  else
    url="${base}/download/${tag}/${asset}"
  fi

  local work
  work="$(mktemp -d)"
  log_info "downloading ${asset}"
  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "${work}/${asset}" ||
    die "download failed: ${url}"

  if [[ -z "$sha" && -n "$sums_file" ]]; then
    local sums_url
    if [[ "$tag" == "latest" ]]; then
      sums_url="${base}/latest/download/${sums_file}"
    else
      sums_url="${base}/download/${tag}/${sums_file}"
    fi
    curl -fsSL --proto '=https' "$sums_url" -o "${work}/SUMS" ||
      die "could not fetch checksum file ${sums_url}"
    sha="$(awk -v a="$asset" '$2 == a || $2 == "*"a {print $1}' "${work}/SUMS" | head -n1)"
    [[ -n "$sha" ]] || die "no checksum entry for ${asset}"
  fi

  local actual
  actual="$(sha256sum "${work}/${asset}" | cut -d' ' -f1)"
  if [[ "$actual" != "$sha" ]]; then
    rm -rf "$work"
    die "checksum mismatch for ${asset}: expected ${sha}, got ${actual}"
  fi
  log_ok "checksum verified"

  mkdir -p "$AI_BIN_DIR" || return $?
  case "$asset" in
    *.tar.gz | *.tgz)
      tar -xzf "${work}/${asset}" -C "$work" || return $?
      local found
      found="$(find "$work" -type f -name "$bin" -perm -u+x | head -n1)"
      [[ -n "$found" ]] || die "binary '${bin}' not found in ${asset}"
      install -m 0755 "$found" "$dest" || return $?
      ;;
    *.zip)
      unzip -qo "${work}/${asset}" -d "$work" || return $?
      local found2
      found2="$(find "$work" -type f -name "$bin" | head -n1)"
      [[ -n "$found2" ]] || die "binary '${bin}' not found in ${asset}"
      install -m 0755 "$found2" "$dest" || return $?
      ;;
    *)
      install -m 0755 "${work}/${asset}" "$dest" || return $?
      ;;
  esac

  rm -rf "$work"
  rollback_record "rmfile ${dest}"
  log_ok "installed ${bin} -> ${dest}"
}

backend_github_release_remove() {
  local bin dest
  bin="$(manifest_bin "$1")"
  dest="${AI_BIN_DIR}/${bin}"
  [[ -e "$dest" ]] || return 0
  run_user rm -f "$dest"
}

backend_github_release_update() {
  backend_github_release_remove "$1"
  backend_github_release_install "$1"
}

backend_github_release_version() { component_version "$1"; }
