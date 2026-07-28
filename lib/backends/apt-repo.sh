#!/usr/bin/env bash
# lib/backends/apt-repo.sh — third-party apt repositories.
#
# SECURITY: keys are fetched over HTTPS, dearmored into /etc/apt/keyrings and
# bound to the repo with `signed-by=`. We never use `apt-key add` (deprecated,
# trusts the key archive-wide) and never `[trusted=yes]`. Nothing here uses a
# `curl | sudo bash` installer, which is how Docker is most commonly (and most
# badly) installed.
#
# shellcheck shell=bash

backend_apt_repo_install() {
  local id="$1"
  local key_url list_url_tpl suite arch keyring listfile repo_id

  repo_id="$(manifest_field "$id" '.repo.id' "$id")"
  key_url="$(manifest_field "$id" '.repo.key_url' '')"
  list_url_tpl="$(manifest_field "$id" '.repo.uri' '')"
  suite="$(manifest_field "$id" '.repo.suite' '')"
  [[ -n "$key_url" && -n "$list_url_tpl" ]] ||
    die "component '${id}': repo.key_url and repo.uri are required"

  keyring="/etc/apt/keyrings/${repo_id}.gpg"
  listfile="/etc/apt/sources.list.d/${repo_id}.list"
  arch="$(dpkg --print-architecture)"

  # Resolve ${VERSION_CODENAME} in the suite, e.g. "noble".
  local codename=""
  if [[ -r /etc/os-release ]]; then
    codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  fi
  [[ -z "$suite" ]] && suite="$codename"
  suite="${suite//\$\{VERSION_CODENAME\}/$codename}"

  if [[ ! -f "$keyring" ]]; then
    log_info "installing signing key for ${repo_id}"
    run_priv install -m 0755 -d /etc/apt/keyrings || return $?
    if [[ "$AI_DRY_RUN" != "1" ]]; then
      local tmp
      tmp="$(mktemp)"
      curl -fsSL --proto '=https' --tlsv1.2 "$key_url" -o "$tmp" ||
        die "could not fetch signing key from ${key_url}"
      run_priv gpg --batch --yes --dearmor -o "$keyring" "$tmp" || {
        local rc=$?
        rm -f "$tmp"
        return "$rc"
      }
      run_priv chmod a+r "$keyring" || {
        local rc=$?
        rm -f "$tmp"
        return "$rc"
      }
      rm -f "$tmp"
      rollback_record "noop apt keyring installed: ${keyring}"
    fi
  fi

  local components
  components="$(manifest_field "$id" '.repo.components' 'stable')"
  local line="deb [arch=${arch} signed-by=${keyring}] ${list_url_tpl} ${suite} ${components}"

  if [[ ! -f "$listfile" ]] || ! grep -qF "$line" "$listfile" 2>/dev/null; then
    log_info "adding apt source ${repo_id}"
    if [[ "$AI_DRY_RUN" == "1" ]]; then
      printf '%s  [dry-run] write %s%s\n' "$C_GREY" "$listfile" "$C_RESET" >&2
    else
      printf '%s\n' "$line" | run_priv tee "$listfile" >/dev/null || return $?
      rollback_record "noop apt source added: ${listfile}"
    fi
    _APT_UPDATED=0
  fi

  backend_load apt
  apt_refresh || return $?
  backend_apt_install "$id"
}

backend_apt_repo_remove() {
  backend_load apt
  backend_apt_remove "$1"
  local repo_id
  repo_id="$(manifest_field "$1" '.repo.id' "$1")"
  log_warn "apt source /etc/apt/sources.list.d/${repo_id}.list left in place; remove it manually if you want it gone"
}

backend_apt_repo_update() {
  backend_load apt
  backend_apt_update "$1"
}

backend_apt_repo_version() { component_version "$1"; }
