#!/usr/bin/env bash
# lib/rollback.sh — transactional journal for user-space changes.
#
# HONESTY NOTE
# ------------
# There is no such thing as a rollback of `apt install`. dpkg does not keep the
# previous state, removing a package can break reverse dependencies, and a
# half-configured dpkg database is worse than a package you did not want. So
# this journal deliberately covers ONLY reversible, user-space operations:
#
#   * npm -g / cargo / uv tool / pipx packages          -> uninstall
#   * files and directories we created                  -> remove
#   * config files we edited                            -> restore from backup
#   * agent plugins / MCP registrations we added        -> deregister
#
# APT operations are journalled as `noop` entries: recorded for the audit log
# and for `ai status`, but never automatically undone. `ai doctor` reports them
# so a human can decide.
#
# shellcheck shell=bash

[[ -n "${_AI_ROLLBACK_SH:-}" ]] && return 0
_AI_ROLLBACK_SH=1

_ROLLBACK_JOURNAL=""

# rollback_begin <name> — open a journal for one logical transaction.
rollback_begin() {
  local name="$1"
  mkdir -p "$AI_STATE_DIR/journal"
  _ROLLBACK_JOURNAL="$AI_STATE_DIR/journal/${name}.$$.journal"
  : >"$_ROLLBACK_JOURNAL"
  log_debug "rollback journal opened: $_ROLLBACK_JOURNAL"
}

# rollback_record <kind> <arg...> — push an undo entry. Entries are replayed in
# reverse order (LIFO), which is the only ordering that is ever correct.
#
# kinds:
#   rmfile <path>
#   rmdir <path>
#   restore <path> <backup>
#   npm <package>
#   cargo <crate>
#   uvtool <tool>
#   pipx <package>
#   mcp <harness> <server>
#   plugin <harness> <plugin>
#   noop <description>
rollback_record() {
  [[ -n "$_ROLLBACK_JOURNAL" ]] || return 0
  printf '%s\n' "$*" >>"$_ROLLBACK_JOURNAL"
}

# rollback_backup <path> — snapshot a file before editing and journal the undo.
rollback_backup() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  local backup="$AI_STATE_DIR/journal/backup.$$.$(printf '%s' "$path" | md5sum | cut -c1-12)"
  mkdir -p "$(dirname "$backup")"
  cp -p "$path" "$backup"
  rollback_record "restore ${path} ${backup}"
}

# rollback_commit — the transaction succeeded; discard the undo log.
rollback_commit() {
  [[ -n "$_ROLLBACK_JOURNAL" ]] || return 0
  rm -f "$_ROLLBACK_JOURNAL"
  _ROLLBACK_JOURNAL=""
}

# rollback_run — replay the journal backwards. Best-effort: a failing undo step
# is logged and skipped rather than aborting the rest of the unwind.
rollback_run() {
  [[ -n "$_ROLLBACK_JOURNAL" && -s "$_ROLLBACK_JOURNAL" ]] || return 0
  log_step "Rolling back user-space changes"
  local line kind a b
  # tac gives us LIFO replay.
  while IFS= read -r line; do
    # shellcheck disable=SC2086
    set -- $line
    kind="${1:-}"
    a="${2:-}"
    b="${3:-}"
    case "$kind" in
      rmfile)
        log_info "remove file ${a}"
        rm -f "$a" || log_warn "could not remove ${a}"
        ;;
      rmdir)
        log_info "remove directory ${a}"
        rmdir "$a" 2>/dev/null || log_debug "${a} not empty, kept"
        ;;
      restore)
        log_info "restore ${a}"
        cp -p "$b" "$a" 2>/dev/null || log_warn "could not restore ${a}"
        rm -f "$b"
        ;;
      npm)
        log_info "npm uninstall -g ${a}"
        npm uninstall -g "$a" >/dev/null 2>&1 || log_warn "npm uninstall ${a} failed"
        ;;
      cargo)
        log_info "cargo uninstall ${a}"
        cargo uninstall "$a" >/dev/null 2>&1 || log_warn "cargo uninstall ${a} failed"
        ;;
      uvtool)
        log_info "uv tool uninstall ${a}"
        uv tool uninstall "$a" >/dev/null 2>&1 || log_warn "uv tool uninstall ${a} failed"
        ;;
      pipx)
        log_info "pipx uninstall ${a}"
        pipx uninstall "$a" >/dev/null 2>&1 || log_warn "pipx uninstall ${a} failed"
        ;;
      mcp)
        log_info "deregister MCP server ${b} from ${a}"
        harness_mcp_remove "$a" "$b" || log_warn "could not deregister ${b}"
        ;;
      plugin)
        log_info "deregister plugin ${b} from ${a}"
        harness_plugin_remove "$a" "$b" || log_warn "could not deregister ${b}"
        ;;
      noop)
        log_warn "not rolled back automatically: ${line#noop }"
        ;;
      *)
        log_debug "unknown journal entry: ${line}"
        ;;
    esac
  done < <(tac "$_ROLLBACK_JOURNAL")
  rm -f "$_ROLLBACK_JOURNAL"
  _ROLLBACK_JOURNAL=""
  log_warn "rollback finished; system packages were left in place by design"
}
