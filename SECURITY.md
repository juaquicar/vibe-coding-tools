# Security policy

## Reporting

Report vulnerabilities privately to **security@stratosgs.com**. Please do not
open a public issue. Expect an acknowledgement within 72 hours.

## Threat model

vibe-coding-tools downloads and executes third-party software as your user. That is
its entire purpose, so the interesting question is not whether it runs foreign
code but how carefully.

### What the design guarantees

| Control | Implementation |
|---|---|
| No `eval` of manifest data | Components declare a `backend`; they carry no shell strings |
| Verification probes are constrained | Compiler regex rejects shell metacharacters in `verify.cmd` |
| No `curl \| bash` | The `script` backend downloads to disk, verifies, then executes |
| Remote scripts are opt-in | `--allow-remote-scripts`, off by default |
| Release binaries are verified | `github-release` refuses to install without a checksum |
| apt keys are scoped | `signed-by=` keyrings, never `apt-key add`, never `trusted=yes` |
| Least privilege | Never runs as root; sudo is requested per-step, never for vendor scripts |
| No sudo for Node packages | fnm keeps Node in `$HOME`, so `npm -g` is user-space |
| Auditable | Every run writes structured JSONL; vendor installers are archived |
| Reset is explicit | `ai reset` previews by default and requires `--apply` |

### What it does not guarantee

- **Upstream compromise.** If an upstream npm package or GitHub release is
  malicious, vibe-coding-tools installs it faithfully. Pin versions in `ai.lock` and
  review what you add.
- **apt rollback.** System packages are not automatically removed on failure.
  This is a stated limitation, not an oversight — see docs/Backends.md.
- **Vendor script contents.** `fnm`, `rustup` and `uv` installers are executed
  as published. A copy of what ran is kept in the cache directory.

## The docker group

Adding your user to the `docker` group grants root-equivalent access to the
machine: anything that can reach the Docker socket can mount the host
filesystem. vibe-coding-tools asks before doing this and states the consequence.
Decline and use `sudo docker` on machines that handle anything sensitive.

## Secrets

The manifest never contains secrets. MCP entries reference environment
variables (`${CONTEXT7_API_KEY}`), expanded at registration time. Keep keys in
your shell environment or a secret manager, not in the repository.

Reset backups can contain agent configuration and MCP environment values. They
are created with user-only directory permissions below
`~/.local/state/vibe-coding-tools/backups/`; protect them like any other local
configuration backup and delete them when no longer needed.

## Telemetry

Several components phone home by default. vibe-coding-tools opts out of all of them
unless you set `AI_OPT_OUT_TELEMETRY=0`. On a work machine that should be a
deliberate choice, not a default you never saw.
