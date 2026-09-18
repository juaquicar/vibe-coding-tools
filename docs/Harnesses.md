# Harnesses (coding agents)

## Supported

| Harness id | Agent | Config | Format |
|---|---|---|---|
| `claude-code` | Claude Code | `~/.claude.json` | JSON |
| `codex` | Codex CLI | `~/.codex/config.toml` | **TOML** |
| `opencode` | OpenCode | `~/.config/opencode/opencode.json` | JSON/JSONC |

OpenCode's config is JSON or JSONC, **not TOML**. That confusion is widespread
and has produced a lot of broken tutorials.

## Contract

Implement in `harnesses/<id>.sh`:

```bash
<id>_name / _detect / _version / _config_path / _config_format
<id>_supports <cap>          # plugin | skill | mcp-stdio | mcp-http
<id>_mcp_add <name> <json>   /  _mcp_remove  /  _mcp_has
<id>_plugin_add <mp> <name>  /  _plugin_remove  /  _plugin_has
<id>_skill_add <repo> [skill]/  _skill_remove   /  _skill_has
```

Adding Cursor or Gemini CLI is one new file here plus manifest rows. The core
never changes.

## The support matrix, honestly

|  | Claude Code | Codex CLI | OpenCode |
|---|---|---|---|
| **CodeGraph** | `--target=claude` | `--target=codex` | `--target=opencode` |
| **Caveman** | `claude plugin install` | skills registry | skills registry |
| **Context7** | MCP (JSON) | MCP (TOML) | MCP (JSONC) |
| **Superpowers** | `claude plugin install` | `codex plugin add` | `opencode plugin` |
| **grill-me** | skills registry | skills registry | skills registry |
| **claude-mem** | `--ide claude-code` | `--ide codex-cli` | `--ide opencode` |

### grill-me and the skills registry

`mattpocock/skills` publishes 38 skills. The manifest's `skill:` field pins the
one the component actually means, and the adapter passes it through as
`--skill`, so installing `grill-me` does not drag in the other 37.

### claude-mem

Its own installer is the only supported path — upstream's README says `npm
install -g claude-mem` gives you the library without the hooks, the agent
config or the worker. The `npx-installer` backend therefore runs
`npx claude-mem install --ide <agent>` once per agent.

Two defaults worth knowing: `--provider claude` keeps the install
non-interactive (memory summarisation then runs on your Anthropic plan —
override with `AI_CLAUDE_MEM_PROVIDER=host|gemini|openrouter`), and
`--no-auto-start` means no background worker is launched during the install.
Start it yourself with `npx claude-mem start`.

Detection is per agent: Claude Code and Codex list it as a plugin, OpenCode
registers it as `./plugins/claude-mem.js` in its config.

### Superpowers on OpenCode

OpenCode installs the upstream git-backed package through its native plugin
manager. The manifest supplies the exact package spec and the adapter verifies
the resulting `plugin` entry in `opencode.json`/`opencode.jsonc`.

## Writing configuration

**Prefer the agent's own subcommand.** `claude mcp add`, `codex mcp add` and
`opencode mcp add` all exist, and using them means the agent owns its own
schema. File editing is a fallback only.

That matters most for Codex, because `jq` cannot write TOML. Rather than pull
in `taplo` or `tomli-w`, the writing lives in `lib/toml_edit.py`: `tomllib` is
stdlib from 3.11 for reading, and the writer emits the narrow subset an agent
config needs. If your Python is older than 3.11, Codex config editing is
unavailable and `bootstrap.sh` warns you.

One implementation, because every caller needs the same invariant: keys that
are not bare-key safe must be quoted. Codex plugin tables are named after
plugin specs such as `claude-mem@claude-mem-local`, and emitting that header
unquoted leaves a config Codex can no longer parse.

For OpenCode, `harness_jsonc_read` strips comments before handing the document
to `jq`, and never touches anything inside a string literal.

Comments are not preserved by a merge. `codex-config` writes
`harnesses/codex-defaults.toml` verbatim when there is no config yet, and
merges key by key when there is — MCP servers, extra profiles and personal
preferences already in the file survive.

## Codex model defaults

`ai install codex-config` applies the stack's Codex configuration: a default
model and reasoning effort, plus profiles selected with `codex -p <name>`:

| Profile | Model | Reasoning effort | For |
|---|---|---|---|
| *(default)* | `gpt-5.6-terra` | high | daily work |
| `fast` | `gpt-5.6-luna` | medium | cheap, simple tasks |
| `arch` | `gpt-5.6-sol` | xhigh | architecture, deep analysis |
| `power` | `gpt-5.6-sol` | max | maximum capability |
| `fix` | `gpt-5.6-terra` | high | bugs and refactors |

Edit `harnesses/codex-defaults.toml` to change any of it; set
`AI_CODEX_DEFAULTS=0` to leave `~/.codex/config.toml` alone entirely.

**Those defaults also set `approval_policy = "never"` and `sandbox_mode =
"danger-full-access"`**, which means Codex runs commands as your user with no
prompt and no sandbox. That is a workstation choice, not a safe default on a
shared or production machine. The installer warns every time it applies them.

## Selecting harnesses

```bash
ai install caveman                              # every detected agent
ai install caveman --harness=claude-code        # one
ai install caveman --harness=claude-code,codex  # several
ai install caveman --harness=all                # explicit
ai remove caveman --harness=opencode            # surgical removal
ai reset                                        # preview a global extension reset
ai reset --apply --yes                          # back up, then reset all three
```

Profiles carry a default set; `--harness` always wins.

## Starting from a clean agent environment

`ai reset` removes global skills, installed plugins, MCP registrations and
OpenCode custom tools for Claude Code, Codex and OpenCode. It keeps the agent
binaries, authentication, conversations, preferences and Codex's `.system`
skills. The command is preview-only until `--apply` is supplied, and creates a
private backup below `~/.local/state/vibe-coding-tools/backups/` first.

The reset intentionally does not scan every repository on disk for
project-local `.claude/`, `.codex/`, `.agents/` or `.opencode/` directories.
