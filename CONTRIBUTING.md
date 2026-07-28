# Contributing

## Before you start

Run the pipeline locally. It is the same one CI runs:

```bash
make ci      # manifest-check + shellcheck + tests
```

## Adding a component

Most contributions are a manifest entry and nothing else.

1. Add it to `manifest/components.yaml`.
2. `make manifest` to recompile and validate.
3. `./bin/aistack install <id> --dry-run` to inspect the plan.
4. `make test`.

Commit **both** the YAML and the regenerated JSON. CI fails if they diverge.

### Rules the compiler enforces

- `verify.cmd` must be a bare read-only probe. No pipes, redirects,
  substitution or chaining — these are rejected by regex, deliberately.
- Agent extensions must not use `verify.kind: command`. Superpowers and Caveman
  are never on `PATH`; a command probe is a permanent false negative.
- Harness-scoped backends must declare a `harnesses` matrix.
- Any `scriptable: false` entry must carry a `note` telling the user exactly
  what to do by hand.
- `github-release` components must carry a checksum.

## Adding a backend

See [docs/Backends.md](docs/Backends.md). Implement four functions, add the
name to `VALID_BACKENDS` in the compiler. No dispatcher edits.

## Adding a harness

See [docs/Harnesses.md](docs/Harnesses.md). One file in `harnesses/`. The test
suite verifies the contract automatically.

## Shell style

- `set -Eeuo pipefail` at the top of every entry point.
- `local` for every function variable.
- Quote every expansion.
- ShellCheck clean. `make shellcheck`.
- `shfmt -i 2 -ci -bn`. `make fmt`.

### Two traps worth knowing

**`die` inside a process substitution is invisible.** `while read ... < <(f)`
runs `f` in a subshell; a fatal error there exits only that subshell and the
caller carries on with empty input. Capture into a variable instead.

**`x // default` in jq treats `false` as absent.** `//` tests null-or-false, so
reading a boolean this way silently collapses every `false` to the default.
Use `select(. != null) | tostring`. This is why `manifest_field` looks the way
it does; please do not "simplify" it back.

## Commits

Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

## Pull requests

Explain *why*, not just what. A component addition should say where the install
command came from — link the upstream docs. Guessed install commands are the
main way a tool like this breaks on other people's machines.
