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
<id>_skill_add <repo>        /  _skill_remove   /  _skill_has
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

### Superpowers on OpenCode

OpenCode installs the upstream git-backed package through its native plugin
manager. The manifest supplies the exact package spec and the adapter verifies
the resulting `plugin` entry in `opencode.json`/`opencode.jsonc`.

## Writing configuration

**Prefer the agent's own subcommand.** `claude mcp add`, `codex mcp add` and
`opencode mcp add` all exist, and using them means the agent owns its own
schema. File editing is a fallback only.

That matters most for Codex, because `jq` cannot write TOML. Rather than pull
in `taplo` or `tomli-w`, the fallback uses Python: `tomllib` is stdlib from
3.11 for reading, and the writer only has to emit the narrow subset an MCP
entry needs. If your Python is older than 3.11, Codex config editing is
unavailable and `bootstrap.sh` warns you.

For OpenCode, `harness_jsonc_read` strips comments before handing the document
to `jq`, and never touches anything inside a string literal.

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
