# Backends

A backend knows how to install one **class** of thing. Twelve of them cover
the entire stack.

## Contract

Implement four functions in `lib/backends/<name>.sh`:

```bash
backend_<name>_install <component-id> [harness]
backend_<name>_remove  <component-id> [harness]
backend_<name>_update  <component-id> [harness]
backend_<name>_version <component-id>            # version on stdout
```

Hyphens in the backend name become underscores in the function name
(`npm-global` → `backend_npm_global_install`). The test suite fails the build
if any backend is missing part of the contract.

## The twelve

| Backend | Installs | sudo | Rollback |
|---|---|---|---|
| `apt` | Ubuntu archive packages | yes | **no** (see below) |
| `apt-repo` | Third-party apt repos (Docker, gh) | yes | **no** |
| `npm-global` | `npm install -g` | no | yes |
| `cargo` | `cargo install` | no | yes |
| `uv-tool` | Python CLIs via `uv tool` | no | yes |
| `pipx` | Python CLIs via pipx (fallback) | no | yes |
| `github-release` | Release binaries, checksum enforced | no | yes |
| `script` | Vendor `curl \| bash` installers | no | partial |
| `claude-plugin` | Agent plugins via a marketplace | no | yes |
| `agent-skill` | Cross-agent skills registry | no | partial |
| `mcp-server` | MCP server registration | no | yes |
| `none` | Meta-components (graph nodes only) | no | n/a |

## Why apt is not rolled back

There is no such thing as a rollback of `apt install`. dpkg keeps no previous
state, removing a package can break reverse dependencies, and a
half-configured dpkg database is worse than a package you did not want.

apt operations are journalled as `noop` entries: recorded for the audit log
and for `ai status`, never automatically undone. This is a deliberate
limitation, stated plainly, rather than a rollback that works until the day
you need it.

User-space backends (npm, cargo, uv, pipx, MCP registrations, plugin installs)
**are** genuinely reversible, and the journal replays them LIFO.

## Why `script` is hostile by default

`curl | bash` is the worst habit in developer tooling: you execute whatever
the server feels like returning, as your user, with no record of what ran.

The `script` backend therefore:

- refuses unless `--allow-remote-scripts` (or `AI_ALLOW_REMOTE_SCRIPTS=1`);
- downloads to disk first, never pipes into a shell;
- verifies a sha256 when the manifest pins one;
- keeps a dated copy of exactly what it executed in the cache directory;
- runs as your user, **never** with sudo.

It is used only where upstream publishes no packaged alternative: `fnm`,
`rustup`, `uv`. A `--dry-run` never fails on this backend — it reports
`WOULD SKIP` so you can audit a plan without granting the flag.

## Why `github-release` demands a checksum

The compiler refuses any `github-release` component without either an explicit
`sha256` or a `checksums` file to verify against. An unverified binary dropped
onto `PATH` is a supply-chain hole, and "it is only a dev machine" is exactly
the reasoning that makes dev machines the target.

## Adding one

1. Write `lib/backends/mybackend.sh` implementing the four functions.
2. Add `"mybackend"` to `VALID_BACKENDS` in `scripts/compile-manifest.py`.
3. Use it from a component: `backend: mybackend`.

No dispatcher edits. `backend_load` discovers it by filename.
