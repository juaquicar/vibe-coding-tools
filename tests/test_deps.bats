#!/usr/bin/env bats
# Dependency resolution.

load helpers

setup() { setup_suite_env; }

@test "resolution is topologically ordered" {
  order="$(deps_resolve claude-code)"
  fnm_pos="$(printf '%s\n' "$order" | grep -n '^fnm$' | cut -d: -f1)"
  node_pos="$(printf '%s\n' "$order" | grep -n '^node$' | cut -d: -f1)"
  cc_pos="$(printf '%s\n' "$order" | grep -n '^claude-code$' | cut -d: -f1)"
  [ "$fnm_pos" -lt "$node_pos" ]
  [ "$node_pos" -lt "$cc_pos" ]
}

@test "an extension pulls in its harness" {
  order="$(deps_resolve superpowers)"
  printf '%s\n' "$order" | grep -qx 'claude-code'
  printf '%s\n' "$order" | grep -qx 'node'
}

@test "resolution is idempotent and de-duplicated" {
  order="$(deps_resolve superpowers caveman)"
  dupes="$(printf '%s\n' "$order" | sort | uniq -d | wc -l)"
  [ "$dupes" -eq 0 ]
}

@test "an unknown component is rejected" {
  run deps_resolve definitely-not-a-real-component
  [ "$status" -ne 0 ]
}

@test "reverse dependencies are found" {
  run deps_reverse claude-code
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'superpowers'
}

@test "the full profile resolves without error" {
  run bash -c "cd '$ROOT' && source lib/common.sh && source lib/manifest.sh && source lib/deps.sh && deps_resolve \$(manifest_profile full | tr '\n' ' ')"
  [ "$status" -eq 0 ]
}

@test "the full profile reaches every catalog component" {
  resolved="$(deps_resolve $(manifest_profile full | tr '\n' ' '))"
  [ "$(comm -23 <(manifest_ids | sort) <(printf '%s\n' "$resolved" | sort) | wc -l)" -eq 0 ]
}
