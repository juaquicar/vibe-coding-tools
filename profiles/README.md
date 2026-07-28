# Profiles

Profiles are defined in `manifest/components.yaml` under the `profiles:` key —
**one source of truth**, validated by the same compiler that validates
components. A profile that referenced a component that no longer exists would
fail CI rather than fail at install time on someone's laptop.

The `.conf` files here are *overlays*: optional, per-site tweaks that are
sourced by `install.sh` when you pass `--profile-conf`. They can only set
environment defaults; they cannot define components.
