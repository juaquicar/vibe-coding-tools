# vibe-coding-tools

A package manager for AI coding agents on Ubuntu.

Installs and configures Claude Code, Codex CLI and OpenCode — plus the
extensions, MCP servers and development toolchain around them — from a single
declarative manifest. Idempotent, reproducible, and honest about what it cannot
automate.

```bash
git clone https://github.com/stratosgs/vibe-coding-tools.git
cd vibe-coding-tools
./bootstrap.sh
./install.sh --profile developer --allow-remote-scripts
```

---

## Why this exists

The setup for a modern AI-assisted development machine is a pile of
copy-pasted `curl | bash` lines that nobody can reproduce, nobody has audited,
and nobody can cleanly undo. Onboard a second engineer and you get a second,
subtly different machine.

Three things make this different from a shell script with nicer colours:

**1. The manifest is declarative.** Components say *what they are*, not what
command to run. There is no `install_cmd:` field, because a manifest carrying
shell strings is an `eval` with YAML decoration — it defeats `--dry-run`,
defeats rollback, hides code from ShellCheck, and makes every component PR an
arbitrary-code-execution PR.

**2. The coding agent is a first-class dimension.** Caveman can be installed in
Claude Code and absent from OpenCode. Context7 has to be registered three
different ways into three different config formats. State is therefore keyed on
`(component, agent)` pairs, and `ai doctor` is a matrix rather than a list.

**3. It refuses to lie.** Every integration has a typed verification step.
When an upstream exposes a stable native command or declarative configuration,
vibe-coding-tools uses it; otherwise it records `manual` instead of pretending.
A package manager that lies about what it installed is worse than none,
because you stop checking.

---

## What you get

```
$ ai doctor

==> Coding agents
  ✓ Claude Code    2.1.4      ~/.claude.json
  ✓ Codex CLI      0.9.2      ~/.codex/config.toml
  ✓ OpenCode       1.18.5     ~/.config/opencode/opencode.json

==> Agent extensions (component x agent)
                  claude-code   codex         opencode
  superpowers     ✓ ok          ✓ ok          ✓ ok
  caveman         ✓ ok          ✓ ok          ✓ ok
  context7        ✓ ok          ✓ ok          ✓ ok

```

| Layer | Components |
|---|---|
| **Agents** | Claude Code, Codex CLI, OpenCode |
| **Extensions** | Superpowers, Caveman, CodeGraph, Context7 (MCP) |
| **Languages** | Python + uv + ruff + pyright, Node via fnm, Rust via rustup |
| **Tooling** | ripgrep, fd, bat, eza, fzf, zoxide, tmux, ast-grep, tree-sitter |
| **Platform** | Docker Engine, GitHub CLI, build toolchain |
| **Domain** | Django (PostgreSQL/Redis), GIS (GDAL, PROJ, GEOS, PostGIS) |

---

## Install

Requires Ubuntu 24.04 or 26.04, amd64. Run as your normal user, never root.

```bash
./bootstrap.sh                              # jq, git, curl, python3 — nothing else
./install.sh --profile developer            # the default workstation
```

Profiles: `minimal`, `developer`, `django`, `gis`, `full`.

After bootstrap, if the machine already has global skills, plugins, MCP
servers or OpenCode custom tools from an earlier setup, preview and apply the
reset before installing:

```bash
./reset.sh                                   # preview all three agents
./reset.sh --apply                           # backup, confirm, then clean
./install.sh --profile developer --allow-remote-scripts
```

The `developer` profile includes Claude Code, Codex and OpenCode. The reset
keeps their binaries, logins, histories and general preferences.

`fnm`, `rustup` and `uv` publish no packaged alternative to a vendor installer,
so a full install needs `--allow-remote-scripts`. That flag is off by default on
purpose — read [docs/Backends.md](docs/Backends.md) before granting it. A
`--dry-run` shows those steps as `WOULD SKIP` so you can audit the plan first.

---

## Usage

```bash
ai install developer                        # a profile
ai install caveman --harness=claude-code    # one component, one agent
ai install codegraph                        # every detected agent
ai install --dry-run full                   # audit the plan, change nothing

ai doctor                                   # health matrix
ai why superpowers                          # explain the dependency graph
ai repair                                   # reinstall whatever fails verification
ai remove caveman --harness=opencode        # surgical removal
ai update                                   # everything installed
ai reset                                    # preview a clean slate for all agents
ai reset --apply                            # back up, then remove global extensions
```

### Reproducible team stacks

```bash
ai export team-stack.json     # on the machine that works
ai import team-stack.json     # on the new hire's machine
```

`ai.lock` pins resolved versions, so onboarding is deterministic rather than
"whatever npm published this morning".

Full reference: [docs/CLI.md](docs/CLI.md).

---

## Architecture

**The core knows nothing about components.** It knows about *backends* (how to
install a class of thing) and *harnesses* (how to configure a class of agent).

```
manifest/components.yaml  ──►  compile-manifest.py  ──►  components.json
                                                              │
                        ┌─────────────────────────────────────┤
                   lib/backends/*.sh                    harnesses/*.sh
                   apt, npm-global, cargo,              claude-code,
                   uv-tool, mcp-server, …               codex, opencode
                        └─────────────────┬───────────────────┘
                                     bin/aistack
                                  orchestration only
```

Adding Cursor support is **one file** in `harnesses/`. Adding a PostgreSQL MCP
server is **six lines of YAML**. Neither touches `bin/aistack`.

See [docs/Architecture.md](docs/Architecture.md).

---

## Extending

### A component — usually just YAML

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

Then `make manifest`. Commit both the YAML and the regenerated JSON — CI fails
if they diverge.

### A backend or a harness

Implement the contract in `lib/backends/<name>.sh` or `harnesses/<id>.sh`. Both
are discovered by filename; there is no dispatcher to edit, and the test suite
verifies the contract automatically. See
[docs/Backends.md](docs/Backends.md) and
[docs/Harnesses.md](docs/Harnesses.md).

---

## Security

vibe-coding-tools downloads and executes third-party software as your user — that is
its purpose. The design decisions that follow from taking that seriously:

- **No `eval` of manifest data.** `verify.cmd` is regex-restricted by the
  compiler to a bare read-only probe.
- **No `curl | bash`.** The `script` backend downloads to disk, verifies a
  checksum where one exists, archives what it ran, and executes as your user —
  never with sudo.
- **Checksums are mandatory** for `github-release` components.
- **apt keys are scoped** with `signed-by=` keyrings, never `apt-key add`.
- **Node lives in `$HOME`** via fnm, so `npm -g` never needs sudo.
- **Docker group membership is root-equivalent**, and the installer says so and
  asks first, rather than doing it silently.
- **Telemetry opt-out is the default.**

Full threat model, including what is *not* guaranteed: [SECURITY.md](SECURITY.md).

---

## FAQ

**Why not Homebrew / Nix / Ansible?**
Homebrew on Linux duplicates apt badly. Nix solves a much harder problem and
costs a much steeper learning curve. Ansible is right for fleets, overkill for
a laptop. This targets one narrow case — a developer workstation whose defining
feature is the coding agents on it — and it understands that the *agents*, not
the packages, are the interesting part.

**Why fnm instead of NodeSource?**
NodeSource puts Node in `/usr`, which forces sudo on every `npm install -g` and
makes clean uninstall impossible. fnm keeps everything in `$HOME`. That single
choice removes roughly half the sudo calls in a typical AI-tooling installer.

**Why can't it install Superpowers everywhere?**
OpenCode's documented method is to ask the agent to fetch and follow an
`INSTALL.md`, which is an LLM-driven install, not a scriptable one. `ai doctor`
tells you exactly what to do by hand. Claude Code and current Codex releases
have scriptable plugin commands.

**Does it work on Debian / Fedora / WSL?**
Ubuntu 24.04 and 26.04 amd64 are supported and tested. Debian is close.
Fedora would need a parallel manifest, not an abstraction layer. WSL2 works
apart from Docker, which needs Docker Desktop instead.

**Can I use only some agents?**
Yes. `--harness=claude-code`, or set `AI_HARNESSES` in your config.

---

## Development

```bash
make help          # every task
make manifest      # recompile components.yaml -> components.json
make lint          # manifest-check + shellcheck
make test          # bats suite
make ci            # everything CI runs
```

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Two traps
documented there are worth knowing before you touch the core: `die` inside a
process substitution is invisible to the caller, and jq's `//` operator treats
`false` as absent. Both produced real bugs in this codebase.

---

## Licence

Apache-2.0. Copyright 2026 Stratos Global Solutions S.L. See
[LICENSE](LICENSE) and [NOTICE](NOTICE).

vibe-coding-tools installs third-party software but does not redistribute it; each
component remains under its own licence.
