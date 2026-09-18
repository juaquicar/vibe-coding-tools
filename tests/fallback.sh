#!/usr/bin/env bash
# tests/fallback.sh — minimal runner for machines without bats.
#
# Covers the highest-value invariants only; CI runs the full bats suite.
#
# Each assertion runs inside a ( ) subshell rather than `bash -c`, for two
# reasons: the sourced library functions are not exported, and `die` calls
# `exit`, which would otherwise kill the runner itself.
set -Eeuo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AI_NO_COLOR=1 AI_DRY_RUN=1 AI_ASSUME_YES=1

pass=0
fail=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

# check <name> <shell-snippet> — expect success
check() {
  if ( eval "$2" ) >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}

# check_fails <name> <shell-snippet> — expect failure
check_fails() {
  if ( eval "$2" ) >/dev/null 2>&1; then bad "$1 (expected failure)"; else ok "$1"; fi
}

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
. "$AI_LIB_DIR/version.sh"
. "$AI_LIB_DIR/state.sh"
. "$AI_LIB_DIR/manifest.sh"
. "$AI_LIB_DIR/deps.sh"
. "$AI_LIB_DIR/harness.sh"
. "$AI_LIB_DIR/backend.sh"
. "$AI_LIB_DIR/rollback.sh"

echo "execution"
check "log_cmd preserves non-zero status" \
  "AI_DRY_RUN=0; AI_LOG_FILE=''; set +e; log_cmd bash -c 'exit 23'; rc=\$?; set -e; [[ \$rc -eq 23 ]]"
check "fnm default runtime wins over system npm" \
  "tmp=\$(mktemp -d); mkdir -p \"\$tmp/share/fnm/aliases/default/bin\"; ln -s /bin/true \"\$tmp/share/fnm/aliases/default/bin/node\"; ln -s /bin/true \"\$tmp/share/fnm/aliases/default/bin/npm\"; HOME=\"\$tmp\"; XDG_DATA_HOME=\"\$tmp/share\"; PATH=/usr/bin:/bin; export HOME XDG_DATA_HOME PATH; node_runtime_activate; [[ \$(command -v npm) == \"\$tmp/share/fnm/aliases/default/bin/npm\" ]]"
check "npm backend propagates install failure" \
  "backend_load npm-global; _npm_require(){ :; }; npm_global_installed(){ return 1; }; lockfile_version(){ :; }; run_user(){ return 74; }; rollback_record(){ :; }; set +e; backend_npm_global_install codegraph; rc=\$?; set -e; [[ \$rc -eq 74 ]]"
check "Superpowers passes OpenCode git spec" \
  "backend_load claude-plugin; harness_detect(){ :; }; harness_plugin_has(){ return 1; }; harness_supports(){ :; }; harness_name(){ printf OpenCode; }; harness_plugin_add(){ [[ \$3 == superpowers@git+https://github.com/obra/superpowers.git ]]; }; rollback_record(){ :; }; backend_claude_plugin_install superpowers opencode"
check "apt refresh propagates repository failure" \
  "backend_load apt; run_priv(){ return 73; }; _APT_UPDATED=0; set +e; apt_refresh; rc=\$?; set -e; [[ \$rc -eq 73 && \$_APT_UPDATED -eq 0 ]]"
check "component state requires a verified postcondition" \
  "rg -q 'component_install_verified' '$ROOT/bin/aistack' && rg -q 'install command finished but verification failed' '$ROOT/bin/aistack'"
check "repair includes failed state rows" \
  "tmp=\$(mktemp -d); AI_STATE_FILE=\"\$tmp/state.json\"; AI_DRY_RUN=0; state_init; state_write caveman opencode unknown claude-plugin failed; [[ \$(state_failed_components) == caveman ]]"

echo "manifest"
check       "compiles and is in sync"      "python3 $ROOT/scripts/compile-manifest.py --check"
check       "ids are listable"             "[[ \$(manifest_ids) == *claude-code* ]]"
check       "profiles resolve"             "[[ \$(manifest_profile full) == *superpowers* ]]"
check       "developer includes linters"   "p=\$(manifest_profile developer); for id in ruff pyright ast-grep tree-sitter; do printf '%s\n' \"\$p\" | grep -qx \"\$id\" || exit 1; done"
check       "Superpowers scripts OpenCode" "manifest_harness_scriptable superpowers opencode && [[ \$(manifest_harness_arg superpowers opencode) == superpowers@git+https://github.com/obra/superpowers.git ]]"
check       "verify kinds are typed"       "[[ \$(manifest_verify_kind superpowers) == plugin ]]"
check       "harness matrix is present"    "[[ \$(manifest_harnesses caveman) == *opencode* ]]"
check_fails "unknown component rejected"   "manifest_exists no-such-thing"
check       "grill-me pins one skill"      "[[ \$(manifest_field grill-me '.skill') == grill-me && \$(manifest_verify_kind grill-me) == skill ]]"
check       "claude-mem uses its installer" "[[ \$(manifest_backend claude-mem) == npx-installer && \$(manifest_harness_arg claude-mem codex) == codex-cli ]]"
check       "hook dirs map to components"  "for d in $ROOT/hooks/*/; do id=\$(basename \$d); [[ \$id == shell ]] && continue; manifest_exists \$id || exit 1; done"

echo "backends"
for f in "$ROOT"/lib/backends/*.sh; do
  n="$(basename "$f" .sh)"
  check "backend ${n} implements the contract" \
    "backend_load '$n'; for v in install remove update version; do declare -F \"\$(backend_fn '$n' \$v)\" >/dev/null || exit 1; done"
done

echo "harnesses"
check "OpenCode sees universal global skills" \
  "tmp=\$(mktemp -d); mkdir -p \"\$tmp/.agents/skills/caveman\"; HOME=\"\$tmp\"; XDG_CONFIG_HOME=\"\$tmp/.config\"; export HOME XDG_CONFIG_HOME; harness_load opencode; opencode_skill_has caveman"
check "OpenCode sees a local plugin bundle" \
  "tmp=\$(mktemp -d); mkdir -p \"\$tmp/.config/opencode\"; printf '%s' '{\"plugin\":[\"./plugins/claude-mem.js\"]}' > \"\$tmp/.config/opencode/opencode.json\"; HOME=\"\$tmp\"; XDG_CONFIG_HOME=\"\$tmp/.config\"; export HOME XDG_CONFIG_HOME; harness_load opencode; opencode_plugin_has claude-mem"
check "Claude Code reads its plugin registry" \
  "tmp=\$(mktemp -d); mkdir -p \"\$tmp/.claude/plugins\"; printf '%s' '{\"plugins\":{\"claude-mem@thedotmack\":[]}}' > \"\$tmp/.claude/plugins/installed_plugins.json\"; HOME=\"\$tmp\"; CLAUDE_CONFIG_DIR=\"\$tmp/.claude\"; export HOME CLAUDE_CONFIG_DIR; harness_load claude-code; claude_code_plugin_has claude-mem"
check "skill selector reaches the registry" \
  "harness_load claude-code; [[ \$(claude_code_skill_add mattpocock/skills grill-me 2>&1) == *'--skill grill-me'* ]]"
check "TOML writer quotes unsafe keys" \
  "tmp=\$(mktemp -d); printf '%s\\n' '[plugins.\"claude-mem@claude-mem-local\"]' 'enabled = true' > \"\$tmp/c.toml\"; printf '%s' '{\"model\":\"gpt-5.6-terra\"}' | python3 $ROOT/lib/toml_edit.py set \"\$tmp/c.toml\"; python3 -c \"import tomllib,sys; d=tomllib.load(open(sys.argv[1],'rb')); sys.exit(0 if d['plugins']['claude-mem@claude-mem-local']['enabled'] and d['model']=='gpt-5.6-terra' else 1)\" \"\$tmp/c.toml\""
check "TOML patch preserves MCP servers" \
  "tmp=\$(mktemp -d); printf '%s\\n' 'model = \"old\"' '' '[mcp_servers.pycharm]' 'url = \"http://x/stream\"' > \"\$tmp/c.toml\"; printf '%s' '{\"model\":\"gpt-5.6-terra\"}' | python3 $ROOT/lib/toml_edit.py set \"\$tmp/c.toml\"; python3 -c \"import tomllib,sys; d=tomllib.load(open(sys.argv[1],'rb')); sys.exit(0 if d['mcp_servers']['pycharm']['url'] and d['model']=='gpt-5.6-terra' else 1)\" \"\$tmp/c.toml\""
check "installer argv is per-agent" \
  "backend_load npx-installer; out=\$(_npx_installer_argv claude-mem install codex); [[ \$out == *--ide* && \$out == *codex-cli* && \$out == *--provider* ]]"
while IFS= read -r h; do
  check "harness ${h} implements the contract" \
    "harness_load '$h'; for v in name detect config_path supports mcp_add mcp_remove mcp_has plugin_has skill_add skill_remove skill_has; do declare -F \"\$(harness_fn '$h' \$v)\" >/dev/null || exit 1; done"
done < <(harness_all)

echo "dependencies"
check       "base comes first"             "[[ \$(deps_resolve claude-code | head -1) == base ]]"
check       "fnm precedes node"            "o=\$(deps_resolve claude-code); [[ \$(echo \"\$o\" | grep -n '^fnm\$' | cut -d: -f1) -lt \$(echo \"\$o\" | grep -n '^node\$' | cut -d: -f1) ]]"
check       "extension pulls its harness"  "[[ \$(deps_resolve superpowers) == *claude-code* ]]"
check       "no duplicates in the plan"    "[[ \$(deps_resolve superpowers caveman | sort | uniq -d | wc -l) -eq 0 ]]"
check       "reverse deps found"           "[[ \$(deps_reverse claude-code) == *superpowers* ]]"
check       "full profile resolves"        "deps_resolve \$(manifest_profile full | tr '\n' ' ')"
check       "full reaches every component" "r=\$(deps_resolve \$(manifest_profile full | tr '\n' ' ')); [[ \$(comm -23 <(manifest_ids | sort) <(printf '%s\n' \"\$r\" | sort) | wc -l) -eq 0 ]]"
check_fails "unknown component fails"      "deps_resolve not-a-real-component"

echo "cli"
AI="$ROOT/bin/aistack"
check       "version"                      "$AI version"
check       "list"                         "[[ \$($AI list) == *claude-code* ]]"
check       "search"                       "[[ \$($AI search caveman) == *caveman* ]]"
check       "why"                          "[[ \$($AI why superpowers) == *claude-code* ]]"
check       "harness list"                 "[[ \$($AI harness list) == *claude-code* ]]"
check       "dry-run install"              "$AI install minimal --dry-run --yes"
check       "dry-run reports script skips" "[[ \$($AI install full --dry-run --yes 2>&1) == *SKIP* ]]"
check       "doctor runs"                  "$AI doctor"
check       "status runs"                  "$AI status"
check       "reset previews"               "[[ \$($AI reset 2>&1) == *'preview only'* ]]"
check_fails "unknown command"              "$AI frobnicate"
check_fails "unknown profile"              "$AI install nonexistent-profile-xyz --dry-run --yes"

printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
