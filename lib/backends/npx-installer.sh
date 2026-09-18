#!/usr/bin/env bash
# lib/backends/npx-installer.sh — tools whose real installer is their own npx CLI.
#
# Some agent extensions are not a package you drop on PATH: the npm package is
# only a bootstrapper, and the actual work (registering hooks, writing agent
# config, provisioning a local service) happens when you run its installer with
# an explicit target agent. claude-mem is the canonical example — its README
# says outright that `npm install -g` gets you the library and none of the
# integration.
#
# This backend is therefore harness-scoped: one installer run per agent, one
# state row per (component, harness) pair.
#
# It stays declarative. The manifest supplies a package name, three
# subcommands, a target flag and a literal argv list; nothing is passed through
# a shell, so there is still no place for a component to smuggle in a command.
#
# shellcheck shell=bash

# _npx_installer_defaults <id> — export `.installer.defaults` for any variable
# the environment has not already set. This is how a manifest can offer a knob
# (which memory provider, which model) without hard-coding one answer.
_npx_installer_defaults() {
  local id="$1" pair name value
  while IFS= read -r pair; do
    [[ -z "$pair" ]] && continue
    name="${pair%%=*}"
    value="${pair#*=}"
    [[ -n "${!name:-}" ]] && continue
    export "${name}=${value}"
  done < <(_npx_installer_map "$id" '.installer.defaults')
}

# _npx_installer_map <id> <jq-path> — KEY=VALUE lines from a manifest object.
_npx_installer_map() {
  manifest_require
  jq -r --arg i "$1" \
    "first(.components[] | select(.id == \$i) | ${2}) // {}
     | to_entries[] | \"\(.key)=\(.value)\"" "$AI_MANIFEST"
}

# _npx_installer_expand <token> — resolve a whole-token \${VAR} reference.
# Deliberately not a shell expansion: only an entire token may be a variable,
# and nothing is ever eval'd.
_npx_installer_expand() {
  local token="$1" name
  if [[ "$token" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
    name="${BASH_REMATCH[1]}"
    printf '%s' "${!name:-}"
  else
    printf '%s' "$token"
  fi
}

# _npx_installer_argv <id> <role> [harness]
# Echoes the argv for one installer run, one word per line. <role> is
# install|remove|update: it selects both the subcommand (.installer.<role>) and
# the extra arguments, which are role-specific — `--provider` belongs to an
# install and would be nonsense on an uninstall.
_npx_installer_argv() {
  local id="$1" role="$2" harness="${3:-}"
  local pkg spec sub flag arg token args_path

  pkg="$(manifest_package "$id")"
  [[ -n "$pkg" ]] || die "component '${id}': .package is required for npx-installer"

  spec="$(lockfile_version "$id")"
  [[ -z "$spec" || "$spec" == "unknown" ]] && spec="$(manifest_version_spec "$id")"
  [[ -z "$spec" ]] && spec="latest"

  sub="$(manifest_field "$id" ".installer.${role}" "$role")"
  printf '%s\n' --yes "${pkg}@${spec}" "$sub"

  flag="$(manifest_field "$id" '.installer.target_flag' '')"
  if [[ -n "$harness" && -n "$flag" ]]; then
    arg="$(manifest_harness_arg "$id" "$harness")"
    [[ -n "$arg" ]] || die "component '${id}': harnesses.${harness}.arg must name the installer target"
    printf '%s\n' "$flag" "$arg"
  fi

  if [[ "$role" == "install" ]]; then
    args_path='.installer.args'
  else
    args_path=".installer.${role}_args"
  fi
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    _npx_installer_expand "$token"
    printf '\n'
  done < <(manifest_list "$id" "$args_path")
}

# _npx_installer_run <id> <role> [harness]
_npx_installer_run() {
  local id="$1" role="$2" harness="${3:-}"
  _npx_installer_defaults "$id"

  local -a argv=()
  local word
  while IFS= read -r word; do
    [[ -z "$word" ]] && continue
    argv+=("$word")
  done < <(_npx_installer_argv "$id" "$role" "$harness")

  # Vendor installers love an interactive account flow. Any env the manifest
  # declares is applied through `env`, so it survives run_user's dry-run print.
  local -a envv=()
  while IFS= read -r word; do
    [[ -z "$word" ]] && continue
    envv+=("$(printf '%s=%s' "${word%%=*}" "$(_npx_installer_expand "${word#*=}")")")
  done < <(_npx_installer_map "$id" '.installer.env')

  if [[ ${#envv[@]} -gt 0 ]]; then
    run_user env "${envv[@]}" npx "${argv[@]}"
  else
    run_user npx "${argv[@]}"
  fi
}

backend_npx_installer_install() {
  local id="$1" harness="${2:-}"

  [[ -n "$harness" ]] || die "component '${id}': npx-installer is harness-scoped"

  if ! harness_detect "$harness"; then
    log_warn "${harness} is not installed; skipping ${id}"
    return 0
  fi

  if ! manifest_harness_scriptable "$id" "$harness"; then
    local note
    note="$(manifest_harness_note "$id" "$harness")"
    log_warn "${id} has no non-interactive install for $(harness_name "$harness")"
    [[ -n "$note" ]] && printf '      %s%s%s\n' "$C_YELLOW" "$note" "$C_RESET" >&2
    state_write "$id" "$harness" "n/a" "npx-installer" "manual"
    return 0
  fi

  if component_verify "$id" "$harness"; then
    log_debug "${id}: already installed in ${harness}"
    return 0
  fi

  node_runtime_activate || true
  have npx || die "npx not found; install the 'node' component first"

  log_info "running ${id} installer for $(harness_name "$harness")"
  _npx_installer_run "$id" install "$harness" || return $?
  rollback_record "noop ${id} installed into ${harness} by its own installer; undo with 'ai remove ${id}'"
}

backend_npx_installer_remove() {
  local id="$1" harness="${2:-}"
  local sub scope
  sub="$(manifest_field "$id" '.installer.remove' '')"
  scope="$(manifest_field "$id" '.installer.remove_scope' 'agent')"
  harness_detect "$harness" || return 0
  component_verify "$id" "$harness" || return 0
  if [[ -z "$sub" ]]; then
    log_warn "${id} declares no uninstall subcommand; remove it by hand"
    return 0
  fi
  node_runtime_activate || true
  have npx || return 0
  if [[ "$scope" == "global" ]]; then
    # The vendor uninstaller takes no target: it removes the integration from
    # every agent at once. Say so rather than implying a surgical removal.
    log_warn "${id}'s uninstaller is not per-agent; this removes it from every agent"
    _npx_installer_run "$id" remove ""
    return $?
  fi
  _npx_installer_run "$id" remove "$harness"
}

backend_npx_installer_update() {
  local id="$1" harness="${2:-}"
  local sub
  sub="$(manifest_field "$id" '.installer.update' '')"
  if [[ -z "$sub" ]]; then
    backend_npx_installer_install "$id" "$harness"
    return $?
  fi
  harness_detect "$harness" || return 0
  node_runtime_activate || true
  have npx || return 0
  # An update is package-wide, not per-agent: no target flag.
  _npx_installer_run "$id" update ""
}

backend_npx_installer_version() {
  local spec
  spec="$(manifest_version_spec "$1")"
  printf '%s' "${spec:-latest}"
}
