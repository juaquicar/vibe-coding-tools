# bash completion for vibe-coding-tools
# shellcheck shell=bash
_aistack_completion() {
  local cur prev cmds
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmds="install remove update repair doctor status list search why versions index harness config clean reset export import completion self-update version help"

  if [[ $COMP_CWORD -eq 1 ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$cmds" -- "$cur")
    return
  fi

  case "$prev" in
    install|remove|rm|update|why|explain)
      local ids
      ids="$(aistack list 2>/dev/null | awk 'NR>1 && $1 !~ /^-/ {print $1, $2}' | awk '{print $NF}' | tr '\n' ' ')"
      mapfile -t COMPREPLY < <(compgen -W "${ids} minimal developer django gis full" -- "$cur")
      return ;;
    --harness)
      mapfile -t COMPREPLY < <(compgen -W "all claude-code codex opencode" -- "$cur")
      return ;;
    --profile)
      mapfile -t COMPREPLY < <(compgen -W "minimal developer django gis full" -- "$cur")
      return ;;
    harness|agents)
      mapfile -t COMPREPLY < <(compgen -W "list detect" -- "$cur")
      return ;;
    config|cfg)
      mapfile -t COMPREPLY < <(compgen -W "path get set" -- "$cur")
      return ;;
    completion)
      mapfile -t COMPREPLY < <(compgen -W "bash zsh" -- "$cur")
      return ;;
    reset)
      mapfile -t COMPREPLY < <(compgen -W "--apply --harness --yes --dry-run" -- "$cur")
      return ;;
  esac

  mapfile -t COMPREPLY < <(compgen -W "--harness --profile --from-lock --dry-run --yes --continue --verbose --quiet --no-color --allow-remote-scripts" -- "$cur")
}
complete -F _aistack_completion aistack ai
