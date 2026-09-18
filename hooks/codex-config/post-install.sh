#!/usr/bin/env bash
# hooks/codex-config/post-install.sh — apply this stack's Codex model configuration.
#
# Installing the Codex CLI leaves it on whatever model and approval policy the
# vendor defaults to. The workstation profile this project describes wants a
# specific model per task shape (daily / fast / architecture / maximum power),
# which Codex expresses as profiles you select with `codex -p <name>`.
#
# The settings live in harnesses/codex-defaults.toml, not in this script, so
# changing a model is a one-line data edit that ShellCheck never has to see.
#
# The merge only overwrites the keys the defaults file declares. MCP servers,
# extra profiles and personal preferences already in ~/.codex/config.toml are
# preserved, which matters because `ai install context7` and claude-mem both
# write into that same file.
set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/common.sh
. "${ROOT}/lib/common.sh"
# shellcheck source=../../lib/rollback.sh
. "$AI_LIB_DIR/rollback.sh"
# shellcheck source=../../lib/harness.sh
. "$AI_LIB_DIR/harness.sh"

DEFAULTS="$ROOT/harnesses/codex-defaults.toml"
CONFIG="$HOME/.codex/config.toml"

if [[ "${AI_CODEX_DEFAULTS:-1}" != "1" ]]; then
  log_info "AI_CODEX_DEFAULTS=0; leaving ${CONFIG} alone"
  exit 0
fi

[[ -f "$DEFAULTS" ]] || die "missing ${DEFAULTS}"

# approval_policy=never plus sandbox_mode=danger-full-access is a real decision,
# not a detail. Say it out loud every time rather than burying it in a file.
log_warn "Codex defaults set approval_policy=never and sandbox_mode=danger-full-access"
log_warn "Codex will run commands as your user with no sandbox and no prompt"
log_warn "set AI_CODEX_DEFAULTS=0 to skip this step, or edit harnesses/codex-defaults.toml"

if [[ ! -e "$CONFIG" ]]; then
  # No config yet: copy the file verbatim, comments and all. A merge would
  # round-trip through tomllib and strip every comment for no reason.
  if [[ "$AI_DRY_RUN" == "1" ]]; then
    printf '%s  [dry-run] write %s%s\n' "$C_GREY" "$CONFIG" "$C_RESET" >&2
    exit 0
  fi
  mkdir -p "$(dirname "$CONFIG")"
  cp "$DEFAULTS" "$CONFIG"
  log_ok "wrote ${CONFIG} (profiles: fast, arch, power, fix)"
  exit 0
fi

patch="$(
  python3 - "$DEFAULTS" <<'PY'
import json, sys, tomllib

with open(sys.argv[1], "rb") as fh:
    print(json.dumps(tomllib.load(fh)))
PY
)" || die "could not read ${DEFAULTS}"

# Nothing to do when the live config already agrees. Keeps `ai install` quiet
# and idempotent on a machine that is already configured.
if python3 - "$CONFIG" "$patch" <<'PY'; then
import json, os, sys, tomllib

path, patch = sys.argv[1], json.loads(sys.argv[2])
data = {}
if os.path.exists(path):
    with open(path, "rb") as fh:
        data = tomllib.load(fh)


def contains(current, wanted):
    for key, value in wanted.items():
        if isinstance(value, dict):
            if not isinstance(current.get(key), dict) or not contains(current[key], value):
                return False
        elif current.get(key) != value:
            return False
    return True


sys.exit(0 if contains(data, patch) else 1)
PY
  log_debug "Codex configuration already matches the stack defaults"
  exit 0
fi

harness_toml_patch "$CONFIG" "$patch"
log_ok "merged stack defaults into ${CONFIG} (profiles: fast, arch, power, fix)"
log_info "comments in that file are not preserved by the merge; a backup is in the rollback journal"
