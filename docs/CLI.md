# CLI reference

## Commands

| Command | Description |
|---|---|
| `ai install [<component>\|<profile>]` | Install, dependencies first |
| `ai remove <component>...` | Remove |
| `ai update [<component>...]` | Update installed components |
| `ai repair` | Reinstall anything failing verification |
| `ai doctor` | Health matrix: component × agent |
| `ai status` | What the state file records |
| `ai list [--type t] [--tag t]` | List known components |
| `ai search <term>` | Search |
| `ai why <component>` | Explain the dependency graph |
| `ai versions` | Installed vs manifest versions |
| `ai index [path]` | Build a CodeGraph index |
| `ai harness [list\|detect]` | Inspect coding agents |
| `ai config [path\|get\|set]` | Configuration |
| `ai clean [--all]` | Clear caches and old logs |
| `ai reset [--apply]` | Preview or reset global agent extensions |
| `ai export <file>` / `ai import <file>` | Move a stack between machines |
| `ai completion <bash\|zsh>` | Print a completion script |
| `ai self-update` | Update vibe-coding-tools itself |

## Global options

| Option | Effect |
|---|---|
| `--harness <spec>` | `all`, or comma-separated ids |
| `--profile <name>` | Select a profile |
| `--from-lock` | Install exactly what `ai.lock` pins |
| `-n, --dry-run` | Show the plan, change nothing |
| `-y, --yes` | Assume yes |
| `-k, --continue` | Keep going after a component fails |
| `-v` / `-q` | Debug / warnings-only logging |
| `--no-color` | Disable ANSI |
| `--allow-remote-scripts` | Permit vendor `curl \| bash` installers |

## Reproducing a stack

```bash
# machine A
ai export team-stack.json

# machine B
./bootstrap.sh
ai import team-stack.json
```

`ai.lock` pins resolved versions, so onboarding is deterministic rather than
"whatever npm published this morning".

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | A component failed, or a fatal error |
| 3 | The harness does not implement that operation |
| 5 | Lock held by another process |

## Files

| Path | Contents |
|---|---|
| `~/.config/vibe-coding-tools/config.env` | Configuration |
| `~/.config/vibe-coding-tools/ai.lock` | Version lockfile |
| `~/.local/state/vibe-coding-tools/state.json` | Install state |
| `~/.local/state/vibe-coding-tools/logs/*.jsonl` | Structured audit logs |
| `~/.cache/vibe-coding-tools/` | Downloads, vendor installer copies |
| `~/.ai/` | Symlinks into the above, for convenience |

XDG layout, not a monolithic `~/.ai`, so backups and dotfile managers behave
as you expect.

## Resetting Claude Code, Codex and OpenCode

```bash
ai reset                         # preview; changes nothing
ai reset --apply                 # back up, confirm, then reset
ai reset --apply --yes           # non-interactive, after reviewing the preview
ai reset --harness=codex         # preview only one agent
```

The reset removes user-installed global skills, plugins, MCP registrations and
OpenCode custom tools. It preserves the three agent CLIs, login data, histories,
general preferences, Codex `.system` skills and system/developer packages.
Before applying changes it copies the affected configuration and skill
directories to `~/.local/state/vibe-coding-tools/backups/reset-*/`.

Only global/user configuration is reset. Project-local agent directories in
other repositories are deliberately not scanned or changed.
