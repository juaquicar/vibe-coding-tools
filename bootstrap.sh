#!/usr/bin/env bash
# bootstrap.sh — the only script that runs before vibe-coding-tools can run itself.
#
# Chicken-and-egg problem: the runtime parses the manifest with jq, so jq has to
# exist first. This script installs that irreducible minimum and nothing else,
# then hands over to install.sh.
#
# It is deliberately tiny and dependency-free, because it is the one file a
# person might reasonably read in full before executing it.

set -Eeuo pipefail

BOOTSTRAP_PKGS=(ca-certificates curl git jq python3 flock)

say()  { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || die "Linux only (found $(uname -s))"
[[ "$(uname -m)" == "x86_64" ]] || die "amd64 only (found $(uname -m))"
[[ "$(id -u)" -ne 0 ]] || die "do not run as root; run as your normal user"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || warn "targeting Ubuntu; found '${ID:-unknown}'"
fi

say "Bootstrapping prerequisites"

missing=()
for pkg in "${BOOTSTRAP_PKGS[@]}"; do
  case "$pkg" in
    flock) command -v flock >/dev/null 2>&1 || missing+=(util-linux) ;;
    *)     dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$' || missing+=("$pkg") ;;
  esac
done

if [[ ${#missing[@]} -gt 0 ]]; then
  say "installing: ${missing[*]}"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
else
  ok "all prerequisites already present"
fi

for cmd in curl git jq python3 flock; do
  command -v "$cmd" >/dev/null 2>&1 || die "${cmd} is still missing after bootstrap"
done
ok "curl git jq python3 flock"

python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
  || warn "python3 < 3.11: editing the Codex TOML config will not work (tomllib is needed)"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say "Bootstrap complete"
printf '\n  Next:\n    %s/install.sh --profile developer\n\n' "$ROOT" >&2
