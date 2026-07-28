#compdef aistack ai
# zsh completion for vibe-coding-tools
_aistack() {
  local -a cmds
  cmds=(
    'install:Install components or a profile'
    'remove:Remove components'
    'update:Update installed components'
    'repair:Reinstall anything failing verification'
    'doctor:Health matrix of components and agents'
    'status:Show the recorded install state'
    'list:List known components'
    'search:Search components'
    'why:Explain the dependency graph'
    'versions:Show installed versions'
    'index:Build a CodeGraph index'
    'harness:Inspect coding agents'
    'config:Read and write configuration'
    'clean:Clear caches and old logs'
    'reset:Reset global agent extensions'
    'export:Export the lockfile'
    'import:Import a lockfile and install'
    'completion:Print a completion script'
    'self-update:Update vibe-coding-tools itself'
    'version:Print the version'
  )
  if (( CURRENT == 2 )); then
    _describe 'command' cmds
    return
  fi
  _arguments \
    '--harness=[Target agents]:harness:(all claude-code codex opencode)' \
    '--profile=[Profile]:profile:(minimal developer django gis full)' \
    '--from-lock[Install from ai.lock]' \
    '(-n --dry-run)'{-n,--dry-run}'[Change nothing]' \
    '(-y --yes)'{-y,--yes}'[Assume yes]' \
    '(-k --continue)'{-k,--continue}'[Continue after failures]' \
    '(-v --verbose)'{-v,--verbose}'[Debug logging]'
}
_aistack "$@"
