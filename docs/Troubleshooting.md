# Troubleshooting

## `ai: command not found` after install

The symlink lands in `~/.local/bin`. Restart your shell, or:

```bash
. ~/.local/share/vibe-coding-tools/shellenv.sh
```

If `~/.local/bin` is still missing from `PATH`, your `.bashrc` is not being
sourced — check for an early `return` in it.

## `node`/`npm` not found after installing the `node` component

Restart your shell or source the generated environment:

```bash
. ~/.local/share/vibe-coding-tools/shellenv.sh
```

The installer itself uses fnm's stable default toolchain directly. It refuses
to fall back to `/usr/bin/npm`, because global installs through Ubuntu's npm
would target `/usr/local` and fail with `EACCES`.

## `apt-get update` fails because an unrelated repository has no Release file

APT refuses all package operations while any configured source is invalid.
The failing URL is printed directly above the error. Locate its source entry,
then correct it or disable it:

```bash
grep -REni 'launchpadcontent|ppa' /etc/apt/sources.list /etc/apt/sources.list.d/
sudo apt-get update
```

For example, a PPA that does not publish packages for your Ubuntu codename must
stay disabled until it adds support. vibe-coding-tools deliberately does not
remove third-party repositories it did not create. Once `sudo apt-get update`
succeeds, re-run the original install command.

## `error: externally-managed-environment`

Ubuntu 24.04+ enforces PEP 668: the system Python refuses `pip install`. This
is correct and vibe-coding-tools never fights it — Python CLIs go through
`uv tool install` or `pipx`. If you hit this, something outside vibe-coding-tools
called pip.

## `permission denied` talking to the Docker daemon

You are not in the `docker` group, or you have not logged out since being
added. `newgrp docker` for the current shell; log out and back in properly.

Note that group membership is root-equivalent on this machine. The Docker hook
asks before adding you, which is why it may have been skipped.

## A component installs via a remote script and is skipped

`fnm`, `rustup` and `uv` publish no packaged alternative. Review
`lib/backends/script.sh`, then:

```bash
ai install developer --allow-remote-scripts
```

A `--dry-run` shows these as `WOULD SKIP` rather than failing, so you can audit
the plan first.

## Superpowers does not load in OpenCode

Confirm that the global OpenCode configuration contains the git-backed plugin:

```json
{
  "plugin": ["superpowers@git+https://github.com/obra/superpowers.git"]
}
```

Restart OpenCode after installation. For diagnostics, run:

```bash
opencode run --print-logs "hello" 2>&1 | grep -i superpowers
```

See [Harnesses.md](Harnesses.md).

## Codex config edits fail

Editing `~/.codex/config.toml` needs Python 3.11+ for `tomllib`. Check with
`python3 --version`. Prefer `codex mcp add`, which vibe-coding-tools tries first.

## `another vibe-coding-tools process is running`

An `flock` is held. If no process is actually running, the lock file is stale:

```bash
rm -f ~/.local/state/vibe-coding-tools/ai.lock.pid
```

## An install failed halfway

```bash
ai doctor            # what is actually present
ai repair            # reinstall whatever fails verification
ai install <profile> --continue   # skip failures instead of aborting
```

User-space changes are rolled back automatically on failure. System packages
are not, by design — see [Backends.md](Backends.md).

## Reading the logs

```bash
ls -t ~/.local/state/vibe-coding-tools/logs/ | head -1
jq -r 'select(.level=="error") | .msg' ~/.local/state/vibe-coding-tools/logs/<run>.jsonl
```

Every run writes structured JSONL alongside the human output.

## Starting completely over

```bash
./uninstall.sh --components --purge
```

## Start with clean Claude Code, Codex and OpenCode extensions

Preview the reset first:

```bash
./reset.sh
```

Then apply it:

```bash
./reset.sh --apply
```

This backs up and removes global skills, plugins, MCP registrations and
OpenCode custom tools without deleting agent logins, conversations or Codex
system skills. Backups are stored under
`~/.local/state/vibe-coding-tools/backups/`.
