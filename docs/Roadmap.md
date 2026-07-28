# Roadmap

## The point of the architecture

Most of what follows is **manifest entries, not code**. The `mcp-server`
backend already registers any MCP server into all three agents, in all three
config formats. Adding one is six lines of YAML.

## Near term — pure manifest additions

No core changes required:

```yaml
- id: postgres-mcp
  type: mcp
  backend: mcp-server
  description: Query and inspect PostgreSQL from your agent.
  requires: [node]
  server: postgres
  verify: { kind: mcp }
  mcp:
    type: stdio
    command: npx
    args: ['-y', '@modelcontextprotocol/server-postgres', '${DATABASE_URL}']
  harnesses:
    claude-code: { scriptable: true, method: mcp }
    codex:       { scriptable: true, method: mcp }
    opencode:    { scriptable: true, method: mcp }
```

Planned in this shape:

- **PostgreSQL MCP** — schema introspection and querying
- **Docker MCP** — container and image management
- **GitHub MCP** — issues, PRs, Actions
- **Playwright MCP** — browser automation
- **Filesystem MCP** — scoped file access

## Near term — new harness adapters

One file each in `harnesses/`, plus matrix rows:

- **Cursor** — `npx skills add -a cursor` and MCP already work
- **Gemini CLI** — has its own extensions mechanism
- **GitHub Copilot CLI**

## Medium term

- **`ai doctor --json`** — machine-readable output for fleet monitoring
- **Signed lockfiles** — sign `ai.lock` so a team stack cannot be tampered with
- **`ai bundle`** — offline installer for air-gapped machines
- **Per-project profiles** — `.vibe-coding-tools.yaml` in a repository root
- **Debian 13 support** — the manifest is close; `apt-repo` suites need work

## Deliberately out of scope

- **Non-Debian distros.** The manifest encodes apt package names. Fedora needs
  a parallel manifest, not an abstraction layer that fits neither.
- **macOS.** Homebrew already does this well.
- **Wrapping the agents themselves.** vibe-coding-tools installs and configures
  them; it does not proxy them.
- **A GUI.** The audience already lives in a terminal.

## Version policy

Semantic versioning. The `manifest` schema and the `state.json` schema are
versioned independently; `state_init` refuses a state file newer than the tool
that is reading it.
