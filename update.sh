#!/usr/bin/env bash
# update.sh — convenience wrapper for `ai update`.
# Updates vibe-coding-tools itself first (when it is a git checkout), then every
# installed component.
set -Eeuo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$ROOT/.git" ]]; then
  printf '\033[36m==>\033[0m Updating vibe-coding-tools itself\n' >&2
  git -C "$ROOT" pull --ff-only || printf '\033[33m  !\033[0m could not fast-forward; continuing\n' >&2
  python3 "$ROOT/scripts/compile-manifest.py" >/dev/null
fi

exec "$ROOT/bin/aistack" update "$@"
