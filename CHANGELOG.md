# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `grill-me` (from `mattpocock/skills`) as a cross-agent skill on Claude Code,
  Codex and OpenCode. The new `skill:` manifest field pins one skill out of a
  multi-skill repository, and `verify.kind: skill` checks for it.
- `claude-mem` (`thedotmack/claude-mem`) — persistent memory across sessions —
  on all three agents, through the new `npx-installer` backend. `npm -g` is
  deliberately not used: upstream ships only the library that way.
- `npx-installer` backend, for tools whose real installer is their own npx CLI
  and which must be pointed at one agent at a time.
- `codex-config` component: model defaults plus the `fast`, `arch`, `power` and
  `fix` profiles (`codex -p <name>`), merged into `~/.codex/config.toml` from
  `harnesses/codex-defaults.toml`. Skip it with `AI_CODEX_DEFAULTS=0`.
- Safe `ai reset` workflow for Claude Code, Codex and OpenCode. It previews by
  default, backs up affected global configuration, then removes user skills,
  plugins, MCP registrations and OpenCode custom tools only with `--apply`.

### Changed

- Project identity, GitHub links, release artifacts and XDG directories now
  consistently use `vibe-coding-tools`.
- Cross-agent skills are installed globally and can be removed through the
  skills registry.
- Codex plugins use the current non-interactive `codex plugin` commands.

### Fixed

- TOML writing lives in `lib/toml_edit.py` and now quotes keys that are not
  bare-key safe. Editing a Codex config that contained a table such as
  `[plugins."claude-mem@claude-mem-local"]` previously rewrote it unquoted and
  left a `config.toml` Codex could no longer parse.
- Plugin detection: Claude Code also reads `installed_plugins.json`, and
  OpenCode recognises plugins registered as a local bundle path
  (`./plugins/<name>.js`). Installers that write those files directly were
  reported as missing forever.

## [0.1.0] — 2026-07-27

First release. Codename `corral`.

### Added

- Declarative component manifest with twelve typed backends. Components carry
  no shell commands; the core dispatches on `backend`.
- Multi-harness support as a first-class dimension: Claude Code, Codex CLI and
  OpenCode. State is keyed on `(component, harness)` pairs.
- `manual` status for things that genuinely cannot be automated, with the exact
  by-hand instructions printed instead of a fake success.
- Twenty-three components across five profiles (`minimal`, `developer`,
  `django`, `gis`, `full`).
- `ai doctor` health matrix, `ai why` dependency explanation, `ai repair`.
- `ai.lock` lockfile plus `ai export` / `ai import` for reproducible team
  stacks.
- LIFO rollback journal for user-space operations. apt is journalled as `noop`
  by design.
- YAML → JSON manifest compiler with schema validation, cycle detection and a
  `--check` mode wired into CI.
- Auto-discovered per-component hooks at `hooks/<id>/<phase>.sh`.
- Node installed through fnm rather than NodeSource, which removes sudo from
  every `npm -g`.
- Docker installed from its official apt repository with a `signed-by` keyring,
  not `get.docker.com`.
- Bash and zsh completions, XDG-correct paths, structured JSONL audit logging.

### Security

- `github-release` components cannot be added without a checksum.
- The `script` backend is opt-in, downloads to disk before executing, never
  pipes to a shell, and never runs with sudo.
- `verify.cmd` strings are restricted by the compiler to read-only probes with
  no shell metacharacters.
- Telemetry opt-out is the default across every component that has one.

[Unreleased]: https://github.com/stratosgs/vibe-coding-tools/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/stratosgs/vibe-coding-tools/releases/tag/v0.1.0
