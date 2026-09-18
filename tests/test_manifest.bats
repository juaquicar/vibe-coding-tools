#!/usr/bin/env bats
# Manifest integrity. These are the tests that stop a bad PR reaching a laptop.

load helpers

setup() { setup_suite_env; }

@test "manifest compiles and is in sync with the YAML source" {
  run python3 "$ROOT/scripts/compile-manifest.py" --check
  [ "$status" -eq 0 ]
}

@test "every component id is unique" {
  ids="$(manifest_ids)"
  [ "$(printf '%s\n' "$ids" | sort | uniq -d | wc -l)" -eq 0 ]
}

@test "every declared backend has an implementation file" {
  while IFS= read -r id; do
    backend="$(manifest_backend "$id")"
    [ -f "$ROOT/lib/backends/${backend}.sh" ] || {
      echo "component '$id' names missing backend '$backend'"
      return 1
    }
  done < <(manifest_ids)
}

@test "every backend implements the full contract" {
  for f in "$ROOT"/lib/backends/*.sh; do
    name="$(basename "$f" .sh)"
    backend_load "$name"
    for verb in install remove update version; do
      fn="$(backend_fn "$name" "$verb")"
      declare -F "$fn" >/dev/null || {
        echo "backend '$name' is missing '$verb'"
        return 1
      }
    done
  done
}

@test "every harness adapter implements the full contract" {
  while IFS= read -r h; do
    harness_load "$h"
    for verb in name detect config_path supports mcp_add mcp_remove mcp_has; do
      fn="$(harness_fn "$h" "$verb")"
      declare -F "$fn" >/dev/null || {
        echo "harness '$h' is missing '$verb'"
        return 1
      }
    done
  done < <(harness_all)
}

@test "harness-scoped components declare a support matrix" {
  while IFS= read -r id; do
    backend="$(manifest_backend "$id")"
    case "$backend" in
      claude-plugin|agent-skill|mcp-server)
        [ -n "$(manifest_harnesses "$id")" ] || {
          echo "'$id' uses backend '$backend' but declares no harnesses"
          return 1
        }
        ;;
    esac
  done < <(manifest_ids)
}

@test "non-scriptable harness entries carry an explanatory note" {
  while IFS= read -r id; do
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      if ! manifest_harness_scriptable "$id" "$h"; then
        [ -n "$(manifest_harness_note "$id" "$h")" ] || {
          echo "'$id' on '$h' is not scriptable and has no note"
          return 1
        }
      fi
    done < <(manifest_harnesses "$id")
  done < <(manifest_ids)
}

@test "agent extensions never verify with 'command'" {
  # Superpowers and Caveman are not on PATH; a command probe would be a
  # permanent false negative. This is the regression test for that bug class.
  for id in superpowers caveman; do
    [ "$(manifest_verify_kind "$id")" != "command" ]
  done
}

@test "every profile references only known components" {
  while IFS= read -r p; do
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      manifest_exists "$c" || {
        echo "profile '$p' references unknown component '$c'"
        return 1
      }
    done < <(manifest_profile "$p")
  done < <(manifest_profiles)
}

@test "developer includes the advertised linting and parser tools" {
  developer="$(manifest_profile developer)"
  for id in ruff pyright ast-grep tree-sitter; do
    printf '%s\n' "$developer" | grep -qx "$id"
  done
}

@test "Superpowers uses OpenCode's scriptable git plugin" {
  run manifest_harness_scriptable superpowers opencode
  [ "$status" -eq 0 ]
  [ "$(manifest_harness_method superpowers opencode)" = "plugin" ]
  [ "$(manifest_harness_arg superpowers opencode)" = \
    "superpowers@git+https://github.com/obra/superpowers.git" ]
}

@test "grill-me pins one skill out of a multi-skill repository" {
  [ "$(manifest_field grill-me '.skill')" = "grill-me" ]
  [ "$(manifest_verify_kind grill-me)" = "skill" ]
}

@test "claude-mem installs through its own installer, not npm -g" {
  # `npm install -g claude-mem` gets you the library and none of the agent
  # integration; upstream says so in its README.
  [ "$(manifest_backend claude-mem)" = "npx-installer" ]
  [ "$(manifest_harness_arg claude-mem codex)" = "codex-cli" ]
  [ "$(manifest_harness_arg claude-mem claude-code)" = "claude-code" ]
  [ "$(manifest_harness_arg claude-mem opencode)" = "opencode" ]
}

@test "the claude-mem installer runs non-interactively, per agent" {
  backend_load npx-installer
  run _npx_installer_argv claude-mem install codex
  [[ "$output" == *"--ide"* ]]
  [[ "$output" == *"codex-cli"* ]]
  [[ "$output" == *"--provider"* ]]
  [[ "$output" == *"claude"* ]]
}

@test "installer argv honours an environment override" {
  backend_load npx-installer
  AI_CLAUDE_MEM_PROVIDER=host run _npx_installer_argv claude-mem install codex
  [[ "$output" == *"host"* ]]
}

@test "every hook directory belongs to a real component" {
  for dir in "$ROOT"/hooks/*/; do
    id="$(basename "$dir")"
    [ "$id" = "shell" ] && continue
    manifest_exists "$id" || {
      echo "hooks/${id}/ has no component in the manifest"
      return 1
    }
  done
}
