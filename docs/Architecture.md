# Architecture

## The one idea

**The core knows nothing about components.** It knows about *backends* (how to
install a class of thing) and *harnesses* (how to configure a class of agent).
Component knowledge lives entirely in `manifest/components.yaml`.

That inversion is what makes the project maintainable. Adding Cursor support is
one file in `harnesses/`. Adding a PostgreSQL MCP server is six lines of YAML.
Neither touches a line of `bin/aistack`.

```
                    manifest/components.yaml   (humans edit this)
                              │
                    scripts/compile-manifest.py  (validates + compiles)
                              │
                    manifest/components.json   (runtime reads this, jq only)
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
    lib/deps.sh          lib/backend.sh        lib/harness.sh
   topological order    "how to install"      "how to configure"
        │                     │                     │
        │              lib/backends/*.sh      harnesses/*.sh
        │              apt, npm-global,       claude-code, codex,
        │              cargo, mcp-server…     opencode
        └─────────────────────┼─────────────────────┘
                              │
                        bin/aistack
                        orchestration only
                              │
                        lib/state.sh
                  state keyed on (component, harness)
```

## Why the manifest is declarative

The obvious design is a manifest with an `install_cmd:` field. It is also
wrong. A manifest carrying shell strings is an `eval` with YAML decoration:

- `--dry-run` becomes a lie, because you cannot inspect a command without
  running it;
- rollback becomes impossible, because nothing knows what the command did;
- ShellCheck cannot see the code at all;
- every pull request that adds a component is a pull request that adds
  arbitrary code running as your user.

So components declare **what they are**, and backends decide **what to do**.
The only manifest string that reaches a shell is `verify.cmd`, which the
compiler restricts by regex to a bare read-only probe — no pipes, no
redirects, no substitution, no chaining.

## Why the harness is a first-class dimension

Once you support more than one coding agent, the agent stops being an
implementation detail. Caveman can be installed in Claude Code and absent from
OpenCode. Context7 must be registered three different ways, into three
different config formats. `ai doctor` is a matrix, not a list.

So state is keyed on the pair `(component, harness)`:

```json
"caveman@claude-code": { "status": "installed", "backend": "claude-plugin" },
"caveman@opencode":    { "status": "installed", "backend": "agent-skill"   },
"superpowers@opencode":{"status": "installed",  "backend": "claude-plugin" }
```

Harness-independent tools use the pseudo-harness `system`.

## The `manual` status

Some integrations genuinely cannot be automated. The tempting move is to shell
out to something approximate and report success. This project records
`status: manual` and prints the exact steps instead.

That status is not permanent policy. When upstream adds a stable native path,
the manifest can promote the integration to `scriptable`. Superpowers did this
for OpenCode by publishing a git-backed plugin package; a later install clears
the stale manual row and verifies the native plugin configuration.

## Layout

| Path | Responsibility |
|---|---|
| `bin/aistack` | Argument parsing, orchestration, output. No component logic. |
| `lib/common.sh` | XDG paths, ERR trap, sudo policy, locking, marker blocks |
| `lib/manifest.sh` | Typed accessors over `components.json` |
| `lib/deps.sh` | Topological sort, cycle detection |
| `lib/backend.sh` + `lib/backends/` | One file per install mechanism |
| `lib/harness.sh` + `harnesses/` | One file per coding agent |
| `lib/state.sh` | `state.json`, `ai.lock` |
| `lib/rollback.sh` | LIFO undo journal (user space only) |
| `hooks/<component>/<phase>.sh` | Auto-discovered per-component escape hatch |

## Hooks

Anything a backend cannot express generically goes in a hook, discovered by
convention at `hooks/<component>/{pre-install,post-install,pre-remove,post-remove}.sh`.
No registration, no manifest entry. Drop the file in and it runs.

Hooks exist because some steps are irreducibly specific: `fnm install --lts`
after installing fnm, adding your user to the `docker` group, running
`codegraph install --target=...` to wire CodeGraph into each detected agent.

## Ordering rule

`hooks/codegraph/pre-remove.sh` runs `codegraph uninstall` *before* the npm
package is removed, because the binary is what strips its own MCP entries out
of each agent's config. Remove the package first and you leave dead server
entries in three config files. Removal order is `pre-remove → backend remove →
post-remove` for exactly this reason.
